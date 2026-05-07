# scripts/session-coord/lock-override.ps1
# Forcibly overrides an active lock held by another session.
# Call this when a session died without releasing its lock.
#
# Usage:
#   pwsh -NoProfile -File C:/dcfg/scripts/session-coord/lock-override.ps1 "deploy:test:spa"

param(
    [Parameter(Mandatory)][string]$ResourceKey
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/lib/lock-ops.ps1"

Write-Host "[lock-override] Attempting to override lock: '$ResourceKey'" -ForegroundColor Cyan

$sessionId = Get-CurrentSessionId
if (-not $sessionId) {
    Write-Host "[lock-override] ERROR: No current session ID found." -ForegroundColor Red
    Write-Host "  Ensure a session is active at: $env:LOCALAPPDATA\dcfg-session\current-session.json"
    exit 1
}

Write-Host "[lock-override] Current session: $sessionId"

$lock = Find-ActiveLock -ResourceKey $ResourceKey
if (-not $lock) {
    Write-Host "[lock-override] No active lock found for '$ResourceKey'." -ForegroundColor Yellow
    Write-Host "  The resource is already clear — no override needed."
    exit 0
}

if ($lock.dcfg_session_id -eq $sessionId) {
    Write-Host "[lock-override] Lock '$ResourceKey' is already held by THIS session." -ForegroundColor Yellow
    Write-Host "  Use Release-Lock or just proceed — no override needed."
    exit 0
}

try   { $lockedAt = [System.DateTimeOffset]::Parse($lock.dcfg_locked_at).ToUniversalTime() } catch { $lockedAt = [System.DateTimeOffset]::UtcNow }
$age  = [Math]::Max(0, [int]([System.DateTimeOffset]::UtcNow - $lockedAt).TotalSeconds)
Write-Host "[lock-override] Found lock held by '$($lock.dcfg_session_id)' (acquired ${age}s ago)"
Write-Host "[lock-override] Operation: $($lock.dcfg_operation)"

$result = Invoke-LockOverride -ResourceKey $ResourceKey
if ($result) {
    Write-Host "[lock-override] Override complete." -ForegroundColor Green
    Write-Host "  '$ResourceKey' is now free. You may retry your command."
} else {
    Write-Host "[lock-override] Override may have failed — check warnings above." -ForegroundColor Red
    exit 1
}
