<#
.SYNOPSIS
  Structural lint for findings.json — schema, ID format, uniqueness, known values.
.NOTES
  Requires PowerShell 7+.
#>

$ErrorActionPreference = 'Stop'
$path = 'C:\dcfg\docs\code-review-2026-04-09\findings.json'

$findings = Get-Content $path -Raw | ConvertFrom-Json
if ($findings -isnot [System.Collections.IEnumerable]) {
    Write-Host "FAIL: findings.json root must be an array" -ForegroundColor Red
    exit 1
}

$required = @('id','file','category','categoryNumber','severity','tier','phase','agent','status','title','detail','recommendedFix','foundAt')
$knownSeverities = @('P0','P1','P2','P3')
$knownTiers = @('auto-fix','batch','catalog-only')
$knownStatuses = @('open','approved','rejected','deferred-future','fixed','verified','closed')
$knownPhases = @('pre-seed','phase-0','phase-1','phase-2','phase-3','phase-4','phase-5')

$seenIds = @{}
$errors = @()

foreach ($f in $findings) {
    # Required keys
    $present = $f.PSObject.Properties.Name
    foreach ($k in $required) {
        if (-not ($present -contains $k)) {
            $errors += "$($f.id): missing required key '$k'"
        }
    }

    # ID format CR-YYYY-MM-DD-NNNN
    if ($f.id -notmatch '^CR-\d{4}-\d{2}-\d{2}-\d{4}$') {
        $errors += "$($f.id): ID format invalid (expected CR-YYYY-MM-DD-NNNN)"
    }

    # Uniqueness
    if ($seenIds.ContainsKey($f.id)) { $errors += "duplicate ID: $($f.id)" }
    $seenIds[$f.id] = $true

    # Enum validation
    if ($f.severity -and ($f.severity -notin $knownSeverities)) { $errors += "$($f.id): unknown severity '$($f.severity)'" }
    if ($f.tier -and ($f.tier -notin $knownTiers))             { $errors += "$($f.id): unknown tier '$($f.tier)'" }
    if ($f.status -and ($f.status -notin $knownStatuses))      { $errors += "$($f.id): unknown status '$($f.status)'" }
    if ($f.phase -and ($f.phase -notin $knownPhases))          { $errors += "$($f.id): unknown phase '$($f.phase)'" }

    # Pre-seed findings should have phase='pre-seed'
    if ($f.agent -match '^human-handoff' -and $f.phase -ne 'pre-seed') {
        $errors += "$($f.id): agent=human-handoff but phase != 'pre-seed'"
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "VALIDATION FAILED - $($errors.Count) error(s)" -ForegroundColor Red
    exit 1
}
Write-Host "findings.json: $($findings.Count) findings, 0 errors" -ForegroundColor Green
