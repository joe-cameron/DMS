# DCFG Flow Operations — What Works and What Doesn't

## Proven Capabilities via Dataverse Workflows Table

Claude CAN successfully:
- Read existing flow definitions via `GET workflows?$filter=name eq 'x'&$select=workflowid,clientdata`
- Deactivate flows via `PATCH workflows(id)` with `statecode=0, statuscode=1`
- Update flow action definitions via `PATCH workflows(id)` with updated `clientdata`
- Reactivate flows via `PATCH workflows(id)` with `statecode=1, statuscode=2`
- Read connection references from existing flow's `clientdata.properties.connectionReferences`

## What Claude CANNOT Do via API

1. **Create new flows** — Only update existing flows
2. **Set trigger type** — User must change triggers manually in Power Automate designer
3. **Establish new connections** — User must add one action of each connector type manually
4. **Set dynamic table names in Dataverse actions** — Power Automate requires table names from dropdown, not expressions. Use Condition branches instead.
5. **Create premium connector actions** — Word Online, SharePoint, Office 365 require manual setup first

## Three-Step Flow Build Process (PROVEN)

### Step 1: Claude pushes placeholder definition
- Compose actions as stand-ins for every connection-dependent action
- Each placeholder describes what it should become: table, fields, expressions
- Variables, conditions, and non-connector actions work directly
- Push via `PATCH workflows(id)` with updated `clientdata`

### Step 2: User manually adds one action per connector type
In Power Automate designer:
- One Dataverse "Get a row" (establishes Dataverse connection)
- One Dataverse "Update a row"
- One Dataverse "Add a new row"
- One Dataverse "List rows"
- One SharePoint "Create file" (establishes SharePoint connection)
- One Word Online "Populate a template" (establishes Word Online connection)
- Change trigger to Dataverse "When a row is added" with table and filter
- Save the flow

### Step 3: Claude reads back and pushes full definition
- Read the flow: `GET workflows(id)?$select=clientdata`
- Extract `connectionReferences` — captures connection IDs and auth pattern per environment
- Extract one working action's `host` block — captures `connectionName` vs `connectionReferenceName` format
- Check if environment uses `authentication` property on actions (Stage does, Test doesn't)
- Replace placeholder Compose actions with real connector actions using the captured connection format
- PATCH back — only replace `actions`, NEVER overwrite `triggers`

## Critical Rules

### Never overwrite the trigger
```powershell
# CORRECT — only replace actions
$cd.properties.definition.actions = $newDef.properties.definition.actions

# WRONG — destroys user's manually-configured trigger
$cd.properties.definition.triggers = $newDef.properties.definition.triggers
```

### Handle "ActiveUnpublished" state
If PATCH returns error code `0x80040203` ("ActiveUnpublished"), the flow has pending unsaved changes in the designer. User must either Save or Discard in the designer before API can update.

### Deactivate before PATCH, reactivate after
```powershell
# Deactivate
PATCH workflows(id) { statecode: 0, statuscode: 1 }
# Update definition
PATCH workflows(id) { clientdata: "..." }
# Reactivate
PATCH workflows(id) { statecode: 1, statuscode: 2 }
```

### Dynamic table names require Condition branches
Power Automate Dataverse connector does NOT allow expressions for `entityName`. Always use a Condition:
```json
{
  "type": "If",
  "expression": { "not": { "equals": ["@triggerOutputs()?['body/_dcfg_contract_id_value']", null] } },
  "actions": {
    "Get_Contract": { "parameters": { "entityName": "dcfg_contracts", "recordId": "..." } }
  },
  "else": {
    "actions": {
      "Get_MSA": { "parameters": { "entityName": "dcfg_msas", "recordId": "..." } }
    }
  }
}
```

### Environment-specific connection formats
- **Stage:** Uses `connectionName` in host block + `authentication: "@parameters('$authentication')"` on actions
- **Test:** Uses `connectionReferenceName` in host block, NO `authentication` property on actions
- Always read from existing flow before building — never assume format

## DCFG Flow Trigger Pattern (Current Architecture)

### OLD (Deprecated): HTTP trigger + callFlow()
```
SPA → callFlow('dcfg_flow_docgen_url', payload) → HTTP POST to flow trigger URL
```
Problems: stale URLs, env-specific URLs, URL rotation on flow save, connection timeouts

### NEW (Current): Dataverse transaction table
```
SPA → createDocumentRequest({ contractId, templateId, requestedBy }) → writes dcfg_document_requests row
Flow → triggers on "When a row is added" to dcfg_document_requests
Flow → reads lookups from trigger row (contract, template, customer, MSA)
Flow → updates request status: Pending → Processing → Complete/Failed
```

### Trigger configuration
- Table: dcfg_document_requests (display: Document Requests)
- Scope: Organization
- Filter rows:
  - DocGen: `dcfg_request_type eq 100000000 and dcfg_status eq 100000000`
  - Email: `dcfg_request_type eq 100000001 and dcfg_status eq 100000000`
  - CertUpload: `dcfg_request_type eq 100000002 and dcfg_status eq 100000000`

### Status lifecycle (flow updates these)
```
Set_Status_Processing → dcfg_status = 100000001
...do work...
Update_Request_Complete → dcfg_status = 100000002, dcfg_output_file_url, dcfg_completed_at
— or —
Update_Request_Failed → dcfg_status = 100000003, dcfg_error_message, dcfg_completed_at
```
