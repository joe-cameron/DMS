# SPA Code Review & Cleanup — Design Spec

**Date:** 2026-04-09
**Author:** Joseph Cameron / Claude
**Status:** Draft
**Scope:** Full-SPA code review and cleanup of `C:\DCFG\spa\dcfg-shell\src\` in preparation for external-user testing of DCFG Contracting Suite on `dmms1.powerappsportals.com`.

---

## 1. Why This Exists

The DCFG SPA has accumulated fixes, feature additions, and one-off patches over the last several weeks without a consolidated quality pass. The operator is preparing to run **external, customer-facing user testing** — meaning strangers will interact with the portal directly. That raises the bar for the entire codebase to: *no crashes, clear error states, accessible, visually consistent, and no latent bugs waiting to be triggered by real users.*

This review is quality-driven (no hard deadline) and explicitly gated — the SPA is read-only by default per `CLAUDE.md`, so every change requires explicit operator approval.

### 1.1 Source context

**Handoff:** `C:\DCFG\docs\handoff-code-review-2026-04-09.md`

**Critical behavioral rule in force:** `feedback_pick_lane_explicit_or_wildcard.md` — never oscillate `Webapi/{table}/fields` between explicit and wildcard. Fix the consumer, not the config.

**Environment correction from handoff:** pac auth indices are currently `[1]=Prod, [2]=Test, [3]=Stage, [4]=Portal`. This disagrees with `CLAUDE.md` but has been verified this session via `pac auth list`. Always run `pac auth list` before any deploy command.

#### 1.1.1 Summary of the six changes already landed on Prod (from handoff + this session)

These are the changes Phase 0 parity-checks against Test and Stage. Every one is on Prod only; neither Test nor Stage has been backported at spec-writing time.

| # | Change | Target | Before | After | Source |
|---|---|---|---|---|---|
| 1 | Add `dcfg_template_id` bind form | `Webapi/dcfg_template_field/fields` on dmms1 (component `5966d12d-2127-f111-8341-000d3a35c231`) | trailing `statuscode` | `statuscode,dcfg_template_id` | Handoff Change 1 |
| 2 | Add `dcfg_customer_id` bind form | `Webapi/dcfg_document_template/fields` on dmms1 (component `7f89f92f-2d34-f111-88b3-000d3a308009`) | trailing `dcfg_template_file_name` | `dcfg_template_file_name,dcfg_customer_id` | Handoff Change 2 |
| 3 | SPA explicit `$select` | `src/screens/templates/useTemplateFields.js` `loadFields` GET | bare GET | `$select=dcfg_template_fieldid,...` (13 cols) | Handoff Change 3 |
| 4 | SPA explicit `$select` | `src/screens/templates/TemplateDetail.jsx` line ~414 template GET | bare GET | `$select=dcfg_document_templateid,dcfg_name,dcfg_template_type,dcfg_notes,_dcfg_customer_id_value` | Handoff Change 4 |
| 5 | Add `dcfg_customer_id` bind form | `Webapi/dcfg_blanket_workorder/fields` on dmms1 (component `da544a98-622c-f111-88b3-6045bd02d765`) | trailing `_dcfg_customer_id_value` | `_dcfg_customer_id_value,dcfg_customer_id` | This session hotfix |
| 6 | Add `dcfg_customer_id` + `dcfg_cost_code_id` bind forms | `Webapi/dcfg_customer_ap_mapping/fields` on dmms1 (component `e0544a98-622c-f111-88b3-6045bd02d765`) | trailing `_dcfg_cost_code_id_value` | `_dcfg_cost_code_id_value,dcfg_customer_id,dcfg_cost_code_id` | This session hotfix |

Also landed this session (related but not parity-checked): config drift revert on `dcfg_sp_templates_library` from `DMS_Templates` → `DCFG_Templates` (Prod only, handoff Change 6).

**This session's artifacts (scripts + backups, audit trail):**
- Backup: `C:\dcfg\scripts\_backups\2026-04-09_admin-bind-forms-before.json`
- Fix script: `C:\dcfg\scripts\fix-admin-bind-forms-2026-04-09.ps1` (idempotent)
- Validate script: `C:\dcfg\scripts\validate-admin-bind-forms-2026-04-09.ps1` (read-only)
- Portal cache cleared manually by operator + smoke-tested — Admin blanket WO + AP mapping creation both green.

---

## 2. Scope

### 2.1 In scope (~68 files)

Customer-facing bar applies to all of these. Shared modules audited first because their issues propagate to consumers.

**Shared modules (audited first, Phase 1) — 17 files:**
`main.jsx`, `App.jsx`, `AppRouter.jsx`, `portalApi.js`, `useTableControls.jsx`, `usePortalUser.jsx`, `Toast.jsx`, `NavPanel.jsx`, `RoleGuard.jsx`, `SlideOutPanel.jsx`, `SpeechMic.jsx`, `FieldName.jsx`, `ErrorReporter.jsx`, `LocationManager.jsx`, `SensorBanner.jsx`, `intakeFieldKeys.js`, `projectConstants.js`.

**Sales section:** `SalesDashboard`, `CustomerList`, `CustomerDetail`, `MsaList`, `MsaDetail`.

**Contracts section:** `ContractList`, `ContractDetail`, `contracts/ContractRowDetail`, `contracts/useContractData`, `contracts/ViewSmartList`, `contracts/ViewCustomerGroups`, `contracts/ViewSplitPanel`.

**Document wizards:** `NewContractWizard`, `NewProposalWizard`, `NewRfpWizard`.

**Facilities section:** `FacilitiesDashboard`, `Locations`, `LocationDetail`, `Operations`, `CompliancePanel`, `Directory`, `MapView`, `VendorList`, `VendorDetail`.

**Onboarding section:** `Onboarding`, `OnboardingDetail`.

**Administration section:** `Admin` (all sub-tabs: Templates, onboarding steps, location types, cost codes, appliance types, vendors, benchmarks), `UserRolesTab`, `SendQueue`.

**Programs & Projects:** `ProgramList`, `ProgramDetail`, `ProjectDashboard`, `ProjectList`, `ProjectDetail`, `RfpList`, `RfpDetail`.

**Templates subsystem (DocGen V4 UI):** `screens/templates/TemplateList`, `TemplateDetail`, `CompositeExpander`, `FieldMappingCard`, `FieldMappingPanel`, `DocumentPreview`, `fieldRegistry.js`, `autoMapper.js`, `useTemplateFields.js`.

**Internal tool (reviewed but lower bar):** `FlowMonitor`.

### 2.2 Out of scope

Not reviewed this pass. Documented here so the exclusion is explicit and revisitable.

- `NoraCopilot` — internal monitoring UI
- `AbsorptionDashboard` — analytics, internal
- `UserManual` — static content
- `CapitalPlan` — not in customer-facing path for this round
- `_archive/` folder — recommended for deletion in Phase 2 auto-fix pass, not review
- `debug/` folder — opt-in diagnostic, not user-facing
- `interview/` folder — old wizard; `interviewGenerate.js` still uses stale `callFlow` — handled as a separate migration, not this review

### 2.3 Known structural issues already visible (feed into Phase 2 auto-fix)

Identified during context exploration; confirmed at the file level:

- **Duplicate router:** `src/AppRouter.jsx` AND `src/screens/AppRouter.jsx` both exist
- **Duplicate contract list:** `src/ContractsList.jsx` AND `src/screens/ContractList.jsx`
- **Duplicate wizard entry:** `src/NewContractWizard.jsx` live + `src/_archive/NewContractWizard.jsx` archived
- **Latent build warning:** `NewContractWizard.jsx:942` — stray `)}` JSX closer from a deleted vendor-selection block; esbuild tolerates today but a tighter version could fail

### 2.4 File-count reconciliation

`Glob` over `src/**/*.{js,jsx,ts,tsx}` returns approximately 82 files. After excluding `_archive/`, `debug/`, `interview/`, `NoraCopilot`, `AbsorptionDashboard`, `UserManual`, `CapitalPlan`, and the `test/` scaffold, the review targets exactly **63 in-scope files**:

| Section | Count |
|---|---|
| Shared modules (Section 2.1) | 17 |
| Sales | 5 |
| Contracts | 7 |
| Wizards | 3 |
| Facilities | 9 |
| Onboarding | 2 |
| Administration | 3 |
| Programs & Projects | 7 |
| Templates subsystem | 9 |
| Internal tool (FlowMonitor) | 1 |
| **Total in scope** | **63** |

This number is the denominator for Phase 3 progress tracking. If the file list drifts during the review (new files added, files deleted in Phase 2), the reconciliation table gets updated in `README.md`.

---

## 3. Review Categories

12 categories, each tagged with a fix tier: **Auto-fix** (pre-approved, single-step batch preview), **Batch** (line-item approval), or **Catalog-only** (no fix scheduled).

| # | Category | Looking for | Tier |
|---|---|---|---|
| 1 | Dead code & duplicates | `_archive/` folder, duplicate files, unused imports/state/vars, orphaned functions, commented-out blocks | Auto-fix |
| 2 | Console pollution | Non-gated `console.log/warn/error`, leftover `debugger` | Auto-fix |
| 3 | Error handling | Missing try/catch on `portalApi` calls, no user-facing toast on error, unhandled promise rejections, `.catch(() => {})` that silently swallow errors | Batch |
| 4 | Accessibility (a11y) | Missing `alt`, `aria-label`, `aria-describedby`, keyboard focus traps, missing `:focus-visible`, color contrast, label association | Batch |
| 5 | Loading / empty states | Missing spinners during in-flight ops, no empty-state messaging on lists, buttons not disabled during submit, double-submit vulnerabilities | Batch |
| 6 | Performance | Re-render storms, missing `useMemo`/`useCallback`, large list rendering without virtualization, N+1 `apiGet` calls, inline-literal `searchFields` arrays breaking `useMemo` cache | Batch |
| 7 | Visual consistency | Badge class usage, spacing, typography, button styles, form field patterns vs. `C:\DCFG\docs\DCFG_Component_Library.md` | Batch |
| 8 | Data integrity | Correct `dcfg_*` field names, correct `EntitySets.*`, `createDocumentRequest` vs stale `callFlow`, correct enum values, hardcoded URLs that should use `loadConfig()` | Batch |
| **8a** | **Web API `$select` safety** | Every bare `apiGet` / raw fetch on an entity set whose fields list is explicit must have `$select`. Bare GETs against explicit-list tables 403. | Batch |
| **8b** | **`@odata.bind` coverage** | Every POST/PATCH with `field@odata.bind` requires the bind column name in the dmms1 fields list. Builds a `{table → {bindColumn → present?}}` matrix. | Batch |
| 9 | Auth / role checks | `isAdmin/isManager/hasRole` coverage, route guards, admin paths exposed to non-admins, action buttons visible to wrong roles | Batch |
| 10 | Test coverage | Which screens have vitest tests, which don't | Catalog-only |
| 11 | Handoff cleanliness | `data-testid` everywhere per golden rule, `FieldName` visibility, hardcoded URLs/names | testids Auto-fix; rest Batch |
| 12 | Bundle size | Unused deps, large imports, code-split opportunities | Catalog-only |

**Tier definitions:**
- **Auto-fix** — pre-approved fix category; the subagent executes fixes during the sweep. A single batch preview is still presented to the operator before the commit lands.
- **Batch** — findings are cataloged during the sweep; fixes happen in named, operator-approved batches recorded in `approvals/`.
- **Catalog-only** — findings are documented but no fix pass is scheduled in this review.

Categories 8a and 8b are **new**, added in response to the handoff's explicit-list pick-lane rule. They produce concrete cross-referenced evidence rather than just opinions.

---

## 4. Execution Phases

```
Phase 0 — Parity sweep
Phase 1 — Shared modules audit
Phase 2 — Auto-fix pass
Phase 3 — Screen audit pass (9 waves)
Phase 4 — Consolidation
Phase 5 — Fix batches (iterative)
Phase 6 — Final validation
```

### 4.1 Phase 0 — Parity sweep (pre-requisite)

**Goal:** confirm Test and Stage environments match Prod for all state that will be touched during the review, or document and backport drift.

**What is compared:**

1. **Webapi fields lists** for the four explicit-list tables:
   - `Webapi/dcfg_template_field/fields` (handoff Change 1)
   - `Webapi/dcfg_document_template/fields` (handoff Change 2)
   - `Webapi/dcfg_blanket_workorder/fields` (this session Change)
   - `Webapi/dcfg_customer_ap_mapping/fields` (this session Change)
2. **SPA state** of `useTemplateFields.js` + `TemplateDetail.jsx`: does the deployed build in Test/Stage include the `$select` additions from the handoff's Changes 3 + 4?
3. **`dcfg_sp_templates_library` config value** (should be `DCFG_Templates`, not `DMS_Templates`)
4. **Playwright `auth-state.json` existence + validity** for both Test and Prod

**Output:** `parity-report.json` under the review working tree.

**Gates:**
- **Gate 0a** — operator reviews drift report and approves backports per environment. No backport happens without per-env approval.
- **Gate 0b** — operator reviews and approves any Playwright scaffolding work proposed in Phase 0 (see Section 6.2) before `tests/e2e/` is created.

**If backport is rejected for an environment:** that env is recorded as **accepted drift** in `parity-report.json` with the operator's reason. The review continues, but any finding in Phase 3 that relies on that env being in sync is flagged `env-drift-blocked` and deferred to `deferred-future` rather than fixed. The final summary verdict (Section 8.1) calls out any deferred env-drift blockers as yellow flags — reviewer cannot declare green for an env that has known drift affecting in-scope files.

**If backport is approved and fails:** halt, escalate to operator. Do not proceed past Phase 0 until resolved.

### 4.2 Phase 1 — Shared modules audit (sequential, single agent)

**Goal:** find and fix issues in shared modules before they propagate into the ~46 consumer screens.

**Approach:** one agent walks all **17 shared modules** (Section 2.1) serially. Because shared-module issues multiply, parallelizing here is counterproductive. The agent applies categories **3, 6, 8, 8a, 8b, 9, 11** — skipping **4, 5, 7** (no UI surface) and **2** (console pollution is handled in Phase 2b's cross-cutting sweep).

**Output:** `by-screen/_shared.json` plus per-module files (`portalApi.json`, `useTableControls.json`, etc.).

**Gate:** Gate 1a — operator reviews findings. Gate 1b — operator approves a Phase 1 fix batch. Gate 1c — Playwright smoke green after fixes land.

### 4.3 Phase 2 — Auto-fix pass (parallel by category, 3 agents)

**Goal:** clean up mechanical issues across all in-scope files in a single sweep so the screen audit pass starts from a clean baseline.

**Agents (dispatched in parallel):**
- **Agent 2a — Dead code & duplicates** (Category 1): audits all 63 in-scope files (shared modules already had Phase 1 on them, but Category 1 wasn't in Phase 1's set, so 2a is the first dead-code pass); identifies `_archive/` folder and duplicate AppRouter/ContractList/NewContractWizard files; identifies unused imports, unused state, orphaned functions. **File deletions (including `_archive/`) and duplicate file removals are destructive operations** and escalate per Section 7.3 — Agent 2a proposes them in its batch but never executes the deletes itself. In-file cleanups (unused imports/state/functions) are fair game for the auto-fix tier.
- **Agent 2b — Console pollution** (Category 2): strips non-gated `console.*` calls; flags any it's uncertain about as `batch` tier findings for operator decision.
- **Agent 2c — testid golden rule** (Category 11 testid subset): audits every interactive element for `data-testid` presence using `feedback_testid_golden_rule.md` naming convention; auto-adds missing testids.

**Output:** 3 findings files, 3 proposed-fix batches.

**Gates:** 2a/2b/2c — each batch preview approved pre-execution. Gate 2d — Playwright smoke green after all three batches land.

### 4.4 Phase 3 — Screen audit pass (parallel by screen, 9 waves)

**Goal:** deep per-screen audit of the remaining categories (3, 4, 5, 6, 7, 8, 8a, 8b, 9, 10, 11-non-testid, 12). Catalog-only at this phase — fixes happen in Phase 5.

**Wave order (customer-journey ordering from Q12):**

1. **Sales** — `SalesDashboard`, `CustomerList`, `CustomerDetail`, `MsaList`, `MsaDetail`
2. **Contracts** — `ContractList`, `ContractDetail`, `contracts/*`
3. **Wizards** — `NewContractWizard`, `NewProposalWizard`, `NewRfpWizard`
4. **Facilities** — `FacilitiesDashboard`, `Locations`, `LocationDetail`, `Operations`, `CompliancePanel`, `Directory`, `MapView`, `VendorList`, `VendorDetail`
5. **Onboarding** — `Onboarding`, `OnboardingDetail`
6. **Programs/Projects** — `ProgramList`, `ProgramDetail`, `ProjectDashboard`, `ProjectList`, `ProjectDetail`, `RfpList`, `RfpDetail`
7. **Templates** — `TemplateList`, `TemplateDetail`, `CompositeExpander`, `FieldMappingCard`, `FieldMappingPanel`, `DocumentPreview`, `fieldRegistry`, `autoMapper`, `useTemplateFields`
8. **Admin** — `Admin` + sub-tabs, `UserRolesTab`, `SendQueue`
9. **FlowMonitor** — internal, lowest bar, last

**Agent count per wave:** ~6-8 in parallel (token-budget aware).

**Between waves:** one-agent consolidation; operator reviews a wave summary before the next wave launches. Gate 3.N per wave.

**No fixes during Phase 3.** Findings are cataloged in `by-screen/<Screen>.json` only.

### 4.5 Phase 4 — Consolidation

**Goal:** merge all findings into one master list, deduplicate cross-cutting issues, produce readable narrative rollups.

**Outputs:**
- `findings.json` — flat append-only array (master)
- `by-category/*.md` — narrative summaries per category
- `summary.md` — counts, severity breakdown, recommended fix-batch ordering

**Gate:** Gate 4 — operator reviews consolidation before Phase 5 begins.

### 4.6 Phase 5 — Fix batches (iterative, operator-gated)

**Goal:** apply approved fixes in atomic, reviewable batches until all P0 + P1 findings are resolved.

**Per-batch flow:**
1. Propose batch in `approvals/YYYY-MM-DD-batch-NN-<topic>.md` (files, lines, current code, proposed code, rationale)
2. Operator approves / rejects per line item or batch-wide
3. Execute approved edits
4. Playwright smoke: full CRUD on Test + read-only nav on Prod
5. Findings marked `fixed` in `findings.json` with commit SHA
6. Batch approval doc updated with smoke-test results

**Batching heuristics:**
- Group by category first (all error-handling fixes together), then by screen within category
- Never mix auto-fix and batch-tier findings in the same batch
- Never propose a batch larger than ~15 findings — operator cognitive load

**Rollback strategy — immediate (same smoke cycle):** if step 4 fails, revert the commit(s) created in step 3, mark the batch `rolled-back` in its approval doc, file a new finding describing what broke. Do not advance to the next batch until the regression is understood.

**Rollback strategy — post-facto (discovered after subsequent batches have landed):** if a regression is discovered after N additional batches have landed on top of it, the operator chooses one of:
1. **Revert the specific commit** via `git revert <sha>`. If that produces conflicts against newer batches, fall back to option 2.
2. **Fix-forward** — file a new P0 finding, put it at the top of the next fix batch, resolve via explicit edit rather than revert.

The default is **fix-forward** unless the operator explicitly chooses revert; silent reverts are prohibited. Every rollback (immediate or post-facto) appends an entry to `summary.md` under a `Rollbacks` section.

**Gate:** Gate 5.N per batch, plus Gate 5.N-smoke per batch. See Section 7.1 for Gate 5.N-smoke failure-behavior defaults.

### 4.7 Phase 6 — Final validation

**Goal:** prove the reviewed SPA is ready for external user testing.

**Steps:**
1. Full Playwright customer-journey pass on Test environment — green bar required
2. Read-only Playwright navigation smoke on Prod — green bar required
3. Manual operator smoke (operator walks critical customer path)
4. `summary.md` finalized with green/yellow/red verdict + rationale
5. Branch `code-review-2026-04-09` ready to merge to `master`

**Gates:** Gate 6a (Playwright green), Gate 6b (manual smoke passed), Gate 6c (operator merge approval).

---

## 5. Output Structure & Tracking

### 5.1 Working tree

```
C:\dcfg\docs\code-review-2026-04-09\
├── README.md                          plan, categories, tier legend, status, resume instructions, link to this spec
├── parity-report.json                 Phase 0 output: Test/Stage drift
├── findings.json                      master findings (flat append-only array)
├── by-screen\                         per-screen JSON outputs (Phase 1 + Phase 3)
│   ├── _shared.json
│   ├── portalApi.json
│   ├── NewContractWizard.json
│   └── …
├── by-category\                       narrative rollups (Phase 4 output)
│   ├── 01-dead-code.md
│   ├── 02-console-pollution.md
│   └── …
├── approvals\                         batch approval records (Phase 5)
│   ├── 2026-04-09-batch-01-phase1-shared.md
│   ├── 2026-04-09-batch-02-phase2-deadcode.md
│   └── …
├── waves\                             Phase 3 wave summaries
│   ├── wave-01-sales.md
│   └── …
├── smoke-runs\                        Playwright traces per batch
│   └── 2026-04-09-batch-02\
│       ├── playwright-report.html
│       ├── traces\
│       └── screenshots\
└── summary.md                         final report (Phase 6)
```

### 5.2 Finding JSON schema

Every finding, in every file, conforms to this schema:

```json
{
  "id": "CR-2026-04-09-0001",
  "file": "src/NewContractWizard.jsx",
  "line": 942,
  "category": "dead-code",
  "categoryNumber": 1,
  "severity": "P0 | P1 | P2 | P3",
  "tier": "auto-fix | batch | catalog-only",
  "phase": "phase-0 | phase-1 | phase-2 | phase-3 | phase-4 | phase-5 | pre-seed",
  "agent": "code-review-dead-code-sweep",
  "status": "open | approved | rejected | deferred-future | fixed | verified | closed",
  "title": "short human-readable title",
  "detail": "full description of the issue",
  "evidence": "file path + line range or code snippet",
  "recommendedFix": "concrete proposed change",
  "relatedFindings": ["CR-...","CR-..."],
  "foundAt": "ISO-8601 UTC",
  "approvedAt": "ISO-8601 UTC or null",
  "approvedIn": "approvals/...md file or null",
  "fixedAt": "ISO-8601 UTC or null",
  "fixCommit": "git SHA or null",
  "verifiedAt": "ISO-8601 UTC or null"
}
```

**Field notes:**
- `line` is nullable — use `null` when the finding is file-level (e.g., duplicate-file issues, deletion recommendations, test-coverage gaps) rather than a specific line
- `file` should be a path relative to `C:\DCFG\spa\dcfg-shell\` for portability
- `relatedFindings` is an array (possibly empty) of finding IDs that share a root cause

**Severity meanings:**
- **P0** — breaks user testing readiness. Must fix before Phase 6 sign-off.
- **P1** — significant quality or robustness concern; must fix before Phase 6 sign-off unless explicitly deferred.
- **P2** — quality issue, latent risk. Fix if time permits, defer otherwise.
- **P3** — nice-to-have, cosmetic, or future-work signal.

**Status lifecycle:** `open → (approved or rejected or deferred-future) → fixed → verified → closed`.

### 5.2.1 Example filled-out finding

```json
{
  "id": "CR-2026-04-09-0001",
  "file": "src/NewContractWizard.jsx",
  "line": 942,
  "category": "dead-code",
  "categoryNumber": 1,
  "severity": "P2",
  "tier": "batch",
  "phase": "pre-seed",
  "agent": "human-handoff-2026-04-09",
  "status": "open",
  "title": "Stray `)}` JSX closer after vendor-selection comment",
  "detail": "Line 942 contains an orphan `)}` with no matching opening — remnant of a deleted vendor-selection block that was moved to Step 3 of the wizard. esbuild recovers today and the runtime is unaffected, but a tighter esbuild/vite version could fail the build. Build warning has been present since at least 2026-04-07.",
  "evidence": "NewContractWizard.jsx lines 941-942:\n  941:             {/* Vendor is selected on Step 3 (Contractor & Signer) — not on this step */}\n  942:             )}",
  "recommendedFix": "Delete lines 941-942 (both the comment and the orphan closer). Verify via `npm run build` that no new esbuild warnings surface.",
  "relatedFindings": [],
  "foundAt": "2026-04-09T18:00:00Z",
  "approvedAt": null,
  "approvedIn": null,
  "fixedAt": null,
  "fixCommit": null,
  "verifiedAt": null
}
```

### 5.3 Cross-session tracking

Quality-driven timeline means this review will span multiple Claude sessions. Tracking discipline:

- **Single source of truth:** `findings.json`. Agents append with unique, pre-assigned ID ranges to avoid conflict.
- **Session log:** `README.md` gets an appended session log entry per session — date, phase, what was touched, next step.
- **Resume instructions:** top of `README.md` has a "To resume" block that tells the next session exactly what state we are in and what to do first.
- **Task list persistence:** `session-state.md` captures the last known TaskList so TaskCreate/TaskUpdate state survives session boundaries.

**Finding ID ranges (reserved at spec time):**

| Range | Owner | Notes |
|---|---|---|
| CR-2026-04-09-0001 … 0099 | Pre-seeded findings (Section 11) | Reserved; no agent may reuse these IDs |
| 0100 … 0199 | Phase 0 parity sweep | Drift findings |
| 0200 … 0299 | Phase 1 shared-modules audit | |
| 0300 … 0399 | Phase 2a dead-code sweep | |
| 0400 … 0499 | Phase 2b console pollution sweep | |
| 0500 … 0599 | Phase 2c testid sweep | |
| 0600 … 0699 | Phase 3 Wave 1 Sales | |
| 0700 … 0799 | Phase 3 Wave 2 Contracts | |
| 0800 … 0899 | Phase 3 Wave 3 Wizards | |
| 0900 … 0999 | Phase 3 Wave 4 Facilities | |
| 1000 … 1099 | Phase 3 Wave 5 Onboarding | |
| 1100 … 1199 | Phase 3 Wave 6 Programs/Projects | |
| 1200 … 1299 | Phase 3 Wave 7 Templates | |
| 1300 … 1399 | Phase 3 Wave 8 Admin | |
| 1400 … 1499 | Phase 3 Wave 9 FlowMonitor | |
| 1500 … 1599 | Phase 4 consolidation (cross-cutting dedupe, new synthesized findings) | |
| 1600 … 1699 | Phase 5 fix-forward findings filed during rollback | |
| 1700+ | Reserved for future phases / unplanned escalations | |

Agents exceeding their range halt and escalate rather than overflow into another agent's block.

### 5.4 Commit strategy

- Branch: `code-review-2026-04-09` off `master`
- One commit per fix batch (not per finding)
- Message format: `code-review: batch NN — <category or screen> — <count> fixes`
- No merge to `master` without Gate 6c explicit approval
- No force-pushes; no `--no-verify`

### 5.5 What is NEVER written automatically

- No edits to `CLAUDE.md`, `MEMORY.md`, or any file outside the review working tree and approved SPA paths
- No writes to Dataverse from the review itself (smoke-test CRUD on Test is a separate controlled step)
- No SPA deploys (`pac pages upload-code-site`) without explicit per-deploy approval

---

## 6. Regression Protection — Playwright Strategy

### 6.1 Test vs Prod split (E → C from Q11)

| Concern | Target env | Kind | Cadence |
|---|---|---|---|
| Functional regression (real CRUD) | **Test** `dcfg.powerappsportals.com` | Full CRUD — create customer, contract, doc request, onboarding case | After every fix batch |
| Config/deploy drift | **Prod** `dmms1.powerappsportals.com` | Read-only navigation — route loads, data renders, no console errors, no 403/500 on any `_api` GET | After every batch that touches SPA code |
| Shared-module impact | **Test** | Full customer journey happy path | Once, end of Phase 1 |
| Final sign-off | **Test + Prod** | Full journey on Test, then Prod read-only walk | Phase 6 |

### 6.2 Playwright inventory (what exists today)

Per the handoff and session exploration, `C:\DCFG\nora\node_modules\@playwright\test` is present, and `C:\DCFG\nora\auth-state.json` exists as a stored Windows Hello auth state. Phase 0 verifies:
- Does `nora/` contain working specs, or just the framework install?
- Does `C:\DCFG\spa\dcfg-shell\` have its own `playwright.config.ts` or `tests/e2e/` tree?
- Is `auth-state.json` still valid for both Test and Prod? (one file per env expected)

If no specs exist for the SPA, Phase 0 includes scaffolding a minimal spec tree. **This scaffolding is subject to Gate 0b** (see Section 4.1) — operator must approve the proposed scaffolding layout, config, and initial spec set before any `tests/e2e/` files are created under `C:\DCFG\spa\dcfg-shell\`.

### 6.3 Auth pattern

Per `feedback_windows_hello_auth.md` — manual-pause Playwright run. Test pauses for human Windows Hello, operator confirms, `auth-state.json` is saved, subsequent runs reuse the state. Two files expected: `auth-state-test.json` and `auth-state-prod.json`.

### 6.4 Proposed spec tree (scaffolding in Phase 0)

```
C:\dcfg\spa\dcfg-shell\tests\e2e\
├── playwright.config.ts                base config with test + prod projects
├── fixtures\
│   └── authState.ts                    loads nora/auth-state-{env}.json
├── helpers\
│   ├── createTestCustomer.ts           creates "CR-TEST-<timestamp>" customer
│   └── cleanup.ts                      soft-deletes CR-TEST-* rows at test end
└── specs\
    ├── nav-smoke.spec.ts               Prod read-only: every route loads, no errors
    ├── customer-journey.spec.ts        Test: create customer → contract → doc → send
    ├── onboarding-journey.spec.ts      Test: create case → phase steps → close
    ├── templates-journey.spec.ts       Test: list → detail → field mapping → save
    └── admin-journey.spec.ts           Test: blanket WO + AP mapping (validates hotfix)
```

### 6.5 Selector discipline

Per `feedback_testid_golden_rule.md`: every assertion uses `data-testid` only. CSS selectors and text matchers are prohibited. If a target is missing a testid, Phase 2c adds one before the spec lands.

### 6.6 Per-batch smoke protocol

```
1. Fix batch lands (approved code edits committed)
2. npm run build                                 # SPA must build clean
3. npx playwright test --project=test-env        # full CRUD on Test
4. npx playwright test --project=prod-readonly   # nav smoke on Prod
5. If either fails: rollback the batch, investigate, retry
6. If both pass: append result to batch approval doc, advance
```

Deploys to Test happen via `npm run build && pac pages upload-code-site` after switching pac auth to Test. **Prod gets no deploy until Phase 6 final sign-off.**

### 6.7 Failure mode handling

| Failure | Response |
|---|---|
| Playwright auth expires mid-run | Pause, refresh `auth-state.json`, continue |
| Flaky (fails once, passes rerun) | Mark finding `flaky-needs-stabilization`, escalate — do not auto-retry beyond once |
| Regression in a fix batch | Rollback commit, mark batch `rolled-back`, file new finding, re-propose fix-to-the-fix |
| Unrelated Prod issue surfaces during smoke | Catalog as out-of-scope, flag to operator, do not auto-fix |

### 6.8 What smoke tests do NOT cover

- Visual regression (no screenshot diffing)
- Performance benchmarks (Cat 6 is static-analysis only)
- Accessibility automation (Cat 4 is manual review only in this pass; automated tooling such as axe-core is explicitly deferred to a future review — no pilot scheduled here)
- Load / security / fuzz testing — out of scope

---

## 7. Approval Gates

### 7.1 Gate list

```
Gate 0a     Parity report + backport plan reviewed and approved per env
Gate 0b     Playwright scaffolding layout approved (if scaffolding is needed)
Gate 1a     Phase 1 findings reviewed
Gate 1b     Phase 1 fix batch approved
Gate 1c     Phase 1 smoke-test results green
Gate 2a     Phase 2a dead-code batch preview approved
Gate 2b     Phase 2b console-pollution batch preview approved
Gate 2c     Phase 2c testid batch preview approved
Gate 2d     Phase 2 smoke-test results green
Gate 3.1    Wave 1 Sales summary reviewed
Gate 3.2    Wave 2 Contracts summary reviewed
Gate 3.3    Wave 3 Wizards summary reviewed
Gate 3.4    Wave 4 Facilities summary reviewed
Gate 3.5    Wave 5 Onboarding summary reviewed
Gate 3.6    Wave 6 Programs/Projects summary reviewed
Gate 3.7    Wave 7 Templates summary reviewed
Gate 3.8    Wave 8 Admin summary reviewed
Gate 3.9    Wave 9 FlowMonitor summary reviewed
Gate 4      Phase 4 consolidated findings reviewed
Gate 5.N        Each Phase 5 fix batch approved (pre-execution)
Gate 5.N-smoke  Each Phase 5 smoke-test green (post-execution)
Gate 6a         Final Playwright run green on both envs
Gate 6b     Manual operator smoke passed
Gate 6c     Branch merge approved
```

**Minimum explicit approvals:** **21 guaranteed gates** (0a, 0b, 1a, 1b, 1c, 2a, 2b, 2c, 2d, 3.1–3.9 = 9, 4, 6a, 6b, 6c), plus 2 per Phase 5 fix batch (approval + smoke). Expected Phase 5 batch count: 10-20. Practical total: **41-61 approvals over the life of the review**.

### 7.1.1 Gate 5.N-smoke failure behavior

If a Gate 5.N-smoke fails (Test CRUD or Prod nav smoke reports a regression):

1. **Default action — automatic rollback of the batch's commits.** The batch is reverted via `git revert` on the branch. The corresponding findings return to `status: open`. A `rolled-back` entry is added to the batch approval doc with the smoke-test failure evidence.
2. **Operator override — fix-forward.** The operator can reply `fix-forward` to the smoke-failure report, which halts auto-rollback, files a new P0 finding describing the regression, and puts it at the top of the next batch.
3. **Unclear failure cause** (the smoke failed but the cause isn't obviously the batch) — escalate per Section 7.3, do not auto-rollback, wait for operator instruction.

The default is **auto-rollback** to avoid cascading state. The operator is notified of every auto-rollback the moment it happens.

### 7.2 Approval vocabulary

Operator reply options per gate:

| Reply | Meaning |
|---|---|
| `approve batch` / `approve` / `yes` | Execute all findings in the batch |
| `approve 1,3,5` | Execute only listed finding IDs |
| `reject 2,4` / `defer 2,4` | Skip listed IDs, execute the rest |
| `reject batch` | Skip the entire batch |
| `hold` | Stop, do not execute, wait for further instruction |

Rejections are sticky. A rejected finding gets `status: rejected` (+ reason if given) and will not be re-proposed by any later agent.

### 7.3 Escalation rules

These bypass the normal gate flow and come straight to the operator:

- Any finding involving destructive operations (file delete, dependency removal, `package.json` change, config file edit) — regardless of tier
- Any finding that would touch a file outside `C:\DCFG\spa\dcfg-shell\src\`
- Any cross-cutting finding affecting >5 files — escalates before being broken into batches
- Any finding where the recommended fix is "I don't know, need human judgment"
- Any smoke test failure whose cause is not obvious

---

## 8. Definition of Done

The review is **complete** when all of the following are true:

1. Parity sweep clean — Test + Stage either match Prod or have documented accepted drift
2. All in-scope files reviewed — every Section 2 file has a `by-screen/*.json` or is folded into `_shared.json`
3. Auto-fix tiers executed or deferred — categories 1, 2, 11-testid have zero `open` findings
4. All P0 + P1 batch-tier findings resolved — `status: fixed` or `rejected` with operator sign-off
5. Test coverage cataloged — Cat 10 findings documented (catalog-only, not fixed)
6. Final smoke green — Playwright full CRUD on Test + read-only nav on Prod both pass; traces archived
7. Manual operator smoke passed — operator walks critical customer path on Test and declares ready
8. Branch clean — `code-review-2026-04-09` has clean `git log`, no uncommitted changes, no TODOs in fix code
9. `summary.md` written — what was found, what was fixed, what was deferred, green/yellow/red recommendation
10. Operator merge sign-off (Gate 6c)

### 8.1 "Ready for user testing" verdict criteria

Beyond DoD, the summary's **go verdict** for external user testing requires:

- Zero open P0 findings
- All wizards complete happy-path flow end-to-end without crashes (`NewContractWizard`, `NewProposalWizard`, `NewRfpWizard`)
- **Current DocGen V4 path produces at least one document** through the existing Admin → Template → Generate flow using already-mapped templates. This is a smoke test of the existing functionality, **not** a test of SPEC-TPL-001 field-mapping UI (which is explicitly Out of Scope per Section 9). If the current DocGen V4 path is not ready for this kind of smoke test at Phase 6 time, the criterion is marked `unverifiable-in-this-review` and surfaces as a yellow flag in the summary rather than blocking the go verdict.
- No `console.error` spam on any in-scope screen during a full nav pass
- All `data-testid`s present on interactive elements in scope
- `dcfg_error_message` on any stuck `dcfg_document_requests` in Prod is empty or explained
- No `env-drift-blocked` deferred findings on any env the user testing will actually run against (Prod is the primary; Test matters only for the regression-smoke path)

---

## 9. Non-Goals

Explicitly **not** tackled by this review:

- Schema changes to Dataverse tables
- Flow modifications (Power Automate)
- Role / permission changes (the rights review from handoff stays paused)
- New feature work
- The `interview/` wizard migration from `callFlow` to `createDocumentRequest`
- DocGen V4 field-mapping flow wiring (SPEC-TPL-001 remains a separate project)
- CI/CD pipeline changes
- Dependency upgrades (React 17 → 18, router upgrade, etc.)
- Visual redesign (the review enforces the existing `DCFG_Component_Library.md`, it does not redesign it)

---

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Subagent parallelization produces duplicate/conflicting findings | Phase 4 consolidation bloat | Phase 2 parallelizes by *category* to avoid overlap; Phase 3 parallelizes by *screen* with clear file ownership |
| A "fix" introduces a regression not caught by smoke | Silent break in a less-trafficked screen | Conservative batch sizes, per-batch smoke, rollback-ready commits |
| Playwright `auth-state.json` expires unpredictably | Smoke runs fail for "wrong" reason | Re-auth is a manual pause pattern; acceptable friction |
| Operator approval fatigue — 41-61 gates is a lot | Gate-skipping temptation; rushed approvals | Batches are small (≤15 findings); tier system keeps auto-fix work lightweight |
| Review spans multiple sessions; state drift | Loss of context across sessions | Session log + `session-state.md` + append-only `findings.json` |
| Hidden latent bugs that don't surface until Prod cache clears after a real customer tries a flow | False "green" verdict | Phase 6 includes manual operator walk on actual Prod build |
| Cross-file patterns missed because of per-screen parallelization | Duplicate findings or missed systemic issue | Phase 2 is explicitly cross-cutting; Phase 1 audits shared modules serially before Phase 3 begins |
| Section 1.1 env correction is itself stale by the time review runs | Deploy to wrong environment; credentials misrouted | Every deploy/PATCH operation in this review runs `pac auth list` first and verifies against the table in Section 13 — no assumptions, no shortcuts |
| Finding ID collision between agents despite reserved ranges | Overwritten findings in `findings.json` | Append-only discipline; each agent halts and escalates on range overflow; consolidation pass in Phase 4 detects any gaps or duplicates |

---

## 11. Appendix — Already-known findings (pre-seed)

These land in `findings.json` on day one, without waiting for any agent to rediscover them. **IDs 0001-0099 are reserved for pre-seeded findings; no agent may reuse them.** Only 6 IDs are currently assigned — 0007-0099 remain available for additional pre-seeds surfaced during Phase 0.

| ID | File | Line | Category | Severity | Source |
|---|---|---|---|---|---|
| CR-2026-04-09-0001 | `src/NewContractWizard.jsx` | 942 | Dead code | P2 | Handoff + session-confirmed: stray `)}` JSX closer, esbuild tolerates |
| CR-2026-04-09-0002 | `src/AppRouter.jsx` vs `src/screens/AppRouter.jsx` | — | Dead code | P1 | Duplicate router files; resolve before user testing |
| CR-2026-04-09-0003 | `src/ContractsList.jsx` vs `src/screens/ContractList.jsx` | — | Dead code | P1 | Duplicate list component |
| CR-2026-04-09-0004 | `src/_archive/NewContractWizard.jsx` + rest of `_archive/` | — | Dead code | P2 | Recommend folder deletion (escalates per 7.3 — destructive) |
| CR-2026-04-09-0005 | `src/screens/templates/DocumentPreview.jsx` + `CompositeExpander.jsx` | — | Data integrity (8a) | P1 | Handoff: verify column coverage of handoff Changes 3/4 `$select` lists; may reference columns not yet included |
| CR-2026-04-09-0006 | `src/interview/interviewGenerate.js` | — | Data integrity | P2 | Still uses stale `callFlow()` — migration to `createDocumentRequest`. Out of scope for this review per Section 2.2; noted for visibility. |

---

## 12. Appendix — Two inactive flows (external dependency note)

Per the handoff and pre-session Nora cycle, two Power Automate flows on Prod are currently inactive:
- `flow_cert_alert`
- `flow_template_validate` (Template Upload Validation)

Neither is a code-review concern. Both are **noted here as external dependencies** that could cause user-testing false positives: `flow_template_validate` being inactive means a template uploaded directly to SharePoint will not get its metadata set, which will look like "the SPA is broken" when it is not. Operator should decide whether to reactivate these before user testing; the code review will not touch them.

---

## 13. Appendix — Environment quick reference

| Env | pac index | Org URL | Portal host |
|---|---|---|---|
| **Prod** (DCFGSystems-Prod) | `[1]` ← currently active | `org06f5de0b.crm.dynamics.com` | `dmms1.powerappsportals.com` |
| **Test** (DCFGSystems-Test) | `[2]` | `org0c17e98d.crm.dynamics.com` | `dcfg.powerappsportals.com` |
| **Stage** (DCFGSystems-Stage) | `[3]` | `org88778bb0.crm.dynamics.com` | `holding.powerappsportals.com` |
| **Portal** (legacy) | `[4]` | `orgf625b080.crm.dynamics.com` | `decades.powerappsportals.com` |

Always run `pac auth list` before any deploy command. The indices in `CLAUDE.md` are stale as of 2026-04-09.

---

## 14. Open questions (to resolve before Phase 0 starts)

None identified at spec-writing time. Any that surface during Phase 0 will be surfaced to the operator as escalations.

---

*End of spec.*
