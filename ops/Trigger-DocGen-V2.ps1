# Fresh DocGen test with aggressive polling
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    $ts = Get-Date -Format 'HHmmss'

    # Use known good IDs
    $customerId = 'f188972b-3e26-f111-8341-7ced8d709731'  # Bancroft
    $vendorId   = 'd19beec7-f920-f111-8341-7ced8d709173'  # Decades Facilities LLC
    $propertyId = '90faceff-931c-f111-8341-7ced8d709173'  # Demo Location
    $templateId = '688d3fde-5e21-f111-8341-7ced8d709173'  # Bancroft_Blanket_Work_Order

    # Create contract
    Write-Host "Creating contract..." -ForegroundColor Cyan
    $contractId = New-Record -setName 'dcfg_contracts' -body @{
        dcfg_contract_family = 100000000
        dcfg_contract_type   = 100000000
        dcfg_status          = 100000000
        dcfg_client_name     = "DocGen Test $ts"
        dcfg_start_date      = '2026-03-24'
        dcfg_fee             = 25000
        'dcfg_customer_id@odata.bind' = "/dcfg_customers($customerId)"
        'dcfg_vendor_id@odata.bind'   = "/dcfg_vendors($vendorId)"
        'dcfg_property_id@odata.bind' = "/dcfg_properties($propertyId)"
    }
    Write-Host "  Contract: $contractId" -ForegroundColor Green

    # Create doc request
    Write-Host "Creating document request..." -ForegroundColor Cyan
    $reqId = New-Record -setName 'dcfg_document_requests' -body @{
        dcfg_name         = "DocGen V2 Test $ts"
        dcfg_request_type = 100000000
        dcfg_status       = 100000000
        dcfg_requested_by = 'jcameron@decades-cg.com'
        'dcfg_contract_id@odata.bind' = "/dcfg_contracts($contractId)"
        'dcfg_template_id@odata.bind' = "/dcfg_document_templates($templateId)"
        'dcfg_customer_id@odata.bind' = "/dcfg_customers($customerId)"
    }
    Write-Host "  Request: $reqId — PENDING" -ForegroundColor Green

    # Poll every 10s for 2 minutes
    Write-Host "`nPolling..." -ForegroundColor Yellow
    $finalStatus = $null
    for ($i = 1; $i -le 12; $i++) {
        Start-Sleep -Seconds 10
        $req = Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($reqId)?`$select=dcfg_status,dcfg_error_message" -Headers $baseHeaders
        $label = switch ($req.dcfg_status) { 100000000 {'Pending'} 100000001 {'Processing'} 100000002 {'Complete'} 100000003 {'Failed'} default {$req.dcfg_status} }
        $color = switch ($req.dcfg_status) { 100000000 {'Gray'} 100000001 {'Yellow'} 100000002 {'Green'} 100000003 {'Red'} default {'Gray'} }
        Write-Host "  ${i}0s: $label" -ForegroundColor $color
        if ($req.dcfg_error_message) { Write-Host "    Error: $($req.dcfg_error_message)" -ForegroundColor Red }

        if ($req.dcfg_status -eq 100000002 -or $req.dcfg_status -eq 100000003) {
            $finalStatus = $label
            break
        }
    }

    if (-not $finalStatus) {
        Write-Host "`n  TIMEOUT — still $label after 2 minutes" -ForegroundColor Red
    } else {
        Write-Host "`n  FINAL: $finalStatus" -ForegroundColor $(if ($finalStatus -eq 'Complete') {'Green'} else {'Red'})
    }

    # Check for output record
    Write-Host "`nChecking outputs..." -ForegroundColor Cyan
    $outputs = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_outputs?`$top=3&`$orderby=createdon desc" -Headers $baseHeaders).value
    if ($outputs.Count -gt 0) {
        Write-Host "  Latest output:" -ForegroundColor Green
        $outputs[0].PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne '' -and $_.Name -match 'dcfg_' -and $_.Name -notmatch '@odata|_value' } | ForEach-Object {
            Write-Host "    $($_.Name) = $($_.Value)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No output records" -ForegroundColor Yellow
    }
}
