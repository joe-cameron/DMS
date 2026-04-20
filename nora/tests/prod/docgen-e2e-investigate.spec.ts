/**
 * Investigation: What happens when Add Item is clicked?
 * Screenshots before and after each click to see row creation behavior.
 */
import { test, expect } from '@playwright/test';

test('Investigate Add Item behavior', async ({ page }) => {
  await page.goto('/#/contracts/new?type=wo');
  await page.waitForTimeout(2000);

  // Pick Bancroft
  await page.locator('[data-testid="cc-customer-search"]').fill('Bancroft');
  await page.waitForTimeout(1500);
  await page.locator('[data-testid^="cc-btn-customer-"]').first().click();
  await page.waitForTimeout(3000);

  // Screenshot: before any items
  await page.screenshot({ path: './test-results/inv-01-before-add.png', fullPage: true });

  // How many rows exist now?
  const rowsBefore = await page.locator('[data-testid^="cc-item-desc-"]').count();
  const costCodesBefore = await page.locator('[data-testid^="cc-costcode-"]').count();
  console.log(`BEFORE ADD: desc inputs=${rowsBefore}, costcode selects=${costCodesBefore}`);

  // Click Add Item
  await page.locator('[data-testid="cc-btn-add-item"]').click();
  await page.waitForTimeout(1000);

  // Screenshot: after Add Item
  await page.screenshot({ path: './test-results/inv-02-after-add-item.png', fullPage: true });

  const rowsAfterAdd = await page.locator('[data-testid^="cc-item-desc-"]').count();
  const costCodesAfterAdd = await page.locator('[data-testid^="cc-costcode-"]').count();
  console.log(`AFTER ADD ITEM: desc inputs=${rowsAfterAdd}, costcode selects=${costCodesAfterAdd}`);

  // Fill row 0
  await page.locator('[data-testid="cc-costcode-0"]').selectOption({ index: 1 }).catch(() => console.log('costcode-0 select failed'));
  await page.locator('[data-testid="cc-item-desc-0"]').fill('TEST-ITEM-1');
  await page.locator('[data-testid="cc-item-amount-0"]').fill('1000');
  await page.waitForTimeout(500);

  // Screenshot: after filling row 0
  await page.screenshot({ path: './test-results/inv-03-after-fill-row0.png', fullPage: true });

  // Check if row 1 already exists
  const row1Exists = await page.locator('[data-testid="cc-item-desc-1"]').isVisible({ timeout: 1000 }).catch(() => false);
  console.log(`ROW 1 EXISTS AFTER FILLING ROW 0: ${row1Exists}`);

  // Click Add Another
  await page.locator('[data-testid="cc-btn-add-another"]').click();
  await page.waitForTimeout(1000);

  // Screenshot: after Add Another
  await page.screenshot({ path: './test-results/inv-04-after-add-another.png', fullPage: true });

  const rowsAfterAnother = await page.locator('[data-testid^="cc-item-desc-"]').count();
  console.log(`AFTER ADD ANOTHER: desc inputs=${rowsAfterAnother}`);

  // Check all visible rows
  for (let i = 0; i < 5; i++) {
    const visible = await page.locator(`[data-testid="cc-item-desc-${i}"]`).isVisible({ timeout: 500 }).catch(() => false);
    if (visible) {
      const val = await page.locator(`[data-testid="cc-item-desc-${i}"]`).inputValue().catch(() => '');
      console.log(`  Row ${i}: visible, value="${val}"`);
    }
  }
});
