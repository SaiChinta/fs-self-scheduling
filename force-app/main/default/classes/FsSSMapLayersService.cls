/**
 * @description AuraEnabled facade for the Field Service Self Scheduling map.
 */
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.StdCyclomaticComplexity')
public with sharing class FsSSMapLayersService {
    private static final String SERVICE_APPOINTMENT = 'ServiceAppointment';
    private static final String UNIT_MILES = 'mi';
    private static final String SKIP_TERRITORY = 'Territory mismatch';
    private static final String SKIP_SKILL = 'Skill mismatch';

    /**
     * @description Test-only replacement for FsSSConfigParser.loadDefault().
     */
    @TestVisible
    private static FsSSConfigParser.Settings settingsOverride;

    /**
     * @description Marker payload returned to the map LWC.
     */
    public class MapAppointment {
        /** @description Service Appointment Id */
        @AuraEnabled
        public Id id;
        /** @description Latitude */
        @AuraEnabled
        public Decimal latitude;
        /** @description Longitude */
        @AuraEnabled
        public Decimal longitude;
        /** @description Appointment number */
        @AuraEnabled
        public String titleFieldValue;
        /** @description Subject */
        @AuraEnabled
        public String firstDetailFieldValue;
        /** @description Status */
        @AuraEnabled
        public String secondDetailFieldValue;
        /** @description Duration in minutes as text */
        @AuraEnabled
        public String thirdDetailFieldValue;
        /** @description Parent work record Id */
        @AuraEnabled
        public Id parentRecordId;
        /** @description Service territory Id */
        @AuraEnabled
        public Id serviceTerritoryId;
        /** @description Duration minutes numeric */
        @AuraEnabled
        public Decimal durationInMinutes;
        /** @description Policy skip reason when applicable */
        @AuraEnabled
        public String skipReason;
        /** @description CMDT-driven Label:Value pairs for the appointment card */
        @AuraEnabled
        public List<CardField> cardFields;
    }

    /**
     * @description One card field shown as Label: value.
     */
    public class CardField {
        /** @description Display label */
        @AuraEnabled
        public String label;
        /** @description Display value */
        @AuraEnabled
        public String value;
        /** @description Field API name or Relationship.Field */
        @AuraEnabled
        public String fieldApiName;
        /** @description True when the value should render as a tel: link */
        @AuraEnabled
        public Boolean isPhone;
    }

    /**
     * @description Access status for one CMDT card field path.
     */
    public class FieldAccessResult {
        /** @description Display label */
        @AuraEnabled
        public String label;
        /** @description Field API name or raw token */
        @AuraEnabled
        public String fieldApiName;
        /** @description True when the running user can read the path */
        @AuraEnabled
        public Boolean accessible;
        /** @description Accessible, skipped, or not readable */
        @AuraEnabled
        public String reason;
    }

    /**
     * @description Map query payload including appointments and the SOQL used.
     */
    public class MapQueryResult {
        /** @description Marker wrappers inside the search radius */
        @AuraEnabled
        public List<MapAppointment> appointments;
        /** @description SOQL with bind variable names */
        @AuraEnabled
        public String soql;
        /** @description SOQL with bind values substituted for Query Editor */
        @AuraEnabled
        public String soqlForDisplay;
        /** @description Latitude bind used in DISTANCE */
        @AuraEnabled
        public Decimal bindLatitude;
        /** @description Longitude bind used in DISTANCE */
        @AuraEnabled
        public Decimal bindLongitude;
        /** @description Radius bind used in DISTANCE */
        @AuraEnabled
        public Decimal bindRadius;
        /** @description LIMIT bind */
        @AuraEnabled
        public Integer bindRowLimit;
        /** @description Status IN bind values */
        @AuraEnabled
        public List<String> bindStatuses;
        /** @description Boolean AND fragment actually appended */
        @AuraEnabled
        public String booleanClause;
        /** @description Number of rows returned after policy matching */
        @AuraEnabled
        public Integer rowCount;
        /** @description Service Resource Id used for matching, or null */
        @AuraEnabled
        public Id matchedResourceId;
        /** @description True when territory or skill matching ran */
        @AuraEnabled
        public Boolean policyMatchingApplied;
        /** @description Radius query size before policy matching */
        @AuraEnabled
        public Integer radiusRowCount;
        /** @description Appointments dropped for territory mismatch */
        @AuraEnabled
        public Integer skippedTerritoryCount;
        /** @description Appointments dropped for skill mismatch */
        @AuraEnabled
        public Integer skippedSkillCount;
        /** @description Work rule types loaded for the resolved resource */
        @AuraEnabled
        public List<String> policyRuleTypes;
        /** @description Policy work rule types this package does not evaluate */
        @AuraEnabled
        public List<String> unimplementedRuleTypes;
    }

    /**
     * @description Serializable settings for the LWC.
     */
    public class ConfigDto {
        /** @description Search radius */
        @AuraEnabled
        public Decimal searchRadius;
        /** @description km or mi */
        @AuraEnabled
        public String distanceUnit;
        /** @description Status query filters */
        @AuraEnabled
        public List<String> statusValues;
        /** @description Boolean query filters as Field=value tokens */
        @AuraEnabled
        public List<String> booleanFilterTokens;
        /** @description Scheduling policy name */
        @AuraEnabled
        public String schedulingPolicyName;
        /** @description Post-claim status */
        @AuraEnabled
        public String targetStatus;
        /** @description Debug panel gate */
        @AuraEnabled
        public Boolean debugEnabled;
        /** @description Query cap */
        @AuraEnabled
        public Integer maxResults;
        /** @description When true, evaluate Match Territory and location work rules */
        @AuraEnabled
        public Boolean evaluateTerritoryRules;
        /** @description When true, evaluate Match Skills work rules */
        @AuraEnabled
        public Boolean evaluateSkillRules;
        /** @description Work rule types loaded from the named scheduling policy */
        @AuraEnabled
        public List<String> policyRuleTypes;
        /** @description Running user name */
        @AuraEnabled
        public String userName;
        /** @description When true, claim skips FSL.ScheduleService.scheduleHere */
        @AuraEnabled
        public Boolean bypassFslScheduleHere;
        /** @description CMDT card field tokens the parser skipped */
        @AuraEnabled
        public List<String> skippedCardFieldTokens;
        /** @description Access check for each CMDT card field */
        @AuraEnabled
        public List<FieldAccessResult> cardFieldAccess;
    }

    /**
     * @description Service Resource context for the map LWC.
     */
    public class ResourceContextDto {
        /** @description Service Resource Id */
        @AuraEnabled
        public Id resourceId;
        /** @description Last known latitude */
        @AuraEnabled
        public Decimal latitude;
        /** @description Last known longitude */
        @AuraEnabled
        public Decimal longitude;
        /** @description Service Resource name */
        @AuraEnabled
        public String resourceName;
    }

    /**
     * @description Resolves the Service Resource for the running user, or an explicit resource when debugging.
     * @param resourceId Optional Service Resource Id; when null the running user's resource is used.
     * @return Resource context with last known location, or null when no resource is linked.
     */
    @AuraEnabled(cacheable=true)
    public static ResourceContextDto getResourceContext(Id resourceId) {
        try {
            List<ServiceResource> rows = queryResource(resourceId);
            if (rows.isEmpty()) {
                return null;
            }
            ResourceContextDto dto = new ResourceContextDto();
            dto.resourceId = rows[0].Id;
            dto.latitude = rows[0].LastKnownLatitude;
            dto.longitude = rows[0].LastKnownLongitude;
            dto.resourceName = rows[0].Name;
            return dto;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description Loads the requested Service Resource, defaulting to the running user's.
     * @param resourceId Optional explicit Service Resource Id.
     * @return Zero or one Service Resource.
     */
    private static List<ServiceResource> queryResource(Id resourceId) {
        if (resourceId != null) {
            return [
                SELECT Id, Name, LastKnownLatitude, LastKnownLongitude
                FROM ServiceResource
                WHERE Id = :resourceId
                WITH USER_MODE
                LIMIT 1
            ];
        }
        Id userId = UserInfo.getUserId();
        return [
            SELECT Id, Name, LastKnownLatitude, LastKnownLongitude
            FROM ServiceResource
            WHERE RelatedRecordId = :userId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /**
     * @description Loads parsed Default CMDT settings for the LWC.
     * @return Config DTO.
     */
    @AuraEnabled(cacheable=true)
    public static ConfigDto getConfig() {
        try {
            return toDto(FsSSConfigParser.loadDefault());
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description Returns appointments inside the configured radius of an origin
     *              that match the resource's territory and skill rules when those
     *              CMDT flags are on. When resourceId is null, matching uses the
     *              Service Resource whose RelatedRecordId is the running user.
     * @param latitude Origin latitude.
     * @param longitude Origin longitude.
     * @param resourceId Optional Service Resource Id; null injects the running user.
     * @return Appointments plus the SOQL, bind values, and matching diagnostics.
     */
    @AuraEnabled
    public static MapQueryResult getMapAppointments(
        Decimal latitude,
        Decimal longitude,
        Id resourceId
    ) {
        try {
            return queryMapAppointments(latitude, longitude, resourceId);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description Claims an appointment for the resource using scheduleHere, then dispatches it.
     * @param appointmentId Service Appointment Id.
     * @param resourceId Service Resource Id.
     * @return Claimed appointment Id.
     */
    @AuraEnabled
    public static Id selfSchedule(Id appointmentId, Id resourceId) {
        try {
            return FsSSSelfScheduler.claim(appointmentId, resourceId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description Returns picklist values for a Service Appointment field.
     * @param obj Object API name.
     * @param field Field API name.
     * @return Value/label maps.
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getAllPicklistOptions(String obj, String field) {
        try {
            if (!SERVICE_APPOINTMENT.equalsIgnoreCase(obj) || !isSafeField(obj, field)) {
                return new List<Map<String, String>>();
            }
            Schema.DescribeFieldResult fieldDescribe = Schema.sObjectType.ServiceAppointment.fields.getMap()
                .get(field)
                .getDescribe();
            List<Map<String, String>> options = new List<Map<String, String>>();
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                Map<String, String> option = new Map<String, String>();
                option.put('value', entry.getValue());
                option.put('label', entry.getLabel());
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description Extra field filter against Ready Now appointments.
     * @param currentObjectFilter Object API name.
     * @param currentFieldFilter type, value, input.
     * @return Matching Ids.
     */
    @AuraEnabled(cacheable=false)
    public static List<sObject> executeFilterQuery(
        String currentObjectFilter,
        Map<String, String> currentFieldFilter
    ) {
        try {
            if (!SERVICE_APPOINTMENT.equalsIgnoreCase(currentObjectFilter) || currentFieldFilter == null) {
                return new List<sObject>();
            }
            String fieldName = currentFieldFilter.get('value');
            if (String.isBlank(fieldName) || !isSafeField(currentObjectFilter, fieldName)) {
                return new List<sObject>();
            }
            Map<String, Object> binds = new Map<String, Object>{
                'filterValue' => coerceFilterValue(
                    currentFieldFilter.get('type'),
                    currentFieldFilter.get('input')
                )
            };
            String soql =
                'SELECT Id FROM ServiceAppointment WHERE FS_Ready_Now__c = true AND ' +
                String.escapeSingleQuotes(fieldName) +
                ' = :filterValue';
            return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description Converts the raw filter input into a typed bind value.
     * @param fieldType Describe type reported by the client.
     * @param input Raw user input.
     * @return Typed value suitable for a SOQL bind variable.
     */
    private static Object coerceFilterValue(String fieldType, String input) {
        if (fieldType == 'Boolean') {
            return Boolean.valueOf(input);
        }
        if (fieldType == 'Integer') {
            return Integer.valueOf(input);
        }
        if (fieldType == 'Double' || fieldType == 'Currency' || fieldType == 'Percent') {
            return Double.valueOf(input);
        }
        return input;
    }

    /**
     * @description Runs the radius query, then applies territory and skill matching.
     * @param latitude Origin latitude.
     * @param longitude Origin longitude.
     * @param resourceId Optional Service Resource Id; null injects the running user.
     * @return Query result wrapper; empty appointments when origin is null.
     */
    private static MapQueryResult queryMapAppointments(
        Decimal latitude,
        Decimal longitude,
        Id resourceId
    ) {
        MapQueryResult result = newEmptyQueryResult();
        if (latitude == null || longitude == null) {
            return result;
        }
        FsSSConfigParser.Settings settings = settingsOverride != null
            ? settingsOverride
            : FsSSConfigParser.loadDefault();
        populateQueryMetadata(result, latitude, longitude, settings);
        List<ServiceAppointment> rows = (List<ServiceAppointment>) Database.queryWithBinds(
            result.soql,
            toBindMap(result),
            AccessLevel.USER_MODE
        );
        List<ServiceResource> resources = queryResource(resourceId);
        Id resolvedResourceId = resources.isEmpty() ? null : resources[0].Id;
        applyPolicyMatching(rows, resolvedResourceId, settings, result);
        return result;
    }

    /**
     * @description Filters radius rows through territory and skill matching.
     * @param rows Radius query results.
     * @param resolvedResourceId Service Resource used for matching, or null.
     * @param settings Parsed CMDT.
     * @param result Query result being populated.
     */
    private static void applyPolicyMatching(
        List<ServiceAppointment> rows,
        Id resolvedResourceId,
        FsSSConfigParser.Settings settings,
        MapQueryResult result
    ) {
        result.radiusRowCount = rows.size();
        result.matchedResourceId = resolvedResourceId;
        if (!shouldApplyMatching(resolvedResourceId, settings)) {
            addAppointments(rows, settings, result);
            result.policyMatchingApplied = false;
            result.rowCount = result.appointments.size();
            return;
        }
        result.policyMatchingApplied = true;
        FsSSPolicyMatcher.ResourceContext context = buildMatcherContext(
            resolvedResourceId,
            settings
        );
        result.policyRuleTypes = new List<String>(context.policyRuleTypes);
        Map<Id, List<SkillRequirement>> skillRequirements =
            settings.evaluateSkillRules == true
                ? FsSSPolicyMatcher.loadSkillRequirements(parentIdsFrom(rows))
                : new Map<Id, List<SkillRequirement>>();
        Set<String> unimplemented = new Set<String>();
        for (ServiceAppointment row : rows) {
            addMatchedAppointment(
                row,
                settings,
                context,
                skillRequirements,
                unimplemented,
                result
            );
        }
        result.unimplementedRuleTypes = new List<String>(unimplemented);
        result.rowCount = result.appointments.size();
    }

    /**
     * @description True when a resource is resolved and at least one rule flag is on.
     * @param resolvedResourceId Resolved Service Resource Id.
     * @param settings Parsed CMDT.
     * @return True when matching should run.
     */
    private static Boolean shouldApplyMatching(
        Id resolvedResourceId,
        FsSSConfigParser.Settings settings
    ) {
        if (resolvedResourceId == null) {
            return false;
        }
        return settings.evaluateTerritoryRules == true ||
            settings.evaluateSkillRules == true;
    }

    /**
     * @description Builds matcher context for the resolved resource.
     * @param resolvedResourceId Service Resource Id.
     * @param settings Parsed CMDT.
     * @return Matcher resource context.
     */
    private static FsSSPolicyMatcher.ResourceContext buildMatcherContext(
        Id resolvedResourceId,
        FsSSConfigParser.Settings settings
    ) {
        FsSSPolicyMatcher.ContextRequest request = new FsSSPolicyMatcher.ContextRequest();
        request.resourceId = resolvedResourceId;
        request.policyName = settings.schedulingPolicyName;
        request.evaluateTerritoryRules = settings.evaluateTerritoryRules;
        request.evaluateSkillRules = settings.evaluateSkillRules;
        return FsSSPolicyMatcher.buildContext(request);
    }

    /**
     * @description Keeps a matching appointment or increments skip counters.
     * @param row Candidate appointment.
     * @param settings Parsed CMDT.
     * @param context Matcher resource context.
     * @param skillRequirements Requirements keyed by parent Id.
     * @param unimplemented Collector for unimplemented work rule types.
     * @param result Query result being populated.
     */
    private static void addMatchedAppointment(
        ServiceAppointment row,
        FsSSConfigParser.Settings settings,
        FsSSPolicyMatcher.ResourceContext context,
        Map<Id, List<SkillRequirement>> skillRequirements,
        Set<String> unimplemented,
        MapQueryResult result
    ) {
        FsSSPolicyMatcher.MatchResult matchResult = FsSSPolicyMatcher.evaluate(
            row,
            skillRequirements,
            context
        );
        if (matchResult.isMatch == true) {
            result.appointments.add(toMapAppointment(row, settings));
            if (matchResult.skippedRuleTypes != null) {
                unimplemented.addAll(matchResult.skippedRuleTypes);
            }
            return;
        }
        incrementSkipCount(result, matchResult.skipReason);
    }

    /**
     * @description Increments skip counters for a matcher skip reason.
     * @param result Query result being populated.
     * @param skipReason Matcher skip reason.
     */
    private static void incrementSkipCount(MapQueryResult result, String skipReason) {
        if (SKIP_TERRITORY.equals(skipReason)) {
            result.skippedTerritoryCount++;
            return;
        }
        if (SKIP_SKILL.equals(skipReason)) {
            result.skippedSkillCount++;
        }
    }

    /**
     * @description Collects parent record Ids from radius rows.
     * @param rows Radius query results.
     * @return Parent Work Order or Work Order Line Item Ids.
     */
    private static Set<Id> parentIdsFrom(List<ServiceAppointment> rows) {
        Set<Id> parentIds = new Set<Id>();
        for (ServiceAppointment row : rows) {
            if (row.ParentRecordId != null) {
                parentIds.add(row.ParentRecordId);
            }
        }
        return parentIds;
    }

    /**
     * @description Converts every radius row without policy matching.
     * @param rows Radius query results.
     * @param settings Parsed CMDT.
     * @param result Query result being populated.
     */
    private static void addAppointments(
        List<ServiceAppointment> rows,
        FsSSConfigParser.Settings settings,
        MapQueryResult result
    ) {
        for (ServiceAppointment row : rows) {
            result.appointments.add(toMapAppointment(row, settings));
        }
    }

    /**
     * @description Builds an empty query result with safe list defaults.
     * @return Empty map query result.
     */
    private static MapQueryResult newEmptyQueryResult() {
        MapQueryResult result = new MapQueryResult();
        result.appointments = new List<MapAppointment>();
        result.bindStatuses = new List<String>();
        result.soql = '';
        result.soqlForDisplay = '';
        result.booleanClause = '';
        result.rowCount = 0;
        result.policyMatchingApplied = false;
        result.radiusRowCount = 0;
        result.skippedTerritoryCount = 0;
        result.skippedSkillCount = 0;
        result.policyRuleTypes = new List<String>();
        result.unimplementedRuleTypes = new List<String>();
        return result;
    }

    /**
     * @description Fills SOQL, binds, and the display query on the result wrapper.
     * @param result Wrapper being populated.
     * @param latitude Origin latitude.
     * @param longitude Origin longitude.
     * @param settings Parsed CMDT.
     */
    private static void populateQueryMetadata(
        MapQueryResult result,
        Decimal latitude,
        Decimal longitude,
        FsSSConfigParser.Settings settings
    ) {
        Boolean useMiles = UNIT_MILES.equalsIgnoreCase(settings.distanceUnit);
        result.soql = buildAppointmentSoql(settings, useMiles);
        result.bindLatitude = latitude;
        result.bindLongitude = longitude;
        result.bindRadius = settings.searchRadius;
        result.bindRowLimit = settings.maxResults;
        result.bindStatuses = settings.statusValues;
        result.booleanClause = buildBooleanFilterClause(settings.booleanFilters);
        result.soqlForDisplay = toDisplaySoql(result);
    }

    /**
     * @description Bind map matching the tokens in buildAppointmentSoql.
     * @param result Query result holding bind values.
     * @return Bind map for Database.queryWithBinds.
     */
    private static Map<String, Object> toBindMap(MapQueryResult result) {
        return new Map<String, Object>{
            'latitude' => result.bindLatitude,
            'longitude' => result.bindLongitude,
            'radius' => result.bindRadius,
            'rowLimit' => result.bindRowLimit,
            'statuses' => result.bindStatuses
        };
    }

    /**
     * @description Substitutes bind values into SOQL for Query Editor paste.
     *              Display only; this string is never executed.
     * @param result Query result with SOQL and binds.
     * @return SOQL with literal bind values.
     */
    private static String toDisplaySoql(MapQueryResult result) {
        String display = result.soql;
        display = display.replace(':longitude', String.valueOf(result.bindLongitude));
        display = display.replace(':latitude', String.valueOf(result.bindLatitude));
        display = display.replace(':rowLimit', String.valueOf(result.bindRowLimit));
        display = display.replace(':statuses', toSoqlInList(result.bindStatuses));
        display = display.replace(':radius', String.valueOf(result.bindRadius));
        return display;
    }

    /**
     * @description Formats status values as a SOQL IN list for display.
     * @param values Status API values.
     * @return Parenthesized quoted list, or empty parentheses.
     */
    private static String toSoqlInList(List<String> values) {
        if (values == null || values.isEmpty()) {
            return '()';
        }
        List<String> quoted = new List<String>();
        for (String value : values) {
            quoted.add('\'' + String.escapeSingleQuotes(value) + '\'');
        }
        return '(' + String.join(quoted, ', ') + ')';
    }

    /**
     * @description Card field paths that are not already in the base SELECT list.
     * @param fields Parsed CMDT card fields.
     * @return Additional SOQL select paths.
     */
    private static List<String> extraSelectFields(
        List<FsSSConfigParser.CardDetailField> fields
    ) {
        Set<String> selected = new Set<String>{
            'id',
            'appointmentnumber',
            'subject',
            'status',
            'duration',
            'durationtype',
            'durationinminutes',
            'latitude',
            'longitude',
            'serviceterritoryid',
            'parentrecordid',
            'fs_ready_now__c'
        };
        List<String> extraFields = new List<String>();
        for (String path : FsSSCardFieldHelper.selectFields(fields)) {
            if (selected.contains(path.toLowerCase())) {
                continue;
            }
            selected.add(path.toLowerCase());
            extraFields.add(path);
        }
        return extraFields;
    }


    /**
     * @description Builds the candidate SOQL string with validated boolean filters.
     * @param settings Parsed CMDT.
     * @param useMiles True to use miles.
     * @return SOQL string using bind variables.
     */
    private static String buildAppointmentSoql(
        FsSSConfigParser.Settings settings,
        Boolean useMiles
    ) {
        String unitLiteral = useMiles ? '\'mi\'' : '\'km\'';
        List<String> extraFields = extraSelectFields(settings.cardDetailFields);
        String extraSelect = extraFields.isEmpty() ? '' : ', ' + String.join(extraFields, ', ');
        String soql =
            'SELECT Id, AppointmentNumber, Subject, Status, Duration, DurationType, ' +
            'DurationInMinutes, Latitude, Longitude, ServiceTerritoryId, ParentRecordId, FS_Ready_Now__c' +
            extraSelect +
            ' FROM ServiceAppointment WHERE Latitude != null AND Longitude != null ' +
            'AND DISTANCE(Address, GEOLOCATION(:latitude, :longitude), ' +
            unitLiteral +
            ') < :radius ';
        if (!settings.statusValues.isEmpty()) {
            soql += ' AND Status IN :statuses';
        }
        soql += buildBooleanFilterClause(settings.booleanFilters);
        soql +=
            ' ORDER BY DISTANCE(Address, GEOLOCATION(:latitude, :longitude), ' +
            unitLiteral +
            ') LIMIT :rowLimit';
        return soql;
    }

    /**
     * @description Appends validated boolean field filters.
     * @param filters Field API name to required value.
     * @return AND clause fragment.
     */
    private static String buildBooleanFilterClause(Map<String, Boolean> filters) {
        String clause = '';
        Map<String, Schema.SObjectField> fields = Schema.sObjectType.ServiceAppointment.fields.getMap();
        for (String fieldName : filters.keySet()) {
            Schema.SObjectField token = fields.get(fieldName);
            if (token == null || !token.getDescribe().isAccessible()) {
                continue;
            }
            if (token.getDescribe().getType() != Schema.DisplayType.BOOLEAN) {
                continue;
            }
            clause += ' AND ' + fieldName + ' = ' + String.valueOf(filters.get(fieldName));
        }
        return clause;
    }

    /**
     * @description Maps an appointment to an LWC wrapper.
     * @param appointment Candidate appointment.
     * @param settings Parsed CMDT used for card fields.
     * @return Map appointment DTO.
     */
    private static MapAppointment toMapAppointment(
        ServiceAppointment appointment,
        FsSSConfigParser.Settings settings
    ) {
        MapAppointment wrapper = new MapAppointment();
        wrapper.id = appointment.Id;
        wrapper.latitude = appointment.Latitude;
        wrapper.longitude = appointment.Longitude;
        wrapper.titleFieldValue = appointment.AppointmentNumber;
        wrapper.firstDetailFieldValue = appointment.Subject;
        wrapper.secondDetailFieldValue = appointment.Status;
        wrapper.thirdDetailFieldValue = appointment.DurationInMinutes == null
            ? null
            : String.valueOf(appointment.DurationInMinutes);
        wrapper.parentRecordId = appointment.ParentRecordId;
        wrapper.serviceTerritoryId = appointment.ServiceTerritoryId;
        wrapper.durationInMinutes = appointment.DurationInMinutes;
        wrapper.cardFields = FsSSCardFieldHelper.toCardFields(
            appointment,
            settings.cardDetailFields
        );
        return wrapper;
    }

    /**
     * @description Converts parser settings to an LWC DTO.
     * @param settings Parsed CMDT.
     * @return Config DTO.
     */
    private static ConfigDto toDto(FsSSConfigParser.Settings settings) {
        ConfigDto dto = new ConfigDto();
        dto.searchRadius = settings.searchRadius;
        dto.distanceUnit = settings.distanceUnit;
        dto.statusValues = settings.statusValues;
        dto.schedulingPolicyName = settings.schedulingPolicyName;
        dto.targetStatus = settings.targetStatus;
        dto.debugEnabled = settings.debugEnabled;
        dto.maxResults = settings.maxResults;
        dto.evaluateTerritoryRules = settings.evaluateTerritoryRules;
        dto.evaluateSkillRules = settings.evaluateSkillRules;
        dto.policyRuleTypes = FsSSPolicyMatcher.listPolicyRuleTypes(settings.schedulingPolicyName);
        dto.userName = UserInfo.getName();
        dto.bypassFslScheduleHere = settings.bypassFslScheduleHere;
        dto.skippedCardFieldTokens = settings.skippedCardFieldTokens;
        dto.cardFieldAccess = FsSSCardFieldHelper.describeAccess(
            settings.cardDetailFields,
            settings.skippedCardFieldTokens
        );
        dto.booleanFilterTokens = new List<String>();
        for (String fieldName : settings.booleanFilters.keySet()) {
            dto.booleanFilterTokens.add(
                fieldName + '=' + String.valueOf(settings.booleanFilters.get(fieldName))
            );
        }
        return dto;
    }

    /**
     * @description Confirms a field is readable on an object.
     * @param objName Object API name.
     * @param fieldName Field API name.
     * @return True when accessible.
     */
    private static Boolean isSafeField(String objName, String fieldName) {
        SObjectType objectType = Schema.getGlobalDescribe().get(objName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            return false;
        }
        SObjectField fieldToken = objectType.getDescribe().fields.getMap().get(fieldName);
        return fieldToken != null && fieldToken.getDescribe().isAccessible();
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
