# Vendor Maintenance Screen — Design Spec

**Date:** 2026-05-06
**Location:** System Admin → Vendors tab (replaces existing VendorsTab in Admin.jsx)
**Status:** Draft

## Purpose

Full CRUD vendor management screen under System Admin. Allows administrators to add, edit, and maintain vendor records outside of the normal contracting workflow. Supports document uploads (MSA, W9, COI), tracks document status and insurance expiration, and surfaces compliance problems in the Send Queue.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Document model | Simple fields on `dcfg_vendor` | One slot per doc type. Upload replaces previous. No history table needed. |
| COI expiration alerts | Yes — shown in Send Queue | Staff sees vendor compliance problems before sending work orders. |
| Compliance gate | Soft — no block | Non-compliant vendors show warnings in Send Queue but are not blocked from assignment. |
| Compliance computation | Read-time, not stored | Calculated from presence of file URLs + expiration date vs today. No stale flag to maintain. |
| Replaces existing | Yes — replaces `VendorsTab` + `VendorForm` in Admin.jsx | New implementation carries forward all existing fields and adds document management. |
| Concurrency | Last-write-wins | Consistent with all other Admin tabs. Acceptable for admin-only screen. |

## Schema Changes

### New columns on `dcfg_vendor`

| Column | Type | Description |
|--------|------|-------------|
| `dcfg_msa_file_url` | String (2000) | SharePoint URL to uploaded MSA document |
| `dcfg_w9_file_url` | String (2000) | SharePoint URL to uploaded W9 document |
| `dcfg_msa_upload_date` | DateTime | When the MSA file was uploaded |
| `dcfg_w9_upload_date` | DateTime | When the W9 file was uploaded |
| `dcfg_coi_upload_date` | DateTime | When the current COI file was uploaded |
| `dcfg_insurance_effective_date` | DateTime | COI policy effective date (start of coverage) |

### Existing columns (no changes)

These columns already exist on `dcfg_vendor` and are used as-is:

**Insurance fields:**
- `dcfg_insurance_file_url` — SharePoint URL to COI document
- `dcfg_insurance_provider` — Insurance company name
- `dcfg_insurance_policy_number` — GL policy number
- `dcfg_insurance_expiration_date` — COI expiration date (primary compliance check)
- `dcfg_insurance_gl_expiration` — GL-specific expiration if different
- `dcfg_insurance_coverage_types` — Coverage types on the certificate

**MSA/signer fields:**
- `dcfg_msa_date` — Date the MSA was executed
- `dcfg_signer_name` — Who signed the MSA
- `dcfg_signer_title` — Signer's title
- `dcfg_signer_phone` — Signer's phone

**Profile fields:**
- `dcfg_legal_name` — Legal entity name
- `dcfg_display_name` — Display name
- `dcfg_address` — Street address
- `dcfg_address_line2` — Address line 2
- `dcfg_city` — City
- `dcfg_state` — State
- `dcfg_zip` — Zip
- `dcfg_primary_contact` — Primary contact name (NOTE: SPA uses `dcfg_primary_contact`, NOT `dcfg_contact_name`)
- `dcfg_email` — Email
- `dcfg_phone` — Phone
- `dcfg_trade` — Trade specialty
- `dcfg_active_flag` — Soft delete flag

**Financial/operational fields (carried forward from existing VendorForm):**
- `dcfg_payment_terms` — Payment terms text
- `dcfg_payment_process` — Payment process picklist
- `dcfg_net_terms` — Net terms (used by ContractComposer)
- `dcfg_notes` — Free-text notes (Memo field)

## Compliance Logic

A vendor is **compliant** when ALL of the following are true:
1. `dcfg_msa_file_url` is not null/empty
2. `dcfg_w9_file_url` is not null/empty
3. `dcfg_insurance_file_url` is not null/empty
4. `dcfg_insurance_expiration_date` is set AND > today

Compliance states (checked in this order):

| State | Condition | Badge | Sort Priority |
|-------|-----------|-------|---------------|
| **Inactive** | `dcfg_active_flag` = false | Gray "Inactive" | 0 |
| **Non-Compliant** | One or more documents missing | Red "Non-Compliant" | 1 |
| **COI Date Missing** | All 3 docs on file but expiration date is null | Yellow "COI Date Missing" | 2 |
| **COI Expired** | All 3 docs on file but COI expiration ≤ today | Red "COI Expired" | 3 |
| **COI Expiring Soon** | All 3 docs on file but COI expires within 30 days | Yellow "COI Expiring" | 4 |
| **Compliant** | All 3 docs on file + COI not expired | Green "Compliant" | 5 |

This logic is a pure function computed at render time — no stored compliance column.

```javascript
function getComplianceStatus(vendor) {
  if (!vendor.dcfg_active_flag) return { status: 'inactive', label: 'Inactive', color: 'gray', priority: 0 };

  const hasMsa = !!vendor.dcfg_msa_file_url;
  const hasW9 = !!vendor.dcfg_w9_file_url;
  const hasCoi = !!vendor.dcfg_insurance_file_url;

  if (!hasMsa || !hasW9 || !hasCoi) return { status: 'non-compliant', label: 'Non-Compliant', color: 'red', priority: 1 };

  const coiExp = vendor.dcfg_insurance_expiration_date ? new Date(vendor.dcfg_insurance_expiration_date) : null;
  if (!coiExp) return { status: 'missing-date', label: 'COI Date Missing', color: 'yellow', priority: 2 };

  const today = new Date();
  if (coiExp <= today) return { status: 'coi-expired', label: 'COI Expired', color: 'red', priority: 3 };

  const in30 = new Date();
  in30.setDate(in30.getDate() + 30);
  if (coiExp <= in30) return { status: 'coi-expiring', label: 'COI Expiring', color: 'yellow', priority: 4 };

  return { status: 'compliant', label: 'Compliant', color: 'green', priority: 5 };
}
```

## SPA Screen: Vendor Maintenance

### Location

System Admin screen (`/#/admin`), replaces the existing "Vendors" tab. Existing tabs remain: Templates, Onboarding Steps, Cost Codes, Vendors, Benchmarks.

### List View

**Layout:** Inline table within the Admin tab (matching existing Admin tab pattern — inline state management, not `useTableControls`).

**Toolbar:**
- Search input (searches `dcfg_legal_name`, `dcfg_display_name`, `dcfg_trade`, `dcfg_primary_contact`)
- Status filter dropdown: All / Compliant / Non-Compliant / Expiring Soon
- "+ Add Vendor" button (admin only)

**Columns:**

| Column | Source | Sortable |
|--------|--------|----------|
| Vendor Name | `dcfg_display_name` (fallback `dcfg_legal_name`) | Yes |
| Trade | `dcfg_trade` | Yes |
| MSA | ✓/✗ icon from `dcfg_msa_file_url` | No |
| W9 | ✓/✗ icon from `dcfg_w9_file_url` | No |
| COI | ✓/✗/! icon from `dcfg_insurance_file_url` + expiration | No |
| COI Expires | `dcfg_insurance_expiration_date` formatted | Yes |
| Status | Computed compliance badge (sortable by priority) | Yes |
| Actions | Edit button | No |

**Default sort:** Vendor Name ascending.
**Default filter:** Active vendors only (inactive shown at bottom, dimmed).

**Empty states:**
- No vendors: "No vendors yet. Click + Add Vendor to get started."
- No filter match: "No vendors match the current filter."
- No search match: "No vendors match '{searchTerm}'."

**Data fetch:**
```javascript
apiGet(`/${EntitySets.vendors}?$select=dcfg_vendorid,dcfg_display_name,dcfg_legal_name,dcfg_trade,
  dcfg_primary_contact,dcfg_msa_file_url,dcfg_w9_file_url,dcfg_insurance_file_url,
  dcfg_insurance_expiration_date,dcfg_active_flag
  &$orderby=dcfg_display_name asc`)
```

### Detail / Edit Panel

Opens when clicking "Edit" or "+ Add Vendor". Inline panel below the list (same pattern as other Admin tabs).

**Two-column layout:**

**Left column — Vendor Profile:**
- Legal Name (text input, required)
- Display Name (text input)
- Trade (text input)
- Phone (text input)
- Address, Address Line 2 (text inputs)
- City, State, Zip (3-column row)
- Primary Contact, Email (2-column row)
- Signer Name, Signer Title, Signer Phone (3-column row)
- MSA Date (date input)
- Payment Terms, Net Terms (2-column row)
- Payment Process (picklist dropdown)
- Notes (textarea)

**Right column — Documents:**

Compliance bar at top showing status of each document (✓/✗ icons + overall badge).

Three document cards, one per type:

**MSA Card:**
- Status badge (On File / Missing)
- Upload date + MSA date if present
- "View File" link (opens SharePoint URL in new tab; hidden when no file)
- "Upload" / "Replace" button (file picker, accepts .pdf)

**W9 Card:**
- Status badge (On File / Missing)
- Upload date if present
- "View File" link (hidden when no file)
- "Upload" / "Replace" button (file picker, accepts .pdf)

**COI Card:**
- Status badge (Active / Expired / Date Missing / Missing)
- Upload date, expiration date, provider, policy number
- "View File" link (hidden when no file)
- "Upload New COI" button (file picker, accepts .pdf)
- When uploading new COI, reveal inline fields:
  - Insurance Provider (text)
  - Policy Number (text)
  - Effective Date (date)
  - Expiration Date (date, required for compliance)

**Footer:**
- Cancel button (discards changes)
- Deactivate/Reactivate toggle (sets `dcfg_active_flag`)
- Save Vendor button

Save writes all changed fields in a single PATCH. New vendors use POST.

**Detail fetch** (separate from list — includes Memo and all fields):
```javascript
apiGet(`/${EntitySets.vendors}(${id})?$select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name,
  dcfg_trade,dcfg_phone,dcfg_email,dcfg_address,dcfg_address_line2,dcfg_city,dcfg_state,dcfg_zip,
  dcfg_primary_contact,dcfg_signer_name,dcfg_signer_title,dcfg_signer_phone,
  dcfg_msa_date,dcfg_msa_file_url,dcfg_msa_upload_date,
  dcfg_w9_file_url,dcfg_w9_upload_date,
  dcfg_insurance_file_url,dcfg_insurance_provider,dcfg_insurance_policy_number,
  dcfg_insurance_expiration_date,dcfg_insurance_effective_date,dcfg_insurance_gl_expiration,
  dcfg_insurance_coverage_types,dcfg_coi_upload_date,
  dcfg_payment_terms,dcfg_payment_process,dcfg_net_terms,dcfg_notes,dcfg_active_flag`)
```

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Save (PATCH/POST) fails | Toast error with message. Form stays open, dirty state preserved. User can retry. |
| File upload fails | Toast error. File picker resets. Vendor record not modified. |
| Upload succeeds, PATCH fails | Toast error showing "File uploaded but record update failed." SharePoint URL displayed so admin can retry save. |
| File too large | Reject client-side if > 15MB (Azure Function base64 limit). Toast: "File exceeds 15MB limit." |

### File Upload Flow

1. User clicks Upload on a document card
2. Browser file picker opens (accept `.pdf`)
3. File is uploaded to SharePoint via the Azure Function endpoint (`/api/sharepoint-upload`)
4. The function currently targets `DCFG_Outputs` library only. **Prerequisite:** Extend the function to accept a `library` parameter (e.g., `"library": "DCFG_Attachments"`) and a `folder_path` parameter.
5. Destination: `DCFG_Attachments/Vendors/{SafeVendorName}/{DocType}.pdf`
   - `SafeVendorName` = display name with special characters (`&`, `/`, `'`, `"`) replaced by `-`, max 50 chars
   - DocType = `MSA`, `W9`, or `COI`
   - Overwrites existing file at that path
6. On success, the returned SharePoint URL is written to the vendor record
7. Upload date field is set to now
8. For COI uploads, the insurance detail fields are also saved

**Fallback:** If the Azure Function endpoint is not yet extended, use `createDocumentRequest()` — write a document request row with type `vendor-upload`, let a flow handle the SharePoint upload, poll for completion.

## Send Queue Integration

### What Changes

The Send Queue (`screens/SendQueue.jsx`) currently shows document requests pending send. When rendering each row, the screen checks the assigned vendor's compliance status.

### Data Path

The Send Queue fetches document requests which join to MSAs and contracts. The vendor is resolved via the MSA relationship:

```
dcfg_msa_id → _dcfg_vendor_id_value → vendor compliance fields
```

For each unique vendor ID found in the queue, a single batch query fetches compliance fields:

```javascript
apiGet(`/${EntitySets.vendors}?$filter=dcfg_vendorid eq ${id1} or dcfg_vendorid eq ${id2}...
  &$select=dcfg_vendorid,dcfg_msa_file_url,dcfg_w9_file_url,dcfg_insurance_file_url,dcfg_insurance_expiration_date`)
```

Results are cached in a `Map<vendorId, complianceStatus>` for the render pass.

### Display

Inline badge on each Send Queue row where vendor is identifiable:

| Condition | Display |
|-----------|---------|
| Vendor compliant | No badge (clean row) |
| COI expires within 30 days | Yellow badge: "Vendor COI Expiring {date}" |
| COI expired | Red badge: "Vendor COI Expired" |
| Missing MSA, W9, or COI | Red badge: "Vendor Non-Compliant" |
| Vendor not resolvable | No badge (graceful skip) |

The badge is informational only — staff can still proceed with sending.

## File Storage Structure

```
DCFG_Attachments/
  Vendors/
    {SafeVendorName}/
      MSA.pdf
      W9.pdf
      COI.pdf
```

**Site:** `https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite`
**Library:** `DCFG_Attachments`

This is an intentional extension of the DMS pattern. The existing `DCFG_Attachments` hierarchy is `Customer/Location/Year` for property documents. Vendor documents are not customer-scoped, so they live under a top-level `Vendors/` segment. Human-readable folder names, flat document structure within each vendor folder.

## Web API Site Setting Update

The `Webapi/dcfg_vendor/fields` site setting uses an explicit field list. The 6 new columns must be appended:

```
dcfg_msa_file_url,dcfg_w9_file_url,dcfg_msa_upload_date,dcfg_w9_upload_date,dcfg_coi_upload_date,dcfg_insurance_effective_date
```

These are appended to the existing comma-separated value. After update, clear portal cache.

## Test IDs

All interactive elements will have `data-testid` attributes:

| Element | Test ID |
|---------|---------|
| Vendor list table | `vendor-maint-table` |
| Search input | `vendor-maint-search` |
| Status filter | `vendor-maint-filter` |
| Add vendor button | `vendor-maint-add` |
| Edit button per row | `vendor-maint-edit-{id}` |
| Detail panel | `vendor-maint-detail` |
| Save button | `vendor-maint-save` |
| Cancel button | `vendor-maint-cancel` |
| Deactivate button | `vendor-maint-deactivate` |
| MSA upload button | `vendor-maint-upload-msa` |
| W9 upload button | `vendor-maint-upload-w9` |
| COI upload button | `vendor-maint-upload-coi` |
| MSA view link | `vendor-maint-view-msa` |
| W9 view link | `vendor-maint-view-w9` |
| COI view link | `vendor-maint-view-coi` |
| Compliance badge (list) | `vendor-maint-compliance-{id}` |
| Send Queue vendor badge | `sendqueue-vendor-status-{id}` |

## Prerequisites

1. **Schema:** 6 new columns on `dcfg_vendor` (created via Dataverse Web API, added to DCFGSystemTest solution)
2. **Web API config:** Append 6 new column names to `Webapi/dcfg_vendor/fields` site setting + clear cache
3. **Table permissions:** Verify `dcfg_vendor` has read+write for Authenticated Users role
4. **Azure Function:** Extend `/api/sharepoint-upload` to accept `library` and `folder_path` parameters (currently hardcoded to `DCFG_Outputs`)
5. **SharePoint folder:** Create `DCFG_Attachments/Vendors/` folder in the DCFGContractingSuite site

## Out of Scope

- Document version history (use simple replace model)
- Automated COI collection from vendors (manual upload only)
- OCR/auto-extraction of COI data from uploaded PDFs (manual field entry)
- Vendor approval workflow (all vendors are immediately usable)
- Bulk vendor import (handled separately via the staged data from the SharePoint MSA extraction)
- `dcfg_contact_name` field (legacy — SPA uses `dcfg_primary_contact` exclusively)
