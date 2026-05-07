# scripts/session-coord/session-start.ps1
# SessionStart hook — runs when Claude Code begins a session.
# Reads JSON from stdin (event payload — content ignored, only event type matters).
# Outputs a context block to stdout for Claude to consume.
#
# On any error: write warning to stderr, exit 0 (never block session start).

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

try {
    # Read stdin (ignore content — we just need to drain it)
    $null = $input | Out-String

    # Load libraries
    . "$PSScriptRoot/lib/dataverse-auth.ps1"
    . "$PSScriptRoot/lib/session-ops.ps1"
    . "$PSScriptRoot/lib/lock-ops.ps1"

    Initialize-DataverseAuth

    # -----------------------------------------------------------------------
    # 1. Generate session ID
    # -----------------------------------------------------------------------
    $nowDt     = Get-Date
    $nowStr    = $nowDt.ToString('yyyyMMddTHHmmss')
    $randHex   = [System.BitConverter]::ToString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(2)).Replace('-', '').ToLower()
    $sessionId = "$env:COMPUTERNAME-$PID-$nowStr-$randHex"

    # -----------------------------------------------------------------------
    # 2. Create $env:LOCALAPPDATA/dcfg-session/ directory
    # -----------------------------------------------------------------------
    $sessionDir  = Join-Path $env:LOCALAPPDATA 'dcfg-session'
    $sessionFile = Join-Path $sessionDir 'current-session.json'
    if (-not (Test-Path $sessionDir)) {
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    }

    # -----------------------------------------------------------------------
    # 3. Capture git state
    # -----------------------------------------------------------------------
    $gitBranch = ''
    $gitStatus = ''
    try {
        $gitBranch = (git -C C:/dcfg branch --show-current 2>&1) -join ''
        $rawStatus = git -C C:/dcfg status --porcelain 2>&1
        $gitStatus = ($rawStatus -join "`n").Trim()
    } catch {}

    # -----------------------------------------------------------------------
    # 4. Create Dataverse session log row
    # -----------------------------------------------------------------------
    $logId = $null
    try {
        $logId = New-SessionLogEntry -SessionId $sessionId
    } catch {
        Write-Warning "[session-start] Could not create session log: $_" | Out-Null
    }

    # -----------------------------------------------------------------------
    # 5. Save session JSON
    # -----------------------------------------------------------------------
    $sessionObj = @{
        sessionId    = $sessionId
        sessionLogId = $logId
        startedAt    = $nowDt.ToUniversalTime().ToString('o')
        gitBranch    = $gitBranch
        gitStatus    = $gitStatus
    }
    $sessionObj | ConvertTo-Json -Depth 5 | Set-Content -Path $sessionFile -Encoding UTF8

    # -----------------------------------------------------------------------
    # 6. Query recent session logs (top 3)
    # -----------------------------------------------------------------------
    $recentLogs = @()
    try { $recentLogs = Get-RecentSessionLogs -Top 3 } catch {}

    # -----------------------------------------------------------------------
    # 7. Query active work items (top 10) + total count
    # -----------------------------------------------------------------------
    $workItems  = @()
    $totalCount = 0
    try { $workItems  = Get-ActiveWorkItems -Top 10 } catch {}
    try { $totalCount = Get-WorkItemCount } catch {}

    # -----------------------------------------------------------------------
    # 8. Query active locks
    # -----------------------------------------------------------------------
    $activeLocks = @()
    try {
        $lockResult  = Invoke-DataverseGet "dcfg_session_locks?`$filter=dcfg_status eq 100000000&`$select=dcfg_session_lockid,dcfg_resource_key,dcfg_session_id,dcfg_operation,dcfg_locked_at"
        $activeLocks = $lockResult.value
    } catch {}

    # -----------------------------------------------------------------------
    # 9. Spawn heartbeat.ps1 as background process
    # -----------------------------------------------------------------------
    $heartbeatScript = Join-Path $PSScriptRoot 'heartbeat.ps1'
    $parentPid = $PID
    try {
        $parentProc = Get-Process -Id $PID -ErrorAction SilentlyContinue
        if ($parentProc -and $parentProc.Parent) {
            $parentPid = $parentProc.Parent.Id
        }
    } catch {}

    $orgUrl = $script:OrgUrl
    $hbPidFile = Join-Path $sessionDir 'heartbeat.pid'
    try {
        $hbProc = Start-Process pwsh -ArgumentList @(
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle', 'Hidden',
            '-File', $heartbeatScript,
            '-SessionId', $sessionId,
            '-ParentPid', $parentPid,
            '-OrgUrl', $orgUrl
        ) -WindowStyle Hidden -PassThru -ErrorAction Stop
        $hbProc.Id | Set-Content -Path $hbPidFile -Encoding UTF8 -Force
    } catch {
        Write-Warning "[session-start] Could not spawn heartbeat: $_" | Out-Null
    }

    # -----------------------------------------------------------------------
    # 10. Format and output context block
    # -----------------------------------------------------------------------

    # --- Last session summary ---
    $lastSessionLine = '(no previous session)'
    if ($recentLogs -and $recentLogs.Count -gt 0) {
        # Skip the first one (that's the one we JUST created)
        $prev = $null
        foreach ($lg in $recentLogs) {
            if ($lg.dcfg_session_id -ne $sessionId) { $prev = $lg; break }
        }
        if ($prev) {
            $prevSummary = if ($prev.dcfg_summary) { $prev.dcfg_summary } else { '(no summary)' }
            $prevBranch  = if ($prev.dcfg_active_branch) { $prev.dcfg_active_branch } else { 'unknown' }
            $prevUncomm  = if ($prev.dcfg_uncommitted_changes) { ($prev.dcfg_uncommitted_changes -replace '\r?\n', ' ').Substring(0, [Math]::Min(200, $prev.dcfg_uncommitted_changes.Length)) } else { 'none' }

            # Time ago
            $timeAgo = ''
            if ($prev.dcfg_started_at) {
                try {
                    $prevTime  = [System.DateTimeOffset]::Parse($prev.dcfg_started_at).ToUniversalTime()
                    $diffSecs  = [Math]::Max(0, [int]([System.DateTimeOffset]::UtcNow - $prevTime).TotalSeconds)
                    if ($diffSecs -lt 3600)      { $timeAgo = "$([int]($diffSecs/60))m ago" }
                    elseif ($diffSecs -lt 86400) { $timeAgo = "$([int]($diffSecs/3600))h ago" }
                    else                          { $timeAgo = "$([int]($diffSecs/86400))d ago" }
                } catch { $timeAgo = '?' }
            }

            $lastSessionLine = "Last session ($timeAgo): $prevSummary"
            $lastSessionLine += "`n  Uncommitted: $prevUncomm"
            $lastSessionLine += "`n  Branch: $prevBranch"
        }
    }

    # --- Backlog summary ---
    $phaseBreakdown = @{}
    foreach ($item in $workItems) {
        $phaseVal = $item.dcfg_phase
        $phaseKey = if ($script:PhaseLabels.ContainsKey($phaseVal)) { $script:PhaseLabels[$phaseVal] } else { "phase$phaseVal" }
        if ($phaseBreakdown.ContainsKey($phaseKey)) { $phaseBreakdown[$phaseKey]++ }
        else { $phaseBreakdown[$phaseKey] = 1 }
    }
    $phaseStr = ($phaseBreakdown.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Value) $($_.Name)" }) -join ', '
    if (-not $phaseStr) { $phaseStr = 'none' }

    $backlogHeader = "Backlog: $totalCount items ($phaseStr) — showing top 10"

    $backlogLines = @()
    foreach ($item in $workItems) {
        $priVal    = $item.dcfg_priority
        $phaseVal2 = $item.dcfg_phase
        $envVal    = $item.dcfg_target_env
        $priLabel  = if ($script:PriorityLabels.ContainsKey($priVal))  { $script:PriorityLabels[$priVal] }  else { "pri$priVal" }
        $phLabel   = if ($script:PhaseLabels.ContainsKey($phaseVal2))  { $script:PhaseLabels[$phaseVal2] }  else { "ph$phaseVal2" }
        $envLabel  = if ($null -ne $envVal -and $script:EnvLabels.ContainsKey($envVal)) { $script:EnvLabels[$envVal] } else { '---' }
        $title     = if ($item.dcfg_title) { $item.dcfg_title } else { '(untitled)' }
        $titlePad  = $title.Substring(0, [Math]::Min(38, $title.Length)).PadRight(38)
        $assignStr = if ($item.dcfg_assigned_session) { "claimed: $($item.dcfg_assigned_session.Substring(0,[Math]::Min(12,$item.dcfg_assigned_session.Length)))..." } else { '(unclaimed)' }
        $backlogLines += "  $($priLabel.PadRight(2)) $($phLabel.PadRight(6)) $titlePad -> $($envLabel.PadRight(5)) ($assignStr)"
    }

    # --- Active locks ---
    $lockLines = @()
    if ($activeLocks -and $activeLocks.Count -gt 0) {
        foreach ($lk in $activeLocks) {
            $lockLines += "  $($lk.dcfg_resource_key) — held by $($lk.dcfg_session_id) [$($lk.dcfg_operation)]"
        }
    }
    $locksStr = if ($lockLines.Count -gt 0) { $lockLines -join "`n" } else { '  none' }

    # --- Emit context block ---
    $output = @"
[SESSION COORDINATOR]
Session: $sessionId
$lastSessionLine
$backlogHeader
$($backlogLines -join "`n")
Active locks:
$locksStr
"@

    Write-Output $output

} catch {
    [Console]::Error.WriteLine("[session-start] WARNING: hook error (non-blocking): $_")
}

exit 0
