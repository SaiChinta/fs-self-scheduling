/**
 * @description Validates CMDT card field paths and reads values from queried
 *              Service Appointment rows for the map card.
 */
public with sharing class FsSSCardFieldHelper {
    private static final String EMPTY_DISPLAY = '—';
    private static final Pattern FIELD_PATH_PATTERN = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z][A-Za-z0-9_]*)?$'
    );

    /**
     * @description Select-list fragments for validated card field paths.
     * @param fields Parsed CMDT card fields.
     * @return Distinct SOQL select paths.
     */
    public static List<String> selectFields(List<FsSSConfigParser.CardDetailField> fields) {
        List<String> selectPaths = new List<String>();
        Set<String> seen = new Set<String>();
        if (fields == null) {
            return selectPaths;
        }
        for (FsSSConfigParser.CardDetailField field : fields) {
            if (field == null || String.isBlank(field.fieldApiName)) {
                continue;
            }
            String path = field.fieldApiName.trim();
            String key = path.toLowerCase();
            if (seen.contains(key) || !isSafePath(path)) {
                continue;
            }
            seen.add(key);
            selectPaths.add(path);
        }
        return selectPaths;
    }

    /**
     * @description Builds label/value pairs for the Service Appointment card.
     * @param appointment Queried appointment row.
     * @param fields Parsed CMDT card fields.
     * @return Card field DTOs in CMDT order.
     */
    public static List<FsSSMapLayersService.CardField> toCardFields(
        ServiceAppointment appointment,
        List<FsSSConfigParser.CardDetailField> fields
    ) {
        List<FsSSMapLayersService.CardField> cardFields = new List<FsSSMapLayersService.CardField>();
        if (fields == null) {
            return cardFields;
        }
        for (FsSSConfigParser.CardDetailField field : fields) {
            if (field == null || String.isBlank(field.label) || String.isBlank(field.fieldApiName)) {
                continue;
            }
            if (!isSafePath(field.fieldApiName)) {
                continue;
            }
            FsSSMapLayersService.CardField wrapper = new FsSSMapLayersService.CardField();
            wrapper.label = field.label;
            wrapper.fieldApiName = field.fieldApiName;
            wrapper.value = displayValue(readValue(appointment, field.fieldApiName));
            wrapper.isPhone = isPhonePath(field.fieldApiName);
            cardFields.add(wrapper);
        }
        return cardFields;
    }

    /**
     * @description True when the path is a readable Service Appointment field
     *              or a one-level relationship field.
     * @param path Field API name or Relationship.Field.
     * @return True when the path may be selected.
     */
    public static Boolean isSafePath(String path) {
        if (String.isBlank(path) || !FIELD_PATH_PATTERN.matcher(path).matches()) {
            return false;
        }
        List<String> parts = path.split('\\.');
        Schema.DescribeSObjectResult appointmentDescribe = ServiceAppointment.SObjectType.getDescribe();
        if (parts.size() == 1) {
            return isAccessibleField(appointmentDescribe, parts[0]);
        }
        return isAccessibleRelationshipField(appointmentDescribe, parts[0], parts[1]);
    }

    /**
     * @description True when a direct field on the object is readable.
     * @param objectDescribe Object describe.
     * @param fieldName Field API name.
     * @return True when accessible.
     */
    private static Boolean isAccessibleField(
        Schema.DescribeSObjectResult objectDescribe,
        String fieldName
    ) {
        if (objectDescribe == null || !objectDescribe.isAccessible()) {
            return false;
        }
        Schema.SObjectField fieldToken = objectDescribe.fields.getMap().get(fieldName);
        return fieldToken != null && fieldToken.getDescribe().isAccessible();
    }

    /**
     * @description True when a one-level relationship field is readable.
     * @param appointmentDescribe Service Appointment describe.
     * @param relationshipName Relationship name.
     * @param relatedFieldName Field API name on the related object.
     * @return True when accessible.
     */
    private static Boolean isAccessibleRelationshipField(
        Schema.DescribeSObjectResult appointmentDescribe,
        String relationshipName,
        String relatedFieldName
    ) {
        Schema.SObjectField relationshipField = findRelationshipField(
            appointmentDescribe,
            relationshipName
        );
        if (relationshipField == null) {
            return false;
        }
        Schema.DescribeFieldResult relationshipDescribe = relationshipField.getDescribe();
        if (!relationshipDescribe.isAccessible()) {
            return false;
        }
        List<Schema.SObjectType> parents = relationshipDescribe.getReferenceTo();
        if (parents == null || parents.isEmpty()) {
            return false;
        }
        return isAccessibleField(parents[0].getDescribe(), relatedFieldName);
    }

    /**
     * @description Finds the lookup/master-detail field for a relationship name.
     * @param objectDescribe Object describe.
     * @param relationshipName Relationship name from SOQL.
     * @return Matching field token, or null.
     */
    private static Schema.SObjectField findRelationshipField(
        Schema.DescribeSObjectResult objectDescribe,
        String relationshipName
    ) {
        if (objectDescribe == null || String.isBlank(relationshipName)) {
            return null;
        }
        for (Schema.SObjectField fieldToken : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (relationshipName.equalsIgnoreCase(fieldDescribe.getRelationshipName())) {
                return fieldToken;
            }
        }
        return null;
    }

    /**
     * @description Reads a direct or one-level relationship value.
     * @param record Queried appointment.
     * @param path Field API name or Relationship.Field.
     * @return Raw value, or null.
     */
    private static Object readValue(ServiceAppointment record, String path) {
        if (record == null || String.isBlank(path)) {
            return null;
        }
        List<String> parts = path.split('\\.');
        SObject current = record;
        for (Integer index = 0; index < parts.size() - 1; index++) {
            current = current.getSObject(parts[index]);
            if (current == null) {
                return null;
            }
        }
        return current.get(parts[parts.size() - 1]);
    }

    /**
     * @description Converts a raw field value into card display text.
     * @param raw Queried value.
     * @return Display text, or an em dash when blank.
     */
    private static String displayValue(Object raw) {
        if (raw == null) {
            return EMPTY_DISPLAY;
        }
        String text = String.valueOf(raw);
        return String.isBlank(text) ? EMPTY_DISPLAY : text;
    }

    /**
     * @description Reports CMDT card field access for the running user.
     * @param fields Parsed CMDT card fields.
     * @param skippedTokens Tokens the parser rejected.
     * @return Access rows in CMDT order, then skipped tokens.
     */
    public static List<FsSSMapLayersService.FieldAccessResult> describeAccess(
        List<FsSSConfigParser.CardDetailField> fields,
        List<String> skippedTokens
    ) {
        List<FsSSMapLayersService.FieldAccessResult> results = new List<FsSSMapLayersService.FieldAccessResult>();
        if (fields != null) {
            for (FsSSConfigParser.CardDetailField field : fields) {
                if (field == null || String.isBlank(field.fieldApiName)) {
                    continue;
                }
                FsSSMapLayersService.FieldAccessResult row = new FsSSMapLayersService.FieldAccessResult();
                row.label = field.label;
                row.fieldApiName = field.fieldApiName;
                Boolean safe = isSafePath(field.fieldApiName);
                row.accessible = safe;
                row.reason = safe
                    ? 'Accessible'
                    : 'Field path is not readable for the running user';
                results.add(row);
            }
        }
        if (skippedTokens != null) {
            for (String token : skippedTokens) {
                FsSSMapLayersService.FieldAccessResult row = new FsSSMapLayersService.FieldAccessResult();
                row.label = token;
                row.fieldApiName = token;
                row.accessible = false;
                row.reason = 'Parser skipped this token';
                results.add(row);
            }
        }
        return results;
    }

    /**
     * @description True when the path is a phone field on Service Appointment
     *              or a related record.
     * @param path Field API name or Relationship.Field.
     * @return True when the describe type is PHONE or the name ends with Phone.
     */
    public static Boolean isPhonePath(String path) {
        if (String.isBlank(path) || !FIELD_PATH_PATTERN.matcher(path).matches()) {
            return false;
        }
        if (path.toLowerCase().endsWith('phone')) {
            return true;
        }
        List<String> parts = path.split('\\.');
        Schema.DescribeSObjectResult appointmentDescribe = ServiceAppointment.SObjectType.getDescribe();
        Schema.DescribeSObjectResult objectDescribe = appointmentDescribe;
        if (parts.size() == 2) {
            Schema.SObjectField relationshipField = findRelationshipField(
                appointmentDescribe,
                parts[0]
            );
            if (relationshipField == null) {
                return false;
            }
            List<Schema.SObjectType> parents = relationshipField.getDescribe().getReferenceTo();
            if (parents == null || parents.isEmpty()) {
                return false;
            }
            objectDescribe = parents[0].getDescribe();
        }
        Schema.SObjectField fieldToken = objectDescribe.fields.getMap().get(parts[parts.size() - 1]);
        if (fieldToken == null) {
            return false;
        }
        return fieldToken.getDescribe().getType() == Schema.DisplayType.PHONE;
    }

}
