# Batch 02 — Phase 1 Expansion Fixes

**Phase:** 1 (expansion)
**Target:** Newly-tracked SPA files committed in spa/dcfg-shell at 39f8efb (49 files: modified screens, new screens, templates subdir, contracts subdir, wizards)
**Findings count:** 14 approved for this batch (2 P0 + 12 P1 — full P0+P1 open set from phase-1-expansion-audit; CR-0309 was 15th but is status=rejected, see count note)
**Generated:** 2026-04-09T00:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-02-phase1-expansion.md
**Predecessor batch:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-01-phase1-shared.md (commit 39f8efb in SPA repo, fixCommit back-filled at parent commit affe1c9)

## Count note

The task spec expected ~15 (2 P0 + 13 P1). Actual open expansion-audit P0+P1 set is 14 (2 P0 + 12 P1). The 15th P1, CR-2026-04-09-0309 (ContractsList.jsx dead-code duplicate), has status `rejected` in findings.json because it duplicates pre-seed CR-2026-04-09-0003. Selection criteria (`status == "open"`) therefore excludes it. The batch is complete and still fits under the ≤15 cap per spec §4.6.

## Scope rules (from spec §4.6)
- Batch size = 14 (under the 15 cap)
- All `batch` tier
- Every proposed edit has before/after code visible
- Sequencing: see cross-finding dependencies below

## Cross-finding dependencies

- **CR-0290 + CR-0291 + pre-seed CR-0209 (already fixed in batch 01):** the typo `dcfg_contract_fe` in `RFP_LIST_COLS` (portalApi.js, fixed in batch 01) was matched by the same typo in two CONSUMERS — `RfpDetail.jsx` and `RfpList.jsx`. The producer-side fix (0209) is in place; consumer-side fixes (0290, 0291) close the loop. Schema-coordinated. **IMPORTANT caveat:** the consumer-side semantics treat this as a boolean checklist marker (`Contract Fully Executed`), while the canonical name on `dcfg_contract` is a money column. See per-finding Rationale/Risk for the verification ask.

- **CR-0296 → CR-0301:** both reference the non-existent `dcfg_contract_value` column (engineering journal Sec 9). 0296 is in the static `FIELD_REGISTRY` array, 0301 is in the `getCompositeParts()` function in TemplateDetail.jsx. The path fix is the same (`dcfg_contract_value` → `dcfg_contract_fee`) and can be applied in either order; no runtime dependency between them.

- **CR-0296 + CR-0297:** both are Dataverse path corrections in the same file (`fieldRegistry.js`). No ordering dependency.

- **CR-0248 + CR-0255:** both fix the "admin-only action visible to every user" bug class, in two different screens. No shared dependency. CR-0248 adds `isAdmin()` guard in ContractDetail.jsx. CR-0255 replaces hardcoded `{true}` props with real function-call values in CustomerDetail.jsx. Both rely on `usePortalUser()`'s `isAdmin`/`isManager` being function returns (verified in usePortalUser.jsx:112-113).

- **CR-0243 → no dependencies.** Payload shape fix in Admin.jsx removeTemplate; the correct null-bind pattern is already in use at TemplateDetail.jsx:641.

- **CR-0259 → no dependencies.** Missing loader fix in MsaDetail.jsx; uses the inline re-fetch pattern from the same file's handleSaveEdit (line 101).

- **CR-0264 → no dependencies.** Outer try/catch fix in Onboarding.jsx loadCases.

- **CR-0254 → no runtime dependency.** Hardcoded LOGO_BASE; fix adds fallback to dcfg_configs via getEnvVar.

- **CR-0289 → CR-0290/0291 only by proximity.** 0289 fixes the `toast` call shape in RfpDetail.jsx. The 0290/0291 schema-name fixes are orthogonal; either order is safe.

- **CR-0292 (UserRolesTab)** is presented with two options (see finding block) because the underlying Web API accessibility is unverified. Operator should pick one at Gate 1b.

- **CR-0294 → no dependencies.** $select fix in VendorList.jsx.

---

## Findings in this batch

### CR-2026-04-09-0289 — toggleCheck calls `toast(...)` as a function, but toast is an object — TypeError on every checklist toggle

**File:** src/screens/RfpDetail.jsx
**Line(s):** 140, 142
**Severity:** P0
**Category:** error-handling

**Current code:**
```javascript
  const toggleCheck = async (key) => {
    const newVal = !rfp[key];
    try {
      await updateRfpPackage(id, { [key]: newVal });
      setRfp({ ...rfp, [key]: newVal });
      toast(`Updated: ${key.replace('dcfg_','').replace(/_/g,' ')}`, 'ok');
    } catch (e) {
      toast(e.message, 'err');
    }
  };
```

**Proposed edit:**
```javascript
  const toggleCheck = async (key) => {
    const newVal = !rfp[key];
    try {
      await updateRfpPackage(id, { [key]: newVal });
      setRfp({ ...rfp, [key]: newVal });
      toast.show('ok', `Updated: ${key.replace('dcfg_','').replace(/_/g,' ')}`);
    } catch (e) {
      toast.show('err', e.message);
    }
  };
```

**Rationale:** `const toast = useToast();` at line 45 returns an object with a `.show(level, msg)` method. The two call sites in `toggleCheck` invoke `toast(...)` directly, which throws `TypeError: toast is not a function`. Elsewhere in the same file (lines 95, 99, 108, 111) the code correctly uses `toast.show('ok', ...)` / `toast.show('err', ...)` — so the two broken sites are outliers, not a systemic pattern. The fix matches the in-file pattern and the conventional (level, msg) argument order used across SendQueue.jsx, ContractDetail.jsx, OnboardingDetail.jsx.

**Risk:** Zero — purely a call-shape fix. Optimistic `setRfp` on line 139 already runs before the toast, so the local UI state continues to update correctly; the fix only eliminates the console TypeError and restores the toast + audit-log write behaviors. Note that the finding text says "THERE IS NO `toast.show` call anywhere in this file" — that claim is incorrect; `toast.show` is used at lines 95/99/108/111. The finding's core bug (the broken `toggleCheck` sites) is still valid.

**Depends on:** none

---

### CR-2026-04-09-0296 — Field registry maps 'Contract value' to `dcfg_contract_value` — column does not exist (journal Sec 9)

**File:** src/screens/templates/fieldRegistry.js
**Line(s):** 109
**Severity:** P0
**Category:** data-integrity

**Current code:**
```javascript
  { label: 'Contract value',           path: 'dcfg_contract_value',      category: FieldCategory.WorkOrderTerms, isComposite: false },
```

**Proposed edit:**
```javascript
  { label: 'Contract value',           path: 'dcfg_contract_fee',        category: FieldCategory.WorkOrderTerms, isComposite: false },
```

**Rationale:** Per engineering journal Section 9 (Schema Quick Reference) and the portalApi.js header comment at line 13 (`dcfg_contract fee = dcfg_contract_fee (Money), NOT dcfg_contract_value`), the money column on `dcfg_contract` is `dcfg_contract_fee`. The field registry feeds template field mappings into the DocGen V4 flow, which resolves each `dcfg_dataverse_path` against the source record at document-generation time. A path that doesn't exist resolves to undefined → blank in the generated document. Keep the user-facing label `'Contract value'` unchanged to preserve familiarity in the template-editor dropdowns; only the backing path changes.

**Risk:** Any existing `dcfg_template_field` rows that previously mapped the 'Contract value' label will still reference the OLD path (`dcfg_contract_value`) in their `dcfg_dataverse_path` column — they're stored in Dataverse and don't auto-update when the registry changes. Post-deploy the operator should run a one-time UPDATE against `dcfg_template_field` to rename stored paths from `dcfg_contract_value` to `dcfg_contract_fee`. Note this as a Phase 3 follow-up — not part of this SPA-only batch.

**Depends on:** none (CR-0301 is a sibling fix to the same path in a different location; no ordering required)

---

### CR-2026-04-09-0243 — TemplateSection.removeTemplate clears customer lookup with `dcfg_customer_id: null` — wrong payload shape

**File:** src/screens/Admin.jsx
**Line(s):** 2104
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
  async function removeTemplate(tplId) {
    setAssigning(tplId);
    try {
      // Clear customer lookup by setting to null
      await apiPatch(`/${EntitySets.docTemplates}(${tplId})`, { dcfg_customer_id: null });
      writeAuditLog({ targetTable: 'dcfg_document_template', targetRecordId: tplId, actionType: AuditActionType.DataUpdated, performedBy: userEmail, newValue: 'Removed customer assignment — reverted to global' }).catch(() => {});
      onReload();
    } catch (err) { toast.show('err', 'Failed: ' + err.message); }
    setAssigning(null);
  }
```

**Proposed edit:**
```javascript
  async function removeTemplate(tplId) {
    setAssigning(tplId);
    try {
      // Clear customer lookup by setting to null (must use @odata.bind form)
      await apiPatch(`/${EntitySets.docTemplates}(${tplId})`, { 'dcfg_customer_id@odata.bind': null });
      writeAuditLog({ targetTable: 'dcfg_document_template', targetRecordId: tplId, actionType: AuditActionType.DataUpdated, performedBy: userEmail, newValue: 'Removed customer assignment — reverted to global' }).catch(() => {});
      onReload();
    } catch (err) { toast.show('err', 'Failed: ' + err.message); }
    setAssigning(null);
  }
```

**Rationale:** Dataverse lookup columns are nulled via the `@odata.bind` property name, not by sending the schema name with a null value. TemplateDetail.jsx:641 already uses the correct pattern (`updateBody['dcfg_customer_id@odata.bind'] = null;`). The current code either throws 400 ("Cannot convert null") or is silently ignored — either way, the customer link is never actually cleared. Users see "success" toast but the template stays linked to the customer.

**Risk:** Minimal. The property name change is the only diff. Audit log still writes. onReload() still fires. If the call previously happened to succeed (lookup cleared), it'll keep succeeding. If it previously silently failed, it'll now succeed correctly. One operator-side validation step: after deploy, click Remove on a customer-assigned template and confirm the template row shows as "global" in Admin → Custom Templates tab.

**Depends on:** none

---

### CR-2026-04-09-0248 — Void/Decline buttons visible to any user — comment says 'Admin only' but no role check wraps them

**File:** src/screens/ContractDetail.jsx
**Line(s):** 182-188
**Severity:** P1
**Category:** auth-role-checks

**Current code:**
```javascript
          {/* Void / Decline - Admin only, non-terminal */}
          {!isTerminal && (
            <>
              <button data-testid="btn-void" onClick={() => { setModal({ type:'void' }); setModalInput(''); }} style={btnDanger}>Void</button>
              <button data-testid="btn-decline" onClick={() => { setModal({ type:'decline' }); setModalInput(''); }} style={btnDanger}>Decline</button>
            </>
          )}
```

**Proposed edit:**
```javascript
          {/* Void / Decline - Admin only, non-terminal */}
          {!isTerminal && isAdmin() && (
            <>
              <button data-testid="btn-void" onClick={() => { setModal({ type:'void' }); setModalInput(''); }} style={btnDanger}>Void</button>
              <button data-testid="btn-decline" onClick={() => { setModal({ type:'decline' }); setModalInput(''); }} style={btnDanger}>Decline</button>
            </>
          )}
```

**Rationale:** Line 28 already destructures `isAdmin, isManager, userEmail` from `usePortalUser()`. Per `usePortalUser.jsx:112` `isAdmin` is a function (`() => hasRole('DCFG_Admin')`), so the gate is `isAdmin()`. Same pattern used in CustomerDetail ProgramsTab (line 506) and OnboardingDetail.jsx (line 619). The inline `{/* Admin only */}` comment already documents the intent — this just closes the hole so DOM actually hides the buttons for non-admins. Paired with route-level RoleGuard from CR-0219 (batch 01) for direct-URL defense in depth.

**Risk:** Non-admin users lose visible Void/Decline actions on ContractDetail (intended). Admin users see the same set they see today. The `import RoleGuard from '../RoleGuard.jsx';` at line 9 remains imported-but-unused; leaving the import in place is harmless (Vite tree-shakes unused imports in production). A follow-up cleanup can remove it; not part of this fix.

**Depends on:** none

---

### CR-2026-04-09-0254 — LOGO_BASE hardcoded to legacy portal URL `https://decades.powerappsportals.com/` — violates loadConfig mandate

**File:** src/screens/CustomerDetail.jsx
**Line(s):** 25
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
const LOGO_BASE = 'https://decades.powerappsportals.com/';
```

**Proposed edit:**
```javascript
// Logo base URL — read from dcfg_configs at runtime, fall back to the legacy
// decades portal so existing customer avatars keep loading until an operator
// adds dcfg_sp_logo_base_url to dcfg_configs. Follow-up: move logos to a
// dedicated DCFG_Assets library (Phase 6 infra task).
const LOGO_BASE_FALLBACK = 'https://decades.powerappsportals.com/';
const getLogoBase = () => getEnvVar('dcfg_sp_logo_base_url') || LOGO_BASE_FALLBACK;
```

**Current code (second sub-edit — use site):**
```javascript
      {LOGO_MAP[customer.dcfg_name] && <img src={LOGO_BASE + LOGO_MAP[customer.dcfg_name]} alt={customer.dcfg_name || ''} style={{ height:60, marginRight:16 }} />}
```

**Proposed edit (second sub-edit):**
```javascript
      {LOGO_MAP[customer.dcfg_name] && <img src={getLogoBase() + LOGO_MAP[customer.dcfg_name]} alt={customer.dcfg_name || ''} style={{ height:60, marginRight:16 }} />}
```

**Current code (third sub-edit — import):**
```javascript
import { apiGet, apiPatch, writeAuditLog, AuditActionType, getOnboardingStatusLabel, getContractStatusLabel, getProgramStatusLabel, getProgramTypeLabel, OnboardingStatus, ContractStatus, EntitySets, createDocumentRequest, DocRequestType, ContractFamily } from '../portalApi.js';
```

**Proposed edit (third sub-edit):**
```javascript
import { apiGet, apiPatch, writeAuditLog, AuditActionType, getOnboardingStatusLabel, getContractStatusLabel, getProgramStatusLabel, getProgramTypeLabel, OnboardingStatus, ContractStatus, EntitySets, createDocumentRequest, DocRequestType, ContractFamily, getEnvVar } from '../portalApi.js';
```

**Rationale:** CLAUDE.md mandates "no hardcoded URLs — read dcfg_configs via loadConfig() / getEnvVar()". The short-term fix adds a `dcfg_sp_logo_base_url` config key with fallback behavior so nothing breaks in Prod today if the config row is missing. The finding explicitly calls out the long-term solution (upload logos to a DCFG_Assets library) as a post-Phase-6 infra follow-up — out of scope for this SPA-only batch. The fix preserves current visual behavior on Prod (legacy portal still serves the images until operator seeds the new config row), and gives the operator a single place to switch when DCFG_Assets is ready.

**Risk:** Low. `getEnvVar` is already exported from portalApi.js (added in CR-0211 batch 01). The fallback preserves today's behavior byte-for-byte if the config key is unset. If the line 81 img tag isn't exactly as shown (CustomerDetail.jsx has multiple img uses), the Edit-tool old_string padding must uniquely identify the LOGO_BASE concatenation site — the surrounding JSX is distinct enough. Operator should add a row to `dcfg_configs` with `dcfg_schema_name = 'dcfg_sp_logo_base_url'` post-deploy to complete the fix; until then the fallback keeps the screen working.

**Depends on:** none (batch 01 CR-0211 already landed getEnvVar; exports unchanged)

---

### CR-2026-04-09-0255 — CustomerDetail hardcodes `isManager={true}` / `isAdmin={true}` to sub-tabs — every user sees admin actions

**File:** src/screens/CustomerDetail.jsx
**Line(s):** 130, 132, 134, 135
**Severity:** P1
**Category:** auth-role-checks

**Current code:**
```javascript
      {activeTab === 'Overview'    && <OverviewTab customer={customer} customerId={id} navigate={navigate} isManager={true} />}
      {activeTab === 'Locations'   && <LocationsMapTab customerId={id} navigate={navigate} />}
      {activeTab === 'MSAs'        && <MsasTab customerId={id} navigate={navigate} isManager={true} />}
      {activeTab === 'Contracts'   && <ContractsTab customerId={id} navigate={navigate} />}
      {activeTab === 'Onboarding'  && <OnboardingTab customerId={id} isManager={true} customer={customer} userEmail={user?.email} />}
      {activeTab === 'Programs'    && <ProgramsTab customerId={id} isAdmin={true} />}
```

**Proposed edit:**
```javascript
      {activeTab === 'Overview'    && <OverviewTab customer={customer} customerId={id} navigate={navigate} isManager={isManager()} />}
      {activeTab === 'Locations'   && <LocationsMapTab customerId={id} navigate={navigate} />}
      {activeTab === 'MSAs'        && <MsasTab customerId={id} navigate={navigate} isManager={isManager()} />}
      {activeTab === 'Contracts'   && <ContractsTab customerId={id} navigate={navigate} />}
      {activeTab === 'Onboarding'  && <OnboardingTab customerId={id} isManager={isManager()} customer={customer} userEmail={user?.email} />}
      {activeTab === 'Programs'    && <ProgramsTab customerId={id} isAdmin={isAdmin()} />}
```

**Rationale:** Line 32 already destructures `isAdmin, isManager` from `usePortalUser()`. Per `usePortalUser.jsx:112-113` both are FUNCTIONS that must be invoked. The current code imports them but silently shadows with hardcoded `{true}` literals, so every authenticated user (including DCFG_Viewer / external testers) sees and can click `+ New MSA`, `+ New Onboarding Case`, `Mark Complete`, `+ New Program`. Same pattern as `OnboardingDetail.jsx:619` (which correctly uses `isManager={isManager()}`).

**Risk:** Non-admin and non-manager users lose visible action buttons inside OverviewTab, MsasTab, OnboardingTab, ProgramsTab (intended). No runtime crash risk — the sub-tabs already destructure these as optional booleans. Smoke-test: operator logs in as a non-admin portal user, opens a customer, confirms the four admin-only create buttons are absent. Paired with CR-0248 (sibling fix for ContractDetail void/decline) to close the admin-actions-visible-to-all bug class in this batch.

**Depends on:** none

---

### CR-2026-04-09-0259 — handleSubmitForApproval calls `loadMsa()` — function is not defined in the component scope

**File:** src/screens/MsaDetail.jsx
**Line(s):** 79-87
**Severity:** P1
**Category:** error-handling

**Current code:**
```javascript
  async function handleSubmitForApproval() {
    try {
      await apiPatch(`/dcfg_msas(${id})`, { dcfg_status: MsaStatus.PendingApproval });
      writeAuditLog({ targetTable: 'dcfg_msa', targetRecordId: id, actionType: AuditActionType.StatusChanged, performedBy: user?.email || 'unknown', newValue: 'Submitted for approval' }).catch(() => {});
      loadMsa();
    } catch (e) {
      toast.show('err', 'Failed to submit: ' + e.message);
    }
  }
```

**Proposed edit:**
```javascript
  async function handleSubmitForApproval() {
    try {
      await apiPatch(`/dcfg_msas(${id})`, { dcfg_status: MsaStatus.PendingApproval });
      writeAuditLog({ targetTable: 'dcfg_msa', targetRecordId: id, actionType: AuditActionType.StatusChanged, performedBy: user?.email || 'unknown', newValue: 'Submitted for approval' }).catch(() => {});
      const fresh = await apiGet(`/dcfg_msas(${id})?$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_budget_total,dcfg_budget_committed,dcfg_contract_family,dcfg_pricing_alternative,dcfg_notes,dcfg_document_url&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name)`);
      setMsa(fresh);
    } catch (e) {
      toast.show('err', 'Failed to submit: ' + e.message);
    }
  }
```

**Rationale:** grep confirms `loadMsa` is never declared in MsaDetail.jsx — the initial-load logic lives in an inline `useEffect` at line 42. Calling `loadMsa()` throws `ReferenceError` after the PATCH succeeds, leaving the UI showing the OLD status. Operator clicks "Submit for Approval", the row updates in Dataverse, but the screen still shows "Draft", so operator clicks again → double-submit. The fix uses the same re-fetch pattern already present in `handleSaveEdit` (line 101), keeping the $select column list identical so `setMsa(fresh)` slots in seamlessly. Option A from the finding (extract a named `useCallback loadMsa`) is cleaner architecturally but larger diff; Option B (inline re-fetch) is zero-risk and matches an existing in-file pattern. Picking Option B for this batch; architectural extract can happen in a later polish batch.

**Risk:** Minimal. The $select column list is copied verbatim from `handleSaveEdit` (line 101), so the refreshed record has exactly the shape the rest of the component expects. No state-shape drift. No new imports needed — apiGet already imported at top of file.

**Depends on:** none

---

### CR-2026-04-09-0264 — loadCases outer apiGet has no try/catch — loading spinner stuck on failure

**File:** src/screens/Onboarding.jsx
**Line(s):** 54-91
**Severity:** P1
**Category:** error-handling

**Current code:**
```javascript
  const loadCases = useCallback(async () => {
    setLoading(true);
    const filterParts = [];
    if (showDeleted) {
      filterParts.push('dcfg_active_flag eq false');
    } else {
      filterParts.push('(dcfg_active_flag eq true or dcfg_active_flag eq null)');
    }
    if (statusFilter) filterParts.push(`dcfg_status eq ${statusFilter}`);
    const filterStr = `$filter=${filterParts.join(' and ')}&`;
    const r = await apiGet(
      `/${EntitySets.onboardingCases}?${filterStr}$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes,dcfg_active_flag&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_msa_id($select=dcfg_msaid,dcfg_name)&$orderby=dcfg_initiated_date desc`
    );
    const rows = r?.value ?? [];
    setCases(rows);

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

    setLoading(false);
  }, [statusFilter, showDeleted]);
```

**Proposed edit:**
```javascript
  const loadCases = useCallback(async () => {
    setLoading(true);
    try {
      const filterParts = [];
      if (showDeleted) {
        filterParts.push('dcfg_active_flag eq false');
      } else {
        filterParts.push('(dcfg_active_flag eq true or dcfg_active_flag eq null)');
      }
      if (statusFilter) filterParts.push(`dcfg_status eq ${statusFilter}`);
      const filterStr = `$filter=${filterParts.join(' and ')}&`;
      const r = await apiGet(
        `/${EntitySets.onboardingCases}?${filterStr}$select=dcfg_onboarding_caseid,dcfg_case_number,dcfg_case_label,dcfg_status,dcfg_initiated_date,dcfg_completed_date,dcfg_notes,dcfg_active_flag&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_msa_id($select=dcfg_msaid,dcfg_name)&$orderby=dcfg_initiated_date desc`
      );
      const rows = r?.value ?? [];
      setCases(rows);

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
    } catch (err) {
      toast.show('err', 'Failed to load cases: ' + (err?.message || 'unknown error'));
      setCases([]);
      setProgress({});
    } finally {
      setLoading(false);
    }
  }, [statusFilter, showDeleted]);
```

**Rationale:** The outer `apiGet` at line 64 has no try/catch. On any failure (401, 403, 500, network blip) the function throws and `setLoading(false)` at line 90 is never reached — the skeleton banner shows forever. The fix wraps the entire body in try/catch/finally, moves `setLoading(false)` to `finally` so it always runs, and adds a user-visible toast + empty-state reset on the catch path so the screen gracefully shows "no cases" instead of hanging. Inner try/catch for the checklist progress query (lines 72-87) is preserved — it already degrades correctly to empty progress.

**Risk:** `toast` is already imported/initialized via `useToast()` at line 52 — no new imports. The dependency array on useCallback (`[statusFilter, showDeleted]`) remains unchanged. Note: a stricter lint rule would add `toast` to the dep array but React convention treats useToast's stable instance as exempt; every other loader in the SPA follows this convention. No ESLint regression.

**Depends on:** none

---

### CR-2026-04-09-0290 — Procurement checklist references `dcfg_contract_fe` — field name mismatch with portalApi.js $select

**File:** src/screens/RfpDetail.jsx
**Line(s):** 131
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
    { key: 'dcfg_contract_fe', label: 'Contract Fully Executed' },
```

**Proposed edit:**
```javascript
    { key: 'dcfg_contract_fee', label: 'Contract Fully Executed' },
```

**Rationale:** Batch 01 CR-0209 already fixed `RFP_LIST_COLS` in portalApi.js to request `dcfg_contract_fee` (no `fe` typo). The consumer side in RfpDetail.jsx still reads the old typo'd key, so `rfp.dcfg_contract_fe` is always undefined → the checkbox always shows unchecked, toggles PATCH the undefined column (Dataverse 400), and the user sees nothing happen. Fix matches the server-side column name committed in batch 01.

**Risk — schema verification needed:** The finding notes the semantic intent was likely a BOOLEAN "Contract Fully Executed" flag, while `dcfg_contract_fee` on the canonical `dcfg_contract` table is a MONEY column (per portalApi.js header line 13). There are two possibilities:
- **(a)** `dcfg_rfp_package` has its own `dcfg_contract_fee` column that IS a boolean (named the same as the contract money column by copy-paste during schema design). The batch 01 fix was correct; this consumer fix completes the loop.
- **(b)** `dcfg_rfp_package` has NO `dcfg_contract_fee` column — the real intended name is `dcfg_contract_fully_executed` or similar. The batch 01 fix was wrong; portalApi.js RFP_LIST_COLS needs another correction, and both 0290 and 0291 must use the true name.

This batch adopts path (a) to stay consistent with what portalApi.js now selects. Operator should verify in Test env by running one of these commands after approve:
```
pac data list --entity dcfg_rfp_package --query "$select=dcfg_contract_fee&$top=1"
```
or querying Dataverse entity definitions for booleans on `dcfg_rfp_package`. If the column does NOT exist as a boolean, operator should REJECT 0290/0291 and file a schema-track follow-up.

**Depends on:** CR-2026-04-09-0209 (already applied in batch 01)

---

### CR-2026-04-09-0291 — RfpList checklist progress reads `r.dcfg_contract_fe` — always undefined, progress stuck at 3/4 max

**File:** src/screens/RfpList.jsx
**Line(s):** 63
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
              const checkCount = [r.dcfg_bid_solicited, r.dcfg_bid_received, r.dcfg_scope_exhibit_drafted, r.dcfg_contract_fe].filter(Boolean).length;
```

**Proposed edit:**
```javascript
              const checkCount = [r.dcfg_bid_solicited, r.dcfg_bid_received, r.dcfg_scope_exhibit_drafted, r.dcfg_contract_fee].filter(Boolean).length;
```

**Rationale:** Same typo as 0290 in the consumer side of RfpList.jsx. With the portalApi.js RFP_LIST_COLS fix in batch 01, the row shape now includes `dcfg_contract_fee` (not `dcfg_contract_fe`). `filter(Boolean)` drops the undefined slot and progress caps at 3/4. After this fix each checklist row correctly reflects all four items when all are true.

**Risk:** Same schema-verification caveat as CR-0290 (see that finding's Risk section). If operator rejects 0290, they should also reject 0291 — both are members of the same consumer-side cleanup.

**Depends on:** CR-2026-04-09-0209 (already applied in batch 01)

---

### CR-2026-04-09-0292 — UserRolesTab queries `/mspp_webroles` and `/contacts` directly — may 400 per engineering journal Sec 11

**File:** src/screens/UserRolesTab.jsx
**Line(s):** 115-172 (loadData), 186-199 (handleToggle), 240-299 (handleInvite)
**Severity:** P1
**Category:** data-integrity

**Status:** NEEDS OPERATOR DECISION — two alternatives presented. Operator picks at Gate 1b.

Per engineering journal Section 11 ("Portal Web API Cannot Access System Tables"), `/_api/mspp_webroles` and `/_api/contacts` are documented as inaccessible via the Power Pages Web API — only `dcfg_*` custom tables are supported. However, the operator has not yet verified whether DCFG has enabled these specific tables via site settings (`Webapi/mspp_webrole/enabled=true`). Until verified, the tab is either (a) completely broken in the UI, or (b) working but brittle.

#### Option A (low-risk gate banner — RECOMMENDED)

Add an operator-visible banner at the top of the tab explaining the limitation, so external testers don't get confused. Leave the existing code intact; if site settings ARE wired up it will still attempt to load and the banner serves as a caveat. If the queries fail, the existing catch at line 167 already toasts an error.

**Current code (after line 315 `return h('div', { 'data-testid': 'user-roles-tab' },`):**
```javascript
  return h('div', { 'data-testid': 'user-roles-tab' },
    // Header
    h('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' } },
```

**Proposed edit (Option A):**
```javascript
  return h('div', { 'data-testid': 'user-roles-tab' },
    // Platform-limitation banner — Power Pages Web API may not return mspp_webroles/contacts
    // depending on site-setting configuration. If the list below is empty, use the Power Pages
    // admin center (Make.powerapps.com → Portal Management → Web Roles) for role assignment.
    h('div', {
      style: { padding: '10px 14px', marginBottom: '12px', background: '#FEF3C7', border: '1px solid #FBBF24', borderRadius: '6px', fontSize: '12.5px', color: '#78350F' }
    }, 'Note: role assignment via this tab depends on Power Pages Web API site settings for mspp_webroles/contacts. If the user list below is empty or fails to load, use the Power Pages admin center (Portal Management → Web Roles) instead.'),
    // Header
    h('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' } },
```

#### Option B (investigate, then decide)

Operator opens Admin → User Roles in the Prod SPA with browser DevTools → Network tab; checks whether `/_api/mspp_webroles` and `/_api/contacts` return 400 or 200. If 400 → mark the tab as a known-broken feature (hide the tab from the Admin screen entirely). If 200 → leave the tab as-is and close this finding as invalid. No code change in this batch; finding reopens in Phase 1b with the verification result.

**Rationale:** Option A is the smaller, safer change — no code-path alteration, just a caveat banner. It neither breaks anything that currently works nor papers over a real bug. Option B is stricter (hide-or-keep based on verification) but requires the operator to run the investigation first, which is a scheduling dependency the fix agent cannot do on its own.

**Risk:** Option A: zero risk, purely additive UI. Option B: cannot be applied by the fix agent — requires manual verification step.

**Depends on:** none (Option A); operator investigation (Option B)

---

### CR-2026-04-09-0294 — VendorList $select omits dcfg_latitude/dcfg_longitude but distance-search reads them — geo filter always empty

**File:** src/screens/VendorList.jsx
**Line(s):** 74
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
    apiGet('/dcfg_vendors?$select=dcfg_vendorid,dcfg_display_name,dcfg_legal_name,dcfg_address,dcfg_city,dcfg_state,dcfg_email,dcfg_phone,dcfg_trade,dcfg_active_flag&$orderby=dcfg_display_name asc&$top=500')
```

**Proposed edit:**
```javascript
    apiGet('/dcfg_vendors?$select=dcfg_vendorid,dcfg_display_name,dcfg_legal_name,dcfg_address,dcfg_city,dcfg_state,dcfg_email,dcfg_phone,dcfg_trade,dcfg_active_flag,dcfg_latitude,dcfg_longitude&$orderby=dcfg_display_name asc&$top=500')
```

**Rationale:** Line 115 (distance computation, not shown here) reads `v.dcfg_latitude` and `v.dcfg_longitude` to compute haversine distances, but they were never in the $select → always undefined → distance search always returns zero matches. Fix just adds the two columns to $select. The values may still be undefined per row if the vendor record hasn't been geocoded yet — that's a separate data-quality issue handled by the geocoding path at line 79 (doDistanceSearch).

**Risk:** Minimal. Adding two columns to $select has negligible payload impact and Power Pages Web API will return them if they exist on the entity. If `dcfg_latitude` or `dcfg_longitude` does NOT exist on `dcfg_vendor`, the entire GET will 400 (Power Pages returns 400 on unknown $select columns). Operator should verify the columns exist before approving — one-line check: `pac data list --entity dcfg_vendor --query "$select=dcfg_latitude,dcfg_longitude&$top=1"` or inspect the solution in make.powerapps.com. Based on the finding's phrasing ("Confirm dcfg_vendor has these columns") this verification is part of the fix.

**Depends on:** operator schema verification (single column-existence check, see Risk)

---

### CR-2026-04-09-0297 — Field registry maps 'Amendment number' to `dcfg_amendment_no` — journal Sec 9 says use `dcfg_amendment_sequence`

**File:** src/screens/templates/fieldRegistry.js
**Line(s):** 59
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
  { label: 'Amendment number',    path: 'dcfg_amendment_no',         category: FieldCategory.ContractIdentifier, isComposite: false },
```

**Proposed edit:**
```javascript
  { label: 'Amendment number',    path: 'dcfg_amendment_sequence',   category: FieldCategory.ContractIdentifier, isComposite: false },
```

**Rationale:** Per engineering journal Section 9 and portalApi.js header line 14 (`dcfg_contract amendment = dcfg_amendment_sequence (Integer), NOT dcfg_amendment_number`), the canonical integer column is `dcfg_amendment_sequence`. `dcfg_amendment_no` matches neither the right name NOR the wrong journaled name — it's an older, different typo. NewContractWizard.jsx:336 writes `dcfg_amendment_sequence` correctly. Templates using this label currently produce blanks in every generated amendment document.

**Risk:** Same data-sync concern as CR-0296 — existing `dcfg_template_field` rows in Dataverse still store the old path. Post-deploy the operator should run a one-time UPDATE to rename `dcfg_amendment_no` → `dcfg_amendment_sequence` in `dcfg_template_field.dcfg_dataverse_path`. Note as a Phase 3 follow-up.

**Depends on:** none (sibling of CR-0296 in the same file; no ordering required)

---

### CR-2026-04-09-0301 — Composite `contract_value_written` references non-existent `dcfg_contract_value` and `dcfg_contract_value_written`

**File:** src/screens/templates/TemplateDetail.jsx
**Line(s):** 522-528
**Severity:** P1
**Category:** data-integrity

**Current code:**
```javascript
      contract_value_written: {
        format: '{written} (${numeric})',
        parts: [
          { key: 'written', label: 'Written amount', path: 'dcfg_contract_value_written' },
          { key: 'numeric', label: 'Numeric amount', path: 'dcfg_contract_value' },
        ]
      },
```

**Proposed edit:**
```javascript
      contract_value_written: {
        format: '${numeric}',
        parts: [
          { key: 'numeric', label: 'Numeric amount', path: 'dcfg_contract_fee' },
        ]
      },
```

**Rationale:** Two separate problems in the composite:
1. `dcfg_contract_value` doesn't exist (sibling fix to CR-0296) — should be `dcfg_contract_fee`.
2. `dcfg_contract_value_written` doesn't exist either — there is no "written amount" text column on dcfg_contract, and adding one is a schema-track task out of scope for this SPA batch.

The safest minimal fix is to drop the `written` part entirely (preserving the composite key `contract_value_written` so template editor references don't break) and keep only the numeric path, corrected to `dcfg_contract_fee`. Result: documents that used the composite will render the numeric dollar value only (e.g., `$12,500.00`) instead of the blank paired-format that they render today (e.g., ` ( $undefined )`). The format is simplified to `${numeric}` to match the single remaining part.

**Risk:** Behavioral change: any template that currently relies on the two-part format (`{written} ({numeric})`) will now emit only the numeric. Operator should audit existing templates for consumers of `contract_value_written` composite and confirm they're OK losing the written form (or file a Phase 3 schema-track task to add `dcfg_contract_fee_written` as a calculated column). If operator wants to preserve the written form in the interim, they can reject this finding and keep the broken state until a schema fix lands — but that means generated documents continue to show "$undefined" blanks. Recommended: approve the minimal fix for this batch; file the "add written-form column" as a Phase 3 schema task.

**Depends on:** none (sibling of CR-0296 in TemplateDetail.jsx; no ordering)

---

## Approval options

Reply with:
- `approve batch` — execute all 14 edits in the order shown (0289, 0296, 0243, 0248, 0254, 0255, 0259, 0264, 0290, 0291, 0292, 0294, 0297, 0301)
- `approve <id1>,<id2>,...` — execute only listed IDs (in the order shown)
- `reject <id>` — skip that finding; execute the rest
- `reject batch` — cancel batch entirely
- `hold` — stop, no execution yet

For CR-0292 (UserRolesTab): if approved as part of the batch, Option A (gate banner) will be applied. To pick Option B instead, reply `hold 0292` and provide the Web API verification result.

For CR-0290/0291/0294: these depend on operator schema verification (see per-finding Risk sections). If operator cannot verify before Gate 1b, reply `approve batch except 0290,0291,0294` and re-batch those three after verification.
