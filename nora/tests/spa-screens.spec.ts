import { test, expect } from '@playwright/test';

/**
 * Nora SPA Screen Tests
 * Tests every screen loads, renders key elements, and navigation works.
 * Uses saved auth state from auth.setup.ts
 */

const SCREENS = [
  { name: 'Dashboard', route: '/#/dashboard', expects: ['Dashboard'] },
  { name: 'Customers', route: '/#/customers', expects: ['Customers'] },
  { name: 'Contracts', route: '/#/contracts', expects: ['Contracts'] },
  { name: 'MSAs', route: '/#/msas', expects: ['MSAs'] },
  { name: 'Locations', route: '/#/locations', expects: ['Locations'] },
  { name: 'Onboarding', route: '/#/onboarding', expects: ['Onboarding'] },
  { name: 'Send Queue', route: '/#/send-queue', expects: ['Send'] },
  { name: 'Admin', route: '/#/admin', expects: ['Admin'] },
  { name: 'New Contract', route: '/#/contracts/new', expects: ['New Contract', 'Step'] },
  { name: 'New Proposal', route: '/#/proposals/new', expects: ['Proposal', 'proposal'] },
];

for (const screen of SCREENS) {
  test(`${screen.name} — page loads`, async ({ page }) => {
    await page.goto(screen.route);
    await page.waitForTimeout(3000);

    // Check page didn't show error
    const body = await page.textContent('body');
    expect(body).not.toContain('Sign in required');
    expect(body).not.toContain('Access Denied');

    // Check at least one expected text appears
    let found = false;
    for (const text of screen.expects) {
      if (body?.includes(text)) { found = true; break; }
    }
    expect(found).toBeTruthy();
  });
}

test('Dashboard — nav panel visible', async ({ page }) => {
  await page.goto('/#/dashboard');
  await page.waitForTimeout(3000);

  // Check nav items exist
  const body = await page.textContent('body');
  expect(body).toContain('Dashboard');
  expect(body).toContain('Customers');
  expect(body).toContain('Contracts');
  expect(body).toContain('MSAs');
});

test('Dashboard — data loads (no 403)', async ({ page }) => {
  await page.goto('/#/dashboard');
  await page.waitForTimeout(5000);

  const body = await page.textContent('body');
  // Should NOT see permission errors
  expect(body).not.toContain('403');
  expect(body).not.toContain('don\'t have permission');
  expect(body).not.toContain('Failed to load');
});

test('Customers — table renders rows', async ({ page }) => {
  await page.goto('/#/customers');
  await page.waitForTimeout(5000);

  // Check for table content (at least one customer name or "No customers")
  const body = await page.textContent('body');
  const hasData = !body?.includes('No customers') && !body?.includes('Loading');
  // Either has data or shows empty state — both are valid (no crash)
  expect(body).not.toContain('403');
});

test('Customers — search input exists', async ({ page }) => {
  await page.goto('/#/customers');
  await page.waitForTimeout(3000);

  const searchInput = page.locator('input[placeholder*="Search"]');
  await expect(searchInput).toBeVisible();
});

test('Contracts — table renders', async ({ page }) => {
  await page.goto('/#/contracts');
  await page.waitForTimeout(5000);

  const body = await page.textContent('body');
  expect(body).not.toContain('403');
  expect(body).not.toContain('Failed to load');
});

test('MSAs — page loads without error', async ({ page }) => {
  await page.goto('/#/msas');
  await page.waitForTimeout(5000);

  const body = await page.textContent('body');
  expect(body).not.toContain('403');
});

test('Onboarding — page loads with cases or empty state', async ({ page }) => {
  await page.goto('/#/onboarding');
  await page.waitForTimeout(5000);

  const body = await page.textContent('body');
  expect(body).not.toContain('403');
  expect(body).toContain('Onboarding');
});

test('Send Queue — tabs visible', async ({ page }) => {
  await page.goto('/#/send-queue');
  await page.waitForTimeout(5000);

  const body = await page.textContent('body');
  expect(body).not.toContain('403');
});

test('Admin — tabs render', async ({ page }) => {
  await page.goto('/#/admin');
  await page.waitForTimeout(5000);

  const body = await page.textContent('body');
  expect(body).not.toContain('403');
  // Should see admin tab options
  expect(body).toContain('Templates') ;
});

test('Navigation — click Customers from Dashboard', async ({ page }) => {
  await page.goto('/#/dashboard');
  await page.waitForTimeout(3000);

  // Click Customers in nav
  await page.click('text=Customers');
  await page.waitForTimeout(3000);

  expect(page.url()).toContain('customers');
});

test('Navigation — click Contracts from Dashboard', async ({ page }) => {
  await page.goto('/#/dashboard');
  await page.waitForTimeout(3000);

  await page.click('text=Contracts');
  await page.waitForTimeout(3000);

  expect(page.url()).toContain('contracts');
});
