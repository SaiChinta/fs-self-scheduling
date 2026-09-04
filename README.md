# Field Service Self Scheduling

Apex-driven map for technicians to find nearby Ready Now Service Appointments and claim one. There is no GraphQL candidate query; the map loads appointments from Apex.

After deploying `force-app`, follow **POST_DEPLOY.md** for permission sets, the User Access Policy, public group, sharing, layouts, CMDT, briefcase assignment, Lightning pages, and the Field Service Mobile action.

## Surfaces

- Desktop Lightning: `fsSelfScheduleRecordPage` on the Service Appointment record page (two-column desktop flexipage). Height is 70vh.
- Field Service Mobile: `mobileMapLayersMain` as a Screen Record Action (and tab / global action). Full height with a 480px minimum.
- Form factors: `Large` (desktop) and `Medium` (tablet) share desktop map controls. `Small` (phone) uses the bottom list sheet, pinch zoom, and five-tap debug.
- Open Record: on Large/Medium, the appointment opens as a Lightning console workspace tab when the app is a console, otherwise as a Lightning record page. On Small, it uses the Field Service Mobile deep link.

## Access

Ready Now appointments are shared to public group **FS Field Resources Team**. User Access Policy **FS_FieldResources_Team_Membership** (Active, Create and Update) grants that group membership to users who have permission set **FS SelfScheduling Access**. Confirm the policy is Active after deploy and apply it to existing users if they already had the permission set. See **POST_DEPLOY.md**.

## Map query versus claim

The map runs a radius DISTANCE query, then filters rows with territory and skill matching. Self-schedule (claim) does not repeat those policy checks. Claim verifies Ready Now and configured statuses. If the appointment is already assigned to the claiming resource, claim updates scheduled start/end and sets Dispatched. If it is assigned to a different resource, claim is rejected.

## Policy matching

After the radius SOQL, Apex resolves a Service Resource: the explicit `resourceId` (debug) or `ServiceResource.RelatedRecordId` equal to the running user. `FsSSPolicyMatcher.evaluate` then applies two families, gated by CMDT `Evaluate_Territory_Rules__c` and `Evaluate_Skill_Rules__c`:

- Territory / location: appointment `ServiceTerritoryId` must be in the resource's effective Service Territory Member set. Blank territory fails closed.
- Skills: `SkillRequirement` on the appointment parent versus the resource's `ServiceResourceSkill` levels.

`loadPolicyRuleTypes` reads work-rule RecordType developer names from the named FSL scheduling policy (`Scheduling_Policy_Name__c`, Default = Self Scheduling).

### Policy rule types (debug)

Diagnostic dump of every work-rule type on that policy. It is what the policy asked for, not what this package executed.

### Unimplemented rules (debug)

Types whose token does not contain `SKILL`, `TERRITOR`, or `LOCATION`. Diagnostic only; they never hide a pin. The list is collected only from appointments that match, so the debug row can show `(none)` when every radius candidate was skipped (for example Skipped skill = 2).

Substring mapping is coarse. `FIELD_WORKING_LOCATIONS` is treated as location/territory because it contains `LOCATION`. That check is STM membership versus appointment territory, not Field Working Locations polygons.

### Not evaluated

- `TIME_RULE_SERVICE`: operating hours, availability, and shifts
- `GAP_RULE_SERVICE`: travel gap between jobs

Claim pins the appointment at `System.now()` with no availability check.

## Distance unit

Default CMDT `Distance_Unit__c` is `km`. Keep it that way; do not set Default to `mi`.

`FsSSConfigParser` uses miles only when the CMDT value is `mi`; otherwise the unit is km. Apex DISTANCE SOQL uses the km unit literal unless that miles flag is on. The LWC haversine uses Earth radius 6371 km unless the unit is `mi`. Card distance labels follow the same parsed unit.

## Apex size

`FsSSMapLayersService` is large (above the usual NCSS type guideline of about 500). Complexity suppressions exist on the map service, policy matcher, and config parser. Do not split that class unless a deploy or PMD run requires it.
