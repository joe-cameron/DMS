# Customer Config — Admin Tab + Blanket WO + AP Mappings + Template Overrides

**Date:** 2026-03-30
**Status:** Design
**Scope:** Admin screen, Send Queue, Contract Wizard (AP resolution), Dataverse schema

---

## Problem

Customer-specific configuration is either missing or scattered:
- **Blanket Work Orders**: TPA customers (e.g., Bancroft) have dollar thresholds below which contracts use a static blanket job number instead of requiring a manually-assigned WO number. This concept doesn't exist in the system.
- **AP Code Mappings**: Currently one global AP code per cost code (`dcfg_customer_ap_code` on `dcfg_ap_cost_code`). Different customers need different AP codes for the same cost code.
- **Custom Templates**: TPA customers can have customer-specific document templates. The `dcfg_is_tpa` and `dcfg_has_custom_templates` flags exist on `dcfg_customer`, and `resolveTemplateId()` already falls back from TPA to Decades templates — but there's no Admin UI to manage customer-template associations, and templates lack a customer lookup.

All of this configuration is security-sensitive and belongs behind Admin access control.

---

## Design

### Approach: C (Hybrid — minimal new tables, leverage existing structures)

- **Blanket WO**: New dedicated table (`dcfg_blanket_workorder`)
- **AP Mappings**: New junction table (`dcfg_customer_ap_mapping`)
- **Templates**: Add `dcfg_customer_id` lookup to existing `dcfg_document_template` table
- **Contract**: Add `dcfg_blanket_number` field (distinct from `dcfg_contract_number`)

---

## Schema

### New Table: `dcfg_blanket_workorder`

| Column | Type | Required | Purpose |
|--------|------|----------|---------|
| `dcfg_blanket_workorderid` | PK (GUID) | Auto | Primary key |
| `dcfg_customer_id` | Lookup → dcfg_customer | Yes | One active blanket per customer |
| `dcfg_dollar_threshold` | Currency | Yes | Contract total below this uses blanket (e.g., 2500.00) |
| `dcfg_job_number` | Text (50) | Yes | Static blanket job number |
| `dcfg_effective_year` | Whole Number | Yes | e.g., 2026 |
| `dcfg_active_flag` | Boolean | Yes | Default true. Old years deactivated, not deleted. |
| `dcfg_name` | Text (200) | Yes | Auto-generated: "{Customer} {Year} Blanket" |

**Constraint:** One active record per customer (enforced in UI, not schema). If Send Queue finds multiple active blankets for a customer, use the one with the most recent `dcfg_effective_year`. Prior years remain as inactive audit trail.

**Edge case — annual transition:** If no current-year blanket exists (e.g., admin hasn't created 2027 yet), the customer is treated as having no blanket. All contracts require manual WO assignment until the new year's record is created.

**Entity set name:** `dcfg_blanket_workorders`

### New Table: `dcfg_customer_ap_mapping`

| Column | Type | Required | Purpose |
|--------|------|----------|---------|
| `dcfg_customer_ap_mappingid` | PK (GUID) | Auto | Primary key |
| `dcfg_customer_id` | Lookup → dcfg_customer | Yes | |
| `dcfg_cost_code_id` | Lookup → dcfg_ap_cost_code | Yes | |
| `dcfg_ap_code` | Text (50) | Yes | Customer-specific AP code for this cost code |
| `dcfg_active_flag` | Boolean | Yes | Default true |
| `dcfg_name` | Text (200) | Yes | Auto-generated: "{Customer} - {Cost Code}" |

**Constraint:** Customer + cost code combination should be unique (enforced in UI). If duplicates exist, use the first active record.

**Entity set name:** `dcfg_customer_ap_mappings`

### Modified Table: `dcfg_document_template`

| Change | Detail |
|--------|--------|
| Add column | `dcfg_customer_id` — Lookup → dcfg_customer, nullable |

- `dcfg_customer_id = null` → global template (current behavior)
- `dcfg_customer_id = {guid}` → customer-specific override

### Modified Table: `dcfg_contract`

| Change | Detail |
|--------|--------|
| Add column | `dcfg_blanket_number` — Text (50), nullable |

- Distinct from `dcfg_contract_number` (real WO number)
- A contract has one or the other, never both
- Populated by Send Queue when blanket applies

---

## UI: Admin Tab — "Customer Config"

Added to the existing Admin screen as a new tab in the TABS array.

### Layout

1. **Customer selector** — search/dropdown, filters to active customers
2. Once selected, three collapsible sections:

### Section A: Blanket Work Order

- **No record exists:** "No blanket work order configured" message + "Add Blanket" button
- **Record exists:** Editable card:
  - Dollar Threshold (currency input)
  - Job Number (text input)
  - Effective Year (number input)
  - Active toggle
  - Save / Cancel buttons
- **History:** Collapsed list of prior year records (read-only) for audit trail
- **New year:** Admin creates a new record; old one is deactivated (not deleted)

### Section B: AP Code Mappings

- **Table columns:** Cost Code | Description | Global AP Code (read-only) | Customer AP Code (editable)
- Global AP code shown from `dcfg_ap_cost_code.dcfg_customer_ap_code` for reference
- Only rows with customer-specific overrides are saved to `dcfg_customer_ap_mapping`
- **Add Mapping:** Pick a cost code, enter customer AP code
- **Deactivate:** Sets `dcfg_active_flag` to false (falls back to global)

### Section C: Custom Templates

- **Table columns:** Document Type | Exhibit Type | Template Name | Version
- Shows templates where `dcfg_customer_id` matches selected customer
- **Assign Template:** Links an existing template to this customer (sets `dcfg_customer_id` lookup)
- **Remove:** Clears the customer lookup (template reverts to global pool)
- **Reference:** Global templates shown below in muted/collapsed section

---

## UI: Send Queue — Blanket-Aware WO Assignment

### Current Behavior
"Needs Work Order Number" tab shows all WIP contracts with `dcfg_contract_number eq null`. Staff manually enters WO number for every contract.

### New Behavior

On load, Send Queue:
1. Fetches active blanket records: `dcfg_blanket_workorders?$filter=dcfg_active_flag eq true`
2. WIP contracts query adds `dcfg_contract_fee` to `$select` (needed for threshold comparison)
3. WIP table adds a **Contract Amount** column so staff can see why a contract qualifies for blanket vs manual

**Threshold comparison:** `dcfg_contract_fee` is the contract total. Strictly less than threshold = blanket. Equal to or greater than threshold = manual WO.

For each contract in the "Needs Work Order Number" tab:

| Condition | Display | Action |
|-----------|---------|--------|
| Has blanket + total **under** threshold | Blanket job number shown read-only with "Blanket" badge | One-click "Apply Blanket" button → writes `dcfg_blanket_number` |
| Has blanket + total **at or over** threshold | Normal manual WO number input | Staff enters WO number → writes `dcfg_contract_number` (existing flow) |
| No blanket record | Normal manual WO number input | Existing behavior |

### Filter Change

Current: `dcfg_status eq 100000007 and dcfg_contract_number eq null and dcfg_active_flag eq true`

New: `dcfg_status eq 100000007 and dcfg_contract_number eq null and dcfg_blanket_number eq null and dcfg_active_flag eq true`

Contracts disappear from the tab after either WO number or blanket number is assigned.

---

## Logic: AP Code Resolution in Contract Wizard

### Current Behavior
When user selects a cost code on Exhibit A (Step 4), AP code auto-fills from `dcfg_ap_cost_code.dcfg_customer_ap_code`.

### New Resolution Order
1. Check `dcfg_customer_ap_mapping` for this customer + cost code → use customer-specific AP code
2. If no mapping → fall back to global `dcfg_customer_ap_code` on the cost code record

### Implementation
- When customer is known (Step 1), fetch customer AP mappings: `dcfg_customer_ap_mappings?$filter=_dcfg_customer_id_value eq {customerId} and dcfg_active_flag eq true`
- Store in wizard state as a map: `{ costCodeId → apCode }`
- On cost code selection, check map first, then fall back to global

---

## Logic: Template Resolution in `resolveTemplateId()`

### Current Behavior
Resolves by `dcfg_contract_family` + `dcfg_document_type`. TPA customers use their family, with Decades fallback.

### New Resolution Order
1. Customer-specific template: `dcfg_customer_id eq {customerId} AND dcfg_document_type eq {docType} AND dcfg_is_active eq true`
2. Family-specific global template: `dcfg_customer_id eq null AND dcfg_contract_family eq {family} AND dcfg_document_type eq {docType} AND dcfg_is_active eq true`
3. Decades fallback: `dcfg_customer_id eq null AND dcfg_contract_family eq Decades AND dcfg_document_type eq {docType} AND dcfg_is_active eq true`

---

## Contract Wizard — No Other Changes

The wizard does not know about blankets. Blanket logic is entirely in the Send Queue at approval time. The only wizard change is AP code resolution (above).

---

## Site Settings (Web API Access)

New entity sets need Web API access via site settings:

| Setting | Value |
|---------|-------|
| `Webapi/dcfg_blanket_workorder/enabled` | true |
| `Webapi/dcfg_blanket_workorder/fields` | `dcfg_blanket_workorderid,dcfg_name,dcfg_dollar_threshold,dcfg_job_number,dcfg_effective_year,dcfg_active_flag,_dcfg_customer_id_value` |
| `Webapi/dcfg_customer_ap_mapping/enabled` | true |
| `Webapi/dcfg_customer_ap_mapping/fields` | `dcfg_customer_ap_mappingid,dcfg_name,dcfg_ap_code,dcfg_active_flag,_dcfg_customer_id_value,_dcfg_cost_code_id_value` |

Existing `Webapi/dcfg_document_template/fields` needs `dcfg_customer_id` added.
Existing `Webapi/dcfg_contract/fields` needs `dcfg_blanket_number` added.

---

## Table Permissions

**Admin web role:**
- `dcfg_blanket_workorder`: Read, Write, Create (soft delete via active_flag, no hard delete)
- `dcfg_customer_ap_mapping`: Read, Write, Create (soft delete via active_flag, no hard delete)
- `dcfg_document_template`: Add AppendTo for customer relationship

**Non-admin web roles (Send Queue staff, contract creators):**
- `dcfg_blanket_workorder`: Read (Send Queue needs to read blankets for threshold logic)
- `dcfg_customer_ap_mapping`: Read (Contract wizard needs to resolve customer AP codes)
- `dcfg_contract`: Write on `dcfg_blanket_number` (Send Queue staff apply blanket numbers)

---

## Files Modified

| File | Changes |
|------|---------|
| `portalApi.js` | New entity sets, fetch/create/update/delete functions for blanket WO and AP mappings. Customer AP mapping fetch. Updated `resolveTemplateId` to use customer lookup. |
| `Admin.jsx` | New "Customer Config" tab with customer selector + 3 sections |
| `SendQueue.jsx` | Fetch blanket records, blanket-aware WO assignment logic, updated filter |
| `NewContractWizard.jsx` | Fetch customer AP mappings, updated cost code → AP code resolution |

---

## Audit Logging

All CRUD operations on new tables write to `dcfg_audit_logs`, consistent with existing Admin tab pattern:
- Blanket WO: create, update, deactivate
- AP Mapping: create, update, deactivate
- Template assignment: assign to customer, remove from customer
- Send Queue: blanket number applied (already logged for WO assignment)

---

## Testing

- Admin: CRUD blanket WO records, AP mappings, template assignments
- Send Queue: Blanket auto-apply for under-threshold, manual for over-threshold, filter excludes assigned
- Wizard: AP code resolves customer-specific first, falls back to global
- Edge cases: No blanket record, expired blanket (inactive), customer with no AP overrides
