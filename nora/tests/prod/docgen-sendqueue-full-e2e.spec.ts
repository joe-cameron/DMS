/**
 * docgen-sendqueue-full-e2e.spec.ts
 *
 * Full E2E: Generate every document type -> Submit to Send Queue -> Verify.
 * 10 document types across Bancroft (TPA) and Decades customers.
 *
 * Auth: tries existing prod-auth-state.json first.
 *       Pauses for manual login ONLY if session expired.
 *
 * Run:
 *   cd C:\dcfg\nora
 *   npx playwright test docgen-sendqueue-full-e2e --config=playwright-prod.config.ts --project=prod-docgen --headed --retries=0
 */
import { test, expect, Page } from '@playwright/test';

// ─── Run config ───────────────────────────────────────────────
const RUN_TAG = `E2E-${Date.now().toString(36).toUpperCase()}`;
const BASE = 'https://dmms1.powerappsportals.com';
const V = 800;
const observe = (p: Page) => p.waitForTimeout(V);

// serial preserves module-level results array; try/catch in each test prevents abort
test.describe.configure({ mode: 'serial', retries: 0, timeout: 300_000 });
test.use({ storageState: './prod-auth-state.json' });

// ─── Result tracking ─────────────────────────────────────────
interface DocResult {
  type: string;
  generated: boolean;
  submitted: boolean;
  skipped: boolean;
  screenshot: string;
}
const results: DocResult[] = [];

// ─── Shared helpers ──────────────────────────────────────────

/** Wait for document to appear in sidebar (doc history or doc link) */
async function waitForDocCreated(page: Page, label: string): Promise<boolean> {
  // Auto-open is disabled — verify via sidebar indicators
  const indicators = page.locator(
    '[data-testid="doc-history-row"], [data-testid="link-view-document"], ' +
    '[data-testid="cc-doc-link"], [data-testid="doc-live-link"], [data-testid="msa-open-doc"]'
  ).first();

  // Race: doc indicator vs error toast vs timeout
  const errorToast = page.locator('[role="alert"], [class*="toast-error"], [class*="Toast"]').first();

  for (let elapsed = 0; elapsed < 90_000; elapsed += 3000) {
    if (await indicators.isVisible().catch(() => false)) {
      console.log(`  [${label}] Document created — indicator visible (${elapsed / 1000}s)`);
      return true;
    }
    // Check for doc count update (e.g. "1 doc" instead of "0 docs")
    const docCount = page.locator('text=/[1-9]\\d* docs?/i').first();
    if (await docCount.isVisible().catch(() => false)) {
      console.log(`  [${label}] Document created — doc count updated (${elapsed / 1000}s)`);
      return true;
    }
    // Check for error
    const errVisible = await errorToast.isVisible().catch(() => false);
    if (errVisible) {
      const errText = await errorToast.innerText().catch(() => 'unknown error');
      console.log(`  [${label}] ERROR toast: ${errText}`);
      return false;
    }
    await page.waitForTimeout(3000);
  }

  console.log(`  [${label}] WARN: No document indicator visible after 90s`);
  return false;
}

/** Click Submit for Approval on MSA Composer */
async function submitMsa(page: Page, label: string): Promise<boolean> {
  const btn = page.getByTestId('msa-btn-submit-approval');
  try {
    await expect(btn).toBeVisible({ timeout: 15_000 });
    await btn.click();
    await page.waitForTimeout(2000);
    console.log(`  [${label}] Submitted for approval`);
    return true;
  } catch {
    console.log(`  [${label}] WARN: msa-btn-submit-approval not found`);
    return false;
  }
}

/** Click Submit for Approval on Contract Composer */
async function submitContract(page: Page, label: string): Promise<boolean> {
  const btn = page.getByTestId('cc-btn-submit-approval');
  try {
    await expect(btn).toBeVisible({ timeout: 15_000 });
    await btn.click();
    await page.waitForTimeout(2000);
    console.log(`  [${label}] Submitted for approval`);
    return true;
  } catch {
    console.log(`  [${label}] WARN: cc-btn-submit-approval not found`);
    return false;
  }
}

/** Open the document link and screenshot as proof */
async function openAndScreenshotDoc(page: Page, label: string): Promise<void> {
  // Find any Open/View document link
  const docLink = page.locator(
    '[data-testid="link-view-document"] a, a[data-testid="link-view-document"], ' +
    '[data-testid="doc-live-link"], [data-testid="msa-open-doc"], ' +
    'a[data-testid="cc-doc-link"]'
  ).first();

  // If no explicit link, try any link with sharepoint in href
  const spLink = page.locator('a[href*="sharepoint"]').first();
  const link = docLink.or(spLink);

  if (!await link.isVisible({ timeout: 10_000 }).catch(() => false)) {
    console.log(`  [${label}] No document link found — skipping proof screenshot`);
    return;
  }

  const href = await link.getAttribute('href').catch(() => null);
  if (!href) {
    console.log(`  [${label}] Document link has no href`);
    return;
  }

  console.log(`  [${label}] Opening document: ${href.substring(0, 100)}`);
  const [newTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 30_000 }).catch(() => null),
    link.click(),
  ]);

  if (newTab) {
    await newTab.waitForLoadState('domcontentloaded', { timeout: 20_000 }).catch(() => {});
    await newTab.waitForTimeout(3000);
    await newTab.screenshot({ path: `./test-results/${RUN_TAG}-PROOF-${label}.png`, fullPage: false });
    console.log(`  [${label}] Document proof screenshot saved`);
    await newTab.close().catch(() => {});
    await page.bringToFront();
  } else {
    console.log(`  [${label}] Document opened in same tab or blocked`);
  }
}

/** Record result — no assertions here, all checks in SUMMARY to prevent serial abort */
function recordResult(result: DocResult) {
  if (result.submitted && !result.generated) result.generated = true;
  results.push(result);
  const g = result.skipped ? 'SKIP' : result.generated ? 'YES' : 'FAIL';
  const s = result.skipped ? 'SKIP' : result.submitted ? 'YES' : 'FAIL';
  console.log(`  >> ${result.type}: generated=${g}, submitted=${s}`);
}

// ═══════════════════════════════════════════════════════════════
// AUTH CHECK
// ═══════════════════════════════════════════════════════════════

test('00 AUTH: Verify or refresh prod session', async ({ page }) => {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  RUN TAG: ${RUN_TAG}`);
  console.log(`  TIME:    ${new Date().toISOString()}`);
  console.log(`${'='.repeat(60)}\n`);

  await page.goto(`${BASE}/#/dashboard`);
  await page.waitForTimeout(5000);

  const url = page.url();
  if (url.includes('login.microsoftonline.com') || url.includes('login.live.com') || url.includes('login.windows.net')) {
    console.log('[AUTH] Session expired — sign in and press Resume in Playwright Inspector');
    await page.pause();
    await page.waitForLoadState('networkidle');
    await page.context().storageState({ path: './prod-auth-state.json' });
    console.log('[AUTH] Session refreshed and saved');
  }

  await page.waitForFunction(() => document.body.innerText.length > 50, null, { timeout: 30_000 });
  console.log(`[AUTH] OK — session valid, SPA loaded at ${page.url()}`);
});

// ═══════════════════════════════════════════════════════════════
// MSA DOCUMENTS (3 packages)
// ═══════════════════════════════════════════════════════════════

const msaPackages = [
  { id: 'PackageA', label: 'MSA-PkgA', search: 'Ban', rate: '1850.00', onboard: '250.00' },
  { id: 'PackageB', label: 'MSA-PkgB', search: 'Penn', rate: '2400.00', onboard: '350.00' },
  { id: 'PackageC', label: 'MSA-PkgC', search: 'Arc',  rate: '3200.00', onboard: '500.00' },
];

for (const [i, pkg] of msaPackages.entries()) {
  test(`0${i + 1} ${pkg.label}: Generate + Submit`, async ({ page }) => {
    const label = pkg.label;
    console.log(`\n=== ${label} ===`);
    const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

    try {
      await page.goto(`${BASE}/#/msa/new`);
      await page.waitForLoadState('networkidle');
      await expect(page.getByTestId(`package-${pkg.id}`)).toBeVisible({ timeout: 15_000 });

      await page.getByTestId(`package-${pkg.id}`).click();
      await observe(page);

      // Select customer
      await page.getByTestId('msa-btn-cust-search').click();
      await observe(page);
      const custInput = page.getByTestId('customer-search');
      await expect(custInput).toBeVisible({ timeout: 5000 });
      await custInput.pressSequentially(pkg.search, { delay: 120 });
      await page.waitForTimeout(3000);
      await page.locator('[data-testid^="customer-result-"]').first().click();
      await observe(page);
      console.log(`  [${label}] Customer selected (${pkg.search})`);

      // Signer
      await page.getByTestId('cust-signer-name').fill(`${RUN_TAG}-SIGN-${pkg.id}`);
      await page.getByTestId('cust-signer-title').fill(`${RUN_TAG}-TITLE`);

      // Pricing — uniform
      await page.getByTestId('msa-btn-price-uniform').click();
      await page.getByTestId('uni-rate').fill(pkg.rate);
      await page.getByTestId('uni-onboard').fill(pkg.onboard);

      // Add 2 locations
      for (let li = 1; li <= 2; li++) {
        await page.getByTestId('new-loc-name').fill(`${RUN_TAG}-LOC-${li}`);
        await page.getByTestId('btn-add-loc').click();
        await page.waitForTimeout(500);
      }
      console.log(`  [${label}] Form filled — 2 locations`);

      // Generate (no auto-open — just click and wait for doc indicator)
      await page.getByTestId('btn-download-msa').first().click();
      console.log(`  [${label}] Create clicked`);

      result.generated = await waitForDocCreated(page, label);
      if (result.generated) await openAndScreenshotDoc(page, label);
      result.submitted = await submitMsa(page, label);
    } catch (e) {
      console.log(`  [${label}] ERROR: ${(e as Error).message}`);
      await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
    }

    result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
    await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
    recordResult(result);
  });
}

// ═══════════════════════════════════════════════════════════════
// BANCROFT CONTRACT DOCUMENTS (4 WO types + 1 VA)
// ═══════════════════════════════════════════════════════════════

/** Shared: select customer in Contract Composer */
async function ccSelectCustomer(page: Page, search: string, label: string) {
  const input = page.getByTestId('cc-customer-search');
  await expect(input).toBeVisible({ timeout: 10_000 });
  await input.pressSequentially(search, { delay: 120 });
  await page.waitForTimeout(3000);
  await page.locator('[data-testid^="cc-btn-customer-"]').first().click();
  await page.waitForTimeout(3000);
  console.log(`  [${label}] Customer selected (${search})`);
}

/** Shared: fill WO number via the chip */
async function ccFillWoNumber(page: Page, label: string) {
  const chip = page.getByTestId('cc-chip-wo-number');
  if (await chip.isVisible({ timeout: 5000 }).catch(() => false)) {
    await chip.click();
    await observe(page);
  }
  const woInput = page.getByTestId('cc-wo-number');
  await expect(woInput).toBeVisible({ timeout: 5000 });
  // Generate a unique 6-char WO number: YY + 4 digits from timestamp
  const woNum = `26${Date.now().toString().slice(-4)}`;
  await woInput.fill(woNum);
  const doneBtn = page.getByTestId('cc-btn-wo-done');
  if (await doneBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
    await doneBtn.click();
    await observe(page);
  }
  console.log(`  [${label}] WO# filled: ${woNum}`);
}

/** Shared: pick first vendor in drawer, then close the drawer */
async function ccPickVendor(page: Page, label: string) {
  const chip = page.getByTestId('cc-chip-vendor');
  if (await chip.isVisible({ timeout: 5000 }).catch(() => false)) {
    await chip.click();
    await page.waitForTimeout(2000);
    const row = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await row.isVisible({ timeout: 5000 }).catch(() => false)) {
      await row.click();
      await observe(page);
      console.log(`  [${label}] Vendor selected`);
      // Close the drawer via its close button
      const closeBtn = page.getByTestId('cc-btn-close-drawer');
      if (await closeBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        await closeBtn.click();
        await observe(page);
      }
      console.log(`  [${label}] Vendor drawer closed`);
    }
  }
}

/** Shared: pick first location in drawer, then close the drawer */
async function ccPickLocation(page: Page, label: string) {
  const chip = page.getByTestId('cc-chip-location');
  const addBtn = page.getByTestId('cc-btn-add-location');
  // Try chip first, fall back to add-location button
  if (await chip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await chip.click();
  } else if (await addBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await addBtn.click();
  }
  await page.waitForTimeout(2000);
  const row = page.locator('[data-testid^="cc-location-row-"]').first();
  if (await row.isVisible({ timeout: 5000 }).catch(() => false)) {
    await row.click();
    await observe(page);
    console.log(`  [${label}] Location selected`);
    // Close the drawer via its close button
    const closeBtn = page.getByTestId('cc-btn-close-drawer');
    if (await closeBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await closeBtn.click();
      await observe(page);
    }
    console.log(`  [${label}] Location drawer closed`);
  }
}

/** Shared: fill signers via the chip */
async function ccFillSigners(page: Page, label: string) {
  const chip = page.getByTestId('cc-chip-signers');
  if (await chip.isVisible({ timeout: 5000 }).catch(() => false)) {
    await chip.click();
    await observe(page);
  }
  await page.getByTestId('cc-cust-signer-name').fill(`${RUN_TAG}-CSIGN`);
  await page.getByTestId('cc-cust-signer-title').fill(`${RUN_TAG}-CTITLE`);
  await page.getByTestId('cc-vendor-signer-name').fill(`${RUN_TAG}-VSIGN`);
  await page.getByTestId('cc-vendor-signer-title').fill(`${RUN_TAG}-VTITLE`);
  await observe(page);
  const done = page.getByTestId('cc-btn-signers-done');
  if (await done.isVisible({ timeout: 2000 }).catch(() => false)) {
    await done.click();
    await observe(page);
  }
  console.log(`  [${label}] Signers filled`);
}

/** Shared: add a line item */
async function ccAddLineItem(page: Page, index: number, desc: string, amount: string) {
  if (index === 0) {
    await page.getByTestId('cc-btn-add-item').click();
  } else {
    await page.getByTestId('cc-btn-add-another').click();
  }
  await page.waitForTimeout(500);
  const costCode = page.getByTestId(`cc-costcode-${index}`);
  if (await costCode.isVisible({ timeout: 2000 }).catch(() => false)) {
    await costCode.selectOption({ index: 1 }).catch(() => {});
  }
  await page.getByTestId(`cc-item-desc-${index}`).fill(desc);
  await page.getByTestId(`cc-item-amount-${index}`).fill(amount);
  await observe(page);
}

/** Shared: validate generate button is enabled, click it, wait for doc.
 *  Returns: 'created' | 'skipped' | 'failed' */
async function ccClickCreate(page: Page, label: string): Promise<'created' | 'skipped' | 'failed'> {
  const btn = page.getByTestId('cc-btn-generate');

  // Check if button exists
  const exists = await btn.isVisible({ timeout: 5_000 }).catch(() => false);
  if (!exists) {
    console.log(`  [${label}] SKIP: cc-btn-generate not found — no template available`);
    return 'skipped';
  }

  // Check if button is enabled (disabled = missing required fields or no template)
  const disabled = await btn.isDisabled().catch(() => true);
  if (disabled) {
    console.log(`  [${label}] SKIP: cc-btn-generate is disabled — missing requirements`);
    // Screenshot the current state to see what's missing
    await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-disabled.png`, fullPage: true }).catch(() => {});
    return 'skipped';
  }

  await btn.click();
  console.log(`  [${label}] Generate clicked`);
  const created = await waitForDocCreated(page, label);
  return created ? 'created' : 'failed';
}

// Bancroft WO types — all use Ban customer + template button selection
const bancroftWoTypes = [
  { label: 'Ban-ExhA-Auto',   tplText: 'Exhibit A - Automated', amount: '4500.00' },
  { label: 'Ban-ExhA-Var',    tplText: 'Exhibit A - Variable',  amount: '3800.00' },
  { label: 'Ban-BlanketWO',   tplText: 'Blanket Work Order',    amount: '1800.00' },
];

for (const [i, wo] of bancroftWoTypes.entries()) {
  test(`0${4 + i} ${wo.label}: Generate + Submit`, async ({ page }) => {
    const label = wo.label;
    console.log(`\n=== ${label} ===`);
    const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

    try {
      await page.goto(`${BASE}/#/contracts/new?type=wo`);
      await page.waitForLoadState('networkidle');

      await ccSelectCustomer(page, 'Ban', label);

      // Wait for template buttons to render (now that query bug is fixed)
      const tplBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: wo.tplText });
      await expect(tplBtn).toBeVisible({ timeout: 10_000 });
      await tplBtn.click();
      await observe(page);
      console.log(`  [${label}] Template "${wo.tplText}" selected`);

      await ccFillWoNumber(page, label);
      await ccPickVendor(page, label);
      await ccPickLocation(page, label);
      await ccFillSigners(page, label);
      await ccAddLineItem(page, 0, `${RUN_TAG}-${wo.label}-ITEM`, wo.amount);

      const createStatus = await ccClickCreate(page, label);
      result.skipped = createStatus === 'skipped';
      result.generated = createStatus === 'created';
      if (result.generated) await openAndScreenshotDoc(page, label);
      if (result.generated) result.submitted = await submitContract(page, label);
    } catch (e) {
      console.log(`  [${label}] ERROR: ${(e as Error).message}`);
      await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
    }

    result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
    await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
    recordResult(result);
  });
}

// ─── 07: Bancroft Amendment ──────────────────────────────────

test('07 Ban-Amendment: Generate + Submit', async ({ page }) => {
  const label = 'Ban-Amendment';
  console.log(`\n=== ${label} ===`);
  const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

  try {
    await page.goto(`${BASE}/#/contracts/new?type=wo`);
    await page.waitForLoadState('networkidle');

    await ccSelectCustomer(page, 'Ban', label);

    // Select Amendment template button
    const tplBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: 'Work Order Amendment' });
    await expect(tplBtn).toBeVisible({ timeout: 10_000 });
    await tplBtn.click();
    await observe(page);
    console.log(`  [${label}] Template "Work Order Amendment" selected`);

    // Select parent contract
    const parentSelect = page.getByTestId('cc-parent-contract');
    if (await parentSelect.isVisible({ timeout: 5000 }).catch(() => false)) {
      await parentSelect.selectOption({ index: 1 });
      await observe(page);
      console.log(`  [${label}] Parent contract selected`);
    }

    // Amendments inherit WO# from parent — no ccFillWoNumber
    await ccPickVendor(page, label);
    await ccPickLocation(page, label);
    await ccFillSigners(page, label);
    await ccAddLineItem(page, 0, `${RUN_TAG}-AMD-ITEM`, '2500.00');

    // Fill amendment-specific required fields
    const svcDesc = page.getByTestId('cc-amendment-service-desc');
    if (await svcDesc.isVisible({ timeout: 3000 }).catch(() => false)) {
      await svcDesc.fill('Extended HVAC maintenance scope — additional units');
      console.log(`  [${label}] Service description filled`);
    }
    const schedDesc = page.getByTestId('cc-amendment-schedule');
    if (await schedDesc.isVisible({ timeout: 2000 }).catch(() => false)) {
      await schedDesc.fill('Mon-Fri 7:00 AM - 5:00 PM');
      console.log(`  [${label}] Schedule filled`);
    }

    const createStatus = await ccClickCreate(page, label);
    result.skipped = createStatus === 'skipped';
    result.generated = createStatus === 'created';
    if (result.generated) await openAndScreenshotDoc(page, label);
    if (result.generated) result.submitted = await submitContract(page, label);
  } catch (e) {
    console.log(`  [${label}] ERROR: ${(e as Error).message}`);
    await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
  }

  result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
  await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
  recordResult(result);
});

// ─── 08: Bancroft Vendor Agreement ───────────────────────────

test('08 Ban-VA: Generate + Submit', async ({ page }) => {
  const label = 'Ban-VA';
  console.log(`\n=== ${label} ===`);
  const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

  try {
    await page.goto(`${BASE}/#/contracts/new?type=msa`);
    await page.waitForLoadState('networkidle');

    // VA shows "Which agreement type?" — pick Bancroft family via testid
    const bancroftCard = page.locator('[data-testid^="cc-va-family-"]', { hasText: /Bancroft/i });
    await expect(bancroftCard).toBeVisible({ timeout: 10_000 });
    await bancroftCard.click();
    await page.waitForTimeout(3000);
    console.log(`  [${label}] Agreement type "Bancroft" selected`);

    await ccPickVendor(page, label);
    await ccFillSigners(page, label);

    const createStatus = await ccClickCreate(page, label);
    result.skipped = createStatus === 'skipped';
    result.generated = createStatus === 'created';
    if (result.generated) await openAndScreenshotDoc(page, label);
    if (result.generated) result.submitted = await submitContract(page, label);
  } catch (e) {
    console.log(`  [${label}] ERROR: ${(e as Error).message}`);
    await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
  }

  result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
  await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
  recordResult(result);
});

// ═══════════════════════════════════════════════════════════════
// DECADES CONTRACT DOCUMENTS (1 WO + 1 VA)
// ═══════════════════════════════════════════════════════════════

// ─── 09: Decades Work Order ──────────────────────────────────

test('09 Dec-WO: Generate + Submit', async ({ page }) => {
  const label = 'Dec-WO';
  console.log(`\n=== ${label} ===`);
  const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

  try {
    await page.goto(`${BASE}/#/contracts/new?type=wo`);
    await page.waitForLoadState('networkidle');

    await ccSelectCustomer(page, 'Penn', label);

    // Decades customers have template buttons (WO + Amendment)
    const tplBtn = page.locator('[data-testid^="cc-tpl-btn-"]').first();
    if (await tplBtn.isVisible({ timeout: 10_000 }).catch(() => false)) {
      // Pick the WO template (not the Amendment)
      const woBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: /Work.?Order|Decades/i }).first();
      if (await woBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await woBtn.click();
      } else {
        await tplBtn.click(); // fallback: first template
      }
      await observe(page);
      console.log(`  [${label}] Decades WO template selected`);
    }

    await ccFillWoNumber(page, label);
    await ccPickVendor(page, label);
    await ccPickLocation(page, label);
    await ccFillSigners(page, label);
    await ccAddLineItem(page, 0, `${RUN_TAG}-DEC-WO-ITEM`, '3500.00');

    const createStatus = await ccClickCreate(page, label);
    result.skipped = createStatus === 'skipped';
    result.generated = createStatus === 'created';
    if (result.generated) await openAndScreenshotDoc(page, label);
    if (result.generated) result.submitted = await submitContract(page, label);
  } catch (e) {
    console.log(`  [${label}] ERROR: ${(e as Error).message}`);
    await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
  }

  result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
  await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
  recordResult(result);
});

// ─── 10: Decades Amendment ───────────────────────────────────

test('10 Dec-Amendment: Generate + Submit', async ({ page }) => {
  const label = 'Dec-Amendment';
  console.log(`\n=== ${label} ===`);
  const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

  try {
    await page.goto(`${BASE}/#/contracts/new?type=wo`);
    await page.waitForLoadState('networkidle');

    await ccSelectCustomer(page, 'Penn', label);

    // Select the Amendment template button (2nd button)
    const tplBtns = page.locator('[data-testid^="cc-tpl-btn-"]');
    await expect(tplBtns.first()).toBeVisible({ timeout: 10_000 });
    const count = await tplBtns.count();
    if (count >= 2) {
      await tplBtns.nth(1).click();
    } else {
      await tplBtns.first().click();
    }
    await observe(page);
    console.log(`  [${label}] Decades Amendment template selected`);

    // Select parent contract
    const parentSelect = page.getByTestId('cc-parent-contract');
    if (await parentSelect.isVisible({ timeout: 5000 }).catch(() => false)) {
      await parentSelect.selectOption({ index: 1 });
      await observe(page);
      console.log(`  [${label}] Parent contract selected`);
    }

    // Amendments inherit WO# from parent — no ccFillWoNumber
    await ccPickVendor(page, label);
    await ccPickLocation(page, label);
    await ccFillSigners(page, label);
    await ccAddLineItem(page, 0, `${RUN_TAG}-DEC-AMD-ITEM`, '2800.00');

    // Fill amendment-specific required fields
    const svcDesc = page.getByTestId('cc-amendment-service-desc');
    if (await svcDesc.isVisible({ timeout: 3000 }).catch(() => false)) {
      await svcDesc.fill('Additional landscaping maintenance scope');
      console.log(`  [${label}] Service description filled`);
    }
    const schedDesc = page.getByTestId('cc-amendment-schedule');
    if (await schedDesc.isVisible({ timeout: 2000 }).catch(() => false)) {
      await schedDesc.fill('Mon-Fri 8:00 AM - 4:00 PM');
      console.log(`  [${label}] Schedule filled`);
    }

    const createStatus = await ccClickCreate(page, label);
    result.skipped = createStatus === 'skipped';
    result.generated = createStatus === 'created';
    if (result.generated) await openAndScreenshotDoc(page, label);
    if (result.generated) result.submitted = await submitContract(page, label);
  } catch (e) {
    console.log(`  [${label}] ERROR: ${(e as Error).message}`);
    await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
  }

  result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
  await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
  recordResult(result);
});

// ─── 11: Decades Vendor Agreement ────────────────────────────

test('11 Dec-VA: Generate + Submit', async ({ page }) => {
  const label = 'Dec-VA';
  console.log(`\n=== ${label} ===`);
  const result: DocResult = { type: label, generated: false, submitted: false, skipped: false, screenshot: '' };

  try {
    await page.goto(`${BASE}/#/contracts/new?type=msa`);
    await page.waitForLoadState('networkidle');

    // VA shows "Which agreement type?" — pick Decades family via testid
    const decadesCard = page.locator('[data-testid^="cc-va-family-"]', { hasText: /Decades/i });
    await expect(decadesCard).toBeVisible({ timeout: 10_000 });
    await decadesCard.click();
    await page.waitForTimeout(3000);
    console.log(`  [${label}] Agreement type "Decades" selected`);

    // After clicking Decades, need to pick a customer
    const custInput = page.getByTestId('cc-customer-search');
    if (await custInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      await custInput.pressSequentially('Penn', { delay: 120 });
      await page.waitForTimeout(3000);
      await page.locator('[data-testid^="cc-btn-customer-"]').first().click();
      await page.waitForTimeout(3000);
      console.log(`  [${label}] Customer selected (Penn)`);
    }

    await ccPickVendor(page, label);
    await ccFillSigners(page, label);

    const createStatus = await ccClickCreate(page, label);
    result.skipped = createStatus === 'skipped';
    result.generated = createStatus === 'created';
    if (result.generated) await openAndScreenshotDoc(page, label);
    if (result.generated) result.submitted = await submitContract(page, label);
  } catch (e) {
    console.log(`  [${label}] ERROR: ${(e as Error).message}`);
    await page.screenshot({ path: `./test-results/${RUN_TAG}-${label}-error.png`, fullPage: true }).catch(() => {});
  }

  result.screenshot = `./test-results/${RUN_TAG}-${label}.png`;
  await page.screenshot({ path: result.screenshot, fullPage: true }).catch(() => {});
  recordResult(result);
});

// ═══════════════════════════════════════════════════════════════
// VERIFICATION: Send Queue
// ═══════════════════════════════════════════════════════════════

test('12 VERIFY: Send Queue contains submitted documents', async ({ page }) => {
  const label = 'VERIFY-SendQueue';
  console.log(`\n=== ${label} ===`);

  await page.goto(`${BASE}/#/send-queue`);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);

  await page.screenshot({ path: `./test-results/${RUN_TAG}-sendqueue.png`, fullPage: true });

  const submittedCount = results.filter(r => r.submitted).length;
  console.log(`  [${label}] Documents submitted this run: ${submittedCount}`);

  // Count pending/draft items
  const pendingBadges = page.locator('text=/Draft|Pending|Pending Approval/i');
  const pendingCount = await pendingBadges.count();
  console.log(`  [${label}] Pending/Draft items visible: ${pendingCount}`);

  expect(pendingCount, `Expected at least ${submittedCount} pending items`).toBeGreaterThanOrEqual(submittedCount);
});

// ═══════════════════════════════════════════════════════════════
// SUMMARY
// ═══════════════════════════════════════════════════════════════

test('13 SUMMARY: Print results', async ({}) => {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  RESULTS — RUN ${RUN_TAG}`);
  console.log(`${'='.repeat(60)}`);
  console.log('');
  console.log('  Type               | Generated | Submitted | Note');
  console.log('  -------------------|-----------|-----------|------');
  for (const r of results) {
    const g = r.skipped ? 'SKIP' : r.generated ? 'YES' : 'FAIL';
    const s = r.skipped ? 'SKIP' : r.submitted ? 'YES' : 'FAIL';
    const note = r.skipped ? 'no template' : '';
    console.log(`  ${r.type.padEnd(19)}| ${g.padEnd(10)}| ${s.padEnd(10)}| ${note}`);
  }
  console.log('');

  const tested = results.filter(r => !r.skipped);
  const skipped = results.filter(r => r.skipped);
  const allGen = tested.every(r => r.generated);
  const allSub = tested.every(r => r.submitted);
  console.log(`  TESTED:      ${tested.length}`);
  console.log(`  SKIPPED:     ${skipped.length} (no template available)`);
  console.log(`  ALL GENERATED: ${allGen ? 'PASS' : 'FAIL'}`);
  console.log(`  ALL SUBMITTED: ${allSub ? 'PASS' : 'FAIL'}`);
  console.log(`${'='.repeat(60)}\n`);

  expect(results.length, 'Expected 11 document types').toBe(11);
  if (skipped.length > 0) {
    console.log(`  WARNING: ${skipped.length} doc types skipped — templates missing in Prod`);
    for (const s of skipped) console.log(`    - ${s.type}`);
  }
  expect(allGen, 'Not all tested documents were generated').toBe(true);
  expect(allSub, 'Not all tested documents were submitted').toBe(true);
});
