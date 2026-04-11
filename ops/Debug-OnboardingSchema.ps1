. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # Get all columns on dcfg_onboarding_checklist
    Write-Host "=== dcfg_onboarding_checklist columns ===" -ForegroundColor Cyan
    $attrs = (Invoke-RestMethod -Uri "$OrgUrl/EntityDefinitions(LogicalName='dcfg_onboarding_checklist')/Attributes?`$select=LogicalName,AttributeType,DisplayName&`$filter=IsCustomAttribute eq true" -Headers $baseHeaders).value
    foreach ($a in ($attrs | Sort-Object LogicalName)) {
        $label = $a.DisplayName.UserLocalizedLabel.Label
        Write-Host "  $($a.LogicalName) ($($a.AttributeType)) — $label" -ForegroundColor Gray
    }

    # Try minimal create to find what's required
    Write-Host "`n=== Minimal create test ===" -ForegroundColor Cyan
    try {
        $minBody = @{
            dcfg_step_name = 'DELETE ME - schema test'
            dcfg_is_template = $true
        } | ConvertTo-Json -Compress
        $h = $baseHeaders.Clone()
        $h['Content-Type'] = 'application/json; charset=utf-8'
        $h['Prefer'] = 'return=representation'
        $resp = Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists" -Method POST -Body $minBody -Headers $h
        Write-Host "  Created: $($resp.dcfg_onboarding_checklistid)" -ForegroundColor Green
        # Delete it
        Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists($($resp.dcfg_onboarding_checklistid))" -Method DELETE -Headers $baseHeaders | Out-Null
        Write-Host "  Deleted test record" -ForegroundColor Yellow
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            $d = $_.ErrorDetails.Message
            if ($d.Length -gt 500) { $d = $d.Substring(0, 500) }
            Write-Host "  $d" -ForegroundColor Red
        }
    }
}
