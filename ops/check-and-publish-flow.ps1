# Check if Set_Doc values are already set, then publish
$t = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "42fae156-8575-9ef8-4224-15e286ab5264"

Write-Output "Reading current flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h
Write-Output "Flow state: $($flow.properties.state)"

$switch = $null
foreach ($prop in $flow.properties.definition.actions.PSObject.Properties) {
    if ($prop.Value.type -eq 'Switch') { $switch = $prop.Value; break }
}

# Check each Set_Doc action for value
$hasValue = 0
$noValue = 0
foreach ($caseProp in $switch.cases.PSObject.Properties) {
    $caseName = $caseProp.Name
    foreach ($actProp in $caseProp.Value.actions.PSObject.Properties) {
        if ($actProp.Name -match '^Set_Doc') {
            $val = $actProp.Value.inputs.value
            if ($val) {
                $hasValue++
                Write-Output "OK: [$caseName] $($actProp.Name) = $val"
            } else {
                $noValue++
                Write-Output "MISSING: [$caseName] $($actProp.Name)"
            }
        }
    }
}

Write-Output ""
Write-Output "Has value: $hasValue / Missing: $noValue"

# Try to turn off and on to clear the unpublished state
if ($hasValue -eq 16) {
    Write-Output ""
    Write-Output "All values set! Toggling flow off/on to publish..."

    # Turn off
    try {
        Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId/stop?api-version=2016-11-01" -Headers $h -Method Post | Out-Null
        Write-Output "Flow stopped"
    } catch {
        Write-Output "Stop failed: $($_.ErrorDetails.Message)"
    }

    Start-Sleep -Seconds 2

    # Turn on
    try {
        Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId/start?api-version=2016-11-01" -Headers $h -Method Post | Out-Null
        Write-Output "Flow started"
    } catch {
        Write-Output "Start failed: $($_.ErrorDetails.Message)"
    }

    # Verify
    $flow2 = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h
    Write-Output "Final state: $($flow2.properties.state)"
}
