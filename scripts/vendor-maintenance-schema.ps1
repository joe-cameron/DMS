# scripts/vendor-maintenance-schema.ps1
# Creates 6 new columns on dcfg_vendor + verifies
# Run: pwsh -File scripts/vendor-maintenance-schema.ps1

. "$PSScriptRoot\..\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"

$org = "https://org0c17e98d.crm.dynamics.com"
Connect $org

$tableName = "dcfg_vendor"
$solutionName = "DCFGSystemTest"

$columns = @(
    @{ SchemaName = "dcfg_msa_file_url";             Type = "String";   MaxLength = 2000; DisplayName = "MSA File URL" },
    @{ SchemaName = "dcfg_w9_file_url";              Type = "String";   MaxLength = 2000; DisplayName = "W9 File URL" },
    @{ SchemaName = "dcfg_msa_upload_date";          Type = "DateTime"; DisplayName = "MSA Upload Date" },
    @{ SchemaName = "dcfg_w9_upload_date";           Type = "DateTime"; DisplayName = "W9 Upload Date" },
    @{ SchemaName = "dcfg_coi_upload_date";          Type = "DateTime"; DisplayName = "COI Upload Date" },
    @{ SchemaName = "dcfg_insurance_effective_date";  Type = "DateTime"; DisplayName = "Insurance Effective Date" }
)

$created = 0
$existed = 0
$failed = 0

foreach ($col in $columns) {
    Write-Host "Creating $($col.SchemaName)..." -ForegroundColor Cyan

    if ($col.Type -eq "String") {
        $body = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            SchemaName    = $col.SchemaName
            DisplayName   = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = $col.DisplayName
                    LanguageCode  = 1033
                })
            }
            RequiredLevel = @{ Value = "None" }
            MaxLength     = $col.MaxLength
            FormatName    = @{ Value = "Url" }
        }
    } else {
        $body = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
            SchemaName    = $col.SchemaName
            DisplayName   = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = $col.DisplayName
                    LanguageCode  = 1033
                })
            }
            RequiredLevel    = @{ Value = "None" }
            Format           = "DateOnly"
            DateTimeBehavior = @{ Value = "UserLocal" }
        }
    }

    try {
        Invoke-RestMethod `
            -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='$tableName')/Attributes" `
            -Method Post `
            -Headers ($baseHeaders + @{ "MSCRM.SolutionUniqueName" = $solutionName }) `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ContentType "application/json"
        Write-Host "  Created: $($col.SchemaName)" -ForegroundColor Green
        $created++
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 409 -or ($_.Exception.Message -match "already exists")) {
            Write-Host "  Already exists: $($col.SchemaName)" -ForegroundColor Yellow
            $existed++
        } else {
            Write-Host "  FAILED: $($col.SchemaName) - $_" -ForegroundColor Red
            $failed++
        }
    }
    Start-Sleep -Seconds 2
}

Write-Host "`n=== RESULTS ===" -ForegroundColor White
Write-Host "Created: $created | Already existed: $existed | Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

# Verify
Write-Host "`nVerifying columns..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
$verify = Invoke-RestMethod `
    -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='$tableName')/Attributes?`$select=SchemaName,AttributeType&`$filter=SchemaName eq 'dcfg_msa_file_url' or SchemaName eq 'dcfg_w9_file_url' or SchemaName eq 'dcfg_msa_upload_date' or SchemaName eq 'dcfg_w9_upload_date' or SchemaName eq 'dcfg_coi_upload_date' or SchemaName eq 'dcfg_insurance_effective_date'" `
    -Headers $baseHeaders

$found = $verify.value | ForEach-Object { $_.SchemaName }
Write-Host "Found $($found.Count)/6 columns: $($found -join ', ')" -ForegroundColor $(if ($found.Count -eq 6) { "Green" } else { "Yellow" })
