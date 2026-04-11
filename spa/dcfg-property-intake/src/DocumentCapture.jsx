import React, { useState, useRef } from 'react';
import { T } from './tokens.js';
import { createDocumentRequest, USE_DATAVERSE } from './intakeApi.js';

const CATEGORIES = [
  'Lease / Rental Agreement',
  'Fire Inspection Report',
  'Generator Service Contract',
  'Roof Warranty',
  'Insurance Certificate',
  'Vendor Call Sheet',
  'Equipment Manual',
  'Other',
];

const ACCEPT = 'image/*,.pdf,.doc,.docx';

export default function DocumentCapture({ documents = [], onAdd, locationName, isMobile, propertyId }) {
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [dragging, setDragging] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef();
  const cameraRef = useRef();

  function readFile(file) {
    const reader = new FileReader();
    reader.onload = async (e) => {
      const dataUrl = e.target.result;
      const doc = {
        id: crypto.randomUUID(),
        name: file.name,
        category,
        dataUrl,
        timestamp: new Date().toISOString(),
        status: 'saving',
      };
      onAdd(doc);

      if (USE_DATAVERSE && propertyId) {
        setUploading(true);
        const base64 = dataUrl.split(',')[1];
        const ok = await createDocumentRequest(propertyId, category, file.name, base64);
        doc.status = ok ? 'uploaded' : 'local-only';
        setUploading(false);
      } else {
        doc.status = 'local-only';
      }
    };
    reader.readAsDataURL(file);
  }

  function handleFiles(files) {
    Array.from(files).forEach(readFile);
  }

  function onDrop(e) {
    e.preventDefault();
    setDragging(false);
    handleFiles(e.dataTransfer.files);
  }

  const segBtn = (cat) => ({
    padding: '6px 14px',
    borderRadius: 20,
    border: `1.5px solid ${category === cat ? T.blue : T.border}`,
    background: category === cat ? T.blue : T.bg,
    color: category === cat ? T.white : T.textMid,
    fontFamily: T.fBody,
    fontSize: 13,
    cursor: 'pointer',
    margin: '3px 4px 3px 0',
    fontWeight: category === cat ? 600 : 400,
    transition: 'all .15s',
  });

  return (
    <div style={{ fontFamily: T.fBody, color: T.text }}>
      {locationName && (
        <p style={{ fontSize: 13, color: T.textLight, margin: '0 0 10px' }}>
          Adding documents for <strong style={{ color: T.text }}>{locationName}</strong>
        </p>
      )}

      {/* Category selector */}
      <div style={{ marginBottom: 16 }}>
        <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 8, color: T.text }}>
          What type of document is this?
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap' }}>
          {CATEGORIES.map((cat) => (
            <button key={cat} style={segBtn(cat)} onClick={() => setCategory(cat)}>{cat}</button>
          ))}
        </div>
      </div>

      {/* Capture area */}
      {isMobile ? (
        <div style={{ textAlign: 'center', padding: '24px 16px', background: T.bluePale, borderRadius: 12, border: `1.5px solid ${T.border}` }}>
          <button
            onClick={() => cameraRef.current.click()}
            style={{ background: T.blue, color: T.white, border: 'none', borderRadius: 12, padding: '14px 36px', fontSize: 17, fontWeight: 700, fontFamily: T.fDisplay, cursor: 'pointer', display: 'block', width: '100%', marginBottom: 12 }}
          >
            Take a Photo
          </button>
          <input ref={cameraRef} type="file" accept={ACCEPT} capture="environment" style={{ display: 'none' }} onChange={(e) => handleFiles(e.target.files)} />
          <button
            onClick={() => fileRef.current.click()}
            style={{ background: 'none', border: 'none', color: T.blueMid, fontSize: 14, fontFamily: T.fBody, cursor: 'pointer', textDecoration: 'underline' }}
          >
            or choose a file from your device
          </button>
          <input ref={fileRef} type="file" accept={ACCEPT} multiple style={{ display: 'none' }} onChange={(e) => handleFiles(e.target.files)} />
        </div>
      ) : (
        <div
          onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
          onDragLeave={() => setDragging(false)}
          onDrop={onDrop}
          onClick={() => fileRef.current.click()}
          style={{ border: `2px dashed ${dragging ? T.blueMid : T.border}`, borderRadius: 12, padding: '36px 24px', textAlign: 'center', background: dragging ? T.bluePale : T.bg, cursor: 'pointer', transition: 'all .15s' }}
        >
          <div style={{ fontSize: 32, marginBottom: 8 }}>📎</div>
          <div style={{ fontWeight: 600, fontSize: 15, marginBottom: 4, color: T.text }}>Drop files here</div>
          <div style={{ fontSize: 13, color: T.textLight }}>or click to browse your computer</div>
          <input ref={fileRef} type="file" accept={ACCEPT} multiple style={{ display: 'none' }} onChange={(e) => handleFiles(e.target.files)} />
        </div>
      )}

      {uploading && (
        <div style={{ marginTop: 12, padding: '8px 12px', background: T.bluePale, borderRadius: 8, fontSize: 13, color: T.blue, textAlign: 'center' }}>
          Uploading to Decades...
        </div>
      )}

      {/* Uploaded documents */}
      {documents.length > 0 && (
        <div style={{ marginTop: 20 }}>
          <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 10, color: T.text }}>
            Uploaded ({documents.length})
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {documents.map((doc) => (
              <div key={doc.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 12px', background: T.greenLt, border: `1px solid ${T.border}`, borderRadius: 8 }}>
                {doc.dataUrl?.startsWith('data:image') ? (
                  <img src={doc.dataUrl} alt={doc.name} style={{ width: 44, height: 44, objectFit: 'cover', borderRadius: 6, flexShrink: 0 }} />
                ) : (
                  <div style={{ width: 44, height: 44, borderRadius: 6, background: T.bluePale, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>📄</div>
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, color: T.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{doc.name}</div>
                  <span style={{ fontSize: 11, background: T.blue, color: T.white, borderRadius: 10, padding: '2px 8px', display: 'inline-block', marginTop: 3 }}>{doc.category}</span>
                </div>
                <div style={{ fontSize: 11, fontWeight: 600, flexShrink: 0,
                  color: doc.status === 'uploaded' ? T.green : doc.status === 'saving' ? T.blueMid : T.textLight }}>
                  {doc.status === 'uploaded' ? 'Uploaded' : doc.status === 'saving' ? 'Saving...' : 'Saved locally'}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
