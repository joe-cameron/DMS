# Assertions — Verifying Application Behavior

## The #1 Rule: Always Await Expect

```typescript
// WRONG — evaluates immediately, no retry, silent false pass
expect(await page.getByText('Success').isVisible()).toBe(true);

// RIGHT — web-first assertion, auto-retries until timeout
await expect(page.getByText('Success')).toBeVisible();
```

Every `expect()` with a locator MUST have `await` before it. This is the single most common bug in AI-generated Playwright tests.

---

## Web-First Assertions (Use These)

These retry automatically until the condition is met or timeout:

```typescript
// Visibility
await expect(locator).toBeVisible();
await expect(locator).toBeHidden();
await expect(locator).toBeAttached();
await expect(locator).not.toBeAttached();

// Text content
await expect(locator).toHaveText('Exact text');
await expect(locator).toHaveText(/partial regex/);
await expect(locator).toContainText('substring');

// Input values
await expect(locator).toHaveValue('filled value');
await expect(locator).toBeEmpty();

// State
await expect(locator).toBeEnabled();
await expect(locator).toBeDisabled();
await expect(locator).toBeChecked();
await expect(locator).toBeFocused();

// Count
await expect(locator).toHaveCount(5);

// CSS / attributes
await expect(locator).toHaveClass(/active/);
await expect(locator).toHaveAttribute('href', '/dashboard');
await expect(locator).toHaveCSS('color', 'rgb(0, 0, 255)');

// Page-level
await expect(page).toHaveURL(/.*\/dashboard/);
await expect(page).toHaveTitle(/Dashboard/);
```

---

## Soft Assertions (Multi-Check Without Stopping)

When verifying multiple things on one screen, use soft assertions so ALL failures are reported, not just the first:

```typescript
await expect.soft(page.getByTestId('customer-name')).toHaveText('Bancroft');
await expect.soft(page.getByTestId('contract-status')).toHaveText('Draft');
await expect.soft(page.getByTestId('contract-fee')).toContainText('$12,500');
await expect.soft(page.getByTestId('vendor-name')).toHaveText('ABC Plumbing');
// Test continues through all checks, reports all failures at end
```

---

## Negative Assertions

```typescript
// Element should NOT be visible
await expect(page.getByText('Error')).not.toBeVisible();

// Element should NOT exist in DOM
await expect(page.getByTestId('deleted-item')).not.toBeAttached();

// Button should be disabled
await expect(page.getByRole('button', { name: 'Generate' })).toBeDisabled();
```

---

## Assertion Timeouts

Default timeout is 5 seconds. Override per-assertion for slow operations:

```typescript
// Document generation might take longer
await expect(page.getByText('Document generated')).toBeVisible({ timeout: 30000 });
```

Or set globally in config:
```typescript
// playwright.config.ts
expect: {
  timeout: 10000, // 10 seconds for all assertions
}
```

---

## API Response Assertions

Verify network responses alongside UI:

```typescript
const responsePromise = page.waitForResponse(
  resp => resp.url().includes('/api/data/v9.2/dcfg_contracts') && resp.status() === 200
);
await page.getByRole('button', { name: 'Save' }).click();
const response = await responsePromise;

// Verify response body
const body = await response.json();
expect(body.dcfg_status).toBe(100000000); // Draft
```

---

## Backend Verification (Dataverse)

After UI actions, verify the database directly:

```typescript
// Create a separate API context for backend checks
const apiContext = await request.newContext({
  baseURL: 'https://org0c17e98d.crm.dynamics.com',
  extraHTTPHeaders: {
    'Authorization': `Bearer ${accessToken}`,
    'OData-Version': '4.0',
  }
});

const resp = await apiContext.get(`/api/data/v9.2/dcfg_contracts(${contractId})?$select=dcfg_status`);
const data = await resp.json();
expect(data.dcfg_status).toBe(100000002); // Generated
```

---

## Anti-Patterns

```typescript
// WRONG: Manual boolean check — no retry
const isVisible = await page.getByText('Done').isVisible();
expect(isVisible).toBeTruthy();

// WRONG: Checking .count() without retry
const count = await page.getByRole('row').count();
expect(count).toBe(5);

// RIGHT versions:
await expect(page.getByText('Done')).toBeVisible();
await expect(page.getByRole('row')).toHaveCount(5);
```
