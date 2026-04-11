# =============================================================================
# Nora Schema — Creates columns and tables for Nora's operation
# Target: Staging (org88778bb0)
# =============================================================================
param(
    [string]$Env = 'stage'
)

. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

$orgUrl = if ($Env -eq 'stage') { 'https://org88778bb0.crm.dynamics.com/' } else { 'https://org0c17e98d.crm.dynamics.com/' }
Connect $orgUrl

$apiBase = "${orgUrl}api/data/v9.2"

Invoke-DataverseCommands {
    $token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl $orgUrl -AsSecureString).Token).Password
    $h = @{
        'Authorization' = "Bearer $token"; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'
        'Accept' = 'application/json'; 'Content-Type' = 'application/json; charset=utf-8'
    }

    Write-Host "=== NORA SCHEMA SETUP ($Env) ===" -ForegroundColor Cyan

    # =========================================================================
    # 1. New columns on dcfg_document_request
    # =========================================================================
    Write-Host "`n--- dcfg_document_request columns ---" -ForegroundColor Yellow

    # Check if columns already exist
    $existingAttrs = (Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='dcfg_document_request')/Attributes?`$select=LogicalName" -Headers $h).value
    $existingNames = $existingAttrs | ForEach-Object { $_.LogicalName }

    # dcfg_nora_retry_count (Integer)
    if ($existingNames -contains 'dcfg_nora_retry_count') {
        Write-Host "  SKIP: dcfg_nora_retry_count (exists)" -ForegroundColor Yellow
    } else {
        $body = @{
            '@odata.type' = '#Microsoft.Dynamics.CRM.IntegerAttributeMetadata'
            SchemaName = 'dcfg_nora_retry_count'
            DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Nora Retry Count'; LanguageCode = 1033 }) }
            RequiredLevel = @{ Value = 'None' }
            Format = 'None'
            MinValue = 0
            MaxValue = 100
        } | ConvertTo-Json -Depth 10
        try {
            Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='dcfg_document_request')/Attributes" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -Headers $h | Out-Null
            Write-Host "  CREATED: dcfg_nora_retry_count" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
    }

    # dcfg_nora_message (String 500)
    if ($existingNames -contains 'dcfg_nora_message') {
        Write-Host "  SKIP: dcfg_nora_message (exists)" -ForegroundColor Yellow
    } else {
        $body = @{
            '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
            SchemaName = 'dcfg_nora_message'
            DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Nora Message'; LanguageCode = 1033 }) }
            RequiredLevel = @{ Value = 'None' }
            MaxLength = 500
            FormatName = @{ Value = 'Text' }
        } | ConvertTo-Json -Depth 10
        try {
            Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='dcfg_document_request')/Attributes" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -Headers $h | Out-Null
            Write-Host "  CREATED: dcfg_nora_message" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
    }

    # =========================================================================
    # 2. Seed nora_last_check in dcfg_configs
    # =========================================================================
    Write-Host "`n--- nora_last_check config ---" -ForegroundColor Yellow

    $existing = (Invoke-RestMethod -Uri "$apiBase/dcfg_configs?`$filter=dcfg_key eq 'nora_last_check'&`$select=dcfg_configid" -Headers $h).value
    if ($existing -and $existing.Count -gt 0) {
        Write-Host "  SKIP: nora_last_check (exists)" -ForegroundColor Yellow
    } else {
        $body = @{
            dcfg_key = 'nora_last_check'
            dcfg_value = (Get-Date).ToUniversalTime().ToString('o')
            dcfg_active = $true
        } | ConvertTo-Json -Compress
        try {
            Invoke-RestMethod -Uri "$apiBase/dcfg_configs" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -Headers $h | Out-Null
            Write-Host "  CREATED: nora_last_check" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
    }

    # =========================================================================
    # 3. Add Webapi site settings for brain_insights (if not present)
    # =========================================================================
    Write-Host "`n--- Web API site settings ---" -ForegroundColor Yellow
    $websiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435'

    $tables = @('dcfg_brain_insight')
    foreach ($table in $tables) {
        $enabledName = "Webapi/$table/enabled"
        $fieldsName = "Webapi/$table/fields"

        $existSS = (Invoke-RestMethod -Uri "$apiBase/powerpagecomponents?`$filter=powerpagecomponenttype eq 9 and name eq '$enabledName' and _powerpagesiteid_value eq $websiteId&`$select=powerpagecomponentid" -Headers $h).value
        if ($existSS -and $existSS.Count -gt 0) {
            Write-Host "  SKIP: $enabledName (exists)" -ForegroundColor Yellow
        } else {
            $ssBody = @{
                name = $enabledName
                powerpagecomponenttype = 9
                content = (@{ value = 'true'; source = 0; websiteid = $websiteId } | ConvertTo-Json -Compress)
                'powerpagesiteid@odata.bind' = "/powerpagesites($websiteId)"
            } | ConvertTo-Json -Depth 5
            try {
                Invoke-RestMethod -Uri "$apiBase/powerpagecomponents" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($ssBody)) -Headers $h | Out-Null
                Write-Host "  CREATED: $enabledName" -ForegroundColor Green
            } catch { Write-Host "  ERROR: $($_.ErrorDetails.Message)" -ForegroundColor Red }

            $ssBody2 = @{
                name = $fieldsName
                powerpagecomponenttype = 9
                content = (@{ value = '*'; source = 0; websiteid = $websiteId } | ConvertTo-Json -Compress)
                'powerpagesiteid@odata.bind' = "/powerpagesites($websiteId)"
            } | ConvertTo-Json -Depth 5
            try {
                Invoke-RestMethod -Uri "$apiBase/powerpagecomponents" -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($ssBody2)) -Headers $h | Out-Null
                Write-Host "  CREATED: $fieldsName" -ForegroundColor Green
            } catch { Write-Host "  ERROR: $($_.ErrorDetails.Message)" -ForegroundColor Red }
        }
    }

    Write-Host "`n=== SCHEMA COMPLETE ===" -ForegroundColor Green
}
