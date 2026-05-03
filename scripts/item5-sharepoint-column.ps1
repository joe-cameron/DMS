# Item 5: Create dcfg_sharepoint_site_url on dcfg_project + backfill from harvest manifest
# Environment: Prod (org06f5de0b.crm.dynamics.com)

. "C:/DCFG/PowerApps-Samples/dataverse/webapi/PS/Core.ps1"
Connect "https://org06f5de0b.crm.dynamics.com/"

# ── Step 1: Check if column already exists ──
Write-Host "`n=== Step 1: Check if dcfg_sharepoint_site_url exists ===" -ForegroundColor Cyan
try {
    $check = Get-Record "EntityDefinitions(LogicalName='dcfg_project')/Attributes(LogicalName='dcfg_sharepoint_site_url')" | ConvertFrom-Json
    Write-Host "Column already exists: $($check.LogicalName) (type: $($check.AttributeType))" -ForegroundColor Green
    $columnExists = $true
} catch {
    Write-Host "Column does not exist yet - creating..." -ForegroundColor Yellow
    $columnExists = $false
}

# ── Step 2: Create column if needed ──
if (-not $columnExists) {
    Write-Host "`n=== Step 2: Creating dcfg_sharepoint_site_url column ===" -ForegroundColor Cyan
    $body = @{
        "@odata.type" = "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName = "dcfg_sharepoint_site_url"
        DisplayName = @{
            "@odata.type" = "#Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = "SharePoint Site URL"
                LanguageCode = 1033
            })
        }
        Description = @{
            "@odata.type" = "#Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = "Verified SharePoint/Teams project site URL from harvest manifest"
                LanguageCode = 1033
            })
        }
        RequiredLevel = @{ Value = "None"; CanBeChanged = $true; ManagedPropertyLogicalName = "canmodifyrequirementlevelsettings" }
        MaxLength = 500
        FormatName = @{ Value = "Url" }
    } | ConvertTo-Json -Depth 10

    $headers = $baseHeaders.Clone()
    $headers["MSCRM.SolutionUniqueName"] = "DCFGSystemTest"

    try {
        Invoke-RestMethod `
            -Uri "$baseURI/EntityDefinitions(LogicalName='dcfg_project')/Attributes" `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -ContentType "application/json"
        Write-Host "Column created successfully" -ForegroundColor Green
        Start-Sleep -Seconds 10
        Write-Host "Waited 10s for metadata cache" -ForegroundColor DarkGray
    } catch {
        Write-Host "ERROR creating column: $($_.Exception.Message)" -ForegroundColor Red
        $errBody = $_.ErrorDetails.Message
        if ($errBody) { Write-Host $errBody -ForegroundColor Red }
        exit 1
    }
}

# ── Step 3: Read harvest manifest ──
Write-Host "`n=== Step 3: Reading harvest manifest ===" -ForegroundColor Cyan
$manifest = Get-Content "C:/DCFG/brain/harvest-37-manifest.json" | ConvertFrom-Json
Write-Host "Manifest entries: $($manifest.Count)"

# ── Step 4: Fetch all projects from Prod ──
Write-Host "`n=== Step 4: Fetching projects ===" -ForegroundColor Cyan
$projResp = Get-Record "dcfg_projects?`$select=dcfg_projectid,dcfg_name,dcfg_job_number,dcfg_sharepoint_site_url,_dcfg_propertyid_value&`$top=500" | ConvertFrom-Json
$projects = $projResp.value
Write-Host "Projects found: $($projects.Count)"

# ── Step 5: Match and backfill ──
Write-Host "`n=== Step 5: Matching manifest to projects ===" -ForegroundColor Cyan
$matched = 0
$skipped = 0
$noMatch = 0

foreach ($entry in $manifest) {
    $siteUrl = $entry.siteUrl
    $code = $entry.code
    $propertyId = $entry.propertyId

    if (-not $siteUrl) { continue }

    # Try match by job number (code)
    $proj = $null
    if ($code) {
        $proj = $projects | Where-Object { $_.dcfg_job_number -and $_.dcfg_job_number -like "*$code*" } | Select-Object -First 1
    }

    # Fallback: match by property ID
    if (-not $proj -and $propertyId) {
        $proj = $projects | Where-Object { $_._dcfg_propertyid_value -eq $propertyId } | Select-Object -First 1
    }

    if (-not $proj) {
        $noMatch++
        continue
    }

    # Skip if already set
    if ($proj.dcfg_sharepoint_site_url) {
        $skipped++
        continue
    }

    # Patch the project
    try {
        $patchBody = @{ dcfg_sharepoint_site_url = $siteUrl } | ConvertTo-Json
        Invoke-RestMethod `
            -Uri "$baseURI/dcfg_projects($($proj.dcfg_projectid))" `
            -Method Patch `
            -Headers $baseHeaders `
            -Body $patchBody `
            -ContentType "application/json"
        $matched++
        Write-Host "  Matched: $($proj.dcfg_name) -> $siteUrl" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED: $($proj.dcfg_name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "Matched & patched: $matched"
Write-Host "Already set (skipped): $skipped"
Write-Host "No project match: $noMatch"
Write-Host "Total manifest entries: $($manifest.Count)"
