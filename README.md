# Field Service Self Scheduling

Technicians find nearby Ready Now Service Appointments on a map and claim one. The map loads appointments from Apex. There is no GraphQL candidate query.

This page has two specifications:

- [Functional specification](#functional-specification) is for dispatchers, technicians, and business administrators.
- [Technical specification](#technical-specification) is for developers and the people who deploy or support the package.

Install steps that Salesforce metadata cannot finish (permission-set assignment, briefcase, mobile publisher layout, page activation) are in **POST_DEPLOY.md**.

## Functional specification

### What this is for

A technician who is already in the field can see work that is ready to start, close to where they are, and suitable for their territory and skills. They choose one appointment and take it. The appointment is then scheduled to start now and moves to the configured status, usually **Dispatched**.

Dispatch still marks which work is eligible. The technician does not build the schedule. They claim a job the business has already flagged as Ready Now.

### Who uses it

| Person | What they do |
|---|---|
| Technician | Opens the map on a phone or in the browser, reviews nearby jobs, and claims one. |
| Dispatcher | Sets **Ready Now** on the work that technicians may claim, and keeps status, territory, skills, and location correct. |
| Administrator | Assigns access, maintains the Default configuration record, and decides whether debug is available on mobile, on the platform, or on both. |

A technician needs an active Service Resource linked to their user, membership in a territory that matches the work, and the skills that work requires when skill matching is turned on.

### Where they open it

- **Phone (Field Service Mobile).** The Self Scheduling action opens a full-screen map. A list sheet sits at the bottom. Pulling it up leaves a band of map visible.
- **Desktop or tablet browser.** The same map opens from the **FS Self Scheduling** app tab, or from the Self Scheduling component on a Service Appointment record page. Desktop and tablet share the larger map controls.

**Open Record** on a phone opens the appointment in Field Service Mobile. On a desktop or tablet it opens the appointment as a console tab when the app is a console, otherwise as a normal Lightning record page.

### What the technician sees

- Their name and the location used to search.
- A map pin and a list row for each matching appointment.
- On each card: the appointment identity, distance, and the extra fields configured for the card (by default work type, duration, contact name, and contact phone).
- **Self Schedule** on the map card and in the list actions.
- A confirmation: appointment, distance, and that the job will start now and finish after its duration. **No** cancels. **Yes** claims the job.
- A success message when the claim completes. A toast shows the error text when it does not.

The search starts from the device location when the browser or the mobile app can provide it. If that is not available yet, the map uses the Service Resource's last known location. A support user can type a latitude and longitude in the debug panel and that location is used instead.

### Which jobs appear

A job appears only when all of the following are true:

1. **Ready Now** is checked on the Service Appointment.
2. The status is one of the configured values. The Default record uses **None** and **Scheduled**.
3. The appointment has a location inside the search radius. The Default radius is 10 kilometres.
4. The technician's territory matches the appointment territory, when territory matching is on.
5. The technician's skills meet the skill requirements on the parent work, when skill matching is on.
6. The technician can see the record. Ready Now Service Appointments are shared with edit access to the **FS Field Resources Team** group. Users in that group are the people who have the **FS SelfScheduling Access** permission set.

The map does not hide a job only because someone is already assigned to it. Claim decides what to do with an existing assignment.

These checks do **not** look at operating hours, shifts, or travel time between jobs. A pin means the job is Ready Now, nearby, and matches territory and skills. It does not mean the technician is free.

Work Orders with **Ready Now** checked are shared read-only to the same group so the team can see the parent work. The map itself lists Service Appointments, not Work Orders. Work Order Line Items also have **Ready Now**, used when the mobile briefcase primes line items and their skill requirements.

### Claiming a job

The technician confirms **Yes**. The product then:

1. Checks that the appointment is still Ready Now and still in an allowed status.
2. Schedules it to start now. The end time is the appointment duration, or 60 minutes when duration is blank.
3. Makes the logged-in technician the assigned resource.
4. Sets the status to the configured target, usually **Dispatched**.

What happens to an existing assignment depends on who owns it:

| Current assignment | What the technician gets |
|---|---|
| Nobody assigned | A new assignment for this technician, start and end set to now, status updated. |
| Already this technician | Start and end move to now. The existing assignment stays. Status is updated. |
| A different technician | That assignment is removed. This technician is assigned. Start and end are set to now. Status is updated. |

The Default configuration does this without calling the Field Service scheduling engine. Turn **Bypass FSL Schedule Here** off only when the org should ask `scheduleHere` to pin the job. That path still runs for an unassigned job, a job already assigned to this technician, and a job assigned to someone else, and it still sets the target status afterward. Enhanced Scheduling and Optimization is required for that engine path.

Territory and skills are checked when the map is loaded. They are not checked again at the moment of claim.

### Debug, for support

Debug is off for an audience until an administrator turns it on.

| Setting | Who it affects |
|---|---|
| Debug Enabled Mobile | Phones. |
| Debug Enabled Platform | Desktop and tablet browsers. |

The Default record turns both on. Five taps within two seconds show or hide the debug panel. On a larger screen a **Debug** chip does the same. The panel can override the Service Resource and the search location, and it lists how the last search ran. When a claim fails and debug is enabled for that device, the error is also shown at the bottom of the appointment list, including the message, the appointment, and the resource.

### Settings a business administrator changes

Setup → Custom Metadata Types → **FS Self Scheduling Config** → **Default**.

| Setting | Default | Business meaning |
|---|---|---|
| Search Radius | 10 | How far from the technician to look. |
| Distance Unit | km | Keep kilometres. |
| Status Values | None, Scheduled | Statuses that may appear and may be claimed. |
| Boolean Filters | Ready Now equals true | Extra true/false filters on the map query. This does not define sharing. |
| Scheduling Policy Name | Self Scheduling | Name of the Field Service scheduling policy whose territory and skill rules the map copies. |
| Target Status | Dispatched | Status after a successful claim. |
| Debug Enabled Mobile | true | Debug on phones. |
| Debug Enabled Platform | true | Debug on desktop and tablet. |
| Max Results | 200 | Most appointments the search will consider. |
| Evaluate Territory Rules | true | Hide jobs outside the technician's territories. |
| Evaluate Skill Rules | true | Hide jobs whose required skills the technician does not meet. |
| Card Detail Fields | Work type, duration, contact name, contact phone | Extra lines on each card, written as Label:Field. |
| Bypass FSL Schedule Here | true | Claim sets the time and the assignment directly. Turn off to use the Field Service scheduling engine. |

## Technical specification

### Package layout

| Area | Main types |
|---|---|
| Map UI | `mobileMapLayersMain`, `mobileMap`, `locationsList`, `confirmModal`, `objectIcon`, `fsSelfScheduleDebug` |
| Record-page host | `fsSelfScheduleRecordPage` (desktop height 70vh). Phone action and tab host `mobileMapLayersMain` at full height with a 480px minimum. |
| Apex | `FsSSMapLayersService` (AuraEnabled facade), `FsSSConfigParser`, `FsSSPolicyMatcher`, `FsSSCardFieldHelper`, `FsSSSelfScheduler` |
| Tests | `FsSSMapLayersServiceTest` |
| Config | `FS_Self_Scheduling_Config__mdt`, record `FS_Self_Scheduling_Config.Default` |
| Access | Permission set `FS_SelfScheduling_Access`, group `FS_FieldResources_Team`, user access policy `FS_FieldResources_Team_Membership` |
| Sharing | `Ready_Now_Appointments_Mobile` (Service Appointment, Edit), `Ready_Now_Work_Orders` (Work Order, Read) |
| Mobile prime | High-volume briefcase `FS_SelfScheduling` |
| App | Lightning app and tab `FS_SelfScheduling`, quick action `FS_SelfScheduling` |

Form factor comes from `@salesforce/client/formFactor`. `Large` and `Medium` are platform (`isDesktopForm`). `Small` is mobile.

### Data model

| Field | Object | Role |
|---|---|---|
| `FS_Ready_Now__c` | Service Appointment | Map filter, claim check, and criteria sharing. Checkbox, Confidential. |
| `FS_Ready_Now__c` | Work Order | Read sharing to the field-resources group. The map query does not list Work Orders. |
| `FS_Ready_Now__c` | Work Order Line Item | Briefcase priming and skill-requirement context. |
| `FS_Work_Order_Line_Item__c` | Service Appointment | Briefcase relationship from the appointment to its line item. |

`FS_SelfScheduling_Access` grants read and edit on all three Ready Now fields. Work Order object edit is on so the Work Order field permission is valid. Assigned Resource create, edit, and delete are on so claim can insert a first assignment and replace a different resource. Service Appointment update is on.

### Access and sharing

User access policy `FS_FieldResources_Team_Membership` is Active, on create and update, and adds a user to `FS_FieldResources_Team` when they have `FS_SelfScheduling_Access`.

| Rule | Criteria | Group | Access |
|---|---|---|---|
| `Ready_Now_Appointments_Mobile` | `ServiceAppointment.FS_Ready_Now__c` equals true | `FS_FieldResources_Team` | Edit, records owned by all |
| `Ready_Now_Work_Orders` | `WorkOrder.FS_Ready_Now__c` equals true | `FS_FieldResources_Team` | Read, records owned by all |

Sharing is not driven by the CMDT boolean-filter string. That string only adds filters to the map SOQL.

The briefcase primes Ready Now Service Appointments, the related Work Order Line Item (`FS_Work_Order_Line_Item__c`), Skill Requirements on that line item, the running user's Service Resource with territory memberships and skills, territories, and the config metadata. It is not attached to a mobile configuration until that is done in Setup. See **POST_DEPLOY.md**.

### Origin

`mobileMapLayersMain` starts from a fixed Auckland coordinate so the map has an origin before a better one arrives.

1. A debug latitude and longitude, once applied, replaces the origin and later GPS fixes are ignored.
2. Otherwise `navigator.geolocation` sets the origin to the device and marks the source `device`.
3. The Service Resource last-known location is applied only when the source is not already `device` or `debug`.

`getMapAppointments` receives that latitude, longitude, and the Service Resource Id.

### Map query

`FsSSMapLayersService.getMapAppointments` loads Default CMDT through `FsSSConfigParser`, then:

1. Builds a Service Appointment SOQL `DISTANCE` filter from the origin, radius, unit, status list, boolean filters, and max results. Queries use `WITH USER_MODE`.
2. Resolves the Service Resource from the passed Id, or from `ServiceResource.RelatedRecordId` equal to the running user.
3. Loads that resource's effective territory memberships and skill levels, and the work-rule type tokens on the named scheduling policy.
4. Runs `FsSSPolicyMatcher.evaluate` per row. Territory mismatch and skill mismatch drop the row. The response includes skip counts, the SOQL text, and the policy rule types for the debug panel.
5. `FsSSCardFieldHelper` fills the configured card fields the user can read.

Claim does not repeat step 4.

### Policy matching

`Evaluate_Territory_Rules__c` and `Evaluate_Skill_Rules__c` gate the two families `FsSSPolicyMatcher` implements.

- Territory and location: appointment `ServiceTerritoryId` must be in the resource's effective Service Territory Member set. A blank territory fails closed.
- Skills: `SkillRequirement` on the appointment parent versus the resource's `ServiceResourceSkill` levels.

`loadPolicyRuleTypes` reads work-rule RecordType developer names from `FSL__Scheduling_Policy__c` where Name equals `Scheduling_Policy_Name__c` (Default value `Self Scheduling`). If the policy has no rule types, both families still run when their CMDT flags are on.

#### Policy rule types (debug)

Diagnostic dump of every work-rule type on that policy. It is what the policy asked for, not what this package executed.

#### Unimplemented rules (debug)

Types whose token does not contain `SKILL`, `TERRITOR`, or `LOCATION`. Diagnostic only; they never hide a pin. The list is collected only from appointments that match, so the debug row can show `(none)` when every radius candidate was skipped (for example Skipped skill = 2).

Substring mapping is coarse. `FIELD_WORKING_LOCATIONS` is treated as location/territory because it contains `LOCATION`. That check is Service Territory Member membership versus appointment territory, not Field Working Locations polygons.

#### Not evaluated

- `TIME_RULE_SERVICE`: operating hours, availability, and shifts.
- `GAP_RULE_SERVICE`: travel gap between jobs.

Claim pins the appointment at `System.now()` with no availability check.

### Claim

`FsSSMapLayersService.selfSchedule` delegates to `FsSSSelfScheduler.claim`.

1. Reject a null appointment or resource Id.
2. Require Service Appointment update and Assigned Resource create.
3. Lock the appointment (`FOR UPDATE`, `WITH USER_MODE`).
4. Require `FS_Ready_Now__c` and, when status values are configured, a status in that list.
5. Classify Assigned Resource rows as none, this resource, or another resource. The read does not throw because another resource is assigned.
6. Choose the engine from `Bypass_Fsl_Schedule_Here__c` only.

| Bypass | Assignment | Action, then set `Target_Status__c` |
|---|---|---|
| true (Default) | None | Set `SchedStartTime` and `SchedEndTime`, then insert one Assigned Resource. |
| true | This resource | Update the scheduled times. Leave the Assigned Resource row. |
| true | Another resource | Delete the other Assigned Resource rows, set the scheduled times, then insert one row for the claiming resource. |
| false | Any of the three | `FSL.ScheduleService.scheduleHere` with the configured policy, then set the target status. |

Scheduled times are written before an Assigned Resource insert. The org rejects an Assigned Resource when the Service Appointment has no schedule time. Duration minutes come from `DurationInMinutes` when it is greater than zero, otherwise 60.

`canClaim` does not require delete. Delete is checked only on the replace path (`AssignedResource.isDeletable()` and `delete as user`). The permission set grants that delete, and edit, because the platform requires edit in order to grant delete.

The test stub for `scheduleHere` updates the scheduled times and inserts an Assigned Resource only when the appointment has none, so tests do not need a second assignment row.

### Debug

`FsSSConfigParser` returns `debugEnabledMobile` and `debugEnabledPlatform`. A null config record sets both false. `getConfig` puts both on the LWC DTO.

`normalizeConfig` stores both flags. `loadConfig` then sets the single `settings.debugEnabled` used by the UI:

- `Small` uses `debugEnabledMobile`.
- `Medium` and `Large` use `debugEnabledPlatform`.

That one flag gates the Debug chip, the five-tap toggle (`debugVisible` and the list error panel), opening the panel after config load, and opening the list error panel after a failed claim. Schedule errors are recorded with source, message, appointment Id, and resource Id. They render at the bottom of `fsSelfScheduleDebug` and as the last row in `locationsList` when the list panel is open. The error toast still shows.

`Debug_Enabled__c` has been removed. `manifest/destructiveChanges.xml` deletes `FS_Self_Scheduling_Config__mdt.Debug_Enabled__c` as a post-destructive change. A deploy that adds the two new fields must pass that file with `--post-destructive-changes` and must also pass `--manifest`, which the CLI requires together with a destructive manifest.

### Distance unit

Default `Distance_Unit__c` is `km`. Keep it that way. Do not set Default to `mi`.

`FsSSConfigParser` uses miles only when the CMDT value is `mi`. Otherwise the unit is km. Apex `DISTANCE` SOQL uses the km unit literal unless that miles flag is on. The LWC haversine in `fsSSGeo` uses Earth radius 6371 km unless the unit is `mi`. Card distance labels use the same parsed unit.

### Security

SOQL that reads appointments, assignments, and config uses `WITH USER_MODE` or an equivalent user-mode DML form. Time updates and new Assigned Resource rows go through `Security.stripInaccessible`. Custom fields in this package set `securityClassification` to Confidential. The classes do not embed endpoints, tokens, or credentials.

### Apex size

`FsSSMapLayersService` is large (above the usual NCSS type guideline of about 500). Complexity suppressions exist on the map service, policy matcher, and config parser. Do not split that class unless a deploy or PMD run requires it.

### Tests

`FsSSMapLayersServiceTest` covers config parsing (including the two debug flags and both-off defaults), the Default `getConfig` payload, radius and policy filtering, and claim:

- Bypass on, another resource: one Assigned Resource remains, and it is the claiming resource. Status is Dispatched and the start time moves to now.
- Bypass on, this resource already assigned: times update, the same assignment remains, status is Dispatched.
- Bypass off, unassigned: the `scheduleHere` stub inserts one Assigned Resource and the status is Dispatched.
- Bypass off, this resource or another resource already assigned: claim uses the stub and does not throw because the appointment is already assigned.

Run that class with the deploy (`--tests FsSSMapLayersServiceTest`).
