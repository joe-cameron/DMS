$baseUrl = 'https://orgf625b080.crm.dynamics.com'

# Get token for Dataverse
$t = Get-AzAccessToken -ResourceUrl "$baseUrl/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
Write-Output "Token acquired (length=$($token.Length))"

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}

$tables = @(
    'dcfg_intake_session',
    'dcfg_property_intake',
    'dcfg_intake_vendor',
    'dcfg_intake_authorized_user',
    'dcfg_onboarding_checklist'
)

foreach ($table in $tables) {
    $url = "$baseUrl/api/data/v9.2/EntityDefinitions?`$filter=LogicalName eq '$table'&`$select=LogicalName,EntitySetName"
    try {
        $result = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        if ($result.value.Count -eq 0) {
            Write-Output "$table : NOT FOUND"
        } else {
            Write-Output "$table : EXISTS ($($result.value[0].EntitySetName))"
        }
    } catch {
        Write-Output "$table : ERROR - $($_.Exception.Message)"
    }
}
