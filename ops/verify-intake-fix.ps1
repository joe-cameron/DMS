# Verify the audience field was updated
$t = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "4869ceba-68d5-4d98-b381-41fab6702c34"

$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h

$session = $flow.properties.definition.actions.Create_Session_Portal.inputs.authentication.audience
$intake = $flow.properties.definition.actions.Create_Property_Intakes.actions.Create_Intake_Record.inputs.authentication.audience

Write-Output "Create_Session_Portal audience: $session"
Write-Output "Create_Intake_Record audience:  $intake"

if ($session -match '/$' -and $intake -match '/$') {
    Write-Output ""
    Write-Output "VERIFIED: Both audiences have trailing slash"
} else {
    Write-Output ""
    Write-Output "WARNING: Trailing slash missing on one or both"
}
