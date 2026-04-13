import React, { useState } from 'react';
import { T } from './tokens.js';
import { parseVendorWorkbook } from './vendorSpreadsheetParser.js';
import { createVendor, USE_DATAVERSE } from './intakeApi.js';

export default function VendorSpreadsheetModal({ sessionId, onClose, onCommitted }) {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState({});
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(null);
  const [retry, setRetry] = useState({});

  const onFile = async (file) => {
    if (!file) return;
    setError(''); setRows([]); setSelected({}); setRetry({});
    const buf = await file.arrayBuffer();
    const result = parseVendorWorkbook(new Uint8Array(buf));
    if (result.error) { setError(result.error); return; }
    setRows(result.rows);
    const preselect = {};
    for (const r of result.rows) if (r.status !== 'error') preselect[r.rowNum] = true;
    setSelected(preselect);
  };

  const selectAll    = () => setSelected(Object.fromEntries(rows.filter(r => r.status !== 'error').map(r => [r.rowNum, true])));
  const selectOkOnly = () => setSelected(Object.fromEntries(rows.filter(r => r.status === 'ok').map(r => [r.rowNum, true])));
  const deselectAll  = () => setSelected({});

  const commit = async () => {
    const toAdd = rows.filter(r => selected[r.rowNum] && r.status !== 'error');
    if (toAdd.length === 0) return;
    setBusy(true);
    setProgress({ done: 0, total: toAdd.length });
    const committed = [];
    const failed = { ...retry };
    for (let i = 0; i < toAdd.length; i++) {
      const r = toAdd[i];
      const vendor = {
        id: crypto.randomUUID(),
        vendorName:    r.vendorName,
        serviceProvided: r.trade,
        contactName:   r.contactName,
        contactPhone:  r.contactPhone,
        contactEmail:  r.contactEmail,
        contractStart: r.contractStart,
        contractEnd:   r.contractEnd,
        notes:         r.notes || '',
        requiresReBid: '',
      };
      let ok = true;
      if (USE_DATAVERSE && sessionId) {
        const created = await createVendor(sessionId, vendor);
        ok = !!created;
      }
      if (ok) committed.push(vendor);
      else    failed[r.rowNum] = true;
      setProgress({ done: i + 1, total: toAdd.length });
    }
    setRetry(failed);
    setBusy(false);
    if (committed.length > 0) onCommitted(committed);
    if (Object.keys(failed).length === 0) onClose();
  };

  return (
    <div role="dialog" aria-modal="true" style={backdrop} onClick={onClose}>
      <div data-testid="spreadsheet-modal" style={modal} onClick={e => e.stopPropagation()}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, margin: '0 0 4px' }}>Upload a vendor spreadsheet</h3>
        <p style={{ color: T.textLight, fontSize: 13, margin: '0 0 14px' }}>Use the template. Extra columns are ignored. Max 500 rows per file.</p>

        {rows.length === 0 && !error && (
          <label data-testid="file-picker" style={dropzone}>
            <input type="file" accept=".xlsx,.xls" onChange={e => onFile(e.target.files[0])} style={{ display: 'none' }} />
            Click to choose an .xlsx file
          </label>
        )}
        {error && (
          <div data-testid="parse-error" style={errorBox}>
            <div style={{ color: T.red, fontSize: 13 }}>{error}</div>
            <a href="/templates/decades-vendor-intake.xlsx" download style={{ color: T.blue, fontSize: 12, marginTop: 8, display: 'inline-block' }}>Download template</a>
          </div>
        )}

        {rows.length > 0 && (
          <>
            <div style={{ display: 'flex', gap: 8, margin: '10px 0', fontSize: 12, flexWrap: 'wrap', alignItems: 'center' }}>
              <span>Found {rows.length}. OK: {rows.filter(r => r.status==='ok').length} &middot; Warning: {rows.filter(r => r.status==='warning').length} &middot; Error: {rows.filter(r => r.status==='error').length}</span>
              <div style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
                <button data-testid="select-all" onClick={selectAll} style={miniBtn}>Select all</button>
                <button data-testid="select-ok" onClick={selectOkOnly} style={miniBtn}>Only OK</button>
                <button data-testid="deselect-all" onClick={deselectAll} style={miniBtn}>Deselect</button>
              </div>
            </div>
            <div style={{ maxHeight: 320, overflow: 'auto', border: `1px solid ${T.border}`, borderRadius: 6 }}>
              <table style={{ width: '100%', fontSize: 12, borderCollapse: 'collapse' }}>
                <thead style={{ background: '#f8fafc', position: 'sticky', top: 0 }}>
                  <tr><th style={th}></th><th style={th}>Row</th><th style={th}>Vendor</th><th style={th}>Trade</th><th style={th}>Status</th></tr>
                </thead>
                <tbody>
                  {rows.map(r => (
                    <tr key={r.rowNum} data-testid={`preview-row-${r.rowNum}`} style={{ background: retry[r.rowNum] ? '#FEF3C7' : 'white' }}>
                      <td style={td}><input type="checkbox" disabled={r.status === 'error'} checked={!!selected[r.rowNum]} onChange={e => setSelected({ ...selected, [r.rowNum]: e.target.checked })} /></td>
                      <td style={td}>{r.rowNum}</td>
                      <td style={td}>{r.vendorName || <em style={{ color: T.textLight }}>(blank)</em>}</td>
                      <td style={td}>{r.trade || <em style={{ color: T.textLight }}>(blank)</em>}</td>
                      <td style={td}>
                        {retry[r.rowNum] && <span style={{ color: '#92400E' }}>Retry</span>}
                        {!retry[r.rowNum] && r.status === 'ok' && <span style={{ color: '#059669' }}>OK</span>}
                        {!retry[r.rowNum] && r.status === 'warning' && <span title={r.warnings.join('; ')} style={{ color: '#d97706' }}>Warning</span>}
                        {!retry[r.rowNum] && r.status === 'error' && <span title={r.errors.join('; ')} style={{ color: T.red }}>Error</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {progress && <div style={{ marginTop: 10, fontSize: 12, color: T.textLight }}>Adding {progress.done} of {progress.total}&hellip;</div>}
          </>
        )}

        <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
          <button data-testid="cancel-upload" onClick={onClose} disabled={busy} style={btnSecondary}>Cancel</button>
          <button data-testid="commit-upload" onClick={commit} disabled={busy || rows.length === 0 || Object.keys(selected).length === 0} style={btnPrimary}>
            {busy ? 'Adding\u2026' : 'Add selected to my vendor list'}
          </button>
        </div>
      </div>
    </div>
  );
}

const backdrop     = { position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 };
const modal        = { background: 'white', borderRadius: 12, padding: 24, width: '100%', maxWidth: 720, maxHeight: '90vh', overflow: 'auto' };
const dropzone     = { display: 'block', padding: 32, border: '2px dashed #cbd5e1', borderRadius: 10, textAlign: 'center', cursor: 'pointer', color: '#64748b', fontSize: 14 };
const errorBox     = { padding: 12, background: '#FEF2F2', borderRadius: 8 };
const miniBtn      = { background: 'white', border: '1px solid #cbd5e1', borderRadius: 6, padding: '4px 10px', fontSize: 11, cursor: 'pointer' };
const th           = { textAlign: 'left', padding: '8px 10px', fontWeight: 600, borderBottom: '1px solid #e2e8f0' };
const td           = { padding: '6px 10px', borderBottom: '1px solid #f1f5f9' };
const btnPrimary   = { flex: 1, padding: 10, background: '#2563eb', color: 'white', border: 'none', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
const btnSecondary = { flex: 1, padding: 10, background: 'white', color: '#2563eb', border: '1px solid #cbd5e1', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
