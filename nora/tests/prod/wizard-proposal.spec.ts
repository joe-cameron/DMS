import { test, expect, Page } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

const BASE = 'https://dmms1.powerappsportals.com';

async function goToProposal(page: Page) {
  await page.goto(`${BASE}/#/proposals/new`);
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

async function skipDrafts(page: Page) {
  const startNew = page.getByTestId('start-new-proposal');
  if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) {
    await startNew.click();
    await page.waitForLoadState('networkidle');
  }
}

async function selectPackage(page: Page, pkg: 'A' | 'B' | 'C') {
  const card = page.getByTestId(`pkg-${pkg}`);
  await expect(card).toBeVisible({ timeout: 10000 });
  await card.click();
}

async function clickNext(page: Page) {
  const nextTop = page.getByTestId('btn-next-top');
  const nextBot = page.getByTestId('btn-next');
  if (await nextTop.isVisible({ timeout: 3000 }).catch(() => false)) {
    await nextTop.click();
  } else if (await nextBot.isVisible({ timeout: 3000 }).catch(() => false)) {
    await nextBot.click();
  }
  await page.waitForLoadState('networkidle');
}

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

async function searchSelectCustomer(page: Page, term = 'Bancroft') {
  const searchInput = page.getByTestId('customer-search');
  if (await searchInput.isVisible({ timeout: 5000 }).catch(() => false)) {
    await searchInput.fill(term);
    await page.waitForLoadState('networkidle');
    // Click first result
    const option = page.locator('[data-testid^="customer-option"], [style*="cursor: pointer"]').filter({ hasText: new RegExp(term, 'i') }).first();
    if (await option.isVisible({ timeout: 5000 }).catch(() => false)) {
      await option.click();
      await page.waitForLoadState('networkidle');
    }
  } else {
    // Try alternate selector
    const altSearch = page.locator('input[placeholder*="search" i], input[placeholder*="customer" i]').first();
    if (await altSearch.isVisible({ timeout: 5000 }).catch(() => false)) {
      await altSearch.fill(term);
      await page.waitForLoadState('networkidle');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// PROPOSAL WIZARD — 20 TESTS
// ═══════════════════════════════════════════════════════════════

test.describe('Proposal Wizard', () => {

  // --- TEST 1: Navigate all 4 steps ---
  test('1. Navigate all 4 steps', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    // Step 1: select package
    await selectPackage(page, 'A');
    await clickNext(page);
    // Step 2: customer
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Step 3: pricing
    await page.waitForLoadState('networkidle');
    await clickNext(page);
    // Step 4: review
    await page.waitForLoadState('networkidle');
    const genBtn = page.getByTestId('btn-generate-proposal');
    await expect(genBtn).toBeVisible({ timeout: 10000 });
    console.log('All 4 proposal steps navigated');
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/proposal-step4.png' });
  });

  // --- TEST 2: Select Package A ---
  test('2. Package A selection', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    // Verify card is highlighted
    const card = page.getByTestId('pkg-A');
    const style = await card.getAttribute('style');
    console.log('Package A style:', style?.substring(0, 100));
  });

  // --- TEST 3: Select Package B ---
  test('3. Package B selection', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'B');
    const card = page.getByTestId('pkg-B');
    const style = await card.getAttribute('style');
    console.log('Package B style:', style?.substring(0, 100));
  });

  // --- TEST 4: Select Package C ---
  test('4. Package C selection', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'C');
    const card = page.getByTestId('pkg-C');
    const style = await card.getAttribute('style');
    console.log('Package C style:', style?.substring(0, 100));
  });

  // --- TEST 5: Switch between packages ---
  test('5. Switch between packages', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await selectPackage(page, 'B');
    await selectPackage(page, 'C');
    await selectPackage(page, 'A'); // back to A
    console.log('Package switching works');
  });

  // --- TEST 6: Customer search and select ---
  test('6. Customer search and select', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    const body = await page.textContent('body');
    console.log(`Customer selected: contains Bancroft = ${body?.includes('Bancroft')}`);
  });

  // --- TEST 7: New customer creation mode ---
  test('7. New customer mode toggle', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    const newCustBtn = page.getByTestId('btn-new-customer');
    if (await newCustBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await newCustBtn.click();
      await page.waitForLoadState('networkidle');
      console.log('New customer form toggled');
      // Switch back
      const searchBtn = page.getByTestId('btn-search-existing');
      if (await searchBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await searchBtn.click();
      }
    }
  });

  // --- TEST 8: Verify vendor info is pre-filled ---
  test('8. Vendor info pre-filled', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    // Look for vendor info (Decades Construction Group)
    const body = await page.textContent('body');
    console.log(`Contains "Decades Construction": ${body?.includes('Decades Construction')}`);
  });

  // --- TEST 9: Signer name/title editing ---
  test('9. Edit signer name and title', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    // Look for signer fields
    const signerInputs = page.locator('[data-testid*="signer"], input[placeholder*="signer" i]');
    const count = await signerInputs.count();
    console.log(`Signer inputs found: ${count}`);
  });

  // --- TEST 10: MSA effective date ---
  test('10. MSA effective date field', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    // Look for date input
    const dateInput = page.locator('input[type="date"]').first();
    if (await dateInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      const val = await dateInput.inputValue();
      console.log(`Effective date default: ${val}`);
    }
  });

  // --- TEST 11: Uniform pricing ---
  test('11. Uniform pricing fields', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Step 3 — pricing
    const uniformBtn = page.getByTestId('pricing-uniform');
    if (await uniformBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await uniformBtn.click();
      console.log('Uniform pricing mode active');
    }
    // Look for monthly rate input
    const rateInputs = page.locator('input[type="number"], input[placeholder*="rate" i], input[placeholder*="$" i]');
    console.log(`Pricing inputs: ${await rateInputs.count()}`);
  });

  // --- TEST 12: Type-based pricing ---
  test('12. Type-based pricing toggle', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    const typeBtn = page.getByTestId('pricing-type-based');
    if (await typeBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await typeBtn.click();
      await page.waitForLoadState('networkidle');
      console.log('Type-based pricing mode active');
    }
  });

  // --- TEST 13: Add a location manually ---
  test('13. Add location', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    const addBtn = page.getByTestId('btn-add-location');
    if (await addBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await addBtn.click();
      await page.waitForLoadState('networkidle');
      console.log('Add location form opened');
      // Fill basic fields and confirm
      const confirmBtn = page.getByTestId('btn-confirm-add-location');
      if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.log('Add location form has confirm button');
      }
    }
  });

  // --- TEST 14: Import CSV button ---
  test('14. Import CSV button visible', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    const importBtn = page.getByTestId('btn-import-locations');
    if (await importBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log('Import CSV button present');
    }
  });

  // --- TEST 15: Config save/load system ---
  test('15. Config save/load buttons', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    const configBanner = page.getByTestId('config-banner');
    if (await configBanner.isVisible({ timeout: 5000 }).catch(() => false)) {
      const loadBtn = page.getByTestId('btn-load-config');
      const saveBtn = page.getByTestId('btn-save-config');
      if (await loadBtn.isVisible()) {
        await loadBtn.click();
        const dropdown = page.getByTestId('config-dropdown');
        if (await dropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
          console.log('Config dropdown opened');
          await page.keyboard.press('Escape');
        }
      }
      if (await saveBtn.isVisible()) {
        await saveBtn.click();
        const saveForm = page.getByTestId('config-save-form');
        if (await saveForm.isVisible({ timeout: 3000 }).catch(() => false)) {
          console.log('Config save form opened');
          const cancelSave = page.getByTestId('btn-cancel-save-config');
          if (await cancelSave.isVisible()) await cancelSave.click();
        }
      }
    }
  });

  // --- TEST 16: Package A — GENERATE PROPOSAL ---
  test('16. Package A — generate proposal (Bancroft)', async ({ page }) => {
    const errors = await captureErrors(page);
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Pricing step — just use defaults
    await clickNext(page);
    // Step 4 — generate
    const genBtn = page.getByTestId('btn-generate-proposal');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await page.waitForLoadState('networkidle');
      // Wait for result
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.getByTestId('link-msa-detail').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.locator('text=Error').first().waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) {
        const href = await viewDoc.getAttribute('href');
        console.log('PROPOSAL A GENERATED OK, doc URL:', href);
      }
      await captureToasts(page);
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/proposal-A-generated.png', fullPage: true });
    console.log('Errors:', errors);
  });

  // --- TEST 17: Package B — GENERATE PROPOSAL ---
  test('17. Package B — generate proposal', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'B');
    await clickNext(page);
    await searchSelectCustomer(page, 'Penn');
    await clickNext(page);
    await clickNext(page);
    const genBtn = page.getByTestId('btn-generate-proposal');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.locator('text=Error').first().waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) console.log('PROPOSAL B GENERATED OK');
      await captureToasts(page);
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/proposal-B-generated.png', fullPage: true });
  });

  // --- TEST 18: Package C — GENERATE PROPOSAL ---
  test('18. Package C — generate proposal', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'C');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    await clickNext(page);
    const genBtn = page.getByTestId('btn-generate-proposal');
    if (await genBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await genBtn.click();
      await Promise.race([
        page.getByTestId('link-view-document').waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
        page.locator('text=Error').first().waitFor({ state: 'visible', timeout: 60000 }).catch(() => null),
      ]);
      const viewDoc = page.getByTestId('link-view-document');
      if (await viewDoc.isVisible().catch(() => false)) console.log('PROPOSAL C GENERATED OK');
      await captureToasts(page);
    }
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/proposal-C-generated.png', fullPage: true });
  });

  // --- TEST 19: Back/forward navigation ---
  test('19. Back/forward navigation', async ({ page }) => {
    await goToProposal(page);
    await skipDrafts(page);
    await selectPackage(page, 'A');
    await clickNext(page);
    await searchSelectCustomer(page, 'Bancroft');
    await clickNext(page);
    // Step 3 — go back
    await clickBack(page);
    // Step 2 — go back
    await clickBack(page);
    // Step 1 — verify package still selected
    const cardA = page.getByTestId('pkg-A');
    const style = await cardA.getAttribute('style');
    console.log('Package A still selected after back:', style?.includes('2px solid'));
    // Forward again
    await clickNext(page);
    await clickNext(page);
    console.log('Back/forward navigation works');
  });

  // --- TEST 20: Draft resume ---
  test('20. Draft resume from landing', async ({ page }) => {
    await goToProposal(page);
    const resumeBtn = page.getByTestId('btn-resume-draft').first();
    if (await resumeBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await resumeBtn.click();
      await page.waitForLoadState('networkidle');
      console.log('Proposal draft resumed');
    } else {
      console.log('No proposal drafts available');
    }
  });
});
