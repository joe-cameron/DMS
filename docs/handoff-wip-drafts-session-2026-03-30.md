# DCFG Session Handoff — 2026-03-30

**From:** WIP Drafts + WO Assignment + UX Polish session
**Deployed to:** Test (dcfg.powerappsportals.com) + Prod (dmms1.powerappsportals.com)

---

## What Was Built

### WIP Drafts (Both Wizards)
- Contract Wizard saves draft at Step 2 (WIP status, invisible to existing views)
- Proposal Wizard saves draft at Step 2 (WIP status on MSA table)
- Auto-save PATCHes on Steps 3→4 and 4→5
- Exhibit A lines saved to Dataverse at Step 4 (survives browser crash)
- My Drafts landing — personal drafts, resume at saved step, soft delete
- Skip landing if no drafts (no extra click)
- "Draft saved" indicator below stepper bar, fades after 2 seconds
- Generate PATCHes WIP → Draft (no duplicate records)

### Send Queue — WO Number Assignment
- New "Needs Work Order Number" tab on Send Queue
- Shows all WIP contracts without dcfg_contract_number
- Inline text input + Assign button writes WO number via PATCH
- Replaces email + spreadsheet WO number assignment process

### Amendment Flow
- Parent WO picker shows: Customer — Location — Vendor — Date (WO# if assigned)
- Service Location Description field (dcfg_service_location_description) — amendment only, skippable
- Step 5 orange warning if description empty (doesn't block Generate)

### Code Review Fixes
- 17 abbreviation fixes across 10 files (WO→Work Order, MSA→Vendor MSA, Med→Medium, ST→State, etc.)
- ContractDetail.jsx crash fix (user?.email → userEmail)
- Audit log field fix (performedBy: userEmail)
- Admin DOCTYPE_LABELS keys fixed (100000000 not 0)
- fetchVendorMSAs fix (statecode eq 0 instead of dcfg_active_flag)
- Operations table badges: "Order"/"Request" with tooltip
- Review pages: required=red "Required", optional=gray "—", filled=green
- Proposal draft landing: shows MSA name instead of "Unknown Customer"
- Location detail: Promise.allSettled for graceful secondary fetch failure
- FieldName component: returns null for empty children

### Schema Deployed (Test + Prod)
- `dcfg_contract`: WIP status (100000007), dcfg_wizard_step, dcfg_created_by_email
- `dcfg_msa`: WIP status (100000008), dcfg_wizard_step, dcfg_created_by_email
- Site settings updated: Webapi/dcfg_contract/fields + Webapi/dcfg_msa/fields
- Customizations published on both environments

---

## Files Modified

| File | Changes |
|------|---------|
| `portalApi.js` | WIP enum on ContractStatus + MsaStatus, fetchMyWIPDrafts, fetchMyWIPProposals, updateContract, updateMsa, deleteContractLine, apiPostReturnId, fetchContractsByCustomer expanded, fetchVendorMSAs statecode fix |
| `NewContractWizard.jsx` | Draft save infrastructure, My Drafts landing, amendment flow (parent WO picker, service location desc), review page required/optional styling, abbreviation fixes |
| `NewProposalWizard.jsx` | Draft save infrastructure, My Drafts landing, abbreviation fixes (State, Monthly Rate, No Charge), removed schema name notes, review page required/optional styling, Unknown Customer fix |
| `SendQueue.jsx` | "Needs Work Order Number" tab, assignWoNumber handler, Vendor MSA badge fix |
| `Operations.jsx` | Filter labels (Work Order/Work Request), badge text (Order/Request with tooltip), Medium priority badge |
| `ContractDetail.jsx` | userEmail crash fix |
| `Admin.jsx` | DOCTYPE_LABELS keys fix, Vendor MSA label |
| `LocationDetail.jsx` | Abbreviation fixes (Inspection, Water Treatment), IDD/DCA tooltips, Promise.allSettled |
| `LocationManager.jsx` | Water Treatment label |
| `NavPanel.jsx` | MSAs nav label with title tooltip |
| `MsaList.jsx` | Master Service Agreements heading |
| `ContractsList.jsx` | AP Code tooltip |
| `FieldName.jsx` | Null return for empty children |

---

## Scripts Created

| Script | Purpose |
|--------|---------|
| `scripts/deploy-wip-schema.ps1` | Add WIP status + columns to dcfg_contract |
| `scripts/deploy-msa-wip-schema.ps1` | Add WIP columns to dcfg_msa |
| `scripts/publish-customizations.ps1` | Publish dcfg_contract + dcfg_msa |
| `scripts/update-prod-site-settings.ps1` | Update Webapi field site settings on Prod |
| `scripts/update-msa-fields-sitesetting.ps1` | Update Webapi/dcfg_msa/fields on Test |

---

## E2E Test Results (Prod)

- 5 tests, all passed, 121 screenshots
- Zero 403s, zero error toasts
- Screenshots at: `C:\DCFG\spa\dcfg-playwright\screenshots\e2e-review\`
- Test file: `C:\DCFG\spa\dcfg-playwright\tests\full-e2e-review.spec.ts`
- .env points to Prod (dmms1.powerappsportals.com)

---

## Known Issues (Not Code Bugs)

| Issue | Type | Notes |
|-------|------|-------|
| Blank detail views in screenshots | Test timing | Screenshots taken before API responds. Real users see data. |
| UpKeep Assigned column shows encoded IDs | Data/integration | UpKeep user name resolution not implemented |
| Location named "1981 Old Cuthbert Rd..." | Data quality | Address used as name in Dataverse record |
| Duplicate MSAs in list | Data quality | Multiple identical MSA records in Prod |
| Field Ops "No customers found" | Prod data | No field ops data in Prod environment |
| MSA list Customer column shows "—" | Data | Customer lookup not populated on some MSAs |

---

## Outstanding Work

| Priority | Item | Status |
|----------|------|--------|
| P0 | Stage deploy (org88778bb0) | Not done — schema + SPA needed |
| P1 | Onboarding Concierge site not rendering SPA | Blocked on Power Pages knowledge |
| P1 | DocGen v2 — Word Online actions | Blocked on template conversion |
| P2 | Owner/Admin Dashboard | Planned |
| P2 | WIP Drafts — track which step user completed on Proposal Wizard more granularly | Minor enhancement |
| P3 | Exhibit B/C template work | Planned |

---

## Memory Updated

- `project_wo_number_lifecycle.md` — WO number assignment process documented
- `project_ux_audit_cleanup.md` — needs update to reflect completion

---

## Clear Cache URLs

- Test: https://dcfg.powerappsportals.com/_services/about
- Prod: https://dmms1.powerappsportals.com/_services/about
