$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$flowId = '71c2aef7-fd34-f111-88b3-000d3a308bc8'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'; 'If-Match' = '*' }

# 1. Read current clientdata
$getUri = "$orgUrl/api/data/v9.2/workflows($flowId)?`$select=workflowid,name,clientdata"
$flow = Invoke-RestMethod -Uri $getUri -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$rawClientData = $flow.clientdata

# Backup
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "C:/DCFG/scripts/code-review/_optionb-4-flow-backup-$stamp.json"
Set-Content -Path $backup -Value $rawClientData -Encoding UTF8
Write-Host "Backup written: $backup"

$cd = $rawClientData | ConvertFrom-Json -Depth 50

# 2. Locate trigger, modify filterexpression only
$triggers  = $cd.properties.definition.triggers
$triggerNm = ($triggers.PSObject.Properties | Select-Object -First 1).Name
$trg       = $triggers.$triggerNm
$oldFilter = $trg.inputs.parameters.'subscriptionRequest/filterexpression'
$newFilter = 'dcfg_request_type eq 100000004 and dcfg_status eq 100000000'

if ($oldFilter -ne 'dcfg_request_type eq 100000002 and dcfg_status eq 100000000') {
    Write-Host "ABORT: unexpected current filter: $oldFilter" -ForegroundColor Red
    exit 1
}

Write-Host "Old filter: $oldFilter"
Write-Host "New filter: $newFilter"

$trg.inputs.parameters.'subscriptionRequest/filterexpression' = $newFilter

# 3. Serialize back with matching depth
$newClientData = $cd | ConvertTo-Json -Depth 50 -Compress

# 4. PATCH
$patchUri = "$orgUrl/api/data/v9.2/workflows($flowId)"
$body = @{ clientdata = $newClientData } | ConvertTo-Json -Depth 50
Write-Host "PATCH clientdata..."
Invoke-RestMethod -Uri $patchUri -Headers $h -Method Patch -Body $body | Out-Null
Write-Host "  Patched."

# 5. Verify
$verify = Invoke-RestMethod -Uri $getUri -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$cd2    = $verify.clientdata | ConvertFrom-Json -Depth 50
$trg2   = $cd2.properties.definition.triggers.$triggerNm
$fe2    = $trg2.inputs.parameters.'subscriptionRequest/filterexpression'
Write-Host ""
Write-Host "Verified filter: $fe2"
if ($fe2 -eq $newFilter) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "MISMATCH" -ForegroundColor Red }
