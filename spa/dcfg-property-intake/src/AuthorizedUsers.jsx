import React from 'react';
import { T } from './tokens.js';
import { createEmptyUser } from './storage.js';
import { createAuthUser, USE_DATAVERSE } from './intakeApi.js';

export default function AuthorizedUsers({ users, properties, onUpdate, sessionId }) {
  const addUser = async () => {
    const newUser = createEmptyUser();
    onUpdate([...users, newUser]);
    if (USE_DATAVERSE && sessionId) {
      await createAuthUser(sessionId, newUser);
    }
  };
  const removeUser = (id) => onUpdate(users.filter(u => u.id !== id));
  const updateField = (id, field, value) =>
    onUpdate(users.map(u => u.id === id ? { ...u, [field]: value } : u));

  const toggleLocation = (userId, locId) => {
    onUpdate(users.map(u => {
      if (u.id !== userId) return u;
      const has = u.locationIds.includes(locId);
      return {
        ...u,
        locationIds: has
          ? u.locationIds.filter(l => l !== locId)
          : [...u.locationIds, locId],
      };
    }));
  };

  const setAccessLevel = (userId, level) => {
    onUpdate(users.map(u => {
      if (u.id !== userId) return u;
      return { ...u, accessLevel: level, locationIds: level === 'all' ? [] : u.locationIds };
    }));
  };

  const locationName = (p) => p.upkeepName || p.streetAddress || 'Unnamed';

  const Field = ({ label, userId, field, value }) => (
    <div style={{ marginBottom: 10 }}>
      <label style={{ fontSize: 12, fontWeight: 600, color: T.blue, display: 'block', marginBottom: 4 }}>{label}</label>
      <input value={value || ''} onChange={e => updateField(userId, field, e.target.value)}
        style={{ width: '100%', padding: '8px 10px', border: `1px solid ${T.border}`, borderRadius: 6, fontSize: 14, fontFamily: T.fBody, boxSizing: 'border-box' }} />
    </div>
  );

  const pillStyle = (active) => ({
    padding: '6px 14px',
    border: `1px solid ${active ? T.blueMid : T.border}`,
    background: active ? T.blueMid : 'white',
    color: active ? 'white' : T.blue,
    borderRadius: 20,
    fontSize: 13,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: T.fBody,
  });

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 20, margin: 0 }}>Authorized Users</h2>
        <button onClick={addUser} style={{
          marginLeft: 'auto', background: T.blueMid, color: T.blueDeep, border: 'none',
          borderRadius: 6, padding: '8px 16px', fontSize: 13, fontWeight: 700, cursor: 'pointer',
        }}>
          + Add User
        </button>
      </div>

      {users.length === 0 && (
        <p style={{ color: T.textLight, fontSize: 14 }}>No users added yet. Click &quot;+ Add User&quot; to begin.</p>
      )}

      {users.map((u, i) => (
        <div key={u.id} style={{
          background: 'white', border: `1px solid ${T.border}`, borderRadius: 8,
          padding: '16px 20px', marginBottom: 12,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 12 }}>
            <span style={{ fontWeight: 700, color: T.blue, fontSize: 14 }}>User {i + 1}</span>
            <button onClick={() => removeUser(u.id)} style={{
              marginLeft: 'auto', background: 'transparent', border: `1px solid ${T.red}`,
              color: T.red, borderRadius: 4, padding: '4px 10px', fontSize: 11, cursor: 'pointer',
            }}>
              Remove
            </button>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0 16px' }}>
            <Field label="Name" userId={u.id} field="name" value={u.name} />
            <Field label="Email" userId={u.id} field="email" value={u.email} />
            <Field label="Phone" userId={u.id} field="phone" value={u.phone} />
          </div>

          {/* Location Access */}
          <div style={{ marginTop: 8 }}>
            <label style={{ fontSize: 12, fontWeight: 600, color: T.blue, display: 'block', marginBottom: 8 }}>Location Access</label>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              <button style={pillStyle(u.accessLevel === 'all')} onClick={() => setAccessLevel(u.id, 'all')}>
                All Locations
              </button>
              <button style={pillStyle(u.accessLevel === 'specific')} onClick={() => setAccessLevel(u.id, 'specific')}>
                Specific Locations
              </button>
            </div>

            {u.accessLevel === 'specific' && (
              <div style={{
                background: T.bg, borderRadius: 6, padding: '12px 14px',
                border: `1px solid ${T.border}`,
              }}>
                {properties.length === 0 && (
                  <p style={{ color: T.textLight, fontSize: 13, margin: 0 }}>No locations available. Add properties first.</p>
                )}
                {properties.map(p => {
                  const checked = u.locationIds.includes(p.id);
                  return (
                    <label key={p.id} style={{
                      display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0',
                      fontSize: 13, color: T.blue, cursor: 'pointer',
                    }}>
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={() => toggleLocation(u.id, p.id)}
                        style={{ accentColor: T.blueMid, width: 16, height: 16 }}
                      />
                      {locationName(p)}
                    </label>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
