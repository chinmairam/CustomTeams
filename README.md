# Custom Teams

A Salesforce Asset that brings **Account Team / Opportunity Team style functionality to any standard or custom object**. Add users to a record's team, grant them Read or Edit sharing access, assign team roles, and automatically manage manual sharing records — all driven by a Lightning Web Component related list and Apex trigger logic.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Object Model](#object-model)
- [Permission Sets](#permission-sets)
- [How It Works](#how-it-works)
- [Dependencies](#dependencies)
- [Deployment](#deployment)
- [Adding the Component to a Record Page](#adding-the-component-to-a-record-page)
- [Extending to a New Parent Object](#extending-to-a-new-parent-object)
- [Custom Labels](#custom-labels)
- [Notifications](#notifications)
- [Security Notes](#security-notes)

---

## Features

- Add any Salesforce user as a team member on any record
- Grant **Read** or **Edit** manual sharing access to the parent record automatically
- Assign a configurable **Team Role** per member
- Prevent exact duplicate team entries; seamlessly replace access level when changed
- Enforce that only the record owner or a role-hierarchy superior can manage team members
- Automatically clean up all team members when a parent record changes owner
- In-app and email notifications to team members on add, update, and remove
- Fully generic — one component and one trigger handler work across all objects
- Granular permission sets for Create / Read / Edit / Delete access

---

## Architecture

```
CustomTeamsTrigger  (Custom_Teams__c trigger)
        │
        ▼
CustomTeamsTriggerHandler        ← Routes trigger context to correct handler
        │
        ▼
CustomTeamAutoShareController    ← Validation, ownership alignment, share orchestration
        │
        ▼
GeneralManualSharing             ← Object-agnostic *Share record DML

CustomTeamRelatedListController  ← @AuraEnabled methods for the LWC
        │
        ▼
customTeamsRelatedList (LWC)     ← Related list UI on any record page
```

---

## Object Model

**Object:** `Custom_Teams__c`  
**Sharing Model:** Read (owner + manual shares)  
**Name Format:** `Teams-{000000}` (Auto Number)

| Field | API Name | Type | Description |
|---|---|---|---|
| Team Member | `Team_Member__c` | Lookup (User) | The user being granted access |
| Access Level | `Access_Level__c` | Picklist | `Read` or `Edit` — controls the manual share level |
| Team Role | `Team_Role__c` | Picklist | Descriptive role label (e.g. Sales Rep, Support) |
| Related Record ID | `Related_Record_Id__c` | Text | Stores the parent record's 18-char ID |
| Object API Name | `Object_API_Name__c` | Text | Stores the parent object's API name (e.g. `Account`) |
| Active | `Active__c` | Checkbox | Indicates whether the team membership is active |

---

## Permission Sets

Six permission sets are included to support role-based access control:

| Permission Set | Object Access |
|---|---|
| `Custom_Teams_Create` | Create + Read |
| `Custom_Teams_Read` | Read only |
| `Custom_Teams_Edit` | Read + Edit |
| `Custom_Teams_Delete` | Read + Delete |
| `Custom_Teams_Field_Level_Security_PS` | Field-level visibility |
| `Custom_Teams_Visibility_Custom_Permission_PS` | UI visibility via Custom Permission |

Assign the minimum required set to each user profile. A typical sales rep needs **Create + Edit**; a manager who removes members needs **Delete** in addition.

---

## How It Works

### Before Insert
1. **`validateAccess`** — Blocks the insert if the running user is not the record owner and is not higher in the role hierarchy than the owner. System Administrators and users with Modify All Data bypass this check.
2. **`preventExactDuplicates`** — If a team entry already exists for the same member + record combination:
   - Same access level → hard duplicate error shown to the user.
   - Different access level → old entry is deleted in `SYSTEM_MODE` so the new one replaces it cleanly.
3. **`setOwnerFromRelatedRecord`** — Sets `OwnerId` on the new `Custom_Teams__c` record to match the parent record's owner, ensuring correct record-level visibility.

### After Insert
- **`handleAfterInsert`** → `processShares(true)` → `GeneralManualSharing.createManualShares()`  
  Inserts a `*Share` row (e.g. `AccountShare`, `My_Object__Share`) with `RowCause = Manual` and the chosen access level.

### After Update
- **`handleTeamMemberUpdate`** — Detects changes to `Access_Level__c`, `Team_Member__c`, `Related_Record_Id__c`, or `Object_API_Name__c`. Only changed records are re-processed — share is re-created for the new values.

### After Delete
- **`handleAfterDelete`** → `processShares(false)` → `GeneralManualSharing.deleteManualShares()`  
  Removes only `RowCause = Manual` share rows for the deleted team member + record combination.

### Parent Owner Change
When the **parent record's owner changes**, all `Custom_Teams__c` entries for that record are deleted (which cascade-triggers the after delete sharing cleanup). This prevents stale team memberships under new ownership.

---

## Dependencies

| Dependency | Purpose |
|---|---|
| [Nebula Logger](https://github.com/jongpie/NebulaLogger) | Structured debug/error logging throughout all Apex classes |

Nebula Logger must be deployed to the target org before deploying Custom Teams/Remove/Replace Nebula Logger statements with System.debug.

---

## Deployment

### Prerequisites
- Salesforce CLI (`sf` or `sfdx`)
- Nebula Logger already deployed
- A connected org (sandbox recommended for first deploy)

### Deploy

```bash
# Authenticate
sf org login web --alias my-sandbox

# Deploy the package
sf project deploy start --source-dir force-app --target-org my-sandbox

### Post-Deploy Checklist

1. Assign at least one permission set to users who need access (see [Permission Sets](#permission-sets)).
2. Add the **Custom Teams Related List** LWC to the record page(s) of your choice via Lightning App Builder.
3. If using on a **standard object** (Account, Opportunity, etc.) or a custom object with **Private OWD**, ensure manual sharing is enabled on the target object (`enableSharing = true`).
4. For parent objects where owner changes should clean up teams, add the parent trigger call (see [Extending to a New Parent Object](#extending-to-a-new-parent-object)).

---

## Adding the Component to a Record Page

1. Open **Setup → Lightning App Builder**.
2. Edit the record page for the target object (e.g. Campaign).
3. Drag **Custom Teams Related List** from the component panel onto the page.
4. Save and **Activate** the page.

The component automatically reads `recordId` and `objectApiName` from the record page context — no manual configuration is needed.

---

## Extending to a New Parent Object

To enable automatic team cleanup when a parent record's **owner changes**, add one line to the parent object's trigger:

```apex
trigger CampaignTrigger on Campaign (after update) {
    CustomTeamsTriggerHandler.handleParentOwnerChange(Trigger.new, Trigger.oldMap);
}
```

This is safe to call alongside any existing trigger logic. The handler only acts when `OwnerId` has actually changed and exits immediately otherwise.

---

## Custom Labels

All user-facing strings are stored as Custom Labels under the `Custom Teams` category, making them translatable and org-configurable without code changes.

| Label API Name | Default Value |
|---|---|
| `ERROR_TEAM_MANAGE_INSUFFICIENT_ACCESS` | You do not have permission to manage team members for this record. |
| `DUPLICATE_CUSTOM_TEAM` | Duplicate Custom Team record: |
| `NO_CUSTOM_TEAM_DELETE_ACCESS` | You do not have permission to delete team members. |
| `TEAM_MEMBER_ADDED_SUCCESS` | Team Member added successfully. |
| `TEAM_MEMBER_UPDATE_SUCCESS` | Team Member updated successfully. |
| `TEAM_MEMBER_DELETE_SUCCESS` | Team Member deleted successfully. |
| `NO_TEAM_MEMBERS` | No team members found. Click "New" to start adding team members. |

---

## Notifications

Notifications are sent via the `Notify_Sales_Rep` custom notification type. Ensure this notification type exists in the target org after deployment.

| Action | In-App Notification |
|---|---|
| Member Added | ✅ |
| Access Level Changed | ✅ |
| Member Removed | ✅ |

---

## Security Notes

1. All SOQL on `Custom_Teams__c` uses `WITH USER_MODE` to enforce FLS and record sharing.
2. User-initiated DML (`deleteTeamMembers` in the LWC controller) uses `AccessLevel.USER_MODE`.
3. System-initiated DML (share record inserts/deletes, access level replacements, owner-change cleanup) uses `AccessLevel.SYSTEM_MODE` because `*Share` objects return `isCreateable/isDeletable = false` via Schema describe.
