# WIP Drafts + WO Number Assignment Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Save as Draft to both wizards, WO number assignment in Send Queue, and amendment flow improvements — replacing the manual email + spreadsheet WO number process.

**Architecture:** Draft records use a new `WIP` status (invisible to existing views). Record created at Step 2 Next, PATCHed on subsequent steps. Exhibit A lines saved at Step 4. Send Queue gets a "Needs Work Order Number" tab. Amendment picker shows customer+location+vendor+date instead of WO number.

**Tech Stack:** React (inline JSX), Dataverse OData Web API, Power Pages Enhanced Data Model, PowerShell for schema deployment

**Spec:** `C:\DCFG\docs\superpowers\specs\2026-03-29-wip-drafts-wo-assignment-design.md`

**SPA Source:** `C:\DCFG\spa\dcfg-shell\src\` — **REQUIRES EXPLICIT EDIT PERMISSION**

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/deploy-wip-schema.ps1` | Create | Add WIP status, dcfg_wizard_step, dcfg_created_by_email to dcfg_contract |
| `src/portalApi.js` | Modify | Add WIP to ContractStatus, new API helpers, update fetchContractsByCustomer |
| `src/NewContractWizard.jsx` | Modify (major) | Draft save, My Drafts landing, amendment flow, abbreviation fixes |
| `src/NewProposalWizard.jsx` | Modify | Draft save pattern, abbreviation fixes |
| `src/screens/SendQueue.jsx` | Modify | Add "Needs Work Order Number" tab |
| `src/screens/ContractDetail.jsx` | Modify (minor) | Bug fix: user?.email → userEmail |
| `src/screens/Admin.jsx` | Modify (minor) | Bug fix: DOCTYPE_LABELS keys |
| `src/screens/Operations.jsx` | Modify (minor) | Abbreviation fixes |
| `src/screens/LocationDetail.jsx` | Modify (minor) | Abbreviation fixes |
| `src/screens/MsaList.jsx` | Modify (minor) | Abbreviation fix |
| `src/LocationManager.jsx` | Modify (minor) | Abbreviation fix |
| `src/ContractsList.jsx` | Modify (minor) | AP Code tooltip |
| `src/NavPanel.jsx` | Modify (minor) | Abbreviation fix |

---

## Chunk 1: Schema + API Layer

### Task 1: Deploy WIP schema to Test

**Files:**
- Create: `C:\DCFG\scripts\deploy-wip-schema.ps1`

- [ ] **Step 1: Write the schema deployment script**

```powershell
# deploy-wip-schema.ps1 — Add WIP status + draft tracking columns to dcfg_contract
# Run against each environment: Test (index 1), Stage (index 2), Prod (index 3)
$ErrorActionPreference = "Stop"

param(
    [string]$EnvUrl = "https://org0c17e98d.crm.dynamics.com/"
)

# Auth
$tokenObj = Get-AzAccessToken -ResourceUrl $EnvUrl -AsSecureString
$token = [System.Net.NetworkCredential]::new("", $tokenObj.Token).Password
$h = @{
    Authorization    = "Bearer $token"
    Accept           = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Content-Type"     = "application/json"
}
$api = "${EnvUrl}api/data/v9.2"

Write-Host "=== Deploying WIP schema to $EnvUrl ===" -ForegroundColor Cyan

# 1. Add WIP option (100000007) to dcfg_status picklist
Write-Host "`n[1/4] Adding WIP status option..." -ForegroundColor Yellow
try {
    $optionBody = @{
        Value = 100000007
        Label = @{
            LocalizedLabels = @(@{
                Label = "WIP"
                LanguageCode = 1033
            })
        }
        Description = @{
            LocalizedLabels = @(@{
                Label = "Work in progress - user still building in wizard"
                LanguageCode = 1033
            })
        }
    } | ConvertTo-Json -Depth 5

    $null = Invoke-RestMethod -Uri "$api/InsertOptionValue" -Method POST -Headers $h -Body $optionBody -ContentType "application/json; charset=utf-8" `
        -Body (@{
            AttributeLogicalName = "dcfg_status"
            EntityLogicalName = "dcfg_contract"
            Value = 100000007
            Label = @{ LocalizedLabels = @(@{ Label = "WIP"; LanguageCode = 1033 }) }
            Description = @{ LocalizedLabels = @(@{ Label = "Work in progress - user still building in wizard"; LanguageCode = 1033 }) }
            SolutionUniqueName = "DCFGSystemTest"
        } | ConvertTo-Json -Depth 5)
    Write-Host "  WIP option added (100000007)" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  WIP option already exists — skipping" -ForegroundColor DarkYellow
    } else { throw }
}

# 2. Add dcfg_wizard_step (Whole Number)
Write-Host "`n[2/4] Adding dcfg_wizard_step column..." -ForegroundColor Yellow
try {
    $wizardStepBody = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        SchemaName = "dcfg_wizard_step"
        DisplayName = @{ LocalizedLabels = @(@{ Label = "Wizard Step"; LanguageCode = 1033 }) }
        Description = @{ LocalizedLabels = @(@{ Label = "Last completed wizard step (1-5) for draft resume"; LanguageCode = 1033 }) }
        RequiredLevel = @{ Value = "None" }
        Format = "None"
        MinValue = 0
        MaxValue = 10
    } | ConvertTo-Json -Depth 5

    $null = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='dcfg_contract')/Attributes" -Method POST -Headers $h -Body $wizardStepBody -ContentType "application/json; charset=utf-8"
    Write-Host "  dcfg_wizard_step added" -ForegroundColor Green

    # Add to solution
    $null = Invoke-RestMethod -Uri "$api/AddSolutionComponent" -Method POST -Headers $h -Body (@{
        ComponentId = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='dcfg_contract')/Attributes(LogicalName='dcfg_wizard_step')?`$select=MetadataId" -Headers $h).MetadataId
        ComponentType = 2
        SolutionUniqueName = "DCFGSystemTest"
        AddRequiredComponents = $false
    } | ConvertTo-Json) -ContentType "application/json; charset=utf-8"
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  dcfg_wizard_step already exists — skipping" -ForegroundColor DarkYellow
    } else { throw }
}

# 3. Add dcfg_created_by_email (String 200)
Write-Host "`n[3/4] Adding dcfg_created_by_email column..." -ForegroundColor Yellow
try {
    $emailBody = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName = "dcfg_created_by_email"
        DisplayName = @{ LocalizedLabels = @(@{ Label = "Created By Email"; LanguageCode = 1033 }) }
        Description = @{ LocalizedLabels = @(@{ Label = "Portal user email who created this draft — used for My Drafts filter"; LanguageCode = 1033 }) }
        RequiredLevel = @{ Value = "None" }
        MaxLength = 200
        FormatName = @{ Value = "Email" }
    } | ConvertTo-Json -Depth 5

    $null = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='dcfg_contract')/Attributes" -Method POST -Headers $h -Body $emailBody -ContentType "application/json; charset=utf-8"
    Write-Host "  dcfg_created_by_email added" -ForegroundColor Green

    # Add to solution
    $null = Invoke-RestMethod -Uri "$api/AddSolutionComponent" -Method POST -Headers $h -Body (@{
        ComponentId = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='dcfg_contract')/Attributes(LogicalName='dcfg_created_by_email')?`$select=MetadataId" -Headers $h).MetadataId
        ComponentType = 2
        SolutionUniqueName = "DCFGSystemTest"
        AddRequiredComponents = $false
    } | ConvertTo-Json) -ContentType "application/json; charset=utf-8"
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  dcfg_created_by_email already exists — skipping" -ForegroundColor DarkYellow
    } else { throw }
}

# 4. Verify
Write-Host "`n[4/4] Verifying..." -ForegroundColor Yellow
$attrs = (Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='dcfg_contract')/Attributes?`$select=LogicalName&`$filter=LogicalName eq 'dcfg_wizard_step' or LogicalName eq 'dcfg_created_by_email'" -Headers $h).value
foreach ($a in $attrs) { Write-Host "  FOUND: $($a.LogicalName)" -ForegroundColor Green }

# Check status options
$statusAttr = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='dcfg_contract')/Attributes(LogicalName='dcfg_status')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet(`$select=Options)" -Headers $h
$wipOption = $statusAttr.OptionSet.Options | Where-Object { $_.Value -eq 100000007 }
if ($wipOption) { Write-Host "  FOUND: WIP status option (100000007)" -ForegroundColor Green }
else { Write-Host "  MISSING: WIP status option" -ForegroundColor Red }

Write-Host "`n=== MANUAL STEPS REQUIRED ===" -ForegroundColor Magenta
Write-Host "1. Add to site setting Webapi/dcfg_contract/fields:"
Write-Host "   dcfg_wizard_step,dcfg_created_by_email,dcfg_service_location_description"
Write-Host "2. Publish all customizations in solution DCFGSystemTest"
```

- [ ] **Step 2: Switch pac auth to Test and run the script**

```bash
pac auth select --index 1
pwsh C:\DCFG\scripts\deploy-wip-schema.ps1 -EnvUrl "https://org0c17e98d.crm.dynamics.com/"
```

Expected: All 3 items created (or "already exists"), verify shows FOUND for all.

- [ ] **Step 3: Operator manually adds columns to Web API site setting**

Add to `Webapi/dcfg_contract/fields` site setting on Test:
`dcfg_wizard_step,dcfg_created_by_email,dcfg_service_location_description`

- [ ] **Step 4: Operator publishes customizations**

---

### Task 2: Update portalApi.js — enums + new helpers

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\portalApi.js`

- [ ] **Step 1: Add WIP to ContractStatus enum (line 73)**

Change:
```javascript
export const ContractStatus = { Draft:100000000, Generated:100000001, Sent:100000002, SignedReceived:100000003, Closed:100000004, Void:100000005, Declined:100000006 };
```
To:
```javascript
export const ContractStatus = { WIP:100000007, Draft:100000000, Generated:100000001, Sent:100000002, SignedReceived:100000003, Closed:100000004, Void:100000005, Declined:100000006 };
```

- [ ] **Step 2: Add WIP to ContractStatusLabel (line 91)**

Change:
```javascript
export const ContractStatusLabel = { [ContractStatus.Draft]:'Draft',[ContractStatus.Generated]:'Generated',...
```
To:
```javascript
export const ContractStatusLabel = { [ContractStatus.WIP]:'In Progress',[ContractStatus.Draft]:'Draft',[ContractStatus.Generated]:'Generated',...
```

- [ ] **Step 3: Update fetchContractsByCustomer to include dcfg_contract_date (line 315)**

Change:
```javascript
export function fetchContractsByCustomer(customerId) { return apiGet(`/${EntitySets.contracts}?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_contract_type eq ${ContractType.WorkOrder}&$select=dcfg_contractid,dcfg_contract_number,dcfg_client_name,_dcfg_vendor_id_value,_dcfg_property_id_value&$orderby=dcfg_contract_date desc`); }
```
To:
```javascript
export function fetchContractsByCustomer(customerId) { return apiGet(`/${EntitySets.contracts}?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_contract_type eq ${ContractType.WorkOrder} and dcfg_status ne ${ContractStatus.Void}&$select=dcfg_contractid,dcfg_contract_number,dcfg_client_name,dcfg_contract_date,_dcfg_vendor_id_value,_dcfg_property_id_value,_dcfg_program_id_value&$orderby=dcfg_contract_date desc`); }
```

- [ ] **Step 4: Add new API helpers after fetchContractsByCustomer (after line 315)**

```javascript
// ── WIP DRAFTS ──
export function fetchMyWIPDrafts(userEmail) {
  return apiGet(`/${EntitySets.contracts}?$filter=dcfg_status eq ${ContractStatus.WIP} and dcfg_created_by_email eq '${userEmail.replace(/'/g, "''")}' and dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_number,dcfg_contract_type,dcfg_contract_date,dcfg_client_name,dcfg_wizard_step,dcfg_created_by_email,dcfg_service_location_description,modifiedon,_dcfg_customer_id_value,_dcfg_vendor_id_value,_dcfg_property_id_value,_dcfg_program_id_value&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name)&$orderby=modifiedon desc`);
}

export function updateContract(contractId, payload) {
  return apiPatch(`/${EntitySets.contracts}(${contractId})`, payload);
}

export function deleteContractLine(lineId) {
  return apiDelete(`/${EntitySets.contractLines}(${lineId})`);
}
```

- [ ] **Step 5: Add apiDelete helper (after apiPatch, around line 178)**

```javascript
export async function apiDelete(path) {
  const token = await getToken();
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`;
  const resp = await fetch(url, { method:'DELETE', headers:{ 'Accept':'application/json','OData-MaxVersion':'4.0','OData-Version':'4.0','__RequestVerificationToken':token }, credentials:'same-origin' });
  if (!resp.ok) { if (resp.status===403||resp.status===401) invalidateToken(); let msg='DELETE failed'; try { const j=await resp.json(); msg=j?.error?.message||msg; } catch {} throw new ApiError(resp.status,path,msg); }
}
```

- [ ] **Step 6: Verify build passes**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

---

## Chunk 2: Contract Wizard — Draft Save Infrastructure

### Task 3: Add draft save state + create WIP on Step 2 Next

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx`

- [ ] **Step 1: Add draft state variables (after line 122, in the state section)**

```javascript
// ═══════════════ DRAFT STATE ═══════════════
const [draftId, setDraftId] = useState(null);        // Contract GUID after first save
const [draftSaving, setDraftSaving] = useState(false);
const [draftSaved, setDraftSaved] = useState(false);  // Triggers "Draft saved" indicator
const [showDraftsLanding, setShowDraftsLanding] = useState(true); // Show My Drafts on open
const [myDrafts, setMyDrafts] = useState([]);
const [draftsLoading, setDraftsLoading] = useState(true);
```

- [ ] **Step 2: Add imports for new API functions (update import block at line 26-34)**

Add `fetchMyWIPDrafts, updateContract, deleteContractLine, fetchContractLines, ContractStatusLabel` to the import from `'./portalApi'`.

- [ ] **Step 3: Load My Drafts on mount (add to useEffect at line 136)**

```javascript
// Load user's WIP drafts
useEffect(() => {
  if (!userEmail) return;
  setDraftsLoading(true);
  fetchMyWIPDrafts(userEmail)
    .then(r => {
      const drafts = r?.value || [];
      setMyDrafts(drafts);
      if (drafts.length === 0) setShowDraftsLanding(false);
    })
    .catch(() => setMyDrafts([]))
    .finally(() => setDraftsLoading(false));
}, [userEmail]);
```

- [ ] **Step 4: Add saveDraft function (after handleCreateCustomer, around line 255)**

```javascript
const saveDraft = async (stepNum) => {
  if (draftSaving) return;
  setDraftSaving(true);
  setDraftSaved(false);
  try {
    const payload = {
      dcfg_status: ContractStatus.WIP,
      dcfg_wizard_step: stepNum,
      dcfg_contract_family: derivedFamily,
      dcfg_contract_type: contractType,
      dcfg_contract_date: contractDate,
      dcfg_client_name: selectedCustomer?.dcfg_name || selectedCustomer?.dcfg_display_name || '',
      dcfg_created_by_email: userEmail,
      ...odataBind('dcfg_customer_id', EntitySets.customers, customerId),
      ...(locationId ? odataBind('dcfg_property_id', EntitySets.properties, locationId) : {}),
      ...(vendor ? odataBind('dcfg_vendor_id', EntitySets.vendors, vendor.dcfg_vendorid) : {}),
      ...(selectedProgramId !== 'none' ? odataBind('dcfg_program_id', EntitySets.programs, selectedProgramId) : {}),
    };

    // Amendment-specific fields
    if (contractType === ContractType.Amendment && parentContractId) {
      payload['dcfg_parent_contract_id@odata.bind'] = `/${EntitySets.contracts}(${parentContractId})`;
      payload.dcfg_amendment_sequence = parseInt(amendmentNumber) || 1;
    }

    // Step 3+ fields
    if (stepNum >= 3) {
      payload.dcfg_contractor_legal_name = contractorLegalName;
      payload.dcfg_company = contractorCompany;
      payload.dcfg_contractor_address = contractorAddress;
      payload.dcfg_contractor_phone = contractorPhone;
      payload.dcfg_contractor_email = contractorEmail;
      payload.dcfg_payment_process = paymentProcess;
      payload.dcfg_signer_printed = signerName;
      payload.dcfg_signer_title = signerTitle;
      payload.dcfg_owner_contact = locContact.name;
      payload.dcfg_owner_title = locContact.title;
      payload.dcfg_owner_email = locContact.email;
      payload.dcfg_owner_street = locContact.street;
      payload.dcfg_owner_city = locContact.city;
      payload.dcfg_owner_state = locContact.state;
    }

    // Service location description (amendment only)
    if (contractType === ContractType.Amendment) {
      payload.dcfg_service_location_description = serviceLocationDesc || null;
    }

    if (draftId) {
      // PATCH existing draft
      await updateContract(draftId, payload);
    } else {
      // POST new draft
      const created = await apiPostReturn(`/${EntitySets.contracts}`, payload);
      const newId = created?.dcfg_contractid;
      if (newId) {
        setDraftId(newId);
        // Audit: draft created
        writeAuditLog({
          targetTable: 'dcfg_contract',
          targetRecordId: newId,
          actionType: AuditActionType.Created,
          performedBy: userEmail,
          newValue: `WIP draft created via wizard`,
          relatedContractId: newId,
        }).catch(e => console.warn('Audit write failed:', e));
      }
    }
    setDraftSaved(true);
    setTimeout(() => setDraftSaved(false), 2000);
  } catch (err) {
    console.error('Draft save failed:', err);
    setDraftSaved('error');
  } finally {
    setDraftSaving(false);
  }
};
```

- [ ] **Step 5: Add serviceLocationDesc state (in Step 2 state section, after line 101)**

```javascript
const [serviceLocationDesc, setServiceLocationDesc] = useState('');
```

- [ ] **Step 6: Wire saveDraft into the Next button handler (modify lines 960-968)**

Replace the current Next button onClick:
```javascript
onClick={() => { if (step === 1 && !customerId) return; setStep(sv => sv + 1); }}
```
With:
```javascript
onClick={async () => {
  if (step === 1 && !customerId) return;
  if (step === 2) await saveDraft(2);
  else if (step === 3) await saveDraft(3);
  else if (step === 4) {
    await saveDraft(4);
    await saveLinesToDataverse();
  }
  setStep(sv => sv + 1);
}}
```

- [ ] **Step 7: Verify build passes**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

---

### Task 4: Save Exhibit A lines to Dataverse at Step 4

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx`

- [ ] **Step 1: Add saveLinesToDataverse function (after saveDraft)**

```javascript
const saveLinesToDataverse = async () => {
  if (!draftId) return;
  try {
    // Delete existing lines for this draft
    const existing = await fetchContractLines(draftId);
    const existingLines = existing?.value || [];
    for (const el of existingLines) {
      await deleteContractLine(el.dcfg_contract_lineid);
    }
    // Create new lines from current state
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineAmount = parseFloat(String(line.amount).replace(/,/g, '')) || 0;
      if (!line.description && !lineAmount) continue;
      await createContractLine({
        dcfg_item_number: i + 1,
        dcfg_description: line.description,
        dcfg_amount: lineAmount,
        ...odataBind('dcfg_contract_id', EntitySets.contracts, draftId),
        ...(line.costCodeId ? odataBind('dcfg_cost_code_id', EntitySets.costCodes, line.costCodeId) : {}),
      });
    }
  } catch (err) {
    console.error('Failed to save lines:', err);
    toast.show('warn', 'Line items may not have saved — check before generating.');
  }
};
```

- [ ] **Step 2: Modify handleGenerate to PATCH instead of POST (lines 280-370)**

Replace the generate handler. Key changes:
- If `draftId` exists, PATCH the draft with final fields + status change to Draft
- Skip line creation (already saved at Step 4)
- If no `draftId` (shouldn't happen but defensive), fall back to POST

```javascript
const handleGenerate = async () => {
  setGenerating(true);
  try {
    const payload = {
      dcfg_status: ContractStatus.Draft,
      dcfg_wizard_step: 5,
      dcfg_contract_family: derivedFamily,
      dcfg_contract_type: contractType,
      dcfg_contract_date: contractDate,
      dcfg_client_name: selectedCustomer?.dcfg_name || selectedCustomer?.dcfg_display_name || '',
      dcfg_contractor_legal_name: contractorLegalName,
      dcfg_company: contractorCompany,
      dcfg_contractor_address: contractorAddress,
      dcfg_contractor_phone: contractorPhone,
      dcfg_contractor_email: contractorEmail,
      dcfg_payment_process: paymentProcess,
      dcfg_signer_printed: signerName,
      dcfg_signer_title: signerTitle,
      dcfg_owner_contact: locContact.name,
      dcfg_owner_title: locContact.title,
      dcfg_owner_email: locContact.email,
      dcfg_owner_street: locContact.street,
      dcfg_owner_city: locContact.city,
      dcfg_owner_state: locContact.state,
      dcfg_contract_fee: linesTotal,
      ...odataBind('dcfg_customer_id', EntitySets.customers, customerId),
      ...(locationId ? odataBind('dcfg_property_id', EntitySets.properties, locationId) : {}),
      ...(vendor ? odataBind('dcfg_vendor_id', EntitySets.vendors, vendor.dcfg_vendorid) : {}),
      ...(selectedProgramId !== 'none' ? odataBind('dcfg_program_id', EntitySets.programs, selectedProgramId) : {}),
    };

    if (contractType === ContractType.Amendment && parentContractId) {
      payload['dcfg_parent_contract_id@odata.bind'] = `/${EntitySets.contracts}(${parentContractId})`;
      payload.dcfg_amendment_sequence = parseInt(amendmentNumber) || 1;
    }
    if (contractType === ContractType.Amendment) {
      payload.dcfg_service_location_description = serviceLocationDesc || null;
    }

    let contractId, contractNumber;

    if (draftId) {
      // PATCH existing WIP → Draft
      toast.show('info', 'Finalizing contract record\u2026');
      await updateContract(draftId, payload);
      contractId = draftId;
      // Re-fetch to get contract number (may have been assigned by Send Queue)
      const refreshed = await apiGet(`/${EntitySets.contracts}(${draftId})?$select=dcfg_contract_number`);
      contractNumber = refreshed?.dcfg_contract_number || 'DRAFT';

      // Re-save lines (in case user edited after Step 4)
      await saveLinesToDataverse();
    } else {
      // Fallback: POST new record (shouldn't happen in normal flow)
      toast.show('info', 'Creating contract record\u2026');
      const created = await createContract(payload);
      contractId = created?.dcfg_contractid;
      contractNumber = created?.dcfg_contract_number || 'DRAFT';

      // Create lines
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const lineAmount = parseFloat(String(line.amount).replace(/,/g, '')) || 0;
        if (!line.description && !lineAmount) continue;
        await createContractLine({
          dcfg_item_number: i + 1,
          dcfg_description: line.description,
          dcfg_amount: lineAmount,
          ...odataBind('dcfg_contract_id', EntitySets.contracts, contractId),
          ...(line.costCodeId ? odataBind('dcfg_cost_code_id', EntitySets.costCodes, line.costCodeId) : {}),
        });
      }
    }

    toast.show('info', 'Submitting document generation request\u2026');
    let docResult = null;
    try {
      docResult = await createDocumentRequest({
        requestType: DocRequestType.DocGen,
        requestedBy: userEmail,
        name: `DocGen ${contractNumber}`,
        contractId: contractId,
        templateId: null,
        notes: `Family: ${ContractFamilyLabel[derivedFamily]}, Type: ${ContractTypeLabel[contractType]}`,
      });
    } catch (flowErr) {
      console.warn('Document request creation failed:', flowErr);
      toast.show('warn', 'Document generation request failed \u2014 check document_request table.');
    }

    writeAuditLog({
      targetTable: 'dcfg_contract',
      targetRecordId: contractId,
      actionType: AuditActionType.Generated,
      performedBy: userEmail,
      newValue: `Generated ${contractNumber} via wizard`,
      relatedContractId: contractId,
    }).catch(e => console.warn('Audit write failed:', e));

    setGenResult({
      contractId,
      contractNumber,
      docUrl: docResult?.document_url || null,
      fileName: docResult?.file_name || `${(selectedCustomer?.dcfg_name || 'Contract').replace(/\s+/g, '_')}_${contractNumber}.docx`,
    });
    toast.show('ok', `Contract generated \u00b7 ${contractNumber} saved.`);
  } catch (err) {
    toast.show('err', `Generation failed: ${err.message}`);
  } finally {
    setGenerating(false);
  }
};
```

- [ ] **Step 3: Verify build passes**

---

### Task 5: My Drafts Landing + Resume

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx`

- [ ] **Step 1: Add resumeDraft function (after saveDraft)**

```javascript
const resumeDraft = async (draft) => {
  setShowDraftsLanding(false);
  setDraftId(draft.dcfg_contractid);
  setCustomerId(draft._dcfg_customer_id_value || '');
  setContractType(draft.dcfg_contract_type ?? ContractType.WorkOrder);
  setContractDate(draft.dcfg_contract_date?.split('T')[0] || new Date().toISOString().split('T')[0]);
  setLocationId(draft._dcfg_property_id_value || '');
  setSelectedProgramId(draft._dcfg_program_id_value || 'none');
  setServiceLocationDesc(draft.dcfg_service_location_description || '');

  if (draft._dcfg_vendor_id_value && draft.dcfg_vendor_id) {
    setVendor({
      dcfg_vendorid: draft._dcfg_vendor_id_value,
      dcfg_legal_name: draft.dcfg_vendor_id?.dcfg_legal_name,
      dcfg_display_name: draft.dcfg_vendor_id?.dcfg_display_name,
    });
  }

  // Load lines if step >= 4
  if ((draft.dcfg_wizard_step || 0) >= 4) {
    try {
      const linesRes = await fetchContractLines(draft.dcfg_contractid);
      const savedLines = (linesRes?.value || []).map(l => ({
        costCodeId: l._dcfg_cost_code_id_value || '',
        costCodeName: l.dcfg_cost_code_id?.dcfg_description || '',
        description: l.dcfg_description || '',
        amount: l.dcfg_amount != null ? String(l.dcfg_amount) : '',
        apCode: l.dcfg_cost_code_id?.dcfg_customer_ap_code || '',
      }));
      if (savedLines.length > 0) setLines(savedLines);
    } catch {}
  }

  // Jump to saved step (user starts FROM that step, progresses forward)
  setStep(Math.min(draft.dcfg_wizard_step || 1, 5));
};
```

- [ ] **Step 2: Add deleteDraft function**

```javascript
const deleteDraft = async (draftContractId) => {
  try {
    await updateContract(draftContractId, { dcfg_active_flag: false });
    setMyDrafts(prev => prev.filter(d => d.dcfg_contractid !== draftContractId));
    writeAuditLog({
      targetTable: 'dcfg_contract',
      targetRecordId: draftContractId,
      actionType: AuditActionType.Deleted,
      performedBy: userEmail,
      newValue: 'WIP draft deleted by user',
      relatedContractId: draftContractId,
    }).catch(() => {});
    toast.show('ok', 'Draft deleted.');
    if (myDrafts.length <= 1) setShowDraftsLanding(false);
  } catch (err) {
    toast.show('err', `Failed to delete draft: ${err.message}`);
  }
};
```

- [ ] **Step 3: Add My Drafts landing JSX (before the stepper bar, inside the return)**

Insert before the stepper bar (`<div style={s.stepperBar}>`):

```jsx
{showDraftsLanding && (
  <div style={{ display: 'flex', flexDirection: 'column', flex: 1, padding: '48px 24px', maxWidth: 700, margin: '0 auto' }}>
    <h1 style={s.pageTitle}>Contract Wizard</h1>
    <p style={s.pageDesc}>Resume a draft or start a new contract.</p>

    {draftsLoading ? (
      <p style={{ color: C.text3, textAlign: 'center', padding: 40 }}>Loading drafts...</p>
    ) : (
      <>
        {myDrafts.length > 0 && (
          <>
            <div style={s.sectionLabel}>YOUR DRAFTS ({myDrafts.length})</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 28 }}>
              {myDrafts.map(d => (
                <div key={d.dcfg_contractid} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 18px', border: `1px solid ${C.border}`, borderRadius: 10, background: '#fff' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 14, fontWeight: 600, color: C.navy }}>
                      {d.dcfg_customer_id?.dcfg_name || 'Unknown Customer'}
                      {' \u2014 '}
                      {ContractTypeLabel[d.dcfg_contract_type] || 'Contract'}
                    </div>
                    <div style={{ fontSize: 12, color: C.text3, marginTop: 3 }}>
                      {d.dcfg_property_id?.dcfg_name || 'No location'}
                      {' \u00b7 '}
                      Step {d.dcfg_wizard_step || 1} of 5
                      {' \u00b7 '}
                      Saved {new Date(d.modifiedon).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                    </div>
                  </div>
                  {d.dcfg_contract_number && (
                    <span style={{ ...s.msaBadge, background: C.greenLt, color: C.green }}>WO# assigned</span>
                  )}
                  <button style={s.btnSmall} onClick={() => resumeDraft(d)}>Resume</button>
                  <button style={{ ...s.btnSmallSec, color: C.red, borderColor: C.red }}
                    onClick={() => { if (confirm('Delete this draft? This cannot be undone.')) deleteDraft(d.dcfg_contractid); }}>
                    Delete
                  </button>
                </div>
              ))}
            </div>
          </>
        )}

        <button style={{ ...s.btnNext, alignSelf: 'flex-start', fontSize: 14, padding: '11px 24px' }}
          onClick={() => setShowDraftsLanding(false)}>
          + Start New Contract
        </button>
      </>
    )}
  </div>
)}
```

- [ ] **Step 4: Wrap stepper + content in conditional (only show when not on landing)**

Wrap the existing stepper bar and step content in `{!showDraftsLanding && ( ... )}`.

- [ ] **Step 5: Add "Draft saved" indicator to stepper bar**

In the stepper bar div, after the STEPS map, add:
```jsx
{draftSaved === true && (
  <div style={{ position: 'absolute', right: 16, top: '50%', transform: 'translateY(-50%)', fontSize: 11, color: C.green, fontWeight: 600, opacity: 0.8, transition: 'opacity 0.5s' }}>
    Draft saved
  </div>
)}
{draftSaved === 'error' && (
  <div style={{ position: 'absolute', right: 16, top: '50%', transform: 'translateY(-50%)', fontSize: 11, color: C.red, fontWeight: 600 }}>
    Save failed
  </div>
)}
```

(Add `position: 'relative'` to the stepperBar style.)

- [ ] **Step 6: Verify build passes**

---

## Chunk 3: Amendment Flow + Send Queue

### Task 6: Amendment flow improvements

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx`

- [ ] **Step 1: Update parent WO picker display format (Step 2, lines 550-556)**

Replace the parent WO dropdown option text:
```jsx
{parentContracts.map(pc => {
  const locName = locations.find(l => l.dcfg_propertyid === pc._dcfg_property_id_value)?.dcfg_name;
  const vendName = allVendors.find(v => v.dcfg_vendorid === pc._dcfg_vendor_id_value)?.dcfg_legal_name;
  const dateStr = pc.dcfg_contract_date ? new Date(pc.dcfg_contract_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '';
  const woNum = pc.dcfg_contract_number ? ` (${pc.dcfg_contract_number})` : '';
  return (
    <option key={pc.dcfg_contractid} value={pc.dcfg_contractid}>
      {[pc.dcfg_client_name, locName, vendName, dateStr].filter(Boolean).join(' \u2014 ')}{woNum}
    </option>
  );
})}
```

- [ ] **Step 2: Add Service Location Description field (after amendment number, in the Amendment section)**

After the amendment number field (around line 562):
```jsx
<div style={{ marginTop: 12 }}>
  <label style={s.fieldLabel}>Service Location Description</label>
  <textarea style={{ ...s.finput, minHeight: 80, resize: 'vertical' }}
    placeholder="Describe where the work is performed..."
    value={serviceLocationDesc}
    onChange={e => setServiceLocationDesc(e.target.value)} />
</div>
```

- [ ] **Step 3: Add Step 5 warning for missing description on amendments**

In Step 5, before the summary cards (around line 910), add:
```jsx
{contractType === ContractType.Amendment && !serviceLocationDesc && (
  <div style={s.warnNote}>Service location description not provided</div>
)}
```

- [ ] **Step 4: Add service_location_description to the generate payload**

Already handled in Task 4 Step 2 (handleGenerate includes it for amendments).

- [ ] **Step 5: Verify build passes**

---

### Task 7: Send Queue — "Needs Work Order Number" tab

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\SendQueue.jsx`

- [ ] **Step 1: Add WIP import and state (update import at line 12, add state)**

Add `ContractStatus` import already exists. Add to ContractStatus import if `WIP` not there.

Add state for WO number assignment:
```javascript
const [wipContracts, setWipContracts] = useState([]);
const [woNumberInputs, setWoNumberInputs] = useState({}); // contractId -> input value
```

- [ ] **Step 2: Load WIP contracts in loadAll (add to Promise.all around line 105)**

Add a 5th fetch to the Promise.all:
```javascript
apiGet(`/${EntitySets.contracts}?$filter=dcfg_status eq 100000007 and dcfg_contract_number eq null and dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_type,dcfg_client_name,dcfg_contract_date,dcfg_created_by_email,createdon&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name),dcfg_program_id($select=dcfg_programid,dcfg_name)&$orderby=createdon desc`).catch(() => ({ value: [] })),
```

And in the destructure/setState, add:
```javascript
setWipContracts(wipRes?.value ?? []);
```

- [ ] **Step 3: Add "Needs Work Order Number" tab button (in the queue tab row)**

Find the queue tab buttons and add a new tab:
```jsx
<button onClick={() => setQueueTab('wo-number')}
  style={{ ...tabStyle, ...(queueTab === 'wo-number' ? tabActiveStyle : {}) }}>
  Needs Work Order Number {wipContracts.length > 0 && <Badge bg={AMBER} color="#fff" style={{ marginLeft: 6 }}>{wipContracts.length}</Badge>}
</button>
```

- [ ] **Step 4: Add the WO number assignment panel (in the queue content area)**

```jsx
{queueTab === 'wo-number' && (
  <div>
    {wipContracts.length === 0 ? (
      <div style={{ padding: 40, textAlign: 'center', color: MUTED, fontSize: 13 }}>No contracts awaiting Work Order numbers.</div>
    ) : (
      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr>
            <th style={thStyle}>Customer</th>
            <th style={thStyle}>Type</th>
            <th style={thStyle}>Location</th>
            <th style={thStyle}>Vendor</th>
            <th style={thStyle}>Program</th>
            <th style={thStyle}>Created By</th>
            <th style={thStyle}>Date</th>
            <th style={{ ...thStyle, width: 200 }}>Assign Work Order Number</th>
          </tr>
        </thead>
        <tbody>
          {wipContracts.map(wip => (
            <tr key={wip.dcfg_contractid}>
              <td style={tdStyle}>{wip.dcfg_customer_id?.dcfg_name || '\u2014'}</td>
              <td style={tdStyle}><Badge {...(TYPE_BADGE[wip.dcfg_contract_type] || { bg:'#eee', color:'#666' })}>{TYPE_BADGE[wip.dcfg_contract_type]?.label || '\u2014'}</Badge></td>
              <td style={tdStyle}>{wip.dcfg_property_id?.dcfg_name || '\u2014'}</td>
              <td style={tdStyle}>{wip.dcfg_vendor_id?.dcfg_legal_name || '\u2014'}</td>
              <td style={tdStyle}>{wip.dcfg_program_id?.dcfg_name || '\u2014'}</td>
              <td style={tdStyle}><span style={{ fontSize: 11, color: MUTED }}>{wip.dcfg_created_by_email || '\u2014'}</span></td>
              <td style={tdStyle}>{fmtDate(wip.createdon)}</td>
              <td style={tdStyle}>
                <div style={{ display: 'flex', gap: 6 }}>
                  <input style={{ ...inputStyle, flex: 1, fontSize: 12 }}
                    placeholder="WO-2026-..."
                    value={woNumberInputs[wip.dcfg_contractid] || ''}
                    onChange={e => setWoNumberInputs(p => ({ ...p, [wip.dcfg_contractid]: e.target.value }))}
                    onKeyDown={e => { if (e.key === 'Enter') assignWoNumber(wip.dcfg_contractid); }} />
                  <button style={btnPrimary}
                    disabled={!woNumberInputs[wip.dcfg_contractid]?.trim()}
                    onClick={() => assignWoNumber(wip.dcfg_contractid)}>
                    Assign
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    )}
  </div>
)}
```

- [ ] **Step 5: Add assignWoNumber handler**

```javascript
async function assignWoNumber(contractId) {
  const number = woNumberInputs[contractId]?.trim();
  if (!number) return;
  setActionBusy(contractId);
  try {
    await apiPatch(`/${EntitySets.contracts}(${contractId})`, { dcfg_contract_number: number });
    toast.show('ok', `Work Order number ${number} assigned.`);
    setWipContracts(prev => prev.filter(w => w.dcfg_contractid !== contractId));
    setWoNumberInputs(prev => { const n = { ...prev }; delete n[contractId]; return n; });
    writeAuditLog({
      targetTable: 'dcfg_contract',
      targetRecordId: contractId,
      actionType: AuditActionType.DataUpdated,
      performedBy: user?.email || 'unknown',
      newValue: `WO number assigned: ${number}`,
      relatedContractId: contractId,
    }).catch(() => {});
  } catch (err) {
    toast.show('err', `Failed to assign number: ${err.message}`);
  }
  setActionBusy(null);
}
```

- [ ] **Step 6: Verify build passes**

---

## Chunk 4: Code Review Fixes (All Abbreviations + Bugs)

### Task 8: Fix all abbreviations across SPA

**Files:**
- Modify: Multiple files (see table below)

- [ ] **Step 1: NewContractWizard.jsx abbreviations**

Line 52: `'WO, Amendment, or Vendor MSA'` → `'Work Order, Amendment, or Vendor MSA'`
Line 471: `"Standalone WO"` → `"Standalone Work Order"`
Line 833: `"Verify all merge fields before generating the contract document."` → `"Verify all contract details before generating the document."`

- [ ] **Step 2: NewProposalWizard.jsx abbreviations**

Line 461: `'ST'` → `'State'` (in add-location form label)
Line 469: `'ST'` → `'State'` and `'$/Mo'` → `'Monthly Rate'` (in table headers)
Line 505: `'Mo. Rate (recurring)'` → `'Monthly Rate (recurring)'` (fee summary)
Line 535: `'$/Mo'` → `'Monthly Rate'` (in second table headers)
Line 538: `'NC'` badge → `'No Charge'`
Line 569: `'Mo. Rate (recurring)'` → `'Monthly Rate (recurring)'` (second fee summary)

- [ ] **Step 3: Operations.jsx abbreviations**

Line 90: `'Med'` → `'Medium'` (priority badge)
Line 359: `'WO'` → `'Work Order'` and `'WR'` → `'Work Request'` (filter labels)

- [ ] **Step 4: SendQueue.jsx abbreviation**

Line 57: `label:'MSA'` → `label:'Vendor MSA'`

- [ ] **Step 5: Admin.jsx abbreviation + bug fix**

Line 23: `{ 0: 'Work Order', 1: 'Amendment', 2: 'MSA' }` → `{ 100000000: 'Work Order', 100000001: 'Amendment', 100000002: 'Vendor MSA' }`

- [ ] **Step 6: LocationDetail.jsx abbreviations**

Lines 76: `'Sprinkler Last Insp.'` → `'Sprinkler Last Inspection'`
Lines 79-80: `'Water Treat. Last'` → `'Water Treatment Last'`, `'Water Treat. Due'` → `'Water Treatment Due'`
Lines 84-87: Add `title` attributes: `'IDD Last'` → `title="Intellectual/Developmental Disabilities"`, `'DCA Last'` → `title="Department of Community Affairs"`

- [ ] **Step 7: LocationManager.jsx abbreviation**

Line 314: `'Water Treat.'` → `'Water Treatment'`

- [ ] **Step 8: ContractsList.jsx tooltip**

Line 415: `<th style={s.th}>AP Code</th>` → `<th title="Accounts Payable Code" style={s.th}>AP Code</th>`

- [ ] **Step 9: NavPanel.jsx + MsaList.jsx**

NavPanel line 39: `label: 'MSAs'` → `label: 'Master Service Agreements'`
MsaList line 37: `'MSAs'` heading → `'Master Service Agreements'`

- [ ] **Step 10: Verify build passes**

---

### Task 9: Fix critical bugs

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\ContractDetail.jsx:68`
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx:354`

- [ ] **Step 1: ContractDetail.jsx — fix undefined user reference**

Line 68: `requestedBy: user?.email || 'unknown'` → `requestedBy: userEmail || 'unknown'`

- [ ] **Step 2: NewContractWizard.jsx — fix audit log field name**

Line 354 (now in the new handleGenerate): Ensure all `writeAuditLog` calls use `performedBy: userEmail` not just `userEmail,` as a bare property.

(Already fixed in the new handleGenerate code from Task 4. Verify.)

- [ ] **Step 3: Verify build passes**

---

## Chunk 5: Proposal Wizard Draft Save + Build + Deploy

### Task 10: Add draft save to Proposal Wizard

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewProposalWizard.jsx`

This follows the identical pattern as Contract Wizard but:
- Uses the same WIP status + dcfg_wizard_step + dcfg_created_by_email fields
- No Send Queue integration (proposals have their own numbering)
- No service location description
- My Drafts landing shows "Your Proposal Drafts" / "+ Start New Proposal"

- [ ] **Step 1: Read the full NewProposalWizard.jsx to identify insertion points**
- [ ] **Step 2: Add draft state variables (mirror Contract Wizard)**
- [ ] **Step 3: Add fetchMyWIPDrafts call filtered to proposal type**

Note: Need to differentiate contract vs proposal WIP drafts. Filter by `dcfg_contract_type`:
- Contract Wizard shows drafts where type = WorkOrder, Amendment, or ContractorMSA
- Proposal Wizard needs a different approach — proposals may use a different table or type

**DECISION NEEDED:** Does the Proposal Wizard create records in `dcfg_contracts` or a different table? Read the file to determine. If same table, filter by a proposal-specific type. If different table, adjust API calls accordingly.

- [ ] **Step 4: Add saveDraft, resumeDraft, deleteDraft functions**
- [ ] **Step 5: Add My Drafts landing JSX**
- [ ] **Step 6: Wire saveDraft into Next button**
- [ ] **Step 7: Verify build passes**

### Task 11: Build + Deploy to Test

- [ ] **Step 1: Full build**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

- [ ] **Step 2: Deploy to Test**

```bash
pac auth select --index 1
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 3: Clear portal cache**

Navigate to: `https://dcfg.powerappsportals.com/_services/about`
Click "Clear Cache"

- [ ] **Step 4: Provide launch URLs**

Test SPA: https://dcfg.powerappsportals.com
Cache clear: https://dcfg.powerappsportals.com/_services/about

- [ ] **Step 5: Functional test**

Open the Contract Wizard:
1. Verify My Drafts landing appears (or skips if no drafts)
2. Select customer → select doc type → click Next → verify "Draft saved" appears
3. Close browser → reopen wizard → verify draft appears in My Drafts
4. Resume draft → verify fields pre-filled at correct step
5. Delete a draft → verify soft delete
6. Complete wizard through Generate → verify works end-to-end
7. Check Send Queue → verify "Needs Work Order Number" tab shows the WIP record
8. Assign a WO number → verify it writes back

---

## Verification Checklist

### Draft Save
- [ ] Draft created on Step 2 Next (status = WIP)
- [ ] Draft invisible in ContractsList, SalesDashboard, existing Send Queue tabs
- [ ] Auto-save PATCHes on Steps 3→4 and 4→5
- [ ] Exhibit A lines saved to Dataverse at Step 4
- [ ] "Draft saved" indicator appears briefly in stepper bar
- [ ] Save failure shows persistent red "Save failed"
- [ ] Step 5 Generate PATCHes WIP → Draft (not POST)

### My Drafts
- [ ] Landing shows only current user's WIP drafts
- [ ] Skip landing if no drafts (straight to Step 1)
- [ ] Resume loads at correct step with all fields pre-filled
- [ ] Lines restored on resume if step >= 4
- [ ] "WO# assigned" badge shows when contract_number populated
- [ ] Delete soft-deletes (dcfg_active_flag = false)

### Send Queue
- [ ] "Needs Work Order Number" tab visible
- [ ] Shows all WIP contracts without dcfg_contract_number
- [ ] Shows customer, type, location, vendor, program, created by, date
- [ ] Inline input + Assign button works
- [ ] Assigned number writes to dcfg_contract_number via PATCH
- [ ] Record disappears from tab after assignment

### Amendment Flow
- [ ] Parent WO picker shows: Customer — Location — Vendor — Date (WO# if assigned)
- [ ] Service Location Description field appears for amendments only
- [ ] Skipping description shows orange warning on Step 5
- [ ] Generate still works with empty description

### Abbreviations
- [ ] No "WO" abbreviation in any label (check: stepper sub, program card, operations filters)
- [ ] No "ST", "$/Mo", "Mo. Rate", "NC", "Med", "Insp.", "Water Treat." in labels
- [ ] "MSA" badge → "Vendor MSA" in Send Queue and Admin
- [ ] "MSAs" nav → "Master Service Agreements"
- [ ] AP Code has tooltip everywhere
- [ ] IDD/DCA have tooltips

### Bug Fixes
- [ ] ContractDetail Generate button doesn't crash (userEmail fix)
- [ ] Audit logs have performedBy populated (not undefined)
- [ ] Admin DOCTYPE_LABELS shows correct doc types (not all dashes)
