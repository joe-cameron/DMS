const fs = require('fs');
const JSZip = require('jszip');

async function run() {
  const templatePath = 'C:/dcfg/tmp/contracts_extracted/Decades-Management Services Agreement.docx';
  const buffer = fs.readFileSync(templatePath);
  const zip = await JSZip.loadAsync(buffer);

  const field_map = [
    { placeholder: 'EFFECTIVE DATE', value: 'April 7, 2026' },
    { placeholder: 'NEW CUSTOMER NAME', value: 'Bancroft, A New Jersey Nonprofit Corporation' },
    { placeholder: 'one (1) year', value: 'two (2) years' },
    { placeholder: 'Customer Organization name', value: 'Bancroft' },
    { placeholder: 'Attn: Contact Name', value: 'Attn: William B. Bancroft III' },
    { placeholder: 'Street Adress', value: '425 N. King Street' },
    { placeholder: 'City, State zip code', value: 'Mt. Holly, NJ 08060' },
    { placeholder: 'Enter Name', value: 'Joseph Cameron' },
    { placeholder: 'Enter Title', value: 'Project Manager' },
    { placeholder: 'Title', value: 'Director of Operations' },
  ];

  // Process document.xml + all headers/footers
  const parts = Object.keys(zip.files).filter(f =>
    f === 'word/document.xml' || f.match(/^word\/header\d+\.xml$/) || f.match(/^word\/footer\d+\.xml$/)
  );

  let totalInjected = 0;

  for (const part of parts) {
    let xml = await zip.files[part].async('string');

    for (const field of field_map) {
      const result = injectHighlight(xml, field.placeholder, field.value);
      xml = result.xml;
      if (result.count > 0) {
        console.log(`  [${part}] "${field.placeholder}" → "${field.value}" (${result.count}x)`);
        totalInjected += result.count;
      }
    }

    zip.file(part, xml);
  }

  const output = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  const outPath = 'C:/dcfg/tmp/v4_processed/contracts/MSA_INJECTED.docx';
  fs.writeFileSync(outPath, output);
  console.log(`\nTotal fields injected: ${totalInjected}`);
  console.log(`Output: ${outPath} (${output.length} bytes)`);
  console.log('Open in Word to verify formatting.');
}

function injectHighlight(xml, placeholder, value) {
  const normalizedPlaceholder = placeholder.trim().replace(/\s+/g, ' ').toLowerCase();
  let count = 0;

  const newXml = xml.replace(/<w:p[\s>][\s\S]*?<\/w:p>/g, (paragraph) => {
    const runRegex = /<w:r[\s>][\s\S]*?<\/w:r>/g;
    let runMatch;
    const runs = [];
    let lastIdx = 0;
    const parts = [];

    // Collect all runs with positions
    while ((runMatch = runRegex.exec(paragraph)) !== null) {
      if (runMatch.index > lastIdx) {
        parts.push({ type: 'raw', text: paragraph.substring(lastIdx, runMatch.index) });
      }
      const rXml = runMatch[0];
      const isHL = /w:highlight\s+w:val="yellow"/.test(rXml);
      const textMatch = rXml.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/);
      const text = textMatch ? textMatch[1] : '';
      const rPrMatch = rXml.match(/<w:rPr>([\s\S]*?)<\/w:rPr>/);

      parts.push({ type: 'run', xml: rXml, highlighted: isHL, text, rPr: rPrMatch ? rPrMatch[1] : '' });
      lastIdx = runMatch.index + rXml.length;
    }
    if (lastIdx < paragraph.length) {
      parts.push({ type: 'raw', text: paragraph.substring(lastIdx) });
    }

    // Find consecutive highlighted runs matching placeholder
    let modified = false;
    const newParts = [];
    let i = 0;

    while (i < parts.length) {
      if (parts[i].type === 'run' && parts[i].highlighted) {
        let accText = '';
        let start = i;
        let firstRPr = parts[i].rPr;

        while (i < parts.length && parts[i].type === 'run' && parts[i].highlighted) {
          accText += parts[i].text;
          i++;
        }

        const normalizedAcc = accText.trim().replace(/\s+/g, ' ').toLowerCase();
        if (normalizedAcc === normalizedPlaceholder) {
          count++;
          modified = true;
          // Remove highlight, keep other formatting
          let cleanRPr = firstRPr.replace(/<w:highlight[^/]*\/>/g, '');
          const rPrTag = cleanRPr.trim() ? `<w:rPr>${cleanRPr}</w:rPr>` : '';
          newParts.push({
            type: 'raw',
            text: `<w:r>${rPrTag}<w:t xml:space="preserve">${escapeXml(value)}</w:t></w:r>`
          });
        } else {
          // Not a match, keep originals
          for (let j = start; j < i; j++) newParts.push(parts[j]);
        }
      } else {
        newParts.push(parts[i]);
        i++;
      }
    }

    if (modified) {
      return newParts.map(p => p.type === 'raw' ? p.text : p.xml).join('');
    }
    return paragraph;
  });

  return { xml: newXml, count };
}

function escapeXml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

run().catch(console.error);
