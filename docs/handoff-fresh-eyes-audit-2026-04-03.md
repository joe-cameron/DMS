# Handoff — Fresh Eyes Audit & Fixes
**Date:** 2026-04-03
**Environment:** DCFGSystems-Prod (dmms1.powerappsportals.com) + DCFGSystems-Test (dcfg.powerappsportals.com)
**Operator:** Joseph Cameron

---

## Session Summary

Full fresh-eyes audit of the production SPA (dmms1), bug fixes deployed to both environments, compliance panel wired into contract wizard, user manual created and hosted, demo data seeded, and architectural review of BidComp (site-nnbam).

---

## What Was Done

### 1. Fresh Eyes Audit — 19 Screens Reviewed

Source code audit of every SPA screen against the Bancroft 7-point compliance checklist. Key finding: the system is a **data entry tool**, not a compliance enforcement engine. The 7-point checklist is verified by people, not software. Automated validation gates are not needed unless explicitly requested.

**Bancroft Compliance Context Saved:**
- External product name: **Decades GO**
- Client: Bancroft — contracts submitted to vendors@bancroft.org, entered into Workday
- 312 Workday cost centers identified from `Cost Centers-WorkDay.xlsx`
- `dcfg_ap_cost_codes` table in Prod is **empty** — needs population from Workday export
- Memory saved: `project_bancroft_compliance.md`

### 2. Bugs Fixed & Deployed (Test + Prod)

| Bug | File | Fix |
|-----|------|-----|
| Loading spinners frozen | App.jsx | Added `@keyframes dcfg-spin` and `@keyframes dcfg-pulse` to global styles |
| Close button encoding `âœ*` | CustomerDetail.jsx:265 | Replaced with `✕` + added `data-testid="custd-msa-btn-close"` |
| MsaList silent error swallow | MsaList.jsx | Added `error` state, catch stores message, renders `warn-banner` |
| Concierge URL mismatch | NavPanel.jsx, OnboardingDetail.jsx | Removed hardcoded fallbacks, config-driven via `concierge_portal_url` |

### 3. Config Records Created (Both Environments)

| Key | Test Value | Prod Value |
|-----|-----------|------------|
| `concierge_portal_url` | `https://dmssystems-test.powerappsportals.com` | `https://dmssystems-prod.powerappsportals.com` |
| `help_manual_url` | (SharePoint link) | (SharePoint link) |

### 4. Compliance Panel Wired into Contract Wizard

**Files changed:**
- `NewContractWizard.jsx` — Added `import CompliancePanel` and embedded it at Step 5 between Exhibit A summary and Generate button
- `CompliancePanel.jsx` — Modified `loadData()` to work without `contractId` (wizard preview mode). Manual checkboxes disabled when no contractId.

**Behavior:**
- Shows only for customers with compliance rules in `dcfg_compliance_rules`
- Runs automated validators against wizard state (line math, cost codes, dates, insurance)
- **Non-blocking** — Generate button works regardless of compliance status
- Returns `null` (invisible) if no rules exist for the customer

### 5. User Manual Created

**File:** `C:\DCFG\docs\decades-go-user-manual.html` (with screenshots)
**Self-contained:** `C:\DCFG\docs\decades-go-user-manual-standalone.html` (base64 images, 2.4MB)
**SharePoint:** Uploaded to `DCFG_Help/Decades-GO-User-Manual.html` with org-wide view link
**SPA route:** `/#/manual` — iframe wrapper at `src/screens/UserManual.jsx`, static HTML served from `public/user-manual.html`
**Nav link:** "User Manual" in Admin section of NavPanel (internal route, no external link)

**Screenshots captured:** 19 screens via Playwright against Prod, stored in `C:\DCFG\spa\dcfg-playwright\screenshots/`
**Test script:** `C:\DCFG\spa\dcfg-playwright\tests\fresh-eyes-screenshots.spec.ts`

### 6. Test Data Cleanup & Demo Data Seeded (Prod)

**Cleaned (soft-deleted):**
- 13 contracts, 1 contract line, 60 MSAs, 70 MSA rates
- 18 onboarding cases, 480 onboarding steps
- 1 document request
- 615 audit logs **kept**

**Demo data created:**

| MSA | Customer | Budget | Committed | Expiration | Alert |
|-----|----------|--------|-----------|------------|-------|
| Bancroft Facilities Services 2026 | Bancroft | $500,000 | $180,000 | Dec 31, 2026 | — |
| PennReach Property Maintenance 2026 | PennReach | $120,000 | $112,000 | Sep 30, 2026 | **Budget warning (93%)** |
| J-ADD Building Services 2026 | J-ADD | $85,000 | $45,000 | Dec 31, 2026 | — |
| The Arc Mercer Facilities 2026 | The Arc Mercer | $240,000 | $96,000 | **May 12, 2026** | **Expiring (39 days)** |
| Newgrange Campus Maintenance 2026 | Newgrange | $156,000 | $78,000 | Dec 31, 2026 | — |

| Contract | Customer | Location | Fee | Status | Alert |
|----------|----------|----------|-----|--------|-------|
| WO-2026-001 | Bancroft | 1981 Old Cuthbert Rd | $8,200 | Signed | — |
| WO-2026-002 | Bancroft | 1981 Old Cuthbert Rd | $3,400 | Sent (Mar 17) | **Unsigned 17 days** |
| WO-2026-003 | PennReach | Garrett 161 | $12,800 | Generated | Pending review |
| WO-2026-004 | PennReach | Grove 320 | $45,000 | Draft | — |
| WO-2026-005 | J-ADD | 118 Ayers | $6,750 | Sent (Mar 29) | — |
| WO-2026-006 | The Arc Mercer | (no location) | $4,200 | Generated | Pending review |
| WO-2026-007 | Newgrange | (no location) | $2,800 | Signed | — |

| Onboarding Case | Customer | Progress | Phase |
|-----------------|----------|----------|-------|
| OB-2026-301 | PennReach | 24/32 (75%) | Site Onboarding |
| OB-2026-302 | The Arc Mercer | 7/32 (22%) | Contract Execution |
| OB-2026-303 | Newgrange | 30/32 (94%) | Go-Live & Monitoring |

**Script:** `C:\DCFG\scripts\create-demo-data.ps1`

### 7. BidComp Architectural Review (site-nnbam.powerappsportals.com)

**14 problems identified.** Real site is `site-nnbam.powerappsportals.com`. `dmsbuilder.powerappsportals.com` is an orphan — delete it.

| # | Problem | Severity |
|---|---------|----------|
| 1 | 403 on every API call — table permissions not configured | FATAL |
| 2 | Debug module missing — FieldName.jsx imports nonexistent ./debug/ | FATAL |
| 3 | No customer concept — no selector, no context, no filtering | ARCHITECTURAL |
| 4 | `loadConfig()` never called — boot sequence broken | BROKEN |
| 5 | No auth guard — unauthenticated users see full app with empty data | BROKEN |
| 6 | Tracker inline edit uses `apiPost` instead of `apiPatch` — every edit fails | BROKEN |
| 7 | Invoices fetch ALL records — no filtering by contract/phase | BROKEN |
| 8 | No audit logging — `writeAuditLog` exists but never called | COMPLIANCE |
| 9 | Hardcoded "FY26" in Tracker title | UX |
| 10 | Toast type keys wrong — callers use `'success'`/`'error'`, Toast expects `'ok'`/`'err'` | UX |
| 11 | Excel export buttons are empty `() => {}` | UX |
| 12 | portalApi.js is 54KB full copy of dcfg-shell — 600 lines dead code | TECH DEBT |
| 13 | No error states on any screen — 403s swallowed silently | UX |
| 14 | 5 of 13 spec'd screens built — no Coming Soon indicators | EXPECTATIONS |

**Fix sequence:**
1. Resolve 403s (table permissions on site-nnbam)
2. Add error states to all screens
3. Add auth guard
4. Fix `apiPost` → `apiPatch` on Tracker
5. Fix Toast type keys
6. Add customer concept (CustomerSelector + ContractSelector cascade)
7. Filter invoices by contract phases
8. Call `loadConfig()` in App.jsx
9. Wire Excel export buttons
10. Add session audit logging

**Source:** `C:\DCFG\spa\dcfg-bidcomp\src\`
**Spec:** `C:\DCFG\docs\superpowers\specs\2026-04-02-bidcomp-module-design.md`

---

## Outstanding Items (Not Done This Session)

1. **Bancroft cost codes** — `dcfg_ap_cost_codes` table is empty in Prod. 312 Workday cost centers from Excel need to be loaded. Source: `C:\Users\JosephCameron\OneDrive - Decades Construction Group\Brook\Cost Centers-WorkDay.xlsx`
2. **Compliance screen route** — `/#/compliance` is orphaned (CompliancePanel needs contract context). Could be removed from router or repurposed.
3. **User Manual iframe** — Power Pages may not serve static HTML from `public/` folder. If `/#/manual` shows blank, convert manual content to a React component instead.
4. **BidComp fixes** — 14 problems identified, none fixed yet. Start with 403 resolution.
5. **Demo data gaps** — WO-2026-006 and WO-2026-007 have no location assigned. Amendment (AMD-2026-001) failed to create due to wrong parent lookup field name.
6. **Fresh eyes observations not fixed** — Compliance readiness % counts "unable to verify" against score; MsaList missing "+ New MSA" button; location name shows raw address as title (data issue on Bancroft location record).

---

## Cache Clear URLs

- **Test:** https://dcfg.powerappsportals.com/_services/about/cache/clear
- **Prod:** https://dmms1.powerappsportals.com/_services/about/cache/clear

---

## Files Changed (SPA — deployed to both environments)

| File | Change |
|------|--------|
| `src/App.jsx` | Added `@keyframes dcfg-spin` and `@keyframes dcfg-pulse` |
| `src/screens/CustomerDetail.jsx` | Fixed close button encoding, added data-testid |
| `src/screens/MsaList.jsx` | Added error state + warn-banner |
| `src/screens/CompliancePanel.jsx` | Made `contractId` optional for wizard preview mode |
| `src/screens/UserManual.jsx` | **NEW** — iframe wrapper for user manual |
| `src/NavPanel.jsx` | Removed concierge fallback URL, added User Manual nav link |
| `src/screens/OnboardingDetail.jsx` | Removed concierge fallback URL |
| `src/NewContractWizard.jsx` | Added CompliancePanel import + embed at Step 5 |
| `src/AppRouter.jsx` | Added `/manual` route + UserManual import |
| `public/user-manual.html` | **NEW** — self-contained user manual (2.4MB) |

---

*Decades Construction & Facilities Group — Our passion is your mission.*
