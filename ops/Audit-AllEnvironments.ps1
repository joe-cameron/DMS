# Audit-AllEnvironments.ps1 — READ-ONLY audit across test, stage, and prod
# Checks permissions, site settings, flows, and role links against desired state
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

$desiredState = Get-Content 'C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\desired-state.json' -Raw | ConvertFrom-Json
$environments = Get-Content 'C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\environments.json' -Raw | ConvertFrom-Json

$envConfigs = @(
    @{ name = 'TEST';  orgUrl = $environments.test.orgUrl;  apiBase = $environments.test.apiBase;  siteId = $environments.test.websiteId },
    @{ name = 'STAGE'; orgUrl = $environments.stage.orgUrl; apiBase = $environments.stage.apiBase; siteId = $environments.stage.websiteId },
    @{ name = 'PROD';  orgUrl = $environments.prod.orgUrl;  apiBase = $environments.prod.apiBase;  siteId = $environments.prod.websiteId }
)

$allResults = @()

foreach ($env in $envConfigs) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host " $($env.name): $($env.orgUrl)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    try {
        Connect "$($env.orgUrl)/"
    } catch {
        Write-Host "  CONNECT FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $allResults += @{ environment = $env.name; status = 'CONNECT_FAILED'; error = $_.Exception.Message }
        continue
    }

    $OrgUrl = $env.apiBase
    $siteId = $env.siteId

    $envResult = @{
        environment = $env.name
        orgUrl = $env.orgUrl
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        permissions = @{ ok = 0; drifted = @(); missing = @(); noRoles = @(); errors = @() }
        flows = @{ active = 0; down = @(); missing = @() }
        siteSettings = @{ ok = 0; missing = @() }
        sites = @()
    }

    Invoke-DataverseCommands {

        # ── PERMISSIONS ──
        Write-Host "`n  [Permissions]" -ForegroundColor Yellow
        if (-not $siteId) {
            Write-Host "    No websiteId configured — skipping permissions" -ForegroundColor Gray
        } else {
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
                            $issues += "NO_ROLES"
                            $envResult.permissions.noRoles += $table
                        }
                    } elseif ($desired.roles) {
                        $missingR = $desired.roles | Where-Object { $_ -notin $liveRoles }
                        if ($missingR.Count -gt 0) { $issues += "MISSING_ROLES:$($missingR.Count)" }
                    }

                    # Check CRUD flags
                    foreach ($f in @('read','write','create','delete','append','appendto')) {
                        if ($desired.$f -ne $content.$f) { $issues += "${f}:live=$($content.$f)" }
                    }

                    if ($issues.Count -gt 0) {
                        $envResult.permissions.drifted += @{ table = $table; issues = $issues }
                        Write-Host "    DRIFT $table : $($issues -join ' | ')" -ForegroundColor Yellow
                    } else {
                        $envResult.permissions.ok++
                    }
                } catch {
                    if ($_.Exception.Message -match '404') {
                        $envResult.permissions.missing += $table
                        Write-Host "    MISSING $table" -ForegroundColor Red
                    } else {
                        $envResult.permissions.errors += @{ table = $table; error = $_.Exception.Message }
                    }
                }
            }
            Write-Host "    OK: $($envResult.permissions.ok) | Drift: $($envResult.permissions.drifted.Count) | Missing: $($envResult.permissions.missing.Count) | NoRoles: $($envResult.permissions.noRoles.Count)" -ForegroundColor $(if ($envResult.permissions.drifted.Count + $envResult.permissions.missing.Count + $envResult.permissions.noRoles.Count -eq 0) { 'Green' } else { 'Yellow' })
        }

        # ── FLOWS ──
        Write-Host "`n  [Flows]" -ForegroundColor Yellow
        foreach ($flowProp in $desiredState.flows.PSObject.Properties) {
            $flowName = $flowProp.Name
            $flowDef = $flowProp.Value
            try {
                $liveFlow = Invoke-RestMethod -Uri "$OrgUrl/workflows($($flowDef.id))?`$select=statecode,name" -Headers $baseHeaders
                if ($liveFlow.statecode -ne $flowDef.expectedState) {
                    $envResult.flows.down += @{ name = $flowName; state = $liveFlow.statecode }
                    Write-Host "    DOWN: $flowName (state=$($liveFlow.statecode))" -ForegroundColor Red
                } else {
                    $envResult.flows.active++
                }
            } catch {
                if ($_.Exception.Message -match '404') {
                    $envResult.flows.missing += $flowName
                    Write-Host "    NOT FOUND: $flowName" -ForegroundColor Red
                } else {
                    Write-Host "    ERROR: $flowName - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        Write-Host "    Active: $($envResult.flows.active) | Down: $($envResult.flows.down.Count) | Missing: $($envResult.flows.missing.Count)" -ForegroundColor $(if ($envResult.flows.down.Count + $envResult.flows.missing.Count -eq 0) { 'Green' } else { 'Red' })

        # ── SITE SETTINGS ──
        Write-Host "`n  [Site Settings]" -ForegroundColor Yellow
        if (-not $siteId) {
            Write-Host "    No websiteId — skipping" -ForegroundColor Gray
        } else {
            foreach ($tbl in $desiredState.siteSettings.tables) {
                foreach ($settingType in @('enabled', 'fields')) {
                    $settingName = "Webapi/$tbl/$settingType"
                    try {
                        $found = (Get-Records -setName 'powerpagecomponents' `
                            -query "?`$select=powerpagecomponentid&`$filter=_powerpagesiteid_value eq $siteId and powerpagecomponenttype eq 9 and name eq '$settingName'&`$top=1").value
                        if ($found -and $found.Count -gt 0) {
                            $envResult.siteSettings.ok++
                        } else {
                            $envResult.siteSettings.missing += $settingName
                        }
                    } catch {
                        $envResult.siteSettings.missing += "$settingName (error)"
                    }
                }
            }
            $missingCount = $envResult.siteSettings.missing.Count
            Write-Host "    OK: $($envResult.siteSettings.ok) | Missing: $missingCount" -ForegroundColor $(if ($missingCount -eq 0) { 'Green' } else { 'Yellow' })
            if ($missingCount -gt 0 -and $missingCount -le 10) {
                foreach ($m in $envResult.siteSettings.missing) {
                    Write-Host "      - $m" -ForegroundColor Yellow
                }
            } elseif ($missingCount -gt 10) {
                Write-Host "      ($missingCount missing — too many to list)" -ForegroundColor Yellow
            }
        }

        # ── ORPHAN SITES ──
        Write-Host "`n  [Portal Sites]" -ForegroundColor Yellow
        try {
            $sites = (Invoke-RestMethod -Uri "$OrgUrl/powerpagesites?`$select=powerpagesiteid,name" -Headers $baseHeaders).value
            $envResult.sites = @($sites | ForEach-Object { @{ id = $_.powerpagesiteid; name = $_.name } })
            Write-Host "    $($sites.Count) site(s) found" -ForegroundColor $(if ($sites.Count -le 2) { 'Green' } else { 'Yellow' })
            foreach ($s in $sites) {
                $marker = if ($s.powerpagesiteid -eq $siteId) { ' <-- ACTIVE' } else { '' }
                Write-Host "      $($s.name) ($($s.powerpagesiteid))$marker" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    Could not query sites" -ForegroundColor Gray
        }
    }

    $allResults += $envResult
}

# ── SUMMARY ──
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " CROSS-ENVIRONMENT SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

foreach ($r in $allResults) {
    if ($r.status -eq 'CONNECT_FAILED') {
        Write-Host "  $($r.environment): CONNECTION FAILED" -ForegroundColor Red
        continue
    }
    $permIssues = $r.permissions.drifted.Count + $r.permissions.missing.Count + $r.permissions.noRoles.Count
    $flowIssues = $r.flows.down.Count + $r.flows.missing.Count
    $settingIssues = $r.siteSettings.missing.Count
    $total = $permIssues + $flowIssues + $settingIssues
    $color = if ($total -eq 0) { 'Green' } elseif ($total -le 5) { 'Yellow' } else { 'Red' }
    Write-Host "  $($r.environment): Perms=$($r.permissions.ok)ok/$($permIssues)issues | Flows=$($r.flows.active)/$($r.flows.down.Count+$r.flows.missing.Count) | Settings=$($r.siteSettings.ok)ok/$settingIssues missing | Sites=$($r.sites.Count)" -ForegroundColor $color
}

# Save
$allResults | ConvertTo-Json -Depth 6 | Out-File -FilePath 'C:\DCFG\ops\env-audit-results.json' -Encoding utf8
Write-Host "`nSaved to C:\DCFG\ops\env-audit-results.json" -ForegroundColor Green
