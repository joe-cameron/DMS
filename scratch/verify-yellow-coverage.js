const JSZip = require('jszip');
const fs = require('fs');

// Field mappings from the Dataverse audit (copy from the PS output)
const mappings = {
  'Decades-Vendor-Agreement.docx': {
    '\\Contractor_Signature\\': '[DOCUSIGN:\\Vendor_Signature\\]',
    '\\Decades_Signature\\': '[DOCUSIGN:\\Decades_Signature\\]',
    'Current Year': '[SYSTEM:TODAY_YEAR]',
    'Day of Month': '[SYSTEM:TODAY_DAY]',
    'Decades Printed Name': '[SIGNATURE:DECADES_NAME]',
    'Decades Title': '[SIGNATURE:DECADES_TITLE]',
    'Month Name': '[SYSTEM:TODAY_MONTH]',
    'Owner/Decades Printed Name': '[SIGNATURE:OWNER_NAME]',
    'Owner/Decades Title': '[SIGNATURE:OWNER_TITLE]',
    'Vendor Address Block': '[COMPOSITE:vendor_address_block]',
    'Vendor Legal Name': 'dcfg_vendor.dcfg_legal_name',
    'Vendor Signer Name': 'dcfg_vendor.dcfg_signer_name',
    'Vendor Signer Title': 'dcfg_vendor.dcfg_signer_title',
  },
  'Decades-Workorder.docx': {
    // From Decades Workorder Amendment type 100000007 mappings
    '\\Decades_Signature\\ _': '[DOCUSIGN:\\Decades_Signature\\]',
    '_ Decades Title __': '[SIGNATURE:DECADES_TITLE]',
    'Amendment Lines': '[BLOCK:amendment_lines]',
    'Amendment Number': 'dcfg_amendment_sequence',
    'Client Name': 'dcfg_customer.dcfg_name',
    'Contractor Printed Name': 'dcfg_vendor.dcfg_signer_name',
    'Contractor Title': 'dcfg_vendor.dcfg_signer_title',
    'Customer Contact': '[COMPOSITE:customer_contract_contact]',
    'Customer Contact Email': 'dcfg_customer.dcfg_primary_contact_email',
    'Customer Contact Name': 'dcfg_customer.dcfg_primary_contact_name',
    'Customer Contact Phone': 'dcfg_customer.dcfg_primary_contact_phone',
    'Customer Date Signed': '[DOCUSIGN:\\Customer_DateSigned\\]',
    'Customer EMail': 'dcfg_customer.dcfg_primary_contact_email',
    'Customer Phone': 'dcfg_customer.dcfg_primary_contact_phone',
    'Customer Printed Name': 'dcfg_customer.dcfg_name',
    'Customer Title': 'dcfg_customer.dcfg_primary_contact_title',
    'Decades Printed Name': '[SIGNATURE:DECADES_NAME]',
    'End Date': 'dcfg_end_date',
    'Hour of Operations': null, // NO PATH
    'Main Contract Date': 'dcfg_contract_date',
    'MSA Date': 'dcfg_msa.createdon',
    'Purchase Order': 'dcfg_po_number',
    'Service Location Description': 'dcfg_property.dcfg_name',
    'Start Date': 'dcfg_start_date',
    'Today\'s Date': '[SYSTEM:TODAY]',
    'Vendor Address Block': '[COMPOSITE:vendor_address_block]',
    'Vendor Contact Info': '[COMPOSITE:vendor_contact]',
    'Vendor Email': 'dcfg_vendor.dcfg_email',
    'Vendor Legal Name': 'dcfg_vendor.dcfg_legal_name',
    'Vendor Name': 'dcfg_vendor.dcfg_legal_name',
    'Vendor Phone': 'dcfg_signer_title', // looks wrong - phone mapped to title?
    'Vendor Signature\\"': '[DOCUSIGN:\\Vendor_Signature\\]',
    'Vendor Signer Name': 'dcfg_signer_printed',
    'Vendor Signer Title': 'dcfg_signer_title',
    'Vendor_DateSigned': '[DOCUSIGN:\\Vendor_DateSigned\\]',
    'WO Number': 'dcfg_contract_number',
    'Work Order Date': 'dcfg_contract_date',
  }
};

async function getYellowTags(filePath) {
  const data = fs.readFileSync(filePath);
  const zip = await JSZip.loadAsync(data);
  const xml = await zip.file('word/document.xml').async('string');
  const tags = [];
  const paragraphs = xml.match(/<w:p[\s>][\s\S]*?<\/w:p>/g) || [];
  for (const para of paragraphs) {
    const runs = para.match(/<w:r[\s>][\s\S]*?<\/w:r>/g) || [];
    let accText = '';
    let inYellow = false;
    for (const run of runs) {
      const isYellow = /w:highlight\s+w:val="yellow"/i.test(run);
      const textParts = run.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g) || [];
      const text = textParts.map(t => t.replace(/<[^>]+>/g, '')).join('');
      if (isYellow) { accText += text; inYellow = true; }
      else if (inYellow && accText.trim()) { tags.push(accText.trim()); accText = ''; inYellow = false; }
    }
    if (inYellow && accText.trim()) tags.push(accText.trim());
  }
  return tags;
}

async function main() {
  const files = ['Decades-Vendor-Agreement.docx', 'Decades-Workorder.docx'];

  for (const file of files) {
    const filePath = `C:/dcfg/Templates/corrected/${file}`;
    const yellowTags = await getYellowTags(filePath);
    const fieldMap = mappings[file] || {};

    console.log(`=== ${file} ===`);
    for (const tag of yellowTags) {
      // Find matching mapping (exact or fuzzy)
      const exact = fieldMap[tag];
      if (exact === null) {
        console.log(`  ❌ NO PATH: "${tag}"`);
      } else if (exact) {
        console.log(`  ✅ "${tag}" → ${exact}`);
      } else {
        // Fuzzy match
        const fuzzy = Object.keys(fieldMap).find(k =>
          k.toLowerCase().replace(/\s+/g, '') === tag.toLowerCase().replace(/\s+/g, '') ||
          tag.includes(k) || k.includes(tag));
        if (fuzzy) {
          console.log(`  ✅ "${tag}" ≈ "${fuzzy}" → ${fieldMap[fuzzy]}`);
        } else {
          console.log(`  ⚠️  UNMAPPED: "${tag}"`);
        }
      }
    }
    console.log('');
  }
}

main().catch(console.error);
