# Debugging & Flaky Tests — Finding and Fixing Failures

## Debugging Tools (Use In Order)

### 1. Trace Viewer (Best for CI Failures)
The trace captures every action, network request, DOM snapshot, and console log.

```bash
# Run with trace on
npx playwright test --trace on

# View the HTML report (includes traces)
npx playwright show-report
```

Configure in `playwright.config.ts` to auto-capture on retry:
```typescript
use: {
  trace: 'on-first-retry',  // only captures when a test fails and retries
}
```

The trace viewer shows a timeline. Click any action to see the page state at that moment, network requests, and console output.

### 2. UI Mode (Best for Local Development)
```bash
npx playwright test --ui
```
Interactive mode with time-travel debugging. Watch tests run, step through actions, inspect DOM at any point.

### 3. Debug Mode (Step Through Code)
```bash
npx playwright test --debug
npx playwright test tests/contract.spec.ts:15 --debug  # specific test + line
```
Opens the Playwright Inspector. Step through actions one at a time.

### 4. Headed Mode (Watch It Run)
```bash
npx playwright test --headed
```
See the browser. Useful for "what is actually happening?" moments.

### 5. Pause in Code
```typescript
await page.pause(); // Opens inspector at this point
```
Insert temporarily to halt execution and inspect the live page.

---

## Common Flaky Test Causes and Fixes

### 1. Race Condition: Element Not Ready
**Symptom:** Test passes locally, fails in CI.

```typescript
// FLAKY — element might not be rendered yet
await page.locator('#submit').click();

// STABLE — auto-waits for element to be actionable
await page.getByRole('button', { name: 'Submit' }).click();
```

### 2. Network Timing
**Symptom:** Data not loaded when assertion runs.

```typescript
// FLAKY — page might still be loading
await page.goto('/contracts');
await expect(page.getByRole('row')).toHaveCount(10);

// STABLE — wait for the API response first
await page.goto('/contracts');
await page.waitForResponse('**/api/data/v9.2/dcfg_contracts**');
await expect(page.getByRole('row')).toHaveCount(10);
```

### 3. Shared State Between Tests
**Symptom:** Tests pass individually, fail when run together.

```typescript
// FLAKY — test B depends on test A's data
let contractId: string;
test('A: create contract', async ({ page }) => {
  // creates contract, saves ID
  contractId = '...';
});
test('B: verify contract', async ({ page }) => {
  // uses contractId from test A — BROKEN if A fails or order changes
});

// STABLE — each test is self-contained
test('create and verify contract', async ({ page }) => {
  // create contract
  // verify contract
  // clean up
});
```

### 4. Animation / Transition Interference
**Symptom:** Click lands on wrong element or is intercepted.

```typescript
// STABLE — wait for animations to settle
await expect(page.getByRole('dialog')).toBeVisible();
await page.getByRole('button', { name: 'Confirm' }).click({ force: false });
// force: false is default — Playwright waits for actionability
```

### 5. Viewport / Responsive Layout
**Symptom:** Element is off-screen or hidden at test viewport size.

```typescript
// Fix in config
use: {
  viewport: { width: 1280, height: 720 },
}
```

### 6. Stale Locators in Loops
**Symptom:** `for...of` loop over `.all()` fails partway through.

```typescript
// FLAKY — DOM changes during iteration
const items = await page.locator('.item').all();
for (const item of items) {
  await item.click(); // might be stale
}

// STABLE — use count and nth, or filter
const count = await page.locator('.item').count();
for (let i = 0; i < count; i++) {
  await page.locator('.item').nth(i).click();
}
```

---

## Structured Failure Reports

When a test fails, capture everything:

```typescript
// In a global afterEach hook or custom reporter
test.afterEach(async ({ page }, testInfo) => {
  if (testInfo.status !== 'passed') {
    // Console errors
    const consoleErrors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    // Failed network requests
    const failedRequests: object[] = [];
    page.on('requestfailed', request => {
      failedRequests.push({
        url: request.url(),
        failure: request.failure()?.errorText,
      });
    });

    // Attach to test report
    await testInfo.attach('console-errors', {
      body: JSON.stringify(consoleErrors, null, 2),
      contentType: 'application/json',
    });
  }
});
```

---

## Retry Configuration

```typescript
// playwright.config.ts
export default defineConfig({
  retries: process.env.CI ? 2 : 0,  // retry on CI, not locally
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
});
```

**Important:** Retries mask flakiness. If a test needs retries to pass, fix the root cause. Use retries as a safety net, not a solution.

---

## Quarantine Pattern

For known-flaky tests blocking the build:
```typescript
test.describe('quarantine', () => {
  test.fixme('flaky contract generation', async ({ page }) => {
    // Known issue: race condition on template lookup
    // Tracking: DCFG-142
  });
});
```

`test.fixme()` skips the test but keeps it visible. Fix and un-quarantine ASAP.
