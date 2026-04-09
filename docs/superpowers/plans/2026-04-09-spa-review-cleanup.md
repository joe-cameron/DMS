# SPA Code Review & Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute a full-SPA code review and gated cleanup of `C:\DCFG\spa\dcfg-shell\src\` so the DCFG Contracting Suite is ready for external customer-facing user testing on `dmms1.powerappsportals.com`.

**Architecture:** Six-phase, operator-gated review. Phase 0 establishes environment parity and Playwright scaffolding. Phase 1 audits and fixes shared modules serially. Phase 2 runs three parallel auto-fix sweeps across all in-scope files. Phase 3 runs nine waves of parallel per-screen audits in customer-journey order. Phase 4 consolidates findings. Phase 5 applies approved fixes in small operator-gated batches with per-batch Playwright smoke. Phase 6 does final validation and merge.

**Tech Stack:** React 17, Vite, HashRouter, vitest, Playwright, PowerShell 7 + Dataverse Web API, python-docx (for reports), git on branch `code-review-2026-04-09`, 63 in-scope SPA files across shared modules + 10 sections.

**Spec reference:** `C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md` (approved 2026-04-09).

**Operator rules in force** (non-negotiable — see CLAUDE.md + memory):
- SPA at `C:\DCFG\spa\` is READ-ONLY by default. Every edit needs explicit per-change approval.
- `feedback_pick_lane_explicit_or_wildcard.md` — never oscillate Webapi fields between explicit and wildcard. Fix the consumer.
- `feedback_mandatory_planning_gate.md` — investigate → options → approval → act.
- `feedback_sox_principles.md` — before-state capture, full audit trail, rollback capability.
- `feedback_soft_delete_only.md` — never hard delete Dataverse records.
- `feedback_verify_pac_auth_before_deploy.md` — always `pac auth list` before deploy.
- `feedback_json_over_markdown.md` — JSON for facts, markdown for instructions.
- `feedback_testid_golden_rule.md` — every interactive element gets `data-testid`; tests use only `data-testid`.
- curl.exe BLOCKED by endpoint security — use `Invoke-RestMethod` in pwsh.

**Environment table (verified 2026-04-09 — re-verify before each deploy):**

| Env | pac index | Org URL | Portal host |
|---|---|---|---|
| **Prod** | `[1]` | `org06f5de0b.crm.dynamics.com` | `dmms1.powerappsportals.com` |
| **Test** | `[2]` | `org0c17e98d.crm.dynamics.com` | `dcfg.powerappsportals.com` |
| **Stage** | `[3]` | `org88778bb0.crm.dynamics.com` | `holding.powerappsportals.com` |
| **Portal (legacy)** | `[4]` | `orgf625b080.crm.dynamics.com` | `decades.powerappsportals.com` |

---

## File Structure (across all phases)

### Created — review working tree
- `C:\dcfg\docs\code-review-2026-04-09\README.md` — status/index/resume
- `C:\dcfg\docs\code-review-2026-04-09\session-state.md` — cross-session persistence
- `C:\dcfg\docs\code-review-2026-04-09\parity-report.json` — Phase 0 output
- `C:\dcfg\docs\code-review-2026-04-09\findings.json` — master findings
- `C:\dcfg\docs\code-review-2026-04-09\by-screen\*.json` — per-screen findings
- `C:\dcfg\docs\code-review-2026-04-09\by-category\*.md` — category rollups
- `C:\dcfg\docs\code-review-2026-04-09\approvals\*.md` — batch approvals
- `C:\dcfg\docs\code-review-2026-04-09\waves\wave-01..09.md` — wave summaries
- `C:\dcfg\docs\code-review-2026-04-09\smoke-runs\<batch-id>\` — Playwright traces
- `C:\dcfg\docs\code-review-2026-04-09\summary.md` — Phase 6 final report

### Created — scripts
- `C:\dcfg\scripts\code-review\parity-sweep.ps1` — Phase 0 env diff
- `C:\dcfg\scripts\code-review\spa-deployed-state-check.ps1` — Phase 0 deployed-bundle diff
- `C:\dcfg\scripts\code-review\backport-field-list.ps1` — Phase 0 fields-list backport
- `C:\dcfg\scripts\code-review\backport-config-value.ps1` — Phase 0 config backport
- `C:\dcfg\scripts\code-review\validate-findings-json.ps1` — schema lint
- `C:\dcfg\scripts\code-review\append-finding.ps1` — thin wrapper to append a finding
- `C:\dcfg\scripts\code-review\consolidate-wave.ps1` — Phase 3 wave merger
- `C:\dcfg\scripts\code-review\per-batch-smoke.ps1` — Phase 5 build + smoke wrapper
- `C:\dcfg\scripts\_backups\2026-04-09_parity-*.json` — per-env before-state

### Created — Playwright scaffolding (only if Gate 0b approves)
- `C:\DCFG\spa\dcfg-shell\playwright.config.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\fixtures\authState.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\helpers\createTestCustomer.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\helpers\cleanup.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\nav-smoke.spec.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\customer-journey.spec.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\onboarding-journey.spec.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\templates-journey.spec.ts`
- `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\admin-journey.spec.ts`

### Modified — SPA (only via approved Phase 5 fix batches)
Tracked in `findings.json → fixCommit`.

### Branch
`code-review-2026-04-09` off `master`.

---

## Chunk 1 — Phase 0 part A: parity sweep + backports + findings validator

**Chunk goal:** Establish environment parity baseline (Test/Stage vs Prod) for all 6 handoff changes, apply approved backports, check deployed SPA bundle state, set up the findings.json schema validator. Does not create Playwright scaffolding — that's Chunk 2. Everything in this chunk is either new files in `docs/` + `scripts/`, or gated Dataverse PATCHes, or gated SPA deploys to Test/Stage.

### Task 0.0: Branch + working tree scaffold + pre-flight checks

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\README.md`
- Create: `C:\dcfg\docs\code-review-2026-04-09\session-state.md`
- Create: `C:\dcfg\docs\code-review-2026-04-09\findings.json`
- Create: `C:\dcfg\scripts\code-review\` directory
- Read-only: `pac auth list`, `git status`

- [ ] **Step 1: Pre-flight — verify environment state before any branch work**

Run:
```bash
cd C:/dcfg
git status
pac auth list
```

Expected:
- `git status` shows current branch is `master` or `main` with a clean or known working tree
- `pac auth list` shows 4 auths with Prod marked active as index `[1]`; if the indices differ from the environment table above, STOP and update the environment table before proceeding

If pac auth indices disagree with the table, the operator must be notified and the table updated before continuing.

- [ ] **Step 2: Create branch from master**

Run:
```bash
cd C:/dcfg
git fetch origin
git checkout master
git pull origin master
git checkout -b code-review-2026-04-09
git branch --show-current
```
Expected: output prints `code-review-2026-04-09`.

- [ ] **Step 3: Create working-tree directories**

Note: `scripts/` already exists at the repo root; only the subfolders are new.

Run:
```bash
cd C:/dcfg
mkdir -p docs/code-review-2026-04-09/by-screen docs/code-review-2026-04-09/by-category docs/code-review-2026-04-09/approvals docs/code-review-2026-04-09/waves docs/code-review-2026-04-09/smoke-runs
mkdir -p scripts/code-review scripts/_backups
ls docs/code-review-2026-04-09/
```
Expected: all 5 subdirs present under `docs/code-review-2026-04-09/`; `scripts/code-review/` and `scripts/_backups/` exist.

- [ ] **Step 4: Write `README.md` with status and resume block**

Create `C:\dcfg\docs\code-review-2026-04-09\README.md`:

```markdown
# DCFG SPA Code Review — 2026-04-09

**Spec:** `C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md`
**Plan:** `C:\dcfg\docs\superpowers\plans\2026-04-09-spa-review-cleanup.md`
**Branch:** `code-review-2026-04-09`

## To Resume
Current phase: **Phase 0 — parity sweep**
Last completed task: _(update per session)_
Next task: _(update per session)_

## Phase Status
- [ ] Phase 0 — Parity sweep + Playwright scaffolding decision
- [ ] Phase 1 — Shared modules audit
- [ ] Phase 2 — Auto-fix pass (dead code / console / testids)
- [ ] Phase 3 — Screen audit (9 waves)
- [ ] Phase 4 — Consolidation
- [ ] Phase 5 — Fix batches
- [ ] Phase 6 — Final validation

## Gate Log
| Gate | Date | Outcome | Notes |
|---|---|---|---|
| 0a | — | — | Parity backport approvals (per env × target) |
| 0b | — | — | Playwright scaffolding approval |
| 1a | — | — | Phase 1 findings review |
| 1b | — | — | Phase 1 fix batch |
| 1c | — | — | Phase 1 smoke |
| 2a | — | — | Phase 2a dead-code batch preview |
| 2b | — | — | Phase 2b console batch preview |
| 2c | — | — | Phase 2c testid batch preview |
| 2d | — | — | Phase 2 smoke |
| 3.1–3.9 | — | — | Phase 3 wave summaries |
| 4 | — | — | Phase 4 consolidation |
| 5.N | — | — | Phase 5 fix batches |
| 5.N-smoke | — | — | Phase 5 smoke per batch |
| 6a | — | — | Final Playwright |
| 6b | — | — | Manual operator smoke |
| 6c | — | — | Merge approval |

## Session Log
_(append one entry per session)_

### 2026-04-09 — Session 1
- Created branch `code-review-2026-04-09`, working tree, seeded `findings.json`
- Next: Task 0.1 (parity sweep script)
```

- [ ] **Step 5: Write `session-state.md`**

Create `C:\dcfg\docs\code-review-2026-04-09\session-state.md`:

```markdown
# Session State — 2026-04-09

## Task List (last known)
_(filled in at end of each session)_

## Current Agent Dispatches
_(none active)_

## Open Gates
_(none yet)_

## Findings ID Cursor
- Pre-seed: 0001-0006 occupied, 0007-0099 reserved
- Phase 0: next = 0100
- Phase 1: next = 0200
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
```

- [ ] **Step 6: Seed `findings.json` with the 6 pre-known findings from spec §11**

Create `C:\dcfg\docs\code-review-2026-04-09\findings.json` with a JSON array of 6 finding objects matching spec §11. Each object conforms to the schema in spec §5.2. Required: IDs CR-2026-04-09-0001 through 0006 in order. Files, categories, severities, tiers, and titles per spec §11 table. Set `phase: "pre-seed"`, `agent: "human-handoff-2026-04-09"`, `status: "open"`, `foundAt: "2026-04-09T18:00:00Z"`, `relatedFindings: []`, and all lifecycle fields (`approvedAt`, `approvedIn`, `fixedAt`, `fixCommit`, `verifiedAt`) as `null`.

For finding 0005 specifically: `category: "data-integrity-select-safety"`, `categoryNumber: 8`, with `detail` explicitly noting this is spec category **8a** (Web API `$select` safety). This keeps the flat `categoryNumber` consistent with the schema while preserving the 8a signal.

**Example structure for finding 0001:**
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
  "detail": "Line 942 contains an orphan `)}` with no matching opening — remnant of a deleted vendor-selection block that was moved to Step 3 of the wizard. esbuild recovers today and runtime is unaffected, but a tighter esbuild/vite version could fail the build.",
  "evidence": "NewContractWizard.jsx lines 941-942: comment + orphan closer",
  "recommendedFix": "Delete lines 941-942. Verify via `npm run build` that no new esbuild warnings surface.",
  "relatedFindings": [],
  "foundAt": "2026-04-09T18:00:00Z",
  "approvedAt": null,
  "approvedIn": null,
  "fixedAt": null,
  "fixCommit": null,
  "verifiedAt": null
}
```

Generate the remaining 5 findings (0002-0006) following the same structure, with data from spec §11. Finding 0002 covers `src/AppRouter.jsx` duplicate; 0003 covers `src/ContractsList.jsx` duplicate; 0004 covers `src/_archive/`; 0005 covers templates `DocumentPreview.jsx + CompositeExpander.jsx` column coverage (category `data-integrity-select-safety`, detail notes "Category 8a"); 0006 covers `src/interview/interviewGenerate.js` stale `callFlow` (tier `catalog-only`).

- [ ] **Step 7: Verify findings.json parses and has 6 entries**

Run:
```bash
pwsh -Command "(Get-Content 'C:\dcfg\docs\code-review-2026-04-09\findings.json' -Raw | ConvertFrom-Json).Count"
```
Expected: `6`. Any parse error means fix the JSON before committing.

- [ ] **Step 8: Commit working tree scaffold**

Run:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/
git commit --only docs/code-review-2026-04-09/ -m "$(cat <<'EOF'
code-review: scaffold review working tree + seed findings

Creates docs/code-review-2026-04-09/ with README, session-state,
findings.json (6 pre-seeded from spec section 11), and empty
directories for by-screen, by-category, approvals, waves, smoke-runs.

Branch: code-review-2026-04-09

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -1
```
Expected: commit succeeds; log shows the new commit.

---

### Task 0.1: Write the parity sweep script

**Files:**
- Create: `C:\dcfg\scripts\code-review\parity-sweep.ps1`

**Goal:** one read-only pwsh script that reports the state of all 4 Webapi fields lists + 1 config key across Test, Stage, and Prod. Writes `parity-report.json` to the review working tree. Requires PowerShell 7+ (uses `ConvertFrom-Json -AsHashtable` downstream; `Get-AzAccessToken -AsSecureString` requires recent Az.Accounts module; `Connect-AzAccount` must have been run in the session at least once).

- [ ] **Step 1: Write the script skeleton with env + target definitions**

Create `C:\dcfg\scripts\code-review\parity-sweep.ps1`:

```powershell
<#
.SYNOPSIS
  Phase 0 parity sweep — compares Test, Stage, Prod for all handoff changes.
.DESCRIPTION
  Read-only. Produces C:\dcfg\docs\code-review-2026-04-09\parity-report.json.
  Requires PowerShell 7+ and a signed-in Az.Accounts session.
  Per feedback_pick_lane_explicit_or_wildcard.md — reports only, no writes.
#>

$ErrorActionPreference = 'Stop'

$outPath = 'C:\dcfg\docs\code-review-2026-04-09\parity-report.json'

# Env table (verified 2026-04-09; Prod SiteId hardcoded from previous audits)
$envs = @(
    @{ Name = 'Prod';  OrgUrl = 'https://org06f5de0b.crm.dynamics.com'; PortalHost = 'dmms1.powerappsportals.com';   SiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435' },
    @{ Name = 'Test';  OrgUrl = 'https://org0c17e98d.crm.dynamics.com'; PortalHost = 'dcfg.powerappsportals.com';    SiteId = $null },
    @{ Name = 'Stage'; OrgUrl = 'https://org88778bb0.crm.dynamics.com'; PortalHost = 'holding.powerappsportals.com'; SiteId = $null }
)

$webapiTargets = @(
    @{ ComponentName = 'Webapi/dcfg_template_field/fields';       RequiredBinds = @('dcfg_template_id') },
    @{ ComponentName = 'Webapi/dcfg_document_template/fields';    RequiredBinds = @('dcfg_customer_id') },
    @{ ComponentName = 'Webapi/dcfg_blanket_workorder/fields';    RequiredBinds = @('dcfg_customer_id') },
    @{ ComponentName = 'Webapi/dcfg_customer_ap_mapping/fields';  RequiredBinds = @('dcfg_customer_id', 'dcfg_cost_code_id') }
)
$configKey = 'dcfg_sp_templates_library'
$expectedConfigValue = 'DCFG_Templates'
```

- [ ] **Step 2: Add helper functions (auth, site-id resolution)**

Append to `parity-sweep.ps1`:

```powershell
function Get-OrgToken { param($OrgUrl)
    [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$OrgUrl/" -AsSecureString).Token).Password
}

function Get-Headers { param($Token)
    @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
}

# Note: parameter is $HostName — $Host is a PowerShell automatic variable and cannot be a parameter name.
function Resolve-SiteId { param($OrgUrl, $Headers, $HostName)
    $uri = "$OrgUrl/api/data/v9.2/powerpagesites?`$select=powerpagesiteid,name"
    $r = (Invoke-RestMethod -Uri $uri -Headers $Headers).value
    # Heuristic match: hostname prefix in the site name
    $keyword = ($HostName -split '\.')[0]
    $match = $r | Where-Object { $_.name -match $keyword } | Select-Object -First 1
    if (-not $match) { throw "Could not resolve powerpagesite for host '$HostName' — found $($r.Count) sites, none match keyword '$keyword'. Sites: $($r.name -join ', ')" }
    return $match.powerpagesiteid
}
```

- [ ] **Step 3: Add the fields-list probe function**

Append to `parity-sweep.ps1`:

```powershell
function Get-FieldsListState { param($OrgUrl, $Headers, $SiteId, $ComponentName)
    if (-not $SiteId) { return @{ present = $false; reason = 'site-id-not-resolved' } }
    $filter = "powerpagecomponenttype eq 9 and _powerpagesiteid_value eq $SiteId and name eq '$ComponentName'"
    $uri = "$OrgUrl/api/data/v9.2/powerpagecomponents?`$filter=$filter&`$select=powerpagecomponentid,content"
    try {
        $r = (Invoke-RestMethod -Uri $uri -Headers $Headers).value | Select-Object -First 1
    } catch {
        return @{ present = $false; reason = "query-failed: $($_.Exception.Message)" }
    }
    if (-not $r) { return @{ present = $false; reason = 'component-not-found' } }
    $content = $r.content | ConvertFrom-Json
    $value = $content.value
    $mode = if ($value -eq '*') { 'wildcard' } else { 'explicit' }
    return @{
        present = $true
        componentId = $r.powerpagecomponentid
        mode = $mode
        fields = $value
        fieldList = ($value -split ',')
    }
}
```

- [ ] **Step 4: Add the config-key probe function**

Append to `parity-sweep.ps1`:

```powershell
function Get-ConfigValue { param($OrgUrl, $Headers, $Key)
    $uri = "$OrgUrl/api/data/v9.2/dcfg_configs?`$filter=dcfg_key eq '$Key'&`$select=dcfg_configid,dcfg_value,modifiedon"
    try {
        $r = (Invoke-RestMethod -Uri $uri -Headers $Headers).value | Select-Object -First 1
    } catch {
        return @{ present = $false; reason = "query-failed: $($_.Exception.Message)" }
    }
    if (-not $r) { return @{ present = $false; reason = 'key-not-found' } }
    return @{ present = $true; id = $r.dcfg_configid; value = $r.dcfg_value; modifiedon = $r.modifiedon }
}
```

- [ ] **Step 5: Add the main loop that builds and writes the parity report**

Append to `parity-sweep.ps1`:

```powershell
$report = @{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    envs = @{}
    drift = @()
}

foreach ($envDef in $envs) {
    $envName = $envDef.Name
    Write-Host ""
    Write-Host "=== $envName ($($envDef.OrgUrl)) ===" -ForegroundColor Cyan
    $token = Get-OrgToken $envDef.OrgUrl
    $headers = Get-Headers $token
    $siteId = if ($envDef.SiteId) { $envDef.SiteId } else { Resolve-SiteId $envDef.OrgUrl $headers $envDef.PortalHost }
    Write-Host "  SiteId: $siteId"

    $envState = @{ orgUrl = $envDef.OrgUrl; portalHost = $envDef.PortalHost; siteId = $siteId; webapi = @{}; config = $null }

    foreach ($tgt in $webapiTargets) {
        $state = Get-FieldsListState $envDef.OrgUrl $headers $siteId $tgt.ComponentName
        $envState.webapi[$tgt.ComponentName] = $state
        if ($state.present -and $state.mode -eq 'explicit') {
            foreach ($bind in $tgt.RequiredBinds) {
                if ($state.fieldList -notcontains $bind) {
                    Write-Host "  DRIFT: $($tgt.ComponentName) missing '$bind'" -ForegroundColor Yellow
                    $report.drift += @{ env = $envName; target = $tgt.ComponentName; kind = 'missing-bind'; column = $bind; currentFields = $state.fields }
                } else {
                    Write-Host "  OK   : $($tgt.ComponentName) has '$bind'" -ForegroundColor Green
                }
            }
        } elseif ($state.present -and $state.mode -eq 'wildcard') {
            Write-Host "  OK   : $($tgt.ComponentName) is wildcard" -ForegroundColor Green
        } else {
            Write-Host "  MISS : $($tgt.ComponentName) — $($state.reason)" -ForegroundColor Red
            $report.drift += @{ env = $envName; target = $tgt.ComponentName; kind = 'not-found'; reason = $state.reason }
        }
    }

    $cfgState = Get-ConfigValue $envDef.OrgUrl $headers $configKey
    $envState.config = $cfgState
    if ($cfgState.present) {
        if ($cfgState.value -eq $expectedConfigValue) {
            Write-Host "  OK   : $configKey = '$($cfgState.value)'" -ForegroundColor Green
        } else {
            Write-Host "  DRIFT: $configKey = '$($cfgState.value)' (expected '$expectedConfigValue')" -ForegroundColor Yellow
            $report.drift += @{ env = $envName; target = $configKey; kind = 'config-drift'; current = $cfgState.value; expected = $expectedConfigValue }
        }
    } else {
        Write-Host "  MISS : $configKey — $($cfgState.reason)" -ForegroundColor Red
    }

    $report.envs[$envName] = $envState
}

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding UTF8
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Drift count: $($report.drift.Count)"
Write-Host "Report     : $outPath"
```

- [ ] **Step 6: Run the parity sweep**

Run:
```bash
pwsh -File "C:/dcfg/scripts/code-review/parity-sweep.ps1"
```

Expected: per-env console output showing OK/DRIFT/MISS per target; `parity-report.json` written; exit code 0.

Common failures and fixes:
- `Get-AzAccessToken` fails → run `Connect-AzAccount` first
- `Resolve-SiteId` throws "Could not resolve" → multiple or zero sites matched the hostname keyword. Stop and escalate; the site ID must be hardcoded in `$envs` like Prod.
- Token acquisition hangs → Az session may need refresh; re-run `Connect-AzAccount`

- [ ] **Step 7: Commit parity script + initial report**

Run:
```bash
cd C:/dcfg
git add scripts/code-review/parity-sweep.ps1 docs/code-review-2026-04-09/parity-report.json
git commit --only scripts/code-review/parity-sweep.ps1 docs/code-review-2026-04-09/parity-report.json -m "$(cat <<'EOF'
code-review: Phase 0 parity sweep script + initial report

Read-only pwsh script comparing Test/Stage/Prod for all 4 Webapi
fields lists + dcfg_sp_templates_library config key. Produces
parity-report.json.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 0.1b: Check deployed SPA bundle state on Test and Stage

**Why this task exists:** Spec §4.1 item 2 requires Phase 0 to check whether the deployed SPA in Test/Stage includes the `$select` additions from handoff Changes 3 + 4. The parity sweep (Task 0.1) only checks Dataverse metadata — it doesn't look at the deployed JavaScript bundle. This task does that by fetching the portal's main JS asset and string-searching for the handoff-added `$select` clauses.

**Files:**
- Create: `C:\dcfg\scripts\code-review\spa-deployed-state-check.ps1`

- [ ] **Step 1: Write the bundle-check script**

Create `C:\dcfg\scripts\code-review\spa-deployed-state-check.ps1`:

```powershell
<#
.SYNOPSIS
  Fetches each portal's main JS bundle and greps for the handoff Change 3/4
  $select clauses. Reports whether Test/Stage have the current SPA deployed.
.NOTES
  Read-only. No auth required for the bundle fetch (public asset). Uses
  Invoke-WebRequest, not curl (curl.exe is blocked).
#>

$ErrorActionPreference = 'Stop'
$outPath = 'C:\dcfg\docs\code-review-2026-04-09\spa-deployed-state.json'

$portals = @(
    @{ Name = 'Prod';  Base = 'https://dmms1.powerappsportals.com' },
    @{ Name = 'Test';  Base = 'https://dcfg.powerappsportals.com' },
    @{ Name = 'Stage'; Base = 'https://holding.powerappsportals.com' }
)

# Distinct string fragments unique to the handoff Changes 3/4
$signatures = @{
    'change-3-useTemplateFields-select' = '_dcfg_template_id_value,dcfg_field_order,dcfg_source_text'
    'change-4-templateDetail-select'    = 'dcfg_document_templateid,dcfg_name,dcfg_template_type,dcfg_notes,_dcfg_customer_id_value'
}

$result = @{ generatedAt = (Get-Date).ToUniversalTime().ToString('o'); portals = @{}; drift = @() }

foreach ($p in $portals) {
    Write-Host ""
    Write-Host "=== $($p.Name) ($($p.Base)) ===" -ForegroundColor Cyan

    # Fetch the portal index and find the main JS asset URL
    try {
        $html = (Invoke-WebRequest -Uri $p.Base -UseBasicParsing).Content
    } catch {
        Write-Host "  FAIL: index fetch: $($_.Exception.Message)" -ForegroundColor Red
        $result.portals[$p.Name] = @{ status = 'fetch-failed'; error = $_.Exception.Message }
        continue
    }

    # Find all <script src="...assets/....js"> entries — Vite output pattern
    $scriptMatches = [regex]::Matches($html, 'src="([^"]+?\.js)"')
    $jsUrls = @()
    foreach ($m in $scriptMatches) {
        $src = $m.Groups[1].Value
        if ($src -match '^https?://') {
            $jsUrls += $src
        } else {
            $jsUrls += "$($p.Base)$src"
        }
    }
    if ($jsUrls.Count -eq 0) {
        Write-Host "  FAIL: no script tags in index" -ForegroundColor Red
        $result.portals[$p.Name] = @{ status = 'no-scripts'; indexLength = $html.Length }
        continue
    }
    Write-Host "  Found $($jsUrls.Count) script URL(s)"

    # Fetch each and check each signature
    $portalResult = @{ status = 'ok'; scriptUrls = $jsUrls; signatures = @{} }
    foreach ($sigName in $signatures.Keys) {
        $needle = $signatures[$sigName]
        $found = $false
        foreach ($url in $jsUrls) {
            try {
                $body = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
                if ($body -match [regex]::Escape($needle)) { $found = $true; break }
            } catch {
                continue
            }
        }
        $portalResult.signatures[$sigName] = $found
        if ($found) {
            Write-Host "  OK   : $sigName present" -ForegroundColor Green
        } else {
            Write-Host "  DRIFT: $sigName NOT FOUND" -ForegroundColor Yellow
            $result.drift += @{ env = $p.Name; signature = $sigName; kind = 'spa-bundle-drift' }
        }
    }
    $result.portals[$p.Name] = $portalResult
}

$result | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding UTF8
Write-Host ""
Write-Host "SPA bundle drift count: $($result.drift.Count)"
Write-Host "Report: $outPath"
```

- [ ] **Step 2: Run the SPA deployed-state check**

Run:
```bash
pwsh -File "C:/dcfg/scripts/code-review/spa-deployed-state-check.ps1"
```

Expected: for each of Prod/Test/Stage, two signature checks (`change-3-*`, `change-4-*`). Prod should show both `OK`. Test and Stage may show `DRIFT` — that's expected if they haven't been backported yet.

Common failures:
- Portal returns 302 → the portal may require auth even for index; if so, document as `status: auth-required` and defer to an authenticated check in Phase 1.
- Bundle URL pattern doesn't match → Vite output filename has changed; update the regex in Step 1.

- [ ] **Step 3: If Test or Stage shows drift, decide whether to backport the SPA code**

A Test/Stage SPA drift means the deployed build is missing the handoff Changes 3/4 `$select` clauses. The fix is a full SPA build + deploy from `master` to that env. This is a bigger action than a Dataverse PATCH and gets its own Gate 0a line item.

If drift exists, note it in the Gate 0a decision matrix (Task 0.2). If operator approves, the backport action for each drifted env is:

```bash
pac auth select --index <test-or-stage-index>
pac auth who   # VERIFY you're on the right env
cd C:/DCFG/spa/dcfg-shell
npm run build
pac pages upload-code-site --rootPath . --compiledPath dist
```

This is documented here so the operator sees it at Gate 0a time, but execution is deferred to Task 0.3 Step 4 (new step added for SPA backports).

- [ ] **Step 4: Commit the SPA check script + state report**

Run:
```bash
cd C:/dcfg
git add scripts/code-review/spa-deployed-state-check.ps1 docs/code-review-2026-04-09/spa-deployed-state.json
git commit --only scripts/code-review/spa-deployed-state-check.ps1 docs/code-review-2026-04-09/spa-deployed-state.json -m "$(cat <<'EOF'
code-review: Phase 0 deployed SPA bundle-state check

Fetches the main JS bundle from each portal and greps for handoff
Changes 3/4 signature strings. Reports per-env drift. Fulfills spec
section 4.1 item 2.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 0.2: Present Gate 0a decision matrix + record outcome

**Files:**
- Read: `C:\dcfg\docs\code-review-2026-04-09\parity-report.json`
- Read: `C:\dcfg\docs\code-review-2026-04-09\spa-deployed-state.json`
- Update: `C:\dcfg\docs\code-review-2026-04-09\README.md` (Gate Log)

- [ ] **Step 1: Build the Gate 0a decision matrix from both reports**

Read both reports and produce a combined per-env × target table like:

```
Env       Target                                     Current state              Proposed backport                           Decision
--------  -----------------------------------------  -------------------------  ------------------------------------------  --------
Test      Webapi/dcfg_blanket_workorder/fields       explicit, no bind          append dcfg_customer_id                     ?
Test      Webapi/dcfg_customer_ap_mapping/fields     explicit, no binds         append dcfg_customer_id, dcfg_cost_code_id  ?
Test      dcfg_sp_templates_library                  DCFG_Templates (OK)        none                                        N/A
Test      SPA bundle (change-3-select)               present (OK)               none                                        N/A
Test      SPA bundle (change-4-select)               MISSING                    full SPA build + deploy from master         ?
Stage     Webapi/dcfg_template_field/fields          explicit, no bind          append dcfg_template_id                     ?
...
```

Every row with a `?` needs an operator decision.

- [ ] **Step 2: Present the matrix to the operator with explicit instructions**

Present:

```
## Gate 0a — Parity Backport Approvals

Matrix above. For each row with a `?`, reply with one of:
  - `approve all`                — execute every proposed backport
  - `approve <env>`              — execute all backports for one env (e.g., `approve Test`)
  - `approve <env>:<target>`     — execute one specific backport (e.g., `approve Test:dcfg_blanket_workorder`)
  - `reject <env>:<target>`      — record as accepted drift, do not backport
  - `defer <env>:<target>`       — do not backport now; leave as open question
  - `hold`                       — stop, no Gate 0a decisions yet

Note: the SPA-bundle backports require a full `pac pages upload-code-site`
deploy to the target env. This is a heavier action than the Dataverse PATCH
backports. The operator should consider approving SPA backports separately
from fields-list backports.
```

- [ ] **Step 3: Record Gate 0a outcome in README and session-state**

Update `docs/code-review-2026-04-09/README.md` Gate Log row `0a` with the date, outcome, and per-row decisions.
Append a session log entry describing what was approved/rejected.

- [ ] **Step 4: Commit the Gate 0a decision record**

Run:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "$(cat <<'EOF'
code-review: Gate 0a recorded — parity backport decisions

Per-env × target decision matrix recorded in README Gate Log.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

**If no rows were approved → skip Task 0.3; proceed to Task 0.4 (findings validator).**

---

### Task 0.3: Apply approved backports (conditional)

**Runs only if Gate 0a approved at least one backport.**

**Files:**
- Create: `C:\dcfg\scripts\code-review\backport-field-list.ps1` (parameterized, idempotent)
- Create: `C:\dcfg\scripts\code-review\backport-config-value.ps1` (parameterized, idempotent)
- Create: `C:\dcfg\scripts\_backups\2026-04-09_parity-<env>-before.json` per env touched
- Potentially: SPA deploy to Test and/or Stage (no new file creation — uses existing build toolchain)

- [ ] **Step 1: Write `backport-field-list.ps1`**

Create `C:\dcfg\scripts\code-review\backport-field-list.ps1`:

```powershell
<#
.SYNOPSIS
  Append required bind columns to a Webapi/*/fields powerpagecomponent.
  Idempotent: only appends what is missing. Backs up before-state to JSON.
.NOTES
  Requires PowerShell 7+ (uses ConvertFrom-Json -AsHashtable).
#>

param(
    [Parameter(Mandatory=$true)][string]$OrgUrl,
    [Parameter(Mandatory=$true)][string]$SiteId,
    [Parameter(Mandatory=$true)][string]$ComponentName,
    [Parameter(Mandatory=$true)][string[]]$RequiredBinds,
    [Parameter(Mandatory=$true)][string]$BackupPath
)

$ErrorActionPreference = 'Stop'

$t = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$OrgUrl/" -AsSecureString).Token).Password
$hR = @{ Authorization = "Bearer $t"; Accept = 'application/json' }
$hW = @{ Authorization = "Bearer $t"; Accept = 'application/json'; 'Content-Type' = 'application/json; charset=utf-8'; 'If-Match' = '*' }

$filter = "powerpagecomponenttype eq 9 and _powerpagesiteid_value eq $SiteId and name eq '$ComponentName'"
$uri = "$OrgUrl/api/data/v9.2/powerpagecomponents?`$filter=$filter&`$select=powerpagecomponentid,name,content,modifiedon"
$rec = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
if (-not $rec) { throw "Component not found: $ComponentName" }

$componentId = $rec.powerpagecomponentid
$currentFields = ($rec.content | ConvertFrom-Json).value
$currentList = $currentFields -split ','
Write-Host "Current: $currentFields"

# Backup (merge into existing file if present)
$backupDir = Split-Path $BackupPath -Parent
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$existing = @{}
if (Test-Path $BackupPath) { $existing = Get-Content $BackupPath -Raw | ConvertFrom-Json -AsHashtable }
$existing[$ComponentName] = @{ componentId = $componentId; beforeFields = $currentFields; modifiedon = $rec.modifiedon }
$existing | ConvertTo-Json -Depth 10 | Set-Content -Path $BackupPath -Encoding UTF8

$toAdd = @()
foreach ($bind in $RequiredBinds) { if ($currentList -notcontains $bind) { $toAdd += $bind } }
if ($toAdd.Count -eq 0) { Write-Host "NO CHANGE NEEDED" -ForegroundColor Green; return }

$newFields = ($currentList + $toAdd) -join ','
$newContent = @{ value = $newFields } | ConvertTo-Json -Compress
$patchBody = @{ content = $newContent } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/powerpagecomponents($componentId)" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $hW | Out-Null

$verify = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
$verifyFields = ($verify.content | ConvertFrom-Json).value
Write-Host "After:   $verifyFields" -ForegroundColor Green
```

- [ ] **Step 2: Write `backport-config-value.ps1`**

Create `C:\dcfg\scripts\code-review\backport-config-value.ps1`:

```powershell
param(
    [Parameter(Mandatory=$true)][string]$OrgUrl,
    [Parameter(Mandatory=$true)][string]$Key,
    [Parameter(Mandatory=$true)][string]$Value,
    [Parameter(Mandatory=$true)][string]$BackupPath
)

$ErrorActionPreference = 'Stop'
$t = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$OrgUrl/" -AsSecureString).Token).Password
$hR = @{ Authorization = "Bearer $t"; Accept = 'application/json' }
$hW = @{ Authorization = "Bearer $t"; Accept = 'application/json'; 'Content-Type' = 'application/json; charset=utf-8'; 'If-Match' = '*' }

$uri = "$OrgUrl/api/data/v9.2/dcfg_configs?`$filter=dcfg_key eq '$Key'&`$select=dcfg_configid,dcfg_value,modifiedon"
$rec = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
if (-not $rec) { throw "Config key not found: $Key" }
Write-Host "Current: $($rec.dcfg_value) (modifiedon $($rec.modifiedon))"

$backupDir = Split-Path $BackupPath -Parent
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$existing = @{}
if (Test-Path $BackupPath) { $existing = Get-Content $BackupPath -Raw | ConvertFrom-Json -AsHashtable }
$existing["config:$Key"] = @{ id = $rec.dcfg_configid; beforeValue = $rec.dcfg_value; modifiedon = $rec.modifiedon }
$existing | ConvertTo-Json -Depth 10 | Set-Content -Path $BackupPath -Encoding UTF8

if ($rec.dcfg_value -eq $Value) { Write-Host "NO CHANGE NEEDED" -ForegroundColor Green; return }

$patchBody = @{ dcfg_value = $Value } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/dcfg_configs($($rec.dcfg_configid))" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $hW | Out-Null

$verify = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
Write-Host "After:   $($verify.dcfg_value)" -ForegroundColor Green
```

- [ ] **Step 3: Execute approved Dataverse backports**

For each approved `env × target` row from Gate 0a that is a Dataverse change (fields list or config), call the appropriate script with parameters from `parity-report.json`. Example for Test env appending `dcfg_customer_id` to the blanket-WO fields list:

```bash
pwsh -File "C:/dcfg/scripts/code-review/backport-field-list.ps1" `
  -OrgUrl https://org0c17e98d.crm.dynamics.com `
  -SiteId "<test-site-id-from-parity-report.json>" `
  -ComponentName "Webapi/dcfg_blanket_workorder/fields" `
  -RequiredBinds dcfg_customer_id `
  -BackupPath "C:/dcfg/scripts/_backups/2026-04-09_parity-test-before.json"
```

Expected per call: `Current: ...` then `After: ...` in green.

- [ ] **Step 4: Execute approved SPA-bundle backports (full deploy to Test/Stage)**

For each approved SPA-bundle backport from Gate 0a, run the following **with extreme care** — this is a full deploy to a different env.

```bash
# Verify current env first
pac auth list
pac auth select --index <test-or-stage-index>   # 2 for Test, 3 for Stage per env table
pac auth who                                     # MUST confirm before next line

cd C:/DCFG/spa/dcfg-shell
npm run build

# Final sanity: confirm dist/ was produced
ls dist/assets/*.js | head

pac pages upload-code-site --rootPath . --compiledPath dist

# Restore pac auth to Prod (index 1) per CLAUDE.md
pac auth select --index 1
pac auth who
```

Then after deploy, clear the target portal's cache manually (Power Platform admin center → Power Pages → <site> → Site Actions → Clear cache). Operator confirms in chat: `cache cleared for <env>`.

- [ ] **Step 5: Re-run the parity sweep AND the SPA bundle check**

Run:
```bash
pwsh -File "C:/dcfg/scripts/code-review/parity-sweep.ps1"
pwsh -File "C:/dcfg/scripts/code-review/spa-deployed-state-check.ps1"
```

Expected: both reports show zero drift for any env/target that was approved+backported. Rows that were `reject`ed or `defer`red still appear.

- [ ] **Step 6: Commit backport scripts + refreshed reports + backups**

Run:
```bash
cd C:/dcfg
git add scripts/code-review/backport-field-list.ps1 scripts/code-review/backport-config-value.ps1 scripts/_backups/2026-04-09_parity-*.json docs/code-review-2026-04-09/parity-report.json docs/code-review-2026-04-09/spa-deployed-state.json
git commit --only scripts/code-review/backport-field-list.ps1 scripts/code-review/backport-config-value.ps1 scripts/_backups/2026-04-09_parity-*.json docs/code-review-2026-04-09/parity-report.json docs/code-review-2026-04-09/spa-deployed-state.json -m "$(cat <<'EOF'
code-review: Phase 0 backports + refreshed parity reports

Idempotent, parameterized backport scripts (fields list + config
value). Per-env backups under scripts/_backups/. Reports refreshed
after approved backports applied.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 0.4: Write the findings.json validator

**Files:**
- Create: `C:\dcfg\scripts\code-review\validate-findings-json.ps1`

**Note:** placed at end of Chunk 1 because it validates the pre-seeded `findings.json` from Task 0.0. Chunk 2 (Phase 0 part B) covers Playwright and Phase 0 completion.

- [ ] **Step 1: Write the validator script**

Create `C:\dcfg\scripts\code-review\validate-findings-json.ps1`:

```powershell
<#
.SYNOPSIS
  Structural lint for findings.json — schema, ID format, uniqueness, known values.
.NOTES
  Requires PowerShell 7+.
#>

$ErrorActionPreference = 'Stop'
$path = 'C:\dcfg\docs\code-review-2026-04-09\findings.json'

$findings = Get-Content $path -Raw | ConvertFrom-Json
if ($findings -isnot [System.Collections.IEnumerable]) {
    Write-Host "FAIL: findings.json root must be an array" -ForegroundColor Red
    exit 1
}

$required = @('id','file','category','categoryNumber','severity','tier','phase','agent','status','title','detail','recommendedFix','foundAt')
$knownSeverities = @('P0','P1','P2','P3')
$knownTiers = @('auto-fix','batch','catalog-only')
$knownStatuses = @('open','approved','rejected','deferred-future','fixed','verified','closed')
$knownPhases = @('pre-seed','phase-0','phase-1','phase-2','phase-3','phase-4','phase-5')

$seenIds = @{}
$errors = @()

foreach ($f in $findings) {
    # Required keys
    $present = $f.PSObject.Properties.Name
    foreach ($k in $required) {
        if (-not ($present -contains $k)) {
            $errors += "$($f.id): missing required key '$k'"
        }
    }

    # ID format CR-YYYY-MM-DD-NNNN
    if ($f.id -notmatch '^CR-\d{4}-\d{2}-\d{2}-\d{4}$') {
        $errors += "$($f.id): ID format invalid (expected CR-YYYY-MM-DD-NNNN)"
    }

    # Uniqueness
    if ($seenIds.ContainsKey($f.id)) { $errors += "duplicate ID: $($f.id)" }
    $seenIds[$f.id] = $true

    # Enum validation
    if ($f.severity -and ($f.severity -notin $knownSeverities)) { $errors += "$($f.id): unknown severity '$($f.severity)'" }
    if ($f.tier -and ($f.tier -notin $knownTiers))             { $errors += "$($f.id): unknown tier '$($f.tier)'" }
    if ($f.status -and ($f.status -notin $knownStatuses))      { $errors += "$($f.id): unknown status '$($f.status)'" }
    if ($f.phase -and ($f.phase -notin $knownPhases))          { $errors += "$($f.id): unknown phase '$($f.phase)'" }

    # Pre-seed findings should have phase='pre-seed'
    if ($f.agent -match '^human-handoff' -and $f.phase -ne 'pre-seed') {
        $errors += "$($f.id): agent=human-handoff but phase != 'pre-seed'"
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "VALIDATION FAILED — $($errors.Count) error(s)" -ForegroundColor Red
    exit 1
}
Write-Host "findings.json: $($findings.Count) findings, 0 errors" -ForegroundColor Green
```

**Key precedence fix:** `if (-not ($present -contains $k))` — the parentheses are critical because `-not` binds tighter than `-contains` in PowerShell. Without the parens, PS would evaluate `(-not $present) -contains $k`, which never detects missing keys.

- [ ] **Step 2: Run the validator against the seeded findings**

Run:
```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```
Expected: `findings.json: 6 findings, 0 errors`. Any error output means fix the finding(s) before committing.

- [ ] **Step 3: Commit the validator**

Run:
```bash
cd C:/dcfg
git add scripts/code-review/validate-findings-json.ps1
git commit --only scripts/code-review/validate-findings-json.ps1 -m "$(cat <<'EOF'
code-review: Phase 0 findings.json schema validator

PowerShell 7 script that checks required keys, ID format/uniqueness,
and enum values (severity/tier/status/phase). Runs clean against the
6 pre-seeded findings.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Append session log entry for Chunk 1 completion**

Update `C:\dcfg\docs\code-review-2026-04-09\README.md`:
- Append under Session Log: `Chunk 1 complete. Parity sweep run, backports <count> applied, findings validator green.`
- Do NOT mark Phase 0 complete yet — Chunk 2 handles Playwright + final Phase 0 closure.

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md
git commit --only docs/code-review-2026-04-09/README.md -m "code-review: Chunk 1 complete — Phase 0 parity + validator"
```

**End of Chunk 1.** Chunk 2 covers Playwright scaffolding (Tasks 0.5, 0.6, 0.7) + Phase 0 closure.

---

## Chunk 2 — Phase 0 part B: Playwright scaffolding + Phase 0 closure

**Chunk goal:** Inventory existing Playwright state, present Gate 0b scaffolding proposal, conditionally create the e2e test tree under `spa/dcfg-shell/tests/e2e/`, verify auth-state files are valid (spec §4.1 item 4), then close Phase 0. Any file touched under `spa/dcfg-shell/` is strictly scoped by Gate 0b approval.

### Task 0.5: Playwright inventory + Gate 0b proposal

**Files:**
- Read-only: `C:\DCFG\nora\`, `C:\DCFG\spa\dcfg-shell\`

- [ ] **Step 1: Inventory existing Playwright assets**

Run (each sub-command separately so each result is captured):

```bash
# Is @playwright/test installed in the nora/ directory?
test -d C:/DCFG/nora/node_modules/@playwright/test && echo "nora: @playwright/test present" || echo "nora: NOT present"

# Does nora/ contain any specs?
find C:/DCFG/nora -type f \( -name "*.spec.ts" -o -name "*.spec.js" \) 2>/dev/null | head -20

# Does the SPA directory have any playwright config?
find C:/DCFG/spa/dcfg-shell -maxdepth 3 -name "playwright.config*" 2>/dev/null

# Does the SPA directory have a tests/e2e tree already?
test -d C:/DCFG/spa/dcfg-shell/tests/e2e && echo "spa tests/e2e: present" || echo "spa tests/e2e: NOT present"

# List auth-state files and their age
ls -la C:/DCFG/nora/auth-state*.json 2>/dev/null || echo "no auth-state files"
```

Expected output varies. Capture verbatim into the Gate 0b proposal (next step).

- [ ] **Step 2: Classify scaffolding state**

Three possible outcomes:

1. **Fully scaffolded** — SPA has `playwright.config.ts` and `tests/e2e/` with specs. Gate 0b is a trivial rubber-stamp; Task 0.6 becomes verify-only.
2. **Partially scaffolded** — framework installed under `nora/` but no SPA-level config or specs. Propose scaffolding the SPA-level tree per spec §6.4.
3. **Nothing** — no SPA-level Playwright work exists. Propose full scaffolding per spec §6.4. Most likely case.

- [ ] **Step 3: Present Gate 0b proposal to operator**

Present this exact text (with the classified state + inventory output filled in):

```markdown
## Gate 0b — Playwright Scaffolding Proposal

### Current state
<paste classification + verbatim inventory output from Step 1>

### Proposed scaffolding (new files to create)

**Under SPA (these modify the READ-ONLY `spa/dcfg-shell/` tree — approval of this gate explicitly authorizes these SPA edits):**
- `spa/dcfg-shell/package.json` — add `@playwright/test` to `devDependencies`
- `spa/dcfg-shell/package-lock.json` — regenerated by `npm install`
- `spa/dcfg-shell/playwright.config.ts` — NEW
- `spa/dcfg-shell/tests/e2e/fixtures/authState.ts` — NEW
- `spa/dcfg-shell/tests/e2e/helpers/createTestCustomer.ts` — NEW (stub)
- `spa/dcfg-shell/tests/e2e/helpers/cleanup.ts` — NEW (stub)
- `spa/dcfg-shell/tests/e2e/specs/nav-smoke.spec.ts` — NEW (9 routes × read-only)
- `spa/dcfg-shell/tests/e2e/specs/customer-journey.spec.ts` — NEW (test.skip placeholder)
- `spa/dcfg-shell/tests/e2e/specs/onboarding-journey.spec.ts` — NEW (test.skip placeholder)
- `spa/dcfg-shell/tests/e2e/specs/templates-journey.spec.ts` — NEW (test.skip placeholder)
- `spa/dcfg-shell/tests/e2e/specs/admin-journey.spec.ts` — NEW (test.skip placeholder)

**Auth-state split (separate from SPA edits, under nora/):**
The existing `nora/auth-state.json` (if present) will be copied to `nora/auth-state-test.json` and `nora/auth-state-prod.json`. Operator will need to manually re-auth via the Windows Hello manual-pause pattern (`feedback_windows_hello_auth.md`) to produce fresh per-env auth files before any spec `run`.

### What scaffolding will NOT do
- No spec will actually execute full CRUD — all four customer-journey specs are stubbed `test.skip` until Phase 5 generates reliable testid coverage
- No SPA code changes (screens, components, hooks) — scaffolding is isolated to `tests/e2e/` + package manifests
- No CI/CD changes — local-run only for now

### Approve Gate 0b?
Reply with one of:
- `approve` — scaffolding proceeds as proposed
- `modify: <what>` — approve with changes
- `defer` — skip scaffolding; review proceeds without Playwright (Phase 5 smoke becomes manual-only)
- `reject` — same as defer
```

- [ ] **Step 4: Record Gate 0b outcome**

Update `C:\dcfg\docs\code-review-2026-04-09\README.md` Gate Log row `0b` with date + outcome. Append session log entry.

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md
git commit --only docs/code-review-2026-04-09/README.md -m "code-review: Gate 0b recorded — Playwright scaffolding decision"
```

**If Gate 0b was `defer` or `reject` → skip Task 0.6; proceed directly to Task 0.7 (auth-state check stays as manual operator TODO).**

---

### Task 0.6: Scaffold Playwright (conditional on Gate 0b = approve)

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\package.json`, `package-lock.json`
- Create: `C:\DCFG\spa\dcfg-shell\playwright.config.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\fixtures\authState.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\helpers\createTestCustomer.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\helpers\cleanup.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\nav-smoke.spec.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\customer-journey.spec.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\onboarding-journey.spec.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\templates-journey.spec.ts`
- Create: `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\admin-journey.spec.ts`

- [ ] **Step 1: Install @playwright/test in the SPA**

```bash
cd C:/DCFG/spa/dcfg-shell
npm install --save-dev @playwright/test
```
Expected: `devDependencies` gets `@playwright/test`; `package-lock.json` updates. No errors.

- [ ] **Step 2: Write `playwright.config.ts`**

Create `C:\DCFG\spa\dcfg-shell\playwright.config.ts`:

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e/specs',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false, // serial: avoid auth-state contention
  forbidOnly: !!process.env.CI,
  retries: 0,           // never silently retry
  workers: 1,
  maxFailures: 1,       // halt fast on first break
  reporter: [
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    ['list'],
  ],
  use: {
    trace: 'on',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'test-env',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'https://dcfg.powerappsportals.com',
        storageState: 'C:\\DCFG\\nora\\auth-state-test.json',
      },
    },
    {
      name: 'prod-readonly',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'https://dmms1.powerappsportals.com',
        storageState: 'C:\\DCFG\\nora\\auth-state-prod.json',
      },
      testMatch: /nav-smoke\.spec\.ts/, // only read-only specs hit Prod
    },
  ],
});
```

- [ ] **Step 3: Write `fixtures/authState.ts`**

Create `C:\DCFG\spa\dcfg-shell\tests\e2e\fixtures\authState.ts`:

```typescript
import { test as base } from '@playwright/test';
import * as fs from 'fs';

type AuthStateFixtures = { hasValidAuthState: void };

export const test = base.extend<AuthStateFixtures>({
  hasValidAuthState: [async ({ browserName: _browserName }, use, testInfo) => {
    const storageStatePath = testInfo.project.use.storageState as string;
    if (!fs.existsSync(storageStatePath)) {
      throw new Error(
        `Auth state not found at ${storageStatePath}. Run manual-pause auth capture first.`
      );
    }
    const stat = fs.statSync(storageStatePath);
    const ageHours = (Date.now() - stat.mtime.getTime()) / 3_600_000;
    if (ageHours > 24) {
      console.warn(`Auth state is ${ageHours.toFixed(1)}h old. May need refresh.`);
    }
    await use();
  }, { auto: true }],
});

export { expect } from '@playwright/test';
```

- [ ] **Step 4: Write `specs/nav-smoke.spec.ts` — the only real spec in this scaffolding pass**

Create `C:\DCFG\spa\dcfg-shell\tests\e2e\specs\nav-smoke.spec.ts`:

```typescript
import { test, expect } from '../fixtures/authState';

const ROUTES = [
  '/',
  '/dashboard',
  '/customers',
  '/contracts',
  '/msas',
  '/locations',
  '/onboarding',
  '/send-queue',
  '/admin',
];

test.describe('Read-only nav smoke', () => {
  for (const route of ROUTES) {
    test(`route ${route} loads without errors`, async ({ page }) => {
      const consoleErrors: string[] = [];
      page.on('console', (msg) => {
        if (msg.type() === 'error') consoleErrors.push(msg.text());
      });
      const networkErrors: string[] = [];
      page.on('response', (r) => {
        if (r.status() >= 400 && r.url().includes('/_api/')) {
          networkErrors.push(`${r.status()} ${r.url()}`);
        }
      });

      await page.goto(`/#${route}`);
      await page.waitForLoadState('networkidle');
      // At least one data-testid visible = SPA mounted
      await expect(page.locator('[data-testid]').first()).toBeVisible({ timeout: 15_000 });

      expect(consoleErrors, `Console errors on ${route}:\n${consoleErrors.join('\n')}`).toEqual([]);
      expect(networkErrors, `Web API errors on ${route}:\n${networkErrors.join('\n')}`).toEqual([]);
    });
  }
});
```

- [ ] **Step 5: Write the four stub journey specs with concrete describe/test names**

Create each of the four files with a minimal `test.skip` body. Each file has a different describe name so they appear as distinct in the Playwright report.

`C:\DCFG\spa\dcfg-shell\tests\e2e\specs\customer-journey.spec.ts`:

```typescript
import { test, expect } from '../fixtures/authState';

test.describe('Customer journey — Test env full CRUD', () => {
  test.skip('create customer → new contract → generate doc → send', async ({ page }) => {
    // Stub. Filled in during Phase 5 once data-testid coverage is reliable.
    expect(page).toBeDefined();
  });
});
```

`C:\DCFG\spa\dcfg-shell\tests\e2e\specs\onboarding-journey.spec.ts`:

```typescript
import { test, expect } from '../fixtures/authState';

test.describe('Onboarding journey — Test env full CRUD', () => {
  test.skip('create case → work phase steps → close case', async ({ page }) => {
    // Stub. Filled in during Phase 5.
    expect(page).toBeDefined();
  });
});
```

`C:\DCFG\spa\dcfg-shell\tests\e2e\specs\templates-journey.spec.ts`:

```typescript
import { test, expect } from '../fixtures/authState';

test.describe('Templates journey — Test env full CRUD', () => {
  test.skip('list → detail → edit field mappings → save', async ({ page }) => {
    // Stub. Filled in during Phase 5.
    expect(page).toBeDefined();
  });
});
```

`C:\DCFG\spa\dcfg-shell\tests\e2e\specs\admin-journey.spec.ts`:

```typescript
import { test, expect } from '../fixtures/authState';

test.describe('Admin journey — Test env full CRUD (validates 2026-04-09 hotfix)', () => {
  test.skip('create blanket work order for selected customer', async ({ page }) => {
    // Validates that the dcfg_blanket_workorder/fields bind-form hotfix works.
    expect(page).toBeDefined();
  });
  test.skip('create customer AP mapping for cost code', async ({ page }) => {
    // Validates that the dcfg_customer_ap_mapping/fields bind-form hotfix works.
    expect(page).toBeDefined();
  });
});
```

- [ ] **Step 6: Write the helper stubs**

Create `C:\DCFG\spa\dcfg-shell\tests\e2e\helpers\createTestCustomer.ts`:

```typescript
/**
 * Creates a throwaway "CR-TEST-<timestamp>" customer via the portal UI.
 * Stub — implementation lands in Phase 5 once data-testid coverage is reliable.
 */
export async function createTestCustomer(_: unknown): Promise<never> {
  throw new Error('createTestCustomer is not yet implemented — Phase 5 work');
}
```

Create `C:\DCFG\spa\dcfg-shell\tests\e2e\helpers\cleanup.ts`:

```typescript
/**
 * Soft-delete any "CR-TEST-*" rows after a spec run.
 * Respects feedback_soft_delete_only — sets dcfg_active_flag = false, not hard delete.
 * Stub — implemented when the customer-journey spec becomes non-skip.
 */
export async function cleanupTestRows(_: unknown): Promise<void> {
  // Intentional no-op — stub for imports to not break.
}
```

- [ ] **Step 7: Prove the config parses and specs are discoverable (no execution)**

```bash
cd C:/DCFG/spa/dcfg-shell
npx playwright test --project=test-env --list
```

Expected: list of 13 tests (9 nav-smoke + 4 stub journey tests, 5 of which are `test.skip` — admin-journey has 2 skipped tests). No parse errors. No actual navigation attempted.

If errors: fix and re-run. Common issues:
- `Cannot find module './fixtures/authState'` → relative path wrong; confirm the fixture file exists at `tests/e2e/fixtures/authState.ts`
- TypeScript errors → likely an import mismatch; check @playwright/test version vs. config

- [ ] **Step 8: Commit the Playwright scaffolding**

```bash
cd C:/dcfg
git add spa/dcfg-shell/playwright.config.ts spa/dcfg-shell/tests/ spa/dcfg-shell/package.json spa/dcfg-shell/package-lock.json
git commit --only spa/dcfg-shell/playwright.config.ts spa/dcfg-shell/tests/ spa/dcfg-shell/package.json spa/dcfg-shell/package-lock.json -m "$(cat <<'EOF'
code-review: Phase 0 Playwright scaffolding (Gate 0b approved)

playwright.config.ts with test-env and prod-readonly projects.
authState fixture. Real nav-smoke spec for 9 core routes.
Stub journey specs (test.skip) for customer/onboarding/templates/
admin, to be filled in during Phase 5. Helper stubs for test-customer
creation + cleanup.

@playwright/test added to devDependencies.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 0.7: Auth-state validity check (spec §4.1 item 4)

**Files:**
- Read-only: `C:\DCFG\nora\auth-state*.json`

**Runs regardless of Gate 0b outcome**, but the check is more rigorous if scaffolding exists.

- [ ] **Step 1: Check file existence + age for each env**

```bash
pwsh -Command "Get-ChildItem C:\DCFG\nora\auth-state*.json -ErrorAction SilentlyContinue | Select-Object Name, LastWriteTime, @{Name='AgeHours';Expression={[math]::Round(((Get-Date) - \$_.LastWriteTime).TotalHours, 1)}}"
```

Expected: list of `auth-state*.json` files with their age in hours.

- [ ] **Step 2: Classify each auth-state file**

For each file:
- **Not present** → Manual operator action required: re-auth via Windows Hello (`feedback_windows_hello_auth.md`), save as `auth-state-test.json` or `auth-state-prod.json`
- **Age > 24h** → Warning: may have expired. Operator should re-auth before Phase 1.
- **Age < 24h** → Likely valid.

- [ ] **Step 3: If scaffolding was approved (Gate 0b), run a one-spec smoke to prove auth works**

```bash
cd C:/DCFG/spa/dcfg-shell
npx playwright test --project=test-env specs/nav-smoke.spec.ts --grep "route / loads" --reporter=list
```

Expected: the `/` route smoke test passes against Test. If it fails with `TimeoutError` or `NetworkError` on a login URL, the auth-state is stale.

**If the single-spec smoke fails → halt.** Operator must re-auth. Do not proceed with any further Playwright work until this is green.

- [ ] **Step 4: If scaffolding was deferred (Gate 0b), document the check as deferred**

Update `parity-report.json` with a note like:
```json
"authStateValidity": {
  "checkedAt": "2026-04-09T20:30:00Z",
  "status": "deferred",
  "reason": "Gate 0b rejected scaffolding; Phase 5 smoke will be manual"
}
```

- [ ] **Step 5: Commit auth-state check outcome**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/parity-report.json
git commit --only docs/code-review-2026-04-09/parity-report.json -m "code-review: Phase 0 auth-state validity check outcome"
```

---

### Task 0.8: Phase 0 closure

**Files:**
- Update: `C:\dcfg\docs\code-review-2026-04-09\README.md`
- Update: `C:\dcfg\docs\code-review-2026-04-09\session-state.md`

- [ ] **Step 1: Re-run `validate-findings-json.ps1` one last time**

```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```
Expected: `findings.json: 6 findings, 0 errors`. Any error here means fix before closing Phase 0.

- [ ] **Step 2: Generate Phase 0 summary block**

Build a concise summary and prepare it for presentation and for the Session Log:

```
Phase 0 complete. Branch: code-review-2026-04-09.

Parity sweep:
  - Prod: <drift count>
  - Test: <drift count> (<backported count> backported, <accepted drift count> accepted)
  - Stage: <drift count> (<backported count> backported, <accepted drift count> accepted)

SPA bundle state:
  - Prod: OK / drift
  - Test: OK / drift / backported via full deploy
  - Stage: OK / drift / backported via full deploy

Findings: 6 pre-seeded, validator green.

Playwright: <scaffolded | deferred>
Auth-state: <valid | stale | deferred>

Gate 0a: <outcome summary>
Gate 0b: <outcome summary>

Ready for Phase 1 — shared modules audit.
```

- [ ] **Step 3: Mark Phase 0 complete in README**

Edit `C:\dcfg\docs\code-review-2026-04-09\README.md`:
- Change `- [ ] Phase 0 — ...` to `- [x] Phase 0 — complete 2026-04-09`
- Append a session log entry with the Phase 0 summary from Step 2

- [ ] **Step 4: Update session-state.md with Phase 0 end state**

Edit `C:\dcfg\docs\code-review-2026-04-09\session-state.md`:
- Update "To Resume" → "Phase 1 — shared modules audit; next task is Task 1.0"
- Update ID cursor if any Phase 0 findings were added (unlikely — this phase was about environment state, not code)

- [ ] **Step 5: Commit Phase 0 closure**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "$(cat <<'EOF'
code-review: Phase 0 complete — parity verified, scaffolding decided

All Phase 0 tasks closed. Environment parity verified across
Test/Stage/Prod; backports applied per Gate 0a; Playwright scaffolding
per Gate 0b; findings validator green. Ready for Phase 1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Present Phase 0 summary to operator**

Post the summary from Step 2 in chat. Ask: "Ready to proceed to Phase 1 — shared modules audit?" Wait for operator `yes` / `hold` / `defer`.

**End of Chunk 2.** Chunk 3 covers Phase 1 (shared modules audit).

---

## Chunk 3 — Phase 1: Shared modules audit

**Chunk goal:** Run a single serial audit agent across all 17 shared modules, applying categories 3, 6, 8, 8a, 8b, 9, 11 (skipping 2, 4, 5, 7 per spec §4.2 — category 2 console pollution is handled in Phase 2b's cross-cutting sweep). Review findings at Gate 1a, propose a fix batch at Gate 1b, apply fixes and run per-batch smoke at Gate 1c. All file operations on `spa/dcfg-shell/src/` are explicitly gated by Gate 1b.

### Task 1.0: Dispatch the shared-modules audit sub-agent

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\by-screen\_shared.json` (agent output)
- Create (per-module): `C:\dcfg\docs\code-review-2026-04-09\by-screen\portalApi.json`, `useTableControls.json`, `usePortalUser.json`, `Toast.json`, `NavPanel.json`, `RoleGuard.json`, `SlideOutPanel.json`, `SpeechMic.json`, `FieldName.json`, `AppRouter.json`, `App.json`, `main.json`, `ErrorReporter.json`, `LocationManager.json`, `SensorBanner.json`, `intakeFieldKeys.json`, `projectConstants.json`

- [ ] **Step 1: Verify pre-requisites before dispatch**

Check:
- Phase 0 is marked complete in README
- `findings.json` validator is green
- Current branch is `code-review-2026-04-09`
- No uncommitted changes on the branch: `git status` shows clean tree

Run:
```bash
cd C:/dcfg
git status
git branch --show-current
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```
Expected: clean tree, `code-review-2026-04-09`, `0 errors`.

- [ ] **Step 2: Read the spa-inventory skill data for current shared-module file sizes and imports**

Load `C:\Users\JosephCameron\.claude\skills\dcfg-spa-reference\data\spa-inventory.json` for context the agent will need. Also check actual file sizes on disk so the agent knows what it's walking into:

```bash
pwsh -Command "Get-ChildItem C:\DCFG\spa\dcfg-shell\src\*.jsx, C:\DCFG\spa\dcfg-shell\src\*.js | Where-Object { $_.Name -in @('main.jsx','App.jsx','AppRouter.jsx','portalApi.js','useTableControls.jsx','usePortalUser.jsx','Toast.jsx','NavPanel.jsx','RoleGuard.jsx','SlideOutPanel.jsx','SpeechMic.jsx','FieldName.jsx','ErrorReporter.jsx','LocationManager.jsx','SensorBanner.jsx','intakeFieldKeys.js','projectConstants.js') } | Select-Object Name, @{N='KB';E={[math]::Round(\$_.Length/1024,1)}}"
```
Expected: a list of 17 files with their sizes. If any file is missing (e.g., the spa-inventory is stale and a file was renamed), STOP and reconcile before dispatching the agent.

- [ ] **Step 3: Dispatch the shared-modules audit agent**

Use the Agent tool (general-purpose subagent) with this exact prompt:

```
You are the Phase 1 shared-modules audit agent for the DCFG SPA code review.

**Spec reference:** C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md (read §3 for categories, §4.2 for your scope)
**Plan reference:** C:\dcfg\docs\superpowers\plans\2026-04-09-spa-review-cleanup.md (Phase 1 / Chunk 3)

**Your scope:** 17 shared-module files under C:\DCFG\spa\dcfg-shell\src\:
main.jsx, App.jsx, AppRouter.jsx, portalApi.js, useTableControls.jsx,
usePortalUser.jsx, Toast.jsx, NavPanel.jsx, RoleGuard.jsx, SlideOutPanel.jsx,
SpeechMic.jsx, FieldName.jsx, ErrorReporter.jsx, LocationManager.jsx,
SensorBanner.jsx, intakeFieldKeys.js, projectConstants.js

**Categories to apply:** 3 (error handling), 6 (performance), 8 (data integrity),
8a (Web API $select safety), 8b (@odata.bind coverage), 9 (auth/role checks),
11 non-testid (hardcoded URLs, FieldName visibility). SKIP categories 2, 4, 5, 7
(handled in Phase 2 or later, or not applicable to non-UI shared modules).

**Finding ID range:** CR-2026-04-09-0200 through 0299. You MUST NOT use any
other range. If you exceed 0299, HALT and escalate.

**Finding schema:** See spec §5.2. Append to findings.json preserving the
existing 6 pre-seeded entries. For each finding also write a per-module
JSON file under C:\dcfg\docs\code-review-2026-04-09\by-screen\<moduleName>.json
as an array of that module's findings only. Write C:\dcfg\docs\code-review-2026-04-09\by-screen\_shared.json
as the union of all 17 modules' findings (same content, one file, for convenience).

**Critical rules:**
- READ-ONLY audit. You do NOT edit any file under C:\DCFG\spa\dcfg-shell\src\.
- You only append to findings.json and write the per-module by-screen files.
- DO NOT dispatch further subagents. This is a single-agent task.
- If you find more than 100 issues in a single file, HALT and escalate.
- For Category 8a (Web API $select safety): walk every apiGet, fetch, and
  raw XHR call. For each call to an explicit-list table (see spec §1.1.1
  table — 4 tables currently explicit on Prod), flag as P1 if no $select.
- For Category 8b (@odata.bind coverage): walk every POST/PATCH with a
  "@odata.bind" attribute. Cross-reference against the table's fields list
  in parity-report.json. Flag as P0 if the bind column is missing.
- For Category 9: flag any route or action that lacks role-check guarding
  via RoleGuard / usePortalUser.hasRole() / isAdmin() / isManager().

**Output format per finding:** fully-formed JSON object matching the schema
in spec §5.2.1 (example finding). Always set phase="phase-1",
agent="phase-1-shared-modules-audit", status="open".

**Do not attempt to fix anything.** Findings only. All fixes happen in
Phase 5 after operator approval at Gate 1b.

**Deliverables:**
1. findings.json updated with N new phase-1 findings (IDs 0200-0299)
2. 17 per-module JSON files under by-screen/
3. by-screen/_shared.json with the same union
4. A terse summary in chat: count per category, count per severity,
   top 5 highest-severity findings with file:line.

Begin.
```

Dispatch this via the Agent tool (general-purpose subagent, foreground).

- [ ] **Step 4: Receive agent output and validate it**

When the agent returns:
1. Run `pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"` — must be green
2. Confirm by-screen/ now has 17 module files + `_shared.json`
3. Confirm all new findings have IDs in range 0200-0299
4. Confirm no findings have `status` other than `open`
5. Confirm no findings have `file` outside the 17 expected modules

If any check fails: do NOT commit. Reject the agent's output, dispatch a second agent with feedback about what was wrong.

- [ ] **Step 5: Commit the audit output (findings + by-screen)**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-screen/
git commit --only docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-screen/ -m "$(cat <<'EOF'
code-review: Phase 1 shared-modules audit complete

Findings appended to findings.json (IDs 0200-0299). Per-module JSON
outputs under by-screen/ for all 17 shared modules. No SPA code
touched; audit is read-only. Fixes pending Gate 1b approval.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.1: Gate 1a — Operator reviews findings

**Files:**
- Read: `C:\dcfg\docs\code-review-2026-04-09\by-screen\_shared.json`
- Update: `C:\dcfg\docs\code-review-2026-04-09\README.md` (Gate Log)

- [ ] **Step 1: Generate a human-readable summary from `_shared.json`**

Read `_shared.json` and produce a markdown table like:

```markdown
## Phase 1 Findings — Shared Modules

Total: <N>

By severity: P0=<n>, P1=<n>, P2=<n>, P3=<n>
By category: 3(err-handling)=<n>, 6(perf)=<n>, 8(data)=<n>, 8a($select)=<n>, 8b(bind)=<n>, 9(auth)=<n>, 11(handoff)=<n>

Top 10 highest-severity:

| ID | File | Line | Sev | Title |
|---|---|---|---|---|
| CR-2026-04-09-0201 | src/portalApi.js | 145 | P0 | ... |
...

Full list: docs/code-review-2026-04-09/by-screen/_shared.json
```

- [ ] **Step 2: Present the summary to the operator**

Post the summary above in chat along with:

```
Gate 1a — review findings before we propose a fix batch.

Options:
- `approve findings` / `yes` → proceed to Task 1.2 (propose fix batch)
- `clarify <id>` → agent re-runs with more detail on a specific finding
- `reject <id>` → mark that finding status=rejected
- `defer <id>` → mark that finding status=deferred-future
- `hold` → stop, no decision yet
```

- [ ] **Step 3: Apply any per-finding decisions**

For each `reject <id>` / `defer <id>` / `clarify <id>` — update findings.json accordingly. For `reject`/`defer` set status + add a `rejectReason` or `deferReason` field. For `clarify`, dispatch a follow-up agent targeted at that one finding.

- [ ] **Step 4: Record Gate 1a outcome**

Update README Gate Log row `1a` with date + outcome. Append session log entry.

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json -m "code-review: Gate 1a recorded — shared-modules findings review"
```

---

### Task 1.2: Propose Phase 1 fix batch (Gate 1b)

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\approvals\2026-04-09-batch-01-phase1-shared.md`

- [ ] **Step 1: Build the batch document**

Create the approval document with this structure:

```markdown
# Batch 01 — Phase 1 Shared-Modules Fixes

**Phase:** 1
**Target:** 17 shared modules under C:\DCFG\spa\dcfg-shell\src\
**Findings count:** <N> approved for this batch (subset of phase-1 open findings, sorted by severity)
**Generated:** 2026-04-09T...

## Scope rules
- Batch size ≤ 15 findings (per spec §4.6 heuristic)
- Never mix tiers (this batch is all `batch` tier; no auto-fix items)
- Every proposed edit has before/after code visible

## Findings in this batch

### Finding CR-2026-04-09-0201 — <title>
**File:** src/portalApi.js
**Line(s):** <range>
**Severity:** <P0-P3>
**Category:** <name>

**Current code:**
```javascript
// exact code from file
```

**Proposed edit:**
```javascript
// exact proposed code
```

**Rationale:** <why this change is correct and safe>

**Risk:** <what could go wrong>

---

### Finding CR-2026-04-09-0202 — <title>
... (repeat for each finding in the batch)

---

## Approval options

Reply with:
- `approve batch` — execute all edits in order
- `approve 0201,0203,0205` — execute only listed IDs
- `reject 0202` — skip that finding; execute the rest
- `reject batch` — cancel this batch entirely
- `hold` — stop, no execution yet
```

- [ ] **Step 2: Present the batch to the operator**

Post the approval doc path and ask for Gate 1b decision.

- [ ] **Step 3: Record Gate 1b outcome**

Update the approval doc with operator decision (approve/reject per finding). Update README Gate Log row `1b`. Update findings.json: for each approved finding set `status=approved`, `approvedAt=<iso>`, `approvedIn=approvals/2026-04-09-batch-01-phase1-shared.md`. For each rejected finding set `status=rejected` with reason.

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/approvals/2026-04-09-batch-01-phase1-shared.md docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json
git commit --only docs/code-review-2026-04-09/approvals/2026-04-09-batch-01-phase1-shared.md docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json -m "code-review: batch 01 — Phase 1 shared-modules approvals recorded"
```

**If `reject batch` → skip Task 1.3; go straight to Task 1.4 (smoke) and record Phase 1 as "audited only, no fixes".**

---

### Task 1.3: Apply approved Phase 1 edits

**Files:**
- Modify: any approved file under `C:\DCFG\spa\dcfg-shell\src\` (per batch 01)

- [ ] **Step 1: For each approved finding, read the file, apply the exact edit from the batch doc**

For each finding with `status=approved` in batch 01:
1. Read the file at the exact line range shown in the batch doc
2. Verify the "current code" in the batch still matches the file (protects against drift)
3. Apply the edit using the Edit tool with `old_string` = current code, `new_string` = proposed code
4. If `old_string` doesn't match (drift): HALT, re-dispatch Gate 1b with updated code for that finding

- [ ] **Step 2: Build the SPA locally to verify no compile errors**

```bash
cd C:/DCFG/spa/dcfg-shell
npm run build
```

Expected: build succeeds; dist/ is written. Note any new warnings — if new warnings appear that weren't there before the batch, halt and investigate.

- [ ] **Step 3: Update findings.json for each applied fix**

For each applied finding set `status=fixed`, `fixedAt=<iso>`, `fixCommit=` (will be set after commit in Step 4).

- [ ] **Step 4: Commit all Phase 1 SPA edits + findings.json updates**

```bash
cd C:/dcfg
git add spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json
git commit --only spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json -m "$(cat <<'EOF'
code-review: batch 01 applied — Phase 1 shared-modules fixes

<N> findings fixed in shared modules per operator approval.
See docs/code-review-2026-04-09/approvals/2026-04-09-batch-01-phase1-shared.md

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git log --oneline -1
```

- [ ] **Step 5: Back-fill fixCommit SHA in findings.json**

Get the commit SHA from Step 4 output and update each fixed finding. Concrete pwsh command:

```bash
cd C:/dcfg
COMMIT=$(git log --format=%H -n 1)
pwsh -Command "
  \$path = 'C:\dcfg\docs\code-review-2026-04-09\findings.json'
  \$findings = Get-Content \$path -Raw | ConvertFrom-Json
  foreach (\$f in \$findings) {
    if (\$f.status -eq 'fixed' -and \$null -eq \$f.fixCommit -and \$f.approvedIn -match 'batch-01-phase1-shared') {
      \$f.fixCommit = '$COMMIT'
    }
  }
  \$findings | ConvertTo-Json -Depth 10 | Set-Content \$path -Encoding UTF8
"
```

Expected: findings.json updated in place. Verify by running the validator:

```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```

Then commit the back-fill:

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/findings.json
git commit --only docs/code-review-2026-04-09/findings.json -m "code-review: batch 01 back-fill fixCommit SHA"
```

---

### Task 1.4: Per-batch smoke — Playwright Test + Prod (Gate 1c)

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\smoke-runs\batch-01\` (Playwright output)

- [ ] **Step 1: If Playwright was scaffolded (Gate 0b approved), deploy to Test**

**Capture the current pac index first, then switch, deploy, restore.** The indices below match the plan's env table (§Environment): Prod=[1], Test=[2], Stage=[3] as verified 2026-04-09. Do not assume — check.

```bash
pac auth list
# Note the current active (*) index — call it $INITIAL_INDEX. Typically [1] Prod.
# Example: if "[1] *" is shown, $INITIAL_INDEX=1

cd C:/DCFG/spa/dcfg-shell

# Switch to Test [2]
pac auth select --index 2
pac auth who   # MUST confirm "DCFGSystems-Test" before proceeding

npm run build
pac pages upload-code-site --rootPath . --compiledPath dist

# Restore to whatever was active at the start of this task
pac auth select --index 1   # If $INITIAL_INDEX was [1] Prod; change if it was [2] or [3]
pac auth who
```

Then clear Test portal cache manually (Power Platform admin center → Power Pages → dcfg.powerappsportals.com → Site Actions → Clear cache). Operator confirms: `cache cleared`.

**Note:** CLAUDE.md has a durable rule "restore pac auth to Test after deploying" but this predates the current verified indices and assumes index [1] = Test. Under current indices (Prod=[1], Test=[2], Stage=[3]), the "restore" step should go to whichever index was active at the start of the task, not blindly to [1] or [2]. When in doubt, ask the operator.

- [ ] **Step 2: Run nav-smoke on Test**

```bash
cd C:/DCFG/spa/dcfg-shell
npx playwright test --project=test-env specs/nav-smoke.spec.ts
```

Expected: all 9 routes green. Trace files written to `playwright-report/` and `test-results/`.

- [ ] **Step 3: Run nav-smoke on Prod (read-only)**

**Prod is NOT deployed.** Only Test is deployed with the new Phase 1 code. Prod smoke just confirms the existing deployed Prod build is still functional (nothing should have changed on Prod):

```bash
cd C:/DCFG/spa/dcfg-shell
npx playwright test --project=prod-readonly specs/nav-smoke.spec.ts
```

Expected: all 9 routes green.

- [ ] **Step 4: Archive Playwright traces**

Copy the `playwright-report/` and `test-results/` output to `docs/code-review-2026-04-09/smoke-runs/batch-01/`:

```bash
mkdir -p C:/dcfg/docs/code-review-2026-04-09/smoke-runs/batch-01
cp -r C:/DCFG/spa/dcfg-shell/playwright-report C:/dcfg/docs/code-review-2026-04-09/smoke-runs/batch-01/
cp -r C:/DCFG/spa/dcfg-shell/test-results C:/dcfg/docs/code-review-2026-04-09/smoke-runs/batch-01/
```

- [ ] **Step 5: If Playwright was deferred (Gate 0b rejected), run manual operator smoke instead**

Present to operator:
```
Gate 1c — Manual smoke required (Playwright was deferred at Gate 0b).

Please walk this path on Test (https://dcfg.powerappsportals.com):
1. Log in
2. Navigate to Dashboard, Customer List, Contract List, MSA List, Locations, Onboarding, Send Queue, Admin
3. Confirm no blank pages, no console errors (check DevTools)
4. Open one customer detail page; confirm it loads
5. Open one contract detail page; confirm it loads
6. Reply `smoke ok` or `smoke fail: <what>`
```

- [ ] **Step 6: Record Gate 1c outcome**

Update README Gate Log row `1c` with outcome + link to smoke-runs/batch-01/.

- [ ] **Step 7: Verify fixed findings + update to verified status**

For each finding with `status=fixed` and `approvedIn=batch 01`, set `status=verified` and `verifiedAt=<iso>`.

- [ ] **Step 8: Commit smoke results and status updates**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/smoke-runs/batch-01/ docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json
git commit --only docs/code-review-2026-04-09/smoke-runs/batch-01/ docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json -m "$(cat <<'EOF'
code-review: Phase 1 smoke green (Gate 1c)

Playwright nav-smoke ran green on Test + Prod after batch 01 fixes.
Findings marked verified. Phase 1 complete.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9: Handle smoke failure (rollback path)**

**Only if Step 2, 3, or 5 reported failure:**

1. Do NOT proceed to Phase 2. Halt the review.
2. Identify the specific smoke failure (console error, network error, broken assertion)
3. Run `git revert <batch-01-commit-sha> --no-edit` to revert the SPA edits
4. Rebuild + redeploy Test: `npm run build && pac pages upload-code-site`
5. Re-run Step 2 smoke — must go green on the reverted build
6. Mark batch 01 in the approvals doc as `rolled-back`
7. For each finding that was marked fixed→rolled back, reset `status=open` and clear `fixedAt`/`fixCommit`/`verifiedAt`
8. Escalate to operator with the failure evidence; do not propose a new batch without operator direction

---

### Task 1.5: Phase 1 closure

- [ ] **Step 1: Update README Phase Status**

Edit `C:\dcfg\docs\code-review-2026-04-09\README.md`:
- Change `- [ ] Phase 1 — Shared modules audit` to `- [x] Phase 1 — complete YYYY-MM-DD`
- Append session log entry with counts: N findings total, N approved, N fixed, N deferred, N rejected

- [ ] **Step 2: Update session-state.md for next phase**

Edit `C:\dcfg\docs\code-review-2026-04-09\session-state.md`:
- "To Resume" → "Phase 2 — auto-fix pass (3 parallel agents); next task is Task 2.0"
- Findings ID cursor: Phase 1 range (0200-0299) is now closed; phase-2a cursor = 0300

- [ ] **Step 3: Commit Phase 1 closure**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "code-review: Phase 1 complete — shared modules audited and fixed"
```

- [ ] **Step 4: Present Phase 1 summary to operator**

```
Phase 1 complete.
  Files audited: 17 shared modules
  Findings:      <total> (P0=<n>, P1=<n>, P2=<n>, P3=<n>)
  Approved:      <n>    Fixed: <n>    Rejected: <n>    Deferred: <n>
  Smoke:         <green | failed → rolled-back>
  Gate 1a/1b/1c: all recorded

Ready to proceed to Phase 2 — auto-fix pass (3 parallel agents)?
```

**End of Chunk 3.** Chunk 4 covers Phase 2 (auto-fix pass).

---

## Chunk 4 — Phase 2: Auto-fix pass (dead code, console, testids)

**Chunk goal:** Three parallel subagents, each handling one cross-cutting category across all 63 in-scope files. Each agent's output is a batch preview gated before execution. Destructive operations (file deletes) escalate per Section 7.3. Per-category gates (2a, 2b, 2c) approve execution; Gate 2d is the combined smoke after all three batches land.

**Parallelization note:** The three agents in Task 2.0 are dispatched **in the same assistant message** using multiple Agent tool calls so they run concurrently. Do NOT dispatch them sequentially.

### Task 2.0: Dispatch 3 parallel auto-fix audit agents

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\by-category\01-dead-code.md` (narrative output)
- Create: `C:\dcfg\docs\code-review-2026-04-09\by-category\02-console-pollution.md`
- Create: `C:\dcfg\docs\code-review-2026-04-09\by-category\11-testid.md`
- Append to: `findings.json` (IDs 0300-0599)

- [ ] **Step 1: Verify pre-requisites**

Check:
- Phase 1 is marked complete in README
- findings.json validator is green
- `git status` shows a clean tree

- [ ] **Step 2: Dispatch Agent 2a — Dead code & duplicates**

Agent prompt (general-purpose, foreground):

```
You are Phase 2a — Dead Code & Duplicates auditor for the DCFG SPA code review.

**Spec:** C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md §3 Category 1
**Plan:** C:\dcfg\docs\superpowers\plans\2026-04-09-spa-review-cleanup.md Phase 2 / Chunk 4

**Scope:** all 63 in-scope SPA files per plan §File Structure (shared modules + screen
sections + templates subsystem + FlowMonitor). Use Glob to find them; skip
everything explicitly out-of-scope: _archive/, debug/, interview/, NoraCopilot,
AbsorptionDashboard, UserManual, CapitalPlan, test/.

**Finding ID range:** CR-2026-04-09-0300 through 0399. HALT if you exceed 0399.

**What to look for (Category 1):**
- Duplicate files (e.g., src/AppRouter.jsx vs src/screens/AppRouter.jsx)
- Entire dead folders (_archive/)
- Unused imports (verify by checking import usage in the same file)
- Unused state declarations (useState whose setter is never called and value never read)
- Orphaned functions (declared but never called in the same file, not exported)
- Commented-out code blocks > 5 lines

**Destructive vs in-file:**
- File deletions and entire-folder removals → DESTRUCTIVE, escalate per spec §7.3.
  Mark tier=batch (NOT auto-fix); note "DESTRUCTIVE" prominently in detail field.
- In-file cleanups (unused imports, unused state, dead functions) → tier=auto-fix.

**Rules:**
- READ-ONLY audit. Do not edit any file.
- For each duplicate-file candidate, determine which is "live" by tracing imports
  from main.jsx → App.jsx → AppRouter. Record evidence.
- Do not flag tagged "keep" comments (look for // KEEP or // INTENTIONAL nearby).
- Do not flag files in C:\DCFG\spa\dcfg-shell\tests\ — that's Playwright scaffolding.

**Deliverables:**
1. Append findings to findings.json (IDs 0300-0399)
2. Write C:\dcfg\docs\code-review-2026-04-09\by-category\01-dead-code.md with a
   narrative rollup: total count, breakdown by destructive vs in-file, top 10 most
   impactful items, and a proposed execution order for in-file fixes.
3. Summary in chat: counts by tier.

Begin.
```

- [ ] **Step 3: In the same message, dispatch Agent 2b — Console pollution**

Agent prompt (general-purpose, foreground):

```
You are Phase 2b — Console Pollution auditor for the DCFG SPA code review.

**Spec:** §3 Category 2
**Plan:** Phase 2 / Chunk 4

**Scope:** all 63 in-scope SPA files.

**Finding ID range:** CR-2026-04-09-0400 through 0499.

**What to look for:**
- console.log, console.warn, console.error, console.debug, console.info calls
- `debugger;` statements
- Leftover alert() calls

**Exclusions:**
- Calls inside debug/index.js or gated behind `if (window.dcfgDebug)` — KEEP, not pollution
- Intentional error logs inside catch blocks that also call `toast.show('err', ...)` — KEEP
  (they're diagnostic supplements to user-facing errors)
- console calls inside Toast.jsx itself — KEEP (Toast is allowed to log its own state)

**Tier:** auto-fix by default. If uncertain about context (e.g., a console.error that
might be intentional), downgrade to tier=batch and note the uncertainty.

**Rules:**
- READ-ONLY audit.
- For each console call: record file:line, the exact line content, and a recommended
  action (delete / replace with toast / keep with gate).

**Deliverables:**
1. findings.json appended (0400-0499)
2. C:\dcfg\docs\code-review-2026-04-09\by-category\02-console-pollution.md narrative rollup
3. Chat summary: count per exclusion reason, count per recommended action.

Begin.
```

- [ ] **Step 4: In the same message, dispatch Agent 2c — testid golden rule**

Agent prompt (general-purpose, foreground):

```
You are Phase 2c — data-testid Golden Rule auditor for the DCFG SPA code review.

**Spec:** §3 Category 11 (testid subset only)
**Feedback:** feedback_testid_golden_rule.md — every interactive element gets data-testid
**Plan:** Phase 2 / Chunk 4

**Scope:** all 63 in-scope SPA files.

**Finding ID range:** CR-2026-04-09-0500 through 0599.

**What to look for:**
Interactive elements that lack a data-testid attribute. Specifically:
- <button>, <input>, <select>, <textarea>, <a onClick=>
- Custom components that render them: e.g., <PrimaryButton>, <Toast>, <ModalClose>
- Form rows, table rows with click handlers

**Naming convention (feedback_testid_golden_rule.md):**
- kebab-case
- Include screen/component prefix: e.g., `customer-list-new-btn`,
  `contract-detail-save-btn`, `onboarding-detail-phase-2-step-3-notes`
- No UUIDs or timestamps in testids (must be stable selectors)

**Tier:** auto-fix. Proposed testid is inserted as a new attribute.

**Rules:**
- READ-ONLY audit. You propose the testid value; the fix is applied in Phase 2c execution.
- For each finding include the EXACT current line and the EXACT proposed line with testid inserted.
- Skip elements that already have data-testid (don't overwrite good ones).
- Skip purely presentational elements (e.g., decorative icons, non-clickable divs).

**Deliverables:**
1. findings.json appended (0500-0599)
2. C:\dcfg\docs\code-review-2026-04-09\by-category\11-testid.md narrative
3. Chat summary: count per component type (button/input/etc).

Begin.
```

- [ ] **Step 5: Wait for all three agents to return**

The three agents run concurrently. When all three have returned, verify:

```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```

Expected: `0 errors` and the count should increase by (agent 2a count) + (agent 2b count) + (agent 2c count). If validation fails, identify which agent's output is malformed and re-dispatch only that agent.

- [ ] **Step 6: Commit all three agents' outputs**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-category/01-dead-code.md docs/code-review-2026-04-09/by-category/02-console-pollution.md docs/code-review-2026-04-09/by-category/11-testid.md
git commit --only docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-category/01-dead-code.md docs/code-review-2026-04-09/by-category/02-console-pollution.md docs/code-review-2026-04-09/by-category/11-testid.md -m "$(cat <<'EOF'
code-review: Phase 2 auto-fix audit output (3 agents)

Agent 2a (dead code): <count> findings, IDs 0300-03xx
Agent 2b (console): <count> findings, IDs 0400-04xx
Agent 2c (testid): <count> findings, IDs 0500-05xx

No SPA code touched; fixes pending Gates 2a/2b/2c approval.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.1: Gate 2a — Dead code batch preview

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\approvals\2026-04-09-batch-02-phase2a-deadcode.md`

- [ ] **Step 1: Build the batch preview doc**

Read `findings.json` for all `phase=phase-2` and `category=dead-code` findings. Split into two sub-groups:

- **Auto-fix sub-group** (in-file cleanups, tier=auto-fix) — presented as a single list for bulk approval
- **Destructive sub-group** (file/folder deletes, tier=batch, noted as DESTRUCTIVE) — presented line-by-line for explicit approval

Write to `approvals/2026-04-09-batch-02-phase2a-deadcode.md`:

```
# Batch 02 — Phase 2a Dead Code

## Part A: Auto-fix (in-file cleanups) — <N> findings

Summary: unused imports / unused state / dead functions. Bulk preview only.

| ID | File | Line | Change |
|---|---|---|---|
| 0301 | src/portalApi.js | 45 | remove unused import `formatDate` |
| 0302 | src/App.jsx | 112 | remove unused state `[debugOpen, setDebugOpen]` |
| ... | | | |

Approval: reply `approve batch 02a` to execute all, or `approve 0301,0303` for subset.

## Part B: Destructive (file/folder deletes) — <N> findings

**These ESCALATE per spec §7.3. Each line-item needs explicit approval.**

### 0350 — DELETE src/_archive/ folder
Evidence: no non-archive file imports anything from _archive/. Verified by grep.
Files inside:
- _archive/NewContractForm.jsx
- _archive/NewContractWizard.jsx
- _archive/Shell.jsx
Action: `rm -rf src/_archive/`
Decision? [approve / reject / defer]

### 0351 — DELETE src/AppRouter.jsx
Evidence: src/main.jsx imports from `./screens/AppRouter`, not `./AppRouter`. Verified.
Action: `rm src/AppRouter.jsx`
Decision? [approve / reject / defer]

### 0352 — DELETE src/ContractsList.jsx
Evidence: no file imports `./ContractsList` — all imports use `./screens/ContractList`. Verified.
Action: `rm src/ContractsList.jsx`
Decision? [approve / reject / defer]

... (repeat per destructive finding)
```

- [ ] **Step 2: Present batch to operator; collect decisions**

Post the doc; wait for operator replies per part and per line item.

- [ ] **Step 3: Apply in-file auto-fix cleanups (if Part A approved)**

For each approved auto-fix finding: read the file, apply the edit using Edit tool. For unused imports: remove the import line. For unused state: remove the `useState` declaration. For dead functions: remove the function declaration entirely.

After all cleanups, build:
```bash
cd C:/DCFG/spa/dcfg-shell
npm run build
```
Expected: build succeeds. If new warnings/errors: halt, investigate.

- [ ] **Step 4: Apply approved destructive operations**

For each approved destructive finding:
```bash
# Example for 0350
rm -rf C:/DCFG/spa/dcfg-shell/src/_archive/

# Example for 0351
rm C:/DCFG/spa/dcfg-shell/src/AppRouter.jsx

# Example for 0352
rm C:/DCFG/spa/dcfg-shell/src/ContractsList.jsx
```

After each delete, run `npm run build` to confirm no remaining imports broke.

**If build fails after a delete:** the delete was wrong. `git restore` the file, mark the finding `status=rejected-build-broke`, escalate.

- [ ] **Step 5: Update findings.json**

For each applied finding: `status=fixed`, `fixedAt=<iso>`, `approvedIn=batch 02a`.

- [ ] **Step 6: Commit Phase 2a results**

```bash
cd C:/dcfg
git add spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/approvals/2026-04-09-batch-02-phase2a-deadcode.md
git commit --only spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/approvals/2026-04-09-batch-02-phase2a-deadcode.md -m "code-review: batch 02 Phase 2a dead-code applied"
```

Back-fill fixCommit SHA per Task 1.3 Step 5 pattern.

Update README Gate Log row `2a`.

---

### Task 2.2: Gate 2b — Console pollution batch preview

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\approvals\2026-04-09-batch-03-phase2b-console.md`

- [ ] **Step 1: Build the batch preview doc** (same structure as Task 2.1 Step 1 but for phase-2 console-pollution findings)

```
# Batch 03 — Phase 2b Console Pollution

## Findings — <N>

| ID | File | Line | Current | Action |
|---|---|---|---|---|
| 0401 | src/portalApi.js | 178 | console.log('apiGet', uri) | delete |
| 0402 | src/App.jsx | 56 | console.warn('FLAG:', flag) | delete |
| 0403 | src/Toast.jsx | 45 | console.error(err) | KEEP (Toast exception) |
| ... | | | | |

Approval: `approve batch 03` or subset.
```

- [ ] **Step 2: Present + collect decisions**

- [ ] **Step 3: Apply deletions**

For each approved finding: read file, delete the exact line using the Edit tool with `old_string` including enough surrounding context.

After all: `npm run build` — expect clean build, no new warnings.

- [ ] **Step 4: Update findings.json + commit**

Same pattern as Task 2.1 Steps 5-6.

```bash
git commit --only spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/approvals/2026-04-09-batch-03-phase2b-console.md -m "code-review: batch 03 Phase 2b console pollution removed"
```

Update README Gate Log row `2b`.

---

### Task 2.3: Gate 2c — testid batch preview

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\approvals\2026-04-09-batch-04-phase2c-testid.md`

- [ ] **Step 1: Build the batch preview doc**

```
# Batch 04 — Phase 2c data-testid Golden Rule

## Findings — <N>

Grouped by file for operator scanning:

### src/screens/CustomerList.jsx
| ID | Line | Element | Proposed testid |
|---|---|---|---|
| 0501 | 45 | <button onClick={newCustomer}> | customer-list-new-btn |
| 0502 | 89 | <input type="search"> | customer-list-search-input |
...

### src/screens/ContractList.jsx
...

Approval: `approve batch 04` for all, or subset.
```

- [ ] **Step 2: Present + collect**

- [ ] **Step 3: Apply testid insertions**

For each approved finding: read file, use Edit tool with exact `old_string` and `new_string` from the agent's finding (`old_string` is the current line without testid, `new_string` is the same line with ` data-testid="..."` inserted in the right spot).

- [ ] **Step 4: Build + commit**

```bash
cd C:/DCFG/spa/dcfg-shell
npm run build
```
Expected: clean build.

```bash
cd C:/dcfg
git commit --only spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/approvals/2026-04-09-batch-04-phase2c-testid.md -m "code-review: batch 04 Phase 2c data-testid golden rule applied"
```

Update README Gate Log row `2c`.

---

### Task 2.4: Gate 2d — Phase 2 smoke

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\smoke-runs\batch-02-03-04\` (combined Playwright output)

- [ ] **Step 1: Deploy to Test**

Same as Task 1.4 Step 1 — capture initial pac index, switch to Test [2], build + upload, restore to initial index, clear Test portal cache, confirm.

- [ ] **Step 2: Run nav-smoke on Test**

```bash
cd C:/DCFG/spa/dcfg-shell
npx playwright test --project=test-env specs/nav-smoke.spec.ts
```
Expected: 9 tests green.

- [ ] **Step 3: Run nav-smoke on Prod (read-only)**

```bash
npx playwright test --project=prod-readonly specs/nav-smoke.spec.ts
```
Expected: 9 tests green (Prod is still the pre-review build; only Test has the Phase 2 edits).

- [ ] **Step 4: Archive traces**

```bash
mkdir -p C:/dcfg/docs/code-review-2026-04-09/smoke-runs/batch-02-03-04
cp -r C:/DCFG/spa/dcfg-shell/playwright-report C:/dcfg/docs/code-review-2026-04-09/smoke-runs/batch-02-03-04/
cp -r C:/DCFG/spa/dcfg-shell/test-results C:/dcfg/docs/code-review-2026-04-09/smoke-runs/batch-02-03-04/
```

- [ ] **Step 5: Mark Phase 2 findings verified**

For every Phase 2 finding with `status=fixed`, update to `status=verified`, `verifiedAt=<iso>`.

- [ ] **Step 6: Handle smoke failure (rollback)**

If any smoke failed:
1. Identify which batch most likely caused the regression (dead code / console / testid)
2. `git revert` the specific batch commit
3. Rebuild + redeploy Test
4. Re-run smoke — must go green
5. Mark rolled-back findings back to `status=open`
6. Escalate with failure evidence

- [ ] **Step 7: Commit Phase 2 closure**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/smoke-runs/batch-02-03-04/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/README.md
git commit --only docs/code-review-2026-04-09/smoke-runs/batch-02-03-04/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/README.md -m "$(cat <<'EOF'
code-review: Phase 2 smoke green (Gate 2d)

Playwright nav-smoke green on Test and Prod after batches 02/03/04.
Dead code / console / testid fixes verified.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Mark Phase 2 complete in README + session-state**

Edit README: `- [x] Phase 2 — complete YYYY-MM-DD`
Edit session-state: "To Resume" → "Phase 3 — screen audit (9 waves); next task 3.0"

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "code-review: Phase 2 complete"
```

**End of Chunk 4.** Chunk 5 covers Phase 3 (screen audit, 9 waves).

---

## Chunk 5 — Phase 3: Screen audit pass (9 waves)

**Chunk goal:** Deep per-screen audit of all non-shared files in customer-journey order. Parallel subagents per wave (6-8 concurrent per wave). Each wave ends with a consolidated wave summary (Gate 3.N). **No fixes during Phase 3** — findings only. Fixes happen in Phase 5.

### Task 3.0: Per-wave template (reusable across all 9 waves)

Every wave follows the same pattern. The wave-specific file lists are in Tasks 3.1-3.9. For each wave, run the following steps. Finding ID ranges are per-wave as documented in §5.3 of the spec (0600-0699 for wave 1, etc.).

**Wave template steps** (applied to each wave in Tasks 3.1-3.9):

- [ ] **WT-1: Dispatch parallel audit agents for the wave**

For a wave with N files, dispatch N Agent tool calls **in the same assistant message** so they run concurrently. Each agent audits ONE file against all remaining categories (3, 4, 5, 6, 7, 8, 8a, 8b, 9, 10, 11-non-testid, 12) — catalog-only, no fixes.

**Per-agent prompt template** (fill in `<FILE>`, `<WAVE_NUMBER>`, `<ID_RANGE_START>`, `<ID_RANGE_END>`):

```
You are a Phase 3 Wave <WAVE_NUMBER> screen audit agent for the DCFG SPA code review.

**Spec:** C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md §3, §4.4
**Plan:** C:\dcfg\docs\superpowers\plans\2026-04-09-spa-review-cleanup.md Phase 3 / Chunk 5

**Your file:** C:\DCFG\spa\dcfg-shell\src\<FILE>
**Your finding ID range:** CR-2026-04-09-<ID_RANGE_START> through <ID_RANGE_END>. HALT if you exceed.

**Categories to apply:**
- 3 (error handling) — missing try/catch on portalApi calls; no toast.show('err') on catch; unhandled promise rejection
- 4 (accessibility) — missing alt, aria-label, keyboard focus, label association, color contrast
- 5 (loading/empty states) — missing spinner during in-flight ops; missing empty-state messaging on lists; buttons not disabled during submit
- 6 (performance) — re-render storms, missing useMemo/useCallback, N+1 apiGet, searchFields inline-literal cache miss
- 7 (visual consistency) — badge class usage, typography, button styles vs DCFG_Component_Library.md
- 8 (data integrity) — correct dcfg_* field names, correct EntitySets.*, createDocumentRequest not callFlow, correct enum values, loadConfig not hardcoded URLs
- 8a (Web API $select safety) — every apiGet/raw fetch on explicit-list tables must have $select (see parity-report.json for which tables are explicit)
- 8b (@odata.bind coverage) — every POST/PATCH with field@odata.bind requires the bind column in the target env's fields list
- 9 (auth/role checks) — isAdmin/isManager/hasRole coverage; admin paths exposed; action buttons visible to wrong roles
- 10 (test coverage) — vitest test for this screen? (catalog-only; no fix)
- 11 non-testid (handoff cleanliness) — FieldName visibility; hardcoded URLs; hardcoded magic numbers that should use loadConfig
- 12 (bundle size) — unused deps referenced by this file (catalog-only; no fix)

**Skip categories 1, 2, 11-testid** — handled in Phase 2.

**Rules:**
- READ-ONLY audit. Do NOT edit the file.
- Only catalog findings. DO NOT propose code. Fixes happen in Phase 5.
- Every finding gets: full JSON object matching schema §5.2.
- phase="phase-3", agent="phase-3-wave-<WAVE_NUMBER>-<FILE>", status="open"
- If the file also imports from shared modules, do NOT re-flag issues already found in Phase 1 — check findings.json for existing phase-1 findings before filing.

**Deliverables:**
1. Append findings to findings.json (IDs in your range)
2. Write C:\dcfg\docs\code-review-2026-04-09\by-screen\<FILE_BASENAME>.json with this file's findings only
3. Terse chat summary: count per category, top 3 highest-severity items

Begin.
```

- [ ] **WT-2: Wait for all wave agents to return + validate**

When all N agents return:
```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```
Expected: 0 errors, finding count increased by ~(N agents × average-findings-per-file).

Confirm every new finding has `file` matching the expected wave file list.

- [ ] **WT-3: Consolidate wave output to a wave summary**

Write `C:\dcfg\docs\code-review-2026-04-09\waves\wave-<NN>-<name>.md`:

```markdown
# Wave <NN> — <name>

**Files audited:** <N>
**Findings:** <total>
**By severity:** P0=<n>, P1=<n>, P2=<n>, P3=<n>
**By category:** 3=<n>, 4=<n>, 5=<n>, 6=<n>, 7=<n>, 8=<n>, 8a=<n>, 8b=<n>, 9=<n>, 10=<n>, 11=<n>, 12=<n>

## Top 10 highest-severity findings

| ID | File | Sev | Title |
|---|---|---|---|
| CR-2026-04-09-06XX | src/screens/CustomerList.jsx | P0 | ... |
...

## Per-file summary
| File | Findings | P0 | P1 |
|---|---|---|---|
| CustomerList.jsx | <n> | <n> | <n> |
| CustomerDetail.jsx | <n> | <n> | <n> |
...

Full detail: docs/code-review-2026-04-09/by-screen/*.json
```

- [ ] **WT-4: Commit wave output**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-screen/ docs/code-review-2026-04-09/waves/wave-<NN>-<name>.md
git commit --only docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-screen/ docs/code-review-2026-04-09/waves/wave-<NN>-<name>.md -m "code-review: Phase 3 wave <NN> <name> complete"
```

- [ ] **WT-5: Present wave summary to operator (Gate 3.N)**

Post the wave summary. Ask:
```
Gate 3.<N> — <name> wave complete.

<paste wave summary>

Options:
- `approve wave` / `yes` → proceed to next wave
- `pause` → stop here, resume next session
- `clarify <id>` → dispatch follow-up agent on specific finding
- `reject <id>` / `defer <id>` → mark finding status
```

- [ ] **WT-6: Record Gate 3.N outcome**

Update README Gate Log row `3.<N>` with date + outcome. Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/findings.json -m "code-review: Gate 3.<N> recorded"
```

---

### Task 3.1: Wave 1 — Sales (Gate 3.1)

**Finding ID range:** 0600-0699
**Files (5):**
- `src/screens/SalesDashboard.jsx`
- `src/screens/CustomerList.jsx`
- `src/screens/CustomerDetail.jsx`
- `src/screens/MsaList.jsx`
- `src/screens/MsaDetail.jsx`

Apply wave template steps WT-1 through WT-6 with these 5 files. Dispatch 5 parallel agents in one message. Wave name: `01-sales`.

---

### Task 3.2: Wave 2 — Contracts (Gate 3.2)

**Finding ID range:** 0700-0799
**Files (7):**
- `src/screens/ContractList.jsx`
- `src/screens/ContractDetail.jsx`
- `src/contracts/ContractRowDetail.jsx`
- `src/contracts/useContractData.jsx`
- `src/contracts/ViewSmartList.jsx`
- `src/contracts/ViewCustomerGroups.jsx`
- `src/contracts/ViewSplitPanel.jsx`

Apply wave template with 7 parallel agents. Wave name: `02-contracts`.

---

### Task 3.3: Wave 3 — Wizards (Gate 3.3)

**Finding ID range:** 0800-0899
**Files (3):**
- `src/NewContractWizard.jsx`
- `src/NewProposalWizard.jsx`
- `src/screens/NewRfpWizard.jsx`

Apply wave template with 3 parallel agents. Wave name: `03-wizards`.

**Extra attention:** `NewContractWizard.jsx` has a known pre-seeded finding (CR-2026-04-09-0001, line 942 stray `)}`). Confirm the agent reports it again in Wave 3 context, and mark the pre-seeded finding's `relatedFindings` to include the new wave-3 finding ID if one is filed.

---

### Task 3.4: Wave 4 — Facilities (Gate 3.4)

**Finding ID range:** 0900-0999
**Files (9):**
- `src/screens/FacilitiesDashboard.jsx`
- `src/screens/Locations.jsx`
- `src/screens/LocationDetail.jsx`
- `src/screens/Operations.jsx`
- `src/screens/CompliancePanel.jsx`
- `src/screens/Directory.jsx`
- `src/screens/MapView.jsx`
- `src/screens/VendorList.jsx`
- `src/screens/VendorDetail.jsx`

Apply wave template with 9 parallel agents. Wave name: `04-facilities`.

**Note:** 9 is the largest wave. If token budget is tight, split into two sub-waves of 5 and 4 — dispatch first group, consolidate, then second group. Maintain the same 0900-0999 ID range.

---

### Task 3.5: Wave 5 — Onboarding (Gate 3.5)

**Finding ID range:** 1000-1099
**Files (2):**
- `src/screens/Onboarding.jsx`
- `src/screens/OnboardingDetail.jsx`

Apply wave template with 2 parallel agents. Wave name: `05-onboarding`.

**Extra attention:** `OnboardingDetail.jsx` is known to be large and feature-dense (voice input, phase accordion, step editing, dirty state guard). Agent may need higher token budget.

---

### Task 3.6: Wave 6 — Programs & Projects (Gate 3.6)

**Finding ID range:** 1100-1199
**Files (7):**
- `src/screens/ProgramList.jsx`
- `src/screens/ProgramDetail.jsx`
- `src/screens/ProjectDashboard.jsx`
- `src/screens/ProjectList.jsx`
- `src/screens/ProjectDetail.jsx`
- `src/screens/RfpList.jsx`
- `src/screens/RfpDetail.jsx`

Apply wave template with 7 parallel agents. Wave name: `06-programs-projects`.

---

### Task 3.7: Wave 7 — Templates subsystem (Gate 3.7)

**Finding ID range:** 1200-1299
**Files (9):**
- `src/screens/templates/TemplateList.jsx`
- `src/screens/templates/TemplateDetail.jsx`
- `src/screens/templates/CompositeExpander.jsx`
- `src/screens/templates/FieldMappingCard.jsx`
- `src/screens/templates/FieldMappingPanel.jsx`
- `src/screens/templates/DocumentPreview.jsx`
- `src/screens/templates/fieldRegistry.js`
- `src/screens/templates/autoMapper.js`
- `src/screens/templates/useTemplateFields.js`

Apply wave template with 9 parallel agents. Wave name: `07-templates`.

**Extra attention:**
- Pre-seeded finding CR-2026-04-09-0005 (DocumentPreview.jsx + CompositeExpander.jsx column coverage) must be re-verified by the agents for those two files.
- `useTemplateFields.js` + `TemplateDetail.jsx` were edited in this session's handoff (Changes 3 + 4). The Wave 7 agents should read the current state, not assume the handoff state is current.

---

### Task 3.8: Wave 8 — Admin + SendQueue (Gate 3.8)

**Finding ID range:** 1300-1399
**Files (3):**
- `src/screens/Admin.jsx`
- `src/screens/UserRolesTab.jsx`
- `src/screens/SendQueue.jsx`

Apply wave template with 3 parallel agents. Wave name: `08-admin`.

**Extra attention:**
- `Admin.jsx` has two hotfix-adjacent callsites (lines 1883 and 2003 per the 2026-04-09 handoff). Agent should check that the Phase 0 Dataverse backports (Test/Stage) landed correctly by cross-referencing the current deployed state with `parity-report.json`. If drift exists, file a Category 8b finding.
- `Admin.jsx` is known to be very large — ensure the agent has enough token budget to walk the whole file.

---

### Task 3.9: Wave 9 — FlowMonitor (Gate 3.9)

**Finding ID range:** 1400-1499
**Files (1):**
- `src/screens/FlowMonitor.jsx`

Apply wave template with 1 agent (FlowMonitor is a single internal-tool file). Wave name: `09-flowmonitor`.

**Note:** Lower bar than other waves. FlowMonitor is internal-only; don't overinvest in Category 4 (accessibility) or Category 7 (visual consistency). Focus on Categories 3, 8, 8a, 8b, 9 (the ones that affect whether the tool actually works).

---

### Task 3.10: Phase 3 closure

- [ ] **Step 1: Validate all wave outputs**

```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```
Expected: 0 errors. Total finding count = 6 (pre-seed) + Phase 1 + Phase 2 + all 9 waves.

- [ ] **Step 2: Verify every in-scope file has a by-screen output**

Run:
```bash
pwsh -Command "Get-ChildItem C:\dcfg\docs\code-review-2026-04-09\by-screen\*.json | Select-Object Name | Sort-Object Name"
```
Cross-reference against the 46 non-shared files in scope (63 total - 17 shared). Every one should have a corresponding `.json` file.

If any file is missing from `by-screen/`: that file was not audited. Dispatch a single-agent audit targeted at the missing file before closing Phase 3.

- [ ] **Step 3: Update README Phase Status**

Edit `C:\dcfg\docs\code-review-2026-04-09\README.md`:
- Change `- [ ] Phase 3 — Screen audit (9 waves)` to `- [x] Phase 3 — complete YYYY-MM-DD`
- Append session log with counts per wave and overall total

- [ ] **Step 4: Update session-state.md**

"To Resume" → "Phase 4 — consolidation; next task 4.0"
Findings ID cursor: phase-3 ranges all closed; phase-4 cursor = 1500

- [ ] **Step 5: Commit Phase 3 closure**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "code-review: Phase 3 complete — 9 waves audited"
```

- [ ] **Step 6: Present Phase 3 summary to operator**

```
Phase 3 complete.
  Files audited: 46 (across 9 waves)
  Findings:      <total phase-3> (P0=<n>, P1=<n>, P2=<n>, P3=<n>)
  Total findings so far: <grand total>

Wave breakdown:
  Wave 1 Sales:       <n> findings
  Wave 2 Contracts:   <n>
  Wave 3 Wizards:     <n>
  Wave 4 Facilities:  <n>
  Wave 5 Onboarding:  <n>
  Wave 6 Programs/Projects: <n>
  Wave 7 Templates:   <n>
  Wave 8 Admin:       <n>
  Wave 9 FlowMonitor: <n>

Ready to proceed to Phase 4 — consolidation?
```

**End of Chunk 5.** Chunk 6 covers Phase 4 (consolidation) + Phase 5 (fix batches protocol).

---

## Chunk 6 — Phase 4 (consolidation) + Phase 5 (fix batches)

**Chunk goal:** Phase 4 runs one consolidation agent that merges all findings into a master list and produces narrative rollups. Phase 5 is iterative: for each proposed fix batch, gate → apply → smoke → verify, with rollback on smoke failure. Phase 5 runs until all P0 + P1 findings are resolved.

### Task 4.0: Dispatch consolidation agent

**Files:**
- Read: `findings.json`, `by-screen/*.json`, `by-category/01-dead-code.md`, `02-console-pollution.md`, `11-testid.md`, `waves/wave-*.md`
- Create: `docs/code-review-2026-04-09/by-category/03-error-handling.md`, `04-a11y.md`, `05-loading-empty.md`, `06-performance.md`, `07-visual.md`, `08-data-integrity.md`, `09-auth.md`, `10-test-coverage.md`, `12-bundle.md`
- Create: `docs/code-review-2026-04-09/summary.md`

- [ ] **Step 1: Verify pre-requisites**

- Phases 0-3 all marked complete in README
- `validate-findings-json.ps1` green
- `git status` clean

- [ ] **Step 2: Dispatch the consolidation agent**

Agent prompt (general-purpose, foreground):

```
You are the Phase 4 consolidation agent for the DCFG SPA code review.

**Plan:** C:\dcfg\docs\superpowers\plans\2026-04-09-spa-review-cleanup.md Phase 4 / Chunk 6
**Finding ID range:** CR-2026-04-09-1500 through 1599 (for any NEW synthesized findings you file during dedupe).

**Your job:** merge the full findings.json into reviewable rollups.

**Inputs:**
- C:\dcfg\docs\code-review-2026-04-09\findings.json (master — hundreds of findings)
- by-screen/*.json (per-screen arrays)
- by-category/01-dead-code.md, 02-console-pollution.md, 11-testid.md (Phase 2 narratives already written)
- waves/wave-*.md (Phase 3 wave summaries)

**Tasks:**
1. **Dedupe pass.** Scan findings.json for near-duplicate findings across phases (e.g., Phase 1 found a try/catch issue in portalApi.js, Phase 3 Wave 2 re-flagged the same issue because ContractDetail calls portalApi). When duplicates exist, link them via `relatedFindings`. Do NOT delete. Add a synthesized "super finding" (IDs in your range) ONLY if the operator needs to see the cross-cutting pattern.

2. **Write 9 narrative rollups** (one per category that doesn't already have a Phase 2 rollup):
   - by-category/03-error-handling.md
   - by-category/04-a11y.md
   - by-category/05-loading-empty.md
   - by-category/06-performance.md
   - by-category/07-visual.md
   - by-category/08-data-integrity.md (include 8a and 8b as subsections)
   - by-category/09-auth.md
   - by-category/10-test-coverage.md
   - by-category/12-bundle.md

   Each rollup is plain markdown with: total count, breakdown by severity, breakdown by file, top 10 findings, pattern observations, and recommended batch ordering.

3. **Write summary.md** at the root:
   - Grand total findings
   - Distribution by phase / category / severity / status
   - Top 20 most impactful findings (weighted by severity + frequency)
   - **Recommended Phase 5 batch order** — list ~15 proposed batches, each batch a coherent group of ≤15 findings, ordered by risk (lowest-risk first for early wins, highest-risk last so any rollback is contained)
   - Initial green/yellow/red verdict based on P0/P1 counts

**Rules:**
- READ-ONLY on findings.json except for setting `relatedFindings` cross-links on deduped pairs
- You may file NEW findings in 1500-1599 range ONLY for synthesized cross-cutting patterns
- No SPA code touched
- Your output is the input for Gate 4

**Deliverables:**
1. findings.json updated in place (cross-links only)
2. 9 new rollup files under by-category/
3. summary.md at the working-tree root
4. Chat summary: grand total, top 5 recommended Phase 5 batches

Begin.
```

- [ ] **Step 3: Validate consolidation output**

```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
```
Expected: 0 errors.

Spot-check: read `by-category/03-error-handling.md` and `summary.md`. Confirm they're readable and the recommended batch order makes sense.

- [ ] **Step 4: Commit Phase 4 output**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-category/ docs/code-review-2026-04-09/summary.md
git commit --only docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/by-category/ docs/code-review-2026-04-09/summary.md -m "$(cat <<'EOF'
code-review: Phase 4 consolidation complete

9 new by-category rollups written. summary.md produced with grand
totals, top-20 findings, and recommended Phase 5 batch order.
findings.json updated with relatedFindings cross-links.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.1: Gate 4 — Operator reviews consolidation

- [ ] **Step 1: Present summary.md to operator**

Post the `summary.md` content (or a truncated version if very long) along with:

```
Gate 4 — Phase 4 consolidation review.

summary.md written. Review before we start Phase 5 fix batches.

Options:
- `approve summary` → proceed to Phase 5 with the recommended batch order
- `modify batch order: <new order>` → use operator's batch order instead
- `reject batch <N>` → skip that batch entirely
- `add batch: <description>` → insert a new batch into the order
- `hold` → stop, need to think
```

- [ ] **Step 2: Record Gate 4 outcome**

Update README Gate Log row `4` with date + outcome. Append session log entry.

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md
git commit --only docs/code-review-2026-04-09/README.md -m "code-review: Gate 4 recorded — consolidation approved"
```

- [ ] **Step 3: Mark Phase 4 complete**

Edit README:
- `- [x] Phase 4 — complete YYYY-MM-DD`
- Session log entry

Edit session-state:
- "To Resume" → "Phase 5 — fix batches; next: Batch 05 per summary order"
- Findings ID cursor: phase-5 fix-forward next = 1600

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "code-review: Phase 4 complete"
```

---

### Task 5.0: Phase 5 fix-batch protocol (reusable per batch)

**Phase 5 is iterative.** For each batch in the summary's recommended order (or operator's modified order), run the following per-batch protocol. Each batch is its own Gate 5.N + Gate 5.N-smoke cycle. Numbering: batch 05 is the first Phase 5 batch, batch 06 is the second, etc. (Batches 01-04 were Phase 1 + Phase 2.)

**Reusable per-batch steps:**

- [ ] **PB-1: Pick next batch from the approved order**

From `summary.md` recommended order, take the next batch. Build its approval doc at `docs/code-review-2026-04-09/approvals/2026-04-09-batch-<NN>-<topic>.md`.

The batch doc follows the same structure as Task 1.2 Step 1: per-finding sections with current code, proposed code, rationale, risk.

**Scope rules:**
- Max 15 findings per batch (spec §4.6 heuristic)
- Never mix tiers in the same batch
- Group by category first, then by screen within category
- Include `relatedFindings` cross-links — if finding X is in this batch and finding Y is a dedupe pair, consider including Y too so fixes don't break symmetry

- [ ] **PB-2: Present batch to operator (Gate 5.N)**

Post the approval doc. Ask:

```
Gate 5.<N> — Batch <NN> <topic> — <count> findings.

Reply with:
- `approve batch` — execute all
- `approve <ids>` — execute subset
- `reject <ids>` / `defer <ids>` — skip subset
- `reject batch` — cancel
- `modify <id>: <new fix>` — operator overrides the proposed fix
- `hold` — stop, no execution yet
```

- [ ] **PB-3: Apply approved fixes**

For each approved finding:
1. Read the file at the exact line range in the batch doc
2. Verify current code matches (protect against drift — if not matching, halt, re-dispatch Gate 5.N for that finding with updated code)
3. Use Edit tool: `old_string` = current code, `new_string` = proposed (or operator-modified) code
4. If the fix involves a cross-file rename or cross-file import update, apply all related edits in this one batch (don't split into follow-ups)

After all fixes:
```bash
cd C:/DCFG/spa/dcfg-shell
npm run build
```
Expected: clean build. New warnings/errors → halt.

- [ ] **PB-4: Update findings.json**

For each applied finding: `status=fixed`, `fixedAt=<iso>`, `approvedIn=batch-<NN>`. `fixCommit` is set in PB-5.

- [ ] **PB-5: Commit + back-fill SHA**

```bash
cd C:/dcfg
git add spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/approvals/2026-04-09-batch-<NN>-<topic>.md
git commit --only spa/dcfg-shell/src/ docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/approvals/2026-04-09-batch-<NN>-<topic>.md -m "$(cat <<'EOF'
code-review: batch <NN> applied — <topic>

<N> findings fixed in <M> files per operator approval at Gate 5.<N>.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

Back-fill fixCommit SHA:

```bash
cd C:/dcfg
COMMIT=$(git log --format=%H -n 1)
pwsh -Command "
  \$path = 'C:\dcfg\docs\code-review-2026-04-09\findings.json'
  \$findings = Get-Content \$path -Raw | ConvertFrom-Json
  foreach (\$f in \$findings) {
    if (\$f.status -eq 'fixed' -and \$null -eq \$f.fixCommit -and \$f.approvedIn -match 'batch-<NN>') {
      \$f.fixCommit = '$COMMIT'
    }
  }
  \$findings | ConvertTo-Json -Depth 10 | Set-Content \$path -Encoding UTF8
"
git add docs/code-review-2026-04-09/findings.json
git commit --only docs/code-review-2026-04-09/findings.json -m "code-review: batch <NN> back-fill fixCommit SHA"
```

- [ ] **PB-6: Deploy to Test + smoke (Gate 5.N-smoke)**

Follow Task 1.4 Step 1 pattern for pac auth handling. Deploy, clear cache, confirm.

Run Playwright smoke:
```bash
cd C:/DCFG/spa/dcfg-shell
npx playwright test --project=test-env specs/nav-smoke.spec.ts
npx playwright test --project=prod-readonly specs/nav-smoke.spec.ts
```

Archive traces to `docs/code-review-2026-04-09/smoke-runs/batch-<NN>/`.

- [ ] **PB-7: If smoke fails, execute Gate 5.N-smoke failure protocol (spec §7.1.1)**

The smoke failure is classified into one of three branches:

**Branch A — Auto-rollback (default, clear cause linked to this batch):**

If the smoke failure stack trace clearly points at a file changed in this batch (or at a consumer of a file changed in this batch), proceed with auto-rollback.

**Important: pause one chat turn before executing the revert** so the operator has a single clear opportunity to intervene with `fix-forward`. Post:

```
Gate 5.<N>-smoke FAILED. Preparing auto-rollback in next turn unless you reply `fix-forward`.

Evidence:
<paste smoke failure output>

Suspected cause: batch <NN> commit <sha>
Will revert unless you reply within one turn.
```

If no `fix-forward` reply arrives, execute the rollback:

1. `git revert <commit-sha> --no-edit` — NEVER `git reset`. Revert creates a new commit.
2. Append rollback entry to `summary.md` under a `## Rollbacks` section (spec §4.6 requirement):
   ```bash
   # Append to summary.md — include batch NN, commit sha, failure evidence, resolution
   ```
3. Rebuild + redeploy Test: `npm run build && pac pages upload-code-site` (with full pac auth dance per Task 1.4 Step 1 pattern)
4. Re-run smoke — must go green on the reverted build
5. Mark batch `rolled-back` in its approval doc
6. For each finding in the batch: reset `status=open`, clear `fixedAt`, `fixCommit`, `verifiedAt`
7. Commit the status changes + summary.md rollback entry:
   ```bash
   cd C:/dcfg
   git add docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/summary.md docs/code-review-2026-04-09/approvals/2026-04-09-batch-<NN>-*.md
   git commit --only docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/summary.md docs/code-review-2026-04-09/approvals/2026-04-09-batch-<NN>-*.md -m "code-review: batch <NN> rolled back (Gate 5.<N>-smoke failure)"
   ```
8. Notify operator that rollback is complete; await direction on whether to file fix-forward or move to next batch.

**Branch B — Fix-forward override:**

If operator replies `fix-forward` during the one-turn pause:
1. Halt auto-rollback (leave the batch commit in place)
2. File a new P0 finding in range 1600-1699 describing the regression; include the smoke failure evidence
3. Insert the new finding at the top of the next batch's approval doc
4. Do NOT re-deploy Test — leave the broken build in place so the next batch can fix and redeploy together
5. Update `summary.md` Rollbacks section with a `fix-forward` entry (not a rollback entry): batch N, commit kept, regression P0 deferred to next batch

**Branch C — Unclear failure cause (spec §7.1.1 item 3):**

If the smoke failure is ambiguous — e.g., the failure stack trace does NOT clearly link to a file in this batch, OR the failure looks like a Test environment issue (auth timeout, portal 503, network flake), OR the same failure would have happened against the pre-batch build — do NOT auto-rollback. Instead:

1. Escalate per §7.3 — post evidence to operator
2. Do not revert, do not rebuild, do not advance
3. Post:
   ```
   Gate 5.<N>-smoke — UNCLEAR cause. Escalating per §7.1.1 item 3.

   Evidence:
   <paste failure>

   Initial triage:
   - <why this might not be the batch's fault>
   - <what could be investigated>

   Options:
   - `retry smoke` — re-run the same test (may clear env flake)
   - `investigate` — dispatch diagnostic agent
   - `rollback anyway` — force Branch A
   - `fix-forward` — force Branch B
   - `hold` — stop Phase 5
   ```
4. Wait for operator instruction before any code changes

- [ ] **PB-8: If smoke passed, mark findings verified**

For each finding fixed in this batch: `status=verified`, `verifiedAt=<iso>`.

Update README Gate Log rows `5.<N>` (approved) and `5.<N>-smoke` (green).

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/smoke-runs/batch-<NN>/
git commit --only docs/code-review-2026-04-09/findings.json docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/smoke-runs/batch-<NN>/ -m "code-review: batch <NN> smoke green (Gate 5.<N>-smoke)"
```

- [ ] **PB-9: Present batch-done summary to operator**

```
Batch <NN> complete.
  Applied: <n> findings
  Smoke:   green on Test + Prod
  Next:    Batch <NN+1> <topic> (<count> findings)

Continue? [yes / hold / stop-here]
```

**PB-9 is the loop point. If `yes`, go back to PB-1 with the next batch. If `hold` or `stop-here`, mark the pause in session-state.md and exit.**

---

### Task 5.N: Run batches until Phase 5 exit conditions met

**Exit conditions** (any one triggers exit):

1. Every P0 finding has `status` in `{fixed, rejected, deferred-future}`
2. Every P1 finding has `status` in `{fixed, rejected, deferred-future}`
3. Operator says `stop-here` at any PB-9 checkpoint

If exit condition 1+2 met: Phase 5 is complete.
If operator stopped early: Phase 5 is paused; session log explicitly notes which P0/P1 findings remain open and why.

- [ ] **Step 1: Run the loop**

Repeat Task 5.0 per batch from the approved summary order until exit conditions met.

- [ ] **Step 2: Close Phase 5**

When exit conditions met, validate:

```bash
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
pwsh -Command "
  \$f = Get-Content 'C:\dcfg\docs\code-review-2026-04-09\findings.json' -Raw | ConvertFrom-Json
  \$p0open = (\$f | Where-Object { \$_.severity -eq 'P0' -and \$_.status -eq 'open' }).Count
  \$p1open = (\$f | Where-Object { \$_.severity -eq 'P1' -and \$_.status -eq 'open' }).Count
  Write-Host ('P0 open: {0}, P1 open: {1}' -f \$p0open, \$p1open)
"
```
Expected: P0 open = 0, P1 open = 0 (unless operator explicitly deferred some).

Edit README: `- [x] Phase 5 — complete YYYY-MM-DD` + session log entry.
Edit session-state: "To Resume" → "Phase 6 — final validation; next task 6.0"

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "code-review: Phase 5 complete — fix batches exhausted"
```

- [ ] **Step 3: Present Phase 5 summary to operator**

```
Phase 5 complete.
  Batches run:     <N>
  Fixes applied:   <N>
  Rolled back:     <N>
  Rejected:        <N>
  Deferred:        <N>
  P0 remaining:    <N>  (should be 0 unless explicitly deferred)
  P1 remaining:    <N>

Ready for Phase 6 — final validation?
```

**End of Chunk 6.** Chunk 7 covers Phase 6 (final validation) + Definition of Done + execution handoff.

---

## Chunk 7 — Phase 6 (final validation) + DoD + Execution Handoff

**Chunk goal:** Prove the reviewed SPA is ready for external user testing on Prod. Full Playwright smoke on Test, read-only Prod nav smoke, manual operator walk, final summary, branch merge approval.

### Task 6.0: Pre-Phase-6 sanity check

- [ ] **Step 1: Confirm all prior phases closed + scan for TODOs in fix code**

Run:
```bash
cd C:/dcfg
pwsh -File "C:/dcfg/scripts/code-review/validate-findings-json.ps1"
pwsh -Command "
  \$f = Get-Content 'C:\dcfg\docs\code-review-2026-04-09\findings.json' -Raw | ConvertFrom-Json
  \$byStatus = \$f | Group-Object status | Select-Object Name, Count
  \$byStatus | Format-Table -AutoSize
  # 'approved' in this context means Gate 5 approval but fix has NOT yet landed OR smoke has not confirmed it.
  # A properly-closed finding reaches 'verified' (post-smoke) or 'fixed' (awaiting next smoke).
  # For Phase 6 entry, we require P0/P1 findings to be in terminal states: verified, rejected, or deferred-future.
  \$p0blocking = (\$f | Where-Object { \$_.severity -eq 'P0' -and \$_.status -notin @('verified','rejected','deferred-future','closed') }).Count
  \$p1blocking = (\$f | Where-Object { \$_.severity -eq 'P1' -and \$_.status -notin @('verified','rejected','deferred-future','closed') }).Count
  Write-Host ''
  Write-Host ('P0 blocking Phase 6: {0}' -f \$p0blocking)
  Write-Host ('P1 blocking Phase 6: {0}' -f \$p1blocking)
  if (\$p0blocking -gt 0 -or \$p1blocking -gt 0) {
    Write-Host 'BLOCK: Phase 6 requires all P0/P1 terminal (verified/rejected/deferred)' -ForegroundColor Red
    exit 1
  }
"

# Scan for TODO markers added during fix batches (DoD item 8)
pwsh -Command "
  \$todos = Select-String -Path 'C:\DCFG\spa\dcfg-shell\src\*' -Pattern 'TODO|FIXME|XXX|HACK' -Recurse -Include *.js,*.jsx -ErrorAction SilentlyContinue
  # Filter to TODOs introduced by this branch: check git blame for any TODO line
  if (\$todos) {
    \$todos | ForEach-Object {
      \$file = \$_.Path
      \$line = \$_.LineNumber
      \$blame = git blame -L \"\$line,\$line\" \$file 2>\$null
      if (\$blame -match 'code-review') {
        Write-Host ('TODO introduced by this review: {0}:{1}: {2}' -f \$file, \$line, \$_.Line) -ForegroundColor Yellow
      }
    }
  }
"

git status
git branch --show-current
```
Expected: P0 blocking = 0, P1 blocking = 0, clean working tree, on `code-review-2026-04-09`. Any TODO introduced by this branch should be eliminated or explicitly deferred-with-comment before Phase 6.

If any block condition trips, return to Phase 5 and close the outstanding items before proceeding.

- [ ] **Step 2: Ensure the Test deployment matches HEAD of `code-review-2026-04-09`**

Phase 5 left Test deployed with the last batch's code. That's the current HEAD commit. If any commits landed AFTER the last batch (e.g., late doc updates), redeploy.

**Capture the pac index BEFORE any switch, and restore to that captured index after** (per the pattern in Chunk 3 Task 1.4 Step 1). Do NOT hardcode the "restore" index based on CLAUDE.md — CLAUDE.md's index table is stale as of 2026-04-09.

```bash
cd C:/DCFG/spa/dcfg-shell

# Capture starting state
pac auth list
# Note which index has the (*) — that is $INITIAL_INDEX. Under verified plan env
# table (Prod=[1], Test=[2], Stage=[3]) most sessions start on [1] Prod, but
# ALWAYS check rather than assume.

# Switch to Test = [2] per plan env table
pac auth select --index 2
pac auth who                 # MUST confirm DCFGSystems-Test before next line

npm run build
pac pages upload-code-site --rootPath . --compiledPath dist

# Restore to whatever was active at start (replace the number if your starting index was 2 or 3)
pac auth select --index 1
pac auth who
```

Clear Test portal cache manually (Power Platform admin center → Power Pages → dcfg.powerappsportals.com → Site Actions → Clear cache). Operator confirms: `cache cleared`.

**Note on CLAUDE.md conflict:** CLAUDE.md states "Always restore pac auth to Test (index 1) after deploying," which assumes Test is index [1]. Under current verified indices (Prod=[1], Test=[2], Stage=[3]), that rule would restore to Prod, not Test. Follow the capture-and-restore pattern above rather than either written rule. If in doubt, ask operator.

---

### Task 6.1: Gate 6a — Final Playwright run on both environments

**Files:**
- Create: `C:\dcfg\docs\code-review-2026-04-09\smoke-runs\phase-6-final\`

**Note:** The `test-env` and `prod-readonly` projects are defined in `playwright.config.ts` created in Chunk 2 Task 0.6 Step 2. Verify the file exists before running — if Gate 0b was deferred, these projects won't exist and Phase 6 falls back to manual smoke only (Gate 6b).

- [ ] **Step 1: Run full Playwright suite on Test + archive immediately**

```bash
cd C:/DCFG/spa/dcfg-shell

# Ensure the final archive directory exists
mkdir -p C:/dcfg/docs/code-review-2026-04-09/smoke-runs/phase-6-final/test
mkdir -p C:/dcfg/docs/code-review-2026-04-09/smoke-runs/phase-6-final/prod

# Clean any leftover report from earlier batch runs
rm -rf playwright-report test-results

# Run the Test project
npx playwright test --project=test-env

# Archive Test results IMMEDIATELY (before the Prod run overwrites them)
cp -r playwright-report C:/dcfg/docs/code-review-2026-04-09/smoke-runs/phase-6-final/test/
cp -r test-results C:/dcfg/docs/code-review-2026-04-09/smoke-runs/phase-6-final/test/
```

This runs the full test-env project: `nav-smoke.spec.ts` plus any journey specs that have been promoted from `test.skip` to real implementations during Phase 5.

Expected: all tests green. Any failure here is Phase 6 blocking.

If journey specs are still all `test.skip` (normal case if Phase 5 didn't stabilize testids enough to enable them), the output will show `N passed, M skipped`. Skipped is acceptable; record the count.

- [ ] **Step 2: Run nav-smoke on Prod (read-only) + archive immediately**

```bash
cd C:/DCFG/spa/dcfg-shell

# Clean the leftover Test report before running Prod (so archives don't mix)
rm -rf playwright-report test-results

# Run the Prod project (nav-smoke only, per prod-readonly project filter)
npx playwright test --project=prod-readonly specs/nav-smoke.spec.ts

# Archive Prod results into the separate prod/ subfolder
cp -r playwright-report C:/dcfg/docs/code-review-2026-04-09/smoke-runs/phase-6-final/prod/
cp -r test-results C:/dcfg/docs/code-review-2026-04-09/smoke-runs/phase-6-final/prod/
```
Expected: all 9 Prod routes green. Prod is still the pre-review build — this confirms Prod hasn't degraded during the review window.

- [ ] **Step 3: Sanity check — confirm Prod is still on the pre-review build**

Before trusting the Prod smoke as meaningful, confirm Prod hasn't been deployed with the review branch during the review window. Run:

```bash
pwsh -File "C:/dcfg/scripts/code-review/spa-deployed-state-check.ps1"
```

Compare the output to the Phase 0 baseline from `docs/code-review-2026-04-09/spa-deployed-state.json`. Prod signatures should be unchanged. If they differ, someone deployed to Prod during the review window — flag this and halt for operator investigation.

- [ ] **Step 4: Record Gate 6a outcome**

Update README Gate Log row `6a`:
- Date
- Outcome (green/failed)
- Counts: Test passed / skipped / failed; Prod passed / skipped / failed
- Link to smoke-runs/phase-6-final/

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/smoke-runs/phase-6-final/ docs/code-review-2026-04-09/README.md
git commit --only docs/code-review-2026-04-09/smoke-runs/phase-6-final/ docs/code-review-2026-04-09/README.md -m "code-review: Gate 6a — final Playwright run"
```

- [ ] **Step 5: Handle Gate 6a failure**

**If any test failed:** do NOT proceed to Gate 6b. Instead:
1. Identify the failing test(s) and the SPA file(s) involved
2. File new P0 findings for each regression (ID range 1700+)
3. Return to Phase 5, run one more fix batch targeting the regression
4. Re-run Task 6.1 from Step 1 after the fix lands

---

### Task 6.2: Gate 6b — Manual operator smoke on Test

**This is a human step.** The plan cannot execute this automatically. The implementing agent presents the instructions and waits.

- [ ] **Step 1: Present manual smoke checklist to operator**

Post:

```markdown
## Gate 6b — Manual Operator Smoke

Please walk the customer-facing critical path on Test:
**https://dcfg.powerappsportals.com**

### Checklist

**1. Sign in**
- [ ] Login page loads
- [ ] Windows Hello / your auth flow works
- [ ] You land on Sales Dashboard

**2. Sales dashboard**
- [ ] KPI cards render with numbers (not "—" or blank)
- [ ] Recent activity list has entries
- [ ] No console errors in DevTools (F12)

**3. Customer list → detail**
- [ ] Customer list loads with data
- [ ] Search works
- [ ] Sort on at least one column works
- [ ] Click into one customer — detail page loads with all tabs (MSA, Contracts, Programs, Locations, Onboarding)

**4. New Contract Wizard (5 steps)**
- [ ] "New Contract" button opens the wizard
- [ ] Step 1 (customer/type): select a customer, pick family/type
- [ ] Step 2 (doc type): pick a document type
- [ ] Step 3 (contractor/signer): auto-fill or manual entry works
- [ ] Step 4 (Exhibit A lines): add/edit line items
- [ ] Step 5 (review): summary displays; "Submit" button enabled
- [ ] Submit → status changes to Pending/Processing in Contract List

**5. Send Queue**
- [ ] Navigate to Send Queue
- [ ] Tabs (Send / Completion) load
- [ ] At least one row shows for any recently-processed doc

**6. Administration**
- [ ] Navigate to Admin
- [ ] Open a customer's Blanket Work Order tab — create a new **blanket WO record** for that customer (validates Phase 0 bind-form hotfix on dcfg_blanket_workorder — note: this is NOT assigning a WO number, that's Send Queue's job per project memory)
- [ ] Open that customer's AP Mapping tab — add an AP code to a cost code (validates Phase 0 bind-form hotfix on dcfg_customer_ap_mapping)
- [ ] Both saves complete without 403 or toast error

**7. Onboarding**
- [ ] Navigate to Onboarding
- [ ] Open an existing case or create a new one
- [ ] Phase accordion expands; at least one step editable

**8. Locations**
- [ ] Navigate to Locations
- [ ] Map view loads
- [ ] Open a location detail; compliance tab shows certs

**9. DevTools spot-check (both tabs)**
- [ ] **Console tab** — ideally zero errors; definitely no red entries from your own SPA code
- [ ] **Network tab** — filter for `/_api/`; no 4xx or 5xx responses on any row (403 failures on Dataverse calls are often visible only in Network, not Console)

### Reply format

Reply with one of:
- `smoke green` — everything passed; OK to close Gate 6b
- `smoke yellow: <list>` — mostly green but list of minor issues (non-blocking for user testing)
- `smoke red: <list>` — critical failures; back to Phase 5 for fixes
```

- [ ] **Step 2: Record Gate 6b outcome**

Update README Gate Log row `6b` with operator's reply.

If `smoke green` or `smoke yellow: ...` with acceptable yellow items → proceed to Task 6.3.
If `smoke red: ...` → file new findings in 1700+ range, return to Phase 5.

Commit:
```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md
git commit --only docs/code-review-2026-04-09/README.md -m "code-review: Gate 6b — manual operator smoke outcome"
```

---

### Task 6.3: Finalize summary.md and generate the go/no-go verdict

**Files:**
- Update: `C:\dcfg\docs\code-review-2026-04-09\summary.md` (final version)

- [ ] **Step 1: Programmatically compute each "Ready-for-user-testing" criterion from findings.json**

Before building the narrative summary, compute the §8.1 criteria so the verdict is evidence-based, not hand-waved:

```bash
pwsh -Command "
  \$f = Get-Content 'C:\dcfg\docs\code-review-2026-04-09\findings.json' -Raw | ConvertFrom-Json
  \$crit = @{}

  # Criterion 1: Zero open P0 findings
  \$crit.p0Open = (\$f | Where-Object { \$_.severity -eq 'P0' -and \$_.status -notin @('verified','rejected','deferred-future','closed') }).Count

  # Criterion 4: No console.error findings unresolved (category 2)
  \$crit.consoleOpen = (\$f | Where-Object { \$_.categoryNumber -eq 2 -and \$_.status -notin @('verified','rejected','deferred-future','closed') }).Count

  # Criterion 5: Testid findings resolved (category 11 testid subset)
  \$crit.testidOpen = (\$f | Where-Object { \$_.categoryNumber -eq 11 -and \$_.category -match 'testid' -and \$_.status -notin @('verified','rejected','deferred-future','closed') }).Count

  # Criterion 7: No env-drift-blocked on Prod
  \$crit.envDriftProd = (\$f | Where-Object { \$_.status -eq 'env-drift-blocked' -and \$_.detail -match 'Prod' }).Count

  # Total verified vs. open
  \$crit.totalVerified = (\$f | Where-Object { \$_.status -eq 'verified' }).Count
  \$crit.totalOpen = (\$f | Where-Object { \$_.status -eq 'open' }).Count

  Write-Host '=== Ready-for-user-testing criteria ==='
  Write-Host ('Zero open P0            : ' + (if (\$crit.p0Open -eq 0) { 'PASS' } else { 'FAIL (' + \$crit.p0Open + ' open)' }))
  Write-Host ('Console category clean  : ' + (if (\$crit.consoleOpen -eq 0) { 'PASS' } else { 'FAIL (' + \$crit.consoleOpen + ' open)' }))
  Write-Host ('Testid coverage         : ' + (if (\$crit.testidOpen -eq 0) { 'PASS' } else { 'FAIL (' + \$crit.testidOpen + ' open)' }))
  Write-Host ('Prod env-drift free     : ' + (if (\$crit.envDriftProd -eq 0) { 'PASS' } else { 'FAIL (' + \$crit.envDriftProd + ' blocked)' }))
  Write-Host ''
  Write-Host ('Total verified: ' + \$crit.totalVerified)
  Write-Host ('Total still open: ' + \$crit.totalOpen)

  # Write the computed crit to a file for inclusion in summary.md
  \$crit | ConvertTo-Json | Set-Content 'C:\dcfg\docs\code-review-2026-04-09\phase-6-criteria-computed.json' -Encoding UTF8
"
```

The computed criteria feed directly into the verdict logic below.

**Verdict decision tree** (use these thresholds to pick GREEN/YELLOW/RED):
- **GREEN** if: p0Open=0 AND consoleOpen=0 AND testidOpen=0 AND envDriftProd=0 AND Gate 6a green AND Gate 6b `smoke green`
- **YELLOW** if: p0Open=0 BUT some advisory criteria failed OR Gate 6b reported `smoke yellow: ...` with non-blocking issues
- **RED** if: any of p0Open, envDriftProd > 0 OR Gate 6a or 6b failed

The agent must show its reasoning when picking the verdict — cite which criterion passed/failed.

- [ ] **Step 2: Build the final summary.md**

Overwrite `summary.md` with the Phase 6 final content:

```markdown
# DCFG SPA Code Review — Final Summary

**Date:** 2026-04-09 → <close date>
**Branch:** code-review-2026-04-09
**Spec:** docs/superpowers/specs/2026-04-09-spa-review-cleanup-design.md

## Verdict

**<GREEN | YELLOW | RED>** for external user testing on dmms1.powerappsportals.com

<one-paragraph rationale — what was fixed, what remains, operator confidence level>

## Counts

| Phase | Findings | Fixed | Rejected | Deferred | Rolled Back |
|---|---|---|---|---|---|
| Pre-seed | 6 | <n> | <n> | <n> | 0 |
| Phase 1 (shared modules) | <n> | <n> | <n> | <n> | <n> |
| Phase 2 (auto-fix) | <n> | <n> | <n> | <n> | <n> |
| Phase 3 (screen audit) | <n> | <n> | <n> | <n> | <n> |
| Phase 4 (consolidation synthesized) | <n> | <n> | <n> | <n> | <n> |
| Phase 5 (fix-forward) | <n> | <n> | <n> | <n> | <n> |
| **Total** | **<n>** | **<n>** | **<n>** | **<n>** | **<n>** |

## By severity

| Severity | Total | Verified | Deferred |
|---|---|---|---|
| P0 | <n> | <n> | <n> |
| P1 | <n> | <n> | <n> |
| P2 | <n> | <n> | <n> |
| P3 | <n> | <n> | <n> |

## Batches run

| # | Topic | Findings | Smoke | Rolled back? |
|---|---|---|---|---|
| 01 | Phase 1 shared modules | <n> | green | no |
| 02 | Phase 2a dead code | <n> | green | no |
| ... | | | | |

## Rollbacks

<list any rolled-back batches with root cause and resolution>

## Deferred items (P2/P3 or explicitly deferred P0/P1)

<list by category; these are future work>

## Yellow flags

<anything the operator should know before user testing starts, but not blocking>

## Ready-for-user-testing criteria (spec §8.1)

- [x/ ] Zero open P0 findings
- [x/ ] All wizards happy-path green
- [x/ ] DocGen V4 smoke green (or marked unverifiable)
- [x/ ] No console.error spam
- [x/ ] data-testid present on interactive elements
- [x/ ] dcfg_document_requests error_message clean
- [x/ ] No env-drift-blocked findings on Prod

## Artifacts

- Parity report: parity-report.json
- SPA bundle state: spa-deployed-state.json
- Per-screen findings: by-screen/*.json
- Per-category rollups: by-category/*.md
- Wave summaries: waves/*.md
- Approval records: approvals/*.md
- Smoke traces: smoke-runs/*
- Final Playwright: smoke-runs/phase-6-final/

## Scripts (for re-running anything)

- scripts/code-review/parity-sweep.ps1
- scripts/code-review/spa-deployed-state-check.ps1
- scripts/code-review/backport-field-list.ps1
- scripts/code-review/backport-config-value.ps1
- scripts/code-review/validate-findings-json.ps1
```

- [ ] **Step 3: Commit the final summary + computed criteria**

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/summary.md docs/code-review-2026-04-09/phase-6-criteria-computed.json
git commit --only docs/code-review-2026-04-09/summary.md docs/code-review-2026-04-09/phase-6-criteria-computed.json -m "code-review: final summary with computed go/no-go verdict"
```

---

### Task 6.4: Gate 6c — Branch merge approval

- [ ] **Step 1: Present summary.md to operator for final sign-off**

Post:

```
Gate 6c — Branch merge approval.

summary.md committed. Verdict: <GREEN | YELLOW | RED>.

Before I merge code-review-2026-04-09 into master, please read summary.md
and reply with one of:

- `merge` — approve merge to master
- `hold` — wait, want to review more
- `reject` — do not merge; branch stays open

Notes about the merge:
- Merge strategy: merge commit (not rebase) — preserves the per-batch commit history for audit
- After merge: I will tag the merge commit as `code-review-2026-04-09-complete`
- Branch stays on remote for historical reference (not deleted)
- Prod is NOT auto-deployed; the merge only lands in master. A separate deploy gate is required.
```

- [ ] **Step 2: If `merge` approved, execute merge — with divergence safety check**

```bash
cd C:/dcfg
git checkout master

# Divergence safety: fetch and check if origin is ahead of local
git fetch origin master
BEHIND=$(git rev-list --count HEAD..origin/master)
AHEAD=$(git rev-list --count origin/master..HEAD)
if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
  echo "DIVERGENCE: local master is ${AHEAD} ahead and ${BEHIND} behind origin/master"
  echo "HALT: manual rebase required before merge"
  exit 1
elif [ "$BEHIND" -gt 0 ]; then
  echo "Local master is ${BEHIND} behind origin. Fast-forwarding..."
  git pull --ff-only origin master
fi

# Now merge the review branch
git merge --no-ff code-review-2026-04-09 -m "$(cat <<'EOF'
Merge code-review-2026-04-09 into master

Full SPA code review and gated cleanup per spec
docs/superpowers/specs/2026-04-09-spa-review-cleanup-design.md

Final verdict: <GREEN | YELLOW | RED>
See docs/code-review-2026-04-09/summary.md

<Co-Authored-By trailer is optional — include only if operator wants
Claude credited on the merge commit. Default: omit for operator-led merges.>
EOF
)"
```

Tag:
```bash
git tag -a code-review-2026-04-09-complete -m "SPA code review complete - ready for user testing"
```

Do NOT push without explicit operator approval. When approved, the push is:
```bash
git push origin master
git push origin code-review-2026-04-09-complete   # the tag
```
The operator may also want to push the review branch for historical reference:
```bash
git push origin code-review-2026-04-09
```

- [ ] **Step 3: Record Gate 6c outcome + commit README**

Update README Gate Log row `6c` with date, outcome, merge SHA, and tag name. Append session log entry.

```bash
cd C:/dcfg
git add docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md
git commit --only docs/code-review-2026-04-09/README.md docs/code-review-2026-04-09/session-state.md -m "code-review: Gate 6c recorded + merge complete"
```

- [ ] **Step 4: Present final completion message**

```
DCFG SPA Code Review — COMPLETE.

Spec:    docs/superpowers/specs/2026-04-09-spa-review-cleanup-design.md
Plan:    docs/superpowers/plans/2026-04-09-spa-review-cleanup.md
Summary: docs/code-review-2026-04-09/summary.md
Branch:  code-review-2026-04-09 (merged to master as <sha>)
Tag:     code-review-2026-04-09-complete

Verdict: <GREEN | YELLOW | RED>
Total findings: <n>
Batches run: <n>
Rollbacks: <n>

Next step (not part of this review): deploy master to Prod for user testing.
Use the normal deploy protocol. Verify Prod smoke after cache clear.
```

---

## Definition of Done (cross-reference)

All of the following must be true at Phase 6 closure. Each maps to spec §8.

- [ ] DoD 1: Parity sweep clean (Phase 0 Tasks 0.1-0.3)
- [ ] DoD 2: All 63 in-scope files reviewed (Phase 1 + Phase 3; verified at Task 3.10 Step 2)
- [ ] DoD 3: Auto-fix tiers executed (Phase 2 Tasks 2.1-2.3)
- [ ] DoD 4: All P0/P1 batch-tier findings resolved (Task 6.0 Step 1 check)
- [ ] DoD 5: Test coverage cataloged (Phase 3 Category 10 findings filed)
- [ ] DoD 6: Final smoke green on both envs (Task 6.1)
- [ ] DoD 7: Manual operator smoke passed (Task 6.2)
- [ ] DoD 8: Branch clean — no uncommitted changes, no TODOs in fix code (Task 6.0 Step 1)
- [ ] DoD 9: summary.md written with verdict (Task 6.3)
- [ ] DoD 10: Operator merge sign-off (Task 6.4)

---

## Execution Handoff

**Plan complete.** Total projected: 7 chunks, ~3,200 lines, Phases 0-6, 21 guaranteed gates + 2 per Phase 5 batch (41-61 total gate interactions).

**Saved to:** `docs/superpowers/plans/2026-04-09-spa-review-cleanup.md`

**Ready to execute?**

Because this harness (Claude Code) has subagents, the execution path is:

**REQUIRED:** Use `superpowers:subagent-driven-development`.
- Fresh subagent per task + two-stage review
- Operator gates are respected (skill integrates with TaskList + approval flows)
- Do NOT execute the plan in the current session — dispatch via the execution skill

**Alternative (not recommended for this plan):** `superpowers:executing-plans` — batch execution with checkpoints. Acceptable only if the operator wants to execute manually step-by-step without subagent orchestration.

**Before execution:**
1. Verify `pac auth list` output still matches the plan's environment table — if it doesn't, update the env table before starting
2. Confirm which environment the current pac session is pointed at — this is your "initial index" for every deploy's capture-and-restore
3. Review `docs/code-review-2026-04-09/README.md` "To Resume" block — should say "Phase 0 — Task 0.0" for a fresh start
4. Confirm the operator is available for gates (this is a quality-driven, high-interaction plan; do not start execution if the operator is away)
5. Phase 0 Task 0.1 requires an active `Connect-AzAccount` session; the operator should run it once before Phase 0 starts if not already active

**Branch reminder:** All execution happens on `code-review-2026-04-09`. If it doesn't exist yet, Task 0.0 creates it.

**Session budget:** Each chunk is independent and can be paused at any gate. `session-state.md` + README "To Resume" make cross-session resume safe.

---

*End of plan.*
