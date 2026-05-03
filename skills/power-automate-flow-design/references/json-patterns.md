# JSON Patterns — Parse JSON, HTTP Bodies, and Schema Design

## Parse JSON — Always After HTTP

Every HTTP response MUST be followed by Parse JSON. This gives you typed dynamic content instead of raw expressions.

### Generating a Schema
1. Run the flow once with sample data
2. Copy the response body from run history
3. In Parse JSON, click "Generate from sample" and paste
4. Review and fix: ensure integers are `integer` not `string`, nullables have `"type": ["string", "null"]`

### Common Schema Patterns

**Single Dataverse record:**
```json
{
  "type": "object",
  "properties": {
    "dcfg_contractid": { "type": "string" },
    "dcfg_name": { "type": ["string", "null"] },
    "dcfg_status": { "type": "integer" },
    "dcfg_contract_fee": { "type": ["number", "null"] },
    "dcfg_is_active": { "type": "boolean" },
    "_dcfg_customer_id_value": { "type": ["string", "null"] }
  }
}
```

**Dataverse list response (OData):**
```json
{
  "type": "object",
  "properties": {
    "@odata.context": { "type": "string" },
    "value": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "dcfg_contractid": { "type": "string" },
          "dcfg_name": { "type": ["string", "null"] },
          "dcfg_status": { "type": "integer" }
        }
      }
    }
  }
}
```

**HubSpot search response:**
```json
{
  "type": "object",
  "properties": {
    "total": { "type": "integer" },
    "results": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "properties": {
            "type": "object",
            "properties": {
              "email": { "type": ["string", "null"] },
              "firstname": { "type": ["string", "null"] },
              "lastname": { "type": ["string", "null"] }
            }
          },
          "createdAt": { "type": "string" },
          "updatedAt": { "type": "string" }
        }
      }
    }
  }
}
```

**UpKeep work order response:**
```json
{
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "result": {
      "type": "object",
      "properties": {
        "id": { "type": "string" },
        "title": { "type": ["string", "null"] },
        "description": { "type": ["string", "null"] },
        "status": { "type": "string" },
        "priority": { "type": "integer" },
        "asset": { "type": ["string", "null"] },
        "location": { "type": ["string", "null"] },
        "createdAt": { "type": "string" },
        "updatedAt": { "type": "string" }
      }
    }
  }
}
```

---

## Building HTTP Request Bodies

### Compose → HTTP Pattern
Build the body in a Compose action, then reference it in HTTP:

```json
// Compose action: Build_Request_Body
{
  "filterGroups": [
    {
      "filters": [
        {
          "propertyName": "email",
          "operator": "EQ",
          "value": "@{variables('contactEmail')}"
        }
      ]
    }
  ],
  "properties": ["email", "firstname", "lastname", "company"]
}
```

Then in HTTP action body: `@{outputs('Build_Request_Body')}`

### Dynamic JSON Construction
Use `json()` with `concat()` for complex dynamic bodies:
```
json(concat(
  '{"title":"', replace(variables('title'), '"', '\\"'), '",',
  '"description":"', replace(variables('desc'), '"', '\\"'), '",',
  '"priority":', string(variables('priority')), '}'
))
```

**WARNING:** Always escape quotes in user-provided strings with `replace(value, '"', '\\"')` to prevent JSON injection.

### OData Filter Expressions in URLs
```
// Single filter
concat(
  '/api/data/v9.2/dcfg_contracts?$filter=',
  'dcfg_status eq ', string(variables('statusInt')),
  '&$select=dcfg_name,dcfg_contract_fee'
)

// Multiple filters
concat(
  '/api/data/v9.2/dcfg_document_templates?$filter=',
  'dcfg_is_active eq true',
  ' and dcfg_contract_family eq ', string(variables('familyInt')),
  ' and dcfg_document_type eq ', string(variables('typeInt')),
  '&$top=1'
)

// Lookup bind (for PATCH/POST)
{
  "dcfg_customer_id@odata.bind": "/dcfg_customers(@{variables('customerId')})"
}
```

---

## Dataverse OData Bind Syntax

For lookup fields in Create/Update:
```json
{
  "dcfg_name": "New Contract",
  "dcfg_contract_fee": 12500.00,
  "dcfg_status": 100000000,
  "dcfg_customer_id@odata.bind": "/dcfg_customers(guid-here)",
  "dcfg_msa_id@odata.bind": "/dcfg_msas(guid-here)",
  "dcfg_property_id@odata.bind": "/dcfg_propertys(guid-here)"
}
```

**Common mistake:** Using `dcfg_customer_id` instead of `dcfg_customer_id@odata.bind`. The `@odata.bind` suffix is REQUIRED for lookup fields.

---

## Schema Gotchas

| Problem | Symptom | Fix |
|---|---|---|
| Field sometimes null | Parse JSON fails | Use `"type": ["string", "null"]` |
| Integer field parsed as string | Comparisons fail | Verify schema says `"type": "integer"` |
| Extra fields in response | No issue (ignored by default) | Leave schema as-is |
| Array might be empty | No issue for Parse JSON | Guard with `if(empty(body('Parse')?['value']))` before Apply to Each |
| Nested object might be null | Runtime error accessing child | Add null check: `if(not(empty(body('Parse')?['nested'])), ...)` |
