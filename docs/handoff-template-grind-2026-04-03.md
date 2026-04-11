# HANDOFF: Template Content Control Cleanup — Autonomous Grind

**Date:** 2026-04-03
**Mode:** `claude --dangerously-skip-permissions`
**Priority:** CRITICAL PATH — DocGen is blocked until this is done

---

## YOUR MISSION

Fix every Word template content control to match the token map. Field by field, document by document. Test each fix with Playwright. Read flow history with Nora. No excuses, no escalation mid-loop. Grind until 100%.

---

## LOAD THESE FIRST

```
Read C:\Users\JosephCameron\.claude\projects\C--DCFG\memory\project_template_cleanup.md
Read C:\Users\JosephCameron\.claude\projects\C--DCFG\memory\reference_engineering_journal.md
Read C:\DCFG\CLAUDE.md
```

---

## CONTEXT

- **Flow ID:** ada6473f (Test environment)
- **Flow scope:** INSIDE THE SWITCH CASES ONLY. Rest of flow is off limits.
- **Token map:** 50 keys defined in `C:\DCFG\docs\tag_builder.html`
- **Templates:** SharePoint DCFG_Templates library. Read `dcfg_configs` for `dcfg_sp_site_url` and `dcfg_sp_templates_library`.
- **VBA macros:** `C:\DCFG\WordTemplates\DCFG_ContentControl_Macros_v2.bas`
- **Test environment:** org0c17e98d.crm.dynamics.com (pac auth index 1)
- **SPA:** https://dcfg.powerappsportals.com
- **SPA is READ-ONLY** unless operator grants permission

---

## THE LOOP

```
FOR EACH template in SharePoint DCFG_Templates:
  1. Download .docx
  2. Unzip, parse word/document.xml for <w:sdt> elements
  3. Extract all content control tags + titles
  4. Compare against the 50 token keys from tag_builder.html
  5. Log: matched / orphaned / missing / duplicated
  6. FOR EACH mismatch:
     a. Rename control tag + alias to match token key
     b. Rezip .docx, upload to SharePoint
     c. Trigger DocGen via Playwright (wizard → generate)
     d. WHILE WAITING: dispatch agents to:
        - Read flow run history for latest request
        - Parse previous output doc for field verification
        - Prepare next template fix
     e. Check dcfg_document_requests for Complete/Failed
     f. If Failed → read flow error → diagnose → fix → retry
     g. If Complete → download output → verify fields populated
     h. Log result
  7. NEXT mismatch
NEXT template
```

---

## 11 TEMPLATES TO PROCESS

| # | Template | Token Count |
|---|----------|-------------|
| 1 | BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx | 22 |
| 2 | Bancroft-Workorder(Template).docx | 25 |
| 3 | Decades_Work_Order.docx | 22 |
| 4 | Bancroft_Work_Order_Amendment.docx | 20 |
| 5 | Bancroft_Blanket_Work_Order_Amendment.docx | 20 |
| 6 | Decades_Work_Order_Amendment.docx | 20 |
| 7 | Decades_Management_Services_Agreement.docx | 8 |
| 8 | Exhibit_A_Basic_Platform_Package_A.docx | 8 |
| 9 | Exhibit_A_Concierge_Package_B.docx | 8 |
| 10 | Exhibit_A_Optimized_Package_C.docx | 8 |
| 11 | Exhibit_C_Fee_Schedule.docx | 7 |

---

## TOKEN MAP (50 keys)

### Customer
- `contract_client_name`
- `contract_owner_city`
- `contract_owner_contact`
- `contract_owner_email`
- `contract_owner_phone`
- `contract_owner_state`
- `contract_owner_street`
- `contract_owner_title`
- `customer_president_name`

### Contract
- `contract_amendment_sequence`
- `contract_completed_date`
- `contract_contractor_legal_name`
- `contract_contractor_name`
- `contract_current_expiration_date`
- `contract_current_properties`
- `contract_description_of_service`
- `contract_description_of_work`
- `contract_end_date`
- `contract_fee`
- `contract_form_of_payment`
- `contract_hours_of_operation`
- `contract_is_budgeted`
- `contract_main_contract_date`
- `contract_original_wo_date`
- `contract_payment_process`
- `contract_po_number`
- `contract_service_location`
- `contract_start_date`
- `contract_type`
- `contract_work_category`
- `contract_work_start_date`
- `work_order_number`

### Vendor
- `vendor_address`
- `vendor_email`
- `vendor_payment_terms`
- `vendor_phone`
- `vendor_primary_contact`
- `vendor_signer_title`

### Property
- `property_name`

### MSA
- `msa_effective_date`
- `msa_expiration_date`

### Exhibit C (Fee Schedule)
- `membership_qty`
- `membership_rate`
- `onboarding_qty`
- `onboarding_rate`
- `onboarding_total`

---

## RULES

1. **SPA is READ-ONLY.** Do not modify files under `C:\DCFG\spa\`.
2. **Flow scope: Switch cases ONLY.** Do not touch trigger, connections, or actions outside the Switch.
3. **Look before you leap.** Read current state before every write.
4. **Test after you change.** Verify the fix worked before moving on.
5. **Roll back as needed.** If a fix doesn't work, undo it and try another approach.
6. **No mid-loop escalation.** Hold blockers until the end. Keep grinding.
7. **Use agents in parallel.** While Playwright waits, agents should be reading flow history, parsing docs, preparing the next fix.
8. **Log every change.** Before/after for rollback capability.
9. **Playwright uses manual-pause pattern** for auth (Windows Hello). Never automate passwords.
10. **Always restore pac auth to Test (index 1)** after any environment operation.

---

## SUCCESS CRITERIA

Every content control in every template matches a token key. Every generated document has all fields populated. Zero blank fields, zero raw token names in output. Flow run history shows no content-control-related failures.

---

## NORA LOGGING — MANDATORY

Log EVERYTHING to `dcfg_brain_insights` via Dataverse API. Every action, every result, every failure.

```
FOR EACH action taken:
  Write to dcfg_brain_insights:
    dcfg_source: "template-grind"
    dcfg_category: "docgen-cleanup"
    dcfg_title: "{template_name} — {field_name}"
    dcfg_detail: "{what was done, what was found, before→after}"
    dcfg_severity: "info" | "warning" | "error"
    dcfg_timestamp: now
```

**Read flow run history from BOTH environments before and during the grind:**
- **Test:** Flow ada6473f on org0c17e98d.crm.dynamics.com (pac auth index 1)
- **Prod:** Flow ada6473f on org06f5de0b.crm.dynamics.com (pac auth index 3)
- Query: `workflows(ada6473f)/runs?$orderby=createdon desc&$top=20`
- Log each run: status, start time, duration, failed action name + error if failed
- Compare Test vs Prod behavior — Prod history shows what WORKS, use it as reference
- **Always restore pac auth to Test (index 1) after reading Prod**

Log types:
- **SCAN:** "Parsed template X — found N controls, M matched, K orphaned, J missing"
- **FIX:** "Renamed control 'OLD_NAME' → 'new_name' in template X"
- **TEST:** "DocGen triggered for template X — request ID: {id}"
- **RESULT:** "DocGen complete — {N} fields populated, {M} blank"
- **FAILURE:** "DocGen failed — flow error: {message} — action: {action_name}"
- **RETRY:** "Retrying template X after fix — attempt {N}"
- **ROLLBACK:** "Rolled back template X to previous version — reason: {why}"

This is your audit trail. If the operator asks "what happened" there must be a complete log in Dataverse.

---

## WHEN DONE

1. Print change summary: template × field × before → after
2. List any blockers encountered (batched, not mid-loop)
3. Update `C:\DCFG\calendar.json` with completion status
4. Clear cache: https://dcfg.powerappsportals.com/_services/about
