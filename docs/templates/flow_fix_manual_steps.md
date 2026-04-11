# DocGen Flow — Fixes (Manual in Designer)

## URGENT FIX: Document URL is NULL

The `Set_varOutputFileUrl` expression `outputs('Create_file')?['body/{Link}']` returns empty because the SharePoint connector property name changed.

**Action:** `Set_varOutputFileUrl`
**Current value:** `@{outputs('Create_file')?['body/{Link}']}`

**Try these replacements in order (test each):**
1. `@{outputs('Create_file')?['body/{SpItemUrl}']}`
2. `@{outputs('Create_file')?['body/{Link}']}`
3. `@{outputs('Create_file')?['body/{Url}']}`
4. `@{outputs('Create_file')?['body/{Path}']}`

**Or use the dynamic content picker:** Click on `Set_varOutputFileUrl`, delete the current value, click "Add dynamic content", find `Create_file` outputs, and look for any URL/Link/Path property.

---

The Power Automate management API has a schema mismatch between read and write that prevents scripted updates for this flow. Apply these changes directly in the Power Automate designer.

## Flow: DCFG DocGen v2
- Environment: Prod (6ee0cd74-e2b2-e429-ac4b-27123cd20d19)
- Flow ID: 42fae156-8575-9ef8-4224-15e286ab5264

---

## Fix 1: Get_Customer — Null Safety

**Action:** `Get_Customer`
**Field:** Row ID

**Current value:**
```
@triggerOutputs()?['body/_dcfg_customer_id_value']
```

**Replace with:**
```
@coalesce(
  if(not(equals(triggerOutputs()?['body/_dcfg_contract_id_value'], null)),
    outputs('Get_Contract')?['body/_dcfg_customer_id_value'],
    null),
  if(not(equals(triggerOutputs()?['body/_dcfg_msa_id_value'], null)),
    outputs('Get_MSA')?['body/_dcfg_customer_id_value'],
    null),
  '00000000-0000-0000-0000-000000000000'
)
```

**One-line version (paste this):**
```
@coalesce(if(not(equals(triggerOutputs()?['body/_dcfg_contract_id_value'], null)), outputs('Get_Contract')?['body/_dcfg_customer_id_value'], null), if(not(equals(triggerOutputs()?['body/_dcfg_msa_id_value'], null)), outputs('Get_MSA')?['body/_dcfg_customer_id_value'], null), '00000000-0000-0000-0000-000000000000')
```

---

## Fix 2a: Get_Property — Null Safety

**Action:** `Get_Property`
**Field:** Row ID

**Current value:**
```
@outputs('Get_Contract')?['body/_dcfg_property_id_value']
```

**Replace with:**
```
@coalesce(outputs('Get_Contract')?['body/_dcfg_property_id_value'], '00000000-0000-0000-0000-000000000000')
```

---

## Fix 2b: Get_Vendor — Null Safety

**Action:** `Get_Vendor`
**Field:** Row ID

**Current value:**
```
@if(not(empty(outputs('Get_Contract')?['body/_dcfg_vendor_id_value'])), outputs('Get_Contract')?['body/_dcfg_vendor_id_value'], outputs('Get_MSA')?['body/_dcfg_vendor_id_value'])
```

**Replace with:**
```
@coalesce(if(not(equals(triggerOutputs()?['body/_dcfg_contract_id_value'], null)), outputs('Get_Contract')?['body/_dcfg_vendor_id_value'], null), if(not(equals(triggerOutputs()?['body/_dcfg_msa_id_value'], null)), outputs('Get_MSA')?['body/_dcfg_vendor_id_value'], null), '00000000-0000-0000-0000-000000000000')
```

---

## Fix 3: Error Handler

**Add a new action** after all existing actions:

1. Click **+ New step** at the bottom of the flow
2. Search for **Dataverse** → **Update a row**
3. Name it: `Handle_Flow_Failure`
4. Configure:
   - **Table name:** Document Requests (dcfg_document_requests)
   - **Row ID:** `@triggerOutputs()?['body/dcfg_document_requestid']`
   - **Status:** Failed (100000003)
   - **Completed At:** `@{utcNow()}`
   - **Error Message:** `Flow failed - check run history for details`
5. Click the **...** menu → **Configure run after**
6. Check: **has failed**, **is skipped**, **has timed out**
7. Uncheck: **is successful**
8. Set **Run after** to: `Update_Request_Complete`

**Save the flow.**

---

## Verification

After saving, trigger a test document request from the SPA. If the flow fails:
- The document request should update to status=Failed (100000003) with an error message
- The SPA polling should detect the failure and show a red banner

Check flow run history to confirm the error handler executed.
