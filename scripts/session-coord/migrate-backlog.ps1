# scripts/session-coord/migrate-backlog.ps1
# One-time migration: imports docs/to-be-fixed.md items into dcfg_session_work_item.
# Idempotent — skips items whose title already exists (exact match on dcfg_title).
#
# Usage:
#   pwsh -NoProfile -File C:/dcfg/scripts/session-coord/migrate-backlog.ps1
#   pwsh -NoProfile -File C:/dcfg/scripts/session-coord/migrate-backlog.ps1 -DryRun

param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/lib/dataverse-auth.ps1"

# Ensure Test environment
$activeUrl = Get-ActiveOrgUrl
if ($activeUrl -notmatch 'org0c17e98d') {
    Write-Host "[migrate] pac auth is on: $activeUrl — switching to Test" -ForegroundColor Yellow
    pac auth select --index 2 | Out-Null
    $script:OrgUrl = $null; $script:BaseUri = $null
}
Initialize-DataverseAuth
Write-Host "[migrate] Target: $($script:OrgUrl)" -ForegroundColor Cyan

# --- Define backlog items ---
# Each item maps to one row in dcfg_session_work_item.
# Phase/priority assigned by human judgment based on handoff-session-2026-05-06.md context.
#
# Picklist values:
#   phase:  design=100000000, build=100000001, test=100000002, deploy=100000003, done=100000004, blocked=100000005
#   priority: P0=100000000, P1=100000001, P2=100000002, P3=100000003
#   target_env: test=100000000, stage=100000001, prod=100000002

$items = @(
    # --- DocuSign E2E (to-be-fixed #1-3) ---
    @{
        title      = 'DocuSign E2E: use real location names instead of fake E2E-DOCUSIGN-LOC'
        phase      = 100000002  # test
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #1'
        notes      = 'Test should select from existing locations, not create fake ones.'
    }
    @{
        title      = 'DocuSign E2E: add console logging to OOXML anchor injection'
        phase      = 100000001  # build
        priority   = 100000003  # P3
        target_env = 100000002  # prod
        source     = 'to-be-fixed #2'
        notes      = 'injectScalarFields() does not log docusign-type field replacements.'
    }
    @{
        title      = 'SharePoint upload CORS fix: proxy through Azure Function'
        phase      = 100000000  # design
        priority   = 100000000  # P0
        target_env = 100000002  # prod
        source     = 'to-be-fixed #3'
        notes      = 'Direct SharePoint upload always fails — CORS blocks _api/contextinfo. Add /upload endpoint to Azure Function that accepts blob + path, uses Graph token. Eliminates CORS error and race condition.'
    }

    # --- Rebuild (to-be-fixed #4-7) ---
    @{
        title      = 'Rebuild: 2 column creates failed in Phase 3'
        phase      = 100000005  # blocked
        priority   = 100000001  # P1
        target_env = 100000000  # test
        source     = 'to-be-fixed #4'
        notes      = 'Check docs/baseline-2026-04-18/phase3-schema-results.json for details.'
    }
    @{
        title      = 'Rebuild: 7 lookup columns skipped — need relationship creation first'
        phase      = 100000005  # blocked
        priority   = 100000001  # P1
        target_env = 100000000  # test
        source     = 'to-be-fixed #5'
        notes      = 'Relationships must be created before lookup columns.'
    }
    @{
        title      = 'Rebuild: connection references require manual designer wiring'
        phase      = 100000005  # blocked
        priority   = 100000001  # P1
        target_env = 100000000  # test
        source     = 'to-be-fixed #6'
        notes      = 'DE-019: no API path. Human must open each flow in Power Automate designer.'
    }
    @{
        title      = 'Rebuild: table ownership mismatch on dcfg_prime_contract'
        phase      = 100000005  # blocked
        priority   = 100000001  # P1
        target_env = 100000000  # test
        source     = 'to-be-fixed #7'
        notes      = 'DE-018: blocks solution import. Operator decision needed.'
    }

    # --- Pipeline Hygiene (to-be-fixed #8-9) ---
    @{
        title      = 'MSA Composer: field values append across runs instead of resetting'
        phase      = 100000001  # build
        priority   = 100000001  # P1
        target_env = 100000002  # prod
        source     = 'to-be-fixed #8'
        notes      = 'React component state not resetting on re-navigation to /#/msa/new. Ensure all composer state resets on mount.'
    }
    @{
        title      = 'Send Queue: stale data from failed/previous runs persists'
        phase      = 100000000  # design
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #9'
        notes      = 'Need: cleanup mechanism for stale rows (age > N days), E2E test tagging, consider admin purge action.'
    }

    # --- SPA Features (to-be-fixed #10-11) ---
    @{
        title      = 'SALES: Resource Library nav item with card grid'
        phase      = 100000000  # design
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #10'
        notes      = 'New nav item under SALES. Page with card grid of leave-behinds and sales tools.'
    }
    @{
        title      = 'Admin: menu visibility controls per role'
        phase      = 100000000  # design
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #11'
        notes      = 'Admin screen toggles nav item visibility. Needs menu config table or dcfg_configs entries that NavPanel reads at boot.'
    }

    # --- Vendor Assignment (to-be-fixed #12) ---
    @{
        title      = 'Customer Detail: vendor slideout needs distance search controls'
        phase      = 100000000  # design
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #12'
        notes      = 'Missing: customer location dropdown, trade filter, radius selector, Search button — same controls as main Vendors page.'
    }

    # --- Trade Cost Analysis (to-be-fixed #13-14) — DONE per handoff-2026-05-06 ---
    @{
        title      = 'Trade Cost Analysis: exclude LumpSum line items'
        phase      = 100000004  # done
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #13'
        notes      = 'DONE 2026-05-06. Deployed to Prod. UOM 100000004 filtered out entirely.'
    }
    @{
        title      = 'Trade Cost Analysis: group by description + UOM'
        phase      = 100000004  # done
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #14'
        notes      = 'DONE 2026-05-06. Deployed to Prod. Grouped by trade -> description + UOM.'
    }

    # --- Scheduler (to-be-fixed #15) ---
    @{
        title      = 'Scheduler: embedded map not showing — replace OSM iframe with Google Maps'
        phase      = 100000001  # build
        priority   = 100000002  # P2
        target_env = 100000002  # prod
        source     = 'to-be-fixed #15'
        notes      = 'OSM iframe blocked by Power Pages CSP. Google Maps API key exists in site setting. Source: dcfg-resources/spa/src/App.jsx lines 1937-1951.'
    }
)

# --- Query existing work items to avoid duplicates ---
Write-Host "[migrate] Checking existing work items..." -ForegroundColor Cyan
$filter = "dcfg_active_flag eq true"
$select = "dcfg_title,dcfg_session_work_itemid"
$existing = Invoke-DataverseGet "dcfg_session_work_items?`$filter=$filter&`$select=$select&`$top=500"
$existingTitles = @{}
foreach ($row in $existing.value) {
    $existingTitles[$row.dcfg_title] = $row.dcfg_session_work_itemid
}
Write-Host "  Found $($existingTitles.Count) existing work items" -ForegroundColor DarkGray

# --- Create items ---
$created = 0
$skipped = 0
$failed  = 0

foreach ($item in $items) {
    $title = $item.title
    if ($existingTitles.ContainsKey($title)) {
        Write-Host "  SKIP: $title (already exists)" -ForegroundColor Yellow
        $skipped++
        continue
    }

    $body = @{
        dcfg_title      = $title
        dcfg_phase      = $item.phase
        dcfg_priority   = $item.priority
        dcfg_target_env = $item.target_env
        dcfg_source     = $item.source
        dcfg_notes      = $item.notes
        dcfg_active_flag = $true
    }
    # Items marked done get a completed_on date
    if ($item.phase -eq 100000004) {
        $body['dcfg_completed_on'] = '2026-05-06T00:00:00Z'
    }

    if ($DryRun) {
        Write-Host "  DRY RUN: would create '$title'" -ForegroundColor Magenta
        $created++
        continue
    }

    try {
        Invoke-DataversePost 'dcfg_session_work_items' $body | Out-Null
        Write-Host "  CREATED: $title" -ForegroundColor Green
        $created++
    } catch {
        Write-Host "  FAILED: $title — $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`n[migrate] Done: $created created, $skipped skipped, $failed failed" -ForegroundColor Cyan
