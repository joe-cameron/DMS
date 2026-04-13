import React, { useState } from 'react';
import { T } from './tokens.js';
import { submitFeedback } from './intakeApi.js';

export default function FeedbackModal({ sessionId, onClose }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const send = async () => {
    if (!text.trim()) return;
    setBusy(true);
    const ok = await submitFeedback(sessionId, text.trim());
    setBusy(false);
    if (ok) { setSent(true); setTimeout(onClose, 1200); }
    else    { alert('Could not send feedback. Please try again.'); }
  };

  return (
    <div role="dialog" aria-modal="true" style={backdrop} onClick={onClose}>
      <div data-testid="feedback-modal" style={modal} onClick={e => e.stopPropagation()}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, margin: '0 0 4px' }}>Give feedback</h3>
        <p style={{ color: T.textLight, fontSize: 13, margin: '0 0 14px' }}>What's working, what isn't, what's missing. Anything.</p>
        {sent ? (
          <div data-testid="feedback-sent" style={{ padding: 20, textAlign: 'center', color: T.textLight, fontSize: 14 }}>Thanks &mdash; we got it.</div>
        ) : (
          <>
            <textarea data-testid="feedback-text" value={text} onChange={e => setText(e.target.value)} rows={6} style={{ width: '100%', padding: 10, border: '1px solid #cbd5e1', borderRadius: 6, fontSize: 14, fontFamily: T.fBody, resize: 'vertical', boxSizing: 'border-box' }} />
            <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
              <button data-testid="feedback-cancel" onClick={onClose} disabled={busy} style={btnSecondary}>Cancel</button>
              <button data-testid="feedback-send" onClick={send} disabled={busy || !text.trim()} style={btnPrimary}>{busy ? 'Sending\u2026' : 'Send'}</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

const backdrop     = { position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 };
const modal        = { background: 'white', borderRadius: 12, padding: 24, width: '100%', maxWidth: 460 };
const btnPrimary   = { flex: 1, padding: 10, background: '#2563eb', color: 'white', border: 'none', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
const btnSecondary = { flex: 1, padding: 10, background: 'white', color: '#2563eb', border: '1px solid #cbd5e1', borderRadius: 8, fontWeight: 600, cursor: 'pointer' };
