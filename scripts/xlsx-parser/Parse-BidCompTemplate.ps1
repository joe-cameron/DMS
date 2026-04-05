<#
.SYNOPSIS
    Parses the DCG Multi Trade Bid Template xlsx into a complete structural schema JSON.
.DESCRIPTION
    Unzips the xlsx as Open XML, reads all sheets (cells, formulas, merges,
    data validations, styles, frozen panes, column widths), and outputs a
    verified JSON schema — the ground truth for producing and parsing bid comp spreadsheets.
.PARAMETER XlsxPath
    Path to the source xlsx template
.PARAMETER OutputPath
    Path to write the schema JSON
#>
param(
    [string]$XlsxPath = "C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx",
    [string]$OutputPath = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json"
)

$ErrorActionPreference = 'Stop'

# --- Unzip and discover ---
$tempDir = Join-Path $env:TEMP "xlsx_parse_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Copy-Item $XlsxPath "$tempDir\template.zip"
    Expand-Archive "$tempDir\template.zip" -DestinationPath "$tempDir\extracted" -Force

    # Read workbook.xml for sheet names and order
    [xml]$workbook = Get-Content "$tempDir\extracted\xl\workbook.xml"
    $nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    $nsRel  = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $ns = @{ s = $nsMain }

    $sheets = @()
    $sheetNodes = Select-Xml -Xml $workbook -XPath "//s:sheet" -Namespace $ns
    foreach ($node in $sheetNodes) {
        $sheets += @{
            name    = $node.Node.name
            sheetId = $node.Node.sheetId
            rId     = $node.Node.GetAttribute("id", $nsRel)
        }
    }

    # Read shared strings
    $sstPath = "$tempDir\extracted\xl\sharedStrings.xml"
    $sharedStrings = @()
    if (Test-Path $sstPath) {
        [xml]$sst = Get-Content $sstPath
        foreach ($si in $sst.sst.si) {
            if ($si.t) {
                $sharedStrings += if ($si.t.'#text') { $si.t.'#text' } else { "$($si.t)" }
            }
            elseif ($si.r) {
                $parts = @()
                foreach ($run in $si.r) {
                    $parts += if ($run.t.'#text') { $run.t.'#text' } else { "$($run.t)" }
                }
                $sharedStrings += ($parts -join '')
            }
            else { $sharedStrings += '' }
        }
    }

    Write-Host "Found $($sheets.Count) sheets, $($sharedStrings.Count) shared strings"

    # --- Parse worksheet function ---
    function Parse-Worksheet {
        param([string]$SheetPath, [string[]]$SharedStrings)

        [xml]$sheet = Get-Content $SheetPath
        $ns = @{ s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main' }

        $cells = [System.Collections.ArrayList]::new()
        $merges = [System.Collections.ArrayList]::new()
        $dataValidations = [System.Collections.ArrayList]::new()

        # Parse cells
        $rows = Select-Xml -Xml $sheet -XPath "//s:sheetData/s:row" -Namespace $ns
        foreach ($row in $rows) {
            $rowNum = [int]$row.Node.r
            $cellNodes = Select-Xml -Xml $row.Node -XPath "s:c" -Namespace $ns
            foreach ($c in $cellNodes) {
                $ref    = $c.Node.r
                $type   = $c.Node.t
                $style  = $c.Node.s
                $formula = $null
                $value   = $null

                # Get formula if present
                $fNode = Select-Xml -Xml $c.Node -XPath "s:f" -Namespace $ns
                if ($fNode) {
                    $fText = $fNode.Node.'#text'
                    if ($fNode.Node.t -eq 'shared') {
                        $formula = @{
                            type    = 'shared'
                            si      = $fNode.Node.si
                            ref     = $fNode.Node.ref
                            formula = $fText
                        }
                    } else {
                        $formula = $fText
                    }
                }

                # Get value
                $vNode = Select-Xml -Xml $c.Node -XPath "s:v" -Namespace $ns
                if ($vNode) {
                    $rawValue = $vNode.Node.'#text'
                    if ($type -eq 's' -and $rawValue -match '^\d+$') {
                        $idx = [int]$rawValue
                        $value = if ($idx -lt $SharedStrings.Count) { $SharedStrings[$idx] } else { $rawValue }
                    } else {
                        $value = $rawValue
                    }
                }

                [void]$cells.Add(@{
                    ref     = $ref
                    row     = $rowNum
                    col     = ($ref -replace '[0-9]', '')
                    type    = $type
                    style   = $style
                    value   = $value
                    formula = $formula
                })
            }
        }

        # Parse merged cells
        $mergeNodes = Select-Xml -Xml $sheet -XPath "//s:mergeCells/s:mergeCell" -Namespace $ns
        foreach ($m in $mergeNodes) {
            [void]$merges.Add($m.Node.ref)
        }

        # Parse data validations
        $dvNodes = Select-Xml -Xml $sheet -XPath "//s:dataValidations/s:dataValidation" -Namespace $ns
        foreach ($dv in $dvNodes) {
            [void]$dataValidations.Add(@{
                sqref    = $dv.Node.sqref
                type     = $dv.Node.type
                formula1 = (Select-Xml -Xml $dv.Node -XPath "s:formula1" -Namespace $ns).Node.'#text'
            })
        }

        # Parse frozen panes
        $pane = Select-Xml -Xml $sheet -XPath "//s:sheetViews/s:sheetView/s:pane" -Namespace $ns
        $frozenPane = if ($pane) {
            @{
                ySplit      = $pane.Node.ySplit
                xSplit      = $pane.Node.xSplit
                topLeftCell = $pane.Node.topLeftCell
            }
        } else { $null }

        # Parse column widths
        $cols = Select-Xml -Xml $sheet -XPath "//s:cols/s:col" -Namespace $ns
        $colWidths = [System.Collections.ArrayList]::new()
        foreach ($col in $cols) {
            [void]$colWidths.Add(@{
                min    = $col.Node.min
                max    = $col.Node.max
                width  = $col.Node.width
                hidden = $col.Node.hidden -eq '1'
            })
        }

        # Parse conditional formatting
        $cfNodes = Select-Xml -Xml $sheet -XPath "//s:conditionalFormatting" -Namespace $ns
        $conditionalFormats = [System.Collections.ArrayList]::new()
        foreach ($cf in $cfNodes) {
            $rules = Select-Xml -Xml $cf.Node -XPath "s:cfRule" -Namespace $ns
            foreach ($rule in $rules) {
                [void]$conditionalFormats.Add(@{
                    sqref    = $cf.Node.sqref
                    type     = $rule.Node.type
                    priority = $rule.Node.priority
                    dxfId    = $rule.Node.dxfId
                    formula  = (Select-Xml -Xml $rule.Node -XPath "s:formula" -Namespace $ns).Node.'#text'
                })
            }
        }

        # Parse print area / page setup
        $pageSetup = Select-Xml -Xml $sheet -XPath "//s:pageSetup" -Namespace $ns
        $printSetup = if ($pageSetup) {
            @{
                orientation = $pageSetup.Node.orientation
                paperSize   = $pageSetup.Node.paperSize
                scale       = $pageSetup.Node.scale
                fitToWidth  = $pageSetup.Node.fitToWidth
                fitToHeight = $pageSetup.Node.fitToHeight
            }
        } else { $null }

        return @{
            cells               = $cells.ToArray()
            mergedCells         = $merges.ToArray()
            dataValidations     = $dataValidations.ToArray()
            frozenPane          = $frozenPane
            columnWidths        = $colWidths.ToArray()
            conditionalFormats  = $conditionalFormats.ToArray()
            printSetup          = $printSetup
            rowCount            = ($rows | Measure-Object).Count
        }
    }

    # --- Read relationship file to map rId to sheet file ---
    [xml]$rels = Get-Content "$tempDir\extracted\xl\_rels\workbook.xml.rels"
    $sheetFiles = @{}
    foreach ($rel in $rels.Relationships.Relationship) {
        $sheetFiles[$rel.Id] = $rel.Target
    }

    # --- Parse all sheets ---
    $schema = @{
        templateName  = "DCG_Multi_Trade_Bid_Template"
        version       = "1"
        parsedAt      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        sourceFile    = (Split-Path $XlsxPath -Leaf)
        sharedStrings = $sharedStrings
        sheets        = [ordered]@{}
    }

    foreach ($sheet in $sheets) {
        $sheetFile = $sheetFiles[$sheet.rId]
        if (-not $sheetFile) {
            Write-Host "  SKIP: $($sheet.name) — no relationship target"
            continue
        }
        $sheetPath = Join-Path "$tempDir\extracted\xl" $sheetFile

        if (-not (Test-Path $sheetPath)) {
            Write-Host "  SKIP: $($sheet.name) — file not found: $sheetFile"
            continue
        }

        Write-Host "  Parsing: $($sheet.name) from $sheetFile"
        $parsed = Parse-Worksheet -SheetPath $sheetPath -SharedStrings $sharedStrings

        $schema.sheets[$sheet.name] = @{
            sheetId            = $sheet.sheetId
            rId                = $sheet.rId
            file               = $sheetFile
            cells              = $parsed.cells
            mergedCells        = $parsed.mergedCells
            dataValidations    = $parsed.dataValidations
            frozenPane         = $parsed.frozenPane
            columnWidths       = $parsed.columnWidths
            conditionalFormats = $parsed.conditionalFormats
            printSetup         = $parsed.printSetup
            rowCount           = $parsed.rowCount
            cellCount          = $parsed.cells.Count
        }
    }

    # --- Ensure output directory exists ---
    $outDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    # --- Save schema ---
    $schema | ConvertTo-Json -Depth 12 -Compress:$false | Set-Content $OutputPath -Encoding UTF8
    Write-Host "`nSchema saved to $OutputPath"
    Write-Host "Total sheets: $($schema.sheets.Count)"

    $totalCells = 0
    $totalFormulas = 0
    $totalMerges = 0
    foreach ($s in $schema.sheets.Values) {
        $totalCells += $s.cellCount
        $totalFormulas += ($s.cells | Where-Object { $_.formula }).Count
        $totalMerges += $s.mergedCells.Count
    }
    Write-Host "Total cells: $totalCells"
    Write-Host "Total formulas: $totalFormulas"
    Write-Host "Total merged ranges: $totalMerges"

} finally {
    # Cleanup
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
