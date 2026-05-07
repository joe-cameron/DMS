# scripts/session-coord/lock-check.ps1
# PreToolUse hook for Bash tool — acquires a lock or blocks with exit 2.
# Claude Code invokes this before every Bash command.
#
# Reads JSON from stdin: { "tool_input": { "command": "..." } }
# Pattern-matches for protected commands, then acquires or checks lock.
#
# Exit codes:
#   0 — proceed (no match, lock acquired, or reentrant)
#   2 — block (conflict: another session holds the lock)
#
# On any exception: exit 0 (never block user on hook error).

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ============================================================================
# Helpers — Env ID → env label
# ============================================================================
$script:OrgMap = @{
    'org06f5de0b' = 'prod'
    'org0c17e98d' = 'test'
    'org88778bb0' = 'stage'
}

function Get-ActiveEnvLabel {
    try {
        $lines = pac auth list 2>&1
        foreach ($line in $lines) {
            if ($line -match '^\[\d+\]\s+\*\s+.*?(org[0-9a-f]+)\.crm\.dynamics\.com') {
                $orgId = $Matches[1]
                if ($script:OrgMap.ContainsKey($orgId)) { return $script:OrgMap[$orgId] }
                return $orgId
            }
        }
    } catch {}
    return 'unknown'
}

function Get-ResourceKey {
    param([string]$Command)

    if ($Command -match 'pac\s+pages\s+upload-code-site') {
        $envLabel = Get-ActiveEnvLabel
        return "deploy:${envLabel}:spa"
    }
    if ($Command -match 'pac\s+solution\s+import') {
        $envLabel = Get-ActiveEnvLabel
        return "solution:import:${envLabel}"
    }
    if ($Command -match 'Invoke-RestMethod' -and $Command -match 'workflows\(([0-9a-fA-F\-]{36})\)') {
        $guid = $Matches[1]
        return "flow:$guid"
    }
    if ($Command -match 'npm\s+run\s+build' -and $Command -match 'dcfg-shell') {
        return "build:spa"
    }
    return $null
}

function Get-OperationLabel {
    param([string]$Command)
    if ($Command -match 'pac\s+pages\s+upload-code-site') { return 'SPA deploy' }
    if ($Command -match 'pac\s+solution\s+import')        { return 'Solution import' }
    if ($Command -match 'workflows\(')                    { return 'Flow update' }
    if ($Command -match 'npm\s+run\s+build')              { return 'SPA build' }
    return 'Protected operation'
}

# ============================================================================
# Main
# ============================================================================
try {
    # Read stdin
    $stdin = $input | Out-String
    if ([string]::IsNullOrWhiteSpace($stdin)) { exit 0 }

    $payload = $stdin | ConvertFrom-Json -ErrorAction Stop
    $command = $payload.tool_input.command
    if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

    # Pattern match
    $resourceKey = Get-ResourceKey -Command $command
    if (-not $resourceKey) { exit 0 }

    # Load lock library
    . "$PSScriptRoot/lib/lock-ops.ps1"

    $sessionId = Get-CurrentSessionId
    $existing  = Find-ActiveLock -ResourceKey $resourceKey

    if (-not $existing) {
        # No lock — acquire and proceed
        $op = Get-OperationLabel -Command $command
        New-Lock -ResourceKey $resourceKey -Operation $op | Out-Null
        exit 0
    }

    if ($existing.dcfg_session_id -eq $sessionId) {
        # Reentrant — same session already holds it
        exit 0
    }

    # Conflict — another session holds it
    $now = [System.DateTimeOffset]::UtcNow
    try {
        $lockedAt   = [System.DateTimeOffset]::Parse($existing.dcfg_locked_at).ToUniversalTime()
        $hbAt       = [System.DateTimeOffset]::Parse($existing.dcfg_heartbeat_at).ToUniversalTime()
        $ageSeconds = [Math]::Max(0, [int]($now - $lockedAt).TotalSeconds)
        $hbSeconds  = [Math]::Max(0, [int]($now - $hbAt).TotalSeconds)
    } catch {
        $ageSeconds = 0
        $hbSeconds  = 0
    }

    $msg  = "LOCK CONFLICT: $resourceKey held by $($existing.dcfg_session_id)`n"
    $msg += "Operation: $($existing.dcfg_operation) (acquired ${ageSeconds}s ago, last heartbeat ${hbSeconds}s ago)`n"
    $msg += "Action required: Wait for the other session to finish, or override with:`n"
    $msg += "  pwsh -NoProfile -File C:/dcfg/scripts/session-coord/lock-override.ps1 `"$resourceKey`"`n"
    $msg += "Then retry the command."
    [Console]::Error.WriteLine($msg)
    exit 2

} catch {
    # Never block the user on a hook error
    [Console]::Error.WriteLine("[lock-check] WARNING: hook error (non-blocking): $_")
    exit 0
}
