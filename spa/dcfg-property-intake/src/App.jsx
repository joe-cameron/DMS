import React, { useState, useEffect, useRef } from 'react';
import { T } from './tokens.js';
import { loadProviderData, saveProviderData, createEmptyProvider, createEmptyProperty, dataverseToForm, formFieldToDataverse, FIELD_MAP } from './storage.js';
import { loadFieldConfig, loadLocationTypes, USE_DATAVERSE, loadSession, loadProperties, loadVendors, loadAuthUsers, savePropertyBatch, isOnline, acquireLock, forceAcquireLock, releaseLock, releaseLockSync, refreshLock } from './intakeApi.js';
import PropertyForm from './PropertyForm.jsx';
import VendorList from './VendorList.jsx';
import AuthorizedUsers from './AuthorizedUsers.jsx';
import WelcomeScreen from './WelcomeScreen.jsx';
import DocumentCapture from './DocumentCapture.jsx';

// Access codes are managed in Dataverse dcfg_intake_sessions — no hardcoded backdoors

// Mobile detection
const isMobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || window.innerWidth < 768;

export default function App() {
  const [code, setCode] = useState('');
  const [providerName, setProviderName] = useState(null);
  const [data, setData] = useState(null);
  const [selectedPropId, setSelectedPropId] = useState(null);
  const [tab, setTab] = useState('locations');
  const [codeInput, setCodeInput] = useState('');
  const [codeError, setCodeError] = useState('');
  const [showWelcome, setShowWelcome] = useState(false);
  const [fieldConfig, setFieldConfig] = useState(null);
  const [locationTypeNames, setLocationTypeNames] = useState([]);
  const [offline, setOffline] = useState(false);
  const [lockWarning, setLockWarning] = useState(null);
  const [mobile] = useState(isMobile);
  const saveTimer = useRef(null);
  const pendingChanges = useRef({});

  // Auto-save — localStorage always, Dataverse when available
  function scheduleSave(newData, changedPropId, changedField, changedValue) {
    if (code) saveProviderData(code, newData);
    if (USE_DATAVERSE && changedPropId && changedField) {
      const dvField = formFieldToDataverse(changedField);
      if (dvField) {
        if (!pendingChanges.current[changedPropId]) pendingChanges.current[changedPropId] = {};
        pendingChanges.current[changedPropId][dvField] = changedValue;
      }
      clearTimeout(saveTimer.current);
      saveTimer.current = setTimeout(async () => {
        const batches = { ...pendingChanges.current };
        pendingChanges.current = {};
        for (const [propId, fields] of Object.entries(batches)) {
          const prop = newData.properties.find(p => p.id === propId);
          const dvId = prop?._dataverseId;
          if (!dvId) continue;
          const ok = await savePropertyBatch(dvId, fields);
          if (!ok) setOffline(true);
          else { if (offline) setOffline(false); await refreshLock(dvId); }
        }
      }, 800);
    }
  }

  // Load config on mount
  useEffect(() => {
    (async () => {
      const types = await loadLocationTypes();
      const typeMap = {};
      if (types) {
        setLocationTypeNames(types.map(t => t.dcfg_name));
        for (const t of types) typeMap[t.dcfg_location_typeid] = t.dcfg_name;
      }
      const configs = await loadFieldConfig();
      if (configs) {
        setFieldConfig(configs.map(c => ({
          key: c.dcfg_field_key,
          locationType: typeMap[c._dcfg_location_type_value] || c._dcfg_location_type_value,
          visible: c.dcfg_visible,
        })));
      }
    })();
  }, []);

  // Reconnection check
  useEffect(() => {
    if (!offline || !USE_DATAVERSE) return;
    const interval = setInterval(async () => {
      const online = await isOnline();
      if (online) {
        setOffline(false);
        if (data && code) {
          for (const prop of data.properties) {
            if (!prop._dataverseId) continue;
            const fields = {};
            for (const [formKey, dvKey] of Object.entries(FIELD_MAP)) {
              if (prop[formKey]) fields[dvKey] = prop[formKey];
            }
            await savePropertyBatch(prop._dataverseId, fields);
          }
        }
      }
    }, 30000);
    return () => clearInterval(interval);
  }, [offline, data, code]);

  // Release lock on unload
  useEffect(() => {
    const handleUnload = () => {
      if (selectedPropId && data) {
        const prop = data.properties.find(p => p.id === selectedPropId);
        if (prop?._dataverseId) releaseLockSync(prop._dataverseId);
      }
    };
    window.addEventListener('beforeunload', handleUnload);
    return () => window.removeEventListener('beforeunload', handleUnload);
  }, [selectedPropId, data]);

  // Auto-login disabled — always prompt for access code
  useEffect(() => {
    localStorage.removeItem('intake_cached_code');
  }, []);

  // Login flow
  async function handleLogin() {
    const upper = codeInput.trim().toUpperCase();
    if (!upper || upper.length < 4) return;
    setCodeError('');
    // No caching — always require fresh code entry

    const session = await loadSession(upper);
    if (session) {
      const props = await loadProperties(session.dcfg_intake_sessionid);
      const vendors = await loadVendors(session.dcfg_intake_sessionid);
      const authUsers = await loadAuthUsers(session.dcfg_intake_sessionid);
      if (props) {
        const formProps = props.map(dataverseToForm);
        setCode(upper);
        setProviderName(session.dcfg_provider_name);
        setData({ properties: formProps, vendors: vendors || [], authorizedUsers: authUsers || [],
          expiresAt: session.dcfg_expires_at, lastModified: new Date().toISOString(),
          _sessionId: session.dcfg_intake_sessionid, _source: 'dataverse', documents: [] });
        setShowWelcome(true);
        return;
      }
    }
    const existing = loadProviderData(upper);
    if (existing) {
      setCode(upper); setProviderName(existing.providerName || upper);
      setData({ ...existing, documents: existing.documents || [] });
      if (existing.properties?.length > 0) setSelectedPropId(existing.properties[0].id);
      return;
    }
    try {
      const resp = await fetch(`./seeds/${upper}.json`);
      if (resp.ok) {
        const seed = await resp.json();
        setCode(upper); setProviderName(seed.providerName || upper);
        const d = { ...seed, documents: [] };
        setData(d); saveProviderData(upper, d);
        setShowWelcome(true);
        return;
      }
    } catch {}
    setCodeError('Invalid access code. Please check and try again.');
  }

  // Property actions
  async function selectProperty(propId) {
    if (selectedPropId) {
      const prev = data.properties.find(p => p.id === selectedPropId);
      if (prev?._dataverseId) await releaseLock(prev._dataverseId);
    }
    const prop = data.properties.find(p => p.id === propId);
    if (prop?._dataverseId) {
      const result = await acquireLock(prop._dataverseId);
      if (!result.locked) {
        setLockWarning({ propertyId: propId, lockedBy: result.lockedBy, lockedAt: result.lockedAt });
        return;
      }
    }
    setSelectedPropId(propId);
    setLockWarning(null);
  }

  function updateProperty(propId, field, value) {
    const newData = { ...data, properties: data.properties.map(p =>
      p.id === propId ? { ...p, [field]: value } : p) };
    setData(newData);
    scheduleSave(newData, propId, field, value);
  }

  function updateData(updater) {
    setData(prev => {
      const next = typeof updater === 'function' ? updater(prev) : updater;
      if (code) saveProviderData(code, next);
      return next;
    });
  }

  const addDocument = (doc) => {
    updateData(prev => ({ ...prev, documents: [...(prev.documents || []), doc] }));
  };

  // Progress per location
  const calcProgress = (prop) => {
    if (!prop) return 0;
    const userFields = ['streetAddress','city','state','zipCode','homeType','homeOwnership',
      'contactPerson','contactPhone','yearBuilt','bedrooms','lockBox','pool','generator',
      'garage','trashCollection','waterSupply','fireAlarmSystem'];
    const filled = userFields.filter(f => prop[f] && String(prop[f]).trim()).length;
    return Math.round((filled / userFields.length) * 100);
  };

  const selectedProp = data?.properties?.find(p => p.id === selectedPropId);

  // Customer logo — falls back to Decades if none provided
  const logoUrl = data?.providerLogo || './logo.png';

  // ── Login Screen ──
  if (!code) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: T.bg, padding: 20 }}>
        <div style={{ background: 'white', borderRadius: 16, padding: mobile ? '36px 24px' : '48px 40px', width: '100%', maxWidth: 420, boxShadow: '0 4px 24px rgba(0,0,0,0.08)' }}>
          <img src={logoUrl} alt={providerName || 'Logo'} style={{ width: '100%', maxWidth: 200, marginBottom: 20 }} />
          <h1 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: mobile ? 20 : 22, margin: '0 0 8px 0' }}>
            Location Information
          </h1>
          <p style={{ color: T.textLight, fontSize: 14, margin: '0 0 28px 0', lineHeight: 1.5 }}>
            Enter your access code to get started. Use demo1234 for a demo.
          </p>
          <input
            value={codeInput}
            onChange={e => { setCodeInput(e.target.value); setCodeError(''); }}
            onKeyDown={e => e.key === 'Enter' && handleLogin()}
            placeholder="Access Code"
            autoComplete="off"
            style={{
              width: '100%', padding: '14px 16px', fontSize: 18, border: `2px solid ${codeError ? T.red : T.border}`,
              borderRadius: 10, outline: 'none', boxSizing: 'border-box', fontFamily: T.fMono,
              letterSpacing: 3, textAlign: 'center', textTransform: 'uppercase',
            }}
            autoFocus
          />
          {codeError && <p style={{ color: T.red, fontSize: 13, margin: '8px 0 0' }}>{codeError}</p>}
          <button onClick={handleLogin} style={{
            width: '100%', marginTop: 20, padding: '14px', background: T.blue, color: 'white',
            border: 'none', borderRadius: 10, fontSize: 16, fontWeight: 600, cursor: 'pointer', fontFamily: T.fBody,
          }}>
            Get Started
          </button>
        </div>
      </div>
    );
  }

  // ── Welcome Screen ──
  if (showWelcome) {
    return <WelcomeScreen providerName={providerName} locationCount={data?.properties?.length || 0} logoUrl={logoUrl}
      onStart={() => { setShowWelcome(false); if (data?.properties?.length > 0) setSelectedPropId(data.properties[0].id); }} />;
  }

  if (!data) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: T.bg }}>
      <p style={{ color: T.textLight }}>Loading...</p>
    </div>
  );

  const TABS = [
    { id: 'locations', label: 'Locations', icon: '📍' },
    { id: 'documents', label: 'Documents', icon: '📄' },
    { id: 'services', label: 'Service Providers', icon: '🔧' },
    { id: 'team', label: 'Your Team', icon: '👥' },
  ];

  // ── Mobile Layout ──
  if (mobile) {
    return (
      <div style={{ minHeight: '100vh', background: T.bg, display: 'flex', flexDirection: 'column' }}>
        {offline && (
          <div style={{ background: '#FEF3C7', color: '#92400E', padding: '8px 12px', fontSize: 12, textAlign: 'center' }}>
            Saving locally — we'll sync when you're back online
          </div>
        )}
        {/* Header */}
        <div style={{ background: T.blue, color: 'white', padding: '12px 16px' }}>
          <div style={{ fontSize: 15, fontWeight: 700 }}>{providerName}</div>
          <div style={{ fontSize: 11, opacity: 0.7 }}>Tap a location to start</div>
        </div>

        {/* Content */}
        <div style={{ flex: 1, overflow: 'auto', padding: '12px' }}>
          {tab === 'locations' && !selectedPropId && (
            <div>
              {data.properties.map(p => {
                const prog = calcProgress(p);
                return (
                  <div key={p.id} onClick={() => selectProperty(p.id)} style={{
                    background: 'white', borderRadius: 10, padding: '14px 16px', marginBottom: 8,
                    border: `1px solid ${T.border}`, cursor: 'pointer',
                  }}>
                    <div style={{ fontSize: 14, fontWeight: 600, color: T.blue }}>
                      {p.upkeepName || p.streetAddress || 'New Location'}
                    </div>
                    <div style={{ fontSize: 12, color: T.textLight, marginTop: 2 }}>
                      {p.city ? `${p.city}, ${p.state}` : 'No address yet'}
                    </div>
                    <div style={{ marginTop: 8, height: 4, background: T.bg, borderRadius: 2 }}>
                      <div style={{ height: '100%', borderRadius: 2, width: `${prog}%`,
                        background: prog === 100 ? T.green : T.blueMid, transition: 'width 0.3s' }} />
                    </div>
                    <div style={{ fontSize: 11, color: prog === 100 ? T.green : T.textLight, marginTop: 4 }}>
                      {prog === 100 ? '✓ Complete' : `${prog}% filled in`}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
          {tab === 'locations' && selectedPropId && selectedProp && (
            <div>
              <button onClick={() => setSelectedPropId(null)} style={{
                background: 'none', border: 'none', color: T.blueMid, fontSize: 13, fontWeight: 600,
                cursor: 'pointer', marginBottom: 12, padding: 0,
              }}>
                ← All locations
              </button>
              <PropertyForm property={selectedProp} onChange={updateProperty}
                onDelete={() => { updateData(prev => ({ ...prev, properties: prev.properties.filter(p => p.id !== selectedPropId) })); setSelectedPropId(null); }}
                fieldConfig={fieldConfig} locationTypes={locationTypeNames} />
            </div>
          )}
          {tab === 'documents' && (
            <DocumentCapture documents={data.documents || []} onAdd={addDocument}
              locationName={selectedProp?.upkeepName || selectedProp?.streetAddress || 'General'} isMobile={true}
              propertyId={selectedProp?._dataverseId} />
          )}
          {tab === 'services' && (
            <VendorList vendors={data.vendors} onUpdate={(v) => updateData(prev => ({ ...prev, vendors: v }))} sessionId={data?._sessionId} />
          )}
          {tab === 'team' && (
            <AuthorizedUsers users={data.authorizedUsers || []} properties={data.properties}
              onUpdate={(u) => updateData(prev => ({ ...prev, authorizedUsers: u }))} sessionId={data?._sessionId} />
          )}
        </div>

        {/* Bottom tab bar */}
        <div style={{ display: 'flex', borderTop: `1px solid ${T.border}`, background: 'white', flexShrink: 0 }}>
          {TABS.map(t => (
            <button key={t.id} onClick={() => { setTab(t.id); if (t.id !== 'locations') setSelectedPropId(null); }} style={{
              flex: 1, padding: '10px 4px', background: 'none', border: 'none', cursor: 'pointer',
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2,
              color: tab === t.id ? T.blue : T.textLight, fontSize: 10, fontWeight: 600,
            }}>
              <span style={{ fontSize: 18 }}>{t.icon}</span>
              {t.label}
            </button>
          ))}
        </div>
      </div>
    );
  }

  // ── Desktop Layout ──
  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: T.bg }}>
      {offline && (
        <div style={{ background: '#FEF3C7', color: '#92400E', padding: '8px 16px', fontSize: 12, textAlign: 'center', borderBottom: '1px solid #F59E0B' }}>
          Your work is being saved locally. We'll sync when connection returns.
        </div>
      )}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Sidebar */}
        <div style={{ width: 280, background: T.blueDeep, color: 'white', display: 'flex', flexDirection: 'column', flexShrink: 0 }}>
          <div style={{ padding: '16px 16px 12px' }}>
            <img src={logoUrl} alt={providerName || 'Logo'} style={{ width: '100%', maxWidth: 160, marginBottom: 10 }} />
            <h2 style={{ fontFamily: T.fDisplay, fontSize: 15, margin: 0 }}>{providerName}</h2>
            {data.expiresAt && (
              <p style={{ fontSize: 10, color: T.blueMid, margin: '6px 0 0' }}>
                Access until {new Date(data.expiresAt).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
              </p>
            )}
          </div>

          {/* Navigation */}
          <div style={{ padding: '0 8px' }}>
            {TABS.map(t => (
              <button key={t.id} onClick={() => setTab(t.id)} style={{
                display: 'flex', alignItems: 'center', gap: 10, width: '100%',
                padding: '10px 12px', marginBottom: 2, borderRadius: 8, border: 'none', cursor: 'pointer',
                background: tab === t.id ? 'rgba(255,255,255,0.12)' : 'transparent',
                color: tab === t.id ? 'white' : 'rgba(255,255,255,0.6)',
                fontSize: 13, fontWeight: 600, textAlign: 'left',
              }}>
                <span style={{ fontSize: 16 }}>{t.icon}</span>
                {t.label}
              </button>
            ))}
          </div>

          {/* Location list when on Locations tab */}
          {tab === 'locations' && (
            <div style={{ flex: 1, overflow: 'auto', padding: '12px 8px', borderTop: '1px solid rgba(255,255,255,0.1)', marginTop: 8 }}>
              {data.properties.map(p => {
                const prog = calcProgress(p);
                const isSelected = selectedPropId === p.id;
                return (
                  <div key={p.id} onClick={() => selectProperty(p.id)} style={{
                    padding: '10px 12px', marginBottom: 4, borderRadius: 8, cursor: 'pointer',
                    background: isSelected ? 'rgba(255,255,255,0.15)' : 'transparent',
                  }}>
                    <div style={{ fontSize: 13, fontWeight: 600, color: 'white' }}>
                      {p.upkeepName || p.streetAddress || 'New Location'}
                    </div>
                    <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.5)', marginTop: 2 }}>
                      {p.city ? `${p.city}, ${p.state}` : 'No address yet'}
                    </div>
                    <div style={{ marginTop: 6, height: 3, background: 'rgba(255,255,255,0.15)', borderRadius: 2 }}>
                      <div style={{ height: '100%', borderRadius: 2, width: `${prog}%`,
                        background: prog === 100 ? T.green : T.blueMid, transition: 'width 0.3s' }} />
                    </div>
                    {prog === 100 && <div style={{ fontSize: 10, color: T.green, marginTop: 3 }}>✓ Complete</div>}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Main content */}
        <div style={{ flex: 1, overflow: 'auto', padding: '24px 32px' }}>
          {lockWarning && (
            <div style={{
              background: '#FEF2F2', border: '1px solid #F87171', borderRadius: 8,
              padding: '14px 18px', margin: '0 0 16px', fontSize: 13, color: '#991B1B',
            }}>
              <strong>This location is being edited by someone else.</strong>
              <div style={{ marginTop: 8, display: 'flex', gap: 8 }}>
                <button onClick={async () => {
                  const prop = data.properties.find(p => p.id === lockWarning.propertyId);
                  if (prop?._dataverseId) await forceAcquireLock(prop._dataverseId);
                  setSelectedPropId(lockWarning.propertyId); setLockWarning(null);
                }} style={{ background: '#DC2626', color: '#fff', border: 'none', borderRadius: 6, padding: '8px 14px', fontSize: 12, fontWeight: 600, cursor: 'pointer' }}>
                  Edit Anyway
                </button>
                <button onClick={() => setLockWarning(null)} style={{ background: '#F1F5F9', color: '#1E293B', border: '1px solid #E2E8F0', borderRadius: 6, padding: '8px 14px', fontSize: 12, cursor: 'pointer' }}>
                  Cancel
                </button>
              </div>
            </div>
          )}

          {tab === 'locations' && selectedProp && (
            <PropertyForm property={selectedProp} onChange={updateProperty}
              onDelete={() => { updateData(prev => ({ ...prev, properties: prev.properties.filter(p => p.id !== selectedPropId) })); setSelectedPropId(null); }}
              fieldConfig={fieldConfig} locationTypes={locationTypeNames} />
          )}
          {tab === 'locations' && !selectedProp && (
            <div style={{ textAlign: 'center', paddingTop: 80, color: T.textLight }}>
              <p style={{ fontSize: 18, marginBottom: 8 }}>Select a location to get started</p>
              <p style={{ fontSize: 14 }}>Pick one from the list on the left</p>
            </div>
          )}
          {tab === 'documents' && (
            <DocumentCapture documents={data.documents || []} onAdd={addDocument}
              locationName={selectedProp?.upkeepName || 'General'} isMobile={false}
              propertyId={selectedProp?._dataverseId} />
          )}
          {tab === 'services' && (
            <VendorList vendors={data.vendors} onUpdate={(v) => updateData(prev => ({ ...prev, vendors: v }))} sessionId={data?._sessionId} />
          )}
          {tab === 'team' && (
            <AuthorizedUsers users={data.authorizedUsers || []} properties={data.properties}
              onUpdate={(u) => updateData(prev => ({ ...prev, authorizedUsers: u }))} sessionId={data?._sessionId} />
          )}
        </div>
      </div>
    </div>
  );
}
