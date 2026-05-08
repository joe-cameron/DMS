/**
 * Deep inspect a single .docx — find all yellow highlights and content controls,
 * extract text around them, and identify which template fields weren't replaced.
 */
const JSZip = require('jszip');
const fs = require('fs');

const filePath = process.argv[2] || 'C:/dcfg/nora/test-results/DOC-Ban-ExhA-Var.docx';

async function main() {
  const data = fs.readFileSync(filePath);
  const zip = await JSZip.loadAsync(data);
  const docXml = await zip.file('word/document.xml')?.async('string');
  if (!docXml) { console.log('ERROR: No word/document.xml'); return; }

  console.log(`File: ${filePath} (${data.length} bytes)`);
  console.log(`document.xml: ${docXml.length} chars\n`);

  // 1. Find all yellow highlights with surrounding context
  console.log('=== YELLOW HIGHLIGHTS ===');
  const yellowPattern = /<w:highlight\s+w:val="yellow"\s*\/>/gi;
  let match;
  let yellowCount = 0;
  while ((match = yellowPattern.exec(docXml)) !== null) {
    yellowCount++;
    // Get 500 chars of context around the match
    const start = Math.max(0, match.index - 300);
    const end = Math.min(docXml.length, match.index + 300);
    const context = docXml.substring(start, end);
    // Extract text runs near this highlight
    const textMatches = context.match(/<w:t[^>]*>([^<]*)<\/w:t>/g) || [];
    const texts = textMatches.map(t => t.replace(/<[^>]+>/g, '')).filter(Boolean);
    console.log(`  #${yellowCount}: "${texts.join(' | ')}"`);
  }
  console.log(`  Total yellow highlights: ${yellowCount}\n`);

  // 2. Find content controls (sdt elements) that might still have placeholder text
  console.log('=== CONTENT CONTROLS (sdt) ===');
  const sdtPattern = /<w:sdt>[\s\S]*?<\/w:sdt>/g;
  let sdtMatch;
  let sdtCount = 0;
  while ((sdtMatch = sdtPattern.exec(docXml)) !== null) {
    sdtCount++;
    const sdt = sdtMatch[0];
    // Get the tag/alias
    const tagMatch = sdt.match(/<w:tag\s+w:val="([^"]+)"/);
    const aliasMatch = sdt.match(/<w:alias\s+w:val="([^"]+)"/);
    const tag = tagMatch ? tagMatch[1] : '';
    const alias = aliasMatch ? aliasMatch[1] : '';
    // Get text content
    const textParts = sdt.match(/<w:t[^>]*>([^<]*)<\/w:t>/g) || [];
    const text = textParts.map(t => t.replace(/<[^>]+>/g, '')).join('');
    // Check for placeholder indicator
    const isPlaceholder = sdt.includes('w:showingPlcHdr') || sdt.includes('showingPlcHdr');
    const hasYellow = sdt.includes('w:highlight') && sdt.includes('yellow');
    console.log(`  #${sdtCount}: tag="${tag}" alias="${alias}" text="${text.substring(0, 60)}" placeholder=${isPlaceholder} yellow=${hasYellow}`);
  }
  console.log(`  Total content controls: ${sdtCount}\n`);

  // 3. Search for specific E2E values
  console.log('=== VALUE SEARCH ===');
  const plainText = docXml.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ');
  const searchTerms = [
    'MOVWZS0E', 'CSIGN', 'VSIGN', 'CTITLE', 'VTITLE',
    '260722', '3800', '3,800', 'South Drive', '1 South',
    '1-800-GOT-JUNK', 'Bancroft', 'Exhibit A',
    'Concrete', 'Masonry',
  ];
  for (const term of searchTerms) {
    const found = plainText.includes(term) || docXml.includes(term);
    console.log(`  ${found ? 'FOUND' : 'MISS '}: "${term}"`);
  }

  // 4. Extract ALL text content in reading order
  console.log('\n=== FULL DOCUMENT TEXT (first 3000 chars) ===');
  // Get text in order from w:t elements
  const allText = (docXml.match(/<w:t[^>]*>([^<]*)<\/w:t>/g) || [])
    .map(t => t.replace(/<[^>]+>/g, ''))
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
  console.log(allText.substring(0, 3000));
}

main().catch(console.error);
