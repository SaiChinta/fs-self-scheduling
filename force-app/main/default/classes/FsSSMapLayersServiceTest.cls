/**
 * @description Tests for Self Scheduling config parsing, map query, and claim.
 */
@IsTest
private class FsSSMapLayersServiceTest {
    private static final Decimal ORIGIN_LAT = -36.8485;
    private static final Decimal ORIGIN_LNG = 174.7633;

    /**
     * @description Creates a Ready Now appointment and a Service Resource for the running user.
     */
    @TestSetup
    static void setupData() {
        Test.startTest();
        upsertResource();
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        OperatingHours hours = new OperatingHours(
            Name = 'Self Scheduling Hours',
            TimeZone = 'Pacific/Auckland'
        );
        insert hours;
        ServiceTerritory territory = new ServiceTerritory(
            Name = 'Self Scheduling Territory',
            OperatingHoursId = hours.Id,
            IsActive = true
        );
        insert territory;
        insert new ServiceTerritoryMember(
            ServiceResourceId = resource.Id,
            ServiceTerritoryId = territory.Id,
            EffectiveStartDate = System.now().addDays(-1),
            TerritoryType = 'P'
        );
        WorkOrder workOrder = new WorkOrder(Subject = 'Self Scheduling Work');
        insert workOrder;
        AppointmentSpec readySpec = new AppointmentSpec();
        readySpec.parentId = workOrder.Id;
        readySpec.subject = 'Ready Nearby';
        readySpec.latitude = ORIGIN_LAT;
        readySpec.longitude = ORIGIN_LNG;
        readySpec.isReadyNow = true;
        readySpec.territoryId = territory.Id;
        AppointmentSpec notReadySpec = new AppointmentSpec();
        notReadySpec.parentId = workOrder.Id;
        notReadySpec.subject = 'Not Ready';
        notReadySpec.latitude = ORIGIN_LAT + 0.001;
        notReadySpec.longitude = ORIGIN_LNG + 0.001;
        notReadySpec.isReadyNow = false;
        notReadySpec.territoryId = territory.Id;
        ServiceAppointment readyNearby = buildAppointment(readySpec);
        ServiceAppointment notReady = buildAppointment(notReadySpec);
        insert new List<ServiceAppointment>{ readyNearby, notReady };
        assignAccessPermissionSet();
        Test.stopTest();
    }

    /**
     * @description Assigns FS_SelfScheduling_Access so USER_MODE queries can read Ready Now.
     */
    private static void assignAccessPermissionSet() {
        PermissionSet access = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'FS_SelfScheduling_Access'
            LIMIT 1
        ];
        List<PermissionSetAssignment> existing = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :access.Id
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = access.Id
            );
        }
    }

    /**
     * @description Config parser splits status and boolean tokens.
     */
    @IsTest
    static void configParserReadsBooleanAndStatusTokens() {
        FS_Self_Scheduling_Config__mdt record = new FS_Self_Scheduling_Config__mdt(
            Status_Values__c = 'Open, Scheduled',
            Boolean_Filters__c = 'Is_Ready_Now__c=true,BadToken,Other__c=false',
            Search_Radius__c = 15,
            Distance_Unit__c = 'km',
            Debug_Enabled__c = true,
            Max_Results__c = 50,
            Target_Status__c = 'Dispatched',
            Evaluate_Territory_Rules__c = true,
            Evaluate_Skill_Rules__c = true
        );
        Test.startTest();
        FsSSConfigParser.Settings settings = FsSSConfigParser.fromRecord(record);
        Test.stopTest();
        System.assertEquals(2, settings.statusValues.size(), 'Two statuses should parse');
        System.assertEquals(true, settings.booleanFilters.get('Is_Ready_Now__c'), 'Ready Now filter should be true');
        System.assertEquals(false, settings.booleanFilters.get('Other__c'), 'Other boolean should be false');
        System.assertEquals(true, settings.skippedBooleanTokens.contains('BadToken'), 'Bad token should be skipped');
        System.assertEquals(true, settings.evaluateTerritoryRules, 'Territory flag should default on');
        System.assertEquals(true, settings.evaluateSkillRules, 'Skill flag should default on');
    }

    /**
     * @description Parser honors explicit off flags for policy rule families.
     */
    @IsTest
    static void configParserReadsPolicyRuleFlagsOff() {
        FS_Self_Scheduling_Config__mdt record = new FS_Self_Scheduling_Config__mdt(
            Evaluate_Territory_Rules__c = false,
            Evaluate_Skill_Rules__c = false
        );
        Test.startTest();
        FsSSConfigParser.Settings settings = FsSSConfigParser.fromRecord(record);
        Test.stopTest();
        System.assertEquals(false, settings.evaluateTerritoryRules, 'Territory flag should be off');
        System.assertEquals(false, settings.evaluateSkillRules, 'Skill flag should be off');
    }

    /**
     * @description Parser reads card field tokens and the scheduleHere bypass flag.
     */
    @IsTest
    static void configParserReadsCardFieldsAndBypass() {
        FS_Self_Scheduling_Config__mdt record = new FS_Self_Scheduling_Config__mdt(
            Card_Detail_Fields__c = 'Work Type:WorkType.Name,Duration(Mins):DurationInMinutes,NotAField,Bad:123',
            Bypass_Fsl_Schedule_Here__c = false
        );
        Test.startTest();
        FsSSConfigParser.Settings settings = FsSSConfigParser.fromRecord(record);
        Test.stopTest();
        System.assertEquals(false, settings.bypassFslScheduleHere, 'Bypass should honor false');
        System.assertEquals(2, settings.cardDetailFields.size(), 'Two valid card fields should parse');
        System.assertEquals('Work Type', settings.cardDetailFields[0].label, 'First card label should parse');
        System.assertEquals('WorkType.Name', settings.cardDetailFields[0].fieldApiName, 'First card field should parse');
        System.assertEquals(true, settings.skippedCardFieldTokens.contains('NotAField'), 'Token without a colon should be skipped');
        System.assertEquals(true, settings.skippedCardFieldTokens.contains('Bad:123'), 'Numeric field path should be skipped');
    }

    /**
     * @description getConfig returns the Default CMDT values.
     */
    @IsTest
    static void getConfigReturnsDefaultRecord() {
        Test.startTest();
        FsSSMapLayersService.ConfigDto config = FsSSMapLayersService.getConfig();
        Test.stopTest();
        System.assertEquals(true, config.searchRadius > 0, 'Radius should be populated');
        System.assertEquals(true, config.booleanFilterTokens.size() > 0, 'Boolean filters should be populated');
        System.assertNotEquals(null, config.evaluateTerritoryRules, 'Territory flag should be returned');
        System.assertNotEquals(null, config.evaluateSkillRules, 'Skill flag should be returned');
        System.assertEquals(true, config.policyRuleTypes != null, 'Policy rule types list should be present');
        System.assertEquals(UserInfo.getName(), config.userName, 'Config should include the running user name');
        System.assertEquals(true, config.bypassFslScheduleHere, 'Default should bypass scheduleHere');
        System.assertNotEquals(null, config.cardFieldAccess, 'Card field access should be returned');
        System.assertEquals(true, config.cardFieldAccess.size() > 0, 'Default CMDT should have card field access rows');
        Boolean foundAccessible = false;
        for (FsSSMapLayersService.FieldAccessResult accessRow : config.cardFieldAccess) {
            if (accessRow.accessible == true) {
                foundAccessible = true;
            }
        }
        System.assertEquals(true, foundAccessible, 'Default card fields should include an accessible path');
    }

    /**
     * @description Map query returns only Ready Now nearby appointments.
     */
    @IsTest
    static void getMapAppointmentsReturnsReadyNow() {
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Test.startTest();
        FsSSMapLayersService.MapQueryResult queryResult = FsSSMapLayersService.getMapAppointments(
            ORIGIN_LAT,
            ORIGIN_LNG,
            resource.Id
        );
        List<FsSSMapLayersService.MapAppointment> results = queryResult.appointments;
        FsSSPolicyMatcher.ContextRequest contextRequest = new FsSSPolicyMatcher.ContextRequest();
        contextRequest.resourceId = resource.Id;
        contextRequest.policyName = 'Self Scheduling';
        contextRequest.evaluateTerritoryRules = true;
        contextRequest.evaluateSkillRules = true;
        FsSSPolicyMatcher.buildContext(contextRequest);
        Test.stopTest();
        System.assertEquals(true, results.size() >= 1, 'At least the Ready Now appointment should return');
        System.assertEquals(results.size(), queryResult.rowCount, 'Row count should match appointments');
        System.assertEquals(true, queryResult.soql.contains('DISTANCE'), 'SOQL should use DISTANCE');
        System.assertEquals(
            false,
            queryResult.soql.contains('AssignedResource'),
            'Map SOQL should not exclude appointments that already have an Assigned Resource'
        );
        System.assertEquals(
            true,
            queryResult.soql.contains('ServiceAppointment'),
            'SOQL should query Service Appointment'
        );
        System.assertEquals(
            true,
            String.isNotBlank(queryResult.soqlForDisplay),
            'Display SOQL should be populated'
        );
        Boolean foundReady = false;
        for (FsSSMapLayersService.MapAppointment row : results) {
            if (row.firstDetailFieldValue == 'Ready Nearby') {
                foundReady = true;
            }
            System.assertNotEquals('Not Ready', row.firstDetailFieldValue, 'Not Ready appointments must be excluded');
        }
        System.assertEquals(true, foundReady, 'Ready Nearby should be present');
        System.assertNotEquals(null, results[0].cardFields, 'Card fields list should be present');
    }

    /**
     * @description Status picklist options are returned for Service Appointment.
     */
    @IsTest
    static void getAllPicklistOptionsReturnsStatusValues() {
        Test.startTest();
        List<Map<String, String>> options = FsSSMapLayersService.getAllPicklistOptions(
            'ServiceAppointment',
            'Status'
        );
        List<Map<String, String>> ignored = FsSSMapLayersService.getAllPicklistOptions(
            'Account',
            'Name'
        );
        List<Map<String, String>> unknownField = FsSSMapLayersService.getAllPicklistOptions(
            'ServiceAppointment',
            'NotARealField__c'
        );
        Test.stopTest();
        System.assertEquals(true, options.size() > 0, 'Status picklist should return values');
        System.assertEquals(0, ignored.size(), 'Unsupported object should return no options');
        System.assertEquals(0, unknownField.size(), 'Unknown field should return no options');
    }

    /**
     * @description Boolean extra filter matches Ready Now appointments.
     */
    @IsTest
    static void executeFilterQueryMatchesReadyNowFlag() {
        Map<String, String> currentFieldFilter = new Map<String, String>();
        currentFieldFilter.put('type', 'Boolean');
        currentFieldFilter.put('value', 'Is_Ready_Now__c');
        currentFieldFilter.put('input', 'true');
        Test.startTest();
        List<sObject> result = FsSSMapLayersService.executeFilterQuery(
            'ServiceAppointment',
            currentFieldFilter
        );
        List<sObject> ignored = FsSSMapLayersService.executeFilterQuery(
            'Account',
            currentFieldFilter
        );
        List<sObject> missingField = FsSSMapLayersService.executeFilterQuery(
            'ServiceAppointment',
            new Map<String, String>{
                'type' => 'String',
                'value' => 'NotARealField__c',
                'input' => 'x'
            }
        );
        Test.stopTest();
        System.assertEquals(true, result.size() >= 1, 'Ready Now boolean filter should match');
        System.assertEquals(0, ignored.size(), 'Unsupported object should return empty');
        System.assertEquals(0, missingField.size(), 'Unknown field should return empty');
    }

    /**
     * @description Matcher fails closed when the appointment has no territory.
     */
    @IsTest
    static void policyMatcherRejectsBlankTerritory() {
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>();
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>();
        ServiceAppointment appointment = new ServiceAppointment();
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            new Map<Id, List<SkillRequirement>>(),
            context
        );
        Test.stopTest();
        System.assertEquals(false, result.isMatch, 'Blank territory must fail closed');
        System.assertEquals('Territory mismatch', result.skipReason, 'Skip reason should be territory');
    }

    /**
     * @description Matcher rejects a skill the resource does not have.
     */
    @IsTest
    static void policyMatcherRejectsMissingSkill() {
        Id territoryId = UserInfo.getUserId();
        Id parentId = UserInfo.getUserId();
        Id skillId = UserInfo.getUserId();
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>{ territoryId };
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>();
        ServiceAppointment appointment = new ServiceAppointment(
            ServiceTerritoryId = territoryId,
            ParentRecordId = parentId
        );
        SkillRequirement requirement = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = skillId,
            SkillLevel = 1
        );
        Map<Id, List<SkillRequirement>> requirements = new Map<Id, List<SkillRequirement>>{
            parentId => new List<SkillRequirement>{ requirement }
        };
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            requirements,
            context
        );
        Test.stopTest();
        System.assertEquals(false, result.isMatch, 'Missing skill must fail');
        System.assertEquals('Skill mismatch', result.skipReason, 'Skip reason should be skill');
    }

    /**
     * @description Turning off the territory flag skips territory matching.
     */
    @IsTest
    static void policyMatcherSkipsTerritoryWhenFlagOff() {
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>();
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>{ 'MATCH_TERRITORY' };
        context.evaluateTerritoryRules = false;
        context.evaluateSkillRules = true;
        ServiceAppointment appointment = new ServiceAppointment();
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            new Map<Id, List<SkillRequirement>>(),
            context
        );
        Test.stopTest();
        System.assertEquals(true, result.isMatch, 'Blank territory must pass when the flag is off');
    }

    /**
     * @description Policy work-rule list gates skill matching when the skill flag is on.
     */
    @IsTest
    static void policyMatcherSkipsSkillsWhenPolicyOmitsSkillRule() {
        Id territoryId = UserInfo.getUserId();
        Id parentId = UserInfo.getUserId();
        Id skillId = UserInfo.getUserId();
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>{ territoryId };
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>{ 'MATCH_TERRITORY' };
        context.evaluateTerritoryRules = true;
        context.evaluateSkillRules = true;
        ServiceAppointment appointment = new ServiceAppointment(
            ServiceTerritoryId = territoryId,
            ParentRecordId = parentId
        );
        SkillRequirement requirement = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = skillId,
            SkillLevel = 1
        );
        Map<Id, List<SkillRequirement>> requirements = new Map<Id, List<SkillRequirement>>{
            parentId => new List<SkillRequirement>{ requirement }
        };
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            requirements,
            context
        );
        Test.stopTest();
        System.assertEquals(true, result.isMatch, 'Missing skill must pass when the policy has no skill rule');
    }

    /**
     * @description Skill matching runs when the policy lists a skill work rule.
     */
    @IsTest
    static void policyMatcherAppliesSkillRuleFromPolicyList() {
        Id territoryId = UserInfo.getUserId();
        Id parentId = UserInfo.getUserId();
        Id skillId = UserInfo.getUserId();
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>{ territoryId };
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>{ 'MATCH_SKILLS' };
        context.evaluateTerritoryRules = false;
        context.evaluateSkillRules = true;
        ServiceAppointment appointment = new ServiceAppointment(
            ServiceTerritoryId = territoryId,
            ParentRecordId = parentId
        );
        SkillRequirement requirement = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = skillId,
            SkillLevel = 1
        );
        Map<Id, List<SkillRequirement>> requirements = new Map<Id, List<SkillRequirement>>{
            parentId => new List<SkillRequirement>{ requirement }
        };
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            requirements,
            context
        );
        Test.stopTest();
        System.assertEquals(false, result.isMatch, 'Skill rule on the policy must be evaluated');
        System.assertEquals('Skill mismatch', result.skipReason, 'Skip reason should be skill');
    }

    /**
     * @description Unimplemented policy work rules are recorded when the appointment matches.
     */
    @IsTest
    static void policyMatcherRecordsSkippedWorkRuleTypes() {
        Id territoryId = UserInfo.getUserId();
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>{ territoryId };
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>{ 'MATCH_TERRITORY', 'TRAVEL' };
        context.evaluateTerritoryRules = true;
        context.evaluateSkillRules = true;
        ServiceAppointment appointment = new ServiceAppointment(ServiceTerritoryId = territoryId);
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            new Map<Id, List<SkillRequirement>>(),
            context
        );
        Test.stopTest();
        System.assertEquals(true, result.isMatch, 'Territory match should pass');
        System.assertEquals(true, result.skippedRuleTypes.contains('TRAVEL'), 'Other work rules should be recorded');
    }

    /**
     * @description Skills pass when the resource has the required skill and level.
     */
    @IsTest
    static void policyMatcherAcceptsMatchingSkillLevel() {
        Id territoryId = UserInfo.getUserId();
        Id parentId = UserInfo.getUserId();
        Id skillId = UserInfo.getUserId();
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>{ territoryId };
        context.skillLevels = new Map<Id, Decimal>{ skillId => 3 };
        context.policyRuleTypes = new Set<String>{ 'MATCH_SKILLS' };
        context.evaluateTerritoryRules = false;
        context.evaluateSkillRules = true;
        ServiceAppointment appointment = new ServiceAppointment(
            ServiceTerritoryId = territoryId,
            ParentRecordId = parentId
        );
        SkillRequirement requirement = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = skillId,
            SkillLevel = 1
        );
        SkillRequirement blankSkill = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = null
        );
        SkillRequirement noLevel = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = skillId
        );
        Map<Id, List<SkillRequirement>> requirements = new Map<Id, List<SkillRequirement>>{
            parentId => new List<SkillRequirement>{ requirement, blankSkill, noLevel }
        };
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            requirements,
            context
        );
        Test.stopTest();
        System.assertEquals(true, result.isMatch, 'Resource skill level should satisfy the requirement');
    }

    /**
     * @description Skill matching fails when the resource level is too low.
     */
    @IsTest
    static void policyMatcherRejectsInsufficientSkillLevel() {
        Id territoryId = UserInfo.getUserId();
        Id parentId = UserInfo.getUserId();
        Id skillId = UserInfo.getUserId();
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>{ territoryId };
        context.skillLevels = new Map<Id, Decimal>{ skillId => 1 };
        context.policyRuleTypes = new Set<String>{ 'MATCH_SKILLS' };
        context.evaluateTerritoryRules = false;
        context.evaluateSkillRules = true;
        ServiceAppointment appointment = new ServiceAppointment(
            ServiceTerritoryId = territoryId,
            ParentRecordId = parentId
        );
        SkillRequirement requirement = new SkillRequirement(
            RelatedRecordId = parentId,
            SkillId = skillId,
            SkillLevel = 5
        );
        Map<Id, List<SkillRequirement>> requirements = new Map<Id, List<SkillRequirement>>{
            parentId => new List<SkillRequirement>{ requirement }
        };
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            requirements,
            context
        );
        Test.stopTest();
        System.assertEquals(false, result.isMatch, 'Lower skill level must fail');
    }

    /**
     * @description Blank policy name returns no work-rule tokens.
     */
    @IsTest
    static void listPolicyRuleTypesBlankNameReturnsEmpty() {
        Test.startTest();
        List<String> blankName = FsSSPolicyMatcher.listPolicyRuleTypes(null);
        List<String> missingPolicy = FsSSPolicyMatcher.listPolicyRuleTypes('Missing Policy Name');
        FsSSPolicyMatcher.ContextRequest contextRequest = new FsSSPolicyMatcher.ContextRequest();
        contextRequest.policyName = 'Self Scheduling';
        contextRequest.evaluateTerritoryRules = false;
        contextRequest.evaluateSkillRules = true;
        FsSSPolicyMatcher.ResourceContext context = FsSSPolicyMatcher.buildContext(
            contextRequest
        );
        Test.stopTest();
        System.assertEquals(0, blankName.size(), 'Blank policy name should return no types');
        System.assertEquals(0, missingPolicy.size(), 'Unknown policy should return no types');
        System.assertEquals(false, context.evaluateTerritoryRules, 'Territory flag should be off');
        System.assertEquals(true, context.evaluateSkillRules, 'Skill flag should be on');
    }

    /**
     * @description Location work-rule tokens gate territory matching.
     */
    @IsTest
    static void policyMatcherUsesLocationTokenForTerritory() {
        FsSSPolicyMatcher.ResourceContext context = new FsSSPolicyMatcher.ResourceContext();
        context.territoryIds = new Set<Id>();
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>{ 'MATCH_LOCATION' };
        context.evaluateTerritoryRules = true;
        context.evaluateSkillRules = false;
        ServiceAppointment appointment = new ServiceAppointment();
        Test.startTest();
        FsSSPolicyMatcher.MatchResult result = FsSSPolicyMatcher.evaluate(
            appointment,
            new Map<Id, List<SkillRequirement>>(),
            context
        );
        Test.stopTest();
        System.assertEquals(false, result.isMatch, 'Location rule should require a territory');
        System.assertEquals('Territory mismatch', result.skipReason, 'Skip reason should be territory');
    }

    /**
     * @description Claim rejects an appointment that already has an assigned resource.
     */
    @IsTest
    static void selfScheduleRejectsAlreadyAssigned() {
        ServiceAppointment appointment = [
            SELECT Id, SchedStartTime, SchedEndTime
            FROM ServiceAppointment
            WHERE Subject = 'Ready Nearby'
            LIMIT 1
        ];
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Datetime startTime = System.now();
        update new ServiceAppointment(
            Id = appointment.Id,
            SchedStartTime = startTime,
            SchedEndTime = startTime.addMinutes(60)
        );
        insert new AssignedResource(
            ServiceAppointmentId = appointment.Id,
            ServiceResourceId = resource.Id
        );
        Boolean threw = false;
        Test.startTest();
        try {
            FsSSMapLayersService.selfSchedule(appointment.Id, resource.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Already assigned appointments must not be claimed');
    }

    /**
     * @description Invalid origin returns an empty list.
     */
    @IsTest
    static void getMapAppointmentsNullOriginReturnsEmpty() {
        Test.startTest();
        FsSSMapLayersService.MapQueryResult queryResult = FsSSMapLayersService.getMapAppointments(
            null,
            ORIGIN_LNG,
            null
        );
        Test.stopTest();
        System.assertEquals(0, queryResult.appointments.size(), 'Null latitude should return no rows');
        System.assertEquals(0, queryResult.rowCount, 'Null latitude should report zero rows');
    }

    /**
     * @description Claim creates an assignment in tests and sets Dispatched.
     */
    @IsTest
    static void selfScheduleDispatchesAppointment() {
        ServiceAppointment appointment = [
            SELECT Id
            FROM ServiceAppointment
            WHERE Subject = 'Ready Nearby'
            LIMIT 1
        ];
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Test.startTest();
        Id claimedId = FsSSMapLayersService.selfSchedule(appointment.Id, resource.Id);
        Test.stopTest();
        ServiceAppointment claimed = [
            SELECT Status
            FROM ServiceAppointment
            WHERE Id = :claimedId
        ];
        System.assertEquals('Dispatched', claimed.Status, 'Claimed appointment should be Dispatched');
        Integer assigned = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :claimedId
        ];
        System.assertEquals(1, assigned, 'Assigned resource should be created');
    }

    /**
     * @description Claim rejects appointments that are not Ready Now.
     */
    @IsTest
    static void selfScheduleRejectsNotReady() {
        ServiceAppointment appointment = [
            SELECT Id
            FROM ServiceAppointment
            WHERE Subject = 'Not Ready'
            LIMIT 1
        ];
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Boolean threw = false;
        Test.startTest();
        try {
            FsSSMapLayersService.selfSchedule(appointment.Id, resource.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Not Ready appointments must not be claimed');
    }

    /**
     * @description Extra filter matches Ready Now by subject.
     */
    @IsTest
    static void executeFilterQueryMatchesSubject() {
        Map<String, String> currentFieldFilter = new Map<String, String>();
        currentFieldFilter.put('type', 'String');
        currentFieldFilter.put('value', 'Subject');
        currentFieldFilter.put('input', 'Ready Nearby');
        Test.startTest();
        List<sObject> result = FsSSMapLayersService.executeFilterQuery(
            'ServiceAppointment',
            currentFieldFilter
        );
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Subject filter should match one Ready Now appointment');
    }

    /**
     * @description Resource context resolves the running user's Service Resource.
     */
    @IsTest
    static void getResourceContextResolvesRunningUser() {
        ServiceResource expected = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Test.startTest();
        FsSSMapLayersService.ResourceContextDto context = FsSSMapLayersService.getResourceContext(
            null
        );
        Test.stopTest();
        System.assertNotEquals(null, context, 'Running user should resolve a Service Resource');
        System.assertEquals(
            expected.Id,
            context.resourceId,
            'Resource context should return the linked Service Resource'
        );
    }

    /**
     * @description Resource context honours an explicit Service Resource Id.
     */
    @IsTest
    static void getResourceContextHonoursExplicitId() {
        ServiceResource expected = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Test.startTest();
        FsSSMapLayersService.ResourceContextDto context = FsSSMapLayersService.getResourceContext(
            expected.Id
        );
        Test.stopTest();
        System.assertEquals(
            expected.Id,
            context.resourceId,
            'Explicit resource Id should be returned unchanged'
        );
    }

    /**
     * @description Resource context returns null when no resource matches.
     */
    @IsTest
    static void getResourceContextReturnsNullWhenMissing() {
        Id missingId = Id.valueOf(
            ServiceResource.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getKeyPrefix() + '000000000000'
        );
        Test.startTest();
        FsSSMapLayersService.ResourceContextDto context = FsSSMapLayersService.getResourceContext(
            missingId
        );
        Test.stopTest();
        System.assertEquals(null, context, 'Unknown resource Id should return null');
    }

    /**
     * @description Field values used to build a test Service Appointment.
     */

    /**
     * @description Card field helper keeps safe paths, skips invalid ones, and formats blanks.
     */
    @IsTest
    static void cardFieldHelperSelectsSafePathsAndFormatsValues() {
        FsSSConfigParser.CardDetailField durationField = new FsSSConfigParser.CardDetailField();
        durationField.label = 'Duration(Mins)';
        durationField.fieldApiName = 'DurationInMinutes';
        FsSSConfigParser.CardDetailField workTypeField = new FsSSConfigParser.CardDetailField();
        workTypeField.label = 'Work Type';
        workTypeField.fieldApiName = 'WorkType.Name';
        FsSSConfigParser.CardDetailField duplicateField = new FsSSConfigParser.CardDetailField();
        duplicateField.label = 'Duration Copy';
        duplicateField.fieldApiName = 'DurationInMinutes';
        FsSSConfigParser.CardDetailField invalidField = new FsSSConfigParser.CardDetailField();
        invalidField.label = 'Invalid';
        invalidField.fieldApiName = 'NotAField__c';
        FsSSConfigParser.CardDetailField nestedField = new FsSSConfigParser.CardDetailField();
        nestedField.label = 'Nested';
        nestedField.fieldApiName = 'WorkType.Name.Extra';
        List<FsSSConfigParser.CardDetailField> fields = new List<FsSSConfigParser.CardDetailField>{
            durationField,
            workTypeField,
            duplicateField,
            invalidField,
            nestedField
        };
        ServiceAppointment appointment = [
            SELECT Id, DurationInMinutes, WorkType.Name
            FROM ServiceAppointment
            WHERE Subject = 'Ready Nearby'
            LIMIT 1
        ];
        Test.startTest();
        List<String> selected = FsSSCardFieldHelper.selectFields(fields);
        List<String> emptySelected = FsSSCardFieldHelper.selectFields(null);
        List<FsSSMapLayersService.CardField> cardFields = FsSSCardFieldHelper.toCardFields(
            appointment,
            fields
        );
        List<FsSSMapLayersService.CardField> emptyCards = FsSSCardFieldHelper.toCardFields(
            appointment,
            null
        );
        Boolean durationSafe = FsSSCardFieldHelper.isSafePath('DurationInMinutes');
        Boolean workTypeSafe = FsSSCardFieldHelper.isSafePath('WorkType.Name');
        Boolean nestedSafe = FsSSCardFieldHelper.isSafePath('WorkType.Name.Extra');
        Boolean blankSafe = FsSSCardFieldHelper.isSafePath('');
        Boolean missingSafe = FsSSCardFieldHelper.isSafePath('NotAField__c');
        Test.stopTest();
        System.assertEquals(true, durationSafe, 'DurationInMinutes should be a safe path');
        System.assertEquals(true, workTypeSafe, 'WorkType.Name should be a safe one-level path');
        System.assertEquals(false, nestedSafe, 'Two-level relationship paths must be rejected');
        System.assertEquals(false, blankSafe, 'Blank paths must be rejected');
        System.assertEquals(false, missingSafe, 'Unknown fields must be rejected');
        System.assertEquals(0, emptySelected.size(), 'Null field list should select nothing');
        System.assertEquals(0, emptyCards.size(), 'Null field list should return no card fields');
        System.assertEquals(true, selected.contains('DurationInMinutes'), 'Duration should be selected once');
        System.assertEquals(true, selected.contains('WorkType.Name'), 'WorkType.Name should be selected');
        System.assertEquals(false, selected.contains('NotAField__c'), 'Unknown fields must not be selected');
        Integer durationCount = 0;
        for (String path : selected) {
            if (path == 'DurationInMinutes') {
                durationCount++;
            }
        }
        System.assertEquals(1, durationCount, 'Duplicate DurationInMinutes tokens should collapse');
        System.assertEquals(true, cardFields.size() >= 2, 'Safe card fields should render');
        System.assertEquals('Duration(Mins)', cardFields[0].label, 'First card label should match CMDT');
        System.assertEquals(true, String.isNotBlank(cardFields[0].value), 'Duration value should be populated or dashed');
        System.assertEquals('Work Type', cardFields[1].label, 'Second card label should match CMDT');
        System.assertEquals('—', cardFields[1].value, 'Missing Work Type should display an em dash');
        System.assertEquals(false, cardFields[0].isPhone, 'Duration is not a phone field');
        System.assertEquals('DurationInMinutes', cardFields[0].fieldApiName, 'Duration field API name should be set');
    }

    /**
     * @description describeAccess reports safe paths, invalid paths, and skipped tokens.
     */
    @IsTest
    static void cardFieldHelperDescribeAccessReportsSafeAndInvalidPaths() {
        FsSSConfigParser.CardDetailField durationField = new FsSSConfigParser.CardDetailField();
        durationField.label = 'Duration(Mins)';
        durationField.fieldApiName = 'DurationInMinutes';
        FsSSConfigParser.CardDetailField invalidField = new FsSSConfigParser.CardDetailField();
        invalidField.label = 'Invalid';
        invalidField.fieldApiName = 'NotAField__c';
        Test.startTest();
        List<FsSSMapLayersService.FieldAccessResult> accessRows = FsSSCardFieldHelper.describeAccess(
            new List<FsSSConfigParser.CardDetailField>{ durationField, invalidField },
            new List<String>{ 'NotAField' }
        );
        Boolean durationPhone = FsSSCardFieldHelper.isPhonePath('DurationInMinutes');
        Boolean contactPhone = FsSSCardFieldHelper.isPhonePath('Contact.Phone');
        Test.stopTest();
        System.assertEquals(3, accessRows.size(), 'Access rows should include CMDT fields and skipped tokens');
        System.assertEquals(true, accessRows[0].accessible, 'DurationInMinutes should be accessible');
        System.assertEquals(false, accessRows[1].accessible, 'Unknown fields should be inaccessible');
        System.assertEquals(false, accessRows[2].accessible, 'Skipped tokens should be inaccessible');
        System.assertEquals('Parser skipped this token', accessRows[2].reason, 'Skipped token reason should be set');
        System.assertEquals(false, durationPhone, 'DurationInMinutes is not a phone path');
        System.assertEquals(true, contactPhone, 'Contact.Phone should be treated as a phone path');
    }

    /**
     * @description Map SOQL selects relationship card fields once and skips base duplicates.
     */
    @IsTest
    static void getMapAppointmentsSelectsCardFieldsWithoutDuplicateColumns() {
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Test.startTest();
        FsSSMapLayersService.MapQueryResult queryResult = FsSSMapLayersService.getMapAppointments(
            ORIGIN_LAT,
            ORIGIN_LNG,
            resource.Id
        );
        Test.stopTest();
        System.assertEquals(true, queryResult.appointments.size() >= 1, 'Ready Now appointment should return');
        System.assertEquals(
            true,
            queryResult.soql.contains('WorkType.Name'),
            'SOQL should select WorkType.Name from card fields'
        );
        System.assertEquals(
            true,
            queryResult.soql.contains('Contact.Name'),
            'SOQL should select Contact.Name from card fields'
        );
        System.assertEquals(
            true,
            queryResult.soql.contains('Contact.Phone'),
            'SOQL should select Contact.Phone from card fields'
        );
        Integer firstDuration = queryResult.soql.indexOf('DurationInMinutes');
        Integer lastDuration = queryResult.soql.lastIndexOf('DurationInMinutes');
        System.assertEquals(
            true,
            firstDuration >= 0 && firstDuration == lastDuration,
            'DurationInMinutes must appear only once in SELECT'
        );
        System.assertEquals(true, queryResult.appointments[0].cardFields.size() >= 1, 'Card fields should be populated');
    }

    /**
     * @description Claim uses the scheduleHere stub when CMDT bypass is off.
     */
    @IsTest
    static void selfScheduleUsesScheduleHereWhenBypassOff() {
        ServiceAppointment appointment = [
            SELECT Id
            FROM ServiceAppointment
            WHERE Subject = 'Ready Nearby'
            LIMIT 1
        ];
        ServiceResource resource = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        FS_Self_Scheduling_Config__mdt record = new FS_Self_Scheduling_Config__mdt(
            Bypass_Fsl_Schedule_Here__c = false,
            Scheduling_Policy_Name__c = 'Self Scheduling',
            Target_Status__c = 'Dispatched',
            Status_Values__c = 'None,Scheduled'
        );
        FsSSSelfScheduler.settingsOverride = FsSSConfigParser.fromRecord(record);
        Test.startTest();
        Id claimedId = FsSSMapLayersService.selfSchedule(appointment.Id, resource.Id);
        Test.stopTest();
        ServiceAppointment claimed = [
            SELECT Status
            FROM ServiceAppointment
            WHERE Id = :claimedId
        ];
        System.assertEquals('Dispatched', claimed.Status, 'scheduleHere path should still dispatch');
        Integer assigned = [
            SELECT COUNT()
            FROM AssignedResource
            WHERE ServiceAppointmentId = :claimedId
        ];
        System.assertEquals(1, assigned, 'scheduleHere stub should insert Assigned Resource');
    }

    /**
     * @description Claim rejects null appointment or resource Ids.
     */
    @IsTest
    static void selfScheduleRejectsNullIds() {
        Boolean threw = false;
        Test.startTest();
        try {
            FsSSMapLayersService.selfSchedule(null, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Null Ids must be rejected');
    }

    private class AppointmentSpec {
        /** @description Parent Work Order Id */
        private Id parentId;
        /** @description Appointment subject */
        private String subject;
        /** @description Latitude */
        private Decimal latitude;
        /** @description Longitude */
        private Decimal longitude;
        /** @description Ready Now flag */
        private Boolean isReadyNow;
        /** @description Service Territory Id */
        private Id territoryId;
    }

    /**
     * @description Builds a Service Appointment for tests.
     * @param spec Field values for the appointment.
     * @return Unsaved Service Appointment.
     */
    private static ServiceAppointment buildAppointment(AppointmentSpec spec) {
        return new ServiceAppointment(
            ParentRecordId = spec.parentId,
            Subject = spec.subject,
            Status = spec.isReadyNow ? 'Scheduled' : 'None',
            EarliestStartTime = System.now(),
            DueDate = System.now().addDays(1),
            Duration = 60,
            DurationType = 'Minutes',
            City = 'Auckland',
            Country = 'New Zealand',
            Latitude = spec.latitude,
            Longitude = spec.longitude,
            ServiceTerritoryId = spec.territoryId,
            Is_Ready_Now__c = spec.isReadyNow
        );
    }

    /**
     * @description Ensures a Service Resource exists for the running user.
     */
    private static void upsertResource() {
        List<ServiceResource> existing = [
            SELECT Id
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }
        insert new ServiceResource(
            Name = 'Self Scheduling Resource',
            RelatedRecordId = UserInfo.getUserId(),
            IsActive = true,
            ResourceType = 'T'
        );
    }
}
