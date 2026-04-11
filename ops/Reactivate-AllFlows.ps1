# Reactivate all deactivated flows on test
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    # Get all cloud flows (category=5)
    Write-Host "=== All Cloud Flows ===" -ForegroundColor Cyan
    $flows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5&`$select=workflowid,name,statecode,statuscode&`$orderby=name" -Headers $baseHeaders).value

    $active = 0; $down = 0; $reactivated = 0; $failed = 0

    foreach ($f in $flows) {
        $state = if ($f.statecode -eq 1) { 'Active' } else { 'Off' }

        if ($f.statecode -eq 0) {
            Write-Host "  OFF: $($f.name) ($($f.workflowid))" -ForegroundColor Red
            # Try to reactivate
            try {
                Update-Record -setName 'workflows' -id $f.workflowid -body @{ statecode = 1; statuscode = 2 }
                Write-Host "    -> REACTIVATED" -ForegroundColor Green
                $reactivated++
            } catch {
                Write-Host "    -> FAIL: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.ErrorDetails.Message) {
                    $d = $_.ErrorDetails.Message
                    if ($d.Length -gt 300) { $d = $d.Substring(0, 300) }
                    Write-Host "    $d" -ForegroundColor Red
                }
                $failed++
            }
            $down++
        } else {
            Write-Host "  OK: $($f.name)" -ForegroundColor Green
            $active++
        }
    }

    Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
    Write-Host "  Total: $($flows.Count) | Already active: $active | Were off: $down" -ForegroundColor Gray
    Write-Host "  Reactivated: $reactivated | Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
}
