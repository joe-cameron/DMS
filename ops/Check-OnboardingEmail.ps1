. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # Check flow_onboarding_init
    $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows(5e5ffeb9-c722-f111-8341-7ced8d709731)?`$select=name,statecode,statuscode" -Headers $baseHeaders
    Write-Host "flow_onboarding_init: state=$($flow.statecode) status=$($flow.statuscode)" -ForegroundColor Cyan

    # Check flow_send_email
    $emailFlow = Invoke-RestMethod -Uri "$OrgUrl/workflows(212faeef-7522-f111-8341-7ced8d709173)?`$select=name,statecode,statuscode" -Headers $baseHeaders
    Write-Host "flow_send_email: state=$($emailFlow.statecode) status=$($emailFlow.statuscode)" -ForegroundColor Cyan

    # Check our test case
    $case = Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_cases(7d850640-db27-f111-8341-7ced8d709731)" -Headers $baseHeaders
    Write-Host "`nCase: $($case.dcfg_case_number) | status=$($case.dcfg_status) | initiated=$($case.dcfg_initiated_date)" -ForegroundColor Green
    $case.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -match 'dcfg_' -and $_.Name -notmatch '@odata|version|_value' } | ForEach-Object {
        Write-Host "  $($_.Name) = $($_.Value)" -ForegroundColor Gray
    }

    # Check steps email status
    Write-Host "`nSteps:" -ForegroundColor Yellow
    $steps = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists?`$filter=_dcfg_case_id_value eq 7d850640-db27-f111-8341-7ced8d709731&`$select=dcfg_step_name,dcfg_assigned_email,dcfg_email_triggered,dcfg_step_number,dcfg_status,dcfg_planner_task_id&`$orderby=dcfg_step_number asc" -Headers $baseHeaders).value
    foreach ($s in $steps) {
        Write-Host "  #$($s.dcfg_step_number) $($s.dcfg_step_name) | email=$($s.dcfg_assigned_email) | triggered=$($s.dcfg_email_triggered) | status=$($s.dcfg_status) | planner=$($s.dcfg_planner_task_id)" -ForegroundColor Gray
    }

    # Check send_queue for any pending sends
    Write-Host "`nSend queue (recent):" -ForegroundColor Yellow
    $queue = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_send_queues?`$top=5&`$orderby=createdon desc&`$select=dcfg_name,dcfg_queue_status,createdon" -Headers $baseHeaders).value
    if ($queue.Count -eq 0) { Write-Host "  Empty" -ForegroundColor Gray }
    foreach ($q in $queue) {
        Write-Host "  $($q.dcfg_name) | status=$($q.dcfg_queue_status) | $($q.createdon)" -ForegroundColor Gray
    }

    # Check if flow_onboarding_init has run recently
    Write-Host "`nflow_onboarding_init recent runs:" -ForegroundColor Yellow
    $runs = (Invoke-RestMethod -Uri "$OrgUrl/flowsessions?`$filter=_regardingobjectid_value eq 5e5ffeb9-c722-f111-8341-7ced8d709731&`$orderby=createdon desc&`$top=5&`$select=createdon,statuscode,completedon" -Headers $baseHeaders).value
    if ($runs.Count -eq 0) { Write-Host "  No runs" -ForegroundColor Red }
    foreach ($r in $runs) {
        $status = switch ($r.statuscode) { 4 {'Succeeded'} 5 {'Failed'} default {$r.statuscode} }
        Write-Host "  $($r.createdon) | $status" -ForegroundColor $(if ($r.statuscode -eq 4) {'Green'} else {'Red'})
    }
}
