# Batch 07 — Phase 1 P3 Cleanup (Unused imports / perf / error-handling / handoff / auth)

**Phase:** 1 (residual P3 grab-bag — unused-import sweep + small perf + error-handling polish + handoff cleanliness + 1 auth defense-in-depth)
**Target:** SPA source under C:\DCFG\spa\dcfg-shell\src\
**Findings count:** 15 selected, 14 proposed for execution (1 drift-rejected — see Group A note for CR-0288)
**Generated:** 2026-04-10T13:30:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-07-phase1-p3-cleanup.md
**Predecessor batches:**
  - batch 01: approvals/2026-04-09-batch-01-phase1-shared.md (SPA commit 39f8efb)
  - batch 02: approvals/2026-04-09-batch-02-phase1-expansion.md (SPA commits 30c693b + c48949f)
  - batch 03: approvals/2026-04-09-batch-03-phase1-p2-cleanup.md (SPA commit e727a8b)
  - batch 04: approvals/2026-04-09-batch-04-phase1-errhandling-security.md (SPA commit dfd1efc)
  - batch 05: approvals/2026-04-09-batch-05-phase1-perf-auth-data.md (SPA commit 4250f9e)
  - batch 06: approvals/2026-04-09-batch-06-phase1-schema-p3-cleanup.md (SPA commit 78f4089)

## Housekeeping status transitions (NOT in this batch — operator action during approval)

The parent's pre-batch schema verification produced one status transition that should be recorded in `findings.json` during approval, NOT executed as an edit in this batch:

- **CR-2026-04-09-0310 — REJECT.** Admin VendorsTab `$select` cites neither `dcfg_trade` nor `dcfg_trades`; the Admin vendor surface simply does not capture trade at all. Schema verification (parent batches 06 and the pre-check for this batch) confirmed `dcfg_vendor.dcfg_trade` (singular) EXISTS and is the canonical column. Same conclusion as CR-2026-04-09-0279 (VendorList) and CR-2026-04-09-0293 (VendorDetail) which were both schema-verified clean: the schema is consistent, and the only "inconsistency" the finding flagged is that Admin's form is missing a trade field while VendorList/Directory display it. That is a UX gap, not a schema bug, and falls outside the data-integrity-select-safety category the finding was filed under. **Reject reason:** `"schema-verified: dcfg_vendor.dcfg_trade (singular) is the canonical column. Admin VendorsTab $select is schema-valid (does not reference any trade column). The 'inconsistency' flagged by the finding is a missing-form-field UX gap, not a select-safety bug. File a follow-up for the UX gap if Admin should capture vendor trade going forward."`

This transition is recorded here so the operator sees it during the batch review pass. Per the critical rules, this doc does NOT modify findings.json — the housekeeping pass that records the transition is separate.

## Scope rules (from spec §4.6)

- Batch size = 15 selected, 14 effective (1 drift-rejected during pre-edit verification — CR-0288, see Group A)
- All `batch` tier — no catalog-only entries
- Every proposed-edit finding has verbatim before-code + concrete after-code
- No new module exports introduced — pure cleanup, no module-surface changes

## Theme — five groups

This batch is the Phase 1 long-tail #2: residual P3 cleanups (unused imports, polling-perf polish, silent catches, handoff-cleanliness handfuls) plus one auth defense-in-depth that didn't fit into batches 03–06's themes.

- **Group A — Unused imports cleanup (3 findings: 0273, 0280, 0288).** Three import/destructure removals. SalesDashboard drops `useRef`/`useMemo`/`useCallback` from its React import and `isManager` from its usePortalUser destructure (the destructure being the only consumer, the entire `usePortalUser` import line goes too). Directory drops the unused `usePortalUser` import. CR-0288 (ProjectList) is **drift-rejected** at the pre-edit verification step — the finding's premise is false against current state, see the finding entry below.

- **Group B — Small performance (3 findings: 0244, 0277, 0281).** Three perf polish wins. 0244 hoists `TRADE_OPTIONS` out of `CostCodeForm` to module scope so the array isn't reallocated on every form render. 0277 and 0281 add visibility-aware polling to AbsorptionDashboard (30s) and FlowMonitor (5s) so background tabs stop hitting Dataverse — both use the same `document.hidden` early-exit pattern.

- **Group C — Error handling (4 findings: 0225, 0230, 0235, 0271).** Four bare-catch / silent-failure surfaces that get a minimum-viable diagnostic. 0225 leaves the App.jsx session-start `console.error` alone but adds an explanatory comment so the silent-by-design behavior is documented. 0230 adds a one-time `console.warn` to usePortalUser when the Power Pages global is missing (legacy portal / pre-hydration / standalone dev). 0235 adds a one-time `console.warn` breadcrumb to SlideOutPanel's localStorage write catch. 0271 applies the same once-flag pattern from batch 06 CR-0242 (SensorBanner) to Operations.jsx fetchSensorAlerts.

- **Group D — Handoff cleanliness (4 findings: 0276, 0285, 0295, 0302).** Four handoff-readiness polish items. 0276 moves SendQueue's hardcoded `team@decades-cg.com` and `compliance@decades-cg.com` strings into `dcfg_configs` via `getEnvVar()` with the current values as fallbacks. 0285 (ProjectDetail browser-prompt) is proposed as a **narrow fix** — keep the prompt but tighten the wording and add a flag for a Phase 3 SlideOutPanel rewrite (the proper fix is too architecturally invasive for a P3 batch). 0295 documents VendorList's hardcoded Nominatim geocoder URL as intentional (with a config-driven follow-up flag) and adds a User-Agent header per Nominatim's usage policy. 0302 replaces TemplateList's raw picklist ints `100000007`/`100000008` with inline comments referencing the existing `AuditActionType` enum so a future grep finds the rationale.

- **Group E — Auth defense-in-depth (1 finding: 0278).** CapitalPlan adds an in-component `isAdmin()` check + early-return access-denied fallback, mirroring batch 05 CR-0246 (Admin screen) verbatim.

## Pre-deferred / drift-rejected findings (1)

**CR-2026-04-09-0288 — DRIFT REJECT.** The original finding states ProjectList "destructures isManager from usePortalUser but never uses it." Pre-edit verification reads `src/screens/ProjectList.jsx` and finds `isManager` is referenced at line 435 inside the empty-state row of the projects table:

```javascript
            {filtered.length === 0 ? (
              <tr><td colSpan={6} style={{ textAlign: 'center', color: '#94A3B8', padding: '32px' }}>
                No projects found.{isManager() && ' Click "+ New Project" to create one.'}
              </td></tr>
```

The destructure IS consumed. The finding is wrong against current state — drift between the audit pass and current SPA. **Reject reason:** `"drift: isManager() is referenced at ProjectList.jsx line 435 to gate the empty-state '+ New Project' hint. The destructure on line 55 is in active use. The finding's premise is false against current state."` Operator should mark CR-0288 `rejected` during approval.

**Effective findings in this batch:** 14.

## Cross-finding dependencies

- **0277 → 0281.** Same visibility-aware-polling pattern applied to two different files. Independent edits but the operator should land them together so the pattern is consistent.
- **0271 → batch 06 CR-0242.** 0271 reuses the once-flag module-scope pattern landed for SensorBanner in batch 06. This batch's edit follows the exact same shape — module-level `let _opsBannerWarnedOnce = false;` + first-failure `console.warn`.
- **0273 → import removal.** SalesDashboard's `usePortalUser` import is dropped along with the destructure since it has no other consumer in the file. Same pattern as batch 06 CR-0263 (MsaList).
- **0276 → portalApi.getEnvVar.** SendQueue does not currently import `getEnvVar`; the proposed edit adds it to the existing portalApi import block.
- **0278 → batch 05 CR-0246.** Direct mirror of the Admin screen pattern.
- All other findings are independent edits.

---

## Findings in this batch

### CR-2026-04-09-0273 — SalesDashboard imports useRef / useMemo / useCallback / isManager — none are used

**File:** src/screens/SalesDashboard.jsx
**Line(s):** 6, 9, 41
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading `src/screens/SalesDashboard.jsx`. Grep in this file for `useRef`, `useMemo`, `useCallback`, and `isManager` returns ONLY the import line (6) / destructure line (41) — no other consumers. The `usePortalUser` import on line 9 is therefore also dead (its only consumer was the `isManager` destructure being dropped here).

**Current code (lines 6-11, 39-42):**
```javascript
import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiGet, ContractStatus, EntitySets, MsaStatus } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import Fn from '../FieldName.jsx';
```

```javascript
export default function SalesDashboard() {
  const navigate = useNavigate();
  const { isManager } = usePortalUser();
```

**Proposed edit (imports, lines 6-10):**
```javascript
// CR-2026-04-09-0273: trimmed React import to the hooks actually used in this
// file (useState/useEffect only). useCallback/useRef/useMemo were never
// referenced. The usePortalUser import was the only consumer of `isManager`,
// which is also dead code per the destructure removal below — drop the import.
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiGet, ContractStatus, EntitySets, MsaStatus } from '../portalApi.js';
import Fn from '../FieldName.jsx';
```

**Proposed edit (component body, lines 39-41):**
```javascript
export default function SalesDashboard() {
  const navigate = useNavigate();
  // CR-2026-04-09-0273: dropped `const { isManager } = usePortalUser();` —
  // isManager was never referenced in the component body. If a future
  // manager-only KPI lands on this dashboard, restore both the import and
  // the destructure then.
```

**Rationale:** Matches `recommendedFix`. Three coupled drops: (1) the unused React hook imports (`useCallback`, `useRef`, `useMemo`), (2) the entire `usePortalUser` import line (the only consumer was `isManager`), (3) the `isManager` destructure on line 41. The `usePortalUser` removal is a sweep — same shape as the batch 06 CR-0263 sweep on MsaList (which dropped both `FAMILY_MAP` and `usePortalUser` imports for the same reason).

**Risk:** Zero. No behavior change. `isManager()` is not referenced anywhere in the file (verified by grep), so dropping both the import and the destructure is byte-safe.

**Depends on:** none

---

### CR-2026-04-09-0280 — Directory imports usePortalUser but never uses it

**File:** src/screens/Directory.jsx
**Line(s):** 9
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading `src/screens/Directory.jsx` and grepping for `usePortalUser`. The only reference is the import line itself — no `usePortalUser()` call anywhere in the file body.

**Current code (lines 6-11):**
```javascript
import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiGet, EntitySets } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import Fn from '../FieldName.jsx';
```

**Proposed edit:**
```javascript
import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiGet, EntitySets } from '../portalApi.js';
// CR-2026-04-09-0280: dropped unused usePortalUser import — never called
// anywhere in this file. Directory is a public read-only contact rolodex
// with no role-gated UI; if that changes, restore the import then.
import Fn from '../FieldName.jsx';
```

**Rationale:** Matches `recommendedFix`. Drops the dead import. Note that batch 06's CR-0279 housekeeping confirmed Directory.jsx is correct schema-wise (it uses the singular `dcfg_trade`), so this batch only touches the unused import — no other Directory edits.

**Risk:** Zero. No behavior change.

**Depends on:** none

---

### CR-2026-04-09-0288 — DRIFT REJECT — ProjectList isManager IS used

**File:** src/screens/ProjectList.jsx
**Line(s):** 55 (cited), 435 (actual usage site)
**Severity:** P3
**Category:** handoff-cleanliness
**Status:** DRIFT REJECT — see "Pre-deferred / drift-rejected findings" at the top of this doc.

**Current code (line 55, destructure):**
```javascript
  const { isManager } = usePortalUser();
```

**Current code (line 435, ACTUAL USAGE):**
```javascript
            {filtered.length === 0 ? (
              <tr><td colSpan={6} style={{ textAlign: 'center', color: '#94A3B8', padding: '32px' }}>
                No projects found.{isManager() && ' Click "+ New Project" to create one.'}
              </td></tr>
```

**Proposed edit:** NONE. The destructure is consumed by the empty-state row hint. The finding's premise ("never uses it") is false against current state. Drift between the audit pass and the current SPA.

**Rationale:** The audit-pass finding is wrong. `isManager()` IS called at line 435 inside the empty-state hint that tells managers they can click `+ New Project` to create one. This is exactly the JS-06 / C-06 role-suppression pattern documented in `usePortalUser.jsx` lines 9-11 — non-managers don't see the hint at all. Dropping the destructure would break the role suppression.

**Risk:** N/A — no edit. (If executed despite this rejection, the SPA would silently break the manager-hint role gate, exposing the new-project hint to non-managers. Don't do it.)

**Operator action:** Mark CR-2026-04-09-0288 `rejected` during approval with the reject reason quoted at the top of this doc.

**Depends on:** none

---

### CR-2026-04-09-0244 — TRADE_OPTIONS constant declared inside CostCodeForm — recreated on every render

**File:** src/screens/Admin.jsx
**Line(s):** 915-929
**Severity:** P3
**Category:** performance

**Verification:** Confirmed by reading lines 903-929 of `src/screens/Admin.jsx`. The `TRADE_OPTIONS` array is declared inside the `CostCodeForm` function body (function starts at line 903). 13 option objects are reallocated on every render. The file already has module-level constants (`SECTIONS` at line 28, `NAV_ROUTES` adjacent) so the hoist target is established.

**Current code (lines 903-929):**
```javascript
function CostCodeForm({ record, onSave, onClose }) {
  const isNew = !record;
  const [form, setForm] = useState({
    dcfg_dcfg_cost_code: record?.dcfg_dcfg_cost_code || '',
    dcfg_description: record?.dcfg_description || '',
    dcfg_customer_ap_code: record?.dcfg_customer_ap_code || '',
    dcfg_trade_category: record?.dcfg_trade_category ?? '',
    dcfg_active_flag: record?.dcfg_active_flag ?? true,
  });
  const [saving, setSaving] = useState(false);
  const upd = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const TRADE_OPTIONS = [
    { value: '', label: '-- None --' },
    { value: 100000000, label: 'HVAC' },
    { value: 100000001, label: 'Plumbing' },
    { value: 100000002, label: 'Electrical' },
    { value: 100000003, label: 'Roof' },
    { value: 100000004, label: 'Generator' },
    { value: 100000005, label: 'Pool' },
    { value: 100000006, label: 'Kitchen' },
    { value: 100000007, label: 'Elevator' },
    { value: 100000008, label: 'Appliance' },
    { value: 100000009, label: 'Vehicle' },
    { value: 100000010, label: 'Safety' },
    { value: 100000011, label: 'Other' },
  ];
```

**Proposed edit (Step 1 — hoist constant to module scope, immediately after the existing module-level constants near the top of the file, around line 26):**

Insert this block immediately after the existing `const NAVY = '#1B2A4A'; const AMBER = '#D4A017';` declarations (line 25), before the `SECTIONS` array (line 28):

```javascript
// CR-2026-04-09-0244: hoisted from CostCodeForm to module scope so the array
// and its 13 option objects aren't reallocated on every form render. Picklist
// values match the dcfg_ap_cost_code.dcfg_trade_category Choice column.
const TRADE_OPTIONS = [
  { value: '', label: '-- None --' },
  { value: 100000000, label: 'HVAC' },
  { value: 100000001, label: 'Plumbing' },
  { value: 100000002, label: 'Electrical' },
  { value: 100000003, label: 'Roof' },
  { value: 100000004, label: 'Generator' },
  { value: 100000005, label: 'Pool' },
  { value: 100000006, label: 'Kitchen' },
  { value: 100000007, label: 'Elevator' },
  { value: 100000008, label: 'Appliance' },
  { value: 100000009, label: 'Vehicle' },
  { value: 100000010, label: 'Safety' },
  { value: 100000011, label: 'Other' },
];
```

**Proposed edit (Step 2 — drop the in-component declaration, lines 915-929):**

```javascript
function CostCodeForm({ record, onSave, onClose }) {
  const isNew = !record;
  const [form, setForm] = useState({
    dcfg_dcfg_cost_code: record?.dcfg_dcfg_cost_code || '',
    dcfg_description: record?.dcfg_description || '',
    dcfg_customer_ap_code: record?.dcfg_customer_ap_code || '',
    dcfg_trade_category: record?.dcfg_trade_category ?? '',
    dcfg_active_flag: record?.dcfg_active_flag ?? true,
  });
  const [saving, setSaving] = useState(false);
  const upd = (k, v) => setForm(p => ({ ...p, [k]: v }));

  // CR-2026-04-09-0244: TRADE_OPTIONS hoisted to module scope (top of file).
  // The array and its 13 option objects are now allocated once at module
  // load instead of on every render. No closure dependencies — the constant
  // is purely static.
```

**Rationale:** Matches `recommendedFix`. Standard React micro-perf pattern. The array has zero closure dependencies (no references to props, state, or other component-scope variables), so module-scope is the correct home. The hoist eliminates 14 allocations (1 array + 13 option objects) per CostCodeForm render — not a hot path, but the pattern is what matters for code review consistency with the rest of the file's existing module-level constants.

**Risk:** Zero. Identity stability changes from "fresh per render" to "stable across all renders" — the only observable effect is that React's `<select><option>` map no longer needs to reconcile the array contents on each render (every option's `value` is identity-stable instead of merely equal). For a 14-element list this is invisible.

**Depends on:** none

---

### CR-2026-04-09-0277 — AbsorptionDashboard 30s polling interval runs regardless of tab visibility

**File:** src/screens/AbsorptionDashboard.jsx
**Line(s):** 61-65
**Severity:** P3
**Category:** performance

**Verification:** Confirmed by reading lines 1-65 of `src/screens/AbsorptionDashboard.jsx`. `REFRESH_MS = 30000` at line 37. The mount-effect at lines 61-65 calls `load()` once and registers `setInterval(load, REFRESH_MS)` with no visibility check. Browser background-tab throttling slows but does not stop the interval. Pre-edit verification: no existing `visibilityState` / `visibilitychange` / `document.hidden` references anywhere in `src/` (grep returned zero matches), so this batch establishes the pattern that 0281 (FlowMonitor) reuses.

**Current code:**
```javascript
  useEffect(() => {
    load();
    const iv = setInterval(load, REFRESH_MS);
    return () => clearInterval(iv);
  }, []);
```

**Proposed edit:**
```javascript
  // CR-2026-04-09-0277: pause the 30s poll while the tab is hidden so a
  // dashboard left open in a background tab does not keep hitting Dataverse.
  // Pattern: the interval still ticks (so we don't have to manage subscription
  // lifecycle on visibilitychange events), but each tick checks document.hidden
  // and short-circuits if the tab is not visible. When the tab becomes visible
  // again the next tick fires within 30s; the listener forces a fresh load
  // immediately on visibility change so the user doesn't wait up to 30s for
  // stale data to refresh.
  useEffect(() => {
    load();
    const tick = () => { if (!document.hidden) load(); };
    const iv = setInterval(tick, REFRESH_MS);
    const onVisible = () => { if (!document.hidden) load(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(iv);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, []);
```

**Rationale:** Matches `recommendedFix`. Two coupled changes: (1) the interval body is wrapped in a `document.hidden` short-circuit so background-tab ticks don't fire `load()` against Dataverse, (2) a `visibilitychange` listener forces an immediate refresh when the user returns to the tab — without it the user could see up to 30s of stale data before the next interval tick. The cleanup also removes the listener so navigating away from the route doesn't leak handlers.

**Risk:** Low. Three failure modes considered:
(a) `document.hidden` is well-supported across all evergreen browsers and Power Pages chrome — no polyfill needed.
(b) The `visibilitychange` listener is module-internal to the effect and is removed on cleanup. No leak.
(c) If the user has `prefers-reduced-data` set, this is strictly an improvement — fewer Dataverse hits, not more.

**Depends on:** none (sibling pattern to CR-0281 — same shape, different file)

---

### CR-2026-04-09-0281 — FlowMonitor polls every 5 seconds with no pause-on-hidden check

**File:** src/screens/FlowMonitor.jsx
**Line(s):** 71-77
**Severity:** P3
**Category:** performance

**Verification:** Confirmed by reading lines 1-90 of `src/screens/FlowMonitor.jsx`. `POLL_INTERVAL = 5000` at line 7. The auto-refresh effect at lines 71-77 toggles `setInterval(fetchRequests, POLL_INTERVAL)` based on the `autoRefresh` state. The current code already has a `timerRef` cleanup pattern, so this fix layers visibility-awareness on top without restructuring the timer ownership.

**Current code:**
```javascript
  useEffect(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (autoRefresh) {
      timerRef.current = setInterval(fetchRequests, POLL_INTERVAL);
    }
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [autoRefresh]);
```

**Proposed edit:**
```javascript
  // CR-2026-04-09-0281: gate the 5s poll on document visibility so a
  // FlowMonitor tab left open in the background does not generate 720
  // unnecessary Dataverse hits per hour. Same pattern as
  // CR-2026-04-09-0277 (AbsorptionDashboard) — interval still ticks but
  // each tick short-circuits when document.hidden, plus a visibilitychange
  // listener forces an immediate fetch on tab return so the user does not
  // see up to 5s of stale state.
  useEffect(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (autoRefresh) {
      const tick = () => { if (!document.hidden) fetchRequests(); };
      timerRef.current = setInterval(tick, POLL_INTERVAL);
    }
    const onVisible = () => { if (autoRefresh && !document.hidden) fetchRequests(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [autoRefresh]);
```

**Rationale:** Matches `recommendedFix`. Same pattern as 0277, applied to the conditional `autoRefresh` toggle. Two refinements specific to FlowMonitor: (1) the visibilitychange handler also reads `autoRefresh` from closure so it does not fire when the user has paused refreshing, (2) the existing `timerRef`-based cleanup is preserved verbatim — only the listener registration/cleanup is added.

**Risk:** Low. Same failure-mode considerations as 0277. One FlowMonitor-specific note: the existing `useEffect` deps array `[autoRefresh]` means the listener is re-registered every time the user toggles auto-refresh — not a performance issue (it's a cheap addEventListener) and the cleanup correctly removes the previous listener before re-registering.

**Depends on:** none (sibling pattern to CR-0277)

---

### CR-2026-04-09-0225 — writeAuditLog session-start .catch(err => console.error(...)) only — no toast

**File:** src/App.jsx
**Line(s):** 233-244
**Severity:** P3
**Category:** error-handling

**Verification:** Confirmed by reading lines 220-244 of `src/App.jsx`. The session-start audit log effect runs once when `user.isAuthenticated && !sessionLogged`. The `.catch(err => console.error(...))` at line 242 silently swallows failures without surfacing to the user.

**Current code:**
```javascript
  // Log session start once when user is authenticated
  React.useEffect(() => {
    if (user?.isAuthenticated && !sessionLogged) {
      setSessionLogged(true);
      writeAuditLog({
        targetTable: 'session',
        targetRecordId: 'app-start',
        actionType: AuditActionType.Other,
        performedBy: user.email || user.name || 'unknown',
        newValue: `Session started | User: ${user.name} | Email: ${user.email} | Roles: ${(user.roles||[]).map(r=>r.name||r).join(', ')} | URL: ${window.location.href} | React: ${React.version}`,
      }).catch(err => console.error('Session audit log failed:', err));
    }
  }, [user, sessionLogged]);
```

**Proposed edit:**
```javascript
  // Log session start once when user is authenticated
  React.useEffect(() => {
    if (user?.isAuthenticated && !sessionLogged) {
      setSessionLogged(true);
      writeAuditLog({
        targetTable: 'session',
        targetRecordId: 'app-start',
        actionType: AuditActionType.Other,
        performedBy: user.email || user.name || 'unknown',
        newValue: `Session started | User: ${user.name} | Email: ${user.email} | Roles: ${(user.roles||[]).map(r=>r.name||r).join(', ')} | URL: ${window.location.href} | React: ${React.version}`,
      }).catch(err => {
        // CR-2026-04-09-0225: session-start audit failure is intentionally
        // silent at the user level — toasting "audit log failed" on every
        // app boot would be alarming noise for an event the user neither
        // initiated nor cares about. The console.error is the only signal,
        // and it's enough: Phase 5 telemetry plan calls for emitting a Nora
        // breadcrumb here so a broken audit-log path shows up on the Nora
        // panel without spamming the user. For now, the silent failure is
        // documented and the error stays in the dev console.
        console.error('Session audit log failed:', err);
      });
    }
  }, [user, sessionLogged]);
```

**Rationale:** Matches the cautious version of `recommendedFix` ("Document the behavior in App.jsx with a comment so future maintainers know the silent failure is intentional"). The finding's `recommendedFix` explicitly says "No code change recommended" — but the operator's directive for this batch ("Add toast + breadcrumb") is in tension with that. This proposal **does not** add a toast (the finding's own rationale is correct: toasting on session start would be alarming noise), but it DOES add the explanatory comment so the silent-by-design behavior is documented for future maintainers.

**Operator note:** The original directive ("Add toast + breadcrumb") was followed with intentional restraint — the finding's own `recommendedFix` field says "No code change recommended" because session-start telemetry should NOT toast the user. Adding a toast here would be a regression in UX (boot-time alarming dialog) for a P3 polish item. The proposed edit upgrades the breadcrumb (adds the inline comment explaining the silent-by-design behavior) but does NOT add the toast. If the operator disagrees and wants the toast anyway, the simplest add is `toast?.show('warn', 'Audit log unavailable')` inside the catch — but flag this as a deliberate UX call before applying.

**Risk:** Zero. The runtime behavior is byte-identical (`console.error` still fires, no new code paths). The only change is the explanatory comment.

**Depends on:** none

---

### CR-2026-04-09-0230 — usePortalUser effect reads window.Microsoft.Dynamic365.Portal.User without error handling

**File:** src/usePortalUser.jsx
**Line(s):** 29-65
**Severity:** P3
**Category:** error-handling

**Verification:** Confirmed by reading lines 25-65 of `src/usePortalUser.jsx`. Line 32 uses optional chaining (`window.Microsoft?.Dynamic365?.Portal?.User ?? null`) so the read itself cannot throw — the existing code already handles the "global is undefined" case by setting `raw = null` and falling through to the unauthenticated user shape (lines 37-46). The finding's "crashes if global is undefined" framing is already false against current state. The actual P3 polish here is "log a console.warn so the developer knows WHY they're in the unauthenticated branch."

**Current code (lines 29-46):**
```javascript
  useEffect(() => {
    // Power Pages populates this object synchronously before React hydrates,
    // but we read it in an effect to be safe with SSR/hydration edge cases.
    const raw = window.Microsoft?.Dynamic365?.Portal?.User ?? null;

    // JS-02: infer auth from properties, NOT from isAuthenticated (doesn't exist)
    const isAuthenticated = !!(raw?.contactId || raw?.userName || raw?.email);

    if (!isAuthenticated || !raw) {
      setUser({
        isAuthenticated: false,
        name:       null,
        email:      null,
        contactId:  null,
        firstName:  null,
        lastName:   null,
        roles:      [],
      });
    } else {
```

**Proposed edit:**
```javascript
  useEffect(() => {
    // Power Pages populates this object synchronously before React hydrates,
    // but we read it in an effect to be safe with SSR/hydration edge cases.
    const raw = window.Microsoft?.Dynamic365?.Portal?.User ?? null;

    // JS-02: infer auth from properties, NOT from isAuthenticated (doesn't exist)
    const isAuthenticated = !!(raw?.contactId || raw?.userName || raw?.email);

    if (!isAuthenticated || !raw) {
      // CR-2026-04-09-0230: emit a one-time warn when the Power Pages global
      // is missing entirely (raw === null). This catches three real failure
      // modes: (1) the SPA is loaded outside Power Pages chrome (e.g., the
      // SPA standalone dev server), (2) the legacy decades.powerappsportals.com
      // site that does not inject the global in time, (3) a script-load order
      // regression where React hydrates before the Power Pages user script.
      // Distinct from the "raw is non-null but missing email/contactId/userName"
      // case, which is normal for an anonymous visitor — no warn for that.
      if (!raw && typeof window !== 'undefined') {
        console.warn('[usePortalUser] window.Microsoft.Dynamic365.Portal.User is null — Power Pages user script may not be loaded (standalone dev or pre-hydration)');
      }
      setUser({
        isAuthenticated: false,
        name:       null,
        email:      null,
        contactId:  null,
        firstName:  null,
        lastName:   null,
        roles:      [],
      });
    } else {
```

**Rationale:** Matches `recommendedFix` exactly. The warn fires only when `raw === null` (the global is missing entirely), not when `raw` is present but the user is anonymous — this avoids spamming the dev console for legitimate unauthenticated visitors. The `typeof window !== 'undefined'` guard is defensive against SSR contexts (Power Pages doesn't SSR, but the guard is cheap insurance).

**Risk:** Zero. The user-state assignment is unchanged. The only new code path is the conditional `console.warn` which fires once per mount of `PortalUserProvider` (which mounts once per app boot — so at most one warn per session).

**Depends on:** none (the useMemo wrap landed in batch 06 CR-0228 stabilizes the value object identity but does not affect the effect body)

---

### CR-2026-04-09-0235 — SlideOutPanel localStorage.setItem wrapped in try/catch with empty handler

**File:** src/SlideOutPanel.jsx
**Line(s):** 60 (write site, not the line 53 cited by the finding — see drift note)
**Severity:** P3
**Category:** error-handling

**Drift note:** Finding cites line 53. Verified current state — the `localStorage.setItem` write site is at line 60 inside the `onMouseUp` handler of the drag effect. Line 53 is now `if (dragging.current) {` — different code, same handler scope. The line drift is presumably due to the CR-2026-04-09-0234 widthRef refactor that landed earlier. The fix targets the actual write site at line 60.

**Current code (lines 52-62):**
```javascript
    function onMouseUp() {
      if (dragging.current) {
        dragging.current = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
        // CR-2026-04-09-0234: read final width from ref so this effect no longer
        // depends on the `width` state (which would otherwise tear down and
        // rebind the event listeners on every drag tick).
        try { localStorage.setItem('dcfg_panel_width_' + testId, String(widthRef.current)); } catch(e) {}
      }
    }
```

**Current code (lines 22-26 — the READ site for context, also has empty catch):**
```javascript
  var _w = useState(function() {
    try { var saved = localStorage.getItem('dcfg_panel_width_' + testId); return saved ? parseInt(saved) : DEFAULT_WIDTH; } catch(e) { return DEFAULT_WIDTH; }
  });
```

**Proposed edit (write site, lines 52-62):**
```javascript
    function onMouseUp() {
      if (dragging.current) {
        dragging.current = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
        // CR-2026-04-09-0234: read final width from ref so this effect no longer
        // depends on the `width` state (which would otherwise tear down and
        // rebind the event listeners on every drag tick).
        // CR-2026-04-09-0235: log the FIRST localStorage failure to the dev
        // console so Safari private mode / quota-exceeded / disabled-storage
        // failures are diagnosable. Subsequent failures stay silent — the
        // resize handle would otherwise spam the console on every drag.
        try {
          localStorage.setItem('dcfg_panel_width_' + testId, String(widthRef.current));
        } catch (e) {
          if (!_dcfgLocalStorageWarned) {
            _dcfgLocalStorageWarned = true;
            console.warn('[DCFG] localStorage unavailable — UI preferences (panel width, etc.) will not persist:', e);
          }
        }
      }
    }
```

**Proposed edit (module-level flag, immediately after the imports near the top of the file, around line 7):**

Insert this declaration immediately after the existing module-level constants (`var NAVY = '#1B2A4A'; var MIN_WIDTH = 320; var MAX_WIDTH = 800; var DEFAULT_WIDTH = 420;`) on lines 8-11:

```javascript
// CR-2026-04-09-0235: module-level guard so localStorage failures only log
// the first time per session. Same once-flag pattern as
// CR-2026-04-09-0242 (SensorBanner) and CR-2026-04-09-0271 (Operations).
// Module scope (not component) so the flag persists across panel mounts.
var _dcfgLocalStorageWarned = false;
```

**Operator note:** I deliberately did NOT also patch the line-22 READ site catch in this edit. The read site is functionally tolerant (it falls back to `DEFAULT_WIDTH`) and triggering `_dcfgLocalStorageWarned` on the read would change which failure mode the user sees first. Keeping the read silent and warning only on the write means the warning fires when the user actually takes an action (drag-resize) that won't persist — clearer signal than "your saved width didn't load." If the operator wants the read site warned too, the symmetric edit is one line — flag it as a follow-up.

**Operator note (2):** This file uses `var` and `function() { ... }` syntax (legacy ES5 style) for compatibility with the Power Pages script chrome. The proposed edits stay in that style — `var _dcfgLocalStorageWarned`, not `let`.

**Rationale:** Matches `recommendedFix`. The once-flag pattern is the only safe approach for an event that fires per drag-tick (the user could trigger this dozens of times in a single resize). Module-scope (not component-scope) is intentional — a `useRef` would reset on every panel unmount/remount, which happens on most route changes and would defeat the once-per-session intent. Same pattern landed in batch 06 for SensorBanner (CR-0242).

**Risk:** Zero. The catch behavior is functionally identical (still silent at the user level, drag still completes successfully). Only the first-failure diagnostic surface changes.

**Depends on:** none (sibling pattern to batch 06 CR-0242 and this batch's CR-0271)

---

### CR-2026-04-09-0271 — Operations.fetchSensorAlerts outer catch silently swallows errors on every 30s poll

**File:** src/screens/Operations.jsx
**Line(s):** 172-176
**Severity:** P3
**Category:** error-handling

**Verification:** Confirmed by reading lines 140-180 of `src/screens/Operations.jsx`. The outer `try` of `fetchSensorAlerts` wraps the sensor-readings fetch + the unresolved-locations resolution. The bare `catch { }` at lines 172-174 has a comment "Sensor table may not be available — fail silently" but no diagnostic output. `SENSOR_POLL_MS = 30000` per line 18, so this fires every 30 seconds for the duration of the Operations route mount.

**Current code:**
```javascript
    } catch {
      // Sensor table may not be available — fail silently
    } finally {
      setSensorLoading(false);
    }
  }, []);
```

**Proposed edit:**
```javascript
    } catch (e) {
      // CR-2026-04-09-0271: sensor readings table may not exist yet — fail
      // silently for the user, but log the FIRST failure so a post-deploy
      // regression to dcfg_sensor_readings access is diagnosable. Subsequent
      // failures stay silent so the 30s poll does not spam the dev console.
      // Same once-flag pattern as CR-2026-04-09-0242 (SensorBanner) landed
      // in batch 06.
      if (!_opsBannerWarnedOnce) {
        _opsBannerWarnedOnce = true;
        console.warn('[Operations] fetchSensorAlerts failed (subsequent failures suppressed):', e);
      }
    } finally {
      setSensorLoading(false);
    }
  }, []);
```

**Proposed edit (module-level flag, immediately after the existing module-level constants near the top of the file, around line 19):**

Insert this declaration immediately after the existing `const NAVY = ...; const PAGE_SIZE = 25; const SENSOR_POLL_MS = 30000; const WORKORDER_POLL_MS = 120000;` declarations (lines 16-19), before the `ALERT_LABELS` block:

```javascript
// CR-2026-04-09-0271: module-level guard so fetchSensorAlerts only logs
// the first failure per session. Same once-flag pattern as the
// CR-2026-04-09-0242 SensorBanner fix landed in batch 06. Module scope
// (not component) so the flag persists across Operations route mounts.
let _opsBannerWarnedOnce = false;
```

**Rationale:** Matches `recommendedFix` ("Same fix as CR-0242 — add a module-level flag to log the warning once, then stay silent on subsequent polls"). Same shape as the SensorBanner fix landed in batch 06. The flag is named `_opsBannerWarnedOnce` (not `_sensorBannerWarnedOnce`) so the two flags don't shadow each other if both fire in the same session — distinct file, distinct flag.

**Risk:** Zero. The catch behavior is functionally identical (still silent at the user level, still loops on failure). Only the first-failure diagnostic surface changes. The inner-loop bare catches at lines 165 and 195 (best-effort location resolution) are intentionally NOT touched by this edit — those have a defensible "best-effort, continue on failure" semantic that should not be turned into warnings.

**Depends on:** none (sibling pattern to batch 06 CR-0242)

---

### CR-2026-04-09-0276 — Hardcoded email addresses team@decades-cg.com / compliance@decades-cg.com in SendQueue templates

**File:** src/screens/SendQueue.jsx
**Line(s):** 322, 334
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading lines 320-345 of `src/screens/SendQueue.jsx`. Line 322 sets `to: 'team@decades-cg.com'` in `handleRequestInfo`. Line 334 embeds `compliance@decades-cg.com` as a literal in the insurance template body inside `handleAlertEmail`. SendQueue does NOT currently import `getEnvVar` from portalApi (verified by grep — zero matches in the file). The proposed edit adds `getEnvVar` to the existing portalApi import block.

**Current code (lines 320-329, handleRequestInfo):**
```javascript
  function handleRequestInfo(c) {
    setEmailModal({
      to: 'team@decades-cg.com',
      subject: `Request More Information — ${c.dcfg_contract_number || 'Contract'}`,
      type: 'info',
      alertId: null,
      contractId: c.dcfg_contractid,
    });
    setEmailBody(`Hi team,\n\nI need more information about this document before I can approve it.\n\nPlease clarify:\n- \n\nThanks,\n${user?.fullname || 'Joseph'}`);
  }
```

**Current code (line 334, insurance template body inside handleAlertEmail):**
```javascript
      insurance: `Dear [Vendor Contact],\n\nYour insurance certificate on file is approaching expiration.\n\nPlease provide an updated certificate to compliance@decades-cg.com.\n\nRequired:\n- General Liability\n- Workers Compensation\n- Auto Liability\n\nThank you,\nDecades CFG`,
```

**Current code (existing import block, lines 10-18):**
```javascript
import {
  apiGet, apiPatch, writeAuditLog,
  AuditActionType, ContractStatus, ContractFamily,
  ContractStatusLabel, ContractTypeLabel, ContractType,
  OnboardingCaseStatus, OnboardingPhaseLabel,
  MsaStatus, EntitySets,
  createDocumentRequest, DocRequestType,
  fetchBlanketWorkorders,
} from '../portalApi.js';
```

**Proposed edit (import block):**
```javascript
import {
  apiGet, apiPatch, writeAuditLog,
  AuditActionType, ContractStatus, ContractFamily,
  ContractStatusLabel, ContractTypeLabel, ContractType,
  OnboardingCaseStatus, OnboardingPhaseLabel,
  MsaStatus, EntitySets,
  createDocumentRequest, DocRequestType,
  fetchBlanketWorkorders,
  // CR-2026-04-09-0276: pull email recipients from dcfg_configs at runtime
  // so the operator can change them without a SPA redeploy.
  getEnvVar,
} from '../portalApi.js';
```

**Proposed edit (handleRequestInfo, lines 320-329):**
```javascript
  function handleRequestInfo(c) {
    // CR-2026-04-09-0276: pull the ops-team recipient from dcfg_configs with
    // the current hardcoded value as a fallback so existing behavior is
    // preserved if the config row is not yet provisioned. Add the
    // dcfg_team_email row to dcfg_configs in each environment to override.
    setEmailModal({
      to: getEnvVar('dcfg_team_email') || 'team@decades-cg.com',
      subject: `Request More Information — ${c.dcfg_contract_number || 'Contract'}`,
      type: 'info',
      alertId: null,
      contractId: c.dcfg_contractid,
    });
    setEmailBody(`Hi team,\n\nI need more information about this document before I can approve it.\n\nPlease clarify:\n- \n\nThanks,\n${user?.fullname || 'Joseph'}`);
  }
```

**Proposed edit (handleAlertEmail templates, line 334):**
```javascript
  function handleAlertEmail(alertItem, type) {
    // CR-2026-04-09-0276: pull the compliance recipient from dcfg_configs
    // with the current hardcoded value as a fallback so existing behavior
    // is preserved if the config row is not yet provisioned. Add the
    // dcfg_compliance_email row to dcfg_configs in each environment to override.
    const complianceEmail = getEnvVar('dcfg_compliance_email') || 'compliance@decades-cg.com';
    const templates = {
      msa: `Dear [Client Contact],\n\nYour Management Services Agreement is approaching expiration.\n\nWe would like to discuss renewal terms.\n\nBest regards,\nDecades Construction & Facilities Group`,
      insurance: `Dear [Vendor Contact],\n\nYour insurance certificate on file is approaching expiration.\n\nPlease provide an updated certificate to ${complianceEmail}.\n\nRequired:\n- General Liability\n- Workers Compensation\n- Auto Liability\n\nThank you,\nDecades CFG`,
    };
```

**Operator-attention items:**

1. **dcfg_configs rows.** This edit relies on two new config rows (`dcfg_team_email` and `dcfg_compliance_email`) being provisioned in each environment (Test / Stage / Prod). The fallback strings preserve current behavior if the rows are missing, so the SPA does not break — but the operator should provision the rows post-deploy so the override path is actually exercised. Use the existing dcfg_configs add pattern from the SendQueue / DocGen URL config rows.

2. **getEnvVar return shape.** Verified by reading `portalApi.js` line 390 (`export function getEnvVar(schemaName)`). The function reads from the same `_configCache` that `loadConfig` populates at boot — so by the time `handleRequestInfo` / `handleAlertEmail` fire (user click), the cache is hydrated and `getEnvVar` returns the row's value or `null`. The `|| 'team@decades-cg.com'` fallback handles the null case.

**Rationale:** Matches `recommendedFix`. Two coupled changes: (1) the ops-team `to:` recipient is now config-driven, (2) the compliance email embedded in the insurance template body is also config-driven. Both have current-value fallbacks so existing behavior is preserved if the dcfg_configs rows are not yet provisioned. This unblocks operator-only email-recipient changes (e.g., post-merger rebrand, sales rep handoff) without a SPA redeploy.

**Risk:** Low. Two failure modes considered:
(a) `getEnvVar` returns `null` if the config row is missing → fallback to the current hardcoded string. No regression.
(b) The operator provisions the dcfg_configs row with an invalid email format → the SPA still pre-fills the email modal with the bad value, and the user is the next gate (they see the recipient before clicking Send). Same risk profile as today.

**Depends on:** none

---

### CR-2026-04-09-0285 — ProjectDetail Save as Template uses browser prompt() — bad UX for external testing

**File:** src/screens/ProjectDetail.jsx
**Line(s):** 237-261
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading lines 230-265 of `src/screens/ProjectDetail.jsx`. `handleSaveAsTemplate` at line 237 calls `prompt('Template name:', ...)` synchronously. The prompt is the only template-name capture surface — there is no inline modal or SlideOutPanel infrastructure already wired into this file.

**Current code:**
```javascript
  // Save as Template
  const [savingTemplate, setSavingTemplate] = useState(false);
  async function handleSaveAsTemplate() {
    if (!project) return;
    const tplName = prompt('Template name:', `${project.dcfg_name} Template`);
    if (!tplName) return;
    setSavingTemplate(true);
    try {
      // Create projecttemplate record with line items as JSON
      const lineData = lines.map(l => ({
        description: l.dcfg_description, trade: l.dcfg_trade, line_type: l.dcfg_line_type,
        uom: l.dcfg_uom, quantity: l.dcfg_quantity, unit_rate: l.dcfg_unit_rate, sequence: l.dcfg_sequence,
      }));
      await apiPostReturnId(`/${EntitySets.projectTemplates}`, {
        dcfg_name: tplName,
        dcfg_trades: project.dcfg_trades || null,
        dcfg_cost_code: project.dcfg_cost_code || null,
        dcfg_description: JSON.stringify(lineData),
        dcfg_isactive: true,
      });
      toast.show('ok', `Template "${tplName}" created with ${lines.length} line items`);
    } catch (e) {
      toast.show('err', e.message || 'Failed to save template');
    } finally {
      setSavingTemplate(false);
    }
  }
```

**Proposed edit (NARROW FIX — keep prompt, tighten wording, flag for Phase 3 redesign):**
```javascript
  // Save as Template
  const [savingTemplate, setSavingTemplate] = useState(false);
  async function handleSaveAsTemplate() {
    if (!project) return;
    // CR-2026-04-09-0285: NARROW FIX. Replacing the browser prompt() with a
    // SlideOutPanel form is the proper fix per the finding's recommendedFix,
    // but doing so requires plumbing slide-out state through this file (which
    // currently has no slide-out infrastructure) plus the state machine for
    // the form's open/close/submit lifecycle. That is too architecturally
    // invasive for a P3 cleanup batch. The narrow fix here:
    //   1. Keep the browser prompt() (only template-name capture surface today).
    //   2. Tighten the prompt label so external testers see a clearer ask.
    //   3. Trim whitespace + reject empty-after-trim names so the audit trail
    //      and template list don't carry junk values.
    //   4. Flagged for Phase 3 redesign — see operator note below.
    const defaultName = `${project.dcfg_name || 'Project'} Template`;
    const raw = window.prompt('Save as project template — enter a template name:', defaultName);
    if (raw === null) return; // user cancelled
    const tplName = raw.trim();
    if (!tplName) {
      toast.show('warn', 'Template name cannot be empty');
      return;
    }
    setSavingTemplate(true);
    try {
      // Create projecttemplate record with line items as JSON
      const lineData = lines.map(l => ({
        description: l.dcfg_description, trade: l.dcfg_trade, line_type: l.dcfg_line_type,
        uom: l.dcfg_uom, quantity: l.dcfg_quantity, unit_rate: l.dcfg_unit_rate, sequence: l.dcfg_sequence,
      }));
      await apiPostReturnId(`/${EntitySets.projectTemplates}`, {
        dcfg_name: tplName,
        dcfg_trades: project.dcfg_trades || null,
        dcfg_cost_code: project.dcfg_cost_code || null,
        dcfg_description: JSON.stringify(lineData),
        dcfg_isactive: true,
      });
      toast.show('ok', `Template "${tplName}" created with ${lines.length} line items`);
    } catch (e) {
      toast.show('err', e.message || 'Failed to save template');
    } finally {
      setSavingTemplate(false);
    }
  }
```

**Operator-attention item — Phase 3 follow-up:**

The proper fix per the finding's `recommendedFix` is "Replace with an inline modal or SlideOutPanel for template-name entry. Match the SlideOutPanel usage pattern from NewRfpWizard or Admin.jsx forms." Doing this in ProjectDetail requires:

1. Adding `import SlideOutPanel from '../SlideOutPanel.jsx';` (file currently does not import it).
2. Adding `const [showTemplateModal, setShowTemplateModal] = useState(false);` and `const [tplNameInput, setTplNameInput] = useState('');` state.
3. Splitting `handleSaveAsTemplate` into two functions: `openTemplateModal()` (sets default name + opens panel) and `handleSaveTemplateConfirm()` (the actual POST).
4. Rendering the SlideOutPanel with a single `<input>` + Save/Cancel buttons inside the existing render tree.

Estimated effort: ~30 lines of new code + careful state-machine work to handle the cancel-from-X-button case. Out of scope for this P3 batch — flag as a Phase 3 design pass item ("ProjectDetail Save-as-Template SlideOutPanel rewrite") and re-batch when the operator is ready.

**Rationale:** Matches the operator directive's guidance ("if too architecturally invasive, propose a smaller fix"). The narrow fix improves three concrete things without touching the file's architecture: (1) clearer prompt wording for external testers, (2) whitespace-trimming so the audit trail doesn't show "  Project Template  ", (3) explicit empty-string rejection with a toast warning instead of the previous silent return. The browser prompt is still the surface — but the surface is now defensive enough to ship to external testers without obvious foot-guns.

**Risk:** Low. Three failure modes:
(a) The user cancels the prompt → `raw === null` → early return, no toast (matches previous behavior).
(b) The user enters whitespace only → `tplName === ''` → warn toast + early return (NEW: previously the empty-string would silently early-return without explanation).
(c) The user enters a valid name → trim is applied before the POST → Dataverse stores the trimmed value.

**Depends on:** none

---

### CR-2026-04-09-0295 — VendorList geocodes via hardcoded nominatim.openstreetmap.org URL

**File:** src/screens/VendorList.jsx
**Line(s):** 79-102
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading lines 75-102 of `src/screens/VendorList.jsx`. The `doDistanceSearch` function fetches the Nominatim public endpoint with no User-Agent header. Per Nominatim's usage policy (https://operations.osmfoundation.org/policies/nominatim/) the public instance is rate-limited to 1 req/sec and REQUIRES a custom User-Agent identifying the application — the SPA's anonymous fetch could get the Decades portal IP banned during heavy use (e.g., a sales rep doing 20 vendor radius searches in a row).

**Current code:**
```javascript
  var doDistanceSearch = useCallback(function () {
    if (!distAddress) return;
    setGeocoding(true);
    setGeoError('');
    fetch('https://nominatim.openstreetmap.org/search?format=json&q=' + encodeURIComponent(distAddress))
      .then(function (r) { return r.json(); })
      .then(function (data) {
        setGeocoding(false);
        if (!data || data.length === 0) {
          setGeoError('Address not found. Try a different address.');
          setDistActive(false);
          setSearchCoords(null);
          return;
        }
        setSearchCoords({ lat: parseFloat(data[0].lat), lon: parseFloat(data[0].lon) });
        setDistActive(true);
      })
      .catch(function () {
        setGeocoding(false);
        setGeoError('Geocoding failed. Check your connection.');
        setDistActive(false);
        setSearchCoords(null);
      });
  }, [distAddress]);
```

**Proposed edit:**
```javascript
  var doDistanceSearch = useCallback(function () {
    if (!distAddress) return;
    setGeocoding(true);
    setGeoError('');
    // CR-2026-04-09-0295: geocoder URL is intentionally the public Nominatim
    // service for now (no DCFG-hosted geocoder exists). Two compliance items
    // per Nominatim's usage policy (operations.osmfoundation.org/policies/nominatim):
    //   1. Add a User-Agent header identifying the DCFG portal so OSM can
    //      contact us if our usage pattern looks abusive. Without this the
    //      portal IP can be banned silently during heavy use.
    //   2. Rate-limit to 1 req/sec — currently enforced by the fact that the
    //      user has to type+click for each search, but worth noting if a
    //      future bulk-geocode feature lands.
    // Operator-attention: a dcfg_configs row (dcfg_geocoder_url) and a
    // localStorage geocode cache are flagged as Phase 3 follow-ups; for now
    // the URL stays inline with this comment as a deliberate decision.
    fetch('https://nominatim.openstreetmap.org/search?format=json&q=' + encodeURIComponent(distAddress), {
      headers: { 'User-Agent': 'DCFG-Portal/1.0 (decades-cg.com)' },
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        setGeocoding(false);
        if (!data || data.length === 0) {
          setGeoError('Address not found. Try a different address.');
          setDistActive(false);
          setSearchCoords(null);
          return;
        }
        setSearchCoords({ lat: parseFloat(data[0].lat), lon: parseFloat(data[0].lon) });
        setDistActive(true);
      })
      .catch(function () {
        setGeocoding(false);
        setGeoError('Geocoding failed. Check your connection.');
        setDistActive(false);
        setSearchCoords(null);
      });
  }, [distAddress]);
```

**Operator-attention items:**

1. **User-Agent header in browser fetch.** Modern browsers do NOT allow JavaScript to override the `User-Agent` request header — the browser strips custom `User-Agent` headers from `fetch()` calls for security reasons (prevents CSRF / cache-poisoning shenanigans). The proposed `headers: { 'User-Agent': ... }` will be silently ignored by the browser and the request will go out with the browser's default UA. **The polite thing to do is still set it** (some frameworks honor it via Service Worker; some Power Pages chrome may pass it through), and it documents intent for code reviewers and any future server-side geocoder migration. But operator should NOT expect to see the custom UA in network traffic.
2. **dcfg_configs migration deferred.** The finding's `recommendedFix` says "Move the geocoder URL to dcfg_configs (`dcfg_geocoder_url`)." This batch does NOT do that — moving the URL to config requires (a) provisioning the config row in three environments, (b) handling the loading-state race when `getEnvVar` returns null on first paint, (c) deciding the fallback URL. Flagged for Phase 3.
3. **localStorage geocode cache deferred.** The finding's secondary suggestion ("Consider caching geocoded addresses in localStorage to avoid re-geocoding the same search") is a 1-day feature, not a 1-hour cleanup. Flagged for Phase 3.

**Rationale:** Matches the "document as intentional public service" branch of the operator directive. The fetch is documented as a deliberate decision (no DCFG-hosted geocoder exists), the User-Agent header is added (best-effort, browser may strip it), and two follow-ups are flagged for Phase 3. This unblocks the handoff-readiness review without forcing a same-day config-migration sprint.

**Risk:** Zero functional change. The User-Agent header will likely be silently dropped by the browser (see operator note 1), so the fetch behavior is byte-identical to current. The only observable difference is the inline comment block.

**Depends on:** none

---

### CR-2026-04-09-0302 — TemplateList doToggle uses raw picklist ints 100000007 / 100000008

**File:** src/screens/templates/TemplateList.jsx
**Line(s):** 142-160
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading lines 130-160 of `src/screens/templates/TemplateList.jsx`. Line 150 passes `actionType: newActive ? 100000007 : 100000008` with the trailing comment `// Template Activated / Deactivated`. The finding correctly notes that 100000007 corresponds to `AuditActionType.Created` and 100000008 to `AuditActionType.Deleted` per `portalApi.js` line 96, but the labels in this file's trailing comment are "Template Activated / Deactivated" — a label/value mismatch. The finding offers two paths: (a) add named constants to the enums file, or (b) add inline comments documenting what the ints mean. Path (a) requires touching the enum file + audit log picklist values in Dataverse — out of scope. Path (b) is the right narrow fix here.

**Current code:**
```javascript
  var doToggle = useCallback(async function(tpl, newActive) {
    try {
      await apiPatch('/' + EntitySets.docTemplates + '(' + tpl.dcfg_document_templateid + ')', {
        dcfg_is_active: newActive,
      });
      await writeAuditLog({
        targetTable: 'dcfg_document_template',
        targetRecordId: tpl.dcfg_document_templateid,
        actionType: newActive ? 100000007 : 100000008, // Template Activated / Deactivated
        performedBy: user?.email || 'admin',
        newValue: "Template '" + tpl.dcfg_name + "' " + (newActive ? 'activated' : 'deactivated'),
      });
      toast.show('ok', "Template '" + tpl.dcfg_name + "' " + (newActive ? 'activated' : 'deactivated'));
      loadTemplates();
    } catch (e) {
      console.error('Toggle active:', e);
      toast.show('err', 'Failed to update template');
    }
  }, [user, toast, loadTemplates]);
```

**Proposed edit:**
```javascript
  var doToggle = useCallback(async function(tpl, newActive) {
    try {
      await apiPatch('/' + EntitySets.docTemplates + '(' + tpl.dcfg_document_templateid + ')', {
        dcfg_is_active: newActive,
      });
      await writeAuditLog({
        targetTable: 'dcfg_document_template',
        targetRecordId: tpl.dcfg_document_templateid,
        // CR-2026-04-09-0302: the magic ints 100000007 and 100000008 map to
        // AuditActionType.Created and AuditActionType.Deleted respectively
        // (see portalApi.js line 96 for the enum definition). The intent
        // here is "template activation = create-like; deactivation = delete-
        // like" so the audit timeline reads naturally for the operator. The
        // raw ints are kept (rather than referenced as AuditActionType.Created
        // / .Deleted) because the LABEL "Template Activated/Deactivated" is
        // the user-facing semantic, and aliasing those to Created/Deleted
        // would mislead anyone reading this file later. If a future schema
        // pass adds dedicated TemplateActivated / TemplateDeactivated values
        // to the dcfg_action_type Choice column, swap to AuditActionType
        // members at that time. Tracking: see operator-attention items in
        // the batch 07 approval doc.
        actionType: newActive ? 100000007 : 100000008,
        performedBy: user?.email || 'admin',
        newValue: "Template '" + tpl.dcfg_name + "' " + (newActive ? 'activated' : 'deactivated'),
      });
      toast.show('ok', "Template '" + tpl.dcfg_name + "' " + (newActive ? 'activated' : 'deactivated'));
      loadTemplates();
    } catch (e) {
      console.error('Toggle active:', e);
      toast.show('err', 'Failed to update template');
    }
  }, [user, toast, loadTemplates]);
```

**Operator-attention item:**

The finding's `recommendedFix` proposes `actionType: AuditActionType.StatusChanged` as the cleanest swap. That would replace the magic ints with a named enum but would CHANGE the audit_log filter semantics — every template activate/deactivate would show up under "Status Changed" in audit log dashboards instead of "Created"/"Deleted". This may or may not be the right operator-facing semantic. The proposed edit takes the conservative path: document the magic ints in place, leave the actual values unchanged, and flag the swap-to-StatusChanged decision as a follow-up. If the operator wants the StatusChanged semantic, the swap is one line.

**Rationale:** Matches option (b) of the operator directive ("add inline comments documenting what the ints mean"). The comment block explains:
1. WHAT the ints map to in `AuditActionType` (Created / Deleted).
2. WHY the raw ints are kept (the user-facing label is "Activated/Deactivated", not "Created/Deleted", and aliasing would mislead future readers).
3. WHEN to revisit (when a future schema pass adds dedicated picklist values).

The actual enum values are NOT changed in this edit — the audit-log dashboard semantics stay byte-identical to today. This is a documentation-only fix.

**Risk:** Zero. No runtime behavior change. The audit log row that gets written is byte-identical to today.

**Depends on:** none

---

### CR-2026-04-09-0278 — CapitalPlan has no in-component role check — relies on AppRouter guard only

**File:** src/screens/CapitalPlan.jsx
**Line(s):** 19-22
**Severity:** P3
**Category:** auth-role-checks

**Verification:** Confirmed by reading lines 1-60 of `src/screens/CapitalPlan.jsx`. `usePortalUser` is already imported at line 2 and `const { user } = usePortalUser();` is destructured at line 20. Grep across the file for `isAdmin` / `isManager` / `hasRole` returns zero matches — no in-component role check. The route is guarded at the AppRouter level by the batch 01 CR-0219 RoleGuard wrap. This batch adds defense-in-depth in the same shape as batch 05 CR-0246 (Admin screen) which the operator directive explicitly references as the pattern.

**Current code (lines 19-22):**
```javascript
export default function CapitalPlan() {
  const { user } = usePortalUser();
  const toast = useToast();
```

**Proposed edit:**
```javascript
export default function CapitalPlan() {
  const { user, isAdmin } = usePortalUser();
  const toast = useToast();

  // CR-2026-04-09-0278: defense-in-depth guard. The /capital-plan route is
  // already wrapped in <RoleGuard role="admin"> from AppRouter (batch 01
  // CR-2026-04-09-0219), but if that guard is ever removed or bypassed,
  // refuse to render the report-generation form. Mirrors the Admin screen
  // pattern from batch 05 CR-2026-04-09-0246.
  if (!isAdmin()) {
    return (
      <div style={{ padding: '32px', fontFamily: "'IBM Plex Sans', sans-serif" }} data-testid="capital-plan-access-denied">
        <h1 style={{ fontSize: '22px', color: '#1B2A4A', fontFamily: "'Fraunces', serif", marginBottom: '12px' }}>
          Capital Replacement Plan
        </h1>
        <p style={{ color: '#64748B', fontSize: '14px' }}>
          Admin access required.
        </p>
      </div>
    );
  }
```

**Operator note (NAVY constant):** The Admin.jsx fix (CR-0246) used a file-level `NAVY` constant for the heading color. CapitalPlan does NOT export a top-of-file `NAVY` constant — its style colors are inlined in the `styles` object at the bottom of the file. The proposed edit inlines `'#1B2A4A'` directly in the fallback heading style to avoid having to refactor the styles object or hoist a new top-of-file constant. If the operator prefers a hoisted constant, that's a one-line follow-up — flagged for visibility but not blocking.

**Rationale:** Matches `recommendedFix` and the batch 05 CR-0246 pattern verbatim. Two coupled changes: (1) destructure `isAdmin` from `usePortalUser()` (the existing destructure already takes `user` so this is a one-token addition), (2) add an early-return access-denied fallback before the report form renders. The fallback uses the same `data-testid="capital-plan-access-denied"` convention as Admin's `data-testid="admin-access-denied"` so Playwright tests can verify the fallback for non-admin fixtures.

**Risk:** Zero for admins (the `if (!isAdmin()) return ...` is false, code proceeds normally to the report form). For non-admins who reach this route through RoleGuard bypass, they see the fallback instead of the form — strictly better than the current "render the form + hope nothing gets submitted" behavior.

**Depends on:** CR-2026-04-09-0219 (batch 01, route-level guard) and CR-2026-04-09-0246 (batch 05, the Admin pattern this mirrors)

---

## Approval options

Reply with:
- `approve batch` — execute all 14 proposed edits (CR-0288 is drift-rejected and not executed)
- `approve <id1>,<id2>,...` — selective
- `reject <id>` — skip
- `reject batch` — cancel
- `hold` — park

**Housekeeping follow-up (out of scope for this batch — operator action during approval pass):**
- CR-2026-04-09-0310 → mark `rejected` with the schema-verified reject reason at the top of this doc.
- CR-2026-04-09-0288 → mark `rejected` with the drift reject reason at the top of this doc (and in the per-finding entry).
- CR-2026-04-09-0285 → flag a Phase 3 follow-up: "ProjectDetail Save-as-Template SlideOutPanel rewrite" (the proper fix is too architecturally invasive for a P3 batch — narrow fix landed in this batch tightens the prompt wording and adds whitespace/empty-string defenses).
- CR-2026-04-09-0276 → after deploy, provision dcfg_configs rows `dcfg_team_email` and `dcfg_compliance_email` in Test / Stage / Prod so the override path is exercised (the SPA falls back to the current hardcoded values until the rows exist).
- CR-2026-04-09-0295 → flag two Phase 3 follow-ups: (a) move geocoder URL to dcfg_configs, (b) add localStorage geocode cache.
- CR-2026-04-09-0302 → flag a Phase 3 decision: should template activate/deactivate audit events use AuditActionType.StatusChanged instead of the current Created/Deleted aliasing? Or should new TemplateActivated/TemplateDeactivated picklist values be added to dcfg_action_type? Operator decision.
