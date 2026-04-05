<#
.SYNOPSIS
    Reads a completed bid comp xlsx (with vendor responses) and extracts structured data.
.DESCRIPTION
    Uses the known cell layout from the parsed schema to extract:
    - Bidder names, licenses, contacts, status
    - Scope item responses (Y/N/N.A./Decades per bidder)
    - Pricing: base contract, sub-total, contract total, low bid
    Outputs JSON suitable for creating dcfg_proposal records in Dataverse.
.PARAMETER BidCompPath
    Path to the completed bid comp xlsx
.PARAMETER SchemaPath
    Path to the parsed schema JSON (for cell position reference)
.PARAMETER OutputPath
    Optional path to write the extracted data JSON
#>
param(
    [string]$BidCompPath,
    [string]$SchemaPath = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json",
    [string]$OutputPath = $null
)

$ErrorActionPreference = 'Stop'
$nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'

# --- Extract sheet data ---
function Extract-SheetData {
    param([string]$SheetPath, [string[]]$SharedStrings)

    [xml]$sheet = Get-Content $SheetPath
    $nsm = New-Object System.Xml.XmlNamespaceManager($sheet.NameTable)
    $nsm.AddNamespace("s", $nsMain)

    $cells = @{}
    foreach ($c in $sheet.SelectNodes('//s:sheetData/s:row/s:c', $nsm)) {
        $ref = $c.GetAttribute("r")
        $type = $c.GetAttribute("t")
        $value = $null

        # Inline string
        $isNode = $c.SelectSingleNode('s:is/s:t', $nsm)
        if ($isNode) { $value = $isNode.InnerText }
        else {
            $vNode = $c.SelectSingleNode('s:v', $nsm)
            if ($vNode) {
                $raw = $vNode.InnerText
                if ($type -eq 's' -and $raw -match '^\d+$') {
                    $idx = [int]$raw
                    $value = if ($idx -lt $SharedStrings.Count) { $SharedStrings[$idx] } else { $raw }
                } else {
                    $value = $raw
                }
            }
        }

        if ($null -ne $value) { $cells[$ref] = $value }
    }
    return $cells
}

# --- Main ---
$tempDir = Join-Path $env:TEMP "xlsx_readback_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Copy-Item $BidCompPath "$tempDir\file.zip"
    Expand-Archive "$tempDir\file.zip" -DestinationPath "$tempDir\ex" -Force

    # Read shared strings
    $sharedStrings = @()
    $sstPath = "$tempDir\ex\xl\sharedStrings.xml"
    if (Test-Path $sstPath) {
        [xml]$sst = Get-Content $sstPath
        foreach ($si in $sst.sst.si) {
            if ($si.t) { $sharedStrings += if ($si.t.'#text') { $si.t.'#text' } else { "$($si.t)" } }
            elseif ($si.r) {
                $parts = @(); foreach ($run in $si.r) { $parts += if ($run.t.'#text') { $run.t.'#text' } else { "$($run.t)" } }
                $sharedStrings += ($parts -join '')
            }
            else { $sharedStrings += '' }
        }
    }

    # Map sheet names to files
    [xml]$workbook = Get-Content "$tempDir\ex\xl\workbook.xml"
    $nsm = New-Object System.Xml.XmlNamespaceManager($workbook.NameTable)
    $nsm.AddNamespace("s", $nsMain)
    $nsRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $sheetMap = @{}
    foreach ($node in $workbook.SelectNodes('//s:sheet', $nsm)) {
        $sheetMap[$node.name] = $node.GetAttribute("id", $nsRel)
    }
    [xml]$rels = Get-Content "$tempDir\ex\xl\_rels\workbook.xml.rels"
    $fileMap = @{}
    foreach ($r in $rels.Relationships.Relationship) { $fileMap[$r.Id] = $r.Target }

    # Known trade sheet names (from template analysis)
    $tradeSheets = @(
        '? TRADE COMP (MASTER)','Carpentry','Roofing','Electrical','Plumbing','HVAC',
        'Painting','Flooring','Glazing','Misc Metals','Spray Insulation',
        'Fire Alarm','Fire Protection','Millwork','Final Cleaning'
    )

    # Known cell positions from structural analysis:
    # Row 9, cols D/F/H/J/L  = Bidder names
    # Row 10                   = Status
    # Row 11                   = License #
    # Row 12                   = Contact/Email
    # Rows 14-45              = Scope items (col B = description, bidder cols = Y/N response)
    # Row 59                   = Bid Bond
    # Row 60                   = Base Contract $
    # Row 61                   = General Conditions
    # Row 62                   = Allowances
    # Row 63                   = Sub-Total
    # Row 64                   = Alternates
    # Row 65                   = Permits
    # Row 66                   = Contract Total
    # Row 68                   = Low Bid (formula result)

    $bidderCols = @('D','F','H','J','L')
    $allResponses = [System.Collections.ArrayList]::new()

    foreach ($tradeName in $tradeSheets) {
        $rId = $sheetMap[$tradeName]
        if (-not $rId) { continue }
        $file = $fileMap[$rId]
        if (-not $file) { continue }
        $sheetPath = Join-Path "$tempDir\ex\xl" $file
        if (-not (Test-Path $sheetPath)) { continue }

        $cells = Extract-SheetData -SheetPath $sheetPath -SharedStrings $sharedStrings

        $bidders = [System.Collections.ArrayList]::new()
        foreach ($col in $bidderCols) {
            $name = $cells["${col}9"]
            if (-not $name -or $name -eq 'Bidding' -or $name -match '^\s*$') { continue }

            # Scope responses
            $scopeResponses = [System.Collections.ArrayList]::new()
            for ($row = 14; $row -le 45; $row++) {
                $scopeItem = $cells["B$row"]
                if (-not $scopeItem -or $scopeItem -match '^\s*$') { continue }
                $response = $cells["${col}$row"]
                [void]$scopeResponses.Add(@{
                    item     = $scopeItem
                    response = if ($response) { $response } else { "" }
                    included = ($response -eq 'Y' -or $response -eq 'Decades')
                })
            }

            # Pricing rows
            $pricing = @{
                bidBond          = $cells["${col}59"]
                baseContract     = $cells["${col}60"]
                generalConditions = $cells["${col}61"]
                allowances       = $cells["${col}62"]
                subTotal         = $cells["${col}63"]
                alternates       = $cells["${col}64"]
                permits          = $cells["${col}65"]
                contractTotal    = $cells["${col}66"]
            }

            [void]$bidders.Add(@{
                name           = $name
                column         = $col
                license        = $cells["${col}11"]
                contact        = $cells["${col}12"]
                status         = $cells["${col}10"]
                scopeResponses = $scopeResponses.ToArray()
                pricing        = $pricing
                scopeCoverage  = if ($scopeResponses.Count -gt 0) {
                    [math]::Round(($scopeResponses | Where-Object { $_.included }).Count / $scopeResponses.Count * 100, 1)
                } else { 0 }
            })
        }

        # Low bid (row 68, formula result)
        $lowBid = $cells["D68"]  # Low bid formula usually in first bidder column area

        if ($bidders.Count -gt 0) {
            [void]$allResponses.Add(@{
                trade    = $tradeName
                bidders  = $bidders.ToArray()
                lowBid   = $lowBid
            })
        }
    }

    # --- Output ---
    $result = @{
        sourceFile  = (Split-Path $BidCompPath -Leaf)
        parsedAt    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        tradeCount  = $allResponses.Count
        trades      = $allResponses.ToArray()
    }

    $json = $result | ConvertTo-Json -Depth 10

    if ($OutputPath) {
        $outDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $json | Set-Content $OutputPath -Encoding UTF8
        Write-Host "Output saved to: $OutputPath"
    }

    # Summary
    Write-Host "`n=== Read-Back Summary ===" -ForegroundColor Cyan
    Write-Host "Source: $(Split-Path $BidCompPath -Leaf)"
    Write-Host "Trades with responses: $($allResponses.Count)"
    foreach ($t in $allResponses) {
        Write-Host "  $($t.trade): $($t.bidders.Count) bidders" -ForegroundColor Green
        foreach ($b in $t.bidders) {
            $total = if ($b.pricing.contractTotal) { "`$$($b.pricing.contractTotal)" } else { "no pricing" }
            Write-Host "    $($b.name) — $total — $($b.scopeCoverage)% scope coverage"
        }
    }

    # Return the result for pipeline use
    return $result

} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
