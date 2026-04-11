# Nora Monitor — PROD READ-ONLY cycle
# No writes, no patches — observation only

. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

Connect "https://org06f5de0b.crm.dynamics.com/"

Invoke-DataverseCommands {
    $token = [System.Net.NetworkCredential]::new("", (Get-AzAccessToken -ResourceUrl "https://org06f5de0b.crm.dynamics.com/" -AsSecureString).Token).Password
    $hR = @{ "Authorization"="Bearer $token"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0"; "Accept"="application/json" }
    $OrgUrl = "https://org06f5de0b.crm.dynamics.com/api/data/v9.2"

    $cycleStart = Get-Date
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host ""
    Write-Host "===== NORA MONITOR (PROD READ-ONLY): $ts =====" -ForegroundColor Cyan
    Write-Host "  Target: org06f5de0b.crm.dynamics.com (DCFGSystems-Prod)" -ForegroundColor Gray

    # --- 1. AUDIT LOG SCAN ---
    Write-Host ""
    Write-Host "  [1] Audit Log Scan" -ForegroundColor Yellow
    $since = (Get-Date).AddHours(-24).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    try {
        $audits = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_audit_logs?`$filter=createdon gt $since&`$select=dcfg_action_type,dcfg_new_value,dcfg_performed_by,createdon&`$orderby=createdon desc" -Headers $hR).value
        $auditCount = if ($audits) { $audits.Count } else { 0 }
        Write-Host "    Audit entries (last 24h): $auditCount"
        if ($auditCount -gt 0) {
            $grouped = $audits | Group-Object dcfg_action_type
            foreach ($g in $grouped) {
                $label = switch ($g.Name) { "100000000" {"Generated"} "100000001" {"Sent"} "100000006" {"StatusChanged"} "100000009" {"DataUpdated"} "100000010" {"Other"} default {$g.Name} }
                Write-Host "      $label : $($g.Count)"
            }
            $errors = $audits | Where-Object { $_.dcfg_new_value -match "error|failed|ERROR|FAIL" }
            if ($errors -and $errors.Count -gt 0) {
                Write-Host "    ERRORS DETECTED: $($errors.Count)" -ForegroundColor Red
                $errors | Select-Object -First 5 | ForEach-Object { Write-Host "      $($_.dcfg_new_value)" -ForegroundColor Red }
            } else {
                Write-Host "    No error patterns detected" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "    Could not read audit logs: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- 2. DOCUMENT REQUEST HEALTH ---
    Write-Host ""
    Write-Host "  [2] Document Request Health" -ForegroundColor Yellow
    try {
        $stuck = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000001&`$select=dcfg_document_requestid,dcfg_name,dcfg_nora_retry_count,modifiedon&`$orderby=modifiedon desc" -Headers $hR).value
        if ($stuck -and $stuck.Count -gt 0) {
            Write-Host "    Stuck at Processing: $($stuck.Count)" -ForegroundColor Red
            foreach ($r in $stuck) {
                $age = (Get-Date) - [DateTime]::Parse($r.modifiedon)
                Write-Host "      $($r.dcfg_name) - $([int]$age.TotalMinutes) min (retries: $($r.dcfg_nora_retry_count))" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    All clear - no stuck requests" -ForegroundColor Green
        }

        $pending = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=dcfg_status eq 100000000&`$select=dcfg_document_requestid,dcfg_name,modifiedon&`$orderby=modifiedon desc" -Headers $hR).value
        if ($pending -and $pending.Count -gt 0) {
            foreach ($p in $pending) {
                $age = (Get-Date) - [DateTime]::Parse($p.modifiedon)
                if ($age.TotalMinutes -gt 30) {
                    Write-Host "    PENDING > 30 min: $($p.dcfg_name) - $([int]$age.TotalMinutes) min" -ForegroundColor Red
                }
            }
        }

        $recent = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_document_requests?`$filter=modifiedon gt $since&`$select=dcfg_name,dcfg_status,modifiedon&`$orderby=modifiedon desc&`$top=10" -Headers $hR).value
        if ($recent -and $recent.Count -gt 0) {
            Write-Host "    Last 24h requests:"
            $statusGroups = $recent | Group-Object dcfg_status
            foreach ($sg in $statusGroups) {
                $label = switch ($sg.Name) { "100000000" {"Pending"} "100000001" {"Processing"} "100000002" {"Complete"} "100000003" {"Failed"} default {$sg.Name} }
                Write-Host "      $label : $($sg.Count)"
            }
        } else {
            Write-Host "    No requests in last 24h"
        }
    } catch {
        Write-Host "    Could not read document requests: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- 3. FLOW HEALTH ---
    Write-Host ""
    Write-Host "  [3] Flow Health" -ForegroundColor Yellow
    $knownActiveFlows = @(
        "DCFG DocGen v2", "DCFG - Compute Metrics", "DCFG - SharePoint Write Cache",
        "DCFG - HTTP Bridge Query Active Portfolio", "flow_cert_upload",
        "flow_onboarding_init", "flow_send_email", "DCFG - Error Reporter",
        "flow_cert_alert", "flow_commit - Budget Commit on Signed/Received",
        "flow_template_validate - Template Upload Validation", "flow_sensor_ingest"
    )
    try {
        $activeFlows = (Invoke-RestMethod -Uri "$OrgUrl/workflows?`$filter=category eq 5 and statecode eq 1&`$select=name" -Headers $hR).value
        $activeNames = @()
        if ($activeFlows) { $activeNames = $activeFlows | ForEach-Object { $_.name } }
        $missing = $knownActiveFlows | Where-Object { $_ -notin $activeNames }
        if ($missing -and $missing.Count -gt 0) {
            Write-Host "    FLOWS NOT ACTIVE:" -ForegroundColor Red
            foreach ($m in $missing) { Write-Host "      $m" -ForegroundColor Red }
        }
        $present = $knownActiveFlows | Where-Object { $_ -in $activeNames }
        Write-Host "    Expected flows active: $($present.Count)/$($knownActiveFlows.Count)"
        Write-Host "    Total active cloud flows: $(if ($activeFlows) { $activeFlows.Count } else { 0 })"
    } catch {
        Write-Host "    Could not read flows: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- 4. PORTAL HEALTH ---
    Write-Host ""
    Write-Host "  [4] Portal Site Health" -ForegroundColor Yellow
    try {
        $resp = Invoke-WebRequest -Uri "https://dmms1.powerappsportals.com/" -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 5
        Write-Host "    dmms1.powerappsportals.com: HTTP $($resp.StatusCode) ($($resp.Content.Length) bytes)" -ForegroundColor Green
    } catch {
        Write-Host "    dmms1.powerappsportals.com UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
    }

    try {
        $resp2 = Invoke-WebRequest -Uri "https://org06f5de0b.crm.dynamics.com/api/data/v9.2/" -UseBasicParsing -TimeoutSec 15 -Headers $hR
        Write-Host "    org06f5de0b.crm.dynamics.com API: HTTP $($resp2.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "    org06f5de0b.crm.dynamics.com API UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- 5. CONFIG HEALTH ---
    Write-Host ""
    Write-Host "  [5] Config Health" -ForegroundColor Yellow
    try {
        $configs = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_configs?`$select=dcfg_key,dcfg_value" -Headers $hR).value
        Write-Host "    Config entries: $(if ($configs) { $configs.Count } else { 0 })"
    } catch {
        Write-Host "    Could not read configs: $($_.Exception.Message)" -ForegroundColor Red
    }

    $elapsed = ((Get-Date) - $cycleStart).TotalSeconds
    Write-Host ""
    Write-Host "  Cycle complete in $([math]::Round($elapsed, 1))s" -ForegroundColor Cyan
    Write-Host "===== NORA: Prod monitoring complete (READ-ONLY) =====" -ForegroundColor Cyan
}
