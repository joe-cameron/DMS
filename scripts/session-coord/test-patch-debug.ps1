# Minimal test: create a lock, PATCH it, read back to verify the PATCH worked.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. "$PSScriptRoot/lib/dataverse-auth.ps1"
Initialize-DataverseAuth

# Find the most recent test:lock-cycle row
$filter = "dcfg_resource_key eq 'test:lock-cycle'"
$select = 'dcfg_session_lockid,dcfg_resource_key,dcfg_status'
$result = Invoke-DataverseGet "dcfg_session_locks?`$filter=$filter&`$select=$select&`$orderby=dcfg_locked_at desc&`$top=1"

if ($result.value.Count -eq 0) { Write-Host "No test lock found"; exit 0 }

$row = $result.value[0]
$id  = $row.dcfg_session_lockid
Write-Host "Row ID:     $id" -ForegroundColor Cyan
Write-Host "Status NOW: $($row.dcfg_status)" -ForegroundColor Cyan

# Direct PATCH — set status to Released (100000001)
Write-Host "`nPATCHing status to 100000001 (Released)..." -ForegroundColor Yellow
$patchBody = @{ dcfg_status = 100000001 }
$json = $patchBody | ConvertTo-Json -Compress
Write-Host "  JSON: $json" -ForegroundColor DarkGray
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

$uri     = "$($script:BaseUri)/dcfg_session_locks($id)"
$headers = Get-DataverseHeaders
try {
    Invoke-RestMethod -Uri $uri -Method PATCH -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null
    Write-Host "  PATCH returned 204" -ForegroundColor Green
} catch {
    Write-Host "  PATCH failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Detail: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

# Read back immediately
Write-Host "`nReading back..." -ForegroundColor Yellow
$readBack = Invoke-DataverseGet "dcfg_session_locks($id)?`$select=dcfg_status,dcfg_resource_key"
Write-Host "  Status AFTER: $($readBack.dcfg_status)" -ForegroundColor $(if ($readBack.dcfg_status -eq 100000001) { 'Green' } else { 'Red' })
