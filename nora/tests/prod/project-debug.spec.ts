import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

test('Debug project page crash', async ({ page }) => {
  const consoleMessages: string[] = [];
  const consoleErrors: string[] = [];
  const networkErrors: string[] = [];

  page.on('console', m => {
    consoleMessages.push(`[${m.type()}] ${m.text()}`);
    if (m.type() === 'error') consoleErrors.push(m.text());
  });
  page.on('pageerror', e => {
    consoleErrors.push(`PAGE ERROR: ${e.message}\n${e.stack}`);
  });
  page.on('response', r => {
    if (r.status() >= 400) networkErrors.push(`${r.status()} ${r.url().substring(0, 120)}`);
  });

  // Navigate directly to projects?new=1 (same as nav-create-project)
  await page.goto('https://dmms1.powerappsportals.com/#/projects?new=1');
  await page.waitForLoadState('networkidle');

  // Wait for content or error
  try {
    await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 15000 });
  } catch {
    console.log('Page did not render substantial content in 15s');
  }

  // Capture state
  const url = page.url();
  const bodyText = await page.textContent('body').catch(() => 'COULD NOT GET BODY');

  console.log('=== URL ===');
  console.log(url);
  console.log('\n=== BODY (first 1000) ===');
  console.log(bodyText?.substring(0, 1000));
  console.log('\n=== CONSOLE ERRORS ===');
  for (const e of consoleErrors) console.log(e);
  console.log('\n=== NETWORK ERRORS ===');
  for (const e of networkErrors) console.log(e);
  console.log('\n=== ALL CONSOLE (last 30) ===');
  for (const m of consoleMessages.slice(-30)) console.log(m);

  // Check for toast errors
  const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').allTextContents();
  if (toasts.length) console.log('\n=== TOASTS ===\n' + toasts.join('\n'));

  // Look for any error display in the page
  const errorElements = await page.locator('[class*="error"], [class*="Error"], [data-testid*="error"]').allTextContents();
  if (errorElements.length) console.log('\n=== ERROR ELEMENTS ===\n' + errorElements.join('\n'));

  await page.screenshot({ path: 'C:/DCFG/nora/test-results/project-debug.png', fullPage: true });

  // Also try just /projects without ?new=1
  console.log('\n=== TRYING /projects (no new param) ===');
  await page.goto('https://dmms1.powerappsportals.com/#/projects');
  await page.waitForLoadState('networkidle');
  try {
    await page.waitForFunction(() => document.body.innerText.length > 200, { timeout: 15000 });
  } catch {}

  const bodyText2 = await page.textContent('body').catch(() => 'COULD NOT GET BODY');
  console.log(bodyText2?.substring(0, 500));

  const toasts2 = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').allTextContents();
  if (toasts2.length) console.log('TOASTS: ' + toasts2.join(' | '));

  await page.screenshot({ path: 'C:/DCFG/nora/test-results/project-list-debug.png', fullPage: true });

  expect(true).toBe(true);
});
