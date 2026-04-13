import React, { useState } from 'react';
import { T } from './tokens.js';
import { createEmptyDate } from './storage.js';
import { createDate, updateDate, softDeleteDate, uploadDateAttachment, USE_DATAVERSE } from './intakeApi.js';

const CATEGORIES = [
  { value: 100000000, label: 'Inspection' },
  { value: 100000001, label: 'Cert Expiration' },
  { value: 100000002, label: 'Contract Anniversary' },
  { value: 100000003, label: 'Insurance' },
  { value: 100000004, label: 'Other' },
];

export default function DatesScreen({ data, updateData, sessionId }) {
  const dates = data?.dates || [];
  const [busyId, setBusyId] = useState(null);

  const add = async () => {
    const d = createEmptyDate();
    updateData(prev => ({ ...prev, dates: [...(prev.dates || []), d] }));
    if (USE_DATAVERSE && sessionId) {
      const created = await createDate(sessionId, d);
      if (created?.dcfg_intake_dateid) {
        updateData(prev => ({
          ...prev,
          dates: prev.dates.map(x => x.id === d.id ? { ...x, _dataverseId: created.dcfg_intake_dateid } : x),
        }));
      }
    }
  };

  const updateField = async (id, field, value) => {
    const next = dates.map(x => x.id === id ? { ...x, [field]: value } : x);
    updateData(prev => ({ ...prev, dates: next }));
    const row = next.find(x => x.id === id);
    if (USE_DATAVERSE && row?._dataverseId) {
      const dvPatch = {};
      if (field === 'label')       dvPatch.dcfg_name         = value;
      if (field === 'dueDate')     dvPatch.dcfg_due_date     = value;
      if (field === 'category')    dvPatch.dcfg_category     = value;
      if (field === 'notes')       dvPatch.dcfg_notes        = value;
      if (field === 'locationRef') dvPatch.dcfg_location_ref = value;
      if (Object.keys(dvPatch).length) await updateDate(row._dataverseId, dvPatch);
    }
  };

  const remove = async (id) => {
    const row = dates.find(x => x.id === id);
    updateData(prev => ({ ...prev, dates: prev.dates.filter(x => x.id !== id) }));
    if (USE_DATAVERSE && row?._dataverseId) await softDeleteDate(row._dataverseId);
  };

  const onFile = async (id, file) => {
    const row = dates.find(x => x.id === id);
    if (!row?._dataverseId) { alert('Please wait for the row to save before attaching a file.'); return; }
    setBusyId(id);
    const ok = await uploadDateAttachment(row._dataverseId, file);
    setBusyId(null);
    if (ok) {
      updateData(prev => ({ ...prev, dates: prev.dates.map(x => x.id === id ? { ...x, _attachmentName: file.name } : x) }));
    } else {
      alert('File upload failed. Try again.');
    }
  };

  return (
    <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
      <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 4px' }}>Important Dates</h2>
      <p style={{ color: T.textLight, fontSize: 14, margin: '0 0 20px' }}>Add inspection deadlines, cert expirations, contract anniversaries &mdash; anything we should know about.</p>
      <button data-testid="add-date" onClick={add} style={{ background: T.blueMid, color: T.blueDeep, border: 'none', padding: '10px 18px', borderRadius: 8, fontWeight: 600, cursor: 'pointer', marginBottom: 16 }}>+ Add a date</button>
      {dates.length === 0 && <div style={{ color: T.textLight, fontSize: 14, padding: 20, textAlign: 'center' }}>No dates yet.</div>}
      {dates.map(d => (
        <div key={d.id} data-testid={`date-row-${d.id}`} style={{ background: 'white', borderRadius: 10, padding: 16, marginBottom: 12, border: `1px solid ${T.border}` }}>
          <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr', gap: 10, marginBottom: 10 }}>
            <input data-testid="date-label" value={d.label} onChange={e => updateField(d.id, 'label', e.target.value)} placeholder="Label (e.g. Fire marshal inspection)" style={fieldStyle} />
            <input type="date" data-testid="date-due" value={d.dueDate} onChange={e => updateField(d.id, 'dueDate', e.target.value)} style={fieldStyle} />
            <select data-testid="date-category" value={d.category} onChange={e => updateField(d.id, 'category', Number(e.target.value))} style={fieldStyle}>
              {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <textarea data-testid="date-notes" value={d.notes} onChange={e => updateField(d.id, 'notes', e.target.value)} placeholder="Notes (optional)" rows={2} style={{ ...fieldStyle, width: '100%', fontFamily: T.fBody, resize: 'vertical' }} />
          <div style={{ display: 'flex', alignItems: 'center', marginTop: 10, gap: 10 }}>
            <label data-testid="date-upload" style={{ fontSize: 12, color: T.blue, cursor: 'pointer', textDecoration: 'underline' }}>
              {busyId === d.id ? 'Uploading\u2026' : d._attachmentName ? `\uD83D\uDCCE ${d._attachmentName}` : '\uD83D\uDCCE Attach file'}
              <input type="file" onChange={e => e.target.files[0] && onFile(d.id, e.target.files[0])} style={{ display: 'none' }} />
            </label>
            <button data-testid="date-delete" onClick={() => remove(d.id)} style={{ marginLeft: 'auto', background: 'none', border: 'none', color: T.red, cursor: 'pointer', fontSize: 12 }}>Remove</button>
          </div>
        </div>
      ))}
    </div>
  );
}

const fieldStyle = { padding: '8px 10px', border: '1px solid #cbd5e1', borderRadius: 6, fontSize: 14, boxSizing: 'border-box' };
