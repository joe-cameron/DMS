import * as XLSX from 'xlsx';

const REQUIRED = ['Vendor Name', 'Trade'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_ROWS = 500;

export function parseVendorWorkbook(arrayBuffer) {
  let wb;
  try { wb = XLSX.read(arrayBuffer, { type: 'array' }); }
  catch { return { error: 'Could not read the spreadsheet file.', rows: [] }; }

  const sheet = wb.Sheets[wb.SheetNames[0]];
  if (!sheet) return { error: 'The spreadsheet looks empty.', rows: [] };

  const raw = XLSX.utils.sheet_to_json(sheet, { defval: '', raw: false });
  if (raw.length === 0) return { error: 'The spreadsheet looks empty.', rows: [] };
  if (raw.length > MAX_ROWS) return { error: `Spreadsheet too large (${raw.length} rows, max ${MAX_ROWS}). Please split into smaller files.`, rows: [] };

  const headers = Object.keys(raw[0]);
  const missing = REQUIRED.filter(h => !headers.includes(h));
  if (missing.length) return { error: `Missing required columns: ${missing.join(', ')}`, rows: [] };

  const rows = raw.map((r, i) => {
    const errors = [];
    const warnings = [];
    const vendorName   = String(r['Vendor Name'] || '').trim();
    const trade        = String(r['Trade'] || '').trim();
    const contactName  = String(r['Contact Name'] || '').trim();
    const contactPhone = String(r['Contact Phone'] || '').trim();
    const contactEmail = String(r['Contact Email'] || '').trim();
    const contractStart = parseDateCell(r['Contract Start']);
    const contractEnd   = parseDateCell(r['Contract End']);
    const notes        = String(r['Notes'] || '').trim();

    if (!vendorName) errors.push('Vendor Name is required');
    if (!trade) errors.push('Trade is required');
    if (contactEmail && !EMAIL_RE.test(contactEmail)) errors.push('Contact Email is invalid');
    if (r['Contract Start'] && !contractStart) warnings.push('Contract Start is not a readable date');
    if (r['Contract End']   && !contractEnd)   warnings.push('Contract End is not a readable date');

    const status = errors.length ? 'error' : (warnings.length ? 'warning' : 'ok');
    return { rowNum: i + 2, vendorName, trade, contactName, contactPhone, contactEmail, contractStart, contractEnd, notes, errors, warnings, status };
  });

  return { error: null, rows };
}

function parseDateCell(v) {
  if (!v) return '';
  if (v instanceof Date && !isNaN(v.getTime())) return v.toISOString().slice(0, 10);
  const parsed = new Date(v);
  return isNaN(parsed.getTime()) ? '' : parsed.toISOString().slice(0, 10);
}
