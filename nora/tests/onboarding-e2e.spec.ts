import { test, expect } from '@playwright/test';

const PORTAL = 'https://dcfg.powerappsportals.com';

test.describe('Onboarding Module E2E', () => {

  test('authenticate, navigate to onboarding, test full workflow', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();

    // ── Auth: Manual Windows Hello ──
    await page.goto(PORTAL);
    await page.pause(); // Sign in, then Resume

    // ── Verify SPA loaded ──
    await expect(page).toHaveURL(/dcfg\.powerappsportals\.com/);

    // ── Navigate to Onboarding ──
    await page.goto(`${PORTAL}/#/onboarding`);
    await page.waitForLoadState('networkidle');

    // Wait for the onboarding list to render
    await expect(page.getByText('Onboarding')).toBeVisible({ timeout: 15000 });

    // ── Screenshot: Onboarding list page ──
    await page.screenshot({ path: 'test-results/onboarding-01-list.png', fullPage: true });

    // ── Test: Create new onboarding case ──
    // Look for the "New" or "+" button to create a case
    const newCaseButton = page.getByRole('button', { name: /new|add|create/i });
    if (await newCaseButton.isVisible({ timeout: 5000 }).catch(() => false)) {
      await newCaseButton.click();
      await page.waitForLoadState('networkidle');
      await page.screenshot({ path: 'test-results/onboarding-02-new-case-panel.png', fullPage: true });

      // Fill in customer selection if there's a dropdown/search
      const customerField = page.getByRole('combobox', { name: /customer/i })
        .or(page.getByLabel(/customer/i))
        .or(page.locator('[data-field*="customer"]'));

      if (await customerField.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        await customerField.first().click();
        // Wait for dropdown options
        await page.waitForLoadState('networkidle');
        await page.screenshot({ path: 'test-results/onboarding-03-customer-select.png', fullPage: true });

        // Select first available customer
        const firstOption = page.getByRole('option').first()
          .or(page.locator('[role="listbox"] [role="option"]').first())
          .or(page.locator('.dropdown-item, .option-item, li[data-value]').first());

        if (await firstOption.isVisible({ timeout: 3000 }).catch(() => false)) {
          await firstOption.click();
        }
      }

      // Look for save/create button
      const saveButton = page.getByRole('button', { name: /save|create|submit/i });
      if (await saveButton.isVisible({ timeout: 3000 }).catch(() => false)) {
        await saveButton.click();
        await page.waitForLoadState('networkidle');
        await page.screenshot({ path: 'test-results/onboarding-04-case-created.png', fullPage: true });
      }
    } else {
      console.log('[ONBOARDING] No new case button found — capturing current state');
      await page.screenshot({ path: 'test-results/onboarding-02-no-new-button.png', fullPage: true });
    }

    // ── Test: Check existing cases are displayed ──
    // Look for case rows/cards in the list
    const caseRows = page.locator('tr, [data-row], .case-card, .onboarding-row').filter({ hasText: /.+/ });
    const rowCount = await caseRows.count();
    console.log(`[ONBOARDING] Found ${rowCount} case rows`);
    await page.screenshot({ path: 'test-results/onboarding-05-case-list.png', fullPage: true });

    // ── Test: Click into first case (if any) ──
    if (rowCount > 0) {
      await caseRows.first().click();
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/onboarding\/.+/);
      await page.screenshot({ path: 'test-results/onboarding-06-case-detail.png', fullPage: true });

      // ── Test: Verify checklist steps loaded ──
      // The 15 test steps should appear as an accordion or list
      await page.waitForLoadState('networkidle');

      // Look for phase headers or step items
      const phaseHeaders = page.getByText(/sales|contracting|setup|training|go.?live/i);
      const phaseCount = await phaseHeaders.count();
      console.log(`[ONBOARDING] Found ${phaseCount} phase headers`);

      const stepItems = page.getByText(/test proposal|client data|invoice|contract generated|contract sent|signed contract|upkeep|portal access|data review|kickoff|portal training|emergency|inspection|go-live|check-in/i);
      const stepCount = await stepItems.count();
      console.log(`[ONBOARDING] Found ${stepCount} step items matching test steps`);

      await page.screenshot({ path: 'test-results/onboarding-07-steps-loaded.png', fullPage: true });

      // ── Test: Verify RACI data on a step ──
      // Click first step to expand/view details
      const firstStep = page.getByText(/test proposal signed/i);
      if (await firstStep.isVisible({ timeout: 5000 }).catch(() => false)) {
        await firstStep.click();
        await page.waitForLoadState('networkidle');
        await page.screenshot({ path: 'test-results/onboarding-08-step-detail.png', fullPage: true });

        // Check for test email addresses in the step detail
        const hasTest1 = await page.getByText('Test1@decades-cg.com').isVisible({ timeout: 3000 }).catch(() => false);
        const hasTest2 = await page.getByText('Test2@decades-cg.com').isVisible({ timeout: 3000 }).catch(() => false);
        console.log(`[ONBOARDING] Test1 email visible: ${hasTest1}, Test2 email visible: ${hasTest2}`);

        // Check for RACI fields
        const hasResponsible = await page.getByText(/responsible|assigned/i).isVisible({ timeout: 2000 }).catch(() => false);
        const hasAccountable = await page.getByText(/accountable/i).isVisible({ timeout: 2000 }).catch(() => false);
        console.log(`[ONBOARDING] Responsible field: ${hasResponsible}, Accountable field: ${hasAccountable}`);
      }

      // ── Test: Edit a step (dates, notes) ──
      const notesField = page.getByRole('textbox', { name: /notes/i })
        .or(page.getByLabel(/notes/i))
        .or(page.locator('textarea'));

      if (await notesField.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        await notesField.first().fill('E2E test note - ' + new Date().toISOString());
        await page.screenshot({ path: 'test-results/onboarding-09-notes-filled.png', fullPage: true });

        // Save
        const saveBtn = page.getByRole('button', { name: /save/i });
        if (await saveBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
          await saveBtn.click();
          await page.waitForLoadState('networkidle');
          await page.screenshot({ path: 'test-results/onboarding-10-saved.png', fullPage: true });
        }
      }

      // ── Test: Mark step complete ──
      const completeBtn = page.getByRole('button', { name: /complete|done|mark/i })
        .or(page.getByRole('checkbox', { name: /complete/i }));

      if (await completeBtn.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        await completeBtn.first().click();
        await page.waitForLoadState('networkidle');
        await page.screenshot({ path: 'test-results/onboarding-11-step-completed.png', fullPage: true });
      }

      // ── Test: Navigate back to list ──
      await page.goto(`${PORTAL}/#/onboarding`);
      await page.waitForLoadState('networkidle');
      await page.screenshot({ path: 'test-results/onboarding-12-back-to-list.png', fullPage: true });
    }

    // ── Test: Search functionality ──
    const searchInput = page.getByRole('searchbox')
      .or(page.getByPlaceholder(/search/i))
      .or(page.locator('input[type="search"]'));

    if (await searchInput.first().isVisible({ timeout: 3000 }).catch(() => false)) {
      await searchInput.first().fill('test');
      await page.waitForLoadState('networkidle');
      await page.screenshot({ path: 'test-results/onboarding-13-search.png', fullPage: true });
      await searchInput.first().clear();
    }

    // ── Test: Sort functionality ──
    const sortHeader = page.locator('th').filter({ hasText: /customer|status|date/i }).first();
    if (await sortHeader.isVisible({ timeout: 3000 }).catch(() => false)) {
      await sortHeader.click();
      await page.screenshot({ path: 'test-results/onboarding-14-sorted.png', fullPage: true });
    }

    // ── Test: Soft delete / restore ──
    // Navigate to a case first
    if (rowCount > 0) {
      await caseRows.first().click();
      await page.waitForLoadState('networkidle');

      const deleteBtn = page.getByRole('button', { name: /delete|archive|close/i });
      if (await deleteBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.log('[ONBOARDING] Delete button found — not clicking (preserving test data)');
        await page.screenshot({ path: 'test-results/onboarding-15-delete-available.png', fullPage: true });
      }
    }

    // ── Final: Admin page — Onboarding Steps tab ──
    await page.goto(`${PORTAL}/#/admin`);
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'test-results/onboarding-16-admin-default.png', fullPage: true });

    // Click the Onboarding Steps tab
    const onboardingTab = page.getByText('Onboarding Steps', { exact: true });
    if (await onboardingTab.isVisible({ timeout: 5000 }).catch(() => false)) {
      await onboardingTab.click();
      await page.waitForLoadState('networkidle');
      await page.screenshot({ path: 'test-results/onboarding-17-admin-steps-tab.png', fullPage: true });

      // Count visible step rows
      const adminStepRows = page.locator('tr, [data-row], .step-row').filter({ hasText: /test proposal|client data|invoice|contract|upkeep|portal|kickoff|training|emergency|inspection|go-live|check-in/i });
      const adminStepCount = await adminStepRows.count();
      console.log(`[ONBOARDING] Admin Onboarding Steps tab shows ${adminStepCount} test steps`);

      // Also check for the step names directly
      for (const name of ['Test proposal signed', 'Contract generated via DocGen', 'Kickoff meeting held', 'Client go-live confirmed']) {
        const visible = await page.getByText(name).isVisible({ timeout: 2000 }).catch(() => false);
        console.log(`[ONBOARDING] Step "${name}": ${visible ? 'VISIBLE' : 'NOT FOUND'}`);
      }
    } else {
      console.log('[ONBOARDING] Onboarding Steps tab not found on admin page');
    }

    // ── Onboarding page: capture DOM for debugging ──
    await page.goto(`${PORTAL}/#/onboarding`);
    await page.waitForLoadState('networkidle');
    // Wait a bit longer for React to render
    await page.waitForFunction(() => document.querySelectorAll('button, [role="button"]').length > 2, null, { timeout: 10000 }).catch(() => {});
    await page.screenshot({ path: 'test-results/onboarding-18-list-after-wait.png', fullPage: true });

    // Log all buttons visible
    const allButtons = await page.getByRole('button').allTextContents();
    console.log(`[ONBOARDING] All buttons on page: ${JSON.stringify(allButtons)}`);

    // Log all visible text elements for debugging
    const mainContent = await page.locator('main, [role="main"], .content, #content').first().textContent().catch(() => 'no main');
    console.log(`[ONBOARDING] Main content text (first 500): ${mainContent?.substring(0, 500)}`);

    await context.close();
  });
});
