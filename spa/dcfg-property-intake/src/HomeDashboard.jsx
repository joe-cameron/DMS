import React from 'react';
import { T } from './tokens.js';

const CARDS = [
  { key: 'vendors',   path: '/home/vendors',   icon: '\uD83D\uDD27', title: 'Vendors',          desc: 'Who do you already use? HVAC, electrical, fire/life safety, pest, pool, elevator, roofing.',               border: '#2563eb' },
  { key: 'dates',     path: '/home/dates',     icon: '\uD83D\uDCC5', title: 'Important Dates',  desc: 'Upcoming inspections, cert expirations, contract anniversaries \u2014 attach the file that proves it.', border: '#d97706' },
  { key: 'locations', path: '/home/locations', icon: '\uD83D\uDCCD', title: 'Location Details', desc: 'Address, entry time, site contact, lockbox, basic systems.',                                            border: '#059669' },
  { key: 'documents', path: '/home/documents', icon: '\uD83D\uDCC4', title: 'Documents',        desc: 'Floor plans, insurance COI, W-9s, manuals \u2014 anything not tied to a specific date.',                border: '#7c3aed' },
];

export default function HomeDashboard({ data, navigate, onDelegate }) {
  const counts = {
    vendors:   (data?.vendors?.length) || 0,
    dates:     (data?.dates?.length) || 0,
    locations: (data?.properties?.length) || 0,
    documents: (data?.documents?.length) || 0,
  };

  return (
    <div style={{ padding: '28px 20px', maxWidth: 780, margin: '0 auto' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 16 }}>
        {CARDS.map(c => (
          <div key={c.key} data-testid={`card-${c.key}`} onClick={() => navigate(c.path)} style={{
            background: 'white', borderRadius: 12, padding: 22, cursor: 'pointer',
            boxShadow: '0 2px 8px rgba(0,0,0,0.06)', borderTop: `4px solid ${c.border}`,
          }}>
            <div style={{ fontSize: 32 }}>{c.icon}</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: T.blue, margin: '6px 0' }}>{c.title}</div>
            <div style={{ fontSize: 13, color: T.textLight, lineHeight: 1.45 }}>{c.desc}</div>
            <div style={{ marginTop: 14, paddingTop: 12, borderTop: `1px solid ${T.border}`, fontSize: 12, color: T.textLight, display: 'flex', justifyContent: 'space-between' }}>
              <span>{counts[c.key]} {c.key === 'locations' ? 'locations' : c.key}</span>
              <button data-testid={`delegate-${c.key}`} onClick={(e) => { e.stopPropagation(); onDelegate(c.key); }} style={{ background: 'none', border: 'none', color: T.blue, cursor: 'pointer', fontSize: 12, textDecoration: 'underline' }}>
                Delegate
              </button>
            </div>
          </div>
        ))}
      </div>
      <div style={{ textAlign: 'center', color: T.textLight, fontSize: 12, marginTop: 24 }}>
        Progress saves automatically. Come back any time.
      </div>
    </div>
  );
}
