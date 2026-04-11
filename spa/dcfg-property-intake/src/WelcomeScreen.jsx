import React from 'react';
import { T } from './tokens.js';

export default function WelcomeScreen({ providerName, locationCount, onStart, logoUrl }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'center', alignItems: 'center',
      minHeight: '100vh', background: T.bg, padding: 20,
    }}>
      <div style={{
        background: 'white', borderRadius: 16, padding: '48px 40px',
        maxWidth: 520, width: '100%', boxShadow: '0 4px 24px rgba(0,0,0,0.08)',
        textAlign: 'center',
      }}>
        <img src={logoUrl || './logo.png'} alt={providerName || 'Logo'} style={{ width: '100%', maxWidth: 200, marginBottom: 24 }} />

        <h1 style={{
          fontFamily: T.fDisplay, color: T.blue, fontSize: 24,
          margin: '0 0 8px', fontWeight: 700,
        }}>
          Welcome, {providerName}
        </h1>

        <p style={{ color: T.textLight, fontSize: 15, margin: '0 0 28px', lineHeight: 1.6 }}>
          We've set up <strong style={{ color: T.blue }}>{locationCount} location{locationCount !== 1 ? 's' : ''}</strong> for you to fill in.
          <br />Take your time — there's no rush.
        </p>

        <div style={{
          background: T.bg, borderRadius: 12, padding: '20px 24px',
          textAlign: 'left', marginBottom: 28,
        }}>
          <p style={{ fontSize: 13, fontWeight: 600, color: T.blue, margin: '0 0 12px' }}>
            Here's what helps us serve your buildings:
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
              <span style={{ color: T.green, fontSize: 16, lineHeight: 1 }}>✓</span>
              <span style={{ fontSize: 13, color: '#475569', lineHeight: 1.4 }}>
                Basic info about each location — who to contact, what kind of building
              </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
              <span style={{ color: T.green, fontSize: 16, lineHeight: 1 }}>✓</span>
              <span style={{ fontSize: 13, color: '#475569', lineHeight: 1.4 }}>
                What systems and features are on site — heating, pool, generator
              </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
              <span style={{ color: T.green, fontSize: 16, lineHeight: 1 }}>✓</span>
              <span style={{ fontSize: 13, color: '#475569', lineHeight: 1.4 }}>
                Any documents you have — leases, inspections, service contracts
              </span>
            </div>
          </div>
        </div>

        <p style={{ fontSize: 13, color: T.textLight, margin: '0 0 24px', lineHeight: 1.5 }}>
          Fill in what you know. Skip what you don't.
          <br />Your work saves automatically — come back anytime.
        </p>

        <button onClick={onStart} style={{
          width: '100%', padding: '14px', background: T.blue, color: 'white',
          border: 'none', borderRadius: 10, fontSize: 16, fontWeight: 600,
          cursor: 'pointer', fontFamily: T.fBody,
        }}>
          Let's get started
        </button>
      </div>
    </div>
  );
}
