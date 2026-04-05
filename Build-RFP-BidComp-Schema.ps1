<#
.SYNOPSIS
    Creates the RFP + Bid Comp Dataverse tables, columns, relationships, permissions, and site settings.
.DESCRIPTION
    Per spec Section 13.2. Idempotent — safe to run multiple times.
    Uses direct Dataverse Web API (proven pattern from Create-LocationType-Portal.ps1).
#>

$ErrorActionPreference = "Stop"
$OrgUrl = "https://org0c17e98d.crm.dynamics.com/"
$tokenObj = Get-AzAccessToken -ResourceUrl $OrgUrl -AsSecureString
$token = [System.Net.NetworkCredential]::new("", $tokenObj.Token).Password
$h = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; Accept = "application/json" }
$hSol = $h + @{ "MSCRM.SolutionUniqueName" = "DCFGSystemTest" }
$api = "${OrgUrl}api/data/v9.2"
$WebsiteId = 'a150bd53-7fbc-423d-a1ad-dd653ab4c435'

function New-Label($text) {
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"; Label = $text; LanguageCode = 1033 }) }
}

# --- Helpers ---

function Test-TableExists([string]$name) {
    try { Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName=%27$name%27)?`$select=LogicalName" -Headers $h | Out-Null; $true } catch { $false }
}

function Test-ColExists([string]$table, [string]$col) {
    try { Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName=%27$table%27)/Attributes(LogicalName=%27$col%27)?`$select=LogicalName" -Headers $h | Out-Null; $true } catch { $false }
}

function New-DcfgTable([string]$name, [string]$display, [string]$plural) {
    if (Test-TableExists $name) { Write-Host "  EXISTS: $name" -ForegroundColor Yellow; return }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName = $name; DisplayName = (New-Label $display); DisplayCollectionName = (New-Label $plural)
        HasNotes = $false; HasActivities = $false; OwnershipType = "OrganizationOwned"; PrimaryNameAttribute = "dcfg_name"
        Attributes = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            SchemaName = "dcfg_name"; DisplayName = (New-Label "Name")
            RequiredLevel = @{ Value = "ApplicationRequired" }; MaxLength = 200; IsPrimaryName = $true
        })
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions" -Headers $hSol -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
    Write-Host "  CREATED: $name" -ForegroundColor Green
    Start-Sleep -Seconds 3  # Let Dataverse propagate
}

function Add-Col([string]$table, [string]$col, [string]$label, [string]$type, [int]$len = 200) {
    if (Test-ColExists $table $col) { Write-Host "    EXISTS: $col" -ForegroundColor Yellow; return }
    $b = @{ SchemaName = $col; DisplayName = (New-Label $label); RequiredLevel = @{ Value = "None" } }
    switch ($type) {
        "string"   { $b["@odata.type"] = "Microsoft.Dynamics.CRM.StringAttributeMetadata"; $b.MaxLength = $len }
        "memo"     { $b["@odata.type"] = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"; $b.MaxLength = 1048576 }
        "money"    { $b["@odata.type"] = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"; $b.PrecisionSource = 2 }
        "int"      { $b["@odata.type"] = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"; $b.MinValue = -2147483648; $b.MaxValue = 2147483647 }
        "decimal"  { $b["@odata.type"] = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"; $b.MinValue = -100000000000; $b.MaxValue = 100000000000; $b.Precision = 4 }
        "datetime" { $b["@odata.type"] = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"; $b.Format = "DateAndTime"; $b.DateTimeBehavior = @{ Value = "UserLocal" } }
        "bool"     { $b["@odata.type"] = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"; $b.DefaultValue = $false
                     $b.OptionSet = @{ TrueOption = @{ Value = 1; Label = (New-Label "Yes") }; FalseOption = @{ Value = 0; Label = (New-Label "No") } } }
    }
    $json = $b | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName=%27$table%27)/Attributes" -Headers $hSol -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
    Write-Host "    CREATED: $col ($type)" -ForegroundColor Green
}

function Add-Choice([string]$table, [string]$col, [string]$label, [hashtable[]]$opts) {
    if (Test-ColExists $table $col) { Write-Host "    EXISTS: $col" -ForegroundColor Yellow; return }
    $items = $opts | ForEach-Object { @{ Value = $_.Value; Label = (New-Label $_.Label) } }
    $b = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName = $col; DisplayName = (New-Label $label); RequiredLevel = @{ Value = "None" }
        OptionSet = @{ "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"; IsGlobal = $false; OptionSetType = "Picklist"; Options = $items }
    } | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName=%27$table%27)/Attributes" -Headers $hSol -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($b)) | Out-Null
    Write-Host "    CREATED: $col (choice)" -ForegroundColor Green
}

function Add-Lookup([string]$parent, [string]$child, [string]$col, [string]$label) {
    if (Test-ColExists $child $col) { Write-Host "    EXISTS: $col on $child" -ForegroundColor Yellow; return }
    $rel = "dcfg_$($parent -replace 'dcfg_','')_$($child -replace 'dcfg_','')_$($col -replace 'dcfg_','')"
    if ($rel.Length -gt 100) { $rel = $rel.Substring(0,100) }
    $b = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName = $rel; ReferencedEntity = $parent; ReferencingEntity = $child
        Lookup = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            SchemaName = $col; DisplayName = (New-Label $label); RequiredLevel = @{ Value = "None" }
        }
    } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$api/RelationshipDefinitions" -Headers $hSol -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($b)) | Out-Null
    Write-Host "    CREATED: $col ($parent -> $child)" -ForegroundColor Green
}

# =====================================================================
# STEP 1: Create Tables
# =====================================================================
Write-Host "`n=== STEP 1: Create Tables ===" -ForegroundColor Cyan
New-DcfgTable "dcfg_rfp_package" "RFP Package" "RFP Packages"
New-DcfgTable "dcfg_rfp_project" "RFP Project" "RFP Projects"
New-DcfgTable "dcfg_rfp_vendor" "RFP Vendor" "RFP Vendors"
New-DcfgTable "dcfg_proposal" "Proposal" "Proposals"
New-DcfgTable "dcfg_template_line_item" "Template Line Item" "Template Line Items"
New-DcfgTable "dcfg_project_line_item" "Project Line Item" "Project Line Items"
New-DcfgTable "dcfg_project_factor" "Project Factor" "Project Factors"
New-DcfgTable "dcfg_template_bundle_member" "Template Bundle Member" "Template Bundle Members"

# =====================================================================
# STEP 2: Columns on new tables
# =====================================================================
Write-Host "`n=== STEP 2: Columns on New Tables ===" -ForegroundColor Cyan

Write-Host "`n  dcfg_rfp_package" -ForegroundColor Cyan
Add-Col "dcfg_rfp_package" "dcfg_trades" "Trades" "string" 500
Add-Col "dcfg_rfp_package" "dcfg_scope_description" "Scope Description" "memo"
Add-Col "dcfg_rfp_package" "dcfg_total_estimated_value" "Total Estimated Value" "money"
Add-Col "dcfg_rfp_package" "dcfg_period_cap" "Period Cap" "money"
Add-Col "dcfg_rfp_package" "dcfg_contract_duration_months" "Contract Duration Months" "int"
Add-Col "dcfg_rfp_package" "dcfg_deadline" "Submission Deadline" "datetime"
Add-Col "dcfg_rfp_package" "dcfg_bid_solicited" "Bid Solicited" "bool"
Add-Col "dcfg_rfp_package" "dcfg_bid_received" "Bid Received" "bool"
Add-Col "dcfg_rfp_package" "dcfg_scope_exhibit_drafted" "Scope Exhibit Drafted" "bool"
Add-Col "dcfg_rfp_package" "dcfg_exhibit_b_issued" "Exhibit B Issued" "bool"
Add-Col "dcfg_rfp_package" "dcfg_contract_out" "Contract Out" "bool"
Add-Col "dcfg_rfp_package" "dcfg_contract_fe" "Contract Fully Executed" "bool"
Add-Col "dcfg_rfp_package" "dcfg_submittals_received" "Submittals Received" "bool"
Add-Col "dcfg_rfp_package" "dcfg_scope_items" "Scope Items JSON" "memo"
Add-Col "dcfg_rfp_package" "dcfg_financial_structure" "Financial Structure JSON" "memo"
Add-Col "dcfg_rfp_package" "dcfg_version" "Version" "int"
Add-Col "dcfg_rfp_package" "dcfg_sp_file_ref" "SharePoint File Ref" "string" 500
Add-Col "dcfg_rfp_package" "dcfg_active_flag" "Active" "bool"

Write-Host "`n  dcfg_template_line_item" -ForegroundColor Cyan
Add-Col "dcfg_template_line_item" "dcfg_description" "Description" "string" 500
Add-Col "dcfg_template_line_item" "dcfg_default_qty" "Default Quantity" "decimal"
Add-Col "dcfg_template_line_item" "dcfg_base_rate" "Base Rate" "money"
Add-Col "dcfg_template_line_item" "dcfg_trade" "Trade" "string" 100
Add-Col "dcfg_template_line_item" "dcfg_sequence" "Sequence" "int"
Add-Col "dcfg_template_line_item" "dcfg_active_flag" "Active" "bool"

Write-Host "`n  dcfg_project_line_item" -ForegroundColor Cyan
Add-Col "dcfg_project_line_item" "dcfg_description" "Description" "string" 500
Add-Col "dcfg_project_line_item" "dcfg_quantity" "Quantity" "decimal"
Add-Col "dcfg_project_line_item" "dcfg_unit_rate" "Unit Rate" "money"
Add-Col "dcfg_project_line_item" "dcfg_extended_cost" "Extended Cost" "money"
Add-Col "dcfg_project_line_item" "dcfg_trade" "Trade" "string" 100
Add-Col "dcfg_project_line_item" "dcfg_needs_takeoff" "Needs Takeoff" "bool"
Add-Col "dcfg_project_line_item" "dcfg_sequence" "Sequence" "int"
Add-Col "dcfg_project_line_item" "dcfg_active_flag" "Active" "bool"

Write-Host "`n  dcfg_project_factor" -ForegroundColor Cyan
Add-Col "dcfg_project_factor" "dcfg_factor_name" "Factor Name" "string" 200
Add-Col "dcfg_project_factor" "dcfg_cost_impact_estimated" "Estimated Cost Impact" "money"
Add-Col "dcfg_project_factor" "dcfg_cost_impact_actual" "Actual Cost Impact" "money"
Add-Col "dcfg_project_factor" "dcfg_notes" "Notes" "memo"
Add-Col "dcfg_project_factor" "dcfg_discovered_date" "Discovered Date" "datetime"
Add-Col "dcfg_project_factor" "dcfg_active_flag" "Active" "bool"

Write-Host "`n  dcfg_template_bundle_member" -ForegroundColor Cyan
Add-Col "dcfg_template_bundle_member" "dcfg_sequence" "Sequence" "int"

Write-Host "`n  dcfg_proposal" -ForegroundColor Cyan
Add-Col "dcfg_proposal" "dcfg_scope_responses" "Scope Responses JSON" "memo"
Add-Col "dcfg_proposal" "dcfg_base_contract" "Base Contract Amount" "money"
Add-Col "dcfg_proposal" "dcfg_sub_total" "Sub Total" "money"
Add-Col "dcfg_proposal" "dcfg_contract_total" "Contract Total" "money"
Add-Col "dcfg_proposal" "dcfg_trade" "Trade" "string" 100
Add-Col "dcfg_proposal" "dcfg_bidder_license" "Bidder License" "string" 100
Add-Col "dcfg_proposal" "dcfg_bidder_contact" "Bidder Contact" "string" 200
Add-Col "dcfg_proposal" "dcfg_sp_file_ref" "SharePoint File Ref" "string" 500
Add-Col "dcfg_proposal" "dcfg_active_flag" "Active" "bool"

# =====================================================================
# STEP 3: Choice columns
# =====================================================================
Write-Host "`n=== STEP 3: Choice Columns ===" -ForegroundColor Cyan

Add-Choice "dcfg_rfp_package" "dcfg_status" "Status" @(
    @{Value=100000000;Label="Draft"},@{Value=100000001;Label="Sent"},@{Value=100000002;Label="Responses In"},
    @{Value=100000003;Label="Leveled"},@{Value=100000004;Label="Awarded"},@{Value=100000005;Label="Canceled"})
Add-Choice "dcfg_rfp_package" "dcfg_billing_pattern" "Billing Pattern" @(
    @{Value=100000000;Label="Per Unit"},@{Value=100000001;Label="Monthly Fixed"},@{Value=100000002;Label="Milestone"},@{Value=100000003;Label="Hybrid"})
Add-Choice "dcfg_rfp_package" "dcfg_period_type" "Period Type" @(
    @{Value=100000000;Label="Monthly"},@{Value=100000001;Label="Quarterly"})
Add-Choice "dcfg_template_line_item" "dcfg_uom" "Unit of Measure" @(
    @{Value=1;Label="Square Foot"},@{Value=2;Label="Each"},@{Value=3;Label="Linear Foot"},@{Value=4;Label="Load"},
    @{Value=5;Label="Hour"},@{Value=6;Label="Lump Sum"},@{Value=7;Label="Cubic Yard"},@{Value=8;Label="Square (roofing)"},
    @{Value=9;Label="Gallon"},@{Value=10;Label="Ton"})
Add-Choice "dcfg_template_line_item" "dcfg_quantity_type" "Quantity Type" @(
    @{Value=100000000;Label="Fixed"},@{Value=100000001;Label="Measured"})
Add-Choice "dcfg_project_line_item" "dcfg_uom" "Unit of Measure" @(
    @{Value=1;Label="Square Foot"},@{Value=2;Label="Each"},@{Value=3;Label="Linear Foot"},@{Value=4;Label="Load"},
    @{Value=5;Label="Hour"},@{Value=6;Label="Lump Sum"},@{Value=7;Label="Cubic Yard"},@{Value=8;Label="Square (roofing)"},
    @{Value=9;Label="Gallon"},@{Value=10;Label="Ton"})
Add-Choice "dcfg_project_line_item" "dcfg_quantity_source" "Quantity Source" @(
    @{Value=100000000;Label="Template Default"},@{Value=100000001;Label="Field Measurement"},
    @{Value=100000002;Label="Property Record"},@{Value=100000003;Label="Historical"})
Add-Choice "dcfg_project_factor" "dcfg_factor_source" "Factor Source" @(
    @{Value=100000000;Label="Property"},@{Value=100000001;Label="Customer"},@{Value=100000002;Label="Discovered"})
Add-Choice "dcfg_proposal" "dcfg_status" "Status" @(
    @{Value=100000000;Label="Invited"},@{Value=100000001;Label="Submitted"},@{Value=100000002;Label="Awarded"},
    @{Value=100000003;Label="Rejected"},@{Value=100000004;Label="No Response"})

# =====================================================================
# STEP 4: Lookup relationships
# =====================================================================
Write-Host "`n=== STEP 4: Lookups ===" -ForegroundColor Cyan
Add-Lookup "dcfg_customer" "dcfg_rfp_package" "dcfg_customer_id" "Customer"
Add-Lookup "dcfg_prime_contract" "dcfg_rfp_package" "dcfg_prime_contract_id" "Prime Contract"
Add-Lookup "dcfg_rfp_package" "dcfg_rfp_project" "dcfg_rfp_package_id" "RFP Package"
Add-Lookup "dcfg_project" "dcfg_rfp_project" "dcfg_project_id" "Project"
Add-Lookup "dcfg_rfp_package" "dcfg_rfp_vendor" "dcfg_rfp_package_id" "RFP Package"
Add-Lookup "dcfg_vendor" "dcfg_rfp_vendor" "dcfg_vendor_id" "Vendor"
Add-Lookup "dcfg_rfp_package" "dcfg_proposal" "dcfg_rfp_package_id" "RFP Package"
Add-Lookup "dcfg_vendor" "dcfg_proposal" "dcfg_vendor_id" "Vendor"
Add-Lookup "dcfg_projecttemplate" "dcfg_template_line_item" "dcfg_project_template_id" "Project Template"
Add-Lookup "dcfg_project" "dcfg_project_line_item" "dcfg_project_id" "Project"
Add-Lookup "dcfg_template_line_item" "dcfg_project_line_item" "dcfg_template_line_item_id" "Template Line Item"
Add-Lookup "dcfg_project" "dcfg_project_factor" "dcfg_project_id" "Project"
Add-Lookup "dcfg_projecttemplate" "dcfg_template_bundle_member" "dcfg_bundle_template_id" "Bundle Template"
Add-Lookup "dcfg_projecttemplate" "dcfg_template_bundle_member" "dcfg_member_template_id" "Member Template"
Add-Lookup "dcfg_rfp_package" "dcfg_milestone" "dcfg_rfp_package_id" "RFP Package"

# =====================================================================
# STEP 5: Columns on EXISTING tables
# =====================================================================
Write-Host "`n=== STEP 5: Columns on Existing Tables ===" -ForegroundColor Cyan

Write-Host "`n  dcfg_projecttemplate" -ForegroundColor Cyan
Add-Col "dcfg_projecttemplate" "dcfg_trades" "Trades" "string" 500
Add-Col "dcfg_projecttemplate" "dcfg_cost_code" "Cost Code" "string" 50
Add-Col "dcfg_projecttemplate" "dcfg_base_duration_days" "Base Duration Days" "int"
Add-Col "dcfg_projecttemplate" "dcfg_bundle_flag" "Is Bundle" "bool"
Add-Choice "dcfg_projecttemplate" "dcfg_billing_pattern" "Billing Pattern" @(
    @{Value=100000000;Label="Per Unit"},@{Value=100000001;Label="Monthly Fixed"},@{Value=100000002;Label="Milestone"})

Write-Host "`n  dcfg_project" -ForegroundColor Cyan
Add-Col "dcfg_project" "dcfg_trades" "Trades" "string" 500
Add-Col "dcfg_project" "dcfg_cost_code" "Cost Code" "string" 50
Add-Col "dcfg_project" "dcfg_estimated_cost" "Estimated Cost" "money"
Add-Col "dcfg_project" "dcfg_estimated_duration_days" "Estimated Duration Days" "int"
Add-Col "dcfg_project" "dcfg_actual_cost" "Actual Cost" "money"
Add-Col "dcfg_project" "dcfg_actual_duration_days" "Actual Duration Days" "int"
Add-Col "dcfg_project" "dcfg_awarded_cost" "Awarded Cost" "money"
Add-Col "dcfg_project" "dcfg_awarded_duration_days" "Awarded Duration Days" "int"
Add-Col "dcfg_project" "dcfg_final_cost" "Final Cost" "money"
Add-Col "dcfg_project" "dcfg_change_order_count" "Change Order Count" "int"
Add-Col "dcfg_project" "dcfg_planning_miss_count" "Planning Miss Count" "int"
Add-Col "dcfg_project" "dcfg_punch_list_count" "Punch List Count" "int"
Add-Col "dcfg_project" "dcfg_callback_count" "Callback Count" "int"
Add-Col "dcfg_project" "dcfg_closeout_date" "Closeout Date" "datetime"
Add-Col "dcfg_project" "dcfg_factor_adjustment" "Factor Adjustment" "decimal"
Add-Col "dcfg_project" "dcfg_reported_by" "Reported By" "string" 200
Add-Lookup "dcfg_property" "dcfg_project" "dcfg_propertyid" "Property"
Add-Choice "dcfg_project" "dcfg_urgency" "Urgency" @(
    @{Value=100000000;Label="Emergency"},@{Value=100000001;Label="Planned"},@{Value=100000002;Label="Deferred"})
Add-Choice "dcfg_project" "dcfg_billing_pattern" "Billing Pattern" @(
    @{Value=100000000;Label="Per Unit"},@{Value=100000001;Label="Monthly Fixed"},
    @{Value=100000002;Label="Milestone"},@{Value=100000003;Label="Hybrid"})

Write-Host "`n  dcfg_property" -ForegroundColor Cyan
Add-Col "dcfg_property" "dcfg_union_required" "Union Labor Required" "bool"
Add-Col "dcfg_property" "dcfg_union_classification" "Union Classification" "string" 200
Add-Col "dcfg_property" "dcfg_prevailing_wage" "Prevailing Wage" "bool"
Add-Col "dcfg_property" "dcfg_historic_preservation" "Historic Preservation" "bool"
Add-Choice "dcfg_property" "dcfg_regulatory_tier" "Regulatory Tier" @(
    @{Value=100000000;Label="Tier 1 (Basic)"},@{Value=100000001;Label="Tier 2 (Enhanced)"},@{Value=100000002;Label="Tier 3 (Strict)"})
Add-Choice "dcfg_property" "dcfg_access_difficulty" "Access Difficulty" @(
    @{Value=100000000;Label="Standard"},@{Value=100000001;Label="Occupied"},
    @{Value=100000002;Label="High-Rise"},@{Value=100000003;Label="Restricted Hours"})

Write-Host "`n  dcfg_customer" -ForegroundColor Cyan
Add-Col "dcfg_customer" "dcfg_bonding_threshold" "Bonding Threshold" "money"
Add-Col "dcfg_customer" "dcfg_compliance_profile" "Compliance Profile" "string" 500
Add-Choice "dcfg_customer" "dcfg_reporting_level" "Reporting Level" @(
    @{Value=100000000;Label="Standard"},@{Value=100000001;Label="Enhanced"},@{Value=100000002;Label="Full Audit"})

# =====================================================================
# STEP 6: Publish all entities
# =====================================================================
Write-Host "`n=== STEP 6: Publish ===" -ForegroundColor Cyan
$entities = @("dcfg_rfp_package","dcfg_rfp_project","dcfg_rfp_vendor","dcfg_proposal",
    "dcfg_template_line_item","dcfg_project_line_item","dcfg_project_factor","dcfg_template_bundle_member",
    "dcfg_milestone","dcfg_projecttemplate","dcfg_project","dcfg_property","dcfg_customer")
$entityXml = ($entities | ForEach-Object { "<entity>$_</entity>" }) -join ''
$pubBody = @{ ParameterXml = "<importexportxml><entities>$entityXml</entities></importexportxml>" } | ConvertTo-Json
Invoke-RestMethod -Uri "$api/PublishXml" -Headers $h -Method Post -Body $pubBody | Out-Null
Write-Host "  Published $($entities.Count) entities" -ForegroundColor Green

# =====================================================================
# STEP 7: Table Permissions + Site Settings (portal access)
# =====================================================================
Write-Host "`n=== STEP 7: Permissions + Site Settings ===" -ForegroundColor Cyan

# Load helpers for permission creation
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"
Connect 'https://org0c17e98d.crm.dynamics.com/'

$AuthUsersRole = 'ae785cc2-54bb-400e-b0be-b448ea923352'

Invoke-DataverseCommands {
    $newTables = @{
        "dcfg_rfp_package" = "dcfg_name,dcfg_trades,dcfg_scope_description,dcfg_total_estimated_value,dcfg_period_cap,dcfg_contract_duration_months,dcfg_deadline,dcfg_status,dcfg_billing_pattern,dcfg_period_type,dcfg_bid_solicited,dcfg_bid_received,dcfg_scope_exhibit_drafted,dcfg_exhibit_b_issued,dcfg_contract_out,dcfg_contract_fe,dcfg_submittals_received,dcfg_scope_items,dcfg_financial_structure,dcfg_version,dcfg_sp_file_ref,dcfg_active_flag,_dcfg_customer_id_value,_dcfg_prime_contract_id_value"
        "dcfg_rfp_project" = "dcfg_name,_dcfg_rfp_package_id_value,_dcfg_project_id_value"
        "dcfg_rfp_vendor" = "dcfg_name,_dcfg_rfp_package_id_value,_dcfg_vendor_id_value"
        "dcfg_proposal" = "dcfg_name,dcfg_scope_responses,dcfg_base_contract,dcfg_sub_total,dcfg_contract_total,dcfg_trade,dcfg_bidder_license,dcfg_bidder_contact,dcfg_status,dcfg_sp_file_ref,dcfg_active_flag,_dcfg_rfp_package_id_value,_dcfg_vendor_id_value"
        "dcfg_template_line_item" = "dcfg_name,dcfg_description,dcfg_uom,dcfg_quantity_type,dcfg_default_qty,dcfg_base_rate,dcfg_trade,dcfg_sequence,dcfg_active_flag,_dcfg_project_template_id_value"
        "dcfg_project_line_item" = "dcfg_name,dcfg_description,dcfg_uom,dcfg_quantity,dcfg_quantity_source,dcfg_unit_rate,dcfg_extended_cost,dcfg_trade,dcfg_needs_takeoff,dcfg_sequence,dcfg_active_flag,_dcfg_project_id_value,_dcfg_template_line_item_id_value"
        "dcfg_project_factor" = "dcfg_name,dcfg_factor_name,dcfg_factor_source,dcfg_cost_impact_estimated,dcfg_cost_impact_actual,dcfg_notes,dcfg_discovered_date,dcfg_active_flag,_dcfg_project_id_value"
        "dcfg_template_bundle_member" = "dcfg_name,dcfg_sequence,_dcfg_bundle_template_id_value,_dcfg_member_template_id_value"
    }

    foreach ($tableName in $newTables.Keys) {
        $fields = $newTables[$tableName]
        Write-Host "`n  ${tableName}:" -ForegroundColor Cyan

        # Check if perm exists
        $existing = (Get-Records -setName 'mspp_entitypermissions' `
            -query "?`$select=mspp_entitypermissionid,mspp_entityname&`$filter=mspp_entityname eq '$tableName' and _mspp_websiteid_value eq $WebsiteId").value
        if ($existing -and $existing.Count -gt 0) {
            $permId = $existing[0].mspp_entitypermissionid
            Write-Host "    PERM EXISTS: $tableName" -ForegroundColor Yellow
        } else {
            $permId = New-Record -setName 'mspp_entitypermissions' -body @{
                mspp_entityname = $tableName; mspp_entitylogicalname = $tableName
                mspp_scope = 756150000; mspp_read = $true; mspp_write = $true; mspp_create = $true
                mspp_delete = $true; mspp_append = $true; mspp_appendto = $true
                'mspp_websiteid@odata.bind' = "/powerpagesites($WebsiteId)"
            }
            Write-Host "    PERM CREATED" -ForegroundColor Green
        }

        # Patch content JSON with role links
        $contentJson = @{
            read = $true; write = $true; create = $true; delete = $true; append = $true; appendto = $true
            scope = 756150000; entityname = $tableName; entitylogicalname = $tableName
            adx_entitypermission_webrole = @($AuthUsersRole)
        } | ConvertTo-Json -Compress
        Update-Record -setName 'powerpagecomponents' -id $permId -body @{ content = $contentJson }
        Write-Host "    ROLES PATCHED" -ForegroundColor Green

        # Site settings
        foreach ($ss in @(
            @{ n = "Webapi/$tableName/enabled"; v = "true" },
            @{ n = "Webapi/$tableName/fields"; v = $fields }
        )) {
            $existSS = (Get-Records -setName 'powerpagecomponents' `
                -query "?`$select=powerpagecomponentid,name&`$filter=_powerpagesiteid_value eq $WebsiteId and powerpagecomponenttype eq 9 and name eq '$($ss.n)'").value
            if ($existSS -and $existSS.Count -gt 0) {
                Write-Host "    SS EXISTS: $($ss.n)" -ForegroundColor Yellow
            } else {
                New-Record -setName 'powerpagecomponents' -body @{
                    name = $ss.n; powerpagecomponenttype = 9
                    content = "{`"value`":`"$($ss.v)`"}"
                    'powerpagesiteid@odata.bind' = "/powerpagesites($WebsiteId)"
                } | Out-Null
                Write-Host "    SS CREATED: $($ss.n)" -ForegroundColor Green
            }
        }
    }
}

Write-Host "`n=== SCHEMA BUILD COMPLETE ===" -ForegroundColor Green
