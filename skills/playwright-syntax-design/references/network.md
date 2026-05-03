# Network — Interception, Mocking, and API Verification

## Intercepting Requests

### Wait for a Specific Response
```typescript
// Start listening BEFORE the action that triggers it
const responsePromise = page.waitForResponse(
  resp => resp.url().includes('/api/data/v9.2/dcfg_contracts') && resp.status() === 200
);
await page.getByRole('button', { name: 'Save' }).click();
const response = await responsePromise;

// Inspect the response
const data = await response.json();
expect(data.dcfg_contractid).toBeDefined();
```

### Wait for Any Network Activity to Settle
```typescript
await page.waitForLoadState('networkidle');
// All pending requests have completed
```
Use after navigation or bulk data loads. Don't use as a replacement for specific response waits.

---

## Mocking API Responses

### Route Interception (Mock Dataverse)
```typescript
// Mock a Dataverse query response
await page.route('**/api/data/v9.2/dcfg_customers**', async route => {
  await route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({
      value: [
        { dcfg_customerid: '1111', dcfg_name: 'Test Customer' },
        { dcfg_customerid: '2222', dcfg_name: 'Another Customer' },
      ]
    }),
  });
});

await page.goto('/customers');
await expect(page.getByText('Test Customer')).toBeVisible();
```

### Selective Mocking (Pass Through + Override)
```typescript
// Let most requests pass, only mock the template lookup
await page.route('**/dcfg_document_templates**', async route => {
  await route.fulfill({
    status: 200,
    body: JSON.stringify({
      value: [{
        dcfg_document_templateid: 'fake-id',
        dcfg_name: 'Bancroft Contract v1',
        dcfg_is_active: true,
        dcfg_contract_family: 100000000,
        dcfg_document_type: 100000000,
      }]
    }),
  });
});
```

### Simulate Errors
```typescript
// Test error handling by returning a 500
await page.route('**/api/data/v9.2/dcfg_contracts**', async route => {
  await route.fulfill({ status: 500, body: 'Internal Server Error' });
});

await page.getByRole('button', { name: 'Save' }).click();
await expect(page.getByText('An error occurred')).toBeVisible();
```

### Simulate Slow Network
```typescript
// Delay response by 5 seconds
await page.route('**/api/data/v9.2/**', async route => {
  await new Promise(resolve => setTimeout(resolve, 5000));
  await route.continue();
});
```

---

## Abort Unwanted Requests

Speed up tests by blocking non-essential resources:
```typescript
await page.route('**/*.{png,jpg,jpeg,svg,gif}', route => route.abort());
await page.route('**/analytics/**', route => route.abort());
await page.route('**/telemetry/**', route => route.abort());
```

---

## Direct API Calls (Backend Verification)

Use `request` fixture or `APIRequestContext` to verify Dataverse state without the UI:

```typescript
import { test, expect } from '@playwright/test';

test('contract creation writes to Dataverse', async ({ page, request }) => {
  // Create contract via UI
  await page.goto('/contracts/new');
  // ... fill fields, click save ...

  // Verify directly via Dataverse API
  const resp = await request.get(
    `${process.env.DCFG_DATAVERSE_URL}/api/data/v9.2/dcfg_contracts?$filter=dcfg_name eq 'Test Contract'&$select=dcfg_status,dcfg_contract_fee`,
    {
      headers: {
        'Authorization': `Bearer ${await getToken()}`,
        'OData-Version': '4.0',
        'Accept': 'application/json',
      }
    }
  );

  const data = await resp.json();
  expect(data.value).toHaveLength(1);
  expect(data.value[0].dcfg_status).toBe(100000000); // Draft
});
```

---

## Monitoring Console Errors

Catch JavaScript errors during tests:
```typescript
const consoleErrors: string[] = [];

page.on('console', msg => {
  if (msg.type() === 'error') {
    consoleErrors.push(msg.text());
  }
});

// ... run test actions ...

// Assert no unexpected JS errors
expect(consoleErrors.filter(e => !e.includes('expected-known-error'))).toHaveLength(0);
```

---

## Monitoring Failed Network Requests

```typescript
const failedRequests: { url: string; error: string }[] = [];

page.on('requestfailed', request => {
  failedRequests.push({
    url: request.url(),
    error: request.failure()?.errorText || 'unknown',
  });
});

// ... run test actions ...

// Assert no unexpected network failures
expect(failedRequests).toHaveLength(0);
```

---

## Power Pages CSRF Token Handling

Power Pages requires an anti-forgery token for POST/PATCH/DELETE. When testing against the live portal, the token is handled by the app's JavaScript. When mocking:

```typescript
// If you need to mock the token endpoint
await page.route('**/__RequestVerificationToken', async route => {
  await route.fulfill({
    status: 200,
    body: 'mock-csrf-token-value',
  });
});
```

In most cases, run tests against the real portal and let the app handle CSRF naturally.
