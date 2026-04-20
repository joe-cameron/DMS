import { test, expect, Page } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

const BASE = 'https://dmms1.powerappsportals.com';

async function goTo(page: Page, hash: string) {
  await page.goto(`${BASE}/#/${hash}`);
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });
}

// Capture toasts helper
async function captureToasts(page: Page): Promise<string[]> {
  const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').allTextContents();
  if (toasts.length) console.log('TOASTS:', toasts.join(' | '));
  return toasts;
}

// ═══ NAVIGATION ═══

test.describe('Navigation links', () => {
  const createLinks = [
    { id: 'nav-create-proposal', expect: 'proposals/new' },
    { id: 'nav-create-workorder', expect: 'contracts/new' },
    { id: 'nav-create-amendment', expect: 'contracts/new' },
    { id: 'nav-create-vendor-agreement', expect: 'contracts/new' },
    { id: 'nav-create-project', expect: 'projects' },
  ];

  for (const link of createLinks) {
    for (let run = 1; run <= 3; run++) {
      test(`${link.id} navigates correctly — run ${run}`, async ({ page }) => {
        await goTo(page, 'dashboard');
        const el = page.getByTestId(link.id);
        await expect(el).toBeVisible();
        // Capture console errors
        const errors: string[] = [];
        page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
        await el.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain(link.expect);
        await captureToasts(page);
        if (errors.length) console.log(`CONSOLE ERRORS on ${link.id}:`, errors);
      });
    }
  }
});

test.describe('Nav group toggles', () => {
  for (const group of ['sales', 'facilities', 'projects', 'administration', 'system']) {
    for (let run = 1; run <= 3; run++) {
      test(`toggle ${group} — run ${run}`, async ({ page }) => {
        await goTo(page, 'dashboard');
        const toggle = page.getByTestId(`nav-group-toggle-${group}`);
        await expect(toggle).toBeVisible();
        await toggle.click();
        await toggle.click();
        await expect(toggle).toBeVisible();
      });
    }
  }
});

test.describe('Nav utility panels', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Directory panel — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await page.getByTestId('nav-directory').click();
      await page.waitForLoadState('networkidle');
      await page.keyboard.press('Escape');
    });

    test(`Nora panel — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await page.getByTestId('nav-nora').click();
      await page.waitForLoadState('networkidle');
      await page.keyboard.press('Escape');
    });

    test(`Help link — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await expect(page.getByTestId('nav-help')).toBeVisible();
    });

    test(`Minimap link — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await expect(page.getByTestId('nav-minimap')).toBeVisible();
    });
  }
});

// ═══ SALES DASHBOARD ═══

test.describe('SalesDashboard', () => {
  for (let run = 1; run <= 3; run++) {
    test(`KPI tiles render — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await expect(page.getByTestId('dash-kpi-active-contracts')).toBeVisible();
      await expect(page.getByTestId('dash-kpi-pending-signatures')).toBeVisible();
      await expect(page.getByTestId('dash-kpi-contracts-this-month')).toBeVisible();
    });

    test(`KPI active contracts click — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await page.getByTestId('dash-kpi-active-contracts').click();
      await page.waitForLoadState('networkidle');
      expect(page.url()).toContain('contracts');
    });

    test(`KPI pending sigs click — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await page.getByTestId('dash-kpi-pending-signatures').click();
      await page.waitForLoadState('networkidle');
      expect(page.url()).toContain('send-queue');
    });

    test(`Pipeline renders — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      const segs = page.locator('[data-testid^="dash-pipeline-"]');
      expect(await segs.count()).toBeGreaterThan(0);
    });

    test(`Onboarding section — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await expect(page.getByTestId('dash-onboarding')).toBeVisible();
      expect(await page.getByTestId('dash-onboarding-item').count()).toBeGreaterThan(0);
    });

    test(`Prospects section — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await expect(page.getByTestId('dash-prospects')).toBeVisible();
    });

    test(`Onboarding item click navigates — run ${run}`, async ({ page }) => {
      await goTo(page, 'dashboard');
      await page.getByTestId('dash-onboarding-item').first().click();
      await page.waitForLoadState('networkidle');
      expect(page.url()).toContain('onboarding');
    });
  }
});

// ═══ CUSTOMER LIST ═══

test.describe('CustomerList', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads with data — run ${run}`, async ({ page }) => {
      await goTo(page, 'customers');
      await expect(page.getByTestId('cust-search')).toBeVisible();
      await expect(page.getByTestId('cust-btn-new')).toBeVisible();
    });

    test(`Search filters — run ${run}`, async ({ page }) => {
      await goTo(page, 'customers');
      const search = page.getByTestId('cust-search');
      await search.fill('Bancroft');
      await page.waitForFunction(() => true, {}, { timeout: 1000 }).catch(() => {});
      const body = await page.textContent('body');
      console.log(`Search "Bancroft": found=${body?.includes('Bancroft')}`);
      await search.fill('');
    });

    test(`Show inactive toggle — run ${run}`, async ({ page }) => {
      await goTo(page, 'customers');
      const cb = page.getByTestId('cust-show-inactive');
      await cb.check();
      await page.waitForLoadState('networkidle');
      await cb.uncheck();
    });

    test(`New customer panel open/close — run ${run}`, async ({ page }) => {
      await goTo(page, 'customers');
      await page.getByTestId('cust-btn-new').click();
      await expect(page.getByTestId('cust-new-dcfg_name')).toBeVisible({ timeout: 5000 });
      const cancel = page.getByTestId('cust-btn-cancel');
      if (await cancel.isVisible()) await cancel.click();
      else await page.keyboard.press('Escape');
    });

    test(`Customer row click to detail — run ${run}`, async ({ page }) => {
      await goTo(page, 'customers');
      const row = page.getByTestId('cust-row').first();
      if (await row.isVisible({ timeout: 10000 }).catch(() => false)) {
        await row.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain('customers/');
      }
    });
  }
});

// ═══ CONTRACT LIST ═══

test.describe('ContractList', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'contracts');
      const body = await page.textContent('body');
      expect(body).not.toContain('Access Denied');
    });

    test(`Search — run ${run}`, async ({ page }) => {
      await goTo(page, 'contracts');
      const search = page.getByTestId('contracts-search');
      if (await search.isVisible({ timeout: 5000 }).catch(() => false)) {
        await search.fill('Bancroft');
        await search.fill('');
      }
    });

    test(`New contract button — run ${run}`, async ({ page }) => {
      await goTo(page, 'contracts');
      const btn = page.getByTestId('contracts-btn-new');
      if (await btn.isVisible({ timeout: 5000 }).catch(() => false)) {
        await btn.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain('contracts/new');
      }
    });

    test(`Contract row click — run ${run}`, async ({ page }) => {
      await goTo(page, 'contracts');
      const row = page.getByTestId('contracts-row').first();
      if (await row.isVisible({ timeout: 10000 }).catch(() => false)) {
        await row.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain('contracts/');
      }
    });
  }
});

// ═══ MSA LIST ═══

test.describe('MsaList', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'msas');
      const body = await page.textContent('body');
      expect(body).not.toContain('Access Denied');
    });

    test(`Search — run ${run}`, async ({ page }) => {
      await goTo(page, 'msas');
      const search = page.getByTestId('msas-search');
      if (await search.isVisible({ timeout: 5000 }).catch(() => false)) {
        await search.fill('Penn');
        await search.fill('');
      }
    });

    test(`MSA row click — run ${run}`, async ({ page }) => {
      await goTo(page, 'msas');
      const row = page.getByTestId('msas-row').first();
      if (await row.isVisible({ timeout: 10000 }).catch(() => false)) {
        await row.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain('msas/');
      }
    });
  }
});

// ═══ LOCATIONS ═══

test.describe('Locations', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'locations');
      const body = await page.textContent('body');
      expect(body).not.toContain('Access Denied');
    });

    test(`Search — run ${run}`, async ({ page }) => {
      await goTo(page, 'locations');
      const search = page.getByTestId('loc-search');
      if (await search.isVisible({ timeout: 5000 }).catch(() => false)) {
        await search.fill('Main');
        await search.fill('');
      }
    });

    test(`Customer filter dropdown — run ${run}`, async ({ page }) => {
      await goTo(page, 'locations');
      const dd = page.getByTestId('loc-filter-customer');
      if (await dd.isVisible({ timeout: 5000 }).catch(() => false)) {
        await dd.click();
        // Try native select option first, then custom dropdown
        const opts = page.locator('option').filter({ hasNotText: /All|Select/i });
        if (await opts.count() > 0) {
          await opts.first().click();
        } else {
          await page.keyboard.press('Escape');
        }
        await page.waitForLoadState('networkidle');
      }
    });

    test(`New location panel — run ${run}`, async ({ page }) => {
      await goTo(page, 'locations');
      const btn = page.getByTestId('loc-btn-new');
      if (await btn.isVisible({ timeout: 5000 }).catch(() => false)) {
        await btn.click();
        await page.waitForLoadState('networkidle');
        await page.keyboard.press('Escape');
      }
    });

    test(`Location row click — run ${run}`, async ({ page }) => {
      await goTo(page, 'locations');
      const row = page.getByTestId('loc-row').first();
      if (await row.isVisible({ timeout: 10000 }).catch(() => false)) {
        await row.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain('locations/');
      }
    });
  }
});

// ═══ ONBOARDING ═══

test.describe('Onboarding', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'onboarding');
      const body = await page.textContent('body');
      expect(body).toContain('Onboarding');
    });

    test(`Status filter dropdown — run ${run}`, async ({ page }) => {
      await goTo(page, 'onboarding');
      const dd = page.getByTestId('onboarding-filter-status');
      if (await dd.isVisible({ timeout: 5000 }).catch(() => false)) {
        await dd.click();
        const opts = page.locator('option').filter({ hasText: /In Progress/i });
        if (await opts.count() > 0) await opts.first().click();
        else await page.keyboard.press('Escape');
        await page.waitForLoadState('networkidle');
      }
    });

    test(`Show deleted toggle — run ${run}`, async ({ page }) => {
      await goTo(page, 'onboarding');
      const cb = page.getByTestId('onboarding-show-deleted');
      if (await cb.isVisible({ timeout: 5000 }).catch(() => false)) {
        await cb.check();
        await page.waitForLoadState('networkidle');
        await cb.uncheck();
      }
    });

    test(`Onboarding row click — run ${run}`, async ({ page }) => {
      await goTo(page, 'onboarding');
      const row = page.getByTestId('onboarding-row').first();
      if (await row.isVisible({ timeout: 10000 }).catch(() => false)) {
        await row.click();
        await page.waitForLoadState('networkidle');
        expect(page.url()).toContain('onboarding/');
      }
    });
  }
});

// ═══ SEND QUEUE ═══

test.describe('SendQueue', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'send-queue');
      const body = await page.textContent('body');
      expect(body).not.toContain('Access Denied');
    });

    test(`Tab switching — run ${run}`, async ({ page }) => {
      await goTo(page, 'send-queue');
      for (const tid of ['send-queue-tab-pending', 'send-queue-tab-approved', 'send-queue-tab-returned']) {
        const tab = page.getByTestId(tid);
        if (await tab.isVisible({ timeout: 3000 }).catch(() => false)) {
          await tab.click();
          await page.waitForLoadState('networkidle');
        }
      }
    });

    test(`Ctrl+K search overlay — run ${run}`, async ({ page }) => {
      await goTo(page, 'send-queue');
      await page.keyboard.press('Control+k');
      // Check for overlay
      await page.waitForLoadState('networkidle');
      await page.keyboard.press('Escape');
    });
  }
});

// ═══ ADMIN ═══

test.describe('Admin', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'admin');
      const body = await page.textContent('body');
      console.log(`Admin: Templates=${body?.includes('Templates')}`);
    });
  }

  const cards = [
    'customer-config', 'location-types', 'cost-codes', 'appliance-types',
    'vendors', 'document-templates', 'template-management', 'onboarding-steps',
  ];
  for (const card of cards) {
    test(`Admin card ${card} — click`, async ({ page }) => {
      await goTo(page, 'admin');
      const el = page.getByTestId(`admin-card-${card}`);
      if (await el.isVisible({ timeout: 5000 }).catch(() => false)) {
        await el.click();
        await page.waitForLoadState('networkidle');
      } else {
        console.log(`MISSING: admin-card-${card}`);
      }
    });
  }
});

// ═══ COMPLIANCE ═══

test.describe('CompliancePanel', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'compliance');
      await page.waitForLoadState('networkidle');
    });
  }
});

// ═══ NEW PROJECT BUTTON — BUG INVESTIGATION ═══

test.describe('New Project button bug', () => {
  test('Click and capture all errors', async ({ page }) => {
    const errors: string[] = [];
    const requests: string[] = [];
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('response', r => { if (r.status() >= 400) requests.push(`${r.status()} ${r.url()}`); });

    await goTo(page, 'dashboard');
    await page.getByTestId('nav-create-project').click();
    await page.waitForLoadState('networkidle');
    await page.waitForFunction(() => true, {}, { timeout: 3000 }).catch(() => {});

    const toasts = await captureToasts(page);
    await page.screenshot({ path: 'C:/DCFG/nora/test-results/new-project-error.png', fullPage: true });

    console.log('=== NEW PROJECT BUG REPORT ===');
    console.log('URL:', page.url());
    console.log('Toasts:', toasts);
    console.log('Console errors:', errors);
    console.log('Failed requests:', requests);
    console.log('Page text (first 500):', (await page.textContent('body'))?.substring(0, 500));
  });
});
