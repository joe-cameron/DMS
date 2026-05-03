---
name: power-pages-content-ops
description: "Generate PowerShell scripts and React/JavaScript code for the DCFG Power Pages SPA. Covers portal metadata (site settings, web roles, table permissions), React component patterns, portalApi.js, OData Web API calls, and pac pages deployment. ALWAYS use this skill when the user asks to: write PowerShell for site settings / web roles / table permissions, write React components or hooks for any of the 8 DCFG screens, write portalApi.js or OData queries, deploy via pac pages upload-code-site, configure Dataverse Web API access, or troubleshoot portal auth / CSRF / 403 errors. Also trigger for any mention of powerpagecomponents, mspp_entitypermissions, portalApi, usePortalUser, dcfg-shell, dcfg-sales, dcfg-contracts, dcfg-delivery, dcfg-locations. This skill REPLACES all adx_* classic portal assumptions — DCFG uses Enhanced Data Model exclusively."
---

# DCFG Power Pages SPA — Content & Code Operations

## ⚠ MANDATORY PRE-RESPONSE VALIDATION

**Before producing ANY code — PowerShell or JavaScript — scan your planned output against every rule in this section. If any rule is violated, fix it silently before responding. Never present a violation and then correct it.**

### GATE PS: PowerShell Rules

**PS-01 — Connect() MUST have trailing slash**
```powershell
# WRONG — produces "No such host is known" (DNS fails on merged string)
Connect 'https://org0c17e98d.crm.dynamics.com'

# CORRECT
Connect 'https://org0c17e98d.crm.dynamics.com/'
```
*Core.ps1 line 53 does string concat: `$uri + 'api/data/v9.2/'` — no slash = broken URL.*

**PS-02 — Invoke-ResilientRestMethod does NOT accept -Uri**
Never use `Invoke-ResilientRestMethod -Uri ...`. It does not support that parameter.
For any call that needs a custom full URL (N:N `$ref` links, `powerpagecomponents`, `mspp_entitypermissions` associations), use raw `Invoke-RestMethod` with `$baseHeaders`:
```powershell
# WRONG
Invoke-ResilientRestMethod -Uri "$OrgUrl/mspp_entitypermissions($id)/..." -Method POST -Body $body

# CORRECT
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'
Invoke-RestMethod -Uri "$OrgUrl/mspp_entitypermissions($id)/mspp_entitypermission_webrole/`$ref" `
    -Method POST -Body $body -Headers $baseHeaders -ContentType 'application/json; charset=utf-8'
```
`$baseHeaders` is set by Core.ps1 in script scope after `Connect`. It contains the bearer token.
A **412 response on a `$ref` POST means the link already exists** — treat as success, not error.

**PS-03 — Single-quote heredoc for strings containing OData/dollar signs**
```powershell
# WRONG — PowerShell interpolates $filter, $select, $top → they become empty
$query = @"?`$filter=name eq 'test'"@

# CORRECT
$query = @'?$filter=name eq 'test''@
```

**PS-04 — Always Unblock-File before pwsh -File**
```powershell
Unblock-File C:\DCFG\ScriptName.ps1
pwsh -File C:\DCFG\ScriptName.ps1
```

**PS-05 — OData filter on lookup columns uses _column_value syntax**
```powershell
# WRONG
?$filter=powerpagesiteid eq {guid}

# CORRECT
?$filter=_powerpagesiteid_value eq {guid}
```

**PS-06 — EntityDefinitions metadata API: filter client-side only**
The metadata API does not support `startswith()` or `contains()` in `$filter`. Always fetch and pipe to `Where-Object`:
```powershell
$all = (Invoke-RestMethod -Uri "...EntityDefinitions?`$select=LogicalName" -Headers $baseHeaders).value
$dcfg = $all | Where-Object { $_.LogicalName -like 'dcfg_*' }
```

**PS-07 — 412 on N:N $ref = idempotent success**
When linking permissions to roles or any N:N association, a 412 HTTP response means the link already exists. Always catch and treat as success:
```powershell
try {
    Invoke-RestMethod -Uri $refUri -Method POST -Body $body -Headers $baseHeaders -ContentType 'application/json; charset=utf-8' | Out-Null
} catch {
    if ($_.Exception.Message -match '412|duplicate|already exists') { <# already linked - ok #> }
    else { Write-Host "WARN: $($_.Exception.Message)" -ForegroundColor Red }
}
```

---

### GATE JS: JavaScript / React Rules

**JS-01 — EntitySetName for dcfg_property is `dcfg_propertys` (NOT `dcfg_properties`)**
Dataverse auto-pluralized `dcfg_property` as `dcfg_propertys`. Using `dcfg_properties` returns 404 on every location query. There are no exceptions to this.

**JS-02 — `window.Microsoft.Dynamic365.Portal.User` has NO `isAuthenticated` property**
This property does not exist. Never generate code that references it.
```javascript
// WRONG — isAuthenticated does not exist
if (window.Microsoft?.Dynamic365?.Portal?.User?.isAuthenticated) { ... }

// CORRECT
const user = window.Microsoft?.Dynamic365?.Portal?.User;
const isAuth = !!(user?.contactId || user?.userName || user?.email);
```

**JS-03 — CSRF token is mandatory on EVERY Web API call**
```javascript
async function getToken() {
  return new Promise((res, rej) => {
    const d = window.shell?.getTokenDeferred?.() || window.top?.shell?.getTokenDeferred?.();
    if (!d) rej(new Error('Token provider unavailable'));
    d.done(res).fail(rej);
  });
}
// Every fetch must include: '__RequestVerificationToken': await getToken()
```

**JS-04 — All lookup fields require OData bind syntax — never plain GUID**
```javascript
// WRONG — does not create the relationship in Dataverse
{ dcfg_msa_id: '...' }

// CORRECT
{ 'dcfg_msa_id@odata.bind': `/dcfg_msas(${msaId})` }
{ 'dcfg_property_id@odata.bind': `/dcfg_propertys(${propId})` }  // propertys
{ 'dcfg_customer_id@odata.bind': `/dcfg_customers(${custId})` }
```

**JS-05 — Build before every deploy**
```bash
npm run build
pac pages upload-code-site --rootPath . --compiledPath dist --siteId 22947376-be10-4bda-a90f-32b855c43045
```

**JS-06 — Role-restricted actions are REMOVED from DOM — never disabled or greyed out**
```jsx
// WRONG — user sees a disabled button and knows the action exists
<button disabled={!isAdmin()}>Void Contract</button>

// CORRECT — action is invisible to non-admin users
{isAdmin() && <button onClick={handleVoid}>Void Contract</button>}
```

**JS-07 — dcfg_budget_committed is NEVER written by the UI**
`dcfg_budget_committed` on `dcfg_msa` and `dcfg_program` is written exclusively by `flow_commit` via Dataverse trigger. Never include it in a PATCH or POST body. Always render as read-only display only.

**JS-08 — flow_commit is NEVER called by the UI**
UI PATCHes `dcfg_contract.dcfg_status` to SignedReceived (100000003). The Dataverse row-modified trigger fires `flow_commit` automatically. Never add a direct HTTP call to `flow_commit`.

**JS-09 — Audit log is CREATE ONLY — never PATCH or DELETE**
Portal entity permission for `dcfg_audit_log` is Create only. Never generate PATCH or DELETE operations against `dcfg_audit_logs`. See AUDIT LOG section for correct column names.

**JS-10 — No client-side caching on Dashboard (Page 01) and Send Queue (Page 07)**
These two screens must reflect live Dataverse state. Never use `useMemo`, `useRef` caching, or `localStorage` for query results on Pages 01 and 07.

---

## Environment

```
Org:             org0c17e98d.crm.dynamics.com
Portal URL:      https://dcfg.powerappsportals.com
Portal version:  9.8.1.34
Data Model:      ENHANCED (critical — all portal metadata uses EDM tables, not adx_*)
powerpagesites ID: a150bd53-7fbc-423d-a1ad-dd653ab4c435  ← USE IN ALL API CALLS
PAC site ID:     22947376-be10-4bda-a90f-32b855c43045  ← USE IN pac pages upload-code-site
Solution:        DCFGContractingSuite
Prefix:          dcfg_
Helpers:         C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\
Scripts:         C:\DCFG\
SPA root:        C:\dcfg\spa\
```

---

## Enhanced Data Model — Portal Metadata Table Map

DCFG uses Enhanced Data Model. Classic `adx_*` tables DO NOT EXIST for portal metadata.

| Purpose | Classic (WRONG — do not use) | Enhanced EDM (CORRECT) |
|---|---|---|
| Website record | adx_websites | powerpagesites |
| Site settings | adx_sitesettings | powerpagecomponents  type=9 |
| Web roles | adx_webroles | powerpagecomponents  type=11 |
| Web pages | adx_webpages | powerpagecomponents  type=2 |
| Web files | adx_webfiles | powerpagecomponents  type=3 |
| Web templates | adx_webtemplates | powerpagecomponents  type=8 |
| Content snippets | adx_contentsnippets | powerpagecomponents  type=7 |
| Table permissions | adx_entitypermission | mspp_entitypermissions |
| Permission↔Role link | adx_entitypermission_webrole | mspp_entitypermission_webrole (N:N nav prop) |

### powerpagecomponents type reference (confirmed from live site)

| Type | Purpose |
|---|---|
| 1 | Publishing States |
| 2 | Web Pages |
| 3 | Web Files (compiled JS/CSS bundles live here after upload) |
| 4 | Web Link Sets |
| 5 | Page Templates |
| 6 | Site Templates |
| 7 | Content Snippets |
| 8 | Web Templates |
| 9 | Site Settings |
| 10 | Webpage Access Control Rules |
| 11 | Web Roles |
| 12 | Role Page Permissions |
| 27 | Bot Consumer |

---

## Script Skeleton

Every Power Pages script MUST follow this structure:

```powershell
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'   # ← trailing slash REQUIRED (PS-01)

$WebsiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435'
$OrgUrl    = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # All operations here — automatic error handling + 429 retry
}
```

Run command (always include at bottom of every script response):
```powershell
Unblock-File C:\DCFG\ScriptName.ps1   # PS-04
pwsh -File C:\DCFG\ScriptName.ps1
```

---

## Site Settings (powerpagecomponents type=9)

Site settings are deployed via direct Dataverse API POST. **Do NOT use solution import** — the `<n>` tag in solution XML produces a blank name field.

### Create a site setting

```powershell
# CORRECT: value goes INSIDE the content JSON as {"value":"..."} — NOT as a separate column
$id = New-Record -setName 'powerpagecomponents' -body @{
    name                         = 'Webapi/dcfg_contract/enabled'
    powerpagecomponenttype       = 9
    content                      = '{"value":"true"}'
    'powerpagesiteid@odata.bind' = "/powerpagesites($WebsiteId)"
}
# WRONG — DO NOT use a separate 'value' column:
# $body['value'] = 'true'   ← This does NOT work
```

### Idempotent check before creating

```powershell
$existing = (Get-Records -setName 'powerpagecomponents' `
    -query "?`$select=powerpagecomponentid,name&`$filter=_powerpagesiteid_value eq $WebsiteId and powerpagecomponenttype eq 9 and name eq 'Webapi/dcfg_contract/enabled'").value
if ($existing -and $existing.Count -gt 0) {
    Write-Host "EXISTS: $($existing[0].name)" -ForegroundColor Yellow
} else {
    # POST new record
}
```

### Required site settings pattern (per table)

Both settings are required for each table. Missing `fields` returns nothing even when `enabled=true`.

```
Webapi/{table}/enabled  = true
Webapi/{table}/fields   = col1,col2,col3,...
```

All 19 tables are already configured in the live environment (DCFG_SPA_SiteSettings.ps1 — completed 2026-03-08). Only add new entries when adding a new table.

---

## Web Roles (powerpagecomponents type=11)

### Confirmed role IDs (live environment)

| Role | powerpagecomponentid |
|---|---|
| DCFG_Admin | 32993d47-be1b-f111-8341-7ced8d709731 |
| DCFG_Manager | 35993d47-be1b-f111-8341-7ced8d709731 |
| DCFG_Viewer | 38993d47-be1b-f111-8341-7ced8d709731 |
| Administrators (system) | b69bbf57-2186-4e72-94c3-55415bb48927 |
| Authenticated Users (system) | ae785cc2-54bb-400e-b0be-b448ea923352 |

### Create a web role

```powershell
$contentObj = @{
    anonymoususersrole     = $false
    authenticatedusersrole = $false
    websiteid              = $WebsiteId
}
$id = New-Record -setName 'powerpagecomponents' -body @{
    name                         = 'DCFG_Admin'
    powerpagecomponenttype       = 11
    content                      = ($contentObj | ConvertTo-Json -Compress)
    'powerpagesiteid@odata.bind' = "/powerpagesites($WebsiteId)"
}
```

---

## Table Permissions (mspp_entitypermissions)

### Field reference (confirmed from live metadata)

| Column | Type | Notes |
|---|---|---|
| mspp_entityname | String | Logical table name |
| mspp_entitylogicalname | String | Same as mspp_entityname |
| mspp_scope | Picklist | 756150000 = Global |
| mspp_read | Boolean | |
| mspp_write | Boolean | |
| mspp_create | Boolean | |
| mspp_delete | Boolean | |
| mspp_append | Boolean | |
| mspp_appendto | Boolean | |
| mspp_websiteid | Lookup | bind to powerpagesites |
| mspp_parententitypermission | Lookup | for Parent scope only |

### Create a table permission (E2E PROVEN — 2026-03-24)

**CRITICAL: Two steps required.** Step 1 creates the record. Step 2 makes the portal enforce it.

```powershell
# STEP 1: Create the permission record (also creates powerpagecomponent type=18)
$permId = New-Record -setName 'mspp_entitypermissions' -body @{
    mspp_entityname             = 'dcfg_contract'
    mspp_entitylogicalname      = 'dcfg_contract'
    mspp_scope                  = 756150000   # Global
    mspp_read                   = $true
    mspp_write                  = $true
    mspp_create                 = $true
    mspp_delete                 = $true
    mspp_append                 = $true
    mspp_appendto               = $true
    'mspp_websiteid@odata.bind' = "/powerpagesites($WebsiteId)"
}

# STEP 2: PATCH the powerpagecomponent content JSON with role links
# WITHOUT THIS STEP, THE PORTAL RETURNS 403 EVEN THOUGH THE RECORD EXISTS
$roleIds = @('ae785cc2-54bb-400e-b0be-b448ea923352')  # Authenticated Users
$contentJson = @{
    read       = $true
    write      = $true
    create     = $true
    delete     = $true
    append     = $true
    appendto   = $true
    scope      = 756150000
    entityname = 'dcfg_contract'
    entitylogicalname = 'dcfg_contract'
    adx_entitypermission_webrole = $roleIds
} | ConvertTo-Json -Compress

Update-Record -setName 'powerpagecomponents' -id $permId -body @{
    content = $contentJson
}
```

### Why $ref alone is NOT enough

The `$ref` POST to `mspp_entitypermission_webrole/$ref` creates intersection table records, but the **portal runtime ignores them**. The portal reads role links from the `adx_entitypermission_webrole` array inside the `powerpagecomponent` content JSON. This was discovered and E2E verified on 2026-03-24.

### Legacy $ref link (creates intersection records — optional, not portal-enforced)

```powershell
# This creates an intersection record but the portal does NOT use it for authorization.
# Include for completeness but the content JSON PATCH above is what actually matters.
$roleId  = '32993d47-be1b-f111-8341-7ced8d709731'  # DCFG_Admin
$refUri  = "$OrgUrl/mspp_entitypermissions($permId)/mspp_entitypermission_webrole/`$ref"
$refBody = @{ '@odata.id' = "$OrgUrl/mspp_webroles($roleId)" } | ConvertTo-Json -Compress

try {
    Invoke-RestMethod -Uri $refUri -Method POST -Body $refBody `
        -Headers $baseHeaders -ContentType 'application/json; charset=utf-8' | Out-Null
} catch {
    if ($_.Exception.Message -match '412|duplicate|already') { <# ok #> }
}
```

### Verify permission works (two methods)

```powershell
# Method 1: Check content JSON has role links (confirms data is set)
$ppc = Invoke-RestMethod -Uri "$OrgUrl/powerpagecomponents($permId)?`$select=content" -Headers $baseHeaders
$content = $ppc.content | ConvertFrom-Json
if ($content.adx_entitypermission_webrole) {
    Write-Host "Roles in content JSON: $($content.adx_entitypermission_webrole -join ', ')"
} else {
    Write-Host "WARNING: No roles in content JSON — portal will return 403!"
}

# Method 2: E2E test via Playwright (confirms portal enforces it)
# See C:\DCFG\nora\tests\permtest-e2e.spec.ts

# DO NOT USE: N:N navigation (mspp_entitypermission_webrole) — always returns 0 (platform bug)
# DO NOT USE: Intersection table query — portal ignores these records
```

### Permission matrix

| Table category | Admin | Manager | Viewer |
|---|---|---|---|
| Write tables (contract, msa, customer, property, etc.) | R W C D Ap AT | R W C Ap AT | R |
| dcfg_audit_log | R C | R C | R |
| Reference tables (vendor, location_type, ap_cost_code, doc_template, template_field) | R | R | R |

---

## portalApi.js — Standard Pattern

```javascript
// C:\dcfg\spa\dcfg-shell\src\portalApi.js

const API_BASE = '/_api';

async function getToken() {
  return new Promise((res, rej) => {
    const d = window.shell?.getTokenDeferred?.()
           || window.top?.shell?.getTokenDeferred?.();
    if (!d) return rej(new Error('Token provider unavailable'));
    d.done(res).fail(rej);
  });
}

async function apiFetch(path, options = {}) {
  const token = await getToken();
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    credentials: 'same-origin',
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'OData-MaxVersion': '4.0',
      'OData-Version': '4.0',
      'X-Requested-With': 'XMLHttpRequest',
      '__RequestVerificationToken': token,   // JS-03
      ...options.headers
    }
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`${res.status}: ${err}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

export const apiGet    = (path)         => apiFetch(path);
export const apiPost   = (path, body)   => apiFetch(path, { method: 'POST',   body: JSON.stringify(body) });
export const apiPatch  = (path, body)   => apiFetch(path, { method: 'PATCH',  body: JSON.stringify(body) });
export const apiDelete = (path)         => apiFetch(path, { method: 'DELETE' });

// OData bind helper — always use for lookup fields (JS-04)
export const bind = (col, entitySet, guid) => ({ [`${col}@odata.bind`]: `/${entitySet}(${guid})` });
```

---

## usePortalUser.js — Standard Pattern

```javascript
// C:\dcfg\spa\dcfg-shell\src\usePortalUser.js
import { useState, useEffect } from 'react';

export function usePortalUser() {
  const [user, setUser] = useState(null);

  useEffect(() => {
    const raw = window.Microsoft?.Dynamic365?.Portal?.User;
    // JS-02 — isAuthenticated does not exist; infer from properties
    const isAuth = !!(raw?.contactId || raw?.userName || raw?.email);
    setUser({
      isAuthenticated: isAuth,
      name:     isAuth ? `${raw.firstName ?? ''} ${raw.lastName ?? ''}`.trim() : null,
      email:    raw?.email ?? null,
      contactId: raw?.contactId ?? null,
      roles:    raw?.roles ?? []
    });
  }, []);

  const hasRole  = (name) => user?.roles?.some(r => r.name === name) ?? false;
  const isAdmin   = ()    => hasRole('DCFG_Admin');
  const isManager = ()    => hasRole('DCFG_Manager') || isAdmin();
  const isViewer  = ()    => user?.isAuthenticated ?? false;

  return { user, isAdmin, isManager, isViewer, hasRole };
}
```

---

## Entity Set Names (complete reference)

| Logical Name | EntitySetName (use in OData paths) |
|---|---|
| dcfg_contract | dcfg_contracts |
| dcfg_contract_line | dcfg_contract_lines |
| dcfg_customer | dcfg_customers |
| dcfg_msa | dcfg_msas |
| dcfg_msa_rate | dcfg_msa_rates |
| dcfg_vendor | dcfg_vendors |
| dcfg_property | **dcfg_propertys** ← propertys not properties |
| dcfg_property_detail | dcfg_property_details |
| dcfg_location_type | dcfg_location_types |
| dcfg_location_document | dcfg_location_documents |
| dcfg_ap_cost_code | dcfg_ap_cost_codes |
| dcfg_audit_log | dcfg_audit_logs |
| dcfg_send_queue | dcfg_send_queues |
| dcfg_onboarding_case | dcfg_onboarding_cases |
| dcfg_onboarding_checklist | dcfg_onboarding_checklists |
| dcfg_program | dcfg_programs |
| dcfg_document_template | dcfg_document_templates |
| dcfg_document_output | dcfg_document_outputs |
| dcfg_template_field | dcfg_template_fields |
| powerpagesites | powerpagesites |
| powerpagecomponents | powerpagecomponents |
| mspp_entitypermissions | mspp_entitypermissions |

---

## OData Bind Syntax Reference

Always use bind syntax for lookup fields. Never pass a plain GUID string.

| Column | Entity Set | Pattern |
|---|---|---|
| dcfg_msa_id on dcfg_contracts | dcfg_msas | `"dcfg_msa_id@odata.bind": "/dcfg_msas({guid})"` |
| dcfg_property_id on dcfg_contracts | dcfg_propertys | `"dcfg_property_id@odata.bind": "/dcfg_propertys({guid})"` |
| dcfg_cost_code on dcfg_contract_lines | dcfg_ap_cost_codes | `"dcfg_cost_code@odata.bind": "/dcfg_ap_cost_codes({guid})"` |
| dcfg_customer_id on dcfg_msas | dcfg_customers | `"dcfg_customer_id@odata.bind": "/dcfg_customers({guid})"` |
| dcfg_vendor_id on dcfg_msas | dcfg_vendors | `"dcfg_vendor_id@odata.bind": "/dcfg_vendors({guid})"` |
| dcfg_property_id on dcfg_location_documents | dcfg_propertys | `"dcfg_property_id@odata.bind": "/dcfg_propertys({guid})"` |
| dcfg_location_type_id on dcfg_propertys | dcfg_location_types | `"dcfg_location_type_id@odata.bind": "/dcfg_location_types({guid})"` |
| mspp_websiteid on mspp_entitypermissions | powerpagesites | `"mspp_websiteid@odata.bind": "/powerpagesites({guid})"` |
| powerpagesiteid on powerpagecomponents | powerpagesites | `"powerpagesiteid@odata.bind": "/powerpagesites({guid})"` |

---

## Corrected Column Names (UL-004)

The UI requirements spec has wrong source column names. Always use the actual schema names:

| Table | Spec says (WRONG) | Actual (CORRECT) |
|---|---|---|
| dcfg_property | dcfg_owner_contact | dcfg_contact_person |
| dcfg_property | dcfg_owner_title | dcfg_contact_title |
| dcfg_property | dcfg_owner_street | dcfg_address |
| dcfg_property | dcfg_owner_city | dcfg_city |
| dcfg_property | dcfg_owner_state | dcfg_state |
| dcfg_property | dcfg_owner_email | dcfg_contact_email |
| dcfg_vendor | dcfg_contractor_legal_name | dcfg_legal_name |
| dcfg_customer / dcfg_vendor | dcfg_is_active | dcfg_active_flag |
| dcfg_contract_line | dcfg_line_description | dcfg_description |
| dcfg_contract_line | dcfg_line_amount | dcfg_amount |

Note: `dcfg_contract` CORRECTLY stores copies as `dcfg_owner_*` — only the source tables have wrong names in the spec.

---

## Audit Log — Correct Column Names

**Using wrong column names produces SILENT Dataverse 400 errors. Every response involving audit logs must reference this table.**

| Column | Required | Notes |
|---|---|---|
| dcfg_target_table | Always | Dataverse logical table name |
| dcfg_target_record_id | Always | GUID of affected record |
| dcfg_action_type | Always | Picklist int (see below) |
| dcfg_performed_by | Always | Authenticated user email |
| dcfg_performed_at | Always | UTC DateTime |
| dcfg_new_value | Always | Human-readable description |
| dcfg_old_value | Optional | Previous state |
| dcfg_reason | Void/Decline/Override only | |
| dcfg_related_contract_id | Always | Contract GUID even when target is another table |

**COLUMNS THAT DO NOT EXIST (using them = silent 400):**
`dcfg_entity_type` | `dcfg_entity_id` | `dcfg_action` | `dcfg_details`

### dcfg_action_type picklist values

| Label | Int |
|---|---|
| Generated | 100000000 |
| Sent | 100000001 |
| Signed | 100000002 |
| Void | 100000003 |
| Declined | 100000004 |
| Override | 100000005 |
| Status Changed | 100000006 |
| Template Activated | 100000007 |
| Template Deactivated | 100000008 |
| Data Updated | 100000009 |
| Other | 100000010 |

---

## Contract Status Integers (OI-01 CLOSED)

| Label | Int |
|---|---|
| Draft | 100000000 |
| Generated | 100000001 |
| Sent | 100000002 |
| Signed/Received | 100000003 |
| Closed | 100000004 |
| Void | 100000005 |
| Declined | 100000006 |

---

## dcfg_send_queue Status Integers

| Label | Int |
|---|---|
| Pending | 100000000 |
| Sent | 100000001 |
| Complete | 100000002 |
| Cancelled | 100000003 |

Page 07 Send Queue reads `dcfg_send_queues` where `dcfg_queue_status eq 100000000` ordered by `dcfg_added_to_queue_date asc`.
Mark Sent must PATCH both `dcfg_send_queues` AND `dcfg_contracts` simultaneously.

---

## Sub-App Structure

| Sub-App | Path | Pages |
|---|---|---|
| dcfg-shell | C:\dcfg\spa\dcfg-shell\ | Shell / Nav / Auth |
| dcfg-sales | C:\dcfg\spa\dcfg-sales\ | 01 Dashboard, 02 Customer List, 03 Customer Detail, 04 New Contract Wizard |
| dcfg-contracts | C:\dcfg\spa\dcfg-contracts\ | 05 MSA Detail, 06 Contract Detail |
| dcfg-delivery | C:\dcfg\spa\dcfg-delivery\ | 07 Contract Delivery / Send Queue |
| dcfg-locations | C:\dcfg\spa\dcfg-locations\ | 08 Location Management |

Deploy command (run after `npm run build` in sub-app root):
```bash
pac pages upload-code-site --rootPath . --compiledPath dist --siteId 22947376-be10-4bda-a90f-32b855c43045
```

---

## Flow Reference

| Flow | Called by | Pattern |
|---|---|---|
| flow_docgen | UI (Pages 04, 05, 06) | HTTP POST to env var `dcfg_flow_docgen_url` |
| flow_send_email | UI (Page 03, steps 9 + 16 only) | HTTP POST to env var `dcfg_flow_send_email_url` |
| flow_cert_upload | UI (Page 08) | HTTP POST to env var `dcfg_flow_cert_upload_url` |
| flow_commit | **SYSTEM ONLY** — Dataverse trigger on status=SignedReceived | UI never calls this (JS-08) |
| flow_cert_alert | **SYSTEM ONLY** — scheduled daily | No UI action |
| flow_template_validate | **SYSTEM ONLY** — SharePoint trigger | No UI action |

---

## Portal Cache

After any metadata change (site settings, web roles, permissions), clear cache:
```
https://dcfg.powerappsportals.com/_services/about?clearCache=true
```

---

## Output Conventions

- All PowerShell scripts saved to `C:\DCFG\`
- Include `Unblock-File` + `pwsh -File` run command at bottom of every script
- Use `Write-Host` color coding: Cyan = section headers, Green = created, Yellow = skipped/exists, Red = errors
- Scripts must be idempotent — safe to run multiple times
- All Dataverse operations inside `Invoke-DataverseCommands { }`
