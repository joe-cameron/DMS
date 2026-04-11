# Fix all Set_Doc_* actions with correct value expressions
$t = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$h = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "42fae156-8575-9ef8-4224-15e286ab5264"

# Step 1: Stop flow to clear unpublished state
Write-Output "Stopping flow to clear unpublished state..."
try {
    Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId/stop?api-version=2016-11-01" -Headers $h -Method Post | Out-Null
    Write-Output "Stopped"
    Start-Sleep -Seconds 3
} catch {
    Write-Output "Stop note: $($_.ErrorDetails.Message)"
}

# Step 2: Read flow
Write-Output "Reading flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h

$def = $flow.properties.definition

# Step 3: Find Switch and fix Set_Doc actions
$switch = $null
foreach ($prop in $def.actions.PSObject.Properties) {
    if ($prop.Value.type -eq 'Switch') { $switch = $prop.Value; break }
}

$pairs = @{
    'Bancroft_Blanket_Work_Order' = @('Set_Doc_Bancroft_Blanket_WO', 'Populate_Bancroft_Blanket_WO')
    'Bancroft_Blanket_WO_Amendment' = @('Set_Doc_Bancroft_Blanket_WO_Amend', 'Populate_Bancroft_Blanket_WO_Amend')
    'Bancroft_Work_Order' = @('Set_Doc_Bancroft_WO', 'Populate_Bancroft_WO')
    'Bancroft_Work_Order_Amendment' = @('Set_Doc_Bancroft_WO_Amendment', 'Populate_Bancroft_WO_Amendment')
    'Decades_Work_Order' = @('Set_Doc_Decades_WO', 'Populate_Decades_WO')
    'Decades_Work_Order_Amendment' = @('Set_Doc_Decades_WO_Amendment', 'Populate_Decades_WO_Amendment')
    'Decades_MSA' = @('Set_Doc_Decades_MSA', 'Populate_Decades_MSA')
    'Decades_Exhibit_A_Basic_A' = @('Set_Doc_Decades_Exhibit_A_Basic_A', 'Populate_Decades_Exhibit_A_Basic_A')
    'Decades_Exhibit_A_Optimized_C' = @('Set_Doc_Decades_Exhibit_A_Optimized_C', 'Populate_Decades_Exhibit_A_Optimized_C')
    'Decades_Exhibit_A_Concierge_B' = @('Set_Doc_Decades_Exhibit_A_Concierge_B', 'Populate_Decades_Exhibit_A_Concierge_B')
    'Decades_Exhibit_B_Location_List' = @('Set_Doc_Decades_Exhibit_B_Location_List', 'Populate_Decades_Exhibit_B_Location_List')
    'Decades_Exhibit_C_Fee_Schedule' = @('Set_Doc_Decades_Exhibit_C', 'Populate_Decades_Exhibit_C')
    'Decades_Exhibit_D_Insurance' = @('Set_Doc_Decades_Exhibit_D_Insurance', 'Populate_Decades_Exhibit_D_Insurance')
    'Bancroft_Exhibit_A_Basic_A' = @('Set_Doc_Bancroft_Exhibit_A_Basic_A', 'Populate_Bancroft_Exhibit_A_Basic_A')
    'Bancroft_Exhibit_A_Concierge_B' = @('Set_Doc_Bancroft_Exhibit_A_Concierge_B', 'Populate_Bancroft_Exhibit_A_Concierge_B')
    'Bancroft_Exhibit_A_Optimized_C' = @('Set_Doc_Bancroft_Exhibit_A_Optimized_C', 'Populate_Bancroft_Exhibit_A_Optimized_C')
}

$fixed = 0
foreach ($caseProp in $switch.cases.PSObject.Properties) {
    $caseName = $caseProp.Name
    if ($pairs.ContainsKey($caseName)) {
        $setName = $pairs[$caseName][0]
        $popName = $pairs[$caseName][1]
        $setAction = $caseProp.Value.actions.$setName
        if ($setAction) {
            $expr = "@outputs('$popName')?['body']"
            $setAction.inputs | Add-Member -NotePropertyName 'value' -NotePropertyValue $expr -Force
            $fixed++
            Write-Output "Fixed: $setName -> $popName"
        }
    }
}
Write-Output "Fixed $fixed / 16"

# Step 4: Build payload — definition only
$payload = @{ properties = @{ definition = $def } }
$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 100 -Compress))
Write-Output "Payload: $($jsonBytes.Length) bytes"

# Step 5: Push
Write-Output "Pushing..."
try {
    $result = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h -Method Patch -Body $jsonBytes
    Write-Output "SUCCESS: pushed"
} catch {
    $err = $_.ErrorDetails.Message
    if (-not $err) { $err = $_.Exception.Message }
    Write-Output "Push result: $err"
}

# Step 6: Start flow
Write-Output "Starting flow..."
Start-Sleep -Seconds 2
try {
    Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId/start?api-version=2016-11-01" -Headers $h -Method Post | Out-Null
    Write-Output "Started"
} catch {
    Write-Output "Start: $($_.ErrorDetails.Message)"
}

# Step 7: Verify
$flow2 = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $h
Write-Output "Final state: $($flow2.properties.state)"

# Quick verify one value
$val = $flow2.properties.definition.actions.Switch_Template.cases.Bancroft_Blanket_Work_Order.actions.Set_Doc_Bancroft_Blanket_WO.inputs.value
Write-Output "Sample check - Set_Doc_Bancroft_Blanket_WO value: $val"
