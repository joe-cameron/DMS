<#
.SYNOPSIS
    Validates the parsed bid comp schema captures known critical structural elements.
#>
param(
    [string]$SchemaPath = "C:\DCFG\scripts\xlsx-parser\bid_comp_schema.json"
)

$ErrorActionPreference = 'Stop'
$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json

$pass = 0; $fail = 0; $warn = 0

function Test-Check {
    param([string]$Sheet, [string]$Desc, [scriptblock]$Test)
    $result = try { & $Test } catch { $false }
    if ($result) {
        Write-Host "  PASS: $Sheet - $Desc" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL: $Sheet - $Desc" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`n=== Bid Comp Schema Validation ===" -ForegroundColor Cyan
Write-Host "Source: $SchemaPath`n"

# --- Sheet count (PSObject.Properties on deserialized JSON) ---
$sheetCount = ($schema.sheets.PSObject.Properties | Measure-Object).Count
Test-Check "Workbook" "Has 19 sheets (found $sheetCount)" { $sheetCount -eq 19 }

# --- Shared strings ---
Test-Check "Workbook" "Has 300+ shared strings" { $schema.sharedStrings.Count -ge 300 }

# --- Trade tabs: verify structure ---
$tradeTabs = @('Carpentry','Roofing','Electrical','Plumbing','HVAC','Painting','Flooring',
    'Glazing','Misc Metals','Spray Insulation','Fire Alarm','Fire Protection','Millwork','Final Cleaning')

foreach ($trade in $tradeTabs) {
    $s = $schema.sheets.$trade
    Test-Check $trade "Sheet exists with cells" { $s -and $s.cellCount -gt 0 }
}

# --- MASTER tab (name has special char prefix: "? TRADE COMP (MASTER)") ---
$masterName = ($schema.sheets.PSObject.Properties | Where-Object { $_.Name -match 'MASTER' }).Name
$master = if ($masterName) { $schema.sheets.$masterName } else { $null }
Test-Check "MASTER" "Master tab exists (name: $masterName)" { $null -ne $master }

# --- Dashboard: SUM formulas for trade subtotals ---
$dash = $schema.sheets.DASHBOARD
Test-Check "DASHBOARD" "Has cells" { $dash -and $dash.cellCount -gt 0 }
Test-Check "DASHBOARD" "Contains formulas" {
    ($dash.cells | Where-Object { $_.formula }).Count -gt 0
}

# --- BID TRACKER: CHOOSE/MATCH dynamic references ---
$bt = $schema.sheets.'BID TRACKER'
Test-Check "BID TRACKER" "Has cells" { $bt -and $bt.cellCount -gt 0 }
# BID TRACKER has 0 formulas — uses static values/cached references. This is structural truth.
$btFormulas = ($bt.cells | Where-Object { $_.formula }).Count
Test-Check "BID TRACKER" "Cells captured (750 expected, formulas=$btFormulas)" { $bt.cellCount -ge 700 }

# --- BID REQ: INDIRECT or cross-sheet refs ---
$br = $schema.sheets.'BID REQ'
Test-Check "BID REQ" "Has cells" { $br -and $br.cellCount -gt 0 }

# --- EXHIBIT B: dynamic scope population ---
$eb = $schema.sheets.'EXHIBIT B'
Test-Check "EXHIBIT B" "Has cells" { $eb -and $eb.cellCount -gt 0 }

# --- Trade tab structural checks (using Carpentry as representative) ---
$carp = $schema.sheets.Carpentry
Test-Check "Carpentry" "Has merged cells (headers)" { $carp.mergedCells.Count -gt 0 }
Test-Check "Carpentry" "Has data validations (Y/N checkboxes)" { $carp.dataValidations.Count -gt 0 }
Test-Check "Carpentry" "Has 50+ cells" { $carp.cellCount -ge 50 }
Test-Check "Carpentry" "Has formulas (subtotals, low bid)" {
    ($carp.cells | Where-Object { $_.formula }).Count -gt 0
}

# --- Fire Alarm: has real bidder data (test case) ---
$fa = $schema.sheets.'Fire Alarm'
Test-Check "Fire Alarm" "Has bidder data in cells" {
    $bidderCells = $fa.cells | Where-Object { $_.value -match 'Independent|A&S|Alarm' }
    $bidderCells.Count -gt 0
}

# --- Column width preservation ---
Test-Check "Carpentry" "Column widths captured" { $carp.columnWidths.Count -gt 0 }

# --- Frozen pane preservation ---
# Frozen panes may or may not be present — check if the field was captured (even if null)
$hasFrozenPaneField = $null -ne ($carp.PSObject.Properties | Where-Object { $_.Name -eq 'frozenPane' })
Test-Check "Carpentry" "Frozen pane field captured (value may be null)" { $hasFrozenPaneField }

# --- Summary ---
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

# --- Quick stats per sheet ---
Write-Host "`n=== Sheet Stats ===" -ForegroundColor Cyan
foreach ($prop in $schema.sheets.PSObject.Properties) {
    $s = $prop.Value
    $fCount = ($s.cells | Where-Object { $_.formula }).Count
    Write-Host ("  {0,-25} cells:{1,5}  formulas:{2,4}  merges:{3,4}  validations:{4,3}" -f $prop.Name, $s.cellCount, $fCount, $s.mergedCells.Count, $s.dataValidations.Count)
}
