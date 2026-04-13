$ErrorActionPreference = 'Stop'
$orgUrl = 'https://org0c17e98d.crm.dynamics.com'
$solution = 'DCFGSystemTest'

# Bearer token via Az module (established DCFG pattern)
$tokenObj = Get-AzAccessToken -ResourceUrl $orgUrl -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $tokenObj.Token).Password
if (-not $token) { throw 'Failed to obtain bearer token via Get-AzAccessToken' }

$headers = @{
  'Authorization'            = "Bearer $token"
  'Content-Type'             = 'application/json; charset=utf-8'
  'OData-MaxVersion'         = '4.0'
  'OData-Version'            = '4.0'
  'Accept'                   = 'application/json'
  'MSCRM.SolutionUniqueName' = $solution
}

Write-Host '1/7 Creating dcfg_intake_date table...'
$tableBody = @{
  '@odata.type'         = '#Microsoft.Dynamics.CRM.EntityMetadata'
  SchemaName            = 'dcfg_intake_date'
  DisplayName           = @{ LocalizedLabels = @(@{ Label = 'Intake Date'; LanguageCode = 1033 }) }
  DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = 'Intake Dates'; LanguageCode = 1033 }) }
  Description           = @{ LocalizedLabels = @(@{ Label = 'Customer-entered important date from onboarding concierge'; LanguageCode = 1033 }) }
  HasActivities         = $false
  HasNotes              = $true
  OwnershipType         = 'UserOwned'
  PrimaryNameAttribute  = 'dcfg_name'
  Attributes            = @(
    @{
      '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
      SchemaName    = 'dcfg_name'
      DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Label'; LanguageCode = 1033 }) }
      RequiredLevel = @{ Value = 'ApplicationRequired' }
      MaxLength     = 200
      FormatName    = @{ Value = 'Text' }
      IsPrimaryName = $true
    }
  )
} | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions" -Method POST -Headers $headers -Body $tableBody
Write-Host 'Table created. Waiting 10s for metadata cache...'
Start-Sleep 10

Write-Host '2/7 Adding lookup to dcfg_intake_session...'
$lookupBody = @{
  '@odata.type'               = '#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
  SchemaName                  = 'dcfg_dcfg_intake_session_dcfg_intake_date'
  ReferencedEntity            = 'dcfg_intake_session'
  ReferencingEntity           = 'dcfg_intake_date'
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
  Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='dcfg_intake_date')/Attributes" -Method POST -Headers $headers -Body ($body | ConvertTo-Json -Depth 20 -Compress)
  Start-Sleep 2
}

Write-Host '3/7 Adding dcfg_due_date (DateOnly)...'
Add-Column @{
  '@odata.type'    = '#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
  SchemaName       = 'dcfg_due_date'
  DisplayName      = @{ LocalizedLabels = @(@{ Label = 'Due Date'; LanguageCode = 1033 }) }
  RequiredLevel    = @{ Value = 'None' }
  Format           = 'DateOnly'
  DateTimeBehavior = @{ Value = 'DateOnly' }
}

Write-Host '4/7 Adding dcfg_category (OptionSet)...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
  SchemaName    = 'dcfg_category'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Category'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  OptionSet     = @{
    '@odata.type' = '#Microsoft.Dynamics.CRM.OptionSetMetadata'
    IsGlobal      = $false
    OptionSetType = 'Picklist'
    Options       = @(
      @{ Value = 100000000; Label = @{ LocalizedLabels = @(@{ Label = 'Inspection';           LanguageCode = 1033 }) } }
      @{ Value = 100000001; Label = @{ LocalizedLabels = @(@{ Label = 'Cert Expiration';      LanguageCode = 1033 }) } }
      @{ Value = 100000002; Label = @{ LocalizedLabels = @(@{ Label = 'Contract Anniversary'; LanguageCode = 1033 }) } }
      @{ Value = 100000003; Label = @{ LocalizedLabels = @(@{ Label = 'Insurance';            LanguageCode = 1033 }) } }
      @{ Value = 100000004; Label = @{ LocalizedLabels = @(@{ Label = 'Other';                LanguageCode = 1033 }) } }
    )
  }
}

Write-Host '5/7 Adding dcfg_notes (Memo 1000)...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.MemoAttributeMetadata'
  SchemaName    = 'dcfg_notes'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Notes'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  MaxLength     = 1000
  Format        = 'TextArea'
}

Write-Host '6/7 Adding dcfg_location_ref (String 100)...'
Add-Column @{
  '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
  SchemaName    = 'dcfg_location_ref'
  DisplayName   = @{ LocalizedLabels = @(@{ Label = 'Location Reference'; LanguageCode = 1033 }) }
  RequiredLevel = @{ Value = 'None' }
  MaxLength     = 100
  FormatName    = @{ Value = 'Text' }
}

Write-Host '7/7 Adding dcfg_active_flag (Boolean)...'
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

Write-Host 'dcfg_intake_date created in DCFGSystemTest with all columns.'
