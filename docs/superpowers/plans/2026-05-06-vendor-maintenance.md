# Vendor Maintenance Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-CRUD Vendor Maintenance screen under System Admin with document uploads (MSA, W9, COI), compliance tracking, and Send Queue integration.

**Architecture:** Replaces the existing inline `VendorsTab`/`VendorForm` in Admin.jsx with a new extracted component `VendorMaintenance.jsx`. Compliance logic lives in a shared pure-function module used by both Admin and SendQueue. Azure Function extended to support `DCFG_Attachments` library for file uploads.

**Tech Stack:** React 16 (DCFG SPA), Dataverse Web API (OData), Azure Functions (Node.js), SharePoint Graph API, PowerShell (schema provisioning)

**Spec:** `docs/superpowers/specs/2026-05-06-vendor-maintenance-design.md`

**SPA source:** `C:\DCFG\spa\dcfg-shell\src\` — READ-ONLY until operator grants edit permission per file.

---

## File Structure

### New files
| File | Responsibility |
|------|---------------|
| `spa/dcfg-shell/src/lib/vendorCompliance.js` | Pure `getComplianceStatus(vendor)` function + `sanitizeVendorName()` helper. Shared by VendorMaintenance and SendQueue. |
| `spa/dcfg-shell/src/screens/VendorMaintenance.jsx` | Complete Vendors tab: list view, detail/edit form, document cards, file upload. Imported by Admin.jsx. |
| `scripts/vendor-maintenance-schema.ps1` | PowerShell: create 6 columns, update site setting, verify. |

### Modified files
| File | Changes |
|------|---------|
| `spa/dcfg-shell/src/screens/Admin.jsx` | Remove inline `VendorsTab` (lines 974-1065) and `VendorForm` (lines 1067-1134+). Replace with `import VendorMaintenance from './VendorMaintenance.jsx'` and render `<VendorMaintenance>` in the Vendors tab. |
| `spa/dcfg-shell/src/portalApi.js` | Add `fetchVendorDetail(id)`, `fetchVendorComplianceBatch(vendorIds)` exports. |
| `spa/dcfg-shell/src/screens/SendQueue.jsx` | After fetching queue rows, resolve vendor IDs from MSA expand, batch-fetch compliance, render badges per row. |
| `azure-functions/html-to-pdf/src/functions/sharepointUpload.js` | Accept optional `library` param (default `DCFG_Outputs`). Use it in `resolveSiteAndDrive()` to find the target drive. Accept optional `folder_path` to override the `customer_name/year/doc_type` path construction. |

---

## Chunk 1: Infrastructure (Schema + Azure Function)

### Task 1: Create Dataverse columns

**Files:**
- Create: `scripts/vendor-maintenance-schema.ps1`

- [ ] **Step 1: Write the schema provisioning script**

```powershell
# scripts/vendor-maintenance-schema.ps1
# Creates 6 new columns on dcfg_vendor + updates Webapi site setting
# Run: pwsh -File scripts/vendor-maintenance-schema.ps1

. "$PSScriptRoot/../PowerApps-Samples/dataverse/webapi/PS/Core.ps1"

# Connect to Test environment (operator must verify pac auth first)
$org = "https://org0c17e98d.crm.dynamics.com"
Connect $org

$tableName = "dcfg_vendor"
$solutionName = "DCFGSystemTest"

$columns = @(
    @{ SchemaName = "dcfg_msa_file_url"; Type = "String"; MaxLength = 2000; DisplayName = "MSA File URL" },
    @{ SchemaName = "dcfg_w9_file_url"; Type = "String"; MaxLength = 2000; DisplayName = "W9 File URL" },
    @{ SchemaName = "dcfg_msa_upload_date"; Type = "DateTime"; DisplayName = "MSA Upload Date" },
    @{ SchemaName = "dcfg_w9_upload_date"; Type = "DateTime"; DisplayName = "W9 Upload Date" },
    @{ SchemaName = "dcfg_coi_upload_date"; Type = "DateTime"; DisplayName = "COI Upload Date" },
    @{ SchemaName = "dcfg_insurance_effective_date"; Type = "DateTime"; DisplayName = "Insurance Effective Date" }
)

foreach ($col in $columns) {
    Write-Host "Creating $($col.SchemaName)..." -ForegroundColor Cyan

    $body = @{
        "@odata.type" = if ($col.Type -eq "String") {
            "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        } else {
            "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        }
        SchemaName = $col.SchemaName
        DisplayName = @{ "@odata.type" = "Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"; Label = $col.DisplayName; LanguageCode = 1033 }) }
        RequiredLevel = @{ Value = "None" }
    }

    if ($col.Type -eq "String") {
        $body.MaxLength = $col.MaxLength
        $body.FormatName = @{ Value = "Url" }
    }
    if ($col.Type -eq "DateTime") {
        $body.Format = "DateOnly"
        $body.DateTimeBehavior = @{ Value = "UserLocal" }
    }

    try {
        $resp = Invoke-RestMethod `
            -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='$tableName')/Attributes" `
            -Method Post `
            -Headers ($baseHeaders + @{ "MSCRM.SolutionUniqueName" = $solutionName }) `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ContentType "application/json"
        Write-Host "  Created: $($col.SchemaName)" -ForegroundColor Green
    } catch {
        $err = $_.Exception.Response
        if ($err -and $err.StatusCode -eq 409) {
            Write-Host "  Already exists: $($col.SchemaName)" -ForegroundColor Yellow
        } else {
            Write-Host "  FAILED: $($col.SchemaName) - $_" -ForegroundColor Red
        }
    }
    Start-Sleep -Seconds 2  # metadata cache lag
}

Write-Host "`nDone. Verify columns in make.powerapps.com > Tables > dcfg_vendor" -ForegroundColor Green
```

- [ ] **Step 2: Run `pac auth list` to verify environment**

```bash
pac auth list
```
Expected: `[2]` active pointing to DCFGSystems-Test.

- [ ] **Step 3: Execute schema script**

```bash
pwsh -File scripts/vendor-maintenance-schema.ps1
```
Expected: 6 "Created" messages (or "Already exists" if rerun).

- [ ] **Step 4: Verify columns exist**

```bash
pwsh -Command ". PowerApps-Samples/dataverse/webapi/PS/Core.ps1; Connect 'https://org0c17e98d.crm.dynamics.com'; Invoke-RestMethod -Uri 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2/EntityDefinitions(LogicalName=''dcfg_vendor'')/Attributes?`$filter=startswith(SchemaName,''dcfg_msa_file'') or startswith(SchemaName,''dcfg_w9_file'') or startswith(SchemaName,''dcfg_msa_upload'') or startswith(SchemaName,''dcfg_w9_upload'') or startswith(SchemaName,''dcfg_coi_upload'') or startswith(SchemaName,''dcfg_insurance_effective'')&`$select=SchemaName,AttributeType' -Headers `$baseHeaders | Select-Object -ExpandProperty value | ForEach-Object { Write-Host `$_.SchemaName }"
```
Expected: 6 column names listed.

- [ ] **Step 5: Commit**

```bash
git add scripts/vendor-maintenance-schema.ps1
git commit -m "feat: vendor maintenance schema provisioning script (6 new columns on dcfg_vendor)"
```

---

### Task 2: Update Web API site setting

- [ ] **Step 1: Read current field list**

```bash
pwsh -Command ". PowerApps-Samples/dataverse/webapi/PS/Core.ps1; Connect 'https://org0c17e98d.crm.dynamics.com'; $r = Invoke-RestMethod -Uri 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2/adx_sitesettings?`$filter=adx_name eq ''Webapi/dcfg_vendor/fields''&`$select=adx_sitesettingid,adx_value' -Headers `$baseHeaders; $r.value[0].adx_value"
```

- [ ] **Step 2: Append new columns to the value**

Append to existing comma-separated value:
```
,dcfg_msa_file_url,dcfg_w9_file_url,dcfg_msa_upload_date,dcfg_w9_upload_date,dcfg_coi_upload_date,dcfg_insurance_effective_date
```

PATCH the site setting record with the updated value. Save the before-state to `scripts/_backups/`.

- [ ] **Step 3: Clear portal cache**

```bash
pwsh -Command "Invoke-RestMethod -Uri 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2/adx_websites?`$top=1' -Headers `$baseHeaders | Select-Object -ExpandProperty value | ForEach-Object { Write-Host 'Restart site...'; Invoke-RestMethod -Uri ('https://org0c17e98d.crm.dynamics.com/api/data/v9.2/adx_websites(' + `$_.adx_websiteid + ')') -Method Patch -Headers `$baseHeaders -Body '{\"adx_headeroutputcache_enabled\":false}' -ContentType 'application/json' }"
```

- [ ] **Step 4: Verify fields are accessible via Web API**

Navigate to `https://dcfg.powerappsportals.com/_api/dcfg_vendors?$top=1&$select=dcfg_msa_file_url,dcfg_w9_file_url` in browser. Should return data (even if null values).

---

### Task 3: Extend Azure Function for library parameter

**Files:**
- Modify: `azure-functions/html-to-pdf/src/functions/sharepointUpload.js`

- [ ] **Step 1: Update `resolveSiteAndDrive()` to accept library name**

In `sharepointUpload.js`, modify the `resolveSiteAndDrive` function (around line 120-140):

```javascript
// BEFORE (line 136):
// const outputsDrive = drives.value.find(d => d.name === 'DCFG_Outputs') || drives.value[0];

// AFTER:
async function resolveSiteAndDrive(token, config, libraryName) {
  // ... existing site resolution code ...

  const targetLibrary = libraryName || 'DCFG_Outputs';
  const targetDrive = drives.value.find(d => d.name === targetLibrary) || drives.value[0];
  if (!targetDrive) throw new Error(`No document library '${targetLibrary}' found`);

  return { siteId: site.id, driveId: targetDrive.id };
}
```

- [ ] **Step 2: Update request body parsing to accept `library` and `folder_path`**

In the main handler function, after parsing the request body:

```javascript
const { file_base64, customer_name, year, doc_type, filename, library, folder_path } = body;

// Build folder path — use explicit folder_path if provided, else construct from customer/year/doc_type
const effectiveFolderPath = folder_path || `${customer_name}/${year}/${doc_type}`;
```

Pass `library` to `resolveSiteAndDrive()` and `effectiveFolderPath` to `ensureFolderPath()`.

- [ ] **Step 3: Test locally with existing parameters (regression)**

```bash
cd azure-functions/html-to-pdf
# Existing tests should still pass — library defaults to DCFG_Outputs
node test/test-all-templates.js
```

- [ ] **Step 4: Commit**

```bash
git add azure-functions/html-to-pdf/src/functions/sharepointUpload.js
git commit -m "feat: sharepointUpload accepts library and folder_path parameters"
```

---

### Task 4: Create SharePoint Vendors folder

- [ ] **Step 1: Create DCFG_Attachments/Vendors/ folder via Graph API**

```bash
python -c "
import sys; sys.path.insert(0, 'C:/DCFG/tools/path-probe')
from graph_auth import get_graph_token
import httpx

token = get_graph_token()
headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

# Get site ID
r = httpx.get('https://graph.microsoft.com/v1.0/sites/decadesconstructiongroup.sharepoint.com:/sites/DCFGContractingSuite?select=id', headers=headers)
site_id = r.json()['id']

# Get DCFG_Attachments drive
r2 = httpx.get(f'https://graph.microsoft.com/v1.0/sites/{site_id}/drives?select=id,name', headers=headers)
drive = [d for d in r2.json()['value'] if d['name'] == 'DCFG_Attachments'][0]

# Create Vendors folder
r3 = httpx.post(f'https://graph.microsoft.com/v1.0/drives/{drive[\"id\"]}/root/children',
    headers=headers,
    json={'name': 'Vendors', 'folder': {}, '@microsoft.graph.conflictBehavior': 'fail'})
print(f'Create folder: {r3.status_code} {r3.text[:200]}')
"
```

- [ ] **Step 2: Verify folder exists**

Navigate to SharePoint > DCFGContractingSuite > DCFG_Attachments > Vendors. Should exist.

---

## Chunk 2: Shared Logic + portalApi

### Task 5: Create vendorCompliance.js

**Files:**
- Create: `spa/dcfg-shell/src/lib/vendorCompliance.js`

**Requires SPA edit permission from operator.**

- [ ] **Step 1: Write the module**

```javascript
/**
 * vendorCompliance.js — Pure compliance logic for vendor documents.
 * Used by VendorMaintenance (Admin) and SendQueue.
 */

/**
 * Compute vendor compliance status from document fields.
 * @param {object} vendor — must include dcfg_active_flag, dcfg_msa_file_url,
 *   dcfg_w9_file_url, dcfg_insurance_file_url, dcfg_insurance_expiration_date
 * @returns {{ status: string, label: string, color: string, priority: number }}
 */
export function getComplianceStatus(vendor) {
  if (!vendor.dcfg_active_flag) return { status: 'inactive', label: 'Inactive', color: 'gray', priority: 0 };

  const hasMsa = !!vendor.dcfg_msa_file_url;
  const hasW9  = !!vendor.dcfg_w9_file_url;
  const hasCoi = !!vendor.dcfg_insurance_file_url;

  if (!hasMsa || !hasW9 || !hasCoi) return { status: 'non-compliant', label: 'Non-Compliant', color: 'red', priority: 1 };

  const coiExp = vendor.dcfg_insurance_expiration_date ? new Date(vendor.dcfg_insurance_expiration_date) : null;
  if (!coiExp) return { status: 'missing-date', label: 'COI Date Missing', color: 'yellow', priority: 2 };

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  if (coiExp <= today) return { status: 'coi-expired', label: 'COI Expired', color: 'red', priority: 3 };

  const in30 = new Date();
  in30.setDate(in30.getDate() + 30);
  in30.setHours(0, 0, 0, 0);
  if (coiExp <= in30) return { status: 'coi-expiring', label: 'COI Expiring', color: 'yellow', priority: 4 };

  return { status: 'compliant', label: 'Compliant', color: 'green', priority: 5 };
}

/** Badge color class name for compliance status */
export function complianceBadgeClass(color) {
  return color === 'green' ? 'badge-green' : color === 'red' ? 'badge-red' : color === 'yellow' ? 'badge-amber' : 'badge-grey';
}

/**
 * Sanitize vendor display name for use as SharePoint folder name.
 * Replaces special chars, truncates to 50 chars.
 */
export function sanitizeVendorName(name) {
  if (!name) return 'unknown-vendor';
  return name.replace(/[&/'"\\#%{}|<>*?:]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '').substring(0, 50) || 'vendor';
}

/** Max upload size in bytes (15MB — Azure Function base64 limit) */
export const MAX_UPLOAD_BYTES = 15 * 1024 * 1024;
```

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-shell/src/lib/vendorCompliance.js
git commit -m "feat: vendor compliance pure function module"
```

---

### Task 6: Add portalApi helpers

**Files:**
- Modify: `spa/dcfg-shell/src/portalApi.js`

**Requires SPA edit permission from operator.**

- [ ] **Step 1: Add vendor detail fetch and batch compliance fetch**

Add near the existing vendor-related functions:

```javascript
// ── VENDOR MAINTENANCE ──

const VENDOR_LIST_SELECT = 'dcfg_vendorid,dcfg_display_name,dcfg_legal_name,dcfg_trade,' +
  'dcfg_primary_contact,dcfg_msa_file_url,dcfg_w9_file_url,dcfg_insurance_file_url,' +
  'dcfg_insurance_expiration_date,dcfg_active_flag';

const VENDOR_DETAIL_SELECT = 'dcfg_vendorid,dcfg_legal_name,dcfg_display_name,' +
  'dcfg_trade,dcfg_phone,dcfg_email,dcfg_address,dcfg_address_line2,dcfg_city,dcfg_state,dcfg_zip,' +
  'dcfg_primary_contact,dcfg_signer_name,dcfg_signer_title,dcfg_signer_phone,' +
  'dcfg_msa_date,dcfg_msa_file_url,dcfg_msa_upload_date,' +
  'dcfg_w9_file_url,dcfg_w9_upload_date,' +
  'dcfg_insurance_file_url,dcfg_insurance_provider,dcfg_insurance_policy_number,' +
  'dcfg_insurance_expiration_date,dcfg_insurance_effective_date,dcfg_insurance_gl_expiration,' +
  'dcfg_insurance_coverage_types,dcfg_coi_upload_date,' +
  'dcfg_payment_terms,dcfg_payment_process,dcfg_net_terms,dcfg_notes,dcfg_active_flag';

export function fetchVendorList() {
  return apiGet(`/${EntitySets.vendors}?$select=${VENDOR_LIST_SELECT}&$orderby=dcfg_display_name asc`);
}

export function fetchVendorDetail(id) {
  return apiGet(`/${EntitySets.vendors}(${id})?$select=${VENDOR_DETAIL_SELECT}`);
}

export function fetchVendorComplianceBatch(vendorIds) {
  if (!vendorIds || vendorIds.length === 0) return Promise.resolve({ value: [] });
  const filter = vendorIds.map(id => `dcfg_vendorid eq ${id}`).join(' or ');
  return apiGet(`/${EntitySets.vendors}?$filter=${filter}&$select=dcfg_vendorid,dcfg_msa_file_url,dcfg_w9_file_url,dcfg_insurance_file_url,dcfg_insurance_expiration_date,dcfg_active_flag`);
}
```

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-shell/src/portalApi.js
git commit -m "feat: vendor maintenance API helpers in portalApi"
```

---

## Chunk 3: VendorMaintenance Component

### Task 7: Build VendorMaintenance.jsx — List View

**Files:**
- Create: `spa/dcfg-shell/src/screens/VendorMaintenance.jsx`

**Requires SPA edit permission from operator.**

This is the largest task. Build the list view first, then the form in the next task.

- [ ] **Step 1: Write list view skeleton**

The component follows the existing Admin tab pattern (inline state, no `useTableControls`). See `Admin.jsx` lines 974-1065 for the pattern being replaced.

Key elements:
- Search input filtering on `dcfg_legal_name`, `dcfg_display_name`, `dcfg_trade`, `dcfg_primary_contact`
- Status filter dropdown (All / Compliant / Non-Compliant / Expiring Soon)
- Table columns: Name, Trade, MSA ✓/✗, W9 ✓/✗, COI ✓/✗/!, COI Expires, Status badge, Edit button
- Sortable columns: Name, Trade, COI Expires, Status (by priority number)
- Empty states per spec
- `data-testid` attributes on all interactive elements per spec
- Import `getComplianceStatus`, `complianceBadgeClass` from `../lib/vendorCompliance.js`
- Import `fetchVendorList` from `../portalApi.js`
- Doc icon helper: `const DocIcon = ({ url, expired }) => <span className={...}>{url ? (expired ? '!' : '✓') : '✗'}</span>`

- [ ] **Step 2: Verify list renders with existing vendor data**

Build and check in Test environment: `npm run build` then deploy to Test. List should show all vendors with compliance badges.

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-shell/src/screens/VendorMaintenance.jsx
git commit -m "feat: VendorMaintenance list view with compliance badges"
```

---

### Task 8: Build VendorMaintenance.jsx — Detail/Edit Form

**Files:**
- Modify: `spa/dcfg-shell/src/screens/VendorMaintenance.jsx`

- [ ] **Step 1: Add detail panel with two-column layout**

Opens inline below list when Edit or +Add clicked. Left column = profile fields, right column = document cards.

**Left column fields** (carry forward ALL from existing VendorForm + add missing ones):
- Legal Name (required), Display Name
- Trade, Phone
- Address, Address Line 2
- City, State (maxLength=2), Zip
- Primary Contact, Email
- Signer Name, Signer Title, Signer Phone
- MSA Date (date input)
- Payment Terms, Net Terms
- Payment Process (picklist — reuse `TRADE_OPTIONS` pattern but with payment process values from existing VendorForm)
- Notes (textarea, 3 rows)
- Active toggle (checkbox)

**Right column — compliance bar + 3 document cards:**
- Compliance bar: row of ✓/✗ icons for MSA, W9, COI + overall badge
- MSA card: badge, upload date, View File link (hidden if null), Upload/Replace button
- W9 card: badge, upload date, View File link (hidden if null), Upload/Replace button
- COI card: badge, provider, policy#, effective date, expiration date, View File link, Upload button
  - COI inline fields revealed on upload: Provider, Policy Number, Effective Date, Expiration Date

**Footer:** Cancel, Deactivate/Reactivate, Save

**Save logic:**
- POST for new (`apiPost`), PATCH for existing (`apiPatch`)
- Write audit log on success
- Toast on error, keep form open
- Reload list on success

**Detail fetch:**
- On edit click, call `fetchVendorDetail(id)` to get all fields including Memo
- Populate form state from response

- [ ] **Step 2: Verify form opens, edits save, new vendor creates**

Test in browser: edit existing vendor, save. Create new vendor. Verify data persists.

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-shell/src/screens/VendorMaintenance.jsx
git commit -m "feat: VendorMaintenance detail/edit form with all vendor fields"
```

---

### Task 9: Build VendorMaintenance.jsx — File Upload

**Files:**
- Modify: `spa/dcfg-shell/src/screens/VendorMaintenance.jsx`

- [ ] **Step 1: Add file upload handler**

```javascript
async function handleFileUpload(docType, file, vendorId, vendorName) {
  if (file.size > MAX_UPLOAD_BYTES) {
    toast.show('err', 'File exceeds 15MB limit.');
    return null;
  }

  const safeName = sanitizeVendorName(vendorName);
  const base64 = await fileToBase64(file);

  const uploadUrl = getEnvVar('AzureFunctionUrl') + '/api/sharepoint-upload';
  const resp = await fetch(uploadUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      file_base64: base64,
      library: 'DCFG_Attachments',
      folder_path: `Vendors/${safeName}`,
      filename: `${docType}.pdf`,
    }),
  });

  if (!resp.ok) {
    toast.show('err', `Upload failed: ${resp.status}`);
    return null;
  }

  const result = await resp.json();
  return result.url;
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
```

- [ ] **Step 2: Wire upload buttons to handler**

Each document card's Upload button triggers a hidden `<input type="file" accept=".pdf">`. On file selection:
1. Call `handleFileUpload(docType, file, vendorId, displayName)`
2. On success, PATCH the vendor record with the returned URL + upload date
3. On PATCH failure, show toast with the SharePoint URL for manual retry
4. Reload vendor detail

- [ ] **Step 3: Test file upload end-to-end**

Upload a test PDF to a vendor's MSA slot. Verify:
- File appears in SharePoint `DCFG_Attachments/Vendors/{VendorName}/MSA.pdf`
- Vendor record's `dcfg_msa_file_url` is populated
- View File link opens the correct SharePoint URL
- Compliance badge updates (if MSA was missing, it should now show ✓)

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-shell/src/screens/VendorMaintenance.jsx
git commit -m "feat: VendorMaintenance file upload to SharePoint"
```

---

### Task 10: Replace VendorsTab in Admin.jsx

**Files:**
- Modify: `spa/dcfg-shell/src/screens/Admin.jsx`

- [ ] **Step 1: Remove old VendorsTab and VendorForm**

Delete the `VendorsTab` function (lines ~974-1065) and `VendorForm` function (lines ~1067-1134+) from Admin.jsx.

- [ ] **Step 2: Add import and render**

At the top of Admin.jsx, add:
```javascript
import VendorMaintenance from './VendorMaintenance.jsx';
```

In the tab render section (around line 226), replace:
```javascript
// BEFORE:
{activeTab === 'Vendors' && <VendorsTab userEmail={user?.email} />}

// AFTER:
{activeTab === 'Vendors' && <VendorMaintenance userEmail={user?.email} />}
```

- [ ] **Step 3: Update Vendors card description in SECTIONS**

In the SECTIONS array (around line 55), update the Vendors card description:
```javascript
// BEFORE:
{ key: 'Vendors', icon: '\u{1F4CB}', title: 'Vendors', desc: 'Vendor directory and trade codes' },

// AFTER:
{ key: 'Vendors', icon: '\u{1F4CB}', title: 'Vendors', desc: 'Vendor maintenance, documents & compliance' },
```

- [ ] **Step 4: Build and verify**

```bash
cd spa/dcfg-shell && npm run build
```
Expected: No errors. Admin → Vendors tab loads the new VendorMaintenance component.

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-shell/src/screens/Admin.jsx
git commit -m "feat: replace VendorsTab with VendorMaintenance in Admin"
```

---

## Chunk 4: Send Queue Integration

### Task 11: Add vendor compliance badges to SendQueue

**Files:**
- Modify: `spa/dcfg-shell/src/screens/SendQueue.jsx`

- [ ] **Step 1: Import compliance utilities**

```javascript
import { getComplianceStatus, complianceBadgeClass } from '../lib/vendorCompliance.js';
import { fetchVendorComplianceBatch } from '../portalApi.js';
```

- [ ] **Step 2: After queue data loads, resolve vendor compliance**

In the data-loading effect, after `fetchSendQueue()` resolves:

```javascript
// Extract unique vendor IDs from MSA expands
const vendorIds = new Set();
rows.forEach(row => {
  const vid = row.dcfg_msa_id?._dcfg_vendor_id_value;
  if (vid) vendorIds.add(vid);
});

let vendorComplianceMap = new Map();
if (vendorIds.size > 0) {
  try {
    const vendorData = await fetchVendorComplianceBatch([...vendorIds]);
    (vendorData?.value || []).forEach(v => {
      vendorComplianceMap.set(v.dcfg_vendorid, getComplianceStatus(v));
    });
  } catch (e) { console.warn('Vendor compliance fetch failed:', e); }
}
// Store in state: setVendorCompliance(vendorComplianceMap)
```

- [ ] **Step 3: Render compliance badge per row**

In the row rendering, after the existing columns, add a vendor compliance badge:

```javascript
const vendorId = row.dcfg_msa_id?._dcfg_vendor_id_value;
const vc = vendorCompliance.get(vendorId);
// Only show badge if there's a problem (compliant = no badge)
{vc && vc.status !== 'compliant' && vc.status !== 'inactive' && (
  <span
    className={`badge ${complianceBadgeClass(vc.color)}`}
    data-testid={`sendqueue-vendor-status-${row.dcfg_send_queueid}`}
    style={{ marginLeft: '8px', fontSize: '11px' }}
  >
    {vc.label}{vc.status === 'coi-expiring' && row.dcfg_msa_id?.dcfg_vendor_id?.dcfg_insurance_expiration_date
      ? ` (${new Date(row.dcfg_msa_id.dcfg_vendor_id.dcfg_insurance_expiration_date).toLocaleDateString()})`
      : ''}
  </span>
)}
```

- [ ] **Step 4: Verify in Test environment**

Load Send Queue. If any vendor has expired/missing docs, badge should appear. If all compliant, no badges (clean rows).

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-shell/src/screens/SendQueue.jsx
git commit -m "feat: vendor compliance badges in Send Queue"
```

---

## Chunk 5: Build, Test, Deploy

### Task 12: Full build and smoke test

- [ ] **Step 1: Build SPA**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```
Expected: Build succeeds with no errors.

- [ ] **Step 2: Deploy to Test** (requires operator approval)

```bash
pac auth select --index 2
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 3: Smoke test checklist**

Open `https://dcfg.powerappsportals.com/#/admin` and verify:

1. Admin → Vendors tab loads new VendorMaintenance
2. Vendor list shows all vendors with compliance columns
3. Search filters correctly
4. Status filter works (All / Compliant / Non-Compliant / Expiring)
5. Click Edit opens detail panel with all fields populated
6. Edit a field, save → persists
7. Click +Add Vendor → create new vendor with required fields → saves
8. Upload MSA PDF → file goes to SharePoint, URL saved, ✓ icon appears
9. Upload W9 PDF → same
10. Upload COI PDF → fill in provider/policy/dates → saves
11. Compliance badge updates correctly after uploads
12. Deactivate vendor → dimmed in list, badge shows Inactive
13. Send Queue → vendor with expired COI shows red badge

- [ ] **Step 4: Commit any fixes from smoke test**

- [ ] **Step 5: Update docs/to-be-fixed.md if needed**

If any issues found during smoke test, add to `docs/to-be-fixed.md`.

---

## Summary

| Task | What | Est. Steps |
|------|------|------------|
| 1 | Schema columns (PowerShell) | 5 |
| 2 | Web API site setting | 4 |
| 3 | Azure Function extension | 4 |
| 4 | SharePoint folder | 2 |
| 5 | vendorCompliance.js | 2 |
| 6 | portalApi.js helpers | 2 |
| 7 | VendorMaintenance list view | 3 |
| 8 | VendorMaintenance detail form | 3 |
| 9 | VendorMaintenance file upload | 4 |
| 10 | Admin.jsx swap | 5 |
| 11 | SendQueue badges | 5 |
| 12 | Build + smoke test | 5 |
| **Total** | | **44 steps** |

**Critical path:** Tasks 1-4 (infrastructure) must complete before Tasks 7-9 (SPA with upload). Tasks 5-6 (shared logic) can parallel with infrastructure. Task 11 (SendQueue) is independent of Tasks 7-10.
