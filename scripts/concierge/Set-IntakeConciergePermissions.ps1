. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'

$WebsiteId = '105da837-2fe3-414a-9eed-42a5ecbf543d'  # decadeswelcomesyou concierge site
$OrgUrl    = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

Invoke-DataverseCommands {

    # ── 1. Discover existing intake permission pattern ──
    Write-Host "`n=== Discovering existing intake permission pattern ===" -ForegroundColor Cyan

    # Find existing permissions for dcfg_intake_vendor to learn which roles are linked
    $existingPerms = (Get-Records -setName 'mspp_entitypermissions' `
        -query "?`$select=mspp_entitypermissionid,mspp_entityname,mspp_scope&`$filter=mspp_entityname eq 'dcfg_intake_vendor' and _mspp_websiteid_value eq $WebsiteId").value

    if ($existingPerms -and $existingPerms.Count -gt 0) {
        Write-Host "Found existing dcfg_intake_vendor permission: $($existingPerms[0].mspp_entitypermissionid)" -ForegroundColor Green
        # Read the powerpagecomponent content JSON to get the role IDs
        $ppc = Invoke-RestMethod -Uri "$OrgUrl/powerpagecomponents($($existingPerms[0].mspp_entitypermissionid))?`$select=content" -Headers $baseHeaders
        $existingContent = $ppc.content | ConvertFrom-Json
        $roleIds = $existingContent.adx_entitypermission_webrole
        Write-Host "Roles linked: $($roleIds -join ', ')" -ForegroundColor Green
        $scope = $existingContent.scope
        Write-Host "Scope: $scope" -ForegroundColor Green
    } else {
        Write-Host "No existing dcfg_intake_vendor permission found — using Authenticated Users as fallback" -ForegroundColor Yellow
        $roleIds = @('ae785cc2-54bb-400e-b0be-b448ea923352')  # Authenticated Users
        $scope = 756150000  # Global
    }

    # ── 2. Site Settings ──
    Write-Host "`n=== Creating Site Settings ===" -ForegroundColor Cyan

    $settings = @(
        @{ Name = 'Webapi/dcfg_intake_date/enabled'; Value = 'true' },
        @{ Name = 'Webapi/dcfg_intake_date/fields';  Value = '_dcfg_sessionid_value,createdon,dcfg_active_flag,dcfg_category,dcfg_due_date,dcfg_intake_dateid,dcfg_location_ref,dcfg_name,dcfg_notes,modifiedon,statecode,statuscode' },
        @{ Name = 'Webapi/dcfg_intake_delegation/enabled'; Value = 'true' },
        @{ Name = 'Webapi/dcfg_intake_delegation/fields';  Value = '_dcfg_sessionid_value,createdon,dcfg_active_flag,dcfg_card_scope,dcfg_delegate_email,dcfg_intake_delegationid,dcfg_name,dcfg_personal_note,dcfg_sender_email,dcfg_sender_name,dcfg_sent_at,modifiedon,statecode,statuscode' }
    )

    foreach ($s in $settings) {
        $existing = (Get-Records -setName 'powerpagecomponents' `
            -query "?`$select=powerpagecomponentid,name&`$filter=_powerpagesiteid_value eq $WebsiteId and powerpagecomponenttype eq 9 and name eq '$($s.Name)'").value
        if ($existing -and $existing.Count -gt 0) {
            Write-Host "EXISTS: $($s.Name)" -ForegroundColor Yellow
        } else {
            $id = New-Record -setName 'powerpagecomponents' -body @{
                name                         = $s.Name
                powerpagecomponenttype       = 9
                content                      = (@{ value = $s.Value } | ConvertTo-Json -Compress)
                'powerpagesiteid@odata.bind' = "/powerpagesites($WebsiteId)"
            }
            Write-Host "CREATED: $($s.Name) => $id" -ForegroundColor Green
        }
    }

    # ── 3. Table Permissions ──
    Write-Host "`n=== Creating Table Permissions ===" -ForegroundColor Cyan

    $tables = @(
        @{ EntityName = 'dcfg_intake_date';       Label = 'Intake Date' },
        @{ EntityName = 'dcfg_intake_delegation'; Label = 'Intake Delegation' }
    )

    foreach ($t in $tables) {
        $existPerm = (Get-Records -setName 'mspp_entitypermissions' `
            -query "?`$select=mspp_entitypermissionid,mspp_entityname&`$filter=mspp_entityname eq '$($t.EntityName)' and _mspp_websiteid_value eq $WebsiteId").value

        if ($existPerm -and $existPerm.Count -gt 0) {
            Write-Host "EXISTS: Permission for $($t.EntityName) => $($existPerm[0].mspp_entitypermissionid)" -ForegroundColor Yellow
            $permId = $existPerm[0].mspp_entitypermissionid
        } else {
            # Step 1: Create permission record
            $permId = New-Record -setName 'mspp_entitypermissions' -body @{
                mspp_entityname             = $t.EntityName
                mspp_entitylogicalname      = $t.EntityName
                mspp_scope                  = $scope
                mspp_read                   = $true
                mspp_write                  = $true
                mspp_create                 = $true
                mspp_delete                 = $true
                mspp_append                 = $true
                mspp_appendto               = $true
                'mspp_websiteid@odata.bind' = "/powerpagesites($WebsiteId)"
            }
            Write-Host "CREATED: Permission for $($t.EntityName) => $permId" -ForegroundColor Green
        }

        # Step 2: PATCH powerpagecomponent content JSON with role links
        # This is what the portal runtime actually reads for authorization
        $contentObj = @{
            read                             = $true
            write                            = $true
            create                           = $true
            delete                           = $true
            append                           = $true
            appendto                         = $true
            scope                            = $scope
            entityname                       = $t.EntityName
            entitylogicalname                = $t.EntityName
            adx_entitypermission_webrole     = $roleIds
        }
        Update-Record -setName 'powerpagecomponents' -id $permId -body @{
            content = ($contentObj | ConvertTo-Json -Compress)
        }
        Write-Host "PATCHED: Content JSON with role links for $($t.EntityName)" -ForegroundColor Green
    }

    # ── 4. Verify ──
    Write-Host "`n=== Verifying ===" -ForegroundColor Cyan

    foreach ($t in $tables) {
        $perm = (Get-Records -setName 'mspp_entitypermissions' `
            -query "?`$select=mspp_entitypermissionid,mspp_entityname&`$filter=mspp_entityname eq '$($t.EntityName)' and _mspp_websiteid_value eq $WebsiteId").value
        if ($perm -and $perm.Count -gt 0) {
            $ppc = Invoke-RestMethod -Uri "$OrgUrl/powerpagecomponents($($perm[0].mspp_entitypermissionid))?`$select=content" -Headers $baseHeaders
            $c = $ppc.content | ConvertFrom-Json
            if ($c.adx_entitypermission_webrole -and $c.adx_entitypermission_webrole.Count -gt 0) {
                Write-Host "OK: $($t.EntityName) — $($c.adx_entitypermission_webrole.Count) role(s) linked" -ForegroundColor Green
            } else {
                Write-Host "WARN: $($t.EntityName) — no roles in content JSON! Portal will return 403." -ForegroundColor Red
            }
        } else {
            Write-Host "FAIL: $($t.EntityName) — permission record not found!" -ForegroundColor Red
        }
    }

    Write-Host "`n=== Done. Clear portal cache at https://decadeswelcomesyou.powerappsportals.com/_services/about ===" -ForegroundColor Cyan
}
