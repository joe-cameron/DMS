<#
.SYNOPSIS
  INSERT a new dcfg_configs row (POST). Used when the key is missing entirely.
.NOTES
  Separate from backport-config-value.ps1 (which only PATCHes existing rows).
  Records the missing-key state in the backup JSON before inserting.
#>

param(
    [Parameter(Mandatory=$true)][string]$OrgUrl,
    [Parameter(Mandatory=$true)][string]$Key,
    [Parameter(Mandatory=$true)][string]$Value,
    [Parameter(Mandatory=$true)][string]$BackupPath
)

$ErrorActionPreference = 'Stop'

$t = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$OrgUrl/" -AsSecureString).Token).Password
$hR = @{ Authorization = "Bearer $t"; Accept = 'application/json' }
$hW = @{ Authorization = "Bearer $t"; Accept = 'application/json'; 'Content-Type' = 'application/json; charset=utf-8'; Prefer = 'return=representation' }

# Check if the row already exists — if yes, refuse to INSERT (use PATCH helper instead)
$uri = "$OrgUrl/api/data/v9.2/dcfg_configs?`$filter=dcfg_key eq '$Key'&`$select=dcfg_configid,dcfg_value"
$existing = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
if ($existing) {
    Write-Host "REFUSING INSERT: key '$Key' already exists with value '$($existing.dcfg_value)' (id $($existing.dcfg_configid)). Use backport-config-value.ps1 for updates." -ForegroundColor Red
    exit 1
}
Write-Host "Current: (key not present)"

# Backup the missing-key state
$backupDir = Split-Path $BackupPath -Parent
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$bkp = @{}
if (Test-Path $BackupPath) { $bkp = Get-Content $BackupPath -Raw | ConvertFrom-Json -AsHashtable }
$bkp["config:$Key"] = @{ id = $null; beforeValue = $null; state = 'missing-key' }
$bkp | ConvertTo-Json -Depth 10 | Set-Content -Path $BackupPath -Encoding UTF8

# POST the new row
$body = @{ dcfg_key = $Key; dcfg_value = $Value } | ConvertTo-Json -Compress
$postUri = "$OrgUrl/api/data/v9.2/dcfg_configs"
$resp = Invoke-RestMethod -Uri $postUri -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -Headers $hW
Write-Host "After:   key='$Key' value='$($resp.dcfg_value)' id=$($resp.dcfg_configid)" -ForegroundColor Green
