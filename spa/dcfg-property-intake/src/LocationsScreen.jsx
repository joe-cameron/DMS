import React from 'react';
import { T } from './tokens.js';
import PropertyForm from './PropertyForm.jsx';

export default function LocationsScreen({ data, selectedPropId, selectProperty, updateProperty, fieldConfig, locationTypes }) {
  const properties = data?.properties || [];
  const selectedProp = properties.find(p => p.id === selectedPropId);

  if (!selectedProp) {
    return (
      <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 16px' }}>Locations</h2>
        {properties.length === 0 && <div style={{ color: T.textLight }}>No locations on file yet.</div>}
        {properties.map(p => (
          <div key={p.id} data-testid={`location-card-${p.id}`} onClick={() => selectProperty(p.id)} style={{ background: 'white', borderRadius: 10, padding: 14, marginBottom: 8, border: `1px solid ${T.border}`, cursor: 'pointer' }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: T.blue }}>{p.upkeepName || p.streetAddress || 'New Location'}</div>
            <div style={{ fontSize: 12, color: T.textLight, marginTop: 2 }}>{p.city ? `${p.city}, ${p.state}` : 'No address yet'}</div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div style={{ padding: '24px 20px', maxWidth: 900, margin: '0 auto' }}>
      <button data-testid="back-to-list" onClick={() => selectProperty(null)} style={{ background: 'none', border: 'none', color: T.blue, cursor: 'pointer', fontSize: 13, marginBottom: 10 }}>&larr; All locations</button>
      <PropertyForm
        property={selectedProp}
        onChange={updateProperty}
        fieldConfig={fieldConfig}
        locationTypes={locationTypes}
      />
    </div>
  );
}
