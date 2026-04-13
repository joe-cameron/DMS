# Category 2: Console Pollution — Phase 2b Audit

**Auditor:** phase-2b-console agent
**Date:** 2026-04-12
**Branch:** code-review-2026-04-09
**Scope:** All in-scope SPA files under `C:\DCFG\spa\dcfg-shell\src\` (excludes `_archive/`, `debug/`, `interview/`, `test/`, `NoraCopilot.jsx`, `AbsorptionDashboard.jsx`, `UserManual.jsx`, `CapitalPlan.jsx`)
**Finding IDs:** CR-2026-04-09-0400 through CR-2026-04-09-0434
**Findings file:** `C:\dcfg\docs\code-review-2026-04-09\phase2b-findings.json`

---

## Executive Summary

The SPA has **82 `console.*` calls** across in-scope files (plus 1 `alert()` call). After applying the exclusion rules, **35 findings** were cataloged. Zero `debugger;` statements found. One `alert()` call found (in MsaComposer CSV import).

The dominant pattern is `catch (e) { console.error('...', e); }` without a corresponding `toast.show()` call. This means API failures are invisible to the user -- the screen simply shows empty data or doesn't update, and the user has no way to know whether the data is empty or the API failed. This is the highest-impact category for external-tester readiness.

---

## Scan Results

| Signal | Count Found | Excluded | Findings Filed |
|--------|-------------|----------|----------------|
| `console.log()` | 1 | 0 | 1 |
| `console.error()` | 40 | 13 | 22 |
| `console.warn()` | 20 | 12 | 6 |
| `console.info()` | 3 | 2 | 1 |
| `console.debug()` | 0 | 0 | 0 |
| `debugger;` | 0 | 0 | 0 |
| `alert()` | 1 | 0 | 1 |
| **Total** | **65** | **27** | **35** |

Note: The 82 total calls mentioned above includes calls inside the `debug/` folder (9 calls) and `AbsorptionDashboard.jsx` (1 call), both of which are out of scope and not counted in the 65 above. Also some files have multiple console calls on the same conceptual issue (e.g., portalApi.js token strategies 1-3 are 3 calls but one logical exclusion).

---

## Exclusions Breakdown

| Exclusion Reason | Count | Files |
|------------------|-------|-------|
| `debug/index.js` (excluded per spec) | 9 | debug/index.js |
| `Toast.jsx` (allowed to log own state) | 1 | Toast.jsx |
| `ErrorReporter.jsx` (allowed to log) | 0 | (no console calls found) |
| `AbsorptionDashboard.jsx` (out of scope) | 1 | AbsorptionDashboard.jsx |
| Diagnostic inside catch + toast (KEEP) | 16 | portalApi.js, ContractDetail.jsx, SendQueue.jsx, NewContractWizard.jsx, CompliancePanel.jsx, UserRolesTab.jsx, TemplateDetail.jsx, TemplateList.jsx, MapView.jsx, LocationManager.jsx, ProjectList.jsx, ProgramDetail.jsx, Operations.jsx |
| Intentional infrastructure diagnostic (boot/config/auth) | 8 | portalApi.js (getToken strategies, loadConfig, audit hook, onboarding fallbacks, copyTemplateSteps), usePortalUser.jsx, SlideOutPanel.jsx, SpeechMic.jsx, RoleGuard.jsx, SensorBanner.jsx |
| **Total excluded** | **27** | |

Note: Several of the "intentional infrastructure diagnostic" exclusions were specifically added by Phase 1 fixes (CR-0213, CR-0215, CR-0216, CR-0230, CR-0235, CR-0236, CR-0242) and are correctly placed.

---

## Findings by Recommended Action

| Action | Count | Tier |
|--------|-------|------|
| **delete** — pure dev diagnostic, no replacement needed | 4 | auto-fix |
| **replace with toast** — catch block needs user-facing feedback | 22 | 18 auto-fix, 4 batch |
| **keep-gated** — borderline intentional, needs gate or cleanup | 4 | batch |
| **keep-intentional** — correctly paired with toast or error state | 5 | auto-fix (no action) |
| **Total** | **35** | |

---

## Hotspots by File

| File | Findings | Pattern |
|------|----------|---------|
| `screens/Admin.jsx` | 14 | Every admin tab has load + save catches that log to console only. The delete handler (line 296) is the only one with a toast. Systematic fix: add `const toast = useToast()` to every tab component and replace every `console.error(...)` with `console.error(...); toast.show('err', ...)`. |
| `MsaComposer.jsx` | 5 | Mix of console.log (injection stats), console.error without toast (loc types, pricing configs, draft save), and alert() (CSV import). |
| `NewContractWizard.jsx` | 1 | Draft save error (P3, same pattern as MsaComposer/ContractComposer). |
| `ContractComposer.jsx` | 1 | Draft save with conditional silent flag (P3, keep-gated). |
| `screens/templates/TemplateDetail.jsx` | 2 | Load customers + load template both console-error-only. |
| `contracts/useContractData.jsx` | 2 | Truncation warn (keep-gated) + load error (needs toast). |
| `screens/Onboarding.jsx` | 2 | console.info in happy path + error catch without toast. |
| Remaining files | 8 | One finding each across CustomerDetail, MsaDetail, FlowMonitor, LocationDetail, TemplateList, useTemplateFields, ProgramDetail. |

---

## Relationship to Phase 1 Findings

Phase 1 already identified the **thematic issue** of console-only error handling in several files:
- CR-2026-04-09-0225 (App.jsx session audit log -- fixed, kept as-is)
- CR-2026-04-09-0251 (Admin tabs missing toast -- this is the error-handling finding; the Phase 2b findings here are the specific console-pollution instances per line)
- CR-2026-04-09-0252 (CompliancePanel console-only -- now has toast per fix)
- CR-2026-04-09-0269 (OnboardingDetail step field save -- now has toast per fix)

This Phase 2b audit is complementary: it catalogs every individual console call for the fix batch to consume, whereas Phase 1 found the pattern at the file level.

---

## Recommendations for Fix Batch

1. **Admin.jsx** is the single highest-leverage fix target (14 findings, all the same pattern). A single fix batch that adds `const toast = useToast()` to each tab and pairs every catch with `toast.show('err', ...)` eliminates 14 findings at once.

2. **MsaComposer.jsx** needs 4 fixes: delete the `console.log` stats line, add toast to the two load-error catches, and replace `alert()` with `toast.show('err', ...)`.

3. **Onboarding.jsx** needs 2 fixes: delete the `console.info` in the happy path, add toast to the error catch.

4. The **keep-gated** findings (CR-0406, CR-0421, CR-0427, CR-0428) can be deferred to a later cleanup pass. They are borderline intentional and low-impact.

5. The **keep-intentional** findings (CR-0430, CR-0431, CR-0434) require no action -- they are correctly paired with toast or error state.
