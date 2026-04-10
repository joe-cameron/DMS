# DCFG SPA Code Review — 2026-04-09

**Spec:** `C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md` (approved iteration 2)
**Spec Word version:** `C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.docx` (23 pages)
**Plan:** `C:\dcfg\docs\superpowers\plans\2026-04-09-spa-review-cleanup.md` (3,838 lines, 7 chunks, all approved)
**Branch:** `code-review-2026-04-09` — **CREATED 2026-04-09 (Session 2).** Phase 0 Part A in progress.

---

## To Resume

**Current state:** Planning phase complete. Execution has not begun.

**Next session should:**

1. **Read this file** and `session-state.md` in the same directory
2. **Read the spec's §1.1.1** (six changes already landed on Prod) so you understand what the Phase 0 parity sweep is checking against
3. **Read the plan's Chunk 1 header** to see Phase 0 entry conditions
4. **Verify pre-flight** before any code action:
   - `pac auth list` → compare to env table in plan (Prod=[1], Test=[2], Stage=[3], Portal=[4])
   - `Connect-AzAccount` active (Phase 0 parity sweep needs it)
   - `git status` shows clean working tree on `master`
5. **Confirm with operator** whether to start execution. Do NOT auto-start — the operator is the gate-holder for 41-61 operator interactions over the life of this review.
6. **If operator green-lights execution:** start at Plan Chunk 1 Task 0.0 Step 1 (pre-flight + branch creation)

**Do NOT:**
- Re-plan. The spec and plan are approved and committed.
- Skip Task 0.0 Step 1 (the pre-flight check). Environment drift since 2026-04-09 is the first thing to catch.
- Start any Phase 5 fix batch without operator approval per gate. The plan's gates are non-negotiable.
- Re-run the hotfix from 2026-04-09 — it's already landed on Prod (see §1.1.1 of spec for exact scope).
- Assume CLAUDE.md's pac auth indices are correct — they are stale as of 2026-04-09.

---

## Phase Status

- [x] Phase 0 — Parity sweep + Playwright scaffolding decision — **PARTIAL** (Part A complete, Gate 0a resolved per operator pivot, Test/Stage SPA bundle redeploys + cache clears DEFERRED — see Session 2 log)
- [ ] Phase 1 — Shared modules audit — NOT STARTED
- [ ] Phase 2 — Auto-fix pass (dead code / console / testids) — NOT STARTED
- [ ] Phase 3 — Screen audit (9 waves) — NOT STARTED
- [ ] Phase 4 — Consolidation — NOT STARTED
- [ ] Phase 5 — Fix batches — NOT STARTED
- [ ] Phase 6 — Final validation — NOT STARTED

---

## Gate Log

| Gate | Date | Outcome | Notes |
|---|---|---|---|
| 0a | 2026-04-09 | **partially resolved** | Q1=A keep, Q2=B flip Stage, Q3=B insert Stage env-specific, Q4=A source verified, Q5 cache clear DEFERRED. Test SPA + Stage SPA redeploy DEFERRED per operator pivot ("done with stage and test, work later"). |
| 0b | — | pending | Playwright scaffolding approval |
| 1a | 2026-04-09 | **approved** | 43 phase-1 findings reviewed (3 P0, 10 P1, 19 P2, 11 P3); operator approved set, proceeding to Gate 1b fix-batch proposal |
| 1b | 2026-04-09 | **approved batch** | 13 findings (3 P0 + 10 P1) approved for execution; doc: approvals/2026-04-09-batch-01-phase1-shared.md |
| 1c | — | pending | Phase 1 smoke |
| 2a | — | pending | Phase 2a dead-code batch preview |
| 2b | — | pending | Phase 2b console batch preview |
| 2c | — | pending | Phase 2c testid batch preview |
| 2d | — | pending | Phase 2 smoke |
| 3.1–3.9 | — | pending | 9 screen-audit waves |
| 4 | — | pending | Phase 4 consolidation |
| 5.N | — | pending | Phase 5 fix batches (~10-20 expected) |
| 5.N-smoke | — | pending | Phase 5 per-batch smoke |
| 6a | — | pending | Final Playwright |
| 6b | — | pending | Manual operator smoke |
| 6c | — | pending | Merge approval |

---

## Session Log

### 2026-04-09 — Session 1 (planning + hotfix)

Work performed (in order):

1. **Hotfix landed on Prod** (not a Phase 0 backport — this pre-dated plan creation):
   - Appended `dcfg_customer_id` bind form to `Webapi/dcfg_blanket_workorder/fields` on dmms1
   - Appended `dcfg_customer_id,dcfg_cost_code_id` bind forms to `Webapi/dcfg_customer_ap_mapping/fields` on dmms1
   - Operator cleared Prod portal cache manually and smoke-tested both new-record flows green
   - Backup: `C:\dcfg\scripts\_backups\2026-04-09_admin-bind-forms-before.json`
   - Fix script: `C:\dcfg\scripts\fix-admin-bind-forms-2026-04-09.ps1` (not committed — `*.ps1` gitignore rule)
   - Validate script: `C:\dcfg\scripts\validate-admin-bind-forms-2026-04-09.ps1` (not committed)
   - **These scripts exist in the working tree but not in git.** If the next session needs them, they're on disk.

2. **Memory saved:** `feedback_nora_always_monitors.md` — Nora baseline now always monitors audit logs + DocGen V4 document requests, no exceptions. Added to MEMORY.md index.

3. **Spec written + reviewed + approved** via `superpowers:brainstorming` + `spec-document-reviewer` (2 iterations). Committed:
   - `5602bf6` — initial spec
   - `7426f8d` — reviewer iteration 2 revisions

4. **Spec Word version generated:**
   - `d271c7e` — .docx (23 pages, 18 styled tables, DCFG brand palette) + converter script `scripts/md-to-docx-spa-review.py`

5. **Plan written + reviewed + approved** via `superpowers:writing-plans` + `plan-document-reviewer` (7 chunks, all approved after 1-2 iterations each):
   - `bbffae5` — plan header + Chunk 1 (Phase 0 part A)
   - `5ff7347` — Chunks 2-7 (Phase 0B through Phase 6)
   - `cb37ff3` — Chunk 6+7 revisions per reviewer (spec §7.1.1 "unclear cause" branch added, Chunk 7 8 fixes)

6. **Session paused** when operator said "I will be away full auto." I declined to proceed autonomously with anything that modifies shared state. No execution work was started. Operator confirmed pause.

7. **This handoff** saved state to `docs/code-review-2026-04-09/` so the next session can resume cleanly.

**Total commits this session: 6** (all on `master` branch). No `code-review-2026-04-09` branch has been created yet.

### 2026-04-09 — Session 2 (execution — Phase 0 Part A)

Operator approved a constrained "full auto" scope: run all read-only Phase 0 Part A work (scaffold + parity sweep + SPA bundle check + findings validator), commit with scoped `--only` paths, STOP at Gate 0a for backport approvals. `/loop 5m /nora` scheduled as background safety monitor (cron job `670e7fd4`).

Work performed (in order):

1. **Pre-flight verified** — pac auth Prod=[1] active, Test=[2], Stage=[3], Portal=[4] (matches plan env table; CLAUDE.md's stale claim of Test=[1]/Stage=[2]/Prod=[3] confirmed wrong). Working tree has 1,201 intentional pending-mass-commit staged files — ALL scoped commits used `--only <path>` to avoid touching them.

2. **Branch cut** from master HEAD (12b7d52) — `code-review-2026-04-09` created. No remote (origin has no refs for this repo yet).

3. **Task 0.0 scaffold** — created by-screen, by-category, approvals, waves, smoke-runs subdirs + scripts/code-review/ + scripts/_backups/. Seeded findings.json with 6 pre-known findings per spec §11 (CR-2026-04-09-0001…0006). **Skipped Task 0.0 Steps 4-5** (README.md / session-state.md templates) per operator approval — existing handoff files are a superset of the plan's templates.
   - Commit `5e4fb39` — scaffold + seeded findings.json

4. **Task 0.1 parity sweep** — wrote `scripts/code-review/parity-sweep.ps1`, ran against Prod/Test/Stage. **Two small script fixes required during first runs:** (a) Stage site-id heuristic failed — keyword `holding` didn't match the actual site name "DCFG Contracting Suite" — hardcoded site-id `a150bd53-7fbc-423d-a1ad-dd653ab4c435` (all 3 envs share the same GUID); (b) ConvertFrom-Json crashed on Stage when a wildcard `content` field was stored as raw `*` instead of JSON — added try/catch fallback. Final drift count: 7 items.
   - Commit `4fbeffe` — parity-sweep.ps1 (force-added via `-f` — `*.ps1` global gitignore rule deviation noted) + parity-report.json

5. **Task 0.1b SPA bundle check** — wrote `scripts/code-review/spa-deployed-state-check.ps1`, ran against all 3 portals. **Results:** Prod has both handoff Changes 3/4 signatures in deployed JS. Test and Stage have NEITHER — their deployed SPAs are pre-handoff builds. Bundle drift: 4 items (2 per env × Test, Stage).
   - Commit `b5eee25` — spa-deployed-state-check.ps1 (force-added) + spa-deployed-state.json

6. **Task 0.4 findings validator** — wrote `scripts/code-review/validate-findings-json.ps1`, ran clean against the 6 pre-seeded findings. 0 errors.
   - Commit `7df5176` — validate-findings-json.ps1 (force-added)

7. **Gate 0a matrix built and presented** — see Session 2's Gate 0a entry below. **Stopped for operator decision** per agreed scope.

8. **Operator approved non-destructive backports (rows 1, 2, 3, 6) via "approve all"** — wrote `scripts/code-review/backport-field-list.ps1`, executed 4 sequential PATCHes via `Get-AzAccessToken`. Each operation captured beforeFields to per-env backup JSON. Re-ran parity sweep: drift dropped 7 → 2.
   - Commit `b56a481` — backport script + Test/Stage backup files + refreshed parity-report.json

9. **Operator answered remaining questions Q1-Q5** with structured replies. Per decisions:
   - **Q1=A** — Test `dcfg_sp_templates_library = DCFG_Templates_Test` accepted as intentional per-env drift (no PATCH).
   - **Q2=B** — Stage `dcfg_blanket_workorder/fields` and `dcfg_customer_ap_mapping/fields` flipped from wildcard `*` to Prod's exact 8-column explicit lists. Destructive but reversible via backup files. Wrote `-Mode Replace` extension to `backport-field-list.ps1`.
   - **Q3=B** — Stage `dcfg_sp_templates_library` row INSERTED with value `DCFG_Templates_Stage` (env-specific naming pattern matching Test convention). Wrote `scripts/code-review/insert-config-value.ps1` (POST helper, refuses if key already exists).
   - **Q4=A** — Source verified: master SPA contains both Change 3 (`useTemplateFields.js:33`) and Change 4 (`TemplateDetail.jsx:416`) signatures. Safe to deploy when Test/Stage SPA bundle redeploy is later approved.
   - **Q5=A** — Started writing Playwright cache-clear script (`nora/clear-portal-cache.mjs`) but operator stopped it before run. Operator feedback saved to memory: "every object has a siteid for playwrite to find it" (`feedback_playwright_siteid_locators.md`). The UI-clicking approach was wrong — use siteId-based deeplinks/selectors next time.
   - Updated `parity-sweep.ps1` to use per-env expected config values (hashtable). Re-ran sweep: **drift count = 0** across all 3 envs.
   - Commit `7555b22` — Stage destructive flips + insert helper + per-env config sweep

10. **Operator pivoted Test/Stage work to "later"** — "we are done with stage and test. we will work with them later." This closes Gate 0a as partial: rows 1, 2, 3, 6, 7, 8, 9 done; row 4 accepted-drift; rows 5 + 10 (SPA bundle redeploys) + Q5 cache clears DEFERRED. The actual Phase 1+ code review work for Prod readiness has NOT started.

11. **Memory saved (Session 2):**
   - `feedback_playwright_siteid_locators.md` — Power Platform Playwright should use siteId, not UI navigation
   - `project_code_review_prod_focus_2026_04_09.md` — Prod is the user-testing target, Test/Stage deferred

**Total commits this session (on `code-review-2026-04-09` branch): 7** (5 from Phase 0 Part A scaffold/scripts + 2 from Gate 0a backport batches + this README update). Master unchanged at `12b7d52`.

**Working tree note:** `nora/clear-portal-cache.mjs` exists but is uncommitted and the wrong approach (UI navigation instead of siteId deeplinks). Either delete it or leave as a learning artifact — not load-bearing either way.

**Live state for next session to be aware of:**
- **Test + Stage Dataverse changes ARE LIVE** but **portal caches NOT CLEARED**. Dataverse parity is correct; SPA rendering on Test/Stage portals may show stale behavior until admin center cache clear runs.
- All changes have rollback files at `scripts/_backups/2026-04-09_parity-{test,stage}-before.json`.
- Phase 0 Playwright scaffolding (Plan Chunk 2 — Tasks 0.5, 0.6, 0.7) NOT touched. Gate 0b never opened.
- Phase 1 (Shared modules audit) is the next real work toward Prod code review readiness.

### Session 2 Gate 0a matrix

**Summary of drift to address:**

| Env | Target | Kind | Current state | Proposed backport | Destructive? |
|---|---|---|---|---|---|
| Test | Webapi/dcfg_document_template/fields | missing-bind | explicit list, missing `dcfg_customer_id` | append `dcfg_customer_id` | No (append-only) |
| Test | Webapi/dcfg_blanket_workorder/fields | missing-bind | explicit list, missing `dcfg_customer_id` | append `dcfg_customer_id` | No (append-only) |
| Test | Webapi/dcfg_customer_ap_mapping/fields | missing-binds | explicit list, missing `dcfg_customer_id`, `dcfg_cost_code_id` | append both | No (append-only) |
| Test | dcfg_sp_templates_library config | config-drift | `DCFG_Templates_Test` | **QUESTION** — is this intentional env-specific value? | No (but unclear if should be changed) |
| Test | SPA bundle (change-3 `$select`) | spa-bundle-drift | pre-handoff build | full `npm run build` + `pac pages upload-code-site` to Test | **Yes** — replaces deployed SPA |
| Test | SPA bundle (change-4 `$select`) | spa-bundle-drift | pre-handoff build | (same deploy covers both) | **Yes** — replaces deployed SPA |
| Stage | Webapi/dcfg_document_template/fields | missing-bind | explicit list, missing `dcfg_customer_id` | append `dcfg_customer_id` | No (append-only) |
| Stage | Webapi/dcfg_blanket_workorder/fields | pick-lane inconsistency | **wildcard (`*`)** — diverges from Prod explicit | **QUESTION** — flip to explicit to match Prod, or accept as wildcard? | Depends on choice |
| Stage | Webapi/dcfg_customer_ap_mapping/fields | pick-lane inconsistency | **wildcard (`*`)** — diverges from Prod explicit | **QUESTION** — flip to explicit to match Prod, or accept as wildcard? | Depends on choice |
| Stage | dcfg_sp_templates_library config | **missing-key** | row does not exist | insert row with value `DCFG_Templates`? (or env-specific name?) | No (insert) |
| Stage | SPA bundle (change-3 `$select`) | spa-bundle-drift | pre-handoff build | full `npm run build` + `pac pages upload-code-site` to Stage | **Yes** |
| Stage | SPA bundle (change-4 `$select`) | spa-bundle-drift | pre-handoff build | (same deploy covers both) | **Yes** |

**Per `feedback_pick_lane_explicit_or_wildcard.md`:** Stage has "picked wildcard" for two tables while Prod has "picked explicit." Per rule, we should NOT oscillate — either keep Stage on wildcard (accept drift, fix any SPA consumer that relies on explicit behavior) or flip Stage to explicit to match Prod. Flipping a wildcard back to explicit is the destructive-ish direction because any SPA call that ever succeeded because of wildcard coverage will start 403-ing.

**Missing Stage config key is load-bearing:** the SPA's `loadConfig()` reads `dcfg_sp_templates_library`. On Stage today, that call returns no row — the SPA will either fail or fall back to a hardcoded default. This is probably blocking any DocGen work on Stage already.

**Gate 0a awaiting operator decision.** Reply formats (per plan Task 0.2):
  - `approve all` — execute every proposed backport
  - `approve <env>` — execute all backports for one env (e.g., `approve Test`)
  - `approve <env>:<target>` — execute one specific backport (e.g., `approve Test:dcfg_blanket_workorder`)
  - `reject <env>:<target>` — record as accepted drift, do not backport
  - `defer <env>:<target>` — do not backport now; leave as open question
  - `hold` — stop, no Gate 0a decisions yet

---

## Git commits this session

```
cb37ff3 docs(plans): revise Chunks 6-7 per reviewer feedback
5ff7347 docs(plans): add Chunks 2-7 (Phase 0 part B through Phase 6)
d271c7e docs(specs): Word version of SPA code review design + converter
bbffae5 docs(plans): SPA code review cleanup — plan header + Chunk 1
7426f8d docs(specs): revise SPA code review design per reviewer pass
5602bf6 docs(specs): add SPA code review & cleanup design
```

---

## Findings ID Cursor

- Pre-seed: 0001-0099 reserved (0001-0006 occupied per spec §11)
- Phase 0: next = 0100 (no findings filed yet)
- Phase 1: next = 0200 (no findings filed yet)
- Phase 2a: next = 0300
- Phase 2b: next = 0400
- Phase 2c: next = 0500
- Phase 3 Wave 1 Sales: next = 0600
- Phase 3 Wave 2 Contracts: next = 0700
- Phase 3 Wave 3 Wizards: next = 0800
- Phase 3 Wave 4 Facilities: next = 0900
- Phase 3 Wave 5 Onboarding: next = 1000
- Phase 3 Wave 6 Programs/Projects: next = 1100
- Phase 3 Wave 7 Templates: next = 1200
- Phase 3 Wave 8 Admin: next = 1300
- Phase 3 Wave 9 FlowMonitor: next = 1400
- Phase 4 consolidation: next = 1500
- Phase 5 fix-forward: next = 1600

`findings.json` has NOT been created yet. Plan Chunk 1 Task 0.0 Step 6 creates it with the 6 pre-seeded entries from spec §11.

---

## Critical reminders for the next session

### Environment indices (verified 2026-04-09 via `pac auth list`)

| Env | pac index | Org URL | Portal host |
|---|---|---|---|
| **Prod** (DCFGSystems-Prod) | `[1]` ← active | `org06f5de0b.crm.dynamics.com` | `dmms1.powerappsportals.com` |
| **Test** (DCFGSystems-Test) | `[2]` | `org0c17e98d.crm.dynamics.com` | `dcfg.powerappsportals.com` |
| **Stage** (DCFGSystems-Stage) | `[3]` | `org88778bb0.crm.dynamics.com` | `holding.powerappsportals.com` |
| **Portal** (legacy) | `[4]` | `orgf625b080.crm.dynamics.com` | `decades.powerappsportals.com` |

**CLAUDE.md is stale** — it claims Test=[1], Stage=[2], Prod=[3]. Do NOT trust it. Always `pac auth list` before any deploy.

### Standing rules in force — complete quick-reference

This is the full landscape of operating rules as of 2026-04-09. Every rule here is either in `CLAUDE.md` (auto-loaded at session start) or in `~/.claude/projects/C--dcfg/memory/` (referenced via `MEMORY.md`). The next session will have all of these loaded automatically — this table exists so they can be seen at a glance without opening 30+ files.

**CLAUDE.md MANDATES (non-negotiable):**

| # | Rule | Source |
|---|---|---|
| M1 | **Look before you leap.** Read current state before every write. Query before creating a record. Check if a column exists before adding it. Verify which environment you're connected to before running anything. Investigation IS the work. | CLAUDE.md §MANDATES |
| M2 | **Limit token usage for database activity.** Use the fewest tokens possible for Dataverse operations. One targeted query beats a verbose script. Use known record IDs instead of searching. | CLAUDE.md §MANDATES |

**CLAUDE.md STANDING BLOCKS:**

| Rule | Summary |
|---|---|
| SPA READ-ONLY | `C:\DCFG\spa\` is read-only. Do not create, edit, or delete without explicit per-change approval. Read and search allowed. |
| Current architecture | Flows use `dcfg_document_requests` (not HTTP triggers). SPA calls `createDocumentRequest()` (not `callFlow()`). Configs read via `loadConfig()` at boot. |
| Entity set | `dcfg_properties` (NOT `dcfg_propertys`) |
| Solution name | `DCFGSystemTest` on all environments |
| Soft delete | `dcfg_active_flag = false`, never hard delete |
| Deploy order | Test → Stage → Prod, operator specifies envs per deploy. Always restore pac auth to default index after deploy. |
| Flow build (3 steps) | (1) placeholder push, (2) manual action per connector in designer, (3) read back connection format + push full definition. NEVER overwrite triggers. |
| Script vs manual | Evaluate manual path first (script-vs-manual-judgment skill) |
| Audit logging | Close/Delete/Restore all write to `dcfg_audit_logs` |
| Table permissions | Append AND AppendTo on BOTH sides of relationships |
| PowerShell | `Connect()` MUST have trailing slash on URL; use `pwsh` not `powershell` |
| curl.exe BLOCKED | endpoint security — use `Invoke-RestMethod` in pwsh instead |
| Portal cache | Always clear after metadata changes (manual via admin center) |

**MEMORY — Critical (READ BEFORE ANY ACTION):**

| Rule | Summary |
|---|---|
| `feedback_nora_always_monitors` | **NEW this session.** Every Nora cycle MUST check audit logs + DocGen V4 document requests. Never skippable. |
| `feedback_momentum_regulation` | Was this directed or momentum? Parse for meaning, not action. |
| `feedback_mandatory_planning_gate` | Investigate → options → approval → act. Non-negotiable sequence. |
| `feedback_investigate_before_acting` | NEVER modify without investigating current state first. |
| `feedback_sox_principles` | Before-state capture, full audit trail, rollback capability on every change. |
| `feedback_token_efficiency` | Track token use. Justify subagent cost. Prefer inline single-query over 200-line scripts. |
| `feedback_json_over_markdown` | JSON for facts, markdown for instructions. |
| `feedback_upkeep_readonly` | UpKeep system is READ-ONLY. No writes ever. |

**MEMORY — Behavioral Rules:**

| Rule | Summary |
|---|---|
| `feedback_flow_build_process` | 3-step flow build: placeholders → manual connections → full definition |
| `feedback_flow_rebuild_pattern` | Copy Prod clientdata, replace connectionReferences only |
| `feedback_flows_update_only` | Only update existing flows, never create new |
| `feedback_word_online_field_mapping` | dynamicFileSchema/{id}; requires designer for initial setup |
| `feedback_verify_before_claiming` | Read source before claiming not built |
| `feedback_verify_pac_auth_before_deploy` | MUST verify `pac auth list` before ANY deploy command |
| `feedback_soft_delete_only` | Never hard delete. Use `dcfg_active_flag` / `dcfg_active` / `statecode` |
| `feedback_submitted_docs_locked` | Submitted documents locked unless explicitly declined |
| `feedback_handoff_links` | After deploy: clear cache + provide launch URLs |
| `feedback_build_summary_and_audit` | After builds: produce change summary + deployment record |
| `feedback_monitoring_loops_silent` | Cron loops SILENT unless something changed — no noise |
| `feedback_windows_hello_auth` | Windows Hello auth via Playwright manual-pause pattern |
| `feedback_no_crm_online_module` | Never `Connect-CrmOnline`. Use `pac auth` token. |
| `feedback_clipboard_html` | `C:\dcfg\clipboard.html` is live scratchpad |

**MEMORY — Display & Data:**

| Rule | Summary |
|---|---|
| `feedback_pick_lane_explicit_or_wildcard` | **Critical for this review.** Pick explicit OR wildcard per Webapi fields list ONCE. Never oscillate. Fix the consumer, not the config. |
| `feedback_sharepoint_dms_structure` | `DCFG_Templates` (flat) / `DCFG_Outputs` (Customer/Year/DocType) / `DCFG_Attachments` (Customer/Location/Year) |
| `feedback_prod_library_names` | No `_Prod` suffix. Read library names from `dcfg_configs`. |
| `feedback_location_display_order` | Name first, then address |
| `feedback_field_names_invisible` | Dataverse field names rendered on screens, invisible until highlighted |
| `feedback_testid_golden_rule` | Every SPA interactive element gets `data-testid`. Tests use only `data-testid`, never CSS or text. |
| `feedback_properties_not_propertys` | Entity set name is `dcfg_properties` (typo-pluralized correctly) |
| `feedback_solution_name` | `DCFGSystemTest` on all environments |
| `feedback_powerpagecomponent_patch` | Enhanced Data Model — PATCH the `powerpagecomponent` content JSON (type 9 for settings, type 18 for permissions). Do NOT PATCH `mspp_sitesettings` (virtual table rejects PATCH). |
| `feedback_solution_import_orphans` | Delete orphan `powerpagesites` records before SPA deploy |
| `feedback_wildcard_site_settings` | `Webapi fields=*` doesn't pick up NEW columns. Use explicit lists for new-column scenarios. (Interacts with `pick_lane` rule above.) |

**MEMORY — User profile:**

| Rule | Summary |
|---|---|
| `user_joseph.md` | Joseph Cameron — operator of DCFG. Senior, directive, expects terse precise output. Prefers JSON facts + markdown instructions. |

**Primary references (load on demand):**

- `reference_database_bible.json` — COMPLETE Dataverse schema inventory (tables/columns/perms/keys). Refresh via `scripts/build-database-bible.ps1`.
- `reference_database_bible_guide.md` — how to use the bible + post-change validation procedure
- `reference_system_snapshot.json` — system snapshot (2026-03-20, may be partially stale)
- `reference_engineering_journal.md` — engineering lessons (permissions, auth, flows, schema, PowerShell)
- `reference_entra_app_registration.md` — DO NOT break existing redirect URIs
- `C:\DCFG\docs\DCFG_Component_Library.md` — UI component library canonical reference
- `C:\DCFG\calendar.json` — read at session start

**Operator preferences recap (in force from earlier session's handoff):**

- SPA is read-only by default — explicit per-task approval for edits
- Investigate → options → approval → act mandatory planning gate
- SOX principles — before-state, audit trail, rollback on every change
- Token efficiency — bulk queries preferred, justify subagent cost
- JSON for facts, markdown for instructions
- Soft delete only
- `Invoke-RestMethod` not curl
- Enhanced Data Model for site settings/perms (powerpagecomponent content JSON)
- Always `@odata.bind mspp_websiteid` when creating site settings
- Clear portal cache after metadata changes

### Hotfix state (already landed on Prod — do NOT repeat)

Two Webapi site-setting PATCHes on dmms1 for bind-form coverage:
- `Webapi/dcfg_blanket_workorder/fields` → now includes `dcfg_customer_id`
- `Webapi/dcfg_customer_ap_mapping/fields` → now includes `dcfg_customer_id,dcfg_cost_code_id`

If the Phase 0 parity sweep reports Prod as "OK" for these two targets, that confirms the hotfix is still in place. If it reports drift, something has been reverted since 2026-04-09 and that is a separate investigation.

---

## Artifacts created this session

### In git (on `master`)
- `docs/superpowers/specs/2026-04-09-spa-review-cleanup-design.md` (spec, 687 lines)
- `docs/superpowers/specs/2026-04-09-spa-review-cleanup-design.docx` (Word, 23 pages)
- `docs/superpowers/plans/2026-04-09-spa-review-cleanup.md` (plan, 3,838 lines)
- `scripts/md-to-docx-spa-review.py` (converter)
- `docs/code-review-2026-04-09/README.md` (this file, will be committed as part of handoff)
- `docs/code-review-2026-04-09/session-state.md` (sibling file, will be committed as part of handoff)

### On disk but NOT in git (blocked by `*.ps1` gitignore rule)
- `scripts/fix-admin-bind-forms-2026-04-09.ps1` (hotfix script, idempotent, re-runnable)
- `scripts/validate-admin-bind-forms-2026-04-09.ps1` (hotfix validator, read-only)
- `scripts/probe-admin-fields.ps1` (early probe — superseded by validator, can be deleted)
- `scripts/verify-docx.ps1` (one-shot Word COM verifier for the .docx)

### On disk, untracked
- `scripts/_backups/2026-04-09_admin-bind-forms-before.json` (hotfix before-state; should be committed for audit trail but was missed this session)

### Not yet created (Plan Chunk 1 Task 0.0 creates these when execution starts)
- `docs/code-review-2026-04-09/findings.json` (master findings — 6 pre-seeded entries pending)
- `docs/code-review-2026-04-09/parity-report.json`
- `docs/code-review-2026-04-09/spa-deployed-state.json`
- `scripts/code-review/` directory and all its contents (parity-sweep.ps1, backport-field-list.ps1, etc.)

---

## Suggested first actions for the next session

1. Read this file + `session-state.md`
2. `git log --oneline -10` to confirm you're on master with the 6 plan/spec commits present
3. `pac auth list` to confirm env indices are still as documented
4. Ask operator: "Ready to start executing the SPA code review plan from Phase 0 Task 0.0? Or do you want to review the spec/plan first?"
5. If operator says yes: begin Plan Chunk 1 Task 0.0 Step 1
6. If operator wants to review first: point them at the .docx for readability, or the .md for precision

---

## Open side questions (deferred)

These were raised during this session and never answered. The next session may want to close them:

1. **Should `scripts/verify-docx.ps1` and the hotfix scripts be committed?** Currently blocked by `*.ps1` gitignore rule. Either force-add with `-f`, or narrow the gitignore rule to `/*.ps1` (root-only), or rewrite the scripts in Python.
2. **Should the plan be generated as a Word doc too?** Same `md-to-docx-spa-review.py` converter can be pointed at the plan file.
3. **Should `scripts/_backups/2026-04-09_admin-bind-forms-before.json` be committed?** SOX principles say yes (audit trail). It's currently untracked.

---

*End of resume block.*
