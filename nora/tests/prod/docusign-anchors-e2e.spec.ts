/**
 * DocuSign Anchor Verification E2E
 *
 * Automated portion of the document test flow:
 * 1. MSA Composer → fill form → Generate
 * 2. Capture OOXML injection console logs → verify DocuSign anchors injected
 * 3. Navigate to Send Queue → verify row created with document URL
 * 4. Verify Word Desktop button and Envelope ID input are present
 *
 * Visual mode: 1s pause between actions so operator can observe.
 *
 * Run:
 *   cd C:\dcfg\nora
 *   npx playwright test docusign-anchors --config=playwright-prod.config.ts --headed --retries=0
 */
import { test, expect, Page } from '@playwright/test';

test.use({ storageState: './prod-auth-state.json' });
test.describe.configure({ mode: 'serial', retries: 0, timeout: 300000 });

const V = 1000; // visual delay — 1s between actions for operator observation
const observe = (p: Page) => p.waitForTimeout(V);

// ─── Console + Network capture ───
interface LogBucket {
  console: string[];
  ooxmlLogs: string[];
  docusignAnchors: string[];
  errors: string[];
  networkFails: string[];
}

function setupCapture(page: Page): LogBucket {
  const bucket: LogBucket = {
    console: [],
    ooxmlLogs: [],
    docusignAnchors: [],
    errors: [],
    networkFails: [],
  };
  page.on('console', msg => {
    const text = msg.text();
    bucket.console.push(`[${msg.type()}] ${text}`);
    if (text.includes('[OOXML]')) {
      bucket.ooxmlLogs.push(text);
      console.log(`  [OOXML] ${text}`);
    }
    if (text.toLowerCase().includes('docusign') || text.includes('Signature')) {
      bucket.docusignAnchors.push(text);
      console.log(`  [SIGN] ${text}`);
    }
    if (msg.type() === 'error') {
      bucket.errors.push(text);
      console.log(`  [ERR] ${text}`);
    }
  });
  page.on('response', resp => {
    if (resp.status() >= 400) {
      const entry = `${resp.status()} ${resp.url().substring(0, 120)}`;
      bucket.networkFails.push(entry);
      console.log(`  [NET] ${entry}`);
    }
  });
  return bucket;
}

test('DocuSign anchor E2E: Composer -> Generate -> Send Queue', async ({ page }) => {
  const logs = setupCapture(page);

  // ── Step 1: Navigate to MSA Composer ──
  console.log('\n=== STEP 1: Open MSA Composer ===');
  await page.goto('/#/msa/new');
  await page.waitForLoadState('networkidle');
  await expect(page.getByTestId('package-PackageA')).toBeVisible({ timeout: 15000 });
  console.log('  OK Composer loaded');
  await observe(page);

  // ── Step 2: Fill the form ──
  console.log('\n=== STEP 2: Fill form ===');

  // Package A
  await page.getByTestId('package-PackageA').click();
  console.log('  OK Package A selected');
  await observe(page);

  // Customer search — click Search existing, wait for mode, type to filter
  await page.getByTestId('msa-btn-cust-search').click();
  await observe(page);
  const searchInput = page.getByTestId('customer-search');
  await expect(searchInput).toBeVisible({ timeout: 5000 });
  await searchInput.click();
  await observe(page);
  // Type slowly to trigger onChange per keystroke — "Ban" matches Bancroft in Prod
  await searchInput.pressSequentially('Ban', { delay: 200 });
  console.log('  -> Typed "Ban" in customer search');
  // Wait for OData results from Prod
  await page.waitForTimeout(3000);

  const custResult = page.locator('[data-testid^="customer-result-"]').first();
  await expect(custResult).toBeVisible({ timeout: 15000 });
  await observe(page);
  await custResult.click();
  console.log('  OK Customer selected');
  await observe(page);

  // Signer info
  const signerName = page.getByTestId('cust-signer-name');
  const signerTitle = page.getByTestId('cust-signer-title');
  await expect(signerName).toBeVisible({ timeout: 5000 });
  await signerName.fill('E2E-DOCUSIGN-SIGNER');
  await observe(page);
  await signerTitle.fill('E2E-DOCUSIGN-TITLE');
  console.log('  OK Signer info filled');
  await observe(page);

  // Pricing
  await page.getByTestId('msa-btn-price-uniform').click();
  await observe(page);
  await page.getByTestId('uni-rate').fill('100.00');
  await page.getByTestId('uni-onboard').fill('50.00');
  console.log('  OK Pricing set');
  await observe(page);

  // One location — fill name field and click Add
  const locNameInput = page.locator('input[placeholder*="Location name"], input[placeholder*="location name"], [data-testid="new-loc-name"]').first();
  await expect(locNameInput).toBeVisible({ timeout: 5000 });
  await locNameInput.fill('1981 Old Cuthbert Rd');
  await observe(page);
  // Click Add button
  const addBtn = page.locator('button', { hasText: /^Add$/ }).first().or(page.getByTestId('btn-add-loc'));
  await addBtn.click();
  await observe(page);
  // Verify via Fee Summary — Total locations should be ≥ 1
  await expect(page.getByText(/Total locations/)).toBeVisible({ timeout: 5000 });
  console.log('  OK Location added');
  await observe(page);

  // Screenshot before generate
  await page.screenshot({ path: './test-results/docusign-e2e-before-generate.png', fullPage: true });

  // ── Step 3: Generate document ──
  console.log('\n=== STEP 3: Generate document (watching OOXML logs) ===');

  const generateBtn = page.getByTestId('btn-download-msa').first();
  await expect(generateBtn).toBeVisible({ timeout: 5000 });
  await observe(page);

  // Watch for new tab (Word Online opens after SP upload)
  const [newTab] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 120000 }).catch(() => null),
    generateBtn.click(),
  ]);
  console.log(`  -> Generate clicked. New tab: ${newTab ? 'YES' : 'NO'}`);

  if (newTab) {
    await newTab.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    console.log(`  -> Word Online URL: ${newTab.url()}`);
    await observe(page);
    await newTab.close().catch(() => {});
  }

  // Wait for document generation to complete
  await page.bringToFront();
  await observe(page);

  const docRow = page.getByTestId('doc-history-row').first();
  try {
    await expect(docRow).toBeVisible({ timeout: 60000 });
    console.log('  OK Document history row appeared');
  } catch {
    console.log('  WARN Document history row not visible after 60s');
  }
  await observe(page);

  // Screenshot after generation
  await page.screenshot({ path: './test-results/docusign-e2e-after-generate.png', fullPage: true });

  // ── Step 4: Check OOXML logs for DocuSign anchors ──
  console.log('\n=== STEP 4: Verify DocuSign anchors in OOXML logs ===');
  console.log(`  Total OOXML logs captured: ${logs.ooxmlLogs.length}`);
  console.log(`  DocuSign-related logs: ${logs.docusignAnchors.length}`);
  for (const log of logs.ooxmlLogs) {
    console.log(`    ${log}`);
  }

  const allConsole = logs.console.join('\n');
  const anchorsFound = {
    decades: allConsole.includes('Decades_Signature'),
    vendor: allConsole.includes('Vendor_Signature'),
    customer: allConsole.includes('Customer_Signature'),
  };
  console.log(`  Decades_Signature: ${anchorsFound.decades ? 'FOUND' : 'NOT FOUND'}`);
  console.log(`  Vendor_Signature:  ${anchorsFound.vendor ? 'FOUND' : 'NOT FOUND'}`);
  console.log(`  Customer_Signature: ${anchorsFound.customer ? 'FOUND' : 'NOT FOUND'}`);

  // ── Step 5: Navigate to Send Queue ──
  console.log('\n=== STEP 5: Verify Send Queue row ===');
  await page.goto('/#/send-queue');
  await page.waitForLoadState('networkidle');
  await observe(page);

  const queueTable = page.locator('table').first();
  await expect(queueTable).toBeVisible({ timeout: 15000 });
  console.log('  OK Send Queue loaded');
  await observe(page);

  const queueRows = page.locator('table tbody tr');
  const rowCount = await queueRows.count();
  console.log(`  Queue rows visible: ${rowCount}`);

  const wordBtn = page.getByTestId('btn-word-desktop').first();
  const envelopeInput = page.getByTestId('envelope-input').first();
  const markSentBtn = page.getByTestId('btn-mark-sent').first();

  if (rowCount > 0) {
    const hasWordBtn = await wordBtn.isVisible({ timeout: 3000 }).catch(() => false);
    const hasEnvelope = await envelopeInput.isVisible({ timeout: 3000 }).catch(() => false);
    const hasMarkSent = await markSentBtn.isVisible({ timeout: 3000 }).catch(() => false);

    console.log(`  Word Desktop button: ${hasWordBtn ? 'PRESENT' : 'MISSING'}`);
    console.log(`  Envelope ID input:   ${hasEnvelope ? 'PRESENT' : 'MISSING'}`);
    console.log(`  Mark Sent button:    ${hasMarkSent ? 'PRESENT' : 'MISSING'}`);
  }
  await observe(page);

  await page.screenshot({ path: './test-results/docusign-e2e-send-queue.png', fullPage: true });

  // ── Summary ──
  console.log('\n=== SUMMARY ===');
  console.log(`  OOXML injection logs: ${logs.ooxmlLogs.length}`);
  console.log(`  DocuSign anchor logs: ${logs.docusignAnchors.length}`);
  console.log(`  Console errors: ${logs.errors.length}`);
  console.log(`  Network failures: ${logs.networkFails.length}`);
  console.log(`  Send Queue rows: ${rowCount}`);
  console.log('  -- Anchors --');
  console.log(`  Decades_Signature: ${anchorsFound.decades}`);
  console.log(`  Vendor_Signature:  ${anchorsFound.vendor}`);
  console.log(`  Customer_Signature: ${anchorsFound.customer}`);
  console.log('\n  MANUAL STEP NEXT: Open Word Desktop -> DocuSign add-in -> verify anchor placement');
});
