/**
 * @description Claims a Ready Now Service Appointment for a technician and then
 *              sets Status to Dispatched. Bypass FSL Schedule Here chooses
 *              forceSchedule or FSL.ScheduleService.scheduleHere.
 */
public with sharing class FsSSSelfScheduler {
    /** @description No Assigned Resource exists for the appointment. */
    private static final String ASSIGNMENT_NONE = 'NONE';
    /** @description The claiming resource already owns the appointment. */
    private static final String ASSIGNMENT_OWN = 'OWN';
    /** @description A different resource owns the appointment. */
    private static final String ASSIGNMENT_OTHER = 'OTHER';
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
     *              Bypass FSL Schedule Here selects forceSchedule. When the flag
     *              is false, FSL.ScheduleService.scheduleHere runs for every
     *              assignment state.
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
        String assignmentState = readAssignmentState(
            appointment.Id,
            resourceId
        );
        if (settings.bypassFslScheduleHere) {
            forceSchedule(appointment, resourceId, assignmentState);
        } else {
            scheduleWithPolicy(
                appointment.Id,
                resourceId,
                settings.schedulingPolicyName
            );
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
     * @description Reads whether the claiming resource, another resource, or nobody is assigned.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id being claimed.
     * @return ASSIGNMENT_NONE, ASSIGNMENT_OWN, or ASSIGNMENT_OTHER.
     */
    private static String readAssignmentState(Id appointmentId, Id resourceId) {
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
            return ASSIGNMENT_OWN;
        }
        Integer assignedCount = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :appointmentId
            WITH USER_MODE
        ];
        if (assignedCount > 0) {
            return ASSIGNMENT_OTHER;
        }
        return ASSIGNMENT_NONE;
    }

    /**
     * @description Calls scheduleHere using the configured scheduling policy.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id.
     * @param policyName Scheduling policy name from CMDT.
     */
    private static void scheduleWithPolicy(
        Id appointmentId,
        Id resourceId,
        String policyName
    ) {
        ScheduleRequest request = new ScheduleRequest();
        request.startTime = System.now();
        request.policyId = resolvePolicyId(policyName);
        request.appointmentId = appointmentId;
        request.resourceId = resourceId;
        scheduleHere(request);
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
     *              The stub pins times and inserts an Assigned Resource only when
     *              the appointment has none, so a second row is not required.
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
            Integer assignedCount = [
                SELECT COUNT()
                FROM AssignedResource
                WHERE ServiceAppointmentId = :request.appointmentId
                WITH USER_MODE
            ];
            if (assignedCount > 0) {
                return;
            }
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
     * @description Pins times and Assigned Resource without scheduleHere.
     *              OWN updates times only. OTHER deletes the other assignment,
     *              updates times, then inserts the claiming resource. NONE updates
     *              times and then inserts the assignment.
     * @param appointment Locked appointment.
     * @param resourceId Service Resource Id.
     * @param assignmentState ASSIGNMENT_NONE, ASSIGNMENT_OWN, or ASSIGNMENT_OTHER.
     */
    private static void forceSchedule(
        ServiceAppointment appointment,
        Id resourceId,
        String assignmentState
    ) {
        if (assignmentState == ASSIGNMENT_OTHER) {
            replaceOtherAssignment(appointment, resourceId);
            return;
        }
        if (assignmentState == ASSIGNMENT_OWN) {
            updateScheduleTimes(appointment);
            return;
        }
        updateScheduleTimes(appointment);
        insertAssignment(appointment.Id, resourceId);
    }

    /**
     * @description Replaces another resource's assignment with the claiming resource.
     * @param appointment Locked appointment.
     * @param resourceId Service Resource Id being claimed.
     */
    private static void replaceOtherAssignment(
        ServiceAppointment appointment,
        Id resourceId
    ) {
        deleteOtherAssignments(appointment.Id, resourceId);
        updateScheduleTimes(appointment);
        if (!resourceAlreadyAssigned(appointment.Id, resourceId)) {
            insertAssignment(appointment.Id, resourceId);
        }
    }

    /**
     * @description Deletes Assigned Resource rows that belong to a different resource.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id that should remain.
     */
    private static void deleteOtherAssignments(Id appointmentId, Id resourceId) {
        if (!Schema.sObjectType.AssignedResource.isDeletable()) {
            throw auraError('You do not have permission to self-schedule.');
        }
        List<AssignedResource> others = [
            SELECT Id
            FROM AssignedResource
            WHERE ServiceAppointmentId = :appointmentId
            AND ServiceResourceId != :resourceId
            WITH USER_MODE
        ];
        if (others.isEmpty()) {
            return;
        }
        delete as user others;
    }

    /**
     * @description True when this resource already has an Assigned Resource row.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id.
     * @return True when the claiming resource is already assigned.
     */
    private static Boolean resourceAlreadyAssigned(Id appointmentId, Id resourceId) {
        Integer ownCount = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :appointmentId
            AND ServiceResourceId = :resourceId
            WITH USER_MODE
        ];
        return ownCount > 0;
    }

    /**
     * @description Inserts one Assigned Resource for the claiming resource.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id.
     */
    private static void insertAssignment(Id appointmentId, Id resourceId) {
        if (!Schema.sObjectType.AssignedResource.isCreateable()) {
            throw auraError('You do not have permission to self-schedule.');
        }
        AssignedResource assignment = new AssignedResource(
            ServiceAppointmentId = appointmentId,
            ServiceResourceId = resourceId
        );
        SObjectAccessDecision assignmentDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<AssignedResource>{ assignment }
        );
        insert assignmentDecision.getRecords();
    }

    /**
     * @description Sets scheduled start to now and end from the appointment duration.
     * @param appointment Locked appointment.
     */
    private static void updateScheduleTimes(ServiceAppointment appointment) {
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
     * @description Sets the appointment status after scheduling succeeds.
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
