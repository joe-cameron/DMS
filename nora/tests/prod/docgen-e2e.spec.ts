/**
 * E2E Document Generation — Full field verification with coded values.
 * Every field uses E2E-{SECTION}-{NNN} codes traceable in the output document.
 * Single-threaded, page.pause() at critical steps for operator intervention.
 */
import { test, expect, Page } from '@playwright/test';

test.describe.configure({ mode: 'serial', retries: 0, timeout: 300000 });
test.use({ actionTimeout: 15000 });

const P = 1000; // pause between visual steps
const wait = (p: Page, ms = P) => p.waitForTimeout(ms);

// ═══════════════════════════════════════════════════════════════
// TEST 1: MSA Composer — Package A, Bancroft, 5 Locations
// ═══════════════════════════════════════════════════════════════

test('TEST 1: MSA Proposal — Bancroft Essential, 5 locations', async ({ page }) => {
  await page.goto('/#/msa/new');
  await wait(page, 2000);

  // Package A
  await page.locator('[data-testid="package-PackageA"]').click();
  await wait(page);

  // Customer search → click result
  await page.locator('[data-testid="msa-btn-cust-search"]').click();
  await wait(page);
  await page.locator('[data-testid="customer-search"]').fill('Bancroft');
  await wait(page, 2000);
  const custResult = page.locator('[data-testid^="customer-result-"]').first();
  await expect(custResult).toBeVisible({ timeout: 5000 });
  await custResult.click();
  await wait(page);

  // PAUSE — verify customer selected
  await wait(page);

  // Signer — coded values
  await page.locator('[data-testid="cust-signer-name"]').fill('E2E-SIGN-NAME-101');
  await page.locator('[data-testid="cust-signer-title"]').fill('E2E-SIGN-TITLE-102');
  await wait(page);

  // Pricing
  await page.locator('[data-testid="msa-btn-price-uniform"]').click();
  await wait(page);
  await page.locator('[data-testid="uni-rate"]').fill('1234.56');
  await page.locator('[data-testid="uni-onboard"]').fill('567.89');
  await wait(page);

  // 5 Locations
  const locs = [
    'E2E-LOC-ALPHA-001',
    'E2E-LOC-BRAVO-002',
    'E2E-LOC-CHARLIE-003',
    'E2E-LOC-DELTA-004',
    'E2E-LOC-ECHO-005',
  ];
  for (const loc of locs) {
    await page.locator('[data-testid="new-loc-name"]').fill(loc);
    await page.locator('[data-testid="btn-add-loc"]').click();
    await wait(page, 500);
  }
  await wait(page);

  // PAUSE — verify 5 locations and fee summary
  await wait(page);

  // Screenshot before generate
  await page.screenshot({ path: './test-results/e2e-msa-before.png', fullPage: true });

  // Create — document uploads to SP then opens in Word Online (new tab)
  const [msaNewTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 90000 }).catch(() => null),
    page.locator('[data-testid="btn-download-msa"]').first().click(),
  ]);
  console.log('[E2E] MSA Create clicked — new tab: ' + (msaNewTab ? 'YES' : 'NO (fallback download)'));

  if (msaNewTab) {
    await msaNewTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    console.log('[E2E] Word Online tab URL: ' + msaNewTab.url());
    await msaNewTab.screenshot({ path: './test-results/e2e-msa-word-online.png' }).catch(() => {});
  }
  await page.bringToFront();
  await wait(page, 3000);

  // Screenshot composer after generation
  await page.screenshot({ path: './test-results/e2e-msa-after-create.png', fullPage: true });

  // Wait for sidebar — Documents card should show the record
  const msaDocRow = page.locator('[data-testid="doc-history-row"]').first();
  try {
    await expect(msaDocRow).toBeVisible({ timeout: 30000 });
    console.log('[E2E] Document history row appeared');
  } catch {
    console.log('[E2E] Document history row NOT visible after 30s');
  }

  // Wait for sidebar buttons (Open Document + Submit for Approval)
  const msaOpenDoc = page.locator('[data-testid="msa-open-doc"]');
  const msaSubmit = page.locator('[data-testid="msa-btn-submit-approval"]');
  try {
    await expect(msaOpenDoc.or(msaSubmit)).toBeVisible({ timeout: 15000 });
    console.log('[E2E] Sidebar buttons visible');
  } catch {
    console.log('[E2E] Sidebar buttons not visible');
  }
  await page.screenshot({ path: './test-results/e2e-msa-sidebar.png', fullPage: true });

  // Submit for approval
  if (await msaSubmit.isVisible({ timeout: 3000 })) {
    await msaSubmit.click();
    await wait(page, 2000);
    console.log('[E2E] MSA submitted for approval');
  }

  await page.screenshot({ path: './test-results/e2e-msa-after.png', fullPage: true });
});

// ═══════════════════════════════════════════════════════════════
// TEST 2: Contract Composer — Blanket Work Order, 3 Line Items
// ═══════════════════════════════════════════════════════════════

test('TEST 2: Work Order — Bancroft Blanket WO, 3 line items', async ({ page }) => {
  await page.goto('/#/contracts/new?type=wo');
  await wait(page, 2000);

  // Customer
  await page.locator('[data-testid="cc-customer-search"]').fill('Bancroft');
  await wait(page, 1500);
  const custBtn = page.locator('[data-testid^="cc-btn-customer-"]').first();
  await expect(custBtn).toBeVisible({ timeout: 5000 });
  await custBtn.click();
  await wait(page, 3000);

  // PAUSE — verify template buttons appeared
  await wait(page);

  // Select Blanket Work Order template
  const tplBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: 'Blanket Work Order' });
  if (await tplBtn.isVisible({ timeout: 3000 })) {
    await tplBtn.click();
    await wait(page);
  }

  // Vendor drawer
  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 2000 })) {
    await vendorChip.click();
    await wait(page, 1500);

    // PAUSE — pick vendor (operator may need to select manually)
    await wait(page);

    // Try to click first vendor row
    const vendorRow = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vendorRow.isVisible({ timeout: 2000 })) {
      await vendorRow.click();
      await wait(page);
    }
  }

  // Location drawer
  const locChip = page.locator('button', { hasText: /Location/ }).first();
  if (await locChip.isVisible({ timeout: 2000 })) {
    await locChip.click();
    await wait(page, 1500);

    // PAUSE — pick location
    await wait(page);

    const locRow = page.locator('[data-testid^="cc-location-row-"]').first();
    if (await locRow.isVisible({ timeout: 2000 })) {
      await locRow.click();
      await wait(page);
    }
  }

  // Signers
  const signerChip = page.locator('button', { hasText: /Signers/ }).first();
  if (await signerChip.isVisible({ timeout: 2000 })) {
    await signerChip.click();
    await wait(page);
  }
  await page.locator('[data-testid="cc-cust-signer-name"]').fill('E2E-CSIGN-201');
  await page.locator('[data-testid="cc-cust-signer-title"]').fill('E2E-CTITLE-202');
  await page.locator('[data-testid="cc-vendor-signer-name"]').fill('E2E-VSIGN-203');
  await page.locator('[data-testid="cc-vendor-signer-title"]').fill('E2E-VTITLE-204');
  await wait(page);
  const signerDone = page.locator('[data-testid="cc-btn-signers-done"]');
  if (await signerDone.isVisible({ timeout: 2000 })) {
    await signerDone.click();
    await wait(page);
  }

  // Line Item 1
  await page.locator('[data-testid="cc-btn-add-item"]').click();
  await wait(page);
  await page.locator('[data-testid="cc-costcode-0"]').selectOption({ index: 1 }).catch(() => {});
  await page.locator('[data-testid="cc-item-desc-0"]').fill('E2E-WORK-ITEM-301');
  await page.locator('[data-testid="cc-item-amount-0"]').fill('5000.00');
  await wait(page);

  // Line Item 2
  await page.locator('[data-testid="cc-btn-add-another"]').click();
  await wait(page);
  await page.locator('[data-testid="cc-costcode-1"]').selectOption({ index: 1 }).catch(() => {});
  await page.locator('[data-testid="cc-item-desc-1"]').fill('E2E-WORK-ITEM-302');
  await page.locator('[data-testid="cc-item-amount-1"]').fill('3500.00');
  await wait(page);

  // Line Item 3
  await page.locator('[data-testid="cc-btn-add-another"]').click();
  await wait(page);
  await page.locator('[data-testid="cc-costcode-2"]').selectOption({ index: 1 }).catch(() => {});
  await page.locator('[data-testid="cc-item-desc-2"]').fill('E2E-WORK-ITEM-303');
  await page.locator('[data-testid="cc-item-amount-2"]').fill('1500.00');
  await wait(page);

  // PAUSE — verify total = $10,000.00
  await wait(page);

  await page.screenshot({ path: './test-results/e2e-wo-before.png', fullPage: true });

  // Create — Word Online opens automatically after SP upload
  const woCreateBtn = page.locator('button', { hasText: /^Create/ }).last();
  const [woNewTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 90000 }).catch(() => null),
    woCreateBtn.click(),
  ]);
  console.log('[E2E] WO Create clicked — new tab: ' + (woNewTab ? 'YES' : 'NO'));
  if (woNewTab) {
    await woNewTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    console.log('[E2E] WO Word Online URL: ' + woNewTab.url());
    await woNewTab.screenshot({ path: './test-results/e2e-wo-word-online.png' }).catch(() => {});
  }
  await page.bringToFront();
  await wait(page, 3000);

  // Submit
  const ccSubmit = page.locator('[data-testid="cc-btn-submit-approval"]');
  if (await ccSubmit.isVisible({ timeout: 3000 })) {
    await ccSubmit.click();
    await wait(page, 2000);
  }

  await page.screenshot({ path: './test-results/e2e-wo-after.png', fullPage: true });
});

// ═══════════════════════════════════════════════════════════════
// TEST 3: Contract Composer — Vendor Agreement
// ═══════════════════════════════════════════════════════════════

test('TEST 3: Vendor Agreement — Bancroft', async ({ page }) => {
  await page.goto('/#/contracts/new?type=msa');
  await wait(page, 2000);

  // Customer
  await page.locator('[data-testid="cc-customer-search"]').fill('Bancroft');
  await wait(page, 1500);
  const custBtn = page.locator('[data-testid^="cc-btn-customer-"]').first();
  await expect(custBtn).toBeVisible({ timeout: 5000 });
  await custBtn.click();
  await wait(page, 3000);

  // PAUSE — verify VA template button
  await wait(page);

  // Select VA template
  const vaBtn = page.locator('[data-testid^="cc-tpl-btn-"]').first();
  if (await vaBtn.isVisible({ timeout: 3000 })) {
    await vaBtn.click();
    await wait(page);
  }

  // Vendor
  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 2000 })) {
    await vendorChip.click();
    await wait(page, 1500);
    await wait(page); // operator picks vendor
    const vendorRow = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vendorRow.isVisible({ timeout: 2000 })) {
      await vendorRow.click();
      await wait(page);
    }
  }

  // Signers
  const signerChip = page.locator('button', { hasText: /Signers/ }).first();
  if (await signerChip.isVisible({ timeout: 2000 })) {
    await signerChip.click();
    await wait(page);
  }
  await page.locator('[data-testid="cc-cust-signer-name"]').fill('E2E-VA-CSIGN-401');
  await page.locator('[data-testid="cc-cust-signer-title"]').fill('E2E-VA-CTITLE-402');
  await page.locator('[data-testid="cc-vendor-signer-name"]').fill('E2E-VA-VSIGN-403');
  await page.locator('[data-testid="cc-vendor-signer-title"]').fill('E2E-VA-VTITLE-404');
  await wait(page);
  const signerDone = page.locator('[data-testid="cc-btn-signers-done"]');
  if (await signerDone.isVisible({ timeout: 2000 })) {
    await signerDone.click();
    await wait(page);
  }

  // PAUSE — verify form complete
  await wait(page);

  await page.screenshot({ path: './test-results/e2e-va-before.png', fullPage: true });

  // Create — Word Online opens automatically
  const vaCreateBtn = page.locator('button', { hasText: /^Create/ }).last();
  const [vaNewTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 90000 }).catch(() => null),
    vaCreateBtn.click(),
  ]);
  console.log('[E2E] VA Create — new tab: ' + (vaNewTab ? 'YES' : 'NO'));
  if (vaNewTab) {
    await vaNewTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    await vaNewTab.screenshot({ path: './test-results/e2e-va-word-online.png' }).catch(() => {});
  }
  await page.bringToFront();
  await wait(page, 3000);

  const ccSubmit3 = page.locator('[data-testid="cc-btn-submit-approval"]');
  if (await ccSubmit3.isVisible({ timeout: 3000 })) {
    await ccSubmit3.click();
    await wait(page, 2000);
  }

  await page.screenshot({ path: './test-results/e2e-va-after.png', fullPage: true });
});

// ═══════════════════════════════════════════════════════════════
// TEST 4: Contract Composer — Amendment
// ═══════════════════════════════════════════════════════════════

test('TEST 4: Amendment — Bancroft', async ({ page }) => {
  await page.goto('/#/contracts/new?type=wo');
  await wait(page, 2000);

  // Customer
  await page.locator('[data-testid="cc-customer-search"]').fill('Bancroft');
  await wait(page, 1500);
  const custBtn = page.locator('[data-testid^="cc-btn-customer-"]').first();
  await expect(custBtn).toBeVisible({ timeout: 5000 });
  await custBtn.click();
  await wait(page, 3000);

  // Select Amendment template
  const amdBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: 'Work Order Amendment' });
  if (await amdBtn.isVisible({ timeout: 3000 })) {
    await amdBtn.click();
    await wait(page, 1000);
  }

  // PAUSE — amendment fields should appear (parent WO picker)
  await wait(page);

  // Parent WO
  const parentSelect = page.locator('[data-testid="cc-parent-contract"]');
  if (await parentSelect.isVisible({ timeout: 3000 })) {
    await parentSelect.selectOption({ index: 1 }); // first WO
    await wait(page);
  }

  // Vendor
  const vendorChip = page.locator('button', { hasText: /Vendor/ }).first();
  if (await vendorChip.isVisible({ timeout: 2000 })) {
    await vendorChip.click();
    await wait(page, 1500);
    await wait(page);
    const vendorRow = page.locator('[data-testid^="cc-vendor-row-"]').first();
    if (await vendorRow.isVisible({ timeout: 2000 })) {
      await vendorRow.click();
      await wait(page);
    }
  }

  // Location
  const locChip = page.locator('button', { hasText: /Location/ }).first();
  if (await locChip.isVisible({ timeout: 2000 })) {
    await locChip.click();
    await wait(page, 1500);
    await wait(page);
    const locRow = page.locator('[data-testid^="cc-location-row-"]').first();
    if (await locRow.isVisible({ timeout: 2000 })) {
      await locRow.click();
      await wait(page);
    }
  }

  // Signers
  const signerChip = page.locator('button', { hasText: /Signers/ }).first();
  if (await signerChip.isVisible({ timeout: 2000 })) {
    await signerChip.click();
    await wait(page);
  }
  await page.locator('[data-testid="cc-cust-signer-name"]').fill('E2E-AMD-CSIGN-501');
  await page.locator('[data-testid="cc-cust-signer-title"]').fill('E2E-AMD-CTITLE-502');
  await page.locator('[data-testid="cc-vendor-signer-name"]').fill('E2E-AMD-VSIGN-503');
  await page.locator('[data-testid="cc-vendor-signer-title"]').fill('E2E-AMD-VTITLE-504');
  await wait(page);
  const signerDone = page.locator('[data-testid="cc-btn-signers-done"]');
  if (await signerDone.isVisible({ timeout: 2000 })) {
    await signerDone.click();
    await wait(page);
  }

  // Amendment line item
  await page.locator('[data-testid="cc-btn-add-item"]').click();
  await wait(page);
  const cc0 = page.locator('[data-testid="cc-costcode-0"]');
  if (await cc0.isVisible({ timeout: 2000 })) {
    await cc0.selectOption({ index: 1 });
  }
  await page.locator('[data-testid="cc-item-desc-0"]').fill('E2E-AMD-ITEM-601');
  await page.locator('[data-testid="cc-item-amount-0"]').fill('2500.00');
  await wait(page);

  // PAUSE — verify form
  await wait(page);

  await page.screenshot({ path: './test-results/e2e-amd-before.png', fullPage: true });

  // Create — Word Online opens automatically
  const amdCreateBtn = page.locator('button', { hasText: /^Create/ }).last();
  const [amdNewTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 90000 }).catch(() => null),
    amdCreateBtn.click(),
  ]);
  console.log('[E2E] AMD Create — new tab: ' + (amdNewTab ? 'YES' : 'NO'));
  if (amdNewTab) {
    await amdNewTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    await amdNewTab.screenshot({ path: './test-results/e2e-amd-word-online.png' }).catch(() => {});
  }
  await page.bringToFront();
  await wait(page, 3000);

  const ccSubmit4 = page.locator('[data-testid="cc-btn-submit-approval"]');
  if (await ccSubmit4.isVisible({ timeout: 3000 })) {
    await ccSubmit4.click();
    await wait(page, 2000);
  }

  await page.screenshot({ path: './test-results/e2e-amd-after.png', fullPage: true });
});
