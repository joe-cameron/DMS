# DCFG Project — Claude Code Instructions

## BOOT SEQUENCE — Execute Before ANY Response

**This is not optional. Every session, every agent, every skill MUST execute these steps before doing anything else.**

1. **Read `docs/to-be-fixed.md`** — the running SPA issues/todos list. Know what's outstanding.
2. **Read `~/.claude/projects/C--DCFG/memory/reference_accomplishments.md`** — what's already been built. Don't reinvent.
3. **Read the most recent `docs/handoff-*.md`** — context from the last session.
4. **Run `pac auth list`** — verify which environment is active. Indices shift. Never assume.
5. **Report what you found** — "I see N open items in to-be-fixed, last handoff was X, pac auth is pointing at Y." Then proceed.

If a skill (HAL, Nora, or any other) skips this sequence, it is operating blind.

## MANDATES — Non-Negotiable
1. **Trace the full path before deploying.** Walk the complete path: user click → API call → data shape → state update → UI render. Compiling is NOT verification. **Deploy once, correctly — not ten times iteratively.**
2. **Look before you leap.** READ current state before every write. Query before creating. Check before adding. Verify environment before running. The investigation step IS the work.
3. **Limit token usage for database activity.** One targeted query beats a verbose script. Known record IDs over searches. Never 200 lines when 5 will do.
4. **Investigate before asking.** Before asking the user for ANY information, search the repo, memory, CLI output, and existing scripts. "I couldn't find it after checking A, B, C" is valid. Skipping the investigation is not.
5. **Search before creating.** Before proposing any new file, script, tracking list, or mechanism — `Glob` + `Grep` the repo for an existing one. Add to what exists. Don't create duplicates.

## RULES OF THE ROAD — Every Session, Every Agent

### You Are a Guest in Other People's Systems
**This is the highest-priority operational rule. It overrides everything below.**

You are an agent operating inside systems that belong to humans. Data belongs to users. Project plans belong to managers. ClickUp boards, SharePoint sites, Dataverse records, flow definitions — these are the work product of real people. **Changing someone else's work without explicit verified permission is not forgivable.**

- **Capability is not permission.** You can technically reach almost everything. The discipline is knowing what you are allowed to touch.
- **Data is work product.** Changing a record is changing someone's work. Treat every write as modifying another person's output.
- **Shared structure belongs to whoever maintains it.** Project plans, task boards, folder layouts, schemas designed by others — off limits. Even when a change would be objectively better.
- **Read freely. Write carefully. Modify never** — unless the human explicitly authorizes the specific change.
- **"I can" is never justification.** "The operator told me to" is the only justification.
- **Verify permission is real.** A general instruction ("help me with X") is not permission to modify X. Explicit means explicit: "update this record," "change this field," "deploy to this environment."

### What You Never Do
- **Never write to Prod without explicit authorization.** No schema changes, no data writes, no flow edits, no solution imports, no deploys to `DCFGSystems-Prod` without the operator saying "do it." Each action is a separate authorization — fixing code does NOT authorize deploying it.
- **Never hard delete.** `dcfg_active_flag` = soft delete. Always.
- **Never write to UpKeep.** Read-only integration.
- **Never use customer names or people names in production code/UI/schema.** No "Bancroft", "PennReach", "Tyler", "Bill" in code, strings, or column names. Generic/role-based terms only. File and folder names are fine.
- **Never use `curl.exe`.** Blocked by endpoint security. Use `Invoke-RestMethod` in pwsh.
- **Never trust hardcoded pac auth indices.** They shift. Run `pac auth list` every time.
- **Never use `callFlow()`.** Use `createDocumentRequest()` — flows trigger from `dcfg_document_requests` table.
- **Never use `Connect-CrmOnline`.** Use `pac auth` token.
- **Never overwrite flow triggers.** Three-step flow build: placeholders → manual connections → full definition.

### What You Always Do
- **Log every significant action to the session journal.** After completing any bug fix, enhancement, service request, or data operation, run:
  ```
  pwsh -NoProfile -File C:/dcfg/scripts/session-coord/write-journal.ps1 -Cat "Bug" -Item "Fixed vendor dropdown"
  ```
  Categories: `Bug`, `Enhancement`, `Service Request`. Plain-language description, no technical details. The SessionEnd hook automatically syncs journal entries to `dashboard/worklog.json` and the Dataverse brain (`dcfg_knowledge`). This feeds ClickUp and cross-session memory.
- **SharePoint is always the second save** for any document generation path. `DCFG_Outputs/Customer/Year/DocType`.
- **Audit logging:** Close/Delete/Restore operations write to `dcfg_audit_logs`.
- **Table permissions:** Append AND AppendTo on BOTH sides of relationships.
- **PowerShell:** `Connect()` MUST have trailing slash. Use `pwsh` not `powershell`.
- **Clear portal cache** after metadata changes (site settings, table permissions, web roles).
- **Restore pac auth to Test** after any Prod/Stage operation.
- **All SPA elements:** `data-testid` attributes. Tests use only `data-testid`.
- **Verbose logging** on all API failures by default. Debug-blind in Prod is too expensive.
- **Before ANY build:** visual mockup of before/after for impacted screens. Get approval first.
- **Entity set:** `dcfg_properties` (NOT `dcfg_propertys`).

### How You Work
- **Investigate → options → approval → act.** Never skip steps.
- **State assumptions explicitly.** Multiple interpretations? Present them, don't pick silently.
- **Surgical edits.** Touch only what the task requires. Don't improve adjacent code.
- **Simplicity.** No features, abstractions, or config beyond what was asked. 200 lines that could be 50? Rewrite.
- **Script vs Manual:** evaluate manual path first. 5-click manual task doesn't need a 200-line script.
- **Report findings, not questions.** "I found X in file Y" beats "what is your X?"
- **Bulk/repeatable work → haiku sub-agents.** Opus stays on decisions.

## KEY PROJECT RESOURCES — Know Where Things Live

| What | Where | Purpose |
|------|-------|---------|
| **SPA issues / todos** | **`docs/to-be-fixed.md`** | **Running list. Add here, don't create new files.** |
| Bug tracking | `docs/bugs.json` | Structured bug records |
| Design specs | `docs/superpowers/specs/` | Design documents before implementation |
| Implementation plans | `docs/superpowers/plans/` | Step-by-step build plans |
| Session handoffs | `docs/handoff-*.md` | Context transfer between sessions |
| Prod baseline | `docs/baseline-2026-04-16/` | 13 JSON files: tables, columns, picklists, flows, site settings, permissions, scripts |
| Harvest manifest | `brain/harvest-37-manifest.json` | 37 SharePoint project sites with driveIds, folders, documents |
| Dataverse brain | `dcfg_knowledge` table (Prod) | 230+ rows of system memory, lessons, baseline data |
| Brain runtime spec | `brain/decades-brain-runtime-spec.md` | HAL + Compass architecture |
| PowerShell helpers | `PowerApps-Samples/dataverse/webapi/PS/Core.ps1` | `Connect $orgUrl` then use `$baseHeaders` |
| Graph auth | `tools/path-probe/graph_auth.py` | MSAL device-code for SharePoint/Graph API |
| Screen captures | `docs/screen-captures/` | Current SPA screenshots by feature area |
| Contract composer mockups | `scratch/brook-exhibit-b/mockups/` | Approved UX designs |
| Engineering lessons | `~/.claude/projects/C--DCFG/memory/reference_engineering_journal.md` | Durable lessons |
| Accomplishments | `~/.claude/projects/C--DCFG/memory/reference_accomplishments.md` | Proven patterns — read before building |
| **Skills directory** | **`C:\DCFG\skills\`** | **80+ skills. See SKILLS LANDSCAPE section below.** |
| HAL skill | `C:\DCFG\skills\hal\SKILL.md` | Orchestrator — commander + droid army for Power Platform |
| HAL droid roster | `C:\DCFG\skills\hal\references\droid-roster.json` | Specialist droid → skill → tier → model mapping |
| HAL mind maps | `C:\DCFG\skills\hal\mind\{domain}.json` | Self-learning patterns, traps, dead ends |
| HAL resolution map | `C:\DCFG\skills\hal\resolution-map.json` | Symptom → fix with success rates |

## SKILLS LANDSCAPE — `C:\DCFG\skills\`

**HAL is the orchestrator.** For any non-trivial Power Platform task, prefer dispatching through HAL rather than invoking domain skills directly. HAL classifies → consults mind maps → dispatches a specialized droid (subagent) loaded with the right skill → updates mind/resolution maps from outcome. Tier 1 (Opus) for classification/design/novel debugging. Tier 2 (Haiku/Sonnet) for template-fill, lookups, validation.

**Custom DCFG skills** (top-level in `skills/`):
`hal`, `dcfg-project-data`, `dcfg-spa-reference`, `dcfg-work-organizer`, `hybrid-agent-supervisor`, `power-automate-flow-design`, `playwright-syntax-design`, `script-vs-manual-judgment`, `auto-research-testing`, `autoresearch-diagrams`, `huashu-design`, `taste-skill`.

**Bundled collections** (sub-directories under `skills/`):
- `anthropic-skills/skills/` — algorithmic-art, brand-guidelines, canvas-design, claude-api, doc-coauthoring, docx, frontend-design, internal-comms, mcp-builder, pdf, pptx, skill-creator, slack-gif-creator, theme-factory, web-artifacts-builder, webapp-testing, xlsx (17)
- `impeccable-*` (top-level, 18 skills) — design-system suite: shape, adapt, animate, audit, bolder, clarify, colorize, critique, delight, distill, harden, impeccable, layout, optimize, overdrive, polish, quieter, typeset
- `sanjay3290-ai-skills/skills/` — connector skills: atlassian, azure-devops, deep-research, elevenlabs, gmail, google-{calendar,chat,docs,drive,sheets,slides,tts}, imagen, jules, manus, mssql, mysql, notebooklm, outline, postgres
- `trailofbits-security/plugins/*/skills/` — 30+ security skills: address-sanitizer, semgrep, codeql, supply-chain-risk-auditor, fuzz tooling (aflpp, atheris, cargo-fuzz, libafl, libfuzzer, ossfuzz, ruzzy), blockchain auditors (algorand, cairo, substrate, cosmos, token-integration), variant-analysis, yara-rule-authoring, zeroize-audit, agentic-actions-auditor, etc.

**Skill discovery rule:** Before writing any new skill or one-off script for a recurring task — `Glob` `C:\DCFG\skills\**\SKILL.md` and `Grep` for the keyword. Add to what exists. Don't duplicate.

## SPA IS READ-ONLY
**`C:\DCFG\spa\` is READ-ONLY. Do not create, edit, or delete any file under spa/.**
Read and search are allowed. All SPA changes require explicit permission from the operator.

**DEPLOY IS A SEPARATE AUTHORIZATION.** Editing, building, and deploying are THREE separate permissions.
- Finding a bug does NOT authorize fixing it. Report the bug, ask to fix.
- Fixing code does NOT authorize building it. Ask before `npm run build`.
- Building does NOT authorize deploying. Ask before `pac pages upload-code-site`.
- Permission earlier in the session does NOT carry forward. Ask each time.
- NEVER run `pac pages upload-code-site` without explicit "deploy to {env}" approval.

## Current Architecture
- **Flow pattern:** Dataverse transaction table (`dcfg_document_requests`), NOT HTTP triggers
- **SPA function:** `createDocumentRequest()` — never `callFlow()`
- **Config:** `dcfg_configs` table read at boot via `loadConfig()` — no hardcoded URLs
- **Entity set:** `dcfg_properties` (NOT dcfg_propertys)
- **Solution name:** `DCFGSystemTest` (all environments)
- **Soft delete:** `dcfg_active_flag` — never hard delete
- **DocGen:** V4 OOXML injection via jszip (Azure Function). V3 is retired.
- **Document storage:** Templates → SharePoint `DCFG_Templates`. Outputs → `DCFG_Outputs/Customer/Year/DocType`. Attachments → `DCFG_Attachments/Customer/Location/Year`.

## Environments

**WARNING: pac auth indices SHIFT. Always run `pac auth list` before any operation.**

| Env | Org URL | Sites |
|-----|---------|-------|
| **Prod** | org06f5de0b.crm.dynamics.com | dmms1.powerappsportals.com (SPA) |
| **Test** (Sandbox) | org0c17e98d.crm.dynamics.com | dcfg.powerappsportals.com (SPA) |
| **Stage** | org88778bb0.crm.dynamics.com | holding.powerappsportals.com (SPA) |
| **Portal** (READ-ONLY) | orgf625b080.crm.dynamics.com | decades.powerappsportals.com (legacy) |

- **Deploy order:** Test → Stage → Prod (operator specifies which envs per deploy)
- **Always restore pac auth to Test after deploying**
- **Solution name:** `DCFGSystemTest` (all environments)
- **Prod is protected.** Every Prod operation requires explicit authorization.

## Deploy Commands
```bash
cd C:\DCFG\spa\dcfg-shell
npm run build
pac pages upload-code-site --rootPath . --compiledPath dist
```
After deploy: clear cache + provide launch URLs.

## Flow Build Process (Three Steps)
1. Push placeholder definition (Compose actions for connection-dependent actions)
2. User manually adds one action per connector type in designer
3. Read back connection format, push full definition — NEVER overwrite triggers

## Engineering Discipline

### Simplicity
- No features, abstractions, or configuration beyond what was asked.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### Surgical edits
- Touch only what the task requires. Don't "improve" adjacent code.
- Don't refactor things that aren't broken. Match existing style.
- Remove imports/variables/functions that YOUR changes orphaned. Leave pre-existing dead code alone.

### Success criteria before execution
- Transform vague asks into verifiable goals before starting.
- For multi-step tasks, state a brief plan with verification per step.
- **Loop verification locally, not the deploy.** The deploy is never the verification mechanism.
