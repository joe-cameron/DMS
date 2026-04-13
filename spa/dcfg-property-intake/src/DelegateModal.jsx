import React, { useState } from 'react';
import { T } from './tokens.js';
import { createDelegation } from './intakeApi.js';
import { loadSenderIdentity, saveSenderIdentity } from './storage.js';

const SCOPES = [
  { value: 100000000, label: 'Vendors', key: 'vendors' },
  { value: 100000001, label: 'Dates', key: 'dates' },
  { value: 100000002, label: 'Locations', key: 'locations' },
  { value: 100000003, label: 'Documents', key: 'documents' },
  { value: 100000004, label: 'All', key: 'all' },
];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default function DelegateModal({ scope, sessionId, onClose, onCreated }) {
  const initial = loadSenderIdentity();
  const [senderName, setSenderName]   = useState(initial.senderName || '');
  const [senderEmail, setSenderEmail] = useState(initial.senderEmail || '');
  const [delegateName, setDelegateName]   = useState('');
  const [delegateEmail, setDelegateEmail] = useState('');
  const [note, setNote] = useState('');
  const [cardScope, setCardScope] = useState(scope || 'all');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  const valid = senderName && EMAIL_RE.test(senderEmail) && delegateName && EMAIL_RE.test(delegateEmail);

  const submit = async () => {
    if (!valid) { setErr('Please fill out all fields with a valid email.'); return; }
    setBusy(true); setErr('');
    saveSenderIdentity({ senderName, senderEmail });
    const scopeValue = SCOPES.find(s => s.key === cardScope)?.value ?? 100000004;
    const created = await createDelegation(sessionId, { delegateName, delegateEmail, senderName, senderEmail, personalNote: note, cardScope: scopeValue });
    setBusy(false);
    if (!created) { setErr('Could not send the invite. Try again.'); return; }
    onCreated({ dcfg_intake_delegationid: created.dcfg_intake_delegationid, dcfg_name: delegateName, dcfg_delegate_email: delegateEmail, dcfg_card_scope: scopeValue, dcfg_active_flag: true });
    onClose();
  };

  return (
    <div role="dialog" aria-modal="true" style={backdrop} onClick={onClose}>
      <div data-testid="delegate-modal" style={modal} onClick={e => e.stopPropagation()}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, margin: '0 0 4px' }}>Invite a helper</h3>
        <p style={{ color: T.textLight, fontSize: 13, margin: '0 0 16px' }}>They'll get an email with a link. They use the same access code to log in.</p>

        <Field label="Your name">
          <input data-testid="sender-name" value={senderName} onChange={e => setSenderName(e.target.value)} style={input} />
        </Field>
        <Field label="Your email">
          <input data-testid="sender-email" value={senderEmail} onChange={e => setSenderEmail(e.target.value)} style={input} />
        </Field>
        <hr style={{ border: 0, borderTop: `1px solid ${T.border}`, margin: '12px 0' }} />
        <Field label="Who you're inviting &mdash; name">
          <input data-testid="delegate-name" value={delegateName} onChange={e => setDelegateName(e.target.value)} style={input} />
        </Field>
        <Field label="Who you're inviting &mdash; email">
          <input data-testid="delegate-email" value={delegateEmail} onChange={e => setDelegateEmail(e.target.value)} style={input} />
        </Field>
        <Field label="What you'd like them to help with">
          <select data-testid="scope-select" value={cardScope} onChange={e => setCardScope(e.target.value)} style={input}>
            {SCOPES.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}
          </select>
        </Field>
        <Field label="Personal note (optional)">
          <textarea data-testid="note" value={note} onChange={e => setNote(e.target.value)} rows={3} style={{ ...input, resize: 'vertical', fontFamily: T.fBody }} />
        </Field>

        {err && <div data-testid="delegate-error" style={{ color: T.red, fontSize: 13, marginTop: 8 }}>{err}</div>}
        <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
          <button data-testid="cancel" onClick={onClose} disabled={busy} style={btnSecondary}>Cancel</button>
          <button data-testid="send" onClick={submit} disabled={!valid || busy} style={btnPrimary}>{busy ? 'Sending\u2026' : 'Send invite'}</button>
        </div>
      </div>
    </div>
  );
}

const Field = ({ label, children }) => (
  <label style={{ display: 'block', marginBottom: 10 }}>
    <div style={{ fontSize: 12, fontWeight: 600, color: '#334155', marginBottom: 4 }}>{label}</div>
    {children}
  </label>
);

const backdrop = { position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 };
const modal = { background: 'white', borderRadius: 12, padding: 24, width: '100%', maxWidth: 460, maxHeight: '90vh', overflow: 'auto' };
const input = { width: '100%', padding: '8px 10px', border: '1px solid #cbd5e1', borderRadius: 6, fontSize: 14, boxSizing: 'border-box' };
const btnPrimary = { flex: 1, padding: '10px', background: '#2563eb', color: 'white', border: 'none', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
const btnSecondary = { flex: 1, padding: '10px', background: 'white', color: '#2563eb', border: '1px solid #cbd5e1', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
