<#
.SYNOPSIS
  Phase 0 parity sweep — compares Test, Stage, Prod for all handoff changes.
.DESCRIPTION
  Read-only. Produces C:\dcfg\docs\code-review-2026-04-09\parity-report.json.
  Requires PowerShell 7+ and a signed-in Az.Accounts session.
  Per feedback_pick_lane_explicit_or_wildcard.md — reports only, no writes.
#>

$ErrorActionPreference = 'Stop'

$outPath = 'C:\dcfg\docs\code-review-2026-04-09\parity-report.json'

# Env table (verified 2026-04-09).
# Site IDs looked up 2026-04-09 — all 3 envs share the same GUID (provisioned from same template).
$envs = @(
    @{ Name = 'Prod';  OrgUrl = 'https://org06f5de0b.crm.dynamics.com'; PortalHost = 'dmms1.powerappsportals.com';   SiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435' },
    @{ Name = 'Test';  OrgUrl = 'https://org0c17e98d.crm.dynamics.com'; PortalHost = 'dcfg.powerappsportals.com';    SiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435' },
    @{ Name = 'Stage'; OrgUrl = 'https://org88778bb0.crm.dynamics.com'; PortalHost = 'holding.powerappsportals.com'; SiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435' }
)

$webapiTargets = @(
    @{ ComponentName = 'Webapi/dcfg_template_field/fields';       RequiredBinds = @('dcfg_template_id') },
    @{ ComponentName = 'Webapi/dcfg_document_template/fields';    RequiredBinds = @('dcfg_customer_id') },
    @{ ComponentName = 'Webapi/dcfg_blanket_workorder/fields';    RequiredBinds = @('dcfg_customer_id') },
    @{ ComponentName = 'Webapi/dcfg_customer_ap_mapping/fields';  RequiredBinds = @('dcfg_customer_id', 'dcfg_cost_code_id') }
)
$configKey = 'dcfg_sp_templates_library'
# Per-env expected values — operator decision 2026-04-09 Gate 0a:
#   Prod  uses DCFG_Templates       (production library)
#   Test  uses DCFG_Templates_Test  (per-env isolation, Q1=A 'keep')
#   Stage uses DCFG_Templates_Stage (per-env isolation, Q3=B insert with env-specific name)
$expectedConfigByEnv = @{
    'Prod'  = 'DCFG_Templates'
    'Test'  = 'DCFG_Templates_Test'
    'Stage' = 'DCFG_Templates_Stage'
}

function Get-OrgToken { param($OrgUrl)
    [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$OrgUrl/" -AsSecureString).Token).Password
}

function Get-Headers { param($Token)
    @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
}

# Note: parameter is $HostName — $Host is a PowerShell automatic variable and cannot be a parameter name.
function Resolve-SiteId { param($OrgUrl, $Headers, $HostName)
    $uri = "$OrgUrl/api/data/v9.2/powerpagesites?`$select=powerpagesiteid,name"
    $r = (Invoke-RestMethod -Uri $uri -Headers $Headers).value
    # Heuristic match: hostname prefix in the site name
    $keyword = ($HostName -split '\.')[0]
    $match = $r | Where-Object { $_.name -match $keyword } | Select-Object -First 1
    if (-not $match) { throw "Could not resolve powerpagesite for host '$HostName' — found $($r.Count) sites, none match keyword '$keyword'. Sites: $($r.name -join ', ')" }
    return $match.powerpagesiteid
}

function Get-FieldsListState { param($OrgUrl, $Headers, $SiteId, $ComponentName)
    if (-not $SiteId) { return @{ present = $false; reason = 'site-id-not-resolved' } }
    $filter = "powerpagecomponenttype eq 9 and _powerpagesiteid_value eq $SiteId and name eq '$ComponentName'"
    $uri = "$OrgUrl/api/data/v9.2/powerpagecomponents?`$filter=$filter&`$select=powerpagecomponentid,content"
    try {
        $r = (Invoke-RestMethod -Uri $uri -Headers $Headers).value | Select-Object -First 1
    } catch {
        return @{ present = $false; reason = "query-failed: $($_.Exception.Message)" }
    }
    if (-not $r) { return @{ present = $false; reason = 'component-not-found' } }
    # Content can be either a JSON object {"value":"..."} or a raw string like "*"
    try {
        $content = $r.content | ConvertFrom-Json -ErrorAction Stop
        $value = if ($content -is [string]) { $content } else { $content.value }
    } catch {
        $value = $r.content
    }
    $mode = if ($value -eq '*') { 'wildcard' } else { 'explicit' }
    return @{
        present = $true
        componentId = $r.powerpagecomponentid
        mode = $mode
        fields = $value
        fieldList = ($value -split ',')
    }
}

function Get-ConfigValue { param($OrgUrl, $Headers, $Key)
    $uri = "$OrgUrl/api/data/v9.2/dcfg_configs?`$filter=dcfg_key eq '$Key'&`$select=dcfg_configid,dcfg_value,modifiedon"
    try {
        $r = (Invoke-RestMethod -Uri $uri -Headers $Headers).value | Select-Object -First 1
    } catch {
        return @{ present = $false; reason = "query-failed: $($_.Exception.Message)" }
    }
    if (-not $r) { return @{ present = $false; reason = 'key-not-found' } }
    return @{ present = $true; id = $r.dcfg_configid; value = $r.dcfg_value; modifiedon = $r.modifiedon }
}

$report = @{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    envs = @{}
    drift = @()
}

foreach ($envDef in $envs) {
    $envName = $envDef.Name
    Write-Host ""
    Write-Host "=== $envName ($($envDef.OrgUrl)) ===" -ForegroundColor Cyan
    $token = Get-OrgToken $envDef.OrgUrl
    $headers = Get-Headers $token
    $siteId = if ($envDef.SiteId) { $envDef.SiteId } else { Resolve-SiteId $envDef.OrgUrl $headers $envDef.PortalHost }
    Write-Host "  SiteId: $siteId"

    $envState = @{ orgUrl = $envDef.OrgUrl; portalHost = $envDef.PortalHost; siteId = $siteId; webapi = @{}; config = $null }

    foreach ($tgt in $webapiTargets) {
        $state = Get-FieldsListState $envDef.OrgUrl $headers $siteId $tgt.ComponentName
        $envState.webapi[$tgt.ComponentName] = $state
        if ($state.present -and $state.mode -eq 'explicit') {
            foreach ($bind in $tgt.RequiredBinds) {
                if ($state.fieldList -notcontains $bind) {
                    Write-Host "  DRIFT: $($tgt.ComponentName) missing '$bind'" -ForegroundColor Yellow
                    $report.drift += @{ env = $envName; target = $tgt.ComponentName; kind = 'missing-bind'; column = $bind; currentFields = $state.fields }
                } else {
                    Write-Host "  OK   : $($tgt.ComponentName) has '$bind'" -ForegroundColor Green
                }
            }
        } elseif ($state.present -and $state.mode -eq 'wildcard') {
            Write-Host "  OK   : $($tgt.ComponentName) is wildcard" -ForegroundColor Green
        } else {
            Write-Host "  MISS : $($tgt.ComponentName) — $($state.reason)" -ForegroundColor Red
            $report.drift += @{ env = $envName; target = $tgt.ComponentName; kind = 'not-found'; reason = $state.reason }
        }
    }

    $cfgState = Get-ConfigValue $envDef.OrgUrl $headers $configKey
    $envState.config = $cfgState
    $envExpected = $expectedConfigByEnv[$envName]
    if ($cfgState.present) {
        if ($cfgState.value -eq $envExpected) {
            Write-Host "  OK   : $configKey = '$($cfgState.value)'" -ForegroundColor Green
        } else {
            Write-Host "  DRIFT: $configKey = '$($cfgState.value)' (expected '$envExpected')" -ForegroundColor Yellow
            $report.drift += @{ env = $envName; target = $configKey; kind = 'config-drift'; current = $cfgState.value; expected = $envExpected }
        }
    } else {
        Write-Host "  MISS : $configKey - $($cfgState.reason)" -ForegroundColor Red
        $report.drift += @{ env = $envName; target = $configKey; kind = 'config-missing'; reason = $cfgState.reason; expected = $envExpected }
    }

    $report.envs[$envName] = $envState
}

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding UTF8
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Drift count: $($report.drift.Count)"
Write-Host "Report     : $outPath"
