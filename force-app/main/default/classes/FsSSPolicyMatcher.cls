/**
 * @description Evaluates scheduling-policy work rules that this package implements:
 *              matching working territories and WOLI/WO skill requirements.
 */
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.StdCyclomaticComplexity')
public with sharing class FsSSPolicyMatcher {
    private static final String SKILL_RULE_KEYWORD = 'SKILL';
    private static final String TERRITORY_RULE_KEYWORD = 'TERRITOR';
    private static final String LOCATION_RULE_KEYWORD = 'LOCATION';

    /**
     * @description Result of evaluating one appointment against the resource.
     */
    public class MatchResult {
        /** @description True when the appointment may be shown */
        public Boolean isMatch;
        /** @description Reason when the appointment is excluded */
        public String skipReason;
        /** @description Work rule types that were not evaluated */
        public List<String> skippedRuleTypes;
    }

    /**
     * @description Resource context used for matching.
     */
    public class ResourceContext {
        /** @description Service Resource Id */
        public Id resourceId;
        /** @description Working territory Ids */
        public Set<Id> territoryIds;
        /** @description Skill Id to resource skill level */
        public Map<Id, Decimal> skillLevels;
        /** @description Work rule types requested by the named policy */
        public Set<String> policyRuleTypes;
        /** @description CMDT flag for Match Territory and location rules */
        public Boolean evaluateTerritoryRules;
        /** @description CMDT flag for Match Skills rules */
        public Boolean evaluateSkillRules;
    }

    /**
     * @description Inputs required to build a resource matching context.
     */
    public class ContextRequest {
        /** @description Service Resource Id */
        public Id resourceId;
        /** @description FSL Scheduling Policy Name from CMDT */
        public String policyName;
        /** @description When false, skip territory matching */
        public Boolean evaluateTerritoryRules;
        /** @description When false, skip skill matching */
        public Boolean evaluateSkillRules;
    }

    /**
     * @description Builds matcher context for a service resource and named policy.
     * @param request Resource, policy name and rule evaluation flags.
     * @return Resource matching context.
     */
    public static ResourceContext buildContext(ContextRequest request) {
        ResourceContext context = new ResourceContext();
        context.resourceId = request.resourceId;
        context.territoryIds = new Set<Id>();
        context.skillLevels = new Map<Id, Decimal>();
        context.policyRuleTypes = new Set<String>();
        context.evaluateTerritoryRules = request.evaluateTerritoryRules != false;
        context.evaluateSkillRules = request.evaluateSkillRules != false;
        if (request.resourceId == null) {
            return context;
        }
        if (context.evaluateTerritoryRules) {
            loadTerritories(context);
        }
        if (context.evaluateSkillRules) {
            loadSkills(context);
        }
        loadPolicyRuleTypes(context, request.policyName);
        return context;
    }

    /**
     * @description Returns work-rule type tokens from the named scheduling policy.
     * @param policyName FSL Scheduling Policy Name from CMDT.
     * @return Uppercase work rule types, empty when the policy is missing.
     */
    public static List<String> listPolicyRuleTypes(String policyName) {
        ResourceContext context = new ResourceContext();
        context.policyRuleTypes = new Set<String>();
        loadPolicyRuleTypes(context, policyName);
        return new List<String>(context.policyRuleTypes);
    }

    /**
     * @description Loads Skill Requirement rows keyed by RelatedRecordId.
     * @param relatedRecordIds Parent Work Order or Work Order Line Item Ids.
     * @return Requirements grouped by related record; empty when none are readable.
     */
    public static Map<Id, List<SkillRequirement>> loadSkillRequirements(
        Set<Id> relatedRecordIds
    ) {
        Map<Id, List<SkillRequirement>> requirements = new Map<Id, List<SkillRequirement>>();
        if (relatedRecordIds == null || relatedRecordIds.isEmpty()) {
            return requirements;
        }
        if (!Schema.sObjectType.SkillRequirement.isAccessible()) {
            return requirements;
        }
        for (SkillRequirement requirement : [
            SELECT SkillId, SkillLevel, RelatedRecordId
            FROM SkillRequirement
            WHERE RelatedRecordId IN :relatedRecordIds
            WITH USER_MODE
        ]) {
            if (!requirements.containsKey(requirement.RelatedRecordId)) {
                requirements.put(
                    requirement.RelatedRecordId,
                    new List<SkillRequirement>()
                );
            }
            requirements.get(requirement.RelatedRecordId).add(requirement);
        }
        return requirements;
    }

    /**
     * @description Evaluates one appointment against the resource context.
     * @param appointment Candidate Service Appointment.
     * @param skillRequirements Skill requirements keyed by related record Id.
     * @param context Resource matching context.
     * @return Match result including skip reason.
     */
    public static MatchResult evaluate(
        ServiceAppointment appointment,
        Map<Id, List<SkillRequirement>> skillRequirements,
        ResourceContext context
    ) {
        MatchResult result = new MatchResult();
        result.isMatch = true;
        result.skippedRuleTypes = new List<String>();
        if (context == null) {
            result.isMatch = false;
            result.skipReason = 'Missing resource context';
            return result;
        }
        if (shouldCheckTerritory(context) && !matchesTerritory(appointment, context)) {
            result.isMatch = false;
            result.skipReason = 'Territory mismatch';
            return result;
        }
        if (shouldCheckSkills(context) && !matchesSkills(appointment, skillRequirements, context)) {
            result.isMatch = false;
            result.skipReason = 'Skill mismatch';
            return result;
        }
        collectSkippedRules(context, result);
        return result;
    }

    /**
     * @description True when territory matching should run for this context.
     * @param context Resource matching context.
     * @return True when the CMDT flag is on and the policy asks for territory or has no rules.
     */
    private static Boolean shouldCheckTerritory(ResourceContext context) {
        if (context.evaluateTerritoryRules == false) {
            return false;
        }
        return shouldEvaluate(context, TERRITORY_RULE_KEYWORD) ||
            shouldEvaluate(context, LOCATION_RULE_KEYWORD) ||
            context.policyRuleTypes == null ||
            context.policyRuleTypes.isEmpty();
    }

    /**
     * @description True when skill matching should run for this context.
     * @param context Resource matching context.
     * @return True when the CMDT flag is on and the policy asks for skills or has no rules.
     */
    private static Boolean shouldCheckSkills(ResourceContext context) {
        if (context.evaluateSkillRules == false) {
            return false;
        }
        return shouldEvaluate(context, SKILL_RULE_KEYWORD) ||
            context.policyRuleTypes == null ||
            context.policyRuleTypes.isEmpty();
    }

    /**
     * @description True when the policy asked for a rule family, or no policy rules loaded.
     * @param context Resource context.
     * @param token Uppercase fragment of a work rule type.
     * @return True when that family should run.
     */
    private static Boolean shouldEvaluate(ResourceContext context, String token) {
        if (context.policyRuleTypes == null || context.policyRuleTypes.isEmpty()) {
            return false;
        }
        for (String ruleType : context.policyRuleTypes) {
            if (ruleType != null && ruleType.contains(token)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Records unimplemented policy rule types for diagnostics.
     * @param context Resource context.
     * @param result Match result being populated.
     */
    private static void collectSkippedRules(ResourceContext context, MatchResult result) {
        if (context.policyRuleTypes == null) {
            return;
        }
        for (String ruleType : context.policyRuleTypes) {
            Boolean implemented = ruleType != null &&
                (ruleType.contains(SKILL_RULE_KEYWORD) ||
                 ruleType.contains(TERRITORY_RULE_KEYWORD) ||
                 ruleType.contains(LOCATION_RULE_KEYWORD));
            if (!implemented) {
                result.skippedRuleTypes.add(ruleType);
            }
        }
    }

    /**
     * @description True when the appointment territory is a working territory of the resource.
     * @param appointment Candidate appointment.
     * @param context Resource context.
     * @return True when territory matches.
     */
    private static Boolean matchesTerritory(
        ServiceAppointment appointment,
        ResourceContext context
    ) {
        if (appointment.ServiceTerritoryId == null) {
            return false;
        }
        return context.territoryIds.contains(appointment.ServiceTerritoryId);
    }

    /**
     * @description True when the resource has every required skill at the required level.
     * @param appointment Candidate appointment.
     * @param skillRequirements Requirements keyed by related record Id.
     * @param context Resource context.
     * @return True when skills match or none are required.
     */
    private static Boolean matchesSkills(
        ServiceAppointment appointment,
        Map<Id, List<SkillRequirement>> skillRequirements,
        ResourceContext context
    ) {
        List<SkillRequirement> requirements = requirementsFor(
            appointment,
            skillRequirements
        );
        for (SkillRequirement requirement : requirements) {
            if (!hasSkill(requirement, context)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @description Collects the skill requirements that apply to an appointment.
     * @param appointment Candidate appointment.
     * @param skillRequirements Requirements keyed by related record Id.
     * @return Requirements for the appointment parent, never null.
     */
    private static List<SkillRequirement> requirementsFor(
        ServiceAppointment appointment,
        Map<Id, List<SkillRequirement>> skillRequirements
    ) {
        List<SkillRequirement> requirements = new List<SkillRequirement>();
        if (appointment.ParentRecordId == null || skillRequirements == null) {
            return requirements;
        }
        List<SkillRequirement> related = skillRequirements.get(
            appointment.ParentRecordId
        );
        if (related != null) {
            requirements.addAll(related);
        }
        return requirements;
    }

    /**
     * @description True when the resource holds one requirement at the needed level.
     * @param requirement Skill requirement under evaluation.
     * @param context Resource context.
     * @return True when the requirement is satisfied or carries no skill.
     */
    private static Boolean hasSkill(
        SkillRequirement requirement,
        ResourceContext context
    ) {
        if (requirement.SkillId == null) {
            return true;
        }
        if (!context.skillLevels.containsKey(requirement.SkillId)) {
            return false;
        }
        Decimal requiredLevel = requirement.SkillLevel;
        return requiredLevel == null ||
            context.skillLevels.get(requirement.SkillId) >= requiredLevel;
    }

    /**
     * @description Loads active service territory memberships for the resource.
     * @param context Resource context being populated.
     */
    private static void loadTerritories(ResourceContext context) {
        Datetime now = System.now();
        for (ServiceTerritoryMember member : [
            SELECT ServiceTerritoryId, EffectiveStartDate, EffectiveEndDate
            FROM ServiceTerritoryMember
            WHERE ServiceResourceId = :context.resourceId
            WITH USER_MODE
        ]) {
            if (member.ServiceTerritoryId == null) {
                continue;
            }
            if (member.EffectiveStartDate != null && member.EffectiveStartDate > now) {
                continue;
            }
            if (member.EffectiveEndDate != null && member.EffectiveEndDate < now) {
                continue;
            }
            context.territoryIds.add(member.ServiceTerritoryId);
        }
    }

    /**
     * @description Loads effective resource skills.
     * @param context Resource context being populated.
     */
    private static void loadSkills(ResourceContext context) {
        Date today = Date.today();
        for (ServiceResourceSkill resourceSkill : [
            SELECT SkillId, SkillLevel, EffectiveStartDate, EffectiveEndDate
            FROM ServiceResourceSkill
            WHERE ServiceResourceId = :context.resourceId
            WITH USER_MODE
        ]) {
            if (resourceSkill.SkillId == null) {
                continue;
            }
            if (resourceSkill.EffectiveStartDate != null && resourceSkill.EffectiveStartDate > today) {
                continue;
            }
            if (resourceSkill.EffectiveEndDate != null && resourceSkill.EffectiveEndDate < today) {
                continue;
            }
            context.skillLevels.put(
                resourceSkill.SkillId,
                resourceSkill.SkillLevel == null ? 0 : resourceSkill.SkillLevel
            );
        }
    }

    /**
     * @description Loads work rule types from the named FSL scheduling policy.
     * @param context Resource context being populated.
     * @param policyName Policy Name from CMDT.
     */
    private static void loadPolicyRuleTypes(ResourceContext context, String policyName) {
        if (String.isBlank(policyName)) {
            return;
        }
        if (!Schema.sObjectType.FSL__Scheduling_Policy__c.isAccessible()) {
            return;
        }
        List<FSL__Scheduling_Policy__c> policies = [
            SELECT Id
            FROM FSL__Scheduling_Policy__c
            WHERE Name = :policyName
            WITH USER_MODE
            LIMIT 1
        ];
        if (policies.isEmpty()) {
            return;
        }
        if (!Schema.sObjectType.FSL__Scheduling_Policy_Work_Rule__c.isAccessible()) {
            return;
        }
        for (FSL__Scheduling_Policy_Work_Rule__c junction : [
            SELECT FSL__Work_Rule__r.Name, FSL__Work_Rule__r.RecordType.DeveloperName
            FROM FSL__Scheduling_Policy_Work_Rule__c
            WHERE FSL__Scheduling_Policy__c = :policies[0].Id
            WITH USER_MODE
        ]) {
            String developerName = junction.FSL__Work_Rule__r.RecordType.DeveloperName;
            String label = junction.FSL__Work_Rule__r.Name;
            String token = String.isBlank(developerName) ? label : developerName;
            if (!String.isBlank(token)) {
                context.policyRuleTypes.add(token.toUpperCase());
            }
        }
    }
}
