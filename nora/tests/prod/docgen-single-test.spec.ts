/**
 * docgen-single-test.spec.ts
 *
 * One-off test: Generate a single Bancroft Exhibit A - Variable WO,
 * download the .docx, and inspect OOXML for field population.
 *
 * Run:
 *   cd C:\dcfg\nora
 *   npx playwright test docgen-single-test --config=playwright-prod.config.ts --project=prod-docgen --headed --retries=0
 */
import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const BASE = 'https://dmms1.powerappsportals.com';
const TAG = `SINGLETEST-${Date.now().toString(36).toUpperCase()}`;
const OUT = './test-results';
const V = 1000;
const observe = (p: Page) => p.waitForTimeout(V);

test.describe.configure({ mode: 'serial', retries: 0, timeout: 300_000 });
test.use({ storageState: './prod-auth-state.json' });

test('00 AUTH', async ({ page }) => {
  await page.goto(`${BASE}/#/dashboard`);
  await page.waitForTimeout(5000);
  if (page.url().includes('login.microsoftonline.com')) {
    console.log('[AUTH] Expired — sign in and press Resume');
    await page.pause();
    await page.context().storageState({ path: './prod-auth-state.json' });
  }
  console.log(`[AUTH] OK — TAG: ${TAG}`);
});

test('01 Generate Ban-ExhA-Var with unique values', async ({ page }) => {
  await page.goto(`${BASE}/#/contracts/new?type=wo`);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(3000);

  // 1. Select customer
  const custInput = page.getByTestId('cc-customer-search');
  await expect(custInput).toBeVisible({ timeout: 10_000 });
  await custInput.pressSequentially('Ban', { delay: 120 });
  await page.waitForTimeout(3000);
  await page.locator('[data-testid^="cc-btn-customer-"]').first().click();
  await page.waitForTimeout(3000);
  console.log('  Customer: Bancroft');

  // 2. Select Exhibit A - Variable template
  const tplBtn = page.locator('[data-testid^="cc-tpl-btn-"]', { hasText: 'Exhibit A - Variable' });
  await expect(tplBtn).toBeVisible({ timeout: 10_000 });
  await tplBtn.click();
  await observe(page);
  console.log('  Template: Exhibit A - Variable');

  // 3. Fill WO number
  const woChip = page.getByTestId('cc-chip-wo-number');
  await expect(woChip).toBeVisible({ timeout: 5000 });
  await woChip.click();
  await observe(page);
  const woInput = page.getByTestId('cc-wo-number');
  await expect(woInput).toBeVisible({ timeout: 5000 });
  const woNum = '269999';
  await woInput.fill(woNum);
  const woDone = page.getByTestId('cc-btn-wo-done');
  if (await woDone.isVisible({ timeout: 2000 }).catch(() => false)) {
    await woDone.click();
    await observe(page);
  }
  console.log(`  WO#: ${woNum}`);

  // 4. Pick vendor
  const vendorChip = page.getByTestId('cc-chip-vendor');
  await expect(vendorChip).toBeVisible({ timeout: 5000 });
  await vendorChip.click();
  await page.waitForTimeout(2000);
  const vendorRow = page.locator('[data-testid^="cc-vendor-row-"]').first();
  await expect(vendorRow).toBeVisible({ timeout: 5000 });
  const vendorName = await vendorRow.innerText().catch(() => 'unknown');
  await vendorRow.click();
  await observe(page);
  const closeDrawer = page.getByTestId('cc-btn-close-drawer');
  if (await closeDrawer.isVisible({ timeout: 2000 }).catch(() => false)) {
    await closeDrawer.click();
    await observe(page);
  }
  console.log(`  Vendor: ${vendorName.substring(0, 40)}`);

  // 5. Pick location
  const locChip = page.getByTestId('cc-chip-location');
  if (await locChip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await locChip.click();
  } else {
    const addLoc = page.getByTestId('cc-btn-add-location');
    if (await addLoc.isVisible({ timeout: 3000 }).catch(() => false)) await addLoc.click();
  }
  await page.waitForTimeout(2000);
  const locRow = page.locator('[data-testid^="cc-location-row-"]').first();
  await expect(locRow).toBeVisible({ timeout: 5000 });
  const locName = await locRow.innerText().catch(() => 'unknown');
  await locRow.click();
  await observe(page);
  if (await closeDrawer.isVisible({ timeout: 2000 }).catch(() => false)) {
    await closeDrawer.click();
    await observe(page);
  }
  console.log(`  Location: ${locName.substring(0, 40)}`);

  // 6. Fill signers — use distinctive values
  const signerChip = page.getByTestId('cc-chip-signers');
  await expect(signerChip).toBeVisible({ timeout: 5000 });
  await signerChip.click();
  await observe(page);

  const custSignerName = `${TAG}-CUST-SIGNER`;
  const custSignerTitle = `${TAG}-CUST-TITLE`;
  const vendorSignerName = `${TAG}-VEND-SIGNER`;
  const vendorSignerTitle = `${TAG}-VEND-TITLE`;

  await page.getByTestId('cc-cust-signer-name').fill(custSignerName);
  await page.getByTestId('cc-cust-signer-title').fill(custSignerTitle);
  await page.getByTestId('cc-vendor-signer-name').fill(vendorSignerName);
  await page.getByTestId('cc-vendor-signer-title').fill(vendorSignerTitle);
  console.log(`  Customer signer: ${custSignerName} / ${custSignerTitle}`);
  console.log(`  Vendor signer: ${vendorSignerName} / ${vendorSignerTitle}`);

  await observe(page);
  const signerDone = page.getByTestId('cc-btn-signers-done');
  if (await signerDone.isVisible({ timeout: 2000 }).catch(() => false)) {
    await signerDone.click();
    await observe(page);
  }

  // 7. Add a line item with distinctive description
  await page.getByTestId('cc-btn-add-item').click();
  await page.waitForTimeout(500);
  const costCode = page.getByTestId('cc-costcode-0');
  if (await costCode.isVisible({ timeout: 2000 }).catch(() => false)) {
    await costCode.selectOption({ index: 1 }).catch(() => {});
  }
  const itemDesc = `${TAG}-WORK-ITEM-DESC`;
  await page.getByTestId('cc-item-desc-0').fill(itemDesc);
  await page.getByTestId('cc-item-amount-0').fill('7777.00');
  console.log(`  Line item: ${itemDesc} / $7,777.00`);
  await observe(page);

  // Screenshot before generate
  await page.screenshot({ path: `${OUT}/SINGLE-before-generate.png`, fullPage: true });

  // 8. Generate
  const genBtn = page.getByTestId('cc-btn-generate');
  await expect(genBtn).toBeVisible({ timeout: 5000 });
  await expect(genBtn).toBeEnabled({ timeout: 5000 });
  await genBtn.click();
  console.log('  Generate clicked — waiting for document...');

  // Wait for document indicator
  const indicators = page.locator(
    '[data-testid="doc-history-row"], [data-testid="link-view-document"], ' +
    '[data-testid="cc-doc-link"], [data-testid="doc-live-link"], [data-testid="msa-open-doc"]'
  ).first();

  for (let elapsed = 0; elapsed < 90_000; elapsed += 3000) {
    if (await indicators.isVisible().catch(() => false)) {
      console.log(`  Document created (${elapsed / 1000}s)`);
      break;
    }
    const docCount = page.locator('text=/[1-9]\\d* docs?/i').first();
    if (await docCount.isVisible().catch(() => false)) {
      console.log(`  Document created — count updated (${elapsed / 1000}s)`);
      break;
    }
    await page.waitForTimeout(3000);
  }

  // Screenshot after generate
  await page.screenshot({ path: `${OUT}/SINGLE-after-generate.png`, fullPage: true });

  // 9. Try to download via "Open Document" or doc history link
  // First try the "Open Document" button on the detail sidebar
  const openDocBtn = page.locator('button:has-text("Open Document"), a:has-text("Open Document")').first();
  if (await openDocBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    const href = await openDocBtn.getAttribute('href').catch(() => null);
    console.log(`  Open Document href: ${href?.substring(0, 100) || 'no href (button)'}`);

    // Try download
    const [download] = await Promise.all([
      page.waitForEvent('download', { timeout: 15000 }).catch(() => null),
      openDocBtn.click(),
    ]);

    if (download) {
      const filePath = path.join(OUT, `SINGLE-doc.docx`);
      await download.saveAs(filePath);
      console.log(`  Downloaded: ${fs.statSync(filePath).size} bytes`);
    } else {
      console.log('  No download — checking for new tab...');
    }
  }

  // Also try the doc history "Open" link
  const historyLink = page.locator('[data-testid="doc-history-link"], a:has-text("Open")').last();
  if (await historyLink.isVisible({ timeout: 3000 }).catch(() => false)) {
    const href = await historyLink.getAttribute('href').catch(() => null);
    console.log(`  History link href: ${href?.substring(0, 120) || 'no href'}`);

    const [download2] = await Promise.all([
      page.waitForEvent('download', { timeout: 15000 }).catch(() => null),
      historyLink.click(),
    ]);

    if (download2) {
      const filePath2 = path.join(OUT, `SINGLE-doc-history.docx`);
      await download2.saveAs(filePath2);
      console.log(`  Downloaded via history: ${fs.statSync(filePath2).size} bytes`);
    }
  }

  // 10. Submit
  const submitBtn = page.getByTestId('cc-btn-submit-approval');
  if (await submitBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await submitBtn.click();
    await page.waitForTimeout(2000);
    console.log('  Submitted for approval');
  }

  await page.screenshot({ path: `${OUT}/SINGLE-final.png`, fullPage: true });
});

test('02 Inspect downloaded doc', async ({}) => {
  const files = [
    path.join(OUT, 'SINGLE-doc.docx'),
    path.join(OUT, 'SINGLE-doc-history.docx'),
  ];

  for (const filePath of files) {
    if (!fs.existsSync(filePath)) {
      console.log(`  File not found: ${filePath}`);
      continue;
    }

    const size = fs.statSync(filePath).size;
    if (size < 100) {
      console.log(`  File too small (${size} bytes): ${filePath}`);
      continue;
    }

    console.log(`\n=== Inspecting: ${path.basename(filePath)} (${size} bytes) ===`);

    const JSZip = require('jszip');
    const data = fs.readFileSync(filePath);
    const zip = await JSZip.loadAsync(data);
    const docXml = await zip.file('word/document.xml')?.async('string');
    if (!docXml) { console.log('  ERROR: No word/document.xml'); continue; }

    const plainText = docXml.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

    // Search for unique test values
    const searchTerms = [
      { label: 'Customer signer name', term: 'CUST-SIGNER' },
      { label: 'Customer signer title', term: 'CUST-TITLE' },
      { label: 'Vendor signer name', term: 'VEND-SIGNER' },
      { label: 'Vendor signer title', term: 'VEND-TITLE' },
      { label: 'Work item description', term: 'WORK-ITEM-DESC' },
      { label: 'WO number', term: '269999' },
      { label: 'Amount', term: '7,777' },
      { label: 'Customer name', term: 'Bancroft' },
    ];

    console.log('\n  Value injection check:');
    for (const s of searchTerms) {
      const found = plainText.includes(s.term);
      console.log(`    ${found ? 'FOUND' : 'MISS '}: ${s.label} ("${s.term}")`);
    }

    // Yellow highlights
    const yellowCount = (docXml.match(/w:highlight[^>]*yellow/gi) || []).length;
    console.log(`\n  Yellow highlights: ${yellowCount}`);

    if (yellowCount > 0) {
      // Show what's near each yellow highlight
      const yellowPattern = /(<w:rPr>[\s\S]*?<w:highlight\s+w:val="yellow"\s*\/>[\s\S]*?<\/w:rPr>[\s\S]*?<w:t[^>]*>([^<]*)<\/w:t>)/gi;
      let m;
      let idx = 0;
      while ((m = yellowPattern.exec(docXml)) !== null) {
        idx++;
        console.log(`    Yellow #${idx}: text="${m[2]}"`);
      }
    }

    // Content controls
    const sdtCount = (docXml.match(/<w:sdt>/g) || []).length;
    console.log(`  Content controls remaining: ${sdtCount}`);

    // Print first 2000 chars of doc text
    const allText = (docXml.match(/<w:t[^>]*>([^<]*)<\/w:t>/g) || [])
      .map(t => t.replace(/<[^>]+>/g, ''))
      .join(' ').replace(/\s+/g, ' ').trim();
    console.log(`\n  Document text (first 2000 chars):\n  ${allText.substring(0, 2000)}`);
  }
});
