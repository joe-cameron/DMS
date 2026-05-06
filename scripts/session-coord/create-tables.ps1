# scripts/session-coord/create-tables.ps1
# Creates 3 Dataverse tables for the Session Coordinator on DCFGSystems-Test.
# Idempotent — skips tables and columns that already exist.
#
# Prerequisites:
#   pac auth active on Test (org0c17e98d). Run 'pac auth select --index 2' if needed.
#   Az module available for Get-AzAccessToken.
#
# Usage:
#   pwsh -NoProfile -File C:/dcfg/scripts/session-coord/create-tables.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- Auth library ---
. "$PSScriptRoot/lib/dataverse-auth.ps1"

# Ensure we are targeting Test, not Prod
$activeUrl = Get-ActiveOrgUrl
if ($activeUrl -notmatch 'org0c17e98d') {
    Write-Host "[create-tables] pac auth is on: $activeUrl" -ForegroundColor Yellow
    Write-Host "[create-tables] Switching to Test (index 2)..." -ForegroundColor Yellow
    pac auth select --index 2 | Out-Null
    # Clear cached values so Initialize-DataverseAuth re-reads
    $script:OrgUrl  = $null
    $script:BaseUri = $null
}

Initialize-DataverseAuth
Write-Host "[create-tables] Target: $($script:OrgUrl)" -ForegroundColor Cyan

$SolutionName = 'DCFGSystemTest'

# ============================================================================
# HELPER — Label block (Dataverse LocalizedLabels shape)
# ============================================================================
function Build-Label([string]$Text) {
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

# ============================================================================
# HELPER — Test if a table exists
# ============================================================================
function Test-TableExists([string]$LogicalName) {
    try {
        $r = Invoke-DataverseGet "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName"
        return ($null -ne $r -and $r.LogicalName -eq $LogicalName)
    } catch {
        return $false
    }
}

# ============================================================================
# HELPER — Test if a column exists on a table
# ============================================================================
function Test-ColumnExists([string]$TableLogicalName, [string]$ColumnLogicalName) {
    try {
        $r = Invoke-DataverseGet "EntityDefinitions(LogicalName='$TableLogicalName')/Attributes?`$select=LogicalName&`$filter=LogicalName eq '$ColumnLogicalName'"
        return ($r.value -and $r.value.Count -gt 0)
    } catch {
        return $false
    }
}

# ============================================================================
# HELPER — Create a table (idempotent)
# ============================================================================
function Ensure-Table {
    param(
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$DisplayCollectionName,
        [string]$PrimaryAttributeSchema,
        [string]$PrimaryAttributeLabel
    )
    $logical = $SchemaName.ToLower()
    if (Test-TableExists $logical) {
        Write-Host "  SKIP TABLE: $logical (already exists)" -ForegroundColor Yellow
        return
    }
    $body = @{
        '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName            = $SchemaName
        DisplayName           = Build-Label $DisplayName
        DisplayCollectionName = Build-Label $DisplayCollectionName
        OwnershipType         = 'UserOwned'
        IsActivity            = $false
        HasActivities         = $false
        HasNotes              = $false
        PrimaryNameAttribute  = $PrimaryAttributeSchema.ToLower()
        Attributes            = @(
            @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
                SchemaName    = $PrimaryAttributeSchema
                IsPrimaryName = $true
                DisplayName   = Build-Label $PrimaryAttributeLabel
                Description   = Build-Label $PrimaryAttributeLabel
                MaxLength     = 200
                RequiredLevel = @{ Value = 'None' }
            }
        )
    }
    # POST to EntityDefinitions with solution header
    $uri     = "$($script:BaseUri)/EntityDefinitions"
    $headers = Get-DataverseHeaders
    $headers['MSCRM.SolutionUniqueName'] = $SolutionName
    $json    = $body | ConvertTo-Json -Depth 20 -Compress
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null
        Write-Host "  CREATED TABLE: $logical" -ForegroundColor Green
    } catch {
        $msg = $_.ErrorDetails.Message
        if ($msg -match 'already exists|0x80041d61|exists in the target system') {
            Write-Host "  SKIP TABLE: $logical (already exists — caught)" -ForegroundColor Yellow
        } else {
            Write-Host "  ERROR creating $logical`: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Detail: $msg" -ForegroundColor Red
            throw
        }
    }
}

# ============================================================================
# HELPER — Add a String column (idempotent)
# ============================================================================
function Add-StringCol {
    param([string]$Table, [string]$Schema, [string]$Label, [int]$Max = 200)
    $logical = $Schema.ToLower()
    if (Test-ColumnExists $Table $logical) {
        Write-Host "    SKIP: $Schema (exists)" -ForegroundColor Yellow; return
    }
    $col = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName    = $Schema
        DisplayName   = Build-Label $Label
        Description   = Build-Label $Label
        MaxLength     = $Max
        RequiredLevel = @{ Value = 'None' }
    }
    Upsert-Column $Table $Schema $col
}

# ============================================================================
# HELPER — Add a Memo (multiline text) column (idempotent)
# ============================================================================
function Add-MemoCol {
    param([string]$Table, [string]$Schema, [string]$Label, [int]$Max = 100000)
    $logical = $Schema.ToLower()
    if (Test-ColumnExists $Table $logical) {
        Write-Host "    SKIP: $Schema (exists)" -ForegroundColor Yellow; return
    }
    $col = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        SchemaName    = $Schema
        DisplayName   = Build-Label $Label
        Description   = Build-Label $Label
        MaxLength     = $Max
        RequiredLevel = @{ Value = 'None' }
    }
    Upsert-Column $Table $Schema $col
}

# ============================================================================
# HELPER — Add a DateTime column (idempotent)
# ============================================================================
function Add-DateTimeCol {
    param([string]$Table, [string]$Schema, [string]$Label)
    $logical = $Schema.ToLower()
    if (Test-ColumnExists $Table $logical) {
        Write-Host "    SKIP: $Schema (exists)" -ForegroundColor Yellow; return
    }
    $col = @{
        '@odata.type'    = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
        SchemaName       = $Schema
        DisplayName      = Build-Label $Label
        Description      = Build-Label $Label
        RequiredLevel    = @{ Value = 'None' }
        Format           = 'DateAndTime'
        DateTimeBehavior = @{ Value = 'UserLocal' }
    }
    Upsert-Column $Table $Schema $col
}

# ============================================================================
# HELPER — Add a Boolean column (idempotent)
# ============================================================================
function Add-BoolCol {
    param([string]$Table, [string]$Schema, [string]$Label, [bool]$Default = $true)
    $logical = $Schema.ToLower()
    if (Test-ColumnExists $Table $logical) {
        Write-Host "    SKIP: $Schema (exists)" -ForegroundColor Yellow; return
    }
    $col = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
        SchemaName    = $Schema
        DisplayName   = Build-Label $Label
        Description   = Build-Label $Label
        DefaultValue  = $Default
        RequiredLevel = @{ Value = 'None' }
        OptionSet     = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
            TrueOption    = @{ Value = 1; Label = Build-Label 'Yes' }
            FalseOption   = @{ Value = 0; Label = Build-Label 'No' }
        }
    }
    Upsert-Column $Table $Schema $col
}

# ============================================================================
# HELPER — Add a Picklist column (idempotent)
# ============================================================================
function Add-PicklistCol {
    param([string]$Table, [string]$Schema, [string]$Label, [array]$Options)
    $logical = $Schema.ToLower()
    if (Test-ColumnExists $Table $logical) {
        Write-Host "    SKIP: $Schema (exists)" -ForegroundColor Yellow; return
    }
    $optItems = @()
    foreach ($o in $Options) {
        $optItems += @{ Value = $o.Value; Label = Build-Label $o.Label }
    }
    $col = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName    = $Schema
        DisplayName   = Build-Label $Label
        Description   = Build-Label $Label
        RequiredLevel = @{ Value = 'None' }
        OptionSet     = @{
            '@odata.type'  = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal       = $false
            OptionSetType  = 'Picklist'
            Options        = $optItems
        }
    }
    Upsert-Column $Table $Schema $col
}

# ============================================================================
# HELPER — POST a column definition (used by all Add-*Col helpers above)
# ============================================================================
function Upsert-Column {
    param([string]$Table, [string]$Schema, [hashtable]$ColDef)
    $uri     = "$($script:BaseUri)/EntityDefinitions(LogicalName='$Table')/Attributes"
    $headers = Get-DataverseHeaders
    $headers['MSCRM.SolutionUniqueName'] = $SolutionName
    $json    = $ColDef | ConvertTo-Json -Depth 20 -Compress
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null
        Write-Host "    ADDED: $Schema" -ForegroundColor Green
    } catch {
        $msg = $_.ErrorDetails.Message
        if ($msg -match 'already exists|0x80041d61') {
            Write-Host "    SKIP: $Schema (already exists — caught)" -ForegroundColor Yellow
        } else {
            Write-Host "    ERROR: $Schema — $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "    Detail: $msg" -ForegroundColor Red
            throw
        }
    }
}

# ============================================================================
# TABLE 1: dcfg_session_lock
# ============================================================================
Write-Host "`n[1/3] dcfg_session_lock" -ForegroundColor Cyan
Ensure-Table `
    -SchemaName            'dcfg_session_lock' `
    -DisplayName           'Session Lock' `
    -DisplayCollectionName 'Session Locks' `
    -PrimaryAttributeSchema 'dcfg_resource_key' `
    -PrimaryAttributeLabel  'Resource Key'

Write-Host "  Waiting 5s for metadata cache..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

$t1 = 'dcfg_session_lock'
Add-StringCol   $t1 'dcfg_session_id'      'Session ID'      200
Add-DateTimeCol $t1 'dcfg_locked_at'       'Locked At'
Add-DateTimeCol $t1 'dcfg_heartbeat_at'    'Heartbeat At'
Add-DateTimeCol $t1 'dcfg_expires_at'      'Expires At'
Add-StringCol   $t1 'dcfg_operation'       'Operation'       500
Add-PicklistCol $t1 'dcfg_status'          'Status' @(
    @{ Value = 100000000; Label = 'Active' }
    @{ Value = 100000001; Label = 'Released' }
    @{ Value = 100000002; Label = 'Expired' }
    @{ Value = 100000003; Label = 'Overridden' }
)
Add-StringCol   $t1 'dcfg_overridden_by'   'Overridden By'   200
Add-DateTimeCol $t1 'dcfg_overridden_at'   'Overridden At'

# ============================================================================
# TABLE 2: dcfg_session_work_item
# ============================================================================
Write-Host "`n[2/3] dcfg_session_work_item" -ForegroundColor Cyan
Ensure-Table `
    -SchemaName            'dcfg_session_work_item' `
    -DisplayName           'Session Work Item' `
    -DisplayCollectionName 'Session Work Items' `
    -PrimaryAttributeSchema 'dcfg_title' `
    -PrimaryAttributeLabel  'Title'

Write-Host "  Waiting 5s for metadata cache..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

$t2 = 'dcfg_session_work_item'
Add-PicklistCol $t2 'dcfg_phase'             'Phase' @(
    @{ Value = 100000000; Label = 'Design' }
    @{ Value = 100000001; Label = 'Build' }
    @{ Value = 100000002; Label = 'Test' }
    @{ Value = 100000003; Label = 'Deploy' }
    @{ Value = 100000004; Label = 'Done' }
    @{ Value = 100000005; Label = 'Blocked' }
)
Add-PicklistCol $t2 'dcfg_priority'          'Priority' @(
    @{ Value = 100000000; Label = 'P0' }
    @{ Value = 100000001; Label = 'P1' }
    @{ Value = 100000002; Label = 'P2' }
    @{ Value = 100000003; Label = 'P3' }
)
Add-PicklistCol $t2 'dcfg_target_env'        'Target Env' @(
    @{ Value = 100000000; Label = 'Test' }
    @{ Value = 100000001; Label = 'Stage' }
    @{ Value = 100000002; Label = 'Prod' }
)
Add-StringCol   $t2 'dcfg_assigned_session'  'Assigned Session'  200
Add-StringCol   $t2 'dcfg_source'            'Source'            500
Add-MemoCol     $t2 'dcfg_notes'             'Notes'             100000
Add-StringCol   $t2 'dcfg_deployed_to'       'Deployed To'       200
Add-DateTimeCol $t2 'dcfg_completed_on'      'Completed On'
Add-BoolCol     $t2 'dcfg_active_flag'       'Active Flag'       $true

# ============================================================================
# TABLE 3: dcfg_session_log
# ============================================================================
Write-Host "`n[3/3] dcfg_session_log" -ForegroundColor Cyan
Ensure-Table `
    -SchemaName            'dcfg_session_log' `
    -DisplayName           'Session Log' `
    -DisplayCollectionName 'Session Logs' `
    -PrimaryAttributeSchema 'dcfg_session_id' `
    -PrimaryAttributeLabel  'Session ID'

Write-Host "  Waiting 5s for metadata cache..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

$t3 = 'dcfg_session_log'
Add-DateTimeCol $t3 'dcfg_started_at'            'Started At'
Add-DateTimeCol $t3 'dcfg_ended_at'              'Ended At'
Add-MemoCol     $t3 'dcfg_summary'               'Summary'
Add-MemoCol     $t3 'dcfg_files_touched'         'Files Touched'
Add-MemoCol     $t3 'dcfg_deploys'               'Deploys'
Add-MemoCol     $t3 'dcfg_work_items_advanced'   'Work Items Advanced'
Add-MemoCol     $t3 'dcfg_uncommitted_changes'   'Uncommitted Changes'
Add-StringCol   $t3 'dcfg_active_branch'         'Active Branch'     200
Add-MemoCol     $t3 'dcfg_git_diff_stat'         'Git Diff Stat'

Write-Host "`n[create-tables] DONE" -ForegroundColor Green
