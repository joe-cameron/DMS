const JSZip = require('jszip');
const fs = require('fs');
const path = require('path');

const docsDir = 'C:/dcfg/scratch/docs';

// Map to the latest E2E run files (MOVWZS0E / MOVX tags)
const docs = [
  { label: 'Ban-ExhA-Auto', file: 'Bancroft-WO268570-2026-05-07.docx' },
  { label: 'Ban-ExhA-Var',  file: 'Bancroft-WO260722-2026-05-07.docx' },
  { label: 'Ban-BlanketWO', file: 'Bancroft-WO263489-2026-05-07.docx' },
  { label: 'Ban-VA',        file: 'Bancroft-DRAFT-2026-05-07.docx' },
  { label: 'Dec-WO',        file: 'PennReach-WO261329-2026-05-07.docx' },
  { label: 'Dec-VA',        file: 'PennReach-DRAFT-2026-05-07.docx' },
  { label: 'Dec-Amendment',  file: 'PennReach-DRAFT-A1-2026-05-07.docx' },
  // Bancroft Amendment not in downloads — checking alternates
  { label: 'Ban-Amendment',  file: 'Bancroft-WO264291-2026-05-07.docx', alt: true },
  // MSA proposals (latest MOVX tags)
  { label: 'MSA-PkgB',      file: 'PennReach---Extended---2026-05-07-MOVX0O9N.docx' },
  { label: 'MSA-PkgC',      file: 'The-Arc-Mercer---Premium---2026-05-07-MOVX14BC.docx' },
];

// Check for Bancroft Amendment specifically
const banAmendment = fs.readdirSync(docsDir).find(f => f.startsWith('Bancroft-DRAFT-A1'));
if (banAmendment) {
  const idx = docs.findIndex(d => d.label === 'Ban-Amendment');
  docs[idx] = { label: 'Ban-Amendment', file: banAmendment };
}

// Check for Bancroft Essential MSA
const banMsa = fs.readdirSync(docsDir).find(f => f.includes('Essential') && f.includes('MOVX'));
if (banMsa) docs.push({ label: 'MSA-PkgA', file: banMsa });

async function inspectDoc(label, filePath) {
  if (!fs.existsSync(filePath)) {
    return { label, status: 'MISSING', size: 0, yellowCount: 0, sdtCount: 0, issues: ['File not found'] };
  }

  const data = fs.readFileSync(filePath);
  const size = data.length;
  const zip = await JSZip.loadAsync(data);
  const docXml = await zip.file('word/document.xml')?.async('string');

  if (!docXml) {
    return { label, status: 'ERROR', size, yellowCount: 0, sdtCount: 0, issues: ['No word/document.xml'] };
  }

  const plainText = docXml.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
  const issues = [];

  // 1. Yellow highlights
  const yellowMatches = docXml.match(/<w:highlight\s+w:val="yellow"\s*\/>/gi) || [];
  const yellowCount = yellowMatches.length;

  // Get text near each yellow highlight
  const yellowTexts = [];
  if (yellowCount > 0) {
    const pattern = /<w:highlight\s+w:val="yellow"\s*\/>/gi;
    let m;
    while ((m = pattern.exec(docXml)) !== null) {
      const start = Math.max(0, m.index - 400);
      const end = Math.min(docXml.length, m.index + 400);
      const ctx = docXml.substring(start, end);
      const texts = (ctx.match(/<w:t[^>]*>([^<]+)<\/w:t>/g) || [])
        .map(t => t.replace(/<[^>]+>/g, '').trim())
        .filter(Boolean);
      yellowTexts.push(texts.join(' | '));
    }
  }

  // 2. Content controls remaining
  const sdtCount = (docXml.match(/<w:sdt>/g) || []).length;

  // 3. Unprocessed template tags
  const doubleBrace = plainText.match(/\{\{[A-Za-z_]+\}\}/g) || [];
  const angleBrace = plainText.match(/<<[A-Za-z_]+>>/g) || [];
  const backslashTags = plainText.match(/\\[A-Za-z_]+\\/g) || [];

  if (doubleBrace.length > 0) issues.push(`{{tags}}: ${doubleBrace.join(', ')}`);
  if (angleBrace.length > 0) issues.push(`<<tags>>: ${angleBrace.join(', ')}`);
  if (backslashTags.length > 0) {
    // Filter out known DocuSign anchors
    const nonDocusign = backslashTags.filter(t => !t.match(/Signature|DateSigned|InitialHere/i));
    if (nonDocusign.length > 0) issues.push(`\\tags\\: ${nonDocusign.join(', ')}`);
  }

  // 4. Check for empty runs with highlight (placeholder text that's blank)
  const emptyHighlightRuns = docXml.match(/<w:r>[\s\S]*?<w:highlight\s+w:val="yellow"[\s\S]*?<w:t[^>]*>\s*<\/w:t>/gi) || [];
  if (emptyHighlightRuns.length > 0) issues.push(`${emptyHighlightRuns.length} empty yellow-highlighted runs`);

  const status = yellowCount === 0 && sdtCount === 0 && issues.length === 0 ? 'PASS' : 'CHECK';

  return { label, status, size, yellowCount, yellowTexts, sdtCount, issues };
}

async function main() {
  console.log(`Inspecting ${docs.length} documents\n`);
  console.log('Label              | Size    | Yellow | SDT | Status | Issues');
  console.log('-------------------|---------|--------|-----|--------|-------');

  const results = [];
  for (const doc of docs) {
    const filePath = path.join(docsDir, doc.file);
    const r = await inspectDoc(doc.label, filePath);
    results.push(r);

    const sizeStr = (r.size / 1024).toFixed(0) + 'KB';
    console.log(
      `${r.label.padEnd(19)}| ${sizeStr.padEnd(8)}| ${String(r.yellowCount).padEnd(7)}| ${String(r.sdtCount).padEnd(4)}| ${r.status.padEnd(7)}| ${r.issues.join('; ') || 'clean'}`
    );
  }

  // Detail on yellow highlights
  console.log('\n=== YELLOW HIGHLIGHT DETAILS ===');
  for (const r of results) {
    if (r.yellowCount > 0 && r.yellowTexts) {
      console.log(`\n  ${r.label} (${r.yellowCount} yellows):`);
      r.yellowTexts.forEach((t, i) => console.log(`    #${i + 1}: "${t.substring(0, 120)}"`));
    }
  }

  // Summary
  const pass = results.filter(r => r.status === 'PASS').length;
  const check = results.filter(r => r.status === 'CHECK').length;
  const missing = results.filter(r => r.status === 'MISSING').length;
  console.log(`\n=== SUMMARY: ${pass} PASS, ${check} CHECK, ${missing} MISSING out of ${results.length} ===`);

  fs.writeFileSync('C:/dcfg/scratch/doc-inspection-results.json', JSON.stringify(results, null, 2));
  console.log('Results saved to scratch/doc-inspection-results.json');
}

main().catch(console.error);
