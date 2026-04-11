# =============================================================================
# Nora Monitor — One monitoring cycle
# Reads audit logs, document requests, flow health
# Investigates stuck requests, auto-fixes verified completions
# Writes findings to dcfg_brain_insights
# =============================================================================

. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

Connect 'https://org88778bb0.crm.dynamics.com/'

$OrgUrl = 'https://org88778bb0.crm.dynamics.com/api/data/v9.2'
$outDriveId = 'b!lGCVWRjYlkiGjk72z8d6szyNF3B4WKtIo0BTKeaWw-myKC0DWmjSS5ea0TsRqstT'

# Known active flows baseline
$knownActiveFlows = @(
    'DCFG DocGen v2', 'DCFG - Compute Metrics', 'DCFG - SharePoint Write Cache',
    'DCFG - HTTP Bridge Query Active Portfolio', 'flow_cert_upload',
    'flow_onboarding_init', 'flow_send_email', 'DCFG - Error Reporter',
    'flow_cert_alert', 'flow_commit - Budget Commit on Signed/Received',
    'flow_template_validate - Template Upload Validation', 'flow_sensor_ingest'
)

function Write-Insight {
    param(
        [string]$Title, [string]$Detail, [string]$Domain = 'System',
        [string]$Priority = 'Info', [string]$InsightType = 'Anomaly',
        [string]$SourceEntity = '', [string]$SourceRecordId = '',
        [bool]$IsActionable = $false, [string]$CreatedBy = 'nora-monitor'
    )
    $priorityMap = @{ 'Info' = 100000000; 'Warning' = 100000001; 'Urgent' = 100000002 }
    $typeMap = @{ 'Anomaly' = 100000000; 'Pattern' = 100000001; 'TestResult' = 100000002; 'Recommendation' = 100000003; 'Incident' = 100000004; 'TrainingGap' = 100000005 }
    $domainMap = @{ 'System' = 100000000; 'DocGen' = 100000001; 'Onboarding' = 100000002; 'Compliance' = 100000003; 'UX' = 100000004; 'Training' = 100000005 }

    $body = @{
        dcfg_title = $Title
        dcfg_detail = "$Detail | domain=$Domain | priority=$Priority | type=$InsightType"
        dcfg_source_entity = $SourceEntity
        dcfg_source_record_id = $SourceRecordId
        dcfg_is_actionable = $IsActionable
        dcfg_created_by_flow = $CreatedBy
    } | ConvertTo-Json -Compress

    try {
        $postHeaders = @{ 'Authorization'=$script:hW['Authorization']; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; 'Accept'='application/json'; 'Content-Type'='application/json; charset=utf-8' }
        Invoke-RestMethod -Uri "$OrgUrl/dcfg_brain_insights" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -Headers $postHeaders | Out-Null
        return $true
    } catch {
        Write-Host "    [Nora] Failed to write insight: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Investigate-StuckRequest {
    param([PSObject]$Request)

    $reqId = $Request.dcfg_document_requestid
    $reqName = $Request.dcfg_name
    $retryCount = if ($Request.dcfg_nora_retry_count) { $Request.dcfg_nora_retry_count } else { 0 }

    Write-Host "    [Nora] Investigating: $reqName (retries: $retryCount)" -ForegroundColor Yellow

    # Hard ceiling check
    if ($retryCount -ge 3) {
        Write-Host "    [Nora] Retry ceiling reached. Marking Failed + Escalating." -ForegroundColor Red
        $patchBody = @{ dcfg_status = 100000003; dcfg_error_message = "Nora: Exceeded retry limit (3). Escalated to operator."; dcfg_nora_message = "I was not able to finish this one after several tries. Joseph has been notified." } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($reqId)" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $script:hW | Out-Null
        Write-Insight -Title "Stuck request escalated: $reqName" -Detail "Request $reqId exceeded 3 retry attempts. Last status: Processing. Nora marked as Failed and escalated." -Domain 'DocGen' -Priority 'Urgent' -InsightType 'Incident' -SourceEntity 'dcfg_document_request' -SourceRecordId $reqId -IsActionable $true
        return
    }

    # Check if document output exists
    $sourceId = if ($Request._dcfg_contract_id_value) { $Request._dcfg_contract_id_value } else { $Request._dcfg_msa_id_value }
    $outputs = @()
    if ($sourceId) {
        $outputs = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_outputs?`$filter=dcfg_source_record_id eq '$sourceId'&`$orderby=createdon desc&`$top=1&`$select=dcfg_document_outputid,dcfg_output_file_url,dcfg_name" -Headers $script:hR).value
    }

    if ($outputs -and $outputs.Count -gt 0 -and $outputs[0].dcfg_output_file_url) {
        # Output exists — check SharePoint
        $fileUrl = $outputs[0].dcfg_output_file_url
        $fileName = $outputs[0].dcfg_name

        # Verify file in SharePoint
        $spExists = $false
        try {
            $graphToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -AsSecureString)
            $gpt = [System.Net.NetworkCredential]::new('', $graphToken.Token).Password
            $spItems = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$outDriveId/root/children" -Headers @{'Authorization'="Bearer $gpt";'Accept'='application/json'}).value
            $spFile = $spItems | Where-Object { $_.name -eq "$fileName.docx" }
            if ($spFile -and $spFile.size -gt 10000) { $spExists = $true }
        } catch {}

        if ($spExists) {
            # AUTO-FIX: Work completed, status just didn't update
            Write-Host "    [Nora] Work verified complete. Auto-fixing status." -ForegroundColor Green
            $patchBody = @{
                dcfg_status = 100000002  # Complete
                dcfg_output_file_url = $fileUrl
                dcfg_completed_at = (Get-Date).ToUniversalTime().ToString('o')
                dcfg_nora_message = "That took an extra try, but your document is ready now."
            } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($reqId)" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $script:hW | Out-Null
            Write-Insight -Title "Auto-fixed: $reqName" -Detail "Request was stuck at Processing but output was found in both Dataverse and SharePoint. Nora updated status to Complete." -Domain 'DocGen' -Priority 'Info' -InsightType 'Incident' -SourceEntity 'dcfg_document_request' -SourceRecordId $reqId
            return
        } else {
            Write-Host "    [Nora] Output record exists but file not in SharePoint. Logging." -ForegroundColor Yellow
            Write-Insight -Title "Partial completion: $reqName" -Detail "Document output record exists but file not found in SharePoint DCFG_Outputs library." -Domain 'DocGen' -Priority 'Warning' -InsightType 'Incident' -SourceEntity 'dcfg_document_request' -SourceRecordId $reqId -IsActionable $true
        }
    } else {
        # No output at all — increment retry count
        Write-Host "    [Nora] No output found. Incrementing retry count to $($retryCount + 1)." -ForegroundColor Yellow
        $patchBody = @{
            dcfg_nora_retry_count = $retryCount + 1
            dcfg_nora_message = "Your document is taking a bit longer than usual. I am keeping an eye on it."
        } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests($reqId)" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $script:hW | Out-Null
        Write-Insight -Title "Stuck request: $reqName (retry $($retryCount + 1))" -Detail "No document output found. Retry count incremented. Will check again next cycle." -Domain 'DocGen' -Priority 'Warning' -InsightType 'Incident' -SourceEntity 'dcfg_document_request' -SourceRecordId $reqId -IsActionable $true
    }
}

Invoke-DataverseCommands {
    $token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl 'https://org88778bb0.crm.dynamics.com/' -AsSecureString).Token).Password
    $script:hR = @{ 'Authorization'="Bearer $token"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; 'Accept'='application/json' }
    $script:hW = @{ 'Authorization'="Bearer $token"; 'OData-MaxVersion'='4.0'; 'OData-Version'='4.0'; 'Accept'='application/json'; 'Content-Type'='application/json; charset=utf-8'; 'If-Match'='*' }

    $cycleStart = Get-Date
    Write-Host "`n===== NORA MONITOR CYCLE: $(Get-Date -Format 'HH:mm:ss') =====" -ForegroundColor Cyan

    # =========================================================================
    # 1. READ CHECKPOINT
    # =========================================================================
    $configRec = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_configs?`$filter=dcfg_key eq 'nora_last_check'&`$select=dcfg_configid,dcfg_value" -Headers $script:hR).value
    $lastCheck = if ($configRec -and $configRec.Count -gt 0) { $configRec[0].dcfg_value } else { (Get-Date).AddHours(-1).ToUniversalTime().ToString('o') }
    $lastCheckId = if ($configRec -and $configRec.Count -gt 0) { $configRec[0].dcfg_configid } else { $null }
    Write-Host "  Last check: $lastCheck"

    # =========================================================================
    # 2. AUDIT LOG SCAN
    # =========================================================================
    Write-Host "`n  [1] Audit Log Scan" -ForegroundColor Yellow
    $lastCheckFormatted = [DateTime]::Parse($lastCheck).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $newAudits = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_audit_logs?`$filter=createdon gt $lastCheckFormatted&`$select=dcfg_action_type,dcfg_new_value,dcfg_performed_by&`$orderby=createdon desc" -Headers $script:hR).value
    $auditCount = if ($newAudits) { $newAudits.Count } else { 0 }
    Write-Host "    New audit entries: $auditCount"

    if ($auditCount -gt 0) {
        $grouped = $newAudits | Group-Object dcfg_action_type
        $grouped | ForEach-Object {
            $label = switch ($_.Name) { '100000000' {'Generated'} '100000001' {'Sent'} '100000006' {'StatusChanged'} '100000009' {'DataUpdated'} '100000010' {'Other'} default {$_.Name} }
            Write-Host "      $label : $($_.Count)"
        }

        # Check for error patterns
        $errors = $newAudits | Where-Object { $_.dcfg_new_value -match 'error|failed|ERROR|FAIL' }
        if ($errors -and $errors.Count -gt 0) {
            Write-Host "    Errors detected: $($errors.Count)" -ForegroundColor Red
            Write-Insight -Title "Error spike: $($errors.Count) errors since last check" -Detail ($errors | ForEach-Object { $_.dcfg_new_value } | Select-Object -First 5 | Out-String) -Domain 'System' -Priority 'Warning' -InsightType 'Anomaly'
        }
    }

    # =========================================================================
    # 3. DOCUMENT REQUEST HEALTH
    # =========================================================================
    Write-Host "`n  [2] Document Request Health" -ForegroundColor Yellow
    $stuckRequests = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000001&`$select=dcfg_document_requestid,dcfg_name,dcfg_nora_retry_count,modifiedon,_dcfg_contract_id_value,_dcfg_msa_id_value" -Headers $script:hR).value

    if ($stuckRequests -and $stuckRequests.Count -gt 0) {
        Write-Host "    Stuck at Processing: $($stuckRequests.Count)" -ForegroundColor Red

        foreach ($req in $stuckRequests) {
            # Only investigate if stuck for > 10 minutes
            $modifiedAge = (Get-Date) - [DateTime]::Parse($req.modifiedon)
            if ($modifiedAge.TotalMinutes -gt 10) {
                Investigate-StuckRequest -Request $req
            } else {
                Write-Host "    $($req.dcfg_name) — still fresh ($([int]$modifiedAge.TotalMinutes) min), waiting" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "    All clear — no stuck requests" -ForegroundColor Green
    }

    # Check for pending too long (> 30 min)
    $pendingTooLong = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000000&`$select=dcfg_document_requestid,dcfg_name,modifiedon" -Headers $script:hR).value
    if ($pendingTooLong) {
        foreach ($p in $pendingTooLong) {
            $age = (Get-Date) - [DateTime]::Parse($p.modifiedon)
            if ($age.TotalMinutes -gt 30) {
                Write-Host "    $($p.dcfg_name) — pending for $([int]$age.TotalMinutes) min (flow may not have triggered)" -ForegroundColor Red
                Write-Insight -Title "Pending too long: $($p.dcfg_name)" -Detail "Document request has been Pending for $([int]$age.TotalMinutes) minutes. The flow trigger may not have fired." -Domain 'DocGen' -Priority 'Warning' -InsightType 'Anomaly' -SourceEntity 'dcfg_document_request' -SourceRecordId $p.dcfg_document_requestid -IsActionable $true
            }
        }
    }

    # =========================================================================
    # 4. FLOW HEALTH
    # =========================================================================
    Write-Host "`n  [3] Flow Health" -ForegroundColor Yellow
    $activeFlows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5 and statecode eq 1&`$select=name" -Headers $script:hR).value
    $activeNames = $activeFlows | ForEach-Object { $_.name }

    $missingFlows = $knownActiveFlows | Where-Object { $_ -notin $activeNames }
    if ($missingFlows -and $missingFlows.Count -gt 0) {
        Write-Host "    FLOWS WENT INACTIVE:" -ForegroundColor Red
        $missingFlows | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
        Write-Insight -Title "Flows went inactive" -Detail "Expected active flows that are now inactive: $($missingFlows -join ', ')" -Domain 'System' -Priority 'Urgent' -InsightType 'Anomaly' -IsActionable $true
    } else {
        Write-Host "    All $($activeFlows.Count) expected flows active" -ForegroundColor Green
    }

    # =========================================================================
    # 5. UPDATE CHECKPOINT
    # =========================================================================
    $now = (Get-Date).ToUniversalTime().ToString('o')
    if ($lastCheckId) {
        $patchBody = @{ dcfg_value = $now } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$OrgUrl/dcfg_configs($lastCheckId)" -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody)) -Headers $script:hW | Out-Null
    }

    $elapsed = ((Get-Date) - $cycleStart).TotalSeconds
    Write-Host "`n  Cycle complete in $([math]::Round($elapsed, 1))s" -ForegroundColor Cyan
    Write-Host "  Checkpoint: $now" -ForegroundColor Gray
    Write-Host "===== NORA: All systems monitored =====" -ForegroundColor Cyan
}
