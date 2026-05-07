# scripts/session-coord/heartbeat.ps1
# Background heartbeat process — keeps session locks alive.
# Spawned by session-start.ps1 as a detached process. Do NOT dot-source from other scripts.
#
# Usage (internal — called by session-start.ps1):
#   Start-Process pwsh -ArgumentList @('-NoProfile','-File','heartbeat.ps1','-SessionId',$id,'-ParentPid',$pid,'-OrgUrl',$url) -WindowStyle Hidden

param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][int]$ParentPid,
    [Parameter(Mandatory)][string]$OrgUrl
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Inline Dataverse helpers — no dot-source; runs independently.
# ---------------------------------------------------------------------------
$script:BaseUri = $OrgUrl.TrimEnd('/') + '/api/data/v9.2'

function Get-HeartbeatToken {
    try {
        $audience    = $OrgUrl.TrimEnd('/') + '/'
        $secureToken = (Get-AzAccessToken -ResourceUrl $audience -AsSecureString -ErrorAction Stop).Token
        return [System.Net.NetworkCredential]::new('', $secureToken).Password
    } catch {
        return $null
    }
}

function Get-HeartbeatHeaders {
    $token = Get-HeartbeatToken
    if (-not $token) { return $null }
    return @{
        'Authorization'            = "Bearer $token"
        'Accept'                   = 'application/json'
        'OData-MaxVersion'         = '4.0'
        'OData-Version'            = '4.0'
        'Content-Type'             = 'application/json; charset=utf-8'
        'MSCRM.SolutionUniqueName' = 'DCFGSystemTest'
    }
}

# ---------------------------------------------------------------------------
# Refresh-AuthToken
# Called every 50 minutes to pre-emptively re-acquire the token.
# Since Get-HeartbeatToken is stateless (no caching), this is a no-op
# but we track last-refresh time so we can add caching later if needed.
# ---------------------------------------------------------------------------
$script:LastTokenRefresh = [System.DateTime]::UtcNow

function Should-RefreshToken {
    $elapsed = ([System.DateTime]::UtcNow - $script:LastTokenRefresh).TotalMinutes
    return $elapsed -ge 50
}

function Do-TokenRefresh {
    # Force a test call to ensure the token pipeline is warm.
    try {
        $hdrs = Get-HeartbeatHeaders
        if ($hdrs) {
            Invoke-RestMethod -Uri "$($script:BaseUri)/WhoAmI" -Method GET -Headers $hdrs -TimeoutSec 10 | Out-Null
        }
    } catch {}
    $script:LastTokenRefresh = [System.DateTime]::UtcNow
}

# ---------------------------------------------------------------------------
# Heartbeat-Locks
# Queries active locks for our session, PATCHes heartbeat_at + expires_at.
# ---------------------------------------------------------------------------
function Heartbeat-Locks {
    try {
        $hdrs = Get-HeartbeatHeaders
        if (-not $hdrs) { return }

        $filter = [Uri]::EscapeDataString("dcfg_session_id eq '$SessionId' and dcfg_status eq 100000000")
        $select = 'dcfg_session_lockid'
        $uri    = "$($script:BaseUri)/dcfg_session_locks?`$filter=$filter&`$select=$select"

        $result = Invoke-RestMethod -Uri $uri -Method GET -Headers $hdrs -TimeoutSec 15 -ErrorAction Stop
        $locks  = $result.value
        if (-not $locks -or $locks.Count -eq 0) { return }

        $nowUtc    = [System.DateTime]::UtcNow
        $expiresAt = $nowUtc.AddMinutes(5)
        $fmt       = 'yyyy-MM-ddTHH:mm:ss.fffZ'
        $body      = @{
            dcfg_heartbeat_at = $nowUtc.ToString($fmt)
            dcfg_expires_at   = $expiresAt.ToString($fmt)
        } | ConvertTo-Json -Compress
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

        foreach ($lk in $locks) {
            try {
                $hdrs2 = Get-HeartbeatHeaders
                if (-not $hdrs2) { continue }
                $patchUri = "$($script:BaseUri)/dcfg_session_locks($($lk.dcfg_session_lockid))"
                Invoke-RestMethod -Uri $patchUri -Method PATCH -Headers $hdrs2 -Body $bodyBytes -TimeoutSec 10 | Out-Null
            } catch {}
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while ($true) {
    # Check if parent process is still alive
    $parentProcess = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
    if (-not $parentProcess) {
        # Parent is gone — locks will expire naturally within <=5 min
        exit 0
    }

    # Refresh auth token if approaching expiry (every 50 min)
    if (Should-RefreshToken) {
        Do-TokenRefresh
    }

    # Update heartbeat on all active locks for this session
    Heartbeat-Locks

    # Wait 60 seconds before next cycle
    Start-Sleep -Seconds 60
}
