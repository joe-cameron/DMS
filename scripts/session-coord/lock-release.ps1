# scripts/session-coord/lock-release.ps1
# PostToolUse hook for Bash tool — releases the lock after the command runs.
# Claude Code invokes this after every Bash command.
#
# Reads JSON from stdin: { "tool_input": { "command": "..." } }
# Same pattern matching as lock-check.ps1 — releases the previously acquired lock.
# If the command was a deploy, appends an entry to dcfg_session_log.dcfg_deploys.
#
# Always exits 0 — PostToolUse hooks cannot block.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ============================================================================
# Helpers — same env/resource-key logic as lock-check.ps1
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

function Get-DeployEnvFromCommand {
    param([string]$Command)
    return Get-ActiveEnvLabel
}

# ============================================================================
# Append-DeployLog
# Appends a JSON entry to the current session's dcfg_session_log.dcfg_deploys.
# ============================================================================
function Append-DeployLog {
    param([string]$Command, [string]$Env)
    try {
        $sessionId = Get-CurrentSessionId
        if (-not $sessionId) { return }

        if (-not $script:BaseUri) { Initialize-DataverseAuth }

        # Find session log row for this session
        $filter = "dcfg_session_id eq '$sessionId'"
        $select = 'dcfg_session_logid,dcfg_deploys'
        $result = Invoke-DataverseGet "dcfg_session_logs?`$filter=$filter&`$select=$select&`$top=1"

        if (-not $result.value -or $result.value.Count -eq 0) {
            Write-Verbose "[lock-release] No session log row found for '$sessionId' — skipping deploy log."
            return
        }

        $logRow    = $result.value[0]
        $logId     = $logRow.dcfg_session_logid
        $existing  = $logRow.dcfg_deploys

        $entry = @{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            env       = $Env
            command   = ($Command -replace '^.{0,200}(.{0,200})$', '$0').Substring(0, [Math]::Min($Command.Length, 300))
        }

        $entries = @()
        if (-not [string]::IsNullOrWhiteSpace($existing)) {
            try { $entries = $existing | ConvertFrom-Json } catch { $entries = @() }
        }
        if ($entries -isnot [array]) { $entries = @($entries) }
        $entries += $entry

        $newJson = $entries | ConvertTo-Json -Depth 5 -Compress
        Invoke-DataversePatch "dcfg_session_logs($logId)" @{ dcfg_deploys = $newJson }
        Write-Verbose "[lock-release] Deploy logged for session '$sessionId', env='$Env'."
    } catch {
        Write-Warning "[lock-release] Append-DeployLog failed (non-critical): $_"
    }
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

    # Load lock library (also loads dataverse-auth)
    . "$PSScriptRoot/lib/lock-ops.ps1"

    # Release the lock
    Release-Lock -ResourceKey $resourceKey

    # If this was a deploy, update the session log
    if ($command -match 'pac\s+pages\s+upload-code-site') {
        $env = Get-DeployEnvFromCommand -Command $command
        Append-DeployLog -Command $command -Env $env
    }

} catch {
    # Never fail on a post-hook
    [Console]::Error.WriteLine("[lock-release] WARNING: hook error (non-blocking): $_")
}

exit 0
