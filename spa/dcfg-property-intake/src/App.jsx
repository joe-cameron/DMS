import React, { useState, useEffect, useRef } from 'react';
import { T } from './tokens.js';
import { loadProviderData, saveProviderData, dataverseToForm, formFieldToDataverse, FIELD_MAP } from './storage.js';
import { loadFieldConfig, loadLocationTypes, USE_DATAVERSE, loadSession, loadProperties, loadVendors, loadDates, loadDelegations, savePropertyBatch, isOnline, acquireLock, forceAcquireLock, releaseLock, releaseLockSync, refreshLock, softDeleteDelegation } from './intakeApi.js';
import WelcomeScreen from './WelcomeScreen.jsx';
import HomeDashboard from './HomeDashboard.jsx';
import ConciergeHeader from './ConciergeHeader.jsx';
import VendorsScreen from './VendorsScreen.jsx';
import DatesScreen from './DatesScreen.jsx';
import LocationsScreen from './LocationsScreen.jsx';
import DocumentsScreen from './DocumentsScreen.jsx';
import DelegateModal from './DelegateModal.jsx';
import FeedbackModal from './FeedbackModal.jsx';
import { useHashRoute } from './useHashRoute.js';

// Access codes are managed in Dataverse dcfg_intake_sessions — no hardcoded backdoors

// Mobile detection
const isMobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || window.innerWidth < 768;

export default function App() {
  const [code, setCode] = useState('');
  const [providerName, setProviderName] = useState(null);
  const [data, setData] = useState(null);
  const [selectedPropId, setSelectedPropId] = useState(null);
  const [codeInput, setCodeInput] = useState('');
  const [codeError, setCodeError] = useState('');
  const [showWelcome, setShowWelcome] = useState(false);
  const [fieldConfig, setFieldConfig] = useState(null);
  const [locationTypeNames, setLocationTypeNames] = useState([]);
  const [offline, setOffline] = useState(false);
  const [lockWarning, setLockWarning] = useState(null);
  const [mobile] = useState(isMobile);
  const [delegateOpen, setDelegateOpen] = useState(false);
  const [delegateScope, setDelegateScope] = useState(null);
  const [feedbackOpen, setFeedbackOpen] = useState(false);
  const saveTimer = useRef(null);
  const pendingChanges = useRef({});
  const { path, navigate } = useHashRoute();

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

    const session = await loadSession(upper);
    if (session) {
      const [props, vendors, dates, delegations] = await Promise.all([
        loadProperties(session.dcfg_intake_sessionid),
        loadVendors(session.dcfg_intake_sessionid),
        loadDates(session.dcfg_intake_sessionid),
        loadDelegations(session.dcfg_intake_sessionid),
      ]);
      if (props) {
        const formProps = props.map(dataverseToForm);
        setCode(upper);
        setProviderName(session.dcfg_provider_name);
        setData({
          properties:   formProps,
          vendors:      vendors || [],
          dates:        dates || [],
          delegations:  delegations || [],
          expiresAt:    session.dcfg_expires_at,
          lastModified: new Date().toISOString(),
          _sessionId:   session.dcfg_intake_sessionid,
          _source:      'dataverse',
          documents:    [],
        });
        setShowWelcome(true);
        navigate('/home');
        return;
      }
    }
    const existing = loadProviderData(upper);
    if (existing) {
      setCode(upper); setProviderName(existing.providerName || upper);
      setData({ ...existing, dates: existing.dates || [], delegations: existing.delegations || [], documents: existing.documents || [] });
      navigate('/home');
      return;
    }
    try {
      const resp = await fetch(`./seeds/${upper}.json`);
      if (resp.ok) {
        const seed = await resp.json();
        setCode(upper); setProviderName(seed.providerName || upper);
        const d = { ...seed, dates: [], delegations: [], documents: [] };
        setData(d); saveProviderData(upper, d);
        setShowWelcome(true);
        navigate('/home');
        return;
      }
    } catch {}
    setCodeError('Invalid access code. Please check and try again.');
  }

  // Property actions
  async function selectProperty(propId) {
    if (propId === null) {
      if (selectedPropId && data) {
        const prev = data.properties.find(p => p.id === selectedPropId);
        if (prev?._dataverseId) await releaseLock(prev._dataverseId);
      }
      setSelectedPropId(null);
      setLockWarning(null);
      return;
    }
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

  // Delegation revoke handler
  const handleRevoke = async (delegationId) => {
    const ok = await softDeleteDelegation(delegationId);
    if (ok) {
      updateData(prev => ({
        ...prev,
        delegations: (prev.delegations || []).filter(d => d.dcfg_intake_delegationid !== delegationId),
      }));
    }
  };

  // Customer logo — falls back to Decades if none provided
  const logoUrl = data?.providerLogo || './logo.png';

  // ── Login Screen ──
  if (!code) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: T.bg, padding: 20 }}>
        <div style={{ background: 'white', borderRadius: 16, padding: mobile ? '36px 24px' : '48px 40px', width: '100%', maxWidth: 420, boxShadow: '0 4px 24px rgba(0,0,0,0.08)' }}>
          <img src={logoUrl} alt={providerName || 'Logo'} style={{ width: '100%', maxWidth: 200, marginBottom: 20 }} />
          <h1 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: mobile ? 20 : 22, margin: '0 0 8px 0' }}>
            Onboarding Concierge
          </h1>
          <p style={{ color: T.textLight, fontSize: 14, margin: '0 0 28px 0', lineHeight: 1.5 }}>
            Enter your access code to get started.
          </p>
          <input
            data-testid="code-input"
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
          <button data-testid="login-button" onClick={handleLogin} style={{
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
      onStart={() => { setShowWelcome(false); navigate('/home'); }} />;
  }

  if (!data) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: T.bg }}>
      <p style={{ color: T.textLight }}>Loading...</p>
    </div>
  );

  // ── Dashboard + Route-Driven Screens ──
  return (
    <div style={{ minHeight: '100vh', background: T.bg }}>
      {offline && (
        <div style={{ background: '#FEF3C7', color: '#92400E', padding: '8px 12px', fontSize: 12, textAlign: 'center' }}>
          Saving locally &mdash; we'll sync when you're back online
        </div>
      )}
      <ConciergeHeader
        providerName={providerName}
        onHome={() => navigate('/home')}
        onGlobalDelegate={() => { setDelegateScope(null); setDelegateOpen(true); }}
        onFeedback={() => setFeedbackOpen(true)}
        showBack={path !== '/home' && path !== '/'}
        delegations={data?.delegations || []}
        onRevoke={handleRevoke}
      />

      {lockWarning && (
        <div style={{
          background: '#FEF2F2', border: '1px solid #F87171', borderRadius: 8,
          padding: '14px 18px', margin: '16px 20px 0', fontSize: 13, color: '#991B1B',
        }}>
          <strong>This location is being edited by someone else.</strong>
          <div style={{ marginTop: 8, display: 'flex', gap: 8 }}>
            <button data-testid="force-edit" onClick={async () => {
              const prop = data.properties.find(p => p.id === lockWarning.propertyId);
              if (prop?._dataverseId) await forceAcquireLock(prop._dataverseId);
              setSelectedPropId(lockWarning.propertyId); setLockWarning(null);
            }} style={{ background: '#DC2626', color: '#fff', border: 'none', borderRadius: 6, padding: '8px 14px', fontSize: 12, fontWeight: 600, cursor: 'pointer' }}>
              Edit Anyway
            </button>
            <button data-testid="cancel-lock" onClick={() => setLockWarning(null)} style={{ background: '#F1F5F9', color: '#1E293B', border: '1px solid #E2E8F0', borderRadius: 6, padding: '8px 14px', fontSize: 12, cursor: 'pointer' }}>
              Cancel
            </button>
          </div>
        </div>
      )}

      {(path === '/home' || path === '/') && (
        <HomeDashboard data={data} navigate={navigate} onDelegate={(scope) => { setDelegateScope(scope); setDelegateOpen(true); }} />
      )}
      {path === '/home/vendors' && (
        <VendorsScreen data={data} updateData={updateData} sessionId={data._sessionId} />
      )}
      {path === '/home/dates' && (
        <DatesScreen data={data} updateData={updateData} sessionId={data._sessionId} />
      )}
      {path === '/home/locations' && (
        <LocationsScreen data={data} selectedPropId={selectedPropId} selectProperty={selectProperty} updateProperty={updateProperty} fieldConfig={fieldConfig} locationTypes={locationTypeNames} />
      )}
      {path === '/home/documents' && (
        <DocumentsScreen data={data} addDocument={addDocument} />
      )}

      {delegateOpen && (
        <DelegateModal
          scope={delegateScope}
          sessionId={data._sessionId}
          onClose={() => setDelegateOpen(false)}
          onCreated={(row) => updateData(prev => ({ ...prev, delegations: [...(prev.delegations || []), row] }))}
        />
      )}
      {feedbackOpen && (
        <FeedbackModal sessionId={data._sessionId} onClose={() => setFeedbackOpen(false)} />
      )}
    </div>
  );
}
