. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    Write-Host "=== ONBOARDING CHECKLIST STEPS (Admin templates) ===" -ForegroundColor Cyan
    # First get all columns
    $steps = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists?`$top=50" -Headers $baseHeaders).value
    Write-Host "  Total: $($steps.Count) steps`n" -ForegroundColor Green
    if ($steps.Count -gt 0) {
        # Show all columns on first record
        Write-Host "`n  Columns on first record:" -ForegroundColor Yellow
        $steps[0].PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -notmatch '@odata|version' } | ForEach-Object {
            Write-Host "    $($_.Name) = $($_.Value)" -ForegroundColor Gray
        }
        Write-Host "`n  All steps:" -ForegroundColor Yellow
        foreach ($s in $steps) {
            $props = @{}
            $s.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -notmatch '@odata|version|_value' } | ForEach-Object { $props[$_.Name] = $_.Value }
            $order = $props['dcfg_step_order'] ?? $props['dcfg_order'] ?? '?'
            $name = $props['dcfg_step_name'] ?? $props['dcfg_description'] ?? $props['dcfg_checklist_name'] ?? ($props.Keys | Where-Object { $_ -match 'name|desc|title' } | ForEach-Object { $props[$_] }) ?? '(unknown)'
            $id = $s.dcfg_onboarding_checklistid
            Write-Host "  #$order | $name | ID: $id" -ForegroundColor Gray
        }
    }
}
