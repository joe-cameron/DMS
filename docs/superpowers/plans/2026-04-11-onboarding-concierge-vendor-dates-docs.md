# Onboarding Concierge — Vendors / Dates / Documents Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4-tab Concierge shell with a 4-card dashboard (Vendors / Important Dates / Location Details / Documents), add email-based delegation, add vendor spreadsheet upload, add a standalone dates list with per-row file attachment, and deploy to Test then Portal envs.

**Architecture:** In-place refactor of `C:\dcfg\spa\dcfg-property-intake\`. Two new Dataverse tables (`dcfg_intake_date`, `dcfg_intake_delegation`), one new Power Automate flow (`dcfg_SendIntakeDelegationInvite`), one new SPA dependency (`xlsx`/SheetJS). Anonymous portal web role is the only auth surface. Component reuse where possible (`PropertyForm`, `VendorList`, `DocumentCapture`). Hash routing replaces tab state. `storage.js` remains a localStorage cache; Dataverse is the source of truth.

**Tech Stack:** React 16.14 · Vite 5.4 · hand-rolled hash routing · SheetJS Community · Dataverse Web API · Power Automate · PowerShell for Dataverse admin · Playwright for E2E

**Spec:** `docs/superpowers/specs/2026-04-11-onboarding-concierge-vendor-dates-docs-design.md`

**Target environments:**
- Test: DCFGSystems-Test (`org0c17e98d`, PAC `[1]`), site `decadeswelcomesyou.powerappsportals.com`
- Portal: `orgf625b080`, PAC `[6]`, site `decades-concierge.powerappsportals.com`
- Solution: `DCFGSystemTest` on both

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `spa/dcfg-property-intake/src/HomeDashboard.jsx` | 4-card landing page after login; renders card grid + header |
| `spa/dcfg-property-intake/src/VendorsScreen.jsx` | Wraps existing `VendorList.jsx`; adds "Download template" + "Upload spreadsheet" + "Delegate" buttons |
| `spa/dcfg-property-intake/src/DatesScreen.jsx` | Standalone dates list with add/edit/delete and per-row file attachment |
| `spa/dcfg-property-intake/src/LocationsScreen.jsx` | Wraps existing `PropertyForm.jsx` list and selection; adds "Delegate" button |
| `spa/dcfg-property-intake/src/DocumentsScreen.jsx` | Wraps existing `DocumentCapture.jsx`; adds "Delegate" button |
| `spa/dcfg-property-intake/src/DelegateModal.jsx` | Name + email capture modal; pre-fills sender from localStorage; multi-select card scope |
| `spa/dcfg-property-intake/src/FeedbackModal.jsx` | Feedback capture (writes to `dcfg_audit_logs` with type="feedback") |
| `spa/dcfg-property-intake/src/VendorSpreadsheetModal.jsx` | File picker → parse → preview → commit via SheetJS |
| `spa/dcfg-property-intake/src/vendorSpreadsheetParser.js` | Pure parser (parses `.xlsx`, validates rows, returns candidates) |
| `spa/dcfg-property-intake/src/useHashRoute.js` | Minimal hash routing hook (no router library) |
| `spa/dcfg-property-intake/public/templates/decades-vendor-intake.xlsx` | Fixed vendor upload template (bundled static file) |
| `spa/dcfg-property-intake/test/vendorSpreadsheetParser.test.js` | Unit tests for parser (Vitest) |
| `spa/dcfg-property-intake/test/fixtures/vendor-template-happy.xlsx` | Happy-path fixture |
| `spa/dcfg-property-intake/test/fixtures/vendor-template-bad-headers.xlsx` | Missing-header fixture |
| `spa/dcfg-property-intake/test/fixtures/vendor-template-bad-rows.xlsx` | Mixed-validity fixture |
| `nora/tests/concierge/concierge-dashboard.spec.ts` | Playwright E2E against `decadeswelcomesyou.powerappsportals.com` |
| `scripts/concierge/Create-IntakeDateTable.ps1` | Creates `dcfg_intake_date` table via Web API |
| `scripts/concierge/Create-IntakeDelegationTable.ps1` | Creates `dcfg_intake_delegation` table via Web API |
| `scripts/concierge/Set-IntakeConciergePermissions.ps1` | Site settings + table permissions for both new tables |
| `scripts/concierge/Seed-IntakeFieldConfigDefaults.ps1` | Seeds C-cut defaults in `dcfg_intake_field_configs` |
| `scripts/concierge/flow-delegate-invite-v1-placeholder.json` | Step 1 flow definition (placeholders) |
| `scripts/concierge/flow-delegate-invite-v3-final.json` | Step 3 flow definition (full) |

### Modified files

| Path | Change |
|---|---|
| `spa/dcfg-property-intake/src/App.jsx` | Strip 4-tab shell; add hash routing; wire dashboard + screens |
| `spa/dcfg-property-intake/src/storage.js` | Add `dates`, `delegations` arrays; add `createEmptyDate()` helper |
| `spa/dcfg-property-intake/src/intakeApi.js` | Add CRUD for dates + delegations; add annotation uploader for dates; add entity set constants |
| `spa/dcfg-property-intake/package.json` | Add `xlsx` dependency |

### Retired files

| Path | Reason |
|---|---|
| `spa/dcfg-property-intake/src/AuthorizedUsers.jsx` | "Your Team" tab body is replaced by `DelegateModal.jsx` |

---

## Chunk 1: Schema and portal integration (Test env)

Creates the two new Dataverse tables, option sets, site settings, and table permissions in DCFGSystems-Test. Verified via direct Dataverse query. No SPA code yet.

### Task 1.0: Verify database bible preconditions

**Files:** none (read-only verification)

- [ ] **Step 1: Confirm `dcfg_intake_session` exists and has `dcfg_intake_sessionid` as PK**

```bash
pwsh -Command "Invoke-RestMethod -Uri '$env:ORG_URL/api/data/v9.2/EntityDefinitions(LogicalName=''dcfg_intake_session'')?\$select=LogicalName,PrimaryIdAttribute,PrimaryNameAttribute' -Headers @{Authorization=\"Bearer \$env:TOKEN\"}"
```
Expected: `PrimaryIdAttribute = dcfg_intake_sessionid`. Abort plan and file an issue if the schema has drifted.

- [ ] **Step 2: Confirm `dcfg_audit_logs` has `dcfg_action`, `dcfg_context`, and `dcfg_actor` columns (used by feedback submit in Task 6.3)**

```bash
pwsh -Command "Invoke-RestMethod -Uri '$env:ORG_URL/api/data/v9.2/EntityDefinitions(LogicalName=''dcfg_audit_logs'')/Attributes?\$select=LogicalName&\$filter=LogicalName eq ''dcfg_action'' or LogicalName eq ''dcfg_context'' or LogicalName eq ''dcfg_actor''' -Headers @{Authorization=\"Bearer \$env:TOKEN\"}"
```
Expected: three rows. If any column is missing, replace `submitFeedback()` in Task 6.3 with the actual column names the bible shows.

### Task 1.1: Pin OptionSet integer codes and spreadsheet template source

**Files:**
- Modify: `docs/superpowers/specs/2026-04-11-onboarding-concierge-vendor-dates-docs-design.md` (inline note only)

- [ ] **Step 1: Decide and record the integer codes**

Add a `<!-- IMPL-NOTE -->` HTML comment at the bottom of the spec pinning these exact values:

```
dcfg_intake_date.dcfg_category:
  100000000 = Inspection
  100000001 = Cert Expiration
  100000002 = Contract Anniversary
  100000003 = Insurance
  100000004 = Other

dcfg_intake_delegation.dcfg_card_scope:
  100000000 = Vendors
  100000001 = Dates
  100000002 = Locations
  100000003 = Documents
  100000004 = All

Spreadsheet template origin:
  The reusable generator script at scripts/concierge/gen-fixture-sheets.mjs
  (created in Task 4.2) also emits the production template to
  spa/dcfg-property-intake/public/templates/decades-vendor-intake.xlsx.
  One generator, three fixtures + one production template.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-04-11-onboarding-concierge-vendor-dates-docs-design.md
git commit -m "spec: pin OptionSet integer codes for intake date + delegation"
```

### Task 1.2: Create `dcfg_intake_date` table in Test

**Files:**
- Create: `scripts/concierge/Create-IntakeDateTable.ps1`

- [ ] **Step 1: Verify PAC auth is on Test**

Run:
```bash
pac auth select --index 1
pac org who
```
Expected output: `Connected to...` with `org0c17e98d.crm.dynamics.com`. If not index 1, fix before proceeding.

- [ ] **Step 2: Write the PowerShell script**

The bearer token is obtained via `pac auth create-token --resource` — no hardcoded credentials. This pattern is already used by `scripts/concierge/Create-IntakeTables.ps1` from the 2026-03-26 plan; reuse the same helper.

```powershell
# scripts/concierge/Create-IntakeDateTable.ps1
$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org0c17e98d.crm.dynamics.com'
$solution = 'DCFGSystemTest'

# Bearer token via pac (already authed to Test on index [1])
$token = (pac auth create-token --resource $orgUrl --output json | ConvertFrom-Json).AccessToken
if (-not $token) { throw 'Failed to obtain bearer token via pac auth create-token' }

$headers = @{
  'Authorization'            = "Bearer $token"
  'Content-Type'             = 'application/json'
  'OData-MaxVersion'         = '4.0'
  'OData-Version'            = '4.0'
  'Accept'                   = 'application/json'
  'MSCRM.SolutionUniqueName' = $solution
}

# 1. Create the table with primary name column (dcfg_name)
$tableBody = @{
  '@odata.type'         = '#Microsoft.Dynamics.CRM.EntityMetadata'
  SchemaName            = 'dcfg_intake_date'
  DisplayName           = @{ LocalizedLabels = @(@{ Label = 'Intake Date'; LanguageCode = 1033 }) }
  DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = 'Intake Dates'; LanguageCode = 1033 }) }
  Description           = @{ LocalizedLabels = @(@{ Label = 'Customer-entered important date from onboarding concierge'; LanguageCode = 1033 }) }
  HasActivities         = $false
  HasNotes              = $true   # enables annotations for file attachments
  OwnershipType         = 'UserOwned'
  PrimaryNameAttribute  = 'dcfg_name'
  Attributes            = @(
    @{
      '@odata.type'  = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
      SchemaName     = 'dcfg_name'
      DisplayName    = @{ LocalizedLabels = @(@{ Label = 'Label'; LanguageCode = 1033 }) }
      RequiredLevel  = @{ Value = 'ApplicationRequired' }
      MaxLength      = 200
      FormatName     = @{ Value = 'Text' }
      IsPrimaryName  = $true
    }
  )
} | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions" -Method POST -Headers $headers -Body $tableBody
Write-Host 'Table created. Waiting 10s for metadata cache...'; Start-Sleep 10

# 2. Add lookup to dcfg_intake_session (one-to-many relationship)
$lookupBody = @{
  '@odata.type'               = '#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
  SchemaName                  = 'dcfg_dcfg_intake_session_dcfg_intake_date'
  ReferencedEntity            = 'dcfg_intake_session'
  ReferencingEntity           = 'dcfg_intake_date'
  Lookup = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.LookupAttributeMetadata'
    SchemaName    = 'dcfg_sessionid'
    DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Session'; LanguageCode = 1033 }) }
    RequiredLevel = @{ Value = 'ApplicationRequired' }
  }
  AssociatedMenuConfiguration = @{ Behavior='UseCollectionName'; Group='Details'; Order=10000 }
  CascadeConfiguration        = @{ Assign='NoCascade'; Delete='Cascade'; Merge='NoCascade'; Reparent='NoCascade'; Share='NoCascade'; Unshare='NoCascade' }
} | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/RelationshipDefinitions" -Method POST -Headers $headers -Body $lookupBody
Start-Sleep 5

function Add-Column($body) {
  Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_intake_date')/Attributes" -Method POST -Headers $headers -Body ($body | ConvertTo-Json -Depth 20 -Compress)
  Start-Sleep 2
}

# 3. dcfg_due_date — DateTime with DateOnly format
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
  SchemaName    = 'dcfg_due_date'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Due Date'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  Format        = 'DateOnly'
  DateTimeBehavior = @{ Value = 'DateOnly' }
}

# 4. dcfg_category — Picklist with pinned option codes from Task 1.1
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
  SchemaName    = 'dcfg_category'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Category'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  OptionSet     = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.OptionSetMetadata'
    IsGlobal      = $false
    OptionSetType = 'Picklist'
    Options       = @(
      @{ Value = 100000000; Label = @{ LocalizedLabels = @(@{ Label = 'Inspection';           LanguageCode = 1033 }) } },
      @{ Value = 100000001; Label = @{ LocalizedLabels = @(@{ Label = 'Cert Expiration';      LanguageCode = 1033 }) } },
      @{ Value = 100000002; Label = @{ LocalizedLabels = @(@{ Label = 'Contract Anniversary'; LanguageCode = 1033 }) } },
      @{ Value = 100000003; Label = @{ LocalizedLabels = @(@{ Label = 'Insurance';            LanguageCode = 1033 }) } },
      @{ Value = 100000004; Label = @{ LocalizedLabels = @(@{ Label = 'Other';                LanguageCode = 1033 }) } }
    )
  }
}

# 5. dcfg_notes — Memo 1000
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.MemoAttributeMetadata'
  SchemaName    = 'dcfg_notes'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Notes'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  MaxLength     = 1000
  Format        = 'TextArea'
}

# 6. dcfg_location_ref — String 100
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_location_ref'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Location Reference'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  MaxLength     = 100
  FormatName    = @{ Value = 'Text' }
}

# 7. dcfg_active_flag — Boolean, default true
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
  SchemaName    = 'dcfg_active_flag'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Active'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  DefaultValue  = $true
  OptionSet     = @{
    '@odata.type'  = '#Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
    TrueOption     = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = 'Active';  LanguageCode = 1033 }) } }
    FalseOption    = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = 'Retired'; LanguageCode = 1033 }) } }
  }
}

Write-Host 'dcfg_intake_date created in DCFGSystemTest with all columns.'
```

- [ ] **Step 3: Run the script**

```bash
pwsh -File scripts/concierge/Create-IntakeDateTable.ps1
```

Expected: Table + relationship + 5 columns created. No 429 errors; if 429 appears, script retries with backoff.

- [ ] **Step 4: Verify via direct query**

```powershell
$r = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_intake_date')?`$select=LogicalName,PrimaryIdAttribute,PrimaryNameAttribute,HasNotes" -Headers @{Authorization="Bearer $token"}
$r
```

Expected: Returns the entity with `HasNotes = true` and `PrimaryNameAttribute = dcfg_name`.

- [ ] **Step 5: Commit**

```bash
git add scripts/concierge/Create-IntakeDateTable.ps1
git commit -m "schema: create dcfg_intake_date table in Test"
```

### Task 1.3: Create `dcfg_intake_delegation` table in Test

**Files:**
- Create: `scripts/concierge/Create-IntakeDelegationTable.ps1`

- [ ] **Step 1: Write the script**

Same token + header bootstrap as Task 1.2. Entity body uses `HasNotes = $false` (no file attachments on delegations) and `PrimaryNameAttribute = 'dcfg_name'`. After entity creation, add the lookup to `dcfg_intake_session` using the same relationship pattern as Task 1.2 (schema name `dcfg_dcfg_intake_session_dcfg_intake_delegation`). Then call the `Add-Column` helper for each remaining column:

```powershell
# dcfg_delegate_email — String 200, Email format
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_delegate_email'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Delegate Email'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'ApplicationRequired' }
  MaxLength     = 200
  FormatName    = @{ Value = 'Email' }
}

# dcfg_sender_name — String 200
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_sender_name'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Sender Name'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'ApplicationRequired' }
  MaxLength     = 200
  FormatName    = @{ Value = 'Text' }
}

# dcfg_sender_email — String 200, Email format
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_sender_email'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Sender Email'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'ApplicationRequired' }
  MaxLength     = 200
  FormatName    = @{ Value = 'Email' }
}

# dcfg_card_scope — Picklist with pinned option codes from Task 1.1
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
  SchemaName    = 'dcfg_card_scope'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Card Scope'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  OptionSet     = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.OptionSetMetadata'
    IsGlobal      = $false
    OptionSetType = 'Picklist'
    Options       = @(
      @{ Value = 100000000; Label = @{ LocalizedLabels = @(@{ Label = 'Vendors';   LanguageCode = 1033 }) } },
      @{ Value = 100000001; Label = @{ LocalizedLabels = @(@{ Label = 'Dates';     LanguageCode = 1033 }) } },
      @{ Value = 100000002; Label = @{ LocalizedLabels = @(@{ Label = 'Locations'; LanguageCode = 1033 }) } },
      @{ Value = 100000003; Label = @{ LocalizedLabels = @(@{ Label = 'Documents'; LanguageCode = 1033 }) } },
      @{ Value = 100000004; Label = @{ LocalizedLabels = @(@{ Label = 'All';       LanguageCode = 1033 }) } }
    )
  }
}

# dcfg_personal_note — Memo 1000
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.MemoAttributeMetadata'
  SchemaName    = 'dcfg_personal_note'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Personal Note'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  MaxLength     = 1000
  Format        = 'TextArea'
}

# dcfg_sent_at — DateTime (DateAndTime)
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
  SchemaName    = 'dcfg_sent_at'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Sent At'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  Format        = 'DateAndTime'
  DateTimeBehavior = @{ Value = 'UserLocal' }
}

# dcfg_active_flag — Boolean, default true (same pattern as Task 1.2)
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
  SchemaName    = 'dcfg_active_flag'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Active'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  DefaultValue  = $true
  OptionSet     = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
    TrueOption    = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = 'Active';  LanguageCode = 1033 }) } }
    FalseOption   = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = 'Retired'; LanguageCode = 1033 }) } }
  }
}
```

- [ ] **Step 2: Run it**

```bash
pwsh -File scripts/concierge/Create-IntakeDelegationTable.ps1
```

- [ ] **Step 3: Verify entity was created**

```powershell
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_intake_delegation')?`$select=LogicalName,PrimaryNameAttribute,HasNotes" -Headers $headers
```
Expected: `PrimaryNameAttribute = dcfg_name`, `HasNotes = false`.

- [ ] **Step 4: Verify OptionSet codes match the Task 1.1 pin**

```powershell
$opts = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_intake_delegation')/Attributes(LogicalName='dcfg_card_scope')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet" -Headers $headers
$codes = $opts.OptionSet.Options | ForEach-Object { $_.Value }
$expected = @(100000000,100000001,100000002,100000003,100000004)
if (Compare-Object $codes $expected) { throw 'dcfg_card_scope OptionSet codes do not match Task 1.1 pin' }
Write-Host 'OptionSet codes verified against Task 1.1 pin.'
```

Repeat the same verification for `dcfg_intake_date.dcfg_category`.

- [ ] **Step 5: Commit**

```bash
git add scripts/concierge/Create-IntakeDelegationTable.ps1
git commit -m "schema: create dcfg_intake_delegation table in Test"
```

### Task 1.4: Site settings and table permissions (Test)

**Files:**
- Create: `scripts/concierge/Set-IntakeConciergePermissions.ps1`

- [ ] **Step 1: Capture before-state**

Run:
```bash
pwsh -Command "Invoke-RestMethod -Uri '$orgUrl/api/data/v9.2/adx_sitesettings?`$filter=startswith(adx_name,''Webapi/dcfg_intake_date'') or startswith(adx_name,''Webapi/dcfg_intake_delegation'')' -Headers `$h | ConvertTo-Json -Depth 10 > scripts/_backups/2026-04-11_concierge-permissions-before.json"
```

- [ ] **Step 2: Write the script**

The script:
1. Reads site GUID for `decadeswelcomesyou.powerappsportals.com` via `mspp_website` query
2. Upserts four site settings rows (two per table: `enabled=true`, `fields=<explicit list>`)
3. Reads or creates two `mspp_entitypermission` rows per table (Full and ReadOnly), scope = Parent via `dcfg_intake_session`
4. Upserts web-role links via the `mspp_entitypermission_webroleset` intersect set

Explicit field lists:

**`dcfg_intake_date` fields:**
```
_dcfg_sessionid_value,createdon,dcfg_active_flag,dcfg_category,dcfg_due_date,dcfg_intake_dateid,dcfg_location_ref,dcfg_name,dcfg_notes,modifiedon,statecode,statuscode
```

**`dcfg_intake_delegation` fields:**
```
_dcfg_sessionid_value,createdon,dcfg_active_flag,dcfg_card_scope,dcfg_delegate_email,dcfg_intake_delegationid,dcfg_name,dcfg_personal_note,dcfg_sender_email,dcfg_sender_name,dcfg_sent_at,modifiedon,statecode,statuscode
```

Use the `Set-IntakeTablePermissions.ps1` script from the 2026-03-26 intake-portal-fixes plan (`docs/superpowers/plans/2026-03-26-intake-portal-fixes.md`) as a reference for the Parent-scope permission pattern.

- [ ] **Step 3: Run the script**

```bash
pwsh -File scripts/concierge/Set-IntakeConciergePermissions.ps1
```

- [ ] **Step 4: Verify role associations via intersect query**

```powershell
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/mspp_entitypermission_webroleset?`$filter=_mspp_entitypermissionid_value eq <new-perm-guid>" -Headers $h
```

Do NOT use `$expand` on this nav property — per `project_contract_composer_schema_built.md`, the expand returns empty for mspp_* M:N. Use the intersect entity set directly.

Expected: Both tables linked to the anonymous intake web role.

- [ ] **Step 5: Clear portal cache (manual)**

Visit `https://decadeswelcomesyou.powerappsportals.com/_services/about` → Clear Cache button. Record the timestamp in a terminal comment.

- [ ] **Step 6a: Smoke GET via unauth fetch**

```bash
pwsh -Command "Invoke-RestMethod -Uri 'https://decadeswelcomesyou.powerappsportals.com/_api/dcfg_intake_dates?`$select=dcfg_name&`$top=1' -Method GET"
```
Expected: 200 with empty value array (no rows yet). **401 or 403 means permissions not wired** — re-run Task 1.4 steps 2–3.

- [ ] **Step 6b: Smoke POST via unauth fetch (Create permission probe)**

Because an empty-table GET passes even with read-only perms, probe Create by POSTing a throwaway row against an existing session ID, then soft-delete it immediately. This requires the portal's `__RequestVerificationToken` — run this from an open browser session on the portal (devtools console) rather than server-side pwsh:

```js
// Run in browser devtools after opening the portal with a valid access code
const token = document.querySelector('input[name="__RequestVerificationToken"]').value;
const sid   = '<paste a known dcfg_intake_sessionid GUID here>';
const r = await fetch('/_api/dcfg_intake_dates', {
  method: 'POST',
  headers: { 'Content-Type':'application/json', 'Accept':'application/json', '__RequestVerificationToken': token },
  credentials: 'same-origin',
  body: JSON.stringify({ dcfg_name:'probe', dcfg_active_flag:true, 'dcfg_sessionid@odata.bind': `/dcfg_intake_sessions(${sid})` }),
});
console.log(r.status); // expect 204 (success)
```
Then PATCH the row `dcfg_active_flag=false` to clean up. Expected: 204 on POST, 204 on PATCH. A 403 on POST means Create permission is missing.

- [ ] **Step 7: Commit**

```bash
git add scripts/concierge/Set-IntakeConciergePermissions.ps1 scripts/_backups/2026-04-11_concierge-permissions-before.json
git commit -m "schema: site settings + table permissions for concierge new tables (Test)"
```

### Chunk 1 complete

All schema + portal integration live in Test. Concierge SPA can read/write both new tables via portal Web API. No SPA code yet.

---

## Chunk 2: API surface (`intakeApi.js`)

Adds the CRUD layer for dates and delegations so the rest of the SPA build has something to call. Also adds the annotation uploader for date records. Pure data layer — no UI.

### Task 2.1: Add entity set constants and feature flag guard

**Files:**
- Modify: `spa/dcfg-property-intake/src/intakeApi.js` (around the existing `ES` constant)

- [ ] **Step 1: Read the existing `ES` declaration**

Run `Read` on `spa/dcfg-property-intake/src/intakeApi.js` to locate the `ES` object near line 80–90.

- [ ] **Step 2: Add new entity sets**

Add:
```js
// inside the existing ES object literal
  dates:        'dcfg_intake_dates',
  delegations:  'dcfg_intake_delegations',
```

- [ ] **Step 3: Sanity check the build compiles**

```bash
cd spa/dcfg-property-intake
npm run build
```
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-property-intake/src/intakeApi.js
git commit -m "intakeApi: add entity sets for dates and delegations"
```

### Task 2.2: Date CRUD functions

**Files:**
- Modify: `spa/dcfg-property-intake/src/intakeApi.js`

- [ ] **Step 1: Add `loadDates(sessionId)`**

```js
export async function loadDates(sessionId) {
  if (!USE_DATAVERSE) return [];
  try {
    const r = await apiGet(`/${ES.dates}?$filter=_dcfg_sessionid_value eq ${sessionId} and dcfg_active_flag eq true&$select=dcfg_intake_dateid,dcfg_name,dcfg_due_date,dcfg_category,dcfg_notes,dcfg_location_ref,createdon&$orderby=dcfg_due_date asc`);
    return r.value || [];
  } catch (e) { console.warn('loadDates failed:', e); return []; }
}
```

- [ ] **Step 2: Add `createDate(sessionId, dateObj)`**

```js
export async function createDate(sessionId, d) {
  if (!USE_DATAVERSE) return null;
  const body = {
    dcfg_name:         d.label || 'Untitled date',
    dcfg_due_date:     d.dueDate || null,
    dcfg_category:     d.category ?? 100000004, // Other
    dcfg_notes:        d.notes || '',
    dcfg_location_ref: d.locationRef || '',
    dcfg_active_flag:  true,
    [`dcfg_sessionid@odata.bind`]: `/${ES.sessions}(${sessionId})`,
  };
  try {
    const created = await apiPostReturn(`/${ES.dates}`, body);
    return created; // { dcfg_intake_dateid, ... }
  } catch (e) { console.warn('createDate failed:', e); return null; }
}
```

- [ ] **Step 3: Add `updateDate(dateId, patch)`**

```js
export async function updateDate(dateId, patch) {
  if (!USE_DATAVERSE || !dateId) return false;
  try {
    await apiPatch(`/${ES.dates}(${dateId})`, patch);
    return true;
  } catch (e) { console.warn('updateDate failed:', e); return false; }
}
```

- [ ] **Step 4: Add `softDeleteDate(dateId)`**

```js
export async function softDeleteDate(dateId) {
  return updateDate(dateId, { dcfg_active_flag: false });
}
```

- [ ] **Step 5: Add `uploadDateAttachment(dateId, file)`**

```js
export async function uploadDateAttachment(dateId, file) {
  if (!USE_DATAVERSE || !file || !dateId) return false;
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = async () => {
      const base64 = reader.result.split(',')[1];
      try {
        const token = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
        const r = await fetch('/_api/annotations', {
          method: 'POST',
          headers: {
            'Content-Type':             'application/json',
            'Accept':                   'application/json',
            '__RequestVerificationToken': token || '',
          },
          credentials: 'same-origin',
          body: JSON.stringify({
            subject:      file.name,
            filename:     file.name,
            mimetype:     file.type,
            documentbody: base64,
            [`objectid_dcfg_intake_date@odata.bind`]: `/${ES.dates}(${dateId})`,
          }),
        });
        resolve(r.ok);
      } catch (e) { console.warn('uploadDateAttachment failed:', e); resolve(false); }
    };
    reader.readAsDataURL(file);
  });
}
```

- [ ] **Step 6: Build check**

```bash
cd spa/dcfg-property-intake && npm run build
```

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-property-intake/src/intakeApi.js
git commit -m "intakeApi: add CRUD + annotation upload for dcfg_intake_date"
```

### Task 2.3: Delegation CRUD functions

**Files:**
- Modify: `spa/dcfg-property-intake/src/intakeApi.js`

- [ ] **Step 1: Add `loadDelegations(sessionId)`**

```js
export async function loadDelegations(sessionId) {
  if (!USE_DATAVERSE) return [];
  try {
    const r = await apiGet(`/${ES.delegations}?$filter=_dcfg_sessionid_value eq ${sessionId} and dcfg_active_flag eq true&$select=dcfg_intake_delegationid,dcfg_name,dcfg_delegate_email,dcfg_sender_name,dcfg_sender_email,dcfg_card_scope,dcfg_personal_note,dcfg_sent_at,createdon&$orderby=createdon desc`);
    return r.value || [];
  } catch (e) { console.warn('loadDelegations failed:', e); return []; }
}
```

- [ ] **Step 2: Add `createDelegation(sessionId, delObj)`**

```js
export async function createDelegation(sessionId, d) {
  if (!USE_DATAVERSE) return null;
  const body = {
    dcfg_name:           d.delegateName,
    dcfg_delegate_email: d.delegateEmail,
    dcfg_sender_name:    d.senderName,
    dcfg_sender_email:   d.senderEmail,
    dcfg_card_scope:     d.cardScope ?? 100000004, // All
    dcfg_personal_note:  d.personalNote || '',
    dcfg_active_flag:    true,
    [`dcfg_sessionid@odata.bind`]: `/${ES.sessions}(${sessionId})`,
  };
  try {
    return await apiPostReturn(`/${ES.delegations}`, body);
  } catch (e) { console.warn('createDelegation failed:', e); return null; }
}
```

- [ ] **Step 3: Add `softDeleteDelegation(delegationId)`**

```js
export async function softDeleteDelegation(delegationId) {
  if (!USE_DATAVERSE || !delegationId) return false;
  try {
    await apiPatch(`/${ES.delegations}(${delegationId})`, { dcfg_active_flag: false });
    return true;
  } catch (e) { console.warn('softDeleteDelegation failed:', e); return false; }
}
```

- [ ] **Step 4: Build + smoke in browser console**

```bash
cd spa/dcfg-property-intake && npm run dev
```
Open the dev URL, log in with demo code, open devtools console, run:
```js
import('./src/intakeApi.js').then(m => m.loadDelegations('00000000-0000-0000-0000-000000000000').then(console.log));
```
Expected: `[]` (empty array) — confirms the API surface is callable.

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-property-intake/src/intakeApi.js
git commit -m "intakeApi: add CRUD for dcfg_intake_delegation"
```

### Chunk 2 complete

API layer for both new tables is in place. All UI chunks below can call these functions.

---

## Chunk 3: Storage layer and shell refactor

Swap the tab shell for hash-routed dashboard. Add dates/delegations to the localStorage cache. Retire `AuthorizedUsers.jsx`.

### Task 3.1: Add `createEmptyDate()` and extend `createEmptyProvider()`

**Files:**
- Modify: `spa/dcfg-property-intake/src/storage.js`

- [ ] **Step 1: Add helper**

```js
export function createEmptyDate() {
  return {
    id: crypto.randomUUID(),
    label: '',
    dueDate: '',
    category: 100000004, // Other
    notes: '',
    locationRef: '',
    _dataverseId: null,
    _attachmentName: null,
  };
}
```

- [ ] **Step 2: Extend `createEmptyProvider()` return object**

Add `dates: []` and `delegations: []` to the returned object literal.

- [ ] **Step 3: Add localStorage sender-identity helpers**

```js
const SENDER_KEY = 'concierge_sender_identity';

export function loadSenderIdentity() {
  try {
    const raw = localStorage.getItem(SENDER_KEY);
    return raw ? JSON.parse(raw) : { senderName: '', senderEmail: '' };
  } catch { return { senderName: '', senderEmail: '' }; }
}

export function saveSenderIdentity({ senderName, senderEmail }) {
  try { localStorage.setItem(SENDER_KEY, JSON.stringify({ senderName, senderEmail })); } catch {}
}
```

- [ ] **Step 4: Build check**

```bash
cd spa/dcfg-property-intake && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-property-intake/src/storage.js
git commit -m "storage: add dates/delegations arrays and sender identity helpers"
```

### Task 3.2: Hash routing hook

**Files:**
- Create: `spa/dcfg-property-intake/src/useHashRoute.js`
- Create: `spa/dcfg-property-intake/test/useHashRoute.test.js`

- [ ] **Step 1: Write the failing test**

```js
// test/useHashRoute.test.js
import { renderHook, act } from '@testing-library/react';
import { useHashRoute } from '../src/useHashRoute.js';

describe('useHashRoute', () => {
  beforeEach(() => { window.location.hash = ''; });

  it('returns the current hash path (default /)', () => {
    const { result } = renderHook(() => useHashRoute());
    expect(result.current.path).toBe('/');
  });

  it('reacts to hashchange events', () => {
    const { result } = renderHook(() => useHashRoute());
    act(() => { window.location.hash = '#/home/vendors'; window.dispatchEvent(new HashChangeEvent('hashchange')); });
    expect(result.current.path).toBe('/home/vendors');
  });

  it('navigate() updates the hash', () => {
    const { result } = renderHook(() => useHashRoute());
    act(() => { result.current.navigate('/home/dates'); });
    expect(window.location.hash).toBe('#/home/dates');
  });
});
```

- [ ] **Step 2: Run it — expect FAIL**

```bash
cd spa/dcfg-property-intake && npm test -- useHashRoute
```
Expected: Module not found.

- [ ] **Step 3: Implement the hook**

```js
// src/useHashRoute.js
import { useState, useEffect, useCallback } from 'react';

function currentPath() {
  const h = window.location.hash || '#/';
  return h.startsWith('#') ? h.slice(1) : h;
}

export function useHashRoute() {
  const [path, setPath] = useState(currentPath());
  useEffect(() => {
    const onChange = () => setPath(currentPath());
    window.addEventListener('hashchange', onChange);
    return () => window.removeEventListener('hashchange', onChange);
  }, []);
  const navigate = useCallback((to) => {
    window.location.hash = to.startsWith('/') ? to : `/${to}`;
  }, []);
  return { path, navigate };
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
npm test -- useHashRoute
```

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-property-intake/src/useHashRoute.js spa/dcfg-property-intake/test/useHashRoute.test.js
git commit -m "spa: minimal hash routing hook"
```

### Task 3.3: `HomeDashboard.jsx`

**Files:**
- Create: `spa/dcfg-property-intake/src/HomeDashboard.jsx`

- [ ] **Step 1: Write the component**

```jsx
import React from 'react';
import { T } from './tokens.js';

const CARDS = [
  { key: 'vendors',   path: '/home/vendors',   icon: '🔧', title: 'Vendors',         desc: 'Who do you already use? HVAC, electrical, fire/life safety, pest, pool, elevator, roofing.',               border: '#2563eb' },
  { key: 'dates',     path: '/home/dates',     icon: '📅', title: 'Important Dates', desc: 'Upcoming inspections, cert expirations, contract anniversaries — attach the file that proves it.', border: '#d97706' },
  { key: 'locations', path: '/home/locations', icon: '📍', title: 'Location Details',desc: 'Address, entry time, site contact, lockbox, basic systems.',                                            border: '#059669' },
  { key: 'documents', path: '/home/documents', icon: '📄', title: 'Documents',       desc: 'Floor plans, insurance COI, W-9s, manuals — anything not tied to a specific date.',                border: '#7c3aed' },
];

export default function HomeDashboard({ data, navigate, onDelegate }) {
  const counts = {
    vendors:   (data?.vendors?.length) || 0,
    dates:     (data?.dates?.length) || 0,
    locations: (data?.properties?.length) || 0,
    documents: (data?.documents?.length) || 0,
  };

  return (
    <div style={{ padding: '28px 20px', maxWidth: 780, margin: '0 auto' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 16 }}>
        {CARDS.map(c => (
          <div key={c.key} data-testid={`card-${c.key}`} onClick={() => navigate(c.path)} style={{
            background: 'white', borderRadius: 12, padding: 22, cursor: 'pointer',
            boxShadow: '0 2px 8px rgba(0,0,0,0.06)', borderTop: `4px solid ${c.border}`,
          }}>
            <div style={{ fontSize: 32 }}>{c.icon}</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: T.blue, margin: '6px 0' }}>{c.title}</div>
            <div style={{ fontSize: 13, color: T.textLight, lineHeight: 1.45 }}>{c.desc}</div>
            <div style={{ marginTop: 14, paddingTop: 12, borderTop: `1px solid ${T.border}`, fontSize: 12, color: T.textLight, display: 'flex', justifyContent: 'space-between' }}>
              <span>{counts[c.key]} {c.key === 'locations' ? 'locations' : c.key}</span>
              <button data-testid={`delegate-${c.key}`} onClick={(e) => { e.stopPropagation(); onDelegate(c.key); }} style={{ background: 'none', border: 'none', color: T.blue, cursor: 'pointer', fontSize: 12, textDecoration: 'underline' }}>
                Delegate
              </button>
            </div>
          </div>
        ))}
      </div>
      <div style={{ textAlign: 'center', color: T.textLight, fontSize: 12, marginTop: 24 }}>
        Progress saves automatically. Come back any time.
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-property-intake/src/HomeDashboard.jsx
git commit -m "spa: HomeDashboard 4-card landing component"
```

### Task 3.4: Refactor `App.jsx` — remove tabs, wire routing

**Files:**
- Modify: `spa/dcfg-property-intake/src/App.jsx`
- Create: `spa/dcfg-property-intake/src/ConciergeHeader.jsx`
- Create: `scratch/app-before-dashboard-refactor.jsx` (snapshot for Task 6.1)
- Delete: `spa/dcfg-property-intake/src/AuthorizedUsers.jsx`

**File size note:** `App.jsx` is already large and after this refactor will add hash routing, modal state, dates/delegations loading, and screen switching. Split `ConciergeHeader` out to its own file (below) to keep `App.jsx` reviewable. If `App.jsx` still exceeds ~600 lines after the refactor, factor additional pieces (e.g. the session-load useEffect) into a hook in a follow-up — out of scope for this task.

- [ ] **Step 1: Snapshot pre-refactor `App.jsx` for Task 6.1 reuse**

```bash
mkdir -p scratch
git show HEAD:spa/dcfg-property-intake/src/App.jsx > scratch/app-before-dashboard-refactor.jsx
```

Task 6.1 copies the mobile/desktop location list/detail rendering from this snapshot into `LocationsScreen.jsx`.

- [ ] **Step 2: Remove the `TABS` array and tab state**

Delete the `const [tab, setTab] = useState('locations');` line and the `TABS` const.

- [ ] **Step 2: Import the new modules**

Add at top:
```js
import HomeDashboard from './HomeDashboard.jsx';
import VendorsScreen from './VendorsScreen.jsx';
import DatesScreen from './DatesScreen.jsx';
import LocationsScreen from './LocationsScreen.jsx';
import DocumentsScreen from './DocumentsScreen.jsx';
import DelegateModal from './DelegateModal.jsx';
import FeedbackModal from './FeedbackModal.jsx';
import { useHashRoute } from './useHashRoute.js';
import { loadDates, loadDelegations } from './intakeApi.js';
```

Remove:
```js
import AuthorizedUsers from './AuthorizedUsers.jsx';
```

- [ ] **Step 3: Renumber this step** — now labelled Step 3 relative to the snapshot step above. Add route state + delegation/feedback modal state:

```jsx
const { path, navigate } = useHashRoute();
const [delegateOpen, setDelegateOpen] = useState(false);
const [delegateScope, setDelegateScope] = useState(null); // null = global
const [feedbackOpen, setFeedbackOpen] = useState(false);
```

- [ ] **Step 4: Extend session-load to parallel-load dates and delegations**

In `handleLogin`, replace the sequential `loadProperties`/`loadVendors`/`loadAuthUsers` calls with a `Promise.all` block:

```jsx
const [props, vendors, dates, delegations] = await Promise.all([
  loadProperties(session.dcfg_intake_sessionid),
  loadVendors(session.dcfg_intake_sessionid),
  loadDates(session.dcfg_intake_sessionid),
  loadDelegations(session.dcfg_intake_sessionid),
]);
if (props) {
  const formProps = props.map(dataverseToForm);
  setCode(upper);
  setProviderName(session.dcfg_provider_name);
  setData({
    properties:   formProps,
    vendors:      vendors || [],
    dates:        dates || [],
    delegations:  delegations || [],
    expiresAt:    session.dcfg_expires_at,
    lastModified: new Date().toISOString(),
    _sessionId:   session.dcfg_intake_sessionid,
    _source:      'dataverse',
    documents:    [],
  });
  setShowWelcome(true);
  return;
}
```

The old `loadAuthUsers` call is dropped — `AuthorizedUsers.jsx` is retired.

- [ ] **Step 5: Replace the tab shell JSX with route-driven JSX**

Delete the entire mobile/desktop tab shell and replace with:

```jsx
return (
  <div style={{ minHeight: '100vh', background: T.bg }}>
    {offline && (
      <div style={{ background: '#FEF3C7', color: '#92400E', padding: '8px 12px', fontSize: 12, textAlign: 'center' }}>
        Saving locally — we'll sync when you're back online
      </div>
    )}
    <ConciergeHeader
      providerName={providerName}
      onHome={() => navigate('/home')}
      onGlobalDelegate={() => { setDelegateScope(null); setDelegateOpen(true); }}
      onFeedback={() => setFeedbackOpen(true)}
      showBack={path !== '/home' && path !== '/'}
    />
    {(path === '/home' || path === '/') && (
      <HomeDashboard data={data} navigate={navigate} onDelegate={(scope) => { setDelegateScope(scope); setDelegateOpen(true); }} />
    )}
    {path === '/home/vendors'   && <VendorsScreen data={data} updateData={updateData} sessionId={data._sessionId} />}
    {path === '/home/dates'     && <DatesScreen data={data} updateData={updateData} sessionId={data._sessionId} />}
    {path === '/home/locations' && <LocationsScreen data={data} setData={setData} selectedPropId={selectedPropId} selectProperty={selectProperty} updateProperty={updateProperty} fieldConfig={fieldConfig} locationTypes={locationTypeNames} />}
    {path === '/home/documents' && <DocumentsScreen data={data} addDocument={addDocument} />}
    {delegateOpen && <DelegateModal scope={delegateScope} sessionId={data._sessionId} onClose={() => setDelegateOpen(false)} onCreated={(row) => updateData(prev => ({ ...prev, delegations: [...(prev.delegations || []), row] }))} />}
    {feedbackOpen && <FeedbackModal sessionId={data._sessionId} onClose={() => setFeedbackOpen(false)} />}
  </div>
);
```

`ConciergeHeader` is defined inline or in a small component file — see Task 3.5.

- [ ] **Step 6: Delete `AuthorizedUsers.jsx`**

```bash
git rm spa/dcfg-property-intake/src/AuthorizedUsers.jsx
```

- [ ] **Step 7: Build check**

```bash
cd spa/dcfg-property-intake && npm run build
```
Expected: Build fails only because screens are stubs — that's fine, we'll stub them next.

- [ ] **Step 8: Stub each new screen component with a one-line placeholder**

Create each screen file as a stub returning a div with its name so the build passes:

```jsx
// src/VendorsScreen.jsx (stub)
import React from 'react';
export default function VendorsScreen() { return <div style={{padding:20}}>Vendors screen</div>; }
```

Repeat for `DatesScreen.jsx`, `LocationsScreen.jsx`, `DocumentsScreen.jsx`, `DelegateModal.jsx`, `FeedbackModal.jsx` — all stubs.

- [ ] **Step 9: Build check**

```bash
npm run build
```
Expected: Build succeeds.

- [ ] **Step 10: Smoke in dev**

```bash
npm run dev
```
Visit the dev URL, log in with demo code, click each card — each navigates to the stub screen and the header's back button returns to `/home`.

- [ ] **Step 11: Commit**

```bash
git add spa/dcfg-property-intake/src/
git rm spa/dcfg-property-intake/src/AuthorizedUsers.jsx
git commit -m "spa: swap tab shell for hash-routed 4-card dashboard (stubbed screens)"
```

### Task 3.5: `ConciergeHeader.jsx` — dedicated file

**Files:**
- Create: `spa/dcfg-property-intake/src/ConciergeHeader.jsx`

- [ ] **Step 1: Write the component**

```jsx
import React, { useState } from 'react';
import { T } from './tokens.js';

export default function ConciergeHeader({ providerName, onHome, onGlobalDelegate, onFeedback, showBack, delegations = [], onRevoke }) {
  const [helpersOpen, setHelpersOpen] = useState(false);
  const activeDelegations = (delegations || []).filter(d => d.dcfg_active_flag !== false);

  return (
    <div style={{ background: T.blue, color: 'white', padding: '12px 18px', display: 'flex', alignItems: 'center', gap: 10 }}>
      {showBack && (
        <button data-testid="header-back" onClick={onHome} style={backBtn}>← Home</button>
      )}
      <div>
        <div style={{ fontSize: 15, fontWeight: 700 }}>{providerName}</div>
        <div style={{ fontSize: 11, opacity: 0.7 }}>Onboarding Concierge</div>
      </div>
      <div style={{ marginLeft: 'auto', display: 'flex', gap: 8, position: 'relative' }}>
        <button data-testid="header-feedback" onClick={onFeedback} style={pill}>💬 Give Feedback</button>
        <button data-testid="header-invite" onClick={() => { onGlobalDelegate(); }} style={pill}>📧 Invite Helpers</button>
        {activeDelegations.length > 0 && (
          <button data-testid="header-helpers-toggle" onClick={() => setHelpersOpen(!helpersOpen)} style={pill}>
            {activeDelegations.length} helper{activeDelegations.length === 1 ? '' : 's'}
          </button>
        )}
        {helpersOpen && (
          <div data-testid="helpers-dropdown" style={dropdown}>
            {activeDelegations.map(d => (
              <div key={d.dcfg_intake_delegationid} style={helperRow}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 600, color: T.blue }}>{d.dcfg_name}</div>
                  <div style={{ fontSize: 11, color: T.textLight }}>{d.dcfg_delegate_email}</div>
                </div>
                <button data-testid={`revoke-${d.dcfg_intake_delegationid}`} onClick={() => onRevoke(d.dcfg_intake_delegationid)} style={{ background: 'none', border: 'none', color: T.red, fontSize: 11, cursor: 'pointer' }}>Revoke</button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

const pill      = { background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)', color: 'white', padding: '6px 12px', borderRadius: 20, fontSize: 12, fontWeight: 600, cursor: 'pointer' };
const backBtn   = { background: 'none', border: 'none', color: 'white', fontSize: 13, cursor: 'pointer', padding: 0, marginRight: 6 };
const dropdown  = { position: 'absolute', top: 40, right: 0, background: 'white', boxShadow: '0 4px 16px rgba(0,0,0,0.15)', borderRadius: 8, width: 280, maxHeight: 320, overflow: 'auto', zIndex: 50 };
const helperRow = { display: 'flex', alignItems: 'center', padding: '10px 14px', borderBottom: '1px solid #f1f5f9' };
```

The component takes `delegations` and `onRevoke` props so the header owns the "Invited helpers" dropdown — there's no separate revoke UI task. Wire `onRevoke` in `App.jsx` to call `softDeleteDelegation(id)` from `intakeApi.js` and update local state.

- [ ] **Step 2: Commit in same commit as Task 3.4**

```bash
git add spa/dcfg-property-intake/src/ConciergeHeader.jsx
git commit -m "spa: ConciergeHeader with feedback, invite helpers, revoke dropdown"
```

### Chunk 3 complete

Shell is the new dashboard. All cards route to stubs. Dates/delegations load and persist in state. Next chunks fill in the stubs.

---

## Chunk 4: Dates and Vendors screens (with spreadsheet upload)

The two largest new screens. Dates is brand new. Vendors reuses `VendorList` and adds the spreadsheet modal.

### Task 4.1: `DatesScreen.jsx`

**Files:**
- Modify: `spa/dcfg-property-intake/src/DatesScreen.jsx` (replace stub)

- [ ] **Step 1: Write the component**

```jsx
import React, { useState } from 'react';
import { T } from './tokens.js';
import { createEmptyDate } from './storage.js';
import { createDate, updateDate, softDeleteDate, uploadDateAttachment, USE_DATAVERSE } from './intakeApi.js';

const CATEGORIES = [
  { value: 100000000, label: 'Inspection' },
  { value: 100000001, label: 'Cert Expiration' },
  { value: 100000002, label: 'Contract Anniversary' },
  { value: 100000003, label: 'Insurance' },
  { value: 100000004, label: 'Other' },
];

export default function DatesScreen({ data, updateData, sessionId }) {
  const dates = data?.dates || [];
  const [busyId, setBusyId] = useState(null);

  const add = async () => {
    const d = createEmptyDate();
    updateData(prev => ({ ...prev, dates: [...(prev.dates || []), d] }));
    if (USE_DATAVERSE && sessionId) {
      const created = await createDate(sessionId, d);
      if (created?.dcfg_intake_dateid) {
        updateData(prev => ({
          ...prev,
          dates: prev.dates.map(x => x.id === d.id ? { ...x, _dataverseId: created.dcfg_intake_dateid } : x),
        }));
      }
    }
  };

  const updateField = async (id, field, value) => {
    const next = dates.map(x => x.id === id ? { ...x, [field]: value } : x);
    updateData(prev => ({ ...prev, dates: next }));
    const row = next.find(x => x.id === id);
    if (USE_DATAVERSE && row?._dataverseId) {
      const dvPatch = {};
      if (field === 'label')       dvPatch.dcfg_name         = value;
      if (field === 'dueDate')     dvPatch.dcfg_due_date     = value;
      if (field === 'category')    dvPatch.dcfg_category     = value;
      if (field === 'notes')       dvPatch.dcfg_notes        = value;
      if (field === 'locationRef') dvPatch.dcfg_location_ref = value;
      if (Object.keys(dvPatch).length) await updateDate(row._dataverseId, dvPatch);
    }
  };

  const remove = async (id) => {
    const row = dates.find(x => x.id === id);
    updateData(prev => ({ ...prev, dates: prev.dates.filter(x => x.id !== id) }));
    if (USE_DATAVERSE && row?._dataverseId) await softDeleteDate(row._dataverseId);
  };

  const onFile = async (id, file) => {
    const row = dates.find(x => x.id === id);
    if (!row?._dataverseId) { alert('Please wait for the row to save before attaching a file.'); return; }
    setBusyId(id);
    const ok = await uploadDateAttachment(row._dataverseId, file);
    setBusyId(null);
    if (ok) {
      updateData(prev => ({ ...prev, dates: prev.dates.map(x => x.id === id ? { ...x, _attachmentName: file.name } : x) }));
    } else {
      alert('File upload failed. Try again.');
    }
  };

  return (
    <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
      <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 4px' }}>Important Dates</h2>
      <p style={{ color: T.textLight, fontSize: 14, margin: '0 0 20px' }}>Add inspection deadlines, cert expirations, contract anniversaries — anything Decades should know about.</p>
      <button data-testid="add-date" onClick={add} style={{ background: T.blueMid, color: T.blueDeep, border: 'none', padding: '10px 18px', borderRadius: 8, fontWeight: 600, cursor: 'pointer', marginBottom: 16 }}>+ Add a date</button>
      {dates.length === 0 && <div style={{ color: T.textLight, fontSize: 14, padding: 20, textAlign: 'center' }}>No dates yet.</div>}
      {dates.map(d => (
        <div key={d.id} data-testid={`date-row-${d.id}`} style={{ background: 'white', borderRadius: 10, padding: 16, marginBottom: 12, border: `1px solid ${T.border}` }}>
          <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr', gap: 10, marginBottom: 10 }}>
            <input data-testid="date-label" value={d.label} onChange={e => updateField(d.id, 'label', e.target.value)} placeholder="Label (e.g. Fire marshal inspection)" style={fieldStyle} />
            <input type="date" data-testid="date-due" value={d.dueDate} onChange={e => updateField(d.id, 'dueDate', e.target.value)} style={fieldStyle} />
            <select data-testid="date-category" value={d.category} onChange={e => updateField(d.id, 'category', Number(e.target.value))} style={fieldStyle}>
              {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <textarea data-testid="date-notes" value={d.notes} onChange={e => updateField(d.id, 'notes', e.target.value)} placeholder="Notes (optional)" rows={2} style={{ ...fieldStyle, width: '100%', fontFamily: T.fBody, resize: 'vertical' }} />
          <div style={{ display: 'flex', alignItems: 'center', marginTop: 10, gap: 10 }}>
            <label data-testid="date-upload" style={{ fontSize: 12, color: T.blue, cursor: 'pointer', textDecoration: 'underline' }}>
              {busyId === d.id ? 'Uploading…' : d._attachmentName ? `📎 ${d._attachmentName}` : '📎 Attach file'}
              <input type="file" onChange={e => e.target.files[0] && onFile(d.id, e.target.files[0])} style={{ display: 'none' }} />
            </label>
            <button data-testid="date-delete" onClick={() => remove(d.id)} style={{ marginLeft: 'auto', background: 'none', border: 'none', color: T.red, cursor: 'pointer', fontSize: 12 }}>Remove</button>
          </div>
        </div>
      ))}
    </div>
  );
}

const fieldStyle = { padding: '8px 10px', border: '1px solid #cbd5e1', borderRadius: 6, fontSize: 14, boxSizing: 'border-box' };
```

- [ ] **Step 2: Build check**

```bash
cd spa/dcfg-property-intake && npm run build
```

- [ ] **Step 3: Manual smoke**

```bash
npm run dev
```
Log in, click Important Dates card, add a row, fill label+date, add notes, attach a file, delete a row. Verify persistence on reload.

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-property-intake/src/DatesScreen.jsx
git commit -m "spa: DatesScreen with file attachment per row"
```

### Task 4.2: `xlsx` dependency and parser

**Files:**
- Modify: `spa/dcfg-property-intake/package.json`
- Create: `spa/dcfg-property-intake/src/vendorSpreadsheetParser.js`
- Create: `spa/dcfg-property-intake/test/vendorSpreadsheetParser.test.js`
- Create fixtures: `test/fixtures/vendor-template-happy.xlsx`, `test/fixtures/vendor-template-bad-headers.xlsx`, `test/fixtures/vendor-template-bad-rows.xlsx`

- [ ] **Step 1: Install `xlsx` with exact version pin**

```bash
cd spa/dcfg-property-intake
npm install --save-exact xlsx@0.20.1
```
Exact pin (no caret) — matches spec intent.

- [ ] **Step 2: Generate fixture files**

Use a small Node script to emit the three test fixtures:

```js
// scripts/concierge/gen-fixture-sheets.mjs
import XLSX from 'xlsx';
import { mkdirSync, writeFileSync } from 'fs';

const outDir = 'spa/dcfg-property-intake/test/fixtures';
mkdirSync(outDir, { recursive: true });

// Happy
const happy = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(happy, XLSX.utils.aoa_to_sheet([
  ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'],
  ['Acme HVAC','HVAC','Jane Doe','555-111-2222','jane@acme.com','2025-01-01','2026-01-01','Monthly PM'],
  ['Blue Fire','Fire/Life Safety','Bob Smith','555-333-4444','bob@bluefire.com','','','Annual inspection'],
]), 'Vendors');
XLSX.writeFile(happy, `${outDir}/vendor-template-happy.xlsx`);

// Bad headers
const bad1 = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(bad1, XLSX.utils.aoa_to_sheet([
  ['Name','Type','Email'], // missing required 'Vendor Name' and 'Trade'
  ['Acme','HVAC','a@b.com'],
]), 'Vendors');
XLSX.writeFile(bad1, `${outDir}/vendor-template-bad-headers.xlsx`);

// Bad rows
const bad2 = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(bad2, XLSX.utils.aoa_to_sheet([
  ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'],
  ['', 'HVAC', '', '', '', '', '', ''],           // missing name
  ['Acme', '', '', '', '', '', '', ''],           // missing trade
  ['Beta', 'Fire', '', '', 'not-an-email', '', '', ''], // bad email
  ['OK Co', 'HVAC', 'Pat', '555', 'p@x.com', '', '', ''], // ok
]), 'Vendors');
XLSX.writeFile(bad2, `${outDir}/vendor-template-bad-rows.xlsx`);

// Production template — headers only, no data rows — the file users download
const templateDir = 'spa/dcfg-property-intake/public/templates';
mkdirSync(templateDir, { recursive: true });
const tpl = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(tpl, XLSX.utils.aoa_to_sheet([
  ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'],
]), 'Vendors');
XLSX.writeFile(tpl, `${templateDir}/decades-vendor-intake.xlsx`);
```

Run: `node scripts/concierge/gen-fixture-sheets.mjs`

- [ ] **Step 3: Write the parser tests**

```js
// test/vendorSpreadsheetParser.test.js
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { parseVendorWorkbook } from '../src/vendorSpreadsheetParser.js';

const load = (name) => new Uint8Array(readFileSync(`test/fixtures/${name}`));

describe('parseVendorWorkbook', () => {
  it('parses a happy-path sheet', () => {
    const result = parseVendorWorkbook(load('vendor-template-happy.xlsx'));
    expect(result.error).toBeNull();
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0].vendorName).toBe('Acme HVAC');
    expect(result.rows[0].status).toBe('ok');
  });

  it('rejects when required headers missing', () => {
    const result = parseVendorWorkbook(load('vendor-template-bad-headers.xlsx'));
    expect(result.error).toMatch(/missing required columns/i);
    expect(result.rows).toHaveLength(0);
  });

  it('flags per-row errors without hard-blocking the sheet', () => {
    const result = parseVendorWorkbook(load('vendor-template-bad-rows.xlsx'));
    expect(result.error).toBeNull();
    expect(result.rows.filter(r => r.status === 'error')).toHaveLength(3);
    expect(result.rows.filter(r => r.status === 'ok')).toHaveLength(1);
  });

  it('enforces the 500-row cap after parse', async () => {
    const XLSX = await import('xlsx');
    const headers = ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'];
    const rows = [headers];
    for (let i = 0; i < 501; i++) rows.push([`Vendor ${i}`, 'HVAC', '', '', '', '', '', '']);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(rows), 'Vendors');
    const buf = XLSX.write(wb, { type: 'array', bookType: 'xlsx' });
    const result = parseVendorWorkbook(new Uint8Array(buf));
    expect(result.error).toMatch(/too large/i);
    expect(result.rows).toHaveLength(0);
  });
});
```

- [ ] **Step 4: Run tests — expect FAIL**

```bash
npm test -- vendorSpreadsheetParser
```

- [ ] **Step 5: Implement the parser**

```js
// src/vendorSpreadsheetParser.js
import * as XLSX from 'xlsx';

const REQUIRED = ['Vendor Name', 'Trade'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_ROWS = 500;

export function parseVendorWorkbook(arrayBuffer) {
  let wb;
  try { wb = XLSX.read(arrayBuffer, { type: 'array' }); }
  catch { return { error: 'Could not read the spreadsheet file.', rows: [] }; }

  const sheet = wb.Sheets[wb.SheetNames[0]];
  if (!sheet) return { error: 'The spreadsheet looks empty.', rows: [] };

  const raw = XLSX.utils.sheet_to_json(sheet, { defval: '', raw: false });
  if (raw.length === 0) return { error: 'The spreadsheet looks empty.', rows: [] };
  if (raw.length > MAX_ROWS) return { error: `Spreadsheet too large (${raw.length} rows, max ${MAX_ROWS}). Please split into smaller files.`, rows: [] };

  const headers = Object.keys(raw[0]);
  const missing = REQUIRED.filter(h => !headers.includes(h));
  if (missing.length) return { error: `Missing required columns: ${missing.join(', ')}`, rows: [] };

  const rows = raw.map((r, i) => {
    const errors = [];
    const warnings = [];
    const vendorName  = String(r['Vendor Name'] || '').trim();
    const trade       = String(r['Trade'] || '').trim();
    const contactName = String(r['Contact Name'] || '').trim();
    const contactPhone= String(r['Contact Phone'] || '').trim();
    const contactEmail= String(r['Contact Email'] || '').trim();
    const contractStart = parseDateCell(r['Contract Start']);
    const contractEnd   = parseDateCell(r['Contract End']);
    const notes       = String(r['Notes'] || '').trim();

    if (!vendorName) errors.push('Vendor Name is required');
    if (!trade) errors.push('Trade is required');
    if (contactEmail && !EMAIL_RE.test(contactEmail)) errors.push('Contact Email is invalid');
    if (r['Contract Start'] && !contractStart) warnings.push('Contract Start is not a readable date');
    if (r['Contract End']   && !contractEnd)   warnings.push('Contract End is not a readable date');

    const status = errors.length ? 'error' : (warnings.length ? 'warning' : 'ok');
    return { rowNum: i + 2, vendorName, trade, contactName, contactPhone, contactEmail, contractStart, contractEnd, notes, errors, warnings, status };
  });

  return { error: null, rows };
}

function parseDateCell(v) {
  if (!v) return '';
  if (v instanceof Date && !isNaN(v.getTime())) return v.toISOString().slice(0, 10);
  const parsed = new Date(v);
  return isNaN(parsed.getTime()) ? '' : parsed.toISOString().slice(0, 10);
}
```

- [ ] **Step 6: Run tests — expect PASS**

```bash
npm test -- vendorSpreadsheetParser
```

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-property-intake/package.json spa/dcfg-property-intake/package-lock.json spa/dcfg-property-intake/src/vendorSpreadsheetParser.js spa/dcfg-property-intake/test/vendorSpreadsheetParser.test.js spa/dcfg-property-intake/test/fixtures/ scripts/concierge/gen-fixture-sheets.mjs
git commit -m "spa: xlsx parser for vendor intake spreadsheet + tests"
```

### Task 4.3: `VendorSpreadsheetModal.jsx`

**Files:**
- Create: `spa/dcfg-property-intake/src/VendorSpreadsheetModal.jsx`

- [ ] **Step 1: Write the component**

```jsx
import React, { useState } from 'react';
import { T } from './tokens.js';
import { parseVendorWorkbook } from './vendorSpreadsheetParser.js';
import { createVendor, USE_DATAVERSE } from './intakeApi.js';

export default function VendorSpreadsheetModal({ sessionId, onClose, onCommitted }) {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState({}); // rowNum -> bool
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(null); // { done, total }
  const [retry, setRetry] = useState({}); // rowNum -> true if committed, failed

  const onFile = async (file) => {
    if (!file) return;
    setError(''); setRows([]); setSelected({}); setRetry({});
    const buf = await file.arrayBuffer();
    const result = parseVendorWorkbook(new Uint8Array(buf));
    if (result.error) { setError(result.error); return; }
    setRows(result.rows);
    const preselect = {};
    for (const r of result.rows) if (r.status !== 'error') preselect[r.rowNum] = true;
    setSelected(preselect);
  };

  const selectAll    = () => setSelected(Object.fromEntries(rows.filter(r => r.status !== 'error').map(r => [r.rowNum, true])));
  const selectOkOnly = () => setSelected(Object.fromEntries(rows.filter(r => r.status === 'ok').map(r => [r.rowNum, true])));
  const deselectAll  = () => setSelected({});

  const commit = async () => {
    const toAdd = rows.filter(r => selected[r.rowNum] && r.status !== 'error');
    if (toAdd.length === 0) return;
    setBusy(true);
    setProgress({ done: 0, total: toAdd.length });
    const committed = [];
    const failed = { ...retry };
    for (let i = 0; i < toAdd.length; i++) {
      const r = toAdd[i];
      const vendor = {
        id: crypto.randomUUID(),
        vendorName:    r.vendorName,
        serviceProvided: r.trade,
        contactName:   r.contactName,
        contactPhone:  r.contactPhone,
        contactEmail:  r.contactEmail,
        contractStart: r.contractStart,
        contractEnd:   r.contractEnd,
        requiresReBid: '',
      };
      let ok = true;
      if (USE_DATAVERSE && sessionId) {
        const created = await createVendor(sessionId, vendor);
        ok = !!created;
      }
      if (ok) committed.push(vendor);
      else    failed[r.rowNum] = true;
      setProgress({ done: i + 1, total: toAdd.length });
    }
    setRetry(failed);
    setBusy(false);
    if (committed.length > 0) onCommitted(committed);
    if (Object.keys(failed).length === 0) onClose();
  };

  return (
    <div role="dialog" aria-modal="true" style={backdrop} onClick={onClose}>
      <div data-testid="spreadsheet-modal" style={modal} onClick={e => e.stopPropagation()}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, margin: '0 0 4px' }}>Upload a vendor spreadsheet</h3>
        <p style={{ color: T.textLight, fontSize: 13, margin: '0 0 14px' }}>Use the Decades template. Extra columns are ignored. Max 500 rows per file.</p>

        {rows.length === 0 && !error && (
          <label data-testid="file-picker" style={dropzone}>
            <input type="file" accept=".xlsx,.xls" onChange={e => onFile(e.target.files[0])} style={{ display: 'none' }} />
            Click to choose an .xlsx file
          </label>
        )}
        {error && (
          <div data-testid="parse-error" style={errorBox}>
            <div style={{ color: T.red, fontSize: 13 }}>{error}</div>
            <a href="/templates/decades-vendor-intake.xlsx" download style={{ color: T.blue, fontSize: 12, marginTop: 8, display: 'inline-block' }}>Download template</a>
          </div>
        )}

        {rows.length > 0 && (
          <>
            <div style={{ display: 'flex', gap: 8, margin: '10px 0', fontSize: 12 }}>
              <span>Found {rows.length}. OK: {rows.filter(r => r.status==='ok').length} · Warning: {rows.filter(r => r.status==='warning').length} · Error: {rows.filter(r => r.status==='error').length}</span>
              <div style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
                <button data-testid="select-all" onClick={selectAll} style={miniBtn}>Select all</button>
                <button data-testid="select-ok" onClick={selectOkOnly} style={miniBtn}>Only OK</button>
                <button data-testid="deselect-all" onClick={deselectAll} style={miniBtn}>Deselect</button>
              </div>
            </div>
            <div style={{ maxHeight: 320, overflow: 'auto', border: `1px solid ${T.border}`, borderRadius: 6 }}>
              <table style={{ width: '100%', fontSize: 12, borderCollapse: 'collapse' }}>
                <thead style={{ background: '#f8fafc', position: 'sticky', top: 0 }}>
                  <tr><th style={th}></th><th style={th}>Row</th><th style={th}>Vendor</th><th style={th}>Trade</th><th style={th}>Status</th></tr>
                </thead>
                <tbody>
                  {rows.map(r => (
                    <tr key={r.rowNum} data-testid={`preview-row-${r.rowNum}`} style={{ background: retry[r.rowNum] ? '#FEF3C7' : 'white' }}>
                      <td style={td}><input type="checkbox" disabled={r.status === 'error'} checked={!!selected[r.rowNum]} onChange={e => setSelected({ ...selected, [r.rowNum]: e.target.checked })} /></td>
                      <td style={td}>{r.rowNum}</td>
                      <td style={td}>{r.vendorName || <em style={{ color: T.textLight }}>(blank)</em>}</td>
                      <td style={td}>{r.trade || <em style={{ color: T.textLight }}>(blank)</em>}</td>
                      <td style={td}>
                        {retry[r.rowNum] && <span style={{ color: '#92400E' }}>Retry</span>}
                        {!retry[r.rowNum] && r.status === 'ok' && <span style={{ color: '#059669' }}>OK</span>}
                        {!retry[r.rowNum] && r.status === 'warning' && <span title={r.warnings.join('; ')} style={{ color: '#d97706' }}>Warning</span>}
                        {!retry[r.rowNum] && r.status === 'error' && <span title={r.errors.join('; ')} style={{ color: T.red }}>Error</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {progress && <div style={{ marginTop: 10, fontSize: 12, color: T.textLight }}>Adding {progress.done} of {progress.total}…</div>}
          </>
        )}

        <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
          <button data-testid="cancel-upload" onClick={onClose} disabled={busy} style={btnSecondary}>Cancel</button>
          <button data-testid="commit-upload" onClick={commit} disabled={busy || rows.length === 0 || Object.keys(selected).length === 0} style={btnPrimary}>
            {busy ? 'Adding…' : `Add selected to my vendor list`}
          </button>
        </div>
      </div>
    </div>
  );
}

const backdrop     = { position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 };
const modal        = { background: 'white', borderRadius: 12, padding: 24, width: '100%', maxWidth: 720, maxHeight: '90vh', overflow: 'auto' };
const dropzone     = { display: 'block', padding: 32, border: '2px dashed #cbd5e1', borderRadius: 10, textAlign: 'center', cursor: 'pointer', color: '#64748b', fontSize: 14 };
const errorBox     = { padding: 12, background: '#FEF2F2', borderRadius: 8 };
const miniBtn      = { background: 'white', border: '1px solid #cbd5e1', borderRadius: 6, padding: '4px 10px', fontSize: 11, cursor: 'pointer' };
const th           = { textAlign: 'left', padding: '8px 10px', fontWeight: 600, borderBottom: '1px solid #e2e8f0' };
const td           = { padding: '6px 10px', borderBottom: '1px solid #f1f5f9' };
const btnPrimary   = { flex: 1, padding: 10, background: '#2563eb', color: 'white', border: 'none', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
const btnSecondary = { flex: 1, padding: 10, background: 'white', color: '#2563eb', border: '1px solid #cbd5e1', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
```

- [ ] **Step 2: Smoke by hand**

```bash
cd spa/dcfg-property-intake && npm run dev
```

- Log in → Vendors card → Upload spreadsheet
- Upload `test/fixtures/vendor-template-happy.xlsx` → preview shows 2 OK rows → Commit → vendor list grows by 2
- Upload `test/fixtures/vendor-template-bad-headers.xlsx` → error banner with re-template link
- Upload `test/fixtures/vendor-template-bad-rows.xlsx` → preview shows 3 errors (non-committable) + 1 OK → Commit → vendor list grows by 1 only

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-property-intake/src/VendorSpreadsheetModal.jsx
git commit -m "spa: VendorSpreadsheetModal preview-and-commit upload flow"
```

### Task 4.4: `VendorsScreen.jsx` wrapper

**Files:**
- Modify: `spa/dcfg-property-intake/src/VendorsScreen.jsx` (replace stub)

- [ ] **Step 1: Write the wrapper**

```jsx
import React, { useState } from 'react';
import { T } from './tokens.js';
import VendorList from './VendorList.jsx';
import VendorSpreadsheetModal from './VendorSpreadsheetModal.jsx';

export default function VendorsScreen({ data, updateData, sessionId }) {
  const [uploadOpen, setUploadOpen] = useState(false);
  const vendors = data?.vendors || [];

  return (
    <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16, gap: 10 }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: 0 }}>Vendors</h2>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
          <a data-testid="download-template" href="/templates/decades-vendor-intake.xlsx" download style={{ padding: '8px 14px', background: 'white', border: `1px solid ${T.border}`, borderRadius: 8, color: T.blue, textDecoration: 'none', fontSize: 13, fontWeight: 600 }}>Download template</a>
          <button data-testid="upload-spreadsheet" onClick={() => setUploadOpen(true)} style={{ padding: '8px 14px', background: T.blue, color: 'white', border: 'none', borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>Upload spreadsheet</button>
        </div>
      </div>
      <VendorList vendors={vendors} onUpdate={(next) => updateData(prev => ({ ...prev, vendors: next }))} sessionId={sessionId} />
      {uploadOpen && (
        <VendorSpreadsheetModal
          sessionId={sessionId}
          existingVendors={vendors}
          onClose={() => setUploadOpen(false)}
          onCommitted={(newVendors) => updateData(prev => ({ ...prev, vendors: [...(prev.vendors || []), ...newVendors] }))}
        />
      )}
    </div>
  );
}
```

- [ ] **Step 2: Verify the production template was emitted by Task 4.2 Step 2**

```bash
ls spa/dcfg-property-intake/public/templates/decades-vendor-intake.xlsx
```
Expected: file exists. If not, re-run `node scripts/concierge/gen-fixture-sheets.mjs`.

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-property-intake/src/VendorsScreen.jsx spa/dcfg-property-intake/public/templates/decades-vendor-intake.xlsx
git commit -m "spa: VendorsScreen wrapper with template download + upload modal"
```

### Chunk 4 complete

Dates screen fully functional. Vendors screen + spreadsheet upload fully functional. Both cards persist to Dataverse.

---

## Chunk 5: Delegation flow (front-end modal + back-end flow)

### Task 5.1: `DelegateModal.jsx`

**Files:**
- Modify: `spa/dcfg-property-intake/src/DelegateModal.jsx` (replace stub)

- [ ] **Step 1: Write the component**

```jsx
import React, { useState, useEffect } from 'react';
import { T } from './tokens.js';
import { createDelegation } from './intakeApi.js';
import { loadSenderIdentity, saveSenderIdentity } from './storage.js';

const SCOPES = [
  { value: 100000000, label: 'Vendors', key: 'vendors' },
  { value: 100000001, label: 'Dates', key: 'dates' },
  { value: 100000002, label: 'Locations', key: 'locations' },
  { value: 100000003, label: 'Documents', key: 'documents' },
  { value: 100000004, label: 'All', key: 'all' },
];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default function DelegateModal({ scope, sessionId, onClose, onCreated }) {
  const initial = loadSenderIdentity();
  const [senderName, setSenderName]   = useState(initial.senderName || '');
  const [senderEmail, setSenderEmail] = useState(initial.senderEmail || '');
  const [delegateName, setDelegateName]   = useState('');
  const [delegateEmail, setDelegateEmail] = useState('');
  const [note, setNote] = useState('');
  const [cardScope, setCardScope] = useState(scope || 'all');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  const valid = senderName && EMAIL_RE.test(senderEmail) && delegateName && EMAIL_RE.test(delegateEmail);

  const submit = async () => {
    if (!valid) { setErr('Please fill out all fields with a valid email.'); return; }
    setBusy(true); setErr('');
    saveSenderIdentity({ senderName, senderEmail });
    const scopeValue = SCOPES.find(s => s.key === cardScope)?.value ?? 100000004;
    const created = await createDelegation(sessionId, { delegateName, delegateEmail, senderName, senderEmail, personalNote: note, cardScope: scopeValue });
    setBusy(false);
    if (!created) { setErr('Could not send the invite. Try again.'); return; }
    onCreated({ dcfg_intake_delegationid: created.dcfg_intake_delegationid, dcfg_name: delegateName, dcfg_delegate_email: delegateEmail, dcfg_card_scope: scopeValue });
    onClose();
  };

  return (
    <div role="dialog" aria-modal="true" style={backdrop} onClick={onClose}>
      <div data-testid="delegate-modal" style={modal} onClick={e => e.stopPropagation()}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, margin: '0 0 4px' }}>Invite a helper</h3>
        <p style={{ color: T.textLight, fontSize: 13, margin: '0 0 16px' }}>They'll get an email with a link. They use the same access code to log in.</p>

        <Field label="Your name">
          <input data-testid="sender-name" value={senderName} onChange={e => setSenderName(e.target.value)} style={input} />
        </Field>
        <Field label="Your email">
          <input data-testid="sender-email" value={senderEmail} onChange={e => setSenderEmail(e.target.value)} style={input} />
        </Field>
        <hr style={{ border: 0, borderTop: `1px solid ${T.border}`, margin: '12px 0' }} />
        <Field label="Who you're inviting — name">
          <input data-testid="delegate-name" value={delegateName} onChange={e => setDelegateName(e.target.value)} style={input} />
        </Field>
        <Field label="Who you're inviting — email">
          <input data-testid="delegate-email" value={delegateEmail} onChange={e => setDelegateEmail(e.target.value)} style={input} />
        </Field>
        <Field label="What you'd like them to help with">
          <select data-testid="scope-select" value={cardScope} onChange={e => setCardScope(e.target.value)} style={input}>
            {SCOPES.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}
          </select>
        </Field>
        <Field label="Personal note (optional)">
          <textarea data-testid="note" value={note} onChange={e => setNote(e.target.value)} rows={3} style={{ ...input, resize: 'vertical', fontFamily: T.fBody }} />
        </Field>

        {err && <div style={{ color: T.red, fontSize: 13, marginTop: 8 }}>{err}</div>}
        <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
          <button data-testid="cancel" onClick={onClose} disabled={busy} style={btnSecondary}>Cancel</button>
          <button data-testid="send" onClick={submit} disabled={!valid || busy} style={btnPrimary}>{busy ? 'Sending…' : 'Send invite'}</button>
        </div>
      </div>
    </div>
  );
}

const Field = ({ label, children }) => (
  <label style={{ display: 'block', marginBottom: 10 }}>
    <div style={{ fontSize: 12, fontWeight: 600, color: '#334155', marginBottom: 4 }}>{label}</div>
    {children}
  </label>
);

const backdrop = { position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 };
const modal = { background: 'white', borderRadius: 12, padding: 24, width: '100%', maxWidth: 460, maxHeight: '90vh', overflow: 'auto' };
const input = { width: '100%', padding: '8px 10px', border: '1px solid #cbd5e1', borderRadius: 6, fontSize: 14, boxSizing: 'border-box' };
const btnPrimary = { flex: 1, padding: '10px', background: '#2563eb', color: 'white', border: 'none', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
const btnSecondary = { flex: 1, padding: '10px', background: 'white', color: '#2563eb', border: '1px solid #cbd5e1', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
```

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-property-intake/src/DelegateModal.jsx
git commit -m "spa: DelegateModal — sender + delegate capture, localStorage pre-fill"
```

### Task 5.2: Build `dcfg_SendIntakeDelegationInvite` flow (three-step pattern)

**Files:**
- Create: `scripts/concierge/flow-delegate-invite-v1-placeholder.json`
- Create: `scripts/concierge/flow-delegate-invite-v3-final.json`
- Reuse existing: `scripts/flows/Push-FlowDefinition.ps1`, `scripts/flows/Read-FlowDefinition.ps1` (if present) — otherwise fall back to the pac CLI path shown in Step 2

**This follows the DCFG three-step flow pattern per `feedback_flow_build_process.md`.** If `Push-FlowDefinition.ps1` / `Read-FlowDefinition.ps1` don't exist in the repo, use `pac flow export` / manual `Invoke-RestMethod` against the Dataverse `workflows` table as the fallback. Verify existence first:

```bash
ls scripts/flows/Push-FlowDefinition.ps1 scripts/flows/Read-FlowDefinition.ps1 2>/dev/null && echo "helpers present" || echo "helpers missing — use fallback"
```

- [ ] **Step 1: Write the v1 placeholder definition**

Base template — copy the structure from an existing placeholder flow in `scripts/_backups/` (the 2026-04-10 Option B backup `_optionb-4-flow-backup-20260410-145648.json` is a good reference for the Dataverse trigger + scope + retry shape). Trigger: Dataverse "When a row is added" on `dcfg_intake_delegation`.

Key actions in the placeholder (all Compose except the Dataverse ones):

| Action name | Type | Purpose |
|---|---|---|
| `Get_session` | Dataverse List rows | Filter `dcfg_intake_session` by `dcfg_intake_sessionid eq @{triggerOutputs()?['body/_dcfg_sessionid_value']}` |
| `Get_config_from` | Dataverse List rows | Filter `dcfg_configs` by `dcfg_name eq 'intake_delegation_from_address'` |
| `Get_config_url` | Dataverse List rows | Filter `dcfg_configs` by `dcfg_name eq 'concierge_portal_url'` |
| `Build_email_html` | Compose | HTML body template with dynamic tokens for `{senderName}`, `{providerName}`, `{personalNote}`, `{portalUrl}?code={accessCode}`, `{cardScopeLabel}` |
| `Send_email` | Compose (placeholder) | Static object `{ "to": "...", "subject": "...", "body": "..." }` — will be replaced by "Send an email (V2)" action in the manual step |
| `Patch_sent_at` | Dataverse Update row | On `dcfg_intake_delegation`, set `dcfg_sent_at = @{utcNow()}` |
| Outer `Try_scope` / `Catch_scope` | Scope | Run-after `Try_scope` on failure; inside Catch, write a row to `dcfg_audit_logs` with the error |

The v1 JSON file is produced by taking a copy of the backup flow, stripping its actions, and adding the seven steps above as Compose placeholders with the schema names configured. Save as `scripts/concierge/flow-delegate-invite-v1-placeholder.json`.

- [ ] **Step 2: Push v1 to Test (placeholder) — triggers and scaffold only**

```bash
pwsh -File scripts/concierge/Push-FlowDefinition.ps1 -DefinitionFile scripts/concierge/flow-delegate-invite-v1-placeholder.json -FlowName dcfg_SendIntakeDelegationInvite -Env test
```

- [ ] **Step 3: Human step — add Outlook / Office 365 "Send an email (V2)" action manually in Power Automate designer**

Operator opens the flow in designer and swaps the `Send_email` Compose placeholder for a real `Send an email (V2)` action, authenticates the connection, saves. Reply-To uses `dcfg_sender_email` dynamic content.

- [ ] **Step 4: Read back the live definition**

```bash
pwsh -File scripts/concierge/Read-FlowDefinition.ps1 -FlowName dcfg_SendIntakeDelegationInvite -Env test -Output scripts/concierge/flow-delegate-invite-v2-readback.json
```

- [ ] **Step 5: Merge the readback `connectionReferences` into v3 final**

Take the readback file, replace any remaining placeholder bodies with the final definition (retry logic on Scope + run-after failure), keep connection references intact. Save as `flow-delegate-invite-v3-final.json`.

- [ ] **Step 6: Push v3 — do NOT overwrite triggers**

```bash
pwsh -File scripts/concierge/Push-FlowDefinition.ps1 -DefinitionFile scripts/concierge/flow-delegate-invite-v3-final.json -FlowName dcfg_SendIntakeDelegationInvite -Env test -PreserveTriggers
```

- [ ] **Step 7: End-to-end smoke**

From the concierge dev site, send a delegation invite to your own email (`joseph@...`). Verify the email lands in the inbox within 60 seconds. Verify `dcfg_sent_at` is populated on the row. Verify the reply-to is the sender email you typed, not the Decades shared mailbox.

- [ ] **Step 8: Commit**

```bash
git add scripts/concierge/flow-delegate-invite-v1-placeholder.json scripts/concierge/flow-delegate-invite-v3-final.json
git commit -m "flow: dcfg_SendIntakeDelegationInvite — placeholder + final definitions"
```

### Task 5.3: Wire the header revoke dropdown to `softDeleteDelegation`

The Revoke dropdown UI is already built into `ConciergeHeader.jsx` from Task 3.5. This task wires the `onRevoke` callback to actually soft-delete.

**Files:**
- Modify: `spa/dcfg-property-intake/src/App.jsx`

- [ ] **Step 1: Add `onRevoke` handler to `App.jsx` and pass it to `ConciergeHeader`**

```jsx
const handleRevoke = async (delegationId) => {
  const ok = await softDeleteDelegation(delegationId);
  if (ok) {
    updateData(prev => ({
      ...prev,
      delegations: (prev.delegations || []).filter(d => d.dcfg_intake_delegationid !== delegationId),
    }));
  }
};

// in JSX:
<ConciergeHeader
  providerName={providerName}
  onHome={() => navigate('/home')}
  onGlobalDelegate={() => { setDelegateScope(null); setDelegateOpen(true); }}
  onFeedback={() => setFeedbackOpen(true)}
  showBack={path !== '/home' && path !== '/'}
  delegations={data?.delegations || []}
  onRevoke={handleRevoke}
/>
```

Don't forget to add `softDeleteDelegation` to the `intakeApi.js` import list at the top of `App.jsx`.

- [ ] **Step 2: Smoke by hand**

Log in → Invite a helper via the modal → helper appears in the header dropdown → click Revoke → helper disappears → reload page → still gone (confirms Dataverse soft-delete persisted).

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-property-intake/src/App.jsx
git commit -m "spa: wire header revoke dropdown to softDeleteDelegation"
```

### Chunk 5 complete

Delegation flow end-to-end: customer clicks → row written → email sent → delegate clicks link → lands on concierge with the same access code → sees everything.

---

## Chunk 6: Locations, Documents, Feedback, and field config defaults

### Task 6.1: `LocationsScreen.jsx` wrapper

**Files:**
- Modify: `spa/dcfg-property-intake/src/LocationsScreen.jsx` (replace stub)
- Reference: `scratch/app-before-dashboard-refactor.jsx` (snapshot from Task 3.4 Step 1)

- [ ] **Step 1: Locate source logic in the snapshot**

Open `scratch/app-before-dashboard-refactor.jsx` and find the two branches that render locations:
- Mobile: inside `if (mobile)` block, the `tab === 'locations' && !selectedPropId` list rendering and the `selectedPropId && prop` detail rendering
- Desktop: the left rail (location list) + right pane (PropertyForm) inside the `else` block

- [ ] **Step 2: Write the screen**

```jsx
import React from 'react';
import { T } from './tokens.js';
import PropertyForm from './PropertyForm.jsx';

export default function LocationsScreen({ data, selectedPropId, selectProperty, updateProperty, fieldConfig, locationTypes }) {
  const properties = data?.properties || [];
  const selectedProp = properties.find(p => p.id === selectedPropId);

  if (!selectedProp) {
    return (
      <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 16px' }}>Locations</h2>
        {properties.length === 0 && <div style={{ color: T.textLight }}>No locations on file yet.</div>}
        {properties.map(p => (
          <div key={p.id} data-testid={`location-card-${p.id}`} onClick={() => selectProperty(p.id)} style={{ background: 'white', borderRadius: 10, padding: 14, marginBottom: 8, border: `1px solid ${T.border}`, cursor: 'pointer' }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: T.blue }}>{p.upkeepName || p.streetAddress || 'New Location'}</div>
            <div style={{ fontSize: 12, color: T.textLight, marginTop: 2 }}>{p.city ? `${p.city}, ${p.state}` : 'No address yet'}</div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div style={{ padding: '24px 20px', maxWidth: 900, margin: '0 auto' }}>
      <button data-testid="back-to-list" onClick={() => selectProperty(null)} style={{ background: 'none', border: 'none', color: T.blue, cursor: 'pointer', fontSize: 13, marginBottom: 10 }}>← All locations</button>
      <PropertyForm
        property={selectedProp}
        onChange={(field, value) => updateProperty(selectedProp.id, field, value)}
        fieldConfig={fieldConfig}
        locationTypes={locationTypes}
      />
    </div>
  );
}
```

- [ ] **Step 3: Build check**

```bash
cd spa/dcfg-property-intake && npm run build
```

- [ ] **Step 4: Smoke in dev**

Log in → Location Details card → click a location → edit a visible field → verify save → back to list → navigate back via header → return.

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-property-intake/src/LocationsScreen.jsx
git commit -m "spa: LocationsScreen wrapper — list + PropertyForm detail"
```

### Task 6.2: `DocumentsScreen.jsx` wrapper

**Files:**
- Modify: `spa/dcfg-property-intake/src/DocumentsScreen.jsx` (replace stub)

- [ ] **Step 1: Write the wrapper**

```jsx
import React from 'react';
import { T } from './tokens.js';
import DocumentCapture from './DocumentCapture.jsx';

export default function DocumentsScreen({ data, addDocument }) {
  return (
    <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
      <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 4px' }}>Documents</h2>
      <p style={{ color: T.textLight, fontSize: 14, margin: '0 0 20px' }}>Floor plans, insurance COI, W-9s, manuals — anything that isn't tied to a specific date.</p>
      <DocumentCapture documents={data?.documents || []} onAdd={addDocument} />
    </div>
  );
}
```

- [ ] **Step 2: Build + smoke**

```bash
cd spa/dcfg-property-intake && npm run build
```
Then `npm run dev`, log in, click the Documents card, upload a file, reload, verify persistence.

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-property-intake/src/DocumentsScreen.jsx
git commit -m "spa: DocumentsScreen wrapper"
```

### Task 6.3: `FeedbackModal.jsx`

**Files:**
- Modify: `spa/dcfg-property-intake/src/intakeApi.js`
- Modify: `spa/dcfg-property-intake/src/FeedbackModal.jsx` (replace stub)

- [ ] **Step 1: Verify column names in the database bible**

The actual column names for `dcfg_audit_logs` may differ from the assumed `dcfg_action`/`dcfg_context`/`dcfg_actor`. Task 1.0 already validates the three columns exist. If the bible shows different names (e.g. `dcfg_audit_action`, `dcfg_audit_detail`), update the code below to match.

- [ ] **Step 2: Add `submitFeedback` to `intakeApi.js`**

```js
export async function submitFeedback(sessionId, text) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPost(`/dcfg_audit_logs`, {
      dcfg_action:  'Feedback',
      dcfg_context: text,
      dcfg_actor:   `Anonymous (session ${sessionId})`,
    });
    return true;
  } catch (e) { console.warn('submitFeedback failed:', e); return false; }
}
```

- [ ] **Step 3: Write the modal**

```jsx
import React, { useState } from 'react';
import { T } from './tokens.js';
import { submitFeedback } from './intakeApi.js';

export default function FeedbackModal({ sessionId, onClose }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const send = async () => {
    if (!text.trim()) return;
    setBusy(true);
    const ok = await submitFeedback(sessionId, text.trim());
    setBusy(false);
    if (ok) { setSent(true); setTimeout(onClose, 1200); }
    else    { alert('Could not send feedback. Please try again.'); }
  };

  return (
    <div role="dialog" aria-modal="true" style={backdrop} onClick={onClose}>
      <div data-testid="feedback-modal" style={modal} onClick={e => e.stopPropagation()}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, margin: '0 0 4px' }}>Give feedback</h3>
        <p style={{ color: T.textLight, fontSize: 13, margin: '0 0 14px' }}>What's working, what isn't, what's missing. Anything.</p>
        {sent ? (
          <div style={{ padding: 20, textAlign: 'center', color: T.textLight, fontSize: 14 }}>Thanks — we got it.</div>
        ) : (
          <>
            <textarea data-testid="feedback-text" value={text} onChange={e => setText(e.target.value)} rows={6} style={{ width: '100%', padding: 10, border: '1px solid #cbd5e1', borderRadius: 6, fontSize: 14, fontFamily: T.fBody, resize: 'vertical', boxSizing: 'border-box' }} />
            <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
              <button data-testid="feedback-cancel" onClick={onClose} disabled={busy} style={btnSecondary}>Cancel</button>
              <button data-testid="feedback-send" onClick={send} disabled={busy || !text.trim()} style={btnPrimary}>{busy ? 'Sending…' : 'Send'}</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

const backdrop     = { position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 };
const modal        = { background: 'white', borderRadius: 12, padding: 24, width: '100%', maxWidth: 460 };
const btnPrimary   = { flex: 1, padding: 10, background: '#2563eb', color: 'white', border: 'none', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
const btnSecondary = { flex: 1, padding: 10, background: 'white', color: '#2563eb', border: '1px solid #cbd5e1', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
```

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-property-intake/src/FeedbackModal.jsx spa/dcfg-property-intake/src/intakeApi.js
git commit -m "spa: FeedbackModal + submitFeedback audit log writer"
```

### Task 6.4: Seed `dcfg_intake_field_configs` C-cut defaults

**Files:**
- Create: `scripts/concierge/Seed-IntakeFieldConfigDefaults.ps1`

- [ ] **Step 1: Capture before-state**

```powershell
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/dcfg_intake_field_configs?`$select=dcfg_field_key,dcfg_visible,_dcfg_location_type_value" -Headers $h > scripts/_backups/2026-04-11_intake_field_configs-before.json
```

- [ ] **Step 2: Write the seed script**

The script upserts rows for each field listed in the spec's C-cut. Visible = `true` for fields in the C-cut, `false` otherwise. Iterates over all active location types.

C-cut visible fields:
```
streetAddress, city, state, zipCode, homeType, contactPerson, contactPhone,
contactEmail, entryTime, lockBox, lockBoxCode, lockBoxLocation, yearBuilt,
bedrooms, heatingType, pool, generator, garage, septicSystem, solarPanels,
wellWater, fireAlarmSystem
```

Everything else in the existing `intakeFieldKeys.js` list goes to `dcfg_visible = false`.

- [ ] **Step 3: Run the script against Test**

```bash
pwsh -File scripts/concierge/Seed-IntakeFieldConfigDefaults.ps1
```

- [ ] **Step 4: Verify**

Open the Concierge in dev → log in → navigate to Location Details card → confirm only C-cut fields render for each location type.

- [ ] **Step 5: Commit**

```bash
git add scripts/concierge/Seed-IntakeFieldConfigDefaults.ps1 scripts/_backups/2026-04-11_intake_field_configs-before.json
git commit -m "seed: field config C-cut defaults for concierge"
```

### Chunk 6 complete

All four screens are functional. Feedback captured. Location fields trimmed by the existing config mechanism. Operator toggles more fields on through the existing Admin tab without redeploying.

---

## Chunk 7: E2E tests, Test deploy, and Portal env mirror

### Task 7.1: Playwright E2E suite

**Files:**
- Create: `nora/tests/concierge/concierge-dashboard.spec.ts`

The suite uses the Concierge test access code against `decadeswelcomesyou.powerappsportals.com` via the existing Playwright infra under `nora/`.

Tests:
1. `login renders 4 cards` — log in with demo code, verify `[data-testid="card-vendors"]`, `card-dates`, `card-locations`, `card-documents` visible
2. `vendor manual add` — navigate to vendors card, add a vendor via the existing form, reload, confirm persistence
3. `vendor spreadsheet upload happy path` — upload `vendor-template-happy.xlsx`, preview modal shows 2 OK rows, commit, vendor list grows by 2
4. `dates add with file attach` — add a date, attach `fixtures/sample.pdf`, reload, confirm attachment name persists
5. `delegation invite end-to-end` — fill modal, submit, verify row in `dcfg_intake_delegation` via a direct Dataverse read helper, verify row disappears after revoke
6. `delegate uses same code in a fresh context` — open a second browser context with the same access code, verify the same data renders
7. `orphan document upload` — navigate to Documents card, upload a file, reload, confirm persistence

- [ ] **Step 1: Testid audit**

```bash
pwsh -Command "Get-ChildItem spa/dcfg-property-intake/src -Recurse -Include *.jsx | Select-String 'data-testid' | ForEach-Object { \$_.Matches.Value } | Sort-Object -Unique"
```
Compare the output against the selectors the test suite uses. Any mismatch fixes before writing tests.

- [ ] **Step 2: Write the suite**

Use the existing Playwright config in `nora/` as the base. Auth model: the concierge uses access-code login (not Entra), so the suite uses the demo access code `demo1234` against the dev/test site — no `.msal_cache.bin` involvement. Add a `concierge` project to `nora/playwright.config.ts` targeting `https://decadeswelcomesyou.powerappsportals.com/` with no storageState (anonymous).

Test file outline:

```ts
import { test, expect } from '@playwright/test';

const CODE = process.env.CONCIERGE_CODE || 'demo1234';

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.getByPlaceholder('Access Code').fill(CODE);
  await page.getByRole('button', { name: 'Get Started' }).click();
  await page.getByRole('button', { name: /Start/i }).click(); // Welcome screen
});

test('renders 4 cards', async ({ page }) => {
  await expect(page.getByTestId('card-vendors')).toBeVisible();
  await expect(page.getByTestId('card-dates')).toBeVisible();
  await expect(page.getByTestId('card-locations')).toBeVisible();
  await expect(page.getByTestId('card-documents')).toBeVisible();
});

// ... 6 more tests per spec Testing section
```

- [ ] **Step 3: Add a Dataverse read helper for delegation verification**

```ts
// nora/tests/concierge/_dataverse-helper.ts
export async function readDelegationsForSession(sessionId: string) {
  // Uses pac auth create-token + Invoke-RestMethod shelled out, or direct fetch with OAuth
  // Returns the rows for $filter=_dcfg_sessionid_value eq {sessionId}
}
```

- [ ] **Step 4: Run**

```bash
cd nora && npx playwright test --project=concierge
```
Expected: all 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add nora/tests/concierge/
git commit -m "e2e: concierge dashboard playwright suite"
```

### Task 7.2: Test env deploy

- [ ] **Step 1: Final build**

```bash
cd spa/dcfg-property-intake
npm ci
npm run build
```

- [ ] **Step 2: Verify PAC auth is index [1]**

```bash
pac auth select --index 1
pac org who
```

- [ ] **Step 3: Deploy**

```bash
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 4: Clear portal cache**

Visit `https://decadeswelcomesyou.powerappsportals.com/_services/about` → Clear Cache.

- [ ] **Step 5: Manual smoke end-to-end**

Walk through: login → 4 cards → add vendor → upload sheet → add date with file → delegate → delegate logs in → revoke → feedback submit.

- [ ] **Step 6: Record deployment in audit + handoff**

Follow `feedback_handoff_links.md` and `feedback_build_summary_and_audit.md`. Provide launch URLs and cache-clear confirmation.

### Task 7.3: Portal env mirror (`orgf625b080`, PAC `[6]`)

- [ ] **Step 1: Switch PAC auth to Portal env**

```bash
pac auth select --index 6
pac org who
```
Expected: `Connected to... orgf625b080.crm.dynamics.com`. **Do not proceed if the wrong env is selected.** If a different org is shown, re-run `pac auth list` to find the correct index, then re-try.

- [ ] **Step 2: Create tables in Portal env**

Re-run the Chunk 1 creation scripts (`Create-IntakeDateTable.ps1`, `Create-IntakeDelegationTable.ps1`) against the Portal env. Parameterize the scripts to accept `-OrgUrl` so they can target either environment without source edits.

- [ ] **Step 3: Permissions**

Re-run `Set-IntakeConciergePermissions.ps1` against the Portal env, targeting the Portal concierge site GUID (`decades-concierge.powerappsportals.com`). Use the same explicit field lists.

- [ ] **Step 4: Flow build**

Repeat the three-step flow pattern for `dcfg_SendIntakeDelegationInvite` against the Portal env. Push v1 placeholder → manual connector add → readback → push v3 with preserved connection references.

- [ ] **Step 5: Field config defaults in Portal env**

Re-run `Seed-IntakeFieldConfigDefaults.ps1` against the Portal env.

- [ ] **Step 6: Deploy build to Portal env concierge site**

```bash
cd spa/dcfg-property-intake
# Verify PAC auth still on Portal env
pac org who
# List pages sites visible to this env and confirm the target
pac pages list
# Deploy — pac pages upload-code-site reads the manifest from the project root
pac pages upload-code-site --rootPath . --compiledPath dist
```

If `pac pages list` shows multiple sites, confirm the upload target is `decades-concierge.powerappsportals.com` before proceeding. If the upload goes to the wrong site, the rollback is `git revert` + redeploy to the correct site — empty new tables can stay in place.

- [ ] **Step 7: Clear portal cache**

Visit `https://decades-concierge.powerappsportals.com/_services/about` → Clear Cache.

- [ ] **Step 8: Manual smoke**

Same 7-step walkthrough as Task 7.2 step 5 but against `decades-concierge.powerappsportals.com`.

- [ ] **Step 9: Restore PAC auth to `[1]`**

```bash
pac auth select --index 1
pac org who
```
Expected: Back on `org0c17e98d`. **Required per `feedback_verify_pac_auth_before_deploy.md`.**

### Task 7.4: Close-out

- [ ] Update `project_onboarding_concierge.md` memory — status = "deployed to Test + Portal" with deploy date
- [ ] Write handoff doc `docs/handoff-concierge-vendors-dates-docs-<YYYY-MM-DD>.md` — replace `<YYYY-MM-DD>` with the actual deploy date at authoring time — with launch URLs, open issues, and follow-up items
- [ ] File a tracking item for Stage-env parity (spec Open Question): memory `project_onboarding_concierge.md` or a new GitHub issue. Stage is deliberately skipped for this build but needs to be tracked.
- [ ] Run one more full Playwright suite against both envs
- [ ] Commit

### Chunk 7 complete

Feature is live in both Test and Portal. Memory updated. Handoff written.

---

## Rollback

```bash
git log --oneline | head -20
git revert <commit-range>
cd spa/dcfg-property-intake && npm run build
pac pages upload-code-site --rootPath . --compiledPath dist
# clear cache
```

Empty new tables can stay in place. Disable the flow in Power Automate UI if needed.
