# UpKeep CMMS API — HTTP Connector Patterns

## Overview

UpKeep provides a REST API at `https://api.onupkeep.com/api/v2/`. API access requires an **Enterprise** or **Business Plus** plan. Use Power Automate's HTTP connector — there is no native UpKeep connector.

## Authentication

UpKeep uses session tokens obtained via username/password authentication.

### Getting a Session Token
**POST** `https://api.onupkeep.com/api/v2/auth`

Body:
```json
{
  "email": "@{parameters('upkeep_api_email')}",
  "password": "@{parameters('upkeep_api_password')}"
}
```

Response includes:
```json
{
  "success": true,
  "result": {
    "sessionToken": "abc123...",
    "user": { "id": "...", "email": "..." }
  }
}
```

**Best practice:** Create a dedicated API user (api@yourcompany.com) with Admin role. Store credentials in environment variables. Mark HTTP actions as Secure Inputs/Outputs.

### Using the Token
All subsequent requests include:
```
Headers:
  Session-Token: @{body('Parse_Auth_Response')?['result']?['sessionToken']}
  Content-Type: application/json
```

### Token Management
Session tokens expire. For scheduled flows:
1. Authenticate at the start of every flow run
2. Store the token in a variable
3. Use it for all subsequent API calls in that run
4. Don't cache tokens across runs

---

## Common Endpoints

### Locations

**List Locations:**
GET `https://api.onupkeep.com/api/v2/locations`

**Create Location:**
POST `https://api.onupkeep.com/api/v2/locations`
```json
{
  "name": "@{body('Get_Property')?['dcfg_name']}",
  "address": "@{body('Get_Property')?['dcfg_address']}",
  "city": "@{body('Get_Property')?['dcfg_city']}",
  "state": "@{body('Get_Property')?['dcfg_state']}",
  "zipCode": "@{body('Get_Property')?['dcfg_zip']}",
  "parentId": "@{coalesce(variables('parentUpKeepId'), null)}"
}
```

Response: `result.id` is the UpKeep Location ID → write back to `dcfg_property.dcfg_upkeep_location_id`

**Get Location by ID:**
GET `https://api.onupkeep.com/api/v2/locations/@{variables('locationId')}`

### Location Hierarchy
UpKeep supports up to 6 levels of nesting (Enterprise/Business Plus).
- Level 0: Root locations (no parent)
- Level 1-5: Child locations with `parentId`

### Work Orders

**List Work Orders:**
GET `https://api.onupkeep.com/api/v2/work-orders`

Query params: `?status=open&limit=50&offset=0`

**Create Work Order:**
POST `https://api.onupkeep.com/api/v2/work-orders`
```json
{
  "title": "@{variables('woTitle')}",
  "description": "@{variables('woDescription')}",
  "priority": @{variables('priority')},
  "location": "@{variables('upkeepLocationId')}",
  "asset": "@{coalesce(variables('upkeepAssetId'), null)}",
  "category": "@{variables('category')}"
}
```

Priority values: 0 = None, 1 = Low, 2 = Medium, 3 = High

**Update Work Order:**
PATCH `https://api.onupkeep.com/api/v2/work-orders/@{variables('workOrderId')}`

**Get Work Order:**
GET `https://api.onupkeep.com/api/v2/work-orders/@{variables('workOrderId')}`

### Assets

**List Assets:**
GET `https://api.onupkeep.com/api/v2/assets`

**Create Asset:**
POST `https://api.onupkeep.com/api/v2/assets`
```json
{
  "name": "@{variables('assetName')}",
  "location": "@{variables('upkeepLocationId')}",
  "model": "@{coalesce(variables('model'), '')}",
  "serialNumber": "@{coalesce(variables('serial'), '')}",
  "category": "@{variables('category')}"
}
```

**Get Asset:**
GET `https://api.onupkeep.com/api/v2/assets/@{variables('assetId')}`

### Preventive Maintenance

**List PM Triggers:**
GET `https://api.onupkeep.com/api/v2/preventive-maintenance`

**Create PM Trigger:**
POST `https://api.onupkeep.com/api/v2/preventive-maintenance`

Note: The old `/preventative-maintenance` endpoints are sunset. Use `/preventive-maintenance` (spelling difference).

---

## Pagination

UpKeep uses offset-based pagination:
```
GET /api/v2/work-orders?limit=50&offset=0
GET /api/v2/work-orders?limit=50&offset=50
GET /api/v2/work-orders?limit=50&offset=100
```

Use a Do Until loop:
- Track `offset` variable, increment by `limit` each iteration
- Stop when response `result` array length < `limit`

---

## DCFG Integration Pattern: Location Push

The DCFG system pushes location data to UpKeep:

```
1. Get property record from Dataverse (dcfg_property)
2. Check if dcfg_upkeep_location_id is empty
   → Not empty: PATCH existing location
   → Empty: POST new location
3. Parse response, extract result.id
4. Update dcfg_property.dcfg_upkeep_location_id with UpKeep ID
5. Write audit log
```

Guard: if `dcfg_upkeep_location_id` already set, the field is read-only (do not overwrite).

---

## Error Handling

### Common Errors
| Status | Meaning | Action |
|---|---|---|
| 200 | Success | Continue |
| 400 | Bad request (validation) | Log error details, don't retry |
| 401 | Session expired | Re-authenticate and retry once |
| 403 | Plan doesn't include API | Cannot proceed — requires plan upgrade |
| 404 | Record not found | Handle gracefully |
| 429 | Rate limited | Retry with backoff |
| 500 | Server error | Retry with exponential backoff |

### Session Expiry Recovery
```
Condition: equals(outputs('HTTP_UpKeep')?['statusCode'], 401)
  → Yes: Re-authenticate (POST /auth), get new token, retry original request
  → No: Continue
```

### Retry Policy
```json
"retryPolicy": {
  "type": "exponential",
  "count": 3,
  "interval": "PT10S",
  "maximumInterval": "PT5M"
}
```

---

## API Versioning

UpKeep versions their API. Set the version header to lock to a known version:
```
upkeep-version: 2023-01-01
```

Without this header, you get the default version set in your account. Pin it to avoid breaking changes.
