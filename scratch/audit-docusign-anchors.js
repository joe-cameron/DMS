const JSZip = require('jszip');
const fs = require('fs');
const path = require('path');

const docsDir = 'C:/dcfg/scratch/docs';

const files = fs.readdirSync(docsDir).filter(f => f.endsWith('.docx') && fs.statSync(path.join(docsDir, f)).size > 0);

async function inspectAnchors(filePath, label) {
  const data = fs.readFileSync(filePath);
  const zip = await JSZip.loadAsync(data);
  const parts = Object.keys(zip.files).filter(n => n === 'word/document.xml' || /^word\/(header|footer)\d+\.xml$/.test(n));

  const anchors = [];

  for (const partName of parts) {
    const xml = await zip.files[partName].async('string');

    // Find DocuSign-style anchors: runs with white color + very small size containing backslash text
    // Pattern: <w:rPr> with color=FFFFFF and sz=2, followed by <w:t> with backslash content
    const runRegex = /<w:r[\s>][\s\S]*?<\/w:r>/g;
    let m;
    while ((m = runRegex.exec(xml)) !== null) {
      const run = m[0];
      const isWhite = /w:color\s+w:val="FFFFFF"/i.test(run);
      const isSmall = /w:sz\s+w:val="[12]"/i.test(run);
      const textMatches = run.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g) || [];
      const text = textMatches.map(t => t.replace(/<[^>]+>/g, '')).join('');

      if (text && (isWhite || text.includes('\\'))) {
        anchors.push({
          part: partName.replace('word/', ''),
          text: text.trim(),
          isWhite,
          isSmall,
          isAnchor: isWhite && isSmall,
        });
      }
    }

    // Also find any backslash-delimited text that looks like anchors even if not white
    const plainText = xml.replace(/<[^>]+>/g, ' ');
    const anchorPattern = /\\[A-Za-z_]+\\/g;
    let am;
    while ((am = anchorPattern.exec(plainText)) !== null) {
      const existing = anchors.find(a => a.text.includes(am[0]));
      if (!existing) {
        anchors.push({
          part: 'plaintext-scan',
          text: am[0],
          isWhite: false,
          isSmall: false,
          isAnchor: false,
          note: 'visible in document text (not hidden)'
        });
      }
    }
  }

  return anchors;
}

async function main() {
  console.log(`Scanning ${files.length} documents for DocuSign anchors\n`);

  for (const file of files) {
    const filePath = path.join(docsDir, file);
    const anchors = await inspectAnchors(filePath, file);

    console.log(`=== ${file} ===`);
    if (anchors.length === 0) {
      console.log('  No anchors found\n');
      continue;
    }

    for (const a of anchors) {
      const status = a.isAnchor ? 'HIDDEN (white 1pt)' : a.isWhite ? 'WHITE but large' : a.note || 'VISIBLE';
      console.log(`  "${a.text}" [${a.part}] — ${status}`);
    }
    console.log('');
  }

  // Summary: unique anchor strings across all docs
  console.log('=== UNIQUE ANCHOR STRINGS ACROSS ALL DOCS ===');
  const allAnchors = new Map();
  for (const file of files) {
    const filePath = path.join(docsDir, file);
    const anchors = await inspectAnchors(filePath, file);
    for (const a of anchors) {
      const key = a.text;
      if (!allAnchors.has(key)) allAnchors.set(key, { count: 0, docs: [], hidden: a.isAnchor });
      allAnchors.get(key).count++;
      allAnchors.get(key).docs.push(file.replace(/-2026-05-07\.docx/, ''));
    }
  }
  for (const [anchor, info] of allAnchors) {
    console.log(`  "${anchor}" — ${info.hidden ? 'HIDDEN' : 'VISIBLE'} — in ${info.docs.join(', ')}`);
  }
}

main().catch(console.error);
