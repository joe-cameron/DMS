# WIP Drafts + WO Number Assignment + Amendment Flow

**Date:** 2026-03-29
**Status:** Approved (spec review complete, all critical items resolved)
**Approach:** Incremental (A) — Draft first, then Queue, then Amendment

---

## Overview

Replace the manual email + spreadsheet WO number assignment process with an integrated workflow:
1. Wizard saves draft early (after Step 2)
2. Draft appears in Send Queue for WO number assignment by approval staff
3. User resumes draft later with WO number already assigned
4. Amendment flow improved with better parent WO identification and skippable description field

Applies to both Contract Wizard and Proposal Wizard (draft save pattern), but only Contract drafts trigger WO number requests. Proposals have their own numbering.

---

## Schema Changes

### New Status Value
`WIP` (100000007) added to `dcfg_status` picklist on `dcfg_contract`. Distinct from `Draft` (100000000).

**Status lifecycle:** `WIP → Draft → Submitted → Approved → Sent`

- `WIP` = user still building in wizard (invisible to existing views)
- `Draft` = user clicked Generate, record is complete (visible in existing views as today)

All existing queries (`fetchContracts`, `fetchContractsByCustomer`, ContractsList, SendQueue, SalesDashboard KPIs) already filter by status or will naturally exclude WIP because they never matched it before. No existing query changes needed.

### New Columns on `dcfg_contract`

| Column | Schema Name | Type | Purpose |
|--------|-------------|------|---------|
| Wizard Step | `dcfg_wizard_step` | Whole Number | Tracks last completed step for resume (1-5) |
| Created By Email | `dcfg_created_by_email` | Text (200) | User who created the draft — filterable for "My Drafts" |

Both columns need Web API access enabled in Power Pages site settings (`Webapi/dcfg_contract/fields`).

### Existing Columns Used (no changes)
- `dcfg_service_location_description` — Memo, already on Test + Prod
- `dcfg_active_flag` — soft delete
- `dcfg_contract_number` — assigned by approval staff via Send Queue

---

## Piece 1: Wizard Save as Draft

### Trigger
User completes Step 2 and clicks Next. Contract/proposal record created in Dataverse with `dcfg_status = WIP` (100000007).

### What's Saved at Step 2
- Customer (`dcfg_customer_id`)
- Document type (`dcfg_contract_type`)
- Location (`dcfg_property_id`)
- Vendor (`dcfg_vendor_id`)
- Program (`dcfg_program_id`) if selected
- Contract date (`dcfg_contract_date`)
- Contract family (`dcfg_contract_family` — derived)
- Created by email (`dcfg_created_by_email` — from `userEmail`)
- Wizard step (`dcfg_wizard_step` = 2)
- For amendments: parent contract ID, amendment number, service location description

### Auto-Save on Subsequent Steps
Each time user clicks Next (Steps 3→4, 4→5), the existing WIP record is PATCHed with new field values. `dcfg_wizard_step` updated to reflect last completed step. No new record created.

**Draft record ID** stored in wizard React state after Step 2 creation. All subsequent steps PATCH this ID.

### Exhibit A Lines (Step 4)
Lines are saved to Dataverse when user clicks Next on Step 4. This survives browser crashes.

**Upsert logic:** If user goes back to Step 4 and edits lines, the wizard:
1. Deletes existing lines for this contract (`fetchContractLines` → delete each)
2. Creates new lines from current React state

This is simpler than true upsert and avoids orphan line tracking. Line count is small (typically <20).

### Subtle Indicator
Small "Draft saved" text in the stepper bar area, fades after 2 seconds. On save failure, show red "Save failed" that does NOT auto-fade.

### Step 5 Generate
PATCHes the existing WIP record: `dcfg_status` changes from `WIP` to `Draft`, then triggers document generation via `createDocumentRequest()`. No duplicate records — the WIP becomes the final contract.

### Audit
- Draft creation at Step 2: `AuditActionType.Created` with user email
- Auto-save PATCHes on Steps 3-4: no audit (too noisy)
- Step 5 Generate: existing audit entry (already implemented)

### Both Wizards
Contract Wizard and Proposal Wizard follow identical draft save pattern. Only Contract WIP records appear in the Send Queue for WO number assignment. Proposal Wizard uses the same WIP status and step tracking but no Send Queue integration.

**File changes:** `NewContractWizard.jsx` and `NewProposalWizard.jsx` both get the draft save infrastructure.

---

## Piece 2: My Drafts Landing

### Location
Shown when user opens Contract Wizard (or Proposal Wizard), before the stepper loads.

### Query
```
dcfg_status eq 100000007 (WIP)
AND dcfg_created_by_email eq '{userEmail}'
AND dcfg_active_flag eq true
```

### Content
Personal drafts only, filtered by `dcfg_created_by_email`. Each draft row shows:
- Customer name
- Document type
- Location name
- Date saved (from `modifiedon`)
- Badge: "WO# assigned" if `dcfg_contract_number` is populated (contracts only)

### Actions
- **Resume** — opens wizard pre-filled at step stored in `dcfg_wizard_step`, user progresses from there
- **Delete** — soft delete (`dcfg_active_flag = false`), confirmation dialog first

### Empty State
If user has no WIP drafts, skip the landing entirely — go straight to wizard Step 1. No extra click.

### Non-Empty State
Show drafts list with a prominent **"+ Start New Contract"** (or "+ Start New Proposal") button.

---

## Piece 3: Send Queue — WO Number Assignment

### Location
New tab on existing Send Queue screen: **"Needs Work Order Number"**

### Filter
```
dcfg_status eq 100000007 (WIP)
AND dcfg_contract_number eq null
AND dcfg_active_flag eq true
```

Shows all users' WIP contract records that need a WO number. Not filtered by user — approval staff see everyone's drafts.

### Queue Item Display
- Customer name
- Document type
- Location name
- Vendor name
- Program name (if applicable)
- Created by (`dcfg_created_by_email`)
- Date created

### Action
Inline text input field — staff types the WO number, hits Enter or clicks Save. Writes directly to `dcfg_contract_number` on the contract record via PATCH.

### No New Roles
Approval staff already use the Send Queue with existing portal access. This is just a new tab with an input field.

---

## Piece 4: Amendment Flow Improvements

### Parent WO Picker (Step 2, Amendment selected)
Dropdown display format: **"Customer Name — Location — Vendor — Date"**
- Location and vendor names resolved **client-side** from already-loaded `locations` and `allVendors` arrays in wizard state
- `fetchContractsByCustomer()` updated to include `dcfg_contract_date` in `$select`
- If WO number assigned, append: `"... (WO-2026-0142)"`
- If no WO number yet, no number shown — still selectable
- Filtered to selected customer's work orders

### Program Selection (Amendment)
- If customer has programs, show program cards within the Amendment section on Step 2
- Pre-select program from parent WO if one exists
- Optional — can proceed without selecting

### Service Location Description
- Field: `dcfg_service_location_description` (Memo column, already deployed to Test + Prod)
- Shown only when Amendment is selected on Step 2
- Label: "Service Location Description"
- Placeholder: "Describe where the work is performed..."
- Optional — user can skip

### Step 5 Warning (Not Blocker)
If `dcfg_service_location_description` is empty on an Amendment:
- Orange warning banner: "Service location description not provided"
- Generate button stays enabled — does not block submission

### Generating Without WO Number
Generating without a WO number assigned is **allowed**. The document template handles null `dcfg_contract_number` by leaving the field blank or showing "DRAFT". No blocker or warning for missing WO number — this is expected in the normal workflow since number assignment is async.

---

## Piece 5: Code Review Fixes (Bundled)

### Abbreviation Violations (17 instances)

| File | Current | Fix |
|------|---------|-----|
| `NewContractWizard.jsx:52` | `'WO, Amendment, or Vendor MSA'` | `'Work Order, Amendment, or Vendor MSA'` |
| `NewContractWizard.jsx:471` | `"Standalone WO"` | `"Standalone Work Order"` |
| `NewContractWizard.jsx:833` | `"Verify all merge fields before..."` | `"Verify all contract details before generating the document."` |
| `NewProposalWizard.jsx:461,469` | `'ST'` | `'State'` |
| `NewProposalWizard.jsx:469,535` | `'$/Mo'` | `'Monthly Rate'` |
| `NewProposalWizard.jsx:505,569` | `'Mo. Rate (recurring)'` | `'Monthly Rate (recurring)'` |
| `NewProposalWizard.jsx:538` | `'NC'` badge | `'No Charge'` |
| `Operations.jsx:359` | `'WO'`, `'WR'` filters | `'Work Order'`, `'Work Request'` |
| `Operations.jsx:90` | `'Med'` badge | `'Medium'` |
| `SendQueue.jsx:57` | `'MSA'` badge | `'Vendor MSA'` |
| `Admin.jsx:23` | `'MSA'` in DOCTYPE_LABELS | `'Vendor MSA'` |
| `LocationDetail.jsx:76,79-80` | `'Insp.'`, `'Water Treat.'` | `'Inspection'`, `'Water Treatment'` |
| `LocationDetail.jsx:84-87` | `'IDD'`, `'DCA'` | Add tooltips with full names |
| `LocationManager.jsx:314` | `'Water Treat.'` | `'Water Treatment'` |
| `ContractsList.jsx:415` | `'AP Code'` no tooltip | Add `title="Accounts Payable Code"` |
| `NavPanel.jsx:39` | `'MSAs'` | `'Master Service Agreements'` |
| `MsaList.jsx:37` | `'MSAs'` heading | `'Master Service Agreements'` |

### Critical Bug Fixes

| File | Issue | Fix |
|------|-------|-----|
| `ContractDetail.jsx:68` | `user?.email` undefined — crash on Generate | Change to `userEmail` |
| `NewContractWizard.jsx:354` | `userEmail,` in writeAuditLog — silent data loss | Change to `performedBy: userEmail,` |
| `Admin.jsx:23` | DOCTYPE_LABELS keys `0,1,2` don't match enum `100000000,...` | Use proper enum values or import `ContractTypeLabel` |

---

## Data Flow

```
User opens wizard
  → My Drafts landing (if WIP drafts exist for this user)
    → Resume draft (loads at dcfg_wizard_step) OR Start new
  → Step 1: Select customer
  → Step 2: Doc type, vendor, location, date
    → [Next] creates WIP record in Dataverse (silent, "Draft saved" indicator)
    → [Contracts only] WIP appears in Send Queue "Needs Work Order Number" tab
  → Step 3: Contractor & signer (PATCH WIP record)
  → Step 4: Exhibit A lines (PATCH WIP record + save lines to Dataverse)
  → Step 5: Review & Generate
    → [Amendment without description] Orange warning, not blocker
    → Generate: PATCH status WIP → Draft + createDocumentRequest()

Meanwhile (async):
  Approval staff see WIP in Send Queue
  → Assign WO number → PATCH dcfg_contract_number
  → User resumes draft, number is populated naturally on review step
  → My Drafts list shows "WO# assigned" badge
```

---

## Implementation Order

1. **Schema** — add WIP status value, `dcfg_wizard_step` column, `dcfg_created_by_email` column, Web API access
2. **portalApi.js** — add `updateContract()`, `deleteContractLines()`, `fetchMyWIPDrafts()`, update `fetchContractsByCustomer()` select, add WIP to ContractStatus enum
3. **Draft save infrastructure** — create WIP on Step 2 Next, PATCH on subsequent steps, save lines at Step 4, modify Generate to PATCH WIP → Draft
4. **My Drafts landing** — personal WIP list, resume at saved step, delete (soft), skip-if-empty
5. **Send Queue "Needs Work Order Number" tab** — new filter for WIP + no contract number, inline number assignment
6. **Amendment flow** — parent WO picker display format, program selection, service location description, Step 5 warning
7. **Code review fixes** — abbreviations, critical bugs
8. **Proposal Wizard** — same draft save pattern (no Send Queue integration)
9. **Build + deploy**

---

## Technical Notes

- WIP status (100000007) is invisible to all existing views — no query changes needed for existing screens
- `dcfg_service_location_description` already deployed to Test + Prod — verify Table Permissions grant write access
- Parent WO picker resolves names client-side from `locations` and `allVendors` arrays (already loaded in wizard state)
- Line upsert at Step 4: delete existing lines + create new (simpler than true upsert, line count is small)
- Generating without WO number is allowed — document template handles null gracefully
- Save failure shows red "Save failed" indicator that does NOT auto-fade (defensive UX)
- URL parameter `?draftId=GUID` is a future enhancement for bookmark/share support (not MVP)
