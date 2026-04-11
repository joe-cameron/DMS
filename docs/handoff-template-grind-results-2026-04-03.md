# Template Content Control Cleanup — Results

**Date:** 2026-04-03
**Operator:** Autonomous grind session

---

## COMPLETED

### Phase 1-3: Content Control Tag Rename (198 changes)
All 15 templates in both `DCFG_Templates` and `DCFG_Templates_Test` SharePoint libraries now have content control tags matching the token map exactly.

| # | Template | Controls | Status |
|---|----------|----------|--------|
| 1 | Bancroft_Blanket_Work_Order_Amendment_CC.docx | 24 | FIXED (upload to main lib LOCKED) |
| 2 | Bancroft_Blanket_Work_Order_CC.docx | 22 | FIXED |
| 3 | Bancroft_Exhibit_A_Basic_A_CC.docx | 8 | FIXED |
| 4 | Bancroft_Exhibit_A_Concierge_B_CC.docx | 8 | FIXED |
| 5 | Bancroft_Exhibit_A_Optimized_C_CC.docx | 8 | FIXED |
| 6 | Bancroft_Work_Order_Amendment_CC.docx | 24 | FIXED |
| 7 | Bancroft_Work_Order_CC.docx | 22 | FIXED |
| 8 | Decades_Exhibit_A_Basic_A_CC.docx | 8 | FIXED |
| 9 | Decades_Exhibit_A_Concierge_B_CC.docx | 8 | FIXED |
| 10 | Decades_Exhibit_B_Location_List_CC.docx | 3 | FIXED |
| 11 | Decades_Exhibit_C_Fee_Schedule_CC.docx | 7 | FIXED |
| 12 | Decades_Exhibit_D_Insurance_CC.docx | 2 | FIXED |
| 13 | Decades_Vendor_MSA_CC.docx | 8 | FIXED |
| 14 | Decades_Work_Order_Amendment_CC.docx | 24 | FIXED |
| 15 | Decades_Work_Order_CC.docx | 22 | FIXED |
| 16 | Decades_Exhibit_A_Optimized_C_CC.docx | 8 | **CREATED** (was missing) |

### Tag Rename Map (34 renames applied to all templates)
| Old (human-readable) | New (token key) |
|---|---|
| Amendment Sequence | contract_amendment_sequence |
| Client Name | contract_client_name |
| Contract End Date | contract_end_date |
| Contract Fee | contract_fee |
| Contract Start Date | contract_start_date |
| Contract Type | contract_type |
| Contractor Legal Name | contract_contractor_legal_name |
| Contractor Name | contract_contractor_name |
| Customer President Name | customer_president_name |
| Description of Service | contract_description_of_service |
| Description of Work | contract_description_of_work |
| Membership Quantity | membership_qty |
| Membership Rate | membership_rate |
| MSA Effective Date | msa_effective_date |
| MSA Expiration Date | msa_expiration_date |
| Onboarding Quantity | onboarding_qty |
| Onboarding Rate | onboarding_rate |
| Onboarding Total | onboarding_total |
| Owner City | contract_owner_city |
| Owner Contact | contract_owner_contact |
| Owner Email | contract_owner_email |
| Owner Phone | contract_owner_phone |
| Owner State | contract_owner_state |
| Owner Street | contract_owner_street |
| Owner Title | contract_owner_title |
| PO Number | contract_po_number |
| Property Name | property_name |
| Vendor Address | vendor_address |
| Vendor Email | vendor_email |
| Vendor Payment Terms | vendor_payment_terms |
| Vendor Phone | vendor_phone |
| Vendor Primary Contact | vendor_primary_contact |
| Vendor Signer Title | vendor_signer_title |
| Work Category | contract_work_category |

### Flow Updates — DCFG DocGen v2 (ada6473f)

**File reference fixes (6 corrections):**
| Case | Old File ID | Issue |
|---|---|---|
| Bancroft_Blanket_Work_Order | 01D4QOAQMVCF4... | Stale ID, pointed at deleted file |
| Bancroft_Exhibit_A_Basic_A | 01D4QOAQMBIY... | Stale ID |
| Bancroft_Exhibit_A_Concierge_B | 01D4QOAQK6GF... | Stale ID |
| Bancroft_Exhibit_A_Optimized_C | 01D4QOAQLZAO... | Stale ID |
| Bancroft_Work_Order_Amendment | 01D4QOAQMCUH... | Stale ID |
| Decades_Exhibit_A_Optimized_C | (was a path string!) | Pointed at wrong file entirely |

**dynamicFileSchema field mappings (206 total):**
All 16 Populate actions now have `dynamicFileSchema/{w:id}` parameters mapped to `@outputs('Build_Token_Map')?['token_key']` expressions. The flow passed server-side validation (GetFileSchema + expression parsing).

---

## BLOCKERS

1. **Bancroft_Blanket_Work_Order_Amendment_CC.docx locked (423) in DCFG_Templates**
   - Successfully uploaded to DCFG_Templates_Test
   - Main library upload blocked — someone has the file open
   - **Action:** Close the file in Word/SharePoint, then re-upload from `C:\DCFG\WordTemplates\grind\`

2. **Flow is in Draft state (statecode=1, statuscode=2)**
   - Was already Draft before this session
   - **Action:** Activate the flow in Power Automate designer after verifying

3. **Word Online recognition uncertainty**
   - Per engineering journal: "Template .docx files MUST be opened and saved by Word desktop to be recognized by Word Online"
   - Content controls were originally created by VBA macros (Word desktop), so they should already be recognized
   - Tag renames don't change w:id values, so dynamicFileSchema mappings should still be valid
   - **If Populate actions fail with "field not found":** Open each template in Word desktop, save, re-upload

4. **Bancroft_Work_Order_CC.docx gap vs tag_builder expectations**
   - Has 22 controls but tag_builder lists 25 for this template
   - Missing: contract_completed_date, contract_main_contract_date, contract_original_wo_date, contract_work_start_date, contract_form_of_payment, contract_hours_of_operation, contract_payment_process, contract_service_location
   - Extra (not in tag_builder for this template): contract_description_of_work, contract_end_date, contract_start_date, property_name, vendor_payment_terms
   - These may need to be added/removed in the Word template manually

---

## FILES

- Fixed templates: `C:\DCFG\WordTemplates\grind\*.docx`
- Flow push script: `C:\DCFG\WordTemplates\grind\push_flow.ps1`
- Original flow clientdata backup: `C:\DCFG\WordTemplates\grind\flow_clientdata.json`
- w:id mappings: embedded in push_flow.ps1 JSON

---

## NEXT STEPS

1. Close locked Bancroft file, re-upload to DCFG_Templates
2. Activate flow in Power Automate designer
3. Test DocGen end-to-end: create a document request via SPA, verify output fields populated
4. If any Populate action fails: open that template in Word desktop, save, re-upload, retry
5. Address Bancroft WO template gaps (missing 8 controls per tag_builder)
