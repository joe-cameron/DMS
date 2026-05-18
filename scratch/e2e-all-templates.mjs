import { readFileSync, writeFileSync } from 'fs';
const { injectTemplate } = await import('file:///C:/DCFG/spa/dcfg-shell/src/lib/ooxmlInject.js');
const { buildContractFieldMap } = await import('file:///C:/DCFG/spa/dcfg-shell/src/lib/contractDocGen.js');

const woContract = {
  dcfg_contract_number: "WO24168", dcfg_contract_type: 100000000, dcfg_contract_family: 100000000,
  dcfg_contractor_legal_name: "Lady Bug Pest Services", dcfg_contract_fee: 10350,
  dcfg_signer_printed: "Zoe Buckridee", dcfg_signer_title: "Commercial Accounts Specialist",
  dcfg_contractor_address: "474 North Ave East, Westfield NJ 07091",
  dcfg_contractor_phone: "908-317-8576", dcfg_contractor_email: "office@ladybugpest.com",
  dcfg_owner_contact: "Sarah Mitchell", dcfg_owner_title: "Director of Operations",
  dcfg_customer_site_contact: "Zoe Buckridee", dcfg_customer_site_phone: "908-342-2166",
  dcfg_customer_site_email: "office@ladybugpest.com",
  dcfg_decades_site_contact: "Eric Hadley", dcfg_decades_site_phone: "856-555-1234",
  dcfg_decades_site_email: "ehadley@decades-cg.com",
  dcfg_billing_city: "Westfield", dcfg_billing_state: "NJ", dcfg_billing_zip: "07091",
  dcfg_billing_address: "474 North Ave East",
  dcfg_msa_date: "2025-01-15", dcfg_msa_number: "MSA-2025-001",
  dcfg_work_hours: "Monday-Friday, 8:00 AM - 5:00 PM",
  dcfg_start_date: "2026-06-01", dcfg_end_date: "2027-05-31",
  dcfg_description_of_work: "Pest control services for all locations",
  dcfg_client_name: "Bancroft", dcfg_company: "Lady Bug Pest Services",
  dcfg_blanket_number: "BWO-2026-042",
  dcfg_contract_date: "2026-05-17",
  dcfg_amendment_sequence: 1, dcfg_po_number: "PO-2026-1234",
  dcfg_current_amount: 10350, dcfg_approved_amount: 12850,
  dcfg_change_amount: 2500, dcfg_original_amount: 10350,
  dcfg_current_properties_included: "Cherry Hill, Haddonfield, Moorestown",
  dcfg_service_description: "Monthly pest control inspections",
  dcfg_description_of_service: "Monthly pest control inspections and treatment",
};

const amendContract = { ...woContract, dcfg_contract_type: 100000001, dcfg_contract_number: "AMD-24168-01" };
const vaContract = { ...woContract, dcfg_contract_type: 100000002, dcfg_contract_number: "VA-2026-001", dcfg_contract_fee: 0 };
const decadesWoContract = { ...woContract, dcfg_contract_family: 100000001, dcfg_contract_number: "DWO-2026-001" };

const allFields = [
  { dcfg_source_text: "VENDOR NAME", dcfg_dataverse_path: "dcfg_contractor_legal_name" },
  { dcfg_source_text: "Vendor Legal Name", dcfg_dataverse_path: "dcfg_contractor_legal_name" },
  { dcfg_source_text: "Vendor Name", dcfg_dataverse_path: "dcfg_contractor_legal_name" },
  { dcfg_source_text: "Contractor Printed Name", dcfg_dataverse_path: "dcfg_signer_printed" },
  { dcfg_source_text: "Vendor Printed Name", dcfg_dataverse_path: "dcfg_signer_printed" },
  { dcfg_source_text: "Decades Printed Name", dcfg_dataverse_path: "dcfg_owner_contact" },
  { dcfg_source_text: "Contractor Title", dcfg_dataverse_path: "dcfg_signer_title" },
  { dcfg_source_text: "Vendor Title", dcfg_dataverse_path: "dcfg_signer_title" },
  { dcfg_source_text: "Decades Title", dcfg_dataverse_path: "dcfg_owner_title" },
  { dcfg_source_text: "Customer Contact Name", dcfg_dataverse_path: "dcfg_owner_contact" },
  { dcfg_source_text: "Customer Printed Name", dcfg_dataverse_path: "dcfg_owner_contact" },
  { dcfg_source_text: "Customer Title", dcfg_dataverse_path: "dcfg_owner_title" },
  { dcfg_source_text: "Tele#", dcfg_dataverse_path: "dcfg_contractor_phone" },
  { dcfg_source_text: "email address (Vendor)", dcfg_dataverse_path: "dcfg_contractor_email" },
  { dcfg_source_text: "email address", dcfg_dataverse_path: "dcfg_contractor_email" },
  { dcfg_source_text: "Vendor Street Address", dcfg_dataverse_path: "dcfg_contractor_address" },
  { dcfg_source_text: "Vendor Address", dcfg_dataverse_path: "dcfg_contractor_address" },
  { dcfg_source_text: "_________", dcfg_dataverse_path: "dcfg_contract_number" },
  { dcfg_source_text: "WO Number", dcfg_dataverse_path: "dcfg_contract_number" },
  { dcfg_source_text: "WorkOrder Number", dcfg_dataverse_path: "dcfg_contract_number" },
  { dcfg_source_text: "Amendment Number", dcfg_dataverse_path: "dcfg_contract_number" },
  { dcfg_source_text: "Contract Fee", dcfg_dataverse_path: "dcfg_contract_fee" },
  { dcfg_source_text: "Work Order Fee", dcfg_dataverse_path: "dcfg_contract_fee" },
  { dcfg_source_text: "Contract Value Dollars ($X.XX)", dcfg_dataverse_path: "dcfg_contract_fee" },
  { dcfg_source_text: "Contract Value", dcfg_dataverse_path: "dcfg_contract_fee" },
  { dcfg_source_text: "Today\u2019s Date", dcfg_dataverse_path: "[SYSTEM:TODAY]" },
  { dcfg_source_text: "MSA Date", dcfg_dataverse_path: "dcfg_msa_date" },
  { dcfg_source_text: "Work Order Date", dcfg_dataverse_path: "dcfg_contract_date" },
  { dcfg_source_text: "Original WorkOrder Date", dcfg_dataverse_path: "dcfg_contract_date" },
  { dcfg_source_text: "Contract Expiration Date", dcfg_dataverse_path: "dcfg_end_date" },
  { dcfg_source_text: "Work State Date", dcfg_dataverse_path: "dcfg_start_date" },
  { dcfg_source_text: "City, State, Zip Code", dcfg_dataverse_path: "[COMPOSITE:vendor_address_block]" },
  { dcfg_source_text: "Contact Name, Tele#", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Vendor Contact Info", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Description of Service", dcfg_dataverse_path: "dcfg_description_of_service" },
  { dcfg_source_text: "Locations", dcfg_dataverse_path: "dcfg_current_properties_included" },
  { dcfg_source_text: "Purchase Order", dcfg_dataverse_path: "dcfg_po_number" },
  { dcfg_source_text: "Service Location Description Hour of Operations", dcfg_dataverse_path: "dcfg_work_hours" },
  { dcfg_source_text: "Contractor Contact", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Vendor Signer Name", dcfg_dataverse_path: "dcfg_signer_printed" },
  { dcfg_source_text: "Vendor Signer Title", dcfg_dataverse_path: "dcfg_signer_title" },
  { dcfg_source_text: "Bancroft PO#", dcfg_dataverse_path: "dcfg_po_number" },
  { dcfg_source_text: "Vendor Contact", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
];

const tests = [
  { name: "ExhA-Auto", file: "Templates/corrected/Exhibit-A---Automated.docx", contract: woContract },
  { name: "ExhA-Var", file: "Templates/corrected/Exhibit-A---Variable.docx", contract: woContract },
  { name: "WO-Amendment", file: "Templates/corrected/Work-Order-Amendment.docx", contract: amendContract },
  { name: "Decades-WO", file: "Templates/corrected/Decades-Workorder.docx", contract: decadesWoContract },
  { name: "Bancroft-VA", file: "Templates/corrected/Bancroft-Vendor-Agreement.docx", contract: vaContract },
  { name: "Decades-VA", file: "Templates/corrected/Decades-Vendor-Agreement.docx", contract: vaContract },
];

for (const t of tests) {
  console.log(`\n=== ${t.name} ===`);
  const fieldMap = buildContractFieldMap(allFields, t.contract, null);
  const bin = readFileSync("C:/DCFG/" + t.file);
  const result = await injectTemplate(bin, fieldMap);
  const blob = result.blob;
  let buf;
  if (blob instanceof Uint8Array || blob instanceof ArrayBuffer) buf = Buffer.from(blob);
  else if (blob && typeof blob.arrayBuffer === 'function') buf = Buffer.from(await blob.arrayBuffer());
  else buf = Buffer.from(blob);
  const outPath = "C:/DCFG/scratch/e2e-" + t.name + "-output.docx";
  writeFileSync(outPath, buf);
  const hits = Object.values(result.stats).filter(v => v > 0).length;
  const total = Object.keys(result.stats).length;
  console.log("  " + hits + "/" + total + " fields injected, output: " + buf.length + " bytes");
  const misses = Object.entries(result.stats).filter(([k,v]) => v === 0).map(([k]) => k);
  if (misses.length) console.log("  0-hit: " + misses.join(", "));
}
