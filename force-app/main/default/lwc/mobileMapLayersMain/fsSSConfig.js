const DEFAULT_RADIUS = 10;
const DEFAULT_MAX_RESULTS = 200;
const DEFAULT_UNIT = "km";
const DEFAULT_TARGET_STATUS = "Dispatched";

export function parseCsv(raw) {
  if (!raw) {
    return [];
  }
  return String(raw)
    .split(",")
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
}

export function isRuleFlagOn(value) {
  return value !== false && value !== "false";
}

export function parseBooleanFilters(raw) {
  const filters = {};
  const skipped = [];
  parseCsv(raw).forEach((token) => {
    const separator = token.indexOf("=");
    if (separator <= 0 || separator === token.length - 1) {
      skipped.push(token);
      return;
    }
    const fieldName = token.substring(0, separator).trim();
    const rawValue = token
      .substring(separator + 1)
      .trim()
      .toLowerCase();
    if (rawValue !== "true" && rawValue !== "false") {
      skipped.push(token);
      return;
    }
    filters[fieldName] = rawValue === "true";
  });
  return { filters, skipped };
}

export function normalizeConfig(source) {
  const booleanRaw = Array.isArray(source?.booleanFilterTokens)
    ? source.booleanFilterTokens.join(",")
    : source?.Boolean_Filters__c || source?.booleanFiltersRaw;
  const parsedBooleans = parseBooleanFilters(booleanRaw);
  const unit = source?.distanceUnit || source?.Distance_Unit__c;
  const radius = Number(source?.searchRadius || source?.Search_Radius__c);
  const maxResults = Number(source?.maxResults || source?.Max_Results__c);
  return {
    searchRadius: radius > 0 ? radius : DEFAULT_RADIUS,
    distanceUnit: unit === "mi" ? "mi" : DEFAULT_UNIT,
    statusValues: Array.isArray(source?.statusValues)
      ? source.statusValues
      : parseCsv(source?.Status_Values__c),
    booleanFilters: parsedBooleans.filters,
    skippedBooleanTokens: parsedBooleans.skipped,
    schedulingPolicyName:
      source?.schedulingPolicyName || source?.Scheduling_Policy_Name__c || "",
    targetStatus:
      source?.targetStatus || source?.Target_Status__c || DEFAULT_TARGET_STATUS,
    debugEnabled: false,
    debugEnabledMobile:
      source?.debugEnabledMobile === true ||
      source?.Debug_Enabled_Mobile__c === true,
    debugEnabledPlatform:
      source?.debugEnabledPlatform === true ||
      source?.Debug_Enabled_Platform__c === true,
    maxResults: maxResults > 0 ? maxResults : DEFAULT_MAX_RESULTS,
    evaluateTerritoryRules: isRuleFlagOn(
      source?.evaluateTerritoryRules ?? source?.Evaluate_Territory_Rules__c
    ),
    evaluateSkillRules: isRuleFlagOn(
      source?.evaluateSkillRules ?? source?.Evaluate_Skill_Rules__c
    ),
    policyRuleTypes: Array.isArray(source?.policyRuleTypes)
      ? source.policyRuleTypes
      : [],
    userName: source?.userName || "",
    bypassFslScheduleHere: source?.bypassFslScheduleHere === true,
    skippedCardFieldTokens: Array.isArray(source?.skippedCardFieldTokens)
      ? source.skippedCardFieldTokens
      : [],
    cardFieldAccess: Array.isArray(source?.cardFieldAccess)
      ? source.cardFieldAccess
      : []
  };
}
