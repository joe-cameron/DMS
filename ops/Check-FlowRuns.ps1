# Check flow run history on prod + investigate test flow link
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

# PROD — check DocGen v2 run history
Write-Host "=== PROD: DocGen v2 flow runs ===" -ForegroundColor Cyan
Connect 'https://org06f5de0b.crm.dynamics.com/'
$OrgUrl = 'https://org06f5de0b.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    $flowId = 'f8e79440-d223-f111-8341-7ced8d7092ad'
    try {
        $runs = (Invoke-RestMethod -Uri "$OrgUrl/flowsessions?`$filter=_regardingobjectid_value eq $flowId&`$orderby=createdon desc&`$top=5&`$select=flowsessionid,createdon,statuscode,startedon,completedon,errorcode,errormessage" -Headers $baseHeaders).value
        Write-Host "  $($runs.Count) recent runs:" -ForegroundColor Green
        foreach ($r in $runs) {
            $status = switch ($r.statuscode) { 1 {'InProgress'} 2 {'Waiting'} 3 {'Suspended'} 4 {'Succeeded'} 5 {'Failed'} 6 {'Cancelled'} 8 {'Failed'} default {$r.statuscode} }
            $color = switch ($r.statuscode) { 4 {'Green'} 5 {'Red'} 8 {'Red'} default {'Yellow'} }
            Write-Host "    $($r.createdon) | $status" -ForegroundColor $color
            if ($r.errormessage) { Write-Host "      Error: $($r.errormessage)" -ForegroundColor Red }
            if ($r.errorcode) { Write-Host "      Code: $($r.errorcode)" -ForegroundColor Red }
        }
    } catch {
        Write-Host "  Flow runs query: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Also recheck the request status
    $prodReqId = '5ee5c4f2-bd27-f111-8341-000d3a35c168'
    try {
        $req = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($prodReqId)?`$select=dcfg_status,dcfg_name,modifiedon,dcfg_error_message,dcfg_notes" -Headers $baseHeaders
        $statusLabel = switch ($req.dcfg_status) { 100000000 {'Pending'} 100000001 {'Processing'} 100000002 {'Complete'} 100000003 {'Failed'} default {$req.dcfg_status} }
        Write-Host "`n  Prod request status: $statusLabel ($($req.dcfg_status))" -ForegroundColor $(if ($req.dcfg_status -eq 100000002) {'Green'} elseif ($req.dcfg_status -eq 100000003) {'Red'} else {'Yellow'})
        if ($req.dcfg_error_message) { Write-Host "  Error: $($req.dcfg_error_message)" -ForegroundColor Red }
        if ($req.dcfg_notes) { Write-Host "  Notes: $($req.dcfg_notes)" -ForegroundColor Gray }
    } catch {
        Write-Host "  Request query failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# TEST — investigate the flow Joseph provided
Write-Host "`n=== TEST: Check flow 6e3e6836... ===" -ForegroundColor Cyan
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    $josephFlowId = '6e3e6836-13b5-436a-a544-42847e62a97e'
    try {
        $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows($josephFlowId)?`$select=name,statecode,statuscode,category" -Headers $baseHeaders
        Write-Host "  Name: $($flow.name)" -ForegroundColor Green
        Write-Host "  State: $($flow.statecode) | Status: $($flow.statuscode) | Category: $($flow.category)" -ForegroundColor Gray
    } catch {
        Write-Host "  Flow $josephFlowId not found: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  This ID might be from the Power Automate portal URL, not a workflow GUID" -ForegroundColor Yellow
    }

    # List ALL flows on test (not just active) to find any docgen-related ones
    Write-Host "`n  All flows matching 'docgen' or 'document':" -ForegroundColor Yellow
    try {
        $allFlows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5&`$select=workflowid,name,statecode,statuscode&`$orderby=name" -Headers $baseHeaders).value
        $docgenFlows = $allFlows | Where-Object { $_.name -match 'docgen|document|doc.gen|DocGen' }
        if ($docgenFlows.Count -eq 0) {
            Write-Host "    None found. All test flows:" -ForegroundColor Yellow
            foreach ($f in $allFlows) {
                $state = if ($f.statecode -eq 1) { 'Active' } else { 'Off' }
                Write-Host "    $state | $($f.name) ($($f.workflowid))" -ForegroundColor $(if ($f.statecode -eq 1) {'Green'} else {'Gray'})
            }
        } else {
            foreach ($f in $docgenFlows) {
                $state = if ($f.statecode -eq 1) { 'Active' } else { 'Off' }
                Write-Host "    $state | $($f.name) ($($f.workflowid))" -ForegroundColor $(if ($f.statecode -eq 1) {'Green'} else {'Red'})
            }
        }
    } catch {
        Write-Host "    Query failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
