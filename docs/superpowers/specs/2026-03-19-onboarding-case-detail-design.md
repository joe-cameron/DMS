# Onboarding Case Detail — Transactional Detail Screen

**Date:** 2026-03-19
**Status:** Approved
**Scope:** OnboardingDetail.jsx, Onboarding.jsx, portalApi.js, voice input utility

---

## Problem

The current onboarding case detail screen is a checklist tracker. PMs and business owners need a full transactional detail view showing customer contact information, editable case fields, and editable step-level fields (dates, notes, evidence). The list screen lacks soft delete, undelete, and filtering for deleted cases.

## Design

### 1. Case Detail Action Bar

Top bar with breadcrumb and three action buttons:

- **Save Changes** — PATCHes case-level fields (label, status, dates, notes) and customer contact fields back to the customer record
- **Close Case** — Sets `dcfg_status` to `Closed` (100000005), locks all fields read-only, hides Save/Delete, shows Reopen button
- **Delete** — Soft delete: sets `dcfg_active_flag = false`, navigates back to list
- **Reopen** (visible only on closed cases) — Sets status back to `InProgress` (100000001)

### 2. Two-Column Info Section

Replaces the existing thin 3-column card.

**Left Column — Case Details:**

| Field | Type | Source | Editable |
|---|---|---|---|
| Case Number | Read-only text | `dcfg_case_number` | No |
| Status | Dropdown | `dcfg_status` | Yes (until closed) |
| Case Label | Text input | `dcfg_case_label` | Yes |
| Customer | Link to `/customers/:id` | `dcfg_customer_id` expand | No (navigation only) |
| MSA | Link to `/msas/:id` | `dcfg_msa_id` expand | No (navigation only) |
| Initiated | Date picker | `dcfg_initiated_date` | Yes |
| Completed | Date picker | `dcfg_completed_date` | Yes |

**Right Column — Customer Contact:**

| Field | Type | Source | Editable |
|---|---|---|---|
| Primary Contact | Text input | `dcfg_primary_contact_name` | Yes |
| Title | Text input | `dcfg_primary_contact_title` | Yes |
| Email | Email input | `dcfg_primary_contact_email` | Yes |
| Phone | Tel input | `dcfg_primary_contact_phone` | Yes |
| President Name | Text input | `dcfg_president_name` | Yes |
| President Title | Text input | `dcfg_president_title` | Yes |

Customer contact fields are read from the customer record via expanded `$select` on the case query. Saving PATCHes back to `dcfg_customers(id)`.

### 3. Full-Width Notes

- Editable `<textarea>` bound to `dcfg_notes` on the case
- Mic button for voice-to-text (see section 7)

### 4. Progress Bar

Unchanged from current implementation. Segmented by phase, color-coded.

### 5. Phase Accordion — Step Detail Enhancements

Phase accordion layout unchanged. Step expand panel gains editable fields:

| Step Field | Current | New |
|---|---|---|
| Due Date | Read-only text | Editable date picker |
| Completed Date | Read-only text | Editable date picker |
| Notes | Read-only text | Editable textarea with mic button |
| Evidence URL | Read-only link | Editable text input (still renders as link when not editing) |
| Reassign R/A | Inline edit | Unchanged |
| Mark Complete | Button | Unchanged |

Step fields use the same mini-form pattern as existing R/A reassign: user edits in place, clicks a Save button (or blurs out of the field) to trigger `apiPatch` on `dcfg_onboarding_checklists(id)`. No on-keystroke saves.

### 6. Closed Case Behavior

When `dcfg_status === Closed` (100000005):

- All inputs (including notes textarea and SpeechMic button) render as read-only text
- Save Changes and Delete buttons hidden
- Close Case button replaced with Reopen button
- Step-level Mark Complete, Reassign, and inline field editing hidden
- Visual indicator: muted styling or banner
- `dcfg_completed_date` auto-set to today if null when closing

### 7. Voice Input — SpeechMic Component

Reusable component for any `<textarea>` in the app.

**Implementation:**

```
SpeechMic.jsx — small button component
  - Uses window.webkitSpeechRecognition || window.SpeechRecognition
  - Props: onTranscript(text), lang='en-US'
  - Renders mic icon button; red when recording
  - On result: calls onTranscript with transcript text
  - Appends to existing textarea content (does not replace)
  - Returns null if SpeechRecognition API unavailable (graceful fallback)
```

**Usage pattern:**

```jsx
<textarea value={notes} onChange={...} />
<SpeechMic onTranscript={text => setNotes(prev => prev + ' ' + text)} />
```

**Target devices:** iPad Safari (primary), Chrome desktop (secondary). No backend needed.

**Notes:**
- Requires HTTPS (Power Pages provides this)
- Requires user gesture to start (mic button click satisfies this)
- Safari uses single-utterance mode (stops after silence) — sufficient for field notes
- First-time use triggers browser microphone permission prompt — no custom UI needed for this

### 8. Onboarding List Changes

**Onboarding.jsx (`/onboarding`):**

- Add Active/Deleted toggle filter (default: Active)
- Default query: `(dcfg_active_flag eq true or dcfg_active_flag eq null)` — handles existing records before backfill
- Deleted view: `dcfg_active_flag eq false`
- **Both locations need this filter:** the inline query in `Onboarding.jsx` (line 52) AND `fetchOnboardingCases()` in `portalApi.js` (line 328)
- Active view: Delete button per row → sets `dcfg_active_flag = false`, reloads
- Deleted view: Restore button per row → sets `dcfg_active_flag = true`, reloads
- Existing status filter continues to work alongside active/deleted filter

### 9. Schema Change

Add `dcfg_active_flag` (Boolean, default `true`) to `dcfg_onboarding_case` table.

**PowerShell script needed:** `DCFG_Schema_OnboardingActiveFlag.ps1`
- Adds `dcfg_active_flag` column to `dcfg_onboarding_case`
- Sets default value to `true`
- Patches existing records to `true`

### 10. API Changes (portalApi.js)

**Expand customer contact on case detail query:**

Current:
```
$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name,dcfg_primary_contact_email)
```

New:
```
$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name,dcfg_primary_contact_name,dcfg_primary_contact_email,dcfg_primary_contact_phone,dcfg_primary_contact_title,dcfg_president_name,dcfg_president_title)
```

**Add to list query filter:**
```
dcfg_active_flag eq true (default)
```

**New/modified exports needed:**
- `updateOnboardingCase(id, payload)` — PATCH case fields
- `updateCustomerContact(custId, payload)` — PATCH customer contact fields (reuse existing `apiPatch`)

### 11. Files Modified

| File | Change |
|---|---|
| `src/screens/OnboardingDetail.jsx` | Rebuild info section, add editable fields, action bar, close/delete/reopen, step field editing |
| `src/screens/Onboarding.jsx` | Add active/deleted filter, delete/restore buttons per row |
| `src/portalApi.js` | Expand customer contact fields on case query, add active_flag filter |
| `src/components/SpeechMic.jsx` | New file — reusable voice input component |

### 12. Out of Scope

- Department-based step grouping (keep phase-based)
- Editing step names, step numbers, or phase assignments from portal
- Audio file recording with server-side transcription
- Changes to the Admin template step management
- Changes to CustomerDetail.jsx onboarding tab
- ETag/concurrency control (last-writer-wins is acceptable for now)

---

## Error Handling

**Save Changes (dual PATCH):**
- Case PATCH and customer contact PATCH are independent — each wrapped in its own try/catch
- On case PATCH failure: toast error, do not proceed to customer PATCH
- On customer PATCH failure: toast error specifying "Contact info failed to save — case data was saved"
- Both success: single success toast

**Unsaved changes guard:**
- Track dirty state for case-level fields (not step-level, since those save inline)
- Show `beforeunload` warning if navigating away with unsaved case-level changes
- Visual indicator on Save button when dirty (e.g., dot or highlight)

**Audit logging:**
- Close Case, Delete Case, Restore Case all call `writeAuditLog()` with action details
- Pattern follows existing `handleNewCase` audit in Onboarding.jsx

---

## Data Flow

```
Case Detail Screen Load:
  apiGet → onboarding case + expanded customer + expanded MSA
  fetchOnboardingChecklist → step list with RACI

Save Changes (case):
  apiPatch → dcfg_onboarding_cases(id) { label, status, dates, notes }
  apiPatch → dcfg_customers(custId) { contact fields }

Step inline save:
  apiPatch → dcfg_onboarding_checklists(stepId) { due_date | completed_date | notes | evidence_url }

Close Case:
  apiPatch → dcfg_onboarding_cases(id) { dcfg_status: 100000005, dcfg_completed_date: today (if null) }
  writeAuditLog → Close case event

Delete Case:
  apiPatch → dcfg_onboarding_cases(id) { dcfg_active_flag: false }
  writeAuditLog → Delete case event

Restore Case:
  apiPatch → dcfg_onboarding_cases(id) { dcfg_active_flag: true }
  writeAuditLog → Restore case event
```
