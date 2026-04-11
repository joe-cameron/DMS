# Contract Wizard — Customer-First Rewrite

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the Contract Wizard so the user selects a customer first, then the system determines template family based on TPA relationship — eliminating the manual Decades/Bancroft family selection. Incorporate all findings from fresh-eyes UX review.

**Architecture:** The current 5-step wizard (Family/Type → Customer/Location → Contractor → Exhibit A → Review) becomes a customer-driven flow (Customer → Doc Type/Vendor/Location → Contractor → Exhibit A → Review). The `ContractFamily` concept moves from user-facing choice to system-derived value based on `dcfg_is_tpa` and `dcfg_has_custom_templates` on the customer record.

**Tech Stack:** React (inline JSX), Dataverse OData Web API, existing portalApi.js helpers, Power Pages Enhanced Data Model

**UX Review Score:** 7/10 → targeting 8.5 with these fixes

---

## Terminology Rules (Apply Throughout)

These replacements apply to ALL wizard screens and the Proposal wizard:

| Current | Replace With |
|---|---|
| "Merge Fields — Contract Body" | "Contract Details" |
| "MSA Body — Merge Fields" | "Proposal Details" |
| "WO" (in stepper subtitles) | "Work Order" |
| "(New Flow)" tab label | Remove — just "Contract Wizard" |
| "Routes to Tyler for approval" | "Routes to management for approval" |
| "Signature Image: — / — (automatic)" | "Signature image added automatically" |
| "AP Code" column | Add tooltip: "Accounts Payable Code" |
| "TPA" badge | Keep badge but add tooltip: "Third-Party Administrator" |
| "Standalone WO" program card | "Standalone Work Order" |

---

## Schema Changes

Two new boolean columns needed on `dcfg_customer`:

| Column | Logical Name | Type | Default | Purpose |
|---|---|---|---|---|
| TPA Customer | `dcfg_is_tpa` | Boolean | No | Customer is a third-party administration relationship |
| Custom Templates | `dcfg_has_custom_templates` | Boolean | No | TPA customer has their own document templates |

**No new tables.** Template resolution already uses `dcfg_contract_family` on the customer record.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `portalApi.js` | Modify | Add `fetchCustomerById()`, `fetchVendorMSAs()`, update `fetchCustomers()` select |
| `NewContractWizard.jsx` | Modify (major) | Rewrite step flow, all 5 steps updated |
| `NewProposalWizard.jsx` | Modify (minor) | Terminology fixes, add "+ Add Customer", fix math display |
| `screens/CustomerList.jsx` | Modify (minor) | Add TPA checkbox to new customer form |

---

## New Step Flow

| Step | Title | Stepper Sub | Content |
|---|---|---|---|
| **1** | Customer | Select or create | Customer dropdown + "+ Add Customer" inline. Programs (cost assignment) as selectable cards with budget bars. Locations list (name first, address second). Instruction text for programs. |
| **2** | Document Type | Work Order, Amendment, or Vendor MSA | Doc type cards. **Amendment: includes WO picker** (dropdown of existing WOs for this customer). Vendor selection with MSA check. Location dropdown (carries from Step 1 if selected). Contract date. |
| **3** | Contractor & Signer | Vendor details + signer | Vendor pre-filled from Step 2 as **read-only with "Change" link** (not a search field). Contractor fields editable. Signer block required. Signature line shows "Signature image added automatically". |
| **4** | Exhibit A — Lines | Line items + cost codes | Same as current. Add $ prefix to amount fields. Add tooltip on AP Code. |
| **5** | Review & Generate | Validate + generate | Header: "Contract Details" (not "Merge Fields"). Per-section "Edit" links to jump back. **Generate button disabled if required fields missing** (Client Name, Signer). Prominent green Generate button matching Proposal wizard pattern. |

---

## Key Logic

- `derivedFamily` = if customer `dcfg_is_tpa` AND `dcfg_has_custom_templates` → use customer's `dcfg_contract_family`. Otherwise → `ContractFamily.Decades`
- Vendor MSA check: query `dcfg_msas` for active MSAs matching vendor
  - If creating a Vendor MSA doc type AND no MSA exists → info message "This will create a new MSA for this vendor" (not a warning)
  - If creating a WO/Amendment AND no MSA exists → orange warning "No MSA on file — proceed with caution"
- Amendment: **must select parent Work Order** from dropdown filtered to customer's existing WOs. Vendor auto-fills from parent WO. Location auto-fills from parent WO. Both can be overridden.
- Programs: selection is **optional** — instruction text: "Select a program to assign costs, or choose Standalone Work Order for individual billing"
- Location selection in Step 1 is **informational preview** — actual location binding happens in Step 2 dropdown (pre-selected if user clicked one in Step 1)

---

## Chunk 1: Schema + API

### Task 1: Add TPA columns to dcfg_customer (Dataverse)

**Files:**
- Create: `scripts/add-tpa-columns.ps1`

- [ ] **Step 1: Write PowerShell script to add columns**

```powershell
$env = "https://org0c17e98d.crm.dynamics.com/"
Connect-CrmOnline -ServerUrl $env

$isTPAMetadata = New-CrmBooleanField -SchemaName "dcfg_is_tpa" -DisplayName "TPA Customer" -DefaultValue $false -Description "Third-party administration relationship"
Add-CrmField -EntityLogicalName "dcfg_customer" -Field $isTPAMetadata -SolutionName "DCFGSystemTest"

$hasTemplatesMetadata = New-CrmBooleanField -SchemaName "dcfg_has_custom_templates" -DisplayName "Custom Templates" -DefaultValue $false -Description "TPA customer has their own document templates"
Add-CrmField -EntityLogicalName "dcfg_customer" -Field $hasTemplatesMetadata -SolutionName "DCFGSystemTest"
```

- [ ] **Step 2: Run script against Test**
- [ ] **Step 3: Verify columns in maker portal**
- [ ] **Step 4: Set Bancroft to `dcfg_is_tpa=true`, `dcfg_has_custom_templates=true`, `dcfg_contract_family=100000002` (Bancroft)**
- [ ] **Step 5: Set Archway Programs to `dcfg_is_tpa=true`, `dcfg_has_custom_templates=false`**
- [ ] **Step 6: Enable Web API access for both columns** (add to `Webapi/dcfg_customer/fields` site setting)
- [ ] **Step 7: Commit script**

### Task 2: Update portalApi.js

**Files:**
- Modify: `src/portalApi.js`

- [ ] **Step 1: Update `fetchCustomers()` to include TPA fields in $select**

Add `dcfg_is_tpa,dcfg_has_custom_templates,dcfg_contract_family` to the customers select list.

- [ ] **Step 2: Update existing `fetchCustomer(id)` to include TPA fields**

The existing `fetchCustomer()` in portalApi.js already fetches a single customer. Add `dcfg_is_tpa,dcfg_has_custom_templates,dcfg_contract_family` to its `$select`. Do NOT create a duplicate function.

- [ ] **Step 3: Add `fetchVendorMSAs(vendorId)` helper**

```javascript
export async function fetchVendorMSAs(vendorId) {
  return apiGet(`/dcfg_msas?$filter=_dcfg_vendor_id_value eq ${vendorId} and dcfg_active_flag eq true&$select=dcfg_msaid,dcfg_name,dcfg_expiration_date&$top=5`);
}
```

- [ ] **Step 4: Add `fetchContractsByCustomer(customerId)` helper** (for Amendment WO picker)

```javascript
export async function fetchContractsByCustomer(customerId) {
  return apiGet(`/dcfg_contracts?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_contract_type eq ${ContractType.WorkOrder}&$select=dcfg_contractid,dcfg_contract_number,dcfg_client_name,_dcfg_vendor_id_value,_dcfg_property_id_value&$orderby=dcfg_contract_date desc`);
}
```

- [ ] **Step 5: Verify build passes**
- [ ] **Step 6: Commit**

---

## Chunk 2: Wizard Rewrite — Steps 1-2

### Task 3: Rewrite STEPS array, state, and derived family

**Files:**
- Modify: `src/NewContractWizard.jsx` (lines 47-61, 76-104)

- [ ] **Step 1: Update STEPS array**

```javascript
const STEPS = [
  { label: 'Customer',            sub: 'Select or create' },
  { label: 'Document Type',       sub: 'Work Order, Amendment, or Vendor MSA' },
  { label: 'Contractor & Signer', sub: 'Vendor details + signer' },
  { label: 'Exhibit A — Lines',   sub: 'Line items + cost codes' },
  { label: 'Review & Generate',   sub: 'Validate + generate' },
];
```

- [ ] **Step 2: Replace `family` state with `derivedFamily` memo**

```javascript
const derivedFamily = useMemo(() => {
  const cust = customers.find(c => c.dcfg_customerid === customerId);
  if (cust?.dcfg_is_tpa && cust?.dcfg_has_custom_templates) {
    return cust.dcfg_contract_family ?? ContractFamily.Decades;
  }
  return ContractFamily.Decades;
}, [customers, customerId]);
```

- [ ] **Step 3: Replace all `family` references with `derivedFamily`** throughout the file

- [ ] **Step 4: Fix `dcfg_client_name` source — use customer name, not location name**

The current code sets `dcfg_client_name` from `selectedLocation?.dcfg_name`. This is wrong — it should come from the customer:
```javascript
// OLD: dcfg_client_name: selectedLocation?.dcfg_name,
// NEW:
dcfg_client_name: selectedCustomer?.dcfg_display_name || selectedCustomer?.dcfg_name,
```
Find all places `dcfg_client_name` is set and fix the source.

- [ ] **Step 5: Update `ContractTypeLabel` — "Contractor MSA" → "Vendor MSA"**

In `portalApi.js`, update the label map:
```javascript
// OLD: [ContractType.ContractorMSA]: 'Contractor MSA'
// NEW:
[ContractType.ContractorMSA]: 'Vendor MSA'
```
This ensures list views, filters, and badges all say "Vendor MSA".

- [ ] **Step 6: Verify build passes**
- [ ] **Step 7: Commit**

### Task 4: Build new Step 1 — Customer + Programs + Locations

**Files:**
- Modify: `src/NewContractWizard.jsx` (Step 1 JSX block)

- [ ] **Step 1: Customer dropdown + "+ Add Customer" inline form**

Customer dropdown with all active customers. Below: "+ Add Customer" link that expands inline form (name required, contact behind "+ Add Contact" expand). On save: creates customer, sets customerId, collapses form.

- [ ] **Step 2: Customer info card with TPA badge**

When customer selected, show card with:
- Avatar initial + name + TPA badge (with title="Third-Party Administrator" tooltip)
- Contact name, email, phone
- If TPA + custom templates: "TPA — using [Family] templates"
- If TPA + no custom templates: "TPA — using Decades templates"

- [ ] **Step 3: Programs section**

Label: "PROGRAMS — COST ASSIGNMENT"
Instruction text: *"Select a program to assign costs, or choose Standalone Work Order for individual billing."*
Selectable cards with budget bars. Cards show name, budget total, budget remaining, progress bar.
Selection is optional — if none selected, defaults to Standalone.
When >3 programs: use 2-column grid instead of single row.

- [ ] **Step 4: Locations section**

Label: "LOCATIONS"
List of customer locations: **name first** (bold), address second (gray), type badge on right.
Third line (if available): contact name, phone, email in small muted text.
Radio-style selection indicator (not tiny dot — use proper radio or checkmark).
Selection here is **preview** — pre-selects the Step 2 location dropdown.
Show compliance badges (Expiring, Expired) where applicable.

- [ ] **Step 5: Empty state guidance**

When no customer selected, show helper text: *"Select a customer to see their programs and locations."*

- [ ] **Step 6: Next validation**

Next enabled when `customerId` is set. Program and location selection are optional on this step.

- [ ] **Step 7: Verify build + visual check**
- [ ] **Step 8: Commit**

### Task 5: Build new Step 2 — Document Type + Vendor + Location

**Files:**
- Modify: `src/NewContractWizard.jsx` (Step 2 JSX block)

- [ ] **Step 1: Document type cards**

Three cards: Work Order, Amendment, Vendor MSA.
- Work Order: "New contract for a specific location and scope of work."
- Amendment: "Modifies the scope or value of an existing Work Order."
- Vendor MSA: "Master subcontract agreement. Routes to management for approval."

- [ ] **Step 2: Amendment — Parent Work Order picker**

When Amendment selected, show:
- "Select Work Order to Amend" dropdown — filtered to customer's existing WOs via `fetchContractsByCustomer()`
- When parent WO selected: auto-fill vendor and location from parent WO
- Both vendor and location can be overridden
- Amendment Number field (required)

- [ ] **Step 3: Vendor selection with context-aware MSA check**

Vendor dropdown (search existing vendors).
After vendor selected, query `fetchVendorMSAs(vendorId)`:
- If doc type is Vendor MSA AND no MSA exists: info message "This will create a new MSA for this vendor" (blue, not orange)
- If doc type is WO/Amendment AND no MSA exists: orange warning "No MSA on file for this vendor — proceed with caution"
- If active MSA found: green "MSA on file" badge
- Badge/warning only appears AFTER vendor is actually selected (not before)

- [ ] **Step 4: Location + Contract Date**

Location dropdown (filtered to customer, pre-selected from Step 1 if user clicked one).
Contract Date picker (defaults to today).

- [ ] **Step 5: Step 2 validation**

Next enabled when: doc type selected + (location selected for WO/Amendment OR vendor selected for Vendor MSA).

- [ ] **Step 6: Verify build + visual check**
- [ ] **Step 7: Commit**

---

## Chunk 3: Steps 3-5 + Terminology

### Task 6: Adjust Step 3 — Contractor & Signer

**Files:**
- Modify: `src/NewContractWizard.jsx` (Step 3 JSX block)

- [ ] **Step 1: Replace "Search Vendor" with read-only vendor display + "Change" link**

Show selected vendor as read-only text: "1-800-GOT-JUNK?" with a "Change" link that reveals the vendor search dropdown. This eliminates the confusion of a search field when vendor is already selected.

- [ ] **Step 2: If "Contractor Legal Name" and "Company" would show the same value, auto-hide Company field**

```javascript
{contractorCompany && contractorCompany !== contractorLegalName && (
  <Field label="Company">...</Field>
)}
```

- [ ] **Step 3: Signature Image field text**

Replace `${signerName || '—'} / ${signerTitle || '—'} (automatic)` with:
`"Signature image added automatically"`

- [ ] **Step 4: Verify build**
- [ ] **Step 5: Commit**

### Task 7: Adjust Step 4 — Exhibit A

**Files:**
- Modify: `src/NewContractWizard.jsx` (Step 4 JSX block)

- [ ] **Step 1: Add $ prefix to amount input fields**

```javascript
<div style={{ display:'flex', alignItems:'center' }}>
  <span style={{ color: C.text3, fontSize: 12, marginRight: 4 }}>$</span>
  <input style={{ ...s.lnInput, textAlign:'right', fontFamily:C.fMono }} ... />
</div>
```

- [ ] **Step 2: Add tooltip to AP Code column header**

```javascript
<th title="Accounts Payable Code" style={{ ...s.lnTh, width: 110 }}>AP Code</th>
```

- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

### Task 8: Rewrite Step 5 — Review & Generate

**Files:**
- Modify: `src/NewContractWizard.jsx` (Step 5 JSX block)

- [ ] **Step 1: Change header from "Merge Fields — Contract Body" to "Contract Details"**

- [ ] **Step 2: Add per-section "Edit" links**

Each card gets an "Edit" link in the header that navigates to the relevant step:
- "Contract Details" → Edit jumps to Step 3
- "Exhibit A — Line Items" → Edit jumps to Step 4

```javascript
<Card title="Contract Details" action={<button style={s.editLink} onClick={() => goStep(3)}>Edit</button>}>
```

- [ ] **Step 3: Generate button disabled when required fields missing**

Check: signerName, signerTitle, contractorLegalName, locationId. If any empty → disable Generate + show "Complete all required fields to generate"

- [ ] **Step 4: Prominent green Generate button**

Match the Proposal wizard's pattern — large green button at bottom with lightning icon. Move from sidebar to inline bottom position.

- [ ] **Step 5: Summary cards at bottom (not sidebar)**

Three horizontal cards below the review grid:
- Final Summary (customer, type, family, lines count)
- Contract Value ($X,XXX.XX in large gold text)
- Generate button (green, full-width within card)

- [ ] **Step 6: Verify build + visual check**
- [ ] **Step 7: Commit**

### Task 9: Apply terminology fixes to Proposal Wizard

**Files:**
- Modify: `src/NewProposalWizard.jsx`

- [ ] **Step 1: "MSA Body — Merge Fields" → "Proposal Details"**
- [ ] **Step 2: Add "+ Add Customer" link to Step 2** (match Contract Wizard pattern)
- [ ] **Step 3: Add $ prefix to fee input fields on Step 3**
- [ ] **Step 4: Fix contract value calculation** — ensure displayed total matches visible inputs × term
- [ ] **Step 5: "Signature Image: Automatic" → "Signature image added automatically"**
- [ ] **Step 6: Verify build**
- [ ] **Step 7: Commit**

### Task 10: Clean up removed code

**Files:**
- Modify: `src/NewContractWizard.jsx`

- [ ] **Step 1: Remove `setFamily` state and FamilyCard/TypeCard tag/note props**
- [ ] **Step 2: Remove `FamilyCard` component if no longer referenced**
- [ ] **Step 3: Remove unused `ownerExpanded`, `contractorExpanded` state vars**
- [ ] **Step 4: Update file header comment to document new flow**
- [ ] **Step 5: Verify build — zero warnings**
- [ ] **Step 6: Commit**

---

## Chunk 4: Deploy + Verify

### Task 11: Schema on Prod + Deploy (Test → Prod, operator specifies envs)

- [ ] **Step 1: Run add-tpa-columns.ps1 against Prod (org06f5de0b, pac auth index 3)**
- [ ] **Step 2: Set Bancroft to TPA with custom templates on Prod**
- [ ] **Step 3: Create Archway Programs customer on Prod if not exists, set TPA without custom templates**
- [ ] **Step 4: Enable Web API access for TPA columns on Prod** (add to `Webapi/dcfg_customer/fields`)
- [ ] **Step 5: Build SPA**
- [ ] **Step 6: Deploy to Test (pac auth index 1)**
- [ ] **Step 7: Deploy to Prod (pac auth index 3)**
- [ ] **Step 8: Restore pac auth to Test (index 1)**
- [ ] **Step 9: Clear cache — dcfg.powerappsportals.com + dmms1.powerappsportals.com**

### Task 12: Functional test + screenshot review

- [ ] **Step 1: Run full functional test against Test**
- [ ] **Step 2: Capture wizard screenshots (all steps, all customer types)**
- [ ] **Step 3: Fresh-eyes review of captured screenshots**
- [ ] **Step 4: Fix any issues found**
- [ ] **Step 5: Final deploy if fixes needed**

---

## Verification Checklist

### Flow
- [ ] Step 1 shows customer dropdown, not family cards
- [ ] "+ Add Customer" creates inline, only name required, contact behind "+ Add Contact"
- [ ] TPA badge appears with tooltip "Third-Party Administrator"
- [ ] Programs show with instruction text, budget bars, optional selection
- [ ] Locations show name first, address second, with compliance badges
- [ ] Step 2 shows doc type cards (Work Order, Amendment, Vendor MSA)
- [ ] Amendment shows parent WO picker — vendor + location auto-fill from parent
- [ ] Vendor MSA creation shows info "This will create a new MSA" (not warning)
- [ ] WO/Amendment with no vendor MSA shows orange warning
- [ ] MSA check badge only appears AFTER vendor selected

### Terminology
- [ ] No "Merge Fields" anywhere — replaced with "Contract Details" / "Proposal Details"
- [ ] No "WO" abbreviation — always "Work Order"
- [ ] No "Tyler" — says "management"
- [ ] No "(New Flow)" in any label
- [ ] "Signature image added automatically" — no "— / —"
- [ ] AP Code has tooltip
- [ ] TPA badge has tooltip

### Step 3
- [ ] Vendor shown as read-only with "Change" link (not search field)
- [ ] Company field hidden when same as Contractor Legal Name

### Step 4
- [ ] $ prefix on amount fields
- [ ] AP Code tooltip present

### Step 5
- [ ] Header says "Contract Details" not "Merge Fields"
- [ ] Per-section "Edit" links jump to correct step
- [ ] Generate disabled when required fields missing
- [ ] Prominent green Generate button at bottom
- [ ] Summary cards horizontal at bottom (not right sidebar)

### Data Integrity
- [ ] `dcfg_client_name` on generated contracts contains customer name (not location name)
- [ ] Existing contracts (created before rewrite) still display correctly in list views
- [ ] `ContractTypeLabel` shows "Vendor MSA" (not "Contractor MSA") everywhere

### Templates
- [ ] Bancroft customers get Bancroft templates automatically
- [ ] Archway Programs (TPA, no custom) gets Decades templates
- [ ] Non-TPA customers always get Decades templates
- [ ] Existing contracts unaffected
- [ ] `resolveTemplate()` receives `derivedFamily` — no duplicate TPA logic

### Proposal Wizard
- [ ] "Proposal Details" header (not "Merge Fields")
- [ ] "+ Add Customer" available
- [ ] $ prefix on fee fields
- [ ] Contract value math is correct
- [ ] "Signature image added automatically"
