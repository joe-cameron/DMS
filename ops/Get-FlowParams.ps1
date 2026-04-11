. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'
Invoke-DataverseCommands {
    $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows(5e5ffeb9-c722-f111-8341-7ced8d709731)?`$select=clientdata" -Headers $baseHeaders
    $cd = $flow.clientdata | ConvertFrom-Json
    # Show parameters and connections sections
    $def = $cd.properties.definition
    Write-Host "=== parameters ===" -ForegroundColor Cyan
    if ($def.parameters) {
        Write-Host ($def.parameters | ConvertTo-Json -Depth 5) -ForegroundColor Gray
    } else {
        Write-Host "  NONE" -ForegroundColor Red
    }
    Write-Host "`n=== `$connections in parameters ===" -ForegroundColor Cyan
    if ($def.'$connections') {
        Write-Host ($def.'$connections' | ConvertTo-Json -Depth 5) -ForegroundColor Gray
    }
    # Show trigger inputs
    Write-Host "`n=== trigger ===" -ForegroundColor Cyan
    $trigger = $def.triggers.PSObject.Properties | Select-Object -First 1
    Write-Host "  Name: $($trigger.Name)" -ForegroundColor Yellow
    Write-Host "  Type: $($trigger.Value.type)" -ForegroundColor Gray
    Write-Host "  Inputs:" -ForegroundColor Gray
    Write-Host ($trigger.Value.inputs | ConvertTo-Json -Depth 5 -Compress) -ForegroundColor Gray
}
