# Nora Template Audit — Download all templates, extract merge fields, map to content controls
Add-Type -AssemblyName System.IO.Compression

$graphToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -AsSecureString)
$gpt = [System.Net.NetworkCredential]::new('', $graphToken.Token).Password
$gh = @{ 'Authorization' = "Bearer $gpt"; 'Accept' = 'application/json' }

$driveId = 'b!lGCVWRjYlkiGjk72z8d6szyNF3B4WKtIo0BTKeaWw-k0gmQTkZA9QKdMLo-aANXH'
$outDir = 'C:\DCFG\nora\templates'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

Write-Host "=== TEMPLATE AUDIT ===" -ForegroundColor Cyan

# List all templates
$items = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root/children" -Headers $gh).value
Write-Host "Files in DCFG_Templates: $($items.Count)"

foreach ($item in $items) {
    if ($item.name -notlike '*.docx') { continue }

    Write-Host "`n--- $($item.name) ($($item.size) bytes) ---" -ForegroundColor Yellow

    # Download
    $localPath = Join-Path $outDir $item.name
    Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/items/$($item.id)/content" `
        -Headers @{'Authorization'="Bearer $gpt"} -OutFile $localPath

    # Extract document.xml from the docx (ZIP)
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($localPath)
        $docEntry = $zip.GetEntry('word/document.xml')

        if ($docEntry) {
            $reader = New-Object System.IO.StreamReader($docEntry.Open())
            $xml = $reader.ReadToEnd()
            $reader.Close()

            # Find merge fields (MERGEFIELD pattern)
            $mergeFields = [regex]::Matches($xml, 'MERGEFIELD\s+([^\s\\»"<]+)')
            $uniqueMerge = $mergeFields | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

            # Find content controls (w:sdt with w:tag)
            $tags = [regex]::Matches($xml, '<w:tag w:val="([^"]+)"')
            $uniqueTags = $tags | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

            # Find «field» style merge placeholders
            $chevronFields = [regex]::Matches($xml, '&#171;([^&#]+)&#187;|«([^»]+)»')
            $uniqueChevron = $chevronFields | ForEach-Object {
                if ($_.Groups[1].Value) { $_.Groups[1].Value } else { $_.Groups[2].Value }
            } | Sort-Object -Unique

            # Also check for fldSimple fields
            $fldSimple = [regex]::Matches($xml, '<w:fldSimple w:instr="[^"]*MERGEFIELD\s+([^"\\]+)')
            $uniqueFld = $fldSimple | ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique

            Write-Host "  MERGE FIELDS: $($uniqueMerge.Count)"
            $uniqueMerge | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

            Write-Host "  CONTENT CONTROLS: $($uniqueTags.Count)"
            $uniqueTags | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }

            Write-Host "  CHEVRON PLACEHOLDERS: $($uniqueChevron.Count)"
            $uniqueChevron | ForEach-Object { Write-Host "    $_" -ForegroundColor Cyan }

            Write-Host "  FLD SIMPLE: $($uniqueFld.Count)"
            $uniqueFld | ForEach-Object { Write-Host "    $_" -ForegroundColor Cyan }

            # Determine template type from filename
            $templateType = 'Unknown'
            if ($item.name -match 'Blanket|Workorder|Work.?Order|WO') { $templateType = 'Work Order (Bancroft)' }
            elseif ($item.name -match 'Amendment') { $templateType = 'Work Order Amendment (Bancroft)' }
            elseif ($item.name -match 'MSA|Management.?Services') { $templateType = 'MSA (Decades)' }
            elseif ($item.name -match 'Exhibit.?A|Package') { $templateType = 'Exhibit A (Concierge)' }
            elseif ($item.name -match 'Exhibit.?C|Fee.?Schedule') { $templateType = 'Exhibit C (Fee Schedule)' }
            elseif ($item.name -match 'Test') { $templateType = 'Test Template' }

            Write-Host "  TYPE: $templateType" -ForegroundColor White

            # Summary
            $totalFields = $uniqueMerge.Count + $uniqueChevron.Count + $uniqueFld.Count
            $hasContentControls = $uniqueTags.Count -gt 0
            Write-Host "  TOTAL MERGE FIELDS: $totalFields"
            Write-Host "  HAS CONTENT CONTROLS: $hasContentControls" -ForegroundColor $(if($hasContentControls){'Green'}else{'Red'})

            if ($totalFields -gt 0 -and -not $hasContentControls) {
                Write-Host "  ACTION NEEDED: Convert merge fields to content controls" -ForegroundColor Red
            }
        }

        $zip.Dispose()
    } catch {
        Write-Host "  ERROR reading: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Also check Dataverse template records for mapping
Write-Host "`n=== DATAVERSE TEMPLATE RECORDS ===" -ForegroundColor Cyan
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

Connect 'https://org88778bb0.crm.dynamics.com/'
Invoke-DataverseCommands {
    $token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl 'https://org88778bb0.crm.dynamics.com/' -AsSecureString).Token).Password
    $h = @{ 'Authorization'="Bearer $token"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; 'Accept'='application/json' }
    $url = 'https://org88778bb0.crm.dynamics.com/api/data/v9.2'

    $templates = (Invoke-RestMethod -Uri "$url/dcfg_document_templates?`$select=dcfg_name,dcfg_document_type,dcfg_exhibit_type,dcfg_contract_family,dcfg_sharepoint_url,dcfg_is_active" -Headers $h).value
    foreach ($t in $templates) {
        $docType = switch ($t.dcfg_document_type) { 100000000 {'WorkOrder'} 100000001 {'Amendment'} 100000002 {'MSA'} default {'?'} }
        $family = switch ($t.dcfg_contract_family) { 100000000 {'Bancroft'} 100000001 {'Decades/Concierge'} default {'?'} }
        $exhibit = switch ($t.dcfg_exhibit_type) { 100000001 {'Exhibit A'} default {''} }
        $fileName = if ($t.dcfg_sharepoint_url) { $t.dcfg_sharepoint_url.Split('/')[-1] } else { 'no file' }

        Write-Host "`n  $($t.dcfg_name)" -ForegroundColor White
        Write-Host "    Type: $docType | Family: $family | Exhibit: $exhibit"
        Write-Host "    File: $fileName"
        Write-Host "    Active: $($t.dcfg_is_active)"
    }
}
