# DCFG Session Handoff — 2026-03-30

**From:** Customer Config + Blanket WO + AP Mappings + Submit for Approval session
**Deployed to:** Test (dcfg.powerappsportals.com) + Prod (dmms1.powerappsportals.com)

---

## What Was Built

### Customer Config Tab (Admin)
- New "Customer Config" tab on Admin screen
- Customer search/dropdown selector with TPA badge
- **Section A: Blanket Work Order** — create/edit/deactivate blanket WO per customer (threshold, job number, effective year). History of prior years collapsed below.
- **Section B: AP Code Mappings** — customer-specific AP code overrides per cost code. Shows all cost codes with global AP (read-only) and customer AP (editable). Save/Remove per mapping.
- **Section C: Custom Templates** — assign/remove global templates to a customer. Picker for unassigned templates.

### Blanket-Aware WO Assignment (Send Queue)
- Send Queue "Needs Work Order Number" tab now filters on **Pending Approval** status (100000008), not WIP
- Fetches active blanket work orders and builds customer→blanket map
- New **Amount** column shows contract fee
- Contracts under blanket threshold: shows "BLANKET" badge + job number + one-click "Apply" button → writes `dcfg_blanket_number`
- Contracts at/over threshold or no blanket: existing manual WO number input → writes `dcfg_contract_number`
- Filter excludes contracts where either number is already assigned

### Submit for Approval
- **ContractDetail.jsx**: "Submit for Approval" button when status = Generated. Confirmation modal. Sets status → Pending Approval (100000008).
- **MsaDetail.jsx**: "Submit for Approval" button when MSA status = Generated. Sets status → Pending Approval (100000009).
- "Mark as Sent" button moved from Generated to Pending Approval status

### Customer AP Code Resolution (Contract Wizard)
- `useEffect` fetches customer AP mappings when `customerId` changes
- `updateLine` checks `customerApMap[costCodeId]` first, falls back to global `dcfg_customer_ap_code`
- Draft line restoration also uses customer map

### Template Resolution (portalApi.js)
- `resolveTemplateId()` now checks customer-specific template first, then family-specific global, then Decades fallback
- Uses `_dcfg_customer_id_value eq null` for global template filtering

---

## Schema Deployed (Test + Prod)

### New Tables
- `dcfg_blanket_workorder` — PK, dcfg_name, dcfg_dollar_threshold (Decimal), dcfg_job_number, dcfg_effective_year, dcfg_active_flag, dcfg_customer_id (Lookup → dcfg_customer)
- `dcfg_customer_ap_mapping` — PK, dcfg_name, dcfg_ap_code, dcfg_active_flag, dcfg_customer_id (Lookup → dcfg_customer), dcfg_cost_code_id (Lookup → dcfg_ap_cost_code)

### Modified Tables
- `dcfg_contract`: added `dcfg_blanket_number` (String 50, nullable)
- `dcfg_document_template`: `dcfg_customer_id` already existed on both environments
- `dcfg_contract.dcfg_status`: added Pending Approval (100000008)
- `dcfg_msa.dcfg_status`: added Pending Approval (100000009)

### Entity Sets
- `dcfg_blanket_workorders`
- `dcfg_customer_ap_mappings`

---

## Files Modified

| File | Changes |
|------|---------|
| `portalApi.js` | 2 entity sets (blanketWorkorders, customerApMappings), 10 new functions (fetch/create/update for blankets + AP mappings + templates by customer), updated `resolveTemplateId` with 3-tier resolution, PendingApproval added to ContractStatus + MsaStatus + labels |
| `Admin.jsx` | New "Customer Config" tab with CustomerConfigTab, SectionHeader, BlanketSection, BlanketHistoryTable, APMappingSection, TemplateSection components. New imports for all CRUD functions. |
| `SendQueue.jsx` | Import fetchBlanketWorkorders, blanketMap state, fetch blankets on load, applyBlanket function, WIP query changed to Pending Approval (100000008) + added dcfg_contract_fee/dcfg_blanket_number to $select + Amount column + blanket/manual conditional rendering |
| `NewContractWizard.jsx` | Import fetchCustomerApMappings, customerApMap state, useEffect to fetch on customerId change, updateLine checks customerApMap first, draft line restoration uses customerApMap |
| `ContractDetail.jsx` | "Submit for Approval" button + submitApproval modal type + handler (Generated → PendingApproval). "Mark as Sent" moved to PendingApproval status. |
| `MsaDetail.jsx` | Import MsaStatus + writeAuditLog + AuditActionType, handleSubmitForApproval function, "Submit for Approval" button when Generated |

---

## Scripts Created

| Script | Purpose | Target |
|--------|---------|--------|
| `scripts/deploy-customer-config-schema.ps1` | Create blanket_workorder + customer_ap_mapping tables + columns | Parameterized (has Money bug — use _deploy-remaining-schema pattern) |
| `scripts/deploy-customer-config-sitesettings.ps1` | Site settings + table permissions | Test |
| `scripts/deploy-pending-approval-status.ps1` | Add Pending Approval status options | Parameterized |
| `scripts/_deploy-remaining-schema.ps1` | Working schema script using Decimal (Test) | Test |
| `scripts/_deploy-remaining-schema-prod.ps1` | Working schema script (Prod) | Prod |
| `scripts/_deploy-prod-sitesettings.ps1` | Site settings + permissions (Prod) | Prod |
| `scripts/_deploy-prod-remaining.ps1` | Lookups + columns + statuses (Prod) | Prod |
| `scripts/_deploy-prod-final.ps1` | Final items — blanket_number + statuses (Prod) | Prod |

---

## Known Issues — NEEDS DEBUGGING

### Permission Errors
- User reported permission errors during testing
- **Likely causes:**
  - Table permissions for `dcfg_blanket_workorder` and `dcfg_customer_ap_mapping` may not have correct role linkage on Prod (the powerpagecomponent content JSON PATCH is the critical step — portal reads roles from content JSON, not intersection table)
  - Web API field list may be missing lookup navigation properties needed for `$expand` queries
  - The `dcfg_blanket_number` field on `dcfg_contract` — verify the existing contract table permission's field list covers it
  - Role IDs used (DCFG_Admin, DCFG_Manager, DCFG_Viewer, Authenticated Users) were from Test — **verify these same IDs exist on Prod** (they may differ)

### Debugging Steps
1. Open browser DevTools → Network tab on the portal
2. Navigate to Admin → Customer Config → select a customer
3. Look for 403 responses on `_api/dcfg_blanket_workorders` or `_api/dcfg_customer_ap_mappings`
4. Check Send Queue → "Needs Work Order Number" tab for 403s
5. Verify role IDs on Prod: query `powerpagecomponents?$filter=powerpagecomponenttype eq 11` to get actual role GUIDs
6. Check powerpagecomponent content JSON for the two new table permissions — confirm `adx_entitypermission_webrole` array has the correct Prod role GUIDs

### Schema Note
- `dcfg_dollar_threshold` is Decimal type (not Money) — the Dataverse REST API's MoneyAttributeMetadata returned "unexpected error" on both Test and Prod. Decimal with Precision=2 works identically for threshold comparison.
- `dcfg_customer_id` already existed on `dcfg_document_template` in both environments (error code 0x80047013 contains "already exists" but the catch pattern didn't match on the first script run)

---

## Status Lifecycle (Updated)

```
WIP → Draft → Generated → Pending Approval → Sent → Signed/Received → Closed
  ↑ wizard      ↑ wizard     ↑ Submit btn      ↑ Approve-to-send
  draft save    generate     (WO# assigned      (DocuSign upload)
                             here by approver)
```

---

## Design Docs

- Spec: `C:\dcfg\docs\superpowers\specs\2026-03-30-customer-config-design.md`
- Plan: `C:\dcfg\docs\superpowers\plans\2026-03-30-customer-config.md`

---

## Clear Cache URLs

- Test: https://dcfg.powerappsportals.com/_services/about
- Prod: https://dmms1.powerappsportals.com/_services/about

## Launch URLs

- Test: https://dcfg.powerappsportals.com
- Prod: https://dmms1.powerappsportals.com
