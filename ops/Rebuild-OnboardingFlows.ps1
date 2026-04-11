# Rebuild onboarding flows on flushed test environment
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    Write-Host "=== Checking what survived the flush ===" -ForegroundColor Cyan

    # Check our 3 notification flows
    $ourFlows = @(
        @{ name = 'flow_onboarding_notify - Step Ready Notification'; id = '6e06f972-df27-f111-8341-7ced8d709731' },
        @{ name = 'flow_onboarding_cascade - Step Completion Cascade'; id = '1c7f2574-df27-f111-8341-7ced8d709173' },
        @{ name = 'flow_onboarding_overdue - Daily Overdue Check'; id = '7a06f972-df27-f111-8341-7ced8d709731' },
        @{ name = 'flow_onboarding_init'; id = '5e5ffeb9-c722-f111-8341-7ced8d709731' }
    )

    foreach ($f in $ourFlows) {
        try {
            $flow = Invoke-RestMethod -Uri "$OrgUrl/workflows($($f.id))?`$select=name,statecode,statuscode" -Headers $baseHeaders
            Write-Host "  EXISTS: $($flow.name) (state=$($flow.statecode))" -ForegroundColor $(if ($flow.statecode -eq 1) {'Green'} else {'Yellow'})

            # Try to activate if off
            if ($flow.statecode -eq 0) {
                try {
                    Update-Record -setName 'workflows' -id $f.id -body @{ statecode = 1; statuscode = 2 }
                    Write-Host "    -> REACTIVATED" -ForegroundColor Green
                } catch {
                    Write-Host "    -> Activate FAIL: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "  GONE: $($f.name) — needs rebuild" -ForegroundColor Red
        }
    }

    # Check all remaining cloud flows
    Write-Host "`n=== All cloud flows on test ===" -ForegroundColor Cyan
    $allFlows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5&`$select=workflowid,name,statecode&`$orderby=name" -Headers $baseHeaders).value
    Write-Host "  Total: $($allFlows.Count)" -ForegroundColor Gray
    foreach ($af in $allFlows) {
        $state = if ($af.statecode -eq 1) { 'Active' } else { 'Off' }
        $color = if ($af.statecode -eq 1) { 'Green' } else { 'Red' }
        Write-Host "  $state | $($af.name) ($($af.workflowid))" -ForegroundColor $color
    }

    # Check connection references available
    Write-Host "`n=== Connection References ===" -ForegroundColor Cyan
    $connRefs = (Invoke-RestMethod -Uri "$OrgUrl/connectionreferences?`$select=connectionreferencelogicalname,connectorid,connectionid&`$top=20" -Headers $baseHeaders).value
    foreach ($cr in $connRefs) {
        $hasConn = if ($cr.connectionid) { 'CONNECTED' } else { 'NO CONNECTION' }
        Write-Host "  $($cr.connectionreferencelogicalname) | $($cr.connectorid) | $hasConn" -ForegroundColor $(if ($cr.connectionid) {'Green'} else {'Red'})
    }
}
