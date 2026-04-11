. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    # Get the template record to see what URL the flow uses
    $templateId = '688d3fde-5e21-f111-8341-7ced8d709173'
    $template = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_templates($templateId)" -Headers $baseHeaders
    Write-Host "=== Template Record ===" -ForegroundColor Cyan
    $template.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -match 'dcfg_' -and $_.Name -notmatch '@odata|_value' } | ForEach-Object {
        Write-Host "  $($_.Name) = $($_.Value)" -ForegroundColor Gray
    }

    # The flow error showed this path:
    Write-Host "`n=== Flow used this file path ===" -ForegroundColor Yellow
    Write-Host "  https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite/DCFG_Templates/Bancroft_Blanket_Work_Order.docx" -ForegroundColor Gray

    # Check the latest flow run status more carefully
    Write-Host "`n=== Latest document request status ===" -ForegroundColor Cyan
    $reqs = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$orderby=createdon desc&`$top=5&`$select=dcfg_document_requestid,dcfg_name,dcfg_status,dcfg_error_message,createdon,modifiedon" -Headers $baseHeaders).value
    foreach ($r in $reqs) {
        $label = switch ($r.dcfg_status) { 100000000 {'Pending'} 100000001 {'Processing'} 100000002 {'Complete'} 100000003 {'Failed'} default {$r.dcfg_status} }
        Write-Host "  $label | $($r.dcfg_name) | created=$($r.createdon) | modified=$($r.modifiedon)" -ForegroundColor $(switch ($r.dcfg_status) { 100000002 {'Green'} 100000003 {'Red'} default {'Yellow'} })
        if ($r.dcfg_error_message) { Write-Host "    Error: $($r.dcfg_error_message)" -ForegroundColor Red }
    }
}
