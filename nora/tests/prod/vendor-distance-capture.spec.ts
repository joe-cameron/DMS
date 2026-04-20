import { test, expect } from '@playwright/test';
test.use({ storageState: './prod-auth-state.json' });

test('Capture vendor distance search from customer location', async ({ page }) => {
  // Navigate to customer detail with vendors tab
  await page.goto('https://dmms1.powerappsportals.com/#/customers');
  await page.waitForLoadState('networkidle');
  const firstRow = page.locator('table tbody tr').first();
  await firstRow.waitFor({ timeout: 15000 });
  await page.waitForTimeout(1000);
  await page.screenshot({ path: './test-results/vendor-01-customer-list.png', fullPage: true });
  
  await firstRow.click();
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  await page.screenshot({ path: './test-results/vendor-02-customer-detail.png', fullPage: true });

  // Click Vendors tab
  const vendorsTab = page.getByTestId('custd-tab-vendors');
  if (await vendorsTab.isVisible({ timeout: 5000 }).catch(() => false)) {
    await vendorsTab.click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: './test-results/vendor-03-vendors-tab.png', fullPage: true });
    console.log('Vendors tab captured');
  }

  // Look for Add Vendor / distance search button
  const addBtn = page.getByTestId('btn-add-customer-vendor');
  if (await addBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await addBtn.click();
    await page.waitForTimeout(1500);
    await page.screenshot({ path: './test-results/vendor-04-slideout-open.png', fullPage: true });
    console.log('Slideout panel captured');
  }

  // Also capture from Vendors nav
  await page.goto('https://dmms1.powerappsportals.com/#/vendors');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: './test-results/vendor-05-vendor-search.png', fullPage: true });
  console.log('Vendor search page captured');

  // Check for distance/trade search controls
  const distanceInput = page.locator('input[placeholder*="distance"], input[placeholder*="miles"], input[placeholder*="radius"]').first();
  if (await distanceInput.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.screenshot({ path: './test-results/vendor-06-distance-search.png', fullPage: true });
    console.log('Distance search captured');
  }
});
