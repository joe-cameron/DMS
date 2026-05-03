# HubSpot API — HTTP Connector Patterns

## Overview

There is no reliable first-party HubSpot connector for Power Automate. The built-in connector has known bugs (type mismatches on Search responses). Use the **HTTP** premium connector with HubSpot's REST API v3 directly.

## Authentication

HubSpot uses Private App access tokens (Bearer tokens). API keys are sunset.

### Setup
1. In HubSpot → Settings → Integrations → Private Apps → Create
2. Grant scopes needed (contacts, companies, deals, tickets as required)
3. Copy the access token
4. Store in a Power Automate **environment variable** (not hardcoded)
5. Mark the HTTP action as **Secure Inputs** and **Secure Outputs**

### HTTP Action Headers
```
Authorization: Bearer @{variables('hubspotToken')}
Content-Type: application/json
```

Or from environment variable:
```
Authorization: concat('Bearer ', parameters('hubspot_api_token'))
```

---

## Common Endpoints

### Base URL
`https://api.hubapi.com`

### Search Contacts by Email
**POST** `https://api.hubapi.com/crm/v3/objects/contacts/search`

Body:
```json
{
  "filterGroups": [
    {
      "filters": [
        {
          "propertyName": "email",
          "operator": "EQ",
          "value": "@{variables('emailAddress')}"
        }
      ]
    }
  ],
  "properties": ["email", "firstname", "lastname", "company", "phone"],
  "limit": 1
}
```

### Get Contact by ID
**GET** `https://api.hubapi.com/crm/v3/objects/contacts/@{variables('contactId')}?properties=email,firstname,lastname`

### Create Contact
**POST** `https://api.hubapi.com/crm/v3/objects/contacts`

Body:
```json
{
  "properties": {
    "email": "@{variables('email')}",
    "firstname": "@{variables('firstName')}",
    "lastname": "@{variables('lastName')}",
    "company": "@{variables('company')}",
    "phone": "@{variables('phone')}"
  }
}
```

### Update Contact
**PATCH** `https://api.hubapi.com/crm/v3/objects/contacts/@{variables('contactId')}`

Body:
```json
{
  "properties": {
    "lifecycle_stage": "customer",
    "company": "@{variables('companyName')}"
  }
}
```

### Search Companies
**POST** `https://api.hubapi.com/crm/v3/objects/companies/search`

Body:
```json
{
  "filterGroups": [
    {
      "filters": [
        {
          "propertyName": "name",
          "operator": "CONTAINS_TOKEN",
          "value": "@{variables('companyName')}"
        }
      ]
    }
  ],
  "properties": ["name", "domain", "city", "state", "industry"],
  "limit": 10
}
```

### Create Deal
**POST** `https://api.hubapi.com/crm/v3/objects/deals`

Body:
```json
{
  "properties": {
    "dealname": "@{variables('dealName')}",
    "amount": "@{string(variables('amount'))}",
    "pipeline": "default",
    "dealstage": "appointmentscheduled"
  }
}
```

---

## Webhook Integration (HubSpot → Power Automate)

HubSpot workflows can trigger Power Automate flows via webhook:

1. Create flow with "When an HTTP request is received" trigger
2. Copy the HTTP POST URL after saving
3. In HubSpot Workflow → Add action → "Send a webhook"
4. Paste the Power Automate URL
5. Configure HubSpot to send contact/deal properties in the payload

Define the JSON schema in the trigger to get typed dynamic content.

---

## Pagination

HubSpot API returns max 100 results per request. For larger datasets:

```
// First request
POST /crm/v3/objects/contacts/search
{ "limit": 100 }

// Response includes:
// "paging": { "next": { "after": "12345" } }

// Subsequent requests:
POST /crm/v3/objects/contacts/search
{ "limit": 100, "after": "12345" }
```

Use a Do Until loop:
- Condition: `empty(body('Parse_Response')?['paging']?['next']?['after'])`
- Inside loop: HTTP call with `after` parameter, append results to array variable

---

## Error Handling for HubSpot

### Rate Limits
HubSpot enforces rate limits (varies by plan, typically 100-150 requests/10 seconds for Private Apps). Configure retry:
```json
"retryPolicy": {
  "type": "exponential",
  "count": 4,
  "interval": "PT5S",
  "maximumInterval": "PT2M"
}
```

### Common Error Responses
| Status | Meaning | Action |
|---|---|---|
| 200 | Success | Continue |
| 401 | Token expired/invalid | Check Private App, regenerate token |
| 404 | Record not found | Handle gracefully — record may have been deleted |
| 409 | Conflict (duplicate) | Search for existing record, update instead of create |
| 429 | Rate limited | Retry policy handles this automatically |
| 500 | HubSpot server error | Retry policy handles this |

### Guard Pattern
```
Condition: equals(outputs('HTTP_HubSpot')?['statusCode'], 200)
  → No: Log error, set varFlowFailed = true
  → Yes: Parse JSON and continue
```
