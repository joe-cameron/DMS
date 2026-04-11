<#
  EXP 6: Why can't Test flow get a Dataverse trigger?
  Compare connection references and connector types between:
  - DocGen flow (broken trigger selection)
  - flow_cert_alert (has Dataverse trigger — "When a row is added" works)
  - flow_onboarding_init (has Dataverse trigger)
  - flow_commit (has Dataverse trigger)
#>
$ErrorActionPreference = "Stop"

$dvUrl = "https://org0c17e98d.crm.dynamics.com/"
$tokenObj = Get-AzAccessToken -ResourceUrl $dvUrl -AsSecureString
$token = [System.Net.NetworkCredential]::new("", $tokenObj.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = "application/json"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "${dvUrl}api/data/v9.2"

$flows = @(
    @{ Name = "flow_docgen (OURS)"; Id = "3d3d278d-7522-f111-8341-7ced8d709731" }
    @{ Name = "flow_cert_alert"; Id = "534249ee-7522-f111-8341-7ced8d709731" }
    @{ Name = "flow_onboarding_init"; Id = "5e5ffeb9-c722-f111-8341-7ced8d709731" }
    @{ Name = "flow_commit"; Id = "3c3d278d-7522-f111-8341-7ced8d709731" }
)

foreach ($f in $flows) {
    Write-Host "`n=== $($f.Name) ===" -ForegroundColor Cyan
    $wf = Invoke-RestMethod -Uri "$api/workflows($($f.Id))?`$select=clientdata,statecode" -Headers $h
    $cd = $wf.clientdata | ConvertFrom-Json

    # Trigger
    $trigName = ($cd.properties.definition.triggers.PSObject.Properties | Select-Object -First 1).Name
    $trig = ($cd.properties.definition.triggers.PSObject.Properties | Select-Object -First 1).Value
    Write-Host "  Trigger: $trigName | type=$($trig.type) kind=$($trig.kind)" -ForegroundColor White
    if ($trig.inputs.host) {
        Write-Host "  Trigger host:" -ForegroundColor DarkGray
        $trig.inputs.host | ConvertTo-Json -Depth 5
    }
    if ($trig.inputs.parameters) {
        Write-Host "  Trigger params:" -ForegroundColor DarkGray
        $trig.inputs.parameters | ConvertTo-Json -Depth 3
    }

    # Connection references
    Write-Host "  Connection References:" -ForegroundColor Yellow
    foreach ($c in $cd.properties.connectionReferences.PSObject.Properties) {
        Write-Host "    $($c.Name):" -ForegroundColor White
        $c.Value | ConvertTo-Json -Depth 5
    }

    # Check if there's a $connections parameter in definition.parameters
    Write-Host "  Definition parameters:" -ForegroundColor Yellow
    $cd.properties.definition.parameters.PSObject.Properties.Name | ForEach-Object { Write-Host "    $_" }
}
