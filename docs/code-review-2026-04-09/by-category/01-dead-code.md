# Category 1: Dead Code & Duplicates — Phase 2a Audit

**Agent:** phase-2a-dead-code
**Date:** 2026-04-12
**Finding range:** CR-2026-04-09-0311 through CR-2026-04-09-0324
**Total findings:** 14
**Data file:** `../phase2a-findings.json`

---

## Summary

Phase 2a audited all in-scope files under `src/` (excluding `_archive/`, `debug/`, `interview/`, `test/`, NoraCopilot, AbsorptionDashboard, UserManual, CapitalPlan) for dead code: duplicate files, unused imports, unused state declarations, orphaned functions, unreachable code, and dead variables.

Phase 1 already identified and fixed 4 dead-code findings (CR-0001 through CR-0004, plus CR-0309). This pass found **14 new findings** that Phase 1 did not cover.

## Key Findings

### 1. Entire dead file: NewContractWizard.jsx (CR-0311 + CR-0312)

The most significant finding. `NewContractWizard.jsx` (1673 lines) is **fully replaced** by `ContractComposer.jsx`. The AppRouter still imports it at line 53 with a `// TODO retire after composer cutover` comment, but never renders it in any route. The `/contracts/new` route uses `<ContractComposer />`. This means 1673 lines of dead code plus its dependency tree are bundled but never executed.

**Impact:** Bundle bloat. No runtime risk since the component is never mounted.
**Fix:** Two-part. (1) Remove the dead import from AppRouter (auto-fix). (2) Delete the entire file (DESTRUCTIVE, batch).

### 2. Dead exports in portalApi.js (CR-0314 through CR-0322)

Nine exports in `portalApi.js` are never imported by any file in the SPA:

| Export | Line | Category |
|--------|------|----------|
| `apiPostReturnRecord` | 860 | Backward-compat alias, all consumers migrated |
| `Urgency` | 97 | Enum; ProjectList uses inline constants instead |
| `ReplaceByStatus` | 99 | Enum; LocationManager reads raw values |
| `AlertStatusLabel` | 113 | Superseded by ALERT_STATUS_MAP |
| `invalidateToken()` | 130 | Token management; no logout/recovery flow uses it |
| `fetchDocumentRequests()` | 853 | Shared fn; screens use inline apiGet instead |
| `fetchTemplateLines()` | 906 | Pre-built for unfinished template-to-project copy |
| `updateProject()` | 895 | Wrapper; ProjectDetail uses apiPatch directly |
| `createRfpVendor()`, `createProposal()`, `updateProposal()` | 923-927 | Pre-built for unfinished RFP vendor/proposal UI |

**Impact:** No runtime impact (tree-shaking may or may not exclude them depending on build config). Maintenance burden: future developers may incorrectly assume these are in use.
**Fix:** Auto-fix for clear dead exports. For pre-built functions (fetchTemplateLines, createRfpVendor, etc.), mark with `// KEEP` if the feature is planned near-term, or remove.

### 3. Dead state variable in NewContractWizard (CR-0313)

`vendorMSAList` (line 120) is fetched and stored via `setVendorMSAList` but the value is never read in any JSX or logic. Subordinate to CR-0312 (entire file is dead), but notable as a pattern.

### 4. Dead export in projectConstants.js (CR-0323)

`fmtDate` is exported but never imported. Date formatting across the SPA is done inline.

### 5. Dead variable in ContractsList.jsx (CR-0324)

`NAVY_MID` design token is declared but never referenced.

## Breakdown by Tier

| Tier | Count | Description |
|------|-------|-------------|
| **auto-fix** | 12 | In-file cleanups: remove unused imports, exports, variables |
| **batch** | 2 | File deletion (NewContractWizard.jsx) + dead import removal |

## Breakdown by Severity

| Severity | Count |
|----------|-------|
| P2 | 2 (NewContractWizard dead import + dead file) |
| P3 | 12 (dead exports, dead state, dead variables) |

## What Was NOT Found

- **No additional duplicate files** beyond those already fixed by Phase 1 (CR-0002 AppRouter duplicate, CR-0003 ContractList duplicate). The screens/AppRouter.jsx and screens/ContractList.jsx were already deleted.
- **No large commented-out code blocks (>5 lines)** that aren't documentation comments or CR-tagged explanatory notes.
- **No unreachable code after early returns** in any in-scope file.
- **No orphaned non-exported functions** -- all declared functions are either called in the same file or exported.
- **Phase 1 import cleanups held** -- MsaList, Directory, ContractList unused imports were already fixed and not re-introduced.

## Pre-Seed Findings Status

| ID | Title | Status |
|----|-------|--------|
| CR-0001 | Stray `)}` in NewContractWizard | Fixed |
| CR-0002 | Duplicate AppRouter | Fixed |
| CR-0003 | Duplicate ContractList | Fixed |
| CR-0004 | `_archive/` folder | Open (DESTRUCTIVE, awaiting approval) |
| CR-0309 | ContractsList duplicate confirmation | Rejected (corrected direction) |
