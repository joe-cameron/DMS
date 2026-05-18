# =============================================================================
# Nora Monitor - PROD
# =============================================================================
# Modes:
#   normal  — quiet unless something needs attention (default)
#   debug   — verbose, shows all data for troubleshooting
#
# Usage:
#   pwsh -File C:\DCFG\nora\nora-monitor-prod.ps1                # normal
#   pwsh -File C:\DCFG\nora\nora-monitor-prod.ps1 -Mode debug    # debug
#
# Auth: MSAL .NET via pac CLI tools. First run: auth-init-prod.ps1
#
# Capabilities:
#   - User experience tracking (document gen success/failure rates)
#   - Send queue activity logging
#   - Composer health (MSA + Contract success/failure rates from audit logs)
#   - Azure Function health ping
#   - SharePoint connectivity check
#   - Portal health, config health, flow health
# =============================================================================

param(
    [ValidateSet('normal','debug')]
    [string]$Mode = 'normal'
)

$ErrorActionPreference = 'Stop'
$isDebug = $Mode -eq 'debug'

function Write-Debug-Line { param([string]$msg, [string]$color = 'Gray')
    if ($isDebug) { Write-Host "    [dbg] $msg" -ForegroundColor $color }
}

# --- Load MSAL assemblies from pac CLI tools ---
$pacTools = 'C:\Users\JosephCameron\AppData\Roaming\Code\User\globalStorage\microsoft-isvexptools.powerplatform-vscode\pac\tools'
Add-Type -Path "$pacTools\Microsoft.Identity.Client.dll"
Add-Type -Path "$pacTools\Microsoft.Identity.Client.Extensions.Msal.dll"

# --- Auth config ---
$TenantId = '71ccf1ec-8b0a-4419-9a45-a617aa1a66d6'
$ClientId = '51f81489-12ee-4a9e-aaae-a2591f45987d'
$OrgUri   = 'https://org06f5de0b.crm.dynamics.com/'
$Scope    = $OrgUri + '.default'
$baseURI  = $OrgUri + 'api/data/v9.2/'

$cacheDir  = 'C:\DCFG\nora'
$cacheFile = '.msal_cache.bin'

# --- Build MSAL public client + attach persistent cache ---
$app = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId).
    WithAuthority("https://login.microsoftonline.com/$TenantId").
    WithRedirectUri('http://localhost').
    Build()

try {
    $storageProps = [Microsoft.Identity.Client.Extensions.Msal.StorageCreationPropertiesBuilder]::new($cacheFile, $cacheDir).Build()
    $helper = [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync($storageProps).GetAwaiter().GetResult()
    $helper.RegisterCache($app.UserTokenCache)
} catch {
    Write-Host "  [auth] Persistent cache unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Acquire token ---
$scopes = [string[]]@($Scope)
$result = $null
try {
    $accounts = $app.GetAccountsAsync().GetAwaiter().GetResult()
    if ($accounts -and $accounts.Count -gt 0) {
        $result = $app.AcquireTokenSilent($scopes, $accounts[0]).ExecuteAsync().GetAwaiter().GetResult()
    }
} catch {
    Write-Debug-Line "Silent acquisition failed: $($_.Exception.Message)" 'Yellow'
}

if (-not $result -or -not $result.AccessToken) {
    Write-Host "`n  NORA PROD - TOKEN EXPIRED. Run: pwsh -File C:\DCFG\nora\auth-init-prod.ps1`n" -ForegroundColor Red
    exit 1
}

$baseHeaders = @{
    'Authorization'    = 'Bearer ' + $result.AccessToken
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    'Accept'           = 'application/json'
}
$writeHeaders = @{
    'Authorization'    = 'Bearer ' + $result.AccessToken
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    'Accept'           = 'application/json'
    'Content-Type'     = 'application/json'
    'Prefer'           = 'return=representation'
}

# --- Helper: PATCH a Dataverse record ---
function Invoke-DvPatch { param([string]$entity, [string]$id, [hashtable]$body)
    $uri = "$baseURI${entity}(${id})"
    $json = $body | ConvertTo-Json -Depth 5 -Compress
    Write-Debug-Line "PATCH $uri : $json"
    Invoke-RestMethod -Uri $uri -Method Patch -Headers $writeHeaders -Body $json | Out-Null
}

# --- Helper: Write a brain insight ---
function Write-Insight { param([string]$title, [string]$detail, [string]$domain, [int]$priority = 100000001)
    $body = @{
        dcfg_title         = $title
        dcfg_detail        = $detail
        dcfg_domain        = $domain
        dcfg_priority      = $priority
        dcfg_insight_type  = 100000001  # Automated
        dcfg_insight_status = 100000000  # Active
        dcfg_is_actionable = $true
        dcfg_source_entity = 'nora_monitor_prod'
    } | ConvertTo-Json -Depth 3 -Compress
    try {
        Invoke-RestMethod -Uri "${baseURI}dcfg_brain_insights" -Method Post -Headers $writeHeaders -Body $body | Out-Null
        Write-Debug-Line "Insight written: $title"
    } catch {
        Write-Debug-Line "Insight write failed: $($_.Exception.Message)" 'Red'
    }
}

# =============================================================================
# MONITORING CYCLE
# =============================================================================
$ErrorActionPreference = 'Continue'
$cycleStart = Get-Date
$ts = Get-Date -Format 'HH:mm:ss'
$since = (Get-Date).AddHours(-3).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$issueCount = 0
$resolvedCount = 0

Write-Host ''
Write-Host "===== NORA PROD [$Mode]: $ts =====" -ForegroundColor Cyan
Write-Debug-Line "Target: org06f5de0b.crm.dynamics.com"
Write-Debug-Line "Token expires: $($result.ExpiresOn.LocalDateTime)"

# =============================================================================
# [1] USER EXPERIENCE — Document Generation Success/Failure
# =============================================================================
Write-Host ''
Write-Host '  [1] User Experience — Document Generation' -ForegroundColor Yellow
try {
    $audits = (Invoke-RestMethod -Uri "$baseURI/dcfg_audit_logs?`$filter=createdon gt $since&`$select=dcfg_action_type,dcfg_new_value,dcfg_performed_by,dcfg_target_table,createdon&`$orderby=createdon desc" -Headers $baseHeaders).value
    $auditCount = if ($audits) { $audits.Count } else { 0 }

    # Document generation events
    $generated = @($audits | Where-Object { $_.dcfg_action_type -eq 100000000 })
    $sent = @($audits | Where-Object { $_.dcfg_action_type -eq 100000001 })
    $statusChanged = @($audits | Where-Object { $_.dcfg_action_type -eq 100000006 })
    $errors = @($audits | Where-Object { $_.dcfg_new_value -match 'error|failed|ERROR|FAIL' })

    # Success/failure summary
    $genSuccess = @($generated | Where-Object { $_.dcfg_new_value -notmatch 'error|failed|FAIL' }).Count
    $genFail = @($generated | Where-Object { $_.dcfg_new_value -match 'error|failed|FAIL' }).Count

    if ($isDebug -or $auditCount -gt 0) {
        Write-Host "    Documents generated: $($generated.Count) (success: $genSuccess, failed: $genFail)"
        Write-Host "    Documents sent:      $($sent.Count)"
        Write-Host "    Status changes:      $($statusChanged.Count)"
        Write-Host "    Total audit events:  $auditCount"
    }

    if ($genFail -gt 0) {
        $issueCount++
        Write-Host "    GENERATION FAILURES: $genFail" -ForegroundColor Red
        $generated | Where-Object { $_.dcfg_new_value -match 'error|failed|FAIL' } | Select-Object -First 5 | ForEach-Object {
            Write-Host "      $($_.createdon) by $($_.dcfg_performed_by): $($_.dcfg_new_value)" -ForegroundColor Red
        }
    } elseif ($genSuccess -gt 0) {
        Write-Host "    All generations successful" -ForegroundColor Green
    }

    if ($errors.Count -gt 0 -and $genFail -eq 0) {
        $issueCount++
        Write-Host "    OTHER ERRORS: $($errors.Count)" -ForegroundColor Red
        $errors | Select-Object -First 3 | ForEach-Object {
            Write-Host "      $($_.dcfg_new_value)" -ForegroundColor Red
        }
    }

    if ($isDebug -and $auditCount -gt 0) {
        Write-Host ''
        Write-Host '    Recent 10 audit entries:'
        $audits | Select-Object -First 10 | ForEach-Object {
            $label = switch ($_.dcfg_action_type) { 100000000 {'Gen'} 100000001 {'Sent'} 100000006 {'Status'} 100000009 {'Update'} default {$_.dcfg_action_type} }
            $val = if ($_.dcfg_new_value.Length -gt 80) { $_.dcfg_new_value.Substring(0, 80) + '...' } else { $_.dcfg_new_value }
            Write-Host "      $($_.createdon)  [$label]  $val"
        }
    }

    if ($auditCount -eq 0) {
        Write-Host '    No activity in last 24h' -ForegroundColor Gray
    }
} catch {
    Write-Host "    Could not read audit logs: $($_.Exception.Message)" -ForegroundColor Red
    $issueCount++
}

# =============================================================================
# [2] SEND QUEUE ACTIVITY
# =============================================================================
Write-Host ''
Write-Host '  [2] Send Queue Activity' -ForegroundColor Yellow
try {
    $queueItems = (Invoke-RestMethod -Uri "$baseURI/dcfg_send_queues?`$filter=createdon gt $since&`$select=dcfg_send_queueid,dcfg_queue_status,dcfg_added_to_queue_date,dcfg_sent_date,dcfg_notes,createdon&`$expand=dcfg_contract_id(`$select=dcfg_contractid,dcfg_contract_number,dcfg_client_name),dcfg_customer_id(`$select=dcfg_customerid,dcfg_name)&`$orderby=createdon desc" -Headers $baseHeaders).value
    $queueCount = if ($queueItems) { $queueItems.Count } else { 0 }

    if ($queueCount -eq 0) {
        if ($isDebug) { Write-Host '    No send queue activity in last 24h' -ForegroundColor Gray }
        else { Write-Host '    No activity' -ForegroundColor Gray }
    } else {
        # Group by status
        $pending   = @($queueItems | Where-Object { $_.dcfg_queue_status -eq 100000000 })
        $qSent     = @($queueItems | Where-Object { $_.dcfg_queue_status -eq 100000001 })
        $complete  = @($queueItems | Where-Object { $_.dcfg_queue_status -eq 100000002 })
        $cancelled = @($queueItems | Where-Object { $_.dcfg_queue_status -eq 100000003 })

        Write-Host "    Last 24h: $queueCount item(s) — Pending: $($pending.Count), Sent: $($qSent.Count), Complete: $($complete.Count), Cancelled: $($cancelled.Count)"

        if ($pending.Count -gt 0) {
            Write-Host "    Pending items awaiting action:" -ForegroundColor Cyan
            foreach ($qi in $pending) {
                $cust = if ($qi.dcfg_customer_id) { $qi.dcfg_customer_id.dcfg_name } else { '—' }
                $contract = if ($qi.dcfg_contract_id) { $qi.dcfg_contract_id.dcfg_contract_number } else { '—' }
                Write-Host "      Added: $($qi.dcfg_added_to_queue_date)  Customer: $cust  Contract: $contract"
            }
        }

        if ($isDebug -and $queueCount -gt 0) {
            Write-Host ''
            Write-Host '    All items (last 24h):'
            foreach ($qi in $queueItems) {
                $status = switch ($qi.dcfg_queue_status) { 100000000 {'Pending'} 100000001 {'Sent'} 100000002 {'Complete'} 100000003 {'Cancelled'} default {"$($qi.dcfg_queue_status)"} }
                $cust = if ($qi.dcfg_customer_id) { $qi.dcfg_customer_id.dcfg_name } else { '—' }
                $contract = if ($qi.dcfg_contract_id) { $qi.dcfg_contract_id.dcfg_contract_number } else { '—' }
                Write-Host "      $($qi.createdon)  [$status]  Customer: $cust  Contract: $contract"
            }
        }
    }

    # All-time pending count (items that may need attention regardless of age)
    $allPending = (Invoke-RestMethod -Uri "$baseURI/dcfg_send_queues?`$filter=dcfg_queue_status eq 100000000&`$select=dcfg_send_queueid&`$top=100" -Headers $baseHeaders).value
    $allPendingCount = if ($allPending) { $allPending.Count } else { 0 }
    if ($allPendingCount -gt 0) {
        Write-Host "    Total pending (all-time): $allPendingCount" -ForegroundColor Cyan
    }
} catch {
    Write-Host "    Could not read send queue: $($_.Exception.Message)" -ForegroundColor Red
    $issueCount++
}

# =============================================================================
# [3] COMPOSER HEALTH (MSA + Contract Composer success/failure from audit logs)
# =============================================================================
Write-Host ''
Write-Host '  [3] Composer Health' -ForegroundColor Yellow
try {
    # Parse audit log entries for composer-specific events
    $msaGen = @($audits | Where-Object { $_.dcfg_new_value -match 'MSA composer generated' })
    $msaErr = @($audits | Where-Object { $_.dcfg_new_value -match 'MSA composer' -and $_.dcfg_new_value -match 'error|failed|FAIL' })
    $ccGen  = @($audits | Where-Object { $_.dcfg_new_value -match 'ContractComposer generated' })
    $ccErr  = @($audits | Where-Object { $_.dcfg_new_value -match 'ContractComposer' -and $_.dcfg_new_value -match 'error|failed|FAIL' })
    $uploads = @($audits | Where-Object { $_.dcfg_new_value -match 'uploaded.*to /DCFG_Outputs' })
    $uploadFail = @($audits | Where-Object { $_.dcfg_new_value -match 'SharePoint save failed' })

    $msaTotal = $msaGen.Count + $msaErr.Count
    $ccTotal  = $ccGen.Count + $ccErr.Count

    if ($isDebug -or $msaTotal -gt 0 -or $ccTotal -gt 0) {
        Write-Host "    MSA Composer:      $($msaGen.Count) generated, $($msaErr.Count) failed"
        Write-Host "    Contract Composer: $($ccGen.Count) generated, $($ccErr.Count) failed"
        Write-Host "    SharePoint uploads: $($uploads.Count) success, $($uploadFail.Count) failed"
    }

    if ($msaErr.Count -gt 0) {
        $issueCount++
        Write-Host "    MSA FAILURES:" -ForegroundColor Red
        $msaErr | Select-Object -First 3 | ForEach-Object {
            $val = if ($_.dcfg_new_value.Length -gt 100) { $_.dcfg_new_value.Substring(0, 100) + '...' } else { $_.dcfg_new_value }
            Write-Host "      $($_.createdon)  $val" -ForegroundColor Red
        }
    }
    if ($ccErr.Count -gt 0) {
        $issueCount++
        Write-Host "    CONTRACT COMPOSER FAILURES:" -ForegroundColor Red
        $ccErr | Select-Object -First 3 | ForEach-Object {
            $val = if ($_.dcfg_new_value.Length -gt 100) { $_.dcfg_new_value.Substring(0, 100) + '...' } else { $_.dcfg_new_value }
            Write-Host "      $($_.createdon)  $val" -ForegroundColor Red
        }
    }
    if ($uploadFail.Count -gt 0) {
        $issueCount++
        Write-Host "    SHAREPOINT UPLOAD FAILURES:" -ForegroundColor Red
        $uploadFail | Select-Object -First 3 | ForEach-Object {
            $val = if ($_.dcfg_new_value.Length -gt 100) { $_.dcfg_new_value.Substring(0, 100) + '...' } else { $_.dcfg_new_value }
            Write-Host "      $($_.createdon)  $val" -ForegroundColor Red
        }
    }

    if ($msaErr.Count -eq 0 -and $ccErr.Count -eq 0 -and $uploadFail.Count -eq 0 -and ($msaTotal + $ccTotal) -gt 0) {
        Write-Host "    All composers healthy" -ForegroundColor Green
    } elseif ($msaTotal + $ccTotal -eq 0) {
        Write-Host '    No composer activity in last 24h' -ForegroundColor Gray
    }
} catch {
    Write-Host "    Could not parse composer health: $($_.Exception.Message)" -ForegroundColor Red
    $issueCount++
}

# =============================================================================
# [4] SHAREPOINT FILE VERIFICATION (via Graph API)
# =============================================================================
Write-Host ''
Write-Host '  [4] SharePoint Verification' -ForegroundColor Yellow
try {
    # CORS preflight (quick connectivity check)
    $spSite = 'https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite'
    $corsResp = Invoke-WebRequest -Uri "$spSite/_api/contextinfo" -Method OPTIONS -Headers @{
        'Origin' = 'https://dmms1.powerappsportals.com'
        'Access-Control-Request-Method' = 'POST'
        'Access-Control-Request-Headers' = 'accept,authorization'
    } -UseBasicParsing -TimeoutSec 10
    $acao = $corsResp.Headers['Access-Control-Allow-Origin']
    $acah = $corsResp.Headers['Access-Control-Allow-Headers']
    $authAllowed = $acah -match 'authorization'

    if ($acao -eq '*' -and $authAllowed) {
        Write-Host "    CORS OK" -ForegroundColor Green
    } elseif (-not $authAllowed) {
        $issueCount++
        Write-Host "    CORS: Authorization header NOT allowed — uploads will fail" -ForegroundColor Red
    }
    Write-Debug-Line "ACAO: $acao | ACAH: $acah"

    # Graph API file verification — cross-reference audit uploads with actual files
    $graphScopes = [System.Collections.Generic.List[string]]::new()
    $graphScopes.Add('https://graph.microsoft.com/.default')
    try {
        $graphToken = $app.AcquireTokenSilent($graphScopes, $accounts[0]).ExecuteAsync().GetAwaiter().GetResult()
        $gh = @{ Authorization = 'Bearer ' + $graphToken.AccessToken }

        # Get DCFG_Outputs drive ID (cache for cycle)
        $siteObj = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/sites/decadesconstructiongroup.sharepoint.com:/sites/DCFGContractingSuite' -Headers $gh
        $drivesResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$($siteObj.id)/drives" -Headers $gh
        $outputsDrive = $drivesResp.value | Where-Object { $_.name -eq 'DCFG_Outputs' }

        if ($outputsDrive) {
            $driveId = $outputsDrive.id

            # Extract upload paths from audit logs this cycle
            $uploadAudits = @($audits | Where-Object { $_.dcfg_new_value -match 'uploaded.*to (/DCFG_Outputs/.+)' })
            $verified = 0; $missing = 0

            foreach ($ua in $uploadAudits) {
                if ($ua.dcfg_new_value -match 'uploaded:\s*(.+\.docx)\s+to\s+(/DCFG_Outputs/.+)') {
                    $fileName = $Matches[1].Trim()
                    $folderPath = $Matches[2].Trim() -replace '^/DCFG_Outputs/', ''
                    # Remove filename from folder path if it's appended
                    $folderPath = $folderPath -replace '/[^/]+\.docx$', ''
                    $encodedPath = $folderPath -replace ' ', '%20'

                    try {
                        $filesResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root:/${encodedPath}:/children?`$filter=name eq '$fileName'&`$select=name,size,lastModifiedDateTime" -Headers $gh -ErrorAction SilentlyContinue
                        if ($filesResp.value -and $filesResp.value.Count -gt 0) {
                            $f = $filesResp.value[0]
                            $kb = [math]::Round($f.size / 1024, 1)
                            $verified++
                            Write-Debug-Line "VERIFIED: $($f.name) (${kb}KB) in $folderPath"
                        } else {
                            $missing++
                            Write-Host "    MISSING: $fileName in $folderPath" -ForegroundColor Red
                        }
                    } catch {
                        $missing++
                        Write-Host "    MISSING: $fileName in $folderPath — $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }

            if ($uploadAudits.Count -gt 0) {
                if ($missing -gt 0) {
                    $issueCount++
                    Write-Host "    Files: $verified verified, $missing MISSING" -ForegroundColor Red
                } else {
                    Write-Host "    Files: $verified/$($uploadAudits.Count) verified on SharePoint" -ForegroundColor Green
                }
            } else {
                # No uploads in window — just show recent file count
                $recentFiles = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/root/search(q='.docx')?`$top=5&`$orderby=lastModifiedDateTime desc&`$select=name,size,lastModifiedDateTime,parentReference" -Headers $gh
                if ($recentFiles.value -and $recentFiles.value.Count -gt 0) {
                    $latest = $recentFiles.value[0]
                    $kb = [math]::Round($latest.size / 1024, 1)
                    Write-Host "    No uploads in window. Latest file: $($latest.name) (${kb}KB, $($latest.lastModifiedDateTime))" -ForegroundColor Gray
                } else {
                    Write-Host "    No uploads in window. Library accessible." -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "    DCFG_Outputs library not found" -ForegroundColor Red
            $issueCount++
        }
    } catch {
        Write-Host "    Graph API unavailable (CORS-only mode): $($_.Exception.Message)" -ForegroundColor Yellow
    }
} catch {
    $issueCount++
    Write-Host "    SharePoint UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# [5] PORTAL HEALTH
# =============================================================================
Write-Host ''
Write-Host '  [5] Portal Health' -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest -Uri 'https://dmms1.powerappsportals.com/' -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 5
    Write-Host "    dmms1.powerappsportals.com: HTTP $($resp.StatusCode)" -ForegroundColor Green
} catch {
    $issueCount++
    Write-Host "    dmms1.powerappsportals.com UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# [6] AZURE FUNCTION HEALTH (OOXML engine)
# =============================================================================
Write-Host ''
Write-Host '  [6] Azure Function Health' -ForegroundColor Yellow
$azFnUrl = 'https://dcfg-html-to-pdf-d9bwchakhgduf4gc.eastus-01.azurewebsites.net/api/html-to-pdf'
$azFnKey = 'nn-eCIrXFRVqFAyqtM4zZ5BWjA7h1L6Wu3vdhE3a5epBAzFuT8W61g=='
try {
    # Send minimal probe — empty body triggers validation error (not 5xx) if function is alive
    $fnStart = Get-Date
    $fnResp = Invoke-WebRequest -Uri "$azFnUrl`?code=$azFnKey" -Method Post -Body '{}' -ContentType 'application/json' -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
    $fnMs = [int]((Get-Date) - $fnStart).TotalMilliseconds
    Write-Host "    OOXML Function: HTTP $($fnResp.StatusCode) ($fnMs ms)" -ForegroundColor Green
} catch {
    $ex = $_.Exception
    if ($ex.Response -and $ex.Response.StatusCode.value__ -eq 400) {
        $fnMs = [int]((Get-Date) - $fnStart).TotalMilliseconds
        Write-Host "    OOXML Function: responding (400 = expected for empty probe, $fnMs ms)" -ForegroundColor Green
    } else {
        $issueCount++
        $code = if ($ex.Response) { $ex.Response.StatusCode.value__ } else { 'unreachable' }
        Write-Host "    OOXML Function UNHEALTHY: $code — $($ex.Message)" -ForegroundColor Red
        Write-Insight 'Azure Function unhealthy' "OOXML function at $azFnUrl returned $code. Composers cannot generate documents." 'DocGen' 100000000
    }
}

# =============================================================================
# [7] FLOW HEALTH (informational — most work is client-side now)
# =============================================================================
if ($isDebug) {
    Write-Host ''
    Write-Host '  [7] Flow Health (informational)' -ForegroundColor Yellow
    $knownActiveFlows = @(
        'DCFG DocGen v4', 'DCFG Template File Upload',
        'flow_cert_upload', 'flow_onboarding_init',
        'flow_send_email', 'flow_cert_alert'
    )
    try {
        $activeFlows = (Invoke-RestMethod -Uri "$baseURI/workflows?`$filter=category eq 5 and statecode eq 1&`$select=name,workflowid" -Headers $baseHeaders).value
        $activeNames = @()
        if ($activeFlows) { $activeNames = $activeFlows | ForEach-Object { $_.name } }
        $missing = $knownActiveFlows | Where-Object { $_ -notin $activeNames }
        if ($missing -and $missing.Count -gt 0) {
            Write-Host '    FLOWS NOT ACTIVE:' -ForegroundColor Red
            foreach ($m in $missing) { Write-Host "      $m" -ForegroundColor Red }
        }
        Write-Host "    Expected active: $(@($knownActiveFlows | Where-Object { $_ -in $activeNames }).Count)/$($knownActiveFlows.Count)"
        Write-Host "    Total active cloud flows: $(if ($activeFlows) { $activeFlows.Count } else { 0 })"
    } catch {
        Write-Host "    Could not read flows: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =============================================================================
# [8] CONFIG HEALTH
# =============================================================================
if ($isDebug) {
    Write-Host ''
    Write-Host '  [8] Config Health' -ForegroundColor Yellow
    try {
        $configs = (Invoke-RestMethod -Uri "$baseURI/dcfg_configs?`$select=dcfg_key,dcfg_value&`$top=200" -Headers $baseHeaders).value
        Write-Host "    Config entries: $(if ($configs) { $configs.Count } else { 0 })"
        $configs | Where-Object { $_.dcfg_key -match '^dcfg_sp_' } | Sort-Object dcfg_key | ForEach-Object {
            Write-Host "      $($_.dcfg_key) = $($_.dcfg_value)"
        }
    } catch {
        Write-Host "    Could not read configs: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =============================================================================
# [9] E2E WATCH — SPA errors, toast events, user reports (always on)
# =============================================================================
Write-Host ''
Write-Host '  [9] SPA Live Errors' -ForegroundColor Yellow
try {
    # Toast errors (ERR/WARN logged by Toast.jsx to spa_toast)
    $toastErrors = @($audits | Where-Object { $_.dcfg_new_value -match '^\[ERR\]' })
    $toastWarns  = @($audits | Where-Object { $_.dcfg_new_value -match '^\[WARN\]' })
    # User-reported errors via Nora panel
    $userReports = @($audits | Where-Object { $_.dcfg_new_value -match 'spa_error_report' -or ($_.dcfg_action_type -eq 100000010 -and $_.dcfg_new_value -match 'error report') })

    if ($toastErrors.Count -gt 0 -or $toastWarns.Count -gt 0 -or $userReports.Count -gt 0) {
        $issueCount++
        Write-Host "    Toast errors: $($toastErrors.Count)  Warnings: $($toastWarns.Count)  User reports: $($userReports.Count)"
        # Show unique errors (dedup by message prefix)
        $seen = @{}
        foreach ($t in $toastErrors) {
            $key = if ($t.dcfg_new_value.Length -gt 60) { $t.dcfg_new_value.Substring(0, 60) } else { $t.dcfg_new_value }
            if (-not $seen[$key]) {
                $seen[$key] = $true
                $val = if ($t.dcfg_new_value.Length -gt 120) { $t.dcfg_new_value.Substring(0, 120) + '...' } else { $t.dcfg_new_value }
                Write-Host "      $($t.createdon)  $val" -ForegroundColor Red
            }
        }
        if ($userReports.Count -gt 0) {
            Write-Host "    USER ERROR REPORTS:" -ForegroundColor Magenta
            foreach ($r in $userReports | Select-Object -First 3) {
                $val = if ($r.dcfg_new_value.Length -gt 120) { $r.dcfg_new_value.Substring(0, 120) + '...' } else { $r.dcfg_new_value }
                Write-Host "      $($r.createdon)  $val" -ForegroundColor Magenta
            }
        }
    } else {
        if ($isDebug) { Write-Host '    No SPA errors in window' -ForegroundColor Green }
        else { Write-Host '    Clean' -ForegroundColor Green }
    }
} catch {
    Write-Host "    Could not parse SPA errors: $($_.Exception.Message)" -ForegroundColor Red
}

# =============================================================================
# CYCLE SUMMARY
# =============================================================================
$elapsed = ((Get-Date) - $cycleStart).TotalSeconds
Write-Host ''
if ($issueCount -eq 0) {
    Write-Host "  ALL CLEAR — $([math]::Round($elapsed, 1))s" -ForegroundColor Green
} else {
    $summary = "  $issueCount issue(s)"
    if ($resolvedCount -gt 0) { $summary += ", $resolvedCount auto-resolved" }
    $summary += " — $([math]::Round($elapsed, 1))s"
    Write-Host $summary -ForegroundColor $(if ($resolvedCount -ge $issueCount) { 'Yellow' } else { 'Red' })
}
Write-Host "===== NORA PROD [$Mode] complete =====" -ForegroundColor Cyan
