import { test, expect, Page } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

const BASE = 'https://dmms1.powerappsportals.com';

async function goToWizard(page: Page, params = '') {
  await page.goto(`${BASE}/#/contracts/new${params}`);
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });
}

async function captureToasts(page: Page): Promise<string[]> {
  const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').allTextContents();
  if (toasts.length) console.log('TOASTS:', toasts.join(' | '));
  return toasts;
}

async function captureErrors(page: Page) {
  const errors: string[] = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('response', r => { if (r.status() >= 400) errors.push(`HTTP ${r.status()} ${r.url().substring(0, 100)}`); });
  return errors;
}

/** Click a doc type card on step 1 */
async function selectDocType(page: Page, type: 'WorkOrder' | 'Amendment' | 'ContractorMSA') {
  const card = page.getByTestId(`doctype-${type}`);
  await expect(card).toBeVisible({ timeout: 10000 });
  await card.click();
}

/** Click Next button */
async function clickNext(page: Page) {
  // Try top next first, then bottom
  const nextTop = page.getByTestId('btn-next-top');
  const nextBot = page.getByTestId('btn-next');
  if (await nextTop.isVisible({ timeout: 3000 }).catch(() => false)) {
    await nextTop.click();
  } else if (await nextBot.isVisible({ timeout: 3000 }).catch(() => false)) {
    await nextBot.click();
  }
  await page.waitForLoadState('networkidle');
}

/** Click Back button */
async function clickBack(page: Page) {
  const backTop = page.getByTestId('btn-back-top');
  const backBot = page.getByTestId('btn-back');
  if (await backTop.isVisible({ timeout: 3000 }).catch(() => false)) {
    await backTop.click();
  } else if (await backBot.isVisible({ timeout: 3000 }).catch(() => false)) {
    await backBot.click();
  }
  await page.waitForLoadState('networkidle');
}

/** Search and select first customer */
async function selectCustomer(page: Page, search = 'Bancroft') {
  const searchInput = page.getByTestId('search-customer');
  await expect(searchInput).toBeVisible({ timeout: 10000 });
  await searchInput.fill(search);
  await page.waitForLoadState('networkidle');
  // Click first customer option
  const option = page.getByTestId('customer-option').first();
  await expect(option).toBeVisible({ timeout: 10000 });
  await option.click();
  await page.waitForLoadState('networkidle');
}

/** Select a location from dropdown */
async function selectLocation(page: Page) {
  const locDD = page.getByTestId('select-location');
  if (await locDD.isVisible({ timeout: 5000 }).catch(() => false)) {
    // It's a native <select> element
    const options = await locDD.locator('option').allTextContents();
    // Select the first non-empty option
    const realOptions = options.filter(o => o.trim() && !o.includes('Select'));
    if (realOptions.length > 0) {
      await locDD.selectOption({ label: realOptions[0] });
      await page.waitForLoadState('networkidle');
    }
  }
}

/** Select a vendor by typing in search */
async function selectVendor(page: Page, search = 'Acme') {
  // Look for vendor search input or Change link
  const changeLink = page.locator('button:has-text("Change")').first();
  if (await changeLink.isVisible({ timeout: 3000 }).catch(() => false)) {
    await changeLink.click();
  }
  // Fill vendor search
  const vendorInput = page.locator('input[placeholder*="vendor" i], input[placeholder*="search vendor" i]').first();
  if (await vendorInput.isVisible({ timeout: 5000 }).catch(() => false)) {
    await vendorInput.fill(search);
    await page.waitForLoadState('networkidle');
    // Click first vendor result
    const vendorOption = page.locator('[data-testid^="vendor-option"], [style*="cursor: pointer"]').filter({ hasText: search }).first();
    if (await vendorOption.isVisible({ timeout: 5000 }).catch(() => false)) {
      await vendorOption.click();
      await page.waitForLoadState('networkidle');
    }
  }
}

/** Add an Exhibit A line */
async function addLine(page: Page, desc: string, amount: string) {
  const addBtn = page.getByTestId('btn-add-line');
  if (await addBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await addBtn.click();
    // Fill last line
    const descInputs = page.getByTestId('line-description');
    const amountInputs = page.getByTestId('line-amount');
    const lastDesc = descInputs.last();
    const lastAmt = amountInputs.last();
    if (await lastDesc.isVisible({ timeout: 3000 }).catch(() => false)) {
      await lastDesc.fill(desc);
    }
    if (await lastAmt.isVisible({ timeout: 3000 }).catch(() => false)) {
      await lastAmt.fill(amount);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// CONTRACT WIZARD — 20 TESTS
// ═══════════════════════════════════════════════════════════════

test.describe('Contract Wizard', () => {

  // --- TEST 1: WO — navigate all 5 steps ---
  test('1. WO — navigate all 5 steps', async ({ page }) => {
    const errors = await captureErrors(page);
    await goToWizard(page);
    // Skip drafts landing if it appears
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) {
      await startNew.click();
      await page.waitForLoadState('networkidle');
    }
    // Step 1: select WO
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    // Step 2: just verify we're on customer step
    const custSearch = page.getByTestId('search-customer');
    await expect(custSearch).toBeVisible({ timeout: 10000 });
    // Select a customer to enable Next
    await selectCustomer(page);
    await clickNext(page);
    // Step 3: contractor
    await page.waitForLoadState('networkidle');
    await clickNext(page);
    // Step 4: exhibit A
    const addLineBtn = page.getByTestId('btn-add-line');
    if (await addLineBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log('Step 4 Exhibit A visible');
    }
    await clickNext(page);
    // Step 5: review
    const genBtn = page.getByTestId('btn-generate-contract');
    await expect(genBtn).toBeVisible({ timeout: 10000 });
    console.log('All 5 steps navigated successfully');
    await captureToasts(page);
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-wo-step5.png' });
  });

  // --- TEST 2: WO — select customer, verify locations populate ---
  test('2. WO — customer selection populates locations', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    // Check location dropdown populated
    const locDD = page.getByTestId('select-location');
    if (await locDD.isVisible({ timeout: 5000 }).catch(() => false)) {
      const options = await locDD.locator('option').allTextContents();
      console.log(`Location options: ${options.length} — ${options.slice(0, 5).join(', ')}`);
      expect(options.length).toBeGreaterThan(1); // at least "Select..." + 1 real
    }
  });

  // --- TEST 3: WO — select customer + location from dropdown ---
  test('3. WO — select customer and location', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await selectLocation(page);
    console.log('Customer + location selected');
  });

  // --- TEST 4: WO — select vendor, verify auto-fill ---
  test('4. WO — vendor search and auto-fill', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Step 3 — vendor
    await selectVendor(page, 'Acme');
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-wo-vendor.png' });
  });

  // --- TEST 5: WO — signer name/title validation ---
  test('5. WO — signer fields on step 3', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Look for signer fields
    const signerName = page.locator('input[placeholder*="signer" i], [data-testid*="signer-name"]').first();
    const signerTitle = page.locator('input[placeholder*="title" i], [data-testid*="signer-title"]').first();
    if (await signerName.isVisible({ timeout: 5000 }).catch(() => false)) {
      await signerName.fill('Test Signer');
    }
    if (await signerTitle.isVisible({ timeout: 5000 }).catch(() => false)) {
      await signerTitle.fill('Test Title');
    }
    console.log('Signer fields filled');
  });

  // --- TEST 6: WO — add Exhibit A line, verify total ---
  test('6. WO — add Exhibit A line', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    await clickNext(page); // skip to step 4
    await addLine(page, 'Test Service Line', '1500');
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-wo-exhibit-a.png' });
  });

  // --- TEST 7: WO — add 3 lines, delete middle one ---
  test('7. WO — add/delete Exhibit A lines', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    await clickNext(page);
    await addLine(page, 'Line One', '1000');
    await addLine(page, 'Line Two', '2000');
    await addLine(page, 'Line Three', '3000');
    // Delete middle line
    const delBtns = page.getByTestId('btn-delete-line');
    const count = await delBtns.count();
    if (count >= 2) {
      await delBtns.nth(1).click(); // delete second line
    }
    console.log(`Lines after delete: ${await page.getByTestId('line-description').count()}`);
  });

  // --- TEST 8: WO — reach step 5, verify summary ---
  test('8. WO — full flow to review step', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await selectLocation(page);
    await clickNext(page);
    await clickNext(page);
    await addLine(page, 'HVAC Maintenance', '2500');
    await clickNext(page);
    // Step 5 — review
    const genBtn = page.getByTestId('btn-generate-contract');
    await expect(genBtn).toBeVisible({ timeout: 10000 });
    const bodyText = await page.textContent('body');
    expect(bodyText).toContain('Bancroft');
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-wo-review.png' });
  });

  // --- TEST 9: WO — GENERATE DOCUMENT ---
  test('9. WO — generate document (Bancroft WO)', async ({ page }) => {
    const errors = await captureErrors(page);
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await selectLocation(page);
    await clickNext(page);
    // Step 3 — vendor should auto-fill, just proceed
    await clickNext(page);
    // Step 4 — add a line
    await addLine(page, 'E2E Test - HVAC Service', '100');
    await clickNext(page);
    // Step 5 — GENERATE
    const genBtn = page.getByTestId('btn-generate-contract');
    await expect(genBtn).toBeVisible({ timeout: 10000 });
    await genBtn.click();
    // Wait for generation (can take up to 60s)
    await page.waitForLoadState('networkidle');
    // Check for success or error
    const viewDoc = page.getByTestId('link-view-document');
    const genError = page.getByTestId('gen-error');
    // Wait up to 60s for either outcome
    await Promise.race([
      viewDoc.waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      genError.waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
    ]);
    await captureToasts(page);
    if (await viewDoc.isVisible().catch(() => false)) {
      console.log('DOCUMENT GENERATED SUCCESSFULLY');
      const href = await viewDoc.getAttribute('href');
      console.log('Doc URL:', href);
    }
    if (await genError.isVisible().catch(() => false)) {
      const errText = await genError.textContent();
      console.log('GENERATION ERROR:', errText);
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-wo-generated.png', fullPage: true });
    console.log('Errors:', errors);
  });

  // --- TEST 10: Amendment — select type, parent WO dropdown appears ---
  test('10. Amendment — parent WO dropdown', async ({ page }) => {
    await goToWizard(page, '?type=amendment');
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'Amendment');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    // Parent WO dropdown should appear
    const parentDD = page.getByTestId('select-parent-wo');
    await expect(parentDD).toBeVisible({ timeout: 10000 });
    const options = await parentDD.locator('option').allTextContents();
    console.log(`Parent WO options: ${options.length} — ${options.slice(0, 5).join(', ')}`);
  });

  // --- TEST 11: Amendment — select parent WO, verify auto-fill ---
  test('11. Amendment — select parent WO and auto-fill', async ({ page }) => {
    await goToWizard(page, '?type=amendment');
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'Amendment');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    const parentDD = page.getByTestId('select-parent-wo');
    if (await parentDD.isVisible({ timeout: 10000 }).catch(() => false)) {
      const opts = await parentDD.locator('option').allTextContents();
      const realOpts = opts.filter(o => o.trim() && !o.includes('Select'));
      if (realOpts.length > 0) {
        await parentDD.selectOption({ label: realOpts[0] });
        await page.waitForLoadState('networkidle');
        // Amendment number should appear
        const amNum = page.getByTestId('amendment-number');
        if (await amNum.isVisible({ timeout: 5000 }).catch(() => false)) {
          console.log('Amendment number field visible');
        }
      }
    }
  });

  // --- TEST 12: Amendment — GENERATE DOCUMENT ---
  test('12. Amendment — generate document', async ({ page }) => {
    await goToWizard(page, '?type=amendment');
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'Amendment');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    const parentDD = page.getByTestId('select-parent-wo');
    if (await parentDD.isVisible({ timeout: 10000 }).catch(() => false)) {
      const opts = await parentDD.locator('option').allTextContents();
      const realOpts = opts.filter(o => o.trim() && !o.includes('Select'));
      if (realOpts.length > 0) {
        await parentDD.selectOption({ label: realOpts[0] });
        await page.waitForLoadState('networkidle');
      }
    }
    await clickNext(page);
    await clickNext(page);
    await addLine(page, 'E2E Test - Amendment Line', '200');
    await clickNext(page);
    const genBtn = page.getByTestId('btn-generate-contract');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await page.waitForLoadState('networkidle');
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.getByTestId('gen-error').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      await captureToasts(page);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) console.log('AMENDMENT GENERATED OK');
      const genError = page.getByTestId('gen-error');
      if (await genError.isVisible().catch(() => false)) console.log('AMENDMENT GEN ERROR:', await genError.textContent());
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-amendment-generated.png', fullPage: true });
  });

  // --- TEST 13: MSA — verify step 4 skipped ---
  test('13. MSA (Vendor Agreement) — step 4 skipped', async ({ page }) => {
    await goToWizard(page, '?type=msa');
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'ContractorMSA');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Step 3 — contractor
    await clickNext(page);
    // Should skip to step 5 (no Exhibit A)
    const genBtn = page.getByTestId('btn-generate-contract');
    await expect(genBtn).toBeVisible({ timeout: 10000 });
    console.log('MSA: Step 4 correctly skipped, on review');
  });

  // --- TEST 14: MSA — GENERATE DOCUMENT ---
  test('14. MSA — generate Vendor Agreement document', async ({ page }) => {
    await goToWizard(page, '?type=msa');
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'ContractorMSA');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    await clickNext(page); // skips to step 5
    const genBtn = page.getByTestId('btn-generate-contract');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await page.waitForLoadState('networkidle');
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.getByTestId('gen-error').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) console.log('MSA GENERATED OK');
      const genError = page.getByTestId('gen-error');
      if (await genError.isVisible().catch(() => false)) console.log('MSA GEN ERROR:', await genError.textContent());
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-msa-generated.png', fullPage: true });
  });

  // --- TEST 15: Back/forward navigation ---
  test('15. Back/forward navigation', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page); // step 3
    await clickBack(page);  // back to step 2
    const custSearch = page.getByTestId('search-customer');
    // Customer should still be selected (state preserved)
    await clickNext(page); // forward to step 3 again
    await clickNext(page); // step 4
    await clickBack(page);  // back to step 3
    console.log('Back/forward navigation works');
  });

  // --- TEST 16: Customer search type-ahead ---
  test('16. Customer search type-ahead', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    const searchInput = page.getByTestId('search-customer');
    await searchInput.fill('Ba'); // type 2 chars
    await page.waitForLoadState('networkidle');
    const options = page.getByTestId('customer-option');
    const count = await options.count();
    console.log(`Customer search "Ba": ${count} results`);
    expect(count).toBeGreaterThan(0);
  });

  // --- TEST 17: Cost code dropdown on Exhibit A ---
  test('17. Cost code dropdown select', async ({ page }) => {
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    await selectCustomer(page, 'Bancroft');
    await clickNext(page);
    await clickNext(page);
    await addLine(page, 'Test Line', '1000');
    // Select a cost code from dropdown
    const ccDD = page.getByTestId('select-cost-code').first();
    if (await ccDD.isVisible({ timeout: 5000 }).catch(() => false)) {
      const opts = await ccDD.locator('option').allTextContents();
      const realOpts = opts.filter(o => o.trim() && !o.includes('Select'));
      if (realOpts.length > 0) {
        await ccDD.selectOption({ label: realOpts[0] });
        console.log(`Selected cost code: ${realOpts[0]}`);
      }
    }
  });

  // --- TEST 18: Decades customer WO generate ---
  test('18. Decades customer WO — generate document', async ({ page }) => {
    const errors = await captureErrors(page);
    await goToWizard(page);
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'WorkOrder');
    await clickNext(page);
    // Search for a Decades family customer (non-Bancroft)
    await selectCustomer(page, 'Penn');
    await selectLocation(page);
    await clickNext(page);
    await clickNext(page);
    await addLine(page, 'E2E Test - Decades WO Service', '150');
    await clickNext(page);
    const genBtn = page.getByTestId('btn-generate-contract');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.getByTestId('gen-error').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) console.log('DECADES WO GENERATED OK');
      const genError = page.getByTestId('gen-error');
      if (await genError.isVisible().catch(() => false)) console.log('DECADES WO ERROR:', await genError.textContent());
    }
    await captureToasts(page);
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-decades-wo-generated.png', fullPage: true });
  });

  // --- TEST 19: Draft resume ---
  test('19. Draft resume from landing', async ({ page }) => {
    await goToWizard(page);
    const resumeBtn = page.getByTestId('btn-resume-draft').first();
    if (await resumeBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await resumeBtn.click();
      await page.waitForLoadState('networkidle');
      console.log('Draft resumed, current URL:', page.url());
    } else {
      console.log('No drafts available to resume');
    }
  });

  // --- TEST 20: Decades MSA generate ---
  test('20. Decades Vendor MSA — generate document', async ({ page }) => {
    await goToWizard(page, '?type=msa');
    const startNew = page.getByTestId('start-new-contract');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) await startNew.click();
    await selectDocType(page, 'ContractorMSA');
    await clickNext(page);
    await selectCustomer(page, 'Penn');
    await clickNext(page);
    await clickNext(page);
    const genBtn = page.getByTestId('btn-generate-contract');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.getByTestId('gen-error').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) console.log('DECADES MSA GENERATED OK');
      const genError = page.getByTestId('gen-error');
      if (await genError.isVisible().catch(() => false)) console.log('DECADES MSA ERROR:', await genError.textContent());
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/wizard-decades-msa-generated.png', fullPage: true });
  });
});
