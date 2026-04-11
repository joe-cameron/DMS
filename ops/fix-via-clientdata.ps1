# Deactivate flow, update clientdata, reactivate, publish
$baseUrl = 'https://org06f5de0b.crm.dynamics.com'
$t = Get-AzAccessToken -ResourceUrl "$baseUrl/" -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $t.Token).Password
$dh = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0' }

$workflowId = 'f8e79440-d223-f111-8341-7ced8d7092ad'

# Step 1: Deactivate (statecode=0 = Draft/Off)
Write-Output "Deactivating flow..."
$deactivate = @{ statecode = 0; statuscode = 1 } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/workflows($workflowId)" -Headers $dh -Method Patch -Body ([System.Text.Encoding]::UTF8.GetBytes($deactivate))
    Write-Output "Deactivated"
} catch {
    $err = $_.ErrorDetails.Message
    if (-not $err) { $err = $_.Exception.Message }
    Write-Output "Deactivate: $err"
}

Start-Sleep -Seconds 2

# Step 2: Read current clientdata and fix
Write-Output ""
Write-Output "Reading clientdata..."
$wf = Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/workflows($workflowId)?`$select=clientdata,statecode" -Headers $dh
Write-Output "StateCode: $($wf.statecode)"
$cdObj = $wf.clientdata | ConvertFrom-Json
$def = $cdObj.properties.definition

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

# Step 3: Patch clientdata
$newClientData = $cdObj | ConvertTo-Json -Depth 100 -Compress
$patchBody = @{ clientdata = $newClientData } | ConvertTo-Json -Depth 2 -Compress

Write-Output "Patching clientdata..."
try {
    Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/workflows($workflowId)" -Headers $dh -Method Patch -Body ([System.Text.Encoding]::UTF8.GetBytes($patchBody))
    Write-Output "SUCCESS: clientdata patched"
} catch {
    $err = $_.ErrorDetails.Message
    if (-not $err) { $err = $_.Exception.Message }
    Write-Output "Patch: $err"
}

# Step 4: Reactivate
Write-Output ""
Write-Output "Reactivating..."
$activate = @{ statecode = 1; statuscode = 2 } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/workflows($workflowId)" -Headers $dh -Method Patch -Body ([System.Text.Encoding]::UTF8.GetBytes($activate))
    Write-Output "Activated"
} catch {
    $err = $_.ErrorDetails.Message
    if (-not $err) { $err = $_.Exception.Message }
    Write-Output "Activate: $err"
}

# Step 5: Verify
Write-Output ""
$t2 = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/" -AsSecureString
$token2 = [System.Net.NetworkCredential]::new('', $t2.Token).Password
$fh = @{ Authorization = "Bearer $token2"; Accept = 'application/json' }
$envId = "6ee0cd74-e2b2-e429-ac4b-27123cd20d19"
$flowId = "42fae156-8575-9ef8-4224-15e286ab5264"

$flow2 = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$envId/flows/$flowId`?api-version=2016-11-01" -Headers $fh
$val = $flow2.properties.definition.actions.Switch_Template.cases.Bancroft_Blanket_Work_Order.actions.Set_Doc_Bancroft_Blanket_WO.inputs.value
Write-Output "Set_Doc_Bancroft_Blanket_WO: $val"
Write-Output "Flow state: $($flow2.properties.state)"
