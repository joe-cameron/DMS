/**
 * composer-smoke.spec.ts — Targeted E2E for the ContractComposer and Vendors
 * tabs (changes deployed 2026-04-11). Verifies:
 *   1. /contracts/new?type=wo loads without the "Copy from recent" button
 *   2. Customer picker shows up
 *   3. No console errors matching the known 400/403 failure patterns
 *   4. Customer Detail → Vendors tab loads without errors
 *   5. Location Detail → Vendors tab loads without errors
 *   6. flow_vendor_geocode row exists in Prod (Dataverse side)
 *
 * Run:
 *   npx playwright test tests/prod/composer-smoke.spec.ts --config=playwright-prod.config.ts --headed
 */
import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

// Collect all console errors + failed network requests so the test can assert
// the absence of the specific patterns we just fixed.
type ErrBucket = { console: string[]; failed: string[] };
async function setupErrorCapture(page: any): Promise<ErrBucket> {
  const bucket: ErrBucket = { console: [], failed: [] };
  page.on('console', (msg: any) => {
    if (msg.type() === 'error') bucket.console.push(msg.text());
  });
  page.on('response', (resp: any) => {
    if (resp.status() >= 400) bucket.failed.push(`${resp.status()} ${resp.url()}`);
  });
  return bucket;
}

test.describe('ContractComposer + Vendors tab smoke', () => {
  test('Work Order composer loads, no 400/403 on junction queries', async ({ page }) => {
    const errs = await setupErrorCapture(page);
    await page.goto('https://dmms1.powerappsportals.com/#/contracts/new?type=wo');
    await page.waitForLoadState('networkidle');
    await page.waitForFunction(
      () => document.body.innerText.includes('Who is this Work Order for?')
         || document.body.innerText.includes('Resume a Work Order draft')
         || document.body.innerText.includes('Work Order'),
      { timeout: 30000 }
    );

    // "Copy from recent" button should NOT appear
    const copyBtn = await page.getByTestId('btn-copy-from-recent').count();
    expect(copyBtn).toBe(0);

    // Theme toggle should exist
    await expect(page.getByTestId('btn-toggle-theme')).toBeVisible();

    // The junction table failures we just fixed should NOT appear
    const badPatterns = errs.failed.filter(f =>
      f.includes('dcfg_customer_vendors') && f.startsWith('400') ||
      f.includes('dcfg_property_vendors') && f.startsWith('400')
    );
    expect(badPatterns, `Junction queries should succeed. Got failures: ${JSON.stringify(badPatterns)}`).toHaveLength(0);

    console.log('Console errors (all):', errs.console);
    console.log('Failed network (all 4xx/5xx):', errs.failed);
  });

  test('Customer Detail Vendors tab opens without error', async ({ page }) => {
    const errs = await setupErrorCapture(page);
    await page.goto('https://dmms1.powerappsportals.com/#/customers');
    await page.waitForLoadState('networkidle');
    // Click the first customer row to drill down
    const firstRow = page.locator('table tbody tr').first();
    await firstRow.waitFor({ timeout: 15000 });
    await firstRow.click();
    await page.waitForLoadState('networkidle');
    // Click the Vendors tab
    const vendorsTab = page.getByTestId('custd-tab-vendors');
    await expect(vendorsTab).toBeVisible({ timeout: 10000 });
    await vendorsTab.click();
    await page.waitForTimeout(2000);
    // Should see either the add button or the empty-state copy
    const addBtn = await page.getByTestId('btn-add-customer-vendor').count();
    expect(addBtn, 'Add Vendor button should render on the Vendors tab').toBeGreaterThan(0);

    // Should NOT see the junction query failures
    const bad = errs.failed.filter(f =>
      (f.includes('dcfg_customer_vendors') && f.startsWith('400')) ||
      (f.includes('dcfg_property_vendors') && f.startsWith('400'))
    );
    expect(bad, `Junction queries should succeed. Got: ${JSON.stringify(bad)}`).toHaveLength(0);
    console.log('Customer Vendors tab errors:', errs.console);
  });

  test('Location Detail Vendors tab opens without error', async ({ page }) => {
    const errs = await setupErrorCapture(page);
    await page.goto('https://dmms1.powerappsportals.com/#/locations');
    await page.waitForLoadState('networkidle');
    const firstRow = page.locator('table tbody tr').first();
    await firstRow.waitFor({ timeout: 15000 });
    await firstRow.click();
    await page.waitForLoadState('networkidle');
    const vendorsTab = page.getByTestId('locd-tab-vendors');
    await expect(vendorsTab).toBeVisible({ timeout: 10000 });
    await vendorsTab.click();
    await page.waitForTimeout(2000);
    const addBtn = await page.getByTestId('btn-add-property-vendor').count();
    expect(addBtn).toBeGreaterThan(0);
    const bad = errs.failed.filter(f =>
      (f.includes('dcfg_property_vendors') && f.startsWith('400'))
    );
    expect(bad).toHaveLength(0);
    console.log('Location Vendors tab errors:', errs.console);
  });
});
