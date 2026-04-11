# Interview-Style Contract Wizard — Design Spec

**Date:** 2026-03-19
**Status:** Approved for build
**Author:** Joseph Cameron / Claude

---

## Summary

Three new presentation modes for contract creation, all sharing one interview engine. Adds a universal flow that handles Decades (direct) and TPA (Bancroft etc.) customers for Work Order, Amendment, or Vendor MSA creation. Existing wizards (New Proposal, New Contract) remain unchanged.

---

## Data Model Changes

### Modified: `dcfg_contract_family` picklist
- Current: `100000000=Bancroft, 100000001=Decades`
- New: `100000000=TPA, 100000001=Decades`
- Bancroft becomes a TPA partner, not a family

### New field: `dcfg_tpa_partner` on `dcfg_customer`
- Type: String (or Lookup to future dcfg_tpa_partner table)
- Purpose: Identifies which TPA partner this customer belongs to (e.g., "Bancroft")
- Only relevant when `dcfg_contract_family = TPA`

### Template organization
- TPA partner templates stored in SharePoint: `DCFG_Templates/<partner_name>/`
- `dcfg_document_template` records filtered by partner name for TPA customers
- TPA Customer MSAs are pre-existing: uploaded/linked as reference, not generated, not a blocker

---

## Interview Flow

```
Step 1: Customer
  → Search/select or create customer
  → System detects Decades vs TPA from customer record
  → If TPA: show partner name (e.g., "Bancroft")

Step 2: What do you need?
  → Work Order
  → Amendment to existing Work Order
  → Vendor MSA

Step 3: Vendor MSA Check (if WO or Amendment)
  → Show MSA status: "On file" / "In process" / "Not on file"
  → If not on file: offer to upload/link, or create new
  → NOT a blocker — user can proceed without MSA

Step 4: Document-specific fields
  Work Order:
    → Location (from customer's locations)
    → Vendor (search/select)
    → Signer info (name, title)
    → Contract date
    → Line items (Exhibit A)
    → Description of service
    → Hours of operation

  Amendment:
    → Parent contract (select from customer's WOs)
    → What changed (scope, fee, dates)
    → Signer info

  Vendor MSA (Decades):
    → Package (A/B/C)
    → Locations + rates (membership + onboarding)
    → Effective date

  Vendor MSA (TPA):
    → Vendor
    → Effective date
    → Template selection (from partner's template set)

Step 5: Review & Generate
  → Summary of all collected data
  → Generate button → flow_docgen with correct template per family/partner
  → Document link (Office Online) appears after generation
```

---

## Sidebar (Upper-Right)

### Visual Design
- Light palette: white background, light navy (#EDF1F8) sections, amber (#D4A017) accents
- NOT the dark navy block from NewProposalWizard
- IBM Plex Sans body, Fraunces for headings, IBM Plex Mono for values

### Content — Top: Checklist
- Green dot = answered, empty dot = remaining
- Shows each interview question as a line item
- Updates in real-time as user progresses

### Content — Bottom: Running Totals
- Customer name
- Family (Decades / TPA + partner)
- Document type (WO / Amendment / MSA)
- Vendor name
- Location count
- Fee total (when applicable)
- MSA status

---

## Three Presentation Modes

All three share one interview engine. Mode selection is the first screen. This is an evaluation exercise for the business owner — one mode will be chosen, other two retired.

### Mode 1: Conversational
- One question per screen, centered, large text
- Big clear "Next" button advances
- Progress bar at top
- Sidebar visible on right
- Feels like: Typeform survey

### Mode 2: Guided
- Section cards, one visible at a time
- Next section appears when current section is complete (progressive disclosure)
- Stepper at top showing phases
- Sidebar visible on right
- Feels like: simplified version of current wizards

### Mode 3: Chat
- Questions appear as chat bubbles from the system
- User answers via inline form controls (dropdowns, inputs) or typed responses
- Conversation scrolls up as interview progresses
- Sidebar visible on right
- Feels like: talking to an assistant

---

## Architecture

```
src/
  interview/
    InterviewEngine.js      — State machine: questions, answers, validation, flow
    interviewQuestions.js    — Question definitions with conditional logic
    interviewGenerate.js    — Creates records + calls flow_docgen (shared by all modes)
    InterviewSidebar.jsx    — Checklist + running totals (shared by all modes)
    ConversationalMode.jsx  — Mode 1: one question per screen
    GuidedMode.jsx          — Mode 2: progressive disclosure cards
    ChatMode.jsx            — Mode 3: chat-style prompts
    InterviewShell.jsx      — Mode selector + routes to chosen mode
```

### InterviewEngine.js
- Pure data layer, no UI
- Exports: `questions`, `currentQuestion`, `answer(questionId, value)`, `validate()`, `canProceed()`, `getSummary()`, `getChecklist()`, `getTotals()`
- Conditional logic: if TPA → skip package question; if WO → check MSA status
- Dependency chain: vendor MSA gate before WO/Amendment

### interviewGenerate.js
- Called by all three modes when user clicks Generate
- Pre-execution audit log (parameters)
- Creates MSA record if needed (with rates for Decades)
- Creates contract record (with lines for WO)
- Calls flow_docgen with correct template family/partner
- Post-execution audit log (success/failure)
- Returns document URL

---

## Routes

- `/interview` — mode selector screen
- `/interview/conversational` — Mode 1
- `/interview/guided` — Mode 2
- `/interview/chat` — Mode 3

### Nav Panel Addition
New item under CONTRACTS group:
```
{ to: '/interview', label: 'New Interview', icon: <InterviewIcon /> }
```

---

## Merge Fields

All shared fields (14 tokens) are auto-populated from lookups — zero interview questions needed:
- 6 vendor fields (address, email, legal name, display name, phone, primary contact)
- 7 property/location fields (city, contact, email, phone, state, street, title)
- 2 customer fields (president contact, president title)

Work-Order-only fields (user enters): signer name, signer title, company, contract date, line items, description of service, hours of operation

MSA-only fields (user enters): effective date, package (Decades), rates (Decades), template ref (TPA)

---

## What This Does NOT Change

- `NewProposalWizard.jsx` — untouched, stays at `/proposals/new`
- `NewContractWizard.jsx` — untouched, stays at `/contracts/new`
- `flow_docgen` — no changes, uses existing template lookup
- `portalApi.js` — may add helper functions but existing API unchanged
- All existing routes and nav items remain
