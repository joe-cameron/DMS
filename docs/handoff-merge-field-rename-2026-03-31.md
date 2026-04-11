# Handoff: Merge Field Rename + New Schema — Retire "Contractor", Add TPA Auto-Number

**Date:** 2026-03-31
**From:** Joseph Cameron (operator) via Claude
**To:** AI code agent (next session)
**Priority:** High — standardizes merge field names + adds TPA WO auto-numbering

---

## What Changed and Why

### The Problem
The DCFG document generation system had **duplicate merge field names** for the same data. The Word template content controls used lowercase names (`contract_contractor_legal_name`), while the flow's `Build_Token_Map` and seed scripts used UPPERCASE names (`CONTRACTOR_LEGAL_NAME`). Some fields had 2-3 different names pointing to the same Dataverse column.

The word "contractor" was used inconsistently — sometimes meaning the vendor, sometimes the signer. This created confusion when building templates and wiring the flow.

### The Decision
1. **All UPPERCASE tag names are retired.** Only lowercase remains.
2. **"Contractor" is retired as a tag prefix.** All vendor-related fields now use `vendor_` prefix.
3. **One canonical tag name per field** across WO, Amendment, and Vendor MSA templates.

### Why This Matters for Dataverse
The Dataverse columns (`dcfg_contractor_legal_name`, `dcfg_contractor_phone`, etc.) **do NOT change**. The column names in the database stay as they are. Only the **merge field tag names** (used in Word content controls and the flow's Build_Token_Map) are changing. The flow's mapping layer translates between tag names and Dataverse columns.

**Do NOT rename Dataverse columns.** Only rename:
- Word template content control Tag/Title values
- Flow `Build_Token_Map` keys
- `dcfg_template_field.dcfg_field_name` records
- Tag Builder HTML references
- Any seed scripts that reference the old names

---

## Rename Map

### Vendor Fields (changed)

| New Tag | Old Tag(s) | Dataverse Column (UNCHANGED) |
|---------|-----------|------------------------------|
| `vendor_legal_name` | `contract_contractor_legal_name`, `CONTRACTOR_LEGAL_NAME` | `dcfg_contract.dcfg_contractor_legal_name` |
| `vendor_name` | `contract_contractor_name`, `COMPANY` | `dcfg_contract.dcfg_company` |
| `vendor_signer_name` | `vendor_primary_contact`, `SIGNER_PRINTED` | `dcfg_contract.dcfg_signer_printed` |

### Fields Already Correct (no change needed)

| Tag | Dataverse Column |
|-----|-----------------|
| `vendor_address` | `dcfg_contract.dcfg_contractor_address` |
| `vendor_phone` | `dcfg_contract.dcfg_contractor_phone` |
| `vendor_email` | `dcfg_contract.dcfg_contractor_email` |
| `vendor_signer_title` | `dcfg_contract.dcfg_signer_title` |
| `vendor_payment_terms` | `dcfg_contract.dcfg_payment_process` |

### UPPERCASE Names Retired (map to existing lowercase)

| Retired | Canonical Lowercase |
|---------|-------------------|
| `CONTRACTOR_LEGAL_NAME` | `vendor_legal_name` |
| `COMPANY` | `vendor_name` |
| `CONTRACTOR_ADDRESS` | `vendor_address` |
| `CONTRACTOR_PHONE` | `vendor_phone` |
| `CONTRACTOR_EMAIL` | `vendor_email` |
| `SIGNER_PRINTED` | `vendor_signer_name` |
| `SIGNER_TITLE` | `vendor_signer_title` |
| `PAYMENT_PROCESS` | `vendor_payment_terms` |
| `OWNER_CONTACT` | `contract_owner_contact` |
| `OWNER_TITLE` | `contract_owner_title` |
| `OWNER_EMAIL` | `contract_owner_email` |
| `OWNER_STREET` | `contract_owner_street` |
| `OWNER_CITY` | `contract_owner_city` |
| `OWNER_STATE` | `contract_owner_state` |
| `CLIENT_NAME` | `contract_client_name` |
| `DECADES_SIGNATURE_IMAGE` | `decades_signature_image` |
| `AMENDMENT_NUMBER` | `contract_amendment_sequence` |
| `PARENT_CONTRACT_NUMBER` | `contract_po_number` |


> **Note:** MSA/Sales Proposal fields (CUSTOMER_NAME, CUSTOMER_SIGNER_NAME, VENDOR_LEGAL_NAME, MSA_DATE, LOCATION_COUNT, MEMBERSHIP_RATE, etc.) are **out of scope** for this rename. This handoff covers WO, Amendment, and Vendor MSA only. MSA proposal fields will be standardized separately.

---

## Files That Need Changes

### 1. Word Templates (content control Tag/Title values)
**Location:** SharePoint `DCFG_Templates` library
**Action:** Open each .docx in desktop Word → Developer → Properties → rename Tag and Title

Templates affected:
- `Bancroft_Blanket_Work_Order.docx` — rename 3 tags
- `Bancroft_Work_Order.docx` — rename 3 tags
- `Decades_Work_Order.docx` — rename 3 tags
- `Bancroft_Work_Order_Amendment.docx` — rename 3 tags
- `Bancroft_Blanket_Work_Order_Amendment.docx` — rename 3 tags
- `Decades_Work_Order_Amendment.docx` — rename 3 tags

Renames in each:
- `contract_contractor_legal_name` → `vendor_legal_name`
- `contract_contractor_name` → `vendor_name`
- `vendor_primary_contact` → `vendor_signer_name`

### 2. Power Automate Flow — `Build_Token_Map` Compose action
**Location:** `flow_docgen` in Test environment
**Action:** Update the Compose action's JSON keys to use new tag names

Change keys:
```json
"vendor_legal_name": "...",      // was contract_contractor_legal_name
"vendor_name": "...",            // was contract_contractor_name
"vendor_signer_name": "...",     // was vendor_primary_contact
```

The expressions (values) stay the same — they still read from `dcfg_contract.dcfg_contractor_legal_name` etc. Only the KEY names change.

### 3. `dcfg_template_field` Dataverse records
**Location:** Test environment, `dcfg_template_fields` entity set
**Action:** Update `dcfg_field_name` values for the 3 renamed fields

```
dcfg_field_name = 'CONTRACTOR_LEGAL_NAME' → 'vendor_legal_name'
dcfg_field_name = 'COMPANY' → 'vendor_name'
dcfg_field_name = 'SIGNER_PRINTED' → 'vendor_signer_name'
```

Also update all other UPPERCASE `dcfg_field_name` values to their lowercase canonical equivalents.

### 4. Tag Builder HTML
**Location:** `C:\DCFG\docs\tag_builder.html`
**Action:** Update the `T` array tag names for the 3 renamed fields across all template sections

### 5. Seed Script
**Location:** `C:\DCFG\DCFG_Seed_TemplateFields.ps1`
**Action:** Update `$workOrderFields` array entries for the 3 renamed fields. Retire all UPPERCASE `$msaBodyFields`, `$exhibitCFields` names to lowercase.

### 6. Template Specification
**Location:** `C:\DCFG\DCFG_Template_Specification_v1.1.md`
**Action:** Update merge field tables to use new canonical lowercase names. Note this is now v1.2.

### 7. Merge Field Registry
**Location:** `C:\DCFG\claude-sync\shared\DCFG_Merge_Field_Registry.md`
**Action:** Already updated with canonical names. Verify consistency after other changes.

---

## NEW: Schema Changes — TPA Auto-Numbering

### Why
TPA customers (e.g., Bancroft) have their own WO numbering format: `{PREFIX}{YY}{sequence}`. Bancroft uses `BWO` → `BWO261000`, `BWO261001`, etc. Each TPA customer has their own prefix initials. Non-TPA customers (Decades) get WO numbers assigned by Send Queue staff.

The `dcfg_contract.dcfg_contract_number` column exists but there's no mechanism to auto-generate TPA numbers. Two new columns are needed on `dcfg_customer`.

### New Dataverse Columns

| Column | Table | Type | Max Length | Description |
|--------|-------|------|-----------|-------------|
| `dcfg_wo_prefix` | `dcfg_customer` | String | 10 | TPA work order number prefix. "BWO" for Bancroft. Null/empty for non-TPA customers. |
| `dcfg_next_wo_sequence` | `dcfg_customer` | Integer | — | Next sequence number for auto-numbering. Incremented by flow on each new WO. Starts at 1000. |

### Auto-Number Logic (for flow_docgen)

```
IF customer.dcfg_wo_prefix is NOT empty (TPA customer):
  1. Read customer.dcfg_wo_prefix → e.g., "BWO"
  2. Read customer.dcfg_next_wo_sequence → e.g., 1003
  3. Get current 2-digit year → "26"
  4. contract_number = prefix + year + sequence → "BWO261003"
  5. Write contract_number to dcfg_contract.dcfg_contract_number
  6. Increment customer.dcfg_next_wo_sequence to 1004
ELSE (non-TPA):
  contract_number stays blank — assigned by Send Queue staff
```

### Seed Data

After creating the columns, set initial values:

| Customer | dcfg_wo_prefix | dcfg_next_wo_sequence | Notes |
|----------|---------------|----------------------|-------|
| Bancroft | `BWO` | `1000` | Starting sequence — adjust based on existing WOs |

### Missing Merge Field — Add to All Templates

`contract_number` was missing from the field list. It must be added:

| Tag | Dataverse Column | Used In | Required | Notes |
|-----|-----------------|---------|----------|-------|
| `contract_number` | `dcfg_contract.dcfg_contract_number` | WO, Amendment, Vendor MSA | No | Blank until assigned (TPA: auto, non-TPA: Send Queue staff) |

This is field **#34** in the unified list. Add it to the `Build_Token_Map` and all Word templates that display a WO number.

### New Column — Owner Phone

`contract_owner_phone` was in the tag builder but had no Dataverse column. **Decision: Create it.**

| Column | Table | Type | Max Length | Description |
|--------|-------|------|-----------|-------------|
| `dcfg_owner_phone` | `dcfg_contract` | String | 30 | Owner/property contact phone. Auto-fill from location at contract creation. |

Total new columns: **3** (`dcfg_wo_prefix`, `dcfg_next_wo_sequence`, `dcfg_owner_phone`)

---

## Complete Unified Field List (WO + Amendment + Vendor MSA)

**34 fields total.** 24 shared + 4 amendment-only + 6 Exhibit A lines.

### Shared — All Three Document Types (24)

| # | Tag | Dataverse Column | Req |
|---|-----|-----------------|-----|
| | **Vendor** | | |
| 1 | `vendor_legal_name` | `dcfg_contract.dcfg_contractor_legal_name` | Yes |
| 2 | `vendor_name` | `dcfg_contract.dcfg_company` | Yes |
| 3 | `vendor_address` | `dcfg_contract.dcfg_contractor_address` | Yes |
| 4 | `vendor_phone` | `dcfg_contract.dcfg_contractor_phone` | Yes |
| 5 | `vendor_email` | `dcfg_contract.dcfg_contractor_email` | Yes |
| 6 | `vendor_signer_name` | `dcfg_contract.dcfg_signer_printed` | Yes |
| 7 | `vendor_signer_title` | `dcfg_contract.dcfg_signer_title` | Yes |
| 8 | `vendor_payment_terms` | `dcfg_contract.dcfg_payment_process` | No |
| | **Owner / Location** | | |
| 9 | `contract_owner_contact` | `dcfg_contract.dcfg_owner_contact` | Yes |
| 10 | `contract_owner_title` | `dcfg_contract.dcfg_owner_title` | No |
| 11 | `contract_owner_email` | `dcfg_contract.dcfg_owner_email` | No |
| 12 | `contract_owner_street` | `dcfg_contract.dcfg_owner_street` | No |
| 13 | `contract_owner_city` | `dcfg_contract.dcfg_owner_city` | No |
| 14 | `contract_owner_state` | `dcfg_contract.dcfg_owner_state` | No |
| | **Contract** | | |
| 15 | `contract_client_name` | `dcfg_contract.dcfg_client_name` | Yes |
| 16 | `contract_number` | `dcfg_contract.dcfg_contract_number` | No |
| 17 | `contract_description_of_work` | `dcfg_contract.dcfg_description` | No |
| 18 | `contract_start_date` | `dcfg_contract.dcfg_start_date` | No |
| 19 | `contract_end_date` | `dcfg_contract.dcfg_end_date` | No |
| 20 | `contract_fee` | `dcfg_contract.dcfg_fee` | No |
| 21 | `contract_type` | `dcfg_contract.dcfg_contract_type` | No |
| 22 | `property_name` | `dcfg_property.dcfg_name` | No |
| 23 | `decades_signature_image` | SharePoint static asset | Yes |
| 24 | `contract_date` | `dcfg_contract.dcfg_contract_date` | No |

### Amendment-Only (+4)

| # | Tag | Dataverse Column | Req |
|---|-----|-----------------|-----|
| 25 | `contract_amendment_sequence` | `dcfg_contract.dcfg_amendment_number` | Yes |
| 26 | `contract_po_number` | `parent.dcfg_contract_number` | Yes |
| 27 | `contract_description_of_service` | `dcfg_contract.dcfg_description_of_service` | No |
| 28 | `contract_work_category` | `dcfg_contract.dcfg_work_category` | No |

### Exhibit A Lines — WO + Amendment only (+6)

| # | Tag | Dataverse Column |
|---|-----|-----------------|
| 29 | `item_number` | `dcfg_contract_line.dcfg_item_number` |
| 30 | `cost_code` | `dcfg_ap_cost_code.dcfg_name` |
| 31 | `description` | `dcfg_contract_line.dcfg_description` |
| 32 | `amount` | `dcfg_contract_line.dcfg_amount` |
| 33 | `customer_ap_code` | `dcfg_ap_cost_code.dcfg_customer_ap_code` |
| 34 | `total` | SUM(amount) — calculated by flow |

---

## What NOT to Change

- **Existing Dataverse column names** — `dcfg_contractor_legal_name`, `dcfg_company`, `dcfg_signer_printed` etc. stay as-is (only the NEW columns `dcfg_wo_prefix` and `dcfg_next_wo_sequence` are created)
- **SPA code** — `C:\DCFG\spa\` is READ-ONLY, do not touch
- **Dataverse table schemas** — no column renames
- **Production environment** — changes go to Test first, promote via solution transport

---

## Verification Steps

After making changes:
1. Open a renamed Word template → verify content controls show new tag names
2. Run flow_docgen against a test contract → verify document populates correctly
3. Check `dcfg_template_field` records show lowercase names
4. Open tag builder → verify new names display and copy correctly
5. Generate one of each: WO, Amendment, Vendor MSA → confirm all fields merge

---

## Reference
- Click-to-copy field reference: `C:\dcfg\clipboard.html`
- Full registry: `C:\DCFG\claude-sync\shared\DCFG_Merge_Field_Registry.md`
- Template spec: `C:\DCFG\DCFG_Template_Specification_v1.1.md`
- Tag builder: `C:\DCFG\docs\tag_builder.html`
- Seed script: `C:\DCFG\DCFG_Seed_TemplateFields.ps1`
