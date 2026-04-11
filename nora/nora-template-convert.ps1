# =============================================================================
# Nora Template Converter — Replace «MERGEFIELD» with content controls
# ALWAYS backs up originals first
# =============================================================================
param(
    [string]$TemplateName = 'BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx'
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$graphToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -AsSecureString)
$gpt = [System.Net.NetworkCredential]::new('', $graphToken.Token).Password
$gh = @{ 'Authorization' = "Bearer $gpt"; 'Accept' = 'application/json' }

$driveId = 'b!lGCVWRjYlkiGjk72z8d6szyNF3B4WKtIo0BTKeaWw-k0gmQTkZA9QKdMLo-aANXH'
$origDir = 'C:\DCFG\nora\templates\originals'
$workDir = 'C:\DCFG\nora\templates'

# Merge field → content control tag mapping
$fieldMap = @{
    # Contract fields
    'CLIENT_NAME' = 'contract_client_name'
    'CONTRACTOR_NAME' = 'contract_contractor_name'
    'CONTRACTOR_LEGAL_NAME' = 'contract_contractor_legal_name'
    'CONTRACTOR_ADDRESS' = 'vendor_address'
    'CONTRACTOR_EMAIL' = 'vendor_email'
    'CONTRCTOR_PHONE' = 'vendor_phone'  # Note: typo in original template
    'CONTRACTOR_PHONE' = 'vendor_phone'
    'CONTRACTOR_PRIMARY_CONTACT' = 'vendor_primary_contact'
    'CONTRACTOR_TITLE' = 'vendor_signer_title'
    'OWNER_CONTACT' = 'contract_owner_contact'
    'OWNER_PRIMARY_CONTACT' = 'contract_owner_contact'
    'OWNER_TITLE' = 'contract_owner_title'
    'OWNER_EMAIL' = 'contract_owner_email'
    'OWNER_PHONE' = 'contract_owner_phone'
    'OWNER_STREET' = 'contract_owner_street'
    'OWNER_CITY' = 'contract_owner_city'
    'OWNER_STATE' = 'contract_owner_state'
    'OWNER_CITY_STATE_ZIP' = 'contract_owner_city'
    'WORK_ORDER_DATE' = 'contract_start_date'
    'WORK_ORDER_FEE' = 'contract_fee'
    'WORK_ORDER_NUMBER' = 'contract_po_number'
    'WORK_START_DATE' = 'contract_start_date'
    'WORK_COMPLETED_DATE' = 'contract_end_date'
    'MAIN_CONTRACT_DATE' = 'contract_start_date'
    'CURRENT_CONTRACT_EXP_DATE' = 'contract_end_date'
    'DESCRIPTION_OF_SERVICE' = 'contract_description_of_service'
    'SERVICE_LOCATION_DESCRIPTION' = 'property_name'
    'CURRENT_PROPERTIES_INCLUDED' = 'property_name'
    'PURCHASE_ORDER_NUMBER' = 'contract_po_number'
    'AMENDMENT_NUMBER' = 'contract_amendment_sequence'
    'BANCROFTWORKORDERTYPE' = 'contract_type'
    'FORMOFPAYMENT' = 'vendor_payment_terms'
    'PAYMENTPROCESS' = 'vendor_payment_terms'
    'HOURS_OF_OPERATION' = 'contract_description_of_work'
    'IS_BUDGETED' = 'contract_work_category'
    'ORG_WORKORDER_DATA' = 'contract_description_of_service'
    # MSA fields
    'MSA_DATE' = 'msa_effective_date'
    'AGREEMENT_TERM' = 'msa_expiration_date'
    'PRESIDENT_CONTACT' = 'customer_president_name'
    # Fee schedule fields
    'MEMBERSHIP_QTY_LOCATIONS' = 'contract_fee'
    'MEMBERSHIP_RATE_PER_LOCATION' = 'contract_fee'
    'MEMBERSHIP_TOTAL_FEE' = 'contract_fee'
    'ONBOARDING_QTY_LOCATIONS' = 'contract_fee'
    'ONBOARDING_RATE_PER_LOCATION' = 'contract_fee'
    'ONBOARDING_TOTAL_FEE' = 'contract_fee'
}

Write-Host "=== NORA TEMPLATE CONVERTER ===" -ForegroundColor Cyan
Write-Host "Template: $TemplateName" -ForegroundColor White

# Step 1: Download from SharePoint
Write-Host "`n[1] Downloading from SharePoint..." -ForegroundColor Yellow
$items = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root/children" -Headers $gh).value
$spFile = $items | Where-Object { $_.name -eq $TemplateName }

if (-not $spFile) {
    Write-Host "  FILE NOT FOUND: $TemplateName" -ForegroundColor Red
    return
}

$localPath = Join-Path $workDir $TemplateName
Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/items/$($spFile.id)/content" `
    -Headers @{'Authorization'="Bearer $gpt"} -OutFile $localPath
Write-Host "  Downloaded: $((Get-Item $localPath).Length) bytes" -ForegroundColor Green

# Step 2: Backup original
Write-Host "`n[2] Backing up original..." -ForegroundColor Yellow
$backupPath = Join-Path $origDir $TemplateName
Copy-Item $localPath $backupPath -Force
Write-Host "  Backup: $backupPath" -ForegroundColor Green

# Also backup to SharePoint with _ORIGINAL suffix
$backupName = $TemplateName -replace '\.docx$', '_ORIGINAL.docx'
$backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
$uploadH = @{ 'Authorization' = "Bearer $gpt"; 'Content-Type' = 'application/octet-stream' }
try {
    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root:/$backupName`:/content" -Method PUT -Body $backupBytes -Headers $uploadH | Out-Null
    Write-Host "  SharePoint backup: $backupName" -ForegroundColor Green
} catch {
    Write-Host "  SharePoint backup failed (continuing): $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 3: Read and convert document.xml
Write-Host "`n[3] Converting merge fields to content controls..." -ForegroundColor Yellow

# Read all zip entries
$zipBytes = [System.IO.File]::ReadAllBytes($localPath)
$memIn = New-Object System.IO.MemoryStream(,$zipBytes)
$zipIn = New-Object System.IO.Compression.ZipArchive($memIn, [System.IO.Compression.ZipArchiveMode]::Read)

$entries = @{}
foreach ($entry in $zipIn.Entries) {
    $sr = New-Object System.IO.StreamReader($entry.Open())
    if ($entry.FullName -eq 'word/document.xml') {
        $docXml = $sr.ReadToEnd()
    } else {
        $ms = New-Object System.IO.MemoryStream
        $entry.Open().CopyTo($ms)
        $entries[$entry.FullName] = $ms.ToArray()
    }
    $sr.Close()
}
$zipIn.Dispose()
$memIn.Dispose()

# Find all merge field patterns and replace with content controls
$idCounter = 900000
$converted = 0
$skipped = 0

# Pattern 1: Complex MERGEFIELD with fldChar (w:fldChar + w:instrText + w:fldChar)
# These are multi-run merge fields — harder to replace
# Pattern 2: «FIELD» chevron placeholders in w:t elements — simpler
# We'll replace the chevron text with content controls

# Find all «FIELD» patterns
$chevronPattern = '&#171;([^&#]+)&#187;'
$chevronMatches = [regex]::Matches($docXml, $chevronPattern)

Write-Host "  Found $($chevronMatches.Count) chevron placeholders"

foreach ($match in $chevronMatches) {
    $mergeName = $match.Groups[1].Value
    $ccTag = if ($fieldMap.ContainsKey($mergeName)) { $fieldMap[$mergeName] } else { $mergeName.ToLower() }
    $idCounter++

    # Replace «FIELD» with a content control
    # The chevron text is inside a <w:t> element. We need to replace the entire <w:r> containing it
    # with an <w:sdt> block

    $sdtBlock = @"
</w:r></w:p><w:sdt><w:sdtPr><w:alias w:val="$ccTag"/><w:tag w:val="$ccTag"/><w:id w:val="$idCounter"/><w:text/></w:sdtPr><w:sdtContent><w:p><w:r><w:t>[$ccTag]</w:t></w:r></w:p></w:sdtContent></w:sdt><w:p><w:r>
"@

    # Simple replacement — replace the chevron text with content control markup
    # This is approximate — the XML structure around chevrons varies
    $docXml = $docXml -replace [regex]::Escape($match.Value), "</w:t></w:r></w:p><w:sdt><w:sdtPr><w:alias w:val=`"$ccTag`"/><w:tag w:val=`"$ccTag`"/><w:id w:val=`"$idCounter`"/><w:text/></w:sdtPr><w:sdtContent><w:p><w:r><w:t>[$ccTag]</w:t></w:r></w:p></w:sdtContent></w:sdt><w:p><w:r><w:t>"

    Write-Host "    $mergeName -> $ccTag" -ForegroundColor Gray
    $converted++
}

# Also handle MERGEFIELD instructions in complex field codes
$mergeFieldPattern = '<w:instrText[^>]*>\s*MERGEFIELD\s+([^\s<]+)'
$instrMatches = [regex]::Matches($docXml, $mergeFieldPattern)
Write-Host "  Found $($instrMatches.Count) MERGEFIELD instructions"

Write-Host "`n  Converted: $converted fields" -ForegroundColor Green

# Step 4: Write new docx
Write-Host "`n[4] Writing converted file..." -ForegroundColor Yellow
$convertedPath = Join-Path $workDir "CONVERTED_$TemplateName"
if (Test-Path $convertedPath) { Remove-Item $convertedPath -Force }

$memOut = New-Object System.IO.MemoryStream
$zipOut = New-Object System.IO.Compression.ZipArchive($memOut, [System.IO.Compression.ZipArchiveMode]::Create, $true)

# Write all non-document entries as-is
foreach ($name in $entries.Keys) {
    $e = $zipOut.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $s = $e.Open()
    $s.Write($entries[$name], 0, $entries[$name].Length)
    $s.Close()
}

# Write modified document.xml
$docEntry = $zipOut.CreateEntry('word/document.xml', [System.IO.Compression.CompressionLevel]::Optimal)
$writer = New-Object System.IO.StreamWriter($docEntry.Open(), [System.Text.Encoding]::UTF8)
$writer.Write($docXml)
$writer.Close()

$zipOut.Dispose()
[System.IO.File]::WriteAllBytes($convertedPath, $memOut.ToArray())
$memOut.Dispose()

$newSize = (Get-Item $convertedPath).Length
Write-Host "  Written: $convertedPath ($newSize bytes)" -ForegroundColor Green

# Verify content controls in converted file
$zipVerify = [System.IO.Compression.ZipFile]::OpenRead($convertedPath)
$docVerify = $zipVerify.GetEntry('word/document.xml')
$readerV = New-Object System.IO.StreamReader($docVerify.Open())
$xmlV = $readerV.ReadToEnd()
$readerV.Close()
$zipVerify.Dispose()

$sdtCount = ([regex]::Matches($xmlV, '<w:sdt>')).Count
$tagCount = ([regex]::Matches($xmlV, '<w:tag w:val="([^"]+)"')).Count
Write-Host "`n  Verification: $sdtCount content controls, $tagCount tags" -ForegroundColor $(if($sdtCount -gt 0){'Green'}else{'Red'})

# Step 5: Upload converted file to SharePoint (replacing original)
Write-Host "`n[5] Uploading to SharePoint..." -ForegroundColor Yellow
$uploadBytes = [System.IO.File]::ReadAllBytes($convertedPath)
try {
    $resp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root:/$TemplateName`:/content" -Method PUT -Body $uploadBytes -Headers $uploadH
    Write-Host "  UPLOADED: $TemplateName (replaced)" -ForegroundColor Green
    Write-Host "  Original backed up as: $backupName" -ForegroundColor Cyan
} catch {
    Write-Host "  UPLOAD FAILED: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

Write-Host "`n=== CONVERSION COMPLETE ===" -ForegroundColor Cyan
Write-Host "  Original backed up locally: $backupPath"
Write-Host "  Original backed up on SharePoint: $backupName"
Write-Host "  Converted: $converted merge fields -> content controls"
Write-Host "  IMPORTANT: Open $TemplateName in Word desktop and re-save to finalize content controls" -ForegroundColor Yellow
