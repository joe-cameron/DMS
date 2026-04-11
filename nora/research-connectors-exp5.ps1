<#
  EXP 5: Full action input comparison — what does a WORKING Test action look like?
#>
$ErrorActionPreference = "Stop"

$dvUrl = "https://org0c17e98d.crm.dynamics.com/"
$tokenObj = Get-AzAccessToken -ResourceUrl $dvUrl -AsSecureString
$token = [System.Net.NetworkCredential]::new("", $tokenObj.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = "application/json"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "${dvUrl}api/data/v9.2"

# Read flow_cert_upload — full action details
$wf = Invoke-RestMethod -Uri "$api/workflows(542faeef-7522-f111-8341-7ced8d709173)?`$select=clientdata" -Headers $h
$cd = $wf.clientdata | ConvertFrom-Json

Write-Host "=== ALL ACTIONS FROM flow_cert_upload (WORKING) ===" -ForegroundColor Cyan
foreach ($a in $cd.properties.definition.actions.PSObject.Properties) {
    $v = $a.Value
    if ($v.type -eq "ApiConnection") {
        Write-Host "`n--- $($a.Name) ---" -ForegroundColor Yellow
        Write-Host "FULL INPUTS:" -ForegroundColor White
        $v.inputs | ConvertTo-Json -Depth 10
    }
}

# Also read flow_send_email for Dataverse CreateRecord format
Write-Host "`n`n=== flow_send_email — CreateRecord action ===" -ForegroundColor Cyan
$wf2 = Invoke-RestMethod -Uri "$api/workflows(212faeef-7522-f111-8341-7ced8d709173)?`$select=clientdata" -Headers $h
$cd2 = $wf2.clientdata | ConvertFrom-Json
foreach ($a in $cd2.properties.definition.actions.PSObject.Properties) {
    $v = $a.Value
    if ($v.type -eq "ApiConnection") {
        Write-Host "`n--- $($a.Name) ---" -ForegroundColor Yellow
        Write-Host "FULL INPUTS:" -ForegroundColor White
        $v.inputs | ConvertTo-Json -Depth 10
    }
}
