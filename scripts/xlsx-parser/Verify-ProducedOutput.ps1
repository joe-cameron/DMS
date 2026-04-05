<#
.SYNOPSIS
    Quick verification that a produced bid comp xlsx has the expected injected data and preserved structure.
#>
param(
    [string]$ProducedPath = "C:\DCFG\tmp\test_bid_comp_output.xlsx"
)

$ErrorActionPreference = 'Stop'
$nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'

$tempDir = Join-Path $env:TEMP "xlsx_verify_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Copy-Item $ProducedPath "$tempDir\out.zip"
    Expand-Archive "$tempDir\out.zip" -DestinationPath "$tempDir\ex" -Force

    # Check Carpentry (sheet2) and Plumbing (sheet5)
    $checks = @(
        @{ name = "Carpentry"; file = "sheet2.xml" }
        @{ name = "Plumbing";  file = "sheet5.xml" }
    )

    foreach ($check in $checks) {
        $path = "$tempDir\ex\xl\worksheets\$($check.file)"
        [xml]$sheet = Get-Content $path

        $nsm = New-Object System.Xml.XmlNamespaceManager($sheet.NameTable)
        $nsm.AddNamespace("s", $nsMain)

        Write-Host "`n=== $($check.name) ===" -ForegroundColor Cyan

        # Count inline strings (injected data)
        $inlineCells = $sheet.SelectNodes('//s:sheetData/s:row/s:c[s:is]', $nsm)
        Write-Host "Injected cells (inline strings): $($inlineCells.Count)"
        foreach ($c in $inlineCells) {
            $ref = $c.GetAttribute("r")
            $tNode = $c.SelectSingleNode('s:is/s:t', $nsm)
            $val = if ($tNode) { $tNode.InnerText } else { "(empty)" }
            Write-Host "  $ref = $val"
        }

        # Count preserved formulas
        $formulas = $sheet.SelectNodes('//s:sheetData/s:row/s:c/s:f', $nsm)
        Write-Host "Formulas preserved: $($formulas.Count)"

        # Count preserved merges
        $merges = $sheet.SelectNodes('//s:mergeCells/s:mergeCell', $nsm)
        Write-Host "Merges preserved: $($merges.Count)"

        # Count data validations
        $dvs = $sheet.SelectNodes('//s:dataValidations/s:dataValidation', $nsm)
        Write-Host "Data validations preserved: $($dvs.Count)"
    }

    # Quick check: total sheet count
    [xml]$wb = Get-Content "$tempDir\ex\xl\workbook.xml"
    $nsm3 = New-Object System.Xml.XmlNamespaceManager($wb.NameTable)
    $nsm3.AddNamespace("s", $nsMain)
    $sheetCount = $wb.SelectNodes('//s:sheet', $nsm3).Count
    Write-Host "`nTotal sheets in output: $sheetCount" -ForegroundColor Cyan

} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
