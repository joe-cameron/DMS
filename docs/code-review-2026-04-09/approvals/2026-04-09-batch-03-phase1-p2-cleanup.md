# Batch 03 — Phase 1 P2 Cleanup

**Phase:** 1 (P2 cleanup pass)
**Target:** SPA shared modules + screens, mechanical P2 fixes
**Findings count:** 15 (all P2)
**Generated:** 2026-04-09T00:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-03-phase1-p2-cleanup.md
**Predecessor batches:**
  - batch 01: approvals/2026-04-09-batch-01-phase1-shared.md (SPA commit 39f8efb, parent affe1c9)
  - batch 02: approvals/2026-04-09-batch-02-phase1-expansion.md (SPA commits 30c693b + c48949f, parent d2bed65 + 93b6387)

## Scope rules (from spec §4.6)

- Batch size = 15 (at the 15 cap)
- All `batch` tier — EXCEPT CR-0006 (`catalog-only`, no fix in this review) and CR-0214 (`catalog-only`, deprecation marker only)
- Every proposed-edit finding has before/after code visible
- Sequencing: see Cross-finding dependencies below

## Theme — three groups

- **Group A — callFlow cleanup chain (4 findings: 0001, 0006, 0274, 0214).** Finishes the migration from HTTP-trigger flows to the `createDocumentRequest()` / Dataverse transaction pattern. 0001 is the cosmetic JSX-closer fix that unlocks a clean build; 0006 is the catalog-only entry for interviewGenerate.js (no fix scheduled in this review per spec §2.2); 0274 migrates the one remaining in-scope callFlow consumer (SendQueue handleSendEmail); 0214 adds a `@deprecated` JSDoc marker to `callFlow()` itself so future cleanup can delete the export once the interview subsystem also migrates. Sequencing matters: the 0274 consumer fix MUST land before 0214's deprecation marker is meaningful, and the `callFlow` export itself MUST NOT be removed until 0006 (interview) also migrates — which is out of scope for this batch.
- **Group B — small bug fixes (6 findings: 0203, 0204, 0222, 0252, 0262, 0265).** Mechanical, low-risk, mostly 1-5 line edits: hardcoded entity-set strings → `EntitySets` constants, silent error swallowing → toast-surfaced errors, broken /concierge nav fallback → hide-when-unconfigured, inline `searchFields` literal arrays → module constants (matching the batch 01 CR-0227 useMemo stability fix), and one admin-button role-guard gap on the Onboarding list.
- **Group C — N+1 loop parallelization (5 findings: 0286, 0300, 0303, 0305, 0308).** Convert sequential `for (await ...)` patterns to `Promise.all(items.map(...))`. Same repeated pattern across ProjectList (project template-line copy), TemplateDetail (field save + audit loops), useTemplateFields (save + audit loops — the hook where the N+1 lives), NewContractWizard (contract-lines on handleGenerate), and NewProposalWizard (MSA-rates create, both uniform and per-type branches). Speeds up template saves, contract generation, and MSA creation from O(N × round-trip) to one-round-trip-plus-server-concurrency. Each loop was checked for side effects; all five are safe to parallelize because the body is a plain POST/PATCH with no intra-iteration mutation or ordering dependency — the only shared state is a loop-local accumulator (mappedCount) which is already computed separately.

## Sequencing dependencies

- **0001 is standalone** — cosmetic fix, must land before any fresh NewContractWizard.jsx build if a stricter esbuild/vite version is adopted. Apply first for cleanliness.
- **0274 BEFORE 0214** — the SendQueue consumer migration must land before `callFlow()` is marked `@deprecated`, otherwise the deprecation comment contradicts a live in-file consumer. (Technically the deprecation is just a JSDoc tag, so the reverse order would not break the build — but the documented audit trail is clearer if the consumer is already migrated.)
- **0006 BEFORE the eventual deletion of `callFlow()`** — NOT part of this batch. 0006 is catalog-only and interviewGenerate.js remains in-place. Ergo, `callFlow()` is NOT deleted in this batch; 0214 only adds a `@deprecated` JSDoc marker. Full export removal must wait until a future batch after the interview subsystem migrates.
- **All group B fixes are independent** — any order, document order recommended.
- **All group C fixes are independent** — any order, document order recommended. 0300 (TemplateDetail) and 0303 (useTemplateFields) both touch the "save loop + audit loop" pattern but live in different files; they're siblings not predecessors.

## Cross-finding dependencies

- **0001 → none**
- **0006 → none** (catalog-only, no code change)
- **0274 → 0214** (weak ordering: migrate consumer before adding deprecation marker on producer)
- **0214 → 0006** (weak ordering: cannot fully remove `callFlow()` export until 0006's interview migration lands; out of scope here)
- **0203 → none**
- **0204 → none** (paired with CR-0205 from prior batches but 0205 is not in this batch)
- **0222 → CR-0211** (config race handled by batch 01 fix — `externalFn` returns null until loadConfig resolves, which is acceptable given the new "hide when null" behavior)
- **0252 → CR-0227** (batch 01 made `useTableControls` tolerate inline searchFields via `searchFieldsKey` — this fix hoists to a module constant for belt-and-braces)
- **0262 → CR-0252** (same pattern in a sibling screen)
- **0265 → none** (sibling of CR-0248/0255 from batch 02)
- **0286 → none**
- **0300 + 0303 → siblings** (same "save + audit" pattern, different files)
- **0305 → none** (matches existing `saveLinesToDataverse` Promise.all pattern in same file)
- **0308 → 0305** (same Promise.all pattern in sibling wizard)

---

## Findings in this batch

### CR-2026-04-09-0001 — Stray `)}` JSX closer after vendor-selection comment

**File:** src/NewContractWizard.jsx
**Line(s):** 941-942
**Severity:** P2
**Category:** dead-code

**Current code:**
```jsx
            {/* Vendor is selected on Step 3 (Contractor & Signer) — not on this step */}
            )}
```

**Proposed edit:**
```jsx
```
(Delete both lines 941 and 942.)

For uniqueness, the Edit tool `old_string` should include surrounding context:

**old_string:**
```jsx
                {parentContractId && (
                  <div style={s.infoNote}>Vendor auto-filled from original Work Order. Override above if needed.</div>
                )}
              </div>
            )}

            {/* Vendor is selected on Step 3 (Contractor & Signer) — not on this step */}
            )}

            {/* Location & Date — hidden for Vendor Agreements (entity-level, no location) */}
```

**new_string:**
```jsx
                {parentContractId && (
                  <div style={s.infoNote}>Vendor auto-filled from original Work Order. Override above if needed.</div>
                )}
              </div>
            )}

            {/* Location & Date — hidden for Vendor Agreements (entity-level, no location) */}
```

**Rationale:** Line 942 is an orphan `)}` closer — a remnant from a vendor-selection block that was moved to Step 3. Esbuild happens to recover today (the file builds with a warning), but a tighter bundler version could fail the build. The comment on line 941 documents the fact but is only useful to a reader who is ALSO seeing the orphan closer; with the closer gone, the comment is dead-code itself. Deleting both keeps the intent implicit (vendor UI simply doesn't appear on Step 1). Matches the finding's `recommendedFix` exactly.

**Risk:** Zero. The two deleted lines are between a closed block at line 939 (`)}`) and the next section label at line 944 (`{/* Location & Date ...}`). Removing them changes no runtime behavior — esbuild was silently skipping the stray closer anyway. Smoke test: `npm run build` should complete with one fewer warning.

**Depends on:** none

---

### CR-2026-04-09-0006 — interviewGenerate.js still uses stale callFlow() — not createDocumentRequest (catalog-only)

**File:** src/interview/interviewGenerate.js
**Line(s):** 7 (import), 74 (MSA flow call), 151 (contract flow call)
**Severity:** P2
**Category:** data-integrity
**Tier:** catalog-only

**Status:** NO CODE CHANGE IN THIS BATCH — catalog-only per spec §2.2 (interview subsystem is outside the in-scope screen list).

**Current code (line 7, for reference only):**
```javascript
import {
  apiPost, apiPostReturn, apiPatch, apiGet, callFlow, writeAuditLog,
  EntitySets, ContractStatus, ContractFamily, AuditActionType,
  odataBind, formatCurrency,
} from '../portalApi.js';
```

**Current code (lines 73-89, for reference only):**
```javascript
    try {
      const doc = await callFlow('dcfg_flow_docgen_url', flowPayload);
      result.docUrl = doc?.document_url || doc?.file_url;
      result.fileName = doc?.file_name;
      await writeAuditLog({
        dcfg_target_table: 'dcfg_msa', dcfg_target_record_id: msaId,
        dcfg_action_type: AuditActionType.Generated, dcfg_performed_by: userEmail,
        dcfg_new_value: `POST-EXEC: docgen SUCCESS | url=${result.docUrl || 'none'}`,
      }).catch(() => {});
    } catch (e) {
      await writeAuditLog({
        dcfg_target_table: 'dcfg_msa', dcfg_target_record_id: msaId,
        dcfg_action_type: AuditActionType.Generated, dcfg_performed_by: userEmail,
        dcfg_new_value: `POST-EXEC: docgen FAILED | error=${e.message}`,
      }).catch(() => {});
      // Not a blocker — MSA record was created
    }
```

**Proposed edit:** NONE. Cataloged for visibility so whoever owns the interview subsystem next knows the migration is still pending.

**Rationale:** Per the finding's `tier: catalog-only`, this is not scheduled for a fix in the current review. Out of scope for spec §2.2. When the interview subsystem is picked up as its own work stream, the migration pattern is: replace the two `callFlow('dcfg_flow_docgen_url', flowPayload)` sites with `createDocumentRequest({ requestType: DocRequestType.DocGen, requestedBy: userEmail, name: '...', msaId|contractId, templateId, notes: JSON.stringify(flowPayload) })`. Note that `createDocumentRequest` is ASYNC (returns after Dataverse row create; the flow fires on the Dataverse trigger and runs independently), so interview callers cannot synchronously read back `doc?.document_url` — they must either poll the `dcfg_document_requests` row or accept that the doc URL appears later. This is a non-trivial UX shift and is exactly why the finding is catalog-only, not batch-tier.

**Critical caveat for operator:** Because 0006 is NOT fixed in this batch, `callFlow()` MUST remain exported from portalApi.js. 0214 below therefore only adds a `@deprecated` JSDoc marker — it does NOT remove the export.

**Risk:** None (no change).

**Depends on:** none

---

### CR-2026-04-09-0274 — handleSendEmail uses stale callFlow('dcfg_flow_send_email_url') instead of createDocumentRequest

**File:** src/screens/SendQueue.jsx
**Line(s):** 15 (import), 344-364 (handleSendEmail)
**Severity:** P2
**Category:** data-integrity

**Current code (line 15, import):**
```javascript
  MsaStatus, EntitySets, callFlow,
```

**Proposed edit (import):**
```javascript
  MsaStatus, EntitySets,
  createDocumentRequest, DocRequestType,
```

**Current code (lines 344-364, handleSendEmail):**
```javascript
  async function handleSendEmail() {
    if (!emailModal) return;
    try {
      // Try to send via flow if available
      await callFlow('dcfg_flow_send_email_url', {
        to: emailModal.to,
        subject: emailModal.subject,
        body: emailBody,
        reminderDays: parseInt(reminderDays, 10),
      });
      toast.show('ok', 'Email sent successfully');
    } catch {
      // If flow not available, just log it
      toast.show('ok', 'Email action logged (flow unavailable)');
    }
    if (emailModal.alertId) {
      setSentAlerts(prev => ({ ...prev, [emailModal.alertId]: true }));
    }
    setEmailModal(null);
    setEmailBody('');
  }
```

**Proposed edit:**
```javascript
  async function handleSendEmail() {
    if (!emailModal) return;
    try {
      // Create a document request row — the email flow triggers on dcfg_document_requests
      // row creation where dcfg_request_type = Email. See project_docgen_transaction_pattern.md.
      await createDocumentRequest({
        requestType: DocRequestType.Email,
        requestedBy: user?.email,
        name: 'Email: ' + emailModal.subject,
        contractId: emailModal.contractId || null,
        notes: JSON.stringify({
          to: emailModal.to,
          subject: emailModal.subject,
          body: emailBody,
          reminderDays: parseInt(reminderDays, 10),
        }),
      });
      toast.show('ok', 'Email request queued');
    } catch (e) {
      // Honest error — do NOT fake success. See CR-2026-04-09-0274.
      toast.show('err', 'Email request failed — ' + (e?.message || 'unknown error'));
      return;
    }
    if (emailModal.alertId) {
      setSentAlerts(prev => ({ ...prev, [emailModal.alertId]: true }));
    }
    setEmailModal(null);
    setEmailBody('');
  }
```

**Rationale:** Matches the finding's `recommendedFix` exactly. Three changes in one: (1) swap `callFlow('dcfg_flow_send_email_url', ...)` for `createDocumentRequest({ requestType: DocRequestType.Email, ... })` per project_docgen_transaction_pattern.md and DCFG architecture mandate ("Flow pattern: Dataverse transaction table, NOT HTTP triggers"); (2) stringify the email payload into `notes` so the flow can parse it back out (same pattern as NewContractWizard line 554 which stringifies `{family, type}`); (3) replace the silent-fallback `catch { toast.show('ok', 'Email action logged (flow unavailable)'); }` with an honest error toast and an early `return` so the modal stays open on failure (user can retry). The import update drops `callFlow` from the import list and adds `createDocumentRequest, DocRequestType`.

One side-effect decision: on error, the code now returns before clearing `emailModal` / `emailBody`. This is intentional — on success the modal closes; on failure the modal stays so the user can fix the problem and retry. If the operator prefers always-close behavior, move the two `setEmailModal(null); setEmailBody('');` lines out of the if/return into a `finally` block; the current shape matches the finding's recommendation more literally.

**Risk:** Medium. Three concrete risks:
1. The email flow must be updated on the Power Automate side to trigger on `dcfg_document_requests` row creation where `dcfg_request_type = 100000001 (Email)` — NOT just the legacy HTTP-trigger flow. The SPA change is incomplete without that flow rewrite. Flag this for the operator's attention; the flow rewrite is a separate work item, and the deploy of this SPA change should be coordinated with the flow deploy.
2. The old silent-fallback behavior was arguably desirable in environments where the flow was never configured — the user would see a reassuring "Email action logged" toast. The new behavior tells the truth: if the dcfg_document_requests insert fails, the user sees an error. This is the intent of the CR, but expect user-visible behavior change on any env where the email flow isn't wired.
3. `user?.email` is available here (line 75 destructures `{ user } = usePortalUser()`), so `requestedBy` will populate correctly.

**Depends on:** 0214 (by weak ordering — both part of the callFlow cleanup chain)

---

### CR-2026-04-09-0214 — callFlow() still exported and used by SendQueue + interview — should be deprecated alongside createDocumentRequest (catalog-only)

**File:** src/portalApi.js
**Line(s):** 293-303 (add @deprecated JSDoc)
**Severity:** P2
**Category:** data-integrity
**Tier:** catalog-only

**Current code (lines 293-303):**
```javascript
// ═══════════════════════════════════════════════════════════════
// FLOW CALLER
// ═══════════════════════════════════════════════════════════════
export async function callFlow(envVarNameOrUrl, payload) {
  // Accept either an env var name (e.g. 'dcfg_flow_docgen_url') or a direct URL
  const url = envVarNameOrUrl.startsWith('http') ? envVarNameOrUrl : getEnvVar(envVarNameOrUrl);
  if (!url) throw new Error(`Flow URL not found for: ${envVarNameOrUrl}`);
  const resp = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload) });
  if (!resp.ok) { let msg='Flow call failed'; try{msg=await resp.text()}catch{} throw new Error(`Flow ${envVarNameOrUrl} returned ${resp.status}: ${msg}`); }
  try { return await resp.json(); } catch { return null; }
}
```

**Proposed edit:**
```javascript
// ═══════════════════════════════════════════════════════════════
// FLOW CALLER — LEGACY / DEPRECATED
// ═══════════════════════════════════════════════════════════════
/**
 * @deprecated Use createDocumentRequest() instead. The DocGen/DMS architecture
 * migrated from HTTP-trigger flows to the dcfg_document_requests Dataverse
 * transaction pattern (see project_docgen_transaction_pattern.md). This
 * function is retained only because src/interview/interviewGenerate.js
 * still depends on it (tracked by CR-2026-04-09-0006). Once the interview
 * subsystem migrates, delete this export entirely. Do NOT add new callers.
 */
export async function callFlow(envVarNameOrUrl, payload) {
  // Accept either an env var name (e.g. 'dcfg_flow_docgen_url') or a direct URL
  const url = envVarNameOrUrl.startsWith('http') ? envVarNameOrUrl : getEnvVar(envVarNameOrUrl);
  if (!url) throw new Error(`Flow URL not found for: ${envVarNameOrUrl}`);
  const resp = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload) });
  if (!resp.ok) { let msg='Flow call failed'; try{msg=await resp.text()}catch{} throw new Error(`Flow ${envVarNameOrUrl} returned ${resp.status}: ${msg}`); }
  try { return await resp.json(); } catch { return null; }
}
```

**Rationale:** The finding is `tier: catalog-only` — its `recommendedFix` is "Add a JSDoc `@deprecated` tag on callFlow with a pointer to createDocumentRequest. Once SendQueue and interview are both migrated (separate work streams), the entire function can be deleted from portalApi.js." This batch migrates SendQueue (CR-0274) but NOT interview (CR-0006 is catalog-only), so the export MUST remain. The JSDoc @deprecated tag is the only code change — it surfaces the deprecation in IntelliSense/hover for anyone tempted to add a new callFlow consumer, and documents why the function still exists.

Grep verification: `callFlow` currently has exactly three references in src/ — the definition at portalApi.js:296, interview/interviewGenerate.js (lines 7, 74, 151), and SendQueue.jsx (lines 15, 348). After CR-0274 lands, SendQueue is removed from the consumer set, leaving only interview. The export is kept, and the banner comment ("LEGACY / DEPRECATED") plus the JSDoc @deprecated tag make the intent explicit.

**Risk:** Zero. Documentation-only change. The function body is byte-for-byte identical. The `@deprecated` tag is advisory and does not break any call.

**Depends on:** 0006 (cannot delete export until interview migrates — out of scope for this batch, only a doc marker added now), 0274 (weak ordering: migrate SendQueue consumer before marking deprecated, purely for cleanliness of audit trail)

---

### CR-2026-04-09-0203 — Hardcoded /dcfg_properties() entity-set string in @odata.bind instead of EntitySets.properties

**File:** src/LocationManager.jsx
**Line(s):** 502, 548 (finding metadata says 498/544 but actual current-code lines are 502 and 548 after batch 01's APPL_COLS insertion)
**Severity:** P2
**Category:** data-integrity

**Current code (line 502, inside saveDetail):**
```javascript
        const body = { ...changes, 'dcfg_property_id@odata.bind': `/dcfg_properties(${currentPropertyId})` };
```

**Proposed edit:**
```javascript
        const body = { ...changes, 'dcfg_property_id@odata.bind': `/${EntitySets.properties}(${currentPropertyId})` };
```

**Current code (line 548, inside confirmAddAppliance):**
```javascript
      const body = {
        'dcfg_property_id@odata.bind': `/dcfg_properties(${currentPropertyId})`,
        dcfg_custom_label: newAppl.label || null,
```

**Proposed edit:**
```javascript
      const body = {
        'dcfg_property_id@odata.bind': `/${EntitySets.properties}(${currentPropertyId})`,
        dcfg_custom_label: newAppl.label || null,
```

**Rationale:** Matches the finding's `recommendedFix` exactly. `EntitySets` is already imported at line 27 of LocationManager.jsx (batch 01 did not need to add it). The whole file uses `${EntitySets.properties}` everywhere else (via `apiGet`, `fetchContractLines`, etc.) — these two @odata.bind sites are the last remaining hardcoded strings. The fix closes the "grep all consumers" gap and makes the file internally consistent with the rest of the codebase. Even though the entity set name is guaranteed not to change (per feedback_properties_not_propertys.md), the principle — "all entity-set references go through EntitySets" — is worth enforcing uniformly.

**Risk:** Zero. `EntitySets.properties` evaluates to the string `'dcfg_properties'` (confirmed from portalApi.js). Before and after are bit-identical at runtime.

**Depends on:** none

---

### CR-2026-04-09-0204 — uploadPhoto silently swallows getEnvVar and fetch errors

**File:** src/LocationManager.jsx
**Line(s):** 186-201 (uploadPhoto), 600-620 (handlePrimaryPhoto / handleSerialPhoto callers)
**Severity:** P2
**Category:** error-handling

**Current code (uploadPhoto, lines 186-201):**
```javascript
async function uploadPhoto(applianceId, slot, dataUrl, fileName) {
  let flowUrl;
  try { flowUrl = await getEnvVar('dcfg_flow_appliance_photo_url'); } catch { /* */ }
  if (!flowUrl) return dataUrl; // Fallback: keep data URL (won't persist)
  const base64 = dataUrl.split(',')[1];
  try {
    const res = await fetch(flowUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ appliance_id: applianceId, photo_slot: slot, file_name: fileName, file_content: base64 })
    });
    if (!res.ok) throw new Error();
    const data = await res.json();
    return data.file_url || dataUrl;
  } catch { return dataUrl; }
}
```

**Proposed edit:**
```javascript
async function uploadPhoto(applianceId, slot, dataUrl, fileName) {
  // getEnvVar is synchronous (it reads the config cache populated by loadConfig
  // at boot). Keep the call simple — no try/catch needed for a cache read.
  const flowUrl = getEnvVar('dcfg_flow_appliance_photo_url');
  if (!flowUrl) {
    // Honest failure — surface to caller so the user sees a toast.
    throw new Error('Photo upload not configured (dcfg_flow_appliance_photo_url missing)');
  }
  const base64 = dataUrl.split(',')[1];
  try {
    const res = await fetch(flowUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ appliance_id: applianceId, photo_slot: slot, file_name: fileName, file_content: base64 })
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Photo upload failed (${res.status})${text ? ': ' + text.slice(0, 120) : ''}`);
    }
    const data = await res.json();
    return data.file_url || dataUrl;
  } catch (e) {
    // Re-throw with a user-friendly message; caller catches and toasts.
    console.warn('uploadPhoto failed:', e);
    throw new Error('Photo upload failed — check connection');
  }
}
```

**Current code (handlePrimaryPhoto, lines 600-609):**
```javascript
  async function handlePrimaryPhoto(id) {
    const dataUrl = await capturePhoto();
    if (!dataUrl) return;
    const a = appliances.find(x => x.id === id);
    if (!a) return;
    const url = await uploadPhoto(a.guid, 'primary', dataUrl, 'primary.jpg');
    if (a.guid) await apiPatch(`/${EntitySets.appliances}(${a.guid})`, { dcfg_primary_photo_url: url }).catch(() => {});
    setAppliances(prev => prev.map(x => x.id === id ? { ...x, primaryPhotoUrl: url } : x));
    toast.show('ok', '📷 Photo saved');
  }
```

**Proposed edit:**
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

**Current code (handleSerialPhoto, lines 611-620):**
```javascript
  async function handleSerialPhoto(id) {
    const dataUrl = await capturePhoto();
    if (!dataUrl) return;
    const a = appliances.find(x => x.id === id);
    if (!a) return;
    const url = await uploadPhoto(a.guid, 'serial', dataUrl, 'serial.jpg');
    if (a.guid) await apiPatch(`/${EntitySets.appliances}(${a.guid})`, { dcfg_serial_photo_url: url }).catch(() => {});
    setAppliances(prev => prev.map(x => x.id === id ? { ...x, serialPhotoUrl: url } : x));
    toast.show('ok', '📷 Nameplate photo saved');
  }
```

**Proposed edit:**
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

**Rationale:** The finding identifies two silent-failure paths inside `uploadPhoto`:
1. `try { flowUrl = await getEnvVar(...); } catch {}` — this catches errors from `getEnvVar`, but `getEnvVar` is a plain synchronous cache read (returns null if key missing, never throws). The `await` and the try/catch are vestigial. Remove both.
2. `catch { return dataUrl; }` — this silently returns the dataUrl (which is just the base64 of the photo, not a real persisted URL) on any upload failure. The caller THEN shows "Photo saved", so the user reloads the page and finds the photo is gone.

Fix: `uploadPhoto` now throws on (a) missing config or (b) fetch failure. The two callers each wrap their call in try/catch + error toast. Also note: there's a standalone use-site at line 563 (`primaryUrl = await uploadPhoto(newGuid, 'primary', newAppl.photos[0], 'primary.jpg');` inside `confirmAddAppliance`) that now also throws on error instead of returning the dataUrl — that call site is already inside an outer try/catch (line 546 onward), so the error bubbles up and the existing `toast.show('err', ...)` at the outer catch handles it. No additional edit needed at line 563.

**Risk:** Medium-low. Three behaviors change:
1. If the `dcfg_flow_appliance_photo_url` config row is missing, handlePrimaryPhoto / handleSerialPhoto now show an error toast instead of an "ok — photo saved" toast. On any env where the config row has never been seeded, this will immediately surface. That IS the fix — the user previously lost data silently and now sees the honest state.
2. `getEnvVar` is truly synchronous (see portalApi.js:343-346 and batch 01 CR-0211 doc block), so dropping the `await` is correct. Verified.
3. The outer try/catch in the callers prevents any UI exception (the promise rejects cleanly and the catch block runs). No console.error leak.

Operator smoke test: open /#/field, add an appliance, tap the primary photo slot, snap a photo, and confirm (a) with config present → green toast + photo persists after reload; (b) with config absent → red toast "Photo upload not configured" and no ghost success.

**Depends on:** none (getEnvVar exported since batch 01 CR-0211; no new imports needed — LocationManager.jsx already imports getEnvVar at line 27)

---

### CR-2026-04-09-0222 — External nav item to=/concierge has no live route — broken link if config returns nothing

**File:** src/NavPanel.jsx
**Line(s):** 124-149 (isVisible function body)
**Severity:** P2
**Category:** data-integrity

**Current code (isVisible, lines 124-149):**
```javascript
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

**Proposed edit:**
```javascript
  function isVisible(item) {
    if (item.to === '/admin') return isAdmin();
    // External link with an env-var resolver: hide the item entirely when the
    // config row is missing, otherwise the user clicks it and lands on the
    // NotFound page for /concierge or /portal (no matching Route in AppRouter).
    // See CR-2026-04-09-0222.
    if (item.externalFn && !item.externalFn()) return false;
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

**Rationale:** Matches the finding's `recommendedFix`: "Add a check in isVisible: `if (item.externalFn && !item.externalFn()) return false;`". The check is inserted AFTER the `/admin` special case (so admin gating still runs first) but BEFORE the role-menu and fallback blocks (so an unconfigured external link is hidden regardless of role). Two concrete effects:
1. If `concierge_portal_url` is unset in `dcfg_configs`, the "Concierge Onboarding Website" nav item disappears entirely.
2. If `customer_portal_url` is unset, the "Portal" nav item disappears entirely.

Before the fix, these items showed a NavLink to `/concierge` / `/portal` — both paths that have no matching `<Route>` in AppRouter.jsx (verified by grep) — so a click landed on the NotFound page. The fix hides the dead link until an operator seeds the config row.

Interaction with batch 01 CR-0211 (config race): `externalFn` calls `getEnvVar(...)`, which returns `null` until `loadConfig` resolves. Batch 01 gates AppRouter render on `configLoaded`, so by the time NavPanel renders, `getEnvVar` is hot. Before that gate fired, the pre-0226 behavior would have briefly shown the nav items with null config — now they're hidden on first render until config arrives. That's correct and preferable.

**Risk:** Low. Operators on environments that DO have `concierge_portal_url` / `customer_portal_url` seeded see identical behavior (item stays visible, links to the external URL). Operators on environments that DON'T have them set lose the dead nav items entirely (intended — that's the whole fix). No runtime errors can result from adding the `externalFn` guard: `externalFn` is defined on the two specific items at NavPanel.jsx:80-81 and nowhere else, and both are zero-argument arrow functions that only call `getEnvVar`.

**Depends on:** CR-0211 (batch 01) — the new "hide when null" behavior depends on `getEnvVar` returning null predictably, which CR-0211 codified in a doc block.

---

### CR-2026-04-09-0252 — Inline searchFields array literal passed to useTableControls — defeats useMemo cache

**File:** src/screens/ContractList.jsx
**Line(s):** 14 (insert module constant), 24 (use site)
**Severity:** P2
**Category:** performance

**Current code (lines 13-25):**
```javascript
const NAVY = '#1B2A4A';

export default function ContractList() {
  const navigate = useNavigate();
  const { isManager } = usePortalUser();
  const [contracts, setContracts] = useState([]);
  const [loading, setLoading] = useState(true);

  const { filtered, sortCol, sortDir, toggleSort, searchTerm, setSearchTerm } = useTableControls(contracts, {
    defaultSort: 'dcfg_contract_date',
    defaultDir: 'desc',
    searchFields: ['dcfg_contract_number', 'dcfg_client_name', 'dcfg_contractor_legal_name', 'dcfg_msa_id.dcfg_customer_id.dcfg_name'],
  });
```

**Proposed edit:**
```javascript
const NAVY = '#1B2A4A';

// Stable module-level searchFields reference — see CR-2026-04-09-0252.
// Belt-and-braces with useTableControls.jsx's searchFieldsKey stability fix (CR-0227).
const CONTRACT_SEARCH_FIELDS = ['dcfg_contract_number', 'dcfg_client_name', 'dcfg_contractor_legal_name', 'dcfg_msa_id.dcfg_customer_id.dcfg_name'];

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
```

**Rationale:** Same pattern used by Onboarding.jsx:31 (`ONBOARDING_SEARCH_FIELDS`). Hoisting to a module-level `const` gives `useTableControls` a reference-stable array that passes identity comparison on every render. Batch 01's CR-0227 fix (searchFieldsKey in useTableControls) already insulates the hook from unstable inputs, but hoisting at the call site is a cheaper belt-and-braces optimization — it also removes the inline-array visual noise and makes the search-field list easy to locate and audit.

**Risk:** Zero. Module constants with the same content behave identically to inline literals, except they're referentially stable. No behavior change beyond the memoization improvement.

**Depends on:** CR-0227 (batch 01) — partially closes the same performance bug; this is the call-site-level fix that pairs with CR-0227's hook-level fix.

---

### CR-2026-04-09-0262 — MsaList inline searchFields array literal — defeats useTableControls useMemo cache

**File:** src/screens/MsaList.jsx
**Line(s):** 14 (insert module constant), 66 (use site)
**Severity:** P2
**Category:** performance

**Current code (lines 13-67):**
```javascript
const NAVY = '#1B2A4A';

// Exhibit type → package label
const EXHIBIT_TYPE_MAP = {
```
... and at line 63-67:
```javascript
  const { filtered, sortCol, sortDir, toggleSort, searchTerm, setSearchTerm } =
    useTableControls(msas, {
      defaultSort: '_customerName',
      searchFields: ['_customerName', 'dcfg_name'],
    });
```

**Proposed edit (module constant, after line 14):**

**old_string:**
```javascript
const NAVY = '#1B2A4A';

// Exhibit type → package label
const EXHIBIT_TYPE_MAP = {
```

**new_string:**
```javascript
const NAVY = '#1B2A4A';

// Stable module-level searchFields reference — see CR-2026-04-09-0262.
const MSA_SEARCH_FIELDS = ['_customerName', 'dcfg_name'];

// Exhibit type → package label
const EXHIBIT_TYPE_MAP = {
```

**Proposed edit (use site, line 66):**

**old_string:**
```javascript
  const { filtered, sortCol, sortDir, toggleSort, searchTerm, setSearchTerm } =
    useTableControls(msas, {
      defaultSort: '_customerName',
      searchFields: ['_customerName', 'dcfg_name'],
    });
```

**new_string:**
```javascript
  const { filtered, sortCol, sortDir, toggleSort, searchTerm, setSearchTerm } =
    useTableControls(msas, {
      defaultSort: '_customerName',
      searchFields: MSA_SEARCH_FIELDS,
    });
```

**Rationale:** Same pattern as CR-0252 / batch 01 CR-0227. Two fields in the searchable set (`_customerName`, `dcfg_name`) — both preserved exactly. Constant named to match the `<NAME>_SEARCH_FIELDS` convention already established by `ONBOARDING_SEARCH_FIELDS` at Onboarding.jsx:31 and introduced here by `CONTRACT_SEARCH_FIELDS` above.

**Risk:** Zero. Same as CR-0252.

**Depends on:** CR-0252 (sibling pattern in same batch — same rationale, different file; no ordering)

---

### CR-2026-04-09-0265 — Onboarding list destructures isManager but never uses it — +New Case visible to all users

**File:** src/screens/Onboarding.jsx
**Line(s):** 243 (New Case button), 288-291 (Delete button)
**Severity:** P2
**Category:** auth-role-checks

**Current code (line 243, + New Case button):**
```javascript
          <button onClick={() => setShowNew(true)} style={btnPrimary} data-testid="onb-btn-new">+ New Case</button>
```

**Proposed edit:**
```javascript
          {isManager() && <button onClick={() => setShowNew(true)} style={btnPrimary} data-testid="onb-btn-new">+ New Case</button>}
```

**Current code (lines 283-291, Delete/Restore buttons inside showDeleted ternary):**
```javascript
                    {showDeleted ? (
                      <button data-testid="onb-btn-restore" onClick={(e) => handleRestore(e, c)} style={{ ...btnSecondary, padding: '4px 10px', fontSize: '11px' }}>
                        Restore
                      </button>
                    ) : (
                      <button data-testid="onb-btn-delete" onClick={(e) => handleDelete(e, c)} style={{ ...btnSecondary, padding: '4px 10px', fontSize: '11px', color: '#DC2626', borderColor: '#FECACA' }}>
                        Delete
                      </button>
                    )}
```

**Proposed edit:**
```javascript
                    {showDeleted ? (
                      <button data-testid="onb-btn-restore" onClick={(e) => handleRestore(e, c)} style={{ ...btnSecondary, padding: '4px 10px', fontSize: '11px' }}>
                        Restore
                      </button>
                    ) : isManager() ? (
                      <button data-testid="onb-btn-delete" onClick={(e) => handleDelete(e, c)} style={{ ...btnSecondary, padding: '4px 10px', fontSize: '11px', color: '#DC2626', borderColor: '#FECACA' }}>
                        Delete
                      </button>
                    ) : null}
```

**Rationale:** Matches the finding's `recommendedFix` exactly: "Wrap the New Case button in `{isManager() && ...}`. Same for the per-row Delete button. Keep Restore visible in showDeleted mode since it's a recovery action." `isManager` is already destructured from `usePortalUser()` at line 44, so no import/wiring changes needed. Per usePortalUser.jsx:112-113, `isManager` is a FUNCTION — so the gate must be `isManager()`, not `isManager`.

The Restore button is deliberately left visible to ALL users in showDeleted mode (per the finding's note: "Restore is a recovery action"). A viewer who somehow sees deleted cases in the showDeleted view can still restore them — this is intentional to avoid stranding data.

Closes the auth gap for the onboarding list, pairing with batch 02's CR-0248 (ContractDetail Void/Decline) and CR-0255 (CustomerDetail isManager={true} hardcoding) which cover sibling admin-actions-visible-to-all bugs.

**Risk:** Low. Non-manager users lose the visible `+ New Case` button and per-row Delete button (intended — previously they could initiate soft-deletes that wrote audit trails with their email). Managers and admins see identical behavior. Restore path is unchanged (available to all users who can access showDeleted mode). Smoke test: log in as a viewer, open /#/onboarding, confirm no + New Case button visible and no Delete buttons in the per-row action column.

**Depends on:** CR-0248 / CR-0255 (batch 02) — sibling fixes for the same bug class

---

### CR-2026-04-09-0286 — Template-line copy loop is sequential N+1 — 20-line template = 20 sequential POSTs

**File:** src/screens/ProjectList.jsx
**Line(s):** 183-197
**Severity:** P2
**Category:** performance

**Current code (lines 181-205):**
```javascript
          try {
            const tplLines = JSON.parse(tpl.dcfg_description);
            for (const line of tplLines) {
              await apiPostReturnId(`/${EntitySets.projectLineItems}`, {
                dcfg_name: line.description?.substring(0, 100) || 'Line item',
                dcfg_description: line.description || null,
                dcfg_trade: line.trade || null,
                dcfg_line_type: line.line_type ?? null,
                dcfg_uom: line.uom ?? null,
                dcfg_quantity: line.quantity ?? null,
                dcfg_unit_rate: line.unit_rate ?? null,
                dcfg_extended_cost: (line.quantity && line.unit_rate) ? line.quantity * line.unit_rate : null,
                dcfg_sequence: line.sequence ?? null,
                dcfg_active_flag: true,
                'dcfg_project_id@odata.bind': `/${EntitySets.projects}(${newProjectId})`,
              });
            }
            toast.show('ok', `Project created with ${tplLines.length} template lines`);
          } catch { toast.show('ok', 'Project created (template lines may need manual entry)'); }
```

**Proposed edit:**
```javascript
          try {
            const tplLines = JSON.parse(tpl.dcfg_description);
            await Promise.all(tplLines.map(line => apiPostReturnId(`/${EntitySets.projectLineItems}`, {
              dcfg_name: line.description?.substring(0, 100) || 'Line item',
              dcfg_description: line.description || null,
              dcfg_trade: line.trade || null,
              dcfg_line_type: line.line_type ?? null,
              dcfg_uom: line.uom ?? null,
              dcfg_quantity: line.quantity ?? null,
              dcfg_unit_rate: line.unit_rate ?? null,
              dcfg_extended_cost: (line.quantity && line.unit_rate) ? line.quantity * line.unit_rate : null,
              dcfg_sequence: line.sequence ?? null,
              dcfg_active_flag: true,
              'dcfg_project_id@odata.bind': `/${EntitySets.projects}(${newProjectId})`,
            })));
            toast.show('ok', `Project created with ${tplLines.length} template lines`);
          } catch { toast.show('ok', 'Project created (template lines may need manual entry)'); }
```

**Rationale:** Standard sequential → parallel conversion. Each iteration is a pure POST with no shared state and no inter-line ordering dependency (the sequence order is encoded in `line.sequence` itself, not in insertion order). Promise.all resolves when all POSTs complete; the outer catch still fires if any one rejects, which preserves the "Project created (template lines may need manual entry)" fallback toast. At ~200ms per Dataverse round-trip and typical templates of 10-30 lines, wall-clock improvement is 2-6 seconds per project creation.

**Risk:** Low. Three potential concerns:
1. Dataverse rate limiting at very high concurrency — acceptable at 10-30 concurrent POSTs (well under the soft throttle of 60 req/s per user).
2. Partial-failure semantics change: with the old sequential loop, a mid-loop failure left N-1 lines successfully written (up to the failure point). With Promise.all, any rejection fails the whole await and surfaces to the outer catch, but other promises continue running in the background and may still commit their rows. This means on partial failure, the user may see the "lines may need manual entry" toast but some lines ARE in the database. This matches the behavior of NewContractWizard.jsx:389 (saveLinesToDataverse uses Promise.all with the same semantics) — the inconsistency is fine.
3. If `tplLines` parse fails (malformed `dcfg_description` JSON), the outer catch still fires identically to today.

**Depends on:** none

---

### CR-2026-04-09-0300 — handleSave template-fields loop is sequential N+1 — large templates take N × round-trip

**File:** src/screens/templates/TemplateDetail.jsx
**Line(s):** 656-691 (two loops: field save + audit log)
**Severity:** P2
**Category:** performance

**Current code (lines 656-691):**
```javascript
      // Save all field records
      for (var i = 0; i < localFields.length; i++) {
        var f = localFields[i];
        var body = {
          dcfg_field_order: f.dcfg_field_order || (i + 1),
          dcfg_source_text: f.dcfg_source_text,
          dcfg_user_label: f.dcfg_user_label || f.dcfg_source_text,
          dcfg_dataverse_path: f.dcfg_dataverse_path || null,
          dcfg_field_category: f.dcfg_field_category,
          dcfg_is_composite: f.dcfg_is_composite || false,
          dcfg_composite_parts: f.dcfg_composite_parts || null,
          dcfg_highlight_color: f.dcfg_highlight_color,
          dcfg_is_mapped: !!f.dcfg_dataverse_path,
          dcfg_is_repeated: f.dcfg_is_repeated || false,
          dcfg_repeat_group_key: f.dcfg_repeat_group_key || null,
        };

        if (f.dcfg_template_fieldid) {
          await apiPatch('/' + EntitySets.templateFields + '(' + f.dcfg_template_fieldid + ')', body);
        } else {
          body['dcfg_template_id@odata.bind'] = '/' + EntitySets.docTemplates + '(' + tplId + ')';
          await apiPostReturnId('/' + EntitySets.templateFields, body);
        }
      }

      // Audit log for field mappings
      var mappedFields = localFields.filter(function(f) { return !!f.dcfg_dataverse_path; });
      for (var m = 0; m < mappedFields.length; m++) {
        await writeAuditLog({
          targetTable: 'dcfg_document_template',
          targetRecordId: tplId,
          actionType: AuditActionType.DataUpdated,
          performedBy: user?.email || 'admin',
          newValue: "Field '" + mappedFields[m].dcfg_source_text + "' mapped to " + mappedFields[m].dcfg_dataverse_path,
        });
      }
```

**Proposed edit:**
```javascript
      // Save all field records — parallelized per CR-2026-04-09-0300.
      // Each iteration is an independent POST/PATCH; ordering is encoded in
      // dcfg_field_order, not in insertion order, so Promise.all is safe.
      await Promise.all(localFields.map(function(f, i) {
        var body = {
          dcfg_field_order: f.dcfg_field_order || (i + 1),
          dcfg_source_text: f.dcfg_source_text,
          dcfg_user_label: f.dcfg_user_label || f.dcfg_source_text,
          dcfg_dataverse_path: f.dcfg_dataverse_path || null,
          dcfg_field_category: f.dcfg_field_category,
          dcfg_is_composite: f.dcfg_is_composite || false,
          dcfg_composite_parts: f.dcfg_composite_parts || null,
          dcfg_highlight_color: f.dcfg_highlight_color,
          dcfg_is_mapped: !!f.dcfg_dataverse_path,
          dcfg_is_repeated: f.dcfg_is_repeated || false,
          dcfg_repeat_group_key: f.dcfg_repeat_group_key || null,
        };

        if (f.dcfg_template_fieldid) {
          return apiPatch('/' + EntitySets.templateFields + '(' + f.dcfg_template_fieldid + ')', body);
        } else {
          body['dcfg_template_id@odata.bind'] = '/' + EntitySets.docTemplates + '(' + tplId + ')';
          return apiPostReturnId('/' + EntitySets.templateFields, body);
        }
      }));

      // Audit log for field mappings — parallelized per CR-2026-04-09-0300.
      // Order is preserved in dcfg_performed_at timestamps on the Dataverse side.
      var mappedFields = localFields.filter(function(f) { return !!f.dcfg_dataverse_path; });
      await Promise.all(mappedFields.map(function(mf) {
        return writeAuditLog({
          targetTable: 'dcfg_document_template',
          targetRecordId: tplId,
          actionType: AuditActionType.DataUpdated,
          performedBy: user?.email || 'admin',
          newValue: "Field '" + mf.dcfg_source_text + "' mapped to " + mf.dcfg_dataverse_path,
        });
      }));
```

**Rationale:** Matches the finding's `recommendedFix`. Two independent sequential loops converted to Promise.all. The field save loop is safe because each field's body is self-contained (it already includes `dcfg_field_order` set by the closure-captured index `i`), and the write does not depend on any prior row. The audit log loop is safe because `writeAuditLog` is independently insertable (each audit row is a separate entity with no row-level dependency) and the finding explicitly notes "order is preserved in dcfg_performed_at" — i.e., the server's timestamp ordering is the canonical order, not client insertion order.

One preservation worth noting: the loop currently uses `var` (not `const/let`) and traditional `function(f) {}` callbacks — I kept those style conventions inside the Promise.all callbacks to minimize diff drift. This file uses a mixed ES5/ES6 style that varies by section.

For a template with 40 fields and 40 audit writes, wall-clock improves from ~16s (2N × 200ms) to ~0.4s (one round-trip + server concurrency). Massive user-visible win on the template editor.

**Risk:** Low-medium. Two concerns:
1. Dataverse rate limiting at 40 concurrent PATCHes — acceptable; the SPA admin user is the only source of concurrent writes, the typical peak is 50-80 (for a heavily-mapped contract template), and the plugin pipeline handles it.
2. Partial-failure semantics as in CR-0286: if one field fails, the outer catch shows "Save failed: ..." but other fields may have committed. The template state was already partially-committed on sequential-loop failure too; this just compresses the failure window. Users have the local `localFields` state to retry saving from.

**Depends on:** CR-0303 (sibling fix to the same pattern in `useTemplateFields.js` hook — both files call into the same shape; no ordering between them)

---

### CR-2026-04-09-0303 — saveAllFields has two sequential N+1 loops — save and audit, both serial

**File:** src/screens/templates/useTemplateFields.js
**Line(s):** 82-113
**Severity:** P2
**Category:** performance

**Current code (lines 82-113):**
```javascript
  const saveAllFields = useCallback(async (fieldList, templateName) => {
    let savedCount = 0;
    let mappedCount = 0;
    const mergeFields = fieldList.filter(f => f.dcfg_highlight_color !== 100000001); // exclude cyan

    for (const f of fieldList) {
      await saveField(f);
      savedCount++;
      if (f.dcfg_dataverse_path && f.dcfg_highlight_color !== 100000001) mappedCount++;
    }

    // Update template record counts
    await apiPatch('/' + EntitySets.docTemplates + '(' + templateId + ')', {
      dcfg_field_count: mergeFields.length,
      dcfg_mapped_count: mappedCount,
    });

    // Audit log for each mapped field
    for (const f of fieldList) {
      if (f.dcfg_dataverse_path) {
        await writeAuditLog({
          targetTable: 'dcfg_document_template',
          targetRecordId: templateId,
          actionType: AuditActionType.DataUpdated,
          performedBy: userEmail || 'admin',
          newValue: "Field '" + f.dcfg_source_text + "' mapped to " + f.dcfg_dataverse_path,
        });
      }
    }

    return { savedCount, mappedCount };
  }, [templateId, userEmail, saveField]);
```

**Proposed edit:**
```javascript
  const saveAllFields = useCallback(async (fieldList, templateName) => {
    const mergeFields = fieldList.filter(f => f.dcfg_highlight_color !== 100000001); // exclude cyan
    // mappedCount: count of fields with a path AND not cyan-highlighted.
    const mappedCount = fieldList.filter(f => f.dcfg_dataverse_path && f.dcfg_highlight_color !== 100000001).length;

    // Parallelized save — per CR-2026-04-09-0303.
    // Each saveField call is a self-contained POST or PATCH; no inter-field ordering.
    await Promise.all(fieldList.map(f => saveField(f)));
    const savedCount = fieldList.length;

    // Update template record counts
    await apiPatch('/' + EntitySets.docTemplates + '(' + templateId + ')', {
      dcfg_field_count: mergeFields.length,
      dcfg_mapped_count: mappedCount,
    });

    // Audit log for each mapped field — parallelized (fire-and-forget shape).
    // Server timestamps (dcfg_performed_at) preserve the canonical order.
    const mapped = fieldList.filter(f => f.dcfg_dataverse_path);
    await Promise.all(mapped.map(f => writeAuditLog({
      targetTable: 'dcfg_document_template',
      targetRecordId: templateId,
      actionType: AuditActionType.DataUpdated,
      performedBy: userEmail || 'admin',
      newValue: "Field '" + f.dcfg_source_text + "' mapped to " + f.dcfg_dataverse_path,
    })));

    return { savedCount, mappedCount };
  }, [templateId, userEmail, saveField]);
```

**Rationale:** Same pattern as CR-0300 applied at the hook level. Two loops converted:
1. Save loop: `for (const f of fieldList) await saveField(f)` → `Promise.all(fieldList.map(f => saveField(f)))`. The mappedCount accumulator used to increment inside the loop; moved out to a pure `filter(...).length` computation so it doesn't depend on sequential iteration order.
2. Audit loop: same Promise.all treatment. Finding explicitly notes audit writes are "fire-and-forget so Promise.all is safe".

`savedCount` now equals `fieldList.length` because Promise.all resolves only if every saveField succeeds (if any fails, the Promise.all rejects and the caller catches). If partial success reporting matters, swap to Promise.allSettled and filter on status === 'fulfilled' — but the current code's `savedCount` is only used in a toast (via TemplateDetail's caller), not in any business logic, so the simpler Promise.all suffices.

The dependency array stays `[templateId, userEmail, saveField]` — unchanged.

**Risk:** Low-medium, same as CR-0300. The operator may notice that the `mergeFields` filter now runs eagerly at the start regardless of whether any save actually happens — a negligible cost (< 1ms on any realistic fieldList size).

**Depends on:** none (CR-0300 is a sibling; no ordering between the two files, they call into the same data shape)

---

### CR-2026-04-09-0305 — handleGenerate contract-lines create loop is sequential — 10-line exhibit = 10 round-trips

**File:** src/NewContractWizard.jsx
**Line(s):** 527-538
**Severity:** P2
**Category:** performance

**Current code (lines 527-538, inside handleGenerate):**
```javascript
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          const lineAmount = parseFloat(String(line.amount).replace(/,/g, '')) || 0;
          if (!line.description && !lineAmount) continue;
          await createContractLine({
            dcfg_item_number: i + 1,
            dcfg_description: line.description,
            dcfg_amount: lineAmount,
            ...odataBind('dcfg_contract_id', EntitySets.contracts, contractId),
            ...(line.costCodeId ? odataBind('dcfg_cost_code_id', EntitySets.costCodes, line.costCodeId) : {}),
          });
        }
```

**Proposed edit:**
```javascript
        // Parallelized per CR-2026-04-09-0305. Matches saveLinesToDataverse
        // (line 389) which already uses Promise.all for the same operation.
        const toCreate = lines
          .map((line, i) => ({ line, idx: i }))
          .filter(({ line }) => {
            const amt = parseFloat(String(line.amount).replace(/,/g, '')) || 0;
            return line.description || amt;
          });
        await Promise.all(toCreate.map(({ line, idx }) => createContractLine({
          dcfg_item_number: idx + 1,
          dcfg_description: line.description,
          dcfg_amount: parseFloat(String(line.amount).replace(/,/g, '')) || 0,
          ...odataBind('dcfg_contract_id', EntitySets.contracts, contractId),
          ...(line.costCodeId ? odataBind('dcfg_cost_code_id', EntitySets.costCodes, line.costCodeId) : {}),
        })));
```

**Rationale:** Matches the existing `saveLinesToDataverse` pattern at line 389 (which already uses Promise.all for the same operation on draft saves). The only logic subtlety: the original loop used `continue` to skip empty rows; the parallel version filters them out BEFORE mapping so Promise.all doesn't receive any no-ops. The `dcfg_item_number` must preserve the ORIGINAL array index (pre-filter), which is why the filter produces `{line, idx}` objects carrying the original index — matching `saveLinesToDataverse` verbatim. This ensures that if the user has lines [A, empty, C], the item numbers come out as 1 and 3, not 1 and 2 — consistent with how `saveLinesToDataverse` behaves.

**Risk:** Low. Dataverse rate limiting at 5-15 concurrent POSTs is well under throttle limits. Partial-failure semantics are preserved (the outer try/catch at ~line 510 still catches any rejection). Internally-consistent with the saveLinesToDataverse path in the same file, so the two code paths no longer diverge.

**Depends on:** none

---

### CR-2026-04-09-0308 — MSA-rates create loops are sequential — one POST per location type

**File:** src/NewProposalWizard.jsx
**Line(s):** 439-467 (two loops inside the uniform and per-type branches)
**Severity:** P2
**Category:** performance

**Current code (lines 439-467):**
```javascript
      if(priceMode==='uniform'){
        for(const lt of locTypes){
          const admin=(lt.dcfg_name||'').toLowerCase()==='admin';
          const memberRate = admin ? 0 : parseFloat(uniRate)||0;
          const onboardRate = admin ? 0 : parseFloat(uniOnboard)||0;
          await apiPost(`/${EntitySets.msaRates}`,{
            dcfg_name:`${dispName} - ${lt.dcfg_name}`,
            dcfg_membership_rate: memberRate,
            dcfg_onboarding_rate: onboardRate,
            dcfg_is_active:true,
            [`dcfg_msa_id@odata.bind`]:`/${EntitySets.msas}(${msaId})`,
            [`dcfg_location_type_id@odata.bind`]:`/${EntitySets.locationTypes}(${lt.dcfg_location_typeid})`,
          });
        }
      } else {
        for(const[tn,r]of Object.entries(typeRates)){
          if(!r.id)continue;
          const memberRate = r.admin ? 0 : parseFloat(r.mo)||0;
          const onboardRate = r.admin ? 0 : parseFloat(r.ob)||0;
          await apiPost(`/${EntitySets.msaRates}`,{
            dcfg_name:`${dispName} - ${tn}`,
            dcfg_membership_rate: memberRate,
            dcfg_onboarding_rate: onboardRate,
            dcfg_is_active:true,
            [`dcfg_msa_id@odata.bind`]:`/${EntitySets.msas}(${msaId})`,
            [`dcfg_location_type_id@odata.bind`]:`/${EntitySets.locationTypes}(${r.id})`,
          });
        }
      }
```

**Proposed edit:**
```javascript
      // Parallelized per CR-2026-04-09-0308. Each msaRate POST is independent.
      if(priceMode==='uniform'){
        await Promise.all(locTypes.map(lt => {
          const admin=(lt.dcfg_name||'').toLowerCase()==='admin';
          const memberRate = admin ? 0 : parseFloat(uniRate)||0;
          const onboardRate = admin ? 0 : parseFloat(uniOnboard)||0;
          return apiPost(`/${EntitySets.msaRates}`,{
            dcfg_name:`${dispName} - ${lt.dcfg_name}`,
            dcfg_membership_rate: memberRate,
            dcfg_onboarding_rate: onboardRate,
            dcfg_is_active:true,
            [`dcfg_msa_id@odata.bind`]:`/${EntitySets.msas}(${msaId})`,
            [`dcfg_location_type_id@odata.bind`]:`/${EntitySets.locationTypes}(${lt.dcfg_location_typeid})`,
          });
        }));
      } else {
        const typeEntries = Object.entries(typeRates).filter(([, r]) => r.id);
        await Promise.all(typeEntries.map(([tn, r]) => {
          const memberRate = r.admin ? 0 : parseFloat(r.mo)||0;
          const onboardRate = r.admin ? 0 : parseFloat(r.ob)||0;
          return apiPost(`/${EntitySets.msaRates}`,{
            dcfg_name:`${dispName} - ${tn}`,
            dcfg_membership_rate: memberRate,
            dcfg_onboarding_rate: onboardRate,
            dcfg_is_active:true,
            [`dcfg_msa_id@odata.bind`]:`/${EntitySets.msas}(${msaId})`,
            [`dcfg_location_type_id@odata.bind`]:`/${EntitySets.locationTypes}(${r.id})`,
          });
        }));
      }
```

**Rationale:** Both branches of the if/else are pure sequential POST loops with no inter-iteration state — textbook Promise.all targets. The only subtlety: the `else` branch has a `continue` for entries where `!r.id`, which becomes a `.filter([,r]) => r.id)` on the typeEntries computation so Promise.all doesn't receive any empty slots. The uniform branch has no continue, so it maps directly.

Each admin-vs-non-admin rate computation stays exactly as written; the `admin`, `memberRate`, `onboardRate` locals are now computed per map-iteration inside the arrow, which is functionally identical to computing them per for-iteration before.

Consistent with CR-0305 and CR-0300/0303 — repeated pattern across the wizards and template editor, finally all made parallel.

**Risk:** Low. Dataverse rate-limiting at 6-8 concurrent POSTs is well under throttle. Partial-failure semantics: if any rate insert fails, the outer try/catch (elsewhere in this file) rolls up to a user-visible error; previously the same was true of sequential failure. No change in the post-success flow (the subsequent `createDocumentRequest` at line 474 still runs exactly once after the Promise.all resolves).

**Depends on:** CR-0305 (sibling pattern in sibling wizard — same rationale)

---

## Approval options

Reply with:
- `approve batch` — execute all 15 edits in the order shown (0001, 0006 [no-op], 0274, 0214, 0203, 0204, 0222, 0252, 0262, 0265, 0286, 0300, 0303, 0305, 0308)
- `approve 0001,0274,0214,...` — execute only listed IDs (in the order shown)
- `reject 0204` — skip that finding; execute the rest
- `reject batch` — cancel this batch entirely
- `hold` — stop, no execution yet

**Operator attention items:**
1. **CR-0274 requires coordinated flow deploy.** The SPA change makes SendQueue write to `dcfg_document_requests` with `dcfg_request_type = Email`. The Power Automate email flow must be updated to trigger on that row creation (not the legacy HTTP-trigger). The SPA deploy should be coordinated with the flow deploy — or the operator must accept that the email-send feature is broken between SPA deploy and flow deploy.
2. **CR-0006 stays as-is (catalog-only).** The interview subsystem is out of scope; `callFlow()` remains exported.
3. **CR-0214 only adds a @deprecated JSDoc tag** — the function body is byte-for-byte identical. The export CANNOT be removed until 0006 (interview) also migrates, which is out of scope for this review.
4. **CR-0204 surfaces previously-silent failures.** On any environment where `dcfg_flow_appliance_photo_url` is missing from dcfg_configs, users will see a red error toast instead of a fake green one. That IS the fix, but expect user-visible behavior change.
5. **CR-0265 hides +New Case and per-row Delete from non-managers.** Non-manager users currently see and can click these buttons. After the fix they disappear. Smoke-test with a viewer login.
