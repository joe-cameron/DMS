import React from 'react';
import { T } from './tokens.js';
import DocumentCapture from './DocumentCapture.jsx';

const isMobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || window.innerWidth < 768;

export default function DocumentsScreen({ data, addDocument }) {
  return (
    <div style={{ padding: '24px 20px', maxWidth: 780, margin: '0 auto' }}>
      <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 4px' }}>Documents</h2>
      <p style={{ color: T.textLight, fontSize: 14, margin: '0 0 20px' }}>Floor plans, insurance COI, W-9s, manuals &mdash; anything that isn't tied to a specific date.</p>
      <DocumentCapture documents={data?.documents || []} onAdd={addDocument} isMobile={isMobile()} />
    </div>
  );
}
