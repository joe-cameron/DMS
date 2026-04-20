import { test, expect, Page } from '@playwright/test';
import * as path from 'path';

test.use({ storageState: './prod-auth-state.json' });

const BASE = 'https://dmms1.powerappsportals.com';
const OUT  = path.resolve(__dirname, '../../../docs/screen-captures');

async function go(page: Page, hash: string) {
  await page.goto(`${BASE}/#/${hash}`);
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });
  await page.waitForTimeout(800);
}

async function snap(page: Page, folder: string, name: string) {
  const dir = path.join(OUT, folder);
  await page.screenshot({ path: path.join(dir, `${name}.png`), fullPage: false });
}

// ═══════════════════════════════════════════════════════
// 0. NAV BAR — CREATE buttons (starting point)
// ═══════════════════════════════════════════════════════
test.describe('Nav Bar — Create Buttons', () => {
  test('capture create section', async ({ page }) => {
    await go(page, 'dashboard');

    // Full dashboard with nav visible
    await snap(page, '00-nav-create', '01-dashboard-with-nav');

    // Highlight each create button by hovering
    const createButtons = [
      { id: 'nav-create-proposal', name: '02-hover-msa' },
      { id: 'nav-create-vendor-agreement', name: '03-hover-vendor-agreement' },
      { id: 'nav-create-workorder', name: '04-hover-work-order' },
      { id: 'nav-create-amendment', name: '05-hover-amendment' },
      { id: 'nav-create-project', name: '06-hover-project' },
    ];

    for (const btn of createButtons) {
      const el = page.getByTestId(btn.id);
      if (await el.isVisible({ timeout: 3000 }).catch(() => false)) {
        await el.hover();
        await page.waitForTimeout(300);
        await snap(page, '00-nav-create', btn.name);
      }
    }
  });
});

// ═══════════════════════════════════════════════════════
// 11. COMPLETED MSA — navigate to MSA list, open first one
// ═══════════════════════════════════════════════════════
test.describe('Completed Documents — MSA', () => {
  test('capture MSA detail with document', async ({ page }) => {
    await go(page, 'msas');
    await page.waitForTimeout(500);

    // MSA list
    await snap(page, '11-completed-msa', '01-msa-list');

    // Click first MSA row
    const firstRow = page.locator('[data-testid="msa-row"]').first()
      .or(page.locator('table tbody tr').first());
    if (await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      // MSA detail — full view
      await snap(page, '11-completed-msa', '02-msa-detail-top');

      // Scroll to documents section
      const docSection = page.locator('text=Documents').first()
        .or(page.locator('text=Document History').first());
      if (await docSection.isVisible({ timeout: 3000 }).catch(() => false)) {
        await docSection.scrollIntoViewIfNeeded();
        await page.waitForTimeout(300);
        await snap(page, '11-completed-msa', '03-msa-documents-section');
      }

      // Scroll to locations/pricing
      const pricingSection = page.locator('text=Pricing').first()
        .or(page.locator('text=Locations').first());
      if (await pricingSection.isVisible({ timeout: 3000 }).catch(() => false)) {
        await pricingSection.scrollIntoViewIfNeeded();
        await page.waitForTimeout(300);
        await snap(page, '11-completed-msa', '04-msa-pricing-locations');
      }

      // Full page scroll
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(200);
      await page.screenshot({
        path: path.join(OUT, '11-completed-msa', '05-msa-detail-fullpage.png'),
        fullPage: true,
      });
    }
  });
});

// ═══════════════════════════════════════════════════════
// 12. COMPLETED CONTRACT — navigate to contract list, open first
// ═══════════════════════════════════════════════════════
test.describe('Completed Documents — Contract', () => {
  test('capture contract detail with document', async ({ page }) => {
    await go(page, 'contracts');
    await page.waitForTimeout(500);

    // Contract list
    await snap(page, '12-completed-contract', '01-contract-list');

    // Click first contract row
    const firstRow = page.locator('[data-testid="contract-row"]').first()
      .or(page.locator('table tbody tr').first());
    if (await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      // Contract detail — top
      await snap(page, '12-completed-contract', '02-contract-detail-top');

      // Scroll to document/compliance section
      const compSection = page.locator('text=Compliance').first()
        .or(page.locator('text=Document').first());
      if (await compSection.isVisible({ timeout: 3000 }).catch(() => false)) {
        await compSection.scrollIntoViewIfNeeded();
        await page.waitForTimeout(300);
        await snap(page, '12-completed-contract', '03-contract-compliance');
      }

      // Look for generated doc link
      const docLink = page.locator('[data-testid="link-view-document"]')
        .or(page.locator('a:has-text("Open in Word")'))
        .or(page.locator('a:has-text("View Document")'));
      if (await docLink.isVisible({ timeout: 3000 }).catch(() => false)) {
        await docLink.scrollIntoViewIfNeeded();
        await page.waitForTimeout(300);
        await snap(page, '12-completed-contract', '04-contract-document-link');
      }

      // Full page
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(200);
      await page.screenshot({
        path: path.join(OUT, '12-completed-contract', '05-contract-detail-fullpage.png'),
        fullPage: true,
      });
    }
  });
});

// ═══════════════════════════════════════════════════════
// 13. COMPLETED ONBOARDING — open a case with steps
// ═══════════════════════════════════════════════════════
test.describe('Completed Documents — Onboarding', () => {
  test('capture onboarding detail with steps', async ({ page }) => {
    await go(page, 'onboarding');
    await page.waitForTimeout(500);

    // Click first onboarding row
    const firstRow = page.locator('[data-testid="onb-row"]').first()
      .or(page.locator('table tbody tr').first());
    if (await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      // Onboarding detail — shows steps checklist
      await snap(page, '13-completed-onboarding', '01-onboarding-detail-top');

      // Full page
      await page.screenshot({
        path: path.join(OUT, '13-completed-onboarding', '02-onboarding-detail-fullpage.png'),
        fullPage: true,
      });
    }
  });
});

// ═══════════════════════════════════════════════════════
// 14. COMPLETED PROJECT — open a project detail
// ═══════════════════════════════════════════════════════
test.describe('Completed Documents — Project', () => {
  test('capture project detail', async ({ page }) => {
    await go(page, 'projects');
    await page.waitForTimeout(500);

    // Click first project row
    const firstRow = page.locator('[data-testid="projects-row"]').first()
      .or(page.locator('table tbody tr').first());
    if (await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      await snap(page, '14-completed-project', '01-project-detail-top');

      await page.screenshot({
        path: path.join(OUT, '14-completed-project', '02-project-detail-fullpage.png'),
        fullPage: true,
      });
    }
  });
});

// ═══════════════════════════════════════════════════════
// 15. CUSTOMER DETAIL — show what a completed customer looks like
// ═══════════════════════════════════════════════════════
test.describe('Completed Documents — Customer', () => {
  test('capture customer detail', async ({ page }) => {
    await go(page, 'customers');
    await page.waitForTimeout(500);

    // Click first customer row
    const firstRow = page.locator('[data-testid="cust-row"]').first()
      .or(page.locator('table tbody tr').first());
    if (await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      await snap(page, '15-completed-customer', '01-customer-detail-top');

      // Scroll to MSAs / Contracts section
      const msaSection = page.locator('text=Service Agreements').first()
        .or(page.locator('text=MSAs').first());
      if (await msaSection.isVisible({ timeout: 3000 }).catch(() => false)) {
        await msaSection.scrollIntoViewIfNeeded();
        await page.waitForTimeout(300);
        await snap(page, '15-completed-customer', '02-customer-msas');
      }

      await page.screenshot({
        path: path.join(OUT, '15-completed-customer', '03-customer-detail-fullpage.png'),
        fullPage: true,
      });
    }
  });
});

// ═══════════════════════════════════════════════════════
// 16. LOCATION DETAIL — show what a completed location looks like
// ═══════════════════════════════════════════════════════
test.describe('Completed Documents — Location', () => {
  test('capture location detail', async ({ page }) => {
    await go(page, 'locations');
    await page.waitForTimeout(500);

    // Click first location row
    const firstRow = page.locator('[data-testid="loc-row"]').first()
      .or(page.locator('table tbody tr').first());
    if (await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      await snap(page, '16-completed-location', '01-location-detail-top');

      await page.screenshot({
        path: path.join(OUT, '16-completed-location', '02-location-detail-fullpage.png'),
        fullPage: true,
      });
    }
  });
});
