# Design Spec: Contract Composer Vendor Entry + Project/BidComp Fixes

**Date:** 2026-04-30
**Status:** Draft
**Branch:** code-review-2026-04-09

## Scope — 5 Items

### Item 1: Add New Vendor from VA Composer Slideout

**Problem:** When creating a Vendor Agreement, the vendor picker slideout only allows selecting existing vendors. If the vendor doesn't exist yet, the user must leave the composer, create the vendor elsewhere, and come back.

**Solution:** Add a "+ New Vendor" button to the vendor picker drawer. Clicking it transforms the drawer content into a compact vendor entry form. On submit, the vendor is created in Dataverse and auto-selected on the composer.

**Interaction flow:**
1. User clicks VENDOR chip on VA composer -> vendor picker drawer opens (existing)
2. "+ New Vendor" button appears below search bar, above trade filters
3. Click -> drawer content replaces with entry form. Header changes to "New Vendor" with back arrow
4. User fills required fields, optionally expands additional details
5. "Create Vendor & Select" button submits
6. POST to `dcfg_vendors` with `dcfg_active_flag: true`
7. Drawer closes, vendor auto-selected on composer chip strip

**Required fields:**
- `dcfg_legal_name` (text)
- `dcfg_email` (text)
- `dcfg_phone` (text)
- `dcfg_address`, `dcfg_city`, `dcfg_state`, `dcfg_zip` (address block)
- `dcfg_trade` (chip select from 20 approved trades)

**Optional fields (collapsed section):**
- `dcfg_display_name`
- `dcfg_contact_name`
- `dcfg_signer_name`, `dcfg_signer_title`, `dcfg_signer_phone`
- `dcfg_payment_terms`, `dcfg_net_terms`
- `dcfg_insurance_provider`, `dcfg_insurance_policy_number`, `dcfg_insurance_expiration_date`, `dcfg_insurance_gl_expiration`, `dcfg_insurance_coverage_types`
- `dcfg_notes`
- File upload (minimal dropzone -> SharePoint `DCFG_Attachments/Vendors/{VendorName}/`, URL stored in `dcfg_insurance_file_url`)

**Alert banner (not blocker):** "New vendors need a signed MSA and proof of insurance. These are not required now — Send Queue Clearance will flag missing items."

**Schema changes:** None. All columns exist on `dcfg_vendor`.

**Mockup:** `scratch/brook-exhibit-b/mockups/vendor-slideout-before-after.html`

**Files to modify:**
- `src/screens/NewContractWizard.jsx` — add new vendor form state + drawer mode toggle in the vendor drawer renderer

---

### Item 2: Remove Non-Functional "New Project" Button

**Problem:** The Projects screen has a "New Project" button that doesn't work.

**Solution:** Remove the button. Project creation will be added as a proper feature later.

**Files to modify:**
- `src/screens/ProjectList.jsx` or `src/screens/ProjectDashboard.jsx` — remove the new project button element

---

### Item 3: Project SharePoint Links — Store Verified URLs

**Problem:** The SPA constructs SharePoint project site URLs, but the constructed URLs 404 because the path doesn't match the actual site names.

**Solution:** Store the verified `siteUrl` directly on the project record. The SPA reads this stored URL instead of constructing one. Source of truth: `brain/harvest-37-manifest.json` (37+ project sites already crawled).

**Schema change:**
- Add `dcfg_sharepoint_site_url` (String, URL format, max 500 chars) on `dcfg_project` table

**Data backfill:**
- One-time script: read `brain/harvest-37-manifest.json`, match project records by job number/name, PATCH `dcfg_sharepoint_site_url` with the verified `siteUrl`

**SPA change:**
- Wherever the SPA constructs a SharePoint project link, read `dcfg_sharepoint_site_url` from the project record instead. If null, don't show the link (don't construct a guess).

**Site settings:**
- Add `dcfg_sharepoint_site_url` to `Webapi/dcfg_project/fields` site setting

**Files to modify:**
- `src/screens/ProjectDashboard.jsx` or `src/screens/ProjectDetail.jsx` — use stored URL
- `src/portalApi.js` — ensure `$select` includes `dcfg_sharepoint_site_url` in project fetches

---

### Item 4: Active/Closed Default Filtering on List Screens

**Problem:** List screens show all records including completed/closed jobs. As transaction volume grows, completed records crowd out active work.

**Solution:** Default all list screens to show active records only. Add a "Show completed" toggle that is off by default and not sticky across sessions.

**Pattern:**
- Default filter: exclude records where status = completed/closed/void/cancelled/expired
- Toggle: small unobtrusive control at end of header bar or filter row
- Visual treatment: when revealed, completed records are visually muted (lower opacity or grey badge)
- Not sticky: every page load starts with active-only

**Screens affected:**

| Screen | Component | Active statuses | Closed statuses |
|--------|-----------|----------------|-----------------|
| Bid Comparisons | `RfpList.jsx` | Draft, In Progress, Awarded | Completed, Cancelled, Void |
| Contracts | `ContractList.jsx` | Draft, Sent, Active | Closed, Void, Declined |
| MSAs | `MsaList.jsx` | Active, Pending | Expired, Terminated |
| Projects | `ProjectList.jsx` / `ProjectDashboard.jsx` | Active, In Progress | Completed, Cancelled |

**Screens NOT affected (already handled or different pattern):**
- SendQueue — has Send/Completion tabs
- Onboarding — already has active/deleted toggle
- Customers — no lifecycle status
- Locations — no lifecycle status

**Files to modify:**
- `src/screens/RfpList.jsx`
- `src/screens/ContractList.jsx`
- `src/screens/MsaList.jsx`
- `src/screens/ProjectList.jsx` and/or `src/screens/ProjectDashboard.jsx`

---

### Item 5: Bid Comp Entry — Project-First Flow

**Problem:** The current New Bid Comparison wizard creates a freestanding bid comp record and optionally attaches projects. This is backwards. The correct flow: a project exists first, and a bid comparison is performed ON that project. Vendors are invited to bid, bids are compared, a winner is awarded, and contracts/WOs are created from the award.

**Correct pipeline:**
```
Project exists -> Bid Comparison performed on project -> Vendors invited to bid -> Bids compared -> Award -> Contract/WO created
```

**Solution:** Redesign the bid comp entry point:
1. User navigates to Bid Comparisons (or clicks "New Bid Comparison")
2. First screen: pick an active project (list with search, filtered to active-only per Item 4)
3. After project selection: bid comp details form (name auto-fills from project, scope, deadline)
4. Create -> bid comp record linked to the selected project
5. From the bid comp detail screen: invite vendors, record bids, compare, award

**Key changes from current wizard:**
- Step order inverts: Project selection is step 1, not step 2
- Project selection is required, not optional
- Name auto-populates from project name (editable)
- Trades derive from the project record
- Project list shows active only (ties to Item 4)

**Files to modify:**
- `src/screens/NewRfpWizard.jsx` — restructure steps: Project first -> Details -> Review
- `src/screens/RfpList.jsx` — no structural change, but filtering per Item 4

---

## Implementation Order

1. **Item 2** (remove button) — 2 minutes, zero risk
2. **Item 4** (active/closed filtering) — foundational, applies to Items 5 and others
3. **Item 5** (bid comp project-first) — depends on Item 4 for project picker filtering
4. **Item 1** (vendor slideout) — independent, largest single item
5. **Item 3** (SharePoint links) — schema + backfill + SPA, independent

## Out of Scope

- Vendor approval workflow (dcfg_vendor_status column)
- Geocoding backfill for vendor lat/lng
- Solution sync to Test/Stage
- Deploy (separate authorization)
