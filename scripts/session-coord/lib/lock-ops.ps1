# scripts/session-coord/lib/lock-ops.ps1
# Lock operations library for Session Coordinator.
# Dot-source this file to get lock management functions.
#
# Usage:
#   . C:/dcfg/scripts/session-coord/lib/lock-ops.ps1
#   $lock = Find-ActiveLock -ResourceKey 'deploy:test:spa'
#   New-Lock -ResourceKey 'deploy:test:spa' -Operation 'SPA deploy'
#   Release-Lock -ResourceKey 'deploy:test:spa'

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/dataverse-auth.ps1"

# Lock status picklist values
$script:LockStatus = @{
    Active     = 100000000
    Released   = 100000001
    Expired    = 100000002
    Overridden = 100000003
}

# ---------------------------------------------------------------------------
# Get-CurrentSessionId
# Reads sessionId from $env:LOCALAPPDATA/dcfg-session/current-session.json.
# Returns $null if the file is missing or malformed.
# ---------------------------------------------------------------------------
function Get-CurrentSessionId {
    $path = Join-Path $env:LOCALAPPDATA 'dcfg-session\current-session.json'
    if (-not (Test-Path $path)) { return $null }
    try {
        $obj = Get-Content $path -Raw | ConvertFrom-Json
        return $obj.sessionId
    } catch {
        Write-Warning "[lock-ops] Could not parse current-session.json: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Find-ActiveLock
# Queries dcfg_session_lock for a row matching ResourceKey with status=Active
# and expires_at > now. Returns the first match or $null.
# ---------------------------------------------------------------------------
function Find-ActiveLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceKey
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $now    = [System.Uri]::EscapeDataString((Get-Date -Format 'o'))
    $filter = "dcfg_resource_key eq '$($ResourceKey -replace "'", "''")' and dcfg_status eq $($script:LockStatus.Active) and dcfg_expires_at gt $now"
    $select = 'dcfg_session_lockid,dcfg_resource_key,dcfg_session_id,dcfg_operation,dcfg_locked_at,dcfg_heartbeat_at,dcfg_expires_at,dcfg_status'
    try {
        $result = Invoke-DataverseGet "dcfg_session_locks?`$filter=$filter&`$select=$select&`$top=1"
        if ($result.value -and $result.value.Count -gt 0) {
            return $result.value[0]
        }
        return $null
    } catch {
        Write-Warning "[lock-ops] Find-ActiveLock query failed: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# New-Lock
# Creates a new lock row in dcfg_session_lock.
# locked_at = heartbeat_at = now, expires_at = now + 5 minutes.
# status = Active (100000000).
# Returns the created record or $null on failure.
# ---------------------------------------------------------------------------
function New-Lock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceKey,
        [Parameter(Mandatory)][string]$Operation
    )
    $sessionId = Get-CurrentSessionId
    if (-not $sessionId) {
        Write-Warning "[lock-ops] No current session ID found — lock not created."
        return $null
    }
    $now       = (Get-Date).ToUniversalTime()
    $expiresAt = $now.AddMinutes(5)
    $fmt       = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $body = @{
        dcfg_resource_key  = $ResourceKey
        dcfg_session_id    = $sessionId
        dcfg_locked_at     = $now.ToString($fmt)
        dcfg_heartbeat_at  = $now.ToString($fmt)
        dcfg_expires_at    = $expiresAt.ToString($fmt)
        dcfg_operation     = $Operation
        dcfg_status        = $script:LockStatus.Active
    }
    try {
        Invoke-DataversePost 'dcfg_session_locks' $body | Out-Null
        Write-Verbose "[lock-ops] Lock acquired: $ResourceKey (session=$sessionId)"
        return $true
    } catch {
        Write-Warning "[lock-ops] New-Lock failed for '$ResourceKey': $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Release-Lock
# Finds the active lock for this resource held by the current session.
# PATCHes status to Released (100000001).
# ---------------------------------------------------------------------------
function Release-Lock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceKey
    )
    $sessionId = Get-CurrentSessionId
    if (-not $sessionId) {
        Write-Warning "[lock-ops] No current session ID — cannot release lock."
        return
    }
    $lock = Find-ActiveLock -ResourceKey $ResourceKey
    if (-not $lock) {
        Write-Verbose "[lock-ops] No active lock found for '$ResourceKey' — nothing to release."
        return
    }
    if ($lock.dcfg_session_id -ne $sessionId) {
        Write-Warning "[lock-ops] Lock '$ResourceKey' is held by '$($lock.dcfg_session_id)', not current session '$sessionId'. Use Invoke-LockOverride to force."
        return
    }
    try {
        Invoke-DataversePatch "dcfg_session_locks($($lock.dcfg_session_lockid))" @{
            dcfg_status = $script:LockStatus.Released
        }
        Write-Verbose "[lock-ops] Lock released: $ResourceKey"
    } catch {
        Write-Warning "[lock-ops] Release-Lock failed for '$ResourceKey': $_"
    }
}

# ---------------------------------------------------------------------------
# Release-AllSessionLocks
# Finds all active locks held by the current session and releases them.
# ---------------------------------------------------------------------------
function Release-AllSessionLocks {
    [CmdletBinding()]
    param()
    $sessionId = Get-CurrentSessionId
    if (-not $sessionId) {
        Write-Verbose "[lock-ops] No current session — nothing to release."
        return
    }
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $filter = "dcfg_session_id eq '$sessionId' and dcfg_status eq $($script:LockStatus.Active)"
    $select = 'dcfg_session_lockid,dcfg_resource_key'
    try {
        $result = Invoke-DataverseGet "dcfg_session_locks?`$filter=$filter&`$select=$select"
        $locks  = $result.value
        if (-not $locks -or $locks.Count -eq 0) {
            Write-Verbose "[lock-ops] No active locks for session '$sessionId'."
            return
        }
        foreach ($lock in $locks) {
            try {
                Invoke-DataversePatch "dcfg_session_locks($($lock.dcfg_session_lockid))" @{
                    dcfg_status = $script:LockStatus.Released
                }
                Write-Verbose "[lock-ops] Released: $($lock.dcfg_resource_key)"
            } catch {
                Write-Warning "[lock-ops] Failed to release lock $($lock.dcfg_session_lockid): $_"
            }
        }
        Write-Host "[lock-ops] Released $($locks.Count) lock(s) for session '$sessionId'." -ForegroundColor Cyan
    } catch {
        Write-Warning "[lock-ops] Release-AllSessionLocks query failed: $_"
    }
}

# ---------------------------------------------------------------------------
# Invoke-LockOverride
# Finds the active lock for the given resource key (any holder).
# PATCHes status to Overridden (100000003), sets overridden_by and overridden_at.
# ---------------------------------------------------------------------------
function Invoke-LockOverride {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceKey
    )
    $sessionId = Get-CurrentSessionId
    if (-not $sessionId) {
        Write-Warning "[lock-ops] No current session ID — cannot override lock."
        return $null
    }
    $lock = Find-ActiveLock -ResourceKey $ResourceKey
    if (-not $lock) {
        Write-Warning "[lock-ops] No active lock found for '$ResourceKey' — nothing to override."
        return $null
    }
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    try {
        Invoke-DataversePatch "dcfg_session_locks($($lock.dcfg_session_lockid))" @{
            dcfg_status        = $script:LockStatus.Overridden
            dcfg_overridden_by = $sessionId
            dcfg_overridden_at = $now
        }
        Write-Host "[lock-ops] Lock '$ResourceKey' overridden (was held by '$($lock.dcfg_session_id)')." -ForegroundColor Yellow
        return $lock
    } catch {
        Write-Warning "[lock-ops] Invoke-LockOverride failed for '$ResourceKey': $_"
        return $null
    }
}
