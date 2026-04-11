# BidComp Phase 1: Bancroft Monthly Reporting MVP

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver working Bancroft monthly reporting — Dashboard, Tracker, Invoices, Buy Sheet, Monthly Report generator — replacing the broken spreadsheet workflow with a live system that never shows #REF!.

**Architecture:** Isolated React 17.0.2 + Vite app deployed to its own Power Pages code site. 3 new Dataverse tables (dcfg_prime_contract, dcfg_phase, dcfg_invoice) in the DCFGSystemTest solution. Reads existing dcfg_vendor, dcfg_customer, dcfg_property tables. Produces Excel exports matching Bancroft's current spreadsheet formats.

**Tech Stack:** React 17.0.2, Vite 5.2.0, react-router-dom 6.3.0, HashRouter, Power Pages Web API, Dataverse OData, SheetJS (xlsx) for Excel export/import. (Note: spec says React 16.14 but dcfg-shell uses 17.0.2 — match dcfg-shell for compatibility.)

**Spec Reference:** `C:\DCFG\docs\superpowers\specs\2026-04-02-bidcomp-module-design.md`

**SPA Reference Model:** `C:\DCFG\spa\dcfg-shell\` (READ for patterns, copy to new app)

**IMPORTANT — spa/ read-only rule:** `C:\DCFG\spa\` is read-only per CLAUDE.md, but `dcfg-bidcomp` is a NEW directory created fresh — not part of the existing SPA. The read-only rule protects existing apps (dcfg-shell, dcfg-sales, etc.). Creating `spa/dcfg-bidcomp/` is allowed. Ask the operator for explicit confirmation before first write.

**Prerequisites:** Before starting, verify:
1. `pac auth list` shows index [1] as active (Test environment)
2. DCFGSystemTest solution exists: `pac solution list`
3. Research data exists at `C:\DCFG\research\bancroft-ghsp-fy26\` (Sage Budget.xlsx, Tracker with Dashboard.xlsx, etc.)
4. Existing tables are accessible: `GET /api/data/v9.2/dcfg_vendors?$top=1`, `dcfg_customers?$top=1`, `dcfg_properties?$top=1`

**Entity set naming:** Dataverse auto-generates entity set names. After creating each table (Tasks 1-3), read back the actual EntitySetName from metadata and update `constants.js` accordingly. Do NOT hardcode assumed names until verified.

---

## File Structure

```
C:\DCFG\spa\dcfg-bidcomp\
├── index.html
├── vite.config.js
├── package.json
├── src/
│   ├── main.jsx
│   ├── App.jsx
│   ├── AppRouter.jsx
│   ├── portalApi.js              # Copy from dcfg-shell, add BidComp entity sets
│   ├── usePortalUser.jsx         # Copy from dcfg-shell
│   ├── useTableControls.jsx      # Copy from dcfg-shell
│   ├── Toast.jsx                 # Copy from dcfg-shell
│   ├── FieldName.jsx             # Copy from dcfg-shell
│   ├── constants.js              # BidComp-specific enums, cost codes, entity sets
│   ├── excelEngine.js            # Excel export/import using SheetJS
│   ├── hooks/
│   │   ├── usePrimeContract.jsx  # Fetch/cache prime contract data
│   │   ├── usePhases.jsx         # Fetch/cache phases for current contract
│   │   └── useInvoices.jsx       # Fetch/cache invoices for current contract
│   ├── components/
│   │   ├── ContractSelector.jsx  # Customer + FY selector (top bar)
│   │   ├── StatusBadge.jsx       # Color-coded status pill
│   │   ├── CurrencyCell.jsx      # Formatted currency display
│   │   ├── DateCell.jsx          # Formatted date display
│   │   ├── AlertBanner.jsx       # Unbilled work / aging invoice alerts
│   │   └── ExcelButtons.jsx      # Export/Import button pair
│   └── screens/
│       ├── Dashboard.jsx         # Portfolio summary with live counts
│       ├── Tracker.jsx           # FY26 Project Tracker grid (inline edit)
│       ├── Invoices.jsx          # Invoice Tracking grid with alerts
│       ├── BuySheet.jsx          # Budget view by cost code
│       └── MonthlyReport.jsx     # Report generator + Excel download
├── tests/
│   ├── constants.test.js
│   ├── excelEngine.test.js
│   ├── ContractSelector.test.jsx
│   ├── Dashboard.test.jsx
│   ├── Tracker.test.jsx
│   ├── Invoices.test.jsx
│   ├── BuySheet.test.jsx
│   └── MonthlyReport.test.jsx
└── dist/                          # Built output
```

---

## Chunk 1: Dataverse Schema — Create Tables

### Task 1: Create dcfg_prime_contract table

**Files:**
- Create: `C:\DCFG\scripts\bidcomp\create_prime_contract_table.ps1`

- [ ] **Step 1: Write the table creation script**

```powershell
# create_prime_contract_table.ps1
# Creates dcfg_prime_contract table in DCFGSystemTest solution
# Run against Test environment (pac auth index [1])

param(
    [string]$OrgUrl = "https://org0c17e98d.crm.dynamics.com"
)

# Auth
$token = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl $OrgUrl -AsSecureString).Token).Password
$h = @{
    'Authorization' = "Bearer $token"
    'OData-MaxVersion' = '4.0'
    'OData-Version' = '4.0'
    'Accept' = 'application/json'
    'Content-Type' = 'application/json'
    'MSCRM.SolutionUniqueName' = 'DCFGSystemTest'
}

$baseUri = "$OrgUrl/api/data/v9.2"

# Check if table already exists
Write-Host "Checking if dcfg_prime_contract exists..."
try {
    $existing = Invoke-RestMethod -Uri "$baseUri/EntityDefinitions(LogicalName='dcfg_prime_contract')" -Headers $h -Method GET
    Write-Host "Table already exists: $($existing.LogicalName)"
    return
} catch {
    Write-Host "Table does not exist, creating..."
}

# Create table
$tableBody = @{
    "@odata.type" = "#Microsoft.Dynamics.CRM.EntityMetadata"
    "SchemaName" = "dcfg_prime_contract"
    "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Prime Contract"; "LanguageCode" = 1033 }) }
    "DisplayCollectionName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Prime Contracts"; "LanguageCode" = 1033 }) }
    "Description" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Master contract for a fiscal year or project"; "LanguageCode" = 1033 }) }
    "OwnershipType" = "UserOwned"
    "HasNotes" = $true
    "HasActivities" = $false
    "IsActivity" = $false
    "PrimaryNameAttribute" = "dcfg_contract_number"
    "Attributes" = @(
        @{
            "@odata.type" = "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
            "SchemaName" = "dcfg_contract_number"
            "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Contract Number"; "LanguageCode" = 1033 }) }
            "MaxLength" = 100
            "RequiredLevel" = @{ "Value" = "ApplicationRequired" }
            "AttributeType" = "String"
            "FormatName" = @{ "Value" = "Text" }
        }
    )
} | ConvertTo-Json -Depth 10

$body = [System.Text.Encoding]::UTF8.GetBytes($tableBody)
Invoke-RestMethod -Uri "$baseUri/EntityDefinitions" -Headers $h -Method POST -Body $body
Write-Host "Created dcfg_prime_contract table"

# Add remaining columns
$columns = @(
    @{ Name = "dcfg_fiscal_year"; Type = "String"; Label = "Fiscal Year"; MaxLength = 20 },
    @{ Name = "dcfg_total_budget"; Type = "Money"; Label = "Total Budget" },
    @{ Name = "dcfg_general_conditions"; Type = "Money"; Label = "General Conditions" },
    @{ Name = "dcfg_contingency"; Type = "Money"; Label = "Contingency" },
    @{ Name = "dcfg_supervision"; Type = "Money"; Label = "Supervision" },
    @{ Name = "dcfg_design_fees"; Type = "Money"; Label = "Design Fees" },
    @{ Name = "dcfg_active_flag"; Type = "Boolean"; Label = "Active"; Default = $true }
)

foreach ($col in $columns) {
    $attrBody = switch ($col.Type) {
        "String" {
            @{
                "@odata.type" = "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
                "SchemaName" = $col.Name
                "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = $col.Label; "LanguageCode" = 1033 }) }
                "MaxLength" = if ($col.MaxLength) { $col.MaxLength } else { 200 }
                "AttributeType" = "String"
                "FormatName" = @{ "Value" = "Text" }
            }
        }
        "Money" {
            @{
                "@odata.type" = "#Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
                "SchemaName" = $col.Name
                "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = $col.Label; "LanguageCode" = 1033 }) }
                "AttributeType" = "Money"
                "PrecisionSource" = 2
            }
        }
        "Boolean" {
            @{
                "@odata.type" = "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
                "SchemaName" = $col.Name
                "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = $col.Label; "LanguageCode" = 1033 }) }
                "AttributeType" = "Boolean"
                "DefaultValue" = $col.Default
                "OptionSet" = @{
                    "TrueOption" = @{ "Value" = 1; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "Yes"; "LanguageCode" = 1033 }) } }
                    "FalseOption" = @{ "Value" = 0; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "No"; "LanguageCode" = 1033 }) } }
                }
            }
        }
    }

    $json = $attrBody | ConvertTo-Json -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Invoke-RestMethod -Uri "$baseUri/EntityDefinitions(LogicalName='dcfg_prime_contract')/Attributes" -Headers $h -Method POST -Body $bytes
    Write-Host "  Added column: $($col.Name)"
}

# Add Choice columns (contract_type, status)
# Contract Type: TPA=1, Direct=2, B2C=3
$contractTypeBody = @{
    "@odata.type" = "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    "SchemaName" = "dcfg_contract_type"
    "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Contract Type"; "LanguageCode" = 1033 }) }
    "AttributeType" = "Picklist"
    "OptionSet" = @{
        "@odata.type" = "#Microsoft.Dynamics.CRM.OptionSetMetadata"
        "IsGlobal" = $false
        "OptionSetType" = "Picklist"
        "Options" = @(
            @{ "Value" = 100000000; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "TPA"; "LanguageCode" = 1033 }) } },
            @{ "Value" = 100000001; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "Direct"; "LanguageCode" = 1033 }) } },
            @{ "Value" = 100000002; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "B2C"; "LanguageCode" = 1033 }) } }
        )
    }
} | ConvertTo-Json -Depth 10
$bytes = [System.Text.Encoding]::UTF8.GetBytes($contractTypeBody)
Invoke-RestMethod -Uri "$baseUri/EntityDefinitions(LogicalName='dcfg_prime_contract')/Attributes" -Headers $h -Method POST -Body $bytes
Write-Host "  Added column: dcfg_contract_type"

# Status: Active=1, Complete=2, Closed=3
$statusBody = @{
    "@odata.type" = "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    "SchemaName" = "dcfg_status"
    "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Status"; "LanguageCode" = 1033 }) }
    "AttributeType" = "Picklist"
    "OptionSet" = @{
        "@odata.type" = "#Microsoft.Dynamics.CRM.OptionSetMetadata"
        "IsGlobal" = $false
        "OptionSetType" = "Picklist"
        "Options" = @(
            @{ "Value" = 100000000; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "Active"; "LanguageCode" = 1033 }) } },
            @{ "Value" = 100000001; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "Complete"; "LanguageCode" = 1033 }) } },
            @{ "Value" = 100000002; "Label" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "Label" = "Closed"; "LanguageCode" = 1033 }) } }
        )
    }
} | ConvertTo-Json -Depth 10
$bytes = [System.Text.Encoding]::UTF8.GetBytes($statusBody)
Invoke-RestMethod -Uri "$baseUri/EntityDefinitions(LogicalName='dcfg_prime_contract')/Attributes" -Headers $h -Method POST -Body $bytes
Write-Host "  Added column: dcfg_status"

# Date columns
foreach ($dateName in @("dcfg_start_date", "dcfg_end_date")) {
    $label = if ($dateName -eq "dcfg_start_date") { "Start Date" } else { "End Date" }
    $dateBody = @{
        "@odata.type" = "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        "SchemaName" = $dateName
        "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = $label; "LanguageCode" = 1033 }) }
        "AttributeType" = "DateTime"
        "Format" = "DateOnly"
    } | ConvertTo-Json -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($dateBody)
    Invoke-RestMethod -Uri "$baseUri/EntityDefinitions(LogicalName='dcfg_prime_contract')/Attributes" -Headers $h -Method POST -Body $bytes
    Write-Host "  Added column: $dateName"
}

# Customer lookup (to existing dcfg_customer table)
$lookupBody = @{
    "@odata.type" = "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
    "SchemaName" = "dcfg_prime_contract_customer"
    "ReferencedEntity" = "dcfg_customer"
    "ReferencingEntity" = "dcfg_prime_contract"
    "Lookup" = @{
        "@odata.type" = "#Microsoft.Dynamics.CRM.LookupAttributeMetadata"
        "SchemaName" = "dcfg_customer"
        "DisplayName" = @{ "@odata.type" = "#Microsoft.Dynamics.CRM.Label"; "LocalizedLabels" = @(@{ "@odata.type" = "#Microsoft.Dynamics.CRM.LocalizedLabel"; "Label" = "Customer"; "LanguageCode" = 1033 }) }
    }
} | ConvertTo-Json -Depth 10
$bytes = [System.Text.Encoding]::UTF8.GetBytes($lookupBody)
Invoke-RestMethod -Uri "$baseUri/RelationshipDefinitions" -Headers $h -Method POST -Body $bytes
Write-Host "  Added lookup: dcfg_customer -> dcfg_customer"

Write-Host "`nDone: dcfg_prime_contract table created with all columns."
```

- [ ] **Step 2: Verify table exists in Dataverse**

Run: `pwsh -Command "Invoke-RestMethod -Uri 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2/EntityDefinitions(LogicalName=''dcfg_prime_contract'')?$select=LogicalName,EntitySetName' -Headers @{...}"`
Expected: Returns entity with EntitySetName

- [ ] **Step 3: Note the EntitySetName for portalApi constants**

Record the auto-generated entity set name (likely `dcfg_prime_contracts`). This goes into `constants.js`.

---

### Task 2: Create dcfg_phase table

**Files:**
- Create: `C:\DCFG\scripts\bidcomp\create_phase_table.ps1`

- [ ] **Step 1: Write the table creation script**

Use the same PowerShell pattern as Task 1 (auth, check-if-exists, create table, add columns). The dcfg_phase table has additional column types not shown in Task 1. Use these Dataverse metadata types:

- **Integer:** `@odata.type = "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata"`, `Format = "None"`, `MinValue = 0`, `MaxValue = 2147483647`
- **Decimal:** `@odata.type = "#Microsoft.Dynamics.CRM.DecimalAttributeMetadata"`, `MinValue = 0`, `MaxValue = 100000`, `Precision = 2`
- **Multiline String:** Same as String but with `FormatName = @{ Value = "TextArea" }` and larger MaxLength (2000 or 4000)

Columns for this table:
- dcfg_phase_number (Integer)
- dcfg_phase_name (String 200)
- dcfg_property_address (String 300)
- dcfg_cost_code (String 20)
- dcfg_cost_code_desc (String 200)
- dcfg_description (String 2000, multiline)
- dcfg_hours (Decimal)
- dcfg_material (Money)
- dcfg_labor (Money)
- dcfg_equipment (Money)
- dcfg_sub (Money)
- dcfg_other (Money)
- dcfg_budget_total (Money)
- dcfg_spent_to_date (Money)
- dcfg_remaining (Money)
- dcfg_cost_center_id (String 20)
- dcfg_pm_assigned (String 100)
- dcfg_wo_number (String 50)
- dcfg_notes (String 4000, multiline)
- dcfg_requester (String 200)
- dcfg_active_flag (Boolean, default true)
- dcfg_service_line (Picklist: Adult North=100000000, Adult South=100000001, Childrens=100000002, Lakeside=100000003, Corp=100000004, Education=100000005, Day=100000006)
- dcfg_rent_or_own (Picklist: Own=100000000, Rent=100000001, Lease=100000002)
- dcfg_sub_or_self (Picklist: Sub=100000000, Self=100000001)
- dcfg_status (Picklist: Not Started=100000000, In Progress=100000001, Completed=100000002, Out to Bid=100000003, Ready to Start=100000004, Canceled=100000005)
- dcfg_planned_or_unplanned (Picklist: Planned=100000000, Unplanned=100000001)
- dcfg_priority_level (Picklist: Priority 1=100000000, Priority 2=100000001)
- Lookup: dcfg_prime_contract → dcfg_prime_contract
- Lookup: dcfg_property → dcfg_property (existing table)

PrimaryNameAttribute: dcfg_phase_name

- [ ] **Step 2: Run script and verify**
- [ ] **Step 3: Note EntitySetName**

---

### Task 3: Create dcfg_invoice table

**Files:**
- Create: `C:\DCFG\scripts\bidcomp\create_invoice_table.ps1`

- [ ] **Step 1: Write the table creation script**

Columns from spec:
- dcfg_contractor_name (String 200) — PrimaryNameAttribute
- dcfg_proposal_number (String 50)
- dcfg_invoice_number (String 100)
- dcfg_cost (Money)
- dcfg_date_invoiced (DateTime DateOnly)
- dcfg_approved_for_billing (DateTime DateOnly)
- dcfg_date_invoiced_to_client (DateTime DateOnly)
- dcfg_date_paid (DateTime DateOnly)
- dcfg_notes (String 2000, multiline)
- dcfg_job (String 200)
- dcfg_sp_file_ref (String 500, URL format)
- dcfg_active_flag (Boolean, default true)
- dcfg_paid_or_open (Picklist: Paid=100000000, Open=100000001, Rejected=100000002)
- Lookup: dcfg_phase → dcfg_phase
- Lookup: dcfg_exhibit_a — OMIT entirely for MVP. The dcfg_exhibit_a table does not exist until Phase 2. Add this lookup column when Phase 2 begins.
- Lookup: dcfg_vendor → dcfg_vendor (existing table)

- [ ] **Step 2: Run script and verify**
- [ ] **Step 3: Note EntitySetName**

---

### Task 4: Configure Web API access and table permissions

**Files:**
- Create: `C:\DCFG\scripts\bidcomp\configure_bidcomp_permissions.ps1`

- [ ] **Step 1: Create site settings for Web API access**

For each new table, create site settings:
```
Webapi/dcfg_prime_contract/enabled = true
Webapi/dcfg_prime_contract/fields = *
Webapi/dcfg_phase/enabled = true
Webapi/dcfg_phase/fields = *
Webapi/dcfg_invoice/enabled = true
Webapi/dcfg_invoice/fields = *
```

- [ ] **Step 2: Create table permissions with role links**

For each table, follow this proven recipe (from `C:\Users\JosephCameron\.claude\projects\C--DCFG\memory\reference_engineering_journal.md`, Section 20):

1. `POST /api/data/v9.2/mspp_entitypermissions` — creates the permission record (also creates powerpagecomponent type=18)
   - Set `mspp_entityname`, `mspp_scope` (Global), CRUD flags (all true for Admin role)
2. Query `GET /api/data/v9.2/powerpagecomponents?$filter=powerpagecomponenttype eq 18 and name eq '{table_logical_name}'` to get the component ID
3. `PATCH /api/data/v9.2/powerpagecomponents({id})` — update `content` JSON to include `"adx_entitypermission_webrole": ["{DCFG_Admin_role_guid}"]`
   - Use `Update-Record` helper or raw PATCH on powerpagecomponents (NOT on mspp_entitypermissions — that fails)
4. Clear portal cache via Power Pages admin center

- [ ] **Step 3: Verify API access**

Test: `GET /_api/dcfg_prime_contracts` should return 200 (empty array).

- [ ] **Step 4: Commit all scripts**

```bash
git add scripts/bidcomp/
git commit -m "feat(bidcomp): Dataverse table creation scripts for Phase 1 MVP

Creates dcfg_prime_contract, dcfg_phase, dcfg_invoice tables
with all columns, lookups, picklists, and Web API permissions."
```

---

## Chunk 2: React App Scaffold

### Task 5: Initialize the dcfg-bidcomp app

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\package.json`
- Create: `C:\DCFG\spa\dcfg-bidcomp\vite.config.js`
- Create: `C:\DCFG\spa\dcfg-bidcomp\index.html`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "dcfg-bidcomp",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "react": "17.0.2",
    "react-dom": "17.0.2",
    "react-router-dom": "6.3.0",
    "xlsx": "0.18.5"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "1.3.2",
    "@testing-library/react": "12.0.0",
    "@testing-library/jest-dom": "5.16.5",
    "vite": "5.2.0",
    "vitest": "1.4.0",
    "jsdom": "21.1.1"
  }
}
```

- [ ] **Step 2: Create vite.config.js**

Copy exact config from dcfg-shell — `jsxRuntime: 'classic'`, single chunk build, sourcemap true.

- [ ] **Step 3: Create index.html**

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>DCFG BidComp</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

- [ ] **Step 4: Install dependencies**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npm install`
Expected: node_modules created, no errors

- [ ] **Step 5: Commit scaffold**

```bash
git add spa/dcfg-bidcomp/package.json spa/dcfg-bidcomp/vite.config.js spa/dcfg-bidcomp/index.html
git commit -m "feat(bidcomp): initialize React app scaffold"
```

---

### Task 6: Copy shared utilities from dcfg-shell

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\portalApi.js`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\usePortalUser.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\useTableControls.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\Toast.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\FieldName.jsx`

- [ ] **Step 1: Copy portalApi.js**

Copy from `C:\DCFG\spa\dcfg-shell\src\portalApi.js`. Do NOT modify the core API functions. Only add BidComp entity sets to the EntitySets enum (done in Task 7).

- [ ] **Step 2: Copy usePortalUser.jsx, useTableControls.jsx, Toast.jsx, FieldName.jsx**

Exact copies. These are proven utilities.

- [ ] **Step 3: Commit shared utilities**

```bash
git add spa/dcfg-bidcomp/src/
git commit -m "feat(bidcomp): copy shared utilities from dcfg-shell"
```

---

### Task 7: Create BidComp constants and extend portalApi

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\constants.js`
- Modify: `C:\DCFG\spa\dcfg-bidcomp\src\portalApi.js` (add entity sets)
- Create: `C:\DCFG\spa\dcfg-bidcomp\tests\constants.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// tests/constants.test.js
import { describe, it, expect } from 'vitest';
import {
  BidCompEntitySets,
  PhaseStatus, PhaseStatusLabel,
  ServiceLine, ServiceLineLabel,
  RentOrOwn, SubOrSelf,
  PaidOrOpen, ContractType,
  CostCodes,
} from '../src/constants.js';

describe('BidComp Constants', () => {
  it('exports entity set names', () => {
    expect(BidCompEntitySets.prime_contracts).toBe('dcfg_prime_contracts');
    expect(BidCompEntitySets.phases).toBe('dcfg_phases');
    expect(BidCompEntitySets.invoices).toBe('dcfg_invoices');
  });

  it('exports phase status enum with labels', () => {
    expect(PhaseStatus.NOT_STARTED).toBe(100000000);
    expect(PhaseStatus.COMPLETED).toBe(100000002);
    expect(PhaseStatusLabel[PhaseStatus.NOT_STARTED]).toBe('Not Started');
    expect(PhaseStatusLabel[PhaseStatus.COMPLETED]).toBe('Completed');
  });

  it('exports service line enum', () => {
    expect(ServiceLine.ADULT_NORTH).toBe(100000000);
    expect(ServiceLineLabel[ServiceLine.ADULT_NORTH]).toBe('Adult North');
  });

  it('exports cost codes from Bancroft FY26', () => {
    expect(CostCodes['70011']).toBe('Bathroom Remodel');
    expect(CostCodes['70012']).toBe('Kitchen Remodel');
    expect(Object.keys(CostCodes).length).toBeGreaterThanOrEqual(25);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npx vitest run tests/constants.test.js`
Expected: FAIL — module not found

- [ ] **Step 3: Write constants.js**

```javascript
// src/constants.js
// BidComp-specific enums and entity sets
// All values match Dataverse picklist values exactly

export const BidCompEntitySets = {
  prime_contracts: 'dcfg_prime_contracts',
  phases: 'dcfg_phases',
  invoices: 'dcfg_invoices',
  // Phase 2+:
  // exhibit_as: 'dcfg_exhibit_as',
  // exhibit_bs: 'dcfg_exhibit_bs',
};

// Phase Status — matches Tracker spreadsheet statuses exactly
export const PhaseStatus = {
  NOT_STARTED: 100000000,
  IN_PROGRESS: 100000001,
  COMPLETED: 100000002,
  OUT_TO_BID: 100000003,
  READY_TO_START: 100000004,
  CANCELED: 100000005,
};

export const PhaseStatusLabel = {
  [PhaseStatus.NOT_STARTED]: 'Not Started',
  [PhaseStatus.IN_PROGRESS]: 'In Progress',
  [PhaseStatus.COMPLETED]: 'Completed',
  [PhaseStatus.OUT_TO_BID]: 'Out to Bid',
  [PhaseStatus.READY_TO_START]: 'Ready to Start',
  [PhaseStatus.CANCELED]: 'Canceled',
};

export const ServiceLine = {
  ADULT_NORTH: 100000000,
  ADULT_SOUTH: 100000001,
  CHILDRENS: 100000002,
  LAKESIDE: 100000003,
  CORP: 100000004,
  EDUCATION: 100000005,
  DAY: 100000006,
};

export const ServiceLineLabel = {
  [ServiceLine.ADULT_NORTH]: 'Adult North',
  [ServiceLine.ADULT_SOUTH]: 'Adult South',
  [ServiceLine.CHILDRENS]: 'Childrens',
  [ServiceLine.LAKESIDE]: 'Lakeside',
  [ServiceLine.CORP]: 'Corp',
  [ServiceLine.EDUCATION]: 'Education',
  [ServiceLine.DAY]: 'Day',
};

export const RentOrOwn = {
  OWN: 100000000,
  RENT: 100000001,
  LEASE: 100000002,
};

export const RentOrOwnLabel = {
  [RentOrOwn.OWN]: 'Own',
  [RentOrOwn.RENT]: 'Rent',
  [RentOrOwn.LEASE]: 'Lease',
};

export const SubOrSelf = {
  SUB: 100000000,
  SELF: 100000001,
};

export const SubOrSelfLabel = {
  [SubOrSelf.SUB]: 'Sub',
  [SubOrSelf.SELF]: 'Self',
};

export const PaidOrOpen = {
  PAID: 100000000,
  OPEN: 100000001,
  REJECTED: 100000002,
};

export const PaidOrOpenLabel = {
  [PaidOrOpen.PAID]: 'Paid',
  [PaidOrOpen.OPEN]: 'Open',
  [PaidOrOpen.REJECTED]: 'Rejected',
};

export const ContractType = {
  TPA: 100000000,
  DIRECT: 100000001,
  B2C: 100000002,
};

export const ContractTypeLabel = {
  [ContractType.TPA]: 'TPA',
  [ContractType.DIRECT]: 'Direct',
  [ContractType.B2C]: 'B2C',
};

export const PlannedOrUnplanned = {
  PLANNED: 100000000,
  UNPLANNED: 100000001,
};

export const PriorityLevel = {
  PRIORITY_1: 100000000,
  PRIORITY_2: 100000001,
};

// Bancroft FY26 Cost Codes — from Sage Budget
export const CostCodes = {
  '50001': 'Contingency',
  '55002': 'GC Reserve',
  '1117': 'Supervision',
  '1400': 'Dumpsters',
  '1901': 'Architecture Design',
  '9900': 'Painting',
  '70001': 'Landscaping / Drainage',
  '70002': 'Fence',
  '70003': 'Deck Replacement',
  '70004': 'Concrete / Asphalt',
  '70005': 'Waterproofing',
  '70006': 'Roof Replacement',
  '70007': 'Siding / Gutters',
  '70008': 'Window Replacement',
  '70009': 'Exterior Doors / Slider',
  '70010': 'Garage Doors / Openers',
  '70011': 'Bathroom Remodel',
  '70012': 'Kitchen Remodel',
  '70013': 'Interior Doors / Finish Trim',
  '70014': 'Flooring / Carpet',
  '70015': 'Wall Protection',
  '70016': 'Plumbing',
  '70017': 'Water Heater',
  '70018': 'HVAC Replacement',
  '70019': 'Electric Upgrade',
  '70020': 'Fire Alarm Upgrades',
  '70021': 'Appliances',
  '70022': 'Building Signage',
  '70023': 'Security Systems',
  '70024': 'Office Renovation',
  '70025': 'Generator',
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npx vitest run tests/constants.test.js`
Expected: PASS

- [ ] **Step 5: Add BidComp entity sets to portalApi.js**

Add to the EntitySets object in the copied portalApi.js:
```javascript
// BidComp tables
prime_contracts: 'dcfg_prime_contracts',
phases: 'dcfg_phases',
invoices: 'dcfg_invoices',
```

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-bidcomp/src/constants.js spa/dcfg-bidcomp/tests/constants.test.js spa/dcfg-bidcomp/src/portalApi.js
git commit -m "feat(bidcomp): add BidComp constants and entity sets"
```

---

### Task 8: Create App shell, router, and ContractSelector

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\main.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\App.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\AppRouter.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\components\ContractSelector.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\hooks\usePrimeContract.jsx`

- [ ] **Step 1: Create main.jsx**

```jsx
import React from 'react';
import ReactDOM from 'react-dom';
import App from './App.jsx';

ReactDOM.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
  document.getElementById('root')
);
```

- [ ] **Step 2: Create App.jsx**

Read `C:\DCFG\spa\dcfg-shell\src\App.jsx` for the exact pattern. Create App.jsx with:

```jsx
import React, { useEffect } from 'react';
import { HashRouter } from 'react-router-dom';
import { PortalUserProvider } from './usePortalUser.jsx';
import { ToastProvider } from './Toast.jsx';
import { ContractProvider } from './components/ContractSelector.jsx';
import AppRouter from './AppRouter.jsx';
import NavPanel from './components/NavPanel.jsx'; // Create: sidebar with 5 tabs

export default function App() {
  useEffect(() => {
    // Inject Google Fonts (IBM Plex Sans + Fraunces) — same as dcfg-shell
    const link = document.createElement('link');
    link.href = 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=Fraunces:wght@700&display=swap';
    link.rel = 'stylesheet';
    document.head.appendChild(link);
    // Inject base styles (same as dcfg-shell)
  }, []);

  return (
    <HashRouter>
      <PortalUserProvider>
        <ToastProvider>
          <ContractProvider>
            <div style={{ display: 'flex', minHeight: '100vh' }}>
              <NavPanel />
              <main style={{ flex: 1, padding: '2rem', overflowY: 'auto' }}>
                <AppRouter />
              </main>
            </div>
          </ContractProvider>
        </ToastProvider>
      </PortalUserProvider>
    </HashRouter>
  );
}
```

NavPanel tabs (220px sticky sidebar, matching dcfg-shell pattern):
1. Dashboard (`/dashboard`)
2. Tracker (`/tracker`)
3. Buy Sheet (`/buysheet`)
4. Invoices (`/invoices`)
5. Monthly Report (`/monthly-report`)

- [ ] **Step 3: Create AppRouter.jsx**

```jsx
import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import Dashboard from './screens/Dashboard.jsx';
import Tracker from './screens/Tracker.jsx';
import Invoices from './screens/Invoices.jsx';
import BuySheet from './screens/BuySheet.jsx';
import MonthlyReport from './screens/MonthlyReport.jsx';

export default function AppRouter() {
  return (
    <Routes>
      <Route index element={<Navigate to="/dashboard" replace />} />
      <Route path="dashboard" element={<Dashboard />} />
      <Route path="tracker" element={<Tracker />} />
      <Route path="invoices" element={<Invoices />} />
      <Route path="buysheet" element={<BuySheet />} />
      <Route path="monthly-report" element={<MonthlyReport />} />
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
```

- [ ] **Step 4: Create ContractSelector component + ContractContext**

```jsx
// src/components/ContractSelector.jsx
import React, { createContext, useContext, useState, useEffect } from 'react';
import { apiGet } from '../portalApi.js';
import { BidCompEntitySets } from '../constants.js';

const ContractContext = createContext(null);

export function useContract() {
  return useContext(ContractContext);
}

export function ContractProvider({ children }) {
  const [contracts, setContracts] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiGet(`/${BidCompEntitySets.prime_contracts}?$filter=dcfg_active_flag eq true&$select=dcfg_prime_contractid,dcfg_contract_number,dcfg_fiscal_year,dcfg_total_budget&$orderby=dcfg_fiscal_year desc`)
      .then(res => {
        const list = res?.value ?? [];
        setContracts(list);
        if (list.length > 0) setSelectedId(list[0].dcfg_prime_contractid);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const selected = contracts.find(c => c.dcfg_prime_contractid === selectedId) || null;

  return (
    <ContractContext.Provider value={{ contracts, selected, selectedId, setSelectedId, loading }}>
      {children}
    </ContractContext.Provider>
  );
}

// Dropdown UI: renders in the top bar, shows "Contract# — FY" for each option
export default function ContractSelector() {
  const { contracts, selectedId, setSelectedId } = useContract();
  return (
    <select value={selectedId || ''} onChange={e => setSelectedId(e.target.value)}>
      {contracts.map(c => (
        <option key={c.dcfg_prime_contractid} value={c.dcfg_prime_contractid}>
          {c.dcfg_contract_number} — {c.dcfg_fiscal_year}
        </option>
      ))}
    </select>
  );
}
```

- [ ] **Step 5: Create usePrimeContract hook**

```jsx
// src/hooks/usePrimeContract.jsx
import { useState, useEffect, useCallback } from 'react';
import { apiGet } from '../portalApi.js';
import { BidCompEntitySets } from '../constants.js';
import { useContract } from '../components/ContractSelector.jsx';

export function usePrimeContract() {
  const { selectedId } = useContract();
  const [contract, setContract] = useState(null);
  const [phases, setPhases] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const refresh = useCallback(() => {
    if (!selectedId) return;
    setLoading(true);
    Promise.all([
      apiGet(`/${BidCompEntitySets.prime_contracts}(${selectedId})`),
      apiGet(`/${BidCompEntitySets.phases}?$filter=_dcfg_prime_contract_value eq '${selectedId}' and dcfg_active_flag eq true&$orderby=dcfg_phase_number asc`),
    ])
      .then(([contractRes, phasesRes]) => {
        setContract(contractRes);
        setPhases(phasesRes?.value ?? []);
        setLoading(false);
      })
      .catch(e => { setError(e); setLoading(false); });
  }, [selectedId]);

  useEffect(() => { refresh(); }, [refresh]);

  return { contract, phases, loading, error, refresh };
}
```

Note: `_dcfg_prime_contract_value` is the lookup filter syntax for Dataverse. Verify the exact navigation property name after table creation. Also create `usePhases` as a re-export alias if screens need phases without the full contract:

```jsx
// src/hooks/usePhases.jsx — convenience re-export
export { usePrimeContract as usePhases } from './usePrimeContract.jsx';
// Screens that only need phases: const { phases, loading } = usePhases();
```

- [ ] **Step 6: Verify dev server starts**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npm run dev`
Expected: Vite dev server starts, app renders with nav + empty screens

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-bidcomp/src/
git commit -m "feat(bidcomp): app shell with router, nav, and contract selector"
```

---

## Chunk 3: Core Screens — Dashboard + Tracker

### Task 9: Build Dashboard screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\screens\Dashboard.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\components\StatusBadge.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\components\CurrencyCell.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\components\AlertBanner.jsx`

- [ ] **Step 1: Create StatusBadge component**

Color-coded pill matching current spreadsheet conventions:
- Not Started: gray
- In Progress: blue
- Completed: green
- Out to Bid: orange
- Ready to Start: yellow
- Canceled: red strikethrough

- [ ] **Step 2: Create CurrencyCell component**

Formats currency values as `$XX,XXX.XX`. Negative values in red with parentheses.

- [ ] **Step 3: Create AlertBanner component**

Displays unbilled work and aging invoice alerts. Red for critical (>30 days), yellow for warning (>14 days).

- [ ] **Step 4: Build Dashboard screen**

Layout matches the Tracker spreadsheet's Dashboard tab:
- **Capital Projects Dashboard** header
- **Summary row:** Total Planned Projects | Total Unplanned Projects | Total Projects
- **Status counts:** Not Started | In Progress | Completed | Out to Bid
- **By Service Line:** Adult North | Adult South | Childrens (each with same counts)
- **Spend-down bar:** Total Budget | Committed | Spent | Remaining
- **Alerts section:** Unbilled work items, Aging invoices

All data computed from dcfg_phase and dcfg_invoice records for the selected prime contract.

- [ ] **Step 5: Verify dashboard renders with test data**
- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-bidcomp/src/screens/Dashboard.jsx spa/dcfg-bidcomp/src/components/
git commit -m "feat(bidcomp): Dashboard screen with status counts and alerts"
```

---

### Task 10: Build Tracker screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\screens\Tracker.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\components\ExcelButtons.jsx`

- [ ] **Step 1: Create ExcelButtons component**

Export and Import buttons. Export calls excelEngine.exportTracker(). Import opens file picker, calls excelEngine.importTracker().

- [ ] **Step 2: Build Tracker screen**

Grid with exact same columns as the FY26 Project Tracker spreadsheet:
```
Planned/Unplanned | Service Line | PM Assigned | WO# | Phase | Phase Name |
Property Address | Description | Status | Notes | Rent/Own | Sub/Self |
Cost Code | Hours | Material | Labor | Equipment | Sub | Other
```

Features:
- useTableControls for sort/search/filter
- Inline edit for: Status (dropdown), PM Assigned, Notes
- apiPost PATCH on blur/change for inline edits
- StatusBadge for status column
- CurrencyCell for money columns
- Filter by Service Line, Status, PM
- Export to Excel button
- Color-coded rows by status (matching spreadsheet conditional formatting)

- [ ] **Step 3: Verify tracker renders with column headers**
- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-bidcomp/src/screens/Tracker.jsx spa/dcfg-bidcomp/src/components/ExcelButtons.jsx
git commit -m "feat(bidcomp): Tracker screen — FY26 Project Tracker grid with inline edit"
```

---

## Chunk 4: Invoices + Buy Sheet Screens

### Task 11: Build Invoices screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\screens\Invoices.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\hooks\useInvoices.jsx`
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\components\DateCell.jsx`

- [ ] **Step 1: Create DateCell component**

Formats dates as MM/DD/YYYY. Highlights aging: >14 days yellow, >30 days red.

- [ ] **Step 2: Create useInvoices hook**

Fetches invoices for the selected prime contract. Computes:
- Aging days (today - date_invoiced, if not yet billed to client)
- Unbilled total
- Cash flow gap (invoiced by contractor but not yet paid by client)

- [ ] **Step 3: Build Invoices screen**

Grid with exact same columns as Invoice Tracking spreadsheet tab:
```
Phase | Contractor Name | Proposal# | Cost | Invoice# | Cost |
Date Invoiced (Contractor) | Approved for Billing (Y/N) |
Date Invoiced to Client | Paid/Open | Notes | Date Paid | Job
```

Features:
- Aging indicators on date columns
- Alert banner for invoices >14 days unbilled
- Add Invoice button opens inline form (not a separate modal component — keep it simple):
  - Required fields: Phase (dropdown of phases), Contractor Name, Invoice Number, Cost (currency)
  - Optional fields: Proposal#, Date Invoiced, Approved for Billing, Date Invoiced to Client, Paid/Open (dropdown), Date Paid, Job, Notes
  - On submit: `apiPost` to create dcfg_invoice record, refresh list
- Quick filters: Paid/Open, by Phase, by Contractor

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-bidcomp/src/screens/Invoices.jsx spa/dcfg-bidcomp/src/hooks/useInvoices.jsx spa/dcfg-bidcomp/src/components/DateCell.jsx
git commit -m "feat(bidcomp): Invoices screen with aging alerts"
```

---

### Task 12: Build Buy Sheet screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\screens\BuySheet.jsx`

- [ ] **Step 1: Build Buy Sheet screen**

Budget view grouped by cost code, matching the Buy Sheet spreadsheet format:
```
CSI# | Description | Estimate Value | Material | Labor | Expense |
Sub | Contract Award | Un-Purchased | Contractor Name | Gain | Loss
```

Data source: dcfg_phase records grouped by dcfg_cost_code. Each row is a rollup of all phases with that cost code.

Features:
- Cost code descriptions from CostCodes constant
- Gain/Loss computed (Estimate - Award)
- Drill-down: click a cost code to see individual phases
- Totals row at bottom
- Export to Excel in Buy Sheet format

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-bidcomp/src/screens/BuySheet.jsx
git commit -m "feat(bidcomp): Buy Sheet screen — budget by cost code"
```

---

## Chunk 5: Excel Engine + Monthly Report

### Task 13: Build Excel export/import engine

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\excelEngine.js`
- Create: `C:\DCFG\spa\dcfg-bidcomp\tests\excelEngine.test.js`

- [ ] **Step 1: Write failing tests**

```javascript
// tests/excelEngine.test.js
import { describe, it, expect } from 'vitest';
import { formatTrackerExport, parseTrackerImport, generateMonthlyReport } from '../src/excelEngine.js';

describe('Excel Engine', () => {
  it('formats tracker data for export with correct column headers', () => {
    const phases = [{ dcfg_phase_number: 5, dcfg_phase_name: '310126 NJ Balfield', dcfg_status: 100000001 }];
    const result = formatTrackerExport(phases);
    expect(result.headers).toContain('Phase');
    expect(result.headers).toContain('Phase Name');
    expect(result.headers).toContain('Status');
    expect(result.rows[0].Status).toBe('In Progress');
  });

  it('parses imported tracker data and detects changes', () => {
    const imported = [{ Phase: 5, 'Phase Name': '310126 NJ Balfield', Status: 'Completed' }];
    const existing = [{ dcfg_phase_number: 5, dcfg_status: 100000001 }];
    const diff = parseTrackerImport(imported, existing);
    expect(diff.changed.length).toBe(1);
    expect(diff.changed[0].field).toBe('dcfg_status');
    expect(diff.changed[0].newValue).toBe(100000002);
  });

  it('generates monthly report workbook structure', () => {
    // Spec calls for 6 tabs. Phase 1 MVP implements 4.
    // "Cadenced Services" and "Change Orders" tabs are deferred to Phase 2+
    // (those tables don't exist yet).
    const data = { phases: [], invoices: [], contract: { dcfg_total_budget: 5988350 } };
    const wb = generateMonthlyReport(data, { year: 2026, month: 3 });
    expect(wb.SheetNames).toContain('Executive Summary');
    expect(wb.SheetNames).toContain('Project Tracker');
    expect(wb.SheetNames).toContain('Invoice Detail');
    expect(wb.SheetNames).toContain('Spend-Down');
    expect(wb.SheetNames.length).toBe(4);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npx vitest run tests/excelEngine.test.js`

- [ ] **Step 3: Implement excelEngine.js**

Uses SheetJS (xlsx) library:
- `formatTrackerExport(phases)` — converts phase records to spreadsheet-format rows with label lookups
- `parseTrackerImport(imported, existing)` — diffs imported rows against existing, returns `{ changed, added, unchanged }`
- `generateMonthlyReport(data, period)` — creates multi-tab XLSX workbook:
  1. Executive Summary
  2. Project Tracker
  3. Invoice Detail
  4. Spend-Down
- `downloadWorkbook(wb, filename)` — triggers browser download

- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-bidcomp/src/excelEngine.js spa/dcfg-bidcomp/tests/excelEngine.test.js
git commit -m "feat(bidcomp): Excel engine — export, import, monthly report generation"
```

---

### Task 14: Build Monthly Report screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-bidcomp\src\screens\MonthlyReport.jsx`

- [ ] **Step 1: Build Monthly Report screen**

UI:
- Period selector (month/year dropdowns, default: previous month)
- Preview section showing summary stats
- "Generate & Download" button
- Status of last generated report (date, file reference)

On generate:
1. Fetch all phases for selected contract
2. Fetch all invoices for the period
3. Compute spend-down per phase, per cost code, per service line
4. Call `generateMonthlyReport()` from excelEngine
5. Trigger download
6. Store generation record (optional: save to SharePoint)

- [ ] **Step 2: Verify report generates and downloads**
- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-bidcomp/src/screens/MonthlyReport.jsx
git commit -m "feat(bidcomp): Monthly Report screen — one-click Bancroft package"
```

---

## Chunk 6: Data Load + Deploy

### Task 15: Import Bancroft FY26 data

**Files:**
- Create: `C:\DCFG\scripts\bidcomp\import_bancroft_fy26.ps1`

- [ ] **Step 0: Verify research data exists**

Run: `ls C:\DCFG\research\bancroft-ghsp-fy26\`
Expected files: `Sage Budget.xlsx`, `Tracker with Dashboard.xlsx`, `Cost Center GL Cross Reference.xlsx`, `Group Home List.xlsx`
If missing: re-run the SharePoint download from the brainstorming session (Graph API, read-only).

- [ ] **Step 1: Write import script**

Uses the downloaded spreadsheets from `C:\DCFG\research\bancroft-ghsp-fy26\`:
1. Read Sage Budget → create 1 dcfg_prime_contract record
2. Read FY26 Project Tracker → create ~92 dcfg_phase records
3. Read Invoice Tracking → create ~14 dcfg_invoice records (start with tracked ones)
4. Match vendors by name to existing dcfg_vendor records

The script should:
- Check for existing records before creating (idempotent)
- Map spreadsheet columns to Dataverse fields
- Convert status text to picklist values
- Log all created record IDs

- [ ] **Step 2: Run import against Test environment**
- [ ] **Step 3: Verify data in system — Dashboard shows correct counts**
- [ ] **Step 4: Commit**

```bash
git add scripts/bidcomp/import_bancroft_fy26.ps1
git commit -m "feat(bidcomp): Bancroft FY26 data import script"
```

---

### Task 16: Build and deploy

**Files:**
- Modify: `C:\DCFG\spa\dcfg-bidcomp\` (build output)

- [ ] **Step 1: Run tests**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npm test`
Expected: All tests pass

- [ ] **Step 2: Build for production**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && npm run build`
Expected: dist/ directory created with single-chunk bundle

- [ ] **Step 3: Deploy to Power Pages**

Run: `cd C:\DCFG\spa\dcfg-bidcomp && pac pages upload-code-site --rootPath . --compiledPath dist`

Note: This requires a Power Pages code site to be provisioned for BidComp. If not yet provisioned, the operator will need to create one.

- [ ] **Step 4: Clear cache and verify**

Clear Power Pages cache. Open site URL. Verify:
- Dashboard shows Bancroft FY26 data
- Tracker shows all 92 phases with correct statuses
- Invoices shows tracked invoices with aging indicators
- Buy Sheet shows cost code rollups
- Monthly Report generates and downloads Excel

- [ ] **Step 5: Provide launch URLs and cache clear link**

- [ ] **Step 6: Final commit**

```bash
git add spa/dcfg-bidcomp/
git commit -m "feat(bidcomp): Phase 1 MVP — Bancroft monthly reporting deployed"
```

---

## Summary

| Chunk | Tasks | What It Delivers |
|-------|-------|-----------------|
| 1: Schema | 1-4 | 3 Dataverse tables + permissions |
| 2: Scaffold | 5-8 | Working React app with routing and shared utilities |
| 3: Screens | 9-10 | Dashboard + Tracker (the two most-used views) |
| 4: More Screens | 11-12 | Invoices + Buy Sheet |
| 5: Excel | 13-14 | Export/import engine + Monthly Report generator |
| 6: Data + Deploy | 15-16 | Bancroft FY26 data loaded, app deployed |

**Total tasks:** 16
**Dependencies:** Chunk 1 must complete before Chunk 3+ (screens need data). Chunks 3-5 can be parallelized with subagents.
