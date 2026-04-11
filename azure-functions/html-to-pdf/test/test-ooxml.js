const fs = require('fs');
const JSZip = require('jszip');

// Load a real template
const templatePath = 'C:/dcfg/tmp/contracts_extracted/Decades-Management Services Agreement.docx';
const templateBuffer = fs.readFileSync(templatePath);
const templateBase64 = templateBuffer.toString('base64');

// Build field map from the handoff spec patterns
const field_map = [
  { marker_type: 'highlight', placeholder: "Today's Date", value: '2026-04-07T00:00:00Z', format_hint: 'date' },
  { marker_type: 'highlight', placeholder: 'LEGAL VENDOR NAME', value: 'ABC Plumbing Services, LLC', format_hint: null },
  { marker_type: 'highlight', placeholder: 'Customer Name', value: 'Bancroft, A New Jersey Nonprofit Corporation', format_hint: null },
  { marker_type: 'highlight', placeholder: 'Vendor Name', value: 'ABC Plumbing Services, LLC', format_hint: null },
  { marker_type: 'content-control', tag: 'contract_contractor_legal_name', value: 'ABC Plumbing Services, LLC', format_hint: null },
  { marker_type: 'content-control', tag: 'contract_client_name', value: 'Bancroft', format_hint: null },
  { marker_type: 'content-control', tag: 'contract_owner_contact', value: 'Joseph Cameron', format_hint: null },
  { marker_type: 'content-control', tag: 'contract_owner_title', value: 'Project Manager', format_hint: null },
  { marker_type: 'content-control', tag: 'contract_owner_email', value: 'jcameron@decades-cg.com', format_hint: null },
  { marker_type: 'content-control', tag: 'vendor_primary_contact', value: 'Michael Rodriguez', format_hint: null },
  { marker_type: 'content-control', tag: 'vendor_signer_title', value: 'Owner', format_hint: null },
  { marker_type: 'content-control', tag: 'vendor_email', value: 'mrodriguez@abcplumbing.com', format_hint: null },
  { marker_type: 'content-control', tag: 'vendor_phone', value: '(215) 555-0234', format_hint: null },
  { marker_type: 'content-control', tag: 'vendor_address', value: '456 Industrial Blvd, King of Prussia, PA 19406', format_hint: null },
  { marker_type: 'content-control', tag: 'msa_effective_date', value: '2025-01-15T00:00:00Z', format_hint: 'date' },
  { marker_type: 'content-control', tag: 'msa_expiration_date', value: '2026-01-15T00:00:00Z', format_hint: 'date' },
];

// Simulate the Azure Function logic locally
async function run() {
  const zip = await JSZip.loadAsync(templateBuffer);

  // List all XML parts
  const parts = Object.keys(zip.files).filter(f =>
    f === 'word/document.xml' || f.match(/^word\/header\d+\.xml$/) || f.match(/^word\/footer\d+\.xml$/)
  );
  console.log('XML parts:', parts);

  // Count markers in the template
  const docXml = await zip.files['word/document.xml'].async('string');

  // Count content controls
  const ccTags = docXml.match(/w:tag\s+w:val="[^"]+"/g) || [];
  console.log(`Content controls: ${ccTags.length}`);
  ccTags.forEach(t => console.log(`  ${t}`));

  // Count highlights
  const hlCount = (docXml.match(/w:highlight\s+w:val="yellow"/g) || []).length;
  console.log(`Yellow highlighted runs: ${hlCount}`);

  // Count merge fields
  const mfCount = (docXml.match(/MERGEFIELD/g) || []).length;
  console.log(`Merge fields: ${mfCount}`);

  console.log('\nSimulating injection...');

  // Simple test: try content control injection on document.xml
  let xml = docXml;
  let totalInjected = 0;

  for (const field of field_map) {
    if (field.marker_type === 'content-control' && field.tag) {
      const tagPattern = new RegExp(
        `(<w:sdt>\\s*<w:sdtPr>[\\s\\S]*?<w:tag\\s+w:val="${field.tag}"\\s*/>` +
        `[\\s\\S]*?<w:sdtContent>)([\\s\\S]*?)(</w:sdtContent>\\s*</w:sdt>)`,
        'g'
      );
      let found = false;
      xml = xml.replace(tagPattern, (match, before, content, after) => {
        found = true;
        totalInjected++;
        const rPrMatch = content.match(/<w:rPr>([\s\S]*?)<\/w:rPr>/);
        const rPr = rPrMatch ? `<w:rPr>${rPrMatch[1]}</w:rPr>` : '';
        const val = field.value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        return before + `<w:r>${rPr}<w:t xml:space="preserve">${val}</w:t></w:r>` + after;
      });
      console.log(`  ${field.tag}: ${found ? 'INJECTED' : 'not found'}`);
    }

    if (field.marker_type === 'highlight' && field.placeholder) {
      const hlRegex = /w:highlight\s+w:val="yellow"/;
      if (hlRegex.test(xml)) {
        console.log(`  highlight "${field.placeholder}": FOUND highlights in doc`);
      } else {
        console.log(`  highlight "${field.placeholder}": no yellow highlights in doc`);
      }
    }
  }

  // Save the modified document
  zip.file('word/document.xml', xml);
  const output = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  const outPath = 'C:/dcfg/tmp/v4_processed/contracts/MSA_INJECTED_TEST.docx';
  fs.writeFileSync(outPath, output);
  console.log(`\nOutput: ${outPath} (${output.length} bytes)`);
  console.log(`Fields injected: ${totalInjected}`);
}

run().catch(console.error);
