$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$flowId = '71c2aef7-fd34-f111-88b3-000d3a308bc8'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

$uri = "$orgUrl/api/data/v9.2/workflows($flowId)?`$select=workflowid,name,statecode,clientdata"
$flow = Invoke-RestMethod -Uri $uri -Headers $h

Write-Host "Name:       $($flow.name)"
Write-Host "statecode:  $($flow.statecode)"

$cd = $flow.clientdata | ConvertFrom-Json -Depth 50
$triggers = $cd.properties.definition.triggers
foreach ($p in $triggers.PSObject.Properties) {
    $t = $p.Value
    Write-Host ""
    Write-Host "Trigger Name:  $($p.Name)"
    Write-Host "Type:          $($t.type)"
    if ($t.inputs.parameters) {
        $pe = $t.inputs.parameters.PSObject.Properties
        foreach ($pp in $pe) {
            Write-Host ("  {0} = {1}" -f $pp.Name, ($pp.Value | Out-String).Trim())
        }
    }
}
