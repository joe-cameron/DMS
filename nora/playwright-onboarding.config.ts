import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: /onboarding-e2e\.spec\.ts/,
  timeout: 180000,
  retries: 0,
  use: {
    baseURL: 'https://dcfg.powerappsportals.com',
    browserName: 'chromium',
    headless: false,
    viewport: { width: 1400, height: 900 },
    screenshot: 'on',
    trace: 'on',
  },
});
