. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'
Invoke-DataverseCommands {
    $flows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5&`$select=workflowid,name,statecode&`$orderby=name" -Headers $baseHeaders).value
    Write-Host "Total: $($flows.Count) flows" -ForegroundColor Cyan
    $active = ($flows | Where-Object { $_.statecode -eq 1 }).Count
    Write-Host "Active: $active | Off: $($flows.Count - $active)`n" -ForegroundColor $(if ($active -gt 0) {'Green'} else {'Red'})
    foreach ($f in $flows) {
        $s = if ($f.statecode -eq 1) {'Active'} else {'Off   '}
        $c = if ($f.statecode -eq 1) {'Green'} else {'Red'}
        Write-Host "  $s | $($f.name) ($($f.workflowid))" -ForegroundColor $c
    }

    # Check pending doc requests
    Write-Host "`nPending doc requests:" -ForegroundColor Cyan
    $pending = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000000 or dcfg_status eq 100000001&`$select=dcfg_document_requestid,dcfg_name,dcfg_status,createdon&`$orderby=createdon desc&`$top=5" -Headers $baseHeaders).value
    if ($pending.Count -eq 0) { Write-Host "  None" -ForegroundColor Green }
    foreach ($p in $pending) {
        $statusLabel = switch ($p.dcfg_status) { 100000000 {'Pending'} 100000001 {'Processing'} default {$p.dcfg_status} }
        Write-Host "  $statusLabel | $($p.dcfg_name) | $($p.createdon)" -ForegroundColor Yellow
    }
}
