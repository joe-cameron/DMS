# Fixtures & Authentication — Setup, Teardown, and Login

## Authentication: Login Once, Reuse Everywhere

The most important optimization. Never re-login per test.

### Setup Project Pattern (Recommended)

```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  projects: [
    {
      name: 'setup',
      testMatch: /.*\.setup\.ts/,
    },
    {
      name: 'tests',
      dependencies: ['setup'],
      use: {
        storageState: 'playwright/.auth/user.json',
      },
    },
  ],
});
```

```typescript
// tests/auth.setup.ts
import { test as setup, expect } from '@playwright/test';

const authFile = 'playwright/.auth/user.json';

setup('authenticate', async ({ page }) => {
  await page.goto('/signin');

  // Entra ID / Azure AD login flow
  await page.getByPlaceholder('Email, phone, or Skype').fill(process.env.TEST_USER_EMAIL!);
  await page.getByRole('button', { name: 'Next' }).click();
  await page.getByPlaceholder('Password').fill(process.env.TEST_USER_PASSWORD!);
  await page.getByRole('button', { name: 'Sign in' }).click();

  // Handle "Stay signed in?" prompt
  await page.getByRole('button', { name: 'Yes' }).click();

  // Wait for redirect to your app
  await page.waitForURL('**/home**');

  // Save signed-in state
  await page.context().storageState({ path: authFile });
});
```

Every test now starts pre-authenticated. No login overhead.

### MFA / Interactive First-Time Login

If Entra ID requires MFA, run the setup once in headed mode:
```bash
npx playwright test --project=setup --headed
```
Complete MFA manually. The saved state persists until the token expires. Re-run setup when it does.

---

## Custom Fixtures

Fixtures inject page objects and shared resources into tests without manual instantiation.

```typescript
// fixtures/fixtures.ts
import { test as base } from '@playwright/test';
import { ContractDetailPage } from '../pages/ContractDetailPage';
import { CustomerListPage } from '../pages/CustomerListPage';
import { SendQueuePage } from '../pages/SendQueuePage';

type DCFGFixtures = {
  contractPage: ContractDetailPage;
  customerListPage: CustomerListPage;
  sendQueuePage: SendQueuePage;
};

export const test = base.extend<DCFGFixtures>({
  contractPage: async ({ page }, use) => {
    await use(new ContractDetailPage(page));
  },
  customerListPage: async ({ page }, use) => {
    await use(new CustomerListPage(page));
  },
  sendQueuePage: async ({ page }, use) => {
    await use(new SendQueuePage(page));
  },
});

export { expect } from '@playwright/test';
```

Usage in tests:
```typescript
// tests/contract.spec.ts
import { test, expect } from '../fixtures/fixtures';

test('create and generate contract', async ({ contractPage, page }) => {
  await page.goto('/contracts/new');
  await contractPage.selectCustomer('Bancroft');
  // ...
});
```

---

## beforeEach / afterEach Hooks

For setup that's common across tests in a file:

```typescript
import { test, expect } from '../fixtures/fixtures';

test.beforeEach(async ({ page }) => {
  await page.goto('/contracts');
  await page.waitForLoadState('networkidle');
});

test('displays contract list', async ({ page }) => {
  await expect(page.getByRole('table')).toBeVisible();
});

test('search filters results', async ({ page }) => {
  await page.getByPlaceholder('Search').fill('HVAC');
  await expect(page.getByRole('row')).toHaveCount(3);
});
```

---

## Worker-Scoped Fixtures (For Expensive Resources)

If a fixture is expensive to create (API clients, database connections), scope it to the worker:

```typescript
export const test = base.extend<{}, { apiContext: APIRequestContext }>({
  apiContext: [async ({ playwright }, use) => {
    const context = await playwright.request.newContext({
      baseURL: process.env.DCFG_DATAVERSE_URL,
      extraHTTPHeaders: {
        'Authorization': `Bearer ${await getAccessToken()}`,
      },
    });
    await use(context);
    await context.dispose();
  }, { scope: 'worker' }],
});
```

---

## Test Data Cleanup

Tests that create data should clean up:

```typescript
test('create and verify contract', async ({ page, apiContext }) => {
  // Create via UI
  // ...
  const contractId = await page.getByTestId('contract-id').innerText();

  // Verify
  await expect(page.getByTestId('status')).toHaveText('Draft');

  // Cleanup via API (not UI — faster and more reliable)
  await apiContext.delete(`/api/data/v9.2/dcfg_contracts(${contractId})`);
});
```

Or use a fixture with teardown:
```typescript
testContract: async ({ apiContext }, use) => {
  // Setup: create test contract via API
  const resp = await apiContext.post('/api/data/v9.2/dcfg_contracts', { data: testData });
  const id = resp.headers()['odata-entityid'];

  await use(id);

  // Teardown: delete after test
  await apiContext.delete(`/api/data/v9.2/dcfg_contracts(${id})`);
},
```

---

## Environment Variables

Store credentials in `.env` (gitignored):
```
TEST_USER_EMAIL=test@decades-cg.com
TEST_USER_PASSWORD=...
DCFG_PORTAL_URL=https://your-portal.powerappsportals.com
DCFG_DATAVERSE_URL=https://org0c17e98d.crm.dynamics.com
```

Load in config:
```typescript
// playwright.config.ts
import dotenv from 'dotenv';
dotenv.config();

export default defineConfig({
  use: {
    baseURL: process.env.DCFG_PORTAL_URL,
  },
});
```
