# Project Structure & Configuration

## Directory Layout

```
dcfg-playwright/
├── playwright.config.ts          # Central config
├── package.json
├── .env                          # Credentials (gitignored)
├── .gitignore
├── playwright/
│   └── .auth/
│       └── user.json             # Saved auth state (gitignored)
├── pages/                        # Page Object Model classes
│   ├── BasePage.ts
│   ├── ContractDetailPage.ts
│   ├── CustomerListPage.ts
│   ├── SendQueuePage.ts
│   └── OnboardingPage.ts
├── components/                   # Reusable UI component objects
│   ├── DataTable.ts
│   ├── Modal.ts
│   ├── Dropdown.ts
│   └── StatusBadge.ts
├── fixtures/                     # Custom Playwright fixtures
│   └── fixtures.ts
├── tests/                        # Test specs (one workflow per file)
│   ├── auth.setup.ts             # Login setup project
│   ├── contract-lifecycle.spec.ts
│   ├── msa-creation.spec.ts
│   ├── amendment.spec.ts
│   ├── duplicate-last.spec.ts
│   ├── send-queue.spec.ts
│   ├── signature-commit.spec.ts
│   ├── onboarding.spec.ts
│   ├── compliance-upload.spec.ts
│   └── void-decline.spec.ts
├── helpers/                      # Utility functions
│   ├── dataverse-api.ts          # Direct Dataverse Web API calls
│   └── report-builder.ts         # Structured failure report JSON
├── reports/                      # Generated failure reports
└── screenshots/                  # Failure screenshots
```

---

## playwright.config.ts — Full Example

```typescript
import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';

dotenv.config();

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,          // fail build if test.only left in
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { open: 'never' }],
    ['json', { outputFile: 'reports/results.json' }],
  ],

  use: {
    baseURL: process.env.DCFG_PORTAL_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    viewport: { width: 1280, height: 720 },
    actionTimeout: 15000,              // 15s per action
    navigationTimeout: 30000,          // 30s for page loads
  },

  expect: {
    timeout: 10000,                    // 10s for assertions
  },

  projects: [
    // Authentication setup — runs first
    {
      name: 'setup',
      testMatch: /.*\.setup\.ts/,
    },

    // Main test suite — depends on setup
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
});
```

---

## Key Config Decisions

### Workers
- **CI:** Set `workers: 1` for Power Pages — parallel tests against the same portal can cause Dataverse concurrency issues.
- **Local:** Leave as default (uses all CPU cores).

### Timeouts
- **Action timeout (15s):** Power Pages can be slow. Default 5s is too tight.
- **Navigation timeout (30s):** Page loads with Dataverse queries need headroom.
- **Assertion timeout (10s):** Give web-first assertions time to retry.

### Reporters
- **HTML:** Always. Opens the full report with traces, screenshots, and video.
- **JSON:** Machine-readable for the developer agent's failure reports.

---

## .gitignore

```
node_modules/
playwright/.auth/
reports/
screenshots/
test-results/
playwright-report/
.env
```

---

## package.json Scripts

```json
{
  "scripts": {
    "test": "npx playwright test",
    "test:headed": "npx playwright test --headed",
    "test:debug": "npx playwright test --debug",
    "test:ui": "npx playwright test --ui",
    "test:setup": "npx playwright test --project=setup --headed",
    "report": "npx playwright show-report"
  }
}
```

---

## Naming Conventions

| Thing | Convention | Example |
|---|---|---|
| Test files | `kebab-case.spec.ts` | `contract-lifecycle.spec.ts` |
| Page objects | `PascalCase.ts` | `ContractDetailPage.ts` |
| Components | `PascalCase.ts` | `DataTable.ts` |
| Fixtures | `camelCase` | `contractPage`, `apiContext` |
| Test names | Describe the outcome | `'should generate Bancroft contract with all required fields'` |
| `data-testid` | `kebab-case` | `data-testid="contract-status"` |

---

## ESLint for Test Quality

Install the floating promises rule to catch missing `await`:

```bash
npm install -D @typescript-eslint/eslint-plugin @typescript-eslint/parser
```

```json
// .eslintrc.json
{
  "parser": "@typescript-eslint/parser",
  "plugins": ["@typescript-eslint"],
  "rules": {
    "@typescript-eslint/no-floating-promises": "error"
  },
  "parserOptions": {
    "project": "./tsconfig.json"
  }
}
```

This catches the #1 Playwright bug — missing `await` — at lint time.
