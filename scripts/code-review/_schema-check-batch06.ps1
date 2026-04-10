$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

function Check { param($Entity,$Col)
    $uri = "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='$Entity')/Attributes(LogicalName='$Col')?`$select=LogicalName,AttributeType"
    try { $r = Invoke-RestMethod -Uri $uri -Headers $h; "OK   : {0}.{1} ({2})" -f $Entity,$Col,$r.AttributeType | Write-Host -ForegroundColor Green
    } catch { "MISS : {0}.{1}" -f $Entity,$Col | Write-Host -ForegroundColor Red }
}

Write-Host "=== 0279/0293: Vendor singular vs plural 'trade' ==="
Check 'dcfg_vendor' 'dcfg_trade'
Check 'dcfg_vendor' 'dcfg_trades'
Check 'dcfg_vendor' 'dcfg_contact_name'
Check 'dcfg_vendor' 'dcfg_primary_contact'

Write-Host ""
Write-Host "=== 0298: Amendment financial columns on dcfg_contract ==="
foreach ($c in @('dcfg_original_amount','dcfg_prev_changes_amount','dcfg_current_amount','dcfg_change_amount','dcfg_approved_amount','dcfg_amendment_amount','dcfg_amendment_value','dcfg_contract_fee_base')) {
    Check 'dcfg_contract' $c
}

Write-Host ""
Write-Host "=== 0299: Vendor address composite fields ==="
foreach ($c in @('address1_line1','address1_city_state_zip','address1_composite','address1_city','address1_stateorprovince','address1_postalcode')) {
    Check 'dcfg_vendor' $c
}

Write-Host ""
Write-Host "=== Full dcfg_vendor dcfg_* columns containing 'trade' or 'contact' ==="
$uri = "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_vendor')/Attributes?`$select=LogicalName,AttributeType"
$cols = (Invoke-RestMethod -Uri $uri -Headers $h).value
$cols | Where-Object { $_.LogicalName -match '(trade|contact)' } | Sort-Object LogicalName | ForEach-Object {
    "  {0,-45} {1}" -f $_.LogicalName, $_.AttributeType
}
