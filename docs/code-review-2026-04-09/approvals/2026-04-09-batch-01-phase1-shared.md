# Batch 01 — Phase 1 Shared-Modules Fixes

**Phase:** 1
**Target:** Shared modules under C:\DCFG\spa\dcfg-shell\src\
**Findings count:** 13 approved for this batch (3 P0 + 10 P1 — the load-bearing subset)
**Generated:** 2026-04-09T00:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-01-phase1-shared.md

## Scope rules (from spec §4.6)

- Batch size ≤ 15 findings (this batch: 13)
- All `batch` tier (no auto-fix items)
- Every proposed edit has before/after code visible
- Sequencing: 0210 before 0201; 0219 before 0233; 0211 before 0226

## Cross-finding dependencies

- **0210 → 0201:** The apiPost contract change must land first (apiPost gains JSDoc marking it void; apiPostReturn remains the record-returning entry point). Then LocationManager.jsx:555 consumer fix switches to apiPostReturn and drops the spurious `true` arg.
- **0211 → 0226:** loadConfig race fix is the root cause. The App.jsx render-gating change in 0226 depends on loadConfig still returning a Promise (it does) and uses a new `configLoaded` state flag to gate AppRouter until the cache is populated. 0240 (SensorBanner hooks bug) also depends on 0211/0226 because once config loads before the first render, the kill-switch path becomes reliable.
- **0219 → 0233:** Wiring RoleGuard into AppRouter.jsx auto-closes the orphaned-component finding. No separate code change for 0233.
- **0219 + 0220:** The route-level RoleGuard (0219) is the primary defense. NavPanel.jsx `isVisible()` (0220) is the secondary cosmetic gate — the two together suppress admin items from DOM for non-admins AND block direct URL access. 0220 adds `role:'admin'` to admin-only NAV_GROUPS entries and reorders the fallback so the role check runs before the `!item.role → return true` default.

---

## Findings in this batch

### CR-2026-04-09-0210 — apiPost has no return value but several callers treat it as if it returns the created record

**File:** src/portalApi.js
**Line(s):** 159-164
**Severity:** P1
**Category:** error-handling

**Current code:**
```javascript
export async function apiPost(path, body) {
  const token = await getToken();
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`;
  const resp = await fetch(url, { method:'POST', headers:{ 'Content-Type':'application/json','Accept':'application/json','OData-MaxVersion':'4.0','OData-Version':'4.0','__RequestVerificationToken':token }, credentials:'same-origin', body:JSON.stringify(trimBody(body)) });
  if (!resp.ok) { if (resp.status===403||resp.status===401) invalidateToken(); let msg='POST failed'; try { const j=await resp.json(); msg=j?.error?.message||msg; } catch {} throw new ApiError(resp.status,path,msg); }
}
```

**Proposed edit:**
```javascript
/**
 * Fire-and-forget POST. Returns void. Throws ApiError on non-OK.
 * Use apiPostReturn() if you need the created record back,
 * or apiPostReturnId() if you only need the GUID.
 *
 * DO NOT read a return value from this function — it is always undefined.
 */
export async function apiPost(path, body) {
  const token = await getToken();
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`;
  const resp = await fetch(url, { method:'POST', headers:{ 'Content-Type':'application/json','Accept':'application/json','OData-MaxVersion':'4.0','OData-Version':'4.0','__RequestVerificationToken':token }, credentials:'same-origin', body:JSON.stringify(trimBody(body)) });
  if (!resp.ok) { if (resp.status===403||resp.status===401) invalidateToken(); let msg='POST failed'; try { const j=await resp.json(); msg=j?.error?.message||msg; } catch {} throw new ApiError(resp.status,path,msg); }
}
```

**Rationale:** Make the void contract explicit at the call site via JSDoc. The finding's recommendedFix proposes either renaming to `apiPostVoid` or adding a JSDoc comment. JSDoc is the smaller, lower-risk change and still surfaces the contract in hover-intellisense. Actual consumer fix (CR-2026-04-09-0201) switches to apiPostReturn, which already exists. Keeping the function name preserves the existing apiPost imports used elsewhere in the SPA.

**Risk:** Zero behavioral change — documentation only. Any future consumer that reads the return value now has a clear JSDoc warning to consult. No API surface changes.

**Depends on:** none

---

### CR-2026-04-09-0211 — loadConfig is async but getEnvVar is synchronous — race condition for early consumers

**File:** src/portalApi.js
**Line(s):** 343-346
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
export function getEnvVar(schemaName) {
  if (!_configCache) return null;
  return _configCache[schemaName] || null;
}
```

**Proposed edit:**
```javascript
/**
 * Synchronously read a config value from the cache populated by loadConfig().
 *
 * RACE-SAFETY NOTE: returns null if loadConfig() has not yet resolved.
 * App.jsx gates AppRouter render until loadConfig resolves (see configLoaded
 * state), so by the time any screen renders, the cache is populated. Modules
 * that render BEFORE AppRouter (NavPanel, SensorBanner) must either:
 *   1. subscribe to the 'dcfg-config-changed' event to re-render once config
 *      reloads at runtime (see NavPanel.jsx:99), or
 *   2. tolerate a null return on first render.
 */
export function getEnvVar(schemaName) {
  if (!_configCache) return null;
  return _configCache[schemaName] || null;
}
```

**Rationale:** The root fix for the race is the App.jsx render-gate in 0226 (which depends on this finding). Here in portalApi.js we add a doc block above getEnvVar that codifies the contract so future consumers know why a null return is possible and which re-render mechanisms exist. No behavior change in the function body itself.

**Risk:** Zero behavioral change — documentation only.

**Depends on:** none (but paired with 0226)

---

### CR-2026-04-09-0209 — RFP_LIST_COLS contains typo `dcfg_contract_fe` (should be dcfg_contract_fee)

**File:** src/portalApi.js
**Line(s):** 754
**Severity:** P0
**Category:** data-integrity

**Current code:**
```javascript
const RFP_LIST_COLS = 'dcfg_rfp_packageid,dcfg_name,dcfg_trades,dcfg_total_estimated_value,dcfg_status,dcfg_billing_pattern,dcfg_deadline,dcfg_active_flag,dcfg_bid_solicited,dcfg_bid_received,dcfg_scope_exhibit_drafted,dcfg_contract_fe';
```

**Proposed edit:**
```javascript
const RFP_LIST_COLS = 'dcfg_rfp_packageid,dcfg_name,dcfg_trades,dcfg_total_estimated_value,dcfg_status,dcfg_billing_pattern,dcfg_deadline,dcfg_active_flag,dcfg_bid_solicited,dcfg_bid_received,dcfg_scope_exhibit_drafted,dcfg_contract_fee';
```

**Rationale:** `dcfg_contract_fe` is a one-character truncation typo of `dcfg_contract_fee`. Dataverse returns 400 on any GET that includes an unknown column in $select, so both fetchRfpPackages() and fetchRfpDetail() (which concatenates RFP_LIST_COLS into RFP_DETAIL_COLS) will 400 on every call, breaking the RFP list and detail screens in every environment. Canonical column name `dcfg_contract_fee` confirmed by comparison to CONTRACT_LIST_COLS at line 361 and CONTRACT_DETAIL_COLS at line 362.

**Risk:** Trivial fix. The only risk is if the dcfg_rfp_packages schema actually lacks a `dcfg_contract_fee` column — but the finding's evidence and the mirror-field pattern from dcfg_contract strongly imply it exists. Operator should smoke-test /#/rfps and /#/rfps/:id after deploy to confirm no 400s.

**Depends on:** none

---

### CR-2026-04-09-0226 — loadConfig() fired in useEffect but AppShell renders immediately — children see null config on first render

**File:** src/App.jsx
**Line(s):** 215-251
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
function AppShell() {
  const { user, loading } = usePortalUser();
  const [sessionLogged, setSessionLogged] = React.useState(false);
  const [directoryOpen, setDirectoryOpen] = React.useState(false);
  const [noraOpen, setNoraOpen] = React.useState(false);

  initErrorBuffer();
  initDebug();

  // Load config from dcfg_configs table (flow URLs, etc.) — once at boot
  React.useEffect(() => { loadConfig(); }, []);

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

  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' }}>
        <div style={{
          width: '40px', height: '40px',
          border: '3px solid #E2E8F0', borderTopColor: '#1B2A4A',
          borderRadius: '50%', animation: 'dcfg-spin 0.7s linear infinite'
        }} />
      </div>
    );
  }
```

**Proposed edit:**
```javascript
function AppShell() {
  const { user, loading } = usePortalUser();
  const [sessionLogged, setSessionLogged] = React.useState(false);
  const [directoryOpen, setDirectoryOpen] = React.useState(false);
  const [noraOpen, setNoraOpen] = React.useState(false);
  const [configLoaded, setConfigLoaded] = React.useState(false);

  initErrorBuffer();
  initDebug();

  // Load config from dcfg_configs table (flow URLs, etc.) — once at boot.
  // Gate AppRouter render on configLoaded so NavPanel/SensorBanner/screens
  // never see a null getEnvVar() on first paint. See CR-2026-04-09-0211.
  React.useEffect(() => {
    loadConfig().finally(() => setConfigLoaded(true));
  }, []);

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

  if (loading || !configLoaded) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' }}>
        <div style={{
          width: '40px', height: '40px',
          border: '3px solid #E2E8F0', borderTopColor: '#1B2A4A',
          borderRadius: '50%', animation: 'dcfg-spin 0.7s linear infinite'
        }} />
      </div>
    );
  }
```

**Rationale:** Matches the recommendedFix precisely. Adds a `configLoaded` flag that is set to true whenever loadConfig's promise settles (either success or failure — we want the spinner to disengage on failure so the user still sees the app rather than a permanent spinner). Gates the AppRouter render behind `loading || !configLoaded`. After this change, every downstream render of NavPanel / SensorBanner / screens is guaranteed to have `_configCache` populated, so getEnvVar() returns live values on first render.

**Risk:** Adds one render cycle (from null config → spinner) on cold load. The spinner already exists for the `loading` state, so users will not notice the extra delay. If loadConfig hangs indefinitely (e.g., Power Pages outage), the spinner will hang too — but so would everything else. The `.finally()` ensures we always flip to configLoaded even on fetch failure, which matches the existing loadConfig error path (it sets _configCache = {} and returns).

**Depends on:** 0211

---

### CR-2026-04-09-0240 — sensor_enabled kill switch reads getEnvVar synchronously at top of render — race with loadConfig

**File:** src/SensorBanner.jsx
**Line(s):** 30-38
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
export default function SensorBanner() {
  // Config kill switch: set sensor_enabled = "false" in dcfg_configs to disable polling
  if (getEnvVar('sensor_enabled') === 'false') return null;
  const [alerts, setAlerts] = useState([]);
  const [dismissed, setDismissed] = useState(() => {
    try {
      return new Set(JSON.parse(sessionStorage.getItem('dcfg_dismissed_sensors') || '[]'));
    } catch { return new Set(); }
  });
  const timerRef = useRef(null);
```

**Proposed edit:**
```javascript
export default function SensorBanner() {
  const [alerts, setAlerts] = useState([]);
  const [dismissed, setDismissed] = useState(() => {
    try {
      return new Set(JSON.parse(sessionStorage.getItem('dcfg_dismissed_sensors') || '[]'));
    } catch { return new Set(); }
  });
  const timerRef = useRef(null);

  // Config kill switch: set sensor_enabled = "false" in dcfg_configs to disable polling.
  // Declared AFTER all hooks to satisfy React rules-of-hooks. See CR-2026-04-09-0240.
  const sensorDisabled = getEnvVar('sensor_enabled') === 'false';
```

**Rationale:** The current code violates the React rules-of-hooks: the early `return null` runs before `useState`/`useRef` declarations, so on the first render (where sensor_enabled is falsy because loadConfig hasn't resolved — see 0211) the component returns null and never registers any hooks. On the second render (after config loads), the conditional disappears and the component runs all the hooks, causing "rendered more hooks than expected" errors. The fix is to declare all hooks unconditionally first, then derive a `sensorDisabled` flag, then use it below in combination with the existing `alerts.length === 0` check at line 120.

Below is the companion edit at line 120 to consume `sensorDisabled`:

**Additional edit at line 120:**

**Current code:**
```javascript
  if (alerts.length === 0) return null;
```

**Proposed edit:**
```javascript
  if (sensorDisabled || alerts.length === 0) return null;
```

**Rationale (additional):** Once the kill-switch flag is declared after the hooks, wiring it into the existing early-return consolidates the suppression logic in one place. The fetchAlerts useEffect still runs (which is a minor cost — one initial fetch before the first render returns null), but this is acceptable and matches the recommendedFix's "declare hooks unconditionally first" pattern. A follow-up P3 finding could short-circuit fetchAlerts based on sensorDisabled if polling cost becomes a concern.

**Risk:** The kill switch no longer takes effect on the VERY first render before any fetch has run — but now that 0226 gates the app on configLoaded, the first SensorBanner render happens AFTER loadConfig resolves, so getEnvVar will return the correct value. The hooks-order bug is eliminated. SensorBanner still does not subscribe to the dcfg-config-changed event, so toggling sensor_enabled at runtime requires a page reload — acceptable for this batch and tracked as future polish.

**Depends on:** 0211, 0226

---

### CR-2026-04-09-0227 — useMemo dep array includes searchFields — inline-literal callers blow the cache every render

**File:** src/useTableControls.jsx
**Line(s):** 28-63
**Severity:** P1
**Category:** performance

**Current code:**
```javascript
  const filtered = useMemo(() => {
    let result = [...(rows || [])];

    // Search filter
    if (searchTerm.trim() && searchFields.length > 0) {
      const term = searchTerm.toLowerCase();
      result = result.filter(row =>
        searchFields.some(field => {
          const val = getNestedValue(row, field);
          return val != null && String(val).toLowerCase().includes(term);
        })
      );
    }

    // Sort
    if (sortCol) {
      result.sort((a, b) => {
        let va = getNestedValue(a, sortCol);
        let vb = getNestedValue(b, sortCol);
        if (va == null) va = '';
        if (vb == null) vb = '';
        // Numeric comparison if both are numbers
        if (typeof va === 'number' && typeof vb === 'number') {
          return sortDir === 'asc' ? va - vb : vb - va;
        }
        // String comparison
        va = String(va).toLowerCase();
        vb = String(vb).toLowerCase();
        if (va < vb) return sortDir === 'asc' ? -1 : 1;
        if (va > vb) return sortDir === 'asc' ? 1 : -1;
        return 0;
      });
    }

    return result;
  }, [rows, sortCol, sortDir, searchTerm, searchFields]);
```

**Proposed edit:**
```javascript
  // Stable key for searchFields so inline-literal callers don't blow the cache
  // on every render. Callers can safely pass inline arrays — see CR-2026-04-09-0227.
  const searchFieldsKey = (searchFields || []).join('|');

  const filtered = useMemo(() => {
    let result = [...(rows || [])];

    // Search filter
    if (searchTerm.trim() && searchFields.length > 0) {
      const term = searchTerm.toLowerCase();
      result = result.filter(row =>
        searchFields.some(field => {
          const val = getNestedValue(row, field);
          return val != null && String(val).toLowerCase().includes(term);
        })
      );
    }

    // Sort
    if (sortCol) {
      result.sort((a, b) => {
        let va = getNestedValue(a, sortCol);
        let vb = getNestedValue(b, sortCol);
        if (va == null) va = '';
        if (vb == null) vb = '';
        // Numeric comparison if both are numbers
        if (typeof va === 'number' && typeof vb === 'number') {
          return sortDir === 'asc' ? va - vb : vb - va;
        }
        // String comparison
        va = String(va).toLowerCase();
        vb = String(vb).toLowerCase();
        if (va < vb) return sortDir === 'asc' ? -1 : 1;
        if (va > vb) return sortDir === 'asc' ? 1 : -1;
        return 0;
      });
    }

    return result;
    // eslint-disable-next-line react-hooks/exhaustive-deps -- searchFieldsKey is the stable proxy for searchFields
  }, [rows, sortCol, sortDir, searchTerm, searchFieldsKey]);
```

**Rationale:** Exactly the recommendedFix. Joining the searchFields array with `|` produces a stable string key that React can reference-check cheaply. For the 6 call sites that pass inline literals (MsaList, ContractList, CustomerList, Locations, ViewSmartList), the useMemo cache now only invalidates when the actual field list content changes, not when the parent re-renders. The eslint-disable is necessary because we're intentionally using a derived key instead of the raw array; the comment makes the rationale explicit.

**Risk:** Very low. The sort+filter logic reads from `searchFields` (not `searchFieldsKey`), so the closure still has access to the real array. The only way this breaks is if two logically different searchFields arrays happen to produce the same `|`-joined string — but that requires field names containing a `|` character, which dcfg column names never do.

**Depends on:** none

---

### CR-2026-04-09-0200 — APPL_COLS referenced but never defined — ReferenceError on every openLocation()

**File:** src/LocationManager.jsx
**Line(s):** 52-64 (constant addition) + 473 (usage site is already correct)
**Severity:** P0
**Category:** data-integrity

**Current code (lines 52-64):**
```javascript
// Property detail columns to SELECT
const DETAIL_COLS = [
  'dcfg_property_detailid','dcfg_heating_type','dcfg_water_supply','dcfg_parking',
  'dcfg_trash_collection','dcfg_home_type','dcfg_home_ownership','dcfg_entry_time','dcfg_service_line',
  'dcfg_has_pool','dcfg_has_garage','dcfg_has_lockbox','dcfg_has_solar','dcfg_has_detectors','dcfg_has_floor_plans',
  'dcfg_generator_present','dcfg_generator_install_date',
  'dcfg_septic_present','dcfg_septic_install_date',
  'dcfg_grease_trap_present','dcfg_grease_trap_install_date',
  'dcfg_sprinkler_present','dcfg_sprinkler_last_inspection','dcfg_sprinkler_next_due',
  'dcfg_water_treatment_present','dcfg_water_treatment_last','dcfg_water_treatment_due',
  'dcfg_fire_alarm_type','dcfg_fire_alarm_last','dcfg_fire_alarm_due',
  'dcfg_idd_last','dcfg_idd_due','dcfg_dca_last','dcfg_dca_due'
];
```

**Proposed edit:**
```javascript
// Property detail columns to SELECT
const DETAIL_COLS = [
  'dcfg_property_detailid','dcfg_heating_type','dcfg_water_supply','dcfg_parking',
  'dcfg_trash_collection','dcfg_home_type','dcfg_home_ownership','dcfg_entry_time','dcfg_service_line',
  'dcfg_has_pool','dcfg_has_garage','dcfg_has_lockbox','dcfg_has_solar','dcfg_has_detectors','dcfg_has_floor_plans',
  'dcfg_generator_present','dcfg_generator_install_date',
  'dcfg_septic_present','dcfg_septic_install_date',
  'dcfg_grease_trap_present','dcfg_grease_trap_install_date',
  'dcfg_sprinkler_present','dcfg_sprinkler_last_inspection','dcfg_sprinkler_next_due',
  'dcfg_water_treatment_present','dcfg_water_treatment_last','dcfg_water_treatment_due',
  'dcfg_fire_alarm_type','dcfg_fire_alarm_last','dcfg_fire_alarm_due',
  'dcfg_idd_last','dcfg_idd_due','dcfg_dca_last','dcfg_dca_due'
];

// Appliance columns to SELECT — mirrors every field read by normaliseAppl() below.
// See CR-2026-04-09-0200.
const APPL_COLS = 'dcfg_applianceid,dcfg_custom_label,dcfg_brand,dcfg_location_in_property,dcfg_install_date,dcfg_serial_number,dcfg_primary_photo_url,dcfg_serial_photo_url,dcfg_replace_by_status,dcfg_estimated_replace_by';
```

**Rationale:** APPL_COLS is referenced at line 473 inside an `apiGet(...${APPL_COLS}...)` template literal but never declared anywhere in the file. On first openLocation() the template-literal evaluation throws ReferenceError BEFORE the network call, Promise.allSettled swallows it as rejected, and the appliance grid stays empty with no visible error. Defining APPL_COLS as a string constant adjacent to DETAIL_COLS keeps the "column list constants at top of file" pattern consistent. Column selection matches every field consumed by normaliseAppl() at lines 146-162:
- dcfg_applianceid (id, guid)
- dcfg_custom_label (customLabel)
- dcfg_brand (brand)
- dcfg_location_in_property (location)
- dcfg_install_date (installDate)
- dcfg_serial_number (serial)
- dcfg_primary_photo_url (primaryPhotoUrl)
- dcfg_serial_photo_url (serialPhotoUrl)
- dcfg_replace_by_status (replaceByStatus)
- dcfg_estimated_replace_by (estimatedReplaceBy)

The `dcfg_appliance_type_id` lookup is NOT included here because it's fetched via `$expand` at line 473 and produces the nested `t` object in normaliseAppl.

Note: the usage at line 473 does NOT need to change — the fix is purely to declare the missing constant.

**Risk:** Explicit $select of a missing column would 400. All 10 columns listed are referenced verbatim in normaliseAppl(), so the schema is implicitly verified by the existing code. Smoke test: tap a property in /#/field and confirm the appliance grid populates without console errors.

**Depends on:** none

---

### CR-2026-04-09-0202 — userName destructured from usePortalUser() but no such property exists

**File:** src/usePortalUser.jsx
**Line(s):** 110-117
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
  return {
    hasRole,
    isAdmin:   () => hasRole('DCFG_Admin'),
    isManager: () => hasRole('DCFG_Manager') || hasRole('DCFG_Admin'),
    isViewer:  () => user?.isAuthenticated === true,
    userEmail: user?.email ?? null,
  };
}
```

**Proposed edit:**
```javascript
  return {
    hasRole,
    isAdmin:   () => hasRole('DCFG_Admin'),
    isManager: () => hasRole('DCFG_Manager') || hasRole('DCFG_Admin'),
    isViewer:  () => user?.isAuthenticated === true,
    userEmail: user?.email ?? null,
    userName:  user?.name ?? null,
  };
}
```

**Rationale:** The recommended fix in CR-2026-04-09-0231 (the paired usePortalUser API gap finding) is to expose `userName` alongside `userEmail`. LocationManager.jsx:354 already does `const { userEmail, userName } = usePortalUser();` expecting userName to exist — right now it's undefined and the avatar initials at line 1099 always fall back to 'FT'. Adding `userName: user?.name ?? null,` is additive and low-risk — existing consumers that don't destructure userName are unaffected, and LocationManager starts working correctly with no further edits. This fixes the LocationManager symptom AT THE SOURCE (usePortalUser) rather than patching just the one consumer, which means any future consumer that wants userName gets it for free.

**Risk:** Pure addition to a returned object. Zero breaking changes. Side benefit: closes part of CR-2026-04-09-0231 (usePortalUser API gap) without touching LocationManager.

**Depends on:** none

---

### CR-2026-04-09-0201 — apiPost called with 3rd arg + treated as if it returns the created record

**File:** src/LocationManager.jsx
**Line(s):** 25-30 (import update) + 555-556 (call site fix)
**Severity:** P0
**Category:** data-integrity

**Current code (lines 25-30):**
```javascript
import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  apiGet, apiPost, apiPatch, odataBind, getEnvVar,
  EntitySets, formatCurrency,
  createDocumentRequest, DocRequestType
} from './portalApi';
```

**Proposed edit (import update):**
```javascript
import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  apiGet, apiPost, apiPostReturn, apiPatch, odataBind, getEnvVar,
  EntitySets, formatCurrency,
  createDocumentRequest, DocRequestType
} from './portalApi';
```

**Current code (line 555-556):**
```javascript
      const created = await apiPost(`/${EntitySets.appliances}`, body, true);
      const newGuid = created?.dcfg_applianceid;
```

**Proposed edit (call site):**
```javascript
      const created = await apiPostReturn(`/${EntitySets.appliances}`, body);
      const newGuid = created?.dcfg_applianceid;
```

**Rationale:** apiPost is void (confirmed by 0210). The third argument `true` was silently ignored, and `created` was always undefined — meaning every new appliance card saved with an undefined GUID and every subsequent debounced PATCH keyed off that undefined GUID was a no-op. The author clearly meant apiPostReturn, which returns the created record via OData-EntityId header lookup (portalApi.js:166-188). Switching to apiPostReturn populates `created.dcfg_applianceid` correctly and fixes the photo upload chain at line 559 which depends on a real newGuid.

The import line update adds `apiPostReturn` to the existing import list (minimal surface area — other apiPost consumers in this file remain unchanged if any exist elsewhere).

**Risk:** apiPostReturn does an extra GET to fetch the created record (portalApi.js:181), so the call takes slightly longer than the broken apiPost. No correctness risk — the function is already used extensively elsewhere in the SPA for tables that need record-after-create. Smoke test: add an appliance via /#/field and confirm the new card has a real GUID in network-tab PATCH calls.

**Depends on:** 0210

---

### CR-2026-04-09-0219 — AppRouter has zero RoleGuard wrappers — admin/internal routes accessible to any authenticated user

**File:** src/AppRouter.jsx
**Line(s):** 13 (import), 56-151 (router body)
**Severity:** P1
**Category:** auth-role-checks

**Current code (imports):**
```javascript
import { Routes, Route, Navigate } from 'react-router-dom';

// ── Existing screens (unchanged) ──
```

**Proposed edit (imports):**
```javascript
import { Routes, Route, Navigate } from 'react-router-dom';
import RoleGuard from './RoleGuard.jsx';

// ── Existing screens (unchanged) ──
```

**Current code (admin route block, lines 88-89):**
```javascript
      {/* Page 07 — Contract Delivery / Send Queue */}
      <Route path="send-queue" element={<SendQueue />} />
```

**Proposed edit:**
```javascript
      {/* Page 07 — Contract Delivery / Send Queue (admin only — see CR-2026-04-09-0219) */}
      <Route path="send-queue" element={<RoleGuard require="admin" fallback={<Navigate to="/dashboard" replace />}><SendQueue /></RoleGuard>} />
```

**Current code (flow-monitor, lines 111-112):**
```javascript
      {/* Flow Monitor */}
      <Route path="flow-monitor" element={<FlowMonitor />} />
```

**Proposed edit:**
```javascript
      {/* Flow Monitor (admin only) */}
      <Route path="flow-monitor" element={<RoleGuard require="admin" fallback={<Navigate to="/dashboard" replace />}><FlowMonitor /></RoleGuard>} />
```

**Current code (absorption, lines 142-143):**
```javascript
      {/* Absorption Dashboard */}
      <Route path="absorption" element={<AbsorptionDashboard />} />
```

**Proposed edit:**
```javascript
      {/* Absorption Dashboard (admin only) */}
      <Route path="absorption" element={<RoleGuard require="admin" fallback={<Navigate to="/dashboard" replace />}><AbsorptionDashboard /></RoleGuard>} />
```

**Current code (admin route, lines 145-146):**
```javascript
      {/* Admin Hub */}
      <Route path="admin" element={<Admin />} />
```

**Proposed edit:**
```javascript
      {/* Admin Hub (admin only) */}
      <Route path="admin" element={<RoleGuard require="admin" fallback={<Navigate to="/dashboard" replace />}><Admin /></RoleGuard>} />
```

**Current code (capital-plan, lines 77-78):**
```javascript
      {/* Capital Replacement Plan Report */}
      <Route path="capital-plan" element={<CapitalPlan />} />
```

**Proposed edit:**
```javascript
      {/* Capital Replacement Plan Report (admin only) */}
      <Route path="capital-plan" element={<RoleGuard require="admin" fallback={<Navigate to="/dashboard" replace />}><CapitalPlan /></RoleGuard>} />
```

**Rationale:** Five admin-only routes get wrapped in `<RoleGuard require="admin" fallback={<Navigate to="/dashboard" replace />}>...</RoleGuard>`. Non-admins typing /#/admin, /#/flow-monitor, /#/send-queue, /#/absorption, or /#/capital-plan are redirected to /dashboard instead of seeing the admin UI. RoleGuard already exists (src/RoleGuard.jsx) and its API signature is `require="admin"|"manager"|"viewer"` and `fallback` prop — both verified from the file. The fallback redirect avoids a blank page for non-admins.

The scope here is the 5 admin-only paths listed in the finding. Other internal-tool paths like /nora and /interview are NOT wrapped in this batch — they're still accessible to any authenticated user. Phase 3 screen audit will flag any additional role-gate needs.

**Risk:** Non-admin users who have previously bookmarked /#/admin etc. will be redirected to /dashboard — this is the intended behavior. Any admin action invoked while RoleGuard is still in `loading` state (before usePortalUser resolves) will render null briefly; RoleGuard handles this via its `if (loading) return null` check. If isAdmin() incorrectly returns false for a valid admin due to a role-normalization bug, the admin sees a redirect to /dashboard — debugging surface is the existing role-helper chain. Low risk given RoleGuard is already well-built and the imports cleanly slot into the existing router.

**Depends on:** none (0233 auto-closes from this edit)

---

### CR-2026-04-09-0233 — RoleGuard component is correct but has zero call sites in shared modules — never wired into the router

**File:** src/RoleGuard.jsx (orphaned-component finding)
**Line(s):** n/a — no code change in this file
**Severity:** P1
**Category:** auth-role-checks

**Status:** CLOSED BY 0219 — no separate code change needed.

**Rationale:** The RoleGuard component implementation is already correct. The finding is about the lack of call sites in shared modules. Once CR-2026-04-09-0219 lands (wrapping 5 admin routes in `<RoleGuard require="admin">`), RoleGuard has real call sites in AppRouter.jsx and the orphaned-component finding is resolved. The executor should mark this finding as fixed/verified in the same commit as 0219 with a note referencing the shared edit.

**Depends on:** 0219

---

### CR-2026-04-09-0220 — isVisible() role gating is config-driven only — no nav item declares item.role, so admin items show to everyone

**File:** src/NavPanel.jsx
**Line(s):** 36-84 (NAV_GROUPS) + 123-148 (isVisible)
**Severity:** P1
**Category:** auth-role-checks

**Current code (NAV_GROUPS admin items, lines 66-83):**
```javascript
  {
    label: 'ADMINISTRATION',
    collapsed: true,
    items: [
      { to: '/send-queue',     label: 'Clearance',       icon: <QueueIcon /> },
    ],
  },
  {
    label: 'SYSTEM',
    collapsed: true,
    items: [
      { to: '/admin',      label: 'System Admin',  icon: <AdminIcon /> },
      { to: '/flow-monitor', label: 'Flow Monitor', icon: <MonitorIcon /> },
      { to: '/field',       label: 'DMS Mobile',    icon: <LocationIcon /> },
      { to: '/concierge',  label: 'Concierge Onboarding Website',    icon: <CustomersIcon />, externalFn: () => getEnvVar('concierge_portal_url') },
      { to: '/portal',     label: 'Portal',         icon: <CustomersIcon />, externalFn: () => getEnvVar('customer_portal_url') },
    ],
  },
];
```

**Proposed edit:**
```javascript
  {
    label: 'ADMINISTRATION',
    collapsed: true,
    items: [
      { to: '/send-queue',     label: 'Clearance',       icon: <QueueIcon />, role: 'admin' },
    ],
  },
  {
    label: 'SYSTEM',
    collapsed: true,
    items: [
      { to: '/admin',      label: 'System Admin',  icon: <AdminIcon />, role: 'admin' },
      { to: '/flow-monitor', label: 'Flow Monitor', icon: <MonitorIcon />, role: 'admin' },
      { to: '/field',       label: 'DMS Mobile',    icon: <LocationIcon /> },
      { to: '/concierge',  label: 'Concierge Onboarding Website',    icon: <CustomersIcon />, externalFn: () => getEnvVar('concierge_portal_url') },
      { to: '/portal',     label: 'Portal',         icon: <CustomersIcon />, externalFn: () => getEnvVar('customer_portal_url') },
    ],
  },
];
```

**Current code (isVisible fallback block, lines 122-148):**
```javascript
  // System Admin is always visible (can't lock yourself out).
  function isVisible(item) {
    if (item.to === '/admin') return true;
    // Create actions use item.key directly; nav items derive route from item.to
    const route = item.key || (item.to.replace(/^\//, '') || 'dashboard');

    // Check role-based menus first
    const userRoles = (user?.roles || []).map(r => r.name || r).filter(Boolean);
    const roleMenus = userRoles
      .map(role => getEnvVar(`nav_menu_${role}`))
      .filter(Boolean);

    if (roleMenus.length > 0) {
      // Role menus exist — build union of allowed routes
      const allowed = new Set();
      roleMenus.forEach(csv => csv.split(',').forEach(r => allowed.add(r.trim())));
      return allowed.has(route);
    }

    // Fallback: global nav_visible_{route} toggle (backward compat)
    const configVal = getEnvVar(`nav_visible_${route}`);
    if (configVal === 'false') return false;
    if (!item.role) return true;
    if (item.role === 'admin')   return isAdmin();
    if (item.role === 'manager') return isManager();
    return isViewer();
  }
```

**Proposed edit:**
```javascript
  // System Admin is always visible to admins (can't lock yourself out),
  // but must be hidden from non-admins. See CR-2026-04-09-0220 / 0224.
  function isVisible(item) {
    if (item.to === '/admin') return isAdmin();
    // Create actions use item.key directly; nav items derive route from item.to
    const route = item.key || (item.to.replace(/^\//, '') || 'dashboard');

    // Check role-based menus first
    const userRoles = (user?.roles || []).map(r => r.name || r).filter(Boolean);
    const roleMenus = userRoles
      .map(role => getEnvVar(`nav_menu_${role}`))
      .filter(Boolean);

    if (roleMenus.length > 0) {
      // Role menus exist — build union of allowed routes
      const allowed = new Set();
      roleMenus.forEach(csv => csv.split(',').forEach(r => allowed.add(r.trim())));
      return allowed.has(route);
    }

    // Fallback: role check FIRST (so /admin items stay hidden from viewers),
    // then global nav_visible_{route} toggle (backward compat).
    if (item.role === 'admin')   return isAdmin();
    if (item.role === 'manager') return isManager();
    const configVal = getEnvVar(`nav_visible_${route}`);
    if (configVal === 'false') return false;
    return true;
  }
```

**Rationale:** Two changes:
1. **NAV_GROUPS:** Adds `role: 'admin'` to the three admin-only nav items (send-queue/Clearance, admin, flow-monitor). The DMS Mobile (/field), Concierge, and Portal items are left without a role because they are not admin-only — Concierge/Portal are external URLs and /field is for the field-ops tablet user.
2. **isVisible():** Flipped the hardcoded `return true` for /admin to `return isAdmin()` so non-admins no longer see System Admin in the nav. Reordered the fallback so the item.role check runs BEFORE the nav_visible_{route} config lookup — this means that if a role-gated item has no nav_visible_ config row, it falls back to the role check instead of defaulting to visible. This is the explicit guidance from the finding: "change the fallback so the absence of a config row falls back to the role check FIRST before defaulting to visible."

Note this is a DEFENSE-IN-DEPTH pair with 0219. Even if NavPanel's isVisible had a bug, the RoleGuard wrapper in AppRouter would still redirect non-admins hitting /#/admin directly. And vice versa — even if RoleGuard's check failed, NavPanel wouldn't show the menu item to non-admins.

**Risk:** Admins will continue to see all admin items (isAdmin() returns true). Non-admins will lose three nav items they previously saw (and could click but not use). If the dcfg_configs table has `nav_menu_DCFG_Admin` set and does NOT include 'admin' in the list, admins now lose the link — but that's a configuration error that the finding explicitly considers the correct behavior (operator should fix the config). Also note: `nav_visible_{route}` path is still active for non-role-gated items (fallback behavior preserved).

**Depends on:** 0219 (co-enforced)

---

### CR-2026-04-09-0221 — CREATE_ACTIONS references <NewContractIcon /> JSX before the function is declared

**File:** src/NavPanel.jsx
**Line(s):** 25-31 (two sub-edits: (a) distinct icons + (b) move icons above CREATE_ACTIONS)
**Severity:** P1
**Category:** data-integrity

**Sub-edit (a): Give each CREATE action a distinct icon**

**Current code (lines 25-31):**
```javascript
const CREATE_ACTIONS = [
  { key: 'create-proposal',         label: 'Proposal',         to: '/proposals/new',              icon: <NewContractIcon /> },
  { key: 'create-vendor-agreement', label: 'Vendor Agreement', to: '/contracts/new?type=msa',     icon: <NewContractIcon /> },
  { key: 'create-workorder',        label: 'Work Order',       to: '/contracts/new',              icon: <NewContractIcon /> },
  { key: 'create-amendment',        label: 'Amendment',        to: '/contracts/new?type=amendment', icon: <NewContractIcon /> },
  { key: 'create-project',          label: 'Project',          to: '/projects?new=1',               icon: <NewContractIcon /> },
];
```

**Proposed edit:**
```javascript
const CREATE_ACTIONS = [
  { key: 'create-proposal',         label: 'Proposal',         to: '/proposals/new',              icon: <MsaIcon /> },
  { key: 'create-vendor-agreement', label: 'Vendor Agreement', to: '/contracts/new?type=msa',     icon: <ContractIcon /> },
  { key: 'create-workorder',        label: 'Work Order',       to: '/contracts/new',              icon: <NewContractIcon /> },
  { key: 'create-amendment',        label: 'Amendment',        to: '/contracts/new?type=amendment', icon: <ReportIcon /> },
  { key: 'create-project',          label: 'Project',          to: '/projects?new=1',               icon: <DashboardIcon /> },
];
```

**Rationale (icons):** Uses only icons that already exist in the file (DashboardIcon, CustomersIcon, NewContractIcon, MsaIcon, ContractIcon, QueueIcon, OnboardingIcon, AdminIcon, LocationIcon, MonitorIcon, ReportIcon — verified via grep). Each create action now has a distinct icon:
- Proposal → MsaIcon (document with lines, reads as "draft proposal")
- Vendor Agreement → ContractIcon (document with fold, reads as "signed contract")
- Work Order → NewContractIcon (document with + sign, reads as "new work")
- Amendment → ReportIcon (document with bar chart, reads as "revised report")
- Project → DashboardIcon (grid, reads as "new project workspace")

Not perfect semantically but all five are visually distinct, which resolves the UX complaint in the finding. Phase 3 can polish the icon set with dedicated glyphs.

**Sub-edit (b): Move icon declarations ABOVE CREATE_ACTIONS**

**Status:** DEFERRED — relies on JavaScript function-declaration hoisting, which works correctly today.

**Rationale (hoisting):** The finding's primary recommendation was to move the icon function declarations above CREATE_ACTIONS / NAV_GROUPS to make the dependency order explicit. However, the current code relies on JavaScript function-declaration hoisting (`function NewContractIcon() { ... }` is hoisted to the top of its enclosing scope), which is standard ES2015+ behavior and works reliably in every browser and bundler the SPA targets. Moving ~120 lines of icon functions from line 620 up above line 25 is a large mechanical refactor with non-trivial diff size and no functional benefit. The recommendedFix explicitly says "function declarations are hoisted in JavaScript so this works at runtime by accident — but it's brittle and hostile to readers". Since this batch is P1-load-bearing-only, we apply sub-edit (a) — the distinct icons fix — which addresses the user-visible UX bug, and DEFER sub-edit (b) to a future polish batch. The hoisting concern is noted and can be picked up in Phase 3 if a future refactor or bundler upgrade demands it.

**Risk (icons only):** Zero functional risk — icons are pure presentation components with no side effects, and all used components are already defined via hoisted function declarations.

**Depends on:** none

---

## Approval options

Reply with:
- `approve batch` — execute all 13 edits in the order shown (0210, 0211, 0209, 0226, 0240, 0227, 0200, 0202, 0201, 0219, 0233, 0220, 0221)
- `approve 0210,0211,0209,0226,...` — execute only listed IDs (in the order shown)
- `reject 0227` — skip that finding; execute the rest
- `reject batch` — cancel this batch entirely
- `hold` — stop, no execution yet
