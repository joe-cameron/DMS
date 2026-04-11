# Create contract + document request to trigger DocGen v2 test
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT!" -ForegroundColor Red; return }

    # Find Bancroft customer
    Write-Host "=== Finding test data ===" -ForegroundColor Cyan
    $customer = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_customers?`$filter=dcfg_name eq 'Bancroft'&`$select=dcfg_customerid,dcfg_name&`$top=1" -Headers $baseHeaders).value
    if ($customer.Count -eq 0) {
        $customer = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_customers?`$select=dcfg_customerid,dcfg_name&`$top=1" -Headers $baseHeaders).value
    }
    Write-Host "  Customer: $($customer[0].dcfg_name) ($($customer[0].dcfg_customerid))" -ForegroundColor Green

    # Find a vendor
    $vendor = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_vendors?`$select=dcfg_vendorid,dcfg_display_name&`$top=1" -Headers $baseHeaders).value
    Write-Host "  Vendor: $($vendor[0].dcfg_display_name) ($($vendor[0].dcfg_vendorid))" -ForegroundColor Green

    # Find a property
    $property = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_properties?`$select=dcfg_propertyid,dcfg_name&`$top=1" -Headers $baseHeaders).value
    Write-Host "  Property: $($property[0].dcfg_name) ($($property[0].dcfg_propertyid))" -ForegroundColor Green

    # Find Bancroft_Blanket_Work_Order template
    # Get all templates - discover column names
    $template = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_templates?`$top=5" -Headers $baseHeaders).value
    if ($template.Count -gt 0) {
        # Find name column
        $nameCol = $template[0].PSObject.Properties | Where-Object { $_.Name -match 'name' -and $_.Name -notmatch '@odata|_value' } | Select-Object -First 1
        Write-Host "  Template name column: $($nameCol.Name)" -ForegroundColor Gray
        foreach ($t in $template) {
            $tName = $t.PSObject.Properties | Where-Object { $_.Name -match 'name' -and $_.Name -notmatch '@odata|_value' -and $null -ne $_.Value } | Select-Object -First 1
            Write-Host "    $($tName.Value) ($($t.dcfg_document_templateid))" -ForegroundColor Gray
        }
        # Find Bancroft_Blanket
        $bancroft = $template | Where-Object { ($_.PSObject.Properties | Where-Object { $_.Value -match 'Bancroft_Blanket' }).Count -gt 0 }
        if ($bancroft) { $template = @($bancroft) } else { $template = @($template[0]) }
    }
    Write-Host "  Using template: $($template[0].dcfg_document_templateid)" -ForegroundColor Green

    # Create contract
    Write-Host "`n=== Creating contract ===" -ForegroundColor Cyan
    $ts = Get-Date -Format 'HHmmss'
    $contractId = New-Record -setName 'dcfg_contracts' -body @{
        dcfg_contract_family    = 100000000
        dcfg_contract_type      = 100000000
        dcfg_status             = 100000000
        dcfg_client_name        = "Bancroft Real Estate - DocGen Test"
        dcfg_start_date         = '2026-03-24'
        dcfg_end_date           = '2027-03-24'
        dcfg_fee                = 35000
        dcfg_description_of_work = 'Facilities maintenance and management services for residential properties.'
        dcfg_po_number          = "PO-2026-TEST-$ts"
        dcfg_work_category      = 100000000
        'dcfg_customer_id@odata.bind' = "/dcfg_customers($($customer[0].dcfg_customerid))"
        'dcfg_vendor_id@odata.bind'   = "/dcfg_vendors($($vendor[0].dcfg_vendorid))"
        'dcfg_property_id@odata.bind' = "/dcfg_properties($($property[0].dcfg_propertyid))"
    }
    Write-Host "  Contract: $contractId" -ForegroundColor Green

    # Create document request
    Write-Host "`n=== Creating document request ===" -ForegroundColor Cyan
    $reqId = New-Record -setName 'dcfg_document_requests' -body @{
        dcfg_name           = "DocGen Test - Bancroft Blanket WO - $ts"
        dcfg_request_type   = 100000000
        dcfg_status         = 100000000
        dcfg_requested_by   = 'jcameron@decades-cg.com'
        'dcfg_contract_id@odata.bind'  = "/dcfg_contracts($contractId)"
        'dcfg_template_id@odata.bind'  = "/dcfg_document_templates($($template[0].dcfg_document_templateid))"
        'dcfg_customer_id@odata.bind'  = "/dcfg_customers($($customer[0].dcfg_customerid))"
    }
    Write-Host "  Request: $reqId" -ForegroundColor Green
    Write-Host "  Status: Pending (100000000) — DocGen v2 should pick this up" -ForegroundColor Yellow

    Write-Host "`n=== MONITORING ===" -ForegroundColor Cyan
    Write-Host "  Contract: $contractId" -ForegroundColor Gray
    Write-Host "  Request: $reqId" -ForegroundColor Gray
    Write-Host "  Flow: ac8f2d1e-e327-f111-8341-7ced8d709173" -ForegroundColor Gray
    Write-Host "  Waiting 30s then checking status..." -ForegroundColor Yellow

    Start-Sleep -Seconds 30

    # Check request status
    $req = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($reqId)?`$select=dcfg_status,dcfg_name,dcfg_error_message" -Headers $baseHeaders
    $statusLabel = switch ($req.dcfg_status) { 100000000 {'Pending'} 100000001 {'Processing'} 100000002 {'Complete'} 100000003 {'Failed'} default {$req.dcfg_status} }
    Write-Host "`n  Request status after 30s: $statusLabel ($($req.dcfg_status))" -ForegroundColor $(switch ($req.dcfg_status) { 100000002 {'Green'} 100000003 {'Red'} default {'Yellow'} })
    if ($req.dcfg_error_message) { Write-Host "  Error: $($req.dcfg_error_message)" -ForegroundColor Red }

    # Check for document output
    $outputs = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_outputs?`$filter=_dcfg_contract_id_value eq $contractId&`$select=dcfg_document_outputid,dcfg_document_url&`$top=1" -Headers $baseHeaders).value
    if ($outputs.Count -gt 0) {
        Write-Host "  Output: $($outputs[0].dcfg_document_url)" -ForegroundColor Green
    } else {
        Write-Host "  No output record yet" -ForegroundColor Yellow
    }
}
