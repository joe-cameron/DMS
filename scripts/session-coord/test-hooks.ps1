# scripts/session-coord/test-hooks.ps1
# Verifies the session coordinator is working: queries all 3 tables, reports state.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/lib/dataverse-auth.ps1"

# Ensure Test environment
$activeUrl = Get-ActiveOrgUrl
if ($activeUrl -notmatch 'org0c17e98d') {
    Write-Host "[test] pac auth is on: $activeUrl — switching to Test" -ForegroundColor Yellow
    pac auth select --index 2 | Out-Null
    $script:OrgUrl = $null; $script:BaseUri = $null
}
Initialize-DataverseAuth
Write-Host "[test] Target: $($script:OrgUrl)`n" -ForegroundColor Cyan

# --- 1. Session Logs ---
Write-Host "=== SESSION LOGS ===" -ForegroundColor Yellow
$logs = Invoke-DataverseGet "dcfg_session_logs?`$select=dcfg_session_id,dcfg_started_at,dcfg_ended_at,dcfg_summary,dcfg_active_branch&`$orderby=dcfg_started_at desc&`$top=5"
if ($logs.value.Count -eq 0) {
    Write-Host "  (no session logs found)" -ForegroundColor DarkGray
} else {
    foreach ($log in $logs.value) {
        $sid     = $log.dcfg_session_id
        $started = $log.dcfg_started_at
        $ended   = if ($log.dcfg_ended_at) { $log.dcfg_ended_at } else { '(active)' }
        $branch  = if ($log.dcfg_active_branch) { $log.dcfg_active_branch } else { '?' }
        $summary = if ($log.dcfg_summary) {
            $log.dcfg_summary.Substring(0, [Math]::Min(100, $log.dcfg_summary.Length))
        } else { '(no summary)' }
        Write-Host "  $sid" -ForegroundColor White
        Write-Host "    started: $started  ended: $ended  branch: $branch" -ForegroundColor DarkGray
        Write-Host "    summary: $summary" -ForegroundColor DarkGray
    }
}

# --- 2. Active Locks ---
Write-Host "`n=== ACTIVE LOCKS ===" -ForegroundColor Yellow
$nowIso = [System.Uri]::EscapeDataString((Get-Date).ToUniversalTime().ToString('o'))
$locks = Invoke-DataverseGet "dcfg_session_locks?`$select=dcfg_resource_key,dcfg_session_id,dcfg_status,dcfg_operation,dcfg_expires_at&`$filter=dcfg_status eq 100000000 and dcfg_expires_at gt $nowIso&`$top=10"
if ($locks.value.Count -eq 0) {
    Write-Host "  (no active locks)" -ForegroundColor DarkGray
} else {
    foreach ($lock in $locks.value) {
        Write-Host "  $($lock.dcfg_resource_key) -> $($lock.dcfg_session_id)" -ForegroundColor Red
        Write-Host "    op: $($lock.dcfg_operation)  expires: $($lock.dcfg_expires_at)" -ForegroundColor DarkGray
    }
}

# --- 3. Work Items ---
Write-Host "`n=== WORK ITEMS (active, by priority) ===" -ForegroundColor Yellow
$items = Invoke-DataverseGet "dcfg_session_work_items?`$select=dcfg_title,dcfg_phase,dcfg_priority,dcfg_target_env,dcfg_source,dcfg_assigned_session&`$filter=dcfg_active_flag eq true&`$orderby=dcfg_priority,dcfg_phase&`$top=20"

$phaseMap = @{ 100000000='design'; 100000001='build'; 100000002='test'; 100000003='deploy'; 100000004='done'; 100000005='blocked' }
$prioMap  = @{ 100000000='P0'; 100000001='P1'; 100000002='P2'; 100000003='P3' }
$envMap   = @{ 100000000='test'; 100000001='stage'; 100000002='prod' }

$openCount = 0
$doneCount = 0
foreach ($wi in $items.value) {
    $phase = $phaseMap[[int]$wi.dcfg_phase]
    $prio  = $prioMap[[int]$wi.dcfg_priority]
    $env   = $envMap[[int]$wi.dcfg_target_env]
    $assigned = if ($wi.dcfg_assigned_session) { " [claimed: $($wi.dcfg_assigned_session)]" } else { '' }

    $color = switch ($phase) {
        'done'    { 'DarkGray' }
        'blocked' { 'Red' }
        default   { 'White' }
    }

    Write-Host "  [$prio] $phase  $($wi.dcfg_title) -> $env$assigned" -ForegroundColor $color
    if ($phase -eq 'done') { $doneCount++ } else { $openCount++ }
}
Write-Host "`n  Total: $($items.value.Count) items ($openCount open, $doneCount done)" -ForegroundColor Cyan

# --- 4. Check if SessionStart hook created a log for this session ---
Write-Host "`n=== HOOK STATUS ===" -ForegroundColor Yellow
$sessionFile = "$env:LOCALAPPDATA/dcfg-session/current-session.json"
if (Test-Path $sessionFile) {
    $current = Get-Content $sessionFile -Raw | ConvertFrom-Json
    $hasSid = [bool]$current.sessionId
    if ($hasSid) {
        Write-Host "  SessionStart hook: FIRED" -ForegroundColor Green
        Write-Host "    sessionId:    $($current.sessionId)" -ForegroundColor DarkGray
        Write-Host "    startedAt:    $($current.startedAt)" -ForegroundColor DarkGray
        Write-Host "    sessionLogId: $($current.sessionLogId)" -ForegroundColor DarkGray
        Write-Host "    gitBranch:    $($current.gitBranch)" -ForegroundColor DarkGray
    } else {
        Write-Host "  SessionStart hook: FIRED but session file has empty fields" -ForegroundColor Yellow
    }
} else {
    Write-Host "  SessionStart hook: NOT FIRED (no $sessionFile)" -ForegroundColor Red
}

# Check heartbeat process
$hbFile = "$env:LOCALAPPDATA/dcfg-session/heartbeat.pid"
if (Test-Path $hbFile) {
    $hbPid = (Get-Content $hbFile -Raw).Trim()
    $proc  = Get-Process -Id $hbPid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  Heartbeat: RUNNING (PID $hbPid)" -ForegroundColor Green
    } else {
        Write-Host "  Heartbeat: STALE PID $hbPid (process not found)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Heartbeat: NOT RUNNING (no $hbFile)" -ForegroundColor Red
}

Write-Host "`n[test] Done" -ForegroundColor Cyan
