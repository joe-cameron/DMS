# ============================================================================
# DCFG Company Brain — dcfg_brain_insight Table Schema Script
# ============================================================================
# Creates the dcfg_brain_insight table with columns and lookup relationships
# to existing DCFG tables (customers, vendors, contracts, MSAs, properties,
# programs, onboarding cases).
#
# Prerequisites:
#   Install-Module Az.Accounts -Scope CurrentUser -Force
#   Connect-AzAccount   (run in the same pwsh session before this script)
#
# Run:
#   Unblock-File C:\DCFG\OP-Brain-Insight.ps1
#   pwsh -ExecutionPolicy Bypass -File C:\DCFG\OP-Brain-Insight.ps1
# ============================================================================

# ── Dot-source Microsoft helpers ─────────────────────────────────────────────
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\MetadataOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"

# ── Connect (TRAILING SLASH REQUIRED) ───────────────────────────────────────
Connect 'https://org0c17e98d.crm.dynamics.com/'

$SolutionName = 'DCFGSystemTest'

# ── Build-Label helper ───────────────────────────────────────────────────────
function Build-Label {
    param([string]$Text)
    return @{
        '@odata.type'   = 'Microsoft.Dynamics.CRM.Label'
        LocalizedLabels = @(
            @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'
                Label         = $Text
                LanguageCode  = 1033
            }
        )
    }
}

# ── Existence checks (bulk GET pattern — $filter on Attributes is UNRELIABLE) ─
function Test-TableExists {
    param([string]$LogicalName)
    try {
        $result = Get-Table -logicalName $LogicalName -query '?$select=LogicalName'
        return ($null -ne $result)
    }
    catch { return $false }
}

function Test-ColumnExists {
    param([string]$TableLogicalName, [string]$ColumnLogicalName)
    try {
        $allCols = (Get-TableColumns -tableLogicalName $TableLogicalName -query '?$select=LogicalName').value
        foreach ($c in $allCols) {
            if ($c.LogicalName -eq $ColumnLogicalName) { return $true }
        }
        return $false
    }
    catch { return $false }
}

function Test-RelationshipExists {
    param([string]$SchemaName)
    try {
        $uri = 'RelationshipDefinitions?$filter=SchemaName eq ' + "'$SchemaName'" + '&$select=SchemaName'
        $result = (Invoke-RestMethod -Uri "$($baseURI)$uri" -Headers $baseHeaders).value
        return ($result.Count -gt 0)
    }
    catch { return $false }
}

# ── Safe column add with try/catch defense ───────────────────────────────────
function Add-ColumnSafe {
    param([string]$Table, [hashtable]$Column)
    $schema = $Column.SchemaName
    if (Test-ColumnExists -TableLogicalName $Table -ColumnLogicalName $schema.ToLower()) {
        Write-Host "    SKIP column: $schema (exists)" -ForegroundColor Yellow
        return
    }
    try {
        New-Column -tableLogicalName $Table -column $Column -solutionUniqueName $SolutionName
        Write-Host "    ADDED column: $schema" -ForegroundColor Green
    } catch {
        if ($_.ToString() -match 'already exists') {
            Write-Host "    SKIP column: $schema (exists)" -ForegroundColor Yellow
        } else { throw }
    }
}

# ── Safe relationship add ────────────────────────────────────────────────────
function Add-RelationshipSafe {
    param([hashtable]$Relationship)
    $schema = $Relationship.SchemaName
    if (Test-RelationshipExists -SchemaName $schema) {
        Write-Host "    SKIP relationship: $schema (exists)" -ForegroundColor Yellow
        return
    }
    try {
        New-Relationship -relationship $Relationship -solutionUniqueName $SolutionName
        Write-Host "    ADDED relationship: $schema" -ForegroundColor Green
    } catch {
        if ($_.ToString() -match 'already exists') {
            Write-Host "    SKIP relationship: $schema (exists)" -ForegroundColor Yellow
        } else { throw }
    }
}

Invoke-DataverseCommands {

    # =========================================================================
    # STEP 1: Create dcfg_brain_insight table
    # =========================================================================
    Write-Host "`n== STEP 1: Create dcfg_brain_insight table ==" -ForegroundColor Cyan

    if (Test-TableExists -LogicalName 'dcfg_brain_insight') {
        Write-Host "  Table dcfg_brain_insight already exists — skipping creation" -ForegroundColor Yellow
    } else {
        $tableBody = @{
            '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
            SchemaName            = 'dcfg_brain_insight'
            DisplayName           = Build-Label 'DCFG Brain Insight'
            DisplayCollectionName = Build-Label 'DCFG Brain Insights'
            Description           = Build-Label 'Cross-system intelligence insights generated by scheduled flows. Surfaces expiring certs, stalled onboarding, neglected proposals, budget warnings, and vendor alerts.'
            HasActivities         = $false
            HasNotes              = $true
            OwnershipType         = 'UserOwned'
            PrimaryNameAttribute  = 'dcfg_title'
            Attributes            = @(
                @{
                    '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
                    IsPrimaryName = $true
                    SchemaName    = 'dcfg_title'
                    RequiredLevel = @{ Value = 'ApplicationRequired' }
                    DisplayName   = Build-Label 'Title'
                    Description   = Build-Label 'Short headline for the insight'
                    MaxLength     = 200
                }
            )
        }
        $tableId = New-Table -body $tableBody -solutionUniqueName $SolutionName
        Write-Host "  CREATED table: dcfg_brain_insight ($tableId)" -ForegroundColor Green

        Write-Host "  Waiting 15s for metadata propagation..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }

    $T = 'dcfg_brain_insight'

    # =========================================================================
    # STEP 2: Add columns
    # =========================================================================
    Write-Host "`n== STEP 2: Add columns to dcfg_brain_insight ==" -ForegroundColor Cyan

    # ── dcfg_detail (multiline text — full context and recommended actions) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        SchemaName    = 'dcfg_detail'
        DisplayName   = Build-Label 'Detail'
        Description   = Build-Label 'Full context including specific records and recommended actions'
        MaxLength     = 4000
    }

    # ── dcfg_domain (choice — Sales / Operations / Contracts / Finance / Company) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName    = 'dcfg_domain'
        DisplayName   = Build-Label 'Domain'
        Description   = Build-Label 'Business domain this insight applies to'
        OptionSet     = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal      = $false
            OptionSetType = 'Picklist'
            Options       = @(
                @{ Value = 100000000; Label = Build-Label 'Sales' }
                @{ Value = 100000001; Label = Build-Label 'Operations' }
                @{ Value = 100000002; Label = Build-Label 'Contracts' }
                @{ Value = 100000003; Label = Build-Label 'Finance' }
                @{ Value = 100000004; Label = Build-Label 'Company' }
            )
        }
    }

    # ── dcfg_priority (choice — Critical / High / Medium / Low / Info) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName    = 'dcfg_priority'
        DisplayName   = Build-Label 'Priority'
        Description   = Build-Label 'Urgency level of this insight'
        OptionSet     = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal      = $false
            OptionSetType = 'Picklist'
            Options       = @(
                @{ Value = 100000000; Label = Build-Label 'Critical' }
                @{ Value = 100000001; Label = Build-Label 'High' }
                @{ Value = 100000002; Label = Build-Label 'Medium' }
                @{ Value = 100000003; Label = Build-Label 'Low' }
                @{ Value = 100000004; Label = Build-Label 'Info' }
            )
        }
    }

    # ── dcfg_insight_type (choice — Expiring / Overdue / Anomaly / Opportunity / Reminder / Trend) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName    = 'dcfg_insight_type'
        DisplayName   = Build-Label 'Insight Type'
        Description   = Build-Label 'Classification of the insight'
        OptionSet     = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal      = $false
            OptionSetType = 'Picklist'
            Options       = @(
                @{ Value = 100000000; Label = Build-Label 'Expiring' }
                @{ Value = 100000001; Label = Build-Label 'Overdue' }
                @{ Value = 100000002; Label = Build-Label 'Anomaly' }
                @{ Value = 100000003; Label = Build-Label 'Opportunity' }
                @{ Value = 100000004; Label = Build-Label 'Reminder' }
                @{ Value = 100000005; Label = Build-Label 'Trend' }
            )
        }
    }

    # ── dcfg_insight_status (choice — Active / Acknowledged / Resolved / Archived) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName    = 'dcfg_insight_status'
        DisplayName   = Build-Label 'Insight Status'
        Description   = Build-Label 'Lifecycle status of this insight'
        OptionSet     = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal      = $false
            OptionSetType = 'Picklist'
            Options       = @(
                @{ Value = 100000000; Label = Build-Label 'Active' }
                @{ Value = 100000001; Label = Build-Label 'Acknowledged' }
                @{ Value = 100000002; Label = Build-Label 'Resolved' }
                @{ Value = 100000003; Label = Build-Label 'Archived' }
            )
        }
    }

    # ── dcfg_source_systems (string — comma-separated system IDs) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName    = 'dcfg_source_systems'
        DisplayName   = Build-Label 'Source Systems'
        Description   = Build-Label 'Comma-separated list of systems queried (e.g., dataverse,upkeep,outlook)'
        MaxLength     = 500
    }

    # ── dcfg_target_roles (string — which roles should see this) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName    = 'dcfg_target_roles'
        DisplayName   = Build-Label 'Target Roles'
        Description   = Build-Label 'Comma-separated roles that should see this insight (e.g., operations,admin)'
        MaxLength     = 200
    }

    # ── dcfg_related_records (multiline — JSON array of entity_set + record_id refs) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        SchemaName    = 'dcfg_related_records'
        DisplayName   = Build-Label 'Related Records'
        Description   = Build-Label 'JSON array of entity_set and record_id references for linked Dataverse records'
        MaxLength     = 4000
    }

    # ── dcfg_action_taken (boolean) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
        SchemaName    = 'dcfg_action_taken'
        DisplayName   = Build-Label 'Action Taken'
        Description   = Build-Label 'Has someone acknowledged or acted on this insight'
        OptionSet     = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
            TrueOption    = @{ Value = 1; Label = Build-Label 'Yes' }
            FalseOption   = @{ Value = 0; Label = Build-Label 'No' }
        }
        DefaultValue  = $false
    }

    # ── dcfg_action_notes (multiline — what was done about it) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        SchemaName    = 'dcfg_action_notes'
        DisplayName   = Build-Label 'Action Notes'
        Description   = Build-Label 'Description of what action was taken in response to this insight'
        MaxLength     = 4000
    }

    # ── dcfg_generated_by (string — which flow produced this) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName    = 'dcfg_generated_by'
        DisplayName   = Build-Label 'Generated By'
        Description   = Build-Label 'Name of the Power Automate flow that generated this insight'
        MaxLength     = 100
    }

    # ── dcfg_generated_at (datetime — when the insight was created by the flow) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
        SchemaName    = 'dcfg_generated_at'
        DisplayName   = Build-Label 'Generated At'
        Description   = Build-Label 'UTC datetime when this insight was generated by the scheduled flow'
        Format        = 'DateAndTime'
        DateTimeBehavior = @{ Value = 'UserLocal' }
    }

    # ── dcfg_expires_at (datetime — when the insight is no longer relevant) ──
    Add-ColumnSafe -Table $T -Column @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
        SchemaName    = 'dcfg_expires_at'
        DisplayName   = Build-Label 'Expires At'
        Description   = Build-Label 'UTC datetime after which this insight should auto-archive'
        Format        = 'DateAndTime'
        DateTimeBehavior = @{ Value = 'UserLocal' }
    }

    Write-Host "`n  Waiting 15s for column propagation before relationships..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15

    # =========================================================================
    # STEP 3: Lookup relationships to existing DCFG tables
    # =========================================================================
    Write-Host "`n== STEP 3: Create lookup relationships ==" -ForegroundColor Cyan

    # ── Lookup to dcfg_customer ──────────────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_customer'
        ReferencedAttribute = 'dcfg_customerid'
        ReferencedEntity    = 'dcfg_customer'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_customer_id'
            DisplayName = Build-Label 'Related Customer'
            Description = Build-Label 'Customer this insight relates to'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # ── Lookup to dcfg_vendor ────────────────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_vendor'
        ReferencedAttribute = 'dcfg_vendorid'
        ReferencedEntity    = 'dcfg_vendor'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_vendor_id'
            DisplayName = Build-Label 'Related Vendor'
            Description = Build-Label 'Vendor this insight relates to'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # ── Lookup to dcfg_contract ──────────────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_contract'
        ReferencedAttribute = 'dcfg_contractid'
        ReferencedEntity    = 'dcfg_contract'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_contract_id'
            DisplayName = Build-Label 'Related Contract'
            Description = Build-Label 'Contract this insight relates to'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # ── Lookup to dcfg_msa ───────────────────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_msa'
        ReferencedAttribute = 'dcfg_msaid'
        ReferencedEntity    = 'dcfg_msa'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_msa_id'
            DisplayName = Build-Label 'Related MSA'
            Description = Build-Label 'MSA this insight relates to'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # ── Lookup to dcfg_property ──────────────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_property'
        ReferencedAttribute = 'dcfg_propertyid'
        ReferencedEntity    = 'dcfg_property'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_property_id'
            DisplayName = Build-Label 'Related Property'
            Description = Build-Label 'Property this insight relates to'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # ── Lookup to dcfg_program ───────────────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_program'
        ReferencedAttribute = 'dcfg_programid'
        ReferencedEntity    = 'dcfg_program'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_program_id'
            DisplayName = Build-Label 'Related Program'
            Description = Build-Label 'Program this insight relates to (for budget health insights)'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # ── Lookup to dcfg_onboarding_case ───────────────────────────────────────
    Add-RelationshipSafe -Relationship @{
        '@odata.type'       = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName          = 'dcfg_brain_insight_onboarding_case'
        ReferencedAttribute = 'dcfg_onboarding_caseid'
        ReferencedEntity    = 'dcfg_onboarding_case'
        ReferencingEntity   = 'dcfg_brain_insight'
        Lookup              = @{
            SchemaName  = 'dcfg_onboarding_case_id'
            DisplayName = Build-Label 'Related Onboarding Case'
            Description = Build-Label 'Onboarding case this insight relates to (for stall detection)'
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
            RollupView = 'NoCascade'; Reparent = 'NoCascade'
            Delete = 'RemoveLink'; Merge = 'NoCascade'
        }
    }

    # =========================================================================
    # DONE
    # =========================================================================
    Write-Host "`n== COMPLETE ==" -ForegroundColor Cyan
    Write-Host "  Table:         dcfg_brain_insight" -ForegroundColor Green
    Write-Host "  Columns:       13 (1 primary + 12 added)" -ForegroundColor Green
    Write-Host "  Choice cols:   4 (domain, priority, insight_type, insight_status)" -ForegroundColor Green
    Write-Host "  Lookups:       7 (customer, vendor, contract, msa, property, program, onboarding_case)" -ForegroundColor Green
    Write-Host "  Solution:      $SolutionName" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Entity set name will be: dcfg_brain_insights" -ForegroundColor Yellow
    Write-Host "  Verify after creation:   GET /api/data/v9.2/dcfg_brain_insights" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Create table permissions for dcfg_brain_insight (Read for all roles, Write for Admin)" -ForegroundColor White
    Write-Host "    2. Build the first intelligence flow (brain-cert-expiry)" -ForegroundColor White
    Write-Host "    3. Add dcfg_brain_insights to power-pages-content-ops entity set reference" -ForegroundColor White
}

# ── Run instructions ─────────────────────────────────────────────────────────
# Unblock-File C:\DCFG\OP-Brain-Insight.ps1
# pwsh -ExecutionPolicy Bypass -File C:\DCFG\OP-Brain-Insight.ps1
