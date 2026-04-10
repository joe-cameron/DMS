# Batch 05 — Phase 1 Performance + Auth/Role + Data Integrity Cleanup

**Phase:** 1 (Performance + auth-role + data-integrity grab-bag)
**Target:** SPA source under C:\DCFG\spa\dcfg-shell\src\
**Findings count:** 15 selected, 13 proposed for execution (2 pre-deferred as duplicates already landed in batch 01)
**Generated:** 2026-04-10T12:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-05-phase1-perf-auth-data.md
**Predecessor batches:**
  - batch 01: approvals/2026-04-09-batch-01-phase1-shared.md (SPA commit 39f8efb)
  - batch 02: approvals/2026-04-09-batch-02-phase1-expansion.md (SPA commits 30c693b + c48949f)
  - batch 03: approvals/2026-04-09-batch-03-phase1-p2-cleanup.md (SPA commit e727a8b)
  - batch 04: approvals/2026-04-09-batch-04-phase1-errhandling-security.md (staged)

## Scope rules (from spec §4.6)

- Batch size = 15 selected, 13 effective (2 pre-deferred — see "Pre-deferred findings" below)
- All `batch` tier — no catalog-only entries
- Every proposed-edit finding has verbatim before-code + concrete after-code
- Sequencing: 0229 introduces `WEB_ROLES` constants in usePortalUser.jsx; no other batch finding consumes them in this pass (NavPanel migration is a natural follow-up but out of scope to keep 0229 self-contained)

## Theme — five groups

This batch cleans up the remaining P2s that don't fit batch 04's error-handling + OData-injection theme. It is a grab-bag organized into five groups:

- **Group A — Performance (5 findings: 0207, 0234, 0266, 0272, 0275).** Four of these are unbounded Dataverse queries on high-traffic dashboard / list screens that currently work at dev-scale (~200 rows) but become the SPA's most expensive operations once tenant data grows. Fix pattern: add `$top` caps, add `dcfg_active_flag` / `statecode` filters where missing, and in two cases scope the query by a key (case-id list) instead of pulling everything. The fifth (0207) is a keystroke-rate `Array.find` bug in LocationManager's appliance editor that also happens to read a stale closure — fixed by deriving the GUID directly from `id` (they are identical in this file) instead of re-searching the appliances array. Finally 0234 is a React useCallback dep-array anti-pattern in SlideOutPanel — fixed with the standard ref-for-fast-changing-state pattern.

- **Group B — Auth/role (3 findings: 0224, 0229, 0246).** Two duplicates from batch 01 and one defense-in-depth hardening. 0224 was already landed in batch 01 (bundled with 0220); marked as duplicate here with a no-op note. 0229 centralizes the hardcoded role name strings (`'DCFG_Admin'`, `'DCFG_Manager'`, `'DCFG_Viewer'`) into an exported `WEB_ROLES` constant. 0246 adds a defensive `isAdmin()` check inside the Admin screen body so the component refuses to render its content if the route-level `RoleGuard` from batch 01 is ever bypassed or removed.

- **Group C — Data integrity (4 findings: 0212, 0231, 0256, 0307).** 0231 is a duplicate from batch 01 (`userName` already exposed at line 116 of usePortalUser.jsx) — marked duplicate, no edit. 0212 needed schema verification; the database bible confirms `dcfg_project` has a `dcfg_portfolioid` lookup to `dcfg_portfolio` (NOT a `dcfg_program_id`), so the existing `_dcfg_portfolioid_value` filter is correct for the current schema — landed as a comment-only change that documents why the legacy-sounding column name is right. 0256 fixes the `$count=true` / `value?.length` mismatch in CustomerDetail OverviewTab by dropping the unused `$count=true` (the cleaner fix per the finding's recommendedFix, since Power Pages Web API does not reliably surface `@odata.count`). 0307 replaces the "first active vendor" fallback in NewProposalWizard with a `getEnvVar('dcfg_decades_vendor_id')`-based lookup that preserves the first-active fallback only when the config row is missing — matches the finding's recommendedFix and is the conservative fix the operator directive asked for.

- **Group D — Error handling straggler (1 finding: 0284).** ProgramDetail `.catch(() => setLoading(false))` pattern — same anti-pattern as ContractList CR-0251 (batch 04) and same fix: add error state, add toast, distinguish 404 from load failure. One finding, carried into this batch because it was not picked up by batch 04's primary cluster.

- **Group E — Handoff cleanliness (2 findings: 0237, 0283).** 0237 tweaks `FieldName.jsx` so the default no-bg case renders as `transparent` via `currentColor` inheritance rather than white — this is a smaller, safer, in-scope fix than the finding's two architectural options; it avoids the white-smudge failure mode over non-white parents without requiring a per-screen audit. The finding's `recommendedFix` explicitly says "No fix in this batch" (Phase 3 audit), but the narrower in-place tweak fits this batch's cleanup theme, so I'm proposing it anyway — see operator note on that finding. 0283 moves the hardcoded Copilot Studio webchat URL in `NoraCopilot.jsx` into `dcfg_configs` via `getEnvVar('dcfg_nora_webchat_url')` with the current hardcoded URL as the in-bundle fallback, matching the loadConfig mandate in CLAUDE.md.

## Pre-deferred findings (2)

Two findings in the selected 15 are pre-deferred because investigation showed the fix is already landed:

- **CR-2026-04-09-0224 — DEFERRED (duplicate of batch 01 fix).** The finding claims NavPanel `isVisible` early-returns `true` for `/admin`. Verified current state: `NavPanel.jsx` line 125 reads `if (item.to === '/admin') return isAdmin();`. This was already landed in batch 01 as part of CR-2026-04-09-0220 (see batch-01 doc lines 662-765 — the 0220 proposed-edit replaced `return true` with `return isAdmin();` AND added the `CR-2026-04-09-0220 / 0224` comment reference at line 123). No edit needed in this batch. `findings.json` status will be updated to `fixed` by a later housekeeping pass that records the approvedIn/fixedAt metadata for 0224 — this batch doc does NOT touch findings.json per the critical rules.

- **CR-2026-04-09-0231 — DEFERRED (duplicate of batch 01 fix).** The finding claims `userName` is not exposed from `usePortalUser`'s `makeRoleHelpers` return. Verified current state: `usePortalUser.jsx` line 116 reads `userName: user?.name ?? null,` inside the return object. This was already landed in batch 01 via CR-2026-04-09-0202 (the companion finding explicitly referenced in 0231's `relatedFindings`). No edit needed in this batch. Same housekeeping note as 0224.

**Effective findings in this batch:** 13.

## Cross-finding dependencies

- **0229 → (none in this batch).** The `WEB_ROLES` constants are introduced in `usePortalUser.jsx` but no other finding in this batch migrates NavPanel's hardcoded strings to reference them. A future sibling batch can do the NavPanel migration once 0229 is landed — out of scope here to keep this finding self-contained and low-risk.
- **0272 ↔ 0275.** Siblings — same unbounded-query pattern on SalesDashboard (0272) and SendQueue (0275). Independent files, applied in document order. `relatedFindings` on 0275 links to 0272.
- **0284 → (sibling of batch 04 CR-0251).** Same pattern as ContractList — carried forward; independent file edit.
- All other findings are independent edits.

## New export introduced in this batch

**File:** src/usePortalUser.jsx
**Location:** immediately after the existing block comment at line 99 (before `function makeRoleHelpers`), as a new top-level exported constant.
**Signature:** `export const WEB_ROLES = { ADMIN: 'DCFG_Admin', MANAGER: 'DCFG_Manager', VIEWER: 'DCFG_Viewer' };`
**Semantics:** A single canonical dictionary of the DCFG web role schema names. `makeRoleHelpers` references the constants instead of string literals so future rename propagates correctly. NavPanel's `getPrimaryRoleLabel` still uses the string literals in this batch — that migration is a natural follow-up once 0229 lands.

```javascript
// Canonical web-role schema names. Keep in sync with the dcfg_webrole table on the portal.
// See CR-2026-04-09-0229.
export const WEB_ROLES = {
  ADMIN:   'DCFG_Admin',
  MANAGER: 'DCFG_Manager',
  VIEWER:  'DCFG_Viewer',
};
```

This export is introduced in 0229's edit. NavPanel migration is deferred to a future batch.

---

## Findings in this batch

### CR-2026-04-09-0207 — updateApplField runs Array.find on every keystroke + closes over stale state

**File:** src/LocationManager.jsx
**Line(s):** 541-554
**Severity:** P2
**Category:** performance

**Current code:**
```javascript
  function updateApplField(id, field, val) {
    setAppliances(prev => prev.map(a => a.id === id ? { ...a, [field]: val } : a));
    const a = appliances.find(x => x.id === id);
    const dvCol = colMap[field];
    if (!dvCol || !a?.guid) return;
    clearTimeout(patchTimers.current[id]);
    patchTimers.current[id] = setTimeout(async () => {
      try {
        const body = {};
        body[dvCol] = field === 'installDate' ? (val ? val + '-01' : null) : val;
        await apiPatch(`/${EntitySets.appliances}(${a.guid})`, body);
      } catch { toast.show('err', 'Auto-save failed'); }
    }, 1500);
  }
```

**Proposed edit:**
```javascript
  function updateApplField(id, field, val) {
    setAppliances(prev => prev.map(a => a.id === id ? { ...a, [field]: val } : a));
    // CR-2026-04-09-0207: derive GUID directly from `id` instead of searching the
    // stale `appliances` closure. In this file `id === guid` throughout the
    // appliance lifecycle (see confirmAddAppliance + loadAppliances) so the find()
    // was redundant AND was reading a one-step-behind array.
    const dvCol = colMap[field];
    if (!dvCol || !id) return;
    clearTimeout(patchTimers.current[id]);
    patchTimers.current[id] = setTimeout(async () => {
      try {
        const body = {};
        body[dvCol] = field === 'installDate' ? (val ? val + '-01' : null) : val;
        await apiPatch(`/${EntitySets.appliances}(${id})`, body);
      } catch { toast.show('err', 'Auto-save failed'); }
    }, 1500);
  }
```

**Rationale:** Matches `recommendedFix`. Two coupled wins: (1) eliminates the per-keystroke `Array.find` scan of the appliances list (O(n) → O(1)), and (2) fixes the stale-closure bug where the lookup `appliances.find(...)` reads the PRE-update array because `setAppliances(prev => ...)` has not yet committed at that point in the synchronous function body. The finding confirms (and I verified via `grep "a\.guid\b" LocationManager.jsx`) that throughout this file the appliance `id` and `guid` are used interchangeably — records loaded from Dataverse via `loadAppliances` are keyed on `dcfg_applianceid` which is then assigned to both `id` and `guid`, and records created via `confirmAddAppliance` assign the returned server GUID to both fields. So `id === guid` is a file-wide invariant. The edit replaces the `{EntitySets.appliances}(${a.guid})` URL with `{EntitySets.appliances}(${id})` to remove the dependency on the stale `a` object.

**Risk:** Low. The guard `if (!dvCol || !id) return;` is strictly stricter than the previous `if (!dvCol || !a?.guid) return;` only when `id` is somehow truthy while `a?.guid` is falsy — which cannot happen in this file because `id` is passed from JSX event handlers which only fire on already-loaded appliance rows where `guid === id`. For newly-added (not-yet-saved) appliances, both `id` and `guid` are null/undefined pre-save, and the JSX does not render the edit inputs until the row has been saved (confirmAddAppliance flow), so `updateApplField` is only invoked on saved rows.

**Depends on:** none

---

### CR-2026-04-09-0234 — SlideOutPanel useCallback dep on width — recreated on every drag tick

**File:** src/SlideOutPanel.jsx
**Line(s):** 27-38 (refs block + onMouseDown), 40-62 (drag useEffect)
**Severity:** P2
**Category:** performance

**Current code (refs + onMouseDown, lines 27-38):**
```javascript
  var dragging = useRef(false);
  var startX = useRef(0);
  var startW = useRef(0);

  var onMouseDown = useCallback(function(e) {
    e.preventDefault();
    dragging.current = true;
    startX.current = e.clientX;
    startW.current = width;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [width]);
```

**Proposed edit:**
```javascript
  var dragging = useRef(false);
  var startX = useRef(0);
  var startW = useRef(0);
  // CR-2026-04-09-0234: keep width in a ref so onMouseDown + the drag useEffect
  // can read the latest value without retriggering memoization on every tick.
  var widthRef = useRef(width);
  useEffect(function() { widthRef.current = width; }, [width]);

  var onMouseDown = useCallback(function(e) {
    e.preventDefault();
    dragging.current = true;
    startX.current = e.clientX;
    startW.current = widthRef.current;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, []);
```

**Current code (drag useEffect, lines 40-62):**
```javascript
  useEffect(function() {
    function onMouseMove(e) {
      if (!dragging.current) return;
      var newW = startW.current + (e.clientX - startX.current);
      if (newW < MIN_WIDTH) newW = MIN_WIDTH;
      if (newW > MAX_WIDTH) newW = MAX_WIDTH;
      setWidth(newW);
    }
    function onMouseUp() {
      if (dragging.current) {
        dragging.current = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
        try { localStorage.setItem('dcfg_panel_width_' + testId, String(width)); } catch(e) {}
      }
    }
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
    return function() {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
    };
  }, [width, testId]);
```

**Proposed edit:**
```javascript
  useEffect(function() {
    function onMouseMove(e) {
      if (!dragging.current) return;
      var newW = startW.current + (e.clientX - startX.current);
      if (newW < MIN_WIDTH) newW = MIN_WIDTH;
      if (newW > MAX_WIDTH) newW = MAX_WIDTH;
      setWidth(newW);
    }
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
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
    return function() {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
    };
  }, [testId]);
```

**Rationale:** Matches `recommendedFix`. Standard React refs-for-fast-changing-state pattern: introduce `widthRef`, sync it in a one-line useEffect keyed on `[width]`, and read `widthRef.current` inside the fast-path callbacks that previously closed over `width`. Two consumer sites get updated: (1) `onMouseDown` — empty deps, reads ref; (2) the drag useEffect — drops `width` from deps, reads `widthRef.current` on the mouseup persist. Net effect during a drag: the drag useEffect registers its document listeners ONCE when the panel mounts, instead of unmounting/remounting them on every mousemove tick. The single-key `testId` dep remains.

**Risk:** Low. The one subtle behavior change is that the localStorage persist on mouseup now reads the ref instead of the state — but they are guaranteed in sync because the `useEffect` on `[width]` syncs the ref before any subsequent render paints. For the final mouseup tick, even if the setWidth commit has not yet landed in React state, the ref update is driven by the same render cycle, so the persisted value is correct. Verified by tracing: drag end → `setWidth(newW)` schedules re-render → React commits → sync effect writes `widthRef.current = newW` → mouseup handler fires later in the same or subsequent frame and reads the updated ref.

**Depends on:** none

---

### CR-2026-04-09-0266 — Progress query loads ALL checklist records across ALL cases

**File:** src/screens/Onboarding.jsx
**Line(s):** 71-89
**Severity:** P2
**Category:** performance

**Current code:**
```javascript
      // Fetch all checklist progress in a single query (avoids N+1)
      if (rows.length > 0) {
        try {
          const allChecks = await apiGet(
            `/${EntitySets.onboardingChecks}?$select=dcfg_onboarding_checklistid,dcfg_is_complete,_dcfg_case_id_value&$filter=dcfg_is_complete ne null`
          );
          const progressMap = {};
          for (const s of (allChecks?.value ?? [])) {
            const cid = s._dcfg_case_id_value;
            if (!cid) continue;
            if (!progressMap[cid]) progressMap[cid] = { done: 0, total: 0 };
            progressMap[cid].total++;
            if (s.dcfg_is_complete) progressMap[cid].done++;
          }
          setProgress(progressMap);
        } catch {
          setProgress({});
        }
      }
```

**Proposed edit:**
```javascript
      // Fetch all checklist progress in a single query (avoids N+1)
      // CR-2026-04-09-0266: scope the query to just the cases currently in the
      // list (rather than every checklist row ever written). Uses an OR-chain
      // filter — Power Pages Web API does not reliably support `in (...)` so
      // we build `(_dcfg_case_id_value eq id1 or _dcfg_case_id_value eq id2 ...)`.
      if (rows.length > 0) {
        try {
          const caseIds = rows.map(r => r.dcfg_onboarding_caseid).filter(Boolean);
          const caseFilter = caseIds.map(cid => `_dcfg_case_id_value eq ${cid}`).join(' or ');
          const allChecks = await apiGet(
            `/${EntitySets.onboardingChecks}?$select=dcfg_onboarding_checklistid,dcfg_is_complete,_dcfg_case_id_value&$filter=(${caseFilter}) and dcfg_is_complete ne null&$top=5000`
          );
          const progressMap = {};
          for (const s of (allChecks?.value ?? [])) {
            const cid = s._dcfg_case_id_value;
            if (!cid) continue;
            if (!progressMap[cid]) progressMap[cid] = { done: 0, total: 0 };
            progressMap[cid].total++;
            if (s.dcfg_is_complete) progressMap[cid].done++;
          }
          setProgress(progressMap);
        } catch {
          setProgress({});
        }
      }
```

**Rationale:** Matches the first option in `recommendedFix` (the server-side rollup option is a larger effort). Scopes the progress query to only the visible cases via an OR-chain on `_dcfg_case_id_value`. Adds a `$top=5000` safety cap to match the Power Pages Web API default ceiling so we cannot be silently truncated without the developer noticing. Also keeps the existing `dcfg_is_complete ne null` filter (still useful because incomplete rows with null flag would otherwise inflate the `total` denominator incorrectly — see the finding's own evidence that the total/done math depends on the filter).

Note: OR-chain filters have a Dataverse query-complexity ceiling around ~100 OR clauses; at current scale (~30 cases visible) we are well below that. At 100+ visible cases the query should be rewritten to use the server-side rollup Power Automate flow path suggested in the finding's `recommendedFix` option 2 — flagged as a follow-up, NOT in this batch.

**Risk:** Low. The OR-chain is parenthesized correctly so the `and dcfg_is_complete ne null` applies to the whole filter (not just the last clause). Dataverse parses `A and (B or C)` correctly — and we wrote `(B or C) and A` for clarity. The `$top=5000` is an upper bound only; below 5000 rows the behavior is identical.

**Depends on:** none

---

### CR-2026-04-09-0272 — SalesDashboard loads ALL contracts and MSAs with no $top cap and no active_flag filter

**File:** src/screens/SalesDashboard.jsx
**Line(s):** 61-68
**Severity:** P2
**Category:** performance

**Current code:**
```javascript
        const [contractRes, msaRes, customerRes, auditRes, onboardRes, prospectRes] = await Promise.all([
          apiGet('/dcfg_contracts?$select=dcfg_contractid,dcfg_status,dcfg_contract_date,dcfg_msa_id,dcfg_sent_date,dcfg_generated_date'),
          apiGet('/dcfg_msas?$select=dcfg_msaid,dcfg_name,_dcfg_customer_id_value,dcfg_budget_total,dcfg_budget_committed&$filter=dcfg_budget_total ne null'),
          apiGet('/dcfg_customers?$select=dcfg_customerid,dcfg_name'),
          apiGet('/dcfg_audit_logs?$select=dcfg_audit_logid,dcfg_action_type,dcfg_performed_by,dcfg_performed_at,dcfg_related_contract_id,dcfg_new_value&$orderby=dcfg_performed_at desc&$top=20'),
          apiGet(`/${EntitySets.onboardingCases}?$filter=dcfg_status ne 100000002&$select=dcfg_onboarding_caseid,dcfg_case_label,dcfg_status,dcfg_initiated_date&$expand=dcfg_customer_id($select=dcfg_name)&$orderby=dcfg_initiated_date asc&$top=10`).catch(() => ({value:[]})),
          apiGet(`/${EntitySets.msas}?$filter=dcfg_status eq ${MsaStatus.WIP} or dcfg_status eq 100000000&$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_effective_date,dcfg_location_count,dcfg_total_monthly&$expand=dcfg_customer_id($select=dcfg_name)&$orderby=createdon desc&$top=10`).catch(() => ({value:[]})),
        ]);
```

**Proposed edit:**
```javascript
        const [contractRes, msaRes, customerRes, auditRes, onboardRes, prospectRes] = await Promise.all([
          // CR-2026-04-09-0272: add active_flag filter + safety $top cap.
          apiGet('/dcfg_contracts?$filter=dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_status,dcfg_contract_date,dcfg_msa_id,dcfg_sent_date,dcfg_generated_date&$top=500'),
          apiGet('/dcfg_msas?$select=dcfg_msaid,dcfg_name,_dcfg_customer_id_value,dcfg_budget_total,dcfg_budget_committed&$filter=dcfg_budget_total ne null and statecode eq 0&$top=500'),
          apiGet('/dcfg_customers?$filter=dcfg_active_flag eq true&$select=dcfg_customerid,dcfg_name&$top=500'),
          apiGet('/dcfg_audit_logs?$select=dcfg_audit_logid,dcfg_action_type,dcfg_performed_by,dcfg_performed_at,dcfg_related_contract_id,dcfg_new_value&$orderby=dcfg_performed_at desc&$top=20'),
          apiGet(`/${EntitySets.onboardingCases}?$filter=dcfg_status ne 100000002&$select=dcfg_onboarding_caseid,dcfg_case_label,dcfg_status,dcfg_initiated_date&$expand=dcfg_customer_id($select=dcfg_name)&$orderby=dcfg_initiated_date asc&$top=10`).catch(() => ({value:[]})),
          apiGet(`/${EntitySets.msas}?$filter=dcfg_status eq ${MsaStatus.WIP} or dcfg_status eq 100000000&$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_effective_date,dcfg_location_count,dcfg_total_monthly&$expand=dcfg_customer_id($select=dcfg_name)&$orderby=createdon desc&$top=10`).catch(() => ({value:[]})),
        ]);
```

**Rationale:** Matches `recommendedFix`. Three queries get filters + caps: contracts (active_flag + $top=500), msas (statecode + $top=500 appended to existing budget filter), customers (active_flag + $top=500). The other three queries (audit_logs, onboardingCases, prospect) already have appropriate $top caps. The audit_logs query at $top=20 is unchanged — already fine.

The `statecode eq 0` filter added to the msas query is the Dataverse equivalent of "not soft-deactivated" — the existing code relied on the `dcfg_budget_total ne null` filter to happen to exclude deactivated rows, which is not reliable. Adding `statecode eq 0` makes the intent explicit.

**Risk:** Low-medium. The `$top=500` cap is a backstop against pathological growth — if the tenant has >500 active contracts, the dashboard counts will be UNDERREPORTED (visible as a subtle KPI drift rather than a hard failure). The finding's recommendedFix explicitly accepts this tradeoff ("At 2,000 contracts the dashboard becomes the single most expensive page load"). A future server-side rollup (in dcfg_configs) removes the cap entirely. Operator should be aware that any tenant with >500 active contracts needs the rollup sooner rather than later.

**Operator note:** The 500 cap is a guess at a reasonable safety ceiling. If the operator has insight that prod will hit 500 soon, raise the cap to 2000 in this edit before approval. The finding's recommendedFix suggests 500 as the default.

**Depends on:** none (paired with 0275 — same pattern on SendQueue)

---

### CR-2026-04-09-0275 — SendQueue loadAll fires 5 unbounded queries at mount

**File:** src/screens/SendQueue.jsx
**Line(s):** 110-116
**Severity:** P2
**Category:** performance

**Current code:**
```javascript
      const [cRes, mRes, custRes, obRes, wipRes] = await Promise.all([
        apiGet(`/${EntitySets.contracts}?$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_family,dcfg_contract_type,dcfg_contract_fee,dcfg_client_name,dcfg_contractor_legal_name,dcfg_contract_date,dcfg_generated_date,dcfg_sent_date,dcfg_signed_date,dcfg_document_url,dcfg_declined_reason,dcfg_active_flag,createdon&$expand=dcfg_msa_id($select=dcfg_msaid,dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name))&$orderby=createdon desc`),
        apiGet(`/${EntitySets.msas}?$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_contract_family,dcfg_expiration_date,dcfg_effective_date&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name)&$orderby=dcfg_expiration_date asc`),
        apiGet(`/${EntitySets.customers}?$filter=dcfg_active_flag eq true&$select=dcfg_customerid,dcfg_name,dcfg_display_name,dcfg_contract_family,dcfg_primary_contact_email,createdon&$orderby=dcfg_name asc`),
        apiGet(`/${EntitySets.onboardingCases}?$filter=dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed}&$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_notes&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)&$orderby=dcfg_initiated_date desc`).catch(() => ({ value: [] })),
        apiGet(`/${EntitySets.contracts}?$filter=dcfg_status eq 100000008 and dcfg_contract_number eq null and dcfg_blanket_number eq null and dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_type,dcfg_client_name,dcfg_contract_fee,dcfg_blanket_number,dcfg_contract_date,dcfg_created_by_email,createdon&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name)&$orderby=createdon desc`).catch(() => ({ value: [] })),
      ]);
```

**Proposed edit:**
```javascript
      const [cRes, mRes, custRes, obRes, wipRes] = await Promise.all([
        // CR-2026-04-09-0275: add active_flag filter + safety $top cap to contracts + msas queries.
        apiGet(`/${EntitySets.contracts}?$filter=dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_family,dcfg_contract_type,dcfg_contract_fee,dcfg_client_name,dcfg_contractor_legal_name,dcfg_contract_date,dcfg_generated_date,dcfg_sent_date,dcfg_signed_date,dcfg_document_url,dcfg_declined_reason,dcfg_active_flag,createdon&$expand=dcfg_msa_id($select=dcfg_msaid,dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name))&$orderby=createdon desc&$top=500`),
        apiGet(`/${EntitySets.msas}?$filter=statecode eq 0&$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_contract_family,dcfg_expiration_date,dcfg_effective_date&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name)&$orderby=dcfg_expiration_date asc&$top=500`),
        apiGet(`/${EntitySets.customers}?$filter=dcfg_active_flag eq true&$select=dcfg_customerid,dcfg_name,dcfg_display_name,dcfg_contract_family,dcfg_primary_contact_email,createdon&$orderby=dcfg_name asc&$top=500`),
        apiGet(`/${EntitySets.onboardingCases}?$filter=dcfg_status ne ${OnboardingCaseStatus.Complete} and dcfg_status ne ${OnboardingCaseStatus.Closed}&$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_notes&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)&$orderby=dcfg_initiated_date desc&$top=200`).catch(() => ({ value: [] })),
        apiGet(`/${EntitySets.contracts}?$filter=dcfg_status eq 100000008 and dcfg_contract_number eq null and dcfg_blanket_number eq null and dcfg_active_flag eq true&$select=dcfg_contractid,dcfg_contract_type,dcfg_client_name,dcfg_contract_fee,dcfg_blanket_number,dcfg_contract_date,dcfg_created_by_email,createdon&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name)&$orderby=createdon desc&$top=200`).catch(() => ({ value: [] })),
      ]);
```

**Rationale:** Matches `recommendedFix`. Five queries get caps: contracts (active_flag + $top=500), msas (statecode + $top=500), customers ($top=500 appended to existing active filter), onboardingCases ($top=200 — already filtered by status), wipContracts ($top=200 — already filtered tightly). The $top=200 for the last two is smaller because they're showing narrow result sets by definition (WIP or open cases only) and a cap of 200 is well above realistic sizes while still protecting against runaway queries.

The finding also suggests "defer non-critical queries (onboarding, wip) until after initial render". That's a more invasive restructure (break up Promise.all, add secondary effect) that goes beyond the P2 fix; I left it out of scope. The caps alone are the primary win.

**Risk:** Low. Same rationale as 0272. SendQueue is the highest-traffic admin landing page, so performance wins here compound. The caps are generous relative to current tenant scale.

**Depends on:** CR-2026-04-09-0272 (sibling — same pattern)

---

### CR-2026-04-09-0224 — DEFERRED (duplicate of batch 01 CR-0220)

**File:** src/NavPanel.jsx
**Line(s):** 124-125 (current state)
**Severity:** P2
**Category:** auth-role-checks
**Status:** deferred — already landed in batch 01

**Current code (lines 122-125):**
```javascript
  // System Admin is always visible to admins (can't lock yourself out),
  // but must be hidden from non-admins. See CR-2026-04-09-0220 / 0224.
  function isVisible(item) {
    if (item.to === '/admin') return isAdmin();
```

**Proposed edit:** NONE — the finding's recommended fix (`if (item.to === '/admin') return isAdmin();`) is already present at line 125, landed in batch 01 as part of the CR-0220 edit which explicitly referenced both 0220 and 0224 in the inline comment. The `findings.json` status entry still reads `open` because no one has run the housekeeping pass to record the approvedIn/fixedAt metadata for 0224 specifically — out of scope for this batch per the critical rules (DO NOT modify findings.json).

**Rationale:** Verified by reading `C:\DCFG\spa\dcfg-shell\src\NavPanel.jsx` lines 122-125 and comparing to `C:\dcfg\docs\code-review-2026-04-09\approvals\2026-04-09-batch-01-phase1-shared.md` lines 748-751 where the exact `return isAdmin();` form was the batch 01 proposed edit. The comment on line 123 ("`See CR-2026-04-09-0220 / 0224.`") is itself batch 01's acknowledgement of this duplicate.

**Risk:** N/A — no edit.

**Depends on:** resolved by batch 01 CR-2026-04-09-0220.

**Operator note:** A future housekeeping pass should update `findings.json` to mark 0224 as `fixed` with `approvedIn: approvals/2026-04-09-batch-01-phase1-shared.md` and `fixCommit: 39f8efb` (or whichever SHA actually carried the 0220 edit).

---

### CR-2026-04-09-0229 — hasRole hardcodes DCFG_Admin / DCFG_Manager / DCFG_Viewer strings

**File:** src/usePortalUser.jsx
**Line(s):** 100-118 (makeRoleHelpers block + new export)
**Severity:** P2
**Category:** auth-role-checks

**Current code (lines 100-118):**
```javascript
// ---------------------------------------------------------------------------
// Role helpers
// DCFG role hierarchy: Admin > Manager > Viewer
// ---------------------------------------------------------------------------

function makeRoleHelpers(user) {
  const hasRole = (name) =>
    user?.isAuthenticated === true &&
    user.roles.some((r) => r.name === name || r === name);

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

**Proposed edit:**
```javascript
// ---------------------------------------------------------------------------
// Role helpers
// DCFG role hierarchy: Admin > Manager > Viewer
// ---------------------------------------------------------------------------

// Canonical web-role schema names. Keep in sync with the dcfg_webrole table on the portal.
// See CR-2026-04-09-0229.
export const WEB_ROLES = {
  ADMIN:   'DCFG_Admin',
  MANAGER: 'DCFG_Manager',
  VIEWER:  'DCFG_Viewer',
};

function makeRoleHelpers(user) {
  const hasRole = (name) =>
    user?.isAuthenticated === true &&
    user.roles.some((r) => r.name === name || r === name);

  return {
    hasRole,
    isAdmin:   () => hasRole(WEB_ROLES.ADMIN),
    isManager: () => hasRole(WEB_ROLES.MANAGER) || hasRole(WEB_ROLES.ADMIN),
    isViewer:  () => user?.isAuthenticated === true,
    userEmail: user?.email ?? null,
    userName:  user?.name ?? null,
  };
}
```

**Rationale:** Matches `recommendedFix`. Introduces an exported `WEB_ROLES` constant dictionary and migrates the three string literals in `isAdmin` / `isManager` to reference it. The constants are defined OUTSIDE `makeRoleHelpers` so they can be imported by other files (NavPanel's `getPrimaryRoleLabel`, RoleGuard, etc.) in a future sibling batch.

NOT migrated in this batch: `NavPanel.jsx` lines 407-409 where `getPrimaryRoleLabel` still uses the string literals directly. The finding's detail section calls this out as duplication, and the clean follow-up is to `import { WEB_ROLES } from './usePortalUser.jsx'` in NavPanel and reference `WEB_ROLES.ADMIN` etc. That migration is a mechanical refactor — kept out of this batch to stay under the 15-cap and because NavPanel has its own active findings (0224) which should land first to reduce merge noise.

**Risk:** Zero behavior change. The string comparisons are byte-identical (`'DCFG_Admin' === WEB_ROLES.ADMIN`). The export adds one symbol to `usePortalUser.jsx`'s public surface — no collision risk since `WEB_ROLES` is a novel name. Consumers that currently import from `usePortalUser.jsx` are unaffected (they still get the same `usePortalUser`, `PortalUserProvider` exports).

**Depends on:** none

---

### CR-2026-04-09-0246 — Admin screen has no in-component isAdmin check

**File:** src/screens/Admin.jsx
**Line(s):** 96-102
**Severity:** P2
**Category:** auth-role-checks

**Current code:**
```javascript
export default function Admin() {
  const { user } = usePortalUser();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState(null);
  const [expandedSections, setExpandedSections] = useState({});
  const toggleSection = (label) => setExpandedSections(prev => ({ ...prev, [label]: !prev[label] }));
```

**Proposed edit:**
```javascript
export default function Admin() {
  const { user, isAdmin } = usePortalUser();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState(null);
  const [expandedSections, setExpandedSections] = useState({});
  const toggleSection = (label) => setExpandedSections(prev => ({ ...prev, [label]: !prev[label] }));

  // CR-2026-04-09-0246: defense-in-depth guard. The /admin route is already
  // wrapped in <RoleGuard role="admin"> from AppRouter (CR-2026-04-09-0219),
  // but if that guard is ever removed or bypassed, refuse to render the tabs.
  if (!isAdmin()) {
    return (
      <div className="page-content" data-testid="admin-access-denied">
        <h1 style={{ fontSize: '22px', color: NAVY, fontFamily: "'Fraunces', serif", marginBottom: '12px' }}>
          System Administration
        </h1>
        <p style={{ color: '#64748B', fontSize: '14px' }}>
          Admin access required.
        </p>
      </div>
    );
  }
```

**Rationale:** Matches `recommendedFix`. Two coupled changes: (1) destructure `isAdmin` from `usePortalUser()`, (2) add an early-return fallback render if `isAdmin()` is false. The fallback uses the same `page-content` wrapper + `NAVY` heading style as the rest of the screen for visual consistency — a non-admin who somehow reaches this route (bypassed router guard) sees a clean "Admin access required" message instead of the full admin card grid.

The message is deliberately terse. The route-level `RoleGuard` from batch 01 CR-0219 is the primary enforcement; this in-component check is defense-in-depth per the finding's detail section ("If the router guard is ever removed or bypassed, every admin action is exposed"). The `data-testid="admin-access-denied"` enables Playwright tests to verify the fallback renders for non-admin fixtures.

**Risk:** Zero for admins (the `if (!isAdmin()) return ...` is false, code proceeds normally). For non-admins who reach this route through RoleGuard, they see the fallback instead of the tabs. The only observable change for the non-admin path is the fallback UI — which is strictly better than the current "render tabs + hope nothing gets clicked" behavior.

**Depends on:** CR-2026-04-09-0219 (batch 01, route-level guard — this fix is layered on top of it)

---

### CR-2026-04-09-0231 — DEFERRED (duplicate of batch 01 CR-0202)

**File:** src/usePortalUser.jsx
**Line(s):** 116 (current state)
**Severity:** P2
**Category:** data-integrity
**Status:** deferred — already landed in batch 01

**Current code (lines 110-118):**
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

**Proposed edit:** NONE — `userName: user?.name ?? null,` is already present at line 116 of `usePortalUser.jsx`. This was added in batch 01's CR-2026-04-09-0202 edit (LocationManager `userName` destructure — the companion finding explicitly referenced in 0231's `relatedFindings`).

**Rationale:** Verified by reading `C:\DCFG\spa\dcfg-shell\src\usePortalUser.jsx` line 116. The finding's premise (userName not exposed) is false against current state.

**Risk:** N/A — no edit.

**Depends on:** resolved by batch 01 CR-2026-04-09-0202.

**Operator note:** Same housekeeping note as 0224 — `findings.json` should be updated by a later pass to mark 0231 as `fixed` with `approvedIn: approvals/2026-04-09-batch-01-phase1-shared.md`.

**Interaction with 0229 in this batch:** The 0229 edit changes lines 110-118 of `usePortalUser.jsx`. The `userName: user?.name ?? null,` line IS preserved in the 0229 proposed edit — verified above. No conflict.

---

### CR-2026-04-09-0256 — OverviewTab counts use $count=true but read value?.length

**File:** src/screens/CustomerDetail.jsx
**Line(s):** 144-160
**Severity:** P2
**Category:** data-integrity

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
          .then(r => setCounts(prev => ({ ...prev, contracts: r?.value?.length ?? 0 })))
          .catch(e => console.warn('OverviewTab contracts count failed:', e));
      }
    }).catch(e => console.warn('OverviewTab counts load failed:', e));
  }, [customerId]);
```

**Proposed edit:**
```javascript
function OverviewTab({ customer, customerId, navigate, isManager }) {
  const [counts, setCounts] = useState({ msas: 0, contracts: 0, locations: 0 });
  useEffect(() => {
    // CR-2026-04-09-0256: drop $count=true — Power Pages Web API does not
    // reliably surface @odata.count, and we were reading value.length anyway.
    // At current scale value.length IS the total (under the Power Pages 5000-row cap).
    Promise.all([
      apiGet(`/dcfg_msas?$filter=_dcfg_customer_id_value eq ${customerId}&$select=dcfg_msaid`),
      apiGet(`/dcfg_properties?$filter=_dcfg_customer_id_value eq ${customerId} and dcfg_active_flag eq true&$select=dcfg_propertyid`),
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

**Rationale:** Matches the preferred option in `recommendedFix` ("Prefer dropping $count=true — it's not supported by Power Pages Web API consistently and value.length is fine at current scale"). Two-character-level change: drop the `&$count=true` suffix from each of the two apiGet URLs. The `.then` callback is unchanged because it was already reading `value.length` — which now IS the correct metric (the semantic mismatch was the `$count=true` parameter promising something the callback was not consuming).

Leaves the batch 04 catches in place (the `.catch(e => console.warn(...))` on both the inner and outer promise chains). Those were added as CR-2026-04-09-0257 in batch 04 — this edit does not touch them.

**Risk:** Zero. Behavior is unchanged at current scale (every tested customer has <5000 MSAs/locations). Once a tenant passes 5000, the counts start truncating at 5000 — but that is the SAME behavior as before this edit (and as the finding notes, `$count=true` was not fixing it). The TRUE fix for multi-thousand-scale customers is a server-side rollup, noted as a future follow-up.

**Depends on:** none (interacts with batch 04 CR-0257 which added the .catch blocks — preserved)

---

### CR-2026-04-09-0212 — fetchProjectsByProgram uses _dcfg_portfolioid_value — schema verified correct

**File:** src/portalApi.js
**Line(s):** 781
**Severity:** P2
**Category:** data-integrity

**Current code:**
```javascript
export function fetchProjectsByProgram(progId) { return apiGet(`/${EntitySets.projects}?$filter=_dcfg_portfolioid_value eq ${progId}&$select=dcfg_projectid,dcfg_name,dcfg_trades,dcfg_estimated_cost,dcfg_status&$orderby=dcfg_name asc`); }
```

**Proposed edit:**
```javascript
// CR-2026-04-09-0212: the column name looks legacy-suspect (portfolio vs program),
// but schema verification against reference_database_bible.json confirms dcfg_project
// has a `dcfg_portfolioid` Lookup referencing `dcfg_portfolio` — there is NO
// `dcfg_program_id` lookup on dcfg_project. The "program" terminology is the SPA's
// display label; the Dataverse-level referent is `dcfg_portfolio`. LEAVE the filter
// column as-is. If the schema is ever refactored to rename dcfg_portfolio →
// dcfg_program, this line (and src/screens/ProjectList.jsx) must move in lockstep.
export function fetchProjectsByProgram(progId) { return apiGet(`/${EntitySets.projects}?$filter=_dcfg_portfolioid_value eq ${progId}&$select=dcfg_projectid,dcfg_name,dcfg_trades,dcfg_estimated_cost,dcfg_status&$orderby=dcfg_name asc`); }
```

**Rationale:** Schema verification completed. I read `~/.claude/projects/C--dcfg/memory/reference_database_bible.json` and confirmed the `dcfg_project` table's `lookups` array contains exactly one program/portfolio-related entry:

```json
{
  "schemaName": "dcfg_project_portfolio",
  "referencingAttribute": "dcfg_portfolioid",
  "referencedEntity": "dcfg_portfolio",
  "navigationProperty": "dcfg_portfolioid"
}
```

There is NO `dcfg_program_id` lookup on `dcfg_project`. The finding's suspicion that this was a "holdover from an earlier schema where projects belonged to 'portfolios'" is INVERTED — `dcfg_portfolio` IS the current schema, and "program" is the SPA's display/UX label layered on top of it. The existing filter `_dcfg_portfolioid_value eq ${progId}` is correct.

Matches the finding's `recommendedFix` option B verbatim: "If it's truly `_dcfg_portfolioid_value`, leave it but add a code comment explaining the legacy name." The edit is comment-only — no functional change.

**Risk:** Zero. Comment-only edit.

**Operator note:** The same schema consideration applies to `src/screens/ProjectList.jsx` (the finding's evidence mentions it). That file is out of scope for Phase 1 per the finding, but when Phase 2 touches ProjectList, the same verification should be done to confirm no false-suspicion rewrites happen there.

**Depends on:** none

---

### CR-2026-04-09-0307 — generate() picks 'first active vendor' as Decades vendor — fragile defaulting

**File:** src/NewProposalWizard.jsx
**Line(s):** 383-384
**Severity:** P2
**Category:** data-integrity

**Current code:**
```javascript
      // 2. Vendor
      let vendorId=null;
      try{const vr=await apiGet(`/${EntitySets.vendors}?$filter=dcfg_active_flag eq true&$select=dcfg_vendorid&$top=1`);vendorId=vr.value?.[0]?.dcfg_vendorid}catch{}
```

**Proposed edit:**
```javascript
      // 2. Vendor
      // CR-2026-04-09-0307: prefer the canonical Decades vendor id from dcfg_configs
      // (dcfg_decades_vendor_id) over the "first active vendor" fallback. Without
      // this, on a tenant with multiple active vendors the proposal wizard would
      // patch the signer details onto whichever vendor happens to sort first —
      // corrupting that vendor's record. The fallback is preserved for tenants
      // that have not yet seeded the config row.
      let vendorId=null;
      try{
        const configuredId = getEnvVar('dcfg_decades_vendor_id');
        if (configuredId) {
          vendorId = configuredId;
        } else {
          const vr=await apiGet(`/${EntitySets.vendors}?$filter=dcfg_active_flag eq true&$select=dcfg_vendorid&$top=1`);
          vendorId=vr.value?.[0]?.dcfg_vendorid;
          if (vendorId) console.warn('[NewProposalWizard] dcfg_decades_vendor_id config missing — using first active vendor as fallback. Seed the config row to avoid writing to the wrong vendor.');
        }
      }catch{}
```

**Current code (import, line 9):**
```javascript
import { apiGet, apiPost, apiPostReturn, apiPatch, apiPostReturnId, createDocumentRequest, DocRequestType, DocTemplateType, writeAuditLog, EntitySets, ContractFamily, MsaStatus, AuditActionType, formatCurrency, fetchMyWIPProposals, updateMsa, resolveTemplateId } from './portalApi';
```

**Proposed edit (import):**
```javascript
import { apiGet, apiPost, apiPostReturn, apiPatch, apiPostReturnId, createDocumentRequest, DocRequestType, DocTemplateType, writeAuditLog, EntitySets, ContractFamily, MsaStatus, AuditActionType, formatCurrency, fetchMyWIPProposals, updateMsa, resolveTemplateId, getEnvVar } from './portalApi';
```

**Rationale:** Matches `recommendedFix` exactly. Three coupled changes: (1) add `getEnvVar` to the named imports from `./portalApi`; (2) wrap the vendor lookup in a priority check — try `dcfg_decades_vendor_id` from dcfg_configs first; (3) preserve the "first active vendor" fallback for tenants that have not seeded the config row, AND emit a `console.warn` breadcrumb when the fallback fires so the operator can grep logs for missing-config situations.

**Schema verification:** I checked the dcfg_vendors schema via `reference_database_bible.json` for a canonical flag column (e.g., `dcfg_is_decades_vendor`). No such column exists — the only matching column is `dcfg_primary_contact` which is unrelated. Confirms the finding's recommendation to use a `dcfg_configs` row rather than a schema flag.

**Operator note (per the task directive "if the recommendedFix is vague, propose the most conservative fix"):** The recommendedFix was explicit, so the conservative-preservation note does not apply here. But the operator DOES need to create the `dcfg_decades_vendor_id` row in `dcfg_configs` on each environment before this edit takes effect — otherwise the fallback fires every run. Suggested seed value: the GUID of the "Decades Construction Group" vendor record in Dataverse. Until the row is seeded, behavior is identical to today (first-active fallback) with an added console.warn per proposal-generate call.

**Risk:** Low. The `getEnvVar` call is synchronous (reads from a module-level config cache populated at boot) so no new awaits are introduced. The fallback path is byte-identical to the current code. The only new failure mode is if `getEnvVar` returns a GUID that does NOT match any vendor in the target tenant — in that case the subsequent apiPatch at lines 386-390 would 404. Same failure mode exists today if the tenant has zero active vendors (the current code would assign `vendorId=null` and skip the patch silently); the new path would 404 loudly which is actually better.

**Depends on:** none

---

### CR-2026-04-09-0284 — ProgramDetail loadProgram silently swallows load errors

**File:** src/screens/ProgramDetail.jsx
**Line(s):** 20-47
**Severity:** P2
**Category:** error-handling

**Current code (lines 20-47):**
```javascript
export default function ProgramDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const [program, setProgram] = useState(null);
  const [projects, setProjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({});
  const [saving, setSaving] = useState(false);

  const loadProgram = useCallback(() => {
    Promise.all([
      fetchProgramDetail(id),
      fetchProjectsByProgram(id).catch(() => ({ value: [] })),
    ]).then(([pg, pj]) => {
      setProgram(pg);
      setProjects(pj?.value ?? []);
      setForm({
        dcfg_name: pg.dcfg_name || '',
        dcfg_program_code: pg.dcfg_program_code || '',
        dcfg_budget_total: pg.dcfg_budget_total ?? '',
        dcfg_start_date: toIsoDate(pg.dcfg_start_date),
        dcfg_end_date: toIsoDate(pg.dcfg_end_date),
      });
      setLoading(false);
    }).catch(() => setLoading(false));
  }, [id]);
```

**Proposed edit:**
```javascript
export default function ProgramDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const [program, setProgram] = useState(null);
  const [projects, setProjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({});
  const [saving, setSaving] = useState(false);

  const loadProgram = useCallback(() => {
    Promise.all([
      fetchProgramDetail(id),
      fetchProjectsByProgram(id).catch(() => ({ value: [] })),
    ]).then(([pg, pj]) => {
      setProgram(pg);
      setProjects(pj?.value ?? []);
      setForm({
        dcfg_name: pg.dcfg_name || '',
        dcfg_program_code: pg.dcfg_program_code || '',
        dcfg_budget_total: pg.dcfg_budget_total ?? '',
        dcfg_start_date: toIsoDate(pg.dcfg_start_date),
        dcfg_end_date: toIsoDate(pg.dcfg_end_date),
      });
      setLoadError(null);
      setLoading(false);
    }).catch(e => {
      // CR-2026-04-09-0284: surface load errors so a real failure is
      // distinguishable from a genuine not-found. Mirrors batch 04 CR-0251.
      console.warn('ProgramDetail load failed:', e);
      setLoadError(e?.message || 'Failed to load program');
      toast.show('err', 'Failed to load program — ' + (e?.message || 'try again'));
      setLoading(false);
    });
  }, [id, toast]);
```

**Current code (render guards, lines 85-86):**
```javascript
  if (loading) return <div className="page-content"><div style={{ height: '300px', backgroundColor: '#F1F5F9', borderRadius: '8px' }} /></div>;
  if (!program) return <div className="page-content"><p>Program not found.</p></div>;
```

**Proposed edit:**
```javascript
  if (loading) return <div className="page-content"><div style={{ height: '300px', backgroundColor: '#F1F5F9', borderRadius: '8px' }} /></div>;
  if (loadError) return <div className="page-content"><div className="warn-banner">Unable to load program: {loadError}</div></div>;
  if (!program) return <div className="page-content"><p>Program not found.</p></div>;
```

**Rationale:** Matches `recommendedFix` and the CR-0251 pattern from batch 04. Adds `loadError` state, surfaces it via both toast (transient notification) AND a persistent `warn-banner` (so a user who misses the toast still has a visible indicator). The `loadError` banner takes precedence over the `!program` not-found branch, so a genuine 404 still reaches the "Program not found." message while a network/server failure reaches the warn-banner.

Adds `toast` to the `loadProgram` useCallback deps (per the same lint-conformance note from batch 04 CR-0247). `toast` is a stable ref so this does not cause re-render churn.

**Risk:** Zero. Happy path is unchanged (catch not triggered, loadError stays null, warn-banner not rendered). Genuine not-found path still works (load succeeds, setProgram(null) via the apiGet returning null, `!program` fallback renders).

**Depends on:** sibling to batch 04 CR-2026-04-09-0251 (same pattern, different file)

---

### CR-2026-04-09-0237 — FieldName default bg '#fff' fails on non-white parents

**File:** src/FieldName.jsx
**Line(s):** 17-34 (Fn default + nameStyle)
**Severity:** P2
**Category:** ui-handoff

**Current code:**
```javascript
export default function Fn({ f, bg = '#fff', children }) {
  if (!f) return children || null;

  // When children are null/undefined/empty string, return null so parent
  // fallback logic (e.g. `value || '—'`) works correctly
  if (children == null || children === '') return null;

  const debug = isDebugActive();
  const nameStyle = {
    fontSize: 9,
    fontFamily: "'IBM Plex Mono', monospace",
    fontWeight: 400,
    letterSpacing: '0.02em',
    marginLeft: 4,
    color: debug ? '#3b82f6' : (bg || '#fff'),
    userSelect: 'all',
    transition: 'color 0.15s',
  };
```

**Proposed edit:**
```javascript
export default function Fn({ f, bg, children }) {
  if (!f) return children || null;

  // When children are null/undefined/empty string, return null so parent
  // fallback logic (e.g. `value || '—'`) works correctly
  if (children == null || children === '') return null;

  const debug = isDebugActive();
  // CR-2026-04-09-0237: when bg is not explicitly passed, render transparent
  // so the schema name inherits the parent's background automatically and
  // cannot smudge over non-white parents. Previous default was '#fff' which
  // failed on navy / amber / slate backgrounds. The explicit bg override still
  // works for callers that need a specific color match.
  const nameStyle = {
    fontSize: 9,
    fontFamily: "'IBM Plex Mono', monospace",
    fontWeight: 400,
    letterSpacing: '0.02em',
    marginLeft: 4,
    color: debug ? '#3b82f6' : (bg || 'transparent'),
    userSelect: 'all',
    transition: 'color 0.15s',
  };
```

**Rationale:** The finding's two options were (1) a CSS variable + `currentColor` trick (requires parent CSS wiring, too invasive for this batch), or (2) a per-screen explicit-bg audit (Phase 3 scope). This proposal is a THIRD narrower option: change the default from `'#fff'` to `'transparent'` so when a caller does NOT pass `bg`, the text renders with `color: transparent` — literally invisible, and specifically invisible regardless of the parent background color. The `bg || 'transparent'` fallback preserves the existing opt-in: `<Fn bg="#1B2A4A">` still paints navy.

This trades one known failure mode (visible white smudge over non-white backgrounds) for a different but benign one: when `bg` is omitted, the schema name is no longer selectable into visibility via the background-matching trick — but it IS still selectable via mouse highlight (the OS selection highlight paints over `transparent` text the same way it paints over `#fff` text), AND it IS still visible in debug mode (`?dcfg_debug=1` forces `#3b82f6`). Per feedback_field_names_invisible.md the contract is "invisible until highlight" — this edit KEEPS the highlight trigger working and REMOVES the smudge failure mode.

The matching `FnTh` table-header wrapper below (lines 48-64) uses `bg = '#1B2A4A'` as its default, which is specifically for the navy table header background. I am NOT changing that default — FnTh is opt-in table-header context where the default is meaningful.

**Risk:** Low-medium. The edit changes the visual behavior for any callsite that passes no `bg` AND expects the old `#fff` default. On a white parent, the old code painted the schema name white (invisible); the new code paints it transparent (also invisible) — identical. On a non-white parent, the old code painted it white (smudge, bug); the new code paints it transparent (correct). The only observable regression I can imagine is a site where someone was relying on the smudge as a debug aid — but debug mode exists for exactly that use case.

**Operator note:** The finding's `recommendedFix` explicitly said "No fix in this batch" and deferred to Phase 3. I am proposing this narrower in-place fix anyway because it's a three-character change (`'#fff'` → `'transparent'` plus dropping the default-value clause on the prop destructure) that eliminates a whole class of smudge bugs without requiring a per-screen audit. If the operator wants to strictly honor the finding's "no fix in this batch" verdict, reject this finding and the rest of batch 05 proceeds fine without it.

**Depends on:** none

---

### CR-2026-04-09-0283 — NoraCopilot hardcodes Copilot Studio webchat URL with environment GUID

**File:** src/screens/NoraCopilot.jsx
**Line(s):** 5-10
**Severity:** P2
**Category:** ui-handoff

**Current code:**
```javascript
import React from 'react';
import ErrorReporter from '../ErrorReporter.jsx';

var NAVY = '#1B2A4A';
var AMBER = '#D4A017';
var WEBCHAT_URL = 'https://copilotstudio.microsoft.com/environments/6ee0cd74-e2b2-e429-ac4b-27123cd20d19/bots/cua_agent_iRkq7/webchat?__version__=2';
```

**Proposed edit:**
```javascript
import React from 'react';
import ErrorReporter from '../ErrorReporter.jsx';
import { getEnvVar } from '../portalApi.js';

var NAVY = '#1B2A4A';
var AMBER = '#D4A017';
// CR-2026-04-09-0283: read webchat URL from dcfg_configs per the loadConfig
// mandate in CLAUDE.md. Falls back to the hardcoded URL for tenants that have
// not seeded the config row — matches current behavior. Seed
// dcfg_nora_webchat_url in dcfg_configs on each environment to allow per-stage
// Copilot Studio bots without a SPA rebuild.
var WEBCHAT_URL_FALLBACK = 'https://copilotstudio.microsoft.com/environments/6ee0cd74-e2b2-e429-ac4b-27123cd20d19/bots/cua_agent_iRkq7/webchat?__version__=2';
var WEBCHAT_URL = getEnvVar('dcfg_nora_webchat_url') || WEBCHAT_URL_FALLBACK;
```

**Rationale:** Matches `recommendedFix`. Three coupled changes: (1) import `getEnvVar` from `../portalApi.js`; (2) rename the hardcoded constant to `WEBCHAT_URL_FALLBACK` so it's clearly the fallback-of-last-resort; (3) compute `WEBCHAT_URL` at module load time by preferring the `dcfg_nora_webchat_url` config row, falling back to the hardcoded URL. No other code in the file changes — the `src: WEBCHAT_URL` assignment in the iframe React.createElement at line 35 remains identical.

**Note on module-level vs component-level read:** `getEnvVar` is computed at module load time, which means the value is fixed once dcfg_configs has been bootstrapped but BEFORE React renders. This matches the pattern used by other SPA modules (see SensorBanner, Operations). If the operator wants per-render resolution (e.g., to hot-reload webchat URLs on config changes without a browser reload), the read can be moved inside the component body — but that's a different semantics and a Phase 3 consideration.

**Risk:** Low. Per-stage deploys still use the same bundle; environments that haven't seeded the config row see identical behavior. Environments that HAVE seeded the row see the config value. The fallback is byte-identical to the current hardcoded URL, so zero-config Test environment is unaffected.

**Operator note:** Seed `dcfg_nora_webchat_url` in `dcfg_configs` on Test/Stage/Prod before deploying. Until seeded, every environment renders the Test bot (current behavior). This is an additive configuration migration, not a destructive one.

**Depends on:** none

---

## Approval options

Reply with:
- `approve batch` — execute all 13 proposed edits (2 pre-deferred findings are already landed, no edits)
- `approve <id1>,<id2>,...` — selective
- `reject <id>` — skip
- `reject batch` — cancel
- `hold` — park

**Housekeeping follow-up (out of scope for this batch):** Pre-deferred findings 0224 and 0231 should be marked `fixed` in `findings.json` by a later housekeeping pass, with `approvedIn` pointing to batch 01 and the corresponding SPA commit SHAs.
