# Fix broken SharePoint folder-path URLs -> proper Graph sharing URLs
# Uses: Core.ps1 for Dataverse, Python graph_auth for Graph token
$ErrorActionPreference = 'Continue'

. "C:/DCFG/PowerApps-Samples/dataverse/webapi/PS/Core.ps1"
Connect "https://org06f5de0b.crm.dynamics.com/"

# Get Graph token via Python
Write-Host "Getting Graph token..." -ForegroundColor Cyan
$graphToken = python -c "import sys; sys.path.insert(0,'C:/DCFG/tools/path-probe'); from graph_auth import get_graph_token; print(get_graph_token())" 2>$null
if (-not $graphToken -or $graphToken.Length -lt 50) {
    Write-Host "Failed to get Graph token. Check device code auth." -ForegroundColor Red
    exit 1
}
Write-Host "Graph token OK (...$($graphToken.Substring($graphToken.Length-8)))" -ForegroundColor Green
$gh = @{ Authorization = "Bearer $graphToken"; Accept = "application/json" }

# Load manifest for driveId lookup
$manifest = Get-Content "C:/DCFG/brain/harvest-37-manifest.json" | ConvertFrom-Json
$siteToDrive = @{}
foreach ($entry in $manifest) {
    $siteName = ($entry.siteUrl -split '/')[-1]
    $siteToDrive[$siteName] = $entry.driveId
}
Write-Host "Manifest: $($siteToDrive.Count) sites with driveIds"

# Fetch all contract attachments
Write-Host "`nFetching contract attachments..." -ForegroundColor Cyan
$resp = Invoke-RestMethod -Uri "$baseURI/dcfg_contract_attachments?`$select=dcfg_contract_attachmentid,dcfg_file_name,dcfg_file_url&`$top=1000" -Method Get -Headers $baseHeaders
$rows = $resp.value
Write-Host "Total attachments: $($rows.Count)"

# Find broken URLs
$broken = @()
$pattern = 'https://decadesconstructiongroup\.sharepoint\.com/sites/([^/]+)/Shared[%20 ]+Documents/(.+)'
foreach ($r in $rows) {
    $url = $r.dcfg_file_url
    if (-not $url) { continue }
    if ($url -match $pattern) {
        $broken += @{
            id = $r.dcfg_contract_attachmentid
            name = $r.dcfg_file_name
            url = $url
            siteName = $Matches[1]
            path = [System.Uri]::UnescapeDataString($Matches[2])
        }
    }
}
Write-Host "Broken URLs: $($broken.Count)"

if ($broken.Count -eq 0) {
    Write-Host "Nothing to fix!" -ForegroundColor Green
    exit 0
}

$fixed = 0; $failed = 0; $noDrive = 0

foreach ($item in $broken) {
    $siteName = $item.siteName
    $path = $item.path
    $driveId = $siteToDrive[$siteName]

    if (-not $driveId) {
        Write-Host "  SKIP (no driveId): $siteName / $($item.name)" -ForegroundColor DarkGray
        $noDrive++
        continue
    }

    # Resolve item via Graph
    $encodedPath = [System.Uri]::EscapeDataString($path) -replace '%2F','/'
    $resolveUri = "https://graph.microsoft.com/v1.0/drives/$driveId/root:/$encodedPath"

    $driveItem = $null
    try {
        $driveItem = Invoke-RestMethod -Uri $resolveUri -Headers $gh -Method Get
    } catch {
        # Try parent folder
        $parentPath = ($path -split '/' | Select-Object -SkipLast 1) -join '/'
        if ($parentPath) {
            $encodedParent = [System.Uri]::EscapeDataString($parentPath) -replace '%2F','/'
            try {
                $driveItem = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root:/$encodedParent" -Headers $gh -Method Get
            } catch {}
        }
    }

    if (-not $driveItem -or -not $driveItem.id) {
        Write-Host "  FAIL (not found): $($item.name) -> $path" -ForegroundColor Red
        $failed++
        continue
    }

    # Create org-wide sharing link
    $linkBody = @{ type = "view"; scope = "organization" } | ConvertTo-Json
    $sharingUrl = $null
    try {
        $linkResult = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/items/$($driveItem.id)/createLink" -Method Post -Headers $gh -Body $linkBody -ContentType "application/json"
        $sharingUrl = $linkResult.link.webUrl
    } catch {
        # Fallback to webUrl
        $sharingUrl = $driveItem.webUrl
    }

    if (-not $sharingUrl) {
        Write-Host "  FAIL (no URL): $($item.name)" -ForegroundColor Red
        $failed++
        continue
    }

    # Patch Dataverse record
    $patchHeaders = $baseHeaders.Clone()
    $patchHeaders["MSCRM.SuppressDuplicateDetection"] = "true"
    try {
        Invoke-RestMethod -Uri "$baseURI/dcfg_contract_attachments($($item.id))" -Method Patch -Headers $patchHeaders -Body (@{ dcfg_file_url = $sharingUrl } | ConvertTo-Json) -ContentType "application/json"
        $fixed++
        Write-Host "  OK: $($item.name) -> $($sharingUrl.Substring(0, [Math]::Min(80, $sharingUrl.Length)))..." -ForegroundColor Green
    } catch {
        Write-Host "  FAIL (patch): $($item.name) - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }

    Start-Sleep -Milliseconds 300
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "Fixed: $fixed"
Write-Host "Failed: $failed"
Write-Host "No driveId: $noDrive"
Write-Host "Total broken: $($broken.Count)"
