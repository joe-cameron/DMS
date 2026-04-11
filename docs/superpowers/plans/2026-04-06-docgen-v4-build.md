# DocGen V4 — HTML Template Engine Build Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the V3 Switch-based Word template system with a data-driven HTML template engine that scales to unlimited clients and templates.

**Architecture:** HTML templates stored in Dataverse, Power Automate flow reads template + merges data + calls Azure Function (Puppeteer) for HTML-to-PDF, saves PDF to SharePoint. Templates created via Claude conversations — user uploads office doc, Claude interviews for field mapping, Claude writes template to Dataverse.

**Tech Stack:** Azure Functions (Node.js 20 + Puppeteer), Power Automate, Dataverse, SharePoint

**Spec:** `C:\dcfg\docs\superpowers\specs\2026-04-06-docgen-v4-blackbox-design.md`

**Flow:** DCFG DocGen v4 — `a9b7da25-0c32-f111-88b3-000d3a308e39` on Prod (`6ee0cd74-e2b2-e429-ac4b-27123cd20d19`)

---

## Chunk 1: Azure Function — HTML to PDF

### Task 1: Create Azure Function project

**Files:**
- Create: `C:\dcfg\azure-functions\html-to-pdf\package.json`
- Create: `C:\dcfg\azure-functions\html-to-pdf\src\functions\htmlToPdf.js`
- Create: `C:\dcfg\azure-functions\html-to-pdf\host.json`
- Create: `C:\dcfg\azure-functions\html-to-pdf\.funcignore`

- [ ] **Step 1: Scaffold the function project**

```bash
mkdir -p C:\dcfg\azure-functions\html-to-pdf
cd C:\dcfg\azure-functions\html-to-pdf
```

`package.json`:
```json
{
  "name": "dcfg-html-to-pdf",
  "version": "1.0.0",
  "description": "Converts HTML to PDF via Puppeteer for DCFG DocGen V4",
  "main": "src/functions/*.js",
  "scripts": {
    "start": "func start",
    "test": "node test/test-local.js"
  },
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "puppeteer": "^23.0.0"
  }
}
```

`host.json`:
```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  },
  "functionTimeout": "00:02:00"
}
```

`.funcignore`:
```
*.js.map
*.ts
.git*
.vscode
local.settings.json
test
node_modules/.cache
```

- [ ] **Step 2: Write the function**

`src/functions/htmlToPdf.js`:
```javascript
const { app } = require('@azure/functions');
const puppeteer = require('puppeteer');

app.http('html-to-pdf', {
  methods: ['POST'],
  authLevel: 'function',
  handler: async (request, context) => {
    try {
      const { html, options } = await request.json();

      if (!html) {
        return { status: 400, body: 'Missing "html" in request body' };
      }

      const browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
      });

      const page = await browser.newPage();
      await page.setContent(html, { waitUntil: 'networkidle0' });

      const pdfBuffer = await page.pdf({
        format: options?.format || 'Letter',
        printBackground: true,
        margin: options?.margin || { top: '0', bottom: '0', left: '0', right: '0' },
        preferCSSPageSize: true,
      });

      await browser.close();

      return {
        body: pdfBuffer,
        headers: { 'Content-Type': 'application/pdf' }
      };
    } catch (err) {
      context.error('PDF generation failed:', err);
      return { status: 500, body: `PDF generation failed: ${err.message}` };
    }
  }
});
```

- [ ] **Step 3: Install dependencies**

Run: `cd C:\dcfg\azure-functions\html-to-pdf && npm install`

- [ ] **Step 4: Create local test script**

Create `test/test-local.js`:
```javascript
const fs = require('fs');
const http = require('http');

const html = fs.readFileSync('C:/dcfg/tmp/v4_test_template.html', 'utf-8');

const data = JSON.stringify({ html });

const req = http.request({
  hostname: 'localhost',
  port: 7071,
  path: '/api/html-to-pdf',
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
}, (res) => {
  const chunks = [];
  res.on('data', c => chunks.push(c));
  res.on('end', () => {
    const pdf = Buffer.concat(chunks);
    fs.writeFileSync('C:/dcfg/tmp/v4_function_test.pdf', pdf);
    console.log(`PDF saved: ${pdf.length} bytes`);
  });
});

req.write(data);
req.end();
```

- [ ] **Step 5: Test locally**

Terminal 1: `cd C:\dcfg\azure-functions\html-to-pdf && npm start`
Terminal 2: `node test/test-local.js`
Expected: PDF saved to `C:\dcfg\tmp\v4_function_test.pdf`, opens correctly, text selectable.

- [ ] **Step 6: Commit**

```bash
git add azure-functions/html-to-pdf/
git commit -m "feat: add Azure Function for HTML-to-PDF conversion (DocGen V4)"
```

### Task 2: Deploy Azure Function to Azure

- [ ] **Step 1: Create Azure resources**

This requires the Azure portal or Azure CLI. The operator will:
1. Create a Resource Group: `dcfg-docgen`
2. Create a Function App: `dcfg-html-to-pdf` (Consumption plan, Node.js 20, East US)
3. Note the function URL and key

**Manual steps — operator performs in Azure Portal.**

- [ ] **Step 2: Deploy the function**

```bash
cd C:\dcfg\azure-functions\html-to-pdf
func azure functionapp publish dcfg-html-to-pdf
```

- [ ] **Step 3: Test deployed function**

```bash
pwsh -Command "
  \$body = @{ html = '<h1>Test</h1><p>Hello World</p>' } | ConvertTo-Json
  \$url = 'https://dcfg-html-to-pdf.azurewebsites.net/api/html-to-pdf?code=FUNCTION_KEY'
  Invoke-RestMethod -Uri \$url -Method POST -Body \$body -ContentType 'application/json' -OutFile 'C:\dcfg\tmp\v4_azure_test.pdf'
  Write-Host 'PDF size:' (Get-Item 'C:\dcfg\tmp\v4_azure_test.pdf').Length
"
```

- [ ] **Step 4: Store function URL in Dataverse config**

```bash
pwsh -Command "
  # Store the Azure Function URL in dcfg_configs
  # Key: docgen_v4_pdf_function_url
  # Value: https://dcfg-html-to-pdf.azurewebsites.net/api/html-to-pdf?code=FUNCTION_KEY
"
```

---

## Chunk 2: Dataverse Table — `dcfg_document_templates`

### Task 3: Create the template table in Dataverse

**Files:**
- Create: `C:\dcfg\Deploy-DocGenV4-Schema.ps1`

- [ ] **Step 1: Write the schema creation script**

```powershell
# Deploy-DocGenV4-Schema.ps1
# Creates dcfg_document_templates table on current pac auth environment

$orgUrl = "https://org06f5de0b.crm.dynamics.com"  # Prod

Import-Module Az.Accounts
$token = ([System.Net.NetworkCredential]::new("", (Get-AzAccessToken -ResourceUrl $orgUrl -AsSecureString).Token)).Password
$headers = @{
  Authorization = "Bearer $token"
  "Content-Type" = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version" = "4.0"
}
$base = "$orgUrl/api/data/v9.2"

# 1. Create table
$tableDef = @{
  SchemaName = "dcfg_document_template_v4"
  DisplayName = @{ "@odata.type" = "Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ Label = "Document Template V4"; LanguageCode = 1033 }) }
  DisplayCollectionName = @{ "@odata.type" = "Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ Label = "Document Templates V4"; LanguageCode = 1033 }) }
  Description = @{ "@odata.type" = "Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ Label = "HTML templates for DocGen V4"; LanguageCode = 1033 }) }
  HasNotes = $false
  HasActivities = $false
  PrimaryNameAttribute = "dcfg_name"
  TableType = "Standard"
} | ConvertTo-Json -Depth 10

Write-Host "Creating table dcfg_document_template_v4..."
Invoke-RestMethod "$base/EntityDefinitions" -Method POST -Headers $headers -Body $tableDef

# 2. Add columns (table auto-creates dcfg_name as primary)
$columns = @(
  @{ SchemaName="dcfg_document_type"; Type="Picklist"; Options=@(
    @{Value=100000000;Label="VendorAgreement"},@{Value=100000001;Label="WorkOrder"},
    @{Value=100000002;Label="Amendment"},@{Value=100000003;Label="Proposal_A"},
    @{Value=100000004;Label="Proposal_B"},@{Value=100000005;Label="Proposal_C"},
    @{Value=100000006;Label="ExhibitA_Basic"},@{Value=100000007;Label="ExhibitA_Optimized"},
    @{Value=100000008;Label="ExhibitB"},@{Value=100000009;Label="ExhibitC"},
    @{Value=100000010;Label="ExhibitD"},@{Value=100000011;Label="BlanketWO"}
  )},
  @{ SchemaName="dcfg_html_body"; Type="Memo"; MaxLength=1048576; Description="HTML template with {{tokens}}" },
  @{ SchemaName="dcfg_field_manifest"; Type="Memo"; MaxLength=100000; Description="JSON field manifest" },
  @{ SchemaName="dcfg_source_entity"; Type="String"; MaxLength=200; Description="Primary Dataverse entity set" },
  @{ SchemaName="dcfg_expand_entities"; Type="Memo"; MaxLength=10000; Description="JSON expand definitions" },
  @{ SchemaName="dcfg_version"; Type="Integer"; DefaultValue=1 },
  @{ SchemaName="dcfg_active_flag"; Type="Boolean"; DefaultValue=$true }
)

# Note: Actual column creation varies by type. Operator may use Dataverse admin UI for faster setup.
Write-Host "Table created. Add columns via admin UI or extend this script."
Write-Host "Required columns: dcfg_document_type (Choice), dcfg_html_body (Multiline), dcfg_field_manifest (Multiline),"
Write-Host "  dcfg_source_entity (String 200), dcfg_expand_entities (Multiline), dcfg_version (Integer), dcfg_active_flag (Boolean)"
Write-Host "Required lookups: dcfg_client (-> dcfg_customers)"
```

- [ ] **Step 2: Evaluate script vs manual**

Per script-vs-manual-judgment: this is one table with ~8 columns. Manual creation in Dataverse admin takes ~5 minutes. The lookup column (dcfg_client → dcfg_customers) is easier to create in the UI.

**Decision: Create the table manually in the Dataverse admin UI.** Use the script as a column reference only.

- [ ] **Step 3: Create the table manually**

Dataverse admin → Tables → New table:
- Name: `Document Template V4`
- Schema name: `dcfg_document_template_v4`
- Primary column: `dcfg_name` (String 200)

Add columns:
| Column | Type | Details |
|--------|------|---------|
| `dcfg_document_type` | Choice | VendorAgreement(100000000), WorkOrder(100000001), Amendment(100000002), Proposal_A(100000003), Proposal_B(100000004), Proposal_C(100000005), ExhibitA_Basic(100000006), ExhibitA_Optimized(100000007), ExhibitB(100000008), ExhibitC(100000009), ExhibitD(100000010), BlanketWO(100000011) |
| `dcfg_html_body` | Multiline Text | Max length: 1048576 |
| `dcfg_field_manifest` | Multiline Text | Max length: 100000 |
| `dcfg_source_entity` | Text | Max length: 200 |
| `dcfg_expand_entities` | Multiline Text | Max length: 10000 |
| `dcfg_version` | Whole Number | Default: 1 |
| `dcfg_active_flag` | Yes/No | Default: Yes |
| `dcfg_client` | Lookup | Related table: dcfg_customers |

- [ ] **Step 4: Add table to DCFGSystemTest solution**

Dataverse admin → Solutions → DCFGSystemTest → Add existing → Table → Document Template V4 (include all components).

- [ ] **Step 5: Verify entity set name**

```bash
pwsh -Command "
  Import-Module Az.Accounts
  \$token = ([System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl 'https://org06f5de0b.crm.dynamics.com' -AsSecureString).Token)).Password
  \$h = @{ Authorization = \"Bearer \$token\"; Accept = 'application/json' }
  \$r = Invoke-RestMethod 'https://org06f5de0b.crm.dynamics.com/api/data/v9.2/EntityDefinitions?`\$filter=SchemaName eq ''dcfg_document_template_v4''&`\$select=EntitySetName' -Headers \$h
  Write-Host 'Entity set name:' \$r.value[0].EntitySetName
"
```

Record the entity set name for use in the flow.

### Task 4: Create first test template (Bancroft Work Order)

- [ ] **Step 1: Produce HTML template from existing Word doc**

In a Claude conversation:
1. Read `C:\dcfg\Bancroft_Blanket_Work_Order_STANDARDIZED.docx`
2. Identify all content control tags (already known from V3: contract_contractor_legal_name, contract_contractor_name, contract_owner_contact, etc.)
3. Produce HTML template with `{{tokens}}` and print CSS
4. Produce field manifest JSON

- [ ] **Step 2: Write template to Dataverse**

```bash
pwsh -Command "
  # Write the Bancroft Work Order HTML template to dcfg_document_template_v4
  Import-Module Az.Accounts
  \$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
  \$token = ([System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl \$orgUrl -AsSecureString).Token)).Password
  \$headers = @{ Authorization = \"Bearer \$token\"; 'Content-Type' = 'application/json' }

  \$body = @{
    dcfg_name = 'Bancroft - Blanket Work Order'
    dcfg_document_type = 100000011  # BlanketWO
    dcfg_html_body = (Get-Content 'C:\dcfg\tmp\v4_bancroft_wo_template.html' -Raw)
    dcfg_field_manifest = (Get-Content 'C:\dcfg\tmp\v4_bancroft_wo_manifest.json' -Raw)
    dcfg_source_entity = 'dcfg_contracts'
    dcfg_version = 1
    dcfg_active_flag = \$true
    # dcfg_client lookup bind TBD after entity set confirmed
  } | ConvertTo-Json -Depth 5

  Invoke-RestMethod \"\$orgUrl/api/data/v9.2/dcfg_document_template_v4s\" -Method POST -Headers \$headers -Body \$body
  Write-Host 'Template written.'
"
```

- [ ] **Step 3: Verify template reads back correctly**

```bash
pwsh -Command "
  # Read back and verify
  Import-Module Az.Accounts
  \$orgUrl = 'https://org06f5de0b.crm.dynamics.com'
  \$token = ([System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl \$orgUrl -AsSecureString).Token)).Password
  \$headers = @{ Authorization = \"Bearer \$token\"; Accept = 'application/json' }
  \$r = Invoke-RestMethod \"\$orgUrl/api/data/v9.2/dcfg_document_template_v4s?\`\$filter=dcfg_name eq 'Bancroft - Blanket Work Order'&\`\$select=dcfg_name,dcfg_document_type,dcfg_version\" -Headers \$headers
  Write-Host 'Found:' \$r.value.Count 'records'
  Write-Host 'Name:' \$r.value[0].dcfg_name
  Write-Host 'Type:' \$r.value[0].dcfg_document_type
  Write-Host 'HTML length:' \$r.value[0].dcfg_html_body.Length
"
```

---

## Chunk 3: Flow Modification — Replace Switch with Black Box

### Task 5: Read current flow structure and plan modifications

- [ ] **Step 1: Document the current flow action sequence**

Read `C:\dcfg\tmp\v4_flow_clientdata.json` and document:
- Which actions precede the Switch_Template (keep these)
- Which actions follow the Switch_Template (keep these)
- What the Switch_Template does (replace this)
- What Init_varPopulatedDoc does (may change — now holds HTML instead of Word doc reference)

- [ ] **Step 2: Design the replacement actions**

The Switch_Template and all Word Online actions get replaced by:

| # | Action Name | Type | Purpose |
|---|-------------|------|---------|
| 1 | Get_Template_V4 | Dataverse Get Row | Read from dcfg_document_template_v4 by document_type + client |
| 2 | Parse_Manifest | Parse JSON | Parse dcfg_field_manifest into array |
| 3 | Get_Source_Record | HTTP with Azure AD | Dynamic Dataverse query using source_entity from template |
| 4 | Build_Token_Map_V4 | Compose | Format each field value per manifest format type |
| 5 | Replace_Tokens | Compose | String replace all `{{tokens}}` in html_body |
| 6 | Call_PDF_Function | HTTP | POST HTML to Azure Function, receive PDF blob |

Actions after (SharePoint save, audit log, status update) remain unchanged except:
- `Create_file` now saves `.pdf` instead of `.docx`
- No Word Online `Populate_template` action needed
- `varPopulatedDoc` is no longer needed (PDF blob comes from HTTP response)

### Task 6: Build the replacement flow actions

- [ ] **Step 1: Push Get_Template_V4 action**

Dataverse "List rows" action:
- Table: dcfg_document_template_v4
- Filter: `dcfg_document_type eq @{triggerBody()?['dcfg_request_type']}` (or map from request's template reference)
- Select: dcfg_html_body, dcfg_field_manifest, dcfg_source_entity, dcfg_expand_entities
- Top: 1

- [ ] **Step 2: Push Parse_Manifest action**

Parse JSON on `first(body('Get_Template_V4')?['value'])?['dcfg_field_manifest']`

Schema: array of `{ token, field, format, trueText?, falseText?, choices?, entity?, expand?, fields? }`

- [ ] **Step 3: Push Get_Source_Record action**

HTTP with Azure AD:
- Method: GET
- URI: `@{uriHost(triggerBody()?['@odata.context'])}/api/data/v9.2/@{first(body('Get_Template_V4')?['value'])?['dcfg_source_entity']}(@{triggerBody()?['_dcfg_contract_id_value']})?$select=@{join(body('Parse_Manifest'),'dcfg_field_name_list')}`
- Headers: `Prefer: odata.include-annotations=*`
- Authentication: Azure AD OAuth (Dataverse resource)

Note: The exact URI construction depends on which lookup is populated on the request (contract, MSA, etc.). A Condition block may route to different source records.

- [ ] **Step 4: Push Build_Token_Map_V4 and Replace_Tokens actions**

Compose action that iterates the manifest and builds the final HTML:
- For each manifest entry, format the value (date → MM/DD/YYYY, currency → $X,XXX.XX, etc.)
- Replace `{{token}}` in the html_body string with the formatted value
- Result: complete HTML string with all data merged

This may use an Apply to each loop or a series of nested `replace()` expressions. For 20-30 tokens, nested `replace()` in a single Compose is more efficient than a loop.

- [ ] **Step 5: Push Call_PDF_Function action**

HTTP action:
- Method: POST
- URI: `@{outputs('Read_PDF_Function_URL')?['dcfg_value']}` (from dcfg_configs)
- Body: `{ "html": "@{outputs('Replace_Tokens')}" }`
- Content-Type: application/json
- Retry policy: exponential, 3 retries

- [ ] **Step 6: Update Create_file action**

Change the SharePoint Create_file action:
- File name: `@{outputs('Compute_Output_Filename')}.pdf` (was .docx)
- File content: `@{body('Call_PDF_Function')}` (PDF blob from function response)
- Folder path: unchanged

- [ ] **Step 7: Remove obsolete actions**

Delete from the flow:
- `Switch_Template` and all its cases
- Any `Populate_template` Word Online actions
- `Init_varPopulatedDoc` (no longer needed)
- Word Online connection reference (if no other actions use it)

- [ ] **Step 8: Test end-to-end**

1. Create a document request in the SPA for a Bancroft Work Order
2. Verify flow triggers and runs successfully
3. Verify PDF appears in SharePoint `DCFG_Outputs/Bancroft/{Year}/BlanketWO/`
4. Open PDF — verify formatting, data accuracy, text selectability
5. Compare against V3 Word output for same record

### Task 7: Migrate remaining templates

- [ ] **Step 1: For each of the 12 Bancroft templates, repeat Task 4:**

1. Read the V3 Word template
2. Claude interviews to confirm field mappings
3. Claude produces HTML template + manifest
4. Claude writes to dcfg_document_template_v4

Templates:
1. Decades_Vendor_MSA
2. Decades_Work_Order
3. Bancroft_Blanket_Work_Order (done in Task 4)
4. Decades_Work_Order_Amendment
5. Bancroft_Work_Order_Amendment
6. Decades_Proposal_Facility_A
7. Decades_Proposal_Individual_A
8. Decades_Proposal_Facility_B
9. Decades_Proposal_Individual_B
10. Decades_Exhibit_A_Basic_A
11. Decades_Exhibit_A_Optimized_C
12. Decades_Exhibit_D_Insurance

- [ ] **Step 2: Test each template produces correct output**

For each template: create a document request, verify PDF output matches expected content and formatting.

---

## Chunk 4: Integration and Cleanup

### Task 8: Update SPA if needed

- [ ] **Step 1: Check if createDocumentRequest needs changes**

The SPA's `createDocumentRequest()` writes to `dcfg_document_requests` which triggers the flow. If the request schema is unchanged (same lookups, same status values), no SPA changes needed.

If the template lookup field needs to reference the new `dcfg_document_template_v4` table instead of the old template table, update the SPA's `createDocumentRequest()` to bind to the new table.

- [ ] **Step 2: Update document download handling**

If the SPA currently expects `.docx` downloads, update any download/preview logic to handle `.pdf`. This may be as simple as changing file extension expectations — PDFs open natively in browsers.

### Task 9: Deploy to Test and Stage

- [ ] **Step 1: Create dcfg_document_template_v4 table on Test environment**

Repeat Task 3 manual steps on Test (org0c17e98d).

- [ ] **Step 2: Create dcfg_document_template_v4 table on Stage environment**

Repeat Task 3 manual steps on Stage (org88778bb0).

- [ ] **Step 3: Copy template data to Test and Stage**

Export template rows from Prod, import to Test and Stage.

- [ ] **Step 4: Create V4 flow on Test and Stage**

Copy the modified V4 flow to Test and Stage environments. Update connection references for each environment.

### Task 10: Decommission V3

- [ ] **Step 1: Verify all 12 templates produce correct V4 output**

Run all 12 template types through the V4 flow. Compare output quality against V3.

- [ ] **Step 2: Disable V3 DocGen flow**

Turn off the V3 flow (do not delete — keep for rollback).

- [ ] **Step 3: Document the migration**

Update handoff doc with:
- V4 flow ID on each environment
- Azure Function URL
- Template table entity set name
- How to add new templates (Claude conversation process)
