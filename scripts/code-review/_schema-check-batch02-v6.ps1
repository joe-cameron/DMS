$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

function Check-Column { param($Entity,$Col)
    $uri = "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='$Entity')/Attributes(LogicalName='$Col')?`$select=LogicalName,AttributeType"
    try { $r = Invoke-RestMethod -Uri $uri -Headers $h
        Write-Host ("OK   : {0,-25}.{1,-30} {2}" -f $Entity,$Col,$r.AttributeType) -ForegroundColor Green; return $true
    } catch {
        Write-Host ("MISS : {0,-25}.{1,-30}" -f $Entity,$Col) -ForegroundColor Red; return $false
    }
}

Write-Host "=== Templates findings — replacement columns ==="
Check-Column 'dcfg_contract' 'dcfg_contract_fee'      | Out-Null
Check-Column 'dcfg_contract' 'dcfg_fee'               | Out-Null
Check-Column 'dcfg_contract' 'dcfg_amendment_sequence'| Out-Null
Check-Column 'dcfg_contract' 'dcfg_amendment_no'      | Out-Null
Check-Column 'dcfg_contract' 'dcfg_amendment_number'  | Out-Null

Write-Host ""
Write-Host "=== List ALL dcfg_* columns on dcfg_contract for reference ==="
$uri = "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_contract')/Attributes?`$select=LogicalName,AttributeType"
$cols = (Invoke-RestMethod -Uri $uri -Headers $h).value
$cols | Where-Object { $_.LogicalName -like 'dcfg_*' } | Sort-Object LogicalName | ForEach-Object { "  {0,-45} {1}" -f $_.LogicalName, $_.AttributeType }
