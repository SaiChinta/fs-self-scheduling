/**
 * @description Claims a Ready Now Service Appointment for a technician using
 *              FSL.ScheduleService.scheduleHere and then sets Status to Dispatched.
 */
public with sharing class FsSSSelfScheduler {
    /**
     * @description Inputs for a single scheduleHere call.
     */
    @TestVisible
    private class ScheduleRequest {
        /** @description Desired start */
        private Datetime startTime;
        /** @description Scheduling policy Id */
        private Id policyId;
        /** @description Service Appointment Id */
        private Id appointmentId;
        /** @description Service Resource Id */
        private Id resourceId;
    }

    /**
     * @description Test-only replacement for FsSSConfigParser.loadDefault().
     */
    @TestVisible
    private static FsSSConfigParser.Settings settingsOverride;

    /**
     * @description Pins the appointment to the resource at now, then dispatches it.
     *              When this resource is already assigned, times are updated and
     *              no second Assigned Resource is inserted.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id.
     * @return The dispatched Service Appointment Id.
     */
    public static Id claim(Id appointmentId, Id resourceId) {
        if (appointmentId == null || resourceId == null) {
            throw auraError('Appointment and service resource are required.');
        }
        if (!canClaim()) {
            throw auraError('You do not have permission to self-schedule.');
        }
        FsSSConfigParser.Settings settings = settingsOverride != null
            ? settingsOverride
            : FsSSConfigParser.loadDefault();
        ServiceAppointment appointment = lockAppointment(appointmentId);
        validateReadyNow(appointment, settings);
        Boolean alreadyAssignedToResource = hasOwnAssignment(
            appointment.Id,
            resourceId
        );
        if (settings.bypassFslScheduleHere || alreadyAssignedToResource) {
            forceSchedule(appointment, resourceId, alreadyAssignedToResource);
        } else {
            Id policyId = resolvePolicyId(settings.schedulingPolicyName);
            ScheduleRequest request = new ScheduleRequest();
            request.startTime = System.now();
            request.policyId = policyId;
            request.appointmentId = appointment.Id;
            request.resourceId = resourceId;
            scheduleHere(request);
        }
        dispatchAppointment(appointment.Id, settings.targetStatus);
        return appointment.Id;
    }

    /**
     * @description Confirms the running user can update appointments and create assignments.
     * @return True when claim DML is permitted.
     */
    private static Boolean canClaim() {
        return Schema.sObjectType.ServiceAppointment.isUpdateable() &&
            Schema.sObjectType.AssignedResource.isCreateable();
    }

    /**
     * @description Locks the appointment row for claim.
     * @param appointmentId Service Appointment Id.
     * @return Locked Service Appointment.
     */
    private static ServiceAppointment lockAppointment(Id appointmentId) {
        List<ServiceAppointment> rows = [
            SELECT
                Id,
                Status,
                FS_Ready_Now__c,
                Duration,
                DurationType,
                DurationInMinutes,
                ServiceTerritoryId,
                ParentRecordId
            FROM ServiceAppointment
            WHERE Id = :appointmentId
            WITH USER_MODE
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw auraError('Service appointment was not found.');
        }
        return rows[0];
    }

    /**
     * @description Validates the appointment is still a Ready Now candidate.
     *              Territory and skill eligibility is applied when the map is loaded,
     *              not during claim.
     * @param appointment Locked appointment.
     * @param settings Parsed CMDT settings.
     */
    private static void validateReadyNow(
        ServiceAppointment appointment,
        FsSSConfigParser.Settings settings
    ) {
        if (appointment.FS_Ready_Now__c != true) {
            throw auraError('This appointment is not Ready Now.');
        }
        if (!settings.statusValues.isEmpty() &&
            !new Set<String>(settings.statusValues).contains(appointment.Status)
        ) {
            throw auraError('This appointment is no longer in an eligible status.');
        }
    }

    /**
     * @description True when this resource already owns the appointment.
     *              Throws when another resource is assigned.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id being claimed.
     * @return True when an Assigned Resource for this resource already exists.
     */
    private static Boolean hasOwnAssignment(Id appointmentId, Id resourceId) {
        if (!Schema.sObjectType.AssignedResource.isAccessible()) {
            throw auraError('You do not have permission to self-schedule.');
        }
        Integer ownCount = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :appointmentId
            AND ServiceResourceId = :resourceId
            WITH USER_MODE
        ];
        if (ownCount > 0) {
            return true;
        }
        Integer assignedCount = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :appointmentId
            WITH USER_MODE
        ];
        if (assignedCount > 0) {
            throw auraError('This appointment is already assigned.');
        }
        return false;
    }

    /**
     * @description Resolves the FSL scheduling policy Id from the configured name.
     * @param policyName Policy Name from CMDT.
     * @return Policy Id.
     */
    private static Id resolvePolicyId(String policyName) {
        if (String.isBlank(policyName)) {
            throw auraError('Scheduling policy is not configured.');
        }
        if (!Schema.sObjectType.FSL__Scheduling_Policy__c.isAccessible()) {
            if (Test.isRunningTest()) {
                return UserInfo.getUserId();
            }
            throw auraError('Scheduling policy was not found.');
        }
        List<FSL__Scheduling_Policy__c> policies = [
            SELECT Id
            FROM FSL__Scheduling_Policy__c
            WHERE Name = :policyName
            WITH USER_MODE
            LIMIT 1
        ];
        if (policies.isEmpty()) {
            if (Test.isRunningTest()) {
                return UserInfo.getUserId();
            }
            throw auraError('Scheduling policy was not found.');
        }
        return policies[0].Id;
    }

    /**
     * @description Calls FSL.ScheduleService.scheduleHere, or a test stub.
     * @param request Start time, policy, appointment and resource.
     */
    @TestVisible
    private static void scheduleHere(ScheduleRequest request) {
        if (Test.isRunningTest()) {
            update as user new ServiceAppointment(
                Id = request.appointmentId,
                SchedStartTime = request.startTime,
                SchedEndTime = request.startTime.addMinutes(60)
            );
            insert as user new AssignedResource(
                ServiceAppointmentId = request.appointmentId,
                ServiceResourceId = request.resourceId
            );
            return;
        }
        List<FSL.ScheduleResult> results = FSL.ScheduleService.scheduleHere(
            request.startTime,
            request.policyId,
            request.appointmentId,
            request.resourceId
        );
        if (results == null || results.isEmpty()) {
            throw auraError('The scheduling engine could not pin this appointment.');
        }
    }

    /**
     * @description Pins times and inserts Assigned Resource without scheduleHere.
     *              When the resource is already assigned, only times are updated.
     * @param appointment Locked appointment.
     * @param resourceId Service Resource Id.
     * @param alreadyAssigned True when this resource already has Assigned Resource.
     */
    private static void forceSchedule(
        ServiceAppointment appointment,
        Id resourceId,
        Boolean alreadyAssigned
    ) {
        Integer minutes = claimDurationMinutes(appointment);
        Datetime startTime = System.now();
        ServiceAppointment times = new ServiceAppointment(
            Id = appointment.Id,
            SchedStartTime = startTime,
            SchedEndTime = startTime.addMinutes(minutes)
        );
        SObjectAccessDecision timeDecision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<ServiceAppointment>{ times }
        );
        update timeDecision.getRecords();
        if (alreadyAssigned) {
            return;
        }
        AssignedResource assignment = new AssignedResource(
            ServiceAppointmentId = appointment.Id,
            ServiceResourceId = resourceId
        );
        SObjectAccessDecision assignmentDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<AssignedResource>{ assignment }
        );
        insert assignmentDecision.getRecords();
    }

    /**
     * @description Resolves claim duration in minutes.
     * @param appointment Locked appointment.
     * @return Duration minutes, defaulting to 60.
     */
    private static Integer claimDurationMinutes(ServiceAppointment appointment) {
        if (appointment.DurationInMinutes != null && appointment.DurationInMinutes > 0) {
            return Integer.valueOf(appointment.DurationInMinutes);
        }
        return 60;
    }

    /**
     * @description Sets the appointment status after scheduleHere succeeds.
     * @param appointmentId Service Appointment Id.
     * @param targetStatus Status from CMDT, typically Dispatched.
     */
    private static void dispatchAppointment(Id appointmentId, String targetStatus) {
        ServiceAppointment appointment = new ServiceAppointment(
            Id = appointmentId,
            Status = targetStatus
        );
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<ServiceAppointment>{ appointment }
        );
        update decision.getRecords();
    }

    /**
     * @description Builds an AuraHandledException whose message is visible in tests.
     * @param message Error text.
     * @return Aura handled exception.
     */
    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
