import XLSX from 'xlsx';
import { mkdirSync } from 'fs';

const outDir = 'spa/dcfg-property-intake/test/fixtures';
mkdirSync(outDir, { recursive: true });

// Happy path
const happy = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(happy, XLSX.utils.aoa_to_sheet([
  ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'],
  ['Acme HVAC','HVAC','Jane Doe','555-111-2222','jane@acme.com','2025-01-01','2026-01-01','Monthly PM'],
  ['Blue Fire','Fire/Life Safety','Bob Smith','555-333-4444','bob@bluefire.com','','','Annual inspection'],
]), 'Vendors');
XLSX.writeFile(happy, `${outDir}/vendor-template-happy.xlsx`);

// Bad headers
const bad1 = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(bad1, XLSX.utils.aoa_to_sheet([
  ['Name','Type','Email'],
  ['Acme','HVAC','a@b.com'],
]), 'Vendors');
XLSX.writeFile(bad1, `${outDir}/vendor-template-bad-headers.xlsx`);

// Bad rows
const bad2 = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(bad2, XLSX.utils.aoa_to_sheet([
  ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'],
  ['', 'HVAC', '', '', '', '', '', ''],
  ['Acme', '', '', '', '', '', '', ''],
  ['Beta', 'Fire', '', '', 'not-an-email', '', '', ''],
  ['OK Co', 'HVAC', 'Pat', '555', 'p@x.com', '', '', ''],
]), 'Vendors');
XLSX.writeFile(bad2, `${outDir}/vendor-template-bad-rows.xlsx`);

// Production template — headers only
const templateDir = 'spa/dcfg-property-intake/public/templates';
mkdirSync(templateDir, { recursive: true });
const tpl = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(tpl, XLSX.utils.aoa_to_sheet([
  ['Vendor Name','Trade','Contact Name','Contact Phone','Contact Email','Contract Start','Contract End','Notes'],
]), 'Vendors');
XLSX.writeFile(tpl, `${templateDir}/decades-vendor-intake.xlsx`);

console.log('Generated fixtures and production template.');
