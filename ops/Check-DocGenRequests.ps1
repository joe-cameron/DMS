# Check status of the two pending DocGen requests
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

# Check TEST
Write-Host "=== TEST ENV ===" -ForegroundColor Cyan
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    $testReqId = 'ede6b6f6-bd27-f111-8341-7ced8d709173'
    try {
        $req = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($testReqId)" -Headers $baseHeaders
        Write-Host "  Request: $testReqId" -ForegroundColor Green
        $req.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -notmatch '@odata|version' } | ForEach-Object {
            Write-Host "    $($_.Name) = $($_.Value)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Request $testReqId NOT FOUND: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Check DocGen flow status
    $flowId = '3d3d278d-7522-f111-8341-7ced8d709731'
    try {
        $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows($flowId)?`$select=name,statecode,statuscode" -Headers $baseHeaders
        Write-Host "`n  DocGen Flow: $($flow.name) | State: $($flow.statecode) | Status: $($flow.statuscode)" -ForegroundColor $(if ($flow.statecode -eq 1) { 'Green' } else { 'Red' })
    } catch {
        Write-Host "  DocGen flow query failed" -ForegroundColor Red
    }

    # Check recent flow runs
    Write-Host "`n  Recent DocGen flow runs:" -ForegroundColor Yellow
    try {
        $runs = (Invoke-RestMethod -Uri "$OrgUrl/flowsessions?`$filter=_regardingobjectid_value eq $flowId&`$orderby=createdon desc&`$top=5&`$select=createdon,statuscode,startedon,completedon" -Headers $baseHeaders).value
        if ($runs.Count -eq 0) {
            Write-Host "    No flow runs found" -ForegroundColor Yellow
        }
        foreach ($r in $runs) {
            $status = switch ($r.statuscode) { 1 { 'InProgress' } 2 { 'Waiting' } 3 { 'Suspended' } 4 { 'Succeeded' } 5 { 'Failed' } 6 { 'Cancelled' } default { $r.statuscode } }
            Write-Host "    $($r.createdon) | Status: $status" -ForegroundColor $(if ($r.statuscode -eq 4) { 'Green' } elseif ($r.statuscode -eq 5) { 'Red' } else { 'Yellow' })
        }
    } catch {
        Write-Host "    Could not query flow runs: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Check all pending document requests
    Write-Host "`n  All pending document requests:" -ForegroundColor Yellow
    try {
        $pending = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000000&`$select=dcfg_document_requestid,dcfg_request_type,dcfg_status,createdon&`$orderby=createdon desc&`$top=10" -Headers $baseHeaders).value
        Write-Host "    $($pending.Count) pending requests" -ForegroundColor $(if ($pending.Count -eq 0) { 'Green' } else { 'Yellow' })
        foreach ($p in $pending) {
            $age = [math]::Round(((Get-Date) - [datetime]$p.createdon).TotalMinutes, 0)
            Write-Host "    $($p.dcfg_document_requestid) | Type: $($p.dcfg_request_type) | Age: ${age}min" -ForegroundColor $(if ($age -gt 30) { 'Red' } else { 'Yellow' })
        }
    } catch {
        Write-Host "    Query failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check PROD
Write-Host "`n=== PROD ENV ===" -ForegroundColor Cyan
Connect 'https://org06f5de0b.crm.dynamics.com/'
$OrgUrl = 'https://org06f5de0b.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    $prodReqId = '5ee5c4f2-bd27-f111-8341-000d3a35c168'
    try {
        $req = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($prodReqId)" -Headers $baseHeaders
        Write-Host "  Request: $prodReqId" -ForegroundColor Green
        $req.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -notmatch '@odata|version' } | ForEach-Object {
            Write-Host "    $($_.Name) = $($_.Value)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Request $prodReqId NOT FOUND: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Check all active flows
    Write-Host "`n  Active flows:" -ForegroundColor Yellow
    try {
        $flows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5 and statecode eq 1&`$select=workflowid,name,statecode&`$orderby=name" -Headers $baseHeaders).value
        Write-Host "    $($flows.Count) active flows" -ForegroundColor Green
        foreach ($f in $flows) {
            $isDocgen = if ($f.name -match 'docgen|document') { ' <-- DOCGEN' } else { '' }
            Write-Host "    $($f.name) ($($f.workflowid))$isDocgen" -ForegroundColor Gray
        }
    } catch {
        Write-Host "    Flow query failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Check pending requests in prod
    Write-Host "`n  Pending document requests:" -ForegroundColor Yellow
    try {
        $pending = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000000&`$select=dcfg_document_requestid,dcfg_request_type,dcfg_status,createdon&`$orderby=createdon desc&`$top=10" -Headers $baseHeaders).value
        Write-Host "    $($pending.Count) pending" -ForegroundColor $(if ($pending.Count -eq 0) { 'Green' } else { 'Yellow' })
        foreach ($p in $pending) {
            $age = [math]::Round(((Get-Date) - [datetime]$p.createdon).TotalMinutes, 0)
            Write-Host "    $($p.dcfg_document_requestid) | Type: $($p.dcfg_request_type) | Age: ${age}min" -ForegroundColor $(if ($age -gt 30) { 'Red' } else { 'Yellow' })
        }
    } catch {
        Write-Host "    Query failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
