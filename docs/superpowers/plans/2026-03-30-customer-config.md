# Customer Config Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Customer Config tab to Admin with Blanket Work Orders, Customer AP Code Mappings, and Customer Template Overrides — plus Send Queue blanket-aware WO assignment and wizard AP code resolution.

**Architecture:** Two new Dataverse tables (dcfg_blanket_workorder, dcfg_customer_ap_mapping), one modified table (dcfg_document_template gets customer lookup), one new field on dcfg_contract (dcfg_blanket_number). New Admin tab with customer selector + 3 sections. Send Queue reads blanket records at approval time. Contract wizard resolves AP codes customer-first.

**Tech Stack:** PowerShell (Dataverse REST API for schema), React 16 (SPA components), Power Pages Web API (OData)

**Target:** Test environment only (org0c17e98d.crm.dynamics.com, pac auth index [1])

**Spec:** `docs/superpowers/specs/2026-03-30-customer-config-design.md`

---

## Chunk 1: Schema Deployment (Dataverse)

### Task 1: Create `dcfg_blanket_workorder` table + columns

**Files:**
- Create: `C:\DCFG\scripts\deploy-customer-config-schema.ps1`

- [ ] **Step 1: Write the schema deployment script**

The script creates the `dcfg_blanket_workorder` table with all columns. Uses the proven pattern from `deploy-wip-schema.ps1`: pac auth token + REST API, idempotent (skips if exists).

```powershell
param(
    [string]$EnvUrl = "https://org0c17e98d.crm.dynamics.com/"
)
# deploy-customer-config-schema.ps1
# Creates: dcfg_blanket_workorder table, dcfg_customer_ap_mapping table
# Modifies: dcfg_document_template (add dcfg_customer_id), dcfg_contract (add dcfg_blanket_number)
# Usage: pwsh deploy-customer-config-schema.ps1 -EnvUrl "https://org0c17e98d.crm.dynamics.com/"
```

Table creation via `POST /EntityDefinitions` with:
- `dcfg_blanket_workorder`: PK, dcfg_name (primary), dcfg_customer_id (Lookup), dcfg_dollar_threshold (Money), dcfg_job_number (String 50), dcfg_effective_year (Integer), dcfg_active_flag (Boolean default true)
- `dcfg_customer_ap_mapping`: PK, dcfg_name (primary), dcfg_customer_id (Lookup), dcfg_cost_code_id (Lookup), dcfg_ap_code (String 50), dcfg_active_flag (Boolean default true)

Add columns to existing tables:
- `dcfg_document_template`: dcfg_customer_id (Lookup → dcfg_customer, nullable)
- `dcfg_contract`: dcfg_blanket_number (String 50, nullable)

All wrapped in try/catch with "already exists" skip pattern. SolutionUniqueName = "DCFGSystemTest".

- [ ] **Step 2: Run the script against Test**

```bash
pwsh C:\DCFG\scripts\deploy-customer-config-schema.ps1 -EnvUrl "https://org0c17e98d.crm.dynamics.com/"
```

Expected: All items created or skipped-if-exists. No errors.

- [ ] **Step 3: Publish customizations**

```bash
pwsh C:\DCFG\scripts\publish-customizations.ps1
```

Or inline:
```powershell
$token = (Get-AzAccessToken -ResourceUrl "https://org0c17e98d.crm.dynamics.com/" -AsSecureString)
# POST /PublishAllXml
```

- [ ] **Step 4: Verify tables exist via metadata API**

```bash
pac auth select --index 1
curl.exe -s -H "Authorization: Bearer $TOKEN" "https://org0c17e98d.crm.dynamics.com/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_blanket_workorder')?$select=LogicalName,EntitySetName" | jq .EntitySetName
```

Expected: `"dcfg_blanket_workorders"`

- [ ] **Step 5: Commit**

```bash
git add scripts/deploy-customer-config-schema.ps1
git commit -m "feat: schema deployment script for customer config tables"
```

---

### Task 2: Deploy site settings + table permissions

**Files:**
- Create: `C:\DCFG\scripts\deploy-customer-config-sitesettings.ps1`

- [ ] **Step 1: Write site settings script**

Creates Web API site settings for the two new tables via powerpagecomponent content JSON (Enhanced Data Model pattern):

| Setting | Value |
|---------|-------|
| `Webapi/dcfg_blanket_workorder/enabled` | `true` |
| `Webapi/dcfg_blanket_workorder/fields` | `dcfg_blanket_workorderid,dcfg_name,dcfg_dollar_threshold,dcfg_job_number,dcfg_effective_year,dcfg_active_flag,_dcfg_customer_id_value` |
| `Webapi/dcfg_customer_ap_mapping/enabled` | `true` |
| `Webapi/dcfg_customer_ap_mapping/fields` | `dcfg_customer_ap_mappingid,dcfg_name,dcfg_ap_code,dcfg_active_flag,_dcfg_customer_id_value,_dcfg_cost_code_id_value` |

Update existing settings:
- `Webapi/dcfg_document_template/fields` — append `,_dcfg_customer_id_value`
- `Webapi/dcfg_contract/fields` — append `,dcfg_blanket_number`

Uses powerpagecomponent content JSON pattern per `feedback_powerpagecomponent_patch.md`.

- [ ] **Step 2: Run against Test**

```bash
pwsh C:\DCFG\scripts\deploy-customer-config-sitesettings.ps1 -EnvUrl "https://org0c17e98d.crm.dynamics.com/"
```

- [ ] **Step 3: Write table permissions script**

Create table permissions for both new tables:
- Admin role: Read, Write, Create, Append, AppendTo on both new tables
- Non-admin roles: Read on dcfg_blanket_workorder (Send Queue needs it), Read on dcfg_customer_ap_mapping (wizard needs it)
- AppendTo on dcfg_document_template for customer relationship
- **Both sides of relationships (CLAUDE.md rule):**
  - Append on dcfg_customer (target of all three lookups — blanket, AP mapping, template)
  - Append on dcfg_ap_cost_code (target of AP mapping cost code lookup)
- **Verify:** dcfg_contract table permission for non-admin roles covers the new dcfg_blanket_number column (Send Queue staff need write access)

- [ ] **Step 3b: Publish customizations after site settings + permissions**

```powershell
# POST /PublishAllXml — required after table permission changes
```

- [ ] **Step 4: Run table permissions against Test**

- [ ] **Step 5: Clear cache**

```bash
curl.exe -s "https://dcfg.powerappsportals.com/_services/about?clearCache=true" | head -5
```

- [ ] **Step 6: Verify Web API access**

Test that a simple OData query works:
```bash
# From browser console or curl with portal auth cookie
GET /dcfg_blanket_workorders?$top=1
```

Expected: 200 OK, empty `value: []`

- [ ] **Step 7: Commit**

```bash
git add scripts/deploy-customer-config-sitesettings.ps1
git commit -m "feat: site settings and table permissions for customer config"
```

---

## SPA Modification Gate

> **IMPORTANT:** Chunks 2-5 modify SPA files under `C:\DCFG\spa\` which is READ-ONLY per CLAUDE.md. Operator must grant explicit permission before proceeding with SPA edits.

---

## Chunk 2: portalApi.js Updates

### Task 3: Add entity sets, enums, and CRUD functions to portalApi.js

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\portalApi.js`
  - EntitySets block (~line 30-68): add `blanketWorkorders` and `customerApMappings`
  - After existing fetch functions (~line 362): add fetch functions
  - After existing CRUD functions (~line 506): add create/update functions

- [ ] **Step 1: Add entity sets**

In the `EntitySets` object (after line ~46 `docTemplates`):

```javascript
blanketWorkorders:  'dcfg_blanket_workorders',
customerApMappings: 'dcfg_customer_ap_mappings',
```

- [ ] **Step 2: Add blanket WO fetch functions**

After the cost code functions (~line 362):

```javascript
// ── BLANKET WORK ORDERS ──
export function fetchBlanketWorkorders() {
  return apiGet(`/${EntitySets.blanketWorkorders}?$filter=dcfg_active_flag eq true&$select=dcfg_blanket_workorderid,dcfg_name,dcfg_dollar_threshold,dcfg_job_number,dcfg_effective_year,dcfg_active_flag,_dcfg_customer_id_value&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)&$orderby=dcfg_effective_year desc`);
}

// Returns ALL blankets (active + inactive) for Admin history view
export function fetchBlanketsByCustomer(customerId) {
  return apiGet(`/${EntitySets.blanketWorkorders}?$filter=_dcfg_customer_id_value eq ${customerId}&$select=dcfg_blanket_workorderid,dcfg_name,dcfg_dollar_threshold,dcfg_job_number,dcfg_effective_year,dcfg_active_flag&$orderby=dcfg_effective_year desc`);
}

export function createBlanketWorkorder(payload) { return apiPostReturn(`/${EntitySets.blanketWorkorders}`, payload); }
export function updateBlanketWorkorder(id, payload) { return apiPatch(`/${EntitySets.blanketWorkorders}(${id})`, payload); }
```

- [ ] **Step 3: Add customer AP mapping functions**

```javascript
// ── CUSTOMER AP MAPPINGS ──
export function fetchCustomerApMappings(customerId) {
  return apiGet(`/${EntitySets.customerApMappings}?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_active_flag eq true&$select=dcfg_customer_ap_mappingid,dcfg_name,dcfg_ap_code,_dcfg_cost_code_id_value,dcfg_active_flag&$expand=dcfg_cost_code_id($select=dcfg_ap_cost_codeid,dcfg_dcfg_cost_code,dcfg_description)&$orderby=dcfg_name asc`);
}

export function fetchAllCustomerApMappings(customerId) {
  return apiGet(`/${EntitySets.customerApMappings}?$filter=_dcfg_customer_id_value eq ${customerId}&$select=dcfg_customer_ap_mappingid,dcfg_name,dcfg_ap_code,_dcfg_cost_code_id_value,dcfg_active_flag&$expand=dcfg_cost_code_id($select=dcfg_ap_cost_codeid,dcfg_dcfg_cost_code,dcfg_description)&$orderby=dcfg_name asc`);
}

export function createCustomerApMapping(payload) { return apiPostReturn(`/${EntitySets.customerApMappings}`, payload); }
export function updateCustomerApMapping(id, payload) { return apiPatch(`/${EntitySets.customerApMappings}(${id})`, payload); }
```

- [ ] **Step 4: Add template-by-customer fetch**

```javascript
export function fetchTemplatesByCustomer(customerId) {
  return apiGet(`/${EntitySets.docTemplates}?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_is_active eq true&$select=dcfg_document_templateid,dcfg_name,dcfg_contract_family,dcfg_document_type,dcfg_exhibit_type,dcfg_version,dcfg_sharepoint_url&$orderby=dcfg_name asc`);
}
```

- [ ] **Step 5: Update `resolveTemplateId()` with customer-first resolution**

Current function (~line 376). New resolution order:

```javascript
export async function resolveTemplateId(family, docType, customer) {
  // 1. Customer-specific template
  if (customer?.dcfg_customerid) {
    const custTpl = await apiGet(`/${EntitySets.docTemplates}?$filter=_dcfg_customer_id_value eq ${customer.dcfg_customerid} and dcfg_document_type eq ${docType} and dcfg_is_active eq true&$select=dcfg_document_templateid&$top=1`);
    if (custTpl?.value?.[0]?.dcfg_document_templateid) return custTpl.value[0].dcfg_document_templateid;
  }
  // 2. Family-specific global template
  const targetFamily = (customer && customer.dcfg_is_tpa) ? (customer.dcfg_contract_family ?? family) : family;
  const r = await apiGet(`/${EntitySets.docTemplates}?$filter=_dcfg_customer_id_value eq null and dcfg_contract_family eq ${targetFamily} and dcfg_document_type eq ${docType} and dcfg_is_active eq true&$select=dcfg_document_templateid&$top=1`);
  if (r?.value?.[0]?.dcfg_document_templateid) return r.value[0].dcfg_document_templateid;
  // 3. Decades fallback
  if (targetFamily !== ContractFamily.Decades) {
    const fallback = await apiGet(`/${EntitySets.docTemplates}?$filter=_dcfg_customer_id_value eq null and dcfg_contract_family eq ${ContractFamily.Decades} and dcfg_document_type eq ${docType} and dcfg_is_active eq true&$select=dcfg_document_templateid&$top=1`);
    return fallback?.value?.[0]?.dcfg_document_templateid || null;
  }
  return null;
}
```

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-shell/src/portalApi.js
git commit -m "feat: portalApi functions for blanket WO, customer AP mappings, template resolution"
```

---

## Chunk 3: Admin Tab — Customer Config

### Task 4: Add "Customer Config" tab to Admin.jsx

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx`
  - Line 19: Add to TABS array
  - Line ~50-57: Add tab render conditional
  - After last tab component (~line 1590): Add `CustomerConfigTab` component

- [ ] **Step 1: Add tab to TABS array and render**

Line 19 — add `'Customer Config'` to TABS array:
```javascript
const TABS = ['Document Templates', 'Onboarding Steps', 'Location Types', 'Cost Codes', 'Appliance Types', 'Vendors', 'Logging', 'Intake Fields', 'Customer Config'];
```

Add render conditional after Intake Fields (~line 57):
```javascript
{activeTab === 'Customer Config' && <CustomerConfigTab userEmail={user?.email} />}
```

Add imports at top of file (line ~9):
```javascript
import {
  apiGet, apiPost, apiPatch, apiPostReturn, EntitySets, ContractFamily, ContractType,
  writeAuditLog, AuditActionType,
  fetchBlanketsByCustomer, createBlanketWorkorder, updateBlanketWorkorder,
  fetchCustomerApMappings, fetchAllCustomerApMappings, createCustomerApMapping, updateCustomerApMapping,
  fetchTemplatesByCustomer, fetchCostCodes, fetchDocTemplates,
} from '../portalApi.js';
```

- [ ] **Step 2: Write CustomerConfigTab component — customer selector + state**

```javascript
function CustomerConfigTab({ userEmail }) {
  const [customers, setCustomers] = useState([]);
  const [selectedCustomerId, setSelectedCustomerId] = useState('');
  const [customerSearch, setCustomerSearch] = useState('');
  const [loading, setLoading] = useState(true);

  // Section data
  const [blankets, setBlankets] = useState([]);
  const [apMappings, setApMappings] = useState([]);
  const [costCodes, setCostCodes] = useState([]);
  const [customerTemplates, setCustomerTemplates] = useState([]);
  const [globalTemplates, setGlobalTemplates] = useState([]);
  const [sectionLoading, setSectionLoading] = useState(false);

  useEffect(() => {
    apiGet(`/${EntitySets.customers}?$filter=dcfg_active_flag eq true&$select=dcfg_customerid,dcfg_name,dcfg_is_tpa&$orderby=dcfg_name asc`)
      .then(r => setCustomers(r?.value ?? []))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  const loadCustomerData = useCallback(async (custId) => {
    if (!custId) return;
    setSectionLoading(true);
    const [bRes, apRes, ccRes, ctRes, gtRes] = await Promise.allSettled([
      fetchBlanketsByCustomer(custId),
      fetchAllCustomerApMappings(custId),
      fetchCostCodes(),
      fetchTemplatesByCustomer(custId),
      fetchDocTemplates(),
    ]);
    setBlankets(bRes.status === 'fulfilled' ? (bRes.value?.value ?? []) : []);
    setApMappings(apRes.status === 'fulfilled' ? (apRes.value?.value ?? []) : []);
    setCostCodes(ccRes.status === 'fulfilled' ? (ccRes.value?.value ?? []) : []);
    setCustomerTemplates(ctRes.status === 'fulfilled' ? (ctRes.value?.value ?? []) : []);
    setGlobalTemplates(gtRes.status === 'fulfilled' ? (gtRes.value?.value ?? []).filter(t => !t._dcfg_customer_id_value) : []);
    setSectionLoading(false);
  }, []);

  useEffect(() => { if (selectedCustomerId) loadCustomerData(selectedCustomerId); }, [selectedCustomerId, loadCustomerData]);

  const selectedCustomer = customers.find(c => c.dcfg_customerid === selectedCustomerId);
  const filtered = customerSearch
    ? customers.filter(c => c.dcfg_name?.toLowerCase().includes(customerSearch.toLowerCase()))
    : customers;

  // ... render (see Steps 3-5 for sections)
}
```

- [ ] **Step 3: Write Section A — Blanket Work Order**

Inside CustomerConfigTab render. Shows active blanket as editable card, history as collapsed list. "Add Blanket" if none active.

Key behaviors:
- Create: POST to dcfg_blanket_workorders with customer bind + auto-name
- Update: PATCH threshold/job number/year
- Deactivate old: PATCH dcfg_active_flag = false on prior year when creating new
- Audit log on every write

```javascript
// BlanketSection component within CustomerConfigTab
// Props: blankets, selectedCustomerId, selectedCustomer, userEmail, onReload
```

Active blanket = `blankets.find(b => b.dcfg_active_flag)`.
History = `blankets.filter(b => !b.dcfg_active_flag)`.

Form fields: Dollar Threshold (type="number" step="0.01"), Job Number (text), Effective Year (number), Active toggle.

Save handler:
```javascript
async function saveBlanket(isNew, formData) {
  const payload = {
    dcfg_name: `${selectedCustomer.dcfg_name} ${formData.year} Blanket`,
    dcfg_dollar_threshold: parseFloat(formData.threshold),
    dcfg_job_number: formData.jobNumber,
    dcfg_effective_year: parseInt(formData.year),
    dcfg_active_flag: true,
  };
  if (isNew) {
    payload[`dcfg_customer_id@odata.bind`] = `/${EntitySets.customers}(${selectedCustomerId})`;
    // Deactivate existing active blanket first
    const existing = blankets.find(b => b.dcfg_active_flag);
    if (existing) await updateBlanketWorkorder(existing.dcfg_blanket_workorderid, { dcfg_active_flag: false });
    await createBlanketWorkorder(payload);
  } else {
    await updateBlanketWorkorder(formData.id, payload);
  }
  writeAuditLog({ targetTable: 'dcfg_blanket_workorder', targetRecordId: formData.id || 'new', actionType: isNew ? AuditActionType.Created : AuditActionType.DataUpdated, performedBy: userEmail, newValue: JSON.stringify(payload) });
  onReload();
}
```

- [ ] **Step 4: Write Section B — AP Code Mappings**

Table: Cost Code | Description | Global AP Code (read-only) | Customer AP Code (editable) | Actions

Shows ALL cost codes. For each, check if a customer mapping exists. If so, show the customer AP code in an editable input. If not, show empty input with muted global value.

Key behaviors:
- Save mapping: If no mapping exists → POST new `dcfg_customer_ap_mapping`. If exists → PATCH `dcfg_ap_code`.
- Deactivate: PATCH `dcfg_active_flag = false` (soft delete, falls back to global)
- Auto-generate dcfg_name: `"${customerName} - ${costCodeName}"`

```javascript
// APMappingSection component
// Props: apMappings, costCodes, selectedCustomerId, selectedCustomer, userEmail, onReload
```

Build lookup map: `apByCode = Object.fromEntries(apMappings.filter(m => m.dcfg_active_flag).map(m => [m._dcfg_cost_code_id_value, m]))`

For each cost code, render row with:
- Read-only: `cc.dcfg_dcfg_cost_code`, `cc.dcfg_description`, `cc.dcfg_customer_ap_code` (global)
- Editable: customer AP code input, sourced from `apByCode[cc.dcfg_ap_cost_codeid]?.dcfg_ap_code`
- Buttons: Save (create or update), Deactivate (if mapping exists)

- [ ] **Step 5: Write Section C — Custom Templates**

Table: Document Type | Exhibit Type | Template Name | Version | Actions

Shows customer-assigned templates. Below: collapsible global templates for reference.

Key behaviors:
- Assign: PATCH existing template to set `dcfg_customer_id@odata.bind`
- Remove: PATCH template to clear customer_id (`dcfg_customer_id@odata.bind: null` or use `/$ref` delete)
- Uses existing doc type/exhibit type label maps from Admin.jsx (FAMILY_LABELS, DOCTYPE_LABELS, EXHIBIT_LABELS)

```javascript
// TemplateSection component
// Props: customerTemplates, globalTemplates, selectedCustomerId, userEmail, onReload
```

"Assign Template" button opens picker modal showing global templates not already assigned to this customer.

- [ ] **Step 6: Assemble full render**

CustomerConfigTab render returns:
1. Customer search input + dropdown
2. If no customer selected: "Select a customer to manage configuration"
3. If selected + loading: skeleton
4. If selected + loaded: Three collapsible sections (A, B, C)

Each section has a header with expand/collapse toggle.

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-shell/src/screens/Admin.jsx
git commit -m "feat: Customer Config tab on Admin — blanket WO, AP mappings, template overrides"
```

---

## Chunk 4: Send Queue — Blanket-Aware WO Assignment

### Task 5: Update SendQueue.jsx for blanket logic

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\SendQueue.jsx`
  - Line ~8-12: Add imports for fetchBlanketWorkorders
  - Line ~112: Update WIP query to add dcfg_contract_fee, dcfg_blanket_number to $select and update filter
  - Line ~126-144: Add applyBlanket function alongside assignWoNumber
  - Line ~500-552: Update WIP table rendering with blanket logic

- [ ] **Step 1: Add import**

```javascript
import { ..., fetchBlanketWorkorders } from '../portalApi.js';
```

- [ ] **Step 2: Add blanket state and fetch**

In the data loading section (~line 100):

```javascript
const [blanketMap, setBlanketMap] = useState({}); // { customerId → blanketRecord }
```

In the Promise.all (~line 107), add:

```javascript
const blkRes = await fetchBlanketWorkorders().catch(() => ({ value: [] }));
const blkMap = {};
for (const b of (blkRes?.value ?? [])) {
  const custId = b._dcfg_customer_id_value;
  if (!custId) continue;
  // If multiple active, take most recent year
  if (!blkMap[custId] || b.dcfg_effective_year > blkMap[custId].dcfg_effective_year) {
    blkMap[custId] = b;
  }
}
setBlanketMap(blkMap);
```

- [ ] **Step 3: Update WIP contracts query**

Line 112 — update the WIP query:

Add `dcfg_contract_fee,dcfg_blanket_number` to `$select`.

Update filter: `dcfg_status eq 100000007 and dcfg_contract_number eq null and dcfg_blanket_number eq null and dcfg_active_flag eq true`

- [ ] **Step 4: Add applyBlanket function**

After assignWoNumber (~line 144):

```javascript
async function applyBlanket(contractId, blanketNumber) {
  setActionBusy(contractId);
  try {
    await apiPatch(`/${EntitySets.contracts}(${contractId})`, { dcfg_blanket_number: blanketNumber });
    toast.show('ok', `Blanket number ${blanketNumber} applied.`);
    setWipContracts(prev => prev.filter(w => w.dcfg_contractid !== contractId));
    writeAuditLog({
      targetTable: 'dcfg_contract', targetRecordId: contractId,
      actionType: AuditActionType.DataUpdated, performedBy: user?.email || 'unknown',
      newValue: `Blanket number applied: ${blanketNumber}`, relatedContractId: contractId,
    }).catch(() => {});
  } catch (err) {
    toast.show('err', `Failed to apply blanket: ${err.message}`);
  }
  setActionBusy(null);
}
```

- [ ] **Step 5: Update WIP table rendering**

In the WIP table (~line 500-552), add a Contract Amount column header and update each row:

Add header after "Date": `<th>Amount</th>`

For each row, determine blanket eligibility:
```javascript
{wipContracts.map(wip => {
  const custId = wip._dcfg_customer_id_value || wip.dcfg_customer_id?.dcfg_customerid;
  const blanket = blanketMap[custId];
  const fee = wip.dcfg_contract_fee ?? 0;
  const isBlanketEligible = blanket && fee < blanket.dcfg_dollar_threshold;

  return (
    <tr key={wip.dcfg_contractid}>
      {/* ...existing columns... */}
      <td>{fee > 0 ? `$${fee.toLocaleString('en-US', { minimumFractionDigits: 2 })}` : '—'}</td>
      <td>
        {isBlanketEligible ? (
          <>
            <span style={{ fontSize: 11, color: '#D4A017', fontWeight: 600, marginRight: 6 }}>BLANKET</span>
            <span style={{ fontSize: 12 }}>{blanket.dcfg_job_number}</span>
            <button onClick={() => applyBlanket(wip.dcfg_contractid, blanket.dcfg_job_number)}
              disabled={actionBusy === wip.dcfg_contractid}
              style={{ ...btnSmall, marginLeft: 8 }}>
              Apply Blanket
            </button>
          </>
        ) : (
          <>
            <input value={woNumberInputs[wip.dcfg_contractid] || ''}
              onChange={e => setWoNumberInputs(p => ({ ...p, [wip.dcfg_contractid]: e.target.value }))}
              onKeyDown={e => { if (e.key === 'Enter') assignWoNumber(wip.dcfg_contractid); }}
              placeholder="WO number..."
              style={{ ...inputSmall, width: 120 }} />
            <button onClick={() => assignWoNumber(wip.dcfg_contractid)}
              disabled={actionBusy === wip.dcfg_contractid || !woNumberInputs[wip.dcfg_contractid]?.trim()}
              style={{ ...btnSmall, marginLeft: 4 }}>
              Assign
            </button>
          </>
        )}
      </td>
    </tr>
  );
})}
```

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-shell/src/screens/SendQueue.jsx
git commit -m "feat: blanket-aware WO assignment in Send Queue"
```

---

## Chunk 5: Contract Wizard — Customer AP Code Resolution

### Task 6: Update NewContractWizard.jsx AP code resolution

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx`
  - Line ~9: Add fetchCustomerApMappings import
  - Line ~119: Add customerApMap state
  - After customer selection (~Step 1 submit): Fetch customer AP mappings
  - Line ~427-430: Update updateLine to check customer map first

- [ ] **Step 1: Add import and state**

Add to imports (~line 9):
```javascript
import { ..., fetchCustomerApMappings } from '../portalApi.js';
```

Add state (~line 119):
```javascript
const [customerApMap, setCustomerApMap] = useState({}); // { costCodeId → apCode }
```

- [ ] **Step 2: Fetch customer AP mappings when customer is selected**

When customer is chosen (Step 1 → Step 2 transition), fetch their AP mappings:

```javascript
// After customer is set (in the step transition or customer selection handler)
if (customerId) {
  fetchCustomerApMappings(customerId).then(r => {
    const map = {};
    for (const m of (r?.value ?? [])) {
      map[m._dcfg_cost_code_id_value] = m.dcfg_ap_code;
    }
    setCustomerApMap(map);
  }).catch(() => setCustomerApMap({}));
}
```

Also fetch when loading a draft that has a customer:
```javascript
// In the draft loading section (~line 391), after customer is known
if (draft._dcfg_customer_id_value) {
  fetchCustomerApMappings(draft._dcfg_customer_id_value).then(r => {
    const map = {};
    for (const m of (r?.value ?? [])) {
      map[m._dcfg_cost_code_id_value] = m.dcfg_ap_code;
    }
    setCustomerApMap(map);
  }).catch(() => {});
}
```

- [ ] **Step 3: Update updateLine AP code resolution**

Line 430 — change from:
```javascript
updated.apCode = cc?.dcfg_customer_ap_code || '';
```

To:
```javascript
updated.apCode = customerApMap[value] || cc?.dcfg_customer_ap_code || '';
```

This checks customer-specific mapping first, falls back to global.

- [ ] **Step 4: Also update draft line restoration**

Line 399 — change from:
```javascript
apCode: l.dcfg_cost_code_id?.dcfg_customer_ap_code || '',
```

To:
```javascript
apCode: customerApMap[l._dcfg_cost_code_id_value] || l.dcfg_cost_code_id?.dcfg_customer_ap_code || '',
```

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-shell/src/NewContractWizard.jsx
git commit -m "feat: customer-specific AP code resolution in contract wizard"
```

---

## Chunk 6: Build + Deploy + Verify

### Task 7: Build and deploy SPA to Test

**Files:** None (build/deploy commands only)

- [ ] **Step 1: Verify pac auth is on Test**

```bash
pac auth list
```

Expected: `[1] *` pointing to org0c17e98d.crm.dynamics.com

- [ ] **Step 2: Build SPA**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

Expected: Build succeeds with no errors.

- [ ] **Step 3: Deploy to Test**

```bash
cd C:\DCFG\spa\dcfg-shell && pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 4: Clear cache**

Provide URL: https://dcfg.powerappsportals.com/_services/about

- [ ] **Step 5: Smoke test**

Navigate to https://dcfg.powerappsportals.com → Admin → Customer Config tab:
1. Select a customer → sections load
2. Create a blanket WO → saves, appears in card
3. Add an AP mapping → saves, appears in table
4. Verify Send Queue → "Needs Work Order Number" tab still works

- [ ] **Step 6: Final commit**

```bash
git add -A && git commit -m "feat: customer config — blanket WO, AP mappings, template overrides (Test deploy)"
```

---

## Update Project Data

### Task 8: Update dcfg-project-data skill with new entity sets

**Files:**
- Modify: `C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\entity-sets.json`

- [ ] **Step 1: Add new tables to entity-sets.json**

```json
"dcfg_blanket_workorder": { "entitySet": "dcfg_blanket_workorders", "hasName": true },
"dcfg_customer_ap_mapping": { "entitySet": "dcfg_customer_ap_mappings", "hasName": true }
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "docs: update entity-sets.json with customer config tables"
```

---

## Rollback Plan (SOX Compliance)

If issues are found after deployment:

**Schema (Dataverse):**
- New tables can be deleted via Dataverse admin if needed (no data loss risk on new tables)
- New columns on existing tables (`dcfg_blanket_number` on contract, `dcfg_customer_id` on template) can be deleted — they are nullable and have no existing data
- Before-state: both columns do not exist, no data to lose

**Site settings:**
- Revert by deleting the new site setting powerpagecomponent records
- Restore original `Webapi/dcfg_contract/fields` and `Webapi/dcfg_document_template/fields` values (capture before-state in script output)

**SPA:**
- Git revert the SPA commits, rebuild, redeploy
- All SPA changes are additive (new tab, new functions, modified resolution logic) — revert is clean

**Table permissions:**
- Delete the new table permission powerpagecomponent records
