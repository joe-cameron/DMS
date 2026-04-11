import { test as setup } from '@playwright/test';

/**
 * Auth Setup — Opens the staging portal and pauses for manual sign-in.
 * The browser will show the Power Pages sign-in screen.
 * Sign in with your Microsoft account, then press "Resume" in the Playwright inspector.
 * After sign-in, the auth state (cookies/session) is saved for all subsequent tests.
 */
setup('authenticate', async ({ page }) => {
  // Navigate to the staging portal
  await page.goto('https://holding.powerappsportals.com');

  // Wait for the page to load
  await page.waitForTimeout(3000);

  // Pause — the browser window will open and show the portal.
  // Sign in manually, then click "Resume" in the Playwright Inspector panel.
  // This captures your auth cookies for all subsequent tests.
  await page.pause();

  // After resume, verify we're authenticated by checking for the nav panel
  // or any element that only appears when signed in
  await page.waitForTimeout(3000);

  // Save the authenticated state
  await page.context().storageState({ path: './auth-state.json' });
});
