# =============================================================================
# Nora Training Generator — Seeds guided training tasks for all SPA screens
# Target: Staging (org88778bb0)
# Table: dcfg_nora_training (entity set: discovered at runtime)
# =============================================================================

. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org88778bb0.crm.dynamics.com/'

$orgUrl = 'https://org88778bb0.crm.dynamics.com'
$apiBase = "$orgUrl/api/data/v9.2"
$solutionName = 'DCFGSystemTest'

Invoke-DataverseCommands {

    # Refresh token for raw REST calls
    $token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "$orgUrl/" -AsSecureString).Token).Password
    $h = @{
        'Authorization' = "Bearer $token"; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'
        'Accept' = 'application/json'; 'Content-Type' = 'application/json; charset=utf-8'
    }

    Write-Host "=== NORA TRAINING GENERATOR ===" -ForegroundColor Cyan

    # =========================================================================
    # STEP 1: Discover or create the dcfg_nora_training table
    # =========================================================================
    Write-Host "`n--- Checking dcfg_nora_training table ---" -ForegroundColor Yellow

    $entitySetName = $null
    try {
        $entityDef = Invoke-RestMethod `
            -Uri "$apiBase/EntityDefinitions(LogicalName='dcfg_nora_training')?`$select=EntitySetName,LogicalName" `
            -Headers $h
        $entitySetName = $entityDef.EntitySetName
        Write-Host "  Table exists. EntitySetName: $entitySetName" -ForegroundColor Green
    }
    catch {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 404) {
            Write-Host "  Table not found. Creating dcfg_nora_training..." -ForegroundColor Yellow

            $tableBody = @{
                '@odata.type' = '#Microsoft.Dynamics.CRM.EntityMetadata'
                SchemaName = 'dcfg_nora_training'
                DisplayName = @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.Label'
                    LocalizedLabels = @(@{
                        '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'
                        Label = 'Nora Training'
                        LanguageCode = 1033
                    })
                }
                DisplayCollectionName = @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.Label'
                    LocalizedLabels = @(@{
                        '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'
                        Label = 'Nora Trainings'
                        LanguageCode = 1033
                    })
                }
                Description = @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.Label'
                    LocalizedLabels = @(@{
                        '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'
                        Label = 'Guided training tasks for the DCFG Contracting Suite'
                        LanguageCode = 1033
                    })
                }
                HasActivities = $false
                HasNotes = $false
                OwnershipType = 'UserOwned'
                IsActivity = $false
                PrimaryNameAttribute = 'dcfg_task'
                Attributes = @(
                    @{
                        '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
                        SchemaName = 'dcfg_task'
                        DisplayName = @{
                            '@odata.type' = '#Microsoft.Dynamics.CRM.Label'
                            LocalizedLabels = @(@{
                                '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'
                                Label = 'Task'
                                LanguageCode = 1033
                            })
                        }
                        IsPrimaryName = $true
                        RequiredLevel = @{ Value = 'ApplicationRequired' }
                        MaxLength = 500
                        FormatName = @{ Value = 'Text' }
                    }
                )
            } | ConvertTo-Json -Depth 15

            try {
                Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" `
                    -Method POST `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes($tableBody)) `
                    -Headers ($h + @{ 'MSCRM.SolutionUniqueName' = $solutionName }) | Out-Null
                Write-Host "  Table created." -ForegroundColor Green
            }
            catch {
                Write-Host "  ERROR creating table: $($_.ErrorDetails.Message)" -ForegroundColor Red
                return
            }

            # Now add the additional columns
            $columns = @(
                @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
                    SchemaName = 'dcfg_screen'
                    DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Screen'; LanguageCode = 1033 }) }
                    RequiredLevel = @{ Value = 'ApplicationRequired' }
                    MaxLength = 100
                    FormatName = @{ Value = 'Text' }
                },
                @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.MemoAttributeMetadata'
                    SchemaName = 'dcfg_steps_json'
                    DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Steps (JSON)'; LanguageCode = 1033 }) }
                    RequiredLevel = @{ Value = 'None' }
                    MaxLength = 100000
                    Format = 'Text'
                },
                @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
                    SchemaName = 'dcfg_difficulty'
                    DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Difficulty'; LanguageCode = 1033 }) }
                    RequiredLevel = @{ Value = 'None' }
                    MaxLength = 50
                    FormatName = @{ Value = 'Text' }
                },
                @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.StringAttributeMetadata'
                    SchemaName = 'dcfg_estimated_time'
                    DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Estimated Time'; LanguageCode = 1033 }) }
                    RequiredLevel = @{ Value = 'None' }
                    MaxLength = 50
                    FormatName = @{ Value = 'Text' }
                },
                @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
                    SchemaName = 'dcfg_active_flag'
                    DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Active'; LanguageCode = 1033 }) }
                    RequiredLevel = @{ Value = 'None' }
                    OptionSet = @{
                        '@odata.type' = '#Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
                        TrueOption = @{ Value = 1; Label = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Yes'; LanguageCode = 1033 }) } }
                        FalseOption = @{ Value = 0; Label = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'No'; LanguageCode = 1033 }) } }
                    }
                    DefaultValue = $true
                },
                @{
                    '@odata.type' = '#Microsoft.Dynamics.CRM.IntegerAttributeMetadata'
                    SchemaName = 'dcfg_sort_order'
                    DisplayName = @{ '@odata.type' = '#Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Sort Order'; LanguageCode = 1033 }) }
                    RequiredLevel = @{ Value = 'None' }
                    Format = 'None'
                    MinValue = 0
                    MaxValue = 9999
                }
            )

            foreach ($col in $columns) {
                $colBody = $col | ConvertTo-Json -Depth 15
                try {
                    Invoke-RestMethod `
                        -Uri "$apiBase/EntityDefinitions(LogicalName='dcfg_nora_training')/Attributes" `
                        -Method POST `
                        -Body ([System.Text.Encoding]::UTF8.GetBytes($colBody)) `
                        -Headers ($h + @{ 'MSCRM.SolutionUniqueName' = $solutionName }) | Out-Null
                    Write-Host "  Column created: $($col.SchemaName)" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ERROR creating $($col.SchemaName): $($_.ErrorDetails.Message)" -ForegroundColor Red
                }
            }

            # Re-read entity set name after creation
            Start-Sleep -Seconds 5
            $entityDef = Invoke-RestMethod `
                -Uri "$apiBase/EntityDefinitions(LogicalName='dcfg_nora_training')?`$select=EntitySetName" `
                -Headers $h
            $entitySetName = $entityDef.EntitySetName
            Write-Host "  EntitySetName resolved: $entitySetName" -ForegroundColor Green
        }
        else {
            Write-Host "  ERROR checking table: $($_.ErrorDetails.Message)" -ForegroundColor Red
            return
        }
    }

    if (-not $entitySetName) {
        Write-Host "  FATAL: Could not resolve entity set name." -ForegroundColor Red
        return
    }

    # =========================================================================
    # STEP 2: Training content — all 15 screens
    # =========================================================================
    Write-Host "`n--- Building training records ---" -ForegroundColor Yellow

    $sortCounter = 0
    $trainingRecords = @()

    # --- 1. Dashboard (SalesDashboard) ---
    $trainingRecords += @{
        screen = 'SalesDashboard'; task = 'Read your KPI cards'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open the app. The Dashboard loads automatically as your home screen.'; tip = 'You can also click "Dashboard" in the left sidebar at any time.' }
            @{ step = 2; instruction = 'Look at the five KPI cards across the top. Each one shows a number and a label like "Active Contracts" or "Pending Send".'; tip = 'A red badge in the corner means something needs your attention.' }
            @{ step = 3; instruction = 'Click any KPI card to see more details in the panel below it.'; tip = 'The card you clicked will get a green bottom border so you know which one is active.' }
        )
    }
    $trainingRecords += @{
        screen = 'SalesDashboard'; task = 'Search for a document from the Dashboard'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Look for the round search button in the bottom-right corner of the screen.' }
            @{ step = 2; instruction = 'Click it, then type part of a customer name, contract number, or document name.' }
            @{ step = 3; instruction = 'Results will appear as you type. Click one to jump to that record.' }
        )
    }
    $trainingRecords += @{
        screen = 'SalesDashboard'; task = 'Review pending documents in the approval queue'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Scroll down on the Dashboard to the Document Approval Queue section.' }
            @{ step = 2; instruction = 'Use the filter buttons (All, Sales, Operations) to narrow down the list.' }
            @{ step = 3; instruction = 'Click the Pending tab to see documents waiting for review.' }
            @{ step = 4; instruction = 'Use the action buttons on each row: Approve (green), Request Info (blue), Return (orange), or Delete (red).'; tip = 'Deleting asks for confirmation first, so you will not lose anything by accident.' }
        )
    }

    # --- 2. CustomerList ---
    $trainingRecords += @{
        screen = 'CustomerList'; task = 'Create a new customer'
        difficulty = 'Beginner'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Customers" in the left sidebar.' }
            @{ step = 2; instruction = 'Click the "New Customer" button at the top right of the page.' }
            @{ step = 3; instruction = 'Fill in the customer name and contact details in the panel that appears.' }
            @{ step = 4; instruction = 'Click "Save" to create the customer.'; tip = 'A green notification will pop up in the bottom-right corner when it saves successfully.' }
        )
    }
    $trainingRecords += @{
        screen = 'CustomerList'; task = 'Search and sort the customer list'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Customers" in the left sidebar.' }
            @{ step = 2; instruction = 'Type a name or keyword into the search box above the table.' }
            @{ step = 3; instruction = 'Click any column header to sort by that column. Click it again to reverse the order.'; tip = 'The arrow icon next to the column name shows which direction the sort is going.' }
        )
    }
    $trainingRecords += @{
        screen = 'CustomerList'; task = 'Open a customer to edit their details'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Customers" in the left sidebar.' }
            @{ step = 2; instruction = 'Find the customer you want by searching or scrolling.' }
            @{ step = 3; instruction = 'Click anywhere on their row to open the Customer Detail screen.' }
        )
    }

    # --- 3. CustomerDetail ---
    $trainingRecords += @{
        screen = 'CustomerDetail'; task = 'Edit a customer contact'
        difficulty = 'Beginner'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open a customer by clicking their row on the Customers list.' }
            @{ step = 2; instruction = 'Find the contact information fields (name, email, phone) at the top of the page.' }
            @{ step = 3; instruction = 'Click "Edit" to make the fields editable, then change what you need.' }
            @{ step = 4; instruction = 'Click "Save" when you are done.'; tip = 'If you navigate away without saving, the app will warn you about unsaved changes.' }
        )
    }
    $trainingRecords += @{
        screen = 'CustomerDetail'; task = 'View related records using tabs'
        difficulty = 'Beginner'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open a customer record.' }
            @{ step = 2; instruction = 'Look at the tabs below the contact information: MSAs, Contracts, Programs, Locations, Onboarding.' }
            @{ step = 3; instruction = 'Click any tab to see related records. For example, click "Contracts" to see all contracts for this customer.' }
            @{ step = 4; instruction = 'Click any item in the tab to jump to its detail screen.'; tip = 'This is a great way to get a full picture of a customer at a glance.' }
        )
    }

    # --- 4. ContractList ---
    $trainingRecords += @{
        screen = 'ContractList'; task = 'Search for a contract'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Contracts" in the left sidebar.' }
            @{ step = 2; instruction = 'Type a contract number, customer name, or keyword into the search box.' }
            @{ step = 3; instruction = 'The table will filter in real-time as you type.' }
        )
    }
    $trainingRecords += @{
        screen = 'ContractList'; task = 'Filter contracts by status'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Contracts" in the left sidebar.' }
            @{ step = 2; instruction = 'Look at the status badges on each row (Draft, Generated, Sent, Signed, etc.).' }
            @{ step = 3; instruction = 'Click any column header to sort. Sort by "Status" to group all contracts with the same status together.'; tip = 'Colored badges make it easy to spot what stage each contract is in.' }
        )
    }

    # --- 5. ContractDetail ---
    $trainingRecords += @{
        screen = 'ContractDetail'; task = 'View contract status and Exhibit A lines'
        difficulty = 'Beginner'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open a contract by clicking its row in the Contracts list.' }
            @{ step = 2; instruction = 'The colored banner at the top shows the current status (Draft, Sent, Signed, etc.).' }
            @{ step = 3; instruction = 'Scroll down to find the Exhibit A section, which lists all the line items for this contract.' }
            @{ step = 4; instruction = 'Each line shows the vendor, cost code, and dollar amount.' }
        )
    }
    $trainingRecords += @{
        screen = 'ContractDetail'; task = 'Generate a contract document'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open a contract that is in Draft status.' }
            @{ step = 2; instruction = 'Click the "Generate Document" button at the top of the page.' }
            @{ step = 3; instruction = 'The system will create a document request. You will see a notification that the document is being generated.'; tip = 'Generation usually takes 10-30 seconds. The status will change to "Generated" when it is done.' }
            @{ step = 4; instruction = 'Once complete, you can view or download the generated document from the document history section.' }
        )
    }
    $trainingRecords += @{
        screen = 'ContractDetail'; task = 'Void a contract'
        difficulty = 'Advanced'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open the contract you need to void.' }
            @{ step = 2; instruction = 'Click the "Void" button. This is only available for contracts that have not been signed.' }
            @{ step = 3; instruction = 'A confirmation dialog will appear. Read it carefully, then click "Confirm" to void the contract.'; tip = 'Voiding cannot be undone. The contract will show a red "Void" status banner.' }
        )
    }

    # --- 6. NewContractWizard ---
    $trainingRecords += @{
        screen = 'NewContractWizard'; task = 'Create a new contract using the 5-step wizard'
        difficulty = 'Intermediate'; estimated_time = '8 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Contracts" in the sidebar, then click "New Contract" at the top right.' }
            @{ step = 2; instruction = 'Step 1: Choose the contract family (Bancroft or Decades) and type (Work Order, Amendment, or Contractor MSA). Click "Next".'; tip = 'The contract family determines which template and rules apply.' }
            @{ step = 3; instruction = 'Step 2: Select the customer and location. The system will auto-fill details from existing records. Click "Next".' }
            @{ step = 4; instruction = 'Step 3: Add Exhibit A line items. Pick a vendor, cost code, and enter the dollar amount for each line. Click "Add Line" for more rows. Click "Next".' }
            @{ step = 5; instruction = 'Step 4: Review your choices. Fill in any remaining details like notes or special terms. Click "Next".' }
            @{ step = 6; instruction = 'Step 5: Review the full summary, then click "Generate" to create the contract document.'; tip = 'You can click "Back" at any step to make corrections before generating.' }
        )
    }
    $trainingRecords += @{
        screen = 'NewContractWizard'; task = 'Save a contract as a draft and come back later'
        difficulty = 'Beginner'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Start the New Contract wizard and fill in at least the first step.' }
            @{ step = 2; instruction = 'Click "Save as Draft" (available on any step).' }
            @{ step = 3; instruction = 'Your work is saved. You can find it later in the Contracts list with a "Draft" badge.'; tip = 'Draft contracts can be edited and completed at any time.' }
        )
    }

    # --- 7. NewProposalWizard ---
    $trainingRecords += @{
        screen = 'NewProposalWizard'; task = 'Create a new proposal using the interview wizard'
        difficulty = 'Advanced'; estimated_time = '10 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Contracts" in the sidebar, then click "New Proposal".' }
            @{ step = 2; instruction = 'The wizard asks you questions one at a time in an interview style. Answer each question and click "Next".'; tip = 'Take your time. The wizard guides you through everything you need.' }
            @{ step = 3; instruction = 'If the customer does not exist yet, you can create them right inside the wizard.' }
            @{ step = 4; instruction = 'Enter MSA rates and pricing details when prompted.' }
            @{ step = 5; instruction = 'At the final step, review all your answers and click "Generate" to create the proposal document.' }
        )
    }
    $trainingRecords += @{
        screen = 'NewProposalWizard'; task = 'Search for an existing customer during proposal creation'
        difficulty = 'Intermediate'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Start the New Proposal wizard.' }
            @{ step = 2; instruction = 'When the wizard asks for a customer, start typing the customer name in the search field.' }
            @{ step = 3; instruction = 'Select the correct customer from the dropdown results.'; tip = 'If you do not see the customer, you can create a new one right from here.' }
        )
    }

    # --- 8. MsaList ---
    $trainingRecords += @{
        screen = 'MsaList'; task = 'Search for an MSA'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "MSAs" in the left sidebar.' }
            @{ step = 2; instruction = 'Type a customer name or MSA number into the search box above the table.' }
            @{ step = 3; instruction = 'The list filters as you type. Click a row to open the MSA detail.' }
        )
    }
    $trainingRecords += @{
        screen = 'MsaList'; task = 'Sort MSAs by column'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "MSAs" in the left sidebar.' }
            @{ step = 2; instruction = 'Click any column header (like Customer or Status) to sort the list.' }
            @{ step = 3; instruction = 'Click the same header again to flip between ascending and descending order.'; tip = 'The arrow icon shows the current sort direction.' }
        )
    }

    # --- 9. MsaDetail ---
    $trainingRecords += @{
        screen = 'MsaDetail'; task = 'View and manage MSA rates'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open an MSA by clicking its row in the MSA list.' }
            @{ step = 2; instruction = 'Look for the Rates section, which shows all pricing rates tied to this MSA.' }
            @{ step = 3; instruction = 'Each rate shows the description, unit, and price. You can add or edit rates from here.'; tip = 'These rates are used automatically when creating new contracts under this MSA.' }
        )
    }
    $trainingRecords += @{
        screen = 'MsaDetail'; task = 'Generate an MSA document'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open the MSA you want to generate a document for.' }
            @{ step = 2; instruction = 'Click "Generate Document" at the top of the page.' }
            @{ step = 3; instruction = 'The system creates a document request and generates the MSA in the background.' }
            @{ step = 4; instruction = 'Check the document history section for the completed document.'; tip = 'You will see a notification when generation finishes.' }
        )
    }
    $trainingRecords += @{
        screen = 'MsaDetail'; task = 'View contracts linked to an MSA'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open an MSA record.' }
            @{ step = 2; instruction = 'Click the "Contracts" tab to see all contracts created under this MSA.' }
            @{ step = 3; instruction = 'Click any contract row to jump directly to its detail page.' }
        )
    }

    # --- 10. Locations ---
    $trainingRecords += @{
        screen = 'Locations'; task = 'Filter locations by customer'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Locations" in the left sidebar.' }
            @{ step = 2; instruction = 'Use the customer filter dropdown above the table to select a specific customer.' }
            @{ step = 3; instruction = 'The table updates to show only locations for that customer.' }
        )
    }
    $trainingRecords += @{
        screen = 'Locations'; task = 'Search locations and check compliance'
        difficulty = 'Intermediate'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Locations" in the left sidebar.' }
            @{ step = 2; instruction = 'Type a location name, address, or keyword into the search box.' }
            @{ step = 3; instruction = 'Look at the compliance badges on each row. Green means compliant, amber means attention needed, and red means out of compliance.'; tip = 'Click a location to see exactly which documents or certifications are missing.' }
        )
    }

    # --- 11. LocationDetail ---
    $trainingRecords += @{
        screen = 'LocationDetail'; task = 'Edit location details'
        difficulty = 'Beginner'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open a location by clicking its row in the Locations list.' }
            @{ step = 2; instruction = 'Click "Edit" to make the fields editable.' }
            @{ step = 3; instruction = 'Update the address, type, or other details as needed.' }
            @{ step = 4; instruction = 'Click "Save" to keep your changes.'; tip = 'Some fields may be locked depending on the location status.' }
        )
    }
    $trainingRecords += @{
        screen = 'LocationDetail'; task = 'Upload a certification document'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open the location that needs a new certification.' }
            @{ step = 2; instruction = 'Scroll down to the Compliance Documents section.' }
            @{ step = 3; instruction = 'Click "Upload Certification" and select the file from your device.' }
            @{ step = 4; instruction = 'The system sends the file to be stored and linked to this location.'; tip = 'Supported formats include PDF and common image types.' }
        )
    }
    $trainingRecords += @{
        screen = 'LocationDetail'; task = 'View and manage appliances'
        difficulty = 'Intermediate'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open a location record.' }
            @{ step = 2; instruction = 'Look for the Appliances section. This lists all equipment tracked at this location.' }
            @{ step = 3; instruction = 'Click "Add Appliance" to register new equipment, or click an existing one to edit its details.'; tip = 'Appliance types are managed in the Admin screen.' }
        )
    }

    # --- 12. Onboarding ---
    $trainingRecords += @{
        screen = 'Onboarding'; task = 'Create a new onboarding case'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Onboarding" in the left sidebar.' }
            @{ step = 2; instruction = 'Click "New Case" at the top right of the page.' }
            @{ step = 3; instruction = 'Fill in the customer, location, and any notes in the panel that appears.' }
            @{ step = 4; instruction = 'Click "Create" to start the onboarding case.'; tip = 'Due dates for each step are automatically calculated based on the template.' }
        )
    }
    $trainingRecords += @{
        screen = 'Onboarding'; task = 'Filter and search onboarding cases'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Onboarding" in the left sidebar.' }
            @{ step = 2; instruction = 'Use the status filter buttons to show only cases in a certain stage (Not Started, In Progress, Live, etc.).' }
            @{ step = 3; instruction = 'Type in the search box to find a specific case by customer or location name.' }
        )
    }
    $trainingRecords += @{
        screen = 'Onboarding'; task = 'Delete and restore an onboarding case'
        difficulty = 'Advanced'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Find the case you want to remove in the Onboarding list.' }
            @{ step = 2; instruction = 'Click the delete button on the row. Confirm when prompted.'; tip = 'Deleted cases are not permanently removed. They are soft-deleted and can be restored.' }
            @{ step = 3; instruction = 'To see deleted cases, toggle the "Show Deleted" switch at the top of the list.' }
            @{ step = 4; instruction = 'Find the deleted case and click "Restore" to bring it back.' }
        )
    }

    # --- 13. OnboardingDetail ---
    $trainingRecords += @{
        screen = 'OnboardingDetail'; task = 'Edit onboarding steps and add notes'
        difficulty = 'Intermediate'; estimated_time = '4 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open an onboarding case by clicking its row in the list.' }
            @{ step = 2; instruction = 'Expand a phase section (like Sales Proposal or Account Setup) to see the individual steps.' }
            @{ step = 3; instruction = 'Click on a step to edit it. You can set the completed date, add notes, or paste an evidence URL.' }
            @{ step = 4; instruction = 'Your changes save automatically when you click away from the field.'; tip = 'Use the microphone button next to any notes field to dictate instead of typing.' }
        )
    }
    $trainingRecords += @{
        screen = 'OnboardingDetail'; task = 'Use voice input for notes'
        difficulty = 'Beginner'; estimated_time = '1 minute'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open an onboarding case and find any notes field (case notes or step notes).' }
            @{ step = 2; instruction = 'Click the small microphone button next to the text box.' }
            @{ step = 3; instruction = 'Speak clearly. Your words will appear as text in the notes field.'; tip = 'This works best on iPad Safari or Chrome desktop. The button turns red while listening.' }
        )
    }
    $trainingRecords += @{
        screen = 'OnboardingDetail'; task = 'Close or reopen a case'
        difficulty = 'Advanced'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Open the onboarding case you want to close.' }
            @{ step = 2; instruction = 'Click the "Close Case" button at the top of the page.' }
            @{ step = 3; instruction = 'Confirm the action. The case will be locked and all fields will become read-only.'; tip = 'Closing a case writes an entry to the audit log.' }
            @{ step = 4; instruction = 'If you need to reopen it later, click "Reopen Case". The status will go back to In Progress.' }
        )
    }

    # --- 14. SendQueue ---
    $trainingRecords += @{
        screen = 'SendQueue'; task = 'Review pending documents and mark them as sent'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Send Queue" in the left sidebar.' }
            @{ step = 2; instruction = 'The "Send" tab shows documents that are ready to be sent out to clients.' }
            @{ step = 3; instruction = 'Review each document in the list. When you have sent one (via email or another method), click "Mark Sent".'; tip = 'This updates the document status across the whole system.' }
        )
    }
    $trainingRecords += @{
        screen = 'SendQueue'; task = 'Mark a document as signed and complete'
        difficulty = 'Intermediate'; estimated_time = '2 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Send Queue" in the left sidebar.' }
            @{ step = 2; instruction = 'Switch to the "Completion" tab to see documents that have been sent.' }
            @{ step = 3; instruction = 'When a signed copy comes back, find it in the list and click "Mark Complete".'; tip = 'Completed documents are locked from further editing.' }
        )
    }

    # --- 15. Admin ---
    $trainingRecords += @{
        screen = 'Admin'; task = 'Manage document templates'
        difficulty = 'Advanced'; estimated_time = '4 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Admin" in the left sidebar. This screen is only available to users with the Admin role.' }
            @{ step = 2; instruction = 'Find the "Templates" section. This lists all document templates used for contract and MSA generation.' }
            @{ step = 3; instruction = 'Click a template to view or edit its details. You can update the name, description, or linked fields.' }
            @{ step = 4; instruction = 'Click "Add Template" to create a new one.'; tip = 'Templates are validated automatically after upload.' }
        )
    }
    $trainingRecords += @{
        screen = 'Admin'; task = 'Manage vendors and cost codes'
        difficulty = 'Intermediate'; estimated_time = '3 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Admin" in the left sidebar.' }
            @{ step = 2; instruction = 'Find the "Vendors" section. Here you can add, edit, or view all vendor records.' }
            @{ step = 3; instruction = 'Switch to the "Cost Codes" section to manage the cost code list used in Exhibit A lines.'; tip = 'Vendors and cost codes appear as dropdown options throughout the app, so keeping them up to date is important.' }
        )
    }
    $trainingRecords += @{
        screen = 'Admin'; task = 'Configure onboarding step templates'
        difficulty = 'Advanced'; estimated_time = '4 minutes'; sort = ($sortCounter++)
        steps = @(
            @{ step = 1; instruction = 'Click "Admin" in the left sidebar.' }
            @{ step = 2; instruction = 'Find the "Onboarding Steps" section. These are the template steps that get copied into each new onboarding case.' }
            @{ step = 3; instruction = 'Click a step to edit its name, phase, turnaround days, or description.' }
            @{ step = 4; instruction = 'The turnaround days value determines the due date when a new case is created.'; tip = 'Changes here only affect new cases. Existing cases keep their original steps.' }
        )
    }

    # =========================================================================
    # STEP 3: Upsert each record — skip if screen+task already exists
    # =========================================================================
    Write-Host "`n--- Loading existing training records ---" -ForegroundColor Yellow

    $existingRecords = @()
    try {
        $response = (Invoke-RestMethod `
            -Uri "$apiBase/$entitySetName`?`$select=dcfg_screen,dcfg_task" `
            -Headers $h)
        $existingRecords = $response.value
        Write-Host "  Found $($existingRecords.Count) existing training records." -ForegroundColor Cyan
    }
    catch {
        Write-Host "  No existing records or table is new. Starting fresh." -ForegroundColor Yellow
    }

    # Build a lookup set for duplicate detection
    $existingKeys = @{}
    foreach ($rec in $existingRecords) {
        $key = "$($rec.dcfg_screen)|$($rec.dcfg_task)"
        $existingKeys[$key] = $true
    }

    $created = 0
    $skipped = 0

    foreach ($training in $trainingRecords) {
        $lookupKey = "$($training.screen)|$($training.task)"

        if ($existingKeys.ContainsKey($lookupKey)) {
            Write-Host "  SKIP: [$($training.screen)] $($training.task)" -ForegroundColor Yellow
            $skipped++
            continue
        }

        $stepsJson = $training.steps | ConvertTo-Json -Depth 5 -Compress
        # Wrap in array if single step (ConvertTo-Json returns object for single-element arrays)
        if ($training.steps.Count -eq 1 -and -not $stepsJson.StartsWith('[')) {
            $stepsJson = "[$stepsJson]"
        }

        $body = @{
            dcfg_screen         = $training.screen
            dcfg_task           = $training.task
            dcfg_steps_json     = $stepsJson
            dcfg_estimated_time = $training.estimated_time
        }

        try {
            $recordBody = $body | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Uri "$apiBase/$entitySetName" `
                -Method POST `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($recordBody)) `
                -Headers $h | Out-Null
            Write-Host "  CREATED: [$($training.screen)] $($training.task)" -ForegroundColor Green
            $created++
        }
        catch {
            Write-Host "  ERROR: [$($training.screen)] $($training.task) - $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
    }

    # =========================================================================
    # SUMMARY
    # =========================================================================
    Write-Host "`n=== TRAINING GENERATION COMPLETE ===" -ForegroundColor Cyan
    Write-Host "  Total tasks: $($trainingRecords.Count)" -ForegroundColor White
    Write-Host "  Created:     $created" -ForegroundColor Green
    Write-Host "  Skipped:     $skipped" -ForegroundColor Yellow
    Write-Host "  Entity set:  $entitySetName" -ForegroundColor White
}
