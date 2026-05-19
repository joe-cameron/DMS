# DCFG Code Review — 2026-05-18

**Scope:** Full SPA source, Azure Functions, root-level scripts, dead code analysis.
**Branch:** `code-review-2026-04-09`
**Backup:** `C:\dcfg\_code-review-snapshot` (10,372 files, ~100 MB)
**Reviewed by:** 4 parallel agents + manual review of core files

---

## Executive Summary

| Category | Count | Severity |
|----------|-------|----------|
| Runtime bugs (will crash) | 5 | CRITICAL |
| Logic bugs (wrong results) | 2 | HIGH |
| Customer names in production code | 5 files | HIGH |
| Dead code files to delete | 27+ files | HIGH |
| Obsolete comments to clean | ~70 CR refs + stale notes | MEDIUM |
| Optimization opportunities | 12 | MEDIUM |
| Dead PS1 scripts (archive candidates) | ~130 files | LOW |
| Style inconsistencies | 6 | LOW |

---

## 1. RUNTIME BUGS — Will Crash When Hit

### 1a. Admin.jsx:155 — `toast` not in scope
`toast.show()` is called inside the `Admin` component's `handleCardClick`, but `useToast()` is only called inside child tab components, not in `Admin` itself. Clicking the Demo Fill toggle will throw `ReferenceError: toast is not defined`.

**Fix:** Add `const toast = useToast();` inside the `Admin` function body.

### 1b. CustomerDetail.jsx:394 — `toast` not in scope in OnboardingTab
`toast.show('err', ...)` is called in `OnboardingTab` but `toast` is never declared there (no `useToast()` call, no prop). If the email send in `handleMarkComplete` fails, this throws `ReferenceError`.

**Fix:** Add `const toast = useToast();` inside `OnboardingTab`.

### 1c. interviewGenerate.js:74,151 — imports banned `callFlow` that doesn't exist
```js
import { apiPost, apiPostReturn, apiPatch, apiGet, callFlow, writeAuditLog, ... } from '../portalApi.js';
```
`callFlow` is not exported from current `portalApi.js`. Import will fail at module load time. AppRouter line 132 confirms: "Interview route removed — composers are the sole creation paths." Entire `interview/` directory (7 files) is dead.

**Fix:** Delete entire `src/interview/` directory (7 files).

### 1d. NavPanel.jsx:211 — `isAdmin` used as value, not function call
`isAdmin` from `usePortalUser()` is a function, but it's used as a truthy value: `{isAdmin && (...)}`. Since all functions are truthy, the CLEARANCE link is **visible to ALL users**, not just admins.

**Fix:** Change to `{isAdmin() && (...)}`.

### 1e. sharepointUpload.js:168,207,262,337 — Path encoding breaks Graph API
`encodeURIComponent()` is applied to full paths including `/` separators, converting them to `%2F`. This breaks Graph API path resolution for multi-level folders.

```js
// BUG: encodes slashes in path
`root:/${encodeURIComponent(folderPath)}`
// FIX: encode each segment
`root:/${folderPath.split('/').map(encodeURIComponent).join('/')}`
```

Affects: folder-exists check (168), chunked upload (207), simple upload (262), file verification (337). Note: `docusignSend.js:169` already does this correctly.

**Fix:** Replace `encodeURIComponent(path)` with segment-by-segment encoding at all 4 locations.

---

## 2. LOGIC BUGS — Wrong Results

### 2a. portalApi.js:1002 — `fetchAmendments` filter value `1` is wrong
```js
export function fetchAmendments(parentId) {
  return apiGet("/" + EntitySets.contracts + "?$filter=_dcfg_parent_contract_id_value eq " + parentId +
    " and dcfg_contract_type eq 1&$select=...");
}
```
`dcfg_contract_type eq 1` — but `ContractType.Amendment` is `100000001`, not `1`. This function **always returns zero results**.

**Fix:** Change `eq 1` to `eq ${ContractType.Amendment}` (100000001).

### 2b. KPI functions missing `dcfg_active_flag` filter
Three functions include soft-deleted records in KPI counts:
- `fetchActiveContracts()` (line 992)
- `fetchPendingSignatures()` (line 993)
- `fetchContractsThisMonth()` (line 994)

**Fix:** Add `dcfg_active_flag eq true and` to each filter.

---

## 3. CUSTOMER NAMES IN PRODUCTION CODE

Per project rules: No customer names in production code/UI strings.

| File | Line | Violation | Fix |
|------|------|-----------|-----|
| `CustomerDetail.jsx` | 30 | `LOGO_MAP` hardcodes 8 customer names (J-ADD, Arc Mercer, PennReach, Bancroft, etc.) | Move to `dcfg_configs` or customer `dcfg_logo_filename` column |
| `SigningWorkflowEditor.jsx` | 21 | Labels: "Work Order (Bancroft)", "Vendor Agreement (Bancroft)" | Change to "Work Order (TPA)", "Vendor Agreement (TPA)" |
| `autoMapper.js` | 43 | Label: "Bancroft PO number" | Change to "PO Number" |
| `inspectionSync.js` | 10,12,254,260 | "PennReach, J-ADD..." in comments + `name: 'bancroft'` in code | Use generic: "Account 1", "Account 2" |
| `sharepointUpload.js` | 33 | "Bancroft" in JSDoc example | Change to "Acme Corp" |

---

## 4. DEAD CODE — Files to Delete

### 4a. `_archive/` directory (4 files)
All import retired APIs (`callFlow`, `apiPostReturnRecord`).

| File | Status |
|------|--------|
| `src/_archive/NewContractWizard.jsx` | Dead — imports `callFlow` |
| `src/_archive/NewContractForm.jsx` | Dead — defines own `callFlow()` |
| `src/_archive/NewContractForm.css` | Dead — stylesheet for above |
| `src/_archive/Shell.jsx` | Dead — old router with retired components |

### 4b. `interview/` directory (7 files)
AppRouter confirms route removed. `interviewGenerate.js` imports nonexistent `callFlow`.

| File | Status |
|------|--------|
| `interview/interviewGenerate.js` | Dead — uses `callFlow` |
| `interview/ChatMode.jsx` | Dead — no route |
| `interview/ConversationalMode.jsx` | Dead — no route |
| `interview/GuidedMode.jsx` | Dead — no route |
| `interview/InterviewEngine.js` | Dead — no route |
| `interview/InterviewShell.jsx` | Dead — no route |
| `interview/InterviewSidebar.jsx` | Dead — no route |

### 4c. Root-level JS/JSX (8 files)
All reference outdated APIs or wrong entity sets.

| File | Evidence |
|------|----------|
| `portalApi.js` (root) | Exports `callFlow`, `apiPostReturnRecord` — OLD version |
| `NewContractWizard.jsx` (root) | Uses `callFlow` (banned) |
| `NewMsaProposal.jsx` (root) | Uses `dcfg_propertys` (wrong entity set) |
| `NewProposalWizard.jsx` (root) | Old wizard, replaced by `MsaComposer.jsx` |
| `OnboardingScreen.jsx` (root) | People names in comments ("Jenn, Joe") |
| `onboardingApi.js` (root) | Uses `dcfg_propertys` in 5 places |
| `pp-skills-install.js` (root) | One-time install, already executed |
| `temp_logo_data.js` (root) | 75K+ token scratch data |

### 4d. Orphan JSX files in `spa/` root (12 files)
Duplicates of files in `spa/dcfg-shell/src/screens/`. Most use `callFlow`.

`spa/portalApi.js`, `spa/NewContractWizard.jsx`, `spa/ContractDetail.jsx`, `spa/ContractList.jsx`, `spa/CustomerDetail.jsx`, `spa/CustomerList.jsx`, `spa/MsaList.jsx`, `spa/MsaDetail.jsx`, `spa/SendQueue.jsx`, `spa/Locations.jsx`, `spa/LocationDetail.jsx`, `spa/SalesDashboard.jsx`, `spa/AppRouter.jsx`

### 4e. Duplicate portalApi.js copies in sub-apps (3 files)
Canonical: `spa/dcfg-shell/src/portalApi.js`. Delete copies at:
- `spa/dcfg-admin/src/portalApi.js`
- `spa/dcfg-contracts/src/portalApi.js`
- `spa/dcfg-bidcomp/src/portalApi.js`

### 4f. Other dead code in SPA screens
| File | Line | Issue |
|------|------|-------|
| `Admin.jsx` | 976-1189 | ~213 lines commented-out EquipmentBenchmarks block |
| `MsaDetail.jsx` | 283 | Unused `Metric` function (budget panel removed) |
| `Onboarding.jsx` | 138 | `stepCount` assigned but never used |
| `NavPanel.jsx` | — | `MonitorIcon`, `ReportIcon` defined but never used |
| `NavPanel.jsx` | — | Full dark-mode infrastructure gated behind `isDark = false` |
| `Directory.jsx` | 37 | `WebIcon` defined but never used |
| `portalApi.js` | 116-124 | `TemplateMap` — V3 retired, dead export |
| `FacilitiesDashboard.jsx` | all | Trivial wrapper: `return <Operations />` — consider removing |
| `CompliancePanel.jsx` | 181,188 | Redundant `x \|\| x` expressions (both sides identical) |

### 4g. Dead V3 test files (3 files)
- `test/test-local.js` — sends HTML, expects PDF (V3 pattern)
- `test/test-bancroft-wo.js` — uses pdfkit (V3 pattern)
- `test/test-pdfmake.js` — uses pdfmake (not in dependencies)

### 4h. Dead Azure Function artifacts
- `package.json`: unused dependency `fast-xml-parser`
- `package.json`: test script points to dead V3 test (`test-local.js`)
- `INSPECTION_CATEGORIES` constant defined but never used in `inspectionSync.js`

---

## 5. AZURE FUNCTION QUALITY ISSUES

### 5a. Missing HTTP response checks in inspectionSync.js
`fetch()` calls don't check `resp.ok` — HTTP errors (4xx/5xx) are silently treated as success:
- UpKeep auth (line 70)
- WO fetch (line 112)
- Dataverse PATCH (line 184)
- Dataverse POST (line 224)

**Fix:** Add `if (!resp.ok) throw new Error(...)` after each fetch.

### 5b. Missing PATCH response checks in docusignPoll.js
Queue update (line 181) and contract status update (line 192) don't check response. A failed PATCH leaves inconsistent state.

### 5c. Hardcoded Prod URL fallback in inspectionSync.js:244
```js
var dvUrl = process.env.DATAVERSE_URL || 'https://org06f5de0b.api.crm.dynamics.com';
```
If env var is missing, silently targets **Prod**. Remove the fallback — fail explicitly.

### 5d. Auth code duplicated across 4 function files
`getDocuSignToken()`, `getGraphToken()`, `getDataverseToken()` copy-pasted across `docusignSend.js`, `docusignComplete.js`, `docusignPoll.js`, `inspectionSync.js`, `customers.js`. Each has its own token cache.

**Fix:** Extract to shared `src/shared/auth.js` module.

### 5e. Package naming — completely wrong
- Package description: "Converts HTML to PDF via Puppeteer" — no Puppeteer, no HTML-to-PDF
- Package name: `dcfg-html-to-pdf` — describes none of the 7 functions

**Fix:** Rename to `dcfg-functions`, update description.

### 5f. docusignPoll.js schedule comment doesn't match code
Header says `0 0 6-23 * * *` but actual schedule is `0 0 10-4 * * *`.

### 5g. htmlToPdf.js doesn't export functions
Injection functions not exported, forcing tests to reimplement logic with subtle differences (e.g., `test-msa-inject.js` has incomplete `escapeXml` missing `&quot;`).

### 5h. docusignSend.js:397 — Wrong key in safety delete
```js
delete safeBody.file_base64;  // WRONG: actual field is fileBase64
```

---

## 6. OBSOLETE COMMENTS

### 6a. ~70 `CR-2026-04-09-XXXX` references across 30 files
Session-specific code review notes. Strip prefixes, keep explanations where non-obvious, delete narration-only comments ("trimmed imports", "dropped unused").

**Files with highest density:** `portalApi.js` (6), `SlideOutPanel.jsx` (4), `SensorBanner.jsx` (4), `Operations.jsx` (4), `SendQueue.jsx` (4)

### 6b. Stale fallbacks marked "can be deleted"
```
portalApi.js:866 — "After Phase 0 parity sweep confirms... this fallback can be deleted"
portalApi.js:883 — same
```

### 6c. Stale session/temporal comments
| File | Issue |
|------|-------|
| `AppRouter.jsx:6-9` | "CHANGES (2026-03-12)" with "this session" language |
| `AppRouter.jsx:30,67` | "Existing screens (unchanged)" / "New modules (this session)" |
| `AppRouter.jsx:94` | "Legacy alias... retire once all nav/links point to /msa/new" |
| `AppRouter.jsx:128` | "temporary until devices arrive" |
| `App.jsx:337` | Comment says "BrowserRouter" but code uses HashRouter |
| `FlowMonitor.jsx:127` | Subtitle says "DocGen v2" — should be V4 |
| `SendQueue.jsx:1061` | "Search moved to header bar — FAB removed" |

---

## 7. OPTIMIZATION OPPORTUNITIES

| Issue | Files | Fix |
|-------|-------|-----|
| `haversine()` duplicated 3× | Directory.jsx, VendorList.jsx, VendorsTab.jsx | Extract to `lib/geo.js` |
| SVG icons duplicated | Directory.jsx, VendorList.jsx | Extract to shared `Icons.jsx` |
| Leaflet loaded from CDN + npm | CustomerDetail.jsx (CDN) vs MapView.jsx (npm) | Use npm consistently |
| Operations.jsx polling no visibility gate | Operations.jsx | Add `document.hidden` guard (like AbsorptionDashboard) |
| portalApi.js unused params | `resolveTemplateId(_family, ..., _opts)` | Remove after checking callers |
| ViewSplitPanel manual OData escaping | ViewSplitPanel.jsx | Use exported `escapeOdataString()` |
| contractDocGen.js hardcoded SP_SITE | lib/contractDocGen.js:16 | Use `getEnvVar('dcfg_sp_site_url')` |
| debug sniffUser reads wrong property | debug/index.js | Read `raw.userRoles` not `raw.roles` |
| Missing data-testid on 3 screens | CapitalPlan, FlowMonitor, MapView | Add testids |

---

## 8. STYLE INCONSISTENCIES

| File(s) | Issue |
|---------|-------|
| `inspectionSync.js` | Uses `var` throughout (~30 places) — all other files use `const/let` |
| `NewProjectScreen.jsx`, `NewRfpWizard.jsx`, `UserRolesTab.jsx` | Use `var` + `React.createElement` instead of `const` + JSX |
| `main.jsx` | Uses React 17 `ReactDOM.render` instead of `createRoot` |
| `customers.js` | Uses SP_* env vars for Dataverse auth (misleading names) |

---

## 9. PS1 SCRIPT CLEANUP (~130 archive candidates)

Of 611 root-level PS1 scripts, ~130 are one-time scripts that have already been executed:
- **37** `temp_`/`tmp_` prefixed diagnostic scripts
- **11** `PermTest_Debug` iteration files
- **6** V3 DocGen scripts (retired)
- **30+** versioned iteration series (v1/v2/v3/v4/v5.x — only final has value)
- **8** `Patch_FlowDocgen` iteration series
- **25+** one-time seed/cleanup/fix scripts with hardcoded record IDs
- **14** diagnostic/debug scripts

No hardcoded credentials found — all use proper `Get-AzAccessToken` pattern.

---

## 10. RECOMMENDED CLEANUP ORDER

### Phase 1 — Fix runtime bugs (highest priority)
1. Fix `Admin.jsx` toast scope bug
2. Fix `CustomerDetail.jsx` OnboardingTab toast scope bug
3. Fix `NavPanel.jsx` `isAdmin` → `isAdmin()` call
4. Fix `portalApi.js` `fetchAmendments` filter value `1` → `100000001`
5. Fix `sharepointUpload.js` path encoding (4 locations)
6. Fix `docusignSend.js` `file_base64` → `fileBase64`

### Phase 2 — Safe deletes (no behavior change)
7. Delete `src/_archive/` directory (4 files)
8. Delete `src/interview/` directory (7 files)
9. Delete root-level JSX/JS files (8 files)
10. Delete orphan `spa/` root JSX files (12 files)
11. Delete sub-app portalApi.js copies (3 files)
12. Delete `TemplateMap` from portalApi.js
13. Delete Admin.jsx commented-out EquipmentBenchmarks block (~213 lines)
14. Delete dead V3 test files (3 files)
15. Remove unused `fast-xml-parser` dependency

### Phase 3 — Comment cleanup
16. Strip CR-2026-04-09 prefixes, delete narration-only comments
17. Delete stale temporal comments in AppRouter
18. Fix misleading comments (BrowserRouter, DocGen v2, schedule)
19. Replace customer names in production code (5 files)

### Phase 4 — Code quality
20. Add `resp.ok` checks in inspectionSync.js and docusignPoll.js
21. Remove hardcoded Prod URL fallback in inspectionSync.js
22. Add `dcfg_active_flag` filter to 3 KPI functions
23. Extract duplicated auth code to shared module
24. Extract haversine/icons to shared utilities
25. Fix hardcoded SP_SITE in contractDocGen.js
26. Export htmlToPdf.js injection functions for testing

### Phase 5 — Low priority
27. Replace `var` with `const/let` in inspectionSync.js + 3 screen files
28. Update main.jsx to React 18 createRoot
29. Fix package naming (dcfg-html-to-pdf → dcfg-functions)
30. Archive ~130 PS1 scripts
