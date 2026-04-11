import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 60000,
  retries: 0,
  use: {
    baseURL: 'https://holding.powerappsportals.com',
    browserName: 'chromium',
    headless: false,  // Show browser so user can sign in
    viewport: { width: 1400, height: 900 },
    screenshot: 'on',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'auth-setup',
      testMatch: /auth\.setup\.ts/,
    },
    {
      name: 'spa-tests',
      testMatch: /.*\.spec\.ts/,
      dependencies: ['auth-setup'],
      use: {
        storageState: './auth-state.json',
      },
    },
  ],
});
