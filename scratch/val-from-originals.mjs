import { readFileSync, writeFileSync } from 'fs';
const { injectTemplate } = await import('file:///C:/DCFG/spa/dcfg-shell/src/lib/ooxmlInject.js');
const { buildContractFieldMap } = await import('file:///C:/DCFG/spa/dcfg-shell/src/lib/contractDocGen.js');

// ── Test data ──
const bd = {
  dcfg_contract_number: "WO24168", dcfg_contract_type: 100000000, dcfg_contract_family: 100000000,
  dcfg_contractor_legal_name: "Lady Bug Pest Services", dcfg_contract_fee: 10350,
  dcfg_signer_printed: "Zoe Buckridee", dcfg_signer_title: "Commercial Accounts Specialist",
  dcfg_contractor_address: "474 North Ave East, Westfield NJ 07091",
  dcfg_contractor_phone: "908-317-8576", dcfg_contractor_email: "office@ladybugpest.com",
  dcfg_owner_contact: "Sarah Mitchell", dcfg_owner_title: "Director of Operations",
  dcfg_customer_site_contact: "Zoe Buckridee", dcfg_customer_site_phone: "908-342-2166",
  dcfg_customer_site_email: "office@ladybugpest.com",
  dcfg_decades_site_contact: "Eric Hadley", dcfg_decades_site_phone: "856-874-4500",
  dcfg_decades_site_email: "ehadley@decades-cg.com",
  dcfg_billing_address: "474 North Ave East", dcfg_billing_city: "Westfield",
  dcfg_billing_state: "NJ", dcfg_billing_zip: "07091",
  dcfg_msa_date: "2025-01-15", dcfg_msa_number: "MSA-2025-0042",
  dcfg_contract_date: "2026-05-18", dcfg_start_date: "2026-06-01", dcfg_end_date: "2027-05-31",
  dcfg_work_hours: "Monday-Friday, 8:00 AM - 5:00 PM",
  dcfg_description_of_service: "Monthly pest control inspections and treatment",
  dcfg_client_name: "Bancroft", dcfg_company: "Lady Bug Pest Services",
  dcfg_blanket_number: "BWO-2026-042", dcfg_po_number: "PO-2026-1234",
  dcfg_service_location_description: "All commercial properties",
  dcfg_amendment_sequence: 1, dcfg_current_amount: 10350,
  dcfg_approved_amount: 12850, dcfg_change_amount: 2500, dcfg_original_amount: 10350,
  dcfg_current_properties_included: "Cherry Hill, Haddonfield, Moorestown",
};

// ── Field mappings (same as production) ──
const af = [
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
  { dcfg_source_text: "Vendor Phone #", dcfg_dataverse_path: "dcfg_contractor_phone" },
  { dcfg_source_text: "email address (Vendor)", dcfg_dataverse_path: "dcfg_contractor_email" },
  { dcfg_source_text: "email address", dcfg_dataverse_path: "dcfg_contractor_email" },
  { dcfg_source_text: "Vendor Email", dcfg_dataverse_path: "dcfg_contractor_email" },
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
  { dcfg_source_text: "MSA Number", dcfg_dataverse_path: "dcfg_msa_number" },
  { dcfg_source_text: "Work Order Date", dcfg_dataverse_path: "dcfg_contract_date" },
  { dcfg_source_text: "Original WorkOrder Date", dcfg_dataverse_path: "dcfg_contract_date" },
  { dcfg_source_text: "Main Contract Date", dcfg_dataverse_path: "dcfg_contract_date" },
  { dcfg_source_text: "Contract Expiration Date", dcfg_dataverse_path: "dcfg_end_date" },
  { dcfg_source_text: "Contract End Date", dcfg_dataverse_path: "dcfg_end_date" },
  { dcfg_source_text: "End Date", dcfg_dataverse_path: "dcfg_end_date" },
  { dcfg_source_text: "Contract Start Date", dcfg_dataverse_path: "dcfg_start_date" },
  { dcfg_source_text: "Start Date", dcfg_dataverse_path: "dcfg_start_date" },
  { dcfg_source_text: "Work State Date", dcfg_dataverse_path: "dcfg_start_date" },
  { dcfg_source_text: "City, State, Zip Code", dcfg_dataverse_path: "[COMPOSITE:vendor_address_block]" },
  { dcfg_source_text: "Contact Name, Tele#", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Vendor Contact Info", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Vendor Contact", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Contractor Contact", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Customer Contact Phone", dcfg_dataverse_path: "dcfg_customer_site_phone" },
  { dcfg_source_text: "Customer Contact Email", dcfg_dataverse_path: "dcfg_customer_site_email" },
  { dcfg_source_text: "Description of Service", dcfg_dataverse_path: "dcfg_description_of_service" },
  { dcfg_source_text: "Locations", dcfg_dataverse_path: "dcfg_current_properties_included" },
  { dcfg_source_text: "Purchase Order", dcfg_dataverse_path: "dcfg_po_number" },
  { dcfg_source_text: "Bancroft PO#", dcfg_dataverse_path: "dcfg_po_number" },
  { dcfg_source_text: "Service Location Description Hour of Operations", dcfg_dataverse_path: "dcfg_work_hours" },
  { dcfg_source_text: "Days, Times", dcfg_dataverse_path: "dcfg_work_hours" },
  { dcfg_source_text: "Contact Name, # Contact Tele, Contact Email (Vendor)", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Account Handler Name, # Tele, Email (Decades)", dcfg_dataverse_path: "[COMPOSITE:decades_contract_contact]" },
  { dcfg_source_text: "Vendor Signer Name", dcfg_dataverse_path: "dcfg_signer_printed" },
  { dcfg_source_text: "Vendor Signer Title", dcfg_dataverse_path: "dcfg_signer_title" },
  { dcfg_source_text: "Customer Contact Title", dcfg_dataverse_path: "dcfg_owner_title" },
  { dcfg_source_text: "Vendor Phone", dcfg_dataverse_path: "dcfg_contractor_phone" },
  { dcfg_source_text: "Vendor Address Block", dcfg_dataverse_path: "[COMPOSITE:vendor_address_block]" },
  { dcfg_source_text: "Client Name", dcfg_dataverse_path: "dcfg_client_name" },
  { dcfg_source_text: "Customer Contact", dcfg_dataverse_path: "dcfg_owner_contact" },
  { dcfg_source_text: "Customer Phone", dcfg_dataverse_path: "dcfg_customer_site_phone" },
  { dcfg_source_text: "Customer EMail", dcfg_dataverse_path: "dcfg_customer_site_email" },
  { dcfg_source_text: "Work Complete Date", dcfg_dataverse_path: "dcfg_end_date" },
  { dcfg_source_text: "Contractor Contact Name Vendor Phone", dcfg_dataverse_path: "[COMPOSITE:vendor_contact]" },
  { dcfg_source_text: "Day of Month", dcfg_dataverse_path: "[SYSTEM:TODAY_DAY]" },
  { dcfg_source_text: "Month Name", dcfg_dataverse_path: "[SYSTEM:TODAY_MONTH]" },
  { dcfg_source_text: "Current Year", dcfg_dataverse_path: "[SYSTEM:TODAY_YEAR]" },
  { dcfg_source_text: "Vendor Signature", dcfg_dataverse_path: "[DOCUSIGN:\\\\Vendor_Signature\\\\]" },
  { dcfg_source_text: "Decades Signature", dcfg_dataverse_path: "[DOCUSIGN:\\\\Decades_Signature\\\\]" },
  { dcfg_source_text: "Vendor Date Signed", dcfg_dataverse_path: "[DOCUSIGN:\\\\Vendor_DateSigned\\\\]" },
  { dcfg_source_text: "Decades Datesigned", dcfg_dataverse_path: "[DOCUSIGN:\\\\Decades_DateSigned\\\\]" },
  { dcfg_source_text: "Customer_DateSigned", dcfg_dataverse_path: "[DOCUSIGN:\\\\Customer_DateSigned\\\\]" },
  { dcfg_source_text: "Vendor_DateSigned", dcfg_dataverse_path: "[DOCUSIGN:\\\\Vendor_DateSigned\\\\]" },
  { dcfg_source_text: "Today's Date", dcfg_dataverse_path: "[SYSTEM:TODAY]" },
  { dcfg_source_text: "_ Decades Title __", dcfg_dataverse_path: "dcfg_owner_title" },
];

// ── Template sources: ORIGINAL untouched files ──
const PROD = "C:/DCFG/Templates/prod-originals/";
const BACKUP = "C:/DCFG/scripts/_backups/2026-05-17_office-harness-before/templates/";

const tests = [
  { name: "01-BWO", file: PROD + "BlanketWO - Blanket Work Order.docx", contract: { ...bd } },
  { name: "02-ExhA-Auto", file: PROD + "ExhA-Auto - Exhibit A - Automated.docx", contract: { ...bd } },
  { name: "03-ExhA-Var", file: PROD + "ExhA-Var - Exhibit A - Variable.docx", contract: { ...bd } },
  { name: "04-WO-Amend", file: PROD + "Amendment - Work Order Amendment.docx", contract: { ...bd, dcfg_contract_type: 100000001, dcfg_contract_number: "AMD-24168-01" } },
  { name: "05-Decades-WO", file: BACKUP + "Decades_Work_Order.docx", contract: { ...bd, dcfg_contract_family: 100000001, dcfg_contract_number: "DWO-2026-001" } },
  { name: "06-Bancroft-VA", file: BACKUP + "Master_Services_Agreement_Bancroft_Vendor.docx", contract: { ...bd, dcfg_contract_type: 100000002, dcfg_contract_number: "VA-2026-001" } },
  { name: "07-Decades-VA", file: BACKUP + "DECADES_MSA_Vendor.docx", contract: { ...bd, dcfg_contract_type: 100000002, dcfg_contract_family: 100000001, dcfg_contract_number: "VA-D-2026-001" } },
];

for (const t of tests) {
  console.log("=== " + t.name + " ===");
  const fm = buildContractFieldMap(af, t.contract, null);
  const bin = readFileSync(t.file);
  const result = await injectTemplate(bin, fm);
  const blob = result.blob;
  let buf;
  if (blob instanceof Uint8Array || blob instanceof ArrayBuffer) buf = Buffer.from(blob);
  else if (blob && typeof blob.arrayBuffer === 'function') buf = Buffer.from(await blob.arrayBuffer());
  else buf = Buffer.from(blob);
  writeFileSync("C:/DCFG/scratch/orig-" + t.name + ".docx", buf);
  const hits = Object.entries(result.stats).filter(([k,v]) => v > 0).length;
  console.log("  " + hits + " fields injected, " + buf.length + " bytes");
}
console.log("DONE — outputs in scratch/orig-*.docx");
