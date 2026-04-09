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
- **Handoff:** `C:\DCFG\docs\handoff-code-review-2026-04-09.md`
- **Pre-review hotfix landed in this session:** appended missing `@odata.bind` column names to the `Webapi/dcfg_blanket_workorder/fields` and `Webapi/dcfg_customer_ap_mapping/fields` site settings on dmms1 Prod. Backup: `C:\dcfg\scripts\_backups\2026-04-09_admin-bind-forms-before.json`. Fix script: `C:\dcfg\scripts\fix-admin-bind-forms-2026-04-09.ps1`. Validate script: `C:\dcfg\scripts\validate-admin-bind-forms-2026-04-09.ps1`. Portal cache cleared manually by operator + smoke-tested.
- **Environment correction from handoff:** pac auth indices are currently `[1]=Prod, [2]=Test, [3]=Stage, [4]=Portal`. This disagrees with `CLAUDE.md` but has been verified this session via `pac auth list`. Always run `pac auth list` before any deploy command.
- **Critical behavioral rule in force:** `feedback_pick_lane_explicit_or_wildcard.md` — never oscillate `Webapi/{table}/fields` between explicit and wildcard. Fix the consumer, not the config.

---

## 2. Scope

### 2.1 In scope (~68 files)

Customer-facing bar applies to all of these. Shared modules audited first because their issues propagate to consumers.

**Shared modules (audited first, Phase 1):**
`portalApi.js`, `useTableControls.jsx`, `usePortalUser.jsx`, `Toast.jsx`, `NavPanel.jsx`, `RoleGuard.jsx`, `SlideOutPanel.jsx`, `SpeechMic.jsx`, `FieldName.jsx`, `AppRouter.jsx`, `App.jsx`, `ErrorReporter.jsx`, `LocationManager.jsx`, `SensorBanner.jsx`.

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

### 2.4 File-count honesty

`Glob` over `src/**/*.{js,jsx,ts,tsx}` returns roughly 82 files. After excluding `_archive/`, `debug/`, `interview/`, `NoraCopilot`, `AbsorptionDashboard`, `UserManual`, `CapitalPlan`, and the `test/` scaffold, the review targets approximately **68 files**.

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

**Gate:** Gate 0 — operator reviews drift report and approves backports per environment before Phase 1 begins. No backport happens without per-env approval.

### 4.2 Phase 1 — Shared modules audit (sequential, single agent)

**Goal:** find and fix issues in shared modules before they propagate into ~54 consumer screens.

**Approach:** one agent walks the 14 shared modules serially. Because shared-module issues multiply, parallelizing here is counterproductive. The agent applies categories **3, 6, 8, 8a, 8b, 9, 11** — skipping **4, 5, 7** (no UI surface).

**Output:** `by-screen/_shared.json` plus per-module files (`portalApi.json`, `useTableControls.json`, etc.).

**Gate:** Gate 1a — operator reviews findings. Gate 1b — operator approves a Phase 1 fix batch. Gate 1c — Playwright smoke green after fixes land.

### 4.3 Phase 2 — Auto-fix pass (parallel by category, 3 agents)

**Goal:** clean up mechanical issues across all in-scope files in a single sweep so the screen audit pass starts from a clean baseline.

**Agents (dispatched in parallel):**
- **Agent 2a — Dead code & duplicates** (Category 1): audits all ~54 screen files + shared modules not already handled in Phase 1; identifies `_archive/` deletion candidates, duplicate AppRouter/ContractList/NewContractWizard files, unused imports, unused state, orphaned functions; produces a single proposed-fix batch.
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

**Gate:** Gate 5.N per batch, plus Gate 5.N-smoke per batch.

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
├── README.md                          plan, categories, tier legend, status, resume instructions
├── plan.md                            reference to this spec doc
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
  "phase": "phase-1 | phase-2 | phase-3",
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

**Severity meanings:**
- **P0** — breaks user testing readiness. Must fix before Phase 6 sign-off.
- **P1** — significant quality or robustness concern; must fix before Phase 6 sign-off unless explicitly deferred.
- **P2** — quality issue, latent risk. Fix if time permits, defer otherwise.
- **P3** — nice-to-have, cosmetic, or future-work signal.

**Status lifecycle:** `open → (approved or rejected or deferred-future) → fixed → verified → closed`.

### 5.3 Cross-session tracking

Quality-driven timeline means this review will span multiple Claude sessions. Tracking discipline:

- **Single source of truth:** `findings.json`. Agents append with unique ID ranges to avoid conflict.
- **Session log:** `README.md` gets an appended session log entry per session — date, phase, what was touched, next step.
- **Resume instructions:** top of `README.md` has a "To resume" block that tells the next session exactly what state we are in and what to do first.
- **Task list persistence:** `session-state.md` captures the last known TaskList so TaskCreate/TaskUpdate state survives session boundaries.

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

If no specs exist for the SPA, Phase 0 includes scaffolding a minimal spec tree. This scaffolding is itself subject to operator approval.

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
- Accessibility automation (Cat 4 is manual; axe-core integration TBD in Phase 1 pilot)
- Load / security / fuzz testing — out of scope

---

## 7. Approval Gates

### 7.1 Gate list

```
Gate 0      Parity report + backport plan reviewed and approved per env
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
Gate 5.N    Each Phase 5 fix batch approved
Gate 5.N-s  Each Phase 5 smoke-test green
Gate 6a     Final Playwright run green on both envs
Gate 6b     Manual operator smoke passed
Gate 6c     Branch merge approved
```

**Minimum explicit approvals:** 15 guaranteed gates, plus 1 per Phase 5 fix batch (expected 10-20) plus 1 smoke gate per fix batch. Practical total: **35-55 approvals over the life of the review**.

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
- DocGen V4 produces at least one document per template type successfully
- No `console.error` spam on any in-scope screen during a full nav pass
- All `data-testid`s present on interactive elements in scope
- `dcfg_error_message` on any stuck `dcfg_document_requests` in Prod is empty or explained

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
| Operator approval fatigue — 35-55 gates is a lot | Gate-skipping temptation; rushed approvals | Batches are small (≤15 findings); tier system keeps auto-fix work lightweight |
| Review spans multiple sessions; state drift | Loss of context across sessions | Session log + `session-state.md` + append-only `findings.json` |
| Hidden latent bugs that don't surface until Prod cache clears after a real customer tries a flow | False "green" verdict | Phase 6 includes manual operator walk on actual Prod build |
| Cross-file patterns missed because of per-screen parallelization | Duplicate findings or missed systemic issue | Phase 2 is explicitly cross-cutting; Phase 1 audits shared modules serially before Phase 3 begins |

---

## 11. Appendix — Already-known findings (pre-seed)

These land in `findings.json` on day one, without waiting for any agent to rediscover them:

| ID | File | Line | Category | Severity | Source |
|---|---|---|---|---|---|
| CR-2026-04-09-0001 | `src/NewContractWizard.jsx` | 942 | Dead code | P2 | Handoff + session-confirmed: stray `)}` JSX closer, esbuild tolerates |
| CR-2026-04-09-0002 | `src/AppRouter.jsx` vs `src/screens/AppRouter.jsx` | — | Dead code | P1 | Duplicate router files; resolve before user testing |
| CR-2026-04-09-0003 | `src/ContractsList.jsx` vs `src/screens/ContractList.jsx` | — | Dead code | P1 | Duplicate list component |
| CR-2026-04-09-0004 | `src/_archive/NewContractWizard.jsx` + rest of `_archive/` | — | Dead code | P2 | Recommend folder deletion |
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
