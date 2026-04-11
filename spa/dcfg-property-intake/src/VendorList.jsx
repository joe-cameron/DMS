import React from 'react';
import { T } from './tokens.js';
import { createEmptyVendor } from './storage.js';
import { createVendor, USE_DATAVERSE, ES } from './intakeApi.js';

async function handleFileUpload(vendorId, file) {
  if (!file || !USE_DATAVERSE) return;
  const reader = new FileReader();
  reader.onload = async () => {
    const base64 = reader.result.split(',')[1];
    try {
      const token = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
      await fetch('/_api/annotations', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          '__RequestVerificationToken': token || '',
        },
        credentials: 'same-origin',
        body: JSON.stringify({
          subject: file.name,
          filename: file.name,
          mimetype: file.type,
          documentbody: base64,
          [`objectid_dcfg_intake_vendor@odata.bind`]: `/${ES.vendors}(${vendorId})`,
        }),
      });
    } catch (e) { console.warn('File upload failed:', e); }
  };
  reader.readAsDataURL(file);
}

export default function VendorList({ vendors, onUpdate, sessionId }) {
  const addVendor = async () => {
    const newVendor = createEmptyVendor();
    const updated = [...vendors, newVendor];
    onUpdate(updated);
    if (USE_DATAVERSE && sessionId) {
      await createVendor(sessionId, newVendor);
    }
  };
  const removeVendor = (id) => onUpdate(vendors.filter(v => v.id !== id));
  const updateField = (id, field, value) =>
    onUpdate(vendors.map(v => v.id === id ? { ...v, [field]: value } : v));

  const Field = ({ label, vendorId, field, value }) => (
    <div style={{ marginBottom: 10 }}>
      <label style={{ fontSize: 12, fontWeight: 600, color: T.blue, display: 'block', marginBottom: 4 }}>{label}</label>
      <input value={value || ''} onChange={e => updateField(vendorId, field, e.target.value)}
        style={{ width: '100%', padding: '8px 10px', border: `1px solid ${T.border}`, borderRadius: 6, fontSize: 14, fontFamily: T.fBody, boxSizing: 'border-box' }} />
    </div>
  );

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 20, margin: 0 }}>Vendor List</h2>
        <button onClick={addVendor} style={{
          marginLeft: 'auto', background: T.blueMid, color: T.blueDeep, border: 'none',
          borderRadius: 6, padding: '8px 16px', fontSize: 13, fontWeight: 700, cursor: 'pointer',
        }}>
          + Add Vendor
        </button>
      </div>

      {vendors.length === 0 && (
        <p style={{ color: T.textLight, fontSize: 14 }}>No vendors added yet. Click &quot;+ Add Vendor&quot; to begin.</p>
      )}

      {vendors.map((v, i) => (
        <div key={v.id} style={{
          background: 'white', border: `1px solid ${T.border}`, borderRadius: 8,
          padding: '16px 20px', marginBottom: 12,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 12 }}>
            <span style={{ fontWeight: 700, color: T.blue, fontSize: 14 }}>Vendor {i + 1}</span>
            <button onClick={() => removeVendor(v.id)} style={{
              marginLeft: 'auto', background: 'transparent', border: `1px solid ${T.red}`,
              color: T.red, borderRadius: 4, padding: '4px 10px', fontSize: 11, cursor: 'pointer',
            }}>
              Remove
            </button>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0 16px' }}>
            <Field label="Vendor Name" vendorId={v.id} field="vendorName" value={v.vendorName} />
            <Field label="Service Provided" vendorId={v.id} field="serviceProvided" value={v.serviceProvided} />
            <Field label="Contact Phone" vendorId={v.id} field="contactPhone" value={v.contactPhone} />
          </div>
          <div style={{ marginBottom: 10 }}>
            <label style={{ fontSize: 12, fontWeight: 600, color: T.blue, display: 'block', marginBottom: 4 }}>Call Sheet / Document</label>
            <input
              type="file"
              onChange={e => handleFileUpload(v.id, e.target.files?.[0])}
              style={{ fontSize: 13, fontFamily: T.fBody }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
