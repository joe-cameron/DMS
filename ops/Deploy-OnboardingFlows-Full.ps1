# Deploy full onboarding notification flows — real actions, no placeholders
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

# Connection references (from flow_send_email — proven working)
$dvConnRef = 'dcfg_sharedcommondataserviceforapps_e71ee'
$mailConnRef = 'dcfg_sharedsendmail_1a963'
$orgId = 'org0c17e98d.crm.dynamics.com'

$connectionReferences = @{
    shared_commondataserviceforapps = @{
        runtimeSource = 'embedded'
        connection = @{ connectionReferenceLogicalName = $dvConnRef }
        api = @{ name = 'shared_commondataserviceforapps' }
        impersonation = @{}
    }
    shared_sendmail = @{
        runtimeSource = 'embedded'
        connection = @{ connectionReferenceLogicalName = $mailConnRef }
        api = @{ name = 'shared_sendmail' }
    }
}

$dvHost = @{ connection = @{ name = "@parameters('`$connections')['shared_commondataserviceforapps']['connectionId']" } }
$mailHost = @{ connection = @{ name = "@parameters('`$connections')['shared_sendmail']['connectionId']" } }
$auth = "@parameters('`$authentication')"

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    # ══════════════════════════════════════════════════════════════
    # FLOW 1: flow_onboarding_notify — Step Ready Notification
    # Trigger: HTTP (manual test) — will be changed to Dataverse trigger in Step 2
    # ══════════════════════════════════════════════════════════════
    Write-Host "=== FLOW 1: flow_onboarding_notify ===" -ForegroundColor Cyan
    $flow1Id = '6e06f972-df27-f111-8341-7ced8d709731'

    $flow1Actions = @{
        Get_Step = @{
            type = 'ApiConnection'
            inputs = @{
                host = $dvHost
                method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{triggerBody()?['step_id']}"
                authentication = $auth
            }
            runAfter = @{}
        }
        Get_Case = @{
            type = 'ApiConnection'
            inputs = @{
                host = $dvHost
                method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_cases'))}/items/@{body('Get_Step')?['_dcfg_case_id_value']}"
                authentication = $auth
            }
            runAfter = @{ Get_Step = @('Succeeded') }
        }
        Get_Customer = @{
            type = 'ApiConnection'
            inputs = @{
                host = $dvHost
                method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_customers'))}/items/@{body('Get_Case')?['_dcfg_customer_id_value']}"
                authentication = $auth
            }
            runAfter = @{ Get_Case = @('Succeeded') }
        }
        Check_Not_Already_Triggered = @{
            type = 'If'
            expression = @{
                equals = @(
                    "@body('Get_Step')?['dcfg_email_triggered']",
                    $false
                )
            }
            actions = @{
                Send_Ready_Email = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $mailHost
                        method = 'post'
                        path = '/v3/mail/send'
                        body = @{
                            to = "@{body('Get_Step')?['dcfg_assigned_email']}"
                            subject = "[DCFG] Your turn: @{body('Get_Step')?['dcfg_step_name']} - @{coalesce(body('Get_Customer')?['dcfg_name'], 'Customer')} onboarding"
                            text = "<h2>Step Ready: @{body('Get_Step')?['dcfg_step_name']}</h2><p><strong>Customer:</strong> @{coalesce(body('Get_Customer')?['dcfg_name'], 'N/A')}</p><p><strong>Case:</strong> @{coalesce(body('Get_Case')?['dcfg_case_number'], 'N/A')}</p><p><strong>Phase:</strong> @{body('Get_Step')?['dcfg_phase']}</p><p><strong>Accountable:</strong> @{coalesce(body('Get_Step')?['dcfg_accountable_name'], 'N/A')} (@{coalesce(body('Get_Step')?['dcfg_accountable_email'], '')})</p><p><a href='https://dcfg.powerappsportals.com/#/onboarding/@{body('Get_Case')?['dcfg_onboarding_caseid']}'>Open Case in Portal</a></p><p>Mark it complete when done - the next step will be notified automatically.</p>"
                            ishtml = $true
                        }
                        authentication = $auth
                    }
                    runAfter = @{}
                }
                Mark_Triggered = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $dvHost
                        method = 'patch'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{triggerBody()?['step_id']}"
                        body = @{ dcfg_email_triggered = $true }
                        authentication = $auth
                    }
                    runAfter = @{ Send_Ready_Email = @('Succeeded') }
                }
            }
            else = @{ actions = @{} }
            runAfter = @{ Get_Customer = @('Succeeded') }
        }
    }

    $flow1ClientData = @{
        schemaVersion = '1.0.0.0'
        properties = @{
            connectionReferences = $connectionReferences
            definition = @{
                '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                contentVersion = '1.0.0.0'
                parameters = @{ '$connections' = @{ defaultValue = @{}; type = 'Object' }; '$authentication' = @{ defaultValue = @{}; type = 'SecureObject' } }
                triggers = @{
                    manual = @{
                        type = 'Request'
                        kind = 'Http'
                        inputs = @{
                            schema = @{
                                type = 'object'
                                properties = @{
                                    step_id = @{ type = 'string' }
                                }
                            }
                        }
                    }
                }
                actions = $flow1Actions
            }
        }
    } | ConvertTo-Json -Depth 20 -Compress

    try {
        Update-Record -setName 'workflows' -id $flow1Id -body @{ clientdata = $flow1ClientData }
        Write-Host "  Updated with full definition" -ForegroundColor Green
        # Activate
        Update-Record -setName 'workflows' -id $flow1Id -body @{ statecode = 1; statuscode = 2 }
        Write-Host "  Activated" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(400, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
    }

    # ══════════════════════════════════════════════════════════════
    # FLOW 2: flow_onboarding_cascade — Step Completion Cascade
    # ══════════════════════════════════════════════════════════════
    Write-Host "`n=== FLOW 2: flow_onboarding_cascade ===" -ForegroundColor Cyan
    $flow2Id = '1c7f2574-df27-f111-8341-7ced8d709173'

    $flow2Actions = @{
        Get_Completed_Step = @{
            type = 'ApiConnection'
            inputs = @{
                host = $dvHost
                method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{triggerBody()?['step_id']}"
                authentication = $auth
            }
            runAfter = @{}
        }
        Find_Dependent_Steps = @{
            type = 'ApiConnection'
            inputs = @{
                host = $dvHost
                method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items"
                queries = @{
                    '$filter' = "_dcfg_case_id_value eq @{body('Get_Completed_Step')?['_dcfg_case_id_value']} and dcfg_predecessor_step eq @{body('Get_Completed_Step')?['dcfg_step_number']} and dcfg_is_complete eq false"
                }
                authentication = $auth
            }
            runAfter = @{ Get_Completed_Step = @('Succeeded') }
        }
        Loop_Dependents = @{
            type = 'Foreach'
            foreach = "@body('Find_Dependent_Steps')?['value']"
            actions = @{
                Mark_Step_Ready = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $dvHost
                        method = 'patch'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{items('Loop_Dependents')?['dcfg_onboarding_checklistid']}"
                        body = @{ dcfg_status = 100000001 }
                        authentication = $auth
                    }
                    runAfter = @{}
                }
                Send_Ready_Notification = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $mailHost
                        method = 'post'
                        path = '/v3/mail/send'
                        body = @{
                            to = "@{items('Loop_Dependents')?['dcfg_assigned_email']}"
                            subject = "[DCFG] Your turn: @{items('Loop_Dependents')?['dcfg_step_name']} - onboarding step ready"
                            text = "<h2>Step Ready: @{items('Loop_Dependents')?['dcfg_step_name']}</h2><p>The previous step was just completed. You can now begin your task.</p><p><strong>Assigned to:</strong> @{items('Loop_Dependents')?['dcfg_assigned_email']}</p><p><strong>Accountable:</strong> @{coalesce(items('Loop_Dependents')?['dcfg_accountable_email'], 'N/A')}</p><p><a href='https://dcfg.powerappsportals.com/#/onboarding/@{body('Get_Completed_Step')?['_dcfg_case_id_value']}'>Open Case in Portal</a></p>"
                            ishtml = $true
                        }
                        authentication = $auth
                    }
                    runAfter = @{ Mark_Step_Ready = @('Succeeded') }
                }
                Mark_Email_Triggered = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $dvHost
                        method = 'patch'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items/@{items('Loop_Dependents')?['dcfg_onboarding_checklistid']}"
                        body = @{ dcfg_email_triggered = $true }
                        authentication = $auth
                    }
                    runAfter = @{ Send_Ready_Notification = @('Succeeded') }
                }
            }
            runAfter = @{ Find_Dependent_Steps = @('Succeeded') }
        }
    }

    $flow2ClientData = @{
        schemaVersion = '1.0.0.0'
        properties = @{
            connectionReferences = $connectionReferences
            definition = @{
                '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                contentVersion = '1.0.0.0'
                parameters = @{ '$connections' = @{ defaultValue = @{}; type = 'Object' }; '$authentication' = @{ defaultValue = @{}; type = 'SecureObject' } }
                triggers = @{
                    manual = @{
                        type = 'Request'; kind = 'Http'
                        inputs = @{ schema = @{ type = 'object'; properties = @{ step_id = @{ type = 'string' } } } }
                    }
                }
                actions = $flow2Actions
            }
        }
    } | ConvertTo-Json -Depth 20 -Compress

    try {
        Update-Record -setName 'workflows' -id $flow2Id -body @{ clientdata = $flow2ClientData }
        Write-Host "  Updated with full definition" -ForegroundColor Green
        Update-Record -setName 'workflows' -id $flow2Id -body @{ statecode = 1; statuscode = 2 }
        Write-Host "  Activated" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(400, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
    }

    # ══════════════════════════════════════════════════════════════
    # FLOW 3: flow_onboarding_overdue — Daily Overdue Check
    # ══════════════════════════════════════════════════════════════
    Write-Host "`n=== FLOW 3: flow_onboarding_overdue ===" -ForegroundColor Cyan
    $flow3Id = '7a06f972-df27-f111-8341-7ced8d709731'

    $flow3Actions = @{
        Find_Overdue_Steps = @{
            type = 'ApiConnection'
            inputs = @{
                host = $dvHost
                method = 'get'
                path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_checklists'))}/items"
                queries = @{
                    '$filter' = "dcfg_due_date lt @{utcNow()} and dcfg_is_complete eq false and _dcfg_case_id_value ne null"
                }
                authentication = $auth
            }
            runAfter = @{}
        }
        Loop_Overdue = @{
            type = 'Foreach'
            foreach = "@body('Find_Overdue_Steps')?['value']"
            actions = @{
                Get_Overdue_Case = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $dvHost
                        method = 'get'
                        path = "/datasets/@{encodeURIComponent(encodeURIComponent('$orgId'))}/tables/@{encodeURIComponent(encodeURIComponent('dcfg_onboarding_cases'))}/items/@{items('Loop_Overdue')?['_dcfg_case_id_value']}"
                        authentication = $auth
                    }
                    runAfter = @{}
                }
                Send_Overdue_Nudge = @{
                    type = 'ApiConnection'
                    inputs = @{
                        host = $mailHost
                        method = 'post'
                        path = '/v3/mail/send'
                        body = @{
                            to = "@{items('Loop_Overdue')?['dcfg_assigned_email']};@{coalesce(items('Loop_Overdue')?['dcfg_accountable_email'], '')}"
                            subject = "[DCFG] Overdue: @{items('Loop_Overdue')?['dcfg_step_name']} - @{coalesce(body('Get_Overdue_Case')?['dcfg_case_number'], 'case')}"
                            text = "<h2>Overdue Step</h2><p><strong>Step:</strong> @{items('Loop_Overdue')?['dcfg_step_name']}</p><p><strong>Due:</strong> @{items('Loop_Overdue')?['dcfg_due_date']}</p><p><strong>Case:</strong> @{coalesce(body('Get_Overdue_Case')?['dcfg_case_number'], 'N/A')}</p><p><strong>Assigned:</strong> @{items('Loop_Overdue')?['dcfg_assigned_email']}</p><p><strong>Accountable:</strong> @{coalesce(items('Loop_Overdue')?['dcfg_accountable_email'], 'N/A')}</p><p><a href='https://dcfg.powerappsportals.com/#/onboarding/@{items('Loop_Overdue')?['_dcfg_case_id_value']}'>Open Case</a></p>"
                            ishtml = $true
                        }
                        authentication = $auth
                    }
                    runAfter = @{ Get_Overdue_Case = @('Succeeded') }
                }
            }
            runAfter = @{ Find_Overdue_Steps = @('Succeeded') }
        }
    }

    $flow3ClientData = @{
        schemaVersion = '1.0.0.0'
        properties = @{
            connectionReferences = $connectionReferences
            definition = @{
                '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                contentVersion = '1.0.0.0'
                parameters = @{ '$connections' = @{ defaultValue = @{}; type = 'Object' }; '$authentication' = @{ defaultValue = @{}; type = 'SecureObject' } }
                triggers = @{
                    manual = @{
                        type = 'Request'; kind = 'Http'
                        inputs = @{ schema = @{} }
                        description = 'HTTP for testing. Change to Recurrence daily 8am for production.'
                    }
                }
                actions = $flow3Actions
            }
        }
    } | ConvertTo-Json -Depth 20 -Compress

    try {
        Update-Record -setName 'workflows' -id $flow3Id -body @{ clientdata = $flow3ClientData }
        Write-Host "  Updated with full definition" -ForegroundColor Green
        Update-Record -setName 'workflows' -id $flow3Id -body @{ statecode = 1; statuscode = 2 }
        Write-Host "  Activated" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(400, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
    }

    Write-Host "`n=== DEPLOYMENT COMPLETE ===" -ForegroundColor Cyan
    Write-Host "All 3 flows use HTTP triggers for testing." -ForegroundColor Yellow
    Write-Host "To test: POST to the flow trigger URL with {`"step_id`": `"<checklist_id>`"}" -ForegroundColor Gray
    Write-Host "After validation, change triggers to Dataverse in the designer." -ForegroundColor Gray
}
