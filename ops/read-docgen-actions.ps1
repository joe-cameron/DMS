# Read DocGen v2 flow and list all action names
$t = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
# DocGen v2 flow ID from clipboard
$flowId = "42fae156-8575-9ef8-4224-15e286ab5264"

Write-Output "Reading DocGen v2 flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h

# Save full definition for inspection
$flow.properties.definition | ConvertTo-Json -Depth 100 | Out-File "C:\DCFG\ops\_docgen_v2_current.json" -Encoding UTF8
Write-Output "Saved to _docgen_v2_current.json"

# List all actions that contain "Populate" or "Set_Doc"
function List-Actions($actions, $prefix) {
    foreach ($prop in $actions.PSObject.Properties) {
        $name = $prop.Name
        $action = $prop.Value
        $type = $action.type

        if ($name -match 'Populate|Set_Doc|Set Doc') {
            Write-Output "$prefix$name (type=$type)"
            # If Set Variable, show current value expression
            if ($type -eq 'SetVariable' -or $type -eq 'InitializeVariable') {
                $val = $action.inputs | ConvertTo-Json -Depth 5 -Compress
                Write-Output "  inputs: $val"
            }
        }

        # Recurse into Switch cases
        if ($action.cases) {
            foreach ($caseProp in $action.cases.PSObject.Properties) {
                $caseName = $caseProp.Name
                $caseActions = $caseProp.Value.actions
                if ($caseActions) {
                    List-Actions $caseActions "$prefix  [$caseName] "
                }
            }
        }

        # Recurse into Scope/Foreach
        if ($action.actions -and $type -ne 'Switch') {
            List-Actions $action.actions "$prefix  "
        }
    }
}

Write-Output ""
Write-Output "=== Populate and Set_Doc actions ==="
List-Actions $flow.properties.definition.actions ""
