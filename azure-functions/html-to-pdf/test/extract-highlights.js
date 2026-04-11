const fs = require('fs');
const path = require('path');
const JSZip = require('jszip');

const CONTRACTS_DIR = 'C:/dcfg/tmp/contracts_extracted';

async function extractHighlights(docxPath) {
  const name = path.basename(docxPath, '.docx');
  const buffer = fs.readFileSync(docxPath);
  const zip = await JSZip.loadAsync(buffer);
  const xml = await zip.files['word/document.xml'].async('string');

  // Extract highlighted text by walking paragraphs
  const highlights = [];
  const pRegex = /<w:p[\s>][\s\S]*?<\/w:p>/g;
  let pMatch;

  while ((pMatch = pRegex.exec(xml)) !== null) {
    const pXml = pMatch[0];
    const runRegex = /<w:r[\s>][\s\S]*?<\/w:r>/g;
    let runMatch;
    let accText = '';
    let inHighlight = false;

    while ((runMatch = runRegex.exec(pXml)) !== null) {
      const runXml = runMatch[0];
      const isHL = /w:highlight\s+w:val="yellow"/.test(runXml);
      const textMatch = runXml.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/);
      const text = textMatch ? textMatch[1] : '';

      if (isHL) {
        accText += text;
        inHighlight = true;
      } else {
        if (inHighlight && accText.trim()) {
          highlights.push(accText.trim());
        }
        accText = '';
        inHighlight = false;
      }
    }
    // Flush at end of paragraph
    if (inHighlight && accText.trim()) {
      highlights.push(accText.trim());
    }
  }

  // Also extract content control tags
  const ccTags = [];
  const ccRegex = /w:tag\s+w:val="([^"]+)"/g;
  let ccMatch;
  while ((ccMatch = ccRegex.exec(xml)) !== null) {
    if (!ccMatch[1].startsWith('goog_')) ccTags.push(ccMatch[1]);
  }

  return { name, highlights: [...new Set(highlights)], ccTags: [...new Set(ccTags)] };
}

async function run() {
  const files = fs.readdirSync(CONTRACTS_DIR).filter(f => f.endsWith('.docx'));

  for (const file of files) {
    const result = await extractHighlights(path.join(CONTRACTS_DIR, file));
    console.log(`\n=== ${result.name} ===`);
    if (result.highlights.length) {
      console.log(`  Highlights (${result.highlights.length}):`);
      result.highlights.forEach(h => console.log(`    "${h}"`));
    }
    if (result.ccTags.length) {
      console.log(`  Content Controls (${result.ccTags.length}):`);
      result.ccTags.forEach(t => console.log(`    ${t}`));
    }
    if (!result.highlights.length && !result.ccTags.length) {
      console.log('  No markers found');
    }
  }

  // Also check the Templates library versions
  const templatesDir = 'C:/DCFG/Templates';
  const tFiles = fs.readdirSync(templatesDir).filter(f => f.endsWith('.docx') && !f.startsWith('~'));
  console.log('\n\n========== TEMPLATES LIBRARY ==========');
  for (const file of tFiles) {
    const result = await extractHighlights(path.join(templatesDir, file));
    console.log(`\n=== ${result.name} ===`);
    if (result.highlights.length) {
      console.log(`  Highlights (${result.highlights.length}):`);
      result.highlights.forEach(h => console.log(`    "${h}"`));
    }
    if (result.ccTags.length) {
      console.log(`  Content Controls (${result.ccTags.length}):`);
      result.ccTags.forEach(t => console.log(`    ${t}`));
    }
    if (!result.highlights.length && !result.ccTags.length) {
      console.log('  No markers found');
    }
  }
}

run().catch(console.error);
