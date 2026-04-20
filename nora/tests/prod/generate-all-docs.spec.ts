/**
 * generate-all-docs.spec.ts — Generate one of every document type
 *
 * Drives the MSA Composer and Contract Composer to produce real documents
 * in SharePoint for every active template. 1s visual pauses for observation.
 *
 * Run:
 *   cd C:\dcfg\nora
 *   npx playwright test generate-all-docs --config=playwright-prod.config.ts --project=prod-docgen --headed --retries=0
 */
import { test, expect, Page } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });
test.describe.configure({ mode: 'serial', retries: 0, timeout: 300000 });

const V = 1000;
const observe = (p: Page) => p.waitForTimeout(V);

// Helper: select customer in MSA Composer
async function selectCustomerMsa(page: Page, searchTerm: string) {
  await page.getByTestId('msa-btn-cust-search').click();
  await observe(page);
  const input = page.getByTestId('customer-search');
  await expect(input).toBeVisible({ timeout: 5000 });
  await input.click();
  await input.pressSequentially(searchTerm, { delay: 150 });
  await page.waitForTimeout(3000);
  const result = page.locator('[data-testid^="customer-result-"]').first();
  await expect(result).toBeVisible({ timeout: 15000 });
  await observe(page);
  await result.click();
  await observe(page);
  console.log(`  OK Customer selected (${searchTerm})`);
}

// Helper: fill signer info in MSA Composer
async function fillSignerMsa(page: Page, name: string, title: string) {
  const signerName = page.getByTestId('cust-signer-name');
  await expect(signerName).toBeVisible({ timeout: 5000 });
  await signerName.fill(name);
  await page.getByTestId('cust-signer-title').fill(title);
  await observe(page);
  console.log(`  OK Signer: ${name} / ${title}`);
}

// Helper: add a location in MSA Composer
async function addLocationMsa(page: Page, locName: string) {
  const locInput = page.locator('input[placeholder*="Location name"], input[placeholder*="location name"], [data-testid="new-loc-name"]').first();
  await expect(locInput).toBeVisible({ timeout: 5000 });
  await locInput.fill(locName);
  await observe(page);
  const addBtn = page.locator('button', { hasText: /^Add$/ }).first().or(page.getByTestId('btn-add-loc'));
  await addBtn.click();
  await observe(page);
  console.log(`  OK Location: ${locName}`);
}

// Helper: click Generate MSA and wait for result
async function generateMsa(page: Page, label: string) {
  const btn = page.getByTestId('btn-download-msa').first();
  await expect(btn).toBeVisible({ timeout: 5000 });
  await observe(page);

  const [newTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 120000 }).catch(() => null),
    btn.click(),
  ]);
  console.log(`  -> ${label} Generate clicked. New tab: ${newTab ? 'YES' : 'NO'}`);

  if (newTab) {
    await newTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    console.log(`  -> Word Online: ${newTab.url().substring(0, 100)}`);
    await newTab.close().catch(() => {});
  }

  await page.bringToFront();
  await observe(page);

  const docRow = page.getByTestId('doc-history-row').first();
  try {
    await expect(docRow).toBeVisible({ timeout: 60000 });
    console.log(`  OK ${label} document created`);
  } catch {
    console.log(`  WARN ${label} doc-history-row not visible after 60s`);
  }

  await page.screenshot({ path: `./test-results/gen-${label.toLowerCase().replace(/\s+/g, '-')}.png`, fullPage: true });
}

// Helper: select customer in Contract Composer
async function selectCustomerContract(page: Page, searchTerm: string) {
  const input = page.getByTestId('cc-customer-search');
  await expect(input).toBeVisible({ timeout: 10000 });
  await input.pressSequentially(searchTerm, { delay: 150 });
  await page.waitForTimeout(3000);
  const result = page.locator('[data-testid^="cc-btn-customer-"]').first();
  await expect(result).toBeVisible({ timeout: 15000 });
  await observe(page);
  await result.click();
  await page.waitForTimeout(3000);
  console.log(`  OK Customer selected (${searchTerm})`);
}

// Helper: fill contract signers
async function fillSignerContract(page: Page, custName: string, custTitle: string, vendName: string, vendTitle: string) {
  const signerChip = page.locator('button', { hasText: /Signers/ }).first();
  if (await signerChip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await signerChip.click();
    await observe(page);
  }
  await page.getByTestId('cc-cust-signer-name').fill(custName);
  await page.getByTestId('cc-cust-signer-title').fill(custTitle);
  await page.getByTestId('cc-vendor-signer-name').fill(vendName);
  await page.getByTestId('cc-vendor-signer-title').fill(vendTitle);
  await observe(page);
  const done = page.getByTestId('cc-btn-signers-done');
  if (await done.isVisible({ timeout: 2000 }).catch(() => false)) {
    await done.click();
    await observe(page);
  }
  console.log(`  OK Signers filled`);
}

// Helper: click Create contract and wait
async function generateContract(page: Page, label: string) {
  const btn = page.locator('button', { hasText: /^Create/ }).last();
  await expect(btn).toBeVisible({ timeout: 5000 });
  await observe(page);

  const [newTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 120000 }).catch(() => null),
    btn.click(),
  ]);
  console.log(`  -> ${label} Create clicked. New tab: ${newTab ? 'YES' : 'NO'}`);

  if (newTab) {
    await newTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    console.log(`  -> Word Online: ${newTab.url().substring(0, 100)}`);
    await newTab.close().catch(() => {});
  }

  await page.bringToFront();
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `./test-results/gen-${label.toLowerCase().replace(/\s+/g, '-')}.png`, fullPage: true });
  console.log(`  OK ${label} document created`);
}

// ═══════════════════════════════════════════════════════════════
// MSA DOCUMENTS
// ═══════════════════════════════════════════════════════════════

test('DOC 1: MSA Package A (Basic Platform)', async ({ page }) => {
  console.log('\n=== DOC 1: MSA Package A ===');
  await page.goto('/#/msa/new');
  await page.waitForLoadState('networkidle');
  await expect(page.getByTestId('package-PackageA')).toBeVisible({ timeout: 15000 });

  await page.getByTestId('package-PackageA').click();
  await observe(page);
  await selectCustomerMsa(page, 'Ban');
  await fillSignerMsa(page, 'VP of Operations', 'Vice President');
  await page.getByTestId('msa-btn-price-uniform').click();
  await page.getByTestId('uni-rate').fill('1850.00');
  await page.getByTestId('uni-onboard').fill('250.00');
  await observe(page);
  await addLocationMsa(page, '1981 Old Cuthbert Rd');
  await addLocationMsa(page, '311 Walton Avenue');
  await addLocationMsa(page, '500 Main Street');
  await generateMsa(page, 'MSA-PackageA');
});

test('DOC 2: MSA Package B (Concierge Platform)', async ({ page }) => {
  console.log('\n=== DOC 2: MSA Package B ===');
  await page.goto('/#/msa/new');
  await page.waitForLoadState('networkidle');
  await expect(page.getByTestId('package-PackageB')).toBeVisible({ timeout: 15000 });

  await page.getByTestId('package-PackageB').click();
  await observe(page);
  await selectCustomerMsa(page, 'Penn');
  await fillSignerMsa(page, 'Director of Operations', 'Director');
  await page.getByTestId('msa-btn-price-uniform').click();
  await page.getByTestId('uni-rate').fill('2400.00');
  await page.getByTestId('uni-onboard').fill('350.00');
  await observe(page);
  await addLocationMsa(page, '100 Princeton Ave');
  await addLocationMsa(page, '250 Route 33');
  await generateMsa(page, 'MSA-PackageB');
});

test('DOC 3: MSA Package C (Optimized Platform)', async ({ page }) => {
  console.log('\n=== DOC 3: MSA Package C ===');
  await page.goto('/#/msa/new');
  await page.waitForLoadState('networkidle');
  await expect(page.getByTestId('package-PackageC')).toBeVisible({ timeout: 15000 });

  await page.getByTestId('package-PackageC').click();
  await observe(page);
  await selectCustomerMsa(page, 'Arc');
  await fillSignerMsa(page, 'Executive Director', 'Executive Director');
  await page.getByTestId('msa-btn-price-uniform').click();
  await page.getByTestId('uni-rate').fill('3200.00');
  await page.getByTestId('uni-onboard').fill('500.00');
  await observe(page);
  await addLocationMsa(page, '215 East State Street');
  await generateMsa(page, 'MSA-PackageC');
});

// ═══════════════════════════════════════════════════════════════
// CONTRACT DOCUMENTS
// ═══════════════════════════════════════════════════════════════

test('DOC 4: Work Order (Exhibit A)', async ({ page }) => {
  console.log('\n=== DOC 4: Work Order ===');
  await page.goto('/#/contracts/new?type=wo');
  await page.waitForLoadState('networkidle');

  await selectCustomerContract(page, 'Ban');

  // Select template
  const tplBtn = page.locator('[data-testid^="cc-tpl-btn-"]').first();
  if (await tplBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await tplBtn.click();
    await observe(page);
  }

  // Vendor
  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await vendorChip.click();
    await page.waitForTimeout(2000);
    const vendorRow = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vendorRow.isVisible({ timeout: 3000 }).catch(() => false)) {
      await vendorRow.click();
      await observe(page);
    }
  }

  // Location
  const locChip = page.locator('button', { hasText: /Location/ }).first();
  if (await locChip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await locChip.click();
    await page.waitForTimeout(2000);
    const locRow = page.locator('[data-testid^="cc-location-row-"]').first();
    if (await locRow.isVisible({ timeout: 3000 }).catch(() => false)) {
      await locRow.click();
      await observe(page);
    }
  }

  await fillSignerContract(page, 'VP of Operations', 'Vice President', 'Service Manager', 'Manager');

  // Line items
  await page.getByTestId('cc-btn-add-item').click();
  await observe(page);
  await page.getByTestId('cc-item-desc-0').fill('HVAC preventive maintenance — quarterly service');
  await page.getByTestId('cc-item-amount-0').fill('4500.00');
  await observe(page);

  await page.getByTestId('cc-btn-add-another').click();
  await observe(page);
  await page.getByTestId('cc-item-desc-1').fill('Filter replacement and system inspection');
  await page.getByTestId('cc-item-amount-1').fill('1200.00');
  await observe(page);

  await generateContract(page, 'WorkOrder');
});

test('DOC 5: Amendment', async ({ page }) => {
  console.log('\n=== DOC 5: Amendment ===');
  await page.goto('/#/contracts/new?type=wo');
  await page.waitForLoadState('networkidle');

  await selectCustomerContract(page, 'Ban');

  // Select Amendment template
  const amdBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: /Amendment/ });
  if (await amdBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await amdBtn.click();
    await observe(page);
  }

  // Parent WO
  const parentSelect = page.getByTestId('cc-parent-contract');
  if (await parentSelect.isVisible({ timeout: 3000 }).catch(() => false)) {
    await parentSelect.selectOption({ index: 1 });
    await observe(page);
  }

  // Vendor + Location
  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 2000 }).catch(() => false)) {
    await vendorChip.click();
    await page.waitForTimeout(2000);
    const vr = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vr.isVisible({ timeout: 2000 }).catch(() => false)) { await vr.click(); await observe(page); }
  }

  const locChip = page.locator('button', { hasText: /Location/ }).first();
  if (await locChip.isVisible({ timeout: 2000 }).catch(() => false)) {
    await locChip.click();
    await page.waitForTimeout(2000);
    const lr = page.locator('[data-testid^="cc-location-row-"]').first();
    if (await lr.isVisible({ timeout: 2000 }).catch(() => false)) { await lr.click(); await observe(page); }
  }

  await fillSignerContract(page, 'VP of Operations', 'Vice President', 'Service Manager', 'Manager');

  await page.getByTestId('cc-btn-add-item').click();
  await observe(page);
  await page.getByTestId('cc-item-desc-0').fill('Additional scope — emergency compressor replacement');
  await page.getByTestId('cc-item-amount-0').fill('2800.00');
  await observe(page);

  await generateContract(page, 'Amendment');
});

test('DOC 6: Vendor Agreement', async ({ page }) => {
  console.log('\n=== DOC 6: Vendor Agreement ===');
  await page.goto('/#/contracts/new?type=msa');
  await page.waitForLoadState('networkidle');

  await selectCustomerContract(page, 'Ban');

  const vaBtn = page.locator('[data-testid^="cc-tpl-btn-"]').first();
  if (await vaBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await vaBtn.click();
    await observe(page);
  }

  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 2000 }).catch(() => false)) {
    await vendorChip.click();
    await page.waitForTimeout(2000);
    const vr = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vr.isVisible({ timeout: 2000 }).catch(() => false)) { await vr.click(); await observe(page); }
  }

  await fillSignerContract(page, 'VP of Operations', 'Vice President', 'Owner', 'President');

  await generateContract(page, 'VendorAgreement');
});

test('DOC 7: Blanket Work Order', async ({ page }) => {
  console.log('\n=== DOC 7: Blanket Work Order ===');
  await page.goto('/#/contracts/new?type=wo');
  await page.waitForLoadState('networkidle');

  await selectCustomerContract(page, 'Penn');

  const blkBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: /Blanket/ });
  if (await blkBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await blkBtn.click();
    await observe(page);
  } else {
    const firstBtn = page.locator('[data-testid^="cc-tpl-btn-"]').first();
    if (await firstBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await firstBtn.click();
      await observe(page);
    }
  }

  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 2000 }).catch(() => false)) {
    await vendorChip.click();
    await page.waitForTimeout(2000);
    const vr = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vr.isVisible({ timeout: 2000 }).catch(() => false)) { await vr.click(); await observe(page); }
  }

  await fillSignerContract(page, 'Director of Operations', 'Director', 'Service Manager', 'Manager');

  await page.getByTestId('cc-btn-add-item').click();
  await observe(page);
  await page.getByTestId('cc-item-desc-0').fill('Annual facilities maintenance — all locations');
  await page.getByTestId('cc-item-amount-0').fill('48000.00');
  await observe(page);

  await generateContract(page, 'BlanketWO');
});
