const JSZip = require('jszip');
const fs = require('fs');

async function auditYellowTags(filePath) {
  const data = fs.readFileSync(filePath);
  const zip = await JSZip.loadAsync(data);
  const parts = Object.keys(zip.files).filter(n =>
    n === 'word/document.xml' || /^word\/(header|footer)\d+\.xml$/.test(n));

  const tags = [];
  for (const partName of parts) {
    const xml = await zip.files[partName].async('string');
    // Walk paragraphs, find yellow-highlighted run groups
    const paragraphs = xml.match(/<w:p[\s>][\s\S]*?<\/w:p>/g) || [];
    for (const para of paragraphs) {
      const runs = para.match(/<w:r[\s>][\s\S]*?<\/w:r>/g) || [];
      let accText = '';
      let inYellow = false;
      for (const run of runs) {
        const isYellow = /w:highlight\s+w:val="yellow"/i.test(run);
        const textParts = run.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g) || [];
        const text = textParts.map(t => t.replace(/<[^>]+>/g, '')).join('');
        if (isYellow) {
          accText += text;
          inYellow = true;
        } else if (inYellow && accText.trim()) {
          tags.push({ part: partName.replace('word/', ''), text: accText.trim() });
          accText = '';
          inYellow = false;
        }
      }
      if (inYellow && accText.trim()) {
        tags.push({ part: partName.replace('word/', ''), text: accText.trim() });
      }
    }
  }
  return tags;
}

async function main() {
  const files = [
    'Decades-Vendor-Agreement.docx',
    'Decades-Workorder.docx',
  ];

  for (const file of files) {
    const filePath = `C:/dcfg/Templates/corrected/${file}`;
    if (!fs.existsSync(filePath)) { console.log(`NOT FOUND: ${file}`); continue; }

    const tags = await auditYellowTags(filePath);
    console.log(`=== ${file} (${tags.length} yellow tags) ===`);
    tags.forEach((t, i) => console.log(`  ${i + 1}. "${t.text}" [${t.part}]`));
    console.log('');
  }
}

main().catch(console.error);
