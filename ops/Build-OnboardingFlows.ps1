# Build-OnboardingFlows.ps1 — Step 1: Push placeholder definitions for 3 onboarding notification flows
# These are created as NEW flows via Dataverse workflows table
# After creation, user adds real connector actions (Step 2), then we push full definitions (Step 3)

. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    Write-Host "=== ONBOARDING NOTIFICATION FLOWS — Step 1 Placeholders ===" -ForegroundColor Cyan
    Write-Host "These flows need Step 2 (manual connector setup) before they work.`n" -ForegroundColor Yellow

    # ══════════════════════════════════════════
    # FLOW 1: flow_onboarding_notify
    # Trigger: Dataverse — when dcfg_onboarding_checklist.dcfg_status changes to Ready
    # Action: Send email to assigned person with step details + case link
    # ══════════════════════════════════════════

    $flow1Name = 'flow_onboarding_notify - Step Ready Notification'
    Write-Host "--- Flow 1: $flow1Name ---" -ForegroundColor Cyan

    # Check if exists
    $existing1 = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=name eq '$flow1Name' and category eq 5&`$select=workflowid,name,statecode" -Headers $baseHeaders).value
    if ($existing1.Count -gt 0) {
        Write-Host "  Already exists: $($existing1[0].workflowid) (state=$($existing1[0].statecode))" -ForegroundColor Yellow
    } else {
        # Create placeholder flow definition
        $flow1Def = @{
            name = $flow1Name
            type = 1; category = 5; statecode = 0; statuscode = 1
            primaryentity = 'none'; scope = 4; mode = 0; languagecode = 1033
            description = 'Sends email notification when an onboarding step becomes Ready (predecessor complete). Step 1 placeholder — needs connector setup.'
            clientdata = (@{
                schemaVersion = '1.0.0.0'
                properties = @{
                    definition = @{
                        '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                        contentVersion = '1.0.0.0'
                        triggers = @{
                            manual = @{
                                type = 'Request'
                                kind = 'Http'
                                inputs = @{ schema = @{} }
                                description = 'PLACEHOLDER — Change to: Dataverse When a row is modified on dcfg_onboarding_checklists, filter: dcfg_status eq 100000001 (Ready)'
                            }
                        }
                        actions = @{
                            STEP1_Get_Checklist_Step = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Replace with: Dataverse Get a row from dcfg_onboarding_checklists using triggerBody()?[''dcfg_onboarding_checklistid'']'
                                runAfter = @{}
                            }
                            STEP2_Get_Case = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Replace with: Dataverse Get a row from dcfg_onboarding_cases using step._dcfg_case_id_value'
                                runAfter = @{ STEP1_Get_Checklist_Step = @('Succeeded') }
                            }
                            STEP3_Get_Customer = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Replace with: Dataverse Get a row from dcfg_customers using case._dcfg_customer_id_value'
                                runAfter = @{ STEP2_Get_Case = @('Succeeded') }
                            }
                            STEP4_Check_Already_Triggered = @{
                                type = 'If'
                                expression = @{
                                    and = @(
                                        @{ equals = @('PLACEHOLDER_email_triggered', $false) }
                                    )
                                }
                                actions = @{
                                    STEP5_Send_Email = @{
                                        type = 'Compose'
                                        inputs = 'PLACEHOLDER — Replace with: Office 365 Outlook Send an email (V2). To: step.dcfg_assigned_email. Subject: [DCFG] Your turn: step.dcfg_step_name - customer.dcfg_name onboarding. Body: Step details + portal link.'
                                        runAfter = @{}
                                    }
                                    STEP6_Mark_Triggered = @{
                                        type = 'Compose'
                                        inputs = 'PLACEHOLDER — Replace with: Dataverse Update a row on dcfg_onboarding_checklists, set dcfg_email_triggered=true'
                                        runAfter = @{ STEP5_Send_Email = @('Succeeded') }
                                    }
                                }
                                else = @{ actions = @{} }
                                runAfter = @{ STEP3_Get_Customer = @('Succeeded') }
                            }
                        }
                    }
                    connectionReferences = @{}
                }
            } | ConvertTo-Json -Depth 15 -Compress)
        }

        try {
            $flow1Id = New-Record -setName 'workflows' -body $flow1Def
            Write-Host "  Created: $flow1Id" -ForegroundColor Green
        } catch {
            Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
            if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(300, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
        }
    }

    # ══════════════════════════════════════════
    # FLOW 2: flow_onboarding_cascade
    # Trigger: Dataverse — when dcfg_onboarding_checklist.dcfg_is_complete changes to true
    # Action: Find dependent steps (predecessor = this step number), set their status to Ready
    # ══════════════════════════════════════════

    $flow2Name = 'flow_onboarding_cascade - Step Completion Cascade'
    Write-Host "`n--- Flow 2: $flow2Name ---" -ForegroundColor Cyan

    $existing2 = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=name eq '$flow2Name' and category eq 5&`$select=workflowid,name,statecode" -Headers $baseHeaders).value
    if ($existing2.Count -gt 0) {
        Write-Host "  Already exists: $($existing2[0].workflowid)" -ForegroundColor Yellow
    } else {
        $flow2Def = @{
            name = $flow2Name
            type = 1; category = 5; statecode = 0; statuscode = 1
            primaryentity = 'none'; scope = 4; mode = 0; languagecode = 1033
            description = 'When a step is marked complete, finds dependent steps and marks them Ready. Triggers notification flow. Step 1 placeholder.'
            clientdata = (@{
                schemaVersion = '1.0.0.0'
                properties = @{
                    definition = @{
                        '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                        contentVersion = '1.0.0.0'
                        triggers = @{
                            manual = @{
                                type = 'Request'; kind = 'Http'
                                inputs = @{ schema = @{} }
                                description = 'PLACEHOLDER — Change to: Dataverse When a row is modified on dcfg_onboarding_checklists, filter: dcfg_is_complete eq true'
                            }
                        }
                        actions = @{
                            STEP1_Get_Completed_Step = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Dataverse Get row: completed step details (step_number, case_id)'
                                runAfter = @{}
                            }
                            STEP2_Find_Dependent_Steps = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Dataverse List rows: dcfg_onboarding_checklists where dcfg_predecessor_step eq completedStep.dcfg_step_number AND _dcfg_case_id_value eq same case AND dcfg_is_complete eq false'
                                runAfter = @{ STEP1_Get_Completed_Step = @('Succeeded') }
                            }
                            STEP3_Loop_Dependents = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Apply to each dependent step: Update row set dcfg_status=100000001 (Ready). The notify flow will pick up the status change.'
                                runAfter = @{ STEP2_Find_Dependent_Steps = @('Succeeded') }
                            }
                            STEP4_Update_Case_Progress = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Dataverse List rows: count completed vs total steps for this case. Update dcfg_onboarding_cases progress/status.'
                                runAfter = @{ STEP3_Loop_Dependents = @('Succeeded') }
                            }
                        }
                    }
                    connectionReferences = @{}
                }
            } | ConvertTo-Json -Depth 15 -Compress)
        }

        try {
            $flow2Id = New-Record -setName 'workflows' -body $flow2Def
            Write-Host "  Created: $flow2Id" -ForegroundColor Green
        } catch {
            Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
            if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(300, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
        }
    }

    # ══════════════════════════════════════════
    # FLOW 3: flow_onboarding_overdue
    # Trigger: Scheduled daily at 8am
    # Action: Find overdue steps, send nudge email to assigned + escalation to accountable
    # ══════════════════════════════════════════

    $flow3Name = 'flow_onboarding_overdue - Daily Overdue Check'
    Write-Host "`n--- Flow 3: $flow3Name ---" -ForegroundColor Cyan

    $existing3 = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=name eq '$flow3Name' and category eq 5&`$select=workflowid,name,statecode" -Headers $baseHeaders).value
    if ($existing3.Count -gt 0) {
        Write-Host "  Already exists: $($existing3[0].workflowid)" -ForegroundColor Yellow
    } else {
        $flow3Def = @{
            name = $flow3Name
            type = 1; category = 5; statecode = 0; statuscode = 1
            primaryentity = 'none'; scope = 4; mode = 0; languagecode = 1033
            description = 'Daily 8am check for overdue onboarding steps. Sends nudge to assigned person + escalation to accountable. Step 1 placeholder.'
            clientdata = (@{
                schemaVersion = '1.0.0.0'
                properties = @{
                    definition = @{
                        '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                        contentVersion = '1.0.0.0'
                        triggers = @{
                            manual = @{
                                type = 'Request'; kind = 'Http'
                                inputs = @{ schema = @{} }
                                description = 'PLACEHOLDER — Change to: Recurrence, daily at 8:00 AM Eastern'
                            }
                        }
                        actions = @{
                            STEP1_Find_Overdue = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Dataverse List rows: dcfg_onboarding_checklists where dcfg_due_date lt utcNow() AND dcfg_is_complete eq false AND _dcfg_case_id_value ne null'
                                runAfter = @{}
                            }
                            STEP2_Loop_Overdue = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Apply to each overdue step: Get case + customer details. Send nudge email to dcfg_assigned_email. Send escalation to dcfg_accountable_email if different. One email per overdue step, not a batch.'
                                runAfter = @{ STEP1_Find_Overdue = @('Succeeded') }
                            }
                            STEP3_Log_Summary = @{
                                type = 'Compose'
                                inputs = 'PLACEHOLDER — Dataverse Add row to dcfg_brain_insights: summary of overdue count, which cases, which steps.'
                                runAfter = @{ STEP2_Loop_Overdue = @('Succeeded') }
                            }
                        }
                    }
                    connectionReferences = @{}
                }
            } | ConvertTo-Json -Depth 15 -Compress)
        }

        try {
            $flow3Id = New-Record -setName 'workflows' -body $flow3Def
            Write-Host "  Created: $flow3Id" -ForegroundColor Green
        } catch {
            Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
            if ($_.ErrorDetails.Message) { Write-Host "  $($_.ErrorDetails.Message.Substring(0, [Math]::Min(300, $_.ErrorDetails.Message.Length)))" -ForegroundColor Red }
        }
    }

    Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "Step 2 (Joseph — manual in Power Automate designer):" -ForegroundColor Yellow
    Write-Host "  For EACH of the 3 flows:" -ForegroundColor Gray
    Write-Host "    1. Open in Power Automate designer" -ForegroundColor Gray
    Write-Host "    2. Change trigger (see placeholder description)" -ForegroundColor Gray
    Write-Host "    3. Add one Dataverse Get/Update/List/Add row action" -ForegroundColor Gray
    Write-Host "    4. Add one Office 365 Outlook Send email action" -ForegroundColor Gray
    Write-Host "    5. Save the flow" -ForegroundColor Gray
    Write-Host "    6. Tell me — I will push the full definitions (Step 3)" -ForegroundColor Gray
}
