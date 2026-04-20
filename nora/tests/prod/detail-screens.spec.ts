import { test, expect, Page } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

const BASE = 'https://dmms1.powerappsportals.com';

async function goTo(page: Page, hash: string) {
  await page.goto(`${BASE}/#/${hash}`);
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });
}

async function captureToasts(page: Page): Promise<string[]> {
  const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').allTextContents();
  if (toasts.length) console.log('TOASTS:', toasts.join(' | '));
  return toasts;
}

async function navigateToFirstDetail(page: Page, listRoute: string, rowTestId: string): Promise<boolean> {
  await goTo(page, listRoute);
  const row = page.getByTestId(rowTestId).first();
  if (await row.isVisible({ timeout: 15000 }).catch(() => false)) {
    await row.click();
    await page.waitForLoadState('networkidle');
    await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });
    return true;
  }
  return false;
}

// ═══ CUSTOMER DETAIL ═══

test.describe('CustomerDetail', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'customers', 'cust-row');
      if (!ok) { test.skip(); return; }
      expect(page.url()).toContain('customers/');
    });

    test(`Edit button — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'customers', 'cust-row');
      if (!ok) { test.skip(); return; }
      const editBtn = page.getByTestId('custd-btn-edit');
      if (await editBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        await editBtn.click();
        const nameField = page.getByTestId('custd-dcfg_name');
        if (await nameField.isVisible({ timeout: 3000 }).catch(() => false)) console.log('Edit mode active');
        const cancelBtn = page.getByTestId('custd-btn-cancel');
        if (await cancelBtn.isVisible()) await cancelBtn.click();
      }
    });

    test(`Tabs switch — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'customers', 'cust-row');
      if (!ok) { test.skip(); return; }
      for (const tab of ['overview', 'locations', 'msas', 'contracts', 'onboarding', 'programs']) {
        const tabEl = page.getByTestId(`custd-tab-${tab}`);
        if (await tabEl.isVisible({ timeout: 3000 }).catch(() => false)) {
          await tabEl.click();
          await page.waitForLoadState('networkidle');
        }
      }
    });
  }

  test('New Contract button', async ({ page }) => {
    const ok = await navigateToFirstDetail(page, 'customers', 'cust-row');
    if (!ok) { test.skip(); return; }
    const btn = page.getByTestId('custd-btn-new-contract');
    if (await btn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await btn.click();
      await page.waitForLoadState('networkidle');
      expect(page.url()).toContain('contracts/new');
    }
  });
});

// ═══ CONTRACT DETAIL ═══

test.describe('ContractDetail', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'contracts', 'contracts-row');
      if (!ok) { test.skip(); return; }
      expect(page.url()).toContain('contracts/');
    });

    test(`Status banner — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'contracts', 'contracts-row');
      if (!ok) { test.skip(); return; }
      const banner = page.getByTestId('status-banner');
      if (await banner.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.log(`Status: ${await banner.textContent()}`);
      }
    });

    test(`Action buttons — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'contracts', 'contracts-row');
      if (!ok) { test.skip(); return; }
      for (const btn of ['btn-generate', 'btn-status-action', 'btn-void', 'btn-decline', 'btn-create-amendment']) {
        const el = page.getByTestId(btn);
        if (await el.isVisible({ timeout: 2000 }).catch(() => false)) console.log(`Visible: ${btn}`);
      }
    });
  }

  test('Exhibit A lines', async ({ page }) => {
    const ok = await navigateToFirstDetail(page, 'contracts', 'contracts-row');
    if (!ok) { test.skip(); return; }
    const body = await page.textContent('body');
    console.log(`Has line items: ${body?.includes('Description') || body?.includes('Amount')}`);
  });

  test('Audit trail', async ({ page }) => {
    const ok = await navigateToFirstDetail(page, 'contracts', 'contracts-row');
    if (!ok) { test.skip(); return; }
    const body = await page.textContent('body');
    console.log(`Has audit: ${body?.includes('Audit') || body?.includes('History') || body?.includes('Timeline')}`);
  });
});

// ═══ MSA DETAIL ═══

test.describe('MsaDetail', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'msas', 'msas-row');
      if (!ok) { test.skip(); return; }
      expect(page.url()).toContain('msas/');
    });

    test(`Content renders — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'msas', 'msas-row');
      if (!ok) { test.skip(); return; }
      const body = await page.textContent('body');
      expect(body).not.toContain('Access Denied');
      await captureToasts(page);
    });
  }
});

// ═══ LOCATION DETAIL ═══

test.describe('LocationDetail', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'locations', 'loc-row');
      if (!ok) { test.skip(); return; }
      expect(page.url()).toContain('locations/');
    });

    test(`Content — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'locations', 'loc-row');
      if (!ok) { test.skip(); return; }
      const body = await page.textContent('body');
      expect(body).not.toContain('Access Denied');
    });
  }
});

// ═══ ONBOARDING DETAIL ═══

test.describe('OnboardingDetail', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'onboarding', 'onboarding-row');
      if (!ok) { test.skip(); return; }
      expect(page.url()).toContain('onboarding/');
    });

    test(`Phases render — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'onboarding', 'onboarding-row');
      if (!ok) { test.skip(); return; }
      const body = await page.textContent('body');
      let found = 0;
      for (const p of ['Sales', 'Contract', 'Account', 'Site', 'Vendor', 'Go-Live', 'Go Live']) {
        if (body?.includes(p)) found++;
      }
      console.log(`Phases found: ${found}`);
      expect(found).toBeGreaterThan(0);
    });

    test(`Case fields — run ${run}`, async ({ page }) => {
      const ok = await navigateToFirstDetail(page, 'onboarding', 'onboarding-row');
      if (!ok) { test.skip(); return; }
      const body = await page.textContent('body');
      console.log(`Status: ${body?.includes('Status')}, Customer: ${body?.includes('Customer')}`);
    });
  }

  test('Lifecycle buttons', async ({ page }) => {
    const ok = await navigateToFirstDetail(page, 'onboarding', 'onboarding-row');
    if (!ok) { test.skip(); return; }
    for (const name of ['Close', 'Delete', 'Reopen']) {
      const btn = page.getByRole('button', { name: new RegExp(name, 'i') }).first();
      if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) console.log(`${name} button visible`);
    }
  });
});
