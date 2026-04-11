# Fix-PermissionDrift.ps1 — Fix permissions missing role links in content JSON
# Reads desired-state.json, compares to live, patches any missing adx_entitypermission_webrole arrays
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'
$WebsiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435'

# Load desired state
$desiredState = Get-Content 'C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\desired-state.json' -Raw | ConvertFrom-Json

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }
    Write-Host "`n===== FIX PERMISSION DRIFT =====" -ForegroundColor Cyan
    Write-Host "Reading live powerpagecomponent content JSONs...`n" -ForegroundColor Gray

    $fixed = 0
    $skipped = 0
    $failed = 0

    foreach ($prop in $desiredState.permissions.PSObject.Properties) {
        $table = $prop.Name
        $desired = $prop.Value
        $permId = $desired.id
        $desiredRoles = $desired.roles

        if (-not $desiredRoles -or $desiredRoles.Count -eq 0) {
            Write-Host "  SKIP $table — no roles defined in desired state" -ForegroundColor Gray
            $skipped++
            continue
        }

        # Read live content JSON
        try {
            $live = Invoke-RestMethod -Uri "$OrgUrl/powerpagecomponents($permId)?`$select=name,content" -Headers $baseHeaders
            $content = $live.content | ConvertFrom-Json

            $liveRoles = $content.adx_entitypermission_webrole
            $hasRoles = $liveRoles -and $liveRoles.Count -gt 0

            if ($hasRoles) {
                # Check if roles match desired
                $missing = $desiredRoles | Where-Object { $_ -notin $liveRoles }
                if ($missing.Count -eq 0) {
                    Write-Host "  OK $table — $($liveRoles.Count) roles" -ForegroundColor Green
                    $skipped++
                    continue
                } else {
                    Write-Host "  DRIFT $table — missing $($missing.Count) roles, will fix" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  MISSING $table — no adx_entitypermission_webrole in content JSON" -ForegroundColor Red
            }

            # Build corrected content JSON
            $content | Add-Member -NotePropertyName 'adx_entitypermission_webrole' -NotePropertyValue @($desiredRoles) -Force

            # Also ensure all CRUD flags match desired state
            $content.read = $desired.read
            $content.write = $desired.write
            $content.create = $desired.create
            $content.delete = $desired.delete
            $content.append = $desired.append
            $content.appendto = $desired.appendto
            $content.scope = $desired.scope

            $newContentJson = $content | ConvertTo-Json -Compress

            # PATCH
            Update-Record -setName 'powerpagecomponents' -id $permId -body @{
                content = $newContentJson
            }
            Write-Host "  FIXED $table — roles: [$($desiredRoles -join ', ')]" -ForegroundColor Green
            $fixed++

        } catch {
            Write-Host "  FAIL $table ($permId): $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }

    # Handle duplicate dcfg_agent_config — delete the extra one
    Write-Host "`n--- Cleaning up duplicates ---" -ForegroundColor Cyan
    $dupeId = '86fa12d1-3f27-f111-8341-7ced8d709173'  # second dcfg_agent_config (RW version)
    try {
        Invoke-RestMethod -Uri "$OrgUrl/mspp_entitypermissions($dupeId)" -Method DELETE -Headers $baseHeaders | Out-Null
        Write-Host "  Deleted duplicate dcfg_agent_config ($dupeId)" -ForegroundColor Yellow
    } catch {
        Write-Host "  Duplicate cleanup: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Handle duplicate dcfg_appliance_photo — delete the one without roles (d3c6402e)
    $dupePhotoId = 'd3c6402e-4221-f111-8341-7ced8d709173'
    try {
        Invoke-RestMethod -Uri "$OrgUrl/mspp_entitypermissions($dupePhotoId)" -Method DELETE -Headers $baseHeaders | Out-Null
        Write-Host "  Deleted duplicate dcfg_appliance_photo ($dupePhotoId)" -ForegroundColor Yellow
    } catch {
        Write-Host "  Duplicate cleanup: $($_.Exception.Message)" -ForegroundColor Gray
    }

    Write-Host "`n===== RESULTS =====" -ForegroundColor Cyan
    Write-Host "  Fixed: $fixed | Already OK: $skipped | Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "`n  NEXT: Clear portal cache" -ForegroundColor Yellow
    Write-Host "  https://dcfg.powerappsportals.com/_services/about?clearCache=true" -ForegroundColor Cyan
}
