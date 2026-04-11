Add-Type -AssemblyName System.IO.Compression

$zip = [System.IO.Compression.ZipFile]::OpenRead('C:\DCFG\nora\templates\originals\BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx')
$doc = $zip.GetEntry('word/document.xml')
$r = New-Object System.IO.StreamReader($doc.Open())
$xml = $r.ReadToEnd()
$r.Close()
$zip.Dispose()

# Find merge field patterns
Write-Host "=== MERGE FIELD XML PATTERNS ===" -ForegroundColor Cyan

# Look for instrText containing MERGEFIELD
$instrMatches = [regex]::Matches($xml, '<w:instrText[^>]*>[^<]*MERGEFIELD[^<]*</w:instrText>')
Write-Host "instrText matches: $($instrMatches.Count)"
foreach ($m in $instrMatches | Select-Object -First 3) {
    Write-Host "  $($m.Value)" -ForegroundColor Gray
}

# Look for fldChar patterns (begin/separate/end)
$fldCharBegin = ([regex]::Matches($xml, '<w:fldChar w:fldCharType="begin"')).Count
Write-Host "`nfldChar begin: $fldCharBegin"

# Look for chevrons in actual text (may be Unicode, not entity)
$unicodeChevron = ([regex]::Matches($xml, '\x{00AB}|\x{00BB}')).Count
Write-Host "Unicode chevrons: $unicodeChevron"

# Entity-encoded chevrons
$entityChevron = ([regex]::Matches($xml, '&#xAB;|&#xBB;|&#171;|&#187;')).Count
Write-Host "Entity chevrons: $entityChevron"

# Show raw text around first MERGEFIELD
$idx = $xml.IndexOf('MERGEFIELD')
if ($idx -gt 0) {
    Write-Host "`n--- XML around first MERGEFIELD (500 chars) ---" -ForegroundColor Yellow
    $start = [Math]::Max(0, $idx - 300)
    Write-Host $xml.Substring($start, 800)
}

# Show full document.xml size
Write-Host "`nDocument.xml size: $($xml.Length) chars"
