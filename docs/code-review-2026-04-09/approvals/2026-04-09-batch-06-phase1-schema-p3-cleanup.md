# Batch 06 — Phase 1 Schema + P3 Cleanup

**Phase:** 1 (Schema fixes + unused-import + error-handling polish + small perf + data-integrity quick fix)
**Target:** SPA source under C:\DCFG\spa\dcfg-shell\src\
**Findings count:** 15 selected, 14 proposed for execution (1 pre-deferred — see below)
**Generated:** 2026-04-10T13:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-06-phase1-schema-p3-cleanup.md
**Predecessor batches:**
  - batch 01: approvals/2026-04-09-batch-01-phase1-shared.md (SPA commit 39f8efb)
  - batch 02: approvals/2026-04-09-batch-02-phase1-expansion.md (SPA commits 30c693b + c48949f)
  - batch 03: approvals/2026-04-09-batch-03-phase1-p2-cleanup.md (SPA commit e727a8b)
  - batch 04: approvals/2026-04-09-batch-04-phase1-errhandling-security.md (SPA commit dfd1efc)
  - batch 05: approvals/2026-04-09-batch-05-phase1-perf-auth-data.md (SPA commit 4250f9e)

## Housekeeping status transitions (NOT in this batch — operator action during approval)

The parent's pre-batch schema verification produced two status transitions that should be recorded in `findings.json` during approval, NOT executed as edits in this batch:

- **CR-2026-04-09-0293 — REJECT.** VendorDetail $select cites `dcfg_contact_name`, `dcfg_primary_contact`, and `dcfg_trade`. Schema-verified by parent: ALL THREE columns exist on `dcfg_vendor`. The finding's premise ("likely incorrect schema names") was based on the wrong assumption that Admin.jsx VendorsTab using `dcfg_primary_contact` was a contradiction — both columns coexist on the table. **Reject reason:** "schema-verified: dcfg_vendor.dcfg_contact_name, dcfg_vendor.dcfg_primary_contact, and dcfg_vendor.dcfg_trade all exist. Finding was based on the wrong assumption that the two contact columns were mutually exclusive."

- **CR-2026-04-09-0298 — DEFER-FUTURE.** Amendment financials paths `dcfg_original_amount`, `dcfg_prev_changes_amount`, `dcfg_current_amount`, `dcfg_change_amount`, `dcfg_approved_amount` in `fieldRegistry.js` lines 116-120 do NOT exist on `dcfg_contract` (parent verified). The only money-related columns on dcfg_contract are `dcfg_contract_fee` (Money), `dcfg_contract_fee_base` (Money), and `dcfg_amendment_sequence` (Integer). **Defer reason:** "schema-blocked: none of dcfg_original_amount, dcfg_prev_changes_amount, dcfg_current_amount, dcfg_change_amount, dcfg_approved_amount exist on dcfg_contract. Only dcfg_contract_fee_base, dcfg_contract_fee, and dcfg_amendment_sequence exist. Requires schema addition (5 new Money columns) OR amendment-math rewrite using contract fee delta across the amendment chain. Out of scope for Phase 1; flag for the amendment-flow design pass."

These two transitions are recorded here so the operator sees them during the batch review pass. Per the critical rules this doc does NOT modify findings.json — the housekeeping pass that records them is separate.

## Scope rules (from spec §4.6)

- Batch size = 15 selected, 14 effective (1 pre-deferred — see "Pre-deferred findings" below)
- All `batch` tier — no catalog-only entries
- Every proposed-edit finding has verbatim before-code + concrete after-code
- No new exports introduced — this batch is grab-bag cleanup, no module-surface changes

## Theme — six groups

This batch is the Phase 1 long-tail: schema fixes that came out of the parent's pre-batch verification, plus the residual P3 cleanups (unused imports, silent catches, micro-perf, a duplicate-column data-integrity nit) that did not fit into batches 03/04/05's themes.

- **Group A — Schema fixes (2 findings: 0299, 0279).** Two schema-derived data-integrity bugs in template + vendor land. 0299 rewrites the Vendor full address composite in `fieldRegistry.js` to use the actual `dcfg_address`/`dcfg_address_line2`/`dcfg_city`/`dcfg_state`/`dcfg_zip` columns (the existing paths reference fictitious `address1_line1` / `address1_city_state_zip` which never resolve). 0279 has expanded scope per the parent directive: schema verification confirmed Directory.jsx's use of singular `dcfg_trade` is CORRECT (no edit there), and the bug is in VendorList.jsx line 138 which defensively reads `v.dcfg_trades || v.dcfg_trade` — the plural fork is dead code referencing a non-existent column. Edit simplifies to just `v.dcfg_trade`. The other two file callouts in the original 0279 (MsaList.jsx, ProjectList.jsx) come up clean against current state — see the per-finding notes in Group A for the verbatim-current evidence.

- **Group B — Unused imports / dead destructure cleanup (4 findings: 0253, 0260, 0263, 0267).** Four straight removals: ContractList drops `isManager` from its usePortalUser destructure; MsaDetail drops `isAdmin, isManager`; MsaList drops both `FAMILY_MAP` and `usePortalUser` imports entirely; Onboarding's NewCasePanel drops a dead `useState(error)` declaration. None of these have functional consequences — they exist to keep the bundle and the lint output clean before external testing.

- **Group C — Error handling polish (4 findings: 0218, 0232, 0242, 0269).** Four bare-catch / console-only sites that need a minimum-viable breadcrumb. 0218 adds the hook count to the audit-hook-error console.warn so a buggy Nora observer is identifiable. 0232 replaces Toast's `.catch(function(){})` with a console.warn so audit-log failures inside the Toast itself are at least diagnosable. 0242 replaces SensorBanner's bare `catch {}` with a one-time console.warn (gated on a module flag so 30s polling doesn't spam the console). 0269 adds a toast to OnboardingDetail's `handleStepFieldSave` catch — the only handler in that file that did not surface failures to the user.

- **Group D — Small performance polish (3 findings: 0208, 0223, 0228).** Three React micro-perf wins. 0208 merges LocationManager's two `[]`-deps mount effects (appliance-type catalog + customer list) into one parallelized Promise.all. 0223 wraps NavPanel's per-render `CREATE_ACTIONS.filter(isVisible)` and `group.items.filter(isVisible)` in useMemo so they don't re-run on every render. 0228 wraps PortalUserProvider's context value in useMemo so context consumers stop re-rendering when the provider's parent re-renders.

- **Group E — Data integrity quick fix (1 finding: 0249).** ContractDetail's `reload()` $select clause lists `dcfg_contract_number` twice. Dataverse tolerates the duplicate, so this is a cosmetic fix — but it signals an unreviewed concatenation edit and should be cleaned up before Phase 2 audits the rest of the file.

- **Group F — Housekeeping check (1 finding: 0239).** Pre-batch verification of 0239's premise (ErrorReporter `userName` prop default `'unknown'`). Per the parent directive this finding may be auto-resolved by batch 01 CR-0202 (which exposed `userName` from usePortalUser). Verified status: NOT auto-resolved. ErrorReporter still receives `userName` as a PROP (not via context), so the upstream context export does not eliminate the prop default. The fix is still actionable: drop the prop, call usePortalUser inside ErrorReporter directly, drop the corresponding prop pass-throughs in NoraCopilot.jsx and App.jsx. Proposed below.

## Pre-deferred findings (1)

**CR-2026-04-09-0279 (Directory.jsx portion only) — DEFERRED (no-op).** The original finding flagged `Directory.jsx` line 68 as suspect. Schema verification confirms `dcfg_vendor.dcfg_trade` (singular) IS the correct column name and Directory.jsx is already using it. No edit to Directory.jsx in this batch. The finding ID 0279 is NOT pre-deferred entirely — the VendorList.jsx portion IS proposed for edit (see Group A). The Directory.jsx-specific portion is the no-op.

**Effective findings in this batch:** 14.

## Cross-finding dependencies

- **0279 → 0299.** Both touch schema-suspect data paths but in different files. Independent edits.
- **0223 → 0228.** Same file family (NavPanel + usePortalUser). NavPanel `isVisible` references `user` and the role helpers from usePortalUser; the 0228 useMemo wrap on PortalUserProvider's value object stabilizes the helper references that 0223 will memoize against. Apply 0228 first if executed selectively — but they're independent file edits and can land in either order.
- **0239 → 0232.** ErrorReporter (0239) and Toast (0232) both touch the audit-log diagnostic surface. Independent edits.
- All other findings are independent edits.

---

## Findings in this batch

### CR-2026-04-09-0299 — Vendor address composite references non-existent address1_* columns

**File:** src/screens/templates/fieldRegistry.js
**Line(s):** 65-75
**Severity:** P2
**Category:** data-integrity

**Current code:**
```javascript
  { label: 'Vendor full address',   path: 'dcfg_vendor.dcfg_address_composite',   category: FieldCategory.VendorInformation, isComposite: true,
    composite: {
      format: '{street}, {city_state_zip}',
      parts: [
        { key: 'street',        label: 'Vendor street address',     path: 'dcfg_vendor.address1_line1' },
        { key: 'city_state_zip', label: 'Vendor city, state, zip', path: 'dcfg_vendor.address1_city_state_zip' },
      ]
    }
  },
  { label: 'Vendor street address',    path: 'dcfg_vendor.address1_line1',           category: FieldCategory.VendorInformation, isComposite: false },
  { label: 'Vendor city, state, zip',  path: 'dcfg_vendor.address1_city_state_zip',  category: FieldCategory.VendorInformation, isComposite: false },
```

**Proposed edit:**
```javascript
  // CR-2026-04-09-0299: rewrite vendor address paths to use the actual dcfg_*
  // columns on dcfg_vendor. Schema verification (parent batch 06 pre-check)
  // confirmed dcfg_vendor has dcfg_address, dcfg_address_line2, dcfg_city,
  // dcfg_state, dcfg_zip — and NO address1_* columns at all. The previous
  // paths (address1_line1, address1_city_state_zip) resolved to undefined,
  // so every template using "Vendor full address" or its parts produced blanks.
  { label: 'Vendor full address',   path: 'dcfg_vendor.dcfg_address_composite',   category: FieldCategory.VendorInformation, isComposite: true,
    composite: {
      format: '{street}, {city_state_zip}',
      parts: [
        { key: 'street',         label: 'Vendor street address',     path: 'dcfg_vendor.dcfg_address' },
        { key: 'city_state_zip', label: 'Vendor city, state, zip',   path: 'dcfg_vendor.dcfg_city, ${dcfg_vendor.dcfg_state} ${dcfg_vendor.dcfg_zip}' },
      ]
    }
  },
  { label: 'Vendor street address',    path: 'dcfg_vendor.dcfg_address',           category: FieldCategory.VendorInformation, isComposite: false },
  { label: 'Vendor city, state, zip',  path: 'dcfg_vendor.dcfg_city, ${dcfg_vendor.dcfg_state} ${dcfg_vendor.dcfg_zip}',  category: FieldCategory.VendorInformation, isComposite: false },
```

**Rationale:** Schema verification (parent pre-check) confirmed `dcfg_vendor` has the columns `dcfg_address`, `dcfg_address_line2`, `dcfg_city`, `dcfg_state`, `dcfg_zip` and NO `address1_*` columns. The previous paths resolved to undefined at every document-generation pass, so every template using "Vendor full address" or its sub-parts produced blank text. The edit:

1. Replaces the `street` part path from `dcfg_vendor.address1_line1` → `dcfg_vendor.dcfg_address`. (`dcfg_address_line2` is intentionally NOT included in the street here — the street part is the line-1 only; templates that want suite/unit can map `dcfg_vendor.dcfg_address_line2` separately. If a follow-up wants to concat both, that's a registry-shape change beyond this fix.)
2. Replaces the `city_state_zip` part path from `dcfg_vendor.address1_city_state_zip` → a concatenated template-string path `dcfg_vendor.dcfg_city, ${dcfg_vendor.dcfg_state} ${dcfg_vendor.dcfg_zip}` which the registry's path resolver expands to "City, ST 12345" at generation time. Same template-string convention used elsewhere in the registry.
3. Applies the same two path fixes to the standalone `Vendor street address` and `Vendor city, state, zip` entries on lines 74-75 so any template referencing those labels directly (not via the composite) also gets the right column.

**Risk:** Low-medium. Templates that currently produce blanks for these labels will now produce real text — a strict improvement at document-generation time. However, two failure modes to flag for the operator:

(a) The path resolver in the DocGen V4 flow needs to handle the template-string `${...}` syntax in path values. If the resolver only does dot-walks (no `${}` interpolation), the new `city_state_zip` path will resolve to literal `"dcfg_city, ${dcfg_state} ${dcfg_zip}"`. Operator should verify the resolver before approval — if interpolation is not supported, the alternative is to make `city_state_zip` a sub-composite with three sub-parts and use the `format` string for concatenation (matches the same pattern as the parent composite at line 66 above).

(b) Vendors with NULL state or zip will produce dangling commas or trailing whitespace. The DocGen flow should handle that downstream (skip-if-null in the merge-field expansion).

**Operator note:** This edit assumes the registry's path resolver supports `${...}` interpolation. If it does NOT, replace the `city_state_zip` part with a nested composite (three sub-parts: dcfg_city, dcfg_state, dcfg_zip; format `'{city}, {state} {zip}'`). Flag if the resolver behavior is unclear and I'll switch to the nested-composite form.

**Depends on:** none

---

### CR-2026-04-09-0279 — Vendor `dcfg_trades` plural references in VendorList — defensive dead-code path

**File:** src/screens/VendorList.jsx
**Line(s):** 138 (read site)
**Severity:** P2
**Category:** data-integrity

**Drift note:** The original finding was filed against `src/Directory.jsx` line 68 with VendorList/MsaList/ProjectList as cross-references. Schema verification (parent pre-check) inverted the conclusion — `dcfg_vendor.dcfg_trade` (singular) IS the correct column name, and Directory.jsx is correct. The actual bug is the inverse: VendorList line 138 defensively reads `v.dcfg_trades || v.dcfg_trade`, where the plural fork is dead code referencing a non-existent column. The other two cross-referenced files (MsaList, ProjectList) come up clean against current state — see "MsaList / ProjectList drift notes" below. Also note the finding cites `src/VendorList.jsx` but the actual current path is `src/screens/VendorList.jsx` (file moved during a previous refactor).

**Current code (lines 73-76, $select context — verified clean):**
```javascript
  useEffect(function () {
    apiGet('/dcfg_vendors?$select=dcfg_vendorid,dcfg_display_name,dcfg_legal_name,dcfg_address,dcfg_city,dcfg_state,dcfg_email,dcfg_phone,dcfg_trade,dcfg_active_flag&$orderby=dcfg_display_name asc&$top=500')
      .then(function (r) { setVendors(r && r.value ? r.value : []); setLoading(false); })
      .catch(function () { setLoading(false); });
  }, []);
```

The `$select` clause already uses singular `dcfg_trade` — no edit needed at line 74.

**Current code (line 138 — the actual bug site):**
```javascript
      // Trade filter
      if (distTrade) {
        var vendorTrades = (v.dcfg_trades || v.dcfg_trade || '').toLowerCase();
        if (!vendorTrades.includes(distTrade.toLowerCase())) return false;
      }
```

**Proposed edit:**
```javascript
      // Trade filter
      // CR-2026-04-09-0279: dcfg_vendor.dcfg_trades (plural) does not exist on
      // the table. Schema verification confirmed the column is dcfg_trade (singular).
      // The defensive `v.dcfg_trades || v.dcfg_trade` fork was dead code reading
      // an undefined property. Simplify to the singular column.
      if (distTrade) {
        var vendorTrades = (v.dcfg_trade || '').toLowerCase();
        if (!vendorTrades.includes(distTrade.toLowerCase())) return false;
      }
```

**MsaList drift notes:** The original finding cited `MsaList.jsx:62` as a sibling site referencing `dcfg_trades`. Verified current state at `src/screens/MsaList.jsx` line 46 — the actual $select is `dcfg_msaid,dcfg_name,dcfg_status,dcfg_exhibit_type,dcfg_location_count,dcfg_location_list,dcfg_total_monthly` — there is no `dcfg_trades` reference anywhere in MsaList (including the line 62 location, which is now a `.catch` block). The MSA list was refactored away from trades entirely (per the file's own header comment: "No budget/amendments/trades."). NO edit to MsaList for this finding. (MsaList still gets an edit in this batch — see CR-2026-04-09-0263 for the unused-import cleanup.)

**ProjectList drift notes:** The original finding cited `ProjectList.jsx:25` as a TRADES list. Verified current state at `src/screens/ProjectList.jsx` line 25 — it IS a JS constant array of trade name strings (`['Alarm','Carpentry/Framing','Concrete', ...]`) used by the New Project picker UI, NOT a column reference. Per the parent directive ("If it's a JS constant ... leave it alone"), NO edit to ProjectList. There is also a line 17 `searchFields = [..., 'dcfg_trades', ...]` constant which IS read by useTableControls against project rows; but that consumes `dcfg_project.dcfg_trades` (a different table from dcfg_vendor), and project-table schema is OUT OF SCOPE for the parent's vendor schema verification. Flagged as an operator-attention item below.

**Rationale:** Matches the inverted conclusion of `recommendedFix`. Three coupled wins:

1. The dead `v.dcfg_trades` fork is removed — it was reading an undefined property and falling through to `v.dcfg_trade` on every row, so functional behavior is unchanged but the dead code is eliminated.
2. The bug is recorded with a CR-comment so a future grep finds the rationale.
3. The lint output is cleaner — no more "always undefined" warnings on the plural fork.

**Risk:** Zero. The current code's behavior (`(undefined || v.dcfg_trade || '')`) is byte-identical to the new code's behavior (`(v.dcfg_trade || '')`).

**Depends on:** none

**Operator-attention items (not in this batch):**
- VendorList line 74's $select still pulls `dcfg_trade` (correct). No action needed.
- ProjectList line 17 includes `dcfg_trades` in `searchFields`, AND `portalApi.js` line 778 `fetchProjects()` includes `dcfg_trades` in its $select against `dcfg_project`. These reference a column on `dcfg_project` (not `dcfg_vendor`) and are OUT OF SCOPE for this batch's vendor schema verification. If `dcfg_project.dcfg_trades` does not exist either, that's a separate finding for Phase 2 to file.
- Directory.jsx — no edit (already correct per schema verification).

---

### CR-2026-04-09-0253 — ContractList imports `isManager` from usePortalUser but never uses it

**File:** src/screens/ContractList.jsx
**Line(s):** 21
**Severity:** P3
**Category:** handoff-cleanliness

**Current code:**
```javascript
export default function ContractList() {
  const navigate = useNavigate();
  const { isManager } = usePortalUser();
  const [contracts, setContracts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
```

**Proposed edit:**
```javascript
export default function ContractList() {
  const navigate = useNavigate();
  // CR-2026-04-09-0253: isManager was destructured but never used in the
  // component body. Removed to keep the lint output clean. If a future
  // admin-only action lands on this screen (compare ContractDetail.jsx
  // void/decline gating, batch 02 CR-0248), restore the destructure then.
  const [contracts, setContracts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
```

**Rationale:** Matches `recommendedFix`. Drops the unused destructure. The `usePortalUser` import on line 9 is also no longer needed after this edit — but verifying the import isn't referenced elsewhere in the file (it isn't; the only usage was the destructure on line 21).

**Risk:** Zero. No behavior change.

**Depends on:** none

**Operator note:** The `import { usePortalUser } from '../usePortalUser.jsx';` on line 9 should ALSO be removed since the only consumer was the destructure being dropped here. The proposed edit does not include the import line removal as a separate hunk to keep the diff focused — the import-removal edit is mechanical and the operator can apply it as a follow-up sweep, OR the edit can be expanded during execution to drop both lines. Flagged for visibility.

---

### CR-2026-04-09-0260 — MsaDetail destructures `isAdmin, isManager` but never uses them

**File:** src/screens/MsaDetail.jsx
**Line(s):** 28
**Severity:** P3
**Category:** handoff-cleanliness

**Current code:**
```javascript
export default function MsaDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { user, isAdmin, isManager } = usePortalUser();
  const toast = useToast();
```

**Proposed edit:**
```javascript
export default function MsaDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  // CR-2026-04-09-0260: isAdmin/isManager were destructured but never referenced
  // in the component body. Dropped per handoff-cleanliness sweep. If MSA edit
  // or generate actions should be admin-gated (recommendedFix option (a)),
  // file a follow-up finding and re-add the destructure with the gating.
  const { user } = usePortalUser();
  const toast = useToast();
```

**Rationale:** Matches the second option in `recommendedFix` ("If NO, drop the unused destructure"). The first option (gate Edit MSA / Generate MSA buttons behind `isAdmin()`) is a business-rule decision that should land as a separate finding with explicit operator approval — out of scope for a P3 cleanup batch.

**Risk:** Zero. No behavior change.

**Operator note:** If the operator decides MSA edit/generate SHOULD be admin-gated, file a follow-up finding referencing CR-2026-04-09-0248 (ContractDetail void/decline gating, batch 02) as the pattern. This batch deliberately defers the gating decision.

**Depends on:** none

---

### CR-2026-04-09-0263 — MsaList imports `FAMILY_MAP` and `usePortalUser` that are never referenced

**File:** src/screens/MsaList.jsx
**Line(s):** 9-10
**Severity:** P3
**Category:** handoff-cleanliness

**Current code:**
```javascript
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiGet, FAMILY_MAP } from '../portalApi.js';
import { usePortalUser } from '../usePortalUser.jsx';
import { useTableControls, SortIcon, searchInputStyle, sortableThStyle } from '../useTableControls.jsx';
import Fn from '../FieldName.jsx';
```

**Proposed edit:**
```javascript
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
// CR-2026-04-09-0263: dropped unused imports. FAMILY_MAP was a holdover from
// the previous MSA list design that exposed contract-family badges; the
// redesigned screen (see file header comment) does not display family at all.
// usePortalUser was never destructured in this file.
import { apiGet } from '../portalApi.js';
import { useTableControls, SortIcon, searchInputStyle, sortableThStyle } from '../useTableControls.jsx';
import Fn from '../FieldName.jsx';
```

**Rationale:** Matches `recommendedFix`. Two coupled drops: (1) `FAMILY_MAP` removed from the `portalApi.js` named import list (the file has zero references to FAMILY_MAP outside this import); (2) the entire `usePortalUser` import line removed (zero references in the file).

**Risk:** Zero. No behavior change.

**Depends on:** none

---

### CR-2026-04-09-0267 — Onboarding NewCasePanel declares `error` state that is never read or set

**File:** src/screens/Onboarding.jsx
**Line(s):** 315 (drift from finding's cited line 303 — see drift note)
**Severity:** P3
**Category:** handoff-cleanliness

**Drift note:** Finding cites line 303. Verified current state — the `useState(error)` declaration is at line 315 inside the `NewCasePanel` function (which starts at line 311). Line 303 is a `</tbody>` closing tag in the parent Onboarding component. The fix targets the same dead-code state in NewCasePanel; the line number drift is presumably due to edits between the audit pass and now.

**Current code:**
```javascript
function NewCasePanel({ onSave, onClose }) {
  const [customers, setCustomers] = useState([]);
  const [customerId, setCustomerId] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [loadingCust, setLoadingCust] = useState(true);
```

**Proposed edit:**
```javascript
function NewCasePanel({ onSave, onClose }) {
  const [customers, setCustomers] = useState([]);
  const [customerId, setCustomerId] = useState('');
  const [saving, setSaving] = useState(false);
  // CR-2026-04-09-0267: dropped the dead `error` state — neither `error` nor
  // `setError` was referenced anywhere in NewCasePanel. The panel's only
  // failure surface today is `toast.show('err', ...)` from the parent's
  // handleNewCase. If the panel grows its own error UI later, re-add then.
  const [loadingCust, setLoadingCust] = useState(true);
```

**Rationale:** Matches `recommendedFix`. Drops the dead state declaration. Verified by grepping the file: only references to `error` / `setError` in Onboarding.jsx are line 97 (the parent component's toast.show call which uses `err` parameter, not `error` state) and the dead useState declaration itself.

**Risk:** Zero. No behavior change.

**Depends on:** none

---

### CR-2026-04-09-0218 — _emitAuditHook iterates with try/catch but only console.warns

**File:** src/portalApi.js
**Line(s):** 288 (drift from finding's cited line 270 — see drift note)
**Severity:** P3
**Category:** error-handling

**Drift note:** Finding cites line 270. Verified current state — `_emitAuditHook` is now defined at line 288. Line 270 is now inside the `apiDelete` body. Same function, fixed via current line numbers below.

**Current code:**
```javascript
const _auditHooks = [];
export function onAuditEvent(fn) { _auditHooks.push(fn); return () => { const i = _auditHooks.indexOf(fn); if (i >= 0) _auditHooks.splice(i, 1); }; }
function _emitAuditHook(raw, normalized) { for (const fn of _auditHooks) { try { fn({ raw, normalized }); } catch(e) { console.warn('Audit hook error:', e); } } }
```

**Proposed edit:**
```javascript
const _auditHooks = [];
export function onAuditEvent(fn) { _auditHooks.push(fn); return () => { const i = _auditHooks.indexOf(fn); if (i >= 0) _auditHooks.splice(i, 1); }; }
// CR-2026-04-09-0218: include the hook index + normalized event type in the
// warn message so a buggy Nora-style observer is easier to identify when
// debugging. Silent failure of audit hooks is intentional (a buggy observer
// must NEVER break the audit log path), so the catch stays — only the message
// is enriched.
function _emitAuditHook(raw, normalized) {
  for (let i = 0; i < _auditHooks.length; i++) {
    try { _auditHooks[i]({ raw, normalized }); }
    catch (e) { console.warn('[portalApi] audit hook #' + i + ' failed (action=' + (normalized?.dcfg_action_type ?? '?') + '):', e); }
  }
}
```

**Rationale:** Matches the optional polish in `recommendedFix` ("include the normalized event type in the warn message"). Adds two pieces of context to the warn message: (1) the index of the failing hook (so if Nora installs three observers, the developer can tell which one threw), (2) the normalized action_type so the developer knows which kind of audit event triggered the failure. The for-of loop is rewritten as a numeric for-loop only because the index is now needed in the catch — no behavioral change to the iteration order.

**Risk:** Zero. The catch path is functionally identical (still silent at the user level, still console.warn at the developer level). Only the message string changes.

**Depends on:** none

---

### CR-2026-04-09-0232 — Toast writeAuditLog .catch silently swallows audit failures

**File:** src/Toast.jsx
**Line(s):** 33-39
**Severity:** P3
**Category:** error-handling

**Current code:**
```javascript
    if (type === 'err' || type === 'warn') {
      writeAuditLog({
        dcfg_target_table: 'spa_toast',
        dcfg_action_type: AuditActionType.DataUpdated,
        dcfg_performed_by: 'spa',
        dcfg_new_value: '[' + type.toUpperCase() + '] ' + message + ' | URL: ' + window.location.hash
      }).catch(function(){});
    }
```

**Proposed edit:**
```javascript
    if (type === 'err' || type === 'warn') {
      writeAuditLog({
        dcfg_target_table: 'spa_toast',
        dcfg_action_type: AuditActionType.DataUpdated,
        dcfg_performed_by: 'spa',
        dcfg_new_value: '[' + type.toUpperCase() + '] ' + message + ' | URL: ' + window.location.hash
      }).catch(function(e){
        // CR-2026-04-09-0232: don't surface to the user (the original toast
        // is already on screen), but leave a console breadcrumb so a broken
        // audit-log path is diagnosable from the dev console.
        console.warn('[Toast] audit log failed for ' + type + ' toast:', e);
      });
    }
```

**Rationale:** Matches `recommendedFix`. Replaces the empty `function(){}` with a console.warn that includes the toast type so the developer can correlate failed audit writes with the user-visible toast that triggered them. Does NOT surface to the user — the original error/warn toast is already showing, so a second user notification would be confusing noise.

The recommendedFix's secondary suggestion ("expose this failure to the ErrorReporter buffer so it shows up in the Nora panel error count") is intentionally NOT done in this edit, because routing the audit-log failure into the error buffer would create a feedback loop: error-toast → audit-log fails → error buffer increments → Nora red dot → user reports error → ErrorReporter writes audit log → audit log fails → ... The plain console.warn is the safer breadcrumb.

**Risk:** Zero. The catch behavior is functionally identical (still swallows, no user impact). Only the diagnostic surface changes.

**Depends on:** none

---

### CR-2026-04-09-0242 — SensorBanner top-level fetchAlerts catch is bare `catch {}`

**File:** src/SensorBanner.jsx
**Line(s):** 92-94
**Severity:** P3
**Category:** error-handling

**Current code:**
```javascript
      setAlerts(enriched);
    } catch {
      // Sensor readings table may not exist yet — fail silently
    }
  }, [dismissed]);
```

**Proposed edit:**
```javascript
      setAlerts(enriched);
    } catch (e) {
      // CR-2026-04-09-0242: sensor readings table may not exist yet — fail
      // silently for the user, but log the FIRST failure so a post-deploy
      // regression to dcfg_sensor_readings access is diagnosable. Subsequent
      // failures stay silent so the 30s poll doesn't spam the dev console.
      if (!_sensorBannerWarnedOnce) {
        _sensorBannerWarnedOnce = true;
        console.warn('[SensorBanner] fetchAlerts failed (subsequent failures suppressed):', e);
      }
    }
  }, [dismissed]);
```

**Current code (file-level — module top, around line 30):**

The proposed edit references a module-level flag `_sensorBannerWarnedOnce`. Add the flag declaration near the top of the file, alongside the other module-level constants. Verbatim insertion site:

```javascript
// CR-2026-04-09-0242: module-level guard so fetchAlerts only logs the first
// failure to the dev console (the 30s poll would otherwise spam).
let _sensorBannerWarnedOnce = false;
```

**Operator note:** I did NOT verbatim-quote the file's existing module-top region above because the exact insertion point depends on the import block layout — the only constraint is that the `let _sensorBannerWarnedOnce = false;` declaration must be at module scope (not inside the component) so it persists across re-renders and across the `setInterval` ticks. Place it immediately after the imports and before the component declaration.

**Rationale:** Matches `recommendedFix`. The "log once, suppress thereafter" pattern is the only safe approach for a polling component — a per-tick console.warn would generate one entry every 30 seconds, drowning the dev console for any user who leaves the SPA open. The first-failure log is enough to identify a post-deploy regression on the sensor readings path; the operator who notices the broken sensor banner can refresh the page to re-arm the once-flag if they need to confirm whether the failure is still happening.

The flag is module-scoped (not component-scoped) intentionally: a component-scope `useRef` would reset on every SensorBanner unmount/remount, which happens on most route changes, defeating the once-per-session intent.

**Risk:** Zero. The catch behavior is functionally identical (still silent at the user level, still loops on failure). Only the first-failure diagnostic surface changes.

**Depends on:** none (sibling pattern to Operations.jsx CR-0271 — same once-flag treatment, different file)

---

### CR-2026-04-09-0269 — handleStepFieldSave logs to console only, no toast

**File:** src/screens/OnboardingDetail.jsx
**Line(s):** 285-296
**Severity:** P3
**Category:** error-handling

**Current code:**
```javascript
  async function handleStepFieldSave(step, field, value) {
    setSaving(true);
    try {
      await apiPatch(`/${EntitySets.onboardingChecks}(${step.dcfg_onboarding_checklistid})`, {
        [field]: value || null,
      });
      loadCase();
    } catch (err) {
      console.error('Step field save failed:', err);
    }
    setSaving(false);
  }
```

**Proposed edit:**
```javascript
  async function handleStepFieldSave(step, field, value) {
    setSaving(true);
    try {
      await apiPatch(`/${EntitySets.onboardingChecks}(${step.dcfg_onboarding_checklistid})`, {
        [field]: value || null,
      });
      loadCase();
    } catch (err) {
      // CR-2026-04-09-0269: surface save failures via toast so the admin
      // editing a step field doesn't think the save worked when it didn't.
      // Every other handler in this file uses the same pattern.
      console.error('Step field save failed:', err);
      toast?.show('err', 'Failed to save field: ' + (err?.message || 'unknown error'));
    }
    setSaving(false);
  }
```

**Rationale:** Matches `recommendedFix`. Adds `toast?.show('err', ...)` alongside the existing `console.error`. The `toast?.` optional-chain matches the pattern used elsewhere in the same file (e.g., the `handleDelete` catch at line 280 in this file uses `toast?.show('err', ...)`). The `(err?.message || 'unknown error')` fallback handles the case where the error has no message property — same defensive pattern as the rest of the file.

**Risk:** Zero. The console.error path is preserved; the toast is purely additive.

**Depends on:** none

---

### CR-2026-04-09-0208 — LocationManager: two separate useEffects with [] deps for appliance types and customer load

**File:** src/LocationManager.jsx
**Line(s):** 431-451 (drift from finding's cited line 416 — see drift note)
**Severity:** P3
**Category:** performance

**Drift note:** Finding cites line 416 (effect 1) and line 434 (effect 2). Verified current state — effect 1 is at lines 431-446 and effect 2 is at lines 449-451. The functional pattern is unchanged.

**Current code:**
```javascript
  // Load appliance type catalog on mount
  useEffect(() => {
    (async () => {
      try {
        const r = await apiGet(
          `/${EntitySets.applianceTypes}?$select=dcfg_appliance_typeid,dcfg_name,dcfg_icon,dcfg_category,dcfg_expected_lifespan_years` +
          `&$filter=dcfg_is_active eq true&$orderby=dcfg_category asc,dcfg_name asc`
        );
        const types = (r?.value || []).map(t => ({
          id: t.dcfg_appliance_typeid, name: t.dcfg_name, icon: t.dcfg_icon || '📦',
          category: t['dcfg_category@OData.Community.Display.V1.FormattedValue'] || '',
          lifespan: t.dcfg_expected_lifespan_years || 10,
        }));
        if (types.length) setTypeTable(types);
      } catch { /* fallback stays */ }
    })();
  }, []);

  // Load customer list on mount
  useEffect(() => {
    loadCustomers();
  }, []);
```

**Proposed edit:**
```javascript
  // CR-2026-04-09-0208: merged two separate mount-only effects (appliance type
  // catalog + customer list) into a single Promise.all so the cold load fires
  // both queries in parallel. Same intent — both are mount-only loads with
  // independent failure modes — but one effect instead of two.
  useEffect(() => {
    (async () => {
      await Promise.all([
        (async () => {
          try {
            const r = await apiGet(
              `/${EntitySets.applianceTypes}?$select=dcfg_appliance_typeid,dcfg_name,dcfg_icon,dcfg_category,dcfg_expected_lifespan_years` +
              `&$filter=dcfg_is_active eq true&$orderby=dcfg_category asc,dcfg_name asc`
            );
            const types = (r?.value || []).map(t => ({
              id: t.dcfg_appliance_typeid, name: t.dcfg_name, icon: t.dcfg_icon || '📦',
              category: t['dcfg_category@OData.Community.Display.V1.FormattedValue'] || '',
              lifespan: t.dcfg_expected_lifespan_years || 10,
            }));
            if (types.length) setTypeTable(types);
          } catch { /* fallback stays */ }
        })(),
        loadCustomers(),
      ]);
    })();
  }, []);
```

**Rationale:** Matches `recommendedFix`. The two effects fire on mount, have independent failure modes (the appliance-type catch keeps the fallback table; loadCustomers has its own catch with a toast), and have no inter-dependency. Merging them into a single effect with Promise.all parallelizes the round-trips on cold load — a single network round-trip in wall-clock time instead of two sequential ones (the old code's two effects DID happen to fire concurrently because React batches mount effects, but the merged form makes the concurrency explicit and gives a single mount-effect lifecycle to reason about).

The two inner failure modes are preserved verbatim:

- Appliance-type fetch wraps in try/catch, falls back silently to the static `setTypeTable` initial value.
- `loadCustomers()` has its own try/catch with a `toast.show('err', ...)` (verified by reading lines 453-464).

**Risk:** Low. The behavior change is purely the lifecycle: instead of two `useEffect` registrations, there is one. React's strict-mode double-invoke behavior (mount/unmount/remount on dev only) will now fire the merged effect twice instead of firing each of the two effects twice — same cumulative number of API calls in dev mode, identical behavior in production.

**Depends on:** none

---

### CR-2026-04-09-0223 — NavPanel re-runs filter on every render — visibleItems/visibleActions not memoized

**File:** src/NavPanel.jsx
**Line(s):** 165-187
**Severity:** P3
**Category:** performance

**Current code (lines 156-187):**
```javascript
  return (
    <nav style={styles.nav} aria-label="Main navigation">

      {/* Decades Logo */}
      <a href="/#/" style={{ display: 'block', padding: '14px 20px 10px', borderBottom: '1px solid #E2E8F0', cursor: 'pointer' }} data-testid="nav-home">
        <img src="/logo.png" alt="Decades Construction & Facilities Group" style={{ width: '100%', maxWidth: '180px', display: 'block' }} />
      </a>

      {/* Create actions */}
      {(() => {
        const visibleActions = CREATE_ACTIONS.filter(a => isVisible(a));
        return visibleActions.length > 0 ? (
          <div style={styles.createZone}>
            <span style={styles.createLabel}>CREATE</span>
            <div style={styles.createButtons}>
              {visibleActions.map(action => (
                <a key={action.key} href={`/#${action.to}`} style={styles.createBtn}
                  data-testid={`nav-${action.key}`} title={action.label}>
                  <span style={styles.createIcon}>{action.icon}</span>
                  <span>{action.label}</span>
                </a>
              ))}
            </div>
          </div>
        ) : null;
      })()}

      {/* Nav groups */}
      <div style={styles.navGroups}>
        {NAV_GROUPS.map((group, gi) => {
          const visibleItems = group.items.filter(isVisible);
          if (visibleItems.length === 0) return null;
```

**Proposed edit:**

Two coupled changes — (1) compute the visible-actions and visible-groups arrays in useMemo before the return statement, (2) reference the memoized values in the JSX.

First, add the useMemo computations near the top of the component body, just before the `return (` on line 156. Insert this block immediately after the existing `if (loading) return ...` early-return on line 116:

```javascript
  // CR-2026-04-09-0223: memoize the visible-items computation so it doesn't
  // re-run on every render. isVisible reads `user`, the role helpers, and
  // getEnvVar (stable cache) — so dep array is just `user` plus the
  // collapsedGroups state for completeness (collapsedGroups doesn't affect
  // visibility but the computation is cheap and the dep simplifies reasoning).
  const visibleCreateActions = useMemo(
    () => CREATE_ACTIONS.filter(a => isVisible(a)),
    [user]  // eslint-disable-line react-hooks/exhaustive-deps -- isVisible reads user via closure
  );
  const visibleNavGroups = useMemo(
    () => NAV_GROUPS.map((group, gi) => ({
      group,
      gi,
      items: group.items.filter(isVisible),
    })).filter(g => g.items.length > 0),
    [user]  // eslint-disable-line react-hooks/exhaustive-deps -- isVisible reads user via closure
  );
```

Then update the JSX to consume the memoized arrays:

```javascript
      {/* Create actions */}
      {visibleCreateActions.length > 0 ? (
        <div style={styles.createZone}>
          <span style={styles.createLabel}>CREATE</span>
          <div style={styles.createButtons}>
            {visibleCreateActions.map(action => (
              <a key={action.key} href={`/#${action.to}`} style={styles.createBtn}
                data-testid={`nav-${action.key}`} title={action.label}>
                <span style={styles.createIcon}>{action.icon}</span>
                <span>{action.label}</span>
              </a>
            ))}
          </div>
        </div>
      ) : null}

      {/* Nav groups */}
      <div style={styles.navGroups}>
        {visibleNavGroups.map(({ group, gi, items: visibleItems }) => {
          if (visibleItems.length === 0) return null;
```

**Rationale:** Matches `recommendedFix`. Two coupled wins:

1. The `CREATE_ACTIONS.filter(a => isVisible(a))` call is now in useMemo with `[user]` as the dep, so it only re-runs when the portal user resolves (or changes role).
2. The `NAV_GROUPS.map(...).filter(...)` chain is also memoized; the result is a pre-filtered array of `{ group, gi, items }` objects, so the JSX `.map` no longer needs to re-run the per-group `.filter(isVisible)` on every render.

The `eslint-disable-next-line react-hooks/exhaustive-deps` comments are necessary because `isVisible` is a function declared inside the component body (not memoized), so React's exhaustive-deps lint would want it in the dep array — but isVisible's transitive deps are `user`, `getEnvVar` (stable), and the role helpers from usePortalUser (which themselves depend on `user`). So `[user]` is the correct minimal dep.

**Risk:** Low. The IIFE that wrapped the create-actions block is collapsed to a direct expression — same render output. The nav-groups map now iterates the pre-filtered array instead of the raw NAV_GROUPS array, but the final DOM is identical because empty groups (where `visibleItems.length === 0`) are pre-filtered out.

The one subtle behavior change: previously, the nav-groups map iterated all NAV_GROUPS and the inner `if (visibleItems.length === 0) return null;` filtered them at render time. The new code pre-filters in the useMemo, so `gi` (the group index) for the first VISIBLE group might be 1 instead of 0 if NAV_GROUPS[0] is empty. The current code uses `gi` only as a React key (line 191 `key={gi}`) — keys must be stable per item, and in the new structure they STILL are (the `gi` is still the original NAV_GROUPS index, captured at memo time). No regression.

**Depends on:** none

---

### CR-2026-04-09-0228 — PortalUserProvider value object created without useMemo

**File:** src/usePortalUser.jsx
**Line(s):** 67-71
**Severity:** P3
**Category:** performance

**Current code:**
```javascript
  const value = {
    user,
    loading,
    ...makeRoleHelpers(user),
  };

  return (
    <PortalUserContext.Provider value={value}>
      {children}
    </PortalUserContext.Provider>
  );
}
```

**Proposed edit:**
```javascript
  // CR-2026-04-09-0228: memoize the context value so consumers of usePortalUser
  // don't re-render every time PortalUserProvider's parent re-renders. The
  // helper functions returned by makeRoleHelpers close over `user`, so the
  // dep array is `[user, loading]` — same as the spread inputs.
  const value = useMemo(
    () => ({
      user,
      loading,
      ...makeRoleHelpers(user),
    }),
    [user, loading]
  );

  return (
    <PortalUserContext.Provider value={value}>
      {children}
    </PortalUserContext.Provider>
  );
}
```

**Current code (imports, line 1):**

The existing import statement at the top of the file needs to add `useMemo`. Verify the current import line first:

```javascript
import React, { createContext, useContext, useEffect, useState } from 'react';
```

**Proposed edit (imports):**
```javascript
import React, { createContext, useContext, useEffect, useState, useMemo } from 'react';
```

**Rationale:** Matches `recommendedFix` exactly. Standard React-Context performance pattern. The value object is now identity-stable across renders that don't change `user` or `loading`, so consumers of `usePortalUser()` (NavPanel, RoleGuard, every screen that calls `const { user } = usePortalUser()`) skip re-renders triggered by parent re-renders of PortalUserProvider.

The `[user, loading]` dep array is correct because `makeRoleHelpers(user)` is a pure function of `user` (verified by reading lines 113-126: it returns helper closures that read `user` and stable string constants from `WEB_ROLES`). When `user` changes, the spread re-runs and the value identity changes — which is correct, because consumers SHOULD re-render when the user changes role.

**Risk:** Zero. The value object's CONTENT is identical to the current code; only the identity stability changes. Consumers that depend on object identity (memoized children, React.memo wrappers) will now skip re-renders when nothing changed — strict improvement.

**Depends on:** none (interacts with CR-2026-04-09-0223 — memoizing NavPanel's visibleItems makes more sense once the upstream context value is also stable)

---

### CR-2026-04-09-0249 — ContractDetail reload() $select lists `dcfg_contract_number` twice

**File:** src/screens/ContractDetail.jsx
**Line(s):** 50
**Severity:** P3
**Category:** data-integrity

**Current code:**
```javascript
  async function reload() {
    const [cRes, lRes, aRes] = await Promise.all([
      apiGet(`/dcfg_contracts(${id})?$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_fee,dcfg_contract_date,dcfg_sent_date,dcfg_signed_date,dcfg_envelope_id,dcfg_description_of_service,dcfg_contractor_legal_name,dcfg_company,dcfg_contractor_address,dcfg_contractor_phone,dcfg_contractor_email,dcfg_owner_contact,dcfg_owner_email,dcfg_client_name,dcfg_document_url,dcfg_contract_number,dcfg_billing_frequency,dcfg_fiscal_year,dcfg_start_date,dcfg_end_date,dcfg_work_start_date,dcfg_work_completed_date&$expand=dcfg_msa_id($select=dcfg_msaid,dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)),dcfg_property_id($select=dcfg_propertyid,dcfg_name,dcfg_active_flag),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_insurance_expiration_date,dcfg_insurance_file_url)`),
```

**Proposed edit:**
```javascript
  async function reload() {
    // CR-2026-04-09-0249: removed the duplicate dcfg_contract_number from the
    // $select clause. Dataverse tolerated the duplicate, but it signaled an
    // unreviewed concatenation edit. The kept occurrence is the FIRST (just
    // after dcfg_contractid) — the second copy mid-list was the spurious one.
    const [cRes, lRes, aRes] = await Promise.all([
      apiGet(`/dcfg_contracts(${id})?$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_fee,dcfg_contract_date,dcfg_sent_date,dcfg_signed_date,dcfg_envelope_id,dcfg_description_of_service,dcfg_contractor_legal_name,dcfg_company,dcfg_contractor_address,dcfg_contractor_phone,dcfg_contractor_email,dcfg_owner_contact,dcfg_owner_email,dcfg_client_name,dcfg_document_url,dcfg_billing_frequency,dcfg_fiscal_year,dcfg_start_date,dcfg_end_date,dcfg_work_start_date,dcfg_work_completed_date&$expand=dcfg_msa_id($select=dcfg_msaid,dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)),dcfg_property_id($select=dcfg_propertyid,dcfg_name,dcfg_active_flag),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_insurance_expiration_date,dcfg_insurance_file_url)`),
```

**Rationale:** Matches `recommendedFix`. Drops the second `dcfg_contract_number,` from the comma-separated list. The first occurrence (just after `dcfg_contractid,`) is preserved. Dataverse tolerated the duplicate (no error), so this is purely a cosmetic / handoff-cleanliness fix to remove a stale-edit signal before Phase 2 audits the rest of this file.

**Risk:** Zero. Behavior is identical at the API level — Dataverse returns the same shape whether the column is requested once or twice. The only observable difference is the URL is shorter by 22 characters (`dcfg_contract_number,` = 21 chars + the leading comma).

**Depends on:** none

---

### CR-2026-04-09-0239 — ErrorReporter `userName` prop default 'unknown'

**File:** src/ErrorReporter.jsx
**Line(s):** 16-17
**Severity:** P3
**Category:** data-integrity

**Status:** OPEN — verification confirmed not auto-resolved.

**Verification (per the housekeeping check directive):** I read `src/ErrorReporter.jsx` lines 1-30 and confirmed the prop default `var userName = props.userName || 'unknown';` is still on line 17 of the current file. The default IS reachable: NoraCopilot.jsx line 38 passes `userName={userName}` where `userName = props && props.userName;` (line 21), and App.jsx line 318 passes `userName={user?.email || user?.name || 'unknown'}` from the parent. The chain is App.jsx → NoraCopilot → ErrorReporter, with `'unknown'` as the leaf default. Batch 01 CR-0202 added `userName` to the usePortalUser context exports — but ErrorReporter does NOT consume the context; it consumes a prop. So the upstream fix does NOT eliminate the prop default. Finding 0239 is still actionable. Proposing the fix below.

**Current code (ErrorReporter.jsx, lines 1-18):**
```javascript
/**
 * ErrorReporter.jsx — One-click error reporting inside Nora panel
 * Writes to dcfg_audit_logs via existing writeAuditLog(). No new tables.
 */
import React from 'react';
import { writeAuditLog, AuditActionType } from './portalApi.js';
import { getErrorBuffer, onErrorCountChange } from './debug/index';
import { useToast } from './Toast';

var AMBER_BG = '#FEF3C7';
var AMBER_BORDER = '#D4A017';
var AMBER_TEXT = '#8A6B12';
var GREEN = '#2D8659';
var RED = '#C0392B';

export default function ErrorReporter(props) {
  var userName = props.userName || 'unknown';
  var errorBuffer = getErrorBuffer();
```

**Proposed edit (ErrorReporter.jsx):**
```javascript
/**
 * ErrorReporter.jsx — One-click error reporting inside Nora panel
 * Writes to dcfg_audit_logs via existing writeAuditLog(). No new tables.
 */
import React from 'react';
import { writeAuditLog, AuditActionType } from './portalApi.js';
import { getErrorBuffer, onErrorCountChange } from './debug/index';
import { useToast } from './Toast';
import { usePortalUser } from './usePortalUser.jsx';

var AMBER_BG = '#FEF3C7';
var AMBER_BORDER = '#D4A017';
var AMBER_TEXT = '#8A6B12';
var GREEN = '#2D8659';
var RED = '#C0392B';

export default function ErrorReporter() {
  // CR-2026-04-09-0239: read user identity directly from usePortalUser
  // instead of taking a prop from the caller. The previous prop drilling
  // (App.jsx → NoraCopilot → ErrorReporter) coupled three layers to the
  // user shape; reading from context here decouples them. The 'unknown'
  // fallback is preserved for the rare case where context is not yet
  // hydrated when the component mounts.
  var portalUser = usePortalUser();
  var userName = (portalUser && (portalUser.userEmail || portalUser.userName)) || 'unknown';
  var errorBuffer = getErrorBuffer();
```

**Current code (NoraCopilot.jsx, line 38 — caller pass-through):**
```javascript
    // Error reporter (above iframe, always present when embedded)
    isEmbedded && React.createElement(ErrorReporter, { userName: userName }),
```

**Proposed edit (NoraCopilot.jsx, line 38):**
```javascript
    // Error reporter (above iframe, always present when embedded)
    // CR-2026-04-09-0239: ErrorReporter now reads identity from usePortalUser
    // directly — drop the userName prop pass-through.
    isEmbedded && React.createElement(ErrorReporter, null),
```

**Operator note (App.jsx):** The original chain also has App.jsx line 318 passing `userName={user?.email || user?.name || 'unknown'}` to NoraCopilot. After this edit, `NoraCopilot` itself still receives the `userName` prop from App.jsx but the prop becomes unused inside NoraCopilot (line 21 `var userName = props && props.userName;` is now dead code, since the only consumer was the line-38 pass-through). The cleanest follow-up is:

1. Drop the `var userName = props && props.userName;` line in NoraCopilot.jsx line 21.
2. Drop the `userName=...` prop from the App.jsx NoraCopilot render at line 318.

These two follow-up edits are NOT included in the proposed diff above to keep the change focused on the ErrorReporter restructure. Operator can apply them as a sweep, OR I can expand the proposed edit during execution to include all four hunks (ErrorReporter, NoraCopilot caller, NoraCopilot prop destructure cleanup, App.jsx prop pass cleanup). Flagged for visibility.

**Rationale:** Matches `recommendedFix`. ErrorReporter now reads user identity directly from usePortalUser instead of through a prop chain. The 'unknown' fallback is preserved for the edge case where usePortalUser returns a context with neither `userEmail` nor `userName` resolved (e.g., the very first render after mount, before the `useEffect` in PortalUserProvider has populated the user state).

The new code prefers `userEmail` over `userName` to match the existing App.jsx fallback order (`user?.email || user?.name || 'unknown'`) — keeping the audit-log `dcfg_performed_by` field consistent with what the rest of the SPA writes.

**Risk:** Low. Two failure modes to flag:

(a) ErrorReporter must be rendered INSIDE a `<PortalUserProvider>` for `usePortalUser()` to work. Verified by reading App.jsx — PortalUserProvider wraps the entire app at the root, so every render path that reaches ErrorReporter is inside the provider. No regression.

(b) The current code's `var userName = props.userName || 'unknown';` fell back to `'unknown'` only when the caller forgot to pass the prop. The new code falls back to `'unknown'` when usePortalUser returns null context (impossible — would throw) OR when both `userEmail` and `userName` are null on the user object. The latter happens only when the user is unauthenticated, in which case `'unknown'` is the right default.

**Depends on:** none (independent of CR-2026-04-09-0228 — the useMemo wrap on PortalUserProvider's value doesn't affect the consumer-side read here)

---

## Approval options

Reply with:
- `approve batch` — execute all 14 proposed edits (1 finding has Directory.jsx-only deferral; the VendorList portion of 0279 IS executed)
- `approve <id1>,<id2>,...` — selective
- `reject <id>` — skip
- `reject batch` — cancel
- `hold` — park

**Housekeeping follow-up (out of scope for this batch — operator action during approval pass):**
- CR-2026-04-09-0293 → mark `rejected` with the schema-verification reject reason at the top of this doc.
- CR-2026-04-09-0298 → mark `deferred-future` with the schema-blocked defer reason at the top of this doc.
- CR-2026-04-09-0279 (Directory.jsx portion) → no separate status change; the finding remains until the VendorList portion lands, then marks `fixed` with the relevant SPA commit.
