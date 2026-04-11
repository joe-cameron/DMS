$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$flowId = '71c2aef7-fd34-f111-88b3-000d3a308bc8'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$hRead = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$hWrite = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'; 'If-Match' = '*' }

$uri = "$orgUrl/api/data/v9.2/workflows($flowId)"
$getUri = "$uri`?`$select=workflowid,name,statecode,statuscode"

Write-Host "Initial state:"
$r = Invoke-RestMethod -Uri $getUri -Headers $hRead
Write-Host "  statecode=$($r.statecode) statuscode=$($r.statuscode)"

Write-Host "PATCH -> statecode=0 (Draft), statuscode=1..."
Invoke-RestMethod -Uri $uri -Headers $hWrite -Method Patch -Body (@{ statecode = 0; statuscode = 1 } | ConvertTo-Json) | Out-Null
Start-Sleep -Seconds 2
$r = Invoke-RestMethod -Uri $getUri -Headers $hRead
Write-Host "  statecode=$($r.statecode) statuscode=$($r.statuscode)"

Write-Host "PATCH -> statecode=1 (Activated), statuscode=2..."
Invoke-RestMethod -Uri $uri -Headers $hWrite -Method Patch -Body (@{ statecode = 1; statuscode = 2 } | ConvertTo-Json) | Out-Null
Start-Sleep -Seconds 2
$r = Invoke-RestMethod -Uri $getUri -Headers $hRead
Write-Host "  statecode=$($r.statecode) statuscode=$($r.statuscode)"

if ($r.statecode -eq 1) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FLOW NOT ACTIVE" -ForegroundColor Red; exit 1 }
