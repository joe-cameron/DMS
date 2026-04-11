. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'
Invoke-DataverseCommands {
    $f = Invoke-RestMethod -Uri "$OrgUrl/workflows(5e5ffeb9-c722-f111-8341-7ced8d709731)?`$select=primaryentity,category,type,scope,languagecode,mode,uniquename" -Headers $baseHeaders
    $f.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Name -notmatch '@odata' } | ForEach-Object { Write-Host "$($_.Name) = $($_.Value)" }
}
