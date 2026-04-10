<#
.SYNOPSIS
  Append required bind columns to a Webapi/*/fields powerpagecomponent.
  Idempotent: only appends what is missing. Backs up before-state to JSON.
.NOTES
  Requires PowerShell 7+ (uses ConvertFrom-Json -AsHashtable).
#>

param(
    [Parameter(Mandatory=$true)][string]$OrgUrl,
    [Parameter(Mandatory=$true)][string]$SiteId,
    [Parameter(Mandatory=$true)][string]$ComponentName,
    [Parameter(Mandatory=$true)][string[]]$RequiredBinds,
    [Parameter(Mandatory=$true)][string]$BackupPath
)

$ErrorActionPreference = 'Stop'

$t = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$OrgUrl/" -AsSecureString).Token).Password
$hR = @{ Authorization = "Bearer $t"; Accept = 'application/json' }
$hW = @{ Authorization = "Bearer $t"; Accept = 'application/json'; 'Content-Type' = 'application/json; charset=utf-8'; 'If-Match' = '*' }

$filter = "powerpagecomponenttype eq 9 and _powerpagesiteid_value eq $SiteId and name eq '$ComponentName'"
$uri = "$OrgUrl/api/data/v9.2/powerpagecomponents?`$filter=$filter&`$select=powerpagecomponentid,name,content,modifiedon"
$rec = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
if (-not $rec) { throw "Component not found: $ComponentName" }

$componentId = $rec.powerpagecomponentid
# Content can be JSON object or raw string — handle both (learned from parity-sweep.ps1 Stage fix)
try {
    $parsed = $rec.content | ConvertFrom-Json -ErrorAction Stop
    $currentFields = if ($parsed -is [string]) { $parsed } else { $parsed.value }
} catch {
    $currentFields = $rec.content
}
$currentList = $currentFields -split ','
Write-Host "Current: $currentFields"

# Backup (merge into existing file if present)
$backupDir = Split-Path $BackupPath -Parent
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$existing = @{}
if (Test-Path $BackupPath) { $existing = Get-Content $BackupPath -Raw | ConvertFrom-Json -AsHashtable }
$existing[$ComponentName] = @{ componentId = $componentId; beforeFields = $currentFields; modifiedon = $rec.modifiedon }
$existing | ConvertTo-Json -Depth 10 | Set-Content -Path $BackupPath -Encoding UTF8

$toAdd = @()
foreach ($bind in $RequiredBinds) { if ($currentList -notcontains $bind) { $toAdd += $bind } }
if ($toAdd.Count -eq 0) { Write-Host "NO CHANGE NEEDED" -ForegroundColor Green; return }

$newFields = ($currentList + $toAdd) -join ','
$newContent = @{ value = $newFields } | ConvertTo-Json -Compress
$patchBody = @{ content = $newContent } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/powerpagecomponents($componentId)" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $hW | Out-Null

$verify = (Invoke-RestMethod -Uri $uri -Headers $hR).value | Select-Object -First 1
try {
    $vparsed = $verify.content | ConvertFrom-Json -ErrorAction Stop
    $verifyFields = if ($vparsed -is [string]) { $vparsed } else { $vparsed.value }
} catch {
    $verifyFields = $verify.content
}
Write-Host "After:   $verifyFields" -ForegroundColor Green
