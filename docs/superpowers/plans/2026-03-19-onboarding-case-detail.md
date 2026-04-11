# Onboarding Case Detail — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the onboarding case detail screen from a read-only checklist tracker into a full transactional detail view with editable fields, customer contact info, voice input, soft delete, and close/reopen lifecycle.

**Architecture:** Modify existing OnboardingDetail.jsx and Onboarding.jsx in-place. Add SpeechMic.jsx as a new reusable component. Extend portalApi.js with wider customer expand and active_flag filtering. No new routes or major structural changes.

**Tech Stack:** React 16 (class-compatible patterns), Dataverse Web API (OData), Web Speech API, Power Pages deployment.

**Spec:** `docs/superpowers/specs/2026-03-19-onboarding-case-detail-design.md`

---

## Chunk 1: SpeechMic Component + portalApi Changes

### Task 1: Create SpeechMic.jsx

**Files:**
- Create: `spa/dcfg-shell/src/SpeechMic.jsx`

- [ ] **Step 1: Create the SpeechMic component**

```jsx
/**
 * SpeechMic.jsx — Voice-to-text button for textareas
 *
 * Uses Web Speech API (Safari 14.1+, Chrome).
 * Returns null if API unavailable. Appends transcript to existing text.
 *
 * Usage:
 *   <SpeechMic onTranscript={text => setNotes(prev => prev + ' ' + text)} />
 */
import React, { useState, useRef } from 'react';

const SpeechRecognition = typeof window !== 'undefined'
  ? (window.SpeechRecognition || window.webkitSpeechRecognition)
  : null;

export default function SpeechMic({ onTranscript, lang = 'en-US', disabled = false }) {
  const [listening, setListening] = useState(false);
  const recRef = useRef(null);

  if (!SpeechRecognition) return null;

  function toggle() {
    if (disabled) return;
    if (listening) {
      recRef.current?.stop();
      return;
    }
    const rec = new SpeechRecognition();
    rec.lang = lang;
    rec.interimResults = false;
    rec.continuous = false; // single-utterance for Safari compat
    rec.onresult = (e) => {
      const transcript = e.results[0]?.[0]?.transcript;
      if (transcript) onTranscript(transcript);
    };
    rec.onerror = () => setListening(false);
    rec.onend = () => setListening(false);
    recRef.current = rec;
    setListening(true);
    rec.start();
  }

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={disabled}
      title={listening ? 'Stop recording' : 'Voice input'}
      style={{
        background: listening ? '#DC2626' : '#F1F5F9',
        color: listening ? '#fff' : '#64748B',
        border: 'none',
        borderRadius: '4px',
        padding: '4px 8px',
        fontSize: '14px',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.4 : 1,
        flexShrink: 0,
        lineHeight: 1,
      }}
    >
      {listening ? '\u23F9' : '\uD83C\uDFA4'}
    </button>
  );
}
```

Write this file to `spa/dcfg-shell/src/SpeechMic.jsx`.

- [ ] **Step 2: Verify file exists**

Run: `ls spa/dcfg-shell/src/SpeechMic.jsx`
Expected: file listed

---

### Task 2: Update portalApi.js — Widen Customer Expand on Case Detail

**Files:**
- Modify: `spa/dcfg-shell/src/portalApi.js`

- [ ] **Step 1: Find the onboarding case detail query in OnboardingDetail.jsx**

The query is at line 101 of `spa/dcfg-shell/src/screens/OnboardingDetail.jsx`. It expands customer with only `dcfg_customerid,dcfg_name,dcfg_primary_contact_email`. This will be updated in Task 4 when we rebuild the detail screen. No portalApi.js change needed for this — the query is inline in OnboardingDetail.jsx.

- [ ] **Step 2: Add active_flag filter to fetchOnboardingCases in portalApi.js**

In `spa/dcfg-shell/src/portalApi.js`, find the `fetchOnboardingCases` function (around line 328-331). The current filter is:

```javascript
const f = custId ? `_dcfg_customer_id_value eq ${custId}` : `dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed}`;
```

Replace with:

```javascript
const activeFilter = '(dcfg_active_flag eq true or dcfg_active_flag eq null)';
const f = custId ? `_dcfg_customer_id_value eq ${custId} and ${activeFilter}` : `dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed} and ${activeFilter}`;
```

- [ ] **Step 3: Add dcfg_active_flag to the $select in fetchOnboardingCases**

In the same function, add `dcfg_active_flag` to the `$select` clause so the list screen can show it:

Current `$select`:
```
dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes
```

New `$select`:
```
dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes,dcfg_active_flag
```

- [ ] **Step 4: Verify portalApi.js has no syntax errors**

Run: `cd spa/dcfg-shell && npx -y acorn --ecma2020 --module src/portalApi.js > /dev/null`
Expected: no errors

---

## Chunk 2: Onboarding List — Soft Delete, Restore, Active/Deleted Filter

### Task 3: Update Onboarding.jsx — Add Active/Deleted Toggle + Delete/Restore

**Files:**
- Modify: `spa/dcfg-shell/src/screens/Onboarding.jsx`

- [ ] **Step 1: Add imports for apiPatch and useToast**

At the top of `Onboarding.jsx`, update the import from portalApi.js to include `apiPatch`:

```javascript
import {
  apiGet, apiPost, apiPostReturn, apiPatch, bind, EntitySets, OnboardingCaseStatus,
  AuditActionType, writeAuditLog, fetchCustomers, copyTemplateStepsToCase,
} from '../portalApi.js';
```

Add toast import:
```javascript
import { useToast } from '../Toast';
```

- [ ] **Step 2: Add showDeleted state and toast hook**

Inside the `Onboarding` function, after the existing state declarations (line 45), add:

```javascript
const [showDeleted, setShowDeleted] = useState(false);
const toast = useToast();
```

- [ ] **Step 3: Update loadCases to filter by active_flag**

In the `loadCases` callback, update the filter construction (currently lines 49-51):

Replace:
```javascript
const filterParts = [];
if (statusFilter) filterParts.push(`dcfg_status eq ${statusFilter}`);
const filterStr = filterParts.length > 0 ? `$filter=${filterParts.join(' and ')}&` : '';
```

With:
```javascript
const filterParts = [];
if (showDeleted) {
  filterParts.push('dcfg_active_flag eq false');
} else {
  filterParts.push('(dcfg_active_flag eq true or dcfg_active_flag eq null)');
}
if (statusFilter) filterParts.push(`dcfg_status eq ${statusFilter}`);
const filterStr = `$filter=${filterParts.join(' and ')}&`;
```

Also add `showDeleted` to the `useCallback` dependency array:

```javascript
}, [statusFilter, showDeleted]);
```

- [ ] **Step 4: Add dcfg_active_flag to the inline $select**

In the apiGet call inside loadCases (line 53), add `dcfg_active_flag` to the `$select`:

Current:
```
$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes
```

New:
```
$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes,dcfg_active_flag
```

- [ ] **Step 5: Add handleDelete and handleRestore functions**

After the `handleNewCase` function (after line 137), add:

```javascript
async function handleDelete(e, caseRow) {
  e.stopPropagation(); // prevent row click navigation
  try {
    await apiPatch(`/${EntitySets.onboardingCases}(${caseRow.dcfg_onboarding_caseid})`, {
      dcfg_active_flag: false,
    });
    await writeAuditLog({
      targetTable: 'dcfg_onboarding_case',
      targetRecordId: caseRow.dcfg_onboarding_caseid,
      actionType: AuditActionType.Other,
      performedBy: user?.email || 'unknown',
      newValue: `Soft-deleted onboarding case ${caseRow.dcfg_case_number}`,
    }).catch(() => {});
    toast?.show('ok', `Case ${caseRow.dcfg_case_number} deleted`);
    loadCases();
  } catch (err) {
    toast?.show('err', `Delete failed: ${err.message}`);
  }
}

async function handleRestore(e, caseRow) {
  e.stopPropagation();
  try {
    await apiPatch(`/${EntitySets.onboardingCases}(${caseRow.dcfg_onboarding_caseid})`, {
      dcfg_active_flag: true,
    });
    await writeAuditLog({
      targetTable: 'dcfg_onboarding_case',
      targetRecordId: caseRow.dcfg_onboarding_caseid,
      actionType: AuditActionType.Other,
      performedBy: user?.email || 'unknown',
      newValue: `Restored onboarding case ${caseRow.dcfg_case_number}`,
    }).catch(() => {});
    toast?.show('ok', `Case ${caseRow.dcfg_case_number} restored`);
    loadCases();
  } catch (err) {
    toast?.show('err', `Restore failed: ${err.message}`);
  }
}
```

- [ ] **Step 6: Add Active/Deleted toggle to the filter bar**

In the JSX, in the filter bar area (around line 145-156), add the toggle button after the status select and before the + New Case button:

```jsx
<button
  onClick={() => setShowDeleted(d => !d)}
  style={{
    ...btnSecondary,
    backgroundColor: showDeleted ? '#FEF2F2' : '#F1F5F9',
    color: showDeleted ? '#DC2626' : '#1E293B',
    border: showDeleted ? '1px solid #FECACA' : '1px solid #E2E8F0',
  }}
>
  {showDeleted ? 'Showing Deleted' : 'Active'}
</button>
```

- [ ] **Step 7: Add Action column to the table**

Add an 8th `<th>` header: `<th>Action</th>`

Update the colSpan on the empty-state td from 7 to 8.

Add a new `<td>` at the end of each row, before the closing `</tr>`:

```jsx
<td onClick={e => e.stopPropagation()}>
  {showDeleted ? (
    <button onClick={(e) => handleRestore(e, c)} style={{ ...btnSecondary, padding: '4px 10px', fontSize: '11px' }}>
      Restore
    </button>
  ) : (
    <button onClick={(e) => handleDelete(e, c)} style={{ ...btnSecondary, padding: '4px 10px', fontSize: '11px', color: '#DC2626', borderColor: '#FECACA' }}>
      Delete
    </button>
  )}
</td>
```

- [ ] **Step 8: Verify no syntax errors**

Run: `cd spa/dcfg-shell && npx -y acorn-jsx --ecma2020 src/screens/Onboarding.jsx > /dev/null 2>&1 || node -e "try{require('./src/screens/Onboarding.jsx')}catch(e){console.log('OK - JSX needs build')}"`

---

## Chunk 3: OnboardingDetail.jsx — Rebuilt Info Section + Action Bar

### Task 4: Rebuild OnboardingDetail.jsx Main Component

**Files:**
- Modify: `spa/dcfg-shell/src/screens/OnboardingDetail.jsx`

This is the largest task. We rebuild the main `OnboardingDetail` function component to add:
- Editable case form state + dirty tracking
- Customer contact fields from expanded query
- Action bar (Save, Close, Delete, Reopen)
- Two-column info layout
- Full-width notes with SpeechMic

- [ ] **Step 1: Add new imports**

At the top of OnboardingDetail.jsx, update imports:

```javascript
import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import {
  apiGet, apiPatch, callFlow, EntitySets, fetchOnboardingChecklist,
  OnboardingCaseStatus, OnboardingPhase, OnboardingPhaseLabel,
  AuditActionType, writeAuditLog,
} from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import { useToast } from '../Toast';
import SpeechMic from '../SpeechMic.jsx';
```

- [ ] **Step 2: Update the case detail API query**

In the `loadCase` callback, replace the apiGet call (line 100-102) with the widened customer expand:

```javascript
apiGet(
  `/${EntitySets.onboardingCases}(${id})?$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes,dcfg_active_flag&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name,dcfg_primary_contact_name,dcfg_primary_contact_email,dcfg_primary_contact_phone,dcfg_primary_contact_title,dcfg_president_name,dcfg_president_title),dcfg_msa_id($select=dcfg_msaid,dcfg_name)`
),
```

- [ ] **Step 3: Add editable form state, dirty tracking, toast, and navigate**

Inside the `OnboardingDetail` function, after the existing state declarations and before `loadCase`, add:

```javascript
const navigate = useNavigate();
const toast = useToast();

// Editable case-level form
const [caseForm, setCaseForm] = useState(null);
const [contactForm, setContactForm] = useState(null);
const [dirty, setDirty] = useState(false);
```

- [ ] **Step 4: Initialize forms after case loads**

In the `loadCase` callback, after `setOnboardingCase(caseRes);` (line 105), add form initialization:

```javascript
const cust = caseRes['dcfg_customer_id'] || {};
setCaseForm({
  dcfg_case_label:     caseRes.dcfg_case_label || '',
  dcfg_status:         caseRes.dcfg_status,
  dcfg_initiated_date: caseRes.dcfg_initiated_date || '',
  dcfg_completed_date: caseRes.dcfg_completed_date || '',
  dcfg_notes:          caseRes.dcfg_notes || '',
});
setContactForm({
  dcfg_primary_contact_name:  cust.dcfg_primary_contact_name || '',
  dcfg_primary_contact_title: cust.dcfg_primary_contact_title || '',
  dcfg_primary_contact_email: cust.dcfg_primary_contact_email || '',
  dcfg_primary_contact_phone: cust.dcfg_primary_contact_phone || '',
  dcfg_president_name:        cust.dcfg_president_name || '',
  dcfg_president_title:       cust.dcfg_president_title || '',
});
setDirty(false);
```

- [ ] **Step 5: Add form update helpers**

After the form state declarations, add:

```javascript
function updateCase(field, value) {
  setCaseForm(prev => ({ ...prev, [field]: value }));
  setDirty(true);
}

function updateContact(field, value) {
  setContactForm(prev => ({ ...prev, [field]: value }));
  setDirty(true);
}
```

- [ ] **Step 6: Add beforeunload guard for dirty state**

After the `useEffect` for loadCase, add:

```javascript
useEffect(() => {
  function warn(e) { if (dirty) { e.preventDefault(); e.returnValue = ''; } }
  window.addEventListener('beforeunload', warn);
  return () => window.removeEventListener('beforeunload', warn);
}, [dirty]);
```

- [ ] **Step 7: Add handleSave function**

After the form helpers, add:

```javascript
async function handleSave() {
  setSaving(true);
  const caseId = onboardingCase.dcfg_onboarding_caseid;
  try {
    await apiPatch(`/${EntitySets.onboardingCases}(${caseId})`, {
      dcfg_case_label:     caseForm.dcfg_case_label || null,
      dcfg_status:         Number(caseForm.dcfg_status),
      dcfg_initiated_date: caseForm.dcfg_initiated_date || null,
      dcfg_completed_date: caseForm.dcfg_completed_date || null,
      dcfg_notes:          caseForm.dcfg_notes || null,
    });
  } catch (err) {
    toast?.show('err', `Case save failed: ${err.message}`);
    setSaving(false);
    return;
  }

  const custId = onboardingCase['dcfg_customer_id']?.dcfg_customerid;
  if (custId) {
    try {
      await apiPatch(`/${EntitySets.customers}(${custId})`, contactForm);
    } catch (err) {
      toast?.show('err', `Contact info failed to save \u2014 case data was saved`);
      setSaving(false);
      setDirty(false);
      loadCase();
      return;
    }
  }

  toast?.show('ok', 'Changes saved');
  setDirty(false);
  setSaving(false);
  loadCase();
}
```

- [ ] **Step 8: Add handleClose, handleReopen, handleDelete functions**

```javascript
async function handleClose() {
  setSaving(true);
  const caseId = onboardingCase.dcfg_onboarding_caseid;
  const patch = { dcfg_status: OnboardingCaseStatus.Closed };
  if (!onboardingCase.dcfg_completed_date) {
    patch.dcfg_completed_date = new Date().toISOString().split('T')[0];
  }
  try {
    await apiPatch(`/${EntitySets.onboardingCases}(${caseId})`, patch);
    await writeAuditLog({
      targetTable: 'dcfg_onboarding_case', targetRecordId: caseId,
      actionType: AuditActionType.StatusChanged, performedBy: user?.email || 'unknown',
      newValue: `Closed onboarding case ${onboardingCase.dcfg_case_number}`,
    }).catch(() => {});
    toast?.show('ok', 'Case closed');
    setDirty(false);
    loadCase();
  } catch (err) {
    toast?.show('err', `Close failed: ${err.message}`);
  }
  setSaving(false);
}

async function handleReopen() {
  setSaving(true);
  const caseId = onboardingCase.dcfg_onboarding_caseid;
  try {
    await apiPatch(`/${EntitySets.onboardingCases}(${caseId})`, {
      dcfg_status: OnboardingCaseStatus.InProgress,
    });
    await writeAuditLog({
      targetTable: 'dcfg_onboarding_case', targetRecordId: caseId,
      actionType: AuditActionType.StatusChanged, performedBy: user?.email || 'unknown',
      newValue: `Reopened onboarding case ${onboardingCase.dcfg_case_number}`,
    }).catch(() => {});
    toast?.show('ok', 'Case reopened');
    setDirty(false);
    loadCase();
  } catch (err) {
    toast?.show('err', `Reopen failed: ${err.message}`);
  }
  setSaving(false);
}

async function handleDeleteCase() {
  setSaving(true);
  const caseId = onboardingCase.dcfg_onboarding_caseid;
  try {
    await apiPatch(`/${EntitySets.onboardingCases}(${caseId})`, { dcfg_active_flag: false });
    await writeAuditLog({
      targetTable: 'dcfg_onboarding_case', targetRecordId: caseId,
      actionType: AuditActionType.Other, performedBy: user?.email || 'unknown',
      newValue: `Soft-deleted onboarding case ${onboardingCase.dcfg_case_number}`,
    }).catch(() => {});
    toast?.show('ok', `Case ${onboardingCase.dcfg_case_number} deleted`);
    navigate('/onboarding');
  } catch (err) {
    toast?.show('err', `Delete failed: ${err.message}`);
  }
  setSaving(false);
}
```

- [ ] **Step 9: Replace the JSX — breadcrumb, action bar, and info section**

Replace the entire return JSX block (lines 194-273) with the new layout. The key sections are:

**Action bar** replaces the old breadcrumb + header (lines 196-209):

```jsx
const isClosed = onboardingCase.dcfg_status === OnboardingCaseStatus.Closed;

return (
  <div className="page-content">
    {/* Action bar */}
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: GREY }}>
        <Link to="/onboarding" style={{ color: GREY }}>Onboarding</Link>
        <span>{'\u203A'}</span>
        <strong style={{ color: NAVY }}>{onboardingCase.dcfg_case_number}</strong>
        <span className={`badge ${badge.cls}`}>{badge.label}</span>
      </div>
      <div style={{ display: 'flex', gap: '8px' }}>
        {!isClosed && (
          <>
            <button onClick={handleSave} disabled={saving || !dirty} style={{
              ...btnAction, backgroundColor: dirty ? '#1B2A4A' : '#F1F5F9',
              color: dirty ? WHITE : '#64748B', border: dirty ? 'none' : '1px solid #E2E8F0',
            }}>
              {saving ? 'Saving\u2026' : dirty ? '\u2022 Save Changes' : 'Save Changes'}
            </button>
            <button onClick={handleClose} disabled={saving} style={{ ...btnAction, backgroundColor: NAVY, color: WHITE }}>
              Close Case
            </button>
            <button onClick={handleDeleteCase} disabled={saving} style={{
              ...btnAction, backgroundColor: WHITE, color: '#DC2626', border: '1px solid #FCA5A5',
            }}>
              Delete
            </button>
          </>
        )}
        {isClosed && (
          <button onClick={handleReopen} disabled={saving} style={{ ...btnAction, backgroundColor: NAVY, color: WHITE }}>
            Reopen Case
          </button>
        )}
      </div>
    </div>
```

**Two-column info card** replaces the old 3-column card (lines 211-249):

```jsx
    {/* Two-column info section */}
    {caseForm && contactForm && (
      <div className="card" style={{ marginBottom: '20px', padding: 0 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr' }}>

          {/* LEFT — Case Details */}
          <div style={{ padding: '20px', borderRight: '1px solid #E2E8F0' }}>
            <div style={sectionTitle}>Case Details</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }}>
              <FieldRO label="Case Number" value={onboardingCase.dcfg_case_number} />
              <FieldSelect label="Status" value={caseForm.dcfg_status} disabled={isClosed}
                options={STATUS_DROPDOWN} onChange={v => updateCase('dcfg_status', v)} />
              <FieldInput label="Case Label" value={caseForm.dcfg_case_label} disabled={isClosed}
                onChange={v => updateCase('dcfg_case_label', v)} full />
              <FieldLink label="Customer" to={customer.dcfg_customerid ? `/customers/${customer.dcfg_customerid}` : null}
                value={customer.dcfg_name} />
              <FieldLink label="MSA" to={msa.dcfg_msaid ? `/msas/${msa.dcfg_msaid}` : null}
                value={msa.dcfg_name} />
              <FieldDate label="Initiated" value={caseForm.dcfg_initiated_date} disabled={isClosed}
                onChange={v => updateCase('dcfg_initiated_date', v)} />
              <FieldDate label="Completed" value={caseForm.dcfg_completed_date} disabled={isClosed}
                onChange={v => updateCase('dcfg_completed_date', v)} />
            </div>
          </div>

          {/* RIGHT — Customer Contact */}
          <div style={{ padding: '20px' }}>
            <div style={sectionTitle}>Customer Contact</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }}>
              <FieldInput label="Primary Contact" value={contactForm.dcfg_primary_contact_name} disabled={isClosed}
                onChange={v => updateContact('dcfg_primary_contact_name', v)} />
              <FieldInput label="Title" value={contactForm.dcfg_primary_contact_title} disabled={isClosed}
                onChange={v => updateContact('dcfg_primary_contact_title', v)} />
              <FieldInput label="Email" value={contactForm.dcfg_primary_contact_email} disabled={isClosed}
                onChange={v => updateContact('dcfg_primary_contact_email', v)} type="email" />
              <FieldInput label="Phone" value={contactForm.dcfg_primary_contact_phone} disabled={isClosed}
                onChange={v => updateContact('dcfg_primary_contact_phone', v)} type="tel" />
              <div style={{ gridColumn: '1 / -1', borderTop: '1px solid #E2E8F0', paddingTop: '12px', marginTop: '2px' }}>
                <span style={{ fontSize: '10px', color: GREY, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.04em' }}>President / Signer</span>
              </div>
              <FieldInput label="Name" value={contactForm.dcfg_president_name} disabled={isClosed}
                onChange={v => updateContact('dcfg_president_name', v)} />
              <FieldInput label="Title" value={contactForm.dcfg_president_title} disabled={isClosed}
                onChange={v => updateContact('dcfg_president_title', v)} />
            </div>
          </div>
        </div>

        {/* Full-width notes */}
        <div style={{ padding: '16px 20px', borderTop: '1px solid #E2E8F0' }}>
          <div style={{ fontSize: '10px', color: GREY, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '5px' }}>Notes</div>
          <div style={{ display: 'flex', gap: '6px', alignItems: 'flex-start' }}>
            <textarea
              value={caseForm.dcfg_notes}
              onChange={e => updateCase('dcfg_notes', e.target.value)}
              disabled={isClosed}
              style={{ ...textareaStyle, flex: 1 }}
            />
            {!isClosed && <SpeechMic onTranscript={t => updateCase('dcfg_notes', caseForm.dcfg_notes + ' ' + t)} />}
          </div>
        </div>
      </div>
    )}
```

**Progress bar + phase accordion** remain unchanged — keep lines 251-273 as-is:

```jsx
    {/* Progress summary bar */}
    <ProgressSummaryBar phases={phaseGroups} pctComplete={pctComplete} doneCount={doneCount} totalCount={totalCount} />

    {/* Phase cards */}
    <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginTop: '16px' }}>
      {phaseGroups.map(phase => (
        <PhaseCard
          key={phase.id}
          phase={phase}
          expanded={expandedPhases.has(phase.id)}
          expandedStep={expandedStep}
          onTogglePhase={() => togglePhase(phase.id)}
          onToggleStep={toggleStep}
          onMarkComplete={handleMarkComplete}
          onReassign={handleReassign}
          isManager={isManager()}
          saving={saving}
          allSteps={checklist}
          isClosed={isClosed}
        />
      ))}
    </div>
  </div>
);
```

Note: `isClosed` is passed as a new prop to PhaseCard — this will be used in Task 5.

- [ ] **Step 10: Add field helper components and new style constants**

At the bottom of the file, before the existing style constants (line 728), add:

```javascript
// ═══════════════════════════════════════════════════════════════
// FIELD HELPERS
// ═══════════════════════════════════════════════════════════════
const STATUS_DROPDOWN = [
  { value: OnboardingCaseStatus.NotStarted,   label: 'Not Started' },
  { value: OnboardingCaseStatus.InProgress,    label: 'In Progress' },
  { value: OnboardingCaseStatus.GoLivePending, label: 'Go-Live Pending' },
  { value: OnboardingCaseStatus.Live,           label: 'Live' },
  { value: OnboardingCaseStatus.Complete,       label: 'Complete' },
];

function FieldRO({ label, value }) {
  return (
    <div>
      <div style={fieldLabel}>{label}</div>
      <span style={{ fontSize: '13px', fontWeight: 600, color: NAVY }}>{value || '\u2014'}</span>
    </div>
  );
}

function FieldInput({ label, value, onChange, disabled, type = 'text', full }) {
  return (
    <div style={full ? { gridColumn: '1 / -1' } : undefined}>
      <div style={fieldLabel}>{label}</div>
      {disabled ? (
        <span style={{ fontSize: '13px', color: NAVY }}>{value || '\u2014'}</span>
      ) : (
        <input type={type} value={value} onChange={e => onChange(e.target.value)} style={fieldInputStyle} />
      )}
    </div>
  );
}

function FieldDate({ label, value, onChange, disabled }) {
  const dateVal = value ? value.split('T')[0] : '';
  return (
    <div>
      <div style={fieldLabel}>{label}</div>
      {disabled ? (
        <span style={{ fontSize: '13px', color: NAVY }}>{dateVal ? fmtDate(value) : '\u2014'}</span>
      ) : (
        <input type="date" value={dateVal} onChange={e => onChange(e.target.value)} style={fieldInputStyle} />
      )}
    </div>
  );
}

function FieldSelect({ label, value, options, onChange, disabled }) {
  return (
    <div>
      <div style={fieldLabel}>{label}</div>
      {disabled ? (
        <span style={{ fontSize: '13px', color: NAVY }}>
          {options.find(o => o.value === Number(value))?.label || '\u2014'}
        </span>
      ) : (
        <select value={value} onChange={e => onChange(e.target.value)} style={fieldInputStyle}>
          {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
      )}
    </div>
  );
}

function FieldLink({ label, to, value }) {
  return (
    <div>
      <div style={fieldLabel}>{label}</div>
      {to ? (
        <Link to={to} style={{ fontSize: '13px', fontWeight: 600, color: '#2563EB', textDecoration: 'underline' }}>
          {value || '\u2014'}
        </Link>
      ) : (
        <span style={{ fontSize: '13px' }}>{value || '\u2014'}</span>
      )}
    </div>
  );
}
```

And add the new style constants alongside the existing ones:

```javascript
const sectionTitle = { fontSize: '11px', fontWeight: 700, color: GREY, textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: '16px' };
const fieldLabel   = { fontSize: '10px', color: GREY, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '4px' };
const fieldInputStyle = { width: '100%', fontSize: '12px', border: '1px solid #E2E8F0', borderRadius: '5px', padding: '6px 10px', fontFamily: 'inherit', color: '#1B2A4A', boxSizing: 'border-box', outline: 'none' };
const textareaStyle = { width: '100%', border: '1px solid #E2E8F0', borderRadius: '5px', padding: '8px 10px', fontSize: '12px', fontFamily: 'inherit', resize: 'vertical', minHeight: '50px', color: '#475569', boxSizing: 'border-box', outline: 'none' };
const btnAction    = { border: 'none', borderRadius: '6px', padding: '7px 16px', fontSize: '12px', fontWeight: 600, cursor: 'pointer' };
```

---

## Chunk 4: Step Detail Panel — Editable Fields

### Task 5: Update StepDetailPanel with Editable Fields + SpeechMic

**Files:**
- Modify: `spa/dcfg-shell/src/screens/OnboardingDetail.jsx` (StepDetailPanel function, lines 489-660)

- [ ] **Step 1: Add isClosed prop threading**

Update `PhaseCard` to pass `isClosed` to `StepRow`:

In the PhaseCard component (line 333), add `isClosed` to the destructured props:
```javascript
function PhaseCard({ phase, expanded, expandedStep, onTogglePhase, onToggleStep, onMarkComplete, onReassign, isManager, saving, allSteps, isClosed }) {
```

In the StepRow rendering inside PhaseCard (line 381-393), add `isClosed` prop:
```jsx
<StepRow
  key={step.dcfg_onboarding_checklistid}
  step={step}
  isExpanded={expandedStep === step.dcfg_onboarding_checklistid}
  onToggle={() => onToggleStep(step.dcfg_onboarding_checklistid)}
  onMarkComplete={onMarkComplete}
  onReassign={onReassign}
  isManager={isManager}
  saving={saving}
  allSteps={allSteps}
  phaseColor={phase.color}
  isClosed={isClosed}
/>
```

Update StepRow to accept and pass through `isClosed`:
```javascript
function StepRow({ step, isExpanded, onToggle, onMarkComplete, onReassign, isManager, saving, allSteps, phaseColor, isClosed }) {
```

Pass to StepDetailPanel:
```jsx
<StepDetailPanel
  step={step}
  consulted={consulted}
  informed={informed}
  onMarkComplete={onMarkComplete}
  onReassign={onReassign}
  isManager={isManager}
  saving={saving}
  allSteps={allSteps}
  isClosed={isClosed}
/>
```

- [ ] **Step 2: Add handleStepFieldSave to OnboardingDetail main component**

After `handleReassign` (line 151-158), add:

```javascript
async function handleStepFieldSave(step, field, value) {
  setSaving(true);
  try {
    await apiPatch(`/${EntitySets.onboardingChecks}(${step.dcfg_onboarding_checklistid})`, {
      [field]: value || null,
    });
    loadCase();
  } catch (err) {
    console.error('Step field save failed:', err);
  }
  setSaving(false);
}
```

Pass `onStepFieldSave={handleStepFieldSave}` through PhaseCard → StepRow → StepDetailPanel (same pattern as `onReassign`).

- [ ] **Step 3: Rebuild StepDetailPanel left column with editable fields**

Replace the left column of StepDetailPanel (the notes, timeline, dependency, evidence sections) with editable versions. The key changes:

**Notes** — replace read-only div with editable textarea + mic + save-on-blur:

```jsx
<div style={{ marginBottom: '14px' }}>
  <div style={detailLabel}>Notes / Instructions</div>
  {isClosed ? (
    <div style={{ fontSize: '13px', color: '#475569', lineHeight: 1.5 }}>{step.dcfg_notes || '\u2014'}</div>
  ) : (
    <EditableText
      value={step.dcfg_notes || ''}
      onSave={val => onStepFieldSave(step, 'dcfg_notes', val)}
      saving={saving}
    />
  )}
</div>
```

**Due Date** — replace read-only with date input:

```jsx
<div>
  <div style={detailLabel}>Due</div>
  {isClosed ? (
    <span style={{ fontSize: '13px', fontWeight: 600, color: NAVY }}>{fmtDate(step.dcfg_due_date)}</span>
  ) : (
    <input
      type="date"
      defaultValue={step.dcfg_due_date ? step.dcfg_due_date.split('T')[0] : ''}
      onBlur={e => {
        if (e.target.value !== (step.dcfg_due_date || '').split('T')[0]) {
          onStepFieldSave(step, 'dcfg_due_date', e.target.value || null);
        }
      }}
      style={{ fontSize: '12px', border: '1px solid #E2E8F0', borderRadius: '4px', padding: '3px 6px' }}
    />
  )}
</div>
```

**Completed Date** — same pattern as Due Date but with `dcfg_completed_date`.

**Evidence URL** — replace read-only link with editable input + link:

```jsx
<div style={{ marginBottom: '14px' }}>
  <div style={detailLabel}>Evidence</div>
  {isClosed ? (
    step.dcfg_evidence_url ? (
      <a href={step.dcfg_evidence_url} target="_blank" rel="noreferrer" style={{ fontSize: '13px', color: NAVY, fontWeight: 500 }}>View Evidence</a>
    ) : <span style={{ fontSize: '13px', color: GREY }}>{'\u2014'}</span>
  ) : (
    <EditableField
      value={step.dcfg_evidence_url || ''}
      onSave={val => onStepFieldSave(step, 'dcfg_evidence_url', val)}
      placeholder="https://..."
      saving={saving}
    />
  )}
</div>
```

- [ ] **Step 4: Add EditableText and EditableField helper components**

Before the style constants section, add:

```javascript
// ═══════════════════════════════════════════════════════════════
// EDITABLE FIELD HELPERS (save-on-blur pattern)
// ═══════════════════════════════════════════════════════════════
function EditableText({ value, onSave, saving }) {
  const [draft, setDraft] = useState(value);
  const [changed, setChanged] = useState(false);

  function handleBlur() {
    if (changed && draft !== value) {
      onSave(draft);
      setChanged(false);
    }
  }

  return (
    <div style={{ display: 'flex', gap: '6px', alignItems: 'flex-start' }}>
      <textarea
        value={draft}
        onChange={e => { setDraft(e.target.value); setChanged(true); }}
        onBlur={handleBlur}
        disabled={saving}
        style={{ ...textareaStyle, flex: 1, minHeight: '40px' }}
      />
      <SpeechMic
        onTranscript={t => { setDraft(prev => prev + ' ' + t); setChanged(true); }}
        disabled={saving}
      />
    </div>
  );
}

function EditableField({ value, onSave, placeholder, saving }) {
  const [draft, setDraft] = useState(value);
  const [changed, setChanged] = useState(false);

  function handleBlur() {
    if (changed && draft !== value) {
      onSave(draft);
      setChanged(false);
    }
  }

  return (
    <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
      <input
        value={draft}
        onChange={e => { setDraft(e.target.value); setChanged(true); }}
        onBlur={handleBlur}
        placeholder={placeholder}
        disabled={saving}
        style={{ fontSize: '12px', border: '1px solid #E2E8F0', borderRadius: '4px', padding: '3px 6px', flex: 1 }}
      />
      {draft && (
        <a href={draft} target="_blank" rel="noreferrer" style={{ fontSize: '11px', color: '#2563EB', flexShrink: 0 }}>open</a>
      )}
    </div>
  );
}
```

- [ ] **Step 5: Hide Mark Complete and Reassign on closed cases**

In the StepDetailPanel, guard the Mark Complete button:

```jsx
{!done && isManager && !isClosed && (
```

In the RaciRow editable prop:

```jsx
editable={isManager && !done && !isClosed}
```

---

## Chunk 5: Build Verification + Debug Fix Deploy

### Task 6: Build and Verify

**Files:**
- All modified files

- [ ] **Step 1: Run the Vite build**

Run: `cd spa/dcfg-shell && npm run build`
Expected: Build succeeds with no errors. Warnings about unused vars are acceptable.

- [ ] **Step 2: Fix any build errors**

If the build fails, read the error output and fix the specific issue. Common issues:
- Missing import (SpeechMic, useNavigate, useToast)
- Mismatched JSX brackets
- Undefined variable references

Re-run build until it passes.

- [ ] **Step 3: Verify the debug fix from earlier in this session**

Confirm the hash-routing fix in `spa/dcfg-shell/src/debug/index.js` is still in place (the `checkUrlParam` function should check both `window.location.search` and the hash portion).

---

### Task 7: Schema Script for dcfg_active_flag

**Files:**
- Create: `DCFG_Schema_OnboardingActiveFlag.ps1`

- [ ] **Step 1: Write the PowerShell script**

This script is for the user to run manually against their Dataverse environment. It adds `dcfg_active_flag` to the `dcfg_onboarding_case` table and backfills existing records.

```powershell
<#
  DCFG_Schema_OnboardingActiveFlag.ps1
  Adds dcfg_active_flag (Boolean, default true) to dcfg_onboarding_case table.
  Run after connecting to Dataverse via pac auth.
#>

$env = "https://yourorg.crm.dynamics.com"  # UPDATE with actual org URL

# Check connection
$me = pac org who 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Not connected. Run: pac auth create"; exit 1 }
Write-Host "Connected: $me"

# The column may already exist — this is idempotent
Write-Host "`nAdding dcfg_active_flag to dcfg_onboarding_case..."
# Use Web API to add column if not present — user should do this via maker portal or solution import
# For existing records, backfill:

$headers = @{ "Content-Type" = "application/json"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; "Prefer" = "return=representation" }

# Fetch all onboarding cases missing active_flag
$cases = Invoke-RestMethod -Uri "$env/api/data/v9.2/dcfg_onboarding_cases?`$filter=dcfg_active_flag eq null&`$select=dcfg_onboarding_caseid" -Headers $headers -Method Get
Write-Host "Found $($cases.value.Count) cases to backfill"

foreach ($c in $cases.value) {
  $id = $c.dcfg_onboarding_caseid
  $body = @{ dcfg_active_flag = $true } | ConvertTo-Json
  Invoke-RestMethod -Uri "$env/api/data/v9.2/dcfg_onboarding_cases($id)" -Headers $headers -Method Patch -Body $body
  Write-Host "  Patched $id -> active_flag=true"
}

Write-Host "`nDone. $($cases.value.Count) records backfilled."
```

Write to `C:\DCFG\DCFG_Schema_OnboardingActiveFlag.ps1`.

**Note:** The user must also add the `dcfg_active_flag` column to the `dcfg_onboarding_case` table via the Dataverse maker portal or solution before running this script. The column type is Yes/No (Boolean), default value Yes (true), schema name `dcfg_active_flag`.

---

## Post-Implementation Notes

- The `dcfg_active_flag` column must be added to Dataverse before the SPA changes will work for delete/restore. The SPA handles null gracefully (`dcfg_active_flag eq null` treated as active).
- Table permissions in Power Pages must allow PATCH on `dcfg_onboarding_cases` for the `dcfg_active_flag` field and on `dcfg_customers` for the contact fields. Both should already have global CRUD enabled per the PRD.
- Deploy the SPA via the standard `pac pages upload-code-site` workflow after building.
- After deploying, clear cache and verify at the portal URL.
