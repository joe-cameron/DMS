# scripts/session-coord/test-lock-cycle.ps1
# Tests: cleanup -> acquire -> verify -> release -> verify -> override.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/lib/lock-ops.ps1"
Initialize-DataverseAuth

$sessionId = Get-CurrentSessionId
Write-Host "[test] Session: $sessionId" -ForegroundColor Cyan
Write-Host "[test] Target:  $($script:OrgUrl)`n" -ForegroundColor Cyan

$testKey = 'test:lock-cycle'
$pass = 0
$fail = 0

# Step 0: Clean up any leftover test locks
Write-Host "Step 0: Cleanup leftover test locks..." -ForegroundColor Yellow
$filter = "dcfg_resource_key eq '$testKey' and dcfg_status eq 100000000"
$stale = Invoke-DataverseGet "dcfg_session_locks?`$filter=$filter&`$select=dcfg_session_lockid"
$cleaned = 0
foreach ($row in $stale.value) {
    Invoke-DataversePatch "dcfg_session_locks($($row.dcfg_session_lockid))" @{ dcfg_status = 100000002 }  # Expired
    $cleaned++
}
Write-Host "  Cleaned $cleaned stale row(s)" -ForegroundColor DarkGray

# Step 1: Acquire
Write-Host "Step 1: Acquire lock..." -ForegroundColor Yellow
$lock = New-Lock -ResourceKey $testKey -Operation 'Lock cycle test'
if ($lock) { Write-Host "  PASS" -ForegroundColor Green; $pass++ }
else       { Write-Host "  FAIL" -ForegroundColor Red; $fail++ }

# Step 2: Verify exists
Write-Host "Step 2: Verify lock exists..." -ForegroundColor Yellow
$found = Find-ActiveLock -ResourceKey $testKey
if ($found -and $found.dcfg_session_id -eq $sessionId) {
    Write-Host "  PASS (expires $($found.dcfg_expires_at))" -ForegroundColor Green; $pass++
} else { Write-Host "  FAIL" -ForegroundColor Red; $fail++ }

# Step 3: Release
Write-Host "Step 3: Release lock..." -ForegroundColor Yellow
Release-Lock -ResourceKey $testKey
$afterRelease = Find-ActiveLock -ResourceKey $testKey
if (-not $afterRelease) {
    Write-Host "  PASS" -ForegroundColor Green; $pass++
} else {
    Write-Host "  FAIL (status=$($afterRelease.dcfg_status))" -ForegroundColor Red; $fail++
}

# Step 4: Override test
Write-Host "Step 4: Override test..." -ForegroundColor Yellow
New-Lock -ResourceKey $testKey -Operation 'Override target' | Out-Null
Invoke-LockOverride -ResourceKey $testKey | Out-Null
$afterOverride = Find-ActiveLock -ResourceKey $testKey
if (-not $afterOverride) {
    Write-Host "  PASS" -ForegroundColor Green; $pass++
} else {
    Write-Host "  FAIL (status=$($afterOverride.dcfg_status))" -ForegroundColor Red; $fail++
}

Write-Host "`n[test] Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
