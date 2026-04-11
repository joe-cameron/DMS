# DCFG UX Audit Cleanup — Session Handoff

**Date:** 2026-03-29
**From:** UX audit session (Nora monitoring + build plan review + full Playwright audit)
**To:** Next session — Planner + Harness
**Environment:** DCFGSystems-Prod (org06f5de0b / dmms1.powerappsportals.com)
**SPA Source:** C:\DCFG\spa\dcfg-shell\src\ (currently READ-ONLY — operator must grant write permission)

---

## What Was Done This Session

1. **Nora monitoring** ran on prod — 10/12 flows active, 13 audit entries, both sites healthy
2. **Brain Insight table upgraded** — 8 new columns + 7 lookup relationships added to `dcfg_brain_insight` on test (org0c17e98d)
3. **98 third-party skills installed** — Trail of Bits (60+), sanjay3290 (20), Anthropic official (17), autoresearch-diagrams (1)
4. **Full UX audit** — 151 screenshots across all 19 screens, every tab, every button logged
5. **Creation flow capture** — 64 screenshots, 4 records actually created on prod (customer, contract, onboarding case, location), validated in UI
6. **Build plan from upload reviewed** — 7-phase Company Brain plan assessed against current state

## Screenshots Location

- Full audit: `C:\dcfg\tests\screen-eval\audit\` (151 files)
- Creation flows: `C:\dcfg\tests\screen-eval\manual\` (64 files)
- Test scripts: `C:\dcfg\tests\screen-eval\full-ux-audit.spec.ts` and `capture-creation-flows.spec.ts`

---

## ISSUES TO FIX — Classified by Type

### Type 1: Encoding (1 root cause, every screen)

All caused by unicode escape sequences written as string literals instead of actual characters.

| ID | Screen | What Shows | Should Show |
|----|--------|-----------|-------------|
| E1 | Send Queue action buttons | `\u2713 Approve` | ✓ Approve |
| E2 | Send Queue action buttons | `\u21A9 Return` | ↩ Return |
| E3 | Send Queue action buttons | `\u2715` | ✕ |
| E4 | Send Queue action buttons | `\u{1F4C4} Open` | 📄 Open |
| E5 | All search placeholders | `Search cases\u2026` | Search cases… |
| E6 | Onboarding new case dropdown | `Select customer\u2026` | Select customer… |
| E7 | New Location panel header | `åœ*` garbled | Clean header text |

**Root cause likely:** String concatenation or template literal using escaped sequences instead of actual Unicode characters. Check for `'\\u2713'` vs `'\u2713'` in the source.

**Files to check:** `SendQueue.jsx`, `useTableControls.jsx` (search placeholder), `Onboarding.jsx`, `Locations.jsx`

### Type 2: Developer Artifacts Visible to Users

Debug/developer information leaking through to production UI.

| ID | Screen | What Shows | Fix |
|----|--------|-----------|-----|
| D1 | Contract Wizard Step 1 | `FAMILY · 100000001`, `TYPE · 0` | Hide choice integers — show only label text |
| D2 | Contract Wizard Step 1 | `Creates a new dcfg_contract record` | Remove — developer note |
| D3 | Contract Wizard Step 1 | `Links to parent via dcfg_parent_contract_id` | Remove — developer note |
| D4 | Contract Wizard Step 1 | `Decades_Contract_v1.docx / ...` template filenames | Remove or hide behind debug mode |
| D5 | Contract Wizard Step 2 | `dcfg_customer`, `dcfg_property` entity badges in section headers | Apply `feedback_field_names_invisible` rule — background-colored, visible only on highlight/debug |
| D6 | Contract Wizard Step 2 | `OWNER_CONTACT — auto-filled from location` | Show "Auto-filled from location" only (no field name) |
| D7 | Contract Wizard Step 2 | `dcfg_budget_committed · written by flow_commit only` | Show "Read-only" or just show the dash |
| D8 | Contract Review Step 5 | All merge field labels raw: `CONTRACTOR_LEGAL_NAME`, `CONTRACTOR_ADDRESS`, `PAYMENT_PROCESS`, `SIGNER_PRINTED`, `OWNER_CONTACT`, `OWNER_TITLE`, `OWNER_EMAIL`, `OWNER_STREET`, `OWNER_CITY`, `OWNER_STATE`, `CLIENT_NAME`, `DECADES_SIGNATURE_IMAGE` | Human labels: "Contractor Name", "Address", "Payment Terms", "Signer Name", etc. |
| D9 | Contract Review Step 5 | `Injected by flow_docgen (static asset)` | Remove |
| D10 | Contract Review Step 5 | `— MISSING —` in red for empty fields | Change to "Not yet provided" in neutral color |

**Files to check:** `NewContractWizard.jsx` (all 5 steps)

### Type 3: Form Density — Minimize Creation Cards

Principle from operator: auto-filled fields collapse into read-only summaries. Expand only on override. If information isn't there, don't show empty fields.

| ID | Screen | Current | Recommended |
|----|--------|---------|-------------|
| F1 | Contract Wizard Step 2 — Location & Owner | 6 empty input fields (Contact Name, Title, Email, Street, City, State) visible even when empty | Collapse when auto-filled into one-line summary: "Jane Smith · jane@ex.com · 100 Main St". If location has no contact, show "No contact on file" — not 6 empty boxes |
| F2 | Contract Wizard Step 2 — Budget | Budget Committed (read-only) and Budget Remaining (calculated) shown as form fields | Show only Budget Amount input. Committed/Remaining as subtle text below, not fields |
| F3 | Contract Wizard Step 3 — Contractor | Contractor fields always expanded even when auto-filled from vendor | Same collapse pattern as F1 |
| F4 | New Customer panel — Contact section | 4 fields (Contact Name, Email, Title, Phone) always visible under "PRIMARY CONTACT (OPTIONAL)" | Collapse by default. Show "+ Add Contact" link to expand. Customer name is the only thing needed to create |

### Type 4: Data/Query Issues

| ID | Screen | Issue | Investigation |
|----|--------|-------|---------------|
| Q1 | MSA List | 3 duplicate "ACP Master Services Agreement 2026" rows | Check Dataverse: are there actually 3 records? Or is the OData query returning duplicates (expand/join issue)? Also: display shows `dcfg_name` appended to MSA name text |
| Q2 | Contract Review Step 5 | NaN in Exhibit A line item amounts | `parseFloat()` on null/undefined. Needs `\|\| 0` fallback |
| Q3 | Dashboard Budget Health | Duplicate rows | Same investigation as Q1 — query or data |

### Type 5: Broken/Missing Routes

| ID | Route | Status |
|----|-------|--------|
| R1 | `/#/compliance` | "Page not found" — nav link exists but screen not deployed. Either deploy CompliancePanel or remove nav item |

---

## WHAT REMAINS UNWRITTEN

### Detail Views — Structure Exists, Content Not Rendering

These are the highest priority. Users can see lists but can't drill into details.

| Screen | Route | Tabs Defined in Code | What Audit Found |
|--------|-------|---------------------|-----------------|
| **Location Detail** | `/#/locations/:id` | Property Info, Facility Profile, Building Systems, Property Features, Compliance Documents, Appliances | 0 tabs rendered, 0 buttons. Shell loads but tab content missing |
| **MSA Detail** | `/#/msas/:id` | Contracts, Document History | 0 tabs rendered, 0 buttons. No Edit, no Generate |
| **Onboarding Detail** | `/#/onboarding/:id` | 6 phase accordions (Sales & Proposal through Go-Live & Monitoring) | 0 phases rendered. List view works but detail is hollow |

**Investigation needed:** Are the tab components crashing silently? Are they behind a permission gate? Are they fetching data that doesn't exist in prod? Read the source for each detail screen to determine why tabs don't render.

### Screens That Are Placeholder/Empty

| Screen | Route | Status |
|--------|-------|--------|
| **Field Ops** | `/#/field` | 0 buttons, no visible content. Placeholder |
| **Compliance Panel** | `/#/compliance` | 404 |

### Features Not Yet Built

| Feature | Where It Would Go | Priority |
|---------|-------------------|----------|
| Send Queue "Mark Sent" / "Mark Complete" tabs | Send Queue screen | High — core workflow |
| Document preview (in-app) | Contract Detail, MSA Detail | Medium |
| Bulk select + batch actions | All list screens | Medium |
| Export CSV/Excel | All list screens | Medium |
| Global search | Floating or nav bar | Medium |
| Alerts/notifications view | Dashboard Alerts KPI drills into...? | Medium |
| Calculator/aggregation toolbar | Floating panel, all screens | Low — new feature |
| Brain/AI chat | Floating panel, `/#/brain` | Low — Phase 3 of build plan |
| Print view | Contract Detail | Low |
| User preferences | Settings screen | Low |

---

## EXECUTION ORDER

### Phase A: Fix What's Broken (no new features)

1. **Encoding fix** (E1-E7) — single root cause, fix once, all screens benefit
2. **NaN in line items** (Q2) — one-line fix, prevents bad data display
3. **Developer artifacts** (D1-D10) — sweep NewContractWizard.jsx, hide/humanize labels
4. **Form collapse** (F1-F4) — minimize creation cards per operator principle
5. **MSA/Budget duplicates** (Q1, Q3) — investigate Dataverse data vs query

### Phase B: Complete the Detail Views

6. **Investigate** why Location Detail, MSA Detail, and Onboarding Detail tabs don't render on prod
7. **Fix rendering** — may be data-dependent, permission-dependent, or simply not wired
8. **Verify** each detail view has functional tabs with content

### Phase C: Missing Workflow Pieces

9. **Send Queue** send/complete workflow
10. **Compliance Panel** — deploy or remove nav link
11. **Field Ops** — build or remove nav link

### Phase D: QA Promotion Pipeline (New Screen)

Spec: `C:\DCFG\docs\superpowers\specs\2026-03-29-qa-promotion-pipeline-design.md`

12. **Schema changes** — extend `dcfg_property_intake` (6 new columns), extend `dcfg_intake_field_config` (2 columns), create `dcfg_intake_queue_request` table on Prod, extend `dcfg_audit_logs` action type (4 new values), add 3 `dcfg_configs` keys
13. **Build Intake Review screen** (`/#/intake-review`) — 3-level drill-down: Session Queue → Property List → Property Detail with side-by-side diff
14. **Build bridge flow** — single Power Automate flow on Prod, Dataverse trigger on `dcfg_intake_queue_requests`, condition branch per request type (Read Session List / Read Detail / Approve / Reject / Dismiss / Undo), "selected environment" connector to Portal org
15. **Build stuck notification flow** — daily scheduled flow, checks items locked > 24h, plain-language notification
16. **Admin wiring** — Intake Fields tab in Admin already exists, add priority_category and priority_rank columns to its UI
17. **Record locking** — lock/unlock pattern in flow, SPA checks lock before actions, 1-hour auto-expire

Key design points:
- Field-level merge: non-empty intake values overwrite production, blanks preserved
- Vendors and authorized users are informational only — never promote
- Documents always promote, even on exception dismiss
- Bulk approve as default — exceptions excluded
- All rules/thresholds table-driven via Admin UI
- Simple undo (revert intake status only, no production rollback)

### Phase E: Testing After All Phases Complete

18. **Re-run full UX audit** — verify all Phase A-D fixes
19. **Clean data load** — fresh production dataset
20. **Negative testing** — invalid inputs, missing required fields, boundary conditions, concurrent edits, what happens when the user does the wrong thing
21. **Security testing** — role-based access (Viewer vs Admin), CSRF validation, unauthorized API calls, direct URL manipulation, session timeout

### Phase F: User Manual (BLOCKED until Phase E passes)

**The manual cannot be written until screens are ready and working.**

22. **Re-capture all screens** with clean data — every list, detail, tab, creation flow
23. **Build interactive AI user manual** using PB&J principle:
    - Every step captured with screenshot
    - "You'll see this. Click here. Now you'll see this."
    - Written for users where change is scary — assume nothing, show everything
    - AI-presented: user asks "how do I create a contract?" and gets walked through step by step with the actual screenshots from their system
24. **Include the floating Calculator/Brain concept** in the manual as upcoming feature preview

---

## OPERATOR RULES FOR THIS WORK

- **SPA is READ-ONLY** until operator grants write permission per session
- **Soft delete only** — never hard delete
- **Audit log CREATE only** — never PATCH/DELETE
- **Budget Committed** — never written by UI (flow_commit only)
- **Debug field names** — background-colored, visible only on highlight or `?dcfg_debug=1`
- **Form principle** — cards collapse when auto-filled, expand only on override. Missing data is OK if the screen doesn't use it. Don't add fields that aren't there today.
- **After deploy** — clear cache + provide launch URLs
- **Solution name** — `DCFGSystemTest` on both environments

## ENVIRONMENT REFERENCE

| Env | Dataverse | Portal | Notes |
|-----|-----------|--------|-------|
| Test | org0c17e98d.crm.dynamics.com | DCGPortal.powerappsportals.com | Work Requests portal, NOT the SPA |
| Stage | org88778bb0.crm.dynamics.com | holding.powerappsportals.com | SPA deployed here |
| Prod | org06f5de0b.crm.dynamics.com | dmms1.powerappsportals.com | SPA deployed here, fully writable for testing |

## TEST DATA CREATED THIS SESSION (on prod)

- Customer: "UX Audit Test Customer" (Jane Smith, ux-test@example.com)
- Contract: Generated via wizard (Decades/Work Order, Bancroft customer, HHS Location)
- Onboarding Case: Created via New Case panel
- Location: "UX Audit Test Location" (200 Test Boulevard, Princeton NJ)

These should be cleaned up after the cleanup pass is complete and verified.
