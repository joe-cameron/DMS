# Contract DocGen Pipeline Fix — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 12 findings from the contract field diagnostic so generated documents contain correct data, and fix the Admin template screen's delete bug + add an Edit button.

**Architecture:** Three streams executed sequentially. Stream 1 patches Dataverse template field mappings (no SPA code). Stream 2 fixes 5 SPA source files for pipeline bugs. Stream 3 fixes 2 SPA files for the template management screen. All SPA changes require explicit operator permission before editing.

**Tech Stack:** PowerShell + Dataverse Web API (Stream 1), React/JSX SPA (Streams 2-3), Vite build + pac pages deploy

**Diagnostic report:** `C:\dcfg\scratch\contract-field-diagnostic-results.json`

---

## Chunk 1: Dataverse Template Field Remapping (Stream 1)

No SPA code changes. All fixes are PATCH operations on `dcfg_template_fields` in Prod.

### Task 1: Back up current template field mappings

**Files:**
- Create: `scripts/_backups/2026-04-27_template-field-remap-before.json`

- [ ] **Step 1: Export all mapped template fields from Prod**

```powershell
# scratch/backup-template-fields.ps1
. "C:/DCFG/PowerApps-Samples/dataverse/webapi/PS/Core.ps1"
Connect "https://org06f5de0b.crm.dynamics.com/"

$url = "$baseURI" + "dcfg_template_fields?" +
  '$select=dcfg_template_fieldid,dcfg_source_text,dcfg_dataverse_path,dcfg_field_category,_dcfg_template_id_value,dcfg_is_mapped' +
  '&$filter=dcfg_is_mapped eq true' +
  '&$orderby=_dcfg_template_id_value'
$r = Invoke-RestMethod -Uri $url -Headers $baseHeaders
[System.IO.File]::WriteAllText(
  "C:\dcfg\scripts\_backups\2026-04-27_template-field-remap-before.json",
  ($r.value | ConvertTo-Json -Depth 3)
)
Write-Host "Backed up $($r.value.Count) fields"
```

Run: `pwsh -File scratch/backup-template-fields.ps1`
Expected: "Backed up 381 fields"

- [ ] **Step 2: Verify backup file exists and is valid JSON**

Run: `pwsh -Command "(Get-Content 'C:\dcfg\scripts\_backups\2026-04-27_template-field-remap-before.json' | ConvertFrom-Json).Count"`
Expected: `381`

### Task 2: Fix F01 — dcfg_wo_number → dcfg_contract_number

Affects 11 templates. The column `dcfg_wo_number` does not exist on `dcfg_contract`.

- [ ] **Step 1: Find affected field IDs**

```powershell
# In the same Prod connection:
$fields = $backup | Where-Object { $_.dcfg_dataverse_path -eq 'dcfg_wo_number' }
Write-Host "F01: $($fields.Count) fields to patch"
# Expected: ~11 records
```

- [ ] **Step 2: Patch all to dcfg_contract_number**

```powershell
foreach ($f in $fields) {
  Invoke-RestMethod -Method Patch `
    -Uri "$baseURI/dcfg_template_fields($($f.dcfg_template_fieldid))" `
    -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
    -Body '{"dcfg_dataverse_path":"dcfg_contract_number"}'
}
Write-Host "F01: Patched $($fields.Count) fields"
```

- [ ] **Step 3: Verify**

Query one patched field back and confirm `dcfg_dataverse_path eq 'dcfg_contract_number'`.

### Task 3: Fix F02 — dcfg_contract_value → dcfg_contract_fee

- [ ] **Step 1: Find and patch**

```powershell
$fields = $backup | Where-Object { $_.dcfg_dataverse_path -eq 'dcfg_contract_value' }
Write-Host "F02: $($fields.Count) fields to patch"
foreach ($f in $fields) {
  Invoke-RestMethod -Method Patch `
    -Uri "$baseURI/dcfg_template_fields($($f.dcfg_template_fieldid))" `
    -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
    -Body '{"dcfg_dataverse_path":"dcfg_contract_fee"}'
}
```

### Task 4: Fix F03 — dcfg_msa.dcfg_msa_number → dcfg_msa.dcfg_name

- [ ] **Step 1: Find and patch**

```powershell
$fields = $backup | Where-Object { $_.dcfg_dataverse_path -eq 'dcfg_msa.dcfg_msa_number' }
Write-Host "F03: $($fields.Count) fields to patch"
foreach ($f in $fields) {
  Invoke-RestMethod -Method Patch `
    -Uri "$baseURI/dcfg_template_fields($($f.dcfg_template_fieldid))" `
    -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
    -Body '{"dcfg_dataverse_path":"dcfg_msa.dcfg_name"}'
}
```

### Task 5: Fix F04 — 5 vendor column remaps

- [ ] **Step 1: Remap all 5 broken vendor paths**

```powershell
$remaps = @{
  'dcfg_vendor.address1_line1'           = 'dcfg_vendor.dcfg_address'
  'dcfg_vendor.address1_city_state_zip'  = '[COMPOSITE:vendor_address_block]'
  'dcfg_vendor.fullname'                 = 'dcfg_vendor.dcfg_primary_contact'
  'dcfg_vendor.jobtitle'                 = 'dcfg_vendor.dcfg_signer_title'
  'dcfg_vendor.dcfg_address_composite'   = '[COMPOSITE:vendor_address_block]'
}
$totalPatched = 0
foreach ($old in $remaps.Keys) {
  $new = $remaps[$old]
  $fields = $backup | Where-Object { $_.dcfg_dataverse_path -eq $old }
  foreach ($f in $fields) {
    $body = @{ dcfg_dataverse_path = $new } | ConvertTo-Json
    Invoke-RestMethod -Method Patch `
      -Uri "$baseURI/dcfg_template_fields($($f.dcfg_template_fieldid))" `
      -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
      -Body $body
    $totalPatched++
  }
  Write-Host "  $old -> $new ($($fields.Count) fields)"
}
Write-Host "F04: Patched $totalPatched fields total"
```

### Task 6: Fix F07 — Vendor signer reads from contract columns

Templates currently read `dcfg_vendor.dcfg_signer_name` / `dcfg_vendor.dcfg_signer_title` (vendor expand). Remap to contract columns so user edits in the composer are reflected.

- [ ] **Step 1: Remap vendor signer paths**

```powershell
$signerRemaps = @{
  'dcfg_vendor.dcfg_signer_name'  = 'dcfg_signer_printed'
  'dcfg_vendor.dcfg_signer_title' = 'dcfg_signer_title'
}
foreach ($old in $signerRemaps.Keys) {
  $new = $signerRemaps[$old]
  $fields = $backup | Where-Object { $_.dcfg_dataverse_path -eq $old }
  foreach ($f in $fields) {
    $body = @{ dcfg_dataverse_path = $new } | ConvertTo-Json
    Invoke-RestMethod -Method Patch `
      -Uri "$baseURI/dcfg_template_fields($($f.dcfg_template_fieldid))" `
      -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
      -Body $body
  }
  Write-Host "F07: $old -> $new ($($fields.Count) fields)"
}
```

### Task 7: Fix F08 — Customer signer reads from contract columns

- [ ] **Step 1: Remap customer signer paths**

```powershell
$custRemaps = @{
  'dcfg_customer.dcfg_primary_contact_name'  = 'dcfg_owner_contact'
  'dcfg_customer.dcfg_primary_contact_title' = 'dcfg_owner_title'
}
foreach ($old in $custRemaps.Keys) {
  $new = $custRemaps[$old]
  $fields = $backup | Where-Object { $_.dcfg_dataverse_path -eq $old }
  foreach ($f in $fields) {
    $body = @{ dcfg_dataverse_path = $new } | ConvertTo-Json
    Invoke-RestMethod -Method Patch `
      -Uri "$baseURI/dcfg_template_fields($($f.dcfg_template_fieldid))" `
      -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
      -Body $body
  }
  Write-Host "F08: $old -> $new ($($fields.Count) fields)"
}
```

### Task 8: Fix F12 — Deactivate duplicate "Decades Workorder" template

- [ ] **Step 1: Deactivate the older duplicate**

```powershell
# "Decades Workorder" (701a0a1e) is the older duplicate. "Decades Work Order" (bd3d2a8b) is kept.
Invoke-RestMethod -Method Patch `
  -Uri "$baseURI/dcfg_document_templates(701a0a1e-c43d-f111-88b4-000d3a30860b)" `
  -Headers ($baseHeaders + @{ 'Content-Type' = 'application/json' }) `
  -Body '{"dcfg_is_active":false}'
Write-Host "F12: Deactivated duplicate 'Decades Workorder'"
```

### Task 9: Verify all data fixes + restore pac auth

- [ ] **Step 1: Re-run diagnostic query to confirm remaps**

```powershell
$after = (Invoke-RestMethod -Uri ($baseURI + "dcfg_template_fields?" +
  '$select=dcfg_dataverse_path&$filter=dcfg_is_mapped eq true') -Headers $baseHeaders).value
$broken = $after | Where-Object {
  $_.dcfg_dataverse_path -in @(
    'dcfg_wo_number','dcfg_contract_value','dcfg_msa.dcfg_msa_number',
    'dcfg_vendor.address1_line1','dcfg_vendor.address1_city_state_zip',
    'dcfg_vendor.fullname','dcfg_vendor.jobtitle','dcfg_vendor.dcfg_address_composite'
  )
}
Write-Host "Remaining broken paths: $($broken.Count) (should be 0)"
```

- [ ] **Step 2: Restore pac auth to Test**

Run: `pac auth select --index 2`

- [ ] **Step 3: Commit backup**

```bash
git add scripts/_backups/2026-04-27_template-field-remap-before.json
git commit -m "backup: template field mappings before F01-F08/F12 remap"
```

---

## Chunk 2: SPA Pipeline Fixes (Stream 2)

All files under `C:\DCFG\spa\dcfg-shell\src\` — **READ-ONLY policy: get explicit permission before editing.**

### Task 10: Fix F05 — ooxmlInject.js highlight matching

**Files:**
- Modify: `spa/dcfg-shell/src/lib/ooxmlInject.js:101`

The current code does strict equality. Change to normalized matching: trim whitespace, collapse internal whitespace, then check if either contains the other.

- [ ] **Step 1: Get SPA edit permission from operator**

- [ ] **Step 2: Edit ooxmlInject.js line 101**

Replace:
```javascript
        const match = scalars.find(f => f.sourceText === accText);
```

With:
```javascript
        const normAcc = accText.replace(/\s+/g, ' ').trim();
        const match = scalars.find(function(f) {
          var normSrc = f.sourceText.replace(/\s+/g, ' ').trim();
          return normSrc === normAcc || normAcc.indexOf(normSrc) !== -1 || normSrc.indexOf(normAcc) !== -1;
        });
```

This normalizes both sides (collapse whitespace + trim), then checks exact match OR contains in either direction. Handles: leading/trailing spaces, offset text, and run-splitting artifacts.

- [ ] **Step 3: Apply same fix to injectBlockField (line 166)**

Replace:
```javascript
    if (groups.includes(sourceText)) {
```

With:
```javascript
    var normSource = sourceText.replace(/\s+/g, ' ').trim();
    if (groups.some(function(g) {
      var ng = g.replace(/\s+/g, ' ').trim();
      return ng === normSource || ng.indexOf(normSource) !== -1 || normSource.indexOf(ng) !== -1;
    })) {
```

### Task 11: Fix F06 — Add MSA expand to contract re-fetch

**Files:**
- Modify: `spa/dcfg-shell/src/ContractComposer.jsx:827-830`

- [ ] **Step 1: Edit line 830 — add dcfg_msa_id to $expand**

Replace (line 827-830):
```javascript
        // 3. Fetch contract with vendor + property expands (skip dcfg_msa_id — not enabled for Web API)
        let fullContract;
        try {
          fullContract = await apiGet(`/${EntitySets.contracts}(${contractId})?$expand=dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_address,dcfg_city,dcfg_state,dcfg_zip,dcfg_phone,dcfg_email,dcfg_primary_contact,dcfg_signer_name,dcfg_signer_title,dcfg_trade,dcfg_net_terms,dcfg_insurance_expiration_date),dcfg_property_id($select=dcfg_propertyid,dcfg_name,dcfg_address)`);
```

With:
```javascript
        // 3. Fetch contract with vendor + property + msa expands
        let fullContract;
        try {
          fullContract = await apiGet(`/${EntitySets.contracts}(${contractId})?$expand=dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_address,dcfg_city,dcfg_state,dcfg_zip,dcfg_phone,dcfg_email,dcfg_primary_contact,dcfg_signer_name,dcfg_signer_title,dcfg_trade,dcfg_net_terms,dcfg_insurance_expiration_date),dcfg_property_id($select=dcfg_propertyid,dcfg_name,dcfg_address),dcfg_msa_id($select=dcfg_msaid,dcfg_name,dcfg_location_count,dcfg_monthly_rate,dcfg_total_monthly,dcfg_onboarding_rate,dcfg_total_onboarding,dcfg_budget_total,createdon)`);
```

### Task 12: Fix F09 — Parent contract navigation property name

**Files:**
- Modify: `spa/dcfg-shell/src/lib/contractDocGen.js:43-49`
- Modify: `spa/dcfg-shell/src/ContractComposer.jsx:830`

- [ ] **Step 1: Fix RELATION_MAP in contractDocGen.js line 48**

Replace:
```javascript
  'dcfg_wo':                  'dcfg_parent_contract_id',
```

With:
```javascript
  'dcfg_wo':                  'dcfg_contract_parent',
```

- [ ] **Step 2: Add dcfg_contract_parent to the $expand in ContractComposer.jsx line 830**

Append to the expand string (after the dcfg_msa_id expand added in Task 11):
```
,dcfg_contract_parent($select=dcfg_contractid,dcfg_contract_number,dcfg_contract_date,dcfg_contract_fee)
```

### Task 13: Fix F10 — Wire decades_handler composite

**Files:**
- Modify: `spa/dcfg-shell/src/lib/contractDocGen.js:83`

- [ ] **Step 1: Replace empty parts with config-based resolution**

Replace line 83:
```javascript
      decades_handler: { format: '{name}, {phone}, {email}', parts: { name: '', phone: '', email: '' } },
```

With:
```javascript
      decades_handler: { format: '{name}, {title}', parts: { name: '_config:dcfg_decades_signer_name', title: '_config:dcfg_decades_signer_title' } },
```

- [ ] **Step 2: Add config resolution in the composite loop (lines 89-96)**

Replace lines 89-96:
```javascript
    for (var ck in compParts) {
      var cp = compParts[ck];
      var cv = '';
      if (cp) {
        var resolved = resolveFieldValue(cp, contract, customer);
        cv = resolved ? resolved.value : '';
      }
      compResult = compResult.replace('{' + ck + '}', cv);
    }
```

With:
```javascript
    for (var ck in compParts) {
      var cp = compParts[ck];
      var cv = '';
      if (cp) {
        if (cp.startsWith('_config:')) {
          cv = (typeof window !== 'undefined' && window.__dcfg_config && window.__dcfg_config[cp.slice(8)]) || '';
        } else {
          var resolved = resolveFieldValue(cp, contract, customer);
          cv = resolved ? resolved.value : '';
        }
      }
      compResult = compResult.replace('{' + ck + '}', cv);
    }
```

- [ ] **Step 3: Verify loadConfig() populates window.__dcfg_config**

Check `portalApi.js` `loadConfig()` to confirm it stores config values on `window.__dcfg_config`. If it uses a different global, adjust the reference in Step 2.

### Task 14: Fix fieldRegistry.js — sync paths to match remapped data

**Files:**
- Modify: `spa/dcfg-shell/src/screens/templates/fieldRegistry.js:140,166`

The registry must match the remapped Dataverse paths so future uploads auto-map correctly.

- [ ] **Step 1: Fix WO Number path (line 140)**

Replace:
```javascript
  { label: 'WO Number',              path: 'dcfg_wo_number',            category: FieldCategory.Contract, isComposite: false },
```

With:
```javascript
  { label: 'WO Number',              path: 'dcfg_contract_number',      category: FieldCategory.Contract, isComposite: false },
```

- [ ] **Step 2: Fix MSA Number path (line 166)**

Replace:
```javascript
  { label: 'MSA Number',             path: 'dcfg_msa.dcfg_msa_number',              category: FieldCategory.Agreement, isComposite: false },
```

With:
```javascript
  { label: 'MSA Number',             path: 'dcfg_msa.dcfg_name',                    category: FieldCategory.Agreement, isComposite: false },
```

---

## Chunk 3: Template Screen Fixes (Stream 3)

### Task 15: Fix delete bug — add statecode filter to loadTemplates

**Files:**
- Modify: `spa/dcfg-shell/src/screens/templates/TemplateList.jsx:197-202`

- [ ] **Step 1: Add $filter=statecode eq 0 to the query**

Replace lines 197-202:
```javascript
      var query = '/' + EntitySets.docTemplates +
        '?$select=dcfg_document_templateid,dcfg_name,dcfg_template_type,dcfg_version,' +
        'dcfg_field_count,dcfg_mapped_count,dcfg_is_active,dcfg_uploaded_at,dcfg_uploaded_by,' +
        'dcfg_source_file_name,dcfg_notes,_dcfg_customer_id_value,dcfg_sharepoint_url,dcfg_source_file_url' +
        '&$expand=dcfg_customer_id($select=dcfg_name)' +
        '&$orderby=dcfg_uploaded_at desc';
```

With:
```javascript
      var query = '/' + EntitySets.docTemplates +
        '?$select=dcfg_document_templateid,dcfg_name,dcfg_template_type,dcfg_version,' +
        'dcfg_field_count,dcfg_mapped_count,dcfg_is_active,dcfg_uploaded_at,dcfg_uploaded_by,' +
        'dcfg_source_file_name,dcfg_notes,_dcfg_customer_id_value,dcfg_sharepoint_url,dcfg_source_file_url' +
        '&$expand=dcfg_customer_id($select=dcfg_name)' +
        '&$filter=statecode eq 0' +
        '&$orderby=dcfg_uploaded_at desc';
```

### Task 16: Add Edit button to template list actions

**Files:**
- Modify: `spa/dcfg-shell/src/screens/templates/TemplateList.jsx:524-548`

- [ ] **Step 1: Add Edit button before the View link in the Actions column**

Insert after line 524 (`onClick: function(e) { e.stopPropagation(); },`), before the View link:

```javascript
                h('button', {
                  onClick: function() { setView({ mode: 'detail', templateId: tpl.dcfg_document_templateid }); },
                  style: {
                    padding: '4px 10px', borderRadius: '4px', fontSize: '11px', fontWeight: 600,
                    border: '1px solid #CBD5E1', background: '#F8FAFC', color: NAVY, cursor: 'pointer',
                    whiteSpace: 'nowrap',
                  },
                  'data-testid': 'btn-edit-' + tpl.dcfg_document_templateid,
                }, 'Edit'),
```

### Task 17: Build, verify, and commit

- [ ] **Step 1: Build the SPA**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 2: Verify locally — check build output exists**

Run: `ls -la C:\DCFG\spa\dcfg-shell\dist\index.html`

- [ ] **Step 3: Commit all SPA changes**

```bash
git add spa/dcfg-shell/src/lib/ooxmlInject.js
git add spa/dcfg-shell/src/lib/contractDocGen.js
git add spa/dcfg-shell/src/ContractComposer.jsx
git add spa/dcfg-shell/src/screens/templates/TemplateList.jsx
git add spa/dcfg-shell/src/screens/templates/fieldRegistry.js
git commit -m "fix(docgen): 12 pipeline fixes — field remaps, expand, matching, template screen"
```

- [ ] **Step 4: Deploy to Prod (requires explicit approval)**

```bash
pac auth select --index 1
cd C:\DCFG\spa\dcfg-shell
pac pages upload-code-site --rootPath . --compiledPath dist
pac auth select --index 2
```

- [ ] **Step 5: Clear Prod portal cache**

Provide launch URL: `https://dmms1.powerappsportals.com/_services/about`

- [ ] **Step 6: Re-run field diagnostic to confirm all fixes**

Re-run `scratch/contract-field-diagnostic.ps1` against Prod. Expected: 0 FAIL, 0 MISSING schema paths.
