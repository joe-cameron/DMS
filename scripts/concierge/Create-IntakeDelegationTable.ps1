$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org0c17e98d.crm.dynamics.com'
$solution = 'DCFGSystemTest'

$tokenObj = Get-AzAccessToken -ResourceUrl $orgUrl -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $tokenObj.Token).Password
if (-not $token) { throw 'Failed to obtain bearer token' }

$headers = @{
  'Authorization'            = "Bearer $token"
  'Content-Type'             = 'application/json; charset=utf-8'
  'OData-MaxVersion'         = '4.0'
  'OData-Version'            = '4.0'
  'Accept'                   = 'application/json'
  'MSCRM.SolutionUniqueName' = $solution
}

Write-Host '1/9 Creating dcfg_intake_delegation table...'
$tableBody = @{
  '@odata.type'         = '#Microsoft.Dynamics.CRM.EntityMetadata'
  SchemaName            = 'dcfg_intake_delegation'
  DisplayName           = @{ LocalizedLabels = @(@{ Label = 'Intake Delegation'; LanguageCode = 1033 }) }
  DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = 'Intake Delegations'; LanguageCode = 1033 }) }
  Description           = @{ LocalizedLabels = @(@{ Label = 'Delegation invite audit trail for onboarding concierge'; LanguageCode = 1033 }) }
  HasActivities         = $false
  HasNotes              = $false
  OwnershipType         = 'UserOwned'
  PrimaryNameAttribute  = 'dcfg_name'
  Attributes            = @(
    @{
      '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
      SchemaName    = 'dcfg_name'
      DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Delegate Name'; LanguageCode = 1033 }) }
      RequiredLevel = @{ Value = 'ApplicationRequired' }
      MaxLength     = 200
      FormatName    = @{ Value = 'Text' }
      IsPrimaryName = $true
    }
  )
} | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions" -Method POST -Headers $headers -Body $tableBody
Write-Host 'Table created. Waiting 10s...'; Start-Sleep 10

Write-Host '2/9 Adding lookup to dcfg_intake_session...'
$lookupBody = @{
  '@odata.type'               = '#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
  SchemaName                  = 'dcfg_dcfg_intake_session_dcfg_intake_delegation'
  ReferencedEntity            = 'dcfg_intake_session'
  ReferencingEntity           = 'dcfg_intake_delegation'
  Lookup = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.LookupAttributeMetadata'
    SchemaName    = 'dcfg_sessionid'
    DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Session'; LanguageCode = 1033 }) }
    RequiredLevel = @{ Value = 'ApplicationRequired' }
  }
  AssociatedMenuConfiguration = @{ Behavior = 'UseCollectionName'; Group = 'Details'; Order = 10000 }
  CascadeConfiguration        = @{ Assign = 'NoCascade'; Delete = 'Cascade'; Merge = 'NoCascade'; Reparent = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade' }
} | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/RelationshipDefinitions" -Method POST -Headers $headers -Body $lookupBody
Start-Sleep 5

function Add-Column($body) {
  Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_intake_delegation')/Attributes" -Method POST -Headers $headers -Body ($body | ConvertTo-Json -Depth 20 -Compress)
  Start-Sleep 2
}

Write-Host '3/9 Adding dcfg_delegate_email...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_delegate_email'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Delegate Email'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'ApplicationRequired' }
  MaxLength     = 200
  FormatName    = @{ Value = 'Email' }
}

Write-Host '4/9 Adding dcfg_sender_name...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_sender_name'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Sender Name'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'ApplicationRequired' }
  MaxLength     = 200
  FormatName    = @{ Value = 'Text' }
}

Write-Host '5/9 Adding dcfg_sender_email...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_sender_email'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Sender Email'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'ApplicationRequired' }
  MaxLength     = 200
  FormatName    = @{ Value = 'Email' }
}

Write-Host '6/9 Adding dcfg_card_scope (OptionSet)...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
  SchemaName    = 'dcfg_card_scope'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Card Scope'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  OptionSet     = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.OptionSetMetadata'
    IsGlobal      = $false
    OptionSetType = 'Picklist'
    Options       = @(
      @{ Value = 100000000; Label = @{ LocalizedLabels = @(@{ Label = 'Vendors';   LanguageCode = 1033 }) } }
      @{ Value = 100000001; Label = @{ LocalizedLabels = @(@{ Label = 'Dates';     LanguageCode = 1033 }) } }
      @{ Value = 100000002; Label = @{ LocalizedLabels = @(@{ Label = 'Locations'; LanguageCode = 1033 }) } }
      @{ Value = 100000003; Label = @{ LocalizedLabels = @(@{ Label = 'Documents'; LanguageCode = 1033 }) } }
      @{ Value = 100000004; Label = @{ LocalizedLabels = @(@{ Label = 'All';       LanguageCode = 1033 }) } }
    )
  }
}

Write-Host '7/9 Adding dcfg_personal_note (Memo 1000)...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.MemoAttributeMetadata'
  SchemaName    = 'dcfg_personal_note'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Personal Note'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  MaxLength     = 1000
  Format        = 'TextArea'
}

Write-Host '8/9 Adding dcfg_sent_at (DateTime)...'
Add-Column @{
  '@odata.type'    = '#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
  SchemaName       = 'dcfg_sent_at'
  DisplayName      = @{ LocalizedLabels = @(@{ Label = 'Sent At'; LanguageCode = 1033 }) }
  RequiredLevel    = @{ Value = 'None' }
  Format           = 'DateAndTime'
  DateTimeBehavior = @{ Value = 'UserLocal' }
}

Write-Host '9/9 Adding dcfg_active_flag (Boolean)...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
  SchemaName    = 'dcfg_active_flag'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Active'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  DefaultValue  = $true
  OptionSet     = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
    TrueOption    = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = 'Active';  LanguageCode = 1033 }) } }
    FalseOption   = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = 'Retired'; LanguageCode = 1033 }) } }
  }
}

Write-Host 'dcfg_intake_delegation created in DCFGSystemTest with all columns.'
