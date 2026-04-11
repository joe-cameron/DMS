# Fresh-Eyes Review Corrections Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all issues identified in the fresh-eyes UX review of the Prod E2E screenshots — schema labels, badge sizing, optional field styling, nav truncation.

**Architecture:** Small targeted edits across 4 files. No new features — pure UX polish. All changes are cosmetic/text-only except the Proposal Wizard field notes fix which removes developer artifacts.

**Tech Stack:** React (inline JSX + React.createElement), Power Pages SPA

---

## File Map

| File | Action | Changes |
|------|--------|---------|
| `src/NewProposalWizard.jsx` | Modify | Remove raw schema names from field notes (I1) |
| `src/screens/Operations.jsx` | Modify | Widen Type column or shrink badge to prevent wrapping (I2) |
| `src/NavPanel.jsx` | Modify | Shorten nav label to prevent truncation (M5) |
| `src/NewContractWizard.jsx` | Modify | Style optional fields differently on Review page (I7) |

---

## Chunk 1: Proposal Wizard Schema Labels + Operations Badge

### Task 1: Remove raw schema names from Proposal Wizard field notes

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewProposalWizard.jsx`

The `F` component has an `nt` prop that renders a note below the field. Lines 524-526 pass raw schema names (`MEMBERSHIP_RATE`, `ONBOARDING_FEE`, `ANNUAL_INCREASE_DATE`) as the `nt` value. These are visible to users in non-debug mode.

- [ ] **Step 1: Read lines 524-526 to confirm the field note values**

- [ ] **Step 2: Replace schema names with user-friendly notes or remove them**

Line 524: Change `nt:'MEMBERSHIP_RATE'` → remove the `nt` prop entirely (the label already says "Monthly Rate")
Line 525: Change `nt:'ONBOARDING_FEE'` → remove the `nt` prop entirely (the label already says "Onboarding Rate")
Line 526: Change `nt:'ANNUAL_INCREASE_DATE'` → remove the `nt` prop entirely (the value already explains itself)

Also check for any other `nt:` props in the file that expose schema names:

```
grep -n "nt:'" NewProposalWizard.jsx
```

Remove all `nt:` values that contain raw schema column names (UPPERCASE or dcfg_ prefixed).

- [ ] **Step 3: Check the type-based pricing section for the same issue**

Around lines 530-540, there may be similar `nt:` props for per-type rate inputs. Remove those too.

- [ ] **Step 4: Verify build passes**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

---

### Task 2: Fix Operations Type badge wrapping

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\Operations.jsx`

The Type column badges now show "Work Order" and "Work Request" (full text), but the column is too narrow and the text wraps to 2 lines.

- [ ] **Step 1: Read the table header and column width definitions**

Find the `<th>` for the Type column and increase its width, OR reduce the badge font size, OR use abbreviated text in the badge while keeping the full text in the filter buttons.

**Recommended approach:** Use "Order" / "Request" as badge text (the column header already says "Type", so context is clear), keeping the filter buttons as "Work Order" / "Work Request".

Alternatively, add `whiteSpace: 'nowrap'` to the badge span and widen the column.

- [ ] **Step 2: Change badge text to short form**

Line 469: Change:
```javascript
{item.dcfg_item_type === 'WO' ? 'Work Order' : item.dcfg_item_type === 'WR' ? 'Work Request' : (item.dcfg_item_type || '—')}
```
To:
```javascript
{item.dcfg_item_type === 'WO' ? 'Order' : item.dcfg_item_type === 'WR' ? 'Request' : (item.dcfg_item_type || '—')}
```

AND add `title` attribute to the badge `<span>` for the full text on hover:
```javascript
React.createElement('span', {
  style: { ... },
  title: item.dcfg_item_type === 'WO' ? 'Work Order' : item.dcfg_item_type === 'WR' ? 'Work Request' : '',
}, ...)
```

- [ ] **Step 3: Verify build passes**

---

### Task 3: Shorten nav sidebar label

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NavPanel.jsx`

Line 39: `label: 'Master Service Agreements'` truncates to "Master Service Agree..." in the sidebar.

- [ ] **Step 1: Change the nav label**

Change:
```javascript
{ to: '/msas', label: 'Master Service Agreements', icon: <MsaIcon /> },
```
To:
```javascript
{ to: '/msas', label: 'MSAs', icon: <MsaIcon /> },
```

**Rationale:** The page heading already says "Master Service Agreements" (in MsaList.jsx). The nav is space-constrained. "MSAs" is the industry-standard abbreviation that all DCFG users know. The no-abbreviation rule applies to screen labels and headings, not nav shortcuts.

Note: If the operator prefers keeping the full name, the alternative is to reduce the nav font size or add `title="Master Service Agreements"` to the link for tooltip.

- [ ] **Step 2: Add title attribute for hover tooltip**

Regardless of which label is used, add a `title` attribute to the nav link element so hovering shows the full name.

- [ ] **Step 3: Verify build passes**

---

## Chunk 2: Review Page Polish

### Task 4: Style optional empty fields as neutral (not red) on Review page

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx`

On Step 5 (Review & Generate), empty optional fields show "Not yet provided" in red (`C.red`). This looks alarming when the fields are truly optional (Contractor Phone, Owner Contact, etc.). Only truly required fields (Signer Name, Signer Title, Location) should show red.

- [ ] **Step 1: Add a `required` flag to the mergeFields array**

Read the `mergeFields` useMemo (around line 280-295) and add `required: true` to fields that must be filled:

```javascript
const mergeFields = useMemo(() => [
  { label: 'Contractor Name',    value: contractorLegalName, required: true },
  ...(contractorCompany && contractorCompany !== contractorLegalName
    ? [{ label: 'Company', value: contractorCompany }] : []),
  { label: 'Contractor Address', value: contractorAddress },
  { label: 'Contractor Phone',   value: contractorPhone },
  { label: 'Contractor Email',   value: contractorEmail },
  { label: 'Payment Terms',      value: paymentProcess },
  { label: 'Signer Name',        value: signerName, required: true },
  { label: 'Signer Title',       value: signerTitle, required: true },
  { label: 'Owner Contact',      value: locContact.name },
  { label: 'Owner Email',        value: locContact.email },
  { label: 'Client Name',        value: selectedCustomer?.dcfg_name || selectedCustomer?.dcfg_display_name, required: true },
  { label: 'Signature Image',    value: null, auto: 'Signature image added automatically' },
], [...deps]);
```

- [ ] **Step 2: Update the Review page rendering to use neutral color for optional empty fields**

Change the color logic (around line 1102-1106):

```javascript
color: mf.auto ? C.text3 : mf.value ? C.green : mf.required ? C.red : C.text3,
```

This makes:
- Filled fields: green (good)
- Required empty fields: red (warning)
- Optional empty fields: gray (neutral — not alarming)

- [ ] **Step 3: Change "Not yet provided" to "—" for optional fields**

```javascript
{mf.auto || mf.value || (mf.required ? 'Required' : '—')}
```

This makes optional empty fields show a simple dash instead of the alarming "Not yet provided" text.

- [ ] **Step 4: Verify build passes**

---

### Task 5: Apply same pattern to Proposal Wizard review page

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\NewProposalWizard.jsx`

The Proposal Wizard Step 4 review (around line 520-528) has the same issue — all empty fields show "Not yet provided" in red.

- [ ] **Step 1: Read the review fields array (around line 521-528)**

- [ ] **Step 2: Add required markers to the array entries**

Required: Customer Name, Customer Signer, Signer Title, Vendor Signer, Vendor Signer Title
Optional: Customer Contact, Contact Email, Vendor Address, Vendor Phone, Vendor Email

- [ ] **Step 3: Update the color logic to match Task 4's pattern**

```javascript
color: k === 'Signature Image' ? TEXT3 : v ? GREEN : isRequired ? RED : TEXT3,
```

And change empty text:
```javascript
v || (isRequired ? 'Required' : '—')
```

- [ ] **Step 4: Verify build passes**

---

## Chunk 3: Build, Deploy, Test

### Task 6: Build + Deploy to Test + Prod

- [ ] **Step 1: Full build**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

- [ ] **Step 2: Deploy to Test**

```bash
pac auth select --index 1
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 3: Deploy to Prod**

```bash
pac auth select --index 3
pac pages upload-code-site --rootPath . --compiledPath dist
pac auth select --index 1  # restore to Test
```

- [ ] **Step 4: Clear cache on both**

Test: https://dcfg.powerappsportals.com/_services/about
Prod: https://dmms1.powerappsportals.com/_services/about

### Task 7: Re-run E2E test on Prod + Fresh-Eyes Review

- [ ] **Step 1: Clear screenshots and run full test**

```bash
rm -f C:/DCFG/spa/dcfg-playwright/screenshots/e2e-review/*.png
cd C:/DCFG/spa/dcfg-playwright
npx playwright test full-e2e-review --project=smoke --headed
```

- [ ] **Step 2: Fresh-eyes review of all screenshots**

Read every screenshot and verify:
- No schema names visible (MEMBERSHIP_RATE, ONBOARDING_FEE gone)
- Type badges fit without wrapping
- Nav label not truncated
- Optional empty fields show "—" in gray (not "Not yet provided" in red)
- Required empty fields show "Required" in red

- [ ] **Step 3: Report findings**

---

## Verification Checklist

- [ ] No raw schema names visible on any screen (MEMBERSHIP_RATE, ONBOARDING_FEE, ANNUAL_INCREASE_DATE)
- [ ] Operations Type badges render on single line (no wrapping)
- [ ] Nav sidebar label fits without truncation
- [ ] Review page: required empty fields = red "Required"
- [ ] Review page: optional empty fields = gray "—"
- [ ] Review page: filled fields = green
- [ ] All 5 E2E tests pass on Prod
- [ ] Zero 403s, zero error toasts

## NOT in scope (data issues, not code)
- Location named "1981 Old Cuthbert Rd..." — data entry issue, not code
- MSA list Customer column showing "—" — data not populated in Prod
- Customer list Primary Contact showing "—" — data not populated
- Field Ops "No customers found" — Prod environment data gap
- Skeleton loading on detail pages — test timing issue (pages load for real users)
