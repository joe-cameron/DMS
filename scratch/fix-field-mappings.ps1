. C:\dcfg\PowerApps-Samples\dataverse\webapi\PS\Core.ps1
Connect 'https://org06f5de0b.crm.dynamics.com/'

# Find Decades Vendor Agreement template ID
$tpls = (Invoke-RestMethod -Uri ($baseURI + 'dcfg_document_templates?$filter=dcfg_is_active eq true&$select=dcfg_document_templateid,dcfg_name') -Headers $baseHeaders).value
$decVA = $tpls | Where-Object { $_.dcfg_name -eq 'Decades Vendor Agreement' }
$decWO = $tpls | Where-Object { $_.dcfg_name -eq 'Decades Workorder' -or $_.dcfg_name -eq 'Decades Work Order' }

Write-Host "Decades VA: $($decVA.dcfg_document_templateid)"
Write-Host "Decades WO: $($decWO | ForEach-Object { $_.dcfg_name + ' = ' + $_.dcfg_document_templateid })"

# 1. Create 4 new field mappings for Decades VA
$vaId = $decVA.dcfg_document_templateid
$newMappings = @(
    @{ dcfg_source_text = 'Vendor Signature'; dcfg_dataverse_path = '[DOCUSIGN:\Vendor_Signature\]' },
    @{ dcfg_source_text = 'Decades Signature'; dcfg_dataverse_path = '[DOCUSIGN:\Decades_Signature\]' },
    @{ dcfg_source_text = 'Vendor Date Signed'; dcfg_dataverse_path = '[DOCUSIGN:\Vendor_DateSigned\]' },
    @{ dcfg_source_text = 'Decades Datesigned'; dcfg_dataverse_path = '[DOCUSIGN:\Decades_DateSigned\]' }
)

foreach ($m in $newMappings) {
    $body = @{
        dcfg_source_text = $m.dcfg_source_text
        dcfg_dataverse_path = $m.dcfg_dataverse_path
        'dcfg_template_id@odata.bind' = "/dcfg_document_templates($vaId)"
    } | ConvertTo-Json
    Write-Host "Creating: `"$($m.dcfg_source_text)`" -> $($m.dcfg_dataverse_path)"
    try {
        Invoke-RestMethod -Method Post -Uri ($baseURI + 'dcfg_template_fields') -Headers $baseHeaders -Body $body -ContentType 'application/json'
        Write-Host "  OK"
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)"
    }
}

# 2. Fix "Vendor Phone" mapping on Decades Workorder — find and update
foreach ($wo in $decWO) {
    $woId = $wo.dcfg_document_templateid
    $fields = (Invoke-RestMethod -Uri ($baseURI + "dcfg_template_fields?`$filter=_dcfg_template_id_value eq $woId and dcfg_source_text eq 'Vendor Phone'&`$select=dcfg_template_fieldid,dcfg_source_text,dcfg_dataverse_path") -Headers $baseHeaders).value
    foreach ($f in $fields) {
        if ($f.dcfg_dataverse_path -eq 'dcfg_signer_title') {
            Write-Host "`nFixing Vendor Phone on $($wo.dcfg_name): dcfg_signer_title -> dcfg_vendor.dcfg_phone"
            $patchBody = @{ dcfg_dataverse_path = 'dcfg_vendor.dcfg_phone' } | ConvertTo-Json
            Invoke-RestMethod -Method Patch -Uri ($baseURI + "dcfg_template_fields($($f.dcfg_template_fieldid))") -Headers $baseHeaders -Body $patchBody -ContentType 'application/json'
            Write-Host "  OK"
        }
    }
}

Write-Host "`nDone."
