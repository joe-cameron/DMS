import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

test('Capture template save errors', async ({ page }) => {
  const networkErrors: string[] = [];
  const consoleErrors: string[] = [];

  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', e => { consoleErrors.push(`PAGE: ${e.message}`); });
  page.on('response', r => {
    if (r.status() >= 400) {
      r.text().then(body => {
        networkErrors.push(`${r.status()} ${r.url().substring(0, 120)}\n  Body: ${body.substring(0, 500)}`);
      }).catch(() => {
        networkErrors.push(`${r.status()} ${r.url().substring(0, 120)}`);
      });
    }
  });

  // Go to admin
  await page.goto('https://dmms1.powerappsportals.com/#/admin');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 30000 });

  // Poll for 45 seconds to catch any errors the user triggers
  for (let i = 0; i < 90; i++) {
    if (networkErrors.length > 0 || consoleErrors.length > 0) {
      console.log('\n=== ERRORS DETECTED ===');
      for (const e of networkErrors) console.log('NETWORK:', e);
      for (const e of consoleErrors) console.log('CONSOLE:', e);
      networkErrors.length = 0;
      consoleErrors.length = 0;
    }
    await page.waitForTimeout(500);
  }

  console.log('\n=== FINAL CHECK ===');
  console.log('Network errors remaining:', networkErrors.length);
  for (const e of networkErrors) console.log('  ', e);
  console.log('Console errors remaining:', consoleErrors.length);
  for (const e of consoleErrors) console.log('  ', e);
});
