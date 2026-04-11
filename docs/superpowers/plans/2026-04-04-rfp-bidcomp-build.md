# RFP + Bid Comp Build — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core loop — produce pre-filled bid comp spreadsheets, parse them on save, track RFPs and vendor responses in Dataverse, and display status in the SPA.

**Architecture:** Two layers work together: (1) A PowerShell-based spreadsheet understanding engine that deep-parses the DCG Multi Trade Bid Template's Open XML structure into a verified JSON schema, then uses that schema to produce pre-filled copies and parse completed ones. (2) Dataverse tables + Power Automate flows + SPA screens that store, trigger, and display the structured data. The spreadsheet IS the user interface — the SPA is the management view.

**Tech Stack:** PowerShell (Open XML parsing + Dataverse API), Power Automate (SharePoint file triggers), React 16.14 + Vite (SPA screens), Dataverse Web API

**Spec:** `C:\DCFG\docs\superpowers\specs\2026-04-04-project-setup-to-rfp-design.md`

**Reference files:**
- Bid comp template: `C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx`
- Extracted Open XML: `C:\DCFG\tmp\bid_template\extracted\`
- Estimate template: `C:\Users\JosephCameron\Downloads\Copy of estiamte template.xlsx`
- Extracted Open XML: `C:\DCFG\tmp\estimate_template\extracted\`
- Sage vendors: `C:\DCFG\tmp\sage_vendors\extracted\`

---

## Chunk 1: Spreadsheet Understanding Engine — Bid Comp Template

### Task 1: Build the Open XML parser for the bid comp template

**Files:**
- Create: `C:\DCFG\scripts\xlsx-parser\Parse-BidCompTemplate.ps1`
- Create: `C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json`

The parser reads the Multi Trade Bid Template's Open XML and produces a complete structural schema in JSON. This schema is the ground truth for producing and parsing bid comp spreadsheets.

- [ ] **Step 1: Write the unzip + sheet discovery function**

```powershell
# Parse-BidCompTemplate.ps1
param(
    [string]$XlsxPath = "C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx",
    [string]$OutputPath = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json"
)

$tempDir = Join-Path $env:TEMP "xlsx_parse_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Unzip
Copy-Item $XlsxPath "$tempDir\template.zip"
Expand-Archive "$tempDir\template.zip" -DestinationPath "$tempDir\extracted" -Force

# Read workbook.xml for sheet names and order
[xml]$workbook = Get-Content "$tempDir\extracted\xl\workbook.xml"
$ns = @{ s = "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
$sheets = Select-Xml -Xml $workbook -XPath "//s:sheet" -Namespace $ns | ForEach-Object {
    @{
        name = $_.Node.name
        sheetId = $_.Node.sheetId
        rId = $_.Node.GetAttribute("id", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
    }
}

# Read shared strings
[xml]$sst = Get-Content "$tempDir\extracted\xl\sharedStrings.xml"
$sharedStrings = @()
foreach ($si in $sst.sst.si) {
    if ($si.t) { $sharedStrings += $si.t.'#text' ?? $si.t }
    elseif ($si.r) { $sharedStrings += ($si.r | ForEach-Object { $_.t.'#text' ?? $_.t }) -join '' }
    else { $sharedStrings += '' }
}

Write-Host "Found $($sheets.Count) sheets, $($sharedStrings.Count) shared strings"
```

- [ ] **Step 2: Run to verify it reads the template**

Run: `pwsh -File C:\DCFG\scripts\xlsx-parser\Parse-BidCompTemplate.ps1`
Expected: "Found 19 sheets, 365 shared strings"

- [ ] **Step 3: Add the cell parser function**

Parse each worksheet XML into structured cell data:

```powershell
function Parse-Worksheet {
    param([string]$SheetPath, [string[]]$SharedStrings)

    [xml]$sheet = Get-Content $SheetPath
    $ns = @{ s = "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }

    $cells = @()
    $merges = @()
    $dataValidations = @()

    # Parse cells
    $rows = Select-Xml -Xml $sheet -XPath "//s:sheetData/s:row" -Namespace $ns
    foreach ($row in $rows) {
        $rowNum = [int]$row.Node.r
        $cellNodes = Select-Xml -Xml $row.Node -XPath "s:c" -Namespace $ns
        foreach ($c in $cellNodes) {
            $ref = $c.Node.r
            $type = $c.Node.t
            $style = $c.Node.s
            $formula = $null
            $value = $null

            # Get formula if present
            $fNode = Select-Xml -Xml $c.Node -XPath "s:f" -Namespace $ns
            if ($fNode) {
                $formula = $fNode.Node.'#text'
                # Capture shared formula info
                if ($fNode.Node.t -eq 'shared') {
                    $formula = @{
                        type = 'shared'
                        si = $fNode.Node.si
                        ref = $fNode.Node.ref
                        formula = $fNode.Node.'#text'
                    }
                }
            }

            # Get value
            $vNode = Select-Xml -Xml $c.Node -XPath "s:v" -Namespace $ns
            if ($vNode) {
                $rawValue = $vNode.Node.'#text'
                if ($type -eq 's') {
                    $value = $SharedStrings[[int]$rawValue]
                } else {
                    $value = $rawValue
                }
            }

            $cells += @{
                ref = $ref
                row = $rowNum
                col = ($ref -replace '[0-9]', '')
                type = $type
                style = $style
                value = $value
                formula = $formula
            }
        }
    }

    # Parse merged cells
    $mergeNodes = Select-Xml -Xml $sheet -XPath "//s:mergeCells/s:mergeCell" -Namespace $ns
    foreach ($m in $mergeNodes) {
        $merges += $m.Node.ref
    }

    # Parse data validations
    $dvNodes = Select-Xml -Xml $sheet -XPath "//s:dataValidations/s:dataValidation" -Namespace $ns
    foreach ($dv in $dvNodes) {
        $dataValidations += @{
            sqref = $dv.Node.sqref
            type = $dv.Node.type
            formula1 = (Select-Xml -Xml $dv.Node -XPath "s:formula1" -Namespace $ns).Node.'#text'
        }
    }

    # Parse frozen panes
    $pane = Select-Xml -Xml $sheet -XPath "//s:sheetViews/s:sheetView/s:pane" -Namespace $ns
    $frozenPane = if ($pane) {
        @{ ySplit = $pane.Node.ySplit; xSplit = $pane.Node.xSplit; topLeftCell = $pane.Node.topLeftCell }
    } else { $null }

    # Parse column widths
    $cols = Select-Xml -Xml $sheet -XPath "//s:cols/s:col" -Namespace $ns
    $colWidths = @()
    foreach ($col in $cols) {
        $colWidths += @{
            min = $col.Node.min
            max = $col.Node.max
            width = $col.Node.width
            hidden = $col.Node.hidden -eq '1'
        }
    }

    return @{
        cells = $cells
        mergedCells = $merges
        dataValidations = $dataValidations
        frozenPane = $frozenPane
        columnWidths = $colWidths
        rowCount = ($rows | Measure-Object).Count
    }
}
```

- [ ] **Step 4: Parse all 19 sheets and build the schema**

```powershell
$schema = @{
    templateName = "DCG_Multi_Trade_Bid_Template"
    version = "1"
    parsedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    sharedStrings = $sharedStrings
    sheets = @{}
}

# Read relationship file to map rId to sheet file
[xml]$rels = Get-Content "$tempDir\extracted\xl\_rels\workbook.xml.rels"
$sheetFiles = @{}
foreach ($rel in $rels.Relationships.Relationship) {
    $sheetFiles[$rel.Id] = $rel.Target
}

foreach ($sheet in $sheets) {
    $sheetFile = $sheetFiles[$sheet.rId]
    $sheetPath = Join-Path "$tempDir\extracted\xl" $sheetFile

    Write-Host "Parsing: $($sheet.name) from $sheetFile"
    $parsed = Parse-Worksheet -SheetPath $sheetPath -SharedStrings $sharedStrings

    $schema.sheets[$sheet.name] = @{
        sheetId = $sheet.sheetId
        rId = $sheet.rId
        file = $sheetFile
        cells = $parsed.cells
        mergedCells = $parsed.mergedCells
        dataValidations = $parsed.dataValidations
        frozenPane = $parsed.frozenPane
        columnWidths = $parsed.columnWidths
        rowCount = $parsed.rowCount
        cellCount = $parsed.cells.Count
    }
}

# Save schema
$schema | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
Write-Host "`nSchema saved to $OutputPath"
Write-Host "Total sheets: $($schema.sheets.Count)"
$totalCells = ($schema.sheets.Values | ForEach-Object { $_.cellCount } | Measure-Object -Sum).Sum
Write-Host "Total cells: $totalCells"

# Cleanup
Remove-Item $tempDir -Recurse -Force
```

- [ ] **Step 5: Run full parser and verify output**

Run: `pwsh -File C:\DCFG\scripts\xlsx-parser\Parse-BidCompTemplate.ps1`
Expected: Schema JSON with 19 sheets, ~1300 cells total, formulas captured for Dashboard/BidReq/ExhibitB cross-sheet references

- [ ] **Step 6: Validate schema captures critical formulas**

Write a validation script that checks the schema JSON for known formulas:

```powershell
# Validate-BidCompSchema.ps1
$schema = Get-Content "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json" | ConvertFrom-Json

$checks = @(
    @{ sheet = "Carpentry"; desc = "Low bid MIN formula"; test = {
        $cells = $schema.sheets.Carpentry.cells | Where-Object { $_.row -eq 68 -and $_.formula }
        $cells.Count -gt 0 -and $cells[0].formula -match 'MIN'
    }},
    @{ sheet = "DASHBOARD"; desc = "Trade subtotal SUM"; test = {
        $cells = $schema.sheets.DASHBOARD.cells | Where-Object { $_.formula -match 'SUM' }
        $cells.Count -gt 0
    }},
    @{ sheet = "BID REQ"; desc = "INDIRECT cross-sheet ref"; test = {
        $cells = $schema.sheets.'BID REQ'.cells | Where-Object { $_.formula -match 'INDIRECT|CHOOSE' }
        $cells.Count -gt 0
    }},
    @{ sheet = "EXHIBIT B"; desc = "Dynamic scope population"; test = {
        $cells = $schema.sheets.'EXHIBIT B'.cells | Where-Object { $_.formula -match 'CHOOSE|MATCH' }
        $cells.Count -gt 0
    }}
)

$pass = 0; $fail = 0
foreach ($check in $checks) {
    $result = & $check.test
    if ($result) { Write-Host "  PASS: $($check.sheet) - $($check.desc)"; $pass++ }
    else { Write-Host "  FAIL: $($check.sheet) - $($check.desc)"; $fail++ }
}
Write-Host "`n$pass passed, $fail failed"
```

- [ ] **Step 7: Commit**

```bash
git add scripts/xlsx-parser/
git commit -m "feat: build Open XML parser for bid comp template - produces verified structural schema"
```

---

### Task 2: Build the bid comp xlsx producer

**Files:**
- Create: `C:\DCFG\scripts\xlsx-parser\Produce-BidComp.ps1`

Takes the verified schema + project data (scope items, vendor list, project info) and produces a fully formatted xlsx that's structurally identical to Tyler's template.

- [ ] **Step 1: Write the xlsx assembly function**

```powershell
# Produce-BidComp.ps1
param(
    [string]$SchemaPath = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json",
    [string]$OutputPath = "C:\DCFG\tmp\test_bid_comp_output.xlsx",
    [hashtable]$ProjectData = @{
        projectName = "Test Project - 599 Sorenson Dr"
        location = "Carneys Point, NJ 08069"
        date = "2026-04-04"
        trades = @{
            "Carpentry" = @{
                csi = "6100"
                scopeItems = @(
                    "Layout and frame partition walls per plans",
                    "Furnish and install drywall to roof deck",
                    "Tape and spackle - paint ready"
                )
                bidders = @(
                    @{ name = "Starr General"; license = "13VH123456"; contact = "Mary Kate / mk@starr.com" },
                    @{ name = "Rahn Companies"; license = "13VH789012"; contact = "Matt Rahn / matt@rahn.com" }
                )
            }
        }
    }
)

$schema = Get-Content $SchemaPath | ConvertFrom-Json

# Strategy: Copy the original template, then modify cells with project data
# This preserves all formatting, formulas, merged cells, styles, and structure
# Only modify cells that contain project-specific data

$tempDir = Join-Path $env:TEMP "xlsx_produce_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Start from the original template
$templatePath = "C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx"
Copy-Item $templatePath "$tempDir\template.zip"
Expand-Archive "$tempDir\template.zip" -DestinationPath "$tempDir\work" -Force

# Modify shared strings to inject project data
# Modify worksheet XMLs to inject scope items and vendor info
# Preserve all formulas, styles, merges untouched
```

- [ ] **Step 2: Implement the shared string injection**

```powershell
function Update-SharedStrings {
    param([string]$SstPath, [hashtable]$Replacements)

    [xml]$sst = Get-Content $SstPath
    $ns = @{ s = "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }

    # Add new strings and track their indices
    $currentCount = [int]$sst.sst.uniqueCount
    $newIndices = @{}

    foreach ($key in $Replacements.Keys) {
        $si = $sst.CreateElement("si", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        $t = $sst.CreateElement("t", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        $t.InnerText = $Replacements[$key]
        $si.AppendChild($t) | Out-Null
        $sst.sst.AppendChild($si) | Out-Null
        $newIndices[$key] = $currentCount
        $currentCount++
    }

    $sst.sst.count = $currentCount.ToString()
    $sst.sst.uniqueCount = $currentCount.ToString()
    $sst.Save($SstPath)

    return $newIndices
}
```

- [ ] **Step 3: Implement the worksheet cell updater**

```powershell
function Set-CellValue {
    param([xml]$SheetXml, [string]$CellRef, [string]$Value, [string]$Type = "s", [string]$StringIndex = $null)

    $ns = @{ s = "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
    $rowNum = [int]($CellRef -replace '[A-Z]', '')

    # Find or create the row
    $row = Select-Xml -Xml $SheetXml -XPath "//s:sheetData/s:row[@r='$rowNum']" -Namespace $ns
    if (-not $row) {
        # Create row (simplified — production code would insert in order)
        $sheetData = Select-Xml -Xml $SheetXml -XPath "//s:sheetData" -Namespace $ns
        $newRow = $SheetXml.CreateElement("row", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        $newRow.SetAttribute("r", $rowNum)
        $sheetData.Node.AppendChild($newRow) | Out-Null
        $row = Select-Xml -Xml $SheetXml -XPath "//s:sheetData/s:row[@r='$rowNum']" -Namespace $ns
    }

    # Find or create the cell
    $cell = Select-Xml -Xml $row.Node -XPath "s:c[@r='$CellRef']" -Namespace $ns
    if (-not $cell) {
        $newCell = $SheetXml.CreateElement("c", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        $newCell.SetAttribute("r", $CellRef)
        $row.Node.AppendChild($newCell) | Out-Null
        $cell = Select-Xml -Xml $row.Node -XPath "s:c[@r='$CellRef']" -Namespace $ns
    }

    # Set type and value
    if ($Type -eq "s") {
        $cell.Node.SetAttribute("t", "s")
        $vNode = $cell.Node.SelectSingleNode("s:v", (New-Object System.Xml.XmlNamespaceManager($SheetXml.NameTable)).AddNamespace("s","http://schemas.openxmlformats.org/spreadsheetml/2006/main"))
        if (-not $vNode) {
            $vNode = $SheetXml.CreateElement("v", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
            $cell.Node.AppendChild($vNode) | Out-Null
        }
        $vNode.InnerText = $StringIndex
    }
}
```

- [ ] **Step 4: Wire it together — populate trade tabs with project data**

```powershell
# For each trade in project data, update the corresponding sheet
foreach ($tradeName in $ProjectData.trades.Keys) {
    $trade = $ProjectData.trades[$tradeName]
    $sheetFile = $schema.sheets.$tradeName.file
    $sheetPath = Join-Path "$tempDir\work\xl" $sheetFile

    [xml]$sheetXml = Get-Content $sheetPath

    # Inject scope items into rows 14+ (specific scope section)
    $scopeRow = 14
    foreach ($item in $trade.scopeItems) {
        # Add to shared strings, get index
        # Set cell B{row} to the scope item text
        $scopeRow++
    }

    # Inject bidder info into header rows
    # Row 9 = Contractor Name (cols D, F, H, J, L)
    # Row 10 = Status
    # Row 11 = License #
    # Row 12 = Contact / Email
    $bidderCols = @('D', 'F', 'H', 'J', 'L')
    for ($i = 0; $i -lt [Math]::Min($trade.bidders.Count, 5); $i++) {
        $col = $bidderCols[$i]
        $bidder = $trade.bidders[$i]
        # Set cells: {col}9 = name, {col}11 = license, {col}12 = contact
    }

    $sheetXml.Save($sheetPath)
}

# Update project header info (Location, Date) on all sheets
# Rezip to xlsx
Compress-Archive -Path "$tempDir\work\*" -DestinationPath "$tempDir\output.zip" -Force
Move-Item "$tempDir\output.zip" $OutputPath -Force

Write-Host "Produced: $OutputPath"
Remove-Item $tempDir -Recurse -Force
```

- [ ] **Step 5: Run producer with test data and verify output opens in Excel**

Run: `pwsh -File C:\DCFG\scripts\xlsx-parser\Produce-BidComp.ps1`
Expected: File created at `C:\DCFG\tmp\test_bid_comp_output.xlsx`, opens in Excel without errors

- [ ] **Step 6: Commit**

```bash
git add scripts/xlsx-parser/Produce-BidComp.ps1
git commit -m "feat: bid comp xlsx producer - generates pre-filled workbooks from template + project data"
```

---

### Task 3: Build the compare-and-verify loop

**Files:**
- Create: `C:\DCFG\scripts\xlsx-parser\Compare-XlsxStructure.ps1`

Compares a produced xlsx against the original template cell-by-cell. Reports mismatches. This is the auto-research quality gate.

- [ ] **Step 1: Write the structural comparison**

```powershell
# Compare-XlsxStructure.ps1
param(
    [string]$OriginalPath = "C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx",
    [string]$ProducedPath = "C:\DCFG\tmp\test_bid_comp_output.xlsx"
)

function Extract-Structure {
    param([string]$XlsxPath)
    # Unzip, parse all sheets, return normalized structure
    # (reuse Parse-Worksheet from Task 1)
}

$original = Extract-Structure -XlsxPath $OriginalPath
$produced = Extract-Structure -XlsxPath $ProducedPath

$mismatches = @()
foreach ($sheetName in $original.Keys) {
    $origSheet = $original[$sheetName]
    $prodSheet = $produced[$sheetName]

    if (-not $prodSheet) {
        $mismatches += @{ sheet = $sheetName; type = "MISSING_SHEET" }
        continue
    }

    # Compare merged cells
    $origMerges = $origSheet.mergedCells | Sort-Object
    $prodMerges = $prodSheet.mergedCells | Sort-Object
    $mergeDiff = Compare-Object $origMerges $prodMerges
    foreach ($d in $mergeDiff) {
        $mismatches += @{ sheet = $sheetName; type = "MERGE"; detail = "$($d.SideIndicator) $($d.InputObject)" }
    }

    # Compare formulas (critical — must be identical)
    $origFormulas = $origSheet.cells | Where-Object { $_.formula } | ForEach-Object { "$($_.ref)=$($_.formula)" }
    $prodFormulas = $prodSheet.cells | Where-Object { $_.formula } | ForEach-Object { "$($_.ref)=$($_.formula)" }
    $formulaDiff = Compare-Object $origFormulas $prodFormulas
    foreach ($d in $formulaDiff) {
        $mismatches += @{ sheet = $sheetName; type = "FORMULA"; detail = "$($d.SideIndicator) $($d.InputObject)" }
    }

    # Compare styles on structural cells (headers, section dividers)
    # (only check cells that should NOT change — headers, boilerplate)
}

Write-Host "`nComparison Results:"
Write-Host "  Sheets checked: $($original.Keys.Count)"
Write-Host "  Mismatches: $($mismatches.Count)"

if ($mismatches.Count -eq 0) {
    Write-Host "  RESULT: PASS - structural match" -ForegroundColor Green
} else {
    Write-Host "  RESULT: FAIL - $($mismatches.Count) mismatches" -ForegroundColor Red
    $mismatches | ForEach-Object { Write-Host "    $($_.sheet) | $($_.type) | $($_.detail)" }
}
```

- [ ] **Step 2: Run comparison against produced output**

Run: `pwsh -File C:\DCFG\scripts\xlsx-parser\Compare-XlsxStructure.ps1`
Expected: Reports any structural mismatches. Fix each one, re-produce, re-compare until PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/xlsx-parser/Compare-XlsxStructure.ps1
git commit -m "feat: xlsx structural comparison - auto-research quality gate for template production"
```

---

## Chunk 2: Dataverse Schema + RFP/Bid Comp Data Layer

### Task 4: Create the RFP + Bid Comp Dataverse tables

**Files:**
- Create: `C:\DCFG\Build-RFP-BidComp-Schema.ps1`

Creates the tables defined in spec Section 13.2: dcfg_rfp_package, dcfg_rfp_project, dcfg_rfp_vendor, dcfg_proposal, dcfg_milestone.

- [ ] **Step 1: Verify existing tables and plan delta**

```powershell
# Build-RFP-BidComp-Schema.ps1
# First: check what already exists
$OrgUrl = "https://org0c17e98d.crm.dynamics.com/"
$token = (Get-AzAccessToken -ResourceUrl $OrgUrl -AsSecureString)
$t = [System.Net.NetworkCredential]::new('', $token.Token).Password
$h = @{ 'Authorization'="Bearer $t"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; 'Accept'='application/json' }

# Check for existing tables
$tables = @('dcfg_rfp_package','dcfg_rfp_project','dcfg_rfp_vendor','dcfg_proposal','dcfg_milestone')
foreach ($table in $tables) {
    try {
        $r = Invoke-RestMethod -Uri "${OrgUrl}api/data/v9.2/EntityDefinitions(LogicalName='$table')?`$select=LogicalName,EntitySetName" -Headers $h
        Write-Host "EXISTS: $table (EntitySet: $($r.EntitySetName))"
    } catch {
        Write-Host "NEEDS CREATE: $table"
    }
}
```

- [ ] **Step 2: Run the check**

Run: `pwsh -File C:\DCFG\Build-RFP-BidComp-Schema.ps1`
Expected: Lists which tables exist vs need creation

- [ ] **Step 3: Add table creation for dcfg_rfp_package**

Per spec Section 13.2 — full column set:

```powershell
function New-Table {
    param([string]$LogicalName, [string]$DisplayName, [string]$PrimaryField, [hashtable]$Headers)
    $body = @{
        "@odata.type" = "#Microsoft.Dynamics.CRM.EntityMetadata"
        LogicalName = $LogicalName
        DisplayName = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; Label = $DisplayName; LanguageCode = 1033 }) }
        DisplayCollectionName = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; Label = "${DisplayName}s"; LanguageCode = 1033 }) }
        HasNotes = $false; HasActivities = $false
        PrimaryNameAttribute = $PrimaryField
        Attributes = @(
            @{
                "@odata.type" = "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
                LogicalName = $PrimaryField; SchemaName = $PrimaryField
                RequiredLevel = @{ Value = "ApplicationRequired" }
                MaxLength = 200
                DisplayName = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; Label = "Name"; LanguageCode = 1033 }) }
            }
        )
    } | ConvertTo-Json -Depth 10

    $result = Invoke-RestMethod -Uri "${OrgUrl}api/data/v9.2/EntityDefinitions" -Method Post -Headers ($Headers + @{'Content-Type'='application/json'}) -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    Write-Host "Created table: $LogicalName"
}

# Create dcfg_rfp_package
New-Table -LogicalName "dcfg_rfp_package" -DisplayName "RFP Package" -PrimaryField "dcfg_name" -Headers $h
```

- [ ] **Step 4: Add columns to dcfg_rfp_package**

```powershell
function Add-Column {
    param([string]$Table, [string]$Name, [string]$Type, [int]$MaxLength = 200, [hashtable]$Headers)

    $attrType = switch ($Type) {
        "string" { "#Microsoft.Dynamics.CRM.StringAttributeMetadata" }
        "memo" { "#Microsoft.Dynamics.CRM.MemoAttributeMetadata" }
        "money" { "#Microsoft.Dynamics.CRM.MoneyAttributeMetadata" }
        "int" { "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata" }
        "bool" { "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata" }
        "datetime" { "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata" }
    }

    $body = @{
        "@odata.type" = $attrType
        LogicalName = $Name; SchemaName = $Name
        RequiredLevel = @{ Value = "None" }
        DisplayName = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; Label = ($Name -replace 'dcfg_',''); LanguageCode = 1033 }) }
    }

    if ($Type -eq "string") { $body.MaxLength = $MaxLength }
    if ($Type -eq "memo") { $body.MaxLength = 1048576 }
    if ($Type -eq "money") { $body.PrecisionSource = 2 }
    if ($Type -eq "int") { $body.MinValue = -2147483648; $body.MaxValue = 2147483647 }

    $json = $body | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "${OrgUrl}api/data/v9.2/EntityDefinitions(LogicalName='$Table')/Attributes" -Method Post -Headers ($Headers + @{'Content-Type'='application/json'}) -Body ([System.Text.Encoding]::UTF8.GetBytes($json))
    Write-Host "  Added: $Name ($Type)"
}

# dcfg_rfp_package columns (from spec Section 13.2)
$rfpCols = @(
    @{n="dcfg_trades"; t="string"; l=500},
    @{n="dcfg_scope_description"; t="memo"},
    @{n="dcfg_total_estimated_value"; t="money"},
    @{n="dcfg_period_cap"; t="money"},
    @{n="dcfg_contract_duration_months"; t="int"},
    @{n="dcfg_deadline"; t="datetime"},
    @{n="dcfg_bid_solicited"; t="bool"},
    @{n="dcfg_bid_received"; t="bool"},
    @{n="dcfg_scope_exhibit_drafted"; t="bool"},
    @{n="dcfg_exhibit_b_issued"; t="bool"},
    @{n="dcfg_contract_out"; t="bool"},
    @{n="dcfg_contract_fe"; t="bool"},
    @{n="dcfg_submittals_received"; t="bool"},
    @{n="dcfg_scope_items"; t="memo"},
    @{n="dcfg_financial_structure"; t="memo"},
    @{n="dcfg_version"; t="int"},
    @{n="dcfg_sp_file_ref"; t="string"; l=500},
    @{n="dcfg_active_flag"; t="bool"}
)

foreach ($col in $rfpCols) {
    Add-Column -Table "dcfg_rfp_package" -Name $col.n -Type $col.t -MaxLength ($col.l ?? 200) -Headers $h
}
```

- [ ] **Step 5: Create remaining tables (dcfg_rfp_project, dcfg_rfp_vendor, dcfg_milestone)**

Same pattern for each junction and child table per spec Section 13.2.

- [ ] **Step 6: Add choice columns (billing_pattern, period_type, status) via OptionSet**

```powershell
# dcfg_billing_pattern: PerUnit=1, MonthlyFixed=2, Milestone=3, Hybrid=4
# dcfg_period_type: Monthly=1, Quarterly=2
# dcfg_status: Draft=1, Sent=2, ResponsesIn=3, Leveled=4, Awarded=5, Canceled=6
```

- [ ] **Step 7: Add relationships (FKs)**

```powershell
# dcfg_rfp_package -> dcfg_customer (lookup)
# dcfg_rfp_package -> dcfg_prime_contract (lookup, nullable)
# dcfg_rfp_project -> dcfg_rfp_package (lookup)
# dcfg_rfp_project -> dcfg_project (lookup)
# dcfg_rfp_vendor -> dcfg_rfp_package (lookup)
# dcfg_rfp_vendor -> dcfg_vendor (lookup)
# dcfg_milestone -> dcfg_rfp_package (lookup, nullable)
# dcfg_proposal -> dcfg_rfp_package (lookup — replaces BidComp's dcfg_rfp FK)
```

- [ ] **Step 8: Add tables to DCFGSystemTest solution**

```powershell
$solutionName = "DCFGSystemTest"
# Add each new table to the solution
```

- [ ] **Step 9: Create table permissions + site settings for portal access**

Per engineering journal Section 1 and 20 — create permissions, link to web role, add Webapi site settings.

- [ ] **Step 10: Run and verify**

Run: `pwsh -File C:\DCFG\Build-RFP-BidComp-Schema.ps1`
Expected: All tables created, columns added, relationships wired, permissions set

- [ ] **Step 11: Commit**

```bash
git add Build-RFP-BidComp-Schema.ps1
git commit -m "feat: create RFP/BidComp Dataverse tables - rfp_package, rfp_project, rfp_vendor, milestone"
```

---

### Task 5: Build the bid comp read-back parser

**Files:**
- Create: `C:\DCFG\scripts\xlsx-parser\Parse-CompletedBidComp.ps1`

Reads a completed bid comp xlsx (with vendor responses filled in) and extracts structured data for Dataverse.

- [ ] **Step 1: Write the vendor response extractor**

Uses the schema to know exactly which cells contain vendor data:

```powershell
# Parse-CompletedBidComp.ps1
param(
    [string]$BidCompPath,
    [string]$SchemaPath = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json"
)

$schema = Get-Content $SchemaPath | ConvertFrom-Json

# Known cell positions from schema analysis:
# Row 9, cols D/F/H/J/L = Bidder names
# Row 10 = Status
# Row 11 = License
# Row 12 = Contact/Email
# Rows 14-45 = Scope item responses (Y/N/blank)
# Row 60 = Base Contract $
# Row 63 = Sub-Total
# Row 66 = Contract Total
# Row 68 = Low Bid (formula result)

$bidderCols = @('D','F','H','J','L')

function Extract-TradeResponses {
    param([hashtable]$SheetData, [string]$TradeName)

    $bidders = @()
    foreach ($col in $bidderCols) {
        $name = ($SheetData.cells | Where-Object { $_.ref -eq "${col}9" }).value
        if (-not $name -or $name -eq 'Bidding') { continue }

        $scopeResponses = @()
        for ($row = 14; $row -le 45; $row++) {
            $scopeItem = ($SheetData.cells | Where-Object { $_.ref -eq "B${row}" }).value
            $response = ($SheetData.cells | Where-Object { $_.ref -eq "${col}${row}" }).value
            if ($scopeItem) {
                $scopeResponses += @{
                    item = $scopeItem
                    included = ($response -eq 'Y')
                    response = $response
                }
            }
        }

        $pricing = @{
            baseContract = ($SheetData.cells | Where-Object { $_.ref -eq "${col}60" }).value
            subTotal = ($SheetData.cells | Where-Object { $_.ref -eq "${col}63" }).value
            contractTotal = ($SheetData.cells | Where-Object { $_.ref -eq "${col}66" }).value
        }

        $bidders += @{
            name = $name
            column = $col
            license = ($SheetData.cells | Where-Object { $_.ref -eq "${col}11" }).value
            contact = ($SheetData.cells | Where-Object { $_.ref -eq "${col}12" }).value
            status = ($SheetData.cells | Where-Object { $_.ref -eq "${col}10" }).value
            scopeResponses = $scopeResponses
            pricing = $pricing
        }
    }

    return @{
        trade = $TradeName
        bidders = $bidders
    }
}

# Parse all trade sheets
$allResponses = @()
$tradeSheets = @('Carpentry','Roofing','Electrical','Plumbing','HVAC','Painting','Flooring','Glazing','Misc Metals','Spray Insulation','Fire Alarm','Fire Protection','Millwork','Final Cleaning')

foreach ($trade in $tradeSheets) {
    # Extract sheet data using same parse logic as Task 1
    $responses = Extract-TradeResponses -SheetData $sheetData -TradeName $trade
    if ($responses.bidders.Count -gt 0) {
        $allResponses += $responses
    }
}

# Output structured JSON for Dataverse import
$allResponses | ConvertTo-Json -Depth 10
```

- [ ] **Step 2: Test with the Fire Alarm sheet (has real data — Independent Alarm, A&S Alarm)**

The Fire Alarm tab in the template has actual Y/N responses. Use it as test data.

- [ ] **Step 3: Commit**

```bash
git add scripts/xlsx-parser/Parse-CompletedBidComp.ps1
git commit -m "feat: bid comp read-back parser - extracts vendor responses from completed xlsx"
```

---

## Chunk 3: SPA Screens + Integration

### Task 6: Add RFP + Bid Comp entity sets and API functions to portalApi.js

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\portalApi.js` (WITH PERMISSION — SPA is read-only by default)

- [ ] **Step 1: Request SPA write permission from operator**

> "I need to add entity sets and API functions to portalApi.js for the RFP/BidComp tables. This adds: EntitySets for rfp_packages, rfp_projects, rfp_vendors, proposals, milestones. Plus fetch/create/update functions. May I modify portalApi.js?"

- [ ] **Step 2: Add entity sets**

```javascript
// In EntitySets object:
rfp_packages: 'dcfg_rfp_packages',
rfp_projects: 'dcfg_rfp_projects',
rfp_vendors: 'dcfg_rfp_vendors',
proposals: 'dcfg_proposals',
milestones: 'dcfg_milestones',
```

- [ ] **Step 3: Add API functions**

```javascript
export async function fetchRfpPackages(filters = '') {
  const query = filters ? `?$filter=${filters}&$orderby=createdon desc` : '?$orderby=createdon desc';
  return apiGet(`/${EntitySets.rfp_packages}${query}`);
}

export async function fetchRfpDetail(id) {
  return apiGet(`/${EntitySets.rfp_packages}(${id})?$expand=dcfg_customer_id($select=dcfg_display_name)`);
}

export async function createRfpPackage(data) {
  return apiPostReturn(`/${EntitySets.rfp_packages}`, data);
}

export async function fetchProposalsForRfp(rfpId) {
  return apiGet(`/${EntitySets.proposals}?$filter=_dcfg_rfp_package_id_value eq '${rfpId}'&$expand=dcfg_vendor_id($select=dcfg_display_name)`);
}
```

- [ ] **Step 4: Commit**

---

### Task 7: Build RFP List screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-shell\src\screens\RfpList.jsx`
- Modify: `C:\DCFG\spa\dcfg-shell\src\AppRouter.jsx` (add route)

Simple list view: RFP name, customer, status, trade count, vendor count, deadline, total value.

- [ ] **Step 1: Build screen following existing list patterns (ContractList, MsaList)**
- [ ] **Step 2: Add route to AppRouter**
- [ ] **Step 3: Verify in browser**
- [ ] **Step 4: Commit**

---

### Task 8: Build RFP Detail / Bid Comp Status screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-shell\src\screens\RfpDetail.jsx`

Shows: RFP header, linked projects, invited vendors with response status, trade breakdown, bid comp summary (from Dashboard tab data parsed into Dataverse).

- [ ] **Step 1: Build screen with tabs: Overview, Projects, Vendors, Bid Summary**
- [ ] **Step 2: Add route `/rfps/:id` to AppRouter**
- [ ] **Step 3: Verify in browser**
- [ ] **Step 4: Commit**

---

### Task 9: Wire Power Automate flow — SharePoint trigger on bid comp save

**Files:**
- Create: `C:\DCFG\Deploy-BidCompParseFlow.ps1`

Flow watches the Proposals folder in project SharePoint sites. When a bid comp xlsx is saved, it triggers the parse-and-write pipeline.

- [ ] **Step 1: Design flow as Dataverse workflow (per engineering journal Section 5)**

Flow definition:
1. Trigger: SharePoint — When a file is created or modified in folder
2. Condition: filename contains "Bid" and extension is ".xlsx"
3. Action: Get file content
4. Action: HTTP call to Azure Function or inline PowerShell to parse
5. Action: Write parsed data to Dataverse (dcfg_proposal records)
6. Action: Update dcfg_rfp_package status

- [ ] **Step 2: Push flow definition via Dataverse workflows table**
- [ ] **Step 3: Test with a real bid comp file save**
- [ ] **Step 4: Commit**

---

## Chunk 4: End-to-End Test

### Task 10: One real single-trade job — RFP to award

- [ ] **Step 1: Create a test project in Dataverse** (plumbing repair at a Bancroft property)
- [ ] **Step 2: Create an RFP package** (one trade: plumbing, two vendors: GPS Plumbing + Hess Plumbing)
- [ ] **Step 3: System produces pre-filled bid comp xlsx** (only Plumbing trade tab populated, two bidder columns)
- [ ] **Step 4: Manually fill in vendor responses** (GPS: $22K all items Y, Hess: $24K missing 2 items)
- [ ] **Step 5: Save to SharePoint — verify flow triggers and parses**
- [ ] **Step 6: Check Dataverse — verify dcfg_proposal records created with scope items + pricing**
- [ ] **Step 7: Check SPA — verify RFP Detail shows both vendors, pricing, gap indicators**
- [ ] **Step 8: Award GPS Plumbing — verify Exhibit B auto-populates**
- [ ] **Step 9: Document results and any fixes needed**
- [ ] **Step 10: Commit**

```bash
git commit -m "test: end-to-end RFP to award - single trade plumbing job verified"
```

---

## Summary

| Chunk | Tasks | What It Delivers |
|-------|-------|-----------------|
| 1 | 1-3 | Spreadsheet understanding engine — parse, produce, compare bid comp templates |
| 2 | 4-5 | Dataverse tables + read-back parser for RFP/bid comp data |
| 3 | 6-9 | SPA screens + Power Automate integration |
| 4 | 10 | End-to-end test — one real job from RFP to award |

After this plan completes, the core loop works: produce a pre-filled bid comp → SME fills it in → system reads it back → data in Dataverse → visible in SPA. Next plan: **Build 3 — Manage Job** (invoices, change orders, closeout).
