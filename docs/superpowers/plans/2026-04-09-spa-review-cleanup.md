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

**End of Chunk 1.** Chunk 2 covers Playwright scaffolding (Tasks 0.5, 0.6) + Phase 0 closure.

---
