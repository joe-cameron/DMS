# Get failed action details from the most recent run
$t = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "4869ceba-68d5-4d98-b381-41fab6702c34"

# Get latest run
$runs = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId/runs?api-version=2016-11-01&`$top=1" -Headers $h
$runId = $runs.value[0].name
$runStatus = $runs.value[0].properties.status
Write-Output "Run: $runId | Status: $runStatus"

# Get actions from this run
$actions = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId/runs/$runId/actions?api-version=2016-11-01" -Headers $h

foreach ($a in $actions.value) {
    $aName = $a.name
    $aStatus = $a.properties.status
    $aCode = $a.properties.code
    Write-Output ""
    Write-Output "Action: $aName | Status: $aStatus | Code: $aCode"

    if ($aStatus -eq 'Failed') {
        $error_obj = $a.properties.error
        if ($error_obj) {
            Write-Output "  Error Code: $($error_obj.code)"
            Write-Output "  Error Message: $($error_obj.message)"
        }

        # Get output details
        $outputsLink = $a.properties.outputsLink
        if ($outputsLink -and $outputsLink.uri) {
            try {
                $outputs = Invoke-RestMethod -Uri $outputsLink.uri -Method Get
                $statusCode = $outputs.statusCode
                $body = $outputs.body | ConvertTo-Json -Depth 5
                Write-Output "  HTTP Status: $statusCode"
                Write-Output "  Response Body: $body"
            } catch {
                Write-Output "  Could not fetch outputs: $($_.Exception.Message)"
            }
        }

        # Also check inputs
        $inputsLink = $a.properties.inputsLink
        if ($inputsLink -and $inputsLink.uri) {
            try {
                $inputs = Invoke-RestMethod -Uri $inputsLink.uri -Method Get
                $uri = $inputs.uri
                $auth = $inputs.authentication
                Write-Output "  Request URI: $uri"
                Write-Output "  Auth Type: $($auth.type)"
                Write-Output "  Auth Audience: $($auth.audience)"
            } catch {
                Write-Output "  Could not fetch inputs: $($_.Exception.Message)"
            }
        }
    }
}
