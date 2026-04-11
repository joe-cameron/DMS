. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # Exact query the SPA uses
    Write-Host "=== SPA query: _dcfg_case_id_value eq null ===" -ForegroundColor Cyan
    $q = '?$select=dcfg_onboarding_checklistid,dcfg_step_number,dcfg_step_name,dcfg_status,dcfg_is_template&$filter=_dcfg_case_id_value eq null&$orderby=dcfg_step_number asc'
    $results = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists$q" -Headers $baseHeaders).value
    Write-Host "  Found: $($results.Count)" -ForegroundColor Green
    foreach ($r in $results) {
        Write-Host "  #$($r.dcfg_step_number) $($r.dcfg_step_name) | template=$($r.dcfg_is_template)" -ForegroundColor Gray
    }

    # Also check: are our steps there at all?
    Write-Host "`n=== All template steps (dcfg_is_template eq true) ===" -ForegroundColor Cyan
    $templates = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists?`$filter=dcfg_is_template eq true&`$select=dcfg_onboarding_checklistid,dcfg_step_name,dcfg_step_number,_dcfg_case_id_value&`$orderby=dcfg_step_number asc" -Headers $baseHeaders).value
    Write-Host "  Found: $($templates.Count)" -ForegroundColor Green
    foreach ($t in $templates) {
        Write-Host "  #$($t.dcfg_step_number) $($t.dcfg_step_name) | case_id=$($t._dcfg_case_id_value)" -ForegroundColor Gray
    }
}
