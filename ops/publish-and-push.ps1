# Publish the specific workflow component, then push
$baseUrl = 'https://org06f5de0b.crm.dynamics.com'
$t = Get-AzAccessToken -ResourceUrl "$baseUrl/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$dh = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json' }

$workflowId = 'f8e79440-d223-f111-8341-7ced8d7092ad'

# Check the workflow record
Write-Output "Checking workflow record..."
$wf = Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/workflows($workflowId)?`$select=name,statecode,statuscode,componentstate" -Headers $dh
Write-Output "Name: $($wf.name)"
Write-Output "StateCode: $($wf.statecode) StatusCode: $($wf.statuscode)"
Write-Output "ComponentState: $($wf.componentstate)"

# Try PublishXml for this specific workflow
Write-Output ""
Write-Output "Publishing specific workflow..."
$publishXml = @{
    ParameterXml = "<importexportxml><workflows><workflow>{$workflowId}</workflow></workflows></importexportxml>"
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/PublishXml" -Headers $dh -Method Post -Body $publishXml
    Write-Output "PublishXml: Success"
} catch {
    $err = $_.ErrorDetails.Message
    if (-not $err) { $err = $_.Exception.Message }
    Write-Output "PublishXml: $err"
}

Start-Sleep -Seconds 3

# Check component state after publish
$wf2 = Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/workflows($workflowId)?`$select=name,statecode,statuscode,componentstate" -Headers $dh
Write-Output "After publish — ComponentState: $($wf2.componentstate)"

# Now try the Flow API push
$t2 = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token2 = [System.Net.NetworkCredential]::new('', $t2.Token).Password
$fh = @{ Authorization = "Bearer $token2"; Accept = 'application/json'; 'Content-Type' = 'application/json' }

$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "42fae156-8575-9ef8-4224-15e286ab5264"

Write-Output ""
Write-Output "Reading flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $fh
$def = $flow.properties.definition

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
        $setAction = $caseProp.Value.actions.($pairs[$caseName][0])
        if ($setAction) {
            $setAction.inputs | Add-Member -NotePropertyName 'value' -NotePropertyValue "@outputs('$($pairs[$caseName][1])')?['body']" -Force
            $fixed++
        }
    }
}
Write-Output "Fixed $fixed / 16"

$payload = @{ properties = @{ definition = $def } }
$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 100 -Compress))
Write-Output "Pushing ($($jsonBytes.Length) bytes)..."

try {
    $result = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $fh -Method Patch -Body $jsonBytes
    Write-Output "SUCCESS: state=$($result.properties.state)"

    # Verify
    $val = $result.properties.definition.actions.Switch_Template.cases.Bancroft_Blanket_Work_Order.actions.Set_Doc_Bancroft_Blanket_WO.inputs.value
    Write-Output "Verify Set_Doc_Bancroft_Blanket_WO: $val"
} catch {
    $err = $_.ErrorDetails.Message
    if (-not $err) { $err = $_.Exception.Message }
    Write-Output "FAILED: $err"
}
