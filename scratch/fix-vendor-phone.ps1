. C:\dcfg\PowerApps-Samples\dataverse\webapi\PS\Core.ps1
Connect 'https://org06f5de0b.crm.dynamics.com/'

# Find ALL fields with source_text "Vendor Phone" across all templates
$fields = (Invoke-RestMethod -Uri ($baseURI + "dcfg_template_fields?`$filter=dcfg_source_text eq 'Vendor Phone'&`$select=dcfg_template_fieldid,dcfg_source_text,dcfg_dataverse_path,_dcfg_template_id_value") -Headers $baseHeaders).value
Write-Host "Found $($fields.Count) 'Vendor Phone' mappings"
foreach ($f in $fields) {
    Write-Host "  ID: $($f.dcfg_template_fieldid) Path: $($f.dcfg_dataverse_path) Template: $($f._dcfg_template_id_value)"
    if ($f.dcfg_dataverse_path -eq 'dcfg_signer_title') {
        Write-Host "  -> FIXING: dcfg_signer_title -> dcfg_vendor.dcfg_phone"
        $body = @{ dcfg_dataverse_path = 'dcfg_vendor.dcfg_phone' } | ConvertTo-Json
        Invoke-RestMethod -Method Patch -Uri ($baseURI + "dcfg_template_fields($($f.dcfg_template_fieldid))") -Headers $baseHeaders -Body $body -ContentType 'application/json'
        Write-Host "  OK"
    }
}
