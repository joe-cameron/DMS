import React, { useState } from 'react';
import { T } from './tokens.js';
import VendorList from './VendorList.jsx';
import VendorSpreadsheetModal from './VendorSpreadsheetModal.jsx';

export default function VendorsScreen({ data, updateData, sessionId }) {
  const [uploadOpen, setUploadOpen] = useState(false);
  const vendors = data?.vendors || [];

  return (
    <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16, gap: 10, flexWrap: 'wrap' }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: 0 }}>Vendors</h2>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
          <a data-testid="download-template" href="/templates/decades-vendor-intake.xlsx" download style={{ padding: '8px 14px', background: 'white', border: `1px solid ${T.border}`, borderRadius: 8, color: T.blue, textDecoration: 'none', fontSize: 13, fontWeight: 600 }}>Download template</a>
          <button data-testid="upload-spreadsheet" onClick={() => setUploadOpen(true)} style={{ padding: '8px 14px', background: T.blue, color: 'white', border: 'none', borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>Upload spreadsheet</button>
        </div>
      </div>
      <VendorList vendors={vendors} onUpdate={(next) => updateData(prev => ({ ...prev, vendors: next }))} sessionId={sessionId} />
      {uploadOpen && (
        <VendorSpreadsheetModal
          sessionId={sessionId}
          onClose={() => setUploadOpen(false)}
          onCommitted={(newVendors) => updateData(prev => ({ ...prev, vendors: [...(prev.vendors || []), ...newVendors] }))}
        />
      )}
    </div>
  );
}
