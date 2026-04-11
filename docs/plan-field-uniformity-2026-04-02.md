# Field Uniformity Implementation Plan — 2026-04-02 4:00 PM Deploy

## Governing Rule
**The Word content control tag name is the source of truth.** All lowercase, underscore-separated. The flow token map key must match exactly. The SPA can use camelCase internally but the value it writes to Dataverse must land in the column that the flow reads.

**Do NOT rename:** camelCase state variables in React, existing Dataverse column schema names, or flow action names. Only align the **token map output keys** and **fill missing data paths**.

---

## ALREADY STAGED (ready to deploy)

| Fix | File | Status |
|-----|------|--------|
| Onboarding step delete filter | Admin.jsx | Built, in dist |
| NavPanel concierge URL race condition | NavPanel.jsx | Built, in dist |

---

## PHASE 1: Token Map — Dual-Key Output (Flow — Designer Work)

**Where:** DocGen v2 flow → Build_Token_Map Compose action
**Strategy:** Option A — keep ALL existing UPPERCASE keys (nothing breaks), ADD lowercase aliases that match Word content control tags exactly. Existing Populate actions keep working. New cases and future migrations use lowercase keys.

### How to Implement
1. Open DocGen v2 flow in designer
2. Edit Build_Token_Map Compose action
3. **Keep every existing key as-is** — do not delete or rename anything
4. **Add a lowercase alias** for each existing key (same value, new key name)
5. **Add new keys** that don't exist yet
6. Save flow — DO NOT touch the trigger

### Existing Keys — Add Lowercase Aliases (keep originals)

| Keep This (existing) | Add This (new alias) | Same Value |
|---|---|---|
| `CLIENT_NAME` | `contract_client_name` | Yes |
| `CONTRACTOR_LEGAL_NAME` | `contract_contractor_legal_name` | Yes |
| `CONTRACTOR_NAME` | `contract_contractor_name` | Yes |
| `WORK_ORDER_FEE` | `contract_fee` | Yes |
| `WORK_ORDER_DATE` | `contract_start_date` | Yes (verify — start or contract date?) |
| `CONTRACTOR_TITLE` | `vendor_signer_title` | Yes |
| `OWNER_CONTACT` | `contract_owner_contact` | Yes |
| `OWNER_TITLE` | `contract_owner_title` | Yes |
| `OWNER_EMAIL` | `contract_owner_email` | Yes |
| `OWNER_PHONE` | `contract_owner_phone` | Yes |
| `OWNER_STREET` | `contract_owner_street` | Yes |
| `OWNER_CITY` | `contract_owner_city` | Yes |
| `OWNER_STATE` | `contract_owner_state` | Yes |
| `PROPERTY_NAME` | `property_name` | Yes |
| `DESCRIPTION_OF_SERVICE` | `contract_description_of_service` | Yes |
| `MAIN_CONTRACT_DATE` | `msa_effective_date` | Yes |
| `PRESIDENT_CONTACT` | `customer_president_name` | Yes |

### New Keys to Add (no existing equivalent)

| Key to Add | Source Expression | Used By Templates |
|---|---|---|
| `contract_description_of_work` | `Get_Source_Record.body/dcfg_description_of_work` | All WO + Amendment |
| `contract_end_date` | `formatDateTime(Get_Source_Record.body/dcfg_end_date, 'MMMM d, yyyy')` | All WO + Amendment |
| `contract_type` | WO/Amendment/MSA label from dcfg_contract_type | All WO |
| `contract_amendment_sequence` | `string(Get_Source_Record.body/dcfg_amendment_sequence)` | All Amendments |
| `contract_po_number` | `Get_Source_Record.body/dcfg_po_number` | All Amendments |
| `contract_work_category` | `Get_Source_Record.body/dcfg_work_category` | All Amendments |
| `vendor_payment_terms` | `Get_Source_Record.body/dcfg_payment_process` | All WO |
| `vendor_address` | `Get_Vendor.body/dcfg_address` | All WO + Amendment |
| `vendor_email` | `Get_Vendor.body/dcfg_email` | All WO + Amendment |
| `vendor_phone` | `Get_Vendor.body/dcfg_phone` | All WO + Amendment |
| `vendor_primary_contact` | `Get_Vendor.body/dcfg_primary_contact` | All WO + Amendment |
| `msa_expiration_date` | `formatDateTime(Get_MSA.body/dcfg_expiration_date, 'MMMM d, yyyy')` | MSA |

### Migration Plan (After Dual-Key is Stable)
1. Deploy dual-key Build_Token_Map (zero risk)
2. Pick ONE Switch case (e.g., Decades_Work_Order)
3. Update its Populate expressions from UPPERCASE → lowercase
4. Test that one document type
5. If good → migrate next case
6. After all 13 cases migrated → remove UPPERCASE keys from Build_Token_Map
7. **Do not remove UPPERCASE keys until all cases are migrated and tested**

---

## PHASE 2: Exhibit C Tokens (Flow — Designer + API)

**Where:** DocGen v2 flow → new Get_MSA_Rates action + Build_Token_Map additions + Switch case

### Step 1: Add Get_MSA_Rates Action
Insert after Get_MSA, before Build_Token_Map:
```
Action: List rows (Dataverse)
Table: dcfg_msa_rates
Filter: _dcfg_msa_id_value eq {MSA ID} and dcfg_is_active eq true
Select: dcfg_membership_rate, dcfg_onboarding_rate, dcfg_name
```

### Step 2: Add Exhibit C Tokens to Build_Token_Map
```json
"membership_qty": length(body('Get_MSA_Rates')?['value']),
"membership_rate": if(greater(length(body('Get_MSA_Rates')?['value']), 0), body('Get_MSA_Rates')?['value'][0]?['dcfg_membership_rate'], 0),
"onboarding_qty": length(body('Get_MSA_Rates')?['value']),
"onboarding_rate": if(greater(length(body('Get_MSA_Rates')?['value']), 0), body('Get_MSA_Rates')?['value'][0]?['dcfg_onboarding_rate'], 0),
"onboarding_total": mul(length(body('Get_MSA_Rates')?['value']), if(greater(length(body('Get_MSA_Rates')?['value']), 0), body('Get_MSA_Rates')?['value'][0]?['dcfg_onboarding_rate'], 0))
```

**Note:** `membership_qty` and `onboarding_qty` are both the count of rate records (one per location type). If uniform pricing, there's one rate per type. The qty represents how many location types have rates — this may need refinement to count actual locations instead. Verify business intent.

### Step 3: Add Switch Case
In Switch_Template, add case `Decades_Exhibit_C_Fee_Schedule` with a Populate action mapping all 7 Exhibit C fields.

---

## PHASE 3: Missing SPA Fields (Code — staged, deploy with build)

### 3a: Amendment Wizard — Add Work Category and PO Number

**File:** `NewContractWizard.jsx`
**Location:** Step 2 (Document Type), visible only when `contractType === ContractType.Amendment`

Add two fields after the existing amendment fields:
```
Work Category → dcfg_work_category (text input)
PO Number → dcfg_po_number (text input)
```

Add to the contract payload in handleGenerate:
```javascript
if (contractType === ContractType.Amendment) {
  payload.dcfg_work_category = workCategory || null;
  payload.dcfg_po_number = poNumber || null;
}
```

### 3b: Proposal Wizard — Add MSA Expiration Date

**File:** `NewProposalWizard.jsx`
**Location:** Step 2 (Customer & Vendor), after MSA Effective Date

Add one field:
```
Expiration Date → dcfg_expiration_date (date input)
```

Add to the MSA payload in generate:
```javascript
mp.dcfg_expiration_date = msaExpDate || null;
```

### 3c: Contract Wizard — Description of Work

**Verify:** Is `dcfg_description_of_work` already in the contract payload? The gap analysis shows the Word tag exists but the token wasn't in the map. Check if the SPA writes it — if yes, just add the token. If no, add the field.

**Current state from code:** The SPA does NOT write `dcfg_description_of_work` to the contract record. The wizard has a "Description of Work" text area but it may be writing to a different column name. **Verify the actual state variable and which column it writes to.**

---

## PHASE 4: Owner Contact Source Fix (Flow)

**Issue:** SPA writes owner contact info to the **contract record** (`dcfg_owner_contact`, `dcfg_owner_city`, etc.). The flow reads it from the **property record** (`dcfg_contact_person`, `dcfg_city`, etc.). If the user overrides the contact in the wizard, the flow ignores the override.

**Fix:** Change Build_Token_Map to read owner fields from the **contract record first**, falling back to the property record:

```
"contract_owner_contact": coalesce(Get_Source_Record.body/dcfg_owner_contact, Get_Property.body/dcfg_contact_person)
"contract_owner_city": coalesce(Get_Source_Record.body/dcfg_owner_city, Get_Property.body/dcfg_city)
"contract_owner_street": coalesce(Get_Source_Record.body/dcfg_owner_street, Get_Property.body/dcfg_address)
"contract_owner_state": coalesce(Get_Source_Record.body/dcfg_owner_state, Get_Property.body/dcfg_state)
"contract_owner_email": coalesce(Get_Source_Record.body/dcfg_owner_email, Get_Property.body/dcfg_contact_email)
"contract_owner_phone": coalesce(Get_Source_Record.body/dcfg_owner_phone, Get_Property.body/dcfg_contact_phone)
"contract_owner_title": coalesce(Get_Source_Record.body/dcfg_owner_title, Get_Property.body/dcfg_contact_title)
```

This respects the user's wizard input while falling back to property data if not set.

---

## PHASE 5: Update Tag Builder & Clipboard (HTML)

After flow changes are made, update:
1. `tag_builder.html` — ensure expression column shows correct `outputs('Build_Token_Map')?['lowercase_key']` format
2. `clipboard.html` — field expressions section already uses lowercase, verify all match

---

## DEPLOY SEQUENCE (4:00 PM)

### Batch 1: SPA (build + deploy)
1. Admin.jsx — onboarding step delete filter (already staged)
2. NavPanel.jsx — concierge URL race condition (already staged)
3. NewContractWizard.jsx — add `dcfg_work_category` and `dcfg_po_number` fields for amendments
4. NewProposalWizard.jsx — add `dcfg_expiration_date` field for MSA

**Deploy order:** Prod first, then Test

### Batch 2: Flow (manual designer work — operator)
1. Open DocGen v2 flow in designer
2. Edit Build_Token_Map — rename keys to lowercase, add missing keys
3. Add Get_MSA_Rates action
4. Add Exhibit C Switch case + Populate action
5. Fix owner contact coalesce logic
6. Save flow

### Batch 3: Verification
1. Generate a test WO document — verify all fields populate
2. Generate a test Amendment — verify work_category, po_number, amendment_sequence
3. Generate a test MSA — verify msa_effective_date, msa_expiration_date, president_name
4. Generate Exhibit C — verify all 5 rate fields

---

## REFERENCE: Complete Field Chain (Post-Implementation)

After all phases, every chain should be:

```
User types in wizard field
  → SPA writes to dcfg_[column] on contract/MSA record
    → createDocumentRequest links contract/MSA + template
      → Flow trigger reads document_request
        → Flow gets contract/MSA/customer/vendor/property/rates
          → Build_Token_Map outputs key matching Word tag name
            → Populate action maps token → content control
              → Word document has correct value
```

### Work Order Complete Chain
| Word Tag | ← Token Key | ← Flow Reads | ← Dataverse Column | ← SPA Writes | ← UI Field |
|---|---|---|---|---|---|
| contract_client_name | contract_client_name | Customer.dcfg_name | dcfg_name | selectedCustomer.dcfg_name | Customer picker |
| contract_contractor_legal_name | contract_contractor_legal_name | Vendor.dcfg_legal_name | dcfg_legal_name | vendor.dcfg_legal_name | Vendor picker |
| contract_contractor_name | contract_contractor_name | Vendor.dcfg_display_name | dcfg_display_name | vendor.dcfg_display_name | Vendor picker |
| contract_description_of_work | contract_description_of_work | Contract.dcfg_description_of_work | dcfg_description_of_work | descriptionOfWork | Description textarea |
| contract_start_date | contract_start_date | Contract.dcfg_contract_date | dcfg_contract_date | contractDate | Date picker |
| contract_end_date | contract_end_date | Contract.dcfg_end_date | dcfg_end_date | — (need to add) | Date picker |
| contract_fee | contract_fee | Contract.dcfg_contract_fee | dcfg_contract_fee | linesTotal | Sum of lines |
| contract_type | contract_type | Contract.dcfg_contract_type (labeled) | dcfg_contract_type | contractType | Type selector |
| contract_owner_contact | contract_owner_contact | coalesce(Contract, Property) | dcfg_owner_contact | locContact.name | Contact name input |
| contract_owner_title | contract_owner_title | coalesce(Contract, Property) | dcfg_owner_title | locContact.title | Contact title input |
| contract_owner_email | contract_owner_email | coalesce(Contract, Property) | dcfg_owner_email | locContact.email | Contact email input |
| contract_owner_phone | contract_owner_phone | coalesce(Contract, Property) | dcfg_owner_phone | — (need to verify) | Contact phone input |
| contract_owner_street | contract_owner_street | coalesce(Contract, Property) | dcfg_owner_street | locContact.street | Address input |
| contract_owner_city | contract_owner_city | coalesce(Contract, Property) | dcfg_owner_city | locContact.city | City input |
| contract_owner_state | contract_owner_state | coalesce(Contract, Property) | dcfg_owner_state | locContact.state | State input |
| property_name | property_name | Property.dcfg_name | dcfg_name | locationId | Location picker |
| vendor_address | vendor_address | Vendor.dcfg_address | dcfg_address | vendor.dcfg_address | Vendor picker |
| vendor_email | vendor_email | Vendor.dcfg_email | dcfg_email | vendor.dcfg_email | Vendor picker |
| vendor_phone | vendor_phone | Vendor.dcfg_phone | dcfg_phone | vendor.dcfg_phone | Vendor picker |
| vendor_primary_contact | vendor_primary_contact | Vendor.dcfg_primary_contact | dcfg_primary_contact | vendor.dcfg_primary_contact | Vendor picker |
| vendor_signer_title | vendor_signer_title | Contract.dcfg_signer_title | dcfg_signer_title | signerTitle | Signer title input |
| vendor_payment_terms | vendor_payment_terms | Contract.dcfg_payment_process | dcfg_payment_process | paymentProcess | Payment terms input |

### Amendment Additional Fields
| Word Tag | ← Token Key | ← Dataverse Column | ← UI Field |
|---|---|---|---|
| contract_amendment_sequence | contract_amendment_sequence | dcfg_amendment_sequence | Amendment number input |
| contract_description_of_service | contract_description_of_service | dcfg_description_of_service | Service description textarea |
| contract_po_number | contract_po_number | dcfg_po_number | PO number input (NEW) |
| contract_work_category | contract_work_category | dcfg_work_category | Work category input (NEW) |

### MSA / Exhibit Chain
| Word Tag | ← Token Key | ← Dataverse Column | ← UI Field |
|---|---|---|---|
| contract_client_name | contract_client_name | Customer.dcfg_name | Customer search/create |
| contract_contractor_legal_name | contract_contractor_legal_name | Vendor.dcfg_legal_name | Vendor (pre-filled Decades) |
| contract_owner_city | contract_owner_city | Customer.dcfg_billing_city | Billing city input |
| contract_owner_street | contract_owner_street | Customer.dcfg_billing_address | Billing address input |
| contract_owner_title | contract_owner_title | Customer.dcfg_president_title | Signer title input |
| customer_president_name | customer_president_name | Customer.dcfg_president_name | Signer name input |
| msa_effective_date | msa_effective_date | MSA.dcfg_effective_date | Effective date picker |
| msa_expiration_date | msa_expiration_date | MSA.dcfg_expiration_date | Expiration date picker (NEW) |

### Exhibit C Chain
| Word Tag | ← Token Key | ← Source | ← UI Field |
|---|---|---|---|
| contract_client_name | contract_client_name | Customer.dcfg_name | Customer search/create |
| msa_effective_date | msa_effective_date | MSA.dcfg_effective_date | Effective date picker |
| membership_qty | membership_qty | count(MSA Rates) | Computed from location count |
| membership_rate | membership_rate | MSA Rate.dcfg_membership_rate | Monthly rate input (Step 3) |
| onboarding_qty | onboarding_qty | count(MSA Rates) | Computed from location count |
| onboarding_rate | onboarding_rate | MSA Rate.dcfg_onboarding_rate | Onboarding fee input (Step 3) |
| onboarding_total | onboarding_total | qty × rate | Computed |
