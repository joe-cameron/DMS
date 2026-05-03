# Item 5 backfill: Match harvest manifest to projects, patch dcfg_sharepoint_site_url
. "C:/DCFG/PowerApps-Samples/dataverse/webapi/PS/Core.ps1"
Connect "https://org06f5de0b.crm.dynamics.com/"

# Fetch projects
Write-Host "Fetching projects..." -ForegroundColor Cyan
$projResp = Invoke-RestMethod `
    -Uri "$baseURI/dcfg_projects?`$select=dcfg_projectid,dcfg_name,dcfg_job_number,dcfg_sharepoint_site_url,_dcfg_propertyid_value&`$top=500" `
    -Method Get -Headers $baseHeaders
$projects = $projResp.value
Write-Host "Projects: $($projects.Count)"

# Read manifest
$manifest = Get-Content "C:/DCFG/brain/harvest-37-manifest.json" | ConvertFrom-Json
Write-Host "Manifest entries: $($manifest.Count)"

$matched = 0; $skipped = 0; $noMatch = 0

foreach ($entry in $manifest) {
    $siteUrl = $entry.siteUrl
    $code = $entry.code
    $propertyId = $entry.propertyId
    if (-not $siteUrl) { continue }

    $proj = $null
    if ($code) {
        $proj = $projects | Where-Object { $_.dcfg_job_number -and $_.dcfg_job_number -like "*$code*" } | Select-Object -First 1
    }
    if (-not $proj -and $propertyId) {
        $proj = $projects | Where-Object { $_._dcfg_propertyid_value -eq $propertyId } | Select-Object -First 1
    }
    if (-not $proj) {
        Write-Host "  No match: code=$code prop=$propertyId team=$($entry.teamName)" -ForegroundColor DarkGray
        $noMatch++
        continue
    }
    if ($proj.dcfg_sharepoint_site_url) {
        $skipped++
        continue
    }

    try {
        $patchBody = @{ dcfg_sharepoint_site_url = $siteUrl } | ConvertTo-Json
        Invoke-RestMethod `
            -Uri "$baseURI/dcfg_projects($($proj.dcfg_projectid))" `
            -Method Patch -Headers $baseHeaders `
            -Body $patchBody -ContentType "application/json"
        $matched++
        Write-Host "  OK: $($proj.dcfg_name) -> $siteUrl" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($proj.dcfg_name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nResults: matched=$matched skipped=$skipped noMatch=$noMatch total=$($manifest.Count)" -ForegroundColor Cyan
