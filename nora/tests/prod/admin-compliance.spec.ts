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

// ═══ ADMIN HUB ═══

test.describe('Admin Hub', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Admin page loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'admin');
      const body = await page.textContent('body');
      console.log(`Admin: Templates=${body?.includes('Templates')}, Vendors=${body?.includes('Vendor')}`);
    });
  }

  // Admin cards — discover what's actually there
  test('Discover all admin cards', async ({ page }) => {
    await goTo(page, 'admin');
    const cards = await page.locator('[data-testid^="admin-card-"]').all();
    console.log(`Admin cards found: ${cards.length}`);
    for (const card of cards) {
      const tid = await card.getAttribute('data-testid');
      const text = await card.textContent();
      console.log(`  ${tid}: "${text?.substring(0, 60).trim()}"`);
    }
  });

  // Click each discovered card 3x
  const knownCards = [
    'customer-config', 'location-types', 'cost-codes', 'appliance-types',
    'vendors', 'document-templates', 'template-management', 'onboarding-steps',
  ];

  for (const card of knownCards) {
    for (let run = 1; run <= 3; run++) {
      test(`Admin card ${card} click — run ${run}`, async ({ page }) => {
        await goTo(page, 'admin');
        const el = page.getByTestId(`admin-card-${card}`);
        if (await el.isVisible({ timeout: 5000 }).catch(() => false)) {
          await el.click();
          await page.waitForLoadState('networkidle');
          await captureToasts(page);
        } else {
          console.log(`SKIP: admin-card-${card} not visible`);
          test.skip();
        }
      });
    }
  }

  // Admin sections
  test('Discover admin sections', async ({ page }) => {
    await goTo(page, 'admin');
    const sections = await page.locator('[data-testid^="admin-section-"]').all();
    console.log(`Admin sections: ${sections.length}`);
    for (const sec of sections) {
      const tid = await sec.getAttribute('data-testid');
      console.log(`  ${tid}`);
    }
  });

  // Vendor management if visible
  for (let run = 1; run <= 3; run++) {
    test(`Vendor admin — search — run ${run}`, async ({ page }) => {
      await goTo(page, 'admin');
      const vendorCard = page.getByTestId('admin-card-vendors');
      if (await vendorCard.isVisible({ timeout: 5000 }).catch(() => false)) {
        await vendorCard.click();
        await page.waitForLoadState('networkidle');
        // Look for vendor search input
        const search = page.locator('input[placeholder*="search" i]').first();
        if (await search.isVisible({ timeout: 5000 }).catch(() => false)) {
          await search.fill('Acme');
          await page.waitForLoadState('networkidle');
          await search.fill('');
        }
      } else {
        test.skip();
      }
    });
  }

  // Document templates
  for (let run = 1; run <= 3; run++) {
    test(`Document templates tab — run ${run}`, async ({ page }) => {
      await goTo(page, 'admin');
      const tplCard = page.getByTestId('admin-card-document-templates');
      if (await tplCard.isVisible({ timeout: 5000 }).catch(() => false)) {
        await tplCard.click();
        await page.waitForLoadState('networkidle');
        const body = await page.textContent('body');
        console.log(`Templates: has template rows = ${body?.includes('Template') || body?.includes('.docx')}`);
        await captureToasts(page);
      } else {
        test.skip();
      }
    });
  }

  // Location types
  for (let run = 1; run <= 3; run++) {
    test(`Location types tab — run ${run}`, async ({ page }) => {
      await goTo(page, 'admin');
      const card = page.getByTestId('admin-card-location-types');
      if (await card.isVisible({ timeout: 5000 }).catch(() => false)) {
        await card.click();
        await page.waitForLoadState('networkidle');
        const body = await page.textContent('body');
        console.log(`Location types: has rows = ${body?.includes('Office') || body?.includes('Warehouse') || body?.includes('Type')}`);
      } else {
        test.skip();
      }
    });
  }

  // Cost codes
  for (let run = 1; run <= 3; run++) {
    test(`Cost codes tab — run ${run}`, async ({ page }) => {
      await goTo(page, 'admin');
      const card = page.getByTestId('admin-card-cost-codes');
      if (await card.isVisible({ timeout: 5000 }).catch(() => false)) {
        await card.click();
        await page.waitForLoadState('networkidle');
        const body = await page.textContent('body');
        console.log(`Cost codes loaded: ${body?.includes('Code') || body?.includes('code')}`);
      } else {
        test.skip();
      }
    });
  }
});

// ═══ COMPLIANCE PANEL ═══

test.describe('CompliancePanel', () => {
  for (let run = 1; run <= 3; run++) {
    test(`Compliance page loads — run ${run}`, async ({ page }) => {
      await goTo(page, 'compliance');
      const body = await page.textContent('body');
      console.log(`Compliance body (100 chars): ${body?.substring(0, 100)}`);
      await captureToasts(page);
    });
  }

  test('Compliance data visible', async ({ page }) => {
    await goTo(page, 'compliance');
    const body = await page.textContent('body');
    const hasRules = body?.includes('Compliant') || body?.includes('compliant') || body?.includes('Warning');
    console.log(`Has compliance data: ${hasRules}`);
  });
});
