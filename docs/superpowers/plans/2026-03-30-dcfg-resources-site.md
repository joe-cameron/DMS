# DCFG Resources Site — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone internal utility site with user manual guides, screenshot capture tests, a Copilot knowledge base, a build pipeline, and a Claude publishing skill — all as an isolated silo with no SPA association.

**Architecture:** Modular Markdown guides → Node.js build script → HTML + PDF → Power Pages resource site via Dataverse API. Playwright captures screenshots in Test env. Copilot Studio consumes a separate knowledge base. A Claude skill enables rapid ongoing content publishing.

**Tech Stack:** Playwright (TypeScript), Node.js (build.mjs), markdown-it, puppeteer, PowerShell + Dataverse Web API, Copilot Studio

**Spec:** `docs/superpowers/specs/2026-03-30-dcfg-resources-site-design.md`

---

## Chunk 1: Playwright Infrastructure & Demo Data

### Task 0: Create Power Pages site (inactive)

**Files:**
- Create: `C:\dcfg\scripts\create-resource-site.ps1`

- [ ] **Step 1: Write the site creation script**

PowerShell script that creates a `powerpagessite` record in Prod via Dataverse API, in **inactive state** (`statecode=1`). Uses `pac auth token` + `curl.exe` (never Connect-CrmOnline).

```powershell
# create-resource-site.ps1
# Creates the DCFG Resources Power Pages site in Prod (INACTIVE)
# Operator activates when ready.

pac auth select --index 3
$token = (pac auth token --format json | ConvertFrom-Json).token
$orgUrl = "https://org06f5de0b.crm.dynamics.com"

$body = @{
  name = "DCFG Resources"
  dcfg_description = "Internal utility site — guides, reviews, tools, AI assistant"
  statecode = 1  # INACTIVE — operator activates
} | ConvertTo-Json -Depth 10

$response = curl.exe -s -X POST "$orgUrl/api/data/v9.2/powerpagessites" `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -H "Prefer: return=representation" `
  -d $body

$site = $response | ConvertFrom-Json
$websiteId = $site.powerpagessiteid
Write-Host "Site created (INACTIVE): $websiteId"
Write-Host "Update site-config.json with this websiteId"

# Restore to Test
pac auth select --index 1
```

- [ ] **Step 2: Run the script**

Run: `pwsh C:\dcfg\scripts\create-resource-site.ps1`

Expected: Returns a `powerpagessiteid`. Record this value.

- [ ] **Step 3: Update site-config.json with websiteId**

Update `C:\Users\JosephCameron\.claude\skills\resource-site-publish\data\site-config.json` with the returned websiteId and portal URL.

- [ ] **Step 4: Commit**

```bash
git add scripts/create-resource-site.ps1
git commit -m "feat: create DCFG Resources Power Pages site (inactive)"
```

---

### Task 1: Initialize Playwright project

**Files:**
- Create: `C:\dcfg\tests\user-manual\package.json`
- Create: `C:\dcfg\tests\user-manual\playwright.config.ts`
- Create: `C:\dcfg\tests\user-manual\tsconfig.json`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "dcfg-user-manual-tests",
  "private": true,
  "scripts": {
    "test": "npx playwright test",
    "test:headed": "npx playwright test --headed",
    "test:ui": "npx playwright test --ui"
  }
}
```

- [ ] **Step 2: Install dependencies**

Run: `cd C:\dcfg\tests\user-manual && npm i -D @playwright/test && npx playwright install chromium`

Expected: Playwright installed, Chromium browser downloaded.

- [ ] **Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "node",
    "strict": true,
    "esModuleInterop": true
  }
}
```

- [ ] **Step 4: Create playwright.config.ts**

```typescript
import { defineConfig } from '@playwright/test';
import path from 'path';

const SCREENSHOT_DIR = path.resolve(__dirname, '../../docs/user-manual/screenshots');

export default defineConfig({
  testDir: './tests',
  timeout: 120_000,            // 2 min per test — wizard navigation is slow
  retries: 0,                  // no retries — screenshots must be deterministic
  use: {
    baseURL: 'https://dcfg.powerappsportals.com',
    viewport: { width: 1440, height: 900 },
    screenshot: 'off',         // we capture manually per step
    storageState: './auth-state.json',
  },
  projects: [
    {
      name: 'auth-setup',
      testMatch: /auth\.setup\.ts/,
      use: { storageState: undefined },
    },
    {
      name: 'screenshots',
      dependencies: ['auth-setup'],
      testMatch: /.*\.spec\.ts/,
    },
  ],
});

export { SCREENSHOT_DIR };
```

- [ ] **Step 5: Create screenshot output directories**

Run:
```bash
mkdir -p C:/dcfg/docs/user-manual/screenshots/{getting-started,sales-proposal,work-order,amendment,vendor-msa}
```

- [ ] **Step 6: Commit**

```bash
cd C:\dcfg && git add tests/user-manual/ docs/user-manual/screenshots/.gitkeep
git commit -m "chore: initialize Playwright project for user manual screenshot capture"
```

---

### Task 2: Auth setup with Windows Hello pause

**Files:**
- Create: `C:\dcfg\tests\user-manual\auth.setup.ts`

- [ ] **Step 1: Write auth.setup.ts**

```typescript
import { test as setup } from '@playwright/test';

/**
 * Auth setup — manual pause pattern for Windows Hello.
 *
 * HOW TO USE:
 * 1. Run: npx playwright test --project=auth-setup --headed
 * 2. Browser opens to portal login page
 * 3. TEST PAUSES — authenticate via Windows Hello manually
 * 4. After login, open the Playwright Inspector and click "Resume"
 * 5. Auth state saved to auth-state.json for all subsequent tests
 *
 * The saved auth state is reused until it expires. Re-run this
 * setup when you get 401 errors in screenshot tests.
 */
setup('authenticate via Windows Hello', async ({ page }) => {
  await page.goto('/');

  // PAUSE — operator authenticates manually via Windows Hello
  // Click "Resume" in the Playwright Inspector after login completes.
  await page.pause();

  // Verify we're logged in — the nav panel should be visible
  await page.waitForSelector('[data-testid="nav-panel"], nav, .nav-panel', {
    timeout: 30_000,
  });

  // Save auth state for reuse
  await page.context().storageState({ path: './auth-state.json' });
});
```

- [ ] **Step 2: Add auth-state.json to .gitignore**

Append to `C:\dcfg\tests\user-manual\.gitignore`:
```
auth-state.json
test-results/
```

- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/auth.setup.ts tests/user-manual/.gitignore
git commit -m "feat: add Windows Hello auth setup for Playwright screenshot tests"
```

---

### Task 3: Demo data constants

**Files:**
- Create: `C:\dcfg\tests\user-manual\demo-data.ts`

- [ ] **Step 1: Write demo-data.ts**

This file defines curated demo data constants. The Playwright test suite creates these records automatically in the Test environment if they don't exist (see Task 3b: demo data setup spec).

```typescript
/**
 * Demo dataset for user manual screenshots.
 * All values must match records in the Test environment (dcfg.powerappsportals.com).
 *
 * IMPORTANT: These are CONSTANTS — display values the Playwright tests type into
 * wizard fields. The corresponding Dataverse records must exist in Test.
 *
 * To set up demo data for the first time, see: docs/user-manual/DEMO-DATA-SETUP.md
 */

export const DEMO = {
  customer: {
    name: 'Parkview Properties LLC',
    searchTerm: 'Parkview',
  },
  vendor: {
    name: 'Summit Mechanical Services',
    legalName: 'Summit Mechanical Services LLC',
    searchTerm: 'Summit',
  },
  location: {
    name: 'Parkview Tower',
    address: '500 Commerce Dr',
    city: 'Atlanta',
    state: 'GA',
  },
  signer: {
    name: 'Maria Chen',
    title: 'VP Operations',
  },
  ownerContact: {
    name: 'James Rivera',
    email: 'j.rivera@parkviewprops.com',
    street: '500 Commerce Dr',
    city: 'Atlanta',
    state: 'GA',
  },
  parentWO: {
    searchTerm: 'HVAC',
    description: 'Parkview HVAC Retrofit',
  },
  costCodes: [
    { code: '5100', name: 'HVAC Labor', amount: '24,500.00', apCode: 'AP-5100' },
    { code: '5200', name: 'HVAC Materials', amount: '18,750.00', apCode: 'AP-5200' },
  ],
  proposal: {
    package: 'PackageB',       // Extended Service
    packageLabel: 'Package B', // displayed on screen
    uniformRate: '2,500.00',
    onboardingRate: '5,000.00',
  },
  contractDate: '2026-04-01',
  paymentProcess: 'Net 30 — ACH',
} as const;

/** Helper: screenshot filename with zero-padded step number */
export function screenshotName(flow: string, step: number, label: string): string {
  const padded = String(step).padStart(2, '0');
  const slug = label.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/-+$/, '');
  return `${flow}/${padded}-${slug}.png`;
}
```

- [ ] **Step 2: Create automated demo data setup spec**

Create: `C:\dcfg\tests\user-manual\tests\demo-data-setup.spec.ts`

This Playwright spec runs FIRST (via project dependency) and creates demo records in Test via the SPA's own UI — navigating to screens and creating records through the portal, not via direct API calls. This ensures the data matches exactly what the SPA expects.

```typescript
import { test, expect } from '@playwright/test';
import { DEMO } from '../demo-data';

/**
 * Demo data setup — creates records in Test environment via the SPA UI.
 * Idempotent: checks if records exist before creating.
 * Runs as a Playwright project dependency before screenshot specs.
 *
 * Records created:
 * - Customer: Parkview Properties LLC
 * - Vendor: Summit Mechanical Services
 * - Location: Parkview Tower (linked to customer)
 * - Cost Codes: 5100, 5200 (if not present)
 * - Parent WO: Parkview HVAC Retrofit (for amendment screenshots)
 */

test.describe('Demo data setup', () => {

  test('Create demo customer if not exists', async ({ page }) => {
    await page.goto('/customers');
    await page.waitForLoadState('networkidle');

    // Search for existing
    const search = page.locator('input[placeholder*="earch"]').first();
    await search.fill(DEMO.customer.searchTerm);
    await page.waitForTimeout(1000);

    const existing = page.getByText(DEMO.customer.name);
    if (await existing.isVisible({ timeout: 2000 }).catch(() => false)) {
      // Already exists — skip
      return;
    }

    // Create new customer via the SPA's create flow
    await page.getByRole('button', { name: /new.*customer|create/i }).click();
    await page.waitForTimeout(500);
    // Fill name and save — exact selectors adjusted at runtime
    await page.getByLabel(/name/i).first().fill(DEMO.customer.name);
    await page.getByRole('button', { name: /save|create/i }).click();
    await page.waitForTimeout(1000);
  });

  test('Create demo vendor if not exists', async ({ page }) => {
    // Similar pattern — navigate to vendor management, search, create if missing
    // Vendor creation may require admin screen access
    await page.goto('/admin');
    await page.waitForLoadState('networkidle');
    // Adjust based on admin screen's vendor management UI
  });

  test('Create demo location if not exists', async ({ page }) => {
    // Navigate to customer detail → add location
    await page.goto('/customers');
    await page.waitForLoadState('networkidle');
    await page.locator('input[placeholder*="earch"]').first().fill(DEMO.customer.searchTerm);
    await page.waitForTimeout(1000);
    await page.getByText(DEMO.customer.name).first().click();
    await page.waitForTimeout(1000);
    // Check if Parkview Tower location exists, create if not
  });

  test('Create parent WO for amendment screenshots', async ({ page }) => {
    // Navigate to /contracts/new, create a WO with demo data, save as draft
    // This gives the amendment spec a parent WO to reference
    await page.goto('/contracts/new');
    await page.waitForLoadState('networkidle');
    // Only create if no existing WO matches DEMO.parentWO.description
  });

});
```

Then update `playwright.config.ts` to add a `demo-data` project that runs before screenshots:

```typescript
// Add to projects array in playwright.config.ts:
{
  name: 'demo-data',
  dependencies: ['auth-setup'],
  testMatch: /demo-data-setup\.spec\.ts/,
},
{
  name: 'screenshots',
  dependencies: ['demo-data'],  // changed from 'auth-setup' to 'demo-data'
  testMatch: /^(?!.*demo-data).*\.spec\.ts/,
},
```

- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/demo-data.ts docs/user-manual/DEMO-DATA-SETUP.md
git commit -m "feat: add demo dataset constants and setup instructions"
```

---

### Task 4: Screenshot helper utilities

**Files:**
- Create: `C:\dcfg\tests\user-manual\screenshot-helpers.ts`

- [ ] **Step 1: Write screenshot-helpers.ts**

```typescript
import { Page, expect } from '@playwright/test';
import path from 'path';

const SCREENSHOT_DIR = path.resolve(__dirname, '../../docs/user-manual/screenshots');

/**
 * Capture a full-page screenshot and save to the correct guide folder.
 *
 * @param page      - Playwright Page object
 * @param flow      - folder name: 'getting-started', 'sales-proposal', etc.
 * @param step      - step number (zero-padded in filename)
 * @param label     - human-readable label (slugified in filename)
 *
 * Example: captureStep(page, 'work-order', 1, 'select-customer')
 * Output:  docs/user-manual/screenshots/work-order/01-select-customer.png
 */
export async function captureStep(
  page: Page,
  flow: string,
  step: number,
  label: string,
): Promise<string> {
  // Wait for any spinners/loading indicators to disappear
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(500); // brief settle

  const padded = String(step).padStart(2, '0');
  const slug = label.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/-+$/, '');
  const filename = `${padded}-${slug}.png`;
  const filepath = path.join(SCREENSHOT_DIR, flow, filename);

  await page.screenshot({ path: filepath, fullPage: true });
  return filepath;
}

/**
 * Capture a focused element screenshot (e.g., a specific dropdown or table).
 *
 * @param page      - Playwright Page object
 * @param selector  - CSS selector or Playwright locator string
 * @param flow      - folder name
 * @param step      - step number
 * @param label     - human-readable label
 */
export async function captureElement(
  page: Page,
  selector: string,
  flow: string,
  step: number,
  label: string,
): Promise<string> {
  const padded = String(step).padStart(2, '0');
  const slug = label.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/-+$/, '');
  const filename = `${padded}-${slug}-detail.png`;
  const filepath = path.join(SCREENSHOT_DIR, flow, filename);

  const element = page.locator(selector).first();
  await expect(element).toBeVisible({ timeout: 10_000 });
  await element.screenshot({ path: filepath });
  return filepath;
}

/**
 * Wait for wizard step to be active before capturing.
 * Checks for step indicator, heading, or similar UI markers.
 */
export async function waitForWizardStep(page: Page, stepNumber: number): Promise<void> {
  // Wait for the step content to render — the wizard uses a step counter
  await page.waitForTimeout(800); // wizard transition animation
  await page.waitForLoadState('networkidle');
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/user-manual/screenshot-helpers.ts
git commit -m "feat: add screenshot capture helpers for Playwright tests"
```

---

## Chunk 2: Playwright Screenshot Specs

### Task 5: Getting Started spec

**Files:**
- Create: `C:\dcfg\tests\user-manual\tests\getting-started.spec.ts`

- [ ] **Step 1: Write getting-started.spec.ts**

```typescript
import { test } from '@playwright/test';
import { captureStep, captureElement } from '../screenshot-helpers';

const FLOW = 'getting-started';

test.describe('Getting Started — screenshots', () => {

  test('01 — Dashboard overview', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 1, 'dashboard');
  });

  test('02 — Navigation panel', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await captureElement(page, 'nav, .nav-panel, [data-testid="nav-panel"]', FLOW, 2, 'navigation-panel');
  });

  test('03 — Customers list', async ({ page }) => {
    await page.goto('/customers');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 3, 'customers-list');
  });

  test('04 — Contracts list', async ({ page }) => {
    await page.goto('/contracts');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 4, 'contracts-list');
  });

  test('05 — Send Queue', async ({ page }) => {
    await page.goto('/send-queue');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 5, 'send-queue');
  });

  test('06 — MSA list', async ({ page }) => {
    await page.goto('/msas');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 6, 'msa-list');
  });

});
```

- [ ] **Step 2: Run headed to verify** (requires auth setup first)

Run: `cd C:\dcfg\tests\user-manual && npx playwright test --project=auth-setup --headed`
Then: `npx playwright test tests/getting-started.spec.ts --headed`

Expected: 6 PNG files in `docs/user-manual/screenshots/getting-started/`

- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/tests/getting-started.spec.ts
git commit -m "feat: getting-started screenshot spec — 6 captures"
```

---

### Task 6: Work Order spec

**Files:**
- Create: `C:\dcfg\tests\user-manual\tests\work-order.spec.ts`

- [ ] **Step 1: Write work-order.spec.ts**

```typescript
import { test, expect } from '@playwright/test';
import { captureStep, captureElement, waitForWizardStep } from '../screenshot-helpers';
import { DEMO } from '../demo-data';

const FLOW = 'work-order';

test.describe('Work Order Wizard — screenshots', () => {

  test.describe.configure({ mode: 'serial' }); // steps must run in order

  let page: any; // shared page across serial tests

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext({ storageState: './auth-state.json' });
    page = await context.newPage();
  });

  test.afterAll(async () => {
    await page?.context()?.close();
  });

  test('01 — Drafts landing page', async () => {
    await page.goto('/contracts/new');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 1, 'drafts-landing');

    // Click "Start New" to enter the wizard
    const startBtn = page.getByRole('button', { name: /start new|new contract/i });
    if (await startBtn.isVisible()) {
      await startBtn.click();
    }
    await waitForWizardStep(page, 1);
  });

  test('02 — Step 1: Select Customer', async () => {
    await captureStep(page, FLOW, 2, 'step1-select-customer');

    // Search for demo customer
    const searchInput = page.locator('input[placeholder*="earch"], input[placeholder*="customer"]').first();
    await searchInput.fill(DEMO.customer.searchTerm);
    await page.waitForTimeout(1000); // search debounce

    // Click the demo customer in results
    await page.getByText(DEMO.customer.name).first().click();
    await page.waitForTimeout(500);

    await captureStep(page, FLOW, 3, 'step1-customer-selected');

    // Advance to step 2
    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 2);
  });

  test('03 — Step 2: Document Type', async () => {
    await captureStep(page, FLOW, 4, 'step2-document-type');

    // Work Order should be default selected
    // Select location
    const locationSelect = page.locator('select').filter({ hasText: /location|property/i }).first();
    if (await locationSelect.isVisible()) {
      await locationSelect.selectOption({ label: new RegExp(DEMO.location.name, 'i') });
    }

    // Set contract date
    const dateInput = page.locator('input[type="date"]').first();
    if (await dateInput.isVisible()) {
      await dateInput.fill(DEMO.contractDate);
    }

    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 5, 'step2-filled');

    // Advance to step 3
    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 3);
  });

  test('04 — Step 3: Contractor & Signer', async () => {
    await captureStep(page, FLOW, 6, 'step3-contractor-signer');

    // Fill signer fields
    const signerNameInput = page.locator('input').filter({ hasText: /signer.*name/i }).or(
      page.locator('input[placeholder*="igner"]')
    ).first();

    // Use more robust fill pattern — find by label
    await page.getByLabel(/signer.*name|printed.*name/i).first().fill(DEMO.signer.name);
    await page.getByLabel(/signer.*title/i).first().fill(DEMO.signer.title);

    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 7, 'step3-filled');

    // Advance to step 4
    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 4);
  });

  test('05 — Step 4: Exhibit A Lines', async () => {
    await captureStep(page, FLOW, 8, 'step4-exhibit-a-empty');

    // Fill first line item
    // Cost code dropdown, description, amount
    // The exact selectors depend on the wizard's render — adjust after first run
    for (const [i, line] of DEMO.costCodes.entries()) {
      if (i > 0) {
        // Click "Add Line" for additional rows
        await page.getByRole('button', { name: /add.*line/i }).click();
        await page.waitForTimeout(300);
      }
      // Fill the line — these selectors will need adjustment based on actual DOM
      // The wizard renders line items as rows with inputs
    }

    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 9, 'step4-exhibit-a-filled');

    // Advance to step 5
    await page.getByRole('button', { name: /next|review/i }).first().click();
    await waitForWizardStep(page, 5);
  });

  test('06 — Step 5: Review & Generate', async () => {
    await captureStep(page, FLOW, 10, 'step5-review');
    // DO NOT click Generate — this is a screenshot capture test only
  });

});
```

**NOTE:** The exact locator selectors (`getByLabel`, `getByRole`, etc.) will need adjustment after the first headed run. The wizard renders dynamic JSX — locators must be confirmed against the actual DOM. Run `--headed` first, inspect the DOM, and update selectors.

- [ ] **Step 2: Run headed to test and adjust selectors**

Run: `npx playwright test tests/work-order.spec.ts --headed`

Expect: Some selectors may fail on first run. Inspect the DOM, update selectors, re-run.

- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/tests/work-order.spec.ts
git commit -m "feat: work order wizard screenshot spec — 10 captures"
```

---

### Task 7: Amendment spec

**Files:**
- Create: `C:\dcfg\tests\user-manual\tests\amendment.spec.ts`

- [ ] **Step 1: Write amendment.spec.ts**

Follows the same serial pattern as work-order.spec.ts but:
- Navigates to `/contracts/new?type=amendment`
- On Step 2, selects "Amendment" document type and picks a parent WO
- Parent WO auto-fills vendor and location — capture this behavior
- Exhibit A lines and Review are the same

```typescript
import { test } from '@playwright/test';
import { captureStep, waitForWizardStep } from '../screenshot-helpers';
import { DEMO } from '../demo-data';

const FLOW = 'amendment';

test.describe('Amendment Wizard — screenshots', () => {
  test.describe.configure({ mode: 'serial' });

  let page: any;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext({ storageState: './auth-state.json' });
    page = await context.newPage();
  });

  test.afterAll(async () => { await page?.context()?.close(); });

  test('01 — Navigate to amendment wizard', async () => {
    await page.goto('/contracts/new?type=amendment');
    await page.waitForLoadState('networkidle');

    // Skip drafts landing if shown
    const startBtn = page.getByRole('button', { name: /start new|new contract/i });
    if (await startBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await startBtn.click();
    }
    await waitForWizardStep(page, 1);
    await captureStep(page, FLOW, 1, 'step1-select-customer');
  });

  test('02 — Select customer', async () => {
    const searchInput = page.locator('input[placeholder*="earch"]').first();
    await searchInput.fill(DEMO.customer.searchTerm);
    await page.waitForTimeout(1000);
    await page.getByText(DEMO.customer.name).first().click();
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 2, 'step1-customer-selected');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 2);
  });

  test('03 — Step 2: Amendment type + parent WO', async () => {
    // Amendment should already be selected via URL param
    await captureStep(page, FLOW, 3, 'step2-amendment-type');

    // Select parent work order
    const parentSelect = page.locator('select').filter({ hasText: /parent|work order/i }).first();
    if (await parentSelect.isVisible()) {
      // Select the demo parent WO
      await parentSelect.selectOption({ label: new RegExp(DEMO.parentWO.searchTerm, 'i') });
    } else {
      // May be a search/click pattern instead of a select
      await page.getByText(DEMO.parentWO.description).first().click();
    }

    await page.waitForTimeout(1000);
    // Capture AFTER parent WO selected — vendor and location should auto-fill
    await captureStep(page, FLOW, 4, 'step2-parent-wo-autofill');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 3);
  });

  test('04 — Step 3: Contractor (auto-filled from parent)', async () => {
    // Contractor fields should be pre-filled from parent WO
    await captureStep(page, FLOW, 5, 'step3-contractor-autofilled');

    // Fill signer
    await page.getByLabel(/signer.*name|printed.*name/i).first().fill(DEMO.signer.name);
    await page.getByLabel(/signer.*title/i).first().fill(DEMO.signer.title);
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 6, 'step3-signer-filled');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 4);
  });

  test('05 — Step 4: Exhibit A Lines', async () => {
    await captureStep(page, FLOW, 7, 'step4-exhibit-a');
    // Fill line items similar to work order
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 8, 'step4-exhibit-a-filled');

    await page.getByRole('button', { name: /next|review/i }).first().click();
    await waitForWizardStep(page, 5);
  });

  test('06 — Step 5: Review', async () => {
    await captureStep(page, FLOW, 9, 'step5-review-amendment');
    // DO NOT click Generate
  });

});
```

- [ ] **Step 2: Run headed and adjust selectors**
- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/tests/amendment.spec.ts
git commit -m "feat: amendment wizard screenshot spec — 9 captures"
```

---

### Task 8: Sales Proposal spec

**Files:**
- Create: `C:\dcfg\tests\user-manual\tests\sales-proposal.spec.ts`

- [ ] **Step 1: Write sales-proposal.spec.ts**

```typescript
import { test } from '@playwright/test';
import { captureStep, waitForWizardStep } from '../screenshot-helpers';
import { DEMO } from '../demo-data';

const FLOW = 'sales-proposal';

test.describe('Sales Proposal Wizard — screenshots', () => {
  test.describe.configure({ mode: 'serial' });

  let page: any;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext({ storageState: './auth-state.json' });
    page = await context.newPage();
  });

  test.afterAll(async () => { await page?.context()?.close(); });

  test('01 — Drafts landing', async () => {
    await page.goto('/proposals/new');
    await page.waitForLoadState('networkidle');
    await captureStep(page, FLOW, 1, 'drafts-landing');

    const startBtn = page.getByRole('button', { name: /start new|new proposal/i });
    if (await startBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await startBtn.click();
    }
    await waitForWizardStep(page, 1);
  });

  test('02 — Step 1: Service Package', async () => {
    await captureStep(page, FLOW, 2, 'step1-package-selection');

    // Select Package B (Extended)
    await page.getByText(/package b|extended/i).first().click();
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 3, 'step1-package-b-selected');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 2);
  });

  test('03 — Step 2: Customer & Vendor', async () => {
    await captureStep(page, FLOW, 4, 'step2-customer-vendor');

    // Search and select customer
    const searchInput = page.locator('input[placeholder*="earch"]').first();
    await searchInput.fill(DEMO.customer.searchTerm);
    await page.waitForTimeout(1000);
    await page.getByText(DEMO.customer.name).first().click();
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 5, 'step2-customer-selected');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 3);
  });

  test('04 — Step 3: Pricing & Locations', async () => {
    await captureStep(page, FLOW, 6, 'step3-pricing-locations');

    // Set uniform rate
    await page.getByLabel(/monthly.*rate|membership.*rate/i).first().fill(DEMO.proposal.uniformRate);
    await page.getByLabel(/onboarding.*rate|onboard/i).first().fill(DEMO.proposal.onboardingRate);
    await page.waitForTimeout(500);

    await captureStep(page, FLOW, 7, 'step3-pricing-filled');

    await page.getByRole('button', { name: /next|review/i }).first().click();
    await waitForWizardStep(page, 4);
  });

  test('05 — Step 4: Review & Generate', async () => {
    await captureStep(page, FLOW, 8, 'step4-review');
    // DO NOT click Generate
  });

});
```

- [ ] **Step 2: Run headed and adjust selectors**
- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/tests/sales-proposal.spec.ts
git commit -m "feat: sales proposal wizard screenshot spec — 8 captures"
```

---

### Task 9: Vendor MSA spec

**Files:**
- Create: `C:\dcfg\tests\user-manual\tests\vendor-msa.spec.ts`

- [ ] **Step 1: Write vendor-msa.spec.ts**

```typescript
import { test } from '@playwright/test';
import { captureStep, waitForWizardStep } from '../screenshot-helpers';
import { DEMO } from '../demo-data';

const FLOW = 'vendor-msa';

test.describe('Vendor MSA Wizard — screenshots', () => {
  test.describe.configure({ mode: 'serial' });

  let page: any;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext({ storageState: './auth-state.json' });
    page = await context.newPage();
  });

  test.afterAll(async () => { await page?.context()?.close(); });

  test('01 — Navigate to Vendor MSA wizard', async () => {
    await page.goto('/contracts/new?type=msa');
    await page.waitForLoadState('networkidle');

    const startBtn = page.getByRole('button', { name: /start new|new contract/i });
    if (await startBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await startBtn.click();
    }
    await waitForWizardStep(page, 1);
    await captureStep(page, FLOW, 1, 'step1-select-customer');
  });

  test('02 — Select customer', async () => {
    const searchInput = page.locator('input[placeholder*="earch"]').first();
    await searchInput.fill(DEMO.customer.searchTerm);
    await page.waitForTimeout(1000);
    await page.getByText(DEMO.customer.name).first().click();
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 2, 'step1-customer-selected');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 2);
  });

  test('03 — Step 2: Document Type (Vendor MSA)', async () => {
    // Vendor MSA should be pre-selected via URL param
    await captureStep(page, FLOW, 3, 'step2-vendor-msa-type');

    await page.getByRole('button', { name: /next/i }).first().click();
    await waitForWizardStep(page, 3);
  });

  test('04 — Step 3: Vendor & Signer', async () => {
    await captureStep(page, FLOW, 4, 'step3-vendor-signer');

    // Select vendor
    const vendorSearch = page.locator('input[placeholder*="endor"], input[placeholder*="earch"]');
    if (await vendorSearch.first().isVisible()) {
      await vendorSearch.first().fill(DEMO.vendor.searchTerm);
      await page.waitForTimeout(1000);
      await page.getByText(DEMO.vendor.name).first().click();
    }

    // Fill signer
    await page.getByLabel(/signer.*name|printed.*name/i).first().fill(DEMO.signer.name);
    await page.getByLabel(/signer.*title/i).first().fill(DEMO.signer.title);
    await page.waitForTimeout(500);
    await captureStep(page, FLOW, 5, 'step3-vendor-signer-filled');

    await page.getByRole('button', { name: /next|review/i }).first().click();
    await waitForWizardStep(page, 5);
  });

  test('05 — Step 5: Review', async () => {
    // Vendor MSA skips Exhibit A (step 4) — goes straight to Review
    await captureStep(page, FLOW, 6, 'step5-review-vendor-msa');
    // DO NOT click Generate
  });

});
```

- [ ] **Step 2: Run headed and adjust selectors**
- [ ] **Step 3: Commit**

```bash
git add tests/user-manual/tests/vendor-msa.spec.ts
git commit -m "feat: vendor MSA wizard screenshot spec — 6 captures"
```

---

## Chunk 3: User Manual Guides (Markdown)

### Task 10: Index and Getting Started guide

**Files:**
- Create: `C:\dcfg\docs\user-manual\index.md`
- Create: `C:\dcfg\docs\user-manual\getting-started.md`

- [ ] **Step 1: Write index.md**

```markdown
# DCFG Document Management System — User Manual

Welcome to the DCFG DMS user manual. These guides walk you through every document creation process in the system, step by step, with screenshots.

## Guides

| Guide | Description |
|-------|------------|
| [Getting Started](getting-started.md) | Login, navigation, and common UI patterns |
| [Sales Proposal](guide-sales-proposal.md) | Create a new customer proposal (MSA) |
| [Work Order](guide-work-order.md) | Create a new work order |
| [Amendment](guide-amendment.md) | Amend an existing work order |
| [Vendor MSA](guide-vendor-msa.md) | Create a vendor master service agreement |

## How Documents Work

All documents in DCFG follow the same lifecycle:

1. **Draft** — Fill out the wizard, save at any point
2. **Generated** — Click "Generate" to create the document from template
3. **In Send Queue** — Document appears in the Send Queue for review and delivery
4. **Sent** — Document emailed to the recipient
5. **Signed / Received** — Confirmation of receipt or signature
6. **Closed** — Document lifecycle complete

You can save a draft at any step and come back later. Your drafts appear on the wizard landing page when you return.

## Need Help?

Can't find what you need in the guides? Try these:

- **Search the guides** — use Ctrl+F to search any guide page
- **Ask the AI Assistant** — if enabled, visit [AI Assistant](/assistant) to ask questions about any DMS process (the assistant can look up contracts, customers, and vendors)
- **Contact your administrator** — for account access or system issues
```

- [ ] **Step 2: Write getting-started.md**

```markdown
# Getting Started

This guide covers logging in, navigating the DCFG system, and understanding the main screens you'll use daily.

## Logging In

DCFG uses Windows Hello for authentication. When you visit the portal, your browser will prompt for Windows Hello — use your PIN, fingerprint, or facial recognition to log in.

> **Tip:** If you're prompted for credentials instead of Windows Hello, contact your administrator.

## Dashboard

After logging in, you land on the **Sales Dashboard**. This shows:

- **Pipeline KPIs** — active proposals, contracts, and their statuses
- **Recent Activity** — latest document actions across the system
- **Status Breakdown** — visual summary of where documents are in their lifecycle

![Dashboard](screenshots/getting-started/01-dashboard.png)

## Navigation

The left navigation panel organizes the system into sections:

![Navigation Panel](screenshots/getting-started/02-navigation-panel.png)

### Sales
- **Dashboard** — pipeline overview and KPIs
- **Customers** — customer list, search, create new
- **MSAs** — master service agreements

### Contracts
- **Contracts** — all contracts with split-pane detail view
- **New Contract** — create Work Order, Amendment, or Vendor MSA
- **New Proposal** — create Sales Proposal (MSA)
- **Send Queue** — document delivery queue

### Key Screens

**Customers List** — search and manage all customers.

![Customers List](screenshots/getting-started/03-customers-list.png)

**Contracts List** — split-pane view showing contract KPIs on top, list on the left, detail on the right.

![Contracts List](screenshots/getting-started/04-contracts-list.png)

**Send Queue** — where generated documents wait for review and delivery. This is where you send documents to recipients.

![Send Queue](screenshots/getting-started/05-send-queue.png)

**MSA List** — all master service agreements.

![MSA List](screenshots/getting-started/06-msa-list.png)

## Next Steps

Ready to create your first document? Choose a guide:

- [Sales Proposal →](guide-sales-proposal.md)
- [Work Order →](guide-work-order.md)
- [Amendment →](guide-amendment.md)
- [Vendor MSA →](guide-vendor-msa.md)
```

- [ ] **Step 3: Commit**

```bash
git add docs/user-manual/index.md docs/user-manual/getting-started.md
git commit -m "feat: user manual index and getting started guide"
```

---

### Task 11: Work Order guide

**Files:**
- Create: `C:\dcfg\docs\user-manual\guide-work-order.md`

- [ ] **Step 1: Write guide-work-order.md**

Write the complete guide following the template from the spec. This is the longest guide since the work order wizard has 5 steps and is the most commonly used flow.

The guide must include:
1. **Overview** — what a work order is, when to create one
2. **Prerequisites** — customer and vendor must exist
3. **Step-by-step** — all 5 wizard steps with screenshot references
4. **Field reference** — every field per step with Dataverse column name
5. **After generation** — Send Queue workflow
6. **Common mistakes** — missing signer, wrong cost code, etc.
7. **Draft and resume** — how WIP drafts work

Key sections for each step:

**Step 1 — Customer:** Search/select customer. Programs and locations load. `dcfg_customer_id`.

**Step 2 — Document Type:** Work Order is default. Select location (`dcfg_property_id`), set contract date (`dcfg_contract_date`). Contract family derived from customer TPA status — not user selectable.

**Step 3 — Contractor & Signer:** Vendor auto-fills from selection. Fields: `dcfg_contractor_legal_name`, `dcfg_company`, `dcfg_contractor_address`, `dcfg_contractor_phone`, `dcfg_contractor_email`, `dcfg_payment_process`, `dcfg_signer_printed`, `dcfg_signer_title`. Owner contact fields: `dcfg_owner_contact`, `dcfg_owner_email`, `dcfg_owner_street`, `dcfg_owner_city`, `dcfg_owner_state`.

**Step 4 — Exhibit A Lines:** Each line: cost code (dropdown from `dcfg_ap_cost_codes`), description, amount, AP code. Add/remove lines. `dcfg_contract_lines` table.

**Step 5 — Review & Generate:** Read-only summary. Click Generate → creates `dcfg_document_request` → flow triggers automatically.

Screenshot references: `screenshots/work-order/01-drafts-landing.png` through `screenshots/work-order/10-step5-review.png`

- [ ] **Step 2: Commit**

```bash
git add docs/user-manual/guide-work-order.md
git commit -m "feat: work order user guide with field reference"
```

---

### Task 12: Amendment guide

**Files:**
- Create: `C:\dcfg\docs\user-manual\guide-amendment.md`

- [ ] **Step 1: Write guide-amendment.md**

Same template as Work Order but with amendment-specific behavior:
- **Key difference:** Step 2 requires selecting a parent Work Order. Selecting the parent auto-fills vendor and location.
- Amendment number is auto-generated
- Exhibit A may show existing lines from parent WO
- Explain that amendments modify an existing WO's scope/cost

- [ ] **Step 2: Commit**

```bash
git add docs/user-manual/guide-amendment.md
git commit -m "feat: amendment user guide with parent WO auto-fill documentation"
```

---

### Task 13: Sales Proposal guide

**Files:**
- Create: `C:\dcfg\docs\user-manual\guide-sales-proposal.md`

- [ ] **Step 1: Write guide-sales-proposal.md**

Proposal-specific content:
- **Step 1 — Package:** A (Essential), B (Extended), C (Premium). Each has different exhibit scopes.
- **Step 2 — Customer & Vendor:** Customer search or create new. Signer info. Vendor defaults to Decades Construction Group LLC.
- **Step 3 — Pricing & Locations:** Uniform vs type-based pricing. Add locations. Monthly membership rate + one-time onboarding rate. Budget calculated automatically.
- **Step 4 — Review & Generate:** MSA summary, budget totals. Creates `dcfg_document_request`.

Field reference: `dcfg_exhibit_type` (100000000=A, 100000001=B, 100000002=C), `dcfg_pricing_alternative` (100000000=uniform, 100000001=type-based), `dcfg_membership_rate`, `dcfg_onboarding_rate`, `dcfg_budget_total`.

- [ ] **Step 2: Commit**

```bash
git add docs/user-manual/guide-sales-proposal.md
git commit -m "feat: sales proposal user guide with package and pricing documentation"
```

---

### Task 14: Vendor MSA guide

**Files:**
- Create: `C:\dcfg\docs\user-manual\guide-vendor-msa.md`

- [ ] **Step 1: Write guide-vendor-msa.md**

Vendor MSA specific:
- Simplified flow — no Exhibit A lines
- Customer → Doc Type (Vendor MSA pre-selected) → Vendor & Signer → Review
- Used for vendor master agreements, not project-specific work orders
- Vendor selection is the primary action
- Signer fields required

- [ ] **Step 2: Commit**

```bash
git add docs/user-manual/guide-vendor-msa.md
git commit -m "feat: vendor MSA user guide"
```

---

## Chunk 4: Build Toolchain

### Task 15: Build script and HTML template

**Files:**
- Create: `C:\dcfg\docs\user-manual\package.json`
- Create: `C:\dcfg\docs\user-manual\build.mjs`
- Create: `C:\dcfg\docs\user-manual\template.html`

- [ ] **Step 1: Create package.json for build dependencies**

```json
{
  "name": "dcfg-user-manual-build",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "node build.mjs",
    "build:pdf": "node build.mjs --pdf"
  }
}
```

- [ ] **Step 2: Install dependencies**

Run: `cd C:\dcfg\docs\user-manual && npm i markdown-it markdown-it-anchor markdown-it-toc-done-right puppeteer`

- [ ] **Step 3: Create template.html**

Shared HTML template with:
- DCFG branding (navy header, IBM Plex Sans font)
- Sticky sidebar TOC (auto-generated from `${toc}` placeholder)
- Previous / Next navigation (from `${prevLink}` / `${nextLink}` placeholders)
- Responsive layout — sidebar collapses on tablet
- Screenshot images referenced via relative paths
- `${content}` placeholder for rendered Markdown

- [ ] **Step 4: Write build.mjs**

```javascript
/**
 * build.mjs — Markdown → HTML + PDF for DCFG User Manual
 *
 * Usage:
 *   node build.mjs          # HTML only
 *   node build.mjs --pdf    # HTML + PDF
 *
 * Output:
 *   dist/*.html
 *   dist/pdf/*.pdf          (if --pdf)
 *   dist/screenshots/       (copied from screenshots/)
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import markdownIt from 'markdown-it';
import markdownItAnchor from 'markdown-it-anchor';
import markdownItToc from 'markdown-it-toc-done-right';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(__dirname, 'dist');
const PDF_DIR = path.join(DIST, 'pdf');
const TEMPLATE = fs.readFileSync(path.join(__dirname, 'template.html'), 'utf-8');

// Guide order for prev/next navigation
const GUIDES = [
  { file: 'getting-started.md', title: 'Getting Started' },
  { file: 'guide-sales-proposal.md', title: 'Sales Proposal' },
  { file: 'guide-work-order.md', title: 'Work Order' },
  { file: 'guide-amendment.md', title: 'Amendment' },
  { file: 'guide-vendor-msa.md', title: 'Vendor MSA' },
];

const md = markdownIt({ html: true, linkify: true })
  .use(markdownItAnchor, { permalink: markdownItAnchor.permalink.headerLink() })
  .use(markdownItToc, { listType: 'ul' });

// Ensure output directories
fs.mkdirSync(DIST, { recursive: true });
fs.mkdirSync(PDF_DIR, { recursive: true });

// Copy screenshots
const screenshotSrc = path.join(__dirname, 'screenshots');
const screenshotDst = path.join(DIST, 'screenshots');
if (fs.existsSync(screenshotSrc)) {
  fs.cpSync(screenshotSrc, screenshotDst, { recursive: true });
}

// Build index
const indexMd = fs.readFileSync(path.join(__dirname, 'index.md'), 'utf-8');
const indexHtml = TEMPLATE
  .replace('${toc}', '')
  .replace('${content}', md.render(indexMd))
  .replace('${prevLink}', '')
  .replace('${nextLink}', `<a href="${GUIDES[0].file.replace('.md', '.html')}">Getting Started →</a>`);
fs.writeFileSync(path.join(DIST, 'index.html'), indexHtml);

// Build each guide
for (let i = 0; i < GUIDES.length; i++) {
  const guide = GUIDES[i];
  const mdContent = fs.readFileSync(path.join(__dirname, guide.file), 'utf-8');

  let tocHtml = '';
  const rendered = md.render(mdContent);

  // Extract TOC from a separate render pass
  const tocRender = md.render('[[toc]]\n\n' + mdContent);
  const tocMatch = tocRender.match(/<nav class="table-of-contents">[\s\S]*?<\/nav>/);
  tocHtml = tocMatch ? tocMatch[0] : '';

  const prev = i > 0
    ? `<a href="${GUIDES[i-1].file.replace('.md', '.html')}">← ${GUIDES[i-1].title}</a>`
    : `<a href="index.html">← Home</a>`;
  const next = i < GUIDES.length - 1
    ? `<a href="${GUIDES[i+1].file.replace('.md', '.html')}">${GUIDES[i+1].title} →</a>`
    : '';

  const html = TEMPLATE
    .replace('${toc}', tocHtml)
    .replace('${content}', rendered)
    .replace('${prevLink}', prev)
    .replace('${nextLink}', next);

  const outName = guide.file.replace('.md', '.html');
  fs.writeFileSync(path.join(DIST, outName), html);
  console.log(`Built: ${outName}`);
}

// PDF generation (optional)
if (process.argv.includes('--pdf')) {
  const puppeteer = await import('puppeteer');
  const browser = await puppeteer.default.launch();

  for (const guide of GUIDES) {
    const htmlPath = path.join(DIST, guide.file.replace('.md', '.html'));
    const pdfPath = path.join(PDF_DIR, guide.file.replace('.md', '.pdf'));

    const page = await browser.newPage();
    await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle0' });
    await page.pdf({
      path: pdfPath,
      format: 'Letter',
      margin: { top: '0.75in', bottom: '0.75in', left: '0.75in', right: '0.75in' },
      printBackground: true,
    });
    await page.close();
    console.log(`PDF: ${pdfPath}`);
  }

  await browser.close();
}

console.log('Build complete.');
```

- [ ] **Step 5: Test the build**

Run: `cd C:\dcfg\docs\user-manual && node build.mjs`

Expected: `dist/` directory created with HTML files and copied screenshots.

- [ ] **Step 6: Add dist/ to .gitignore**

Append to `C:\dcfg\docs\user-manual\.gitignore`:
```
dist/
node_modules/
```

- [ ] **Step 7: Commit**

```bash
git add docs/user-manual/package.json docs/user-manual/build.mjs docs/user-manual/template.html docs/user-manual/.gitignore
git commit -m "feat: markdown-to-HTML+PDF build pipeline for user manual"
```

---

## Chunk 5: Copilot Knowledge Base

### Task 16: DMS Processes document

**Files:**
- Create: `C:\dcfg\docs\copilot-kb\dms-processes.md`

- [ ] **Step 1: Write dms-processes.md**

Complete step-by-step flows for all 4 document types. Written for Copilot consumption — clear, unambiguous, no screenshots (Copilot can't see images). Include decision points, auto-fill behaviors, and required vs optional fields at each step.

Structure:
```markdown
# DMS Document Creation Processes

## Sales Proposal (MSA)
### When to Use
### Prerequisites
### Step 1: Service Package
### Step 2: Customer & Vendor
### Step 3: Pricing & Locations
### Step 4: Review & Generate

## Work Order
### When to Use
### Prerequisites
### Step 1: Customer
### Step 2: Document Type
### Step 3: Contractor & Signer
### Step 4: Exhibit A — Lines
### Step 5: Review & Generate

## Amendment
### When to Use
### Prerequisites
### Step 1: Customer
### Step 2: Document Type + Parent WO
### Step 3: Contractor & Signer
### Step 4: Exhibit A — Lines
### Step 5: Review & Generate
### Key Difference: Parent WO auto-fills vendor and location

## Vendor MSA
### When to Use
### Prerequisites
### Step 1: Customer
### Step 2: Document Type
### Step 3: Vendor & Signer
### Step 5: Review & Generate
### Key Difference: No Exhibit A lines
```

Each step must document: what appears on screen, what the user fills in, what auto-fills, what's required, and what happens when they click Next.

- [ ] **Step 2: Commit**

```bash
git add docs/copilot-kb/dms-processes.md
git commit -m "feat: DMS processes knowledge base document for Copilot"
```

---

### Task 17: DMS Field Reference document

**Files:**
- Create: `C:\dcfg\docs\copilot-kb\dms-field-reference.md`

- [ ] **Step 1: Write dms-field-reference.md**

Every field on every wizard screen. Source this from the SPA source code (READ-ONLY). Format:

```markdown
# DMS Field Reference

## Work Order — Step 1: Customer
| Display Name | Dataverse Column | Type | Required | Notes |
|---|---|---|---|---|
| Customer | dcfg_customer_id | Lookup | Yes | Search by name |
| Program | dcfg_program_id | Lookup | No | Filters by selected customer |

## Work Order — Step 2: Document Type
| Display Name | Dataverse Column | Type | Required | Notes |
|---|---|---|---|---|
| Type | dcfg_contract_type | OptionSet | Yes | 100000000=WO, 100000001=Amendment, 100000002=Vendor MSA |
| Location | dcfg_property_id | Lookup | Yes | Filtered by customer |
| Contract Date | dcfg_contract_date | Date | Yes | Defaults to today |
| Contract Family | (derived) | — | — | Auto-set from customer TPA status. NOT user-selectable. |
...
```

Continue for all fields across all 4 flows and all steps. Include enum values with their integer codes.

- [ ] **Step 2: Commit**

```bash
git add docs/copilot-kb/dms-field-reference.md
git commit -m "feat: DMS field reference knowledge base — every field, every screen"
```

---

### Task 18: Business Rules, Status Lifecycles, Troubleshooting, Glossary

**Files:**
- Create: `C:\dcfg\docs\copilot-kb\dms-business-rules.md`
- Create: `C:\dcfg\docs\copilot-kb\dms-status-lifecycles.md`
- Create: `C:\dcfg\docs\copilot-kb\dms-troubleshooting.md`
- Create: `C:\dcfg\docs\copilot-kb\dms-glossary.md`

- [ ] **Step 1: Write dms-business-rules.md**

Document all business rules embedded in the SPA code:
- Contract family derived from customer TPA status
- Amendment parent WO auto-fills vendor + location
- `dcfg_client_name` from customer name, not location
- `dcfg_budget_committed` never written from UI
- Soft delete only (`dcfg_active_flag`)
- Submitted documents are locked — no edit/delete unless declined
- WO numbers assigned by Send Queue staff, not users
- Draft save available at any wizard step
- Multiple document versions allowed, only one submitted
- Document generation via `dcfg_document_requests` transaction table

- [ ] **Step 2: Write dms-status-lifecycles.md**

Status transitions for each entity:
- **Contracts:** WIP → Draft → Generated → Sent → Signed → Closed
- **MSAs:** WIP → Draft → Generated → Sent → Active → Closed
- **Document Requests:** Pending → Processing → Completed → Failed
- **Send Queue Items:** Ready → Sent → Confirmed → Closed

Include which transitions are manual (user-initiated) vs automatic (flow-triggered).

- [ ] **Step 3: Write dms-troubleshooting.md**

Common issues:
- "Generate button doesn't work" → check required fields
- "Can't find my draft" → check WIP Drafts on wizard landing
- "Amendment doesn't show parent WO" → select customer first
- "Document stuck in Processing" → check document request status
- "Can't edit a sent document" → submitted docs are locked

- [ ] **Step 4: Write dms-glossary.md**

All terms: MSA, WO, Amendment, Exhibit A, Cost Code, AP Code, TPA, Contract Family, Send Queue, Document Request, Signer, Owner Contact, Soft Delete, Draft/WIP.

- [ ] **Step 5: Commit**

```bash
git add docs/copilot-kb/dms-business-rules.md docs/copilot-kb/dms-status-lifecycles.md docs/copilot-kb/dms-troubleshooting.md docs/copilot-kb/dms-glossary.md
git commit -m "feat: business rules, status lifecycles, troubleshooting, and glossary for Copilot KB"
```

---

### Task 19: Copilot System Prompt

**Files:**
- Create: `C:\dcfg\docs\copilot-kb\dms-copilot-system-prompt.md`

- [ ] **Step 1: Write dms-copilot-system-prompt.md**

This is NOT a knowledge source — it is the system message pasted into Copilot Studio's configuration.

```markdown
# DCFG DMS Assistant — System Prompt

Paste this into Copilot Studio's "System message" field. Do NOT upload as a knowledge source.

---

You are the DCFG Document Management System assistant. You help staff create and manage contracts, work orders, amendments, proposals, and vendor MSAs.

## Core Principle

**You are read-only.** You can look up records, explain processes, reference field definitions, and guide users through workflows. You CANNOT create, edit, delete, or modify any record, trigger any flow, or change any system setting. If a user asks you to do something that requires a write action, explain what they need to do themselves and guide them step by step.

Your standard response when asked to make changes:
"I can show you exactly how to do that, but I can't make changes myself. Here's what to do: [step-by-step guidance]"

## Scope

You ONLY answer questions about the DCFG Document Management System:
- Creating documents: Sales Proposals, Work Orders, Amendments, Vendor MSAs
- Document lifecycle: Draft → Generated → Sent → Signed → Closed
- Send Queue operations
- Customer, vendor, and location lookups
- Field definitions and valid values
- Business rules and process guidance

You do NOT answer questions about:
- General IT support or troubleshooting
- Operations, compliance, or onboarding (separate systems)
- System administration or user management
- Power Automate flows or technical infrastructure
- Anything outside the DMS

When asked an out-of-scope question, respond:
"That's outside my area — I specialize in the DCFG document management system (contracts, proposals, work orders). For [topic], please contact [appropriate resource]."

## Tone

Professional, helpful, concise. Use the same terminology as the user manual guides. Reference specific wizard steps when guiding users (e.g., "On Step 3: Contractor & Signer, you'll see..."). Never use jargon the user manual doesn't define.

## Dataverse Access

You can query these tables (READ-ONLY):
- dcfg_contracts — contract records
- dcfg_msas — master service agreements
- dcfg_customers — customer information
- dcfg_vendors — vendor information
- dcfg_properties — locations (NOTE: entity set is dcfg_properties, not dcfg_propertys)
- dcfg_document_requests — document generation status
- dcfg_ap_cost_codes — AP cost code lookups

You CANNOT access: audit logs, user records, config tables, flow metadata, or any other table.
```

- [ ] **Step 2: Commit**

```bash
git add docs/copilot-kb/dms-copilot-system-prompt.md
git commit -m "feat: Copilot Studio system prompt — read-only DMS specialist"
```

---

## Chunk 6: Resource Site Publishing Skill

### Task 20: Create the resource-site-publish Claude skill

**Files:**
- Create: `C:\Users\JosephCameron\.claude\skills\resource-site-publish\skill.md`
- Create: `C:\Users\JosephCameron\.claude\skills\resource-site-publish\data\site-config.json`
- Create: `C:\Users\JosephCameron\.claude\skills\resource-site-publish\templates\review-item.html`
- Create: `C:\Users\JosephCameron\.claude\skills\resource-site-publish\templates\link-card.html`
- Create: `C:\Users\JosephCameron\.claude\skills\resource-site-publish\templates\guide-page.html`

- [ ] **Step 1: Create site-config.json**

```json
{
  "_comment": "OPERATOR-MANAGED — Claude proposes changes, operator approves",
  "siteUrl": "PENDING_PROVISIONING",
  "websiteId": "PENDING_PROVISIONING",
  "environment": "Prod",
  "orgUrl": "org06f5de0b.crm.dynamics.com",
  "pacAuthIndex": 3,
  "pacAuthRestoreIndex": 1,
  "solutionName": "DCFGSystemTest",
  "portalDomain": "PENDING_PROVISIONING.powerappsportals.com"
}
```

Values will be populated after the operator provisions the Power Pages site.

- [ ] **Step 2: Create HTML templates**

**guide-page.html** — wrapper for publishing built HTML guides to Power Pages:
```html
<div class="guide-page">
  <div class="guide-header">
    <h1>{{TITLE}}</h1>
    <p class="guide-subtitle">DCFG Document Management System — User Guide</p>
  </div>
  <div class="guide-content">
    {{CONTENT}}
  </div>
  <div class="guide-nav">
    {{PREV_LINK}}
    {{NEXT_LINK}}
  </div>
</div>
```

**review-item.html:**
```html
<div class="review-item">
  <div class="review-header">
    <h2>📌 {{TITLE}}</h2>
    <span class="review-date">Posted {{DATE}}</span>
  </div>
  <div class="review-body">
    <p>{{DESCRIPTION}}</p>
    <a href="{{URL}}" target="_blank" class="review-link">🔗 {{URL}}</a>
    {{#CHECKLIST}}
    <div class="review-checklist">
      <strong>What to check:</strong>
      <ul>
        {{CHECKLIST_ITEMS}}
      </ul>
    </div>
    {{/CHECKLIST}}
  </div>
</div>
```

**link-card.html:**
```html
<div class="link-card">
  <span class="link-icon">{{ICON}}</span>
  <div class="link-body">
    <strong>{{TITLE}}</strong>
    <p>{{DESCRIPTION}}</p>
    <a href="{{URL}}" target="_blank">🔗 {{URL_DISPLAY}}</a>
  </div>
</div>
```

- [ ] **Step 3: Write skill.md**

```markdown
---
name: resource-site-publish
description: Publish content to the DCFG internal resource site (Power Pages in Prod). Manages guides, review items, links, and tools. Uses Dataverse API to create/update powerpagecomponent records.
---

# Resource Site Publisher

## When to Use
Trigger on: "publish to resource site", "share with the team", "add to resources",
"put on the internal site", "send for review", "update the resource site",
"take down [item] from resource site"

## Site Configuration
Read `data/site-config.json` for websiteId, org URL, and pac auth indexes.
If websiteId is "PENDING_PROVISIONING", inform the operator that the Power Pages
site must be provisioned first.

## Silo Rules
- This site is COMPLETELY SEPARATE from the SPA (C:\DCFG\spa\)
- Do NOT use `pac pages upload-code-site` — that is SPA-only
- Content is published via Dataverse API (powerpagecomponent records)
- Always include `powerpagesiteid` lookup in every record
- Always restore pac auth to index 1 (Test) after deployment

## Content Types

### Review Item
For sharing sites/pages for staff to review.
- Use template: `templates/review-item.html`
- Replace: {{TITLE}}, {{DATE}}, {{DESCRIPTION}}, {{URL}}, {{CHECKLIST_ITEMS}}
- Publish to /reviews section

### Link Card
For adding quick-reference links to the tools page.
- Use template: `templates/link-card.html`
- Replace: {{ICON}}, {{TITLE}}, {{DESCRIPTION}}, {{URL}}, {{URL_DISPLAY}}
- Publish to /tools section

### Guide Page
For publishing user manual HTML.
- Build guides first: `cd C:\dcfg\docs\user-manual && node build.mjs`
- Upload HTML from `dist/` directory
- Upload screenshots as web file powerpagecomponent records
- Publish to /guides section

## Publishing Steps

1. Read site-config.json for websiteId and auth
2. Switch pac auth: `pac auth select --index 3`
3. Get auth token: `pac auth token`
4. Create/update powerpagecomponent via Dataverse Web API:
   - POST to `https://{orgUrl}/api/data/v9.2/powerpagecomponents`
   - Include `powerpagesiteid` lookup
   - Set `content` field with HTML
   - Set `name` field for identification
5. Restore pac auth: `pac auth select --index 1`
6. Report the page URL to the operator

## Removal
Set `statecode = 1` (inactive) via PATCH. NEVER delete records.

## After Publishing
Always provide:
- Direct URL to the published page
- Reminder to clear portal cache if needed
- Confirmation of pac auth restored to Test
```

- [ ] **Step 4: Commit**

```bash
git add C:\Users\JosephCameron\.claude\skills\resource-site-publish/
git commit -m "feat: resource-site-publish Claude skill with templates and config"
```

---

## Chunk 7: AI Operator Instructions

This chunk creates the documentation that enables a **second AI** (another Claude instance, or any agentic worker) to use the complete resource site system independently.

### Task 21: AI Operator Manual

**Files:**
- Create: `C:\dcfg\docs\resource-site\AI-OPERATOR-MANUAL.md`

- [ ] **Step 1: Write the AI Operator Manual**

This document is the complete instruction set for a second AI to operate the resource site system. It must be self-contained — the AI reading this has zero prior context.

```markdown
# DCFG Resource Site — AI Operator Manual

You are operating the DCFG internal resource site. This document tells you
everything you need to know to publish content, update guides, and manage
the site. Read this completely before taking any action.

## What This System Is

An internal utility site hosted on Power Pages (Microsoft) in the DCFG Prod
environment. Staff access it at a *.powerappsportals.com URL with no login
required. It contains:

1. **User Guides** — step-by-step documentation for the DCFG Document
   Management System with screenshots
2. **Review Items** — links to sites/pages shared for staff review
3. **Tools & Links** — quick-reference resources
4. **AI Assistant** — Copilot Studio chat (managed separately in Copilot Studio)

## Your Role

You are the **publisher**. You create, update, and deactivate content on the
resource site when directed by the operator (Joseph Cameron). You do NOT:

- Modify the SPA codebase (`C:\DCFG\spa\` — this is a separate silo)
- Write to any Dataverse business tables (the resource site is content-only)
- Modify Copilot Studio configuration (that's an operator step)
- Activate the Power Pages site (you create it inactive, operator activates)
- Take actions without operator direction

## Operating Modes

The site has two modes. **Always assume Base Mode unless the operator has confirmed Copilot is configured.**

### Base Mode (default)
Guides + Reviews + Tools. The `/assistant` page shows a "coming soon" message.
No Copilot dependency. Fully functional.

### Copilot Mode (operator-activated)
Everything in Base Mode, plus the `/assistant` page embeds a Copilot Studio chat widget.
The operator will provide you with the embed snippet when ready. Until then, do not
reference Copilot as active in any published content.

## System Architecture

```
┌─────────────────────────────┐
│  YOU (AI Publisher)          │
│  - Builds HTML from Markdown │
│  - Publishes via Dataverse   │
│  - Manages content lifecycle │
└──────────┬──────────────────┘
           │ writes powerpagecomponent records
           ▼
┌─────────────────────────────┐
│  Resource Site (Power Pages) │
│  - *.powerappsportals.com    │
│  - Anonymous access          │
│  - Static HTML content       │
└──────────┬──────────────────┘
           │ staff reads
           ▼
┌─────────────────────────────┐
│  Staff (read-only consumers) │
└─────────────────────────────┘
```

## File Locations

| What | Where |
|------|-------|
| User manual source (Markdown) | `C:\dcfg\docs\user-manual\*.md` |
| Screenshots | `C:\dcfg\docs\user-manual\screenshots\` |
| Build script | `C:\dcfg\docs\user-manual\build.mjs` |
| Built HTML output | `C:\dcfg\docs\user-manual\dist\` |
| Built PDF output | `C:\dcfg\docs\user-manual\dist\pdf\` |
| Copilot knowledge base | `C:\dcfg\docs\copilot-kb\` |
| Playwright screenshot tests | `C:\dcfg\tests\user-manual\` |
| Demo data constants | `C:\dcfg\tests\user-manual\demo-data.ts` |
| Site config | `C:\Users\JosephCameron\.claude\skills\resource-site-publish\data\site-config.json` |
| HTML templates | `C:\Users\JosephCameron\.claude\skills\resource-site-publish\templates\` |
| This manual | `C:\dcfg\docs\resource-site\AI-OPERATOR-MANUAL.md` |

## Common Operations

### Publishing a Review Item

When the operator says "publish X for the team to review":

1. Read site config: `C:\Users\JosephCameron\.claude\skills\resource-site-publish\data\site-config.json`
2. Verify `websiteId` is not "PENDING_PROVISIONING" — if it is, tell the operator
3. Read template: `templates/review-item.html`
4. Replace placeholders: {{TITLE}}, {{DATE}} (today), {{DESCRIPTION}}, {{URL}}, {{CHECKLIST_ITEMS}}
5. Authenticate:
   ```bash
   pac auth select --index 3
   ```
6. Get token:
   ```bash
   pac auth token
   ```
7. Create powerpagecomponent record:
   ```powershell
   $token = (pac auth token --format json | ConvertFrom-Json).token
   $body = @{
     name = "review-YYYY-MM-DD-slug"
     powerpagesiteid = "WEBSITEID_FROM_CONFIG"
     content = "RENDERED_HTML"
   } | ConvertTo-Json -Depth 10

   curl.exe -X POST "https://ORG_URL/api/data/v9.2/powerpagecomponents" `
     -H "Authorization: Bearer $token" `
     -H "Content-Type: application/json" `
     -d $body
   ```
8. Restore auth:
   ```bash
   pac auth select --index 1
   ```
9. Report to operator: provide the page URL and confirm auth restored.

### Updating User Manual Guides

When the operator says "update the user manual" or after SPA changes:

1. Re-run Playwright screenshot tests:
   ```bash
   cd C:\dcfg\tests\user-manual
   npx playwright test --project=auth-setup --headed
   # Operator authenticates via Windows Hello
   npx playwright test --headed
   ```
2. Review screenshots in `C:\dcfg\docs\user-manual\screenshots\` — confirm they look correct
3. Update Markdown guides if wizard behavior changed
4. Build HTML:
   ```bash
   cd C:\dcfg\docs\user-manual
   node build.mjs
   node build.mjs --pdf   # optional: also generate PDFs
   ```
5. Publish updated HTML to Power Pages (same powerpagecomponent PATCH pattern)
6. Update knowledge base docs in `C:\dcfg\docs\copilot-kb\` if processes changed
7. Remind operator to re-upload KB docs to Copilot Studio if they changed

### Adding a Link to the Tools Page

1. Read the current /tools page content from Dataverse
2. Read template: `templates/link-card.html`
3. Replace placeholders: {{ICON}}, {{TITLE}}, {{DESCRIPTION}}, {{URL}}
4. Append the new card to the existing tools page HTML
5. PATCH the powerpagecomponent record with updated content
6. Restore pac auth to index 1

### Removing Content

When the operator says "take down X":

1. Find the powerpagecomponent record by name
2. PATCH with `statecode = 1` (inactive)
3. NEVER use DELETE — soft deactivation only
4. Confirm removal to operator

## Rules You Must Follow

1. **SILO** — This system has NO connection to the SPA (`C:\DCFG\spa\`). Never read, write, or reference SPA code as part of resource site operations. The SPA exists in a different universe.

2. **READ-ONLY TO DATAVERSE** — You publish content to the resource site via powerpagecomponent records. You do NOT read or write to business tables (dcfg_contracts, dcfg_customers, etc.). That's Copilot's job.

3. **OPERATOR-DIRECTED** — Publish only what the operator asks. Don't add content proactively. Don't remove content without direction.

4. **SOFT DELETE ONLY** — Deactivate records (statecode=1). Never delete.

5. **RESTORE AUTH** — After every Prod deployment, run `pac auth select --index 1` to restore to Test environment.

6. **TEMPLATES** — Use the HTML templates in the skill's templates/ directory. Don't invent new layouts.

7. **SCREENSHOTS FROM TEST ONLY** — Playwright runs against the Test environment. Screenshots are static images. They cross to Prod only as embedded content in HTML pages.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `websiteId` is PENDING_PROVISIONING | Tell the operator — they need to provision the Power Pages site in the admin center |
| pac auth token fails | Run `pac auth list` — check index 3 exists for Prod |
| Playwright auth expires | Re-run `npx playwright test --project=auth-setup --headed` |
| Screenshots look wrong | Check demo data exists in Test env — see `docs/user-manual/DEMO-DATA-SETUP.md` |
| Build fails | Check `cd C:\dcfg\docs\user-manual && npm install` has been run |
| 403 on Dataverse API | Check pac auth token is fresh and has correct permissions |

## Handoff Checklist

Before your session ends, verify:

- [ ] pac auth restored to index 1 (Test)
- [ ] Any published content confirmed accessible at the portal URL
- [ ] Operator informed of all changes made
- [ ] No SPA files were touched
```

- [ ] **Step 2: Commit**

```bash
git add docs/resource-site/AI-OPERATOR-MANUAL.md
git commit -m "feat: AI operator manual — complete instructions for second AI to operate resource site"
```

---

### Task 22: Quick-reference card for the AI

**Files:**
- Create: `C:\dcfg\docs\resource-site\AI-QUICK-REFERENCE.md`

- [ ] **Step 1: Write the quick reference**

A single-page cheat sheet an AI can load at session start for fast context.

```markdown
# DCFG Resource Site — AI Quick Reference

**What:** Internal utility site on Power Pages (Prod). Guides, reviews, tools, Copilot assistant.
**Where:** *.powerappsportals.com (check site-config.json for exact URL)
**Who:** You publish. Staff reads. Copilot answers questions. Operator directs.
**Auth:** pac auth index 3 (Prod), always restore to index 1 (Test) after.

## Commands

```bash
# Build guides
cd C:\dcfg\docs\user-manual && node build.mjs

# Capture screenshots
cd C:\dcfg\tests\user-manual && npx playwright test --headed

# Deploy auth
pac auth select --index 3
pac auth token
# ... do work ...
pac auth select --index 1  # ALWAYS RESTORE
```

## Content Types
- **Review:** templates/review-item.html → /reviews
- **Link:** templates/link-card.html → /tools
- **Guide:** build.mjs output → /guides

## Modes
- **Base Mode** (default): Guides + Reviews + Tools. No Copilot.
- **Copilot Mode** (operator activates): Base + AI Assistant on /assistant page.
- Assume Base Mode unless operator confirms Copilot is configured.

## Hard Rules
1. SILO — never touch C:\DCFG\spa\
2. READ-ONLY — never write to business Dataverse tables
3. SOFT DELETE — statecode=1, never DELETE
4. OPERATOR-DIRECTED — publish only what's asked
5. RESTORE AUTH — pac auth select --index 1 after every deploy
6. INACTIVE CREATION — you create sites/content inactive, operator activates
7. BASE MODE DEFAULT — don't reference Copilot as active unless operator confirms

## Key Files
- Site config: `~/.claude/skills/resource-site-publish/data/site-config.json`
- Full manual: `C:\dcfg\docs\resource-site\AI-OPERATOR-MANUAL.md`
- Spec: `C:\dcfg\docs\superpowers\specs\2026-03-30-dcfg-resources-site-design.md`
```

- [ ] **Step 2: Commit**

```bash
git add docs/resource-site/AI-QUICK-REFERENCE.md
git commit -m "feat: AI quick-reference card for resource site operations"
```

---

## Execution Order & Dependencies

```
Task 0:    Create Power Pages site INACTIVE (first — establishes websiteId)
Task 1-4:  Playwright infrastructure (parallel-safe, after Task 0)
Task 5-9:  Screenshot specs (depends on Tasks 1-4, demo data created by test suite)
Task 10-14: User manual guides (can start in parallel with Tasks 5-9 — screenshots added later)
Task 15:   Build toolchain (depends on Tasks 10-14 — reads all guide .md files)
Task 16-19: Copilot knowledge base (parallel with Tasks 10-15 — reads SPA source)
Task 20:   Publishing skill (parallel with Tasks 16-19)
Task 21-22: AI operator manual (depends on all above — references final paths)
```

**Parallelization opportunities:**
- Tasks 1-4 (infrastructure) in parallel
- Tasks 5-9 (screenshot specs) — serial within each, but independent across flows
- Tasks 10-14 (guides) alongside Tasks 5-9
- Tasks 16-19 (KB) alongside Tasks 10-15
- Task 20 (skill) alongside Tasks 16-19

## Pre-Implementation Prerequisites

None. Claude creates the site inactive, demo data is created by the test suite, and Copilot is optional.

## Post-Implementation — Operator Actions

After all tasks are complete, the operator:

- [ ] **Reviews the inactive site** and all content
- [ ] **Activates the Power Pages site** when satisfied (statecode=0)
- [ ] **Optionally enables Copilot Mode** — create Copilot in Copilot Studio, upload KB docs, configure system prompt, provide embed snippet to Claude
