. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'
Invoke-DataverseCommands {
    $reqId = 'eb561c12-ec27-f111-8341-7ced8d709173'
    $contractId = 'ea561c12-ec27-f111-8341-7ced8d709173'

    # Check request
    $req = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($reqId)" -Headers $baseHeaders
    $statusLabel = switch ($req.dcfg_status) { 100000000 {'Pending'} 100000001 {'Processing'} 100000002 {'Complete'} 100000003 {'Failed'} default {$req.dcfg_status} }
    Write-Host "Request: $statusLabel ($($req.dcfg_status))" -ForegroundColor $(switch ($req.dcfg_status) { 100000002 {'Green'} 100000003 {'Red'} default {'Yellow'} })

    # Show all non-null fields
    $req.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -match 'dcfg_' -and $_.Name -notmatch '@odata|_value' } | ForEach-Object {
        Write-Host "  $($_.Name) = $($_.Value)" -ForegroundColor Gray
    }

    # Check outputs
    Write-Host "`nDocument outputs for this contract:" -ForegroundColor Cyan
    $outputs = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_outputs?`$filter=_dcfg_contract_id_value eq $contractId&`$top=3" -Headers $baseHeaders).value
    Write-Host "  Count: $($outputs.Count)" -ForegroundColor $(if ($outputs.Count -gt 0) {'Green'} else {'Yellow'})
    foreach ($o in $outputs) {
        $o.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -match 'dcfg_' -and $_.Name -notmatch '@odata|_value' } | ForEach-Object {
            Write-Host "  $($_.Name) = $($_.Value)" -ForegroundColor Gray
        }
    }
}
