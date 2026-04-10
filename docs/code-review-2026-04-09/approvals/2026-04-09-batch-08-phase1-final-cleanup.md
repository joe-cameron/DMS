# Batch 08 — Phase 1 Final Cleanup

**Phase:** 1 (final)
**Target:** Remaining P1 destructive + final P3 cleanups
**Findings count:** 7 (2 P1 destructive + 5 P3)
**Generated:** 2026-04-10T15:00:00Z
**Approval doc location:** docs/code-review-2026-04-09/approvals/2026-04-09-batch-08-phase1-final-cleanup.md
**Predecessor batches:**
  - batch 01: approvals/2026-04-09-batch-01-phase1-shared.md (SPA commit 39f8efb)
  - batch 02: approvals/2026-04-09-batch-02-phase1-expansion.md (SPA commits 30c693b + c48949f)
  - batch 03: approvals/2026-04-09-batch-03-phase1-p2-cleanup.md (SPA commit e727a8b)
  - batch 04: approvals/2026-04-09-batch-04-phase1-errhandling-security.md (SPA commit dfd1efc)
  - batch 05: approvals/2026-04-09-batch-05-phase1-perf-auth-data.md (SPA commit 4250f9e)
  - batch 06: approvals/2026-04-09-batch-06-phase1-schema-p3-cleanup.md (SPA commit 78f4089)
  - batch 07: approvals/2026-04-09-batch-07-phase1-p3-cleanup.md

**NOT in this batch:**
  - **CR-2026-04-09-0268** — `callFlow` → `createDocumentRequest` migration. Needs a paired flow deploy (same coordination constraint as CR-2026-04-09-0274 in an earlier batch). Defer to a flow-deploy coordination batch.
  - **CR-2026-04-09-0299** — resolver drift. The finding's premise cannot be reconciled against current state without a resolver reformulation pass. Defer to the next drift-reconciliation sweep.

## Destructive actions

Findings 0002 and 0003 propose `git rm` of duplicate files. Each includes full verification evidence showing which file is dead. Operator must explicitly approve destructive actions per spec §7.3.

**CRITICAL — contradiction with batch 02 housekeeping for CR-0309:** Batch 02's count note (line 5 + line 12 of `2026-04-09-batch-02-phase1-expansion.md`) states CR-2026-04-09-0309 was rejected as a duplicate of pre-seed CR-0003 on the claim that `src/ContractsList.jsx` (plural) is dead. **Current-state verification contradicts that claim.** Grep + file-read of `src/App.jsx` line 9 and `src/AppRouter.jsx` lines 51 + 86 shows the LIVE entry point imports `ContractsList` from `./ContractsList.jsx` (plural) — and the singular `src/screens/ContractList.jsx` is referenced ONLY by the dead `src/screens/AppRouter.jsx`. The dead file is the SINGULAR (`src/screens/ContractList.jsx`), not the plural. See finding 0003 below for the full evidence trail. The operator must reconcile this contradiction before the `git rm` lands.

## Non-destructive fixes (5 P3)

This batch closes out Phase 1 with five small P3 polish items scattered across speech, map injection, data-completeness guards, and error handling:

- **Group A — Speech error breadcrumb (1 finding: 0236).** SpeechMic's `rec.onerror = () => setListening(false)` discards the error event entirely; add a `console.warn` breadcrumb with `e.error` / `e.message` so Safari/iOS permission denials and 'no-speech' events leave a diagnostic trail.
- **Group B — Leaflet CDN config-ification (1 finding: 0258).** CustomerDetail's LocationsMapTab injects Leaflet CSS + JS from `https://unpkg.com/leaflet@1.9.4/...` at runtime. The narrow fix (option a per the operator directive) moves the two CDN URLs to `dcfg_configs` via `getEnvVar()` with the current values as fallbacks. The deeper refactor (option b — bundle Leaflet as an npm dep to match `MapView.jsx` which already does) is flagged as a Phase 3 follow-up because it touches the build config and would double-bundle Leaflet if CustomerDetail and MapView are ever loaded in the same session.
- **Group C — MapView truncation-warning guard (1 finding: 0282).** MapView's properties query caps at `$top=2000` with no UI indication when the cap is hit. Add a `console.warn` + toast warning when the response length is exactly 2000 (signals silent truncation). Current scale (~150 locations) is nowhere near the cap, but the cap is latent data-completeness risk as the system scales.
- **Group D — ProjectList apiGet error handlers (1 finding: 0287).** ProjectList's "+ New Project" inline panel triggers three `apiGet`s on open (properties, templates, customers) with no `.catch` handlers. Wrap each in a `.catch` that fires a `console.warn` + single toast so silent dropdown-empty failures get surfaced.
- **Group E — useContractData $top safety cap (1 finding: 0304).** useContractData loads ALL contracts client-side via `fetchContractsPaginated('')`. Narrow fix: detect when the returned array is "suspiciously large" (≥1000) and (a) slice client-side to a 1000-row cap, (b) expose a `truncated: true` flag in the hook return so a future render can surface a "showing first 1000 contracts" footer. This does NOT solve the bandwidth problem — Dataverse still returns every row — but it caps the in-memory blast radius and surfaces the scaling threshold to callers. Full fix (server-side `$top=1000` cap in `portalApi.fetchContractsPaginated` + server-side pagination + UI footer) is flagged as Phase 3.

## Scope rules (from spec §4.6)

- Batch size = 7 (2 P1 destructive + 5 P3)
- All `batch` tier — no catalog-only entries
- Every proposed-edit finding has verbatim before-code + concrete after-code
- Destructive findings (0002, 0003) carry verification evidence in place of a code diff
- No new module exports introduced — pure cleanup, no module-surface changes

## Cross-finding dependencies

- **0002 → 0003.** Both destructive. The AppRouter deletion (0002) and the ContractList deletion (0003) are independent `git rm`s — deleting one does not affect the other. But since the ContractList file lives under the dead AppRouter subtree (`src/screens/`), and since the dead AppRouter is the ONLY remaining importer of the dead ContractList file, the operator may wish to land both together to keep the `src/screens/` hygiene consistent.
- **0258 → `portalApi.getEnvVar`.** CustomerDetail already imports `getEnvVar` at line 15 — no new import needed.
- **0304 → portalApi.fetchContractsPaginated.** The narrow fix does NOT edit `portalApi.js` (that's the Phase 3 server-side fix). This batch's edit stays inside `useContractData.jsx` only and caps in memory after fetch.
- All other findings are independent edits.

---

## Findings in this batch

### CR-2026-04-09-0002 — Duplicate AppRouter files — src/AppRouter.jsx vs src/screens/AppRouter.jsx

**File (proposed delete):** src/screens/AppRouter.jsx
**Severity:** P1
**Category:** dead-code
**Destructive:** YES — `git rm`

**Verification evidence:**

Trace the live entry point:

1. **`src/main.jsx`** (the Vite entry) line 3:
   ```javascript
   import App from './App';
   ```
   No AppRouter import at the entry. AppRouter is loaded by App.jsx.

2. **`src/App.jsx`** line 9:
   ```javascript
   import AppRouter from './AppRouter';
   ```
   Relative import `./AppRouter` resolves to `src/AppRouter.jsx` — the ROOT-level file, NOT `src/screens/AppRouter.jsx`. App.jsx line 306 renders `<AppRouter />` inside the gated `{configLoaded && ...}` block.

3. **Grep across entire `src/` for `AppRouter`:**
   ```
   src/App.jsx:9:              import AppRouter from './AppRouter';
   src/AppRouter.jsx:57:       export default function AppRouter() { ... }
   src/screens/AppRouter.jsx:2:  * AppRouter.jsx - DCFG Power Pages SPA
   src/screens/AppRouter.jsx:40: export default function AppRouter() { ... }
   ```
   The ROOT-level `src/AppRouter.jsx` has exactly one importer (App.jsx). The `src/screens/AppRouter.jsx` has ZERO importers — no file in the tree imports `./screens/AppRouter` or `../screens/AppRouter`.

4. **Content comparison:**
   - `src/AppRouter.jsx` (LIVE): 163 lines. Declares all 40+ current routes including programs, projects, RFPs, absorption, NoraCopilot, interview, LocationManager, field — matches the current nav. Uses `<RoleGuard require="admin">` for admin routes. Comment header dated 2026-03-12 describing the split-pane contract pattern migration.
   - `src/screens/AppRouter.jsx` (DEAD): 60-ish lines. Uses `React.lazy()` + `Suspense` and declares a much smaller legacy route set (only MsaList, ContractList, Directory, Admin). No programs, projects, RFPs, absorption, NoraCopilot, interview, RoleGuard. This is an OLD router from before the expansion audit batches — its route list is a proper subset of the live router's route list and has no unique routes that would need to be preserved.

**Conclusion:** `src/screens/AppRouter.jsx` is DEAD. It has zero importers (verified by grep), declares a strict subset of the live router's routes, and predates the 2026-03-12 split-pane migration documented in the live router's header comment. Safe to remove.

**Proposed action:**
```bash
git rm src/screens/AppRouter.jsx
```

**Rationale:** Matches pre-seed finding CR-0002's recommendedFix and §7.3 operator-approval requirement. Deletion is strictly additive — it removes a dead code path that cannot be reached by the live entry point and that carries only latent risk (future maintainers editing the wrong file).

**Risk:** Zero against the live routing surface — `src/screens/AppRouter.jsx` has no importers. Rollback is trivial (`git revert`) if an unexpected importer surfaces later.

**Depends on:** none (but see dependency note re: 0003 — operator may wish to land both deletes in the same commit for `src/screens/` hygiene)

---

### CR-2026-04-09-0003 — Duplicate contract list files — src/ContractsList.jsx vs src/screens/ContractList.jsx

**File (proposed delete):** src/screens/ContractList.jsx  *(NOTE: see contradiction-with-batch-02 callout below)*
**Severity:** P1
**Category:** dead-code
**Destructive:** YES — `git rm`

**Verification evidence:**

1. **Live AppRouter (`src/AppRouter.jsx`) lines 51 + 86:**
   ```javascript
   // line 51 (imports block)
   import ContractsList      from './ContractsList.jsx';

   // line 86 (routes block)
   <Route path="contracts" element={<ContractsList />} />
   ```
   The LIVE router imports the PLURAL file `./ContractsList.jsx` (root-level, not under `screens/`) and mounts it at the `/contracts` route. The header comment at lines 7–8 is explicit:
   ```
   *   - Removed: screens/ContractList, screens/ContractDetail, screens/NewContractWizard (replaced)
   *   - Added: ContractsList (split-pane, replaces flat list + detail)
   ```
   The 2026-03-12 split-pane migration renamed the file to the plural `ContractsList.jsx` and moved it to the root level. The live router's header documents the singular `screens/ContractList.jsx` as REMOVED.

2. **Grep across entire `src/` for `ContractList` (singular) and `ContractsList` (plural):**
   ```
   src/ContractsList.jsx:2:              * ContractsList.jsx — DCFG Contracting Suite
   src/ContractsList.jsx:37:             export default function ContractsList() { ... }
   src/ContractsList.jsx:15:             import { useContractData } from './contracts/useContractData.jsx';
   src/AppRouter.jsx:51:                 import ContractsList      from './ContractsList.jsx';
   src/AppRouter.jsx:86:                 <Route path="contracts" element={<ContractsList />} />
   src/AppRouter.jsx:8:                    *   - Added: ContractsList (split-pane, replaces flat list + detail)
   src/screens/AppRouter.jsx:17:         const ContractList      = lazy(() => import('./screens/ContractList.jsx'));
   src/screens/AppRouter.jsx:51:         <Route path="/contracts"  element={<ContractList />} />
   src/screens/ContractList.jsx:2:        * ContractList.jsx - Contract List screen
   src/screens/ContractList.jsx:19:       export default function ContractList() { ... }
   ```
   - `src/ContractsList.jsx` (plural): ONE importer — the LIVE `src/AppRouter.jsx`.
   - `src/screens/ContractList.jsx` (singular): ONE importer — the DEAD `src/screens/AppRouter.jsx` (which finding 0002 proposes to delete above).

3. **Transitive reachability from the entry point:**
   `main.jsx` → `App.jsx` → `src/AppRouter.jsx` → `src/ContractsList.jsx`. The plural file is reachable. `src/screens/ContractList.jsx` is ONLY reachable through `src/screens/AppRouter.jsx`, which is itself unreachable (see 0002). The singular file is therefore unreachable from the entry point — DEAD.

4. **Content spot check:**
   - `src/ContractsList.jsx` (LIVE, 7012 bytes): "Three switchable production views" header comment, imports `useContractData` from `./contracts/useContractData.jsx`, renders the split-pane view-toggle shell that matches current production UX (verified by the view-toggle screenshots in `docs/screenshots/`).
   - `src/screens/ContractList.jsx` (DEAD, 5777 bytes): flat-list screen, header says "ContractList.jsx - Contract List screen", no view-toggle, no split-pane — the pre-2026-03-12 legacy shape.

**Conclusion:** `src/screens/ContractList.jsx` (SINGULAR) is DEAD. It has exactly one importer (`src/screens/AppRouter.jsx`) which is itself dead per 0002. The LIVE contract list is `src/ContractsList.jsx` (PLURAL) at the root level. Safe to remove the singular file.

**⚠️ CONTRADICTION WITH BATCH 02 HOUSEKEEPING — operator attention required:**

Batch 02's count note (`2026-04-09-batch-02-phase1-expansion.md` lines 5 + 12) states CR-2026-04-09-0309 was marked `rejected` on the premise that `src/ContractsList.jsx` (PLURAL) is the dead file, duplicating pre-seed CR-0003. The rejectReason in `findings.json` line 2783 reads:

> "Duplicate of pre-seed CR-2026-04-09-0003 (ContractsList.jsx duplicate of screens/ContractList.jsx). Tracking the original."

And the CR-0309 detail (findings.json line 2771) reads:

> "Confirmed during file-by-file walk: src/ContractsList.jsx is a 'three switchable views' wrapper that imports from contracts/* but is not referenced by the live router. The active contract-list screen per AppRouter is src/screens/ContractList.jsx (a separate shorter file)."

**This is wrong against current state.** The phase-1-expansion-audit agent that filed CR-0309 recorded the wrong conclusion — it claimed the PLURAL file was dead and the SINGULAR file was live. My verification (done for this batch) reads the ACTUAL live router file `src/AppRouter.jsx` and the ACTUAL entry point `src/main.jsx` → `src/App.jsx` and finds the reverse: the PLURAL file is LIVE and the SINGULAR file is DEAD. The expansion-audit agent may have been reading `src/screens/AppRouter.jsx` in isolation and mistook it for the live router.

**What the operator needs to decide before approving this destructive action:**

1. **Accept my verification** (RECOMMENDED): `git rm src/screens/ContractList.jsx`. The evidence trail above is unambiguous — live entry point, live AppRouter file, grep results all confirm the plural is live. The batch 02 housekeeping note recorded the wrong conclusion on CR-0309 and should be corrected during this approval pass. Housekeeping follow-up: mark CR-0309's `rejectReason` as stale and re-open it as a tracking-only duplicate of CR-0003 with the CORRECT direction (singular is dead), OR leave CR-0309 rejected since it is indeed subsumed by CR-0003 and the direction is recorded correctly in THIS doc.

2. **Re-verify independently.** If the operator wants a second pair of eyes, the one-command check is: `grep -r "from './ContractsList'\|from './screens/ContractList'" C:/DCFG/spa/dcfg-shell/src/` — the first pattern should return a hit in `src/AppRouter.jsx`, the second pattern should return zero hits (or only a hit in `src/screens/AppRouter.jsx` which is itself dead).

3. **Hold the batch if uncertain.** If the contradiction cannot be resolved, the P3 group (0236, 0258, 0282, 0287, 0304) can still be approved selectively while 0002 and 0003 are held.

**Proposed action (pending operator reconciliation):**
```bash
git rm src/screens/ContractList.jsx
```

**Rationale:** Matches pre-seed finding CR-0003's recommendedFix and §7.3 operator-approval requirement — once the operator confirms which file is dead. The deletion is strictly additive; it removes a legacy flat-list component whose split-pane replacement lives at `src/ContractsList.jsx`.

**Risk:** Zero IF the verification above holds. Rollback is trivial (`git revert`). The ONLY risk vector is if the batch-02 CR-0309 housekeeping was correct and my verification is wrong — in which case deleting the plural instead of the singular would break the live contracts route. The operator should apply the one-command re-verification in option 2 above before approving.

**Depends on:** 0002 (same-batch) — 0002's `src/screens/AppRouter.jsx` deletion removes the only importer of `src/screens/ContractList.jsx`, making this delete trivially safe. Landing 0002 without 0003 is fine (singular file just becomes an unimportable orphan). Landing 0003 without 0002 is also fine (0002's dead router references a file that no longer exists, which would produce a build warning IF something re-awakened the dead router — it would not). Operator may prefer to land both in the same commit for `src/screens/` hygiene.

---

### CR-2026-04-09-0236 — SpeechMic rec.onerror handler discards the error event entirely

**File:** src/SpeechMic.jsx
**Line(s):** 40
**Severity:** P3
**Category:** error-handling

**Verification:** Confirmed by reading `src/SpeechMic.jsx`. Line 40 reads `rec.onerror = () => setListening(false);` — the arrow function takes zero arguments and the `error` event object is discarded. The Web Speech API's `SpeechRecognitionErrorEvent` carries an `error` property (one of `no-speech`, `audio-capture`, `not-allowed`, `service-not-allowed`, `bad-grammar`, `language-not-supported`, `network`, `aborted`) plus a `message` property. The current handler loses both.

**Current code (lines 36-44):**
```javascript
    rec.onresult = (e) => {
      const transcript = e.results[0]?.[0]?.transcript;
      if (transcript) onTranscript(transcript);
    };
    rec.onerror = () => setListening(false);
    rec.onend = () => setListening(false);
    recRef.current = rec;
    setListening(true);
    rec.start();
```

**Proposed edit:**
```javascript
    rec.onresult = (e) => {
      const transcript = e.results[0]?.[0]?.transcript;
      if (transcript) onTranscript(transcript);
    };
    // CR-2026-04-09-0236: capture the error event instead of discarding it.
    // The SpeechRecognitionErrorEvent carries an `error` property (e.g.
    // 'no-speech', 'not-allowed', 'network') that is useful diagnostic info
    // for Safari/iOS permission denials. No toast — that would be annoying
    // for accidental clicks — just a console.warn breadcrumb.
    rec.onerror = (e) => {
      setListening(false);
      console.warn('[SpeechMic] recognition error:', e?.error || 'unknown', e?.message || '');
    };
    rec.onend = () => setListening(false);
    recRef.current = rec;
    setListening(true);
    rec.start();
```

**Rationale:** Matches `recommendedFix` exactly. The handler now accepts the event argument, logs the `error` and `message` fields, and preserves the existing `setListening(false)` behavior so the button state still resets. No new props, no toast, no onError callback — this is purely a diagnostic breadcrumb for ops.

**Risk:** Zero. Behavior-preserving for all callers (the button state reset is unchanged). The only new behavior is a `console.warn` line when the recognition session errors — which is additive information.

**Depends on:** none

---

### CR-2026-04-09-0258 — LocationsMapTab injects Leaflet CSS/JS from CDN at runtime — hardcoded unpkg.com URLs

**File:** src/screens/CustomerDetail.jsx
**Line(s):** 615-629 (CDN injection block), function `LocationsMapTab`
**Severity:** P3
**Category:** handoff-cleanliness

**Verification:** Confirmed by reading `src/screens/CustomerDetail.jsx` lines 599-650. The `LocationsMapTab` component (line 603) injects Leaflet CSS (line 620) and JS (line 625) from hardcoded `https://unpkg.com/leaflet@1.9.4/...` URLs. Cross-check with `src/screens/MapView.jsx` lines 10-11 confirms MapView imports leaflet as an npm dep (`import L from 'leaflet'; import 'leaflet/dist/leaflet.css';`) — so the bundle already ships a copy of Leaflet for the `/map` route. CustomerDetail duplicates the Leaflet surface via runtime CDN injection, which is the category-11 cleanliness issue. `getEnvVar` is already imported on line 15 of CustomerDetail.jsx — no new import needed.

**Option (a) — narrow fix (this batch):** Move the two CDN URLs into `dcfg_configs` via `getEnvVar()` with the current hardcoded URLs as fallbacks. Unlocks per-environment override without touching the build system.

**Option (b) — full fix (Phase 3 follow-up, FLAGGED NOT IN THIS BATCH):** Replace the runtime CDN injection with `import L from 'leaflet'; import 'leaflet/dist/leaflet.css';` at the top of CustomerDetail.jsx, matching MapView's pattern. This is invasive because (1) it means two screens in the same SPA both pull Leaflet at bundle time, doubling the Leaflet surface on combined renders unless Vite's tree-shake/code-split story handles it cleanly, (2) the CustomerDetail tab bar lazy-loads the tab content so eagerly-bundling Leaflet imposes a cost even for customers who never open the Locations tab, (3) the runtime injection currently has a side benefit — it's cached at `window.L` so re-mounts don't re-download. Moving to `import L` means each tab open re-runs the leaflet init which would need verification against the existing render flow.

**Current code (lines 615-629):**
```javascript
  // Load Leaflet CSS + JS from CDN
  useEffect(() => {
    if (!document.getElementById('leaflet-css')) {
      const css = document.createElement('link');
      css.id = 'leaflet-css'; css.rel = 'stylesheet';
      css.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
      document.head.appendChild(css);
    }
    if (!window.L && !document.getElementById('leaflet-js')) {
      const js = document.createElement('script');
      js.id = 'leaflet-js'; js.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
      js.onload = () => renderMap();
      document.head.appendChild(js);
    }
  }, []);
```

**Proposed edit:**
```javascript
  // Load Leaflet CSS + JS from CDN
  // CR-2026-04-09-0258: the two unpkg URLs below were hardcoded. They are
  // now resolved via getEnvVar() from dcfg_configs so ops can pin a
  // different CDN / version / local mirror per environment without a
  // code change. The current unpkg URLs remain as fallbacks so behavior
  // is byte-identical until the dcfg_configs rows are provisioned.
  // Phase 3 follow-up: bundle leaflet as an npm dep to match MapView.jsx
  // (see LocationsMapTab header comment above for the trade-offs).
  useEffect(() => {
    const leafletCssUrl = getEnvVar('dcfg_leaflet_css_url') || 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    const leafletJsUrl  = getEnvVar('dcfg_leaflet_js_url')  || 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    if (!document.getElementById('leaflet-css')) {
      const css = document.createElement('link');
      css.id = 'leaflet-css'; css.rel = 'stylesheet';
      css.href = leafletCssUrl;
      document.head.appendChild(css);
    }
    if (!window.L && !document.getElementById('leaflet-js')) {
      const js = document.createElement('script');
      js.id = 'leaflet-js'; js.src = leafletJsUrl;
      js.onload = () => renderMap();
      document.head.appendChild(js);
    }
  }, []);
```

**Rationale:** Narrow config-ification matching the operator directive's option (a). Two coupled changes:
1. Resolve each URL via `getEnvVar('dcfg_leaflet_css_url')` / `getEnvVar('dcfg_leaflet_js_url')` at effect time (not module scope — `loadConfig` must have completed before `getEnvVar` returns real values, and effects run after the `configLoaded` gate per App.jsx line 226).
2. Fall back to the current hardcoded unpkg URLs via `||` so the page works out-of-the-box even before the dcfg_configs rows are provisioned in Test/Stage/Prod.

`getEnvVar` is already imported at line 15 of CustomerDetail.jsx so no new import is needed.

**Risk:** Zero until dcfg_configs rows are provisioned (behavior byte-identical to current state via fallback). After provisioning, risk scales with whatever URL the operator puts in the config rows — a broken override would show the map-tab with an empty map, matching today's failure mode if unpkg.com is unreachable.

**Operator-attention item (Phase 3 follow-up):** Bundle Leaflet as an npm dep to match MapView.jsx. Tracking title: "CustomerDetail LocationsMapTab — switch from runtime CDN to bundled leaflet import to match MapView". Also: after this batch deploys, provision `dcfg_leaflet_css_url` and `dcfg_leaflet_js_url` rows in `dcfg_configs` on Test / Stage / Prod so the override path is exercised.

**Depends on:** `getEnvVar` (already imported line 15). No new dcfg_configs rows are required for the fix to work — fallbacks carry the current behavior.

---

### CR-2026-04-09-0282 — MapView properties query capped at $top=2000 — silent truncation above that

**File:** src/screens/MapView.jsx
**Line(s):** 56-83 (the `load` useEffect in the map component)
**Severity:** P3
**Category:** data-integrity

**Verification:** Confirmed by reading `src/screens/MapView.jsx` lines 55-90. Line 63 passes `$top=2000` to the `apiGet` call. Lines 65-66 consume the response via `const locs = r?.value ?? []; setLocations(locs);`. There is NO length-check against the cap and NO UI surface for truncation. Current scale is well under 2000 so not a live issue, but latent. `useToast` is already imported at line 13 and `toast` is already destructured at line 53, so no new wiring is needed for the warning.

**Current code (lines 56-78):**
```javascript
  // Load locations with geocoding
  useEffect(() => {
    async function load() {
      try {
        const r = await apiGet(
          `/${EntitySets.properties}?$select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_latitude,dcfg_longitude,dcfg_contact_person,dcfg_active_flag` +
          `&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_location_type_id($select=dcfg_name)` +
          `&$filter=dcfg_active_flag eq true and dcfg_latitude ne null and dcfg_longitude ne null and dcfg_latitude ne 0 and dcfg_longitude ne 0` +
          `&$orderby=dcfg_name asc&$top=2000`
        );
        const locs = r?.value ?? [];
        setLocations(locs);

        // Extract unique customers for legend + filter
        const custMap = {};
        locs.forEach(l => {
          const c = l.dcfg_customer_id;
          if (c && c.dcfg_customerid && !custMap[c.dcfg_customerid]) {
            custMap[c.dcfg_customerid] = c.dcfg_name;
          }
        });
        const custList = Object.entries(custMap).map(([id, name], i) => ({ id, name, color: getColor(i) }));
        setCustomers(custList);
      } catch (err) {
```

**Proposed edit:**
```javascript
  // Load locations with geocoding
  useEffect(() => {
    async function load() {
      try {
        const r = await apiGet(
          `/${EntitySets.properties}?$select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_latitude,dcfg_longitude,dcfg_contact_person,dcfg_active_flag` +
          `&$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name),dcfg_location_type_id($select=dcfg_name)` +
          `&$filter=dcfg_active_flag eq true and dcfg_latitude ne null and dcfg_longitude ne null and dcfg_latitude ne 0 and dcfg_longitude ne 0` +
          `&$orderby=dcfg_name asc&$top=2000`
        );
        const locs = r?.value ?? [];
        setLocations(locs);

        // CR-2026-04-09-0282: the $top=2000 cap above is latent data-
        // completeness risk. If the response hits the cap exactly,
        // Dataverse silently truncated the tail — the operator needs
        // to know. Current scale (~150 locations) is nowhere near the
        // cap so this warning should never fire in practice. If it
        // does, the Phase 3 fix is a proper server-side pagination
        // pass over the properties entity set.
        if (locs.length === 2000) {
          console.warn('[MapView] properties query hit $top=2000 cap — map may be missing records beyond the first 2000');
          toast.show('warn', 'Map showing first 2000 locations — filter by customer to see the rest');
        }

        // Extract unique customers for legend + filter
        const custMap = {};
        locs.forEach(l => {
          const c = l.dcfg_customer_id;
          if (c && c.dcfg_customerid && !custMap[c.dcfg_customerid]) {
            custMap[c.dcfg_customerid] = c.dcfg_name;
          }
        });
        const custList = Object.entries(custMap).map(([id, name], i) => ({ id, name, color: getColor(i) }));
        setCustomers(custList);
      } catch (err) {
```

**Rationale:** Matches `recommendedFix` with a single added `if (locs.length === 2000)` check plus `console.warn` + `toast.show('warn', ...)`. The warning fires only on EXACT-match to the cap — this is a defensible heuristic because the probability of a real dataset containing exactly 2000 geocoded active locations is negligible; any production dataset that returns exactly 2000 rows is almost certainly truncated. If the real count is 1999 or 2001, the warning behavior is correct (no fire at 1999, fires at 2000 which is the truncation boundary).

**Risk:** Zero. The `console.warn` + toast only fire when the cap is hit, which it isn't today. Consumers that never hit the cap see byte-identical behavior.

**Depends on:** `useToast` (already imported line 13), `toast` (already destructured line 53).

---

### CR-2026-04-09-0287 — ProjectList New Project panel load-customers/templates/properties apiGets have no error handlers

**File:** src/screens/ProjectList.jsx
**Line(s):** 83-88
**Severity:** P3
**Category:** error-handling

**Verification:** Confirmed by reading `src/screens/ProjectList.jsx` lines 80-90. The `useEffect` gated by `showNew` fires three parallel async fetches (properties via `apiGet`, templates via `fetchProjectTemplates`, customers via `fetchCustomers`) and each only has a `.then`. Any failure produces an empty dropdown with no toast, no console, no hint to the user. `useToast` is already imported and used elsewhere in the file (grep confirms `toast.show` usage in `handleCreate`), so no new wiring is needed.

**Current code (lines 80-89):**
```javascript
  // Load customers, properties, templates when panel opens
  useEffect(() => {
    if (!showNew) return;
    apiGet(`/${EntitySets.properties}?$filter=dcfg_active_flag eq true&$select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,_dcfg_customer_id_value&$orderby=dcfg_name asc&$top=500`)
      .then(r => setProperties(r?.value ?? []));
    fetchProjectTemplates()
      .then(r => setTemplates(r?.value ?? []));
    fetchCustomers()
      .then(r => setCustomers(r?.value ?? []));
  }, [showNew]);
```

**Proposed edit:**
```javascript
  // Load customers, properties, templates when panel opens
  // CR-2026-04-09-0287: each of the three fetches below previously had
  // no .catch. A failure silently produced an empty dropdown with no
  // hint to the user. Each fetch now catches, logs a console.warn
  // breadcrumb naming the failed fetch, and surfaces a single toast
  // per-fetch so the user knows which dropdown failed to populate.
  useEffect(() => {
    if (!showNew) return;
    apiGet(`/${EntitySets.properties}?$filter=dcfg_active_flag eq true&$select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,_dcfg_customer_id_value&$orderby=dcfg_name asc&$top=500`)
      .then(r => setProperties(r?.value ?? []))
      .catch(err => {
        console.warn('[ProjectList] load properties failed:', err);
        toast.show('err', 'Failed to load properties for New Project panel');
      });
    fetchProjectTemplates()
      .then(r => setTemplates(r?.value ?? []))
      .catch(err => {
        console.warn('[ProjectList] load project templates failed:', err);
        toast.show('err', 'Failed to load project templates');
      });
    fetchCustomers()
      .then(r => setCustomers(r?.value ?? []))
      .catch(err => {
        console.warn('[ProjectList] load customers failed:', err);
        toast.show('err', 'Failed to load customers for New Project panel');
      });
  }, [showNew]);
```

**Rationale:** Matches `recommendedFix` with a `.catch` on each of the three fetches. Each catch (1) logs a console.warn naming the failed fetch so an engineer can grep for the breadcrumb, (2) fires a toast so the user knows which dropdown is empty because of a failure vs. because there is no data. No retry, no fallback — just surface the failure.

**Risk:** Zero. Each `.catch` is additive. Success paths are byte-identical. Failure paths now surface the error instead of silently emptying the dropdown.

**Depends on:** `toast` (already in scope via `useToast` usage elsewhere in the file).

---

### CR-2026-04-09-0304 — useContractData loads ALL contracts client-side then paginates in memory

**File:** src/contracts/useContractData.jsx
**Line(s):** 29-41 (the `load` callback) + 90-96 (the hook return)
**Severity:** P3
**Category:** performance

**Verification:** Confirmed by reading `src/contracts/useContractData.jsx` lines 1-97. Line 31 calls `fetchContractsPaginated('')` which in `src/portalApi.js` line 414-418 issues a single Dataverse query with no `$top` cap. The response is stored in `allContracts` (line 33), then filtered (line 46-65) and paginated (line 70-73) entirely client-side via `Array.slice()`. Current scale (~200 contracts) is fine; the detail on CR-0304 notes "scales poorly to 2,000+". `fetchContractsPaginated` lives in `portalApi.js` and is consumed only by this hook (grep across `src/` for `fetchContractsPaginated` returns two hits: the export site in portalApi.js and the import in this file).

**Why the narrow fix stays inside useContractData.jsx:**

The operator directive specifies: "Propose a narrow fix: add $top=1000 cap with a 'showing first 1000 contracts' footer note. Flag full server-side pagination as Phase 3."

The ideal narrow fix would be to edit `fetchContractsPaginated` in portalApi.js to append `&$top=1000` to the query string, which saves bandwidth. But that's a shared-module edit outside the finding file and would need its own batch-01-style shared-module treatment.

The narrower still fix — staying inside `useContractData.jsx` only — is:
1. After `fetchContractsPaginated` resolves, cap the array to 1000 rows client-side via `.slice(0, 1000)`.
2. Expose a `truncated` flag in the hook's return shape so `ContractsList.jsx` (the single consumer) can render a footer note in a follow-up edit.

This does NOT solve the bandwidth problem — Dataverse still returns every row — but it does cap the in-memory blast radius (React state, useMemo filter, useMemo pagination all process at most 1000 rows) AND it surfaces the scaling threshold to callers via a typed flag. The full server-side `$top` + pagination pass is flagged as Phase 3.

**Current code (lines 29-41 + 90-96):**
```javascript
  // Load all contracts once
  var load = useCallback(function() {
    setLoading(true);
    fetchContractsPaginated('')
      .then(function(r) {
        setAllContracts(r && r.value ? r.value : []);
        setLoading(false);
      })
      .catch(function(e) {
        console.error('Contract load failed:', e);
        setAllContracts([]);
        setLoading(false);
      });
  }, []);
```

```javascript
  return {
    contracts: contracts, grouped: grouped, loading: loading, totalCount: totalCount,
    page: page, setPage: setPage, totalPages: totalPages,
    viewMode: viewMode, setViewMode: setViewMode,
    searchTerm: searchTerm, setSearchTerm: setSearchTerm,
    refresh: load, allContracts: allContracts,
  };
}
```

**Proposed edit (load callback + new truncated state, replaces lines 16-41):**
```javascript
// CR-2026-04-09-0304: client-side safety cap. Power Pages Web API does not
// support $skip so true server-side pagination is not an option. The narrow
// fix is a 1000-row client-side cap — any response above 1000 rows is
// truncated and the hook exposes a `truncated: true` flag so ContractsList
// (the single consumer) can render a "showing first 1000 contracts" footer
// in a follow-up edit. This does NOT save bandwidth — Dataverse still
// returns every row — but it caps the in-memory blast radius (state,
// filter, pagination all process at most 1000 rows) and surfaces the
// scaling threshold to callers. Phase 3 follow-up: add $top=1000 to
// fetchContractsPaginated in portalApi.js and add the footer UI.
var CLIENT_SIDE_CAP = 1000;

export function useContractData() {
  var _all = useState([]);
  var allContracts = _all[0], setAllContracts = _all[1];
  var _t = useState(false);
  var truncated = _t[0], setTruncated = _t[1];
  var _l = useState(true);
  var loading = _l[0], setLoading = _l[1];
  var _p = useState(0);
  var page = _p[0], setPage = _p[1];
  var _vm = useState('attention');
  var viewMode = _vm[0], setViewMode = _vm[1];
  var _st = useState('');
  var searchTerm = _st[0], setSearchTerm = _st[1];

  // Load all contracts once (capped client-side — see CR-2026-04-09-0304
  // comment above).
  var load = useCallback(function() {
    setLoading(true);
    fetchContractsPaginated('')
      .then(function(r) {
        var raw = (r && r.value) ? r.value : [];
        if (raw.length > CLIENT_SIDE_CAP) {
          console.warn('[useContractData] contract count ' + raw.length + ' exceeds client-side cap ' + CLIENT_SIDE_CAP + ' — truncating in memory. See CR-2026-04-09-0304.');
          setTruncated(true);
          setAllContracts(raw.slice(0, CLIENT_SIDE_CAP));
        } else {
          setTruncated(false);
          setAllContracts(raw);
        }
        setLoading(false);
      })
      .catch(function(e) {
        console.error('Contract load failed:', e);
        setAllContracts([]);
        setTruncated(false);
        setLoading(false);
      });
  }, []);
```

**Proposed edit (return shape, replaces lines 90-96):**
```javascript
  return {
    contracts: contracts, grouped: grouped, loading: loading, totalCount: totalCount,
    page: page, setPage: setPage, totalPages: totalPages,
    viewMode: viewMode, setViewMode: setViewMode,
    searchTerm: searchTerm, setSearchTerm: setSearchTerm,
    refresh: load, allContracts: allContracts,
    // CR-2026-04-09-0304: true when the last load returned more than 1000
    // rows and was truncated client-side. ContractsList should render a
    // "showing first 1000 contracts" footer when this is true (Phase 3
    // follow-up — not in this batch's edit surface).
    truncated: truncated,
  };
}
```

**Rationale:** Matches the operator directive as closely as possible while keeping the edit inside the finding file. Three coupled changes:
1. New module-scope constant `CLIENT_SIDE_CAP = 1000` — documents the threshold and makes future tuning a one-line edit.
2. New `truncated` useState — exposes the flag to callers without changing any existing field.
3. Conditional `.slice(0, CLIENT_SIDE_CAP)` in the load callback — caps in memory only if the raw response exceeds the cap, otherwise stores the full response unchanged.

The return shape change is strictly additive (new `truncated` field) — existing callers that destructure `contracts`, `grouped`, `loading`, etc. keep working unchanged.

**Risk:** Low. At current scale (~200 contracts), the cap is never hit and behavior is byte-identical. Above 1000 contracts, the hook silently caps the result set and surfaces the flag — strictly safer than today's behavior (which would just keep piling rows into React state and regenerating useMemo on every keystroke). The only failure mode is if the 1001st contract carries data a user needed to see; that surfaces as the `truncated` flag being true and the follow-up footer UI will make it visible.

**Operator-attention items (Phase 3 follow-ups):**
- Add `$top=1000` to `fetchContractsPaginated` in `src/portalApi.js` (saves bandwidth, not just memory).
- Add a "showing first 1000 contracts" footer in `src/ContractsList.jsx` when `data.truncated === true`.
- Evaluate switching to a server-side rollup table when load exceeds 1000 contracts in any environment.

**Depends on:** none (all edits inside `useContractData.jsx`).

---

## Approval options

Reply with:
- `approve batch` — execute all 7 proposed actions (5 P3 edits + 2 `git rm`s)
- `approve <id1>,<id2>,...` — selective (destructive findings 0002/0003 can be held while P3 group lands)
- `reject <id>` — skip
- `reject batch` — cancel
- `hold` — park

**Operator-attention / housekeeping follow-ups (out of scope for this batch — operator action during approval pass):**
- **CR-2026-04-09-0309 reconciliation.** Batch 02's rejectReason for CR-0309 recorded the DIRECTION of the ContractsList/ContractList duplication backwards. The evidence trail in finding 0003 above is the corrected direction. Either (a) update CR-0309's rejectReason in findings.json to reflect the correct direction (singular is dead, plural is live) while keeping its `rejected` status, or (b) re-open CR-0309 as a tracking duplicate of CR-0003. Recommend option (a) — the reject verdict stands, only the prose is wrong.
- **CR-2026-04-09-0258** — after deploy, provision `dcfg_leaflet_css_url` and `dcfg_leaflet_js_url` rows in `dcfg_configs` on Test / Stage / Prod so the override path is exercised (SPA falls back to current unpkg URLs until the rows exist). Flag Phase 3 follow-up: "CustomerDetail LocationsMapTab — bundle leaflet as npm dep to match MapView".
- **CR-2026-04-09-0282** — if the MapView warning ever fires in real use, schedule a proper server-side pagination pass over the properties entity set.
- **CR-2026-04-09-0304** — Phase 3: (a) add `$top=1000` to `fetchContractsPaginated` in portalApi.js, (b) add the "showing first 1000 contracts" footer in ContractsList.jsx when `data.truncated === true`, (c) evaluate a server-side rollup table.
- **CR-2026-04-09-0268** — pending flow-deploy coordination batch (paired with CR-0274-style migration).
- **CR-2026-04-09-0299** — pending drift-reconciliation sweep.
