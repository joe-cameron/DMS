/**
 * docgen-open-docs.spec.ts
 *
 * Downloads each generated .docx via "View Document" link in contracts list,
 * then inspects OOXML content for unprocessed tags and expected values.
 *
 * Run:
 *   cd C:\dcfg\nora
 *   npx playwright test docgen-open-docs --config=playwright-prod.config.ts --project=prod-docgen --headed --retries=0
 */
import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const BASE = 'https://dmms1.powerappsportals.com';
const OUT = './test-results';

test.describe.configure({ mode: 'serial', retries: 0, timeout: 180_000 });
test.use({ storageState: './prod-auth-state.json' });

const docs = [
  { label: 'Ban-ExhA-Auto', search: '268570', expect: ['268570', 'CSIGN', 'VSIGN', '4,500', 'South Drive'] },
  { label: 'Ban-ExhA-Var',  search: '260722', expect: ['260722', 'CSIGN', 'VSIGN', '3,800', 'South Drive'] },
  { label: 'Ban-BlanketWO', search: '263489', expect: ['263489', 'CSIGN', 'VSIGN', '1,800', 'South Drive'] },
  { label: 'Ban-Amendment',  search: 'Bancroft-DRAFT-A1', expect: ['CSIGN', 'VSIGN', 'Extended HVAC', 'South Drive'] },
  { label: 'Ban-VA',        search: 'Bancroft-DRAFT-2026-05-07', expect: ['CSIGN', 'VSIGN', '1-800-GOT-JUNK'] },
  { label: 'Dec-WO',        search: '261329', expect: ['261329', 'CSIGN', 'VSIGN', '3,500', 'Village'] },
  { label: 'Dec-Amendment',  search: 'PennReach-DRAFT-A1', expect: ['CSIGN', 'VSIGN', 'landscaping', 'Village'] },
  { label: 'Dec-VA',        search: 'PennReach-DRAFT-2026-05-07', expect: ['CSIGN', 'VSIGN', '1-800-GOT-JUNK'] },
];

test('00 AUTH check', async ({ page }) => {
  await page.goto(`${BASE}/#/dashboard`);
  await page.waitForTimeout(5000);
  if (page.url().includes('login.microsoftonline.com')) {
    console.log('[AUTH] Session expired — sign in and press Resume');
    await page.pause();
    await page.context().storageState({ path: './prod-auth-state.json' });
  }
  console.log('[AUTH] OK');
});

for (const doc of docs) {
  test(`01 Inspect ${doc.label}`, async ({ page }) => {
    console.log(`\n=== ${doc.label} ===`);

    await page.goto(`${BASE}/#/contracts`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Search for the contract
    const searchInput = page.locator('input[type="text"]').first();
    if (await searchInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      await searchInput.fill(doc.search);
      await page.waitForTimeout(2000);
    }

    // Click the first matching row to expand it
    const firstRow = page.locator('tbody tr').first();
    if (!await firstRow.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log(`  [${doc.label}] No contract row found for "${doc.search}"`);
      return;
    }
    await firstRow.click();
    await page.waitForTimeout(2000);

    // Find "View Document" link — this downloads the .docx
    const viewDoc = page.locator('a:has-text("View Document")').first();
    if (!await viewDoc.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log(`  [${doc.label}] View Document link not found`);
      await page.screenshot({ path: `${OUT}/DOC-${doc.label}-nolink.png`, fullPage: true });
      return;
    }

    // Intercept the download
    const [download] = await Promise.all([
      page.waitForEvent('download', { timeout: 30000 }).catch(() => null),
      viewDoc.click(),
    ]);

    if (!download) {
      console.log(`  [${doc.label}] No download triggered — maybe it opened a new tab`);
      await page.screenshot({ path: `${OUT}/DOC-${doc.label}-nodownload.png`, fullPage: true });
      return;
    }

    // Save the downloaded file
    const filePath = path.join(OUT, `DOC-${doc.label}.docx`);
    await download.saveAs(filePath);
    const size = fs.statSync(filePath).size;
    console.log(`  [${doc.label}] Downloaded: ${size} bytes`);

    // Inspect OOXML with jszip
    const JSZip = require('jszip');
    const data = fs.readFileSync(filePath);
    const zip = await JSZip.loadAsync(data);
    const docXml = await zip.file('word/document.xml')?.async('string');

    if (!docXml) {
      console.log(`  [${doc.label}] ERROR: No word/document.xml in archive`);
      return;
    }

    // Strip XML tags for text search
    const plainText = docXml.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

    // Check expected values
    const found: string[] = [];
    const missing: string[] = [];
    for (const v of doc.expect) {
      if (plainText.includes(v) || docXml.includes(v)) found.push(v);
      else missing.push(v);
    }

    // Check for unprocessed template tags
    const doubleBrace = plainText.match(/\{\{[A-Za-z_]+\}\}/g) || [];
    const angleBrace = plainText.match(/<<[A-Za-z_]+>>/g) || [];
    const yellowHighlight = (docXml.match(/w:highlight[^>]*w:val="yellow"/gi) || []).length;

    console.log(`  [${doc.label}] Values: ${found.length}/${doc.expect.length} found`);
    if (found.length > 0) console.log(`    FOUND: ${found.join(', ')}`);
    if (missing.length > 0) console.log(`    MISSING: ${missing.join(', ')}`);
    if (doubleBrace.length > 0) console.log(`    UNPROCESSED {{ }}: ${doubleBrace.join(', ')}`);
    if (angleBrace.length > 0) console.log(`    UNPROCESSED << >>: ${angleBrace.join(', ')}`);
    if (yellowHighlight > 0) console.log(`    YELLOW HIGHLIGHTS: ${yellowHighlight}`);

    const status = missing.length === 0 && doubleBrace.length === 0 && angleBrace.length === 0 && yellowHighlight === 0;
    console.log(`  [${doc.label}] RESULT: ${status ? 'PASS' : 'ISSUES'}`);
  });
}
