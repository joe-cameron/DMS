# =============================================================================
# Nora Template Converter v2 — Replace complex MERGEFIELD sequences with content controls
# Handles: fldChar(begin) → instrText → fldChar(separate) → display text → fldChar(end)
# ALWAYS backs up originals first
# =============================================================================
param(
    [string]$TemplateName = 'BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx'
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$graphToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -AsSecureString)
$gpt = [System.Net.NetworkCredential]::new('', $graphToken.Token).Password
$driveId = 'b!lGCVWRjYlkiGjk72z8d6szyNF3B4WKtIo0BTKeaWw-k0gmQTkZA9QKdMLo-aANXH'
$origDir = 'C:\DCFG\nora\templates\originals'
$workDir = 'C:\DCFG\nora\templates'

# Field mapping
$fieldMap = @{
    'CLIENT_NAME' = 'contract_client_name'
    'CONTRACTOR_NAME' = 'contract_contractor_name'
    'CONTRACTOR_LEGAL_NAME' = 'contract_contractor_legal_name'
    'CONTRACTOR_ADDRESS' = 'vendor_address'
    'CONTRACTOR_EMAIL' = 'vendor_email'
    'CONTRCTOR_PHONE' = 'vendor_phone'
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
    'MSA_DATE' = 'msa_effective_date'
    'AGREEMENT_TERM' = 'msa_expiration_date'
    'PRESIDENT_CONTACT' = 'customer_president_name'
    'MEMBERSHIP_QTY_LOCATIONS' = 'membership_qty'
    'MEMBERSHIP_RATE_PER_LOCATION' = 'membership_rate'
    'MEMBERSHIP_TOTAL_FEE' = 'membership_total'
    'ONBOARDING_QTY_LOCATIONS' = 'onboarding_qty'
    'ONBOARDING_RATE_PER_LOCATION' = 'onboarding_rate'
    'ONBOARDING_TOTAL_FEE' = 'onboarding_total'
}

Write-Host "=== NORA TEMPLATE CONVERTER v2 ===" -ForegroundColor Cyan
Write-Host "Template: $TemplateName"

# Download original from backup (not the one we may have corrupted)
$origPath = Join-Path $origDir $TemplateName
if (-not (Test-Path $origPath)) {
    Write-Host "Downloading original from SharePoint..." -ForegroundColor Yellow
    # Try the _ORIGINAL backup first
    $backupName = $TemplateName -replace '\.docx$', '_ORIGINAL.docx'
    $items = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root/children" -Headers @{'Authorization'="Bearer $gpt";'Accept'='application/json'}).value
    $origFile = $items | Where-Object { $_.name -eq $backupName }
    if (-not $origFile) { $origFile = $items | Where-Object { $_.name -eq $TemplateName } }
    if ($origFile) {
        Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/items/$($origFile.id)/content" -Headers @{'Authorization'="Bearer $gpt"} -OutFile $origPath
        Write-Host "  Downloaded: $((Get-Item $origPath).Length) bytes" -ForegroundColor Green
    } else {
        Write-Host "  FILE NOT FOUND" -ForegroundColor Red; return
    }
}

# Read document.xml
$zip = [System.IO.Compression.ZipFile]::OpenRead($origPath)
$docEntry = $zip.GetEntry('word/document.xml')
$reader = New-Object System.IO.StreamReader($docEntry.Open())
$xml = $reader.ReadToEnd()
$reader.Close()

# Read all other entries as bytes
$otherEntries = @{}
foreach ($entry in $zip.Entries) {
    if ($entry.FullName -eq 'word/document.xml') { continue }
    $ms = New-Object System.IO.MemoryStream
    $s = $entry.Open()
    $s.CopyTo($ms)
    $s.Close()
    $otherEntries[$entry.FullName] = $ms.ToArray()
    $ms.Dispose()
}
$zip.Dispose()

# Replace complex field code sequences with content controls
# Pattern: <w:r ...><w:fldChar type="begin"/></w:r>
#          <w:r ...><w:instrText>MERGEFIELD NAME</w:instrText></w:r>
#          <w:r ...><w:fldChar type="separate"/></w:r>
#          <w:r ...><w:t>display text</w:t></w:r>
#          <w:r ...><w:fldChar type="end"/></w:r>

# The regex needs to match the entire begin→end sequence across multiple <w:r> elements
$mergePattern = '(<w:r[^>]*>(?:<w:rPr>.*?</w:rPr>)?<w:fldChar w:fldCharType="begin"/>)</w:r>(.*?<w:instrText[^>]*>\s*MERGEFIELD\s+(\w+)\s+[^<]*</w:instrText>.*?<w:fldChar w:fldCharType="end"/>)</w:r>'

$idCounter = 800000
$converted = 0

$xml = [regex]::Replace($xml, $mergePattern, {
    param($m)
    $fieldName = $m.Groups[3].Value.Trim()
    $ccTag = if ($fieldMap.ContainsKey($fieldName)) { $fieldMap[$fieldName] } else { $fieldName.ToLower() }
    $script:idCounter++
    $script:converted++

    Write-Host "  $fieldName -> $ccTag" -ForegroundColor Gray

    # Return a content control instead of the field code
    return "<w:sdt><w:sdtPr><w:alias w:val=`"$ccTag`"/><w:tag w:val=`"$ccTag`"/><w:id w:val=`"$($script:idCounter)`"/><w:placeholder><w:docPart w:val=`"DefaultPlaceholder_-1854013440`"/></w:placeholder><w:text/></w:sdtPr><w:sdtContent><w:r><w:t>[$ccTag]</w:t></w:r></w:sdtContent></w:sdt>"
}, [System.Text.RegularExpressions.RegexOptions]::Singleline)

Write-Host "`n  Converted: $converted fields" -ForegroundColor $(if($converted -gt 0){'Green'}else{'Red'})

if ($converted -eq 0) {
    # Try a simpler pattern — sometimes the runs are structured differently
    Write-Host "  Trying alternate pattern..." -ForegroundColor Yellow

    # Match each instrText individually and replace the surrounding field code structure
    $instrPattern = '<w:instrText[^>]*>\s*MERGEFIELD\s+(\w+)\s+[^<]*</w:instrText>'
    $instrMatches = [regex]::Matches($xml, $instrPattern)

    foreach ($im in $instrMatches) {
        $fieldName = $im.Groups[1].Value.Trim()
        $ccTag = if ($fieldMap.ContainsKey($fieldName)) { $fieldMap[$fieldName] } else { $fieldName.ToLower() }
        $idCounter++

        # Find the enclosing begin...end sequence by searching backwards from instrText for begin and forward for end
        $instrPos = $im.Index

        # Find the fldChar begin before this instrText
        $beginPattern = '<w:fldChar w:fldCharType="begin"/>'
        $lastBegin = $xml.LastIndexOf($beginPattern, $instrPos)

        # Find the fldChar end after this instrText
        $endPattern = '<w:fldChar w:fldCharType="end"/>'
        $nextEnd = $xml.IndexOf($endPattern, $instrPos)

        if ($lastBegin -gt 0 -and $nextEnd -gt 0) {
            # Find the <w:r that contains the begin
            $rStartBegin = $xml.LastIndexOf('<w:r', $lastBegin)
            # Find the </w:r> after the end
            $rEndAfter = $xml.IndexOf('</w:r>', $nextEnd) + 6

            if ($rStartBegin -gt 0 -and $rEndAfter -gt $rStartBegin) {
                $oldBlock = $xml.Substring($rStartBegin, $rEndAfter - $rStartBegin)
                $newBlock = "<w:sdt><w:sdtPr><w:alias w:val=`"$ccTag`"/><w:tag w:val=`"$ccTag`"/><w:id w:val=`"$idCounter`"/><w:placeholder><w:docPart w:val=`"DefaultPlaceholder_-1854013440`"/></w:placeholder><w:text/></w:sdtPr><w:sdtContent><w:r><w:t>[$ccTag]</w:t></w:r></w:sdtContent></w:sdt>"

                $xml = $xml.Replace($oldBlock, $newBlock)
                $converted++
                Write-Host "  $fieldName -> $ccTag (alt)" -ForegroundColor Gray
            }
        }
    }
    Write-Host "  Alt converted: $converted fields" -ForegroundColor $(if($converted -gt 0){'Green'}else{'Red'})
}

# Write new docx
$convertedPath = Join-Path $workDir "CONVERTED_$TemplateName"
if (Test-Path $convertedPath) { Remove-Item $convertedPath -Force }

$memOut = New-Object System.IO.MemoryStream
$zipOut = New-Object System.IO.Compression.ZipArchive($memOut, [System.IO.Compression.ZipArchiveMode]::Create, $true)

foreach ($name in $otherEntries.Keys) {
    $e = $zipOut.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $s = $e.Open()
    $s.Write($otherEntries[$name], 0, $otherEntries[$name].Length)
    $s.Close()
}

$docE = $zipOut.CreateEntry('word/document.xml', [System.IO.Compression.CompressionLevel]::Optimal)
$w = New-Object System.IO.StreamWriter($docE.Open(), [System.Text.Encoding]::UTF8)
$w.Write($xml)
$w.Close()
$zipOut.Dispose()

[System.IO.File]::WriteAllBytes($convertedPath, $memOut.ToArray())
$memOut.Dispose()

# Verify
$zipV = [System.IO.Compression.ZipFile]::OpenRead($convertedPath)
$docV = $zipV.GetEntry('word/document.xml')
$rv = New-Object System.IO.StreamReader($docV.Open())
$xmlV = $rv.ReadToEnd()
$rv.Close()
$zipV.Dispose()

$sdtCount = ([regex]::Matches($xmlV, '<w:sdt>')).Count
$tags = [regex]::Matches($xmlV, '<w:tag w:val="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
Write-Host "`nVerification: $sdtCount content controls" -ForegroundColor $(if($sdtCount -gt 0){'Green'}else{'Red'})
$tags | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }

# Upload
Write-Host "`nUploading to SharePoint..." -ForegroundColor Yellow
$uploadBytes = [System.IO.File]::ReadAllBytes($convertedPath)
$uploadH = @{ 'Authorization' = "Bearer $gpt"; 'Content-Type' = 'application/octet-stream' }
try {
    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root:/$TemplateName`:/content" -Method PUT -Body $uploadBytes -Headers $uploadH | Out-Null
    Write-Host "UPLOADED: $TemplateName" -ForegroundColor Green
} catch {
    Write-Host "UPLOAD FAILED: $($_.ErrorDetails.Message)" -ForegroundColor Red
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Converted: $converted | Content controls: $sdtCount"
Write-Host "Original backup: $origDir\$TemplateName"
Write-Host "NEXT: Open $TemplateName in Word desktop and re-save" -ForegroundColor Yellow
