import { test, expect } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });

test('verify auth and capture SPA state', async ({ page }) => {
  // Navigate to dashboard
  await page.goto('https://dmms1.powerappsportals.com/#/dashboard');
  await page.waitForLoadState('networkidle');

  // Give SPA time to boot (React hydration on Power Pages is slow)
  await page.waitForFunction(() => {
    return document.querySelector('#dcfg-root') !== null ||
           document.body.innerText.length > 100;
  }, { timeout: 30000 });

  // Capture what we see
  const bodyText = await page.textContent('body');
  console.log('=== BODY TEXT (first 2000 chars) ===');
  console.log(bodyText?.substring(0, 2000));

  // Check for auth issues
  const hasSignIn = bodyText?.includes('Sign in');
  const has403 = bodyText?.includes('403');
  const hasAccessDenied = bodyText?.includes('Access Denied');
  console.log(`\nAuth check: SignIn=${hasSignIn}, 403=${has403}, AccessDenied=${hasAccessDenied}`);

  // Capture all visible buttons
  const buttons = await page.getByRole('button').all();
  console.log(`\n=== BUTTONS FOUND: ${buttons.length} ===`);
  for (const btn of buttons.slice(0, 30)) {
    const text = await btn.textContent();
    const testId = await btn.getAttribute('data-testid');
    console.log(`  Button: "${text?.trim()}" testid=${testId}`);
  }

  // Capture all links
  const links = await page.getByRole('link').all();
  console.log(`\n=== LINKS FOUND: ${links.length} ===`);
  for (const link of links.slice(0, 30)) {
    const text = await link.textContent();
    const href = await link.getAttribute('href');
    const testId = await link.getAttribute('data-testid');
    console.log(`  Link: "${text?.trim()}" href=${href} testid=${testId}`);
  }

  // Capture all inputs
  const inputs = await page.locator('input').all();
  console.log(`\n=== INPUTS FOUND: ${inputs.length} ===`);
  for (const input of inputs.slice(0, 20)) {
    const placeholder = await input.getAttribute('placeholder');
    const type = await input.getAttribute('type');
    const testId = await input.getAttribute('data-testid');
    console.log(`  Input: type=${type} placeholder="${placeholder}" testid=${testId}`);
  }

  // Capture all elements with data-testid
  const testIdElements = await page.locator('[data-testid]').all();
  console.log(`\n=== ELEMENTS WITH data-testid: ${testIdElements.length} ===`);
  for (const el of testIdElements.slice(0, 50)) {
    const testId = await el.getAttribute('data-testid');
    const tag = await el.evaluate(e => e.tagName);
    const text = await el.textContent();
    console.log(`  ${tag} testid="${testId}" text="${text?.substring(0, 60).trim()}"`);
  }

  // Capture any toasts or error messages
  const toasts = await page.locator('[class*="toast"], [class*="Toast"], [role="alert"]').all();
  console.log(`\n=== TOASTS/ALERTS: ${toasts.length} ===`);
  for (const t of toasts) {
    const text = await t.textContent();
    console.log(`  Toast: "${text?.trim()}"`);
  }

  // Take a screenshot
  await page.screenshot({ path: './test-results/prod-dashboard-state.png', fullPage: true });
  console.log('\nScreenshot saved to test-results/prod-dashboard-state.png');

  // Now navigate to customers and capture
  await page.goto('https://dmms1.powerappsportals.com/#/customers');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 100, { timeout: 30000 });

  const custBody = await page.textContent('body');
  console.log('\n=== CUSTOMERS PAGE (first 1000 chars) ===');
  console.log(custBody?.substring(0, 1000));

  // Capture table rows
  const rows = await page.locator('tr').all();
  console.log(`\nTable rows found: ${rows.length}`);

  // Capture all data-testids on customers page
  const custTestIds = await page.locator('[data-testid]').all();
  console.log(`\n=== CUSTOMER PAGE data-testids: ${custTestIds.length} ===`);
  for (const el of custTestIds.slice(0, 50)) {
    const testId = await el.getAttribute('data-testid');
    const tag = await el.evaluate(e => e.tagName);
    console.log(`  ${tag} testid="${testId}"`);
  }

  await page.screenshot({ path: './test-results/prod-customers-state.png', fullPage: true });

  // Navigate to contracts/new (wizard)
  await page.goto('https://dmms1.powerappsportals.com/#/contracts/new');
  await page.waitForLoadState('networkidle');
  await page.waitForFunction(() => document.body.innerText.length > 100, { timeout: 30000 });

  const wizBody = await page.textContent('body');
  console.log('\n=== CONTRACT WIZARD (first 1000 chars) ===');
  console.log(wizBody?.substring(0, 1000));

  const wizTestIds = await page.locator('[data-testid]').all();
  console.log(`\n=== WIZARD data-testids: ${wizTestIds.length} ===`);
  for (const el of wizTestIds.slice(0, 50)) {
    const testId = await el.getAttribute('data-testid');
    const tag = await el.evaluate(e => e.tagName);
    console.log(`  ${tag} testid="${testId}"`);
  }

  await page.screenshot({ path: './test-results/prod-wizard-state.png', fullPage: true });

  expect(true).toBe(true); // always pass — this is discovery
});
