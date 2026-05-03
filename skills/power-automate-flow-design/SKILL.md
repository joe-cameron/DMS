---
name: power-automate-flow-design
description: Write fail-safe Power Automate cloud flows with correct expression syntax, proper JSON handling, and robust error handling. ALWAYS use this skill when writing Power Automate expressions, building flow JSON definitions, creating HTTP connector actions for REST APIs (especially HubSpot and UpKeep), designing try-catch-finally error handling with Scope actions, configuring run-after settings, writing Compose expressions, building Parse JSON schemas, or troubleshooting flow failures. Also trigger for any mention of coalesce, formatDateTime, triggerOutputs, result(), workflow(), actions(), Configure Run After, Scope actions, HTTP connector, Bearer token, OData filter, or Dataverse connector expressions. This skill prevents the most common AI-generated flow failures: wrong expression syntax, missing null guards, no error handling, incorrect JSON schemas, and unhandled API error responses.
---

# Power Automate Flow Design Skill

Write production-grade Power Automate cloud flows with correct syntax, fail-safe error handling, and reliable API integrations.

## When You're About to Build a Flow

Before writing any flow definition or expression, read the relevant reference:

| Task | Read First |
|---|---|
| Writing any expression (string, date, math, logic) | `references/expressions.md` |
| Building JSON bodies, Parse JSON schemas | `references/json-patterns.md` |
| Error handling (try-catch-finally, logging) | `references/failsafe-design.md` |
| HubSpot API via HTTP connector | `references/hubspot-api.md` |
| UpKeep CMMS API via HTTP connector | `references/upkeep-api.md` |
| Dataverse connector patterns | `references/dataverse-patterns.md` |
| **DCFG flow operations (READ FIRST)** | **`references/dcfg-flow-operations.md`** |

---

## Critical Rules (Always Apply)

### 1. Every Flow Gets Try-Catch-Finally
No exceptions. Every flow must use the Scope-based try-catch-finally pattern:
- **Try Scope** — all business logic actions
- **Catch Scope** — Configure Run After: "has failed", "has timed out". Filter failed actions, log to audit table, send notification.
- **Finally Scope** — Configure Run After: "is successful", "has been skipped". Cleanup, status update, terminate with correct status.

### 2. Null-Guard Everything
Expressions that access dynamic content MUST handle null:
```
coalesce(triggerBody()?['email'], '')
coalesce(body('Get_Record')?['dcfg_name'], 'UNKNOWN')
```
The `?[]` operator is null-safe property access. The `coalesce()` function provides a fallback. Use BOTH together.

### 3. Never Hardcode Connection References
Use environment variables for URLs, API keys, site paths, and email addresses. Never embed them in expressions or action inputs.

### 4. Type Safety in Expressions
Power Automate expressions are NOT loosely typed. Common traps:
```
// WRONG — comparing string to int
equals(triggerBody()?['status'], 1)

// RIGHT — explicit conversion
equals(int(triggerBody()?['status']), 1)
```

### 5. Variables Cannot Self-Reference
```
// WRONG — causes runtime error
Set Variable: mySum = add(variables('mySum'), items('Apply_to_each')?['amount'])

// RIGHT — use Compose intermediary
Compose: add(variables('runningTotal'), items('Apply_to_each')?['amount'])
Set Variable: runningTotal = outputs('Compose_Sum')
```

### 6. Initialize Variables at Top Level Only
Variables CANNOT be initialized inside Scope, Condition, Switch, or Apply to each. They must be initialized before any branching or looping action.

### 7. Parse JSON After Every HTTP Response
Never access HTTP response properties directly. Always Parse JSON first with a defined schema. This catches schema mismatches at design time instead of runtime.

### 8. HTTP Actions Need Retry Policies
```json
"retryPolicy": {
  "type": "exponential",
  "count": 3,
  "interval": "PT10S",
  "maximumInterval": "PT1H"
}
```
Applies to 408, 429, and 5xx errors. Does NOT retry 4xx (except 408/429).

### 9. Log Before You Fail
Before any Terminate action, write an audit log record with: flow name, run ID, failed action name, error message, timestamp. The audit record survives even if the Terminate action itself fails.

### 10. Auth Tokens in Secure Inputs
Mark any action containing API keys, Bearer tokens, or passwords with "Secure Inputs" and "Secure Outputs" in the action settings. This prevents credentials from appearing in run history.

---

## Expression Quick Reference

```
// String
concat('Hello ', variables('name'))
substring('ABCDEF', 2, 3)                    // 'CDE'
replace('WO-001', 'WO-', '')                 // '001'
toLower(triggerBody()?['email'])
trim(body('Get_Item')?['title'])
split('a,b,c', ',')                          // ['a','b','c']
join(variables('myArray'), ', ')              // 'a, b, c'
if(empty(variables('x')), 'none', variables('x'))

// Date
utcNow()
formatDateTime(utcNow(), 'yyyy-MM-dd')
formatDateTime(utcNow(), 'dd MMM yyyy HH:mm')
addDays(utcNow(), 30)
dateDifference(variables('start'), variables('end'))

// Math
add(1, 2)
sub(10, 3)
mul(5, 4)
div(100, 3)                                  // integer division
float(div(100, 3))                           // float division

// Logic
if(equals(variables('status'), 'Active'), 'Yes', 'No')
and(greater(variables('x'), 0), less(variables('x'), 100))
or(equals(variables('a'), 1), equals(variables('b'), 2))
not(empty(triggerBody()?['name']))

// Type conversion
int('42')
float('3.14')
string(42)
bool('true')
json('{"key":"value"}')
array(variables('singleItem'))

// Null handling
coalesce(triggerBody()?['field'], 'default')
if(empty(body('Get')?['value']), 'missing', body('Get')?['value'])

// Collections
length(body('List_rows')?['value'])
first(body('List_rows')?['value'])
last(body('List_rows')?['value'])
contains(variables('myArray'), 'target')

// Flow metadata
workflow()?['name']                           // flow GUID
workflow()?['run']?['name']                   // run GUID
workflow()?['tags']?['environmentName']        // environment ID
workflow()?['tags']?['flowDisplayName']        // display name
```

---

## Patterns to NEVER Generate

| Anti-Pattern | Why It Fails | Do Instead |
|---|---|---|
| `body('action')['property']` without `?` | Null reference crash | `body('action')?['property']` |
| Initialize Variable inside Scope | Design-time error | Initialize before all Scopes |
| `Set Variable` referencing itself | Runtime error | Use Compose intermediary |
| HTTP without retry policy | Transient failures crash flow | Add exponential retry |
| HTTP without Parse JSON after | Silent data corruption | Always Parse JSON |
| No error handling | Silent failures, no notification | Try-Catch-Finally Scope pattern |
| Hardcoded API keys in expressions | Security risk, visible in run history | Environment variables + Secure Inputs |
| `equals(field, 1)` on string field | Type mismatch, always false | `equals(int(field), 1)` |
| `formatDateTime` on null | Runtime error | `if(empty(date), '', formatDateTime(date, 'fmt'))` |
| Terminate without audit log | No record of what failed | Log first, then Terminate |

---

## Reference Files

For detailed patterns, read the reference files in `references/`. Each covers one topic with copy-paste-ready expressions and JSON.
