import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: /.*\.spec\.ts/,
  timeout: 60000,
  retries: 0,
  use: {
    baseURL: 'https://holding.powerappsportals.com',
    browserName: 'chromium',
    headless: true,
    viewport: { width: 1400, height: 900 },
    screenshot: 'only-on-failure',
    storageState: './auth-state.json',
  },
});
