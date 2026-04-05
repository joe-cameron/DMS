<#
.SYNOPSIS
    Cell-by-cell structural comparison between an original and produced xlsx.
.DESCRIPTION
    The auto-research quality gate. Compares formulas, merged cells, data validations,
    column widths, and cell structure. Reports mismatches by category.
    Injected data cells (inline strings) are expected to differ and are reported
    separately from structural issues.
.PARAMETER OriginalPath
    Path to the original template xlsx
.PARAMETER ProducedPath
    Path to the produced xlsx to verify
#>
param(
    [string]$OriginalPath = "C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx",
    [string]$ProducedPath = "C:\DCFG\tmp\test_bid_comp_output.xlsx"
)

$ErrorActionPreference = 'Stop'
$nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'

function Extract-SheetStructure {
    param([string]$XlsxPath)

    $tempDir = Join-Path $env:TEMP "xlsx_cmp_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Copy-Item $XlsxPath "$tempDir\file.zip"
    Expand-Archive "$tempDir\file.zip" -DestinationPath "$tempDir\ex" -Force

    # Read workbook for sheet names
    [xml]$workbook = Get-Content "$tempDir\ex\xl\workbook.xml"
    $nsm = New-Object System.Xml.XmlNamespaceManager($workbook.NameTable)
    $nsm.AddNamespace("s", $nsMain)
    $nsRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

    $sheetMap = @{}
    foreach ($node in $workbook.SelectNodes('//s:sheet', $nsm)) {
        $rId = $node.GetAttribute("id", $nsRel)
        $sheetMap[$node.name] = $rId
    }

    [xml]$rels = Get-Content "$tempDir\ex\xl\_rels\workbook.xml.rels"
    $fileMap = @{}
    foreach ($r in $rels.Relationships.Relationship) { $fileMap[$r.Id] = $r.Target }

    $result = [ordered]@{}
    foreach ($name in $sheetMap.Keys) {
        $file = $fileMap[$sheetMap[$name]]
        $path = Join-Path "$tempDir\ex\xl" $file
        if (-not (Test-Path $path)) { continue }

        [xml]$sheet = Get-Content $path
        $nsm2 = New-Object System.Xml.XmlNamespaceManager($sheet.NameTable)
        $nsm2.AddNamespace("s", $nsMain)

        # Cells: ref, type, style, formula, hasValue
        $cells = @{}
        foreach ($c in $sheet.SelectNodes('//s:sheetData/s:row/s:c', $nsm2)) {
            $ref = $c.GetAttribute("r")
            $fNode = $c.SelectSingleNode('s:f', $nsm2)
            $formula = if ($fNode) { $fNode.InnerText } else { $null }
            $cells[$ref] = @{
                type       = $c.GetAttribute("t")
                style      = $c.GetAttribute("s")
                formula    = $formula
                hasInline  = ($null -ne $c.SelectSingleNode('s:is', $nsm2))
            }
        }

        # Merges
        $merges = @()
        foreach ($m in $sheet.SelectNodes('//s:mergeCells/s:mergeCell', $nsm2)) {
            $merges += $m.GetAttribute("ref")
        }

        # Data validations
        $dvs = @()
        foreach ($dv in $sheet.SelectNodes('//s:dataValidations/s:dataValidation', $nsm2)) {
            $dvs += "$($dv.GetAttribute('sqref'))|$($dv.GetAttribute('type'))"
        }

        # Column widths
        $colWidths = @()
        foreach ($col in $sheet.SelectNodes('//s:cols/s:col', $nsm2)) {
            $colWidths += "$($col.GetAttribute('min'))-$($col.GetAttribute('max')):$($col.GetAttribute('width'))"
        }

        $result[$name] = @{
            cells      = $cells
            merges     = ($merges | Sort-Object)
            dvs        = ($dvs | Sort-Object)
            colWidths  = ($colWidths | Sort-Object)
        }
    }

    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    return $result
}

Write-Host "=== Structural Comparison ===" -ForegroundColor Cyan
Write-Host "Original: $OriginalPath"
Write-Host "Produced: $ProducedPath`n"

Write-Host "Extracting original..." -NoNewline
$orig = Extract-SheetStructure -XlsxPath $OriginalPath
Write-Host " done ($($orig.Count) sheets)"

Write-Host "Extracting produced..." -NoNewline
$prod = Extract-SheetStructure -XlsxPath $ProducedPath
Write-Host " done ($($prod.Count) sheets)"

$mismatches = [System.Collections.ArrayList]::new()
$injectedCells = 0
$preservedFormulas = 0
$preservedMerges = 0

foreach ($sheetName in $orig.Keys) {
    $o = $orig[$sheetName]
    $p = $prod[$sheetName]

    if (-not $p) {
        [void]$mismatches.Add(@{ sheet = $sheetName; type = "MISSING_SHEET"; detail = "Sheet not in produced output" })
        continue
    }

    # --- Formula comparison (CRITICAL — must match exactly) ---
    foreach ($ref in $o.cells.Keys) {
        $oCell = $o.cells[$ref]
        $pCell = $p.cells[$ref]

        if ($oCell.formula) {
            if (-not $pCell) {
                [void]$mismatches.Add(@{ sheet = $sheetName; type = "FORMULA_MISSING_CELL"; detail = "$ref — cell missing in produced" })
            } elseif ($oCell.formula -ne $pCell.formula) {
                [void]$mismatches.Add(@{ sheet = $sheetName; type = "FORMULA_CHANGED"; detail = "$ref — orig: $($oCell.formula) | prod: $($pCell.formula)" })
            } else {
                $preservedFormulas++
            }
        }
    }

    # --- Count injected cells (inline strings not in original) ---
    foreach ($ref in $p.cells.Keys) {
        $pCell = $p.cells[$ref]
        if ($pCell.hasInline) { $injectedCells++ }
    }

    # --- Merged cells comparison ---
    $mergeDiff = Compare-Object $o.merges $p.merges -ErrorAction SilentlyContinue
    if ($mergeDiff) {
        foreach ($d in $mergeDiff) {
            [void]$mismatches.Add(@{ sheet = $sheetName; type = "MERGE_DIFF"; detail = "$($d.SideIndicator) $($d.InputObject)" })
        }
    }
    $preservedMerges += $o.merges.Count

    # --- Data validation comparison ---
    $dvDiff = Compare-Object $o.dvs $p.dvs -ErrorAction SilentlyContinue
    if ($dvDiff) {
        foreach ($d in $dvDiff) {
            [void]$mismatches.Add(@{ sheet = $sheetName; type = "VALIDATION_DIFF"; detail = "$($d.SideIndicator) $($d.InputObject)" })
        }
    }

    # --- Column width comparison ---
    $cwDiff = Compare-Object $o.colWidths $p.colWidths -ErrorAction SilentlyContinue
    if ($cwDiff) {
        foreach ($d in $cwDiff) {
            [void]$mismatches.Add(@{ sheet = $sheetName; type = "COLWIDTH_DIFF"; detail = "$($d.SideIndicator) $($d.InputObject)" })
        }
    }

    # --- Style preservation on formula cells ---
    foreach ($ref in $o.cells.Keys) {
        $oCell = $o.cells[$ref]
        $pCell = $p.cells[$ref]
        if ($oCell.formula -and $pCell -and $oCell.style -ne $pCell.style) {
            [void]$mismatches.Add(@{ sheet = $sheetName; type = "STYLE_CHANGED"; detail = "$ref — orig style: $($oCell.style) | prod style: $($pCell.style)" })
        }
    }
}

# --- Extra sheets in produced ---
foreach ($sheetName in $prod.Keys) {
    if (-not $orig[$sheetName]) {
        [void]$mismatches.Add(@{ sheet = $sheetName; type = "EXTRA_SHEET"; detail = "Sheet in produced but not in original" })
    }
}

# --- Report ---
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "Formulas preserved: $preservedFormulas" -ForegroundColor Green
Write-Host "Merges preserved: $preservedMerges" -ForegroundColor Green
Write-Host "Injected cells (expected new): $injectedCells" -ForegroundColor Yellow

# Group mismatches by type
$grouped = $mismatches | Group-Object { $_.type }
if ($mismatches.Count -eq 0) {
    Write-Host "`nRESULT: PASS — structural match (0 mismatches)" -ForegroundColor Green
} else {
    Write-Host "`nMismatches by type:" -ForegroundColor Red
    foreach ($g in $grouped) {
        Write-Host "  $($g.Name): $($g.Count)" -ForegroundColor Red
        foreach ($m in ($g.Group | Select-Object -First 5)) {
            Write-Host "    $($m.sheet) — $($m.detail)"
        }
        if ($g.Count -gt 5) { Write-Host "    ... and $($g.Count - 5) more" }
    }
    Write-Host "`nRESULT: $($mismatches.Count) structural mismatches found" -ForegroundColor Red
}
