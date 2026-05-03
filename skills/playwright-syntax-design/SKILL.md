---
name: playwright-syntax-design
description: Write, debug, and maintain Playwright end-to-end tests in TypeScript following battle-tested best practices. ALWAYS use this skill when writing Playwright test code, creating page objects, setting up fixtures, choosing locators, handling authentication, debugging flaky tests, structuring test projects, configuring playwright.config.ts, writing assertions, or reviewing any .spec.ts file. Also trigger when the user mentions E2E tests, browser automation, test selectors, data-testid, getByRole, test flakiness, Playwright trace, codegen, or CI test pipelines. This skill prevents the most common AI-generated test failures: brittle selectors, missing awaits, shared state between tests, hardcoded waits, and wrong assertion patterns.
---

# Playwright Syntax Design Skill

Write production-grade Playwright tests in TypeScript. This skill encodes patterns from the official Playwright docs, community lessons, and real-world failure modes.

## When You're About to Write a Test

Before writing any test code, read the relevant reference file(s):

| Task | Read First |
|---|---|
| Choosing how to find elements | `references/locators.md` |
| Writing assertions / checking results | `references/assertions.md` |
| Structuring page objects and helpers | `references/page-objects.md` |
| Setting up auth, fixtures, hooks | `references/fixtures-auth.md` |
| Debugging failures or flaky tests | `references/debugging-flaky.md` |
| Project structure and config | `references/project-structure.md` |
| Network interception, API mocking | `references/network.md` |

Read the reference BEFORE writing code. Don't guess at patterns.

---

## Critical Rules (Always Apply)

### 1. Never Use Hardcoded Waits
```typescript
// WRONG — causes flakiness and slowness
await page.waitForTimeout(3000);

// RIGHT — wait for a real condition
await expect(page.getByRole('button', { name: 'Submit' })).toBeEnabled();
await page.waitForResponse(resp => resp.url().includes('/api/save') && resp.status() === 200);
```
Playwright auto-waits on actions. Trust it. Only add explicit waits when waiting for a specific network response or DOM condition.

### 2. Every `expect()` Must Be Awaited
```typescript
// WRONG — checks immediately, doesn't retry
expect(await page.getByText('Success').isVisible()).toBe(true);

// RIGHT — web-first assertion, retries until timeout
await expect(page.getByText('Success')).toBeVisible();
```
This is the #1 bug in AI-generated Playwright code. The `await` goes BEFORE `expect`, not inside it.

### 3. Locator Priority Order
1. `page.getByRole()` — best, mirrors user/accessibility view
2. `page.getByTestId()` — stable, resilient to CSS/structure changes
3. `page.getByLabel()`, `page.getByPlaceholder()`, `page.getByText()` — good for specific cases
4. `page.locator('[data-testid="x"]')` — acceptable fallback
5. `page.locator('.css-class')` or XPath — AVOID. Brittle, breaks on redesign.

### 4. Tests Must Be Isolated
Each test gets its own browser context. Never share state between tests. Never depend on test execution order. If a test needs data, create it in setup or via API — don't assume a prior test left it there.

### 5. One Workflow Per Test
A test should verify ONE user journey. Don't chain unrelated workflows. If a test name needs "and" in it, split it into two tests.

### 6. Always Use TypeScript
TypeScript catches missing awaits, wrong argument types, and undefined properties at write time. Never write Playwright tests in plain JavaScript.

### 7. Use Soft Assertions for Multi-Check Scenarios
```typescript
// Collects all failures instead of stopping at first
await expect.soft(page.getByTestId('status')).toHaveText('Active');
await expect.soft(page.getByTestId('balance')).toContainText('$');
// Test continues, reports all failures at end
```

### 8. Screenshots and Traces on Failure
Always configure in `playwright.config.ts`:
```typescript
use: {
  screenshot: 'only-on-failure',
  trace: 'on-first-retry',
  video: 'retain-on-failure',
}
```

---

## Patterns to NEVER Generate

| Anti-Pattern | Why It Fails | Do Instead |
|---|---|---|
| `page.waitForTimeout(N)` | Arbitrary delay, flaky | Wait for specific condition |
| `expect(await locator.isVisible()).toBe(true)` | No retry, races | `await expect(locator).toBeVisible()` |
| `page.locator('.btn-primary')` | CSS class changes | `page.getByRole('button', { name: '...' })` |
| `page.locator('//div[3]/span[2]')` | DOM position changes | Semantic locator |
| Shared `let` variables between tests | Cross-test pollution | Use fixtures or beforeEach |
| `page.$()` or `page.$$()` | Legacy API, no auto-wait | Use `page.locator()` |
| `for (const el of await locator.all())` inside assertions | Race condition | Use `locator.filter()` or `expect(locator).toHaveCount()` |
| Missing `await` before `expect` | Silent pass, no retry | Always `await expect(...)` |

---

## Quick Reference: Common Actions

```typescript
// Navigation
await page.goto('/dashboard');
await page.waitForURL('**/dashboard');

// Click
await page.getByRole('button', { name: 'Save' }).click();

// Fill input
await page.getByLabel('Email').fill('user@example.com');

// Select dropdown
await page.getByRole('combobox', { name: 'Country' }).selectOption('US');

// Check / uncheck
await page.getByRole('checkbox', { name: 'Agree' }).check();

// Upload file
await page.getByLabel('Upload').setInputFiles('path/to/file.pdf');

// Wait for network
const responsePromise = page.waitForResponse('**/api/data');
await page.getByRole('button', { name: 'Load' }).click();
const response = await responsePromise;

// Assert text
await expect(page.getByRole('heading')).toHaveText('Dashboard');

// Assert count
await expect(page.getByRole('listitem')).toHaveCount(5);

// Assert URL
await expect(page).toHaveURL(/.*\/success/);

// Assert invisible
await expect(page.getByText('Loading')).toBeHidden();
```

---

## Power Pages / Dataverse Specific Notes

When testing Power Pages portals with Dataverse backends:

1. **Auth is Entra ID** — use the setup project pattern to login once, save `storageState`, reuse across all tests. Never re-login per test.
2. **Dataverse API calls use OData** — intercept with `page.route('**/api/data/v9.2/**', ...)` for mocking.
3. **CSRF tokens** — Power Pages uses `window.shell.getTokenDeferred()`. Tests that POST to Dataverse need the portal's anti-forgery token. Either run against the real portal (preferred) or mock the token endpoint.
4. **Slow form loads** — Power Pages can be slow. Use `await page.waitForLoadState('networkidle')` after navigation, but NEVER use `waitForTimeout`.
5. **Dynamic IDs** — Power Pages generates dynamic element IDs. Always prefer `data-testid` attributes added by the developer, or `getByRole`/`getByLabel` locators.
6. **Verify backend state via API** — after UI actions, verify Dataverse records directly using `request.newContext()` with auth headers, not by reading the UI.

---

## Reference Files

For detailed patterns, read the reference files in `references/`. Each covers one topic in depth with DO/DON'T examples. The SKILL.md table above maps tasks to files.
