$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0' }

# 1. InsertOptionValue (unbound action) — scoped via AttributeLogicalName + EntityLogicalName
$actionUri = "$orgUrl/api/data/v9.2/InsertOptionValue"
$body = @{
    EntityLogicalName    = 'dcfg_document_request'
    AttributeLogicalName = 'dcfg_request_type'
    Value                = 100000004
    Label                = @{
        '@odata.type'          = 'Microsoft.Dynamics.CRM.Label'
        LocalizedLabels        = @(
            @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'
                Label         = 'Template Upload'
                LanguageCode  = 1033
            }
        )
        UserLocalizedLabel = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'
            Label         = 'Template Upload'
            LanguageCode  = 1033
        }
    }
} | ConvertTo-Json -Depth 10

Write-Host "POST InsertOptionValue..."
$resp = Invoke-RestMethod -Uri $actionUri -Headers $h -Method Post -Body $body
Write-Host "  NewOptionValue: $resp"

# 2. PublishXml for the entity
$pubUri  = "$orgUrl/api/data/v9.2/PublishXml"
$pubBody = @{ ParameterXml = '<importexportxml><entities><entity>dcfg_document_request</entity></entities></importexportxml>' } | ConvertTo-Json
Write-Host "POST PublishXml..."
Invoke-RestMethod -Uri $pubUri -Headers $h -Method Post -Body $pubBody | Out-Null
Write-Host "  Published."

# 3. Verify
Start-Sleep -Seconds 1
$verifyUri = "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_document_request')/Attributes(LogicalName='dcfg_request_type')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet"
$r = Invoke-RestMethod -Uri $verifyUri -Headers $h
Write-Host ""
Write-Host "Verified Options:"
foreach ($opt in $r.OptionSet.Options) {
    Write-Host ("  {0}  {1}" -f $opt.Value, $opt.Label.UserLocalizedLabel.Label)
}
