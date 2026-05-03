. "C:/DCFG/PowerApps-Samples/dataverse/webapi/PS/Core.ps1"
Connect "https://org06f5de0b.crm.dynamics.com/"

$headers = $baseHeaders.Clone()
$headers["MSCRM.SuppressDuplicateDetection"] = "true"

# dcfg_kind: 100000000=lesson, 100000001=pattern, etc. Using 100000001 for rules/patterns
$kindPattern = 100000001

function Upsert-Knowledge($name, $title, $body) {
    $encodedFilter = [System.Uri]::EscapeDataString("dcfg_name eq '$name'")
    $existing = Invoke-RestMethod -Uri "$baseURI/dcfg_knowledges?`$filter=$encodedFilter&`$select=dcfg_knowledgeid" -Method Get -Headers $baseHeaders

    $record = @{
        dcfg_name = $name
        dcfg_title = $title
        dcfg_body = $body
        dcfg_kind = $kindPattern
        dcfg_active_flag = $true
    } | ConvertTo-Json -Depth 5

    if ($existing.value.Count -gt 0) {
        $id = $existing.value[0].dcfg_knowledgeid
        Invoke-RestMethod -Uri "$baseURI/dcfg_knowledges($id)" -Method Patch -Headers $headers -Body $record -ContentType "application/json"
        Write-Host "  Updated: $title" -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$baseURI/dcfg_knowledges" -Method Post -Headers $headers -Body $record -ContentType "application/json" | Out-Null
        Write-Host "  Created: $title" -ForegroundColor Cyan
    }
}

Write-Host "=== Pushing rules to Dataverse brain ===" -ForegroundColor Cyan

Upsert-Knowledge "system_boot_sequence" "DCFG AI Agent Boot Sequence" @"
Every AI session working with DCFG must execute these steps before doing anything:

1. Read docs/to-be-fixed.md — the running SPA issues/todos list. Know what is outstanding.
2. Read the most recent docs/handoff-*.md — context from the last session.
3. If using pac CLI, run pac auth list — verify which environment is active. Indices shift.
4. Check docs/baseline-2026-04-16/ for current Prod schema state.
5. Report what you found before proceeding.

If an agent skips this sequence, it is operating blind and will make avoidable mistakes.
"@

Upsert-Knowledge "system_rules_never_do" "DCFG Rules - What You Never Do" @"
1. Never write to Prod (DCFGSystems-Prod / org06f5de0b.crm.dynamics.com) without explicit operator authorization.
2. Never hard delete. Use dcfg_active_flag = false (soft delete). Always.
3. Never write to UpKeep. Read-only integration.
4. Never use customer names (Bancroft, PennReach) or people names (Tyler, Bill) in production code, UI strings, or schema.
5. Never use curl.exe — blocked by endpoint security. Use Invoke-RestMethod in pwsh.
6. Never trust hardcoded pac auth indices — they shift. Run pac auth list every time.
7. Never use callFlow(). Use createDocumentRequest() — flows trigger from dcfg_document_requests table.
8. Never overwrite flow triggers. Three-step flow build: placeholders, manual connections, full definition.
9. Never create new tracking files without searching for existing ones first. docs/to-be-fixed.md is the todo list.
"@

Upsert-Knowledge "system_rules_always_do" "DCFG Rules - What You Always Do" @"
1. SharePoint is always the second save for any document generation. Path: DCFG_Outputs/Customer/Year/DocType.
2. Audit logging: Close/Delete/Restore operations write to dcfg_audit_logs.
3. Table permissions: Append AND AppendTo on BOTH sides of relationships.
4. PowerShell: Connect() MUST have trailing slash. Use pwsh not powershell.
5. Clear portal cache after metadata changes (site settings, table permissions, web roles).
6. Restore pac auth to Test after any Prod/Stage operation.
7. All SPA elements must have data-testid attributes. Tests use only data-testid.
8. Verbose logging on all API failures by default.
9. Before ANY SPA build: visual mockup of before/after for impacted screens. Get approval first.
10. Entity set for locations is dcfg_properties (NOT dcfg_propertys).
11. Investigate before asking. Search repo, memory, CLI output before asking the user for any data.
12. Report findings, not questions.
"@

Upsert-Knowledge "system_architecture_current" "DCFG Architecture - Current State" @"
Flow pattern: Dataverse transaction table (dcfg_document_requests), NOT HTTP triggers.
SPA function: createDocumentRequest() — never callFlow().
Config: dcfg_configs table read at boot via loadConfig() — no hardcoded URLs.
Solution name: DCFGSystemTest (all environments).
DocGen: V4 OOXML injection via jszip (Azure Function). V3 is retired.
Document storage: Templates in SharePoint DCFG_Templates. Outputs in DCFG_Outputs/Customer/Year/DocType.
SPA stack: React 16.14 + Vite 5.4 + HashRouter. Fonts: IBM Plex Sans, Fraunces, IBM Plex Mono.
Environments: Prod (org06f5de0b), Test (org0c17e98d), Stage (org88778bb0), Portal (orgf625b080 READ-ONLY).
Deploy order: Test then Stage then Prod. Operator specifies which envs per deploy.
"@

Upsert-Knowledge "system_key_file_locations" "DCFG Key File Locations" @"
SPA issues/todos: docs/to-be-fixed.md — Running list. Add here, don't create new files.
Bug tracking: docs/bugs.json
Design specs: docs/superpowers/specs/
Implementation plans: docs/superpowers/plans/
Session handoffs: docs/handoff-*.md
Prod baseline: docs/baseline-2026-04-16/ (13 JSON files)
Harvest manifest: brain/harvest-37-manifest.json (37 SharePoint project sites)
PowerShell helpers: PowerApps-Samples/dataverse/webapi/PS/Core.ps1
Graph auth: tools/path-probe/graph_auth.py (MSAL device-code)
Screen captures: docs/screen-captures/
Contract composer mockups: scratch/brook-exhibit-b/mockups/
SPA source (READ-ONLY unless authorized): spa/dcfg-shell/src/
"@

Upsert-Knowledge "system_engineering_discipline" "DCFG Engineering Discipline" @"
Simplicity: No features, abstractions, or config beyond what was asked. 200 lines that could be 50? Rewrite.
Surgical edits: Touch only what the task requires. Don't improve adjacent code. Match existing style.
Investigate then options then approval then act: Never skip steps.
Script vs Manual: Evaluate manual path first. 5-click manual task doesn't need a 200-line script.
Success criteria before execution: Transform vague asks into verifiable goals.
Loop verification locally not the deploy: The deploy is never the verification mechanism.
Bulk/repeatable work goes to haiku sub-agents: Opus stays on decisions.
"@

Write-Host "`nDone." -ForegroundColor Green
