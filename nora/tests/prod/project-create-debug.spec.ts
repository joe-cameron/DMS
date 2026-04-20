import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

test('Create project and capture errors', async ({ page }) => {
  const consoleErrors: string[] = [];
  const networkErrors: string[] = [];
  const allToasts: string[] = [];

  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', e => { consoleErrors.push(`PAGE: ${e.message}`); });
  page.on('requestfailed', r => { networkErrors.push(`REQFAIL: ${r.url().substring(0, 120)} ${r.failure()?.errorText}`); });
  page.on('response', r => {
    if (r.status() >= 400) {
      r.text().then(body => {
        networkErrors.push(`${r.status()} ${r.url().substring(0, 120)}\n  Body: ${body.substring(0, 300)}`);
      }).catch(() => {
        networkErrors.push(`${r.status()} ${r.url().substring(0, 120)}`);
      });
    }
  });

  await page.goto('https://dmms1.powerappsportals.com/#/projects?new=1');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });

  // Fill the form
  const nameInput = page.getByTestId('projects-new-name');
  await expect(nameInput).toBeVisible({ timeout: 10000 });
  await nameInput.fill('E2E Test Project - DELETE ME');

  // Select a property from dropdown
  const propSelect = page.getByTestId('projects-new-property');
  if (await propSelect.isVisible()) {
    const opts = await propSelect.locator('option').allTextContents();
    console.log('Property options:', opts.slice(0, 5));
    // Use index to avoid multiline label issues
    const optionElements = propSelect.locator('option');
    const count = await optionElements.count();
    if (count > 1) {
      const val = await optionElements.nth(1).getAttribute('value');
      if (val) {
        await propSelect.selectOption(val);
        console.log('Selected property value:', val);
      }
    }
  }

  // Select a trade
  const hvacChip = page.locator('text=HVAC').first();
  if (await hvacChip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await hvacChip.click();
    console.log('Selected trade: HVAC');
  }

  await page.screenshot({ path: 'C:/DCFG/nora/test-results/project-form-filled.png', fullPage: true });

  // Click Create Project
  const createBtn = page.locator('button:has-text("Create Project")').first();
  if (await createBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.log('Clicking Create Project...');
    await createBtn.click();

    // Wait for response
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Capture toasts
    const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').allTextContents();
    for (const t of toasts) {
      if (t.trim()) allToasts.push(t.trim());
    }
  }

  console.log('\n=== RESULTS ===');
  console.log('Console errors:', consoleErrors.length);
  for (const e of consoleErrors) console.log('  ', e.substring(0, 200));
  console.log('Network errors:', networkErrors.length);
  for (const e of networkErrors) console.log('  ', e);
  console.log('Toasts:', allToasts);

  await page.screenshot({ path: 'C:/DCFG/nora/test-results/project-after-create.png', fullPage: true });
});
