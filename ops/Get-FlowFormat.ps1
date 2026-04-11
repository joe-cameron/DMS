. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # Get flow_onboarding_init clientdata to see the schema
    $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows(5e5ffeb9-c722-f111-8341-7ced8d709731)?`$select=clientdata" -Headers $baseHeaders
    $cd = $flow.clientdata | ConvertFrom-Json
    # Show top-level keys
    Write-Host "Top-level keys:" -ForegroundColor Cyan
    $cd.PSObject.Properties.Name | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    Write-Host "`nproperties keys:" -ForegroundColor Cyan
    $cd.properties.PSObject.Properties.Name | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    # Show schemaVersion and other required fields
    Write-Host "`nschemaVersion: $($cd.properties.definition.schemaVersion)" -ForegroundColor Yellow

    # Dump the minimal top-level structure (not full actions)
    $minimal = @{
        properties = @{
            definition = @{
                schemaVersion = $cd.properties.definition.schemaVersion
                contentVersion = $cd.properties.definition.contentVersion
                actions_count = ($cd.properties.definition.actions.PSObject.Properties).Count
                triggers_count = ($cd.properties.definition.triggers.PSObject.Properties).Count
            }
            connectionReferences = 'exists'
        }
    }
    Write-Host "`nMinimal structure:" -ForegroundColor Cyan
    Write-Host ($minimal | ConvertTo-Json -Depth 5) -ForegroundColor Gray

    # Show the full top-level clientdata (first 1000 chars)
    $raw = $flow.clientdata
    Write-Host "`nRaw clientdata (first 1000):" -ForegroundColor Cyan
    Write-Host $raw.Substring(0, [Math]::Min(1000, $raw.Length)) -ForegroundColor Gray
}
