. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
Connect 'https://org06f5de0b.crm.dynamics.com/'
$OrgUrl = 'https://org06f5de0b.crm.dynamics.com/api/data/v9.2'
$sites = (Invoke-RestMethod -Uri "$OrgUrl/powerpagesites?`$select=powerpagesiteid,name" -Headers $baseHeaders).value
foreach ($s in $sites) {
    Write-Host "  $($s.name) | ID: $($s.powerpagesiteid)" -ForegroundColor Cyan
}
