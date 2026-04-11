# Audit-PermissionDrift.ps1 — READ-ONLY drift audit
# Compares live permissions against desired-state.json, reports mismatches, logs to JSON
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

$desiredState = Get-Content 'C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\desired-state.json' -Raw | ConvertFrom-Json
$logPath = 'C:\DCFG\ops\drift-audit-log.json'

# Load existing log or start fresh
$auditLog = if (Test-Path $logPath) {
    Get-Content $logPath -Raw | ConvertFrom-Json
} else {
    @{ cycles = @() }
}

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] DRIFT AUDIT" -ForegroundColor Cyan

    $ok = 0; $drifted = @(); $missing = @(); $errors = @()

    foreach ($prop in $desiredState.permissions.PSObject.Properties) {
        $table = $prop.Name
        if ($table -eq '_note') { continue }
        $desired = $prop.Value
        $permId = $desired.id

        try {
            $live = Invoke-RestMethod -Uri "$OrgUrl/powerpagecomponents($permId)?`$select=name,content" -Headers $baseHeaders
            $content = $live.content | ConvertFrom-Json

            $issues = @()

            # Check roles
            $liveRoles = $content.adx_entitypermission_webrole
            if (-not $liveRoles -or $liveRoles.Count -eq 0) {
                if ($desired.roles -and $desired.roles.Count -gt 0) {
                    $issues += "NO_ROLES (expected $($desired.roles.Count))"
                }
            } elseif ($desired.roles) {
                $missingRoles = $desired.roles | Where-Object { $_ -notin $liveRoles }
                $extraRoles = $liveRoles | Where-Object { $_ -notin $desired.roles }
                if ($missingRoles.Count -gt 0) { $issues += "MISSING_ROLES: $($missingRoles -join ',')" }
                if ($extraRoles.Count -gt 0) { $issues += "EXTRA_ROLES: $($extraRoles -join ',')" }
            }

            # Check CRUD flags
            $flags = @('read','write','create','delete','append','appendto')
            foreach ($f in $flags) {
                $desiredVal = $desired.$f
                $liveVal = $content.$f
                if ($desiredVal -ne $liveVal) {
                    $issues += "${f}: live=$liveVal desired=$desiredVal"
                }
            }

            if ($issues.Count -gt 0) {
                $drifted += @{ table = $table; id = $permId; issues = $issues }
                Write-Host "  DRIFT $table : $($issues -join ' | ')" -ForegroundColor Yellow
            } else {
                $ok++
            }
        } catch {
            if ($_.Exception.Message -match '404') {
                $missing += $table
                Write-Host "  MISSING $table ($permId) - permission record does not exist" -ForegroundColor Red
            } else {
                $errors += @{ table = $table; error = $_.Exception.Message }
                Write-Host "  ERROR $table : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    # Check flows
    $flowOk = 0; $flowDown = @()
    foreach ($flowProp in $desiredState.flows.PSObject.Properties) {
        $flowName = $flowProp.Name
        $flowDef = $flowProp.Value
        try {
            $liveFlow = Invoke-RestMethod -Uri "$OrgUrl/workflows($($flowDef.id))?`$select=statecode,name" -Headers $baseHeaders
            if ($liveFlow.statecode -ne $flowDef.expectedState) {
                $flowDown += @{ name = $flowName; expected = $flowDef.expectedState; actual = $liveFlow.statecode }
                Write-Host "  FLOW DOWN: $flowName (state=$($liveFlow.statecode))" -ForegroundColor Red
            } else {
                $flowOk++
            }
        } catch {
            $flowDown += @{ name = $flowName; error = $_.Exception.Message }
            Write-Host "  FLOW ERROR: $flowName" -ForegroundColor Red
        }
    }

    # Summary
    $summary = "Perms: ${ok} OK, $($drifted.Count) drifted, $($missing.Count) missing | Flows: ${flowOk} active, $($flowDown.Count) down"
    $color = if ($drifted.Count -eq 0 -and $missing.Count -eq 0 -and $flowDown.Count -eq 0) { 'Green' } else { 'Yellow' }
    Write-Host "  $summary" -ForegroundColor $color

    # Append to log
    $cycle = @{
        timestamp = $ts
        permissionsOk = $ok
        permissionsDrifted = $drifted.Count
        permissionsMissing = $missing.Count
        flowsActive = $flowOk
        flowsDown = $flowDown.Count
        summary = $summary
        drift = $drifted
        missingPerms = $missing
        flowIssues = $flowDown
        errors = $errors
    }

    # Keep last 500 cycles
    $cycles = @($auditLog.cycles) + @($cycle)
    if ($cycles.Count -gt 500) { $cycles = $cycles[-500..-1] }
    @{ cycles = $cycles } | ConvertTo-Json -Depth 5 | Out-File -FilePath $logPath -Encoding utf8
}
