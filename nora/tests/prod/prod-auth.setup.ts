import { test as setup } from '@playwright/test';

/**
 * Prod Auth Setup — Opens dmms1.powerappsportals.com and pauses for manual Entra ID sign-in.
 * Sign in with your Microsoft account, then press "Resume" in the Playwright inspector.
 * Saves cookies to prod-auth-state.json for all subsequent prod tests.
 */
setup('authenticate on prod', async ({ page }) => {
  await page.goto('https://dmms1.powerappsportals.com');

  // Wait for redirect to Entra ID or page load
  await page.waitForLoadState('networkidle');

  // Pause for manual sign-in — click Resume after authenticating
  await page.pause();

  // Verify we're authenticated — wait for SPA to boot
  await page.waitForLoadState('networkidle');

  // Save authenticated state
  await page.context().storageState({ path: './prod-auth-state.json' });
});
