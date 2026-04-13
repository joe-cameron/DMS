import React, { useState } from 'react';
import { T } from './tokens.js';

export default function ConciergeHeader({ providerName, onHome, onGlobalDelegate, onFeedback, showBack, delegations = [], onRevoke }) {
  const [helpersOpen, setHelpersOpen] = useState(false);
  const activeDelegations = (delegations || []).filter(d => d.dcfg_active_flag !== false);

  return (
    <div data-testid="concierge-header" style={{ background: T.blue, color: 'white', padding: '12px 18px', display: 'flex', alignItems: 'center', gap: 10 }}>
      {showBack && (
        <button data-testid="header-back" onClick={onHome} style={backBtn}>&larr; Home</button>
      )}
      <div>
        <div style={{ fontSize: 15, fontWeight: 700 }}>{providerName}</div>
        <div style={{ fontSize: 11, opacity: 0.7 }}>Onboarding Concierge</div>
      </div>
      <div style={{ marginLeft: 'auto', display: 'flex', gap: 8, position: 'relative' }}>
        <button data-testid="header-feedback" onClick={onFeedback} style={pill}>{'\uD83D\uDCAC'} Give Feedback</button>
        <button data-testid="header-invite" onClick={() => { onGlobalDelegate(); }} style={pill}>{'\uD83D\uDCE7'} Invite Helpers</button>
        {activeDelegations.length > 0 && (
          <button data-testid="header-helpers-toggle" onClick={() => setHelpersOpen(!helpersOpen)} style={pill}>
            {activeDelegations.length} helper{activeDelegations.length === 1 ? '' : 's'}
          </button>
        )}
        {helpersOpen && (
          <div data-testid="helpers-dropdown" style={dropdown}>
            {activeDelegations.map(d => (
              <div key={d.dcfg_intake_delegationid} style={helperRow}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 600, color: T.blue }}>{d.dcfg_name}</div>
                  <div style={{ fontSize: 11, color: T.textLight }}>{d.dcfg_delegate_email}</div>
                </div>
                <button data-testid={`revoke-${d.dcfg_intake_delegationid}`} onClick={() => onRevoke(d.dcfg_intake_delegationid)} style={{ background: 'none', border: 'none', color: T.red, fontSize: 11, cursor: 'pointer' }}>Revoke</button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

const pill      = { background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)', color: 'white', padding: '6px 12px', borderRadius: 20, fontSize: 12, fontWeight: 600, cursor: 'pointer' };
const backBtn   = { background: 'none', border: 'none', color: 'white', fontSize: 13, cursor: 'pointer', padding: 0, marginRight: 6 };
const dropdown  = { position: 'absolute', top: 40, right: 0, background: 'white', boxShadow: '0 4px 16px rgba(0,0,0,0.15)', borderRadius: 8, width: 280, maxHeight: 320, overflow: 'auto', zIndex: 50 };
const helperRow = { display: 'flex', alignItems: 'center', padding: '10px 14px', borderBottom: '1px solid #f1f5f9' };
