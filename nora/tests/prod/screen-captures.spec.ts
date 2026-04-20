import { test, expect, Page } from '@playwright/test';
import * as path from 'path';

test.use({ storageState: './prod-auth-state.json' });

const BASE = 'https://dmms1.powerappsportals.com';
const OUT  = path.resolve(__dirname, '../../../docs/screen-captures');

/** Navigate + wait for SPA to render */
async function go(page: Page, hash: string) {
  await page.goto(`${BASE}/#/${hash}`);
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });
  await page.waitForTimeout(800); // let animations settle
}

/** Save screenshot to structured path */
async function snap(page: Page, folder: string, name: string) {
  const dir = path.join(OUT, folder);
  await page.screenshot({ path: path.join(dir, `${name}.png`), fullPage: false });
}

/** Type into a field by testid */
async function fill(page: Page, testId: string, value: string) {
  const el = page.getByTestId(testId);
  await el.click();
  await el.fill(value);
}

/** Select first option from a dropdown by testid */
async function selectFirst(page: Page, testId: string) {
  const el = page.getByTestId(testId);
  await el.click();
  const options = el.locator('option');
  const count = await options.count();
  if (count > 1) {
    const val = await options.nth(1).getAttribute('value');
    if (val) await el.selectOption(val);
  }
}

// ═══════════════════════════════════════════════════════
// 1. MSA COMPOSER (Proposal Wizard)
// ═══════════════════════════════════════════════════════
test.describe('MSA Composer', () => {
  test('capture all steps', async ({ page }) => {
    await go(page, 'proposals/new');

    // Skip draft picker if visible
    const startNew = page.getByTestId('start-new-proposal');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) {
      await startNew.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(500);
    }

    // 1a — Package selection (initial state)
    await snap(page, '01-msa-composer', '01-package-selection');

    // Select Package A
    const pkgA = page.getByTestId('package-A').or(page.getByTestId('pkg-A'));
    if (await pkgA.isVisible({ timeout: 5000 }).catch(() => false)) {
      await pkgA.click();
      await page.waitForTimeout(400);
    }
    await snap(page, '01-msa-composer', '02-package-a-selected');

    // 1b — Customer search mode
    const custSearch = page.getByTestId('msa-btn-cust-search');
    if (await custSearch.isVisible({ timeout: 3000 }).catch(() => false)) {
      await custSearch.click();
      await page.waitForTimeout(400);
    }
    // Type into search
    const searchInput = page.getByTestId('customer-search');
    if (await searchInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await searchInput.fill('a');
      await page.waitForTimeout(1500); // let results load
    }
    await snap(page, '01-msa-composer', '03-customer-search');

    // Click first customer result
    const firstResult = page.locator('[data-testid^="customer-result-"]').first();
    if (await firstResult.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstResult.click();
      await page.waitForTimeout(800);
    }
    await snap(page, '01-msa-composer', '04-customer-selected');

    // 1c — Signer info
    const signerName = page.getByTestId('cust-signer-name');
    if (await signerName.isVisible({ timeout: 3000 }).catch(() => false)) {
      await signerName.fill('VP of Operations');
      const signerTitle = page.getByTestId('cust-signer-title');
      if (await signerTitle.isVisible()) await signerTitle.fill('Vice President');
      await page.waitForTimeout(300);
    }
    await snap(page, '01-msa-composer', '05-signer-info');

    // 1d — Pricing: uniform
    const uniformBtn = page.getByTestId('msa-btn-price-uniform');
    if (await uniformBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await uniformBtn.click();
      await page.waitForTimeout(300);
      const uniRate = page.getByTestId('uni-rate');
      if (await uniRate.isVisible()) await uniRate.fill('450');
      const uniOnboard = page.getByTestId('uni-onboard');
      if (await uniOnboard.isVisible()) await uniOnboard.fill('250');
    }
    await snap(page, '01-msa-composer', '06-pricing-uniform');

    // 1e — Switch to type-based pricing
    const typeBasedBtn = page.getByTestId('msa-btn-price-typebased');
    if (await typeBasedBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await typeBasedBtn.click();
      await page.waitForTimeout(500);
    }
    await snap(page, '01-msa-composer', '07-pricing-typebased');

    // 1f — Add location manually
    const locName = page.getByTestId('new-loc-name');
    if (await locName.isVisible({ timeout: 3000 }).catch(() => false)) {
      await locName.fill('Corporate HQ - Main Campus');
      const addLoc = page.getByTestId('btn-add-loc');
      if (await addLoc.isVisible()) await addLoc.click();
      await page.waitForTimeout(400);
    }
    await snap(page, '01-msa-composer', '08-location-added');

    // 1g — CSV import button visible
    const csvBtn = page.getByTestId('btn-import-csv');
    if (await csvBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await snap(page, '01-msa-composer', '09-csv-import-available');
    }
  });
});

// ═══════════════════════════════════════════════════════
// 2. CONTRACT COMPOSER — Work Order
// ═══════════════════════════════════════════════════════
test.describe('Contract Composer — Work Order', () => {
  test('capture all steps', async ({ page }) => {
    await go(page, 'contracts/new?type=wo');

    // Skip draft picker if visible
    const startNew = page.locator('[data-testid="start-new-contract"]');
    if (await startNew.isVisible({ timeout: 5000 }).catch(() => false)) {
      await startNew.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(500);
    }

    // 2a — Initial state with WO type selected
    await snap(page, '02-contract-wo', '01-wo-type-selected');

    // 2b — Customer selection
    const custBtns = page.locator('[data-testid^="cc-btn-customer-"]');
    const custCount = await custBtns.count();
    if (custCount > 0) {
      await custBtns.first().click();
      await page.waitForTimeout(800);
    }
    await snap(page, '02-contract-wo', '02-customer-selected');

    // 2c — Blanket WO dropdown
    const blanketSelect = page.getByTestId('cc-blanket-wo-select');
    if (await blanketSelect.isVisible({ timeout: 3000 }).catch(() => false)) {
      await snap(page, '02-contract-wo', '03-blanket-wo-dropdown');
    }

    // 2d — Add Exhibit A item
    const addItem = page.getByTestId('cc-btn-add-item');
    if (await addItem.isVisible({ timeout: 3000 }).catch(() => false)) {
      await addItem.click();
      await page.waitForTimeout(500);
    }
    await snap(page, '02-contract-wo', '04-exhibit-a-item-added');

    // 2e — Add another item
    const addAnother = page.getByTestId('cc-btn-add-another');
    if (await addAnother.isVisible({ timeout: 3000 }).catch(() => false)) {
      await addAnother.click();
      await page.waitForTimeout(500);
    }
    await snap(page, '02-contract-wo', '05-multiple-items');

    // 2f — Full page with form filled
    await snap(page, '02-contract-wo', '06-full-page-overview');
  });
});

// ═══════════════════════════════════════════════════════
// 3. CONTRACT COMPOSER — Amendment
// ═══════════════════════════════════════════════════════
test.describe('Contract Composer — Amendment', () => {
  test('capture steps', async ({ page }) => {
    await go(page, 'contracts/new?type=amendment');
    await page.waitForTimeout(500);

    // 3a — Initial amendment view
    await snap(page, '03-contract-amendment', '01-amendment-initial');

    // Select first customer if available
    const custBtns = page.locator('[data-testid^="cc-btn-customer-"]');
    if (await custBtns.count() > 0) {
      await custBtns.first().click();
      await page.waitForTimeout(800);
    }
    await snap(page, '03-contract-amendment', '02-customer-selected');

    // Parent WO dropdown
    await snap(page, '03-contract-amendment', '03-parent-wo-dropdown');
  });
});

// ═══════════════════════════════════════════════════════
// 4. CONTRACT COMPOSER — Vendor Agreement
// ═══════════════════════════════════════════════════════
test.describe('Contract Composer — Vendor Agreement', () => {
  test('capture steps', async ({ page }) => {
    await go(page, 'contracts/new?type=msa');
    await page.waitForTimeout(500);

    // 4a — Initial VA view
    await snap(page, '04-contract-va', '01-va-initial');

    // Select first customer
    const custBtns = page.locator('[data-testid^="cc-btn-customer-"]');
    if (await custBtns.count() > 0) {
      await custBtns.first().click();
      await page.waitForTimeout(800);
    }
    await snap(page, '04-contract-va', '02-customer-selected');

    // Full view
    await snap(page, '04-contract-va', '03-full-page');
  });
});

// ═══════════════════════════════════════════════════════
// 5. NEW CUSTOMER
// ═══════════════════════════════════════════════════════
test.describe('New Customer', () => {
  test('capture panel', async ({ page }) => {
    await go(page, 'customers');

    // 5a — List view before opening panel
    await snap(page, '05-new-customer', '01-customer-list');

    // Click + New Customer
    const newBtn = page.getByTestId('cust-btn-new');
    await expect(newBtn).toBeVisible({ timeout: 10000 });
    await newBtn.click();
    await page.waitForTimeout(600);

    // 5b — Empty panel
    await snap(page, '05-new-customer', '02-panel-open-empty');

    // Fill in form
    const nameInput = page.getByTestId('cust-new-dcfg_name');
    if (await nameInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await nameInput.fill('Sample Facilities Corp');
    }

    // Add contact
    const addContact = page.getByTestId('cust-btn-add-contact');
    if (await addContact.isVisible({ timeout: 3000 }).catch(() => false)) {
      await addContact.click();
      await page.waitForTimeout(400);

      const contactName = page.getByTestId('cust-new-dcfg_primary_contact_name');
      if (await contactName.isVisible()) await contactName.fill('Operations Manager');
      const contactEmail = page.getByTestId('cust-new-dcfg_primary_contact_email');
      if (await contactEmail.isVisible()) await contactEmail.fill('ops@example.com');
      const contactTitle = page.getByTestId('cust-new-dcfg_primary_contact_title');
      if (await contactTitle.isVisible()) await contactTitle.fill('Director of Operations');
      const contactPhone = page.getByTestId('cust-new-dcfg_primary_contact_phone');
      if (await contactPhone.isVisible()) await contactPhone.fill('(555) 123-4567');
    }

    // 5c — Filled form
    await snap(page, '05-new-customer', '03-panel-filled');
  });
});

// ═══════════════════════════════════════════════════════
// 6. NEW LOCATION
// ═══════════════════════════════════════════════════════
test.describe('New Location', () => {
  test('capture panel', async ({ page }) => {
    await go(page, 'locations');

    // 6a — List view
    await snap(page, '06-new-location', '01-location-list');

    // Click + New Location
    const newBtn = page.getByTestId('loc-btn-new');
    await expect(newBtn).toBeVisible({ timeout: 10000 });
    await newBtn.click();
    await page.waitForTimeout(600);

    // 6b — Empty panel
    await snap(page, '06-new-location', '02-panel-open-empty');

    // Fill form
    const nameInput = page.getByTestId('loc-new-dcfg_name');
    if (await nameInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await nameInput.fill('Downtown Office Tower');
    }
    const addrInput = page.getByTestId('loc-new-dcfg_address');
    if (await addrInput.isVisible()) await addrInput.fill('100 Main Street');
    const cityInput = page.getByTestId('loc-new-dcfg_city');
    if (await cityInput.isVisible()) await cityInput.fill('Philadelphia');
    const stateInput = page.getByTestId('loc-new-dcfg_state');
    if (await stateInput.isVisible()) await stateInput.fill('PA');
    const zipInput = page.getByTestId('loc-new-dcfg_zip');
    if (await zipInput.isVisible()) await zipInput.fill('19103');

    // Select customer dropdown
    const custDropdown = page.getByTestId('loc-new-dcfg_customer_id');
    if (await custDropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = custDropdown.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await custDropdown.selectOption(val);
      }
    }

    // Select location type
    const typeDropdown = page.getByTestId('loc-new-dcfg_location_type_id');
    if (await typeDropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = typeDropdown.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await typeDropdown.selectOption(val);
      }
    }

    await page.waitForTimeout(300);

    // 6c — Filled form
    await snap(page, '06-new-location', '03-panel-filled');
  });
});

// ═══════════════════════════════════════════════════════
// 7. NEW PROJECT
// ═══════════════════════════════════════════════════════
test.describe('New Project', () => {
  test('capture panel', async ({ page }) => {
    await go(page, 'projects');

    // 7a — Project list
    await snap(page, '07-new-project', '01-project-list');

    // Click + New Project
    const newBtn = page.getByTestId('projects-btn-new');
    await expect(newBtn).toBeVisible({ timeout: 10000 });
    await newBtn.click();
    await page.waitForTimeout(600);

    // 7b — Empty panel
    await snap(page, '07-new-project', '02-panel-open-empty');

    // Fill form
    const nameInput = page.getByTestId('projects-new-name');
    if (await nameInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await nameInput.fill('HVAC Replacement - Building A');
    }

    // Select category
    const catDropdown = page.getByTestId('projects-new-category');
    if (await catDropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = catDropdown.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await catDropdown.selectOption(val);
      }
    }

    // Select urgency
    const urgencyDropdown = page.getByTestId('projects-new-urgency');
    if (await urgencyDropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = urgencyDropdown.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await urgencyDropdown.selectOption(val);
      }
    }

    // Use existing customer mode
    const existingMode = page.getByTestId('cust-mode-existing');
    if (await existingMode.isVisible({ timeout: 3000 }).catch(() => false)) {
      await existingMode.click();
      await page.waitForTimeout(400);
    }

    // Select customer
    const custDropdown = page.getByTestId('projects-new-customer');
    if (await custDropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = custDropdown.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await custDropdown.selectOption(val);
        await page.waitForTimeout(500);
      }
    }

    // Select location
    const propDropdown = page.getByTestId('projects-new-property');
    if (await propDropdown.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = propDropdown.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await propDropdown.selectOption(val);
      }
    }

    // Description
    const descInput = page.getByTestId('projects-new-desc');
    if (await descInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await descInput.fill('Replace aging HVAC units across all floors. Includes ductwork inspection.');
    }

    // Click a trade toggle if visible
    const tradeBtns = page.locator('[data-testid^="projects-new-trade-"]');
    const tradeCount = await tradeBtns.count();
    if (tradeCount > 0) {
      await tradeBtns.first().click();
      if (tradeCount > 1) await tradeBtns.nth(1).click();
      await page.waitForTimeout(300);
    }

    // 7c — Filled form
    await snap(page, '07-new-project', '03-panel-filled');

    // Scroll down to see full form if needed
    const panel = page.getByTestId('projects-new-panel');
    if (await panel.isVisible({ timeout: 2000 }).catch(() => false)) {
      await panel.evaluate(el => el.scrollTop = el.scrollHeight);
      await page.waitForTimeout(300);
      await snap(page, '07-new-project', '04-panel-filled-bottom');
    }
  });
});

// ═══════════════════════════════════════════════════════
// 8. NEW ONBOARDING CASE
// ═══════════════════════════════════════════════════════
test.describe('New Onboarding Case', () => {
  test('capture panel', async ({ page }) => {
    await go(page, 'onboarding');

    // 8a — Onboarding list
    await snap(page, '08-new-onboarding', '01-onboarding-list');

    // Click + New Case
    const newBtn = page.getByTestId('onb-btn-new');
    await expect(newBtn).toBeVisible({ timeout: 10000 });
    await newBtn.click();
    await page.waitForTimeout(600);

    // 8b — Empty panel
    await snap(page, '08-new-onboarding', '02-panel-open-empty');

    // Select customer
    const custSelect = page.getByTestId('new-case-customer-select');
    if (await custSelect.isVisible({ timeout: 3000 }).catch(() => false)) {
      const options = custSelect.locator('option');
      const count = await options.count();
      if (count > 1) {
        const val = await options.nth(1).getAttribute('value');
        if (val) await custSelect.selectOption(val);
      }
    }
    await page.waitForTimeout(300);

    // 8c — Customer selected
    await snap(page, '08-new-onboarding', '03-customer-selected');
  });
});

// ═══════════════════════════════════════════════════════
// 9. NEW RFP WIZARD
// ═══════════════════════════════════════════════════════
test.describe('New RFP Wizard', () => {
  test('capture all steps', async ({ page }) => {
    await go(page, 'rfps/new');

    // 9a — Step 1: Bid Info (empty)
    await snap(page, '09-rfp-wizard', '01-step1-empty');

    // Fill Step 1
    const rfpName = page.getByTestId('rfp-input-name');
    if (await rfpName.isVisible({ timeout: 5000 }).catch(() => false)) {
      await rfpName.fill('Q3 HVAC Replacement Package');
    }
    const rfpScope = page.getByTestId('rfp-input-scope');
    if (await rfpScope.isVisible()) {
      await rfpScope.fill('Full HVAC replacement across 12 locations including ductwork inspection, unit installation, and commissioning.');
    }
    const rfpValue = page.getByTestId('rfp-input-value');
    if (await rfpValue.isVisible()) await rfpValue.fill('850000');
    const rfpDeadline = page.getByTestId('rfp-input-deadline');
    if (await rfpDeadline.isVisible()) await rfpDeadline.fill('2026-06-30');

    // 9b — Step 1: Filled
    await snap(page, '09-rfp-wizard', '02-step1-filled');

    // Click Next
    const nextBtn = page.getByTestId('rfp-wizard-next-btn');
    if (await nextBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await nextBtn.click();
      await page.waitForTimeout(800);
    }

    // 9c — Step 2: Select Projects
    await snap(page, '09-rfp-wizard', '03-step2-projects');

    // Select some projects if available
    const projectOptions = page.locator('[data-testid="rfp-project-option"]');
    const projCount = await projectOptions.count();
    if (projCount > 0) {
      await projectOptions.first().click();
      if (projCount > 1) await projectOptions.nth(1).click();
      await page.waitForTimeout(400);
    }
    await snap(page, '09-rfp-wizard', '04-step2-projects-selected');

    // Click Next to Review
    if (await nextBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await nextBtn.click();
      await page.waitForTimeout(800);
    }

    // 9d — Step 3: Review
    await snap(page, '09-rfp-wizard', '05-step3-review');
  });
});

// ═══════════════════════════════════════════════════════
// 10. ADMIN — Create Panels
// ═══════════════════════════════════════════════════════
test.describe('Admin Creates', () => {
  test('capture onboarding step', async ({ page }) => {
    await go(page, 'admin');

    // 10a — Admin overview
    await snap(page, '10-admin', '01-admin-overview');

    // Click Onboarding Steps card
    const stepsCard = page.locator('[data-testid="admin-card-onboarding-steps"]')
      .or(page.locator('text=Onboarding Steps').first());
    if (await stepsCard.isVisible({ timeout: 5000 }).catch(() => false)) {
      await stepsCard.click();
      await page.waitForTimeout(600);
      await snap(page, '10-admin', '02-onboarding-steps-list');

      // Click + Add Step
      const addStep = page.getByTestId('admin-btn-new-step');
      if (await addStep.isVisible({ timeout: 3000 }).catch(() => false)) {
        await addStep.click();
        await page.waitForTimeout(500);

        // Fill step form
        const stepNum = page.getByTestId('admin-step-dcfg_step_number');
        if (await stepNum.isVisible()) await stepNum.fill('99');
        const stepName = page.getByTestId('admin-step-dcfg_step_name');
        if (await stepName.isVisible()) await stepName.fill('Final Walkthrough');
        const stepNotes = page.getByTestId('admin-step-dcfg_notes');
        if (await stepNotes.isVisible()) await stepNotes.fill('Complete site walkthrough with customer representative');

        await snap(page, '10-admin', '03-new-step-form');
      }
    }
  });

  test('capture cost code', async ({ page }) => {
    await go(page, 'admin');

    const costCard = page.locator('[data-testid="admin-card-cost-codes"]')
      .or(page.locator('text=Cost Codes').first());
    if (await costCard.isVisible({ timeout: 5000 }).catch(() => false)) {
      await costCard.click();
      await page.waitForTimeout(600);
      await snap(page, '10-admin', '04-cost-codes-list');

      const addCode = page.getByTestId('admin-btn-new-cost-code');
      if (await addCode.isVisible({ timeout: 3000 }).catch(() => false)) {
        await addCode.click();
        await page.waitForTimeout(500);

        const codeInput = page.getByTestId('admin-costcode-dcfg_cost_code');
        if (await codeInput.isVisible()) await codeInput.fill('HVAC-001');
        const descInput = page.getByTestId('admin-costcode-dcfg_description');
        if (await descInput.isVisible()) await descInput.fill('HVAC Installation & Repair');

        await snap(page, '10-admin', '05-new-cost-code-form');
      }
    }
  });

  test('capture location type', async ({ page }) => {
    await go(page, 'admin');

    const locTypeCard = page.locator('[data-testid="admin-card-location-types"]')
      .or(page.locator('text=Location Types').first());
    if (await locTypeCard.isVisible({ timeout: 5000 }).catch(() => false)) {
      await locTypeCard.click();
      await page.waitForTimeout(600);
      await snap(page, '10-admin', '06-location-types-list');

      const addType = page.getByTestId('admin-btn-new-location-type');
      if (await addType.isVisible({ timeout: 3000 }).catch(() => false)) {
        await addType.click();
        await page.waitForTimeout(500);

        const nameInput = page.getByTestId('admin-loctype-dcfg_name');
        if (await nameInput.isVisible()) await nameInput.fill('Medical Office');
        const descInput = page.getByTestId('admin-loctype-dcfg_description');
        if (await descInput.isVisible()) await descInput.fill('Medical or dental office facility');

        await snap(page, '10-admin', '07-new-location-type-form');
      }
    }
  });

  test('capture vendor', async ({ page }) => {
    await go(page, 'admin');

    const vendorCard = page.locator('[data-testid="admin-card-vendors"]')
      .or(page.locator('text=Vendors').first());
    if (await vendorCard.isVisible({ timeout: 5000 }).catch(() => false)) {
      await vendorCard.click();
      await page.waitForTimeout(600);
      await snap(page, '10-admin', '08-vendors-list');

      const addVendor = page.getByTestId('admin-btn-new-vendor');
      if (await addVendor.isVisible({ timeout: 3000 }).catch(() => false)) {
        await addVendor.click();
        await page.waitForTimeout(500);
        await snap(page, '10-admin', '09-new-vendor-form');
      }
    }
  });
});
