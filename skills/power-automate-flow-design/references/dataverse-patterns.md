# Dataverse Connector — Common Patterns

## Connector Choice

Use the **Dataverse** connector (not "Common Data Service" — that's legacy). Action names:
- List rows
- Get a row by ID
- Add a new row
- Update a row
- Delete a row
- Perform a bound/unbound action

---

## List Rows with OData Filter

### Filter syntax
```
dcfg_is_active eq true
dcfg_status eq 100000000
dcfg_name eq 'Bancroft'
_dcfg_customer_id_value eq 'guid-here'
dcfg_contract_fee gt 10000
```

### Combining filters
```
dcfg_is_active eq true and dcfg_contract_family eq 100000000
dcfg_status eq 100000000 or dcfg_status eq 100000001
```

### Select columns (reduce payload)
```
dcfg_name,dcfg_status,dcfg_contract_fee,dcfg_contractid
```

### Expand lookups
```
dcfg_customer_id($select=dcfg_name)
```

### Order by
```
dcfg_created_on desc
```

### Top (limit results)
Set Row count: `1` for "get the first matching row" pattern.

---

## Lookup Binding (Create/Update)

When setting a lookup field, use the OData bind syntax in an **untyped** action or HTTP request:

```json
"dcfg_customer_id@odata.bind": "/dcfg_customers(guid)"
"dcfg_msa_id@odata.bind": "/dcfg_msas(guid)"
"dcfg_template_id@odata.bind": "/dcfg_document_templates(guid)"
```

In the standard Dataverse connector, lookup fields accept the GUID directly (the connector adds the bind syntax). But in HTTP actions against the Web API, you MUST use the full bind syntax.

---

## Picklist (Choice) Values

Picklist fields use integer values, not labels:

### dcfg_contract.dcfg_status
| Value | Label |
|---|---|
| 100000000 | Draft |
| 100000001 | Generated |
| 100000002 | Sent |
| 100000003 | Signed/Received |
| 100000004 | Closed |
| 100000005 | Void |
| 100000006 | Declined |

### dcfg_audit_log.dcfg_action_type
| Value | Label |
|---|---|
| 100000000 | Generated |
| 100000001 | Sent |
| 100000002 | Signed |
| 100000003 | Void |
| 100000004 | Declined |
| 100000005 | Override |
| 100000006 | Status Changed |
| 100000007 | Template Activated |
| 100000008 | Template Deactivated |
| 100000009 | Data Updated |
| 100000010 | Other |

### dcfg_document_template.dcfg_contract_family
| Value | Label |
|---|---|
| 100000000 | Bancroft |
| 100000001 | Decades |

### dcfg_document_template.dcfg_document_type
| Value | Label |
|---|---|
| 100000000 | Contract |
| 100000001 | Amendment |
| 100000002 | MSA |
| 100000003 | Cover Sheet |

Always use integers in expressions:
```
equals(int(body('Get_Contract')?['dcfg_status']), 100000003)
```

---

## Audit Log Pattern (INSERT Only)

`dcfg_audit_logs` is immutable. Only Create, never Update or Delete.

```json
{
  "dcfg_target_table": "dcfg_contract",
  "dcfg_target_record_id": "@{variables('contractId')}",
  "dcfg_action_type": 100000000,
  "dcfg_performed_by": "@{triggerOutputs()?['headers']?['x-ms-user-email-encoded']}",
  "dcfg_performed_at": "@{utcNow()}",
  "dcfg_new_value": "Document generated successfully",
  "dcfg_reason": "@{coalesce(variables('overrideReason'), '')}"
}
```

For flow-initiated actions, use the flow display name as `dcfg_performed_by`:
```
workflow()?['tags']?['flowDisplayName']
```

---

## Concurrency and Throttling

### Apply to Each with Dataverse
Set concurrency to **1** (sequential) for:
- Any loop that writes to the same table
- Budget calculations (sum patterns)
- Sequential numbering

### Batch Alternatives
For bulk operations (50+ records), consider:
- ChangeSets via HTTP with Dataverse Web API $batch endpoint
- Power Automate Desktop for very large datasets

### Sum Pattern (No Self-Referencing Variables)
```
Initialize: varRunningTotal (Float) = 0

Apply to Each (concurrency: 1):
  Compose: Add_Amount
    Expression: add(variables('varRunningTotal'), float(items('Apply_to_each')?['dcfg_contract_fee']))
  Set Variable: varRunningTotal = outputs('Add_Amount')
```

---

## Common Expression Patterns for DCFG

### Get first active template
```
Filter: dcfg_is_active eq true and dcfg_contract_family eq @{variables('familyInt')} and dcfg_document_type eq @{variables('typeInt')}
Row count: 1
```
Then: `first(body('List_Templates')?['value'])`

### Contract number formatting
```
// Pad to 4 digits: 42 → "0042"
concat(
  substring('0000', 0, sub(4, length(string(variables('seqNumber'))))),
  string(variables('seqNumber'))
)
```

### Budget remaining calculation
```
sub(
  float(body('Get_MSA')?['dcfg_budget_total']),
  float(body('Get_MSA')?['dcfg_budget_committed'])
)
```

### MSA_DATE_LONG formatting
```
// "13th day of March, 2026"
concat(
  string(dayOfMonth(variables('msaDate'))),
  variables('ordinalSuffix'),
  ' day of ',
  formatDateTime(variables('msaDate'), 'MMMM'),
  ', ',
  formatDateTime(variables('msaDate'), 'yyyy')
)
```
