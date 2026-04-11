import React from 'react';
import { T } from './tokens.js';

export default function SegmentedControl({ label, options, value, onChange, hint }) {
  return (
    <div style={{ marginBottom: 14 }}>
      {label && (
        <label style={{ fontSize: 12, fontWeight: 600, color: T.blue, display: 'block', marginBottom: 6 }}>
          {label}
        </label>
      )}
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {options.map(opt => {
          const optValue = typeof opt === 'string' ? opt : opt.value;
          const optLabel = typeof opt === 'string' ? opt : opt.label;
          const isActive = value === optValue;
          // Special colors for Y/N
          const isY = optValue === 'Y';
          const isN = optValue === 'N';
          let bg = isActive ? T.bluePale : 'white';
          let borderColor = isActive ? T.blueMid : T.border;
          let textColor = isActive ? T.blue : T.textLight;
          if (isActive && isY) { bg = T.greenLt; borderColor = T.green; textColor = T.green; }
          if (isActive && isN) { bg = T.redLt; borderColor = T.red; textColor = T.red; }

          return (
            <button
              key={optValue}
              onClick={() => onChange(optValue)}
              style={{
                padding: '7px 16px', fontSize: 13, fontWeight: 600, cursor: 'pointer',
                borderRadius: 6, border: `2px solid ${borderColor}`,
                background: bg, color: textColor, fontFamily: T.fBody,
                transition: 'all 0.15s',
                minWidth: 44,
              }}
            >
              {optLabel}
            </button>
          );
        })}
      </div>
      {hint && <div style={{ fontSize: 11, color: T.textLight, marginTop: 4, fontStyle: 'italic' }}>{hint}</div>}
    </div>
  );
}
