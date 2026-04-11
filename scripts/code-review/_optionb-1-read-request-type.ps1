$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

$uri = "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_document_request')/Attributes(LogicalName='dcfg_request_type')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet"
$r = Invoke-RestMethod -Uri $uri -Headers $h

Write-Host "Attribute: $($r.LogicalName)"
Write-Host "OptionSet Name: $($r.OptionSet.Name)"
Write-Host "MetadataId: $($r.OptionSet.MetadataId)"
Write-Host ""
Write-Host "Current Options:"
foreach ($opt in $r.OptionSet.Options) {
    Write-Host ("  {0}  {1}" -f $opt.Value, $opt.Label.UserLocalizedLabel.Label)
}
