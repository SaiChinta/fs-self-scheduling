# Post-deployment manual steps

These steps are **not** completed by deploying `force-app`. Do them after every new org install, and re-check after upgrades if layouts, mobile config, or users changed.

Product behaviour (map query, claim, policy matching) is in `README.md`.

## What the deploy already created

| Item | API / developer name | Notes |
|---|---|---|
| Permission set | `FS_SelfScheduling_Access` (label **FS SelfScheduling Access**) | Apex, CMDT, Ready Now FLS, tab, app, Field Service objects. Does **not** assign itself to users. |
| Public group | `FS_FieldResources_Team` (label **FS Field Resources Team**) | Membership is granted by the User Access Policy when the access permission set is assigned. |
| User Access Policy | `FS_FieldResources_Team_Membership` | Active. Create and Update. Grants group **FS Field Resources Team** to users who have **FS SelfScheduling Access**. |
| Sharing rule | `Ready_Now_Appointments_Mobile` | Edit on Service Appointments where `FS_Ready_Now__c` is true, shared to that group. |
| Briefcase | `FS_SelfScheduling` (label **FS Self Scheduling**, High Volume, Active) | Not assigned to a mobile configuration until you do it in Setup. |
| Global / screen action | `FS_SelfScheduling` (label **Self Scheduling**, LWC `mobileMapLayersMain`) | Not on any publisher or page layout. |
| Lightning tab | `FS_SelfScheduling` | Visible via the permission set. |
| Lightning app | `FS_SelfScheduling` (label **FS Self Scheduling**) | Home + Self Scheduling tab. |
| Custom fields | `ServiceAppointment.FS_Ready_Now__c`, `WorkOrderLineItem.FS_Ready_Now__c` | Label **Ready Now**. Not on page layouts. |
| CMDT record | `FS_Self_Scheduling_Config.Default` | See CMDT section. Policy name must exist in the org. |
| FlexiPage | `ClonedServiceAppointmentRecordPageForApp` | Not activated. Also references `fsShowRelatedAppointments`, which is **not** in this package. Prefer adding `fsSelfScheduleRecordPage` to an existing Service Appointment page. |

## Prerequisites

Confirm in the target org before assigning users:

1. Field Service is enabled.
2. Service Appointment status picklist includes the CMDT values (`None`, `Scheduled` for the map; `Dispatched` as the post-claim status). Adjust CMDT if this org uses different status API names.
3. Enhanced Scheduling and Optimization is only required if you turn **off** `Bypass_Fsl_Schedule_Here__c` (Default is **on**, so claim does not call `scheduleHere`).
4. Each technician user has an **active** Service Resource (`ResourceType` Technician) whose `RelatedRecordId` is that user.

---

## 1. Permission sets

Assign to every admin, dispatcher, and technician who will use the map:

- **FS SelfScheduling Access** (`FS_SelfScheduling_Access`)
- **Field Service Mobile Standard** (`FieldServiceMobileStandardPermSet`)

The package permission set description calls out the Field Service Mobile set because briefcase priming and SFS Mobile need it. `FS_SelfScheduling_Access` also enables the `FieldServiceAccess` user permission.

If a technician sees `[object Object]` or a permission error on claim, the usual cause is a missing assignment of **FS SelfScheduling Access** on that Service Resource user.

`ServiceResource.Name` cannot be added to the permission set (required field). `ServiceResource.IsActive` FLS is included for the debug lookup.

## 2. Public group, User Access Policy, and sharing

### User Access Policy

The package includes User Access Policy **FS_FieldResources_Team_Membership**.

| Property | Value |
|---|---|
| Developer name | `FS_FieldResources_Team_Membership` |
| Status | Active |
| Trigger | Create and Update |
| Filter | User has permission set `FS_SelfScheduling_Access` |
| Action | Grant public group `FS_FieldResources_Team` |

It replaces hand-adding every technician to **FS Field Resources Team**, as long as they receive **FS SelfScheduling Access**.

After deploy:

1. Setup → User Access Policies. Confirm **User Access Policies** is enabled for the org.
2. Open **FS_FieldResources_Team_Membership**. Confirm Status is **Active**.
3. If the org already had users with **FS SelfScheduling Access** before this policy existed, use **Apply** (apply to existing users) so they are added to the group without waiting for a user update.
4. If deploy fails because `order` `11` is already used by another policy in that org, change Order to the next free number and redeploy.

Manual group membership remains a fallback if the policy cannot run.

### Sharing

1. Setup → Public Groups → **FS Field Resources Team**. After the policy runs, technicians with the access permission set should appear as members.
2. Confirm sharing rule **Ready Now Appointments to Mobile Users** (`Ready_Now_Appointments_Mobile`) is active:
   - Object: Service Appointment
   - Criteria: `Ready Now` equals True
   - Share with: FS Field Resources Team
   - Access: Edit
   - Includes records owned by all users

Users **not** in the group will not see other people’s Ready Now appointments, even if the map query would otherwise match them.

### Verify User Access Policy

1. Pick a user who is not in **FS Field Resources Team**.
2. Assign **FS SelfScheduling Access** (or update the user so the policy re-evaluates).
3. Confirm the user is a member of **FS Field Resources Team**.
4. As that user, open a Ready Now Service Appointment owned by someone else and confirm Edit access.
5. As a user **without** the permission set and **not** in the group, confirm they cannot see those Ready Now appointments.

## 3. Ready Now on layouts

The fields deploy but are not placed on layouts. Add **Ready Now** (`FS_Ready_Now__c`) to:

- Service Appointment page layouts used by dispatchers and technicians
- Work Order Line Item page layouts used for priming and skill matching

Optional: add the same fields to Lightning record pages / dynamic forms if the org uses those instead of classic layouts.

## 4. Custom metadata (Default record)

Setup → Custom Metadata Types → **FS Self Scheduling Config** → **Default**.

| Field | Default deploy value | What to do |
|---|---|---|
| Search Radius | `10` | Radius from the technician origin. |
| Distance Unit | `km` | Keep `km`. Do not set Default to `mi`. |
| Status Values | `None,Scheduled` | Must match Service Appointment status picklist values in this org. |
| Boolean Filters | `FS_Ready_Now__c=true` | Map query filter. Do not use this field to define sharing. |
| Scheduling Policy Name | `Self Scheduling` | **Must be the exact Name of an FSL Scheduling Policy in this org.** Create a policy named Self Scheduling, or change this to an existing policy (for example Customer First or Standard). Territory and skill matching read that policy’s work-rule types. |
| Target Status | `Dispatched` | Status set after a successful claim. |
| Debug Enabled | `true` | Shows the Debug chip. Five-tap on the map also opens debug on phone. |
| Max Results | `200` | Cap on the radius query. |
| Evaluate Territory Rules | `true` | Appointment territory must be in the resource’s Service Territory Member set. |
| Evaluate Skill Rules | `true` | Parent Skill Requirements versus Service Resource Skills. |
| Card Detail Fields | `Work Type:WorkType.Name,Duration(Mins):DurationInMinutes,Contact Name:Contact.Name,Contact Phone:Contact.Phone` | Label:FieldApiName pairs on the marker card. |
| Bypass FSL Schedule Here | `true` | When true, claim pins times and inserts Assigned Resource without `FSL.ScheduleService.scheduleHere`. Turn off only if Enhanced Scheduling is enabled and you want the engine to pin the appointment. |

CMDT access is under **Custom Metadata Types**, not Object Settings.

## 5. Technician identity and skills

For each technician user:

1. Active Service Resource linked via `RelatedRecordId`.
2. Service Territory Member effective now (Primary or Secondary) on the **same** territory as the Ready Now appointments they should see.
3. Service Resource Skills that satisfy Skill Requirements on the parent Work Order / Work Order Line Item when skill matching is on.

Blank appointment territory fails closed when territory matching is on. Missing skills fail closed when skill matching is on.

## 6. Briefcase (Field Service Mobile offline)

The briefcase **FS Self Scheduling** deploys **Active** and High Volume. It is **not** attached to a mobile configuration until you assign it.

### What it primes

| Rule | Filter | Related records | Limit |
|---|---|---|---|
| Work Order Line Item | `FS_Ready_Now__c` = true | Child Skill Requirements | 2000 / 2000 |
| Service Appointment | `FS_Ready_Now__c` = true | — | 2000 |
| Service Resource | `RelatedRecordId` = running user | Service Territory Members, Service Resource Skills | 50 / 200 / 200 |
| FS Self Scheduling Config | all CMDT rows | — | — |

### Assign it

1. Setup → Field Service Mobile Settings (or Briefcase Builder / mobile configuration used by your org).
2. Open the **mobile configuration** assigned to tester profiles or permission sets.
3. Add briefcase **FS Self Scheduling** (`FS_SelfScheduling`).
4. Keep it Active.
5. On the device: log in, allow location, **sync**. Primed Ready Now rows are then available offline; the map still runs Apex when online.

If testers already have another briefcase, add this one rather than replacing the org’s existing work briefcase unless you intend to.

## 7. Lightning (desktop / tablet)

### App and tab

1. App Launcher → **FS Self Scheduling**.
2. Open the **Self Scheduling** tab (`mobileMapLayersMain`).
3. Hard-refresh once after deploy so LWCs load.

App visibility comes from **FS SelfScheduling Access**.

### Record page map

Do **not** rely on activating `ClonedServiceAppointmentRecordPageForApp` as-is. That page includes `fsShowRelatedAppointments`, which this package does not ship.

Safer:

1. Lightning App Builder → the Service Appointment record page used by Field Service (and/or Work Order / Work Order Line Item).
2. Add component **Self Scheduling** (`fsSelfScheduleRecordPage`).
3. Activate for the **FS Self Scheduling** app and the Field Service app, Desktop (and phone if you want the map on Lightning mobile).

## 8. Field Service Mobile (SFS) action

The quick action **Self Scheduling** (`FS_SelfScheduling`) is a Screen Action on LWC `mobileMapLayersMain`. It is **not** on a layout.

1. Setup → Global Actions, confirm **Self Scheduling** exists.
2. Add it to **Salesforce Mobile and Lightning Experience Actions** on the **Global Publisher Layout** used by Field Service Mobile.
3. Optionally add the same action to the Service Appointment page layout mobile / Lightning actions if technicians should open it from a record.
4. In the Field Service Mobile app, confirm the action appears on the action bar after sync.

The LWC also targets Lightning tabs and record screen actions. Adding the tab to the Field Service Mobile navigation is optional if the publisher action is in place.

## 9. Test data

Create unassigned work the map can claim:

1. Work Order Line Item: **Ready Now** = true, latitude/longitude within the CMDT radius (default 10 km) of the tester (device GPS, or a known origin if GPS is denied).
2. Skill Requirements on that WOLI if skill matching should pass.
3. Child Service Appointment: **Ready Now** = true, status **None** or **Scheduled**, same coordinates and territory, duration set.
4. No Assigned Resource for a first-time claim. If the appointment is already assigned to **this** technician, claim updates scheduled start/end and sets **Dispatched**. If it is assigned to a **different** resource, claim is rejected.

## 10. Smoke checks

### Platform

- Pins appear for Ready Now appointments in radius after territory/skill filters.
- List grabber expands the sheet and leaves a band of map visible.
- Confirm modal: **No** left, **Yes** right, buttons spanning the footer.
- Self Schedule sets status **Dispatched** and leaves a single Assigned Resource.
- Debug chip is visible when Debug Enabled is true.
- Open Record on desktop/tablet opens the Service Appointment as a console workspace tab (or a Lightning record page if the app is not a console). It must not open a blank browser tab.

### Field Service Mobile

- After sync, primed Ready Now rows are on the device.
- Bottom sheet pull-up stops short of the top (map still visible).
- Claim succeeds for unassigned work and for work already assigned to the logged-in resource.
- Open Record still opens the appointment in Field Service Mobile (unchanged deep link).
- A second technician in **FS Field Resources Team** can see the same Ready Now appointments. A user **not** in the group should not.

### Empty map

Open Debug and check origin, radius unit (`km`), Ready Now, status, skipped territory, skipped skill, and that **Scheduling Policy Name** matches a policy that exists in the org.

---

## Checklist

- [ ] `FS_SelfScheduling_Access` assigned
- [ ] `FieldServiceMobileStandardPermSet` assigned
- [ ] User Access Policy **FS_FieldResources_Team_Membership** is Active
- [ ] Policy applied to existing users if they already had the access permission set
- [ ] Those users are members of **FS Field Resources Team**
- [ ] Sharing rule active on `FS_Ready_Now__c`
- [ ] Ready Now on Service Appointment and Work Order Line Item layouts
- [ ] CMDT Default policy name matches an org FSL policy
- [ ] Status and target status match the org picklist
- [ ] Each tester has Service Resource + territory member + skills
- [ ] Briefcase **FS Self Scheduling** assigned to the SFS mobile configuration
- [ ] Device sync completed
- [ ] Self Scheduling action on the Field Service Mobile publisher layout
- [ ] `fsSelfScheduleRecordPage` on the Lightning Service Appointment page (optional for desktop)
- [ ] Hard-refresh / app restart after deploy
