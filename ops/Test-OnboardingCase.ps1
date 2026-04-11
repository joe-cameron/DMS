# Create a new onboarding case to test the full 15-step flow with Test1/Test2 emails
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    # ── Find a customer to attach the case to ──
    Write-Host "=== Finding test customer ===" -ForegroundColor Cyan
    $customers = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_customers?`$select=dcfg_customerid,dcfg_name&`$top=5&`$orderby=dcfg_name" -Headers $baseHeaders).value
    foreach ($c in $customers) {
        Write-Host "  $($c.dcfg_name) ($($c.dcfg_customerid))" -ForegroundColor Gray
    }
    $testCustomer = $customers | Where-Object { $_.dcfg_name -match 'Heritage|Bancroft|SCARC' } | Select-Object -First 1
    if (-not $testCustomer) { $testCustomer = $customers[0] }
    Write-Host "  Using: $($testCustomer.dcfg_name)" -ForegroundColor Green

    # ── Find an MSA for this customer ──
    Write-Host "`n=== Finding MSA ===" -ForegroundColor Cyan
    $msas = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_msas?`$select=dcfg_msaid,dcfg_name&`$filter=_dcfg_customer_id_value eq $($testCustomer.dcfg_customerid)&`$top=3" -Headers $baseHeaders).value
    if ($msas.Count -gt 0) {
        $testMsa = $msas[0]
        Write-Host "  Using: $($testMsa.dcfg_name) ($($testMsa.dcfg_msaid))" -ForegroundColor Green
    } else {
        Write-Host "  No MSA found for this customer" -ForegroundColor Yellow
        $testMsa = $null
    }

    # ── Create the onboarding case ──
    Write-Host "`n=== Creating onboarding case ===" -ForegroundColor Cyan
    $caseBody = @{
        dcfg_case_number = 'OB-TEST-001'
        dcfg_status = 100000000  # Not Started
        'dcfg_customer_id@odata.bind' = "/dcfg_customers($($testCustomer.dcfg_customerid))"
    }
    if ($testMsa) {
        $caseBody['dcfg_msa_id@odata.bind'] = "/dcfg_msas($($testMsa.dcfg_msaid))"
    }

    try {
        $caseId = New-Record -setName 'dcfg_onboarding_cases' -body $caseBody
        Write-Host "  Case created: $caseId" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            $d = $_.ErrorDetails.Message
            if ($d.Length -gt 400) { $d = $d.Substring(0, 400) }
            Write-Host "  $d" -ForegroundColor Red
        }
        return
    }

    # ── Copy template steps to this case ──
    Write-Host "`n=== Copying 15 template steps to case ===" -ForegroundColor Cyan
    $templates = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists?`$filter=dcfg_is_template eq true and _dcfg_case_id_value eq null&`$orderby=dcfg_step_number asc" -Headers $baseHeaders).value
    Write-Host "  Templates found: $($templates.Count)" -ForegroundColor Gray

    $copied = 0
    foreach ($t in $templates) {
        $stepBody = @{
            dcfg_step_name          = $t.dcfg_step_name
            dcfg_step_number        = $t.dcfg_step_number
            dcfg_phase              = $t.dcfg_phase
            dcfg_is_template        = $false
            dcfg_responsible_person = $t.dcfg_responsible_person
            dcfg_assigned_email     = $t.dcfg_assigned_email
            dcfg_assigned_name      = $t.dcfg_assigned_name
            dcfg_accountable        = $t.dcfg_accountable
            dcfg_accountable_email  = $t.dcfg_accountable_email
            dcfg_accountable_name   = $t.dcfg_accountable_name
            dcfg_dependency_type    = $t.dcfg_dependency_type
            dcfg_is_complete        = $false
            'dcfg_case_id@odata.bind' = "/dcfg_onboarding_cases($caseId)"
            'dcfg_customer_id@odata.bind' = "/dcfg_customers($($testCustomer.dcfg_customerid))"
        }
        if ($t.dcfg_consulted) { $stepBody['dcfg_consulted'] = $t.dcfg_consulted }
        if ($t.dcfg_informed) { $stepBody['dcfg_informed'] = $t.dcfg_informed }

        try {
            $stepId = New-Record -setName 'dcfg_onboarding_checklists' -body $stepBody
            Write-Host "  #$($t.dcfg_step_number) $($t.dcfg_step_name) => $stepId" -ForegroundColor Green
            $copied++
        } catch {
            Write-Host "  FAIL #$($t.dcfg_step_number) $($t.dcfg_step_name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
    Write-Host "  Case: OB-TEST-001 ($caseId)" -ForegroundColor Green
    Write-Host "  Customer: $($testCustomer.dcfg_name)" -ForegroundColor Gray
    Write-Host "  Steps copied: $copied / $($templates.Count)" -ForegroundColor Green
    Write-Host "  Emails: Test1@decades-cg.com, Test2@decades-cg.com" -ForegroundColor Gray
    Write-Host "`n  View at: https://dcfg.powerappsportals.com/#/onboarding/$caseId" -ForegroundColor Cyan
}
