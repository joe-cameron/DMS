# scripts/session-coord/lib/session-ops.ps1
# Session log and work item operations library for Session Coordinator.
# Dot-source this file to get session management functions.
#
# Usage:
#   . C:/dcfg/scripts/session-coord/lib/session-ops.ps1
#   $logId = New-SessionLogEntry -SessionId $id
#   $items = Get-ActiveWorkItems -Top 10

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/dataverse-auth.ps1"

# ---------------------------------------------------------------------------
# Lookup hashtables for phase / priority / env picklist values
# ---------------------------------------------------------------------------
$script:PhaseLabels = @{
    100000000 = 'design'
    100000001 = 'build'
    100000002 = 'test'
    100000003 = 'deploy'
    100000004 = 'done'
    100000005 = 'blocked'
}

$script:PriorityLabels = @{
    100000000 = 'P0'
    100000001 = 'P1'
    100000002 = 'P2'
    100000003 = 'P3'
}

$script:EnvLabels = @{
    100000000 = 'Test'
    100000001 = 'Stage'
    100000002 = 'Prod'
}

# ---------------------------------------------------------------------------
# Get-CurrentSessionId
# Reads sessionId from $env:LOCALAPPDATA/dcfg-session/current-session.json.
# Returns $null if the file is missing or malformed.
# ---------------------------------------------------------------------------
function Get-CurrentSessionId {
    $sessionPath = Join-Path $env:LOCALAPPDATA 'dcfg-session\current-session.json'
    if (-not (Test-Path $sessionPath)) { return $null }
    try {
        $obj = Get-Content $sessionPath -Raw | ConvertFrom-Json
        return $obj.sessionId
    } catch {
        Write-Warning "[session-ops] Could not parse current-session.json: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Get-CurrentSessionLogId
# Reads sessionLogId from $env:LOCALAPPDATA/dcfg-session/current-session.json.
# Returns $null if missing or malformed.
# ---------------------------------------------------------------------------
function Get-CurrentSessionLogId {
    $sessionPath = Join-Path $env:LOCALAPPDATA 'dcfg-session\current-session.json'
    if (-not (Test-Path $sessionPath)) { return $null }
    try {
        $obj = Get-Content $sessionPath -Raw | ConvertFrom-Json
        return $obj.sessionLogId
    } catch {
        Write-Warning "[session-ops] Could not parse current-session.json for sessionLogId: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Get-RecentSessionLogs
# Queries dcfg_session_logs ordered by started_at desc.
# Returns an array of log objects (up to $Top rows).
# ---------------------------------------------------------------------------
function Get-RecentSessionLogs {
    [CmdletBinding()]
    param(
        [int]$Top = 3
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $select  = 'dcfg_session_logid,dcfg_session_id,dcfg_started_at,dcfg_ended_at,dcfg_summary,dcfg_active_branch,dcfg_uncommitted_changes,dcfg_files_touched,dcfg_git_diff_stat'
    $orderby = 'dcfg_started_at desc'
    try {
        $result = Invoke-DataverseGet "dcfg_session_logs?`$select=$select&`$orderby=$orderby&`$top=$Top"
        return $result.value
    } catch {
        Write-Warning "[session-ops] Get-RecentSessionLogs failed: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# Get-ActiveWorkItems
# Queries dcfg_session_work_items where phase != Done(100000004) and active_flag=true.
# Ordered by priority asc then createdon asc.
# Returns an array of work item objects (up to $Top rows).
# ---------------------------------------------------------------------------
function Get-ActiveWorkItems {
    [CmdletBinding()]
    param(
        [int]$Top = 10
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $filter  = 'dcfg_active_flag eq true and dcfg_phase ne 100000004'
    $select  = 'dcfg_session_work_itemid,dcfg_title,dcfg_phase,dcfg_priority,dcfg_target_env,dcfg_assigned_session,dcfg_notes,createdon'
    $orderby = 'dcfg_priority asc,createdon asc'
    try {
        $result = Invoke-DataverseGet "dcfg_session_work_items?`$filter=$filter&`$select=$select&`$orderby=$orderby&`$top=$Top"
        return $result.value
    } catch {
        Write-Warning "[session-ops] Get-ActiveWorkItems failed: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# Get-WorkItemCount
# Returns the count of active (non-done) work items.
# Uses $count=true for efficiency.
# ---------------------------------------------------------------------------
function Get-WorkItemCount {
    [CmdletBinding()]
    param()
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $filter = 'dcfg_active_flag eq true and dcfg_phase ne 100000004'
    try {
        $result = Invoke-DataverseGet "dcfg_session_work_items?`$filter=$filter&`$count=true&`$top=0"
        return $result.'@odata.count'
    } catch {
        Write-Warning "[session-ops] Get-WorkItemCount failed: $_"
        return 0
    }
}

# ---------------------------------------------------------------------------
# New-SessionLogEntry
# Creates a new row in dcfg_session_logs with session_id and started_at=now.
# Returns the new log ID (GUID string), or $null on failure.
# ---------------------------------------------------------------------------
function New-SessionLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $now  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $body = @{
        dcfg_session_id = $SessionId
        dcfg_started_at = $now
    }
    try {
        $result = Invoke-DataversePost 'dcfg_session_logs' $body
        # POST to Dataverse returns the full entity; extract primary key
        if ($result -and $result.dcfg_session_logid) {
            return $result.dcfg_session_logid
        }
        # Fallback: look for OData entity id in the response headers (not available here)
        Write-Warning "[session-ops] New-SessionLogEntry: POST succeeded but no ID in response."
        return $null
    } catch {
        Write-Warning "[session-ops] New-SessionLogEntry failed: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Update-SessionLogEntry
# PATCHes the session log row identified by $LogId with the provided $Fields hashtable.
# ---------------------------------------------------------------------------
function Update-SessionLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogId,
        [Parameter(Mandatory)][hashtable]$Fields
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    try {
        Invoke-DataversePatch "dcfg_session_logs($LogId)" $Fields
        Write-Verbose "[session-ops] Session log $LogId updated."
    } catch {
        Write-Warning "[session-ops] Update-SessionLogEntry failed for '$LogId': $_"
    }
}

# ---------------------------------------------------------------------------
# Clear-SessionAssignments
# Finds work items assigned to the given session that aren't Done (100000004).
# Clears their assigned_session field so they can be picked up by a future session.
# ---------------------------------------------------------------------------
function Clear-SessionAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $escapedId = $SessionId -replace "'", "''"
    $filter    = "dcfg_assigned_session eq '$escapedId' and dcfg_phase ne 100000004 and dcfg_active_flag eq true"
    $select    = 'dcfg_session_work_itemid,dcfg_title'
    try {
        $result = Invoke-DataverseGet "dcfg_session_work_items?`$filter=$filter&`$select=$select"
        $items  = $result.value
        if (-not $items -or $items.Count -eq 0) {
            Write-Verbose "[session-ops] No assigned work items to clear for session '$SessionId'."
            return
        }
        foreach ($item in $items) {
            try {
                Invoke-DataversePatch "dcfg_session_work_items($($item.dcfg_session_work_itemid))" @{
                    dcfg_assigned_session = $null
                }
                Write-Verbose "[session-ops] Cleared assignment for work item: $($item.dcfg_title)"
            } catch {
                Write-Warning "[session-ops] Failed to clear assignment for item $($item.dcfg_session_work_itemid): $_"
            }
        }
        Write-Verbose "[session-ops] Cleared $($items.Count) assignment(s) for session '$SessionId'."
    } catch {
        Write-Warning "[session-ops] Clear-SessionAssignments query failed: $_"
    }
}
