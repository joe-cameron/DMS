# Plan: DocGen Field Alignment — Contract Record as Source of Truth

**Date:** 2026-05-15
**Branch:** `code-review-2026-04-09`
**Handoff:** `docs/handoff-session-2026-05-15.md`

## Problem

Template field mappings resolve from vendor/MSA/customer **lookups** via `$expand`, but:
1. Lookups are often null on real contracts (vendor, MSA, property not linked)
2. Even when linked, users can **override** field values in the composer
3. Overrides are saved to **flat fields** on the contract record — the lookup still points to the original value
4. The generated document must match what the user approved, not the lookup source

**Result:** Documents have blank fields where data exists on the contract record, and overrides are ignored when lookups are used.

## Principle

> The contract record (`dcfg_contract`) flat fields are the **source of truth** for the generated document. Template field resolution MUST use flat contract fields, NEVER lookup expands. Lookups are for initial population only.

> If the contract record does not hold a field the user overrode, only the document has that data — it cannot be audited, re-generated, or compared.

## Audit Results

### A. Template mappings pointing to lookups — flat field already exists (9 fields)

These template field paths use `$expand` but the composer already saves the value to a flat field. Fix = remap the `dcfg_template_fields` rows in Dataverse.

| Current Path (lookup) | Correct Path (flat) | Template Placeholder |
|---|---|---|
| `dcfg_vendor.dcfg_legal_name` | `dcfg_contractor_legal_name` | Vendor Name / Legal Name |
| `dcfg_vendor.dcfg_phone` | `dcfg_contractor_phone` | Vendor Phone |
| `dcfg_vendor.dcfg_email` | `dcfg_contractor_email` | Vendor Email |
| `dcfg_vendor.dcfg_address` | `dcfg_contractor_address` | Vendor Street Address |
| `dcfg_vendor.dcfg_primary_contact` | `dcfg_customer_site_contact` | Vendor Contact |
| `dcfg_vendor.dcfg_signer_name` | `dcfg_signer_printed` | Contractor Printed Name |
| `dcfg_vendor.dcfg_signer_title` | `dcfg_signer_title` | Contractor Title |
| `dcfg_vendor_contact.fullname` | `dcfg_signer_printed` | Contact Name |
| `dcfg_vendor_contact.jobtitle` | `dcfg_signer_title` | Contractor Title |

**Note:** `dcfg_customer.dcfg_name` → `dcfg_client_name` is also a remap candidate, but customer billing address fields have no flat equivalent (see Section B).

### B. Schema gaps — no flat field on contract record (7 new columns needed)

These fields appear in templates but have no flat column on `dcfg_contract`. If the user overrides them, the override is lost.

| Field | New Column | Type | Populated From |
|---|---|---|---|
| MSA Number | `dcfg_msa_number` | Text (200) | Vendor MSA slot matching contract's customer |
| MSA Date | `dcfg_msa_date` | DateTime | Vendor MSA slot matching contract's customer |
| Customer Billing Street | `dcfg_billing_address` | Text (400) | `dcfg_customer.dcfg_billing_address` |
| Customer Billing City | `dcfg_billing_city` | Text (100) | `dcfg_customer.dcfg_billing_city` |
| Customer Billing State | `dcfg_billing_state` | Text (10) | `dcfg_customer.dcfg_billing_state` |
| Customer Billing Zip | `dcfg_billing_zip` | Text (20) | `dcfg_customer.dcfg_billing_zip` |
| Customer Name (flat) | `dcfg_client_name` already exists | — | Already saved by composer |

After creation: remap `dcfg_customer.dcfg_billing_*` and `dcfg_msa.*` template paths to the new flat columns.

### C. Composer gaps — field not saved on draft/generate (2 fields)

These fields exist on the contract table but the composer's `buildMutableFields` doesn't include them.

| Field | Column | Fix |
|---|---|---|
| Work Hours / Schedule | `dcfg_work_hours` | Add to `buildMutableFields` |
| Service Location Description | `dcfg_service_location_description` | Add to `buildMutableFields` |

### D. Vendor MSA tracking (20 new columns on `dcfg_vendor`)

A vendor can have up to 5 MSAs with different customers. Each slot tracks the MSA for one customer relationship.

| Slot | Number | Date | Customer | Status |
|---|---|---|---|---|
| 1 | `dcfg_msa_number_1` (Text) | `dcfg_msa_date_1` (DateTime) | `dcfg_msa_customer_1` (Lookup → dcfg_customer) | `dcfg_msa_status_1` (Choice) |
| 2 | `dcfg_msa_number_2` | `dcfg_msa_date_2` | `dcfg_msa_customer_2` | `dcfg_msa_status_2` |
| 3 | `dcfg_msa_number_3` | `dcfg_msa_date_3` | `dcfg_msa_customer_3` | `dcfg_msa_status_3` |
| 4 | `dcfg_msa_number_4` | `dcfg_msa_date_4` | `dcfg_msa_customer_4` | `dcfg_msa_status_4` |
| 5 | `dcfg_msa_number_5` | `dcfg_msa_date_5` | `dcfg_msa_customer_5` | `dcfg_msa_status_5` |

**Status choice values:** Draft (100000000), Sent (100000001), Signed (100000002), Expired (100000003)

**Lifecycle:**
- Creating a VA in the composer → writes to the next open MSA slot on the vendor
- DocuSign poll (`docusignPoll.js`) collects completed envelope → updates status to Signed
- WO/Amendment composer → reads vendor's MSA slot matching the contract's customer → pre-populates `dcfg_msa_number` and `dcfg_msa_date` on the contract (user can override)

### E. Address formatting

`dcfg_contractor_address` on existing contracts contains embedded commas between state and zip (e.g., `NJ,07091`). This is source data quality — the composer should validate/format on input. Not a docgen issue.

**Fix:** Add formatting in the composer when populating `dcfg_contractor_address` from vendor fields: `{street}, {city} {state} {zip}` (space between state and zip, no comma).

---

## Execution Plan

### Phase 1 — Remap existing template fields (no schema changes, no code changes)

Update `dcfg_template_fields` rows in Dataverse to point to flat contract fields instead of lookup paths. 9 path remaps. Safe to do immediately — the flat fields are already populated by the composer.

**Verification:** Re-run the field validation audit. All 9 remapped fields should show OK.

### Phase 2 — Add flat columns to `dcfg_contract` (schema + composer + remap)

1. Create 6 new columns on `dcfg_contract` in Prod: `dcfg_msa_number`, `dcfg_msa_date`, `dcfg_billing_address`, `dcfg_billing_city`, `dcfg_billing_state`, `dcfg_billing_zip`
2. Add to `Webapi/dcfg_contract/fields` site setting
3. Update `buildMutableFields` in `ContractComposer.jsx` to populate all 6 from customer/MSA sources + add `dcfg_work_hours` and `dcfg_service_location_description`
4. Remap template fields: `dcfg_msa.createdon` → `dcfg_msa_date`, `dcfg_msa.dcfg_name` → `dcfg_msa_number`, `dcfg_customer.dcfg_billing_*` → flat `dcfg_billing_*`
5. Build + deploy SPA

**Verification:** Create a test contract, verify all fields save to the record, generate document, confirm all placeholders filled.

### Phase 3 — Vendor MSA tracking (schema + composer + DocuSign wiring)

1. Create 20 new columns on `dcfg_vendor` (5 slots × 4 fields)
2. Add to `Webapi/dcfg_vendor/fields` site setting
3. Wire VA composer: on generate/send, write MSA number + date + customer to the next open vendor slot
4. Wire `docusignPoll.js`: on envelope completion for a VA, update the vendor's MSA status to Signed
5. Wire WO/Amendment composer: on vendor selection, look up the vendor's MSA slot matching the contract's customer → pre-populate `dcfg_msa_number` and `dcfg_msa_date` on the contract
6. Build + deploy SPA + deploy Azure Function

**Verification:** Create VA → send via DocuSign → poll picks up completion → vendor record updated → create WO for same vendor/customer → MSA fields auto-populated.

### Phase 4 — Address formatting

1. Update composer: when building `dcfg_contractor_address` from vendor parts, format as `{street}, {city} {state} {zip}` (no comma between state and zip)
2. Optional: backfill existing records with corrected formatting

---

## Files Impacted

| File | Phase | Change |
|------|-------|--------|
| Dataverse `dcfg_template_fields` | 1, 2 | Remap 9+ paths to flat fields |
| Dataverse `dcfg_contract` schema | 2 | 6 new columns |
| Dataverse `dcfg_vendor` schema | 3 | 20 new columns |
| Site setting `Webapi/dcfg_contract/fields` | 2 | Add new columns |
| Site setting `Webapi/dcfg_vendor/fields` | 3 | Add new columns |
| `spa/dcfg-shell/src/ContractComposer.jsx` | 2, 3, 4 | buildMutableFields + MSA slot logic + address format |
| `spa/dcfg-shell/src/lib/contractDocGen.js` | 3 | MSA resolution from vendor slot |
| `azure-functions/.../docusignPoll.js` | 3 | Update vendor MSA status on completion |

## Risk

- **Phase 1 is zero-risk** — remapping existing paths to existing flat fields, no schema or code changes
- **Phase 2 is low-risk** — new columns are additive, composer changes are in `buildMutableFields` only
- **Phase 3 is medium-risk** — touches vendor schema, composer vendor selection flow, DocuSign poll, and docgen resolution. Should be tested on Stage before Prod.
- **Phase 4 is low-risk** — input formatting only
