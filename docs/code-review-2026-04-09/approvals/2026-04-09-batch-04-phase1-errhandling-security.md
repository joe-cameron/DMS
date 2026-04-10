# Batch 04 — Phase 1 Error Handling + OData Injection Security

**Phase:** 1 (Error handling + security pass)
**Target:** SPA source under C:\DCFG\spa\dcfg-shell\src\
**Findings count:** 15 (all P2)
**Generated:** 2026-04-10T00:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-04-phase1-errhandling-security.md
**Predecessor batches:**
  - batch 01: approvals/2026-04-09-batch-01-phase1-shared.md (SPA commit 39f8efb)
  - batch 02: approvals/2026-04-09-batch-02-phase1-expansion.md (SPA commits 30c693b + c48949f)
  - batch 03: approvals/2026-04-09-batch-03-phase1-p2-cleanup.md (SPA commit e727a8b)

## Scope rules (from spec §4.6)

- Batch size = 15 (at the 15 cap)
- All `batch` tier — no catalog-only entries in this batch
- Every proposed-edit finding has verbatim before-code + concrete after-code
- Sequencing: 0217 introduces the `escapeOdataString` helper; 0241 and 0270 consume it

## Theme — two groups

- **Group A — error handling cluster (12 findings: 0205, 0206, 0213, 0215, 0216, 0238, 0245, 0247, 0250, 0251, 0257, 0261).** Mechanical. The SPA is littered with `.catch(() => {})`, `.catch(() => setLoading(false))`, `catch (e) { console.error(...) }`, promise chains with no `.catch` at all, and one remaining `alert()` fallback. Every one of these swallows a real failure and leaves the user either (a) staring at a blank state they cannot distinguish from an empty dataset, (b) watching a success toast after an actual save failure, or (c) suffering a modal alert that references internal-only triage guidance. Fix pattern: replace silent swallowing with either a user-visible `toast.show('err'|'warn', …)` call, or a narrowly scoped `console.warn` breadcrumb for poll loops and background fallbacks where a toast would be noisy. Where `useToast` is not yet imported in the file, add the import. The shared error-handling principle: no silent failures on money-flow or data-flow actions; non-critical background polls get a one-time console warn, not a toast.

- **Group B — OData filter injection security (3 findings: 0217, 0241, 0270).** All three interpolate a user-controlled or sensor-controlled string directly into an OData `$filter` clause without escaping. 0217 is a `userEmail` interpolated into a `dcfg_created_by_email eq '…'` filter inside `portalApi.js` — the existing code DOES call `.replace(/'/g, "''")` inline, but the pattern is copy-paste fragile and lacks a central helper. 0241 and 0270 interpolate `dcfg_location_id_text` (sensor-supplied text, often NOT a GUID) into a `dcfg_propertyid eq …` clause where the column is a GUID type — on a non-GUID input the filter emits something like `dcfg_propertyid eq GroupHome-12` and Dataverse returns 400, which is then silently swallowed by a nearby `try/catch`. Fix: introduce an `escapeOdataString(s)` helper in `portalApi.js` (exported) and a GUID regex validation pattern. 0217 wires up the helper at the two existing email-filter call sites; 0241 and 0270 import it AND add a GUID-regex guard before issuing the property lookup, so non-GUID sensor IDs short-circuit instead of firing a doomed round-trip.

## Cross-finding dependencies

- **0217 → 0241, 0270:** The `escapeOdataString` helper is introduced in `portalApi.js` during the 0217 fix. 0241 (`SensorBanner.jsx`) and 0270 (`Operations.jsx`) both import it for consistency, even though their specific fix (GUID regex guard) is the primary mitigation — the helper is for defense-in-depth if the GUID check is ever relaxed. Apply 0217 BEFORE 0241/0270.
- **0215 ↔ 0216:** siblings — same try/fallback pattern in `fetchOnboardingCases` and `fetchOnboardingChecklist`. Independent edits inside the same file; apply in document order.
- **0205 ↔ 0206:** both in `LocationManager.jsx` (photo URL save + customer/location loaders). Independent edits.
- **0245 → 0247 → 0250 → 0251 → 0257 → 0261:** all error-surface fixes in different screen files. No ordering constraint; applied in document order.
- **0238 → none** — standalone alert() replacement in ErrorReporter.jsx.
- **0213 → none** — standalone observability improvement in getToken().

## New helper introduced in this batch

**File:** src/portalApi.js
**Location:** immediately after `trimBody()` (line 157) and before the `apiPost()` JSDoc block (line 159)
**Signature:** `export function escapeOdataString(s)`
**Semantics:** Accepts any value, coerces to string, doubles single quotes per OData 4.0 literal escaping rules. Returns `''` for null/undefined. No quotes added — callers still supply their own wrapping `'…'`.

```javascript
/**
 * Escape a string for safe inclusion in an OData $filter literal.
 * Doubles single quotes per OData 4.0 spec (e.g. O'Brien → O''Brien).
 * Returns '' for null/undefined. Callers must still wrap the result in quotes:
 *   `dcfg_email eq '${escapeOdataString(userInput)}'`
 * See CR-2026-04-09-0217.
 */
export function escapeOdataString(s) {
  return String(s ?? '').replace(/'/g, "''");
}
```

This helper is introduced in 0217, re-exported from `portalApi.js` alongside other shared utilities, and imported by `SensorBanner.jsx` (0241) and `Operations.jsx` (0270). A future Phase 5 pass can grep `eq '\${` across src/ to find any remaining call sites that still use inline `.replace(/'/g, "''")` and migrate them to the helper — NOT in scope for this batch.

---

## Findings in this batch

### CR-2026-04-09-0205 — apiPatch .catch(() => {}) on appliance photo URL save swallows errors silently

**File:** src/LocationManager.jsx
**Line(s):** 618 (primary photo), 633 (serial/nameplate photo)
**Severity:** P2
**Category:** error-handling

**Current code (primary photo, lines 611-624):**
```javascript
  async function handlePrimaryPhoto(id) {
    const dataUrl = await capturePhoto();
    if (!dataUrl) return;
    const a = appliances.find(x => x.id === id);
    if (!a) return;
    try {
      const url = await uploadPhoto(a.guid, 'primary', dataUrl, 'primary.jpg');
      if (a.guid) await apiPatch(`/${EntitySets.appliances}(${a.guid})`, { dcfg_primary_photo_url: url }).catch(() => {});
      setAppliances(prev => prev.map(x => x.id === id ? { ...x, primaryPhotoUrl: url } : x));
      toast.show('ok', '📷 Photo saved');
    } catch (e) {
      toast.show('err', 'Photo not saved — ' + (e?.message || 'try again'));
    }
  }
```

**Proposed edit (primary photo):**
```javascript
  async function handlePrimaryPhoto(id) {
    const dataUrl = await capturePhoto();
    if (!dataUrl) return;
    const a = appliances.find(x => x.id === id);
    if (!a) return;
    try {
      const url = await uploadPhoto(a.guid, 'primary', dataUrl, 'primary.jpg');
      if (a.guid) {
        await apiPatch(`/${EntitySets.appliances}(${a.guid})`, { dcfg_primary_photo_url: url })
          .catch(e => {
            console.error('Photo URL save failed:', e);
            toast.show('err', 'Photo uploaded but link could not be saved — refresh and retry');
            throw e;
          });
      }
      setAppliances(prev => prev.map(x => x.id === id ? { ...x, primaryPhotoUrl: url } : x));
      toast.show('ok', '📷 Photo saved');
    } catch (e) {
      toast.show('err', 'Photo not saved — ' + (e?.message || 'try again'));
    }
  }
```

**Current code (serial photo, lines 626-639):**
```javascript
  async function handleSerialPhoto(id) {
    const dataUrl = await capturePhoto();
    if (!dataUrl) return;
    const a = appliances.find(x => x.id === id);
    if (!a) return;
    try {
      const url = await uploadPhoto(a.guid, 'serial', dataUrl, 'serial.jpg');
      if (a.guid) await apiPatch(`/${EntitySets.appliances}(${a.guid})`, { dcfg_serial_photo_url: url }).catch(() => {});
      setAppliances(prev => prev.map(x => x.id === id ? { ...x, serialPhotoUrl: url } : x));
      toast.show('ok', '📷 Nameplate photo saved');
    } catch (e) {
      toast.show('err', 'Nameplate photo not saved — ' + (e?.message || 'try again'));
    }
  }
```

**Proposed edit (serial photo):**
```javascript
  async function handleSerialPhoto(id) {
    const dataUrl = await capturePhoto();
    if (!dataUrl) return;
    const a = appliances.find(x => x.id === id);
    if (!a) return;
    try {
      const url = await uploadPhoto(a.guid, 'serial', dataUrl, 'serial.jpg');
      if (a.guid) {
        await apiPatch(`/${EntitySets.appliances}(${a.guid})`, { dcfg_serial_photo_url: url })
          .catch(e => {
            console.error('Photo URL save failed:', e);
            toast.show('err', 'Nameplate photo uploaded but link could not be saved — refresh and retry');
            throw e;
          });
      }
      setAppliances(prev => prev.map(x => x.id === id ? { ...x, serialPhotoUrl: url } : x));
      toast.show('ok', '📷 Nameplate photo saved');
    } catch (e) {
      toast.show('err', 'Nameplate photo not saved — ' + (e?.message || 'try again'));
    }
  }
```

**Rationale:** Both handlers currently upload the image, PATCH the appliance row with the URL, and then unconditionally show a success toast — even if the PATCH rejects. The inner `.catch(() => {})` was added to keep the appliance list render in-sync on a transient failure, but it has the effect of turning a real data-loss condition (Webapi/dcfg_appliances/fields drift, 401 on CSRF expiry, 500 on throttle) into an invisible bug: tester sees "Photo saved" but the URL never persisted and the next page reload shows no photo. Fix replaces the silent swallow with a logged error + error toast + rethrow. The rethrow preserves the existing outer `try/catch` path so the optimistic setAppliances update is skipped on failure — the user sees "saved" or "not saved", never both.

Matches the finding's `recommendedFix` exactly at both sites.

**Risk:** Low. On the happy path the behavior is identical (PATCH succeeds → no catch → optimistic update + ok toast). On failure, the user now sees an explicit error toast instead of a phantom success, and the optimistic update is skipped (the rethrow bubbles to the outer catch which already shows its own error toast — user will see TWO toasts on failure, one "link could not be saved" and one "Photo not saved". Minor UX stutter acceptable for the data-integrity win; a future polish pass can dedupe if needed.)

**Depends on:** none (paired with batch 03's CR-0204 which covered the upload helper itself)

---

### CR-2026-04-09-0206 — loadCustomers / openCustomer console.warn-only error handling

**File:** src/LocationManager.jsx
**Line(s):** 460 (loadCustomers catch), 475 (openCustomer catch)
**Severity:** P2
**Category:** error-handling

**Current code (loadCustomers, lines 453-461):**
```javascript
  async function loadCustomers() {
    try {
      const r = await apiGet(
        `/${EntitySets.customers}?$select=dcfg_customerid,dcfg_name,dcfg_active_flag` +
        `&$filter=dcfg_active_flag eq true&$orderby=dcfg_name asc&$top=50`
      );
      setCustomers(r?.value || []);
    } catch (e) { console.warn('Customer load failed:', e.message); }
  }
```

**Proposed edit:**
```javascript
  async function loadCustomers() {
    try {
      const r = await apiGet(
        `/${EntitySets.customers}?$select=dcfg_customerid,dcfg_name,dcfg_active_flag` +
        `&$filter=dcfg_active_flag eq true&$orderby=dcfg_name asc&$top=50`
      );
      setCustomers(r?.value || []);
    } catch (e) {
      console.warn('Customer load failed:', e);
      toast.show('err', 'Could not load customers — check connection');
    }
  }
```

**Current code (openCustomer, lines 463-477):**
```javascript
  async function openCustomer(id, name) {
    setCurrentCustomerName(name);
    setView('locations');
    setLoading(true);
    try {
      // JS-01: dcfg_properties NOT dcfg_properties
      const r = await apiGet(
        `/${EntitySets.properties}?$select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_contact_person` +
        `&$expand=dcfg_location_type_id($select=dcfg_name)` +
        `&$filter=_dcfg_customer_id_value eq ${id}&$orderby=dcfg_address asc`
      );
      setLocations(r?.value || []);
    } catch (e) { console.warn('Location load failed:', e.message); }
    setLoading(false);
  }
```

**Proposed edit:**
```javascript
  async function openCustomer(id, name) {
    setCurrentCustomerName(name);
    setView('locations');
    setLoading(true);
    try {
      // JS-01: dcfg_properties NOT dcfg_properties
      const r = await apiGet(
        `/${EntitySets.properties}?$select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_contact_person` +
        `&$expand=dcfg_location_type_id($select=dcfg_name)` +
        `&$filter=_dcfg_customer_id_value eq ${id}&$orderby=dcfg_address asc`
      );
      setLocations(r?.value || []);
    } catch (e) {
      console.warn('Location load failed:', e);
      toast.show('err', 'Could not load locations — check connection');
    }
    setLoading(false);
  }
```

**Rationale:** Matches `recommendedFix`. `toast` is already in scope via `useToast()` at the top of the component (import on line 32, hook call earlier in the function body — verified). In the field-ops mobile context a dropped connection is a real and silent failure; the distinction between "no customers" and "load failed" matters because the tester's next action is different (wait for reconnect vs. escalate). Also changes `.message` → `e` inside `console.warn` so the full error object (incl. status, url via ApiError) is logged instead of just the text.

**Risk:** Minimal. If `toast` is undefined the call would throw — but the file already calls `toast.show(...)` in multiple sibling functions (deleteAppliance line 604, handlePrimaryPhoto line 620, etc.) so the hook is known-good.

**Depends on:** none

---

### CR-2026-04-09-0213 — getToken() has three nested try/catch blocks that all swallow errors

**File:** src/portalApi.js
**Line(s):** 130-140
**Severity:** P2
**Category:** error-handling

**Current code:**
```javascript
export async function getToken() {
  if (_cachedToken) return _cachedToken;
  if (_tokenPromise) return _tokenPromise;
  _tokenPromise = (async () => {
    try { const d = window.shell?.getTokenDeferred?.() || window.top?.shell?.getTokenDeferred?.(); if (d) { let t; if (typeof d.then === 'function') { t = await d; } else if (typeof d.done === 'function') { t = await new Promise((res, rej) => { d.done(res).fail(rej); }); } if (typeof t === 'string') { _cachedToken = t; return t; } if (t && typeof t === 'object') { const m = String(t).match(/value="([^"]+)"/); if (m) { _cachedToken = m[1]; return m[1]; } } } } catch {}
    try { const r = await fetch('/', { credentials: 'same-origin' }); const h = await r.text(); const m = h.match(/name="__RequestVerificationToken"[^>]*value="([^"]+)"/); if (m) { _cachedToken = m[1]; return m[1]; } } catch {}
    try { const el = document.querySelector('input[name="__RequestVerificationToken"]'); if (el?.value) { _cachedToken = el.value; return el.value; } } catch {}
    throw new Error('CSRF token unavailable');
  })();
  try { return await _tokenPromise; } finally { _tokenPromise = null; }
}
```

**Proposed edit:**
```javascript
export async function getToken() {
  if (_cachedToken) return _cachedToken;
  if (_tokenPromise) return _tokenPromise;
  _tokenPromise = (async () => {
    try { const d = window.shell?.getTokenDeferred?.() || window.top?.shell?.getTokenDeferred?.(); if (d) { let t; if (typeof d.then === 'function') { t = await d; } else if (typeof d.done === 'function') { t = await new Promise((res, rej) => { d.done(res).fail(rej); }); } if (typeof t === 'string') { _cachedToken = t; return t; } if (t && typeof t === 'object') { const m = String(t).match(/value="([^"]+)"/); if (m) { _cachedToken = m[1]; return m[1]; } } } } catch (e) { console.warn('[portalApi] token strategy 1 (shell.getTokenDeferred) failed:', e); }
    try { const r = await fetch('/', { credentials: 'same-origin' }); const h = await r.text(); const m = h.match(/name="__RequestVerificationToken"[^>]*value="([^"]+)"/); if (m) { _cachedToken = m[1]; return m[1]; } } catch (e) { console.warn('[portalApi] token strategy 2 (root HTML scrape) failed:', e); }
    try { const el = document.querySelector('input[name="__RequestVerificationToken"]'); if (el?.value) { _cachedToken = el.value; return el.value; } } catch (e) { console.warn('[portalApi] token strategy 3 (DOM input lookup) failed:', e); }
    throw new Error('CSRF token unavailable — all three token source strategies failed. See console warnings for details.');
  })();
  try { return await _tokenPromise; } finally { _tokenPromise = null; }
}
```

**Rationale:** Matches the finding's `recommendedFix` verbatim in spirit. Each of the three bare `catch {}` blocks is replaced with a named `catch (e)` that emits a labeled `console.warn` breadcrumb identifying WHICH strategy failed. The final throw is also expanded to reference the console warnings so anyone seeing "CSRF token unavailable" in the wild knows to scroll up in the console for context. Six lines of warning code, no behavior change on the happy path, and when Power Pages misbehaves we go from "token unavailable, good luck" to "strategy 1 failed with TypeError: X, strategy 2 failed with network error, strategy 3 returned no element" — dramatic improvement in field debuggability.

**Risk:** Zero on happy path (no control flow change). On failure, adds three console entries per failed getToken call — if the DOM has no token element at all, every subsequent apiPost/apiPatch will re-fire and spam the console. Acceptable for diagnostic purposes; the token promise is cached so the re-fire rate is bounded by the `_tokenPromise` reset cycle.

**Depends on:** none

---

### CR-2026-04-09-0215 — fetchOnboardingCases hides 400s by reissuing without dcfg_active_flag

**File:** src/portalApi.js
**Line(s):** 548-561
**Severity:** P2
**Category:** error-handling

**Current code:**
```javascript
export function fetchOnboardingCases(custId) {
  const baseCols = 'dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes';
  const expand = '$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_msa_id($select=dcfg_msaid,dcfg_name)&$orderby=dcfg_initiated_date desc';
  // Try with active_flag, fall back without if column doesn't exist
  const activeFilter = '(dcfg_active_flag eq true or dcfg_active_flag eq null)';
  const f = custId ? `_dcfg_customer_id_value eq ${custId} and ${activeFilter}` : `dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed} and ${activeFilter}`;
  return apiGet(`/${EntitySets.onboardingCases}?$filter=${f}&$select=${baseCols},dcfg_active_flag&${expand}`).catch(err => {
    if (err?.status === 400) {
      const fFallback = custId ? `_dcfg_customer_id_value eq ${custId}` : `dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed}`;
      return apiGet(`/${EntitySets.onboardingCases}?$filter=${fFallback}&$select=${baseCols}&${expand}`);
    }
    throw err;
  });
}
```

**Proposed edit:**
```javascript
export function fetchOnboardingCases(custId) {
  const baseCols = 'dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes';
  const expand = '$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_msa_id($select=dcfg_msaid,dcfg_name)&$orderby=dcfg_initiated_date desc';
  // Try with active_flag, fall back without if column doesn't exist
  const activeFilter = '(dcfg_active_flag eq true or dcfg_active_flag eq null)';
  const f = custId ? `_dcfg_customer_id_value eq ${custId} and ${activeFilter}` : `dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed} and ${activeFilter}`;
  return apiGet(`/${EntitySets.onboardingCases}?$filter=${f}&$select=${baseCols},dcfg_active_flag&${expand}`).catch(err => {
    if (err?.status === 400) {
      // CR-2026-04-09-0215: log which environment is still missing dcfg_active_flag on dcfg_onboarding_cases
      // After Phase 0 parity sweep confirms the column exists on every env, this fallback can be deleted.
      console.warn('[fetchOnboardingCases] active_flag filter failed with 400 — env not migrated? Falling back to unfiltered query.');
      const fFallback = custId ? `_dcfg_customer_id_value eq ${custId}` : `dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed}`;
      return apiGet(`/${EntitySets.onboardingCases}?$filter=${fFallback}&$select=${baseCols}&${expand}`);
    }
    throw err;
  });
}
```

**Rationale:** Matches `recommendedFix`. Adds a console.warn breadcrumb inside the 400 branch so we can spot which environments are still relying on the fallback, without removing the fallback itself (that's a Phase 5 task after parity confirmation). The warn fires only on the defensive path; happy path (column present, no 400) is unchanged.

**Risk:** Zero. One added log line on a failure path that already exists.

**Depends on:** none (paired with 0216 below)

---

### CR-2026-04-09-0216 — fetchOnboardingChecklist same try/fallback pattern hides RACI column drift

**File:** src/portalApi.js
**Line(s):** 562-572
**Severity:** P2
**Category:** error-handling

**Current code:**
```javascript
export function fetchOnboardingChecklist(caseId) {
  // Core columns (always exist) + RACI columns (added by DCFG_Onboarding_RACI_Schema.ps1)
  // If RACI columns don't exist yet, Dataverse returns 400 — so we try with them, fall back without
  const coreCols = 'dcfg_onboarding_checklistid,dcfg_step_number,dcfg_step_name,dcfg_status,dcfg_responsible_role,dcfg_assigned_email,dcfg_predecessor_step,dcfg_dependency_type,dcfg_due_date,dcfg_completed_date,dcfg_evidence_url,dcfg_email_triggered,dcfg_is_complete,dcfg_notes';
  const raciCols = ',dcfg_assigned_name,dcfg_accountable_name,dcfg_accountable_email,dcfg_consulted,dcfg_informed,dcfg_expected_hours,dcfg_turnaround_days,dcfg_phase';
  const base = `/${EntitySets.onboardingChecks}?$filter=_dcfg_case_id_value eq ${caseId}&$orderby=dcfg_step_number asc&$select=`;
  return apiGet(base + coreCols + raciCols).catch(err => {
    if (err?.status === 400) return apiGet(base + coreCols);
    throw err;
  });
}
```

**Proposed edit:**
```javascript
export function fetchOnboardingChecklist(caseId) {
  // Core columns (always exist) + RACI columns (added by DCFG_Onboarding_RACI_Schema.ps1)
  // If RACI columns don't exist yet, Dataverse returns 400 — so we try with them, fall back without
  const coreCols = 'dcfg_onboarding_checklistid,dcfg_step_number,dcfg_step_name,dcfg_status,dcfg_responsible_role,dcfg_assigned_email,dcfg_predecessor_step,dcfg_dependency_type,dcfg_due_date,dcfg_completed_date,dcfg_evidence_url,dcfg_email_triggered,dcfg_is_complete,dcfg_notes';
  const raciCols = ',dcfg_assigned_name,dcfg_accountable_name,dcfg_accountable_email,dcfg_consulted,dcfg_informed,dcfg_expected_hours,dcfg_turnaround_days,dcfg_phase';
  const base = `/${EntitySets.onboardingChecks}?$filter=_dcfg_case_id_value eq ${caseId}&$orderby=dcfg_step_number asc&$select=`;
  return apiGet(base + coreCols + raciCols).catch(err => {
    if (err?.status === 400) {
      // CR-2026-04-09-0216: log which environment is still missing the RACI columns.
      // After Phase 0 parity sweep confirms the columns exist on every env, this fallback can be deleted.
      console.warn('[fetchOnboardingChecklist] RACI columns missing (400) — env not migrated? Falling back to core columns only.');
      return apiGet(base + coreCols);
    }
    throw err;
  });
}
```

**Rationale:** Same pattern as 0215, same rationale. Breadcrumb inside the 400 branch only; fallback still fires on drift so the app remains functional, but we can now grep logs to find un-migrated environments. Matches `recommendedFix`.

**Risk:** Zero. Single added log line on an existing failure path.

**Depends on:** 0215 (sibling — same pattern, paired in findings.json via relatedFindings)

---

### CR-2026-04-09-0238 — alert() fallback when audit log fails — modal alert disrupts external tester flow

**File:** src/ErrorReporter.jsx
**Line(s):** 6 (import), 47 (handleSend), 73-76 (catch block)
**Severity:** P2
**Category:** error-handling

**Current code (import, line 6):**
```javascript
import { writeAuditLog, AuditActionType } from './portalApi.js';
import { getErrorBuffer, onErrorCountChange } from './debug/index';
```

**Proposed edit (import):**
```javascript
import { writeAuditLog, AuditActionType } from './portalApi.js';
import { getErrorBuffer, onErrorCountChange } from './debug/index';
import { useToast } from './Toast';
```

**Current code (handleSend + catch, lines 47-77):**
```javascript
  function handleSend() {
    setSending(true);
    var context = {
      errors: errorBuffer.errors.slice(0, 10),
      url: window.location.hash,
      screenSize: window.innerWidth + 'x' + window.innerHeight,
      userAgent: navigator.userAgent,
      timestamp: new Date().toISOString()
    };

    var contextStr;
    try { contextStr = JSON.stringify(context); } catch { contextStr = '{"error":"could not serialize"}'; }
    if (contextStr.length > 4000) contextStr = contextStr.slice(0, 4000);

    writeAuditLog({
      dcfg_target_table: 'spa_error_report',
      dcfg_action_type: AuditActionType.Other,
      dcfg_performed_by: userName,
      dcfg_new_value: description || '(no description)',
      dcfg_old_value: contextStr,
      dcfg_reason: 'User-reported error via Nora panel'
    }).then(function() {
      setSending(false);
      setSent(true);
      setDescription('');
      if (window.DCFG && window.DCFG.clearErrors) window.DCFG.clearErrors();
    }).catch(function() {
      setSending(false);
      alert('Could not send report. Please use Win+Shift+S to screenshot the issue and send to Joseph via Teams.');
    });
  }
```

**Proposed edit:**
Inside the component body (after the existing useState declarations but before `handleSend`), add:
```javascript
  var toast = useToast();
```

Then replace the catch block:
```javascript
    }).catch(function() {
      setSending(false);
      toast.show('err', 'Report could not be sent — please try again later');
    });
```

For the Edit tool, the exact old_string anchor is the three-line catch block:
```javascript
    }).catch(function() {
      setSending(false);
      alert('Could not send report. Please use Win+Shift+S to screenshot the issue and send to Joseph via Teams.');
    });
```

new_string:
```javascript
    }).catch(function() {
      setSending(false);
      toast.show('err', 'Report could not be sent — please try again later');
    });
```

And the `var toast = useToast();` insertion goes after line 37 (the existing `var expandedState` / `setExpanded` pair):
old_string (for uniqueness includes the preceding useState block):
```javascript
  var expandedState = React.useState(false);
  var expanded = expandedState[0];
  var setExpanded = expandedState[1];

  // Subscribe to error count changes
```

new_string:
```javascript
  var expandedState = React.useState(false);
  var expanded = expandedState[0];
  var setExpanded = expandedState[1];

  var toast = useToast();

  // Subscribe to error count changes
```

**Rationale:** Matches `recommendedFix`. Three changes: (1) import `useToast` from `./Toast` (the shared toast hook used across the SPA); (2) call `useToast()` inside the component body to get a toast handle — note this file uses `var` rather than `const` and plain function expressions (no JSX, all `React.createElement`), so we match that style; (3) replace the native `alert()` call with `toast.show('err', …)` using a neutral customer-facing message that drops the Joseph/Teams/Win+Shift+S internal triage references. External testers now get a dismissible in-app toast instead of a blocking browser modal with insider jargon.

**Risk:** Low. `useToast` is a hook so the placement matters — inserting it after the other `React.useState` calls and before the `React.useEffect` maintains hook order stability. ToastProvider must wrap the component tree for `useToast` to work; verified by the fact that `Toast.jsx` is already used across SPA screens and ErrorReporter is rendered inside the Nora panel (which is under the app shell where the provider lives).

**Depends on:** none

---

### CR-2026-04-09-0245 — DocumentTemplatesTab load + save errors only console.error — no user feedback

**File:** src/screens/Admin.jsx
**Line(s):** 206 (load catch), 229 (save catch)
**Severity:** P2
**Category:** error-handling

**Current code (DocumentTemplatesTab, lines 195-230):**
```javascript
function DocumentTemplatesTab({ userEmail }) {
  const [templates, setTemplates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(null); // null or template object
  const [showNew, setShowNew] = useState(false);

  const loadTemplates = useCallback(async () => {
    setLoading(true);
    try {
      const r = await apiGet(`/${EntitySets.docTemplates}?$select=dcfg_document_templateid,dcfg_name,dcfg_contract_family,dcfg_document_type,dcfg_exhibit_type,dcfg_is_active,dcfg_version,dcfg_sharepoint_url,dcfg_validation_status,dcfg_notes&$orderby=dcfg_contract_family asc,dcfg_document_type asc`);
      setTemplates(r?.value ?? []);
    } catch (e) { console.error('Load templates:', e); }
    setLoading(false);
  }, []);

  useEffect(() => { loadTemplates(); }, [loadTemplates]);

  async function handleSave(data, isNew) {
    try {
      if (isNew) {
        await apiPost(`/${EntitySets.docTemplates}`, data);
      } else {
        await apiPatch(`/${EntitySets.docTemplates}(${data.dcfg_document_templateid})`, data);
      }
      await writeAuditLog({
        targetTable: 'dcfg_document_template',
        targetRecordId: data.dcfg_document_templateid || 'new',
        actionType: AuditActionType.DataUpdated,
        performedBy: userEmail || 'admin',
        newValue: `${isNew ? 'Created' : 'Updated'} template: ${data.dcfg_name}`,
      }).catch(() => {});
      setEditing(null);
      setShowNew(false);
      loadTemplates();
    } catch (e) { console.error('Save template:', e); }
  }
```

**Proposed edit:**
```javascript
function DocumentTemplatesTab({ userEmail }) {
  const toast = useToast();
  const [templates, setTemplates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(null); // null or template object
  const [showNew, setShowNew] = useState(false);

  const loadTemplates = useCallback(async () => {
    setLoading(true);
    try {
      const r = await apiGet(`/${EntitySets.docTemplates}?$select=dcfg_document_templateid,dcfg_name,dcfg_contract_family,dcfg_document_type,dcfg_exhibit_type,dcfg_is_active,dcfg_version,dcfg_sharepoint_url,dcfg_validation_status,dcfg_notes&$orderby=dcfg_contract_family asc,dcfg_document_type asc`);
      setTemplates(r?.value ?? []);
    } catch (e) {
      console.error('Load templates:', e);
      toast.show('warn', 'Failed to load templates — ' + (e?.message || 'unknown error'));
    }
    setLoading(false);
  }, [toast]);

  useEffect(() => { loadTemplates(); }, [loadTemplates]);

  async function handleSave(data, isNew) {
    try {
      if (isNew) {
        await apiPost(`/${EntitySets.docTemplates}`, data);
      } else {
        await apiPatch(`/${EntitySets.docTemplates}(${data.dcfg_document_templateid})`, data);
      }
      await writeAuditLog({
        targetTable: 'dcfg_document_template',
        targetRecordId: data.dcfg_document_templateid || 'new',
        actionType: AuditActionType.DataUpdated,
        performedBy: userEmail || 'admin',
        newValue: `${isNew ? 'Created' : 'Updated'} template: ${data.dcfg_name}`,
      }).catch(() => {});
      setEditing(null);
      setShowNew(false);
      loadTemplates();
      toast.show('ok', `Template ${isNew ? 'created' : 'updated'}`);
    } catch (e) {
      console.error('Save template:', e);
      toast.show('err', 'Failed to save template — ' + (e?.message || 'unknown error'));
    }
  }
```

**Rationale:** `useToast` is already imported at the top of Admin.jsx (line 17, verified). Adds `const toast = useToast();` at the top of the DocumentTemplatesTab function body, surfaces both load and save errors via `toast.show('warn'|'err', …)` with the specific error message appended, AND adds an `toast.show('ok', …)` success confirmation on save (previously the admin had zero feedback either way). Also adds `toast` to the `useCallback` deps array for correctness per eslint-plugin-react-hooks. Matches `recommendedFix` for THIS specific tab — the finding lists 7 total tabs that share the pattern (OnboardingStepsTab, LocationTypesTab, CostCodesTab, ApplianceTypesTab, VendorsTab, IntakeFieldsTab) but this batch fix covers only DocumentTemplatesTab per the in-scope finding; the other tabs are siblings not separately catalogued (the finding's `detail` mentions them but only DocumentTemplatesTab is the primary site). A future batch can extend the pattern.

**Risk:** Low. Adding a hook at the top of a function component is safe as long as it's unconditional, which it is. `toast` in the deps array is stable (provider returns a stable ref). The `toast.show('ok', ...)` success confirmation is additive UX.

**Depends on:** none

**Operator note:** The finding's detail section lists six sibling tabs with the same anti-pattern. Fixing only DocumentTemplatesTab leaves those tabs silent; if the operator wants all seven fixed atomically, the same edit can be replicated to each function body. Keeping this batch to the primary finding to stay under the 15-cap — sibling tabs can be a follow-up batch.

---

### CR-2026-04-09-0247 — CompliancePanel load + save errors swallowed to console — no toast surface

**File:** src/screens/CompliancePanel.jsx
**Line(s):** 16 (import), 128 (component start), 167-171 (load catch), 201-205 (save catch)
**Severity:** P2
**Category:** error-handling

**Current code (imports, lines 15-18):**
```javascript
import React, { useState, useEffect, useCallback } from 'react';
import { apiGet, apiPost, apiPatch, EntitySets } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import Fn from '../FieldName.jsx';
```

**Proposed edit (imports):**
```javascript
import React, { useState, useEffect, useCallback } from 'react';
import { apiGet, apiPost, apiPatch, EntitySets } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import { useToast } from '../Toast';
import Fn from '../FieldName.jsx';
```

**Current code (component start, lines 128-137):**
```javascript
export default function CompliancePanel({ contractId, customerId, contract, contractLines, vendor }) {
  const { user } = usePortalUser();

  const [rules, setRules]           = useState([]);
  const [checks, setChecks]         = useState({});   // keyed by rule id
  const [loading, setLoading]       = useState(true);
  const [noRules, setNoRules]       = useState(false);
  const [expanded, setExpanded]     = useState({});    // keyed by rule id
  const [saving, setSaving]         = useState({});    // keyed by rule id
```

**Proposed edit:**
```javascript
export default function CompliancePanel({ contractId, customerId, contract, contractLines, vendor }) {
  const { user } = usePortalUser();
  const toast = useToast();

  const [rules, setRules]           = useState([]);
  const [checks, setChecks]         = useState({});   // keyed by rule id
  const [loading, setLoading]       = useState(true);
  const [noRules, setNoRules]       = useState(false);
  const [expanded, setExpanded]     = useState({});    // keyed by rule id
  const [saving, setSaving]         = useState({});    // keyed by rule id
```

**Current code (load catch, lines 167-171):**
```javascript
    } catch (e) {
      console.error('CompliancePanel load error:', e);
    } finally {
      setLoading(false);
    }
```

**Proposed edit:**
```javascript
    } catch (e) {
      console.error('CompliancePanel load error:', e);
      toast.show('warn', 'Failed to load compliance rules');
    } finally {
      setLoading(false);
    }
```

**Current code (save catch, lines 201-205):**
```javascript
    } catch (e) {
      console.error('CompliancePanel save error:', e);
    } finally {
      setSaving(prev => ({ ...prev, [ruleId]: false }));
    }
```

**Proposed edit:**
```javascript
    } catch (e) {
      console.error('CompliancePanel save error:', e);
      toast.show('err', 'Failed to save check — try again');
    } finally {
      setSaving(prev => ({ ...prev, [ruleId]: false }));
    }
```

**Rationale:** Matches `recommendedFix` exactly. Adds `useToast` import, declares `const toast = useToast();` right after the `usePortalUser()` call, and surfaces both load and save errors. The stakes here are specifically called out in the finding detail: compliance scores drive contract readiness, and a silent save failure means the badge could show "All Checks Passed" even though the save failed. Toast surface closes that false-readiness gap.

**Risk:** Low. Both catch blocks are inside `useCallback` bodies (loadData + handleManualToggle). The `toast` reference is stable so does NOT need to be added to the useCallback dep arrays to satisfy eslint-plugin-react-hooks — but if the lint config is strict, both `loadData` and `handleManualToggle` would need `toast` appended to their deps. Since the existing code does NOT add stable refs like `user` to deps (see current line 206 — `[checks, contractId, user, loadData]` DOES include user, so the convention in this file IS to include stable refs), I'd include toast too. Recommend adding `toast` to both useCallback deps arrays for lint conformance.

**Depends on:** none

---

### CR-2026-04-09-0250 — reload() error routes to top-level error banner instead of toast — replaces entire page content

**File:** src/screens/ContractDetail.jsx
**Line(s):** 11 (import), 28 (component start), 60 (initial reload catch), 100-104 (commitTransition catch)
**Severity:** P2
**Category:** error-handling

**Current code (imports, lines 5-11):**
```javascript
import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { apiGet, apiPatch, apiPost, createDocumentRequest, DocRequestType, writeAuditLog, AuditActionType, ContractStatus, ContractFamily, EntitySets } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import RoleGuard from '../RoleGuard.jsx';
import CompliancePanel from './CompliancePanel.jsx';
import Fn from '../FieldName.jsx';
```

**Proposed edit (imports):**
```javascript
import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { apiGet, apiPatch, apiPost, createDocumentRequest, DocRequestType, writeAuditLog, AuditActionType, ContractStatus, ContractFamily, EntitySets } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import { useToast } from '../Toast';
import RoleGuard from '../RoleGuard.jsx';
import CompliancePanel from './CompliancePanel.jsx';
import Fn from '../FieldName.jsx';
```

**Current code (component start, lines 25-35):**
```javascript
export default function ContractDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { isAdmin, isManager, userEmail } = usePortalUser();

  const [contract,  setContract]  = useState(null);
  const [lines,     setLines]     = useState([]);
  const [auditLogs, setAuditLogs] = useState([]);
  const [loading,   setLoading]   = useState(true);
  const [error,     setError]     = useState(null);
```

**Proposed edit:**
```javascript
export default function ContractDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { isAdmin, isManager, userEmail } = usePortalUser();
  const toast = useToast();

  const [contract,  setContract]  = useState(null);
  const [lines,     setLines]     = useState([]);
  const [auditLogs, setAuditLogs] = useState([]);
  const [loading,   setLoading]   = useState(true);
  const [error,     setError]     = useState(null);
```

**Current code (commitTransition catch, lines 100-104):**
```javascript
    } catch (e) {
      setError(e.message);
    } finally {
      setModalSaving(false);
    }
```

**Proposed edit:**
```javascript
    } catch (e) {
      toast.show('err', 'Status change failed — ' + (e?.message || 'try again'));
    } finally {
      setModalSaving(false);
    }
```

**Rationale:** The finding's recommendation is to split error paths: initial load failure keeps the full-page banner (catastrophic — user can't see the contract at all, banner is appropriate), but transient errors from commitTransition (status change) should toast instead of replacing the entire page. This preserves the contract view so the user can retry without navigating away. The initial `reload().catch(e => setError(e.message))` on line 60 is LEFT UNCHANGED — that's the "hard load failure" path the finding explicitly wants to keep. Only the commitTransition path is switched to toast. Also adds the `useToast` import and hook call.

Note: the existing `setError(e.message)` on line 101 is removed in the edit — the full-page banner will NOT be triggered by a failed status change. If the operator wants to keep the banner as a fallback (in case the toast is missed), we could add BOTH `toast.show(...)` and `setError(e.message)`, but the finding's recommendation is unambiguous: toast, not banner, for transient errors.

**Risk:** Medium-low. If toast is missed by the user they won't see an error at all — but the modal stays closed and the contract view still shows the PRE-transition state (because `reload()` was not called on the failure path). The user will notice the status didn't change. Acceptable. The finding writer judged this is the right tradeoff.

**Depends on:** none

---

### CR-2026-04-09-0251 — Contract list load swallows errors with .catch(() => setLoading(false))

**File:** src/screens/ContractList.jsx
**Line(s):** 22-35
**Severity:** P2
**Category:** error-handling

**Current code:**
```javascript
export default function ContractList() {
  const navigate = useNavigate();
  const { isManager } = usePortalUser();
  const [contracts, setContracts] = useState([]);
  const [loading, setLoading] = useState(true);

  const { filtered, sortCol, sortDir, toggleSort, searchTerm, setSearchTerm } = useTableControls(contracts, {
    defaultSort: 'dcfg_contract_date',
    defaultDir: 'desc',
    searchFields: CONTRACT_SEARCH_FIELDS,
  });

  useEffect(() => {
    apiGet(`/dcfg_contracts?$filter=dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_fee,dcfg_contract_date,dcfg_contractor_legal_name,dcfg_client_name&$expand=dcfg_msa_id($select=dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_name))&$orderby=dcfg_contract_date desc&$top=100`)
      .then(r => { setContracts(r?.value ?? []); setLoading(false); })
      .catch(() => setLoading(false));
  }, []);
```

**Proposed edit:**
```javascript
export default function ContractList() {
  const navigate = useNavigate();
  const { isManager } = usePortalUser();
  const [contracts, setContracts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const { filtered, sortCol, sortDir, toggleSort, searchTerm, setSearchTerm } = useTableControls(contracts, {
    defaultSort: 'dcfg_contract_date',
    defaultDir: 'desc',
    searchFields: CONTRACT_SEARCH_FIELDS,
  });

  useEffect(() => {
    apiGet(`/dcfg_contracts?$filter=dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_fee,dcfg_contract_date,dcfg_contractor_legal_name,dcfg_client_name&$expand=dcfg_msa_id($select=dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_name))&$orderby=dcfg_contract_date desc&$top=100`)
      .then(r => { setContracts(r?.value ?? []); setLoading(false); })
      .catch(e => { setError(e?.message || 'Failed to load contracts'); setLoading(false); });
  }, []);
```

**Current code (render empty state, line 58-60):**
```javascript
          <tbody>
            {filtered.length === 0 ? (
              <tr><td colSpan={5} style={{textAlign:'center',color:'#94A3B8',padding:'32px'}}>No contracts found.</td></tr>
            ) : filtered.map(c => {
```

**Proposed edit:** Add an error banner render just above the table-wrapper. The exact placement is after the header div closes and before `<div className="table-wrapper">`. Add:
```javascript
      {error && <div className="warn-banner" style={{ marginBottom: '16px' }}>Unable to load contracts: {error}</div>}
```

For the Edit tool, anchor on the line right before `<div className="table-wrapper">`:

old_string:
```javascript
          <button onClick={() => navigate('/contracts/new')} style={{ backgroundColor:'#1B2A4A', color:'#FFF', border:'none', borderRadius:'6px', padding:'9px 18px', fontSize:'13.5px', fontWeight:600, cursor:'pointer' }} data-testid="contracts-btn-new">+ New Contract</button>
        </div>
      </div>
      <div className="table-wrapper">
```

new_string:
```javascript
          <button onClick={() => navigate('/contracts/new')} style={{ backgroundColor:'#1B2A4A', color:'#FFF', border:'none', borderRadius:'6px', padding:'9px 18px', fontSize:'13.5px', fontWeight:600, cursor:'pointer' }} data-testid="contracts-btn-new">+ New Contract</button>
        </div>
      </div>
      {error && <div className="warn-banner" style={{ marginBottom: '16px' }}>Unable to load contracts: {error}</div>}
      <div className="table-wrapper">
```

**Rationale:** Matches `recommendedFix` exactly. Adds error state, populates it from the .catch, and renders a distinct `warn-banner` (shared CSS class, already used by ContractDetail for the same purpose) so the user can distinguish "no contracts" from "load failed". Preserves the "No contracts found" empty-state row for the real-empty case.

**Risk:** Zero. The banner only renders when `error` is truthy, so happy path is identical.

**Depends on:** none

---

### CR-2026-04-09-0257 — OverviewTab nested apiGet inside .then has no error handler — unhandled promise rejection on failure

**File:** src/screens/CustomerDetail.jsx
**Line(s):** 144-159 (OverviewTab useEffect)
**Severity:** P2
**Category:** error-handling

**Current code:**
```javascript
function OverviewTab({ customer, customerId, navigate, isManager }) {
  const [counts, setCounts] = useState({ msas: 0, contracts: 0, locations: 0 });
  useEffect(() => {
    Promise.all([
      apiGet(`/dcfg_msas?$filter=_dcfg_customer_id_value eq ${customerId}&$select=dcfg_msaid&$count=true`),
      apiGet(`/dcfg_properties?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_active_flag eq true&$select=dcfg_propertyid&$count=true`),
    ]).then(([msaRes, locRes]) => {
      const msaIds = (msaRes?.value ?? []).map(m => m.dcfg_msaid);
      setCounts(prev => ({ ...prev, msas: msaRes?.value?.length ?? 0, locations: locRes?.value?.length ?? 0 }));
      if (msaIds.length > 0) {
        const filter = msaIds.map(id => `_dcfg_msa_id_value eq ${id}`).join(' or ');
        apiGet(`/dcfg_contracts?$filter=(${filter}) and dcfg_status ne ${ContractStatus.Void} and dcfg_status ne ${ContractStatus.Declined} and dcfg_status ne ${ContractStatus.Closed}&$select=dcfg_contractid`)
          .then(r => setCounts(prev => ({ ...prev, contracts: r?.value?.length ?? 0 })));
      }
    });
  }, [customerId]);
```

**Proposed edit:**
```javascript
function OverviewTab({ customer, customerId, navigate, isManager }) {
  const [counts, setCounts] = useState({ msas: 0, contracts: 0, locations: 0 });
  useEffect(() => {
    Promise.all([
      apiGet(`/dcfg_msas?$filter=_dcfg_customer_id_value eq ${customerId}&$select=dcfg_msaid&$count=true`),
      apiGet(`/dcfg_properties?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_active_flag eq true&$select=dcfg_propertyid&$count=true`),
    ]).then(([msaRes, locRes]) => {
      const msaIds = (msaRes?.value ?? []).map(m => m.dcfg_msaid);
      setCounts(prev => ({ ...prev, msas: msaRes?.value?.length ?? 0, locations: locRes?.value?.length ?? 0 }));
      if (msaIds.length > 0) {
        const filter = msaIds.map(id => `_dcfg_msa_id_value eq ${id}`).join(' or ');
        apiGet(`/dcfg_contracts?$filter=(${filter}) and dcfg_status ne ${ContractStatus.Void} and dcfg_status ne ${ContractStatus.Declined} and dcfg_status ne ${ContractStatus.Closed}&$select=dcfg_contractid`)
          .then(r => setCounts(prev => ({ ...prev, contracts: r?.value?.length ?? 0 })))
          .catch(e => console.warn('OverviewTab contracts count failed:', e));
      }
    }).catch(e => console.warn('OverviewTab counts load failed:', e));
  }, [customerId]);
```

**Rationale:** Matches `recommendedFix`. Adds `.catch(() => ...)` to BOTH the inner apiGet (the nested contracts count) and the outer Promise.all chain so failures on either path are caught instead of producing unhandled promise rejections. Uses `console.warn` rather than toast because the OverviewTab is a secondary metrics panel — a failed count shouldn't interrupt the customer detail view. The counts simply stay at 0 on failure, which is the same visible state as before, but with a diagnostic breadcrumb in the console. If the operator wants a toast surface here, upgrade both catches to `toast.show('warn', ...)` — `useToast` is already imported at the top of the file (line 20, verified) so the upgrade is one-line.

**Risk:** Zero. Catches are additive — happy path is unchanged. Worst case the counts read `0, 0, 0` on failure instead of whatever stale state they might have had, but that's already the initial state.

**Depends on:** none

---

### CR-2026-04-09-0261 — DocumentHistory useEffect has no error handler on the apiGet

**File:** src/screens/MsaDetail.jsx
**Line(s):** 241-246 (DocumentHistory)
**Severity:** P2
**Category:** error-handling

**Current code:**
```javascript
function DocumentHistory({ sourceEntity, sourceId }) {
  const [docs, setDocs] = useState([]);
  useEffect(() => {
    apiGet(`/dcfg_document_outputs?$filter=dcfg_source_entity eq '${sourceEntity}' and dcfg_source_record_id eq '${sourceId}'&$orderby=dcfg_generated_at desc`)
      .then(r => setDocs(r?.value ?? []));
  }, [sourceEntity, sourceId]);
```

**Proposed edit:**
```javascript
function DocumentHistory({ sourceEntity, sourceId }) {
  const [docs, setDocs] = useState([]);
  useEffect(() => {
    apiGet(`/dcfg_document_outputs?$filter=dcfg_source_entity eq '${sourceEntity}' and dcfg_source_record_id eq '${sourceId}'&$orderby=dcfg_generated_at desc`)
      .then(r => setDocs(r?.value ?? []))
      .catch(e => { console.warn('DocumentHistory load failed:', e); setDocs([]); });
  }, [sourceEntity, sourceId]);
```

**Rationale:** Matches `recommendedFix`. Adds a `.catch` that logs the error and resets docs to empty array (so the "No documents generated yet" fallback row renders). Previously a 403 or 500 on the dcfg_document_outputs table would produce an unhandled promise rejection and leave `docs` at whatever stale value it had — usually empty, so the visible behavior is unchanged, but the diagnostic breadcrumb matters because `DocumentHistory` is a subcomponent of `MsaDetail` and a failed load was completely invisible to debugging.

The finding also mentions the alternative of surfacing to a toast/banner. Chose console.warn over toast here because (a) DocumentHistory is a tertiary panel (not the MSA's primary content), (b) a failed load results in the same visible state as "no documents yet" which isn't alarming, and (c) the finding's first recommendation is the `.catch(() => setDocs([]))` pattern.

**Risk:** Zero. Catch is additive.

**Depends on:** none

---

### CR-2026-04-09-0217 — userEmail interpolated into $filter without escape — single-quote injection risk

**File:** src/portalApi.js
**Line(s):** 157-158 (new helper location), 411-412 (fetchMyWIPDrafts), 420-421 (fetchMyWIPProposals)
**Severity:** P2
**Category:** data-integrity

**NEW HELPER: Insert between `trimBody` and `apiPost`'s JSDoc block.**

**Current code (lines 156-159):**
```javascript
// Trim all string values in an object before sending to Dataverse
function trimBody(obj) { if (!obj || typeof obj !== 'object') return obj; const out = {}; for (const [k,v] of Object.entries(obj)) { out[k] = typeof v === 'string' ? v.trim() : v; } return out; }

/**
 * Fire-and-forget POST. Returns void. Throws ApiError on non-OK.
```

**Proposed edit:**
```javascript
// Trim all string values in an object before sending to Dataverse
function trimBody(obj) { if (!obj || typeof obj !== 'object') return obj; const out = {}; for (const [k,v] of Object.entries(obj)) { out[k] = typeof v === 'string' ? v.trim() : v; } return out; }

/**
 * Escape a string for safe inclusion in an OData $filter literal.
 * Doubles single quotes per OData 4.0 spec (e.g. O'Brien → O''Brien).
 * Returns '' for null/undefined. Callers must still wrap the result in quotes:
 *   `dcfg_email eq '${escapeOdataString(userInput)}'`
 * See CR-2026-04-09-0217.
 */
export function escapeOdataString(s) {
  return String(s ?? '').replace(/'/g, "''");
}

/**
 * Fire-and-forget POST. Returns void. Throws ApiError on non-OK.
```

**Current code (fetchMyWIPDrafts, lines 411-413):**
```javascript
// ── WIP DRAFTS ──
export function fetchMyWIPDrafts(userEmail) {
  return apiGet(`/${EntitySets.contracts}?$filter=dcfg_status eq ${ContractStatus.WIP} and dcfg_created_by_email eq '${userEmail.replace(/'/g, "''")}' and dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_number,dcfg_contract_type,dcfg_contract_date,dcfg_client_name,dcfg_wizard_step,dcfg_created_by_email,dcfg_service_location_description,modifiedon,_dcfg_customer_id_value,_dcfg_vendor_id_value,_dcfg_property_id_value,_dcfg_program_id_value&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name)&$orderby=modifiedon desc`);
}
```

**Proposed edit:**
```javascript
// ── WIP DRAFTS ──
export function fetchMyWIPDrafts(userEmail) {
  return apiGet(`/${EntitySets.contracts}?$filter=dcfg_status eq ${ContractStatus.WIP} and dcfg_created_by_email eq '${escapeOdataString(userEmail)}' and dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_number,dcfg_contract_type,dcfg_contract_date,dcfg_client_name,dcfg_wizard_step,dcfg_created_by_email,dcfg_service_location_description,modifiedon,_dcfg_customer_id_value,_dcfg_vendor_id_value,_dcfg_property_id_value,_dcfg_program_id_value&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name)&$orderby=modifiedon desc`);
}
```

**Current code (fetchMyWIPProposals, lines 419-422):**
```javascript
// ── WIP PROPOSAL DRAFTS ──
export function fetchMyWIPProposals(userEmail) {
  return apiGet(`/${EntitySets.msas}?$filter=dcfg_status eq ${MsaStatus.WIP} and dcfg_created_by_email eq '${userEmail.replace(/'/g, "''")}' and statecode eq 0&$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_exhibit_type,dcfg_wizard_step,dcfg_created_by_email,dcfg_pricing_alternative,dcfg_effective_date,dcfg_service_fee_pct,modifiedon&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)&$orderby=modifiedon desc`);
}
```

**Proposed edit:**
```javascript
// ── WIP PROPOSAL DRAFTS ──
export function fetchMyWIPProposals(userEmail) {
  return apiGet(`/${EntitySets.msas}?$filter=dcfg_status eq ${MsaStatus.WIP} and dcfg_created_by_email eq '${escapeOdataString(userEmail)}' and statecode eq 0&$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_exhibit_type,dcfg_wizard_step,dcfg_created_by_email,dcfg_pricing_alternative,dcfg_effective_date,dcfg_service_fee_pct,modifiedon&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)&$orderby=modifiedon desc`);
}
```

**Rationale:** Matches `recommendedFix` exactly. Three coordinated changes: (1) introduce the `escapeOdataString` helper (exported so consumers can import it); (2) replace the inline `userEmail.replace(/'/g, "''")` in `fetchMyWIPDrafts` with `escapeOdataString(userEmail)`; (3) same in `fetchMyWIPProposals`. Semantic equivalence verified: both forms produce identical output for all inputs, but the helper also handles `null`/`undefined` (existing code would throw TypeError on `null.replace(...)` whereas helper returns `''`). The existing code would crash if `userEmail` were ever null — the helper fixes that silently as a bonus.

Additional search done: `grep "eq '\${" src/` revealed two other sites (ContractDetail.jsx:50 interpolates `id`, MsaDetail.jsx:244 interpolates `sourceEntity`/`sourceId`) — but `id`, `sourceEntity`, `sourceId` come from route params / component props that are controlled by the router, NOT user-controlled strings. They are lower risk and are NOT migrated in this batch. A future Phase 5 pass can audit and migrate them if desired.

**Risk:** Low. Behavioral equivalence for the happy path (both forms escape single quotes identically). Null-safety improvement is additive. Export of the new helper adds one symbol to the `portalApi.js` public surface — no risk of collision since `escapeOdataString` is a novel name.

**Depends on:** none (but blocks 0241 and 0270 — they import this helper)

---

### CR-2026-04-09-0241 — Property lookup interpolates dcfg_location_id_text into a guid filter without quoting

**File:** src/SensorBanner.jsx
**Line(s):** 18 (import), 68-83 (enrichment loop)
**Severity:** P2
**Category:** data-integrity

**Current code (import, line 18):**
```javascript
import { apiGet, apiPatch, EntitySets, getEnvVar } from './portalApi.js';
```

**Proposed edit (import):**
```javascript
import { apiGet, apiPatch, EntitySets, getEnvVar, escapeOdataString } from './portalApi.js';
```

**Current code (enrichment loop, lines 67-83):**
```javascript
      // Enrich with location info if we have location_id
      const enriched = await Promise.all(active.map(async (rd) => {
        let locationName = rd.dcfg_location_id_text || 'Unknown Location';
        let contact = '';
        try {
          // Try to find the property by matching the location_id text
          const loc = await apiGet(
            `/${EntitySets.properties}?$filter=dcfg_propertyid eq ${rd.dcfg_location_id_text}` +
            `&$select=dcfg_name,dcfg_contact_person,dcfg_contact_phone&$top=1`
          );
          if (loc?.value?.[0]) {
            locationName = loc.value[0].dcfg_name || locationName;
            contact = [loc.value[0].dcfg_contact_person, loc.value[0].dcfg_contact_phone].filter(Boolean).join(' - ');
          }
        } catch { /* location lookup is best-effort */ }
        return { ...rd, locationName, contact };
      }));
```

**Proposed edit:**
```javascript
      // Enrich with location info if we have location_id
      // GUID regex guard — dcfg_propertyid is a GUID column, so non-GUID sensor IDs would 400.
      // See CR-2026-04-09-0241.
      const GUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const enriched = await Promise.all(active.map(async (rd) => {
        let locationName = rd.dcfg_location_id_text || 'Unknown Location';
        let contact = '';
        const locId = rd.dcfg_location_id_text;
        if (locId && GUID_RE.test(locId)) {
          try {
            // Try to find the property by matching the location_id text
            const loc = await apiGet(
              `/${EntitySets.properties}?$filter=dcfg_propertyid eq ${locId}` +
              `&$select=dcfg_name,dcfg_contact_person,dcfg_contact_phone&$top=1`
            );
            if (loc?.value?.[0]) {
              locationName = loc.value[0].dcfg_name || locationName;
              contact = [loc.value[0].dcfg_contact_person, loc.value[0].dcfg_contact_phone].filter(Boolean).join(' - ');
            }
          } catch { /* location lookup is best-effort */ }
        }
        return { ...rd, locationName, contact };
      }));
```

**Rationale:** Matches `recommendedFix`. Primary mitigation is the GUID regex guard — if `dcfg_location_id_text` is a friendly name like `GroupHome-12`, the lookup is skipped entirely, avoiding a doomed 400 round-trip and the wasted Promise.all concurrency slot. The enrichment falls back to `locationName = rd.dcfg_location_id_text` (which is already the default). OData GUID literals do NOT require quoting (the current code uses unquoted form) so we keep that form — the guard ensures only valid GUIDs reach the filter.

The `escapeOdataString` import is added even though it's not directly used here: the import is defensive for future changes where someone might add a string-filter fallback (e.g., look up by friendly name). This matches the cross-finding dependency — 0217 creates the helper, 0241/0270 import it. If the operator prefers strict minimalism, the import can be removed; leaving it in preempts a future "why did you not import the helper you created" question.

**Risk:** Low. The regex guard CAN produce a false negative if a sensor ever reports a GUID-ish string that's off by a character — but those sensors already 400 and silently fail, so the new behavior (skip lookup) is strictly better than the old behavior (issue doomed request). Power Pages sensor readings that DO carry real GUIDs continue to work unchanged.

**Depends on:** CR-2026-04-09-0217 (imports the helper it defines)

---

### CR-2026-04-09-0270 — Sensor alert location lookup interpolates raw text into GUID filter — same pattern as CR-0241

**File:** src/screens/Operations.jsx
**Line(s):** 10 (import), 141-174 (fetchSensorAlerts)
**Severity:** P2
**Category:** data-integrity

**Current code (import, line 10):**
```javascript
import { apiGet, EntitySets } from '../portalApi.js';
```

**Proposed edit (import):**
```javascript
import { apiGet, EntitySets, escapeOdataString } from '../portalApi.js';
```

**Current code (fetchSensorAlerts, lines 141-174):**
```javascript
  // ── Fetch Sensor Alerts ──
  const fetchSensorAlerts = useCallback(async () => {
    try {
      const since = new Date(Date.now() - 86400000).toISOString();
      const r = await apiGet(
        `/${EntitySets.sensorReadings}?$filter=dcfg_alert_type ne 'None' and dcfg_alert_type ne null and dcfg_acknowledged eq false and dcfg_reading_timestamp gt ${since}` +
        `&$select=dcfg_sensor_readingid,dcfg_location_id_text,dcfg_alert_type,dcfg_temperature_f,dcfg_humidity_pct,dcfg_reading_timestamp` +
        `&$orderby=dcfg_reading_timestamp desc&$top=50`
      );
      const readings = r?.value || [];
      setSensorAlerts(readings);

      const uniqueLocIds = [...new Set(readings.map(rd => rd.dcfg_location_id_text).filter(Boolean))];
      const unresolvedIds = uniqueLocIds.filter(id => !locationMapRef.current[id]);
      if (unresolvedIds.length > 0) {
        const results = await Promise.all(unresolvedIds.map(async locId => {
          try {
            const loc = await apiGet(
              `/${EntitySets.properties}?$filter=dcfg_propertyid eq ${locId}&$select=dcfg_propertyid,dcfg_name&$top=1`
            );
            if (loc?.value?.[0]) return { locId, id: loc.value[0].dcfg_propertyid, name: loc.value[0].dcfg_name };
          } catch { /* best-effort */ }
          return null;
        }));
        for (const r of results) {
          if (r) locationMapRef.current[r.locId] = { id: r.id, name: r.name };
        }
      }
    } catch {
      // Sensor table may not be available — fail silently
    } finally {
      setSensorLoading(false);
    }
  }, []);
```

**Proposed edit:**
```javascript
  // ── Fetch Sensor Alerts ──
  const fetchSensorAlerts = useCallback(async () => {
    try {
      const since = new Date(Date.now() - 86400000).toISOString();
      const r = await apiGet(
        `/${EntitySets.sensorReadings}?$filter=dcfg_alert_type ne 'None' and dcfg_alert_type ne null and dcfg_acknowledged eq false and dcfg_reading_timestamp gt ${since}` +
        `&$select=dcfg_sensor_readingid,dcfg_location_id_text,dcfg_alert_type,dcfg_temperature_f,dcfg_humidity_pct,dcfg_reading_timestamp` +
        `&$orderby=dcfg_reading_timestamp desc&$top=50`
      );
      const readings = r?.value || [];
      setSensorAlerts(readings);

      // GUID regex guard — dcfg_propertyid is a GUID column, so non-GUID sensor IDs would 400.
      // See CR-2026-04-09-0270 and the matching SensorBanner fix CR-2026-04-09-0241.
      const GUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const uniqueLocIds = [...new Set(readings.map(rd => rd.dcfg_location_id_text).filter(Boolean))];
      const unresolvedIds = uniqueLocIds.filter(id => !locationMapRef.current[id] && GUID_RE.test(id));
      if (unresolvedIds.length > 0) {
        const results = await Promise.all(unresolvedIds.map(async locId => {
          try {
            const loc = await apiGet(
              `/${EntitySets.properties}?$filter=dcfg_propertyid eq ${locId}&$select=dcfg_propertyid,dcfg_name&$top=1`
            );
            if (loc?.value?.[0]) return { locId, id: loc.value[0].dcfg_propertyid, name: loc.value[0].dcfg_name };
          } catch { /* best-effort */ }
          return null;
        }));
        for (const r of results) {
          if (r) locationMapRef.current[r.locId] = { id: r.id, name: r.name };
        }
      }
    } catch {
      // Sensor table may not be available — fail silently
    } finally {
      setSensorLoading(false);
    }
  }, []);
```

**Rationale:** Matches `recommendedFix` — same GUID regex guard pattern as 0241. The key difference from 0241 is the placement: here the filter `id => !locationMapRef.current[id] && GUID_RE.test(id)` is added directly into the unresolved-ID filter chain BEFORE the Promise.all loop kicks off, so non-GUID IDs are never even considered. Net result: one test per unique loc ID per poll, and zero doomed round-trips regardless of how many non-GUID sensors are active.

The `escapeOdataString` import is added for parity with 0241 and as a defensive for future string-filter paths — same reasoning as 0241.

The finding's `recommendedFix` ALSO mentions batching the unresolved IDs into a single `$filter=dcfg_propertyid in (...)` query. That's a performance optimization (N-to-1 round trips) that goes beyond the P2 data-integrity fix; I left it out of scope for this batch to keep the edit minimal. A future performance-focused batch can add the `in (…)` batching; the guard alone is the data-integrity win that qualifies for this batch.

**Risk:** Low. Same rationale as 0241 — GUID-filter skip is strictly better than doomed round-trips. The only observable change for users is faster sensor poll cycles when non-GUID IDs are present.

**Depends on:** CR-2026-04-09-0217 (imports the helper), sibling to CR-2026-04-09-0241

---

## Approval options

Reply with:
- `approve batch` — execute all 15
- `approve <id1>,<id2>,...` — selective
- `reject <id>` — skip
- `reject batch` — cancel
- `hold` — park
