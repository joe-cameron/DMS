# DCFG Contracting Suite — Consolidated Schema Reference
**Purpose:** AI evaluation target. Compare this document against the live Dataverse environment at `org0c17e98d.crm.dynamics.com` to identify gaps, mismatches, and pending changes.
**Solution:** DCFGContractingSuite
**Prefix:** dcfg_
**Date:** 2026-03-12

---

## How to Use This Document

1. For each table below, query `EntityDefinitions(LogicalName='{table}')/Attributes?$select=LogicalName,AttributeType,RequiredLevel,DisplayName` and compare against the expected columns.
2. Flag columns marked `NEW` that do not yet exist in production — these are pending schema changes.
3. Flag columns that exist in production but are NOT listed here — they may be orphaned or undocumented.
4. Verify all picklist integer values match production.
5. Verify all relationships exist and point to the correct referenced table.

---

## Table Inventory (19 DCFG tables)

| # | Logical Name | Entity Set Name | Primary Key | Primary Name | Purpose |
|---|---|---|---|---|---|
| 1 | dcfg_customer | dcfg_customers | dcfg_customerid | dcfg_name | Customer accounts |
| 2 | dcfg_vendor | dcfg_vendors | dcfg_vendorid | dcfg_name | Vendor entities (Decades, Bancroft parent cos) |
| 3 | dcfg_msa | dcfg_msas | dcfg_msaid | dcfg_name | Master Subcontract Agreements |
| 4 | dcfg_msa_rate | dcfg_msa_rates | dcfg_msa_rateid | dcfg_name | Rate per location type per MSA |
| 5 | dcfg_contract | dcfg_contracts | dcfg_contractid | dcfg_name | Work order contracts |
| 6 | dcfg_contract_line | dcfg_contract_lines | dcfg_contract_lineid | dcfg_name | Exhibit A line items |
| 7 | dcfg_property | dcfg_propertys | dcfg_propertyid | dcfg_name | Locations (entity set is propertys NOT properties) |
| 8 | dcfg_property_detail | dcfg_property_details | dcfg_property_detailid | dcfg_name | Extended location attributes |
| 9 | dcfg_location_type | dcfg_location_types | dcfg_location_typeid | dcfg_name | Location type reference (GroupHome, School, etc.) |
| 10 | dcfg_location_document | dcfg_location_documents | dcfg_location_documentid | dcfg_name | Compliance documents per location |
| 11 | dcfg_ap_cost_code | dcfg_ap_cost_codes | dcfg_ap_cost_codeid | dcfg_name | AP cost codes + customer crosswalk |
| 12 | dcfg_program | dcfg_programs | dcfg_programid | dcfg_name | Budget programs (conditional on customer) |
| 13 | dcfg_onboarding_case | dcfg_onboarding_cases | dcfg_onboarding_caseid | dcfg_name | Onboarding case wrapper |
| 14 | dcfg_onboarding_checklist | dcfg_onboarding_checklists | dcfg_onboarding_checklistid | dcfg_name | 16-step checklist items |
| 15 | dcfg_document_template | dcfg_document_templates | dcfg_document_templateid | dcfg_name | Word template registry |
| 16 | dcfg_document_output | dcfg_document_outputs | dcfg_document_outputid | dcfg_name | Generated document records |
| 17 | dcfg_template_field | dcfg_template_fields | dcfg_template_fieldid | dcfg_name | Merge field definitions per template |
| 18 | dcfg_audit_log | dcfg_audit_logs | dcfg_audit_logid | dcfg_name | Immutable audit trail (CREATE only) |
| 19 | dcfg_send_queue | dcfg_send_queues | dcfg_send_queueid | dcfg_name | DocuSign send queue |

---

## Table Schemas

### 1. dcfg_customer

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_customerid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Primary name |
| dcfg_primary_contact_name | String(200) | No | Auto-fills MSA contact fields |
| dcfg_primary_contact_email | String(200) | No | |
| dcfg_president_name | String(200) | No | Customer signer for MSA |
| dcfg_president_title | String(200) | No | Customer signer title |
| dcfg_active_flag | Boolean | No | Default true. NOT dcfg_is_active. |
| dcfg_vendor_id | Lookup → dcfg_vendor | No | Resolves contract family |

**Relationships:**
- dcfg_customer → dcfg_vendor (N:1 via dcfg_vendor_id)

---

### 2. dcfg_vendor

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_vendorid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Display name |
| dcfg_legal_name | String(300) | No | Full legal name for documents. NOT dcfg_contractor_legal_name. |
| dcfg_address | String(500) | No | |
| dcfg_phone | String(50) | No | |
| dcfg_email | String(200) | No | |
| dcfg_signer_name | String(200) | No | Vendor signer for MSA |
| dcfg_signer_title | String(200) | No | |
| dcfg_contract_family | Choice | No | 100000000=Bancroft, 100000001=Decades |
| dcfg_active_flag | Boolean | No | Default true. NOT dcfg_is_active. |

---

### 3. dcfg_msa

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_msaid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Auto-gen: Customer + Package + Date |
| dcfg_msa_date | Date | No | MSA effective date |
| dcfg_status | Choice | No | See picklist below |
| dcfg_exhibit_type | Choice | No | **NEW (T-S2).** 100000000=PackageA, 100000001=PackageB, 100000002=PackageC. Null for auto-resolved customers (Bancroft). |
| dcfg_budget_total | Currency | No | |
| dcfg_budget_committed | Currency | No | **READ-ONLY in UI. Written by flow_commit only (JS-07).** |
| dcfg_active_flag | Boolean | No | |
| dcfg_customer_id | Lookup → dcfg_customer | Yes | |
| dcfg_vendor_id | Lookup → dcfg_vendor | Yes | |

**dcfg_msa.dcfg_status picklist (T-S3 — pending confirmation):**

| Label | Int |
|---|---|
| Draft | 100000000 |
| Proposal | 100000001 |
| Submitted | 100000002 |
| Approved | 100000003 |
| Sent | 100000004 |
| Active | 100000005 |
| Inactive | 100000006 |

> **Evaluate:** Confirm which status values currently exist. T-S3 may require expanding this picklist.

**Relationships:**
- dcfg_msa → dcfg_customer (N:1 via dcfg_customer_id)
- dcfg_msa → dcfg_vendor (N:1 via dcfg_vendor_id)

---

### 4. dcfg_msa_rate

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_msa_rateid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_membership_rate | Currency | No | Monthly rate per location type |
| dcfg_onboarding_rate | Currency | No | One-time onboarding fee per location |
| dcfg_msa_id | Lookup → dcfg_msa | Yes | |
| dcfg_location_type_id | Lookup → dcfg_location_type | No | Null for uniform pricing |

**Relationships:**
- dcfg_msa_rate → dcfg_msa (N:1 via dcfg_msa_id)
- dcfg_msa_rate → dcfg_location_type (N:1 via dcfg_location_type_id)

---

### 5. dcfg_contract

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_contractid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_contract_number | String(50) | No | System-assigned |
| dcfg_status | Choice | Yes | See picklist below |
| dcfg_contract_family | Choice | No | 100000000=Bancroft, 100000001=Decades |
| dcfg_contractor_legal_name | String(300) | No | Denormalized from vendor |
| dcfg_contractor_address | String(500) | No | Denormalized from vendor |
| dcfg_contractor_phone | String(50) | No | |
| dcfg_contractor_email | String(200) | No | |
| dcfg_company | String(200) | No | |
| dcfg_signer_printed | String(200) | No | |
| dcfg_signer_title | String(200) | No | |
| dcfg_payment_process | String(500) | No | |
| dcfg_owner_contact | String(200) | No | Denormalized from property |
| dcfg_owner_title | String(200) | No | |
| dcfg_owner_email | String(200) | No | |
| dcfg_owner_street | String(500) | No | |
| dcfg_owner_city | String(200) | No | |
| dcfg_owner_state | String(50) | No | |
| dcfg_client_name | String(200) | No | Location display name |
| dcfg_amendment_number | Integer | No | For amendments only |
| dcfg_budget_committed | Currency | No | **READ-ONLY. Written by flow_commit only.** |
| dcfg_msa_id | Lookup → dcfg_msa | No | |
| dcfg_property_id | Lookup → dcfg_property | No | |
| dcfg_parent_contract_id | Lookup → dcfg_contract | No | Self-referencing for amendments |
| dcfg_program_id | Lookup → dcfg_program | No | Conditional — only when customer has programs |

**dcfg_contract.dcfg_status picklist (confirmed):**

| Label | Int |
|---|---|
| Draft | 100000000 |
| Generated | 100000001 |
| Sent | 100000002 |
| Signed/Received | 100000003 |
| Closed | 100000004 |
| Void | 100000005 |
| Declined | 100000006 |

**Relationships:**
- dcfg_contract → dcfg_msa (N:1 via dcfg_msa_id)
- dcfg_contract → dcfg_property (N:1 via dcfg_property_id) — entity set is dcfg_propertys
- dcfg_contract → dcfg_contract (self N:1 via dcfg_parent_contract_id)
- dcfg_contract → dcfg_program (N:1 via dcfg_program_id)

---

### 6. dcfg_contract_line

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_contract_lineid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_item_number | Integer | No | Sort order for Exhibit A |
| dcfg_description | String(2000) | No | NOT dcfg_line_description |
| dcfg_amount | Currency | No | NOT dcfg_line_amount |
| dcfg_contract_id | Lookup → dcfg_contract | Yes | |
| dcfg_cost_code_id | Lookup → dcfg_ap_cost_code | No | |

**Relationships:**
- dcfg_contract_line → dcfg_contract (N:1 via dcfg_contract_id)
- dcfg_contract_line → dcfg_ap_cost_code (N:1 via dcfg_cost_code_id)

---

### 7. dcfg_property

**Entity set: dcfg_propertys (NOT dcfg_properties — JS-01)**

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_propertyid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Location display name |
| dcfg_address | String(500) | No | NOT dcfg_owner_street |
| dcfg_city | String(200) | No | NOT dcfg_owner_city |
| dcfg_state | String(50) | No | NOT dcfg_owner_state |
| dcfg_contact_person | String(200) | No | NOT dcfg_owner_contact |
| dcfg_contact_title | String(200) | No | NOT dcfg_owner_title |
| dcfg_contact_email | String(200) | No | NOT dcfg_owner_email |
| dcfg_active_flag | Boolean | No | NOT dcfg_is_active |
| dcfg_customer_id | Lookup → dcfg_customer | No | |
| dcfg_location_type_id | Lookup → dcfg_location_type | No | |

> **Column name corrections (UL-004):** The spec/BRD uses `dcfg_owner_*` names but the actual production columns are `dcfg_contact_*` and `dcfg_address`/`dcfg_city`/`dcfg_state`. The `dcfg_contract` table correctly stores copies as `dcfg_owner_*` — only the source table (`dcfg_property`) uses different names.

**Relationships:**
- dcfg_property → dcfg_customer (N:1 via dcfg_customer_id)
- dcfg_property → dcfg_location_type (N:1 via dcfg_location_type_id)

---

### 8. dcfg_property_detail

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_property_detailid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_property_id | Lookup → dcfg_property | No | |

> **Evaluate:** This table has 35+ columns per the UX skill. Query all attributes and document what exists. Not fully inventoried in current specs.

---

### 9. dcfg_location_type

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_location_typeid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | e.g. GroupHome, DayProgram, School, Admin |
| dcfg_description | String(500) | No | |

**Expected seed data:**

| dcfg_name | Notes |
|---|---|
| GroupHome | Standard billable |
| DayProgram | Standard billable |
| School | Standard billable |
| Admin | Always $0 / no-charge |

---

### 10. dcfg_location_document

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_location_documentid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_property_id | Lookup → dcfg_property | No | Entity set: dcfg_propertys |

> **Evaluate:** Full column inventory needed. Used for compliance document tracking.

---

### 11. dcfg_ap_cost_code

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_ap_cost_codeid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Cost code name |
| dcfg_customer_ap_code | String(100) | No | Customer's AP crosswalk code |

---

### 12. dcfg_program

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_programid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_budget_total | Currency | No | |
| dcfg_budget_committed | Currency | No | **READ-ONLY. Written by flow_commit only.** |
| dcfg_customer_id | Lookup → dcfg_customer | No | |

---

### 13. dcfg_onboarding_case

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_onboarding_caseid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_customer_id | Lookup → dcfg_customer | No | |
| dcfg_msa_id | Lookup → dcfg_msa | No | |

> **Evaluate:** Full column inventory needed.

---

### 14. dcfg_onboarding_checklist

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_onboarding_checklistid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Step title |
| dcfg_step_number | Integer | No | 1-16 |
| dcfg_onboarding_case_id | Lookup → dcfg_onboarding_case | No | |

> **Evaluate:** Full column inventory needed. Steps 9 and 16 trigger flow_send_email.

---

### 15. dcfg_document_template

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_document_templateid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | e.g. "Decades MSA Package A" |
| dcfg_contract_family | Choice | No | 100000000=Bancroft, 100000001=Decades |
| dcfg_document_type | Choice | No | 0=Contract, 1=Amendment, 2=MSA, 3=CoverSheet |
| dcfg_exhibit_type | Choice | No | **NEW (T-S1).** 100000000=PackageA, 100000001=PackageB, 100000002=PackageC. Null for non-MSA and single-template families. |
| dcfg_is_active | Boolean | No | |
| dcfg_sharepoint_url | String(500) | No | URL to template in DCFG_Templates library |

**dcfg_document_template.dcfg_document_type picklist:**

| Label | Int |
|---|---|
| Contract | 0 |
| Amendment | 1 |
| MSA | 2 |
| CoverSheet | 3 |

**dcfg_document_template.dcfg_exhibit_type picklist (NEW — T-S1):**

| Label | Int |
|---|---|
| PackageA | 100000000 |
| PackageB | 100000001 |
| PackageC | 100000002 |

**Expected seed data (9 records — after Word files exist):**

| dcfg_name | family | document_type | exhibit_type | is_active |
|---|---|---|---|---|
| Bancroft MSA | 100000000 | 2 | null | true |
| Bancroft Contract | 100000000 | 0 | null | true |
| Bancroft Amendment | 100000000 | 1 | null | true |
| Decades MSA Package A | 100000001 | 2 | 100000000 | true |
| Decades MSA Package B | 100000001 | 2 | 100000001 | true |
| Decades MSA Package C | 100000001 | 2 | 100000002 | true |
| Decades Contract | 100000001 | 0 | null | true |
| Decades Amendment | 100000001 | 1 | null | TBD |
| Cover Sheet | (both) | 3 | null | TBD |

---

### 16. dcfg_document_output

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_document_outputid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_document_url | String(500) | No | SharePoint URL to generated file |
| dcfg_merge_status | String(50) | No | Clean / EmptyFields / Failed |
| dcfg_empty_field_count | Integer | No | Count of missing required fields |
| dcfg_source_entity | String(100) | No | dcfg_msa or dcfg_contracts |
| dcfg_source_record_id | String(100) | No | GUID of source record |
| dcfg_template_id | Lookup → dcfg_document_template | No | |

> **Evaluate:** Confirm exact column names. This table is created by flow_docgen, not the UI.

---

### 17. dcfg_template_field

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_template_fieldid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | Primary name (= content control name) |
| dcfg_field_name | String(200) | Yes | **NEW (T-S4).** Content control name in Word template |
| dcfg_source_entity | String(200) | Yes | **NEW (T-S4).** Dataverse table logical name |
| dcfg_source_column | String(500) | Yes | **NEW (T-S4).** Dataverse column path |
| dcfg_is_required | Boolean | No | **NEW (T-S4).** Default false. Required fields produce EmptyFields status when missing. |
| dcfg_document_template_id | Lookup → dcfg_document_template | No | Which template this field belongs to |

> **Evaluate:** Before running the seed script, confirm (a) the table exists, (b) the NEW columns from T-S4 propagated, (c) what columns already existed on this table prior to T-S4. The seed script got 400 errors — likely the new columns haven't propagated or column names don't match what's in production.

**Expected seed data (36 records):**

**MSA Body fields (14):**

| dcfg_name / dcfg_field_name | dcfg_source_entity | dcfg_source_column | dcfg_is_required |
|---|---|---|---|
| CUSTOMER_NAME | dcfg_customer | dcfg_name | true |
| CUSTOMER_CONTACT | dcfg_customer | dcfg_primary_contact_name | false |
| CUSTOMER_CONTACT_EMAIL | dcfg_customer | dcfg_primary_contact_email | false |
| CUSTOMER_SIGNER_NAME | dcfg_customer | dcfg_president_name | true |
| CUSTOMER_SIGNER_TITLE | dcfg_customer | dcfg_president_title | true |
| VENDOR_LEGAL_NAME | dcfg_vendor | dcfg_legal_name | true |
| VENDOR_ADDRESS | dcfg_vendor | dcfg_address | false |
| VENDOR_PHONE | dcfg_vendor | dcfg_phone | false |
| VENDOR_EMAIL | dcfg_vendor | dcfg_email | false |
| VENDOR_SIGNER_NAME | dcfg_vendor | dcfg_signer_name | true |
| VENDOR_SIGNER_TITLE | dcfg_vendor | dcfg_signer_title | true |
| MSA_DATE | dcfg_msa | dcfg_msa_date | true |
| MSA_NAME | dcfg_msa | dcfg_name | false |
| DECADES_SIGNATURE_IMAGE | sharepoint | static_asset | true |

**Exhibit C calculated fields (5):**

| dcfg_name / dcfg_field_name | dcfg_source_entity | dcfg_source_column | dcfg_is_required |
|---|---|---|---|
| LOCATION_COUNT | dcfg_property | COUNT(dcfg_active_flag eq true) | true |
| MEMBERSHIP_RATE | dcfg_msa_rate | dcfg_membership_rate | true |
| MONTHLY_TOTAL | calculated | SUM(Exhibit B Cost/Mo) | true |
| ONBOARDING_FEE | dcfg_msa_rate | dcfg_onboarding_rate | true |
| ANNUAL_INCREASE_DATE | calculated | Jan 1 of (MSA year + 1) | true |

**Work Order fields (15):**

| dcfg_name / dcfg_field_name | dcfg_source_entity | dcfg_source_column | dcfg_is_required |
|---|---|---|---|
| CONTRACTOR_LEGAL_NAME | dcfg_contract | dcfg_contractor_legal_name | true |
| COMPANY | dcfg_contract | dcfg_company | true |
| CONTRACTOR_ADDRESS | dcfg_contract | dcfg_contractor_address | true |
| CONTRCTOR_PHONE | dcfg_contract | dcfg_contractor_phone | true |
| CONTRACTOR_EMAIL | dcfg_contract | dcfg_contractor_email | true |
| SIGNER_PRINTED | dcfg_contract | dcfg_signer_printed | true |
| SIGNER_TITLE | dcfg_contract | dcfg_signer_title | true |
| PAYMENT_PROCESS | dcfg_contract | dcfg_payment_process | false |
| OWNER_CONTACT | dcfg_contract | dcfg_owner_contact | true |
| OWNER_TITLE | dcfg_contract | dcfg_owner_title | false |
| OWNER_EMAIL | dcfg_contract | dcfg_owner_email | false |
| OWNER_STREET | dcfg_contract | dcfg_owner_street | false |
| OWNER_CITY | dcfg_contract | dcfg_owner_city | false |
| OWNER_STATE | dcfg_contract | dcfg_owner_state | false |
| CLIENT_NAME | dcfg_contract | dcfg_client_name | true |

**Amendment-only fields (2):**

| dcfg_name / dcfg_field_name | dcfg_source_entity | dcfg_source_column | dcfg_is_required |
|---|---|---|---|
| PARENT_CONTRACT_NUMBER | dcfg_contract | dcfg_parent_contract_id.dcfg_contract_number | true |
| AMENDMENT_NUMBER | dcfg_contract | dcfg_amendment_number | true |

---

### 18. dcfg_audit_log

**CREATE only — no UPDATE, no DELETE (JS-09)**

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_audit_logid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_target_table | String(200) | Always | Dataverse logical table name |
| dcfg_target_record_id | String(100) | Always | GUID |
| dcfg_action_type | Choice | Always | See picklist below |
| dcfg_performed_by | String(200) | Always | User email |
| dcfg_performed_at | DateTime | Always | UTC |
| dcfg_new_value | String(4000) | Always | Human-readable description |
| dcfg_old_value | String(4000) | Optional | Previous state |
| dcfg_reason | String(2000) | Conditional | Required for Void/Decline/Override |
| dcfg_related_contract_id | String(100) | Always | Contract GUID context |

**Columns that DO NOT EXIST (using them = silent 400):**
`dcfg_entity_type` | `dcfg_entity_id` | `dcfg_action` | `dcfg_details`

**dcfg_audit_log.dcfg_action_type picklist:**

| Label | Int |
|---|---|
| Generated | 100000000 |
| Sent | 100000001 |
| Signed | 100000002 |
| Void | 100000003 |
| Declined | 100000004 |
| Override | 100000005 |
| Status Changed | 100000006 |
| Template Activated | 100000007 |
| Template Deactivated | 100000008 |
| Data Updated | 100000009 |
| Other | 100000010 |

---

### 19. dcfg_send_queue

| Column | Type | Required | Notes |
|---|---|---|---|
| dcfg_send_queueid | Uniqueidentifier | PK | Auto |
| dcfg_name | String(200) | Yes | |
| dcfg_queue_status | Choice | No | See picklist below |
| dcfg_added_to_queue_date | DateTime | No | Sort key for queue display |
| dcfg_contract_id | Lookup → dcfg_contract | No | |

**dcfg_send_queue.dcfg_queue_status picklist:**

| Label | Int |
|---|---|
| Pending | 100000000 |
| Sent | 100000001 |
| Complete | 100000002 |
| Cancelled | 100000003 |

---

## Global Picklist Summary

All choice columns use LOCAL option sets (not global). Verify each table's picklist independently.

**dcfg_contract_family (used on dcfg_vendor, dcfg_contract):**

| Label | Int |
|---|---|
| Bancroft | 100000000 |
| Decades | 100000001 |

**dcfg_exhibit_type (NEW — used on dcfg_document_template, dcfg_msa):**

| Label | Int |
|---|---|
| PackageA | 100000000 |
| PackageB | 100000001 |
| PackageC | 100000002 |

---

## Schema Changes Pending (from Template Spec v1.1)

| ID | Table | Column | Type | Status | Evaluate |
|---|---|---|---|---|---|
| T-S1 | dcfg_document_template | dcfg_exhibit_type | Choice (PackageA/B/C) | Script delivered | Does column exist? Do option values match? |
| T-S2 | dcfg_msa | dcfg_exhibit_type | Choice (PackageA/B/C) | Script delivered | Does column exist? Do option values match? |
| T-S3 | dcfg_msa | dcfg_status | Choice (expand) | Pending | How many options exist today vs. the 7 listed above? |
| T-S4 | dcfg_template_field | dcfg_field_name | String(200) | Script delivered | Does column exist? |
| T-S4 | dcfg_template_field | dcfg_source_entity | String(200) | Script delivered | Does column exist? |
| T-S4 | dcfg_template_field | dcfg_source_column | String(500) | Script delivered | Does column exist? |
| T-S4 | dcfg_template_field | dcfg_is_required | Boolean | Script delivered | Does column exist? |
| T-02 | dcfg_template_field | (36 data records) | Seed data | **FAILED — 400 errors** | Investigate: are T-S4 columns present? Column name mismatch? |

---

## Relationship Inventory

| Parent Table | Child Table | FK Column on Child | Relationship Name (expected pattern) |
|---|---|---|---|
| dcfg_vendor | dcfg_customer | dcfg_vendor_id | dcfg_customer_vendor |
| dcfg_customer | dcfg_msa | dcfg_customer_id | dcfg_msa_customer |
| dcfg_vendor | dcfg_msa | dcfg_vendor_id | dcfg_msa_vendor |
| dcfg_msa | dcfg_msa_rate | dcfg_msa_id | dcfg_msa_rate_msa |
| dcfg_location_type | dcfg_msa_rate | dcfg_location_type_id | dcfg_msa_rate_location_type |
| dcfg_msa | dcfg_contract | dcfg_msa_id | dcfg_contract_msa |
| dcfg_property | dcfg_contract | dcfg_property_id | dcfg_contract_property |
| dcfg_contract | dcfg_contract | dcfg_parent_contract_id | dcfg_contract_parent (self-ref) |
| dcfg_program | dcfg_contract | dcfg_program_id | dcfg_contract_program |
| dcfg_contract | dcfg_contract_line | dcfg_contract_id | dcfg_contract_line_contract |
| dcfg_ap_cost_code | dcfg_contract_line | dcfg_cost_code_id | dcfg_contract_line_cost_code |
| dcfg_customer | dcfg_property | dcfg_customer_id | dcfg_property_customer |
| dcfg_location_type | dcfg_property | dcfg_location_type_id | dcfg_property_location_type |
| dcfg_property | dcfg_property_detail | dcfg_property_id | dcfg_property_detail_property |
| dcfg_property | dcfg_location_document | dcfg_property_id | dcfg_location_document_property |
| dcfg_customer | dcfg_onboarding_case | dcfg_customer_id | dcfg_onboarding_case_customer |
| dcfg_msa | dcfg_onboarding_case | dcfg_msa_id | dcfg_onboarding_case_msa |
| dcfg_onboarding_case | dcfg_onboarding_checklist | dcfg_onboarding_case_id | dcfg_checklist_case |
| dcfg_document_template | dcfg_template_field | dcfg_document_template_id | dcfg_template_field_template |
| dcfg_document_template | dcfg_document_output | dcfg_template_id | dcfg_document_output_template |
| dcfg_contract | dcfg_send_queue | dcfg_contract_id | dcfg_send_queue_contract |
| dcfg_customer | dcfg_program | dcfg_customer_id | dcfg_program_customer |

---

## Evaluation Checklist

For an AI evaluating production against this spec:

1. **For each of the 19 tables:** Does the table exist? Query `EntityDefinitions?$filter=LogicalName eq '{name}'`.
2. **For each table's columns:** Query all attributes, compare against the expected list above. Flag missing, extra, or type-mismatched columns.
3. **For NEW columns (T-S1, T-S2, T-S4):** Do they exist? If not, the schema script needs to be re-run or debugged.
4. **For each relationship:** Query `RelationshipDefinitions` and confirm the FK column exists and points to the correct referenced table.
5. **For each picklist:** Query the option set metadata and confirm all expected values exist with correct integer assignments.
6. **For dcfg_template_field seed data:** Are there 36 records? If 0, the seed script failed (T-02 400 errors). Investigate column names first.
7. **For entity set names:** Confirm `dcfg_propertys` (not properties) is the correct plural. Test with a GET request.
8. **For corrected column names (UL-004):** Confirm dcfg_property uses `dcfg_contact_person` / `dcfg_contact_title` / `dcfg_contact_email` (not `dcfg_owner_*`).

---
*DCFG_Schema_Consolidated.md — 2026-03-12*
