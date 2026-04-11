# DCFG UX Cleanup — Session 2 Handoff

**Date:** 2026-03-29 (end of session)
**From:** UX cleanup + wizard rewrite session
**To:** Next session

---

## What Was Done This Session

### Phase A: Fix What's Broken (ALL COMPLETE)
- Encoding fix — all `\uXXXX` and `\u{XXXXX}` patterns across 14 files
- NaN fix in Exhibit A amounts
- Developer artifacts removed (D1-D10) — FieldNotes, choice integers, template filenames, entity badges
- Step 5 merge labels humanized + "MISSING" → "Not yet provided"
- Compliance route wired (AppRouter + import)
- MSA Detail `$select` fix + friendly error message
- Contract Detail labels humanized (14 labels)
- "flow_docgen" references cleaned up throughout

### Screenshot Review Fixes (ALL COMPLETE)
- Dashboard telemetry truncated to first segment
- Budget Health CUSTOMER column fixed ($select)
- Ghost text on selected contract list items (Fn bg prop)
- Garbled close button on New Location panel
- Location save toast notification added
- ZIP code field added to New Location
- Cost code column widened (160→220px)
- Disabled Create Case button visual state
- Onboarding tab error handling (try/catch)
- Operations dropdown aria-labels
- All 17 AuditActionType.Other calls corrected (Created, Deleted, Restored, Generated)
- AuditActionType enum extended with 3 new values

### Form Collapse (F2, F4 DONE — F1, F3 REVERTED)
- F2: Budget simplified (single input, committed/remaining as subtle text)
- F4: New Customer contact hidden behind "+ Add Primary Contact"
- F1/F3: Reverted — fields populated by explicit user selection should stay visible

### Contract Wizard Customer-First Rewrite (STRUCTURAL COMPLETE, UI IN PROGRESS)
- Plan: `C:\dcfg\docs\superpowers\plans\2026-03-29-contract-wizard-customer-first.md`
- Demo: `C:\dcfg\docs\wizard-preview.html`
- Schema: TPA columns created on Test, Bancroft + Archway flagged
- Code: derivedFamily logic, imports, STEPS array, client name source fixed, all family→derivedFamily
- **REMAINING:** Step 1/2 JSX visual rewrite (old family cards still render, need customer selection UI)

### Environment Reference
- `reference_system_snapshot.json` updated with correct portal URLs + all sites
- `CLAUDE.md` updated with environment table + deploy order
- `feedback_location_display_order.md` saved (name first, address second)
- `feedback_deploy_order.md` removed (consolidated into CLAUDE.md)

---

## Resume Point

### IMMEDIATE: Complete Step 1/2 JSX Rewrite
1. **Step 1 JSX** — Replace family/type cards with: customer dropdown, "+ Add Customer", customer info card with TPA badge, programs section (selectable cards with budgets), locations list (name first, address second, contact info, compliance badges)
2. **Step 2 JSX** — Replace customer/location section with: doc type cards (WO/Amendment/Vendor MSA), amendment WO picker, vendor selection with MSA check, location dropdown + date
3. **Step 3** — Vendor display as read-only with "Change" link (not search field)
4. Build + deploy

### THEN: Schema on Prod
- Run `add-tpa-columns-v3.ps1` against Prod (org06f5de0b)
- Add columns to Webapi/dcfg_customer/fields on Prod
- Create Archway Programs customer on Prod if needed

### THEN: Full Functional Test
- Run `full-functional-test.spec.ts` against both environments
- Exercise every screen, every button, create records
- Fresh-eyes screenshot review
- Fix any issues found

---

## Outstanding Items (Not Wizard)

| Item | Status |
|---|---|
| Duplicate MSA rows (Q1, Q3) | Needs Dataverse investigation |
| Detail views — Location/Onboarding empty tabs | Data-dependent, code fixes deployed |
| Send Queue tabs | Awaiting operator call — keep 3-tab? |
| Vendor duplicates + "306" in Admin | Data cleanup |
| Sample programs for Bancroft/Archway | Create via `C:\dcfg\docs\create-sample-programs.html` |

## Handoff Phases Not Started
- Phase B: Detail view content (data population)
- Phase C: Send Queue workflow, Field Ops
- Phase D: QA Promotion Pipeline
- Phase E: Full QA pass
- Phase F: User manual
