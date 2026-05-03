# Fail-Safe Flow Design — Try-Catch-Finally, Logging, and Recovery

## The Mandatory Pattern: Try-Catch-Finally

Every production flow uses this structure. No exceptions.

```
[Initialize Variables]        ← Top level, before all Scopes
    ↓
[Scope: Try]                  ← All business logic goes here
    ↓ (on failure)
[Scope: Catch]                ← Run After: has failed, has timed out
    ↓ (always)
[Scope: Finally]              ← Run After: is successful, has been skipped
    ↓
[Terminate]                   ← Set status based on varFlowFailed
```

### Step 1: Initialize Variables (Before Any Scope)
```
Initialize variable: varFlowFailed (Boolean) = false
Initialize variable: varErrorMessage (String) = ''
Initialize variable: varFailedAction (String) = ''
```

### Step 2: Try Scope
Contains ALL business logic. If any action inside fails, the entire Scope fails.

### Step 3: Catch Scope
Configure Run After → check ONLY: "has failed", "has timed out"

Actions inside Catch:
1. **Set varFlowFailed** = `true`

2. **Compose: Get Workflow Details**
   ```
   workflow()
   ```

3. **Filter Array: Get Failed Actions**
   From: `result('Try')`
   Filter: `or(equals(item()?['Status'], 'Failed'), equals(item()?['Status'], 'TimedOut'))`

4. **Set varErrorMessage** (first failed action's error):
   ```
   first(body('Filter_Failed_Actions'))?['error']?['message']
   ```

5. **Set varFailedAction**:
   ```
   first(body('Filter_Failed_Actions'))?['name']
   ```

6. **Create Audit Log Record** (Dataverse: dcfg_audit_logs):
   - dcfg_target_table: `'flow_run'`
   - dcfg_action_type: `100000010` (Other)
   - dcfg_performed_by: flow name
   - dcfg_performed_at: `utcNow()`
   - dcfg_new_value: error message
   - dcfg_reason: concat of failed action + error
   - dcfg_related_contract_id: source record ID if available

7. **Send Failure Notification** (email or Teams):
   Include: flow name, failed action, error message, link to run history.

   Flow run URL expression:
   ```
   concat(
     'https://make.powerautomate.com/environments/',
     outputs('Compose_Get_Workflow_Details')?['tags']?['environmentName'],
     '/flows/',
     outputs('Compose_Get_Workflow_Details')?['name'],
     '/runs/',
     outputs('Compose_Get_Workflow_Details')?['run']?['name']
   )
   ```

### Step 4: Finally Scope
Configure Run After → check: "is successful", "has been skipped"

This runs whether Try succeeded or Catch ran. Use it for:
- Setting final status on source records
- Cleanup operations
- Conditional Terminate

### Step 5: Terminate
```
Condition: varFlowFailed equals true
  → Yes: Terminate (Failed) with message: varErrorMessage
  → No:  Terminate (Succeeded)
```

**CRITICAL:** Without the Terminate action, a flow that fails inside Try but succeeds in Catch will show as "Succeeded" in run history. The Terminate action corrects this.

---

## Retry Policies

### Default Retry (for HTTP actions)
```json
{
  "retryPolicy": {
    "type": "exponential",
    "count": 3,
    "interval": "PT10S",
    "maximumInterval": "PT1H"
  }
}
```

### No Retry (for actions that should fail fast)
```json
{
  "retryPolicy": {
    "type": "none"
  }
}
```

### When to Use Which
- **Exponential retry:** HTTP calls to external APIs (HubSpot, UpKeep, SharePoint)
- **Fixed retry:** Dataverse operations that might hit throttling
- **No retry:** Validation checks, Terminate actions, audit log writes

---

## Guard Patterns

### Auth Guard (HTTP-triggered flows)
First action after trigger — reject unauthenticated callers:
```
Condition: empty(triggerOutputs()?['headers']?['x-ms-user-email-encoded'])
  → Yes: Terminate (Failed, 'Unauthenticated caller rejected')
  → No:  Continue
```

### Data Guard (before processing)
```
Condition: empty(triggerBody()?['source_record_id'])
  → Yes: Terminate (Failed, 'Missing required field: source_record_id')
  → No:  Continue
```

### Template Guard (before document generation)
```
Condition: empty(body('Get_Template')?['value'])
  → Yes: Write audit log ('Template not found'), Terminate (Failed)
  → No:  Continue with first(body('Get_Template')?['value'])
```

---

## Parallel Branch Error Handling

When using Parallel branches inside Try:
- If ANY branch fails, the Try Scope fails
- The Catch scope receives `result('Try')` with ALL branch results
- Filter for failed actions across all branches

For independent operations that should continue even if one fails:
```
[Scope: Try_Branch_A]  ← own try-catch inside
[Scope: Try_Branch_B]  ← own try-catch inside
```
Each inner scope handles its own errors. The outer flow continues.

---

## Throttling and Concurrency

### Dataverse Throttling
Dataverse limits: ~6000 requests per 5 minutes per user. Flows hitting Apply to Each with Dataverse actions can throttle.

Mitigation:
- Set Apply to Each concurrency to 1 (sequential) for Dataverse writes
- Use batch operations where available
- Add `Delay` (PT1S) between iterations for bulk operations

### SharePoint Throttling
SharePoint returns 429 when throttled. The exponential retry policy handles this automatically if configured.

### Power Automate Action Limits
- 100,000 actions per flow run (lifetime of a single run)
- 256 nested actions depth
- 500 Apply to Each iterations before needing pagination

---

## Monitoring and Alerting

### Flow Failure Email Template
```
Subject: FLOW FAILED: @{workflow()?['tags']?['flowDisplayName']}

Flow: @{workflow()?['tags']?['flowDisplayName']}
Environment: @{workflow()?['tags']?['environmentName']}
Run ID: @{workflow()?['run']?['name']}
Failed Action: @{variables('varFailedAction')}
Error: @{variables('varErrorMessage')}
Time: @{utcNow()}

View Run: [link to run URL]
```

### Structured Error Logging to Dataverse
For every flow failure, write to `dcfg_audit_logs` with:
- `dcfg_target_table`: flow logical name
- `dcfg_target_record_id`: source record GUID (if applicable)
- `dcfg_action_type`: 100000010 (Other)
- `dcfg_performed_by`: flow display name
- `dcfg_performed_at`: utcNow()
- `dcfg_new_value`: full error details (JSON string of failed actions)
- `dcfg_reason`: human-readable summary
