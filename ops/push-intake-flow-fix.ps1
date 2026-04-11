# Push trailing-slash fix to intake flow in Prod
$t = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "4869ceba-68d5-4d98-b381-41fab6702c34"

# Step 1: Read current flow to preserve trigger and connections
Write-Output "Reading current flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h

# Step 2: Load updated definition from local file
$newDef = Get-Content "C:\DCFG\Flows\Scripts\flow_intake_setup_def.json" -Raw | ConvertFrom-Json

# Step 3: Preserve the existing trigger (NEVER overwrite triggers)
$currentTrigger = $flow.properties.definition.triggers
$newDef.triggers = $currentTrigger

# Step 4: Preserve parameters from current flow
$newDef.parameters = $flow.properties.definition.parameters

# Step 5: Build the PATCH payload
$payload = @{
    properties = @{
        definition = $newDef
    }
} | ConvertTo-Json -Depth 50

# Step 6: Push the update
Write-Output "Pushing updated definition..."
try {
    $result = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h -Method Patch -Body $payload
    Write-Output "SUCCESS: Flow updated"
    Write-Output "Flow state: $($result.properties.state)"
} catch {
    Write-Output "FAILED: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $body = $reader.ReadToEnd()
        Write-Output "Response: $body"
    }
}
