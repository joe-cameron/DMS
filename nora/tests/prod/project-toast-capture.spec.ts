import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

test('Capture project toast errors live', async ({ page }) => {
  const allToasts: string[] = [];
  const consoleErrors: string[] = [];
  const networkErrors: string[] = [];

  page.on('console', m => {
    if (m.type() === 'error') consoleErrors.push(m.text());
  });
  page.on('pageerror', e => {
    consoleErrors.push(`PAGE ERROR: ${e.message}`);
  });
  page.on('response', r => {
    if (r.status() >= 400) networkErrors.push(`${r.status()} ${r.url().substring(0, 150)}`);
  });

  await page.goto('https://dmms1.powerappsportals.com/#/projects?new=1');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });

  // Poll for toasts every 500ms for 60 seconds
  for (let i = 0; i < 120; i++) {
    const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"], [data-testid*="toast"]').allTextContents();
    for (const t of toasts) {
      if (t.trim() && !allToasts.includes(t.trim())) {
        allToasts.push(t.trim());
        console.log(`TOAST [${new Date().toISOString()}]: ${t.trim()}`);
      }
    }

    // Also check for any new console errors
    if (consoleErrors.length > 0) {
      for (const e of consoleErrors) console.log(`CONSOLE ERROR: ${e}`);
      consoleErrors.length = 0;
    }
    if (networkErrors.length > 0) {
      for (const e of networkErrors) console.log(`NETWORK ERROR: ${e}`);
      networkErrors.length = 0;
    }

    await page.waitForTimeout(500);
  }

  console.log('\n=== FINAL TOAST SUMMARY ===');
  for (const t of allToasts) console.log(`  ${t}`);
  console.log(`Total unique toasts: ${allToasts.length}`);

  await page.screenshot({ path: 'C:/DCFG/nora/test-results/project-toast-final.png', fullPage: true });
});
