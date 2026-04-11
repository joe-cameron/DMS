# Create onboarding flows from scratch with live connection references
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

$orgId = 'org0c17e98d.crm.dynamics.com'

# Use the LIVE connection references from the flushed environment
$connectionReferences = @{
    shared_commondataserviceforapps = @{
        runtimeSource = 'embedded'
        connection = @{ connectionReferenceLogicalName = 'dcfg_dataverse_connection' }
        api = @{ name = 'shared_commondataserviceforapps' }
        impersonation = @{}
    }
    shared_sendmail = @{
        runtimeSource = 'embedded'
        connection = @{ connectionReferenceLogicalName = 'dcfg_sharedsendmail_1a963' }
        api = @{ name = 'shared_sendmail' }
    }
}

$dvHost = @{ connection = @{ name = "@parameters('`$connections')['shared_commondataserviceforapps']['connectionId']" } }
$mailHost = @{ connection = @{ name = "@parameters('`$connections')['shared_sendmail']['connectionId']" } }
$auth = "@parameters('`$authentication')"
$params = @{
    '$connections' = @{ defaultValue = @{}; type = 'Object' }
    '$authentication' = @{ defaultValue = @{}; type = 'SecureObject' }
}

function Build-FlowClientData($triggers, $actions) {
    return @{
        schemaVersion = '1.0.0.0'
        properties = @{
            connectionReferences = $connectionReferences
            definition = @{
                '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                contentVersion = '1.0.0.0'
                parameters = $params
                triggers = $triggers
                actions = $actions
            }
        }
    } | ConvertTo-Json -Depth 20 -Compress
}

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT!" -ForegroundColor Red; return }

    $httpTrigger = @{
        manual = @{
            type = 'Request'; kind = 'Http'
            inputs = @{ schema = @{ type = 'object'; properties = @{ step_id = @{ type = 'string' } } } }
        }
    }

    # ══════════════════════════════════════
    # FLOW 1: Notify — send email when step is ready
    # ══════════════════════════════════════
    Write-Host "=== FLOW 1: flow_onboarding_notify ===" -ForegroundColor Cyan

    $f1Actions = @{
        Get_Step = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{triggerBody()?['step_id']}"
                authentication = $auth }
            runAfter = @{}
        }
        Get_Case = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_cases'))}/items/@{body('Get_Step')?['_dcfg_case_id_value']}"
                authentication = $auth }
            runAfter = @{ Get_Step = @('Succeeded') }
        }
        Get_Customer = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_customers'))}/items/@{body('Get_Case')?['_dcfg_customer_id_value']}"
                authentication = $auth }
            runAfter = @{ Get_Case = @('Succeeded') }
        }
        Send_Ready_Email = @{
            type = 'ApiConnection'
            inputs = @{ host = $mailHost; method = 'post'; path = '/v3/mail/send'
                body = @{
                    to = "@{body('Get_Step')?['dcfg_assigned_email']}"
                    subject = "[DCFG] Your turn: @{body('Get_Step')?['dcfg_step_name']} - @{coalesce(body('Get_Customer')?['dcfg_name'],'Customer')} onboarding"
                    text = "<h2>Step Ready: @{body('Get_Step')?['dcfg_step_name']}</h2><p><b>Customer:</b> @{coalesce(body('Get_Customer')?['dcfg_name'],'N/A')}</p><p><b>Case:</b> @{coalesce(body('Get_Case')?['dcfg_case_number'],'N/A')}</p><p><b>Accountable:</b> @{coalesce(body('Get_Step')?['dcfg_accountable_email'],'')}</p><p><a href='https://dcfg.powerappsportals.com/#/onboarding/@{body('Get_Case')?['dcfg_onboarding_caseid']}'>Open Case</a></p><p>Mark complete when done - next step notified automatically.</p>"
                    ishtml = $true
                }
                authentication = $auth }
            runAfter = @{ Get_Customer = @('Succeeded') }
        }
        Mark_Triggered = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'patch'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{triggerBody()?['step_id']}"
                body = @{ dcfg_email_triggered = $true }
                authentication = $auth }
            runAfter = @{ Send_Ready_Email = @('Succeeded') }
        }
    }

    $f1Data = Build-FlowClientData $httpTrigger $f1Actions
    try {
        $f1Id = New-Record -setName 'workflows' -body @{
            name = 'flow_onboarding_notify - Step Ready Notification'
            type = 1; category = 5; statecode = 0; statuscode = 1
            primaryentity = 'none'; scope = 4; mode = 0; languagecode = 1033
            clientdata = $f1Data
        }
        Write-Host "  Created + Active: $f1Id" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(400, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
    }

    # ══════════════════════════════════════
    # FLOW 2: Cascade — mark dependent steps ready when predecessor completes
    # ══════════════════════════════════════
    Write-Host "`n=== FLOW 2: flow_onboarding_cascade ===" -ForegroundColor Cyan

    $f2Actions = @{
        Get_Completed = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{triggerBody()?['step_id']}"
                authentication = $auth }
            runAfter = @{}
        }
        Find_Dependents = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items"
                queries = @{ '$filter' = "_dcfg_case_id_value eq @{body('Get_Completed')?['_dcfg_case_id_value']} and dcfg_predecessor_step eq @{body('Get_Completed')?['dcfg_step_number']} and dcfg_is_complete eq false" }
                authentication = $auth }
            runAfter = @{ Get_Completed = @('Succeeded') }
        }
        Loop_Dependents = @{
            type = 'Foreach'
            foreach = "@body('Find_Dependents')?['value']"
            actions = @{
                Mark_Ready = @{
                    type = 'ApiConnection'
                    inputs = @{ host = $dvHost; method = 'patch'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{items('Loop_Dependents')?['dcfg_onboarding_checklistid']}"
                        body = @{ dcfg_status = 100000001 }
                        authentication = $auth }
                    runAfter = @{}
                }
                Notify_Email = @{
                    type = 'ApiConnection'
                    inputs = @{ host = $mailHost; method = 'post'; path = '/v3/mail/send'
                        body = @{
                            to = "@{items('Loop_Dependents')?['dcfg_assigned_email']}"
                            subject = "[DCFG] Your turn: @{items('Loop_Dependents')?['dcfg_step_name']} is ready"
                            text = "<h2>Step Ready: @{items('Loop_Dependents')?['dcfg_step_name']}</h2><p>Previous step completed. You can begin.</p><p><b>Assigned:</b> @{items('Loop_Dependents')?['dcfg_assigned_email']}</p><p><a href='https://dcfg.powerappsportals.com/#/onboarding/@{body('Get_Completed')?['_dcfg_case_id_value']}'>Open Case</a></p>"
                            ishtml = $true
                        }
                        authentication = $auth }
                    runAfter = @{ Mark_Ready = @('Succeeded') }
                }
                Flag_Triggered = @{
                    type = 'ApiConnection'
                    inputs = @{ host = $dvHost; method = 'patch'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{items('Loop_Dependents')?['dcfg_onboarding_checklistid']}"
                        body = @{ dcfg_email_triggered = $true }
                        authentication = $auth }
                    runAfter = @{ Notify_Email = @('Succeeded') }
                }
            }
            runAfter = @{ Find_Dependents = @('Succeeded') }
        }
    }

    $f2Data = Build-FlowClientData $httpTrigger $f2Actions
    try {
        $f2Id = New-Record -setName 'workflows' -body @{
            name = 'flow_onboarding_cascade - Step Completion Cascade'
            type = 1; category = 5; statecode = 0; statuscode = 1
            primaryentity = 'none'; scope = 4; mode = 0; languagecode = 1033
            clientdata = $f2Data
        }
        Write-Host "  Created + Active: $f2Id" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(400, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
    }

    # ══════════════════════════════════════
    # FLOW 3: Overdue — daily check for overdue steps
    # ══════════════════════════════════════
    Write-Host "`n=== FLOW 3: flow_onboarding_overdue ===" -ForegroundColor Cyan

    $f3Actions = @{
        Find_Overdue = @{
            type = 'ApiConnection'
            inputs = @{ host = $dvHost; method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items"
                queries = @{ '$filter' = "dcfg_due_date lt @{utcNow()} and dcfg_is_complete eq false and _dcfg_case_id_value ne null" }
                authentication = $auth }
            runAfter = @{}
        }
        Loop_Overdue = @{
            type = 'Foreach'
            foreach = "@body('Find_Overdue')?['value']"
            actions = @{
                Get_Case = @{
                    type = 'ApiConnection'
                    inputs = @{ host = $dvHost; method = 'get'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_cases'))}/items/@{items('Loop_Overdue')?['_dcfg_case_id_value']}"
                        authentication = $auth }
                    runAfter = @{}
                }
                Send_Nudge = @{
                    type = 'ApiConnection'
                    inputs = @{ host = $mailHost; method = 'post'; path = '/v3/mail/send'
                        body = @{
                            to = "@{items('Loop_Overdue')?['dcfg_assigned_email']};@{coalesce(items('Loop_Overdue')?['dcfg_accountable_email'],'')}"
                            subject = "[DCFG] Overdue: @{items('Loop_Overdue')?['dcfg_step_name']} - @{coalesce(body('Get_Case')?['dcfg_case_number'],'case')}"
                            text = "<h2>Overdue Step</h2><p><b>Step:</b> @{items('Loop_Overdue')?['dcfg_step_name']}</p><p><b>Due:</b> @{items('Loop_Overdue')?['dcfg_due_date']}</p><p><b>Case:</b> @{coalesce(body('Get_Case')?['dcfg_case_number'],'')}</p><p><a href='https://dcfg.powerappsportals.com/#/onboarding/@{items('Loop_Overdue')?['_dcfg_case_id_value']}'>Open Case</a></p>"
                            ishtml = $true
                        }
                        authentication = $auth }
                    runAfter = @{ Get_Case = @('Succeeded') }
                }
            }
            runAfter = @{ Find_Overdue = @('Succeeded') }
        }
    }

    $f3Trigger = @{
        manual = @{
            type = 'Request'; kind = 'Http'
            inputs = @{ schema = @{} }
        }
    }
    $f3Data = Build-FlowClientData $f3Trigger $f3Actions
    try {
        $f3Id = New-Record -setName 'workflows' -body @{
            name = 'flow_onboarding_overdue - Daily Overdue Check'
            type = 1; category = 5; statecode = 0; statuscode = 1
            primaryentity = 'none'; scope = 4; mode = 0; languagecode = 1033
            clientdata = $f3Data
        }
        Write-Host "  Created + Active: $f3Id" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(400, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
    }

    # Activate all 3
    Write-Host "`n=== ACTIVATING ===" -ForegroundColor Cyan
    foreach ($id in @($f1Id, $f2Id, $f3Id)) {
        if ($id) {
            try {
                Update-Record -setName 'workflows' -id $id -body @{ statecode = 1; statuscode = 2 }
                Write-Host "  Activated: $id" -ForegroundColor Green
            } catch {
                Write-Host "  Activate FAIL $id : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n=== DONE ===" -ForegroundColor Cyan
    Write-Host "All 3 flows use HTTP triggers for immediate testing." -ForegroundColor Yellow
    Write-Host "To test notify: POST {step_id: '<checklist_guid>'} to flow 1 trigger URL" -ForegroundColor Gray
    Write-Host "To test cascade: POST {step_id: '<completed_step_guid>'} to flow 2 trigger URL" -ForegroundColor Gray
    Write-Host "To test overdue: POST {} to flow 3 trigger URL" -ForegroundColor Gray
}
