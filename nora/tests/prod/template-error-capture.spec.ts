import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

test('Watch template screen for all errors', async ({ page }) => {
  const allErrors: string[] = [];

  page.on('console', m => {
    if (m.type() === 'error') allErrors.push(`[console.error] ${m.text()}`);
  });
  page.on('pageerror', e => {
    allErrors.push(`[pageerror] ${e.message}\n${e.stack}`);
  });
  page.on('response', r => {
    if (r.status() >= 400) {
      r.text().then(body => {
        allErrors.push(`[HTTP ${r.status()}] ${r.url()}\n${body.substring(0, 500)}`);
      }).catch(() => {
        allErrors.push(`[HTTP ${r.status()}] ${r.url()}`);
      });
    }
  });
  page.on('requestfailed', r => {
    allErrors.push(`[REQFAIL] ${r.url()} ${r.failure()?.errorText}`);
  });

  // Navigate to admin > template management
  await page.goto('https://dmms1.powerappsportals.com/#/admin');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });

  // Click Template Management card
  const tplCard = page.getByTestId('admin-card-template-management');
  if (await tplCard.isVisible({ timeout: 5000 }).catch(() => false)) {
    await tplCard.click();
    await page.waitForLoadState('networkidle');
  }

  // Wait and watch for 120 seconds - user will interact manually
  console.log('Watching for errors... interact with the template screen now');
  let lastCount = 0;
  for (let i = 0; i < 240; i++) {
    if (allErrors.length > lastCount) {
      for (let j = lastCount; j < allErrors.length; j++) {
        console.log(`\n=== ERROR ${j + 1} [${new Date().toISOString()}] ===`);
        console.log(allErrors[j]);
      }
      lastCount = allErrors.length;
    }
    await page.waitForTimeout(500);
  }

  console.log(`\n=== TOTAL ERRORS: ${allErrors.length} ===`);
});
