<#
.SYNOPSIS
  Update status (and optional lifecycle fields) on a list of finding IDs in findings.json.
.PARAMETER Ids
  Comma-separated list of finding IDs (e.g. "CR-2026-04-09-0200,CR-2026-04-09-0201")
.PARAMETER Status
  New status: open, approved, rejected, deferred-future, fixed, verified, closed
.PARAMETER ApprovedIn
  Optional. Path to approval doc (only set when transitioning to 'approved').
.PARAMETER FixCommit
  Optional. Git SHA (only set when transitioning to 'fixed' or back-filling).
.PARAMETER FindingsPath
  Override findings.json path. Default: docs/code-review-2026-04-09/findings.json
#>

param(
    [Parameter(Mandatory=$true)][string]$Ids,
    [Parameter(Mandatory=$true)][ValidateSet('open','approved','rejected','deferred-future','fixed','verified','closed')][string]$Status,
    [string]$ApprovedIn,
    [string]$FixCommit,
    [string]$FindingsPath = 'C:\dcfg\docs\code-review-2026-04-09\findings.json'
)

$ErrorActionPreference = 'Stop'

$idList = $Ids -split ',' | ForEach-Object { $_.Trim() }
$now = (Get-Date).ToUniversalTime().ToString('o')

$findings = Get-Content $FindingsPath -Raw | ConvertFrom-Json

$updated = 0
$notFound = @()
foreach ($targetId in $idList) {
    $entry = $findings | Where-Object { $_.id -eq $targetId } | Select-Object -First 1
    if (-not $entry) {
        $notFound += $targetId
        continue
    }
    $entry.status = $Status
    if ($Status -eq 'approved') {
        $entry.approvedAt = $now
        if ($ApprovedIn) { $entry.approvedIn = $ApprovedIn }
    }
    if ($Status -eq 'fixed') {
        $entry.fixedAt = $now
        if ($FixCommit) { $entry.fixCommit = $FixCommit }
    }
    if ($Status -eq 'verified') {
        $entry.verifiedAt = $now
    }
    $updated++
}

if ($notFound.Count -gt 0) {
    Write-Host "ERROR: not found: $($notFound -join ', ')" -ForegroundColor Red
    exit 1
}

# Preserve original ordering — write back the full array
$findings | ConvertTo-Json -Depth 10 | Set-Content -Path $FindingsPath -Encoding UTF8

Write-Host "Updated $updated finding(s) to status='$Status'" -ForegroundColor Green
