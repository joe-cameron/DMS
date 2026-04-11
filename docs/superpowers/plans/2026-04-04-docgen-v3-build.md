# DocGen v3 Build Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push a clean v3 flow definition that generates all 11 document types without errors.

**Architecture:** Copy v2's proven actions into v3's shell (same connections). Fix 3 known bugs. Push via PA Management API. Test one template at a time.

**Tech Stack:** PowerShell, Power Automate Management API, Dataverse API

**Key insight:** V2 and V3 share identical connectionNames (`shared_commondataserviceforapps`, `shared_sharepointonline`, `shared_wordonlinebusiness`). No connection remapping needed. Just copy actions, fix bugs, push.

---

## Known Bugs to Fix (from v2)

1. **Get_Property crashes on null** — needs Condition_Has_Property wrapper
2. **Set_Doc actions missing `value`** — all 11 need `@body('Populate_XXX')`
3. **Set_varOutputFileUrl missing `value`** — needs `@body('Create_file')?['Path']`
4. **Dead Switch cases** — Blanket WO x2, Exhibit B/C/D must be removed

---

### Task 1: Copy v2 actions into v3 definition (no modifications)

**Files:**
- Read: `C:\DCFG\Flows\_docgen_v2_test_live.json`
- Read: `C:\DCFG\Flows\_docgen_v3_shell.json`
- Write: `C:\DCFG\Flows\_docgen_v3_step1.json`

- [ ] **Step 1: Read v2 and v3 definitions**
- [ ] **Step 2: Copy v2 actions into v3 — DO NOT touch triggers or connectionReferences**
- [ ] **Step 3: Save as `_docgen_v3_step1.json`**
- [ ] **Step 4: Verify — count actions, confirm trigger untouched**

---

### Task 2: Remove dead Switch cases

**Files:**
- Modify: `C:\DCFG\Flows\_docgen_v3_step1.json`
- Write: `C:\DCFG\Flows\_docgen_v3_step2.json`

- [ ] **Step 1: Remove 5 cases:** Bancroft_Blanket_Work_Order, Bancroft_Blanket_WO_Amendment, Decades_Exhibit_B_Location_List, Decades_Exhibit_C_Fee_Schedule, Decades_Exhibit_D_Insurance
- [ ] **Step 2: Verify 11 cases remain**
- [ ] **Step 3: Save as `_docgen_v3_step2.json`**

---

### Task 3: Fix Get_Property null guard

**Files:**
- Modify: `C:\DCFG\Flows\_docgen_v3_step2.json`
- Write: `C:\DCFG\Flows\_docgen_v3_step3.json`

- [ ] **Step 1: Remove flat Get_Property action, save its host block and runAfter**
- [ ] **Step 2: Create Condition_Has_Property wrapping Get_Property**
  - Expression: contract_id not null AND Get_Contract property_id not null
  - Preserves original host block and operationId
- [ ] **Step 3: Update Build_Token_Map runAfter: replace Get_Property → Condition_Has_Property with ["Succeeded","Skipped"]**
- [ ] **Step 4: Save as `_docgen_v3_step3.json`**

---

### Task 4: Fix all SetVariable value fields

**Files:**
- Modify: `C:\DCFG\Flows\_docgen_v3_step3.json`
- Write: `C:\DCFG\Flows\_docgen_v3_final.json`

- [ ] **Step 1: For each Set_Doc_XXX action, add `value: "@body('Populate_XXX')"`**
- [ ] **Step 2: Fix Set_varOutputFileUrl: add `value: "@body('Create_file')?['Path']"`**
- [ ] **Step 3: Verify all 12 SetVariable actions have value property**
- [ ] **Step 4: Save as `_docgen_v3_final.json`**

---

### Task 5: Push v3 via PA Management API

**Files:**
- Read: `C:\DCFG\Flows\_docgen_v3_final.json`

- [ ] **Step 1: Read v3 shell LIVE from PA API (get current trigger/connectionReferences)**
- [ ] **Step 2: Replace only `definition.actions` with the final actions**
- [ ] **Step 3: Push via PATCH to PA API**
- [ ] **Step 4: Verify — read back, confirm 11 cases, all Set_Doc have values**

---

### Task 6: Test one template — Decades VendorAgreement (MSA, no contract)

- [ ] **Step 1: Create one dcfg_document_request with template=Decades_Vendor_MSA**
- [ ] **Step 2: Wait 30s, check PA run history for the new run**
- [ ] **Step 3: If Failed — read failed action from run, diagnose, fix, re-push**
- [ ] **Step 4: If Succeeded — check dcfg_document_requests status = Complete**
- [ ] **Step 5: Check dcfg_output_file_url has a value**

---

### Task 7: Test remaining templates one at a time

For each template, repeat Task 6 pattern:

- [ ] Bancroft WorkOrder (needs contract)
- [ ] Decades WorkOrder (needs contract)
- [ ] Bancroft Amendment (needs contract)
- [ ] Decades Amendment (needs contract)
- [ ] Bancroft Proposal A (MSA only)
- [ ] Bancroft Proposal B (MSA only)
- [ ] Bancroft Proposal C (MSA only)
- [ ] Decades Proposal A (MSA only)
- [ ] Decades Proposal B (MSA only)
- [ ] Decades Proposal C (MSA only)

Each test: create request → wait → check run → if fail diagnose and fix → if pass move on.

---

### Task 8: Download outputs and screenshot for validation

- [ ] **Step 1: For each completed request, download output .docx from SharePoint**
- [ ] **Step 2: Open each in Playwright browser, screenshot**
- [ ] **Step 3: Log which fields are populated vs blank**
- [ ] **Step 4: Report results**
