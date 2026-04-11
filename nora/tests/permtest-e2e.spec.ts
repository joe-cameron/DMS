import { test, expect } from '@playwright/test';

/**
 * E2E Permission Validation — dcfg_permtest
 *
 * Tests whether API-created table permissions are actually enforced
 * by the Power Pages portal runtime.
 *
 * Prerequisites (already created by PermTest_E2E.ps1):
 * - dcfg_permtest table exists
 * - Site settings: Webapi/dcfg_permtest/enabled = true, fields = *
 * - Table permission: global, full CRUD, linked to Authenticated Users + DCFG_Admin
 * - Test record seeded with dcfg_name = 'E2E Test Record'
 */

const PORTAL_URL = 'https://dcfg.powerappsportals.com';

test.describe('Permission E2E Validation', () => {

  test('authenticate and test dcfg_permtests API', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();

    // Step 1: Navigate to portal — triggers Entra login
    console.log('[E2E] Navigating to portal...');
    await page.goto(PORTAL_URL);
    await page.waitForTimeout(2000);

    // Step 2: Manual sign-in via Windows Hello
    console.log('[E2E] PAUSE — Sign in with Windows Hello, then press Resume');
    await page.pause();

    // Step 3: Verify we're on the SPA
    console.log('[E2E] Verifying SPA loaded...');
    await page.waitForTimeout(3000);
    const url = page.url();
    console.log(`[E2E] Current URL: ${url}`);
    expect(url).toContain('dcfg.powerappsportals.com');

    // Step 4: Clear cache
    console.log('[E2E] Clearing portal cache...');
    await page.goto(`${PORTAL_URL}/_services/about?clearCache=true`);
    await page.waitForTimeout(3000);
    console.log('[E2E] Cache cleared');

    // Step 5: TEST THE PERMISSION — call /_api/dcfg_permtests
    console.log('[E2E] Testing /_api/dcfg_permtests...');
    const apiResponse = await page.evaluate(async () => {
      try {
        const resp = await fetch('/_api/dcfg_permtests', {
          credentials: 'same-origin',
          headers: {
            'Accept': 'application/json',
            'OData-MaxVersion': '4.0',
            'OData-Version': '4.0',
          }
        });
        return {
          status: resp.status,
          statusText: resp.statusText,
          body: resp.status === 200 ? await resp.json() : await resp.text()
        };
      } catch (err: any) {
        return { status: -1, statusText: 'fetch error', body: err.message };
      }
    });

    console.log(`[E2E] API Response: ${apiResponse.status} ${apiResponse.statusText}`);
    console.log(`[E2E] Body: ${JSON.stringify(apiResponse.body).substring(0, 500)}`);

    // VERDICT
    if (apiResponse.status === 200) {
      const records = apiResponse.body?.value || [];
      console.log(`[E2E] SUCCESS — Permission works! ${records.length} records returned`);

      // Check if our test record is there
      const testRecord = records.find((r: any) => r.dcfg_name === 'E2E Test Record');
      if (testRecord) {
        console.log(`[E2E] Test record found: ${testRecord.dcfg_permtestid}`);
      }

      expect(apiResponse.status).toBe(200);
    } else if (apiResponse.status === 403) {
      console.log('[E2E] FAIL — 403 Forbidden. Permission NOT enforced by portal.');
      expect(apiResponse.status, 'Permission should return 200, got 403').toBe(200);
    } else {
      console.log(`[E2E] UNEXPECTED — Status ${apiResponse.status}`);
      expect(apiResponse.status, `Unexpected status ${apiResponse.status}`).toBe(200);
    }

    // Step 6: Test CREATE via portal API (the real CRUD test)
    console.log('[E2E] Testing CREATE via portal API...');
    const createResponse = await page.evaluate(async () => {
      try {
        // Get CSRF token
        const tokenPromise = new Promise<string>((resolve, reject) => {
          const d = (window as any).shell?.getTokenDeferred?.()
                 || (window as any).top?.shell?.getTokenDeferred?.();
          if (!d) return reject(new Error('Token provider unavailable'));
          d.done(resolve).fail(reject);
        });

        let token: string;
        try {
          token = await tokenPromise;
        } catch {
          return { status: -2, statusText: 'no CSRF token', body: 'Token provider not available — may need to navigate to SPA first' };
        }

        const resp = await fetch('/_api/dcfg_permtests', {
          method: 'POST',
          credentials: 'same-origin',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'OData-MaxVersion': '4.0',
            'OData-Version': '4.0',
            '__RequestVerificationToken': token
          },
          body: JSON.stringify({ dcfg_name: 'E2E Created via Portal API' })
        });
        return {
          status: resp.status,
          statusText: resp.statusText,
          body: resp.status === 204 ? 'Created (204)' : await resp.text()
        };
      } catch (err: any) {
        return { status: -1, statusText: 'fetch error', body: err.message };
      }
    });

    console.log(`[E2E] CREATE Response: ${createResponse.status} ${createResponse.statusText}`);
    console.log(`[E2E] CREATE Body: ${JSON.stringify(createResponse.body).substring(0, 300)}`);

    if (createResponse.status === 204 || createResponse.status === 200) {
      console.log('[E2E] CREATE SUCCESS — Full CRUD permission confirmed!');
    } else if (createResponse.status === -2) {
      console.log('[E2E] No CSRF token — navigating to SPA for token provider...');

      // Navigate to SPA to get token provider
      await page.goto(`${PORTAL_URL}/#/dashboard`);
      await page.waitForTimeout(5000);

      // Retry create
      const retryResponse = await page.evaluate(async () => {
        try {
          const tokenPromise = new Promise<string>((resolve, reject) => {
            const d = (window as any).shell?.getTokenDeferred?.()
                   || (window as any).top?.shell?.getTokenDeferred?.();
            if (!d) return reject(new Error('still no token'));
            d.done(resolve).fail(reject);
          });
          const token = await tokenPromise;

          const resp = await fetch('/_api/dcfg_permtests', {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'OData-MaxVersion': '4.0',
              'OData-Version': '4.0',
              '__RequestVerificationToken': token
            },
            body: JSON.stringify({ dcfg_name: 'E2E Created via Portal API (retry)' })
          });
          return {
            status: resp.status,
            statusText: resp.statusText,
            body: resp.status === 204 ? 'Created (204)' : await resp.text()
          };
        } catch (err: any) {
          return { status: -1, statusText: 'error', body: err.message };
        }
      });

      console.log(`[E2E] RETRY CREATE: ${retryResponse.status} ${retryResponse.statusText}`);
      console.log(`[E2E] RETRY Body: ${JSON.stringify(retryResponse.body).substring(0, 300)}`);
    }

    // Step 7: Final READ to confirm all records
    console.log('[E2E] Final READ...');
    await page.goto(`${PORTAL_URL}/#/dashboard`);
    await page.waitForTimeout(3000);

    const finalRead = await page.evaluate(async () => {
      try {
        const resp = await fetch('/_api/dcfg_permtests?$select=dcfg_name,dcfg_permtestid', {
          credentials: 'same-origin',
          headers: { 'Accept': 'application/json' }
        });
        if (resp.ok) return await resp.json();
        return { error: resp.status, text: await resp.text() };
      } catch (err: any) {
        return { error: err.message };
      }
    });

    console.log(`[E2E] Final records: ${JSON.stringify(finalRead).substring(0, 500)}`);

    await context.close();
  });
});
