. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # Get connection refs from flow_onboarding_init (known working)
    $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows(5e5ffeb9-c722-f111-8341-7ced8d709731)?`$select=clientdata" -Headers $baseHeaders
    $cd = $flow.clientdata | ConvertFrom-Json
    Write-Host "=== Connection References ===" -ForegroundColor Cyan
    $cd.properties.connectionReferences.PSObject.Properties | ForEach-Object {
        Write-Host "  $($_.Name):" -ForegroundColor Yellow
        Write-Host "    $($_.Value | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }

    # Get connection refs from flow_send_email (has Office 365 Outlook)
    $emailFlow = Invoke-RestMethod -Uri "$OrgUrl/workflows(212faeef-7522-f111-8341-7ced8d709173)?`$select=clientdata" -Headers $baseHeaders
    $ecd = $emailFlow.clientdata | ConvertFrom-Json
    Write-Host "`n=== flow_send_email Connection References ===" -ForegroundColor Cyan
    $ecd.properties.connectionReferences.PSObject.Properties | ForEach-Object {
        Write-Host "  $($_.Name):" -ForegroundColor Yellow
        Write-Host "    $($_.Value | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }

    # Get one working Dataverse action host block
    $actions = $cd.properties.definition.actions
    Write-Host "`n=== Sample Dataverse action (first found) ===" -ForegroundColor Cyan
    $firstAction = $actions.PSObject.Properties | Where-Object { $_.Value.type -match 'ApiConnection|OpenApiConnection' } | Select-Object -First 1
    if ($firstAction) {
        Write-Host "  Action: $($firstAction.Name)" -ForegroundColor Yellow
        Write-Host "  Host: $($firstAction.Value.inputs.host | ConvertTo-Json -Compress)" -ForegroundColor Gray
        if ($firstAction.Value.inputs.authentication) {
            Write-Host "  Auth: $($firstAction.Value.inputs.authentication | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
    }

    # Get one working email action from flow_send_email
    $emailActions = $ecd.properties.definition.actions
    Write-Host "`n=== Sample Email action ===" -ForegroundColor Cyan
    $emailAction = $emailActions.PSObject.Properties | Where-Object { $_.Value.inputs.path -match 'sendmail|Mail' -or $_.Name -match 'Send|Email' } | Select-Object -First 1
    if ($emailAction) {
        Write-Host "  Action: $($emailAction.Name)" -ForegroundColor Yellow
        Write-Host "  Full: $($emailAction.Value | ConvertTo-Json -Depth 5 -Compress)" -ForegroundColor Gray
    } else {
        # Just dump all action names
        Write-Host "  No email action found. All actions:" -ForegroundColor Yellow
        $emailActions.PSObject.Properties | ForEach-Object {
            Write-Host "    $($_.Name) ($($_.Value.type))" -ForegroundColor Gray
        }
    }
}
