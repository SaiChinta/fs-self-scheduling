/**
 * @description Parses FS_Self_Scheduling_Config__mdt into a typed settings object
 *              used by map queries and self-schedule.
 */
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.StdCyclomaticComplexity')
public with sharing class FsSSConfigParser {
    private static final String DEFAULT_DEVELOPER_NAME = 'Default';
    private static final String UNIT_MILES = 'mi';
    private static final Decimal DEFAULT_RADIUS = 10;
    private static final Integer DEFAULT_MAX_RESULTS = 200;
    private static final String DEFAULT_TARGET_STATUS = 'Dispatched';
    private static final String DEFAULT_DISTANCE_UNIT = 'km';
    private static final String DEFAULT_CARD_DETAIL_FIELDS =
        'Work Type:WorkType.Name,Duration(Mins):DurationInMinutes,Contact Name:Contact.Name,Contact Phone:Contact.Phone';
    private static final Pattern CARD_FIELD_PATH_PATTERN = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z][A-Za-z0-9_]*)?$'
    );

    /**
     * @description Typed configuration consumed by the map and claim services.
     */
    public class Settings {
        /** @description Search radius from the origin */
        public Decimal searchRadius;
        /** @description Distance unit km or mi */
        public String distanceUnit;
        /** @description Status picklist values used as query filters */
        public List<String> statusValues;
        /** @description Boolean field API name to required value */
        public Map<String, Boolean> booleanFilters;
        /** @description FSL Scheduling Policy Name */
        public String schedulingPolicyName;
        /** @description Status applied after a successful claim */
        public String targetStatus;
        /** @description Whether the debug panel may be revealed on mobile */
        public Boolean debugEnabledMobile;
        /** @description Whether the debug panel may be revealed on platform */
        public Boolean debugEnabledPlatform;
        /** @description Candidate query row cap */
        public Integer maxResults;
        /** @description When true, evaluate Match Territory and location work rules */
        public Boolean evaluateTerritoryRules;
        /** @description When true, evaluate Match Skills work rules */
        public Boolean evaluateSkillRules;
        /** @description Boolean filter tokens that were ignored */
        public List<String> skippedBooleanTokens;
        /** @description Card Label:FieldApiName pairs to show under Subject */
        public List<CardDetailField> cardDetailFields;
        /** @description Card field tokens that were ignored */
        public List<String> skippedCardFieldTokens;
        /** @description When true, claim without FSL.ScheduleService.scheduleHere */
        public Boolean bypassFslScheduleHere;
    }

    /**
     * @description One CMDT card field token after Label:FieldApiName parsing.
     */
    public class CardDetailField {
        /** @description Display label on the card */
        public String label;
        /** @description Service Appointment field path, including one-level relationships */
        public String fieldApiName;
    }

    /**
     * @description Loads the Default custom metadata record and parses it.
     * @return Parsed settings with safe defaults.
     */
    public static Settings loadDefault() {
        List<FS_Self_Scheduling_Config__mdt> records;
        try {
            records = [
                SELECT
                    Search_Radius__c,
                    Distance_Unit__c,
                    Status_Values__c,
                    Boolean_Filters__c,
                    Scheduling_Policy_Name__c,
                    Target_Status__c,
                    Debug_Enabled_Mobile__c,
                    Debug_Enabled_Platform__c,
                    Max_Results__c,
                    Evaluate_Territory_Rules__c,
                    Evaluate_Skill_Rules__c,
                    Card_Detail_Fields__c,
                    Bypass_Fsl_Schedule_Here__c
                FROM FS_Self_Scheduling_Config__mdt
                WHERE DeveloperName = :DEFAULT_DEVELOPER_NAME
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (QueryException queryError) {
            // The running user cannot read the configuration metadata; fall back
            // to packaged defaults so the map still renders.
            records = new List<FS_Self_Scheduling_Config__mdt>();
        }
        if (records.isEmpty()) {
            return applyDefaults(new Settings(), null);
        }
        return fromRecord(records[0]);
    }

    /**
     * @description Parses a custom metadata record into settings.
     * @param record Configuration custom metadata record.
     * @return Parsed settings.
     */
    public static Settings fromRecord(FS_Self_Scheduling_Config__mdt record) {
        Settings settings = new Settings();
        settings.skippedBooleanTokens = new List<String>();
        settings.skippedCardFieldTokens = new List<String>();
        settings.statusValues = splitCsv(record == null ? null : record.Status_Values__c);
        settings.booleanFilters = parseBooleanFilters(
            record == null ? null : record.Boolean_Filters__c,
            settings.skippedBooleanTokens
        );
        settings.cardDetailFields = parseCardDetailFields(
            record == null ? null : record.Card_Detail_Fields__c,
            settings.skippedCardFieldTokens
        );
        settings.schedulingPolicyName = record == null
            ? null
            : record.Scheduling_Policy_Name__c;
        return applyDefaults(settings, record);
    }

    /**
     * @description Applies numeric and text defaults.
     * @param settings Settings being populated.
     * @param record Source record, may be null.
     * @return Settings with defaults applied.
     */
    private static Settings applyDefaults(
        Settings settings,
        FS_Self_Scheduling_Config__mdt record
    ) {
        applyCollectionDefaults(settings);
        applyDistanceDefaults(settings, record);
        applyClaimDefaults(settings, record);
        applyPolicyDefaults(settings, record);
        return settings;
    }

    /**
     * @description Ensures collection members are never null.
     * @param settings Settings being populated.
     */
    private static void applyCollectionDefaults(Settings settings) {
        if (settings.skippedBooleanTokens == null) {
            settings.skippedBooleanTokens = new List<String>();
        }
        if (settings.statusValues == null) {
            settings.statusValues = new List<String>();
        }
        if (settings.booleanFilters == null) {
            settings.booleanFilters = new Map<String, Boolean>();
        }
        if (settings.skippedCardFieldTokens == null) {
            settings.skippedCardFieldTokens = new List<String>();
        }
        if (settings.cardDetailFields == null) {
            settings.cardDetailFields = new List<CardDetailField>();
        }
        if (settings.cardDetailFields.isEmpty()) {
            settings.cardDetailFields = parseCardDetailFields(
                DEFAULT_CARD_DETAIL_FIELDS,
                new List<String>()
            );
        }
    }

    /**
     * @description Applies radius, unit and row cap defaults.
     * @param settings Settings being populated.
     * @param record Source record, may be null.
     */
    private static void applyDistanceDefaults(
        Settings settings,
        FS_Self_Scheduling_Config__mdt record
    ) {
        Decimal radius = record == null ? null : record.Search_Radius__c;
        settings.searchRadius = (radius == null || radius <= 0)
            ? DEFAULT_RADIUS
            : radius;
        String unit = record == null ? null : record.Distance_Unit__c;
        settings.distanceUnit = UNIT_MILES.equalsIgnoreCase(unit)
            ? UNIT_MILES
            : DEFAULT_DISTANCE_UNIT;
        Decimal maxResults = record == null ? null : record.Max_Results__c;
        settings.maxResults = (maxResults == null || maxResults <= 0)
            ? DEFAULT_MAX_RESULTS
            : Integer.valueOf(maxResults);
    }

    /**
     * @description Applies claim status and debug defaults.
     * @param settings Settings being populated.
     * @param record Source record, may be null.
     */
    private static void applyClaimDefaults(
        Settings settings,
        FS_Self_Scheduling_Config__mdt record
    ) {
        String targetStatus = record == null ? null : record.Target_Status__c;
        settings.targetStatus = String.isBlank(targetStatus)
            ? DEFAULT_TARGET_STATUS
            : targetStatus;
        settings.debugEnabledMobile = record != null && record.Debug_Enabled_Mobile__c == true;
        settings.debugEnabledPlatform = record != null && record.Debug_Enabled_Platform__c == true;
        settings.bypassFslScheduleHere = record == null
            ? true
            : record.Bypass_Fsl_Schedule_Here__c != false;
    }

    /**
     * @description Applies work rule evaluation flags.
     * @param settings Settings being populated.
     * @param record Source record, may be null.
     */
    private static void applyPolicyDefaults(
        Settings settings,
        FS_Self_Scheduling_Config__mdt record
    ) {
        settings.evaluateTerritoryRules = isRuleFlagOn(
            record == null ? null : record.Evaluate_Territory_Rules__c
        );
        settings.evaluateSkillRules = isRuleFlagOn(
            record == null ? null : record.Evaluate_Skill_Rules__c
        );
    }

    /**
     * @description Splits a comma-separated list into trimmed tokens.
     * @param raw Comma-separated values.
     * @return List of non-blank tokens.
     */
    public static List<String> splitCsv(String raw) {
        List<String> values = new List<String>();
        if (String.isBlank(raw)) {
            return values;
        }
        for (String token : raw.split(',')) {
            String trimmed = token == null ? '' : token.trim();
            if (!String.isBlank(trimmed)) {
                values.add(trimmed);
            }
        }
        return values;
    }

    /**
     * @description Parses Label:FieldApiName tokens from commas or newlines.
     * @param raw CMDT card field text.
     * @param skippedTokens Collector for invalid tokens.
     * @return Ordered card field definitions.
     */
    public static List<CardDetailField> parseCardDetailFields(
        String raw,
        List<String> skippedTokens
    ) {
        List<CardDetailField> fields = new List<CardDetailField>();
        List<String> skipBucket = skippedTokens == null ? new List<String>() : skippedTokens;
        for (String token : splitCardFieldTokens(raw)) {
            CardDetailField parsed = parseCardDetailToken(token, skipBucket);
            if (parsed != null) {
                fields.add(parsed);
            }
        }
        return fields;
    }

    /**
     * @description Splits card field configuration on newlines and commas.
     * @param raw CMDT card field text.
     * @return Trimmed tokens.
     */
    private static List<String> splitCardFieldTokens(String raw) {
        List<String> tokens = new List<String>();
        if (String.isBlank(raw)) {
            return tokens;
        }
        String normalized = raw.replace('\r\n', '\n').replace('\r', '\n');
        for (String line : normalized.split('\n')) {
            tokens.addAll(splitCsv(line));
        }
        return tokens;
    }

    /**
     * @description Parses one Label:FieldApiName token.
     * @param token Raw token.
     * @param skippedTokens Collector for invalid tokens.
     * @return Parsed field, or null when skipped.
     */
    private static CardDetailField parseCardDetailToken(
        String token,
        List<String> skippedTokens
    ) {
        Integer separator = token.indexOf(':');
        if (separator <= 0 || separator == token.length() - 1) {
            skippedTokens.add(token);
            return null;
        }
        String label = token.substring(0, separator).trim();
        String fieldApiName = token.substring(separator + 1).trim();
        if (String.isBlank(label) || !isCardFieldPath(fieldApiName)) {
            skippedTokens.add(token);
            return null;
        }
        CardDetailField field = new CardDetailField();
        field.label = label;
        field.fieldApiName = fieldApiName;
        return field;
    }

    /**
     * @description True when the token is a direct field or one-level relationship path.
     * @param path Field API name.
     * @return True when the path syntax is safe for SOQL.
     */
    private static Boolean isCardFieldPath(String path) {
        return !String.isBlank(path) && CARD_FIELD_PATH_PATTERN.matcher(path).matches();
    }

    /**
     * @description Parses FieldApiName=true|false pairs into a map.
     * @param raw Comma-separated boolean filters.
     * @param skippedTokens Collector for invalid tokens.
     * @return Map of field API name to boolean value.
     */
    public static Map<String, Boolean> parseBooleanFilters(
        String raw,
        List<String> skippedTokens
    ) {
        Map<String, Boolean> filters = new Map<String, Boolean>();
        for (String token : splitCsv(raw)) {
            Integer separator = token.indexOf('=');
            if (separator <= 0 || separator == token.length() - 1) {
                skippedTokens.add(token);
                continue;
            }
            String fieldName = token.substring(0, separator).trim();
            String rawValue = token.substring(separator + 1).trim();
            if (String.isBlank(fieldName) || !isBooleanLiteral(rawValue)) {
                skippedTokens.add(token);
                continue;
            }
            filters.put(fieldName, Boolean.valueOf(rawValue));
        }
        return filters;
    }

    /**
     * @description True when the token is a boolean literal.
     * @param rawValue Token after the equals sign.
     * @return True for true or false ignoring case.
     */
    private static Boolean isBooleanLiteral(String rawValue) {
        return 'true'.equalsIgnoreCase(rawValue) || 'false'.equalsIgnoreCase(rawValue);
    }

    /**
     * @description Policy rule flags default on when the record or value is missing.
     * @param flagValue Checkbox from the CMDT record, may be null.
     * @return True unless the flag is explicitly false.
     */
    private static Boolean isRuleFlagOn(Boolean flagValue) {
        return flagValue != false;
    }
}
