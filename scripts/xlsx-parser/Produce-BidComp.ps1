<#
.SYNOPSIS
    Produces a pre-filled bid comp xlsx from the template + project data.
.DESCRIPTION
    Copies the original template, then modifies specific cells with project-specific
    data (scope items, bidder info, project header). All formatting, formulas,
    merges, and styles are preserved from the original.
.PARAMETER TemplatePath
    Path to the original bid comp template xlsx
.PARAMETER SchemaPath
    Path to the parsed schema JSON (for cell position reference)
.PARAMETER OutputPath
    Path to write the produced xlsx
.PARAMETER ProjectData
    JSON file or inline hashtable with project data
#>
param(
    [string]$TemplatePath = "C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx",
    [string]$SchemaPath   = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json",
    [string]$OutputPath   = "C:\DCFG\tmp\test_bid_comp_output.xlsx",
    [string]$ProjectDataJson = $null
)

$ErrorActionPreference = 'Stop'
$nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$ns = @{ s = $nsMain }

# --- Default test project data ---
$ProjectData = if ($ProjectDataJson -and (Test-Path $ProjectDataJson)) {
    Get-Content $ProjectDataJson -Raw | ConvertFrom-Json -AsHashtable
} else {
    @{
        projectName = "Test Project - 599 Sorenson Dr"
        location    = "Carneys Point, NJ 08069"
        date        = (Get-Date -Format "MM/dd/yyyy")
        rfpNumber   = "RFP-2026-001"
        trades      = @{
            "Carpentry" = @{
                csi        = "6100"
                scopeItems = @(
                    "Layout and frame partition walls per plans"
                    "Furnish and install drywall to roof deck"
                    "Tape and spackle - paint ready"
                    "Install door frames and hardware"
                    "Install base trim and shoe molding"
                )
                bidders = @(
                    @{ name = "Starr General Contracting"; license = "13VH123456"; contact = "Mary Kate / mk@starr.com" }
                    @{ name = "Rahn Companies"; license = "13VH789012"; contact = "Matt Rahn / matt@rahn.com" }
                )
            }
            "Plumbing" = @{
                csi        = "22002"
                scopeItems = @(
                    "Rough-in plumbing per plans"
                    "Furnish and install fixtures"
                    "Water heater replacement"
                    "Backflow preventer install"
                )
                bidders = @(
                    @{ name = "GPS Plumbing & Heating"; license = "36BI456789"; contact = "Greg / greg@gpsplumbing.com" }
                    @{ name = "Hess Plumbing"; license = "36BI111222"; contact = "Dave Hess / dave@hessplumb.com" }
                    @{ name = "A-1 Plumbing"; license = "36BI333444"; contact = "Tony / tony@a1plumb.com" }
                )
            }
        }
    }
}

# Load schema for reference
$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json

# --- Helper: update or create a cell in sheet XML ---
function Set-CellValue {
    param(
        [xml]$SheetXml,
        [string]$CellRef,
        [string]$Value,
        [string]$Type = 'inlineStr'
    )

    $rowNum = [int]($CellRef -replace '[A-Z]', '')
    $sheetData = Select-Xml -Xml $SheetXml -XPath "//s:sheetData" -Namespace $ns

    # Find or create row
    $row = Select-Xml -Xml $SheetXml -XPath "//s:sheetData/s:row[@r='$rowNum']" -Namespace $ns
    if (-not $row) {
        $newRow = $SheetXml.CreateElement("row", $nsMain)
        $newRow.SetAttribute("r", $rowNum)
        # Insert in order
        $existingRows = Select-Xml -Xml $SheetXml -XPath "//s:sheetData/s:row" -Namespace $ns
        $inserted = $false
        foreach ($er in $existingRows) {
            if ([int]$er.Node.r -gt $rowNum) {
                $sheetData.Node.InsertBefore($newRow, $er.Node) | Out-Null
                $inserted = $true
                break
            }
        }
        if (-not $inserted) { $sheetData.Node.AppendChild($newRow) | Out-Null }
        $row = Select-Xml -Xml $SheetXml -XPath "//s:sheetData/s:row[@r='$rowNum']" -Namespace $ns
    }

    # Find or create cell
    $cell = Select-Xml -Xml $row.Node -XPath "s:c[@r='$CellRef']" -Namespace $ns
    if (-not $cell) {
        $newCell = $SheetXml.CreateElement("c", $nsMain)
        $newCell.SetAttribute("r", $CellRef)
        $row.Node.AppendChild($newCell) | Out-Null
        $cell = Select-Xml -Xml $row.Node -XPath "s:c[@r='$CellRef']" -Namespace $ns
    }

    if ($Type -eq 'inlineStr') {
        # Use inline string — avoids shared string table modification
        $cell.Node.SetAttribute("t", "inlineStr")
        # Remove any existing <v> element
        $existingV = Select-Xml -Xml $cell.Node -XPath "s:v" -Namespace $ns
        if ($existingV) { $cell.Node.RemoveChild($existingV.Node) | Out-Null }
        # Remove any existing <is> element
        $existingIs = Select-Xml -Xml $cell.Node -XPath "s:is" -Namespace $ns
        if ($existingIs) { $cell.Node.RemoveChild($existingIs.Node) | Out-Null }
        # Add <is><t>value</t></is>
        $isElem = $SheetXml.CreateElement("is", $nsMain)
        $tElem  = $SheetXml.CreateElement("t", $nsMain)
        $tElem.InnerText = $Value
        $isElem.AppendChild($tElem) | Out-Null
        $cell.Node.AppendChild($isElem) | Out-Null
    }
    elseif ($Type -eq 'number') {
        # Remove 't' attribute if present, set <v>
        if ($cell.Node.HasAttribute("t")) { $cell.Node.RemoveAttribute("t") }
        $existingIs = Select-Xml -Xml $cell.Node -XPath "s:is" -Namespace $ns
        if ($existingIs) { $cell.Node.RemoveChild($existingIs.Node) | Out-Null }
        $vNode = Select-Xml -Xml $cell.Node -XPath "s:v" -Namespace $ns
        if (-not $vNode) {
            $vElem = $SheetXml.CreateElement("v", $nsMain)
            $cell.Node.AppendChild($vElem) | Out-Null
            $vNode = Select-Xml -Xml $cell.Node -XPath "s:v" -Namespace $ns
        }
        $vNode.Node.InnerText = $Value
    }
}

# --- Main production ---
$tempDir = Join-Path $env:TEMP "xlsx_produce_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # Copy and extract template
    Copy-Item $TemplatePath "$tempDir\template.zip"
    Expand-Archive "$tempDir\template.zip" -DestinationPath "$tempDir\work" -Force

    # Read workbook relationships to map sheet names to files
    [xml]$workbook = Get-Content "$tempDir\work\xl\workbook.xml"
    $nsRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $wbSheets = @{}
    $sheetNodes = Select-Xml -Xml $workbook -XPath "//s:sheet" -Namespace $ns
    foreach ($node in $sheetNodes) {
        $rId = $node.Node.GetAttribute("id", $nsRel)
        $wbSheets[$node.Node.name] = $rId
    }

    [xml]$rels = Get-Content "$tempDir\work\xl\_rels\workbook.xml.rels"
    $sheetFiles = @{}
    foreach ($rel in $rels.Relationships.Relationship) {
        $sheetFiles[$rel.Id] = $rel.Target
    }

    # Map sheet name -> file path
    $sheetPaths = @{}
    foreach ($name in $wbSheets.Keys) {
        $rId = $wbSheets[$name]
        $file = $sheetFiles[$rId]
        if ($file) { $sheetPaths[$name] = Join-Path "$tempDir\work\xl" $file }
    }

    # Known cell layout from schema analysis:
    # Row 3, col B = Project/Location header
    # Row 5, col B = Date
    # Row 9, cols D/F/H/J/L = Bidder names (up to 5)
    # Row 10, cols D/F/H/J/L = Status
    # Row 11, cols D/F/H/J/L = License #
    # Row 12, cols D/F/H/J/L = Contact / Email
    # Rows 14-45 = Scope item descriptions (col B) and Y/N responses (bidder cols)

    $bidderCols = @('D','F','H','J','L')
    $modifiedSheets = 0

    foreach ($tradeName in $ProjectData.trades.Keys) {
        $trade = $ProjectData.trades[$tradeName]
        $sheetPath = $sheetPaths[$tradeName]

        if (-not $sheetPath -or -not (Test-Path $sheetPath)) {
            Write-Host "  SKIP: $tradeName — sheet not found in template"
            continue
        }

        Write-Host "  Populating: $tradeName"
        [xml]$sheetXml = Get-Content $sheetPath

        # Project header (row 3, col B)
        Set-CellValue -SheetXml $sheetXml -CellRef "B3" -Value "$($ProjectData.projectName) — $($ProjectData.location)"

        # Date (row 5, col B)
        Set-CellValue -SheetXml $sheetXml -CellRef "B5" -Value "Date: $($ProjectData.date)"

        # Scope items (rows 14+)
        $scopeRow = 14
        foreach ($item in $trade.scopeItems) {
            Set-CellValue -SheetXml $sheetXml -CellRef "B$scopeRow" -Value $item
            $scopeRow++
        }

        # Bidder info
        $bidders = if ($trade.bidders -is [System.Collections.IEnumerable] -and $trade.bidders -isnot [string]) {
            @($trade.bidders)
        } else { @() }

        for ($i = 0; $i -lt [Math]::Min($bidders.Count, 5); $i++) {
            $col = $bidderCols[$i]
            $bidder = $bidders[$i]

            $bName    = if ($bidder.name)    { $bidder.name }    else { "$bidder" }
            $bLicense = if ($bidder.license)  { $bidder.license }  else { "" }
            $bContact = if ($bidder.contact)  { $bidder.contact }  else { "" }

            Set-CellValue -SheetXml $sheetXml -CellRef "${col}9"  -Value $bName
            Set-CellValue -SheetXml $sheetXml -CellRef "${col}10" -Value "Bidding"
            Set-CellValue -SheetXml $sheetXml -CellRef "${col}11" -Value $bLicense
            Set-CellValue -SheetXml $sheetXml -CellRef "${col}12" -Value $bContact
        }

        # Save modified sheet
        $sheetXml.Save($sheetPath)
        $modifiedSheets++
    }

    # Ensure output directory exists
    $outDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    # Rezip to xlsx — must use .NET ZipFile for proper xlsx structure
    # (Compress-Archive can produce invalid xlsx in some cases)
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Remove existing output if present
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        "$tempDir\work",
        $OutputPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false  # don't include base directory name
    )

    Write-Host "`nProduced: $OutputPath"
    Write-Host "Modified $modifiedSheets trade sheets"
    Write-Host "File size: $([math]::Round((Get-Item $OutputPath).Length / 1024, 1)) KB"

} finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
