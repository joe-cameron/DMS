# DocGen V4 — HTML Template Engine with Azure Function PDF Renderer

**Date:** 2026-04-06
**Author:** Joseph Cameron / Claude
**Status:** Approved
**Replaces:** DocGen V3 Switch-based Word Online field mapping
**Flow:** DCFG DocGen v4 (a9b7da25-0c32-f111-88b3-000d3a308e39) on Prod (6ee0cd74-e2b2-e429-ac4b-27123cd20d19)
**Stack:** Power Automate + Dataverse + Azure Function (Puppeteer) + SharePoint

---

## 1. What This System Does

Generates professional PDF documents from HTML templates stored in Dataverse. A single Azure Function converts HTML to PDF. The Power Automate flow orchestrates: read template, merge data, call function, save PDF. No Word files at runtime. No content controls. No field mapping. No designer activation.

Templates are created through a Claude conversation: user hands Claude an office document, Claude interviews the user to identify data fields, Claude produces the HTML template and writes it to Dataverse. Live immediately.

---

## 2. Why V4

| | V3 (12 templates) | V3 (120 templates) | V4 (120 templates) |
|---|---|---|---|
| Word template files | 12 | 120 | 0 |
| Switch cases in flow | 12 | 120 | 0 |
| Field mappings | ~240 | ~2,400 | 0 |
| Designer activations | ~240 | ~2,400 | 0 |
| Flow actions to maintain | ~200+ | ~2,000+ | ~10 (fixed) |
| Add new template | Hours | Hours | One Claude conversation |
| Flow changes when templates change | Always | Always | Never |

---

## 3. Architecture

```
BUILD TIME (once per template):
  User gives Claude an office doc (Word, Excel, PDF)
  → Claude reads it, asks: "what field is this?"
  → User answers conversationally
  → Claude produces HTML template + print CSS + field manifest
  → Claude writes to dcfg_document_templates via Dataverse API
  → Live immediately

RUNTIME (every document request):
  SPA: createDocumentRequest()
  → Flow triggers on new dcfg_document_requests row
  → Flow reads HTML template from dcfg_document_templates
  → Flow queries source data (fields from manifest)
  → Flow replaces {{tokens}} with formatted data
  → Flow calls Azure Function: HTML in → PDF blob out
  → Flow saves PDF to SharePoint DCFG_Outputs/{Customer}/{Year}/{DocType}
  → Flow updates dcfg_document_requests status → Complete
```

---

## 4. Components

### 4.1 Dataverse Table: `dcfg_document_templates`

| Column | Type | Purpose |
|--------|------|---------|
| `dcfg_document_templateid` | GUID (PK) | |
| `dcfg_name` | String (200) | "Bancroft — Vendor MSA" |
| `dcfg_client` | Lookup → dcfg_customer | Which client owns this template |
| `dcfg_document_type` | Choice | VendorAgreement, WorkOrder, Amendment, Proposal_A, etc. |
| `dcfg_html_body` | Multiline Text (max) | HTML template with `{{tokens}}` and embedded `<style>` |
| `dcfg_field_manifest` | Multiline Text | JSON — maps tokens to Dataverse fields + format rules |
| `dcfg_source_entity` | String (200) | Primary entity set: `dcfg_contracts`, `dcfg_vendoragreements` |
| `dcfg_expand_entities` | Multiline Text | JSON — related entities to $expand |
| `dcfg_version` | Integer | Incremented on update |
| `dcfg_active_flag` | Boolean | Soft delete |
| `dcfg_created_on` | DateTime | Auto |
| `dcfg_modified_on` | DateTime | Auto |

### 4.2 Field Manifest Format

```json
[
  { "token": "customer_name", "field": "dcfg_customer_name", "format": "text" },
  { "token": "effective_date", "field": "dcfg_effective_date", "format": "date" },
  { "token": "contract_value", "field": "dcfg_contract_value", "format": "currency" },
  { "token": "scope_of_work", "field": "dcfg_scope_of_work", "format": "multiline" },
  { "token": "is_prevailing_wage", "field": "dcfg_prevailing_wage", "format": "boolean", "trueText": "Yes", "falseText": "No" },
  { "token": "trade_type", "field": "dcfg_trade_type", "format": "choice", "choices": { "100000000": "Plumbing", "100000001": "Electrical" } },
  { "token": "customer_name", "entity": "_dcfg_customer_value", "expand": "dcfg_customer", "field": "dcfg_name", "format": "text" }
]
```

### 4.3 Repeating Sections (Child Records)

```json
{
  "token": "exhibit_lines",
  "format": "children",
  "entity": "dcfg_exhibit_a_lines",
  "filter": "_dcfg_contract_value eq {recordId}",
  "orderby": "dcfg_line_number asc",
  "fields": [
    { "token": "line_number", "field": "dcfg_line_number", "format": "number" },
    { "token": "description", "field": "dcfg_description", "format": "text" },
    { "token": "amount", "field": "dcfg_amount", "format": "currency" }
  ]
}
```

The flow queries child records, loops, and produces repeated HTML blocks via Handlebars `{{#each}}` syntax before sending to the Azure Function.

### 4.4 Format Types

| Format | Behavior |
|--------|----------|
| `text` | Direct substitution, HTML-escaped |
| `date` | Formatted as MM/DD/YYYY |
| `currency` | Formatted as $X,XXX.XX |
| `number` | Formatted with commas |
| `percent` | Formatted as X.X% |
| `multiline` | Line breaks converted to `<br>` |
| `boolean` | Renders trueText/falseText from manifest |
| `choice` | Maps Dataverse choice int to label from manifest |
| `lookup` | Display name via OData formatted value annotation |
| `phone` | Formatted as (XXX) XXX-XXXX |
| `uppercase` | Uppercased text |

---

## 5. Azure Function: HTML to PDF

### What It Does

Receives an HTML string, renders it with Puppeteer (headless Chrome), returns a PDF blob.

### Specification

- **Runtime:** Node.js 20
- **Trigger:** HTTP (POST)
- **Input:** JSON body `{ "html": "<full HTML string>" }`
- **Output:** PDF binary (application/pdf)
- **Hosting:** Azure Functions Consumption Plan
- **Cost:** ~$0/month at DCFG volume (< 1000 executions/month)
- **Cold start:** ~3-5s first call, <1s warm

### Implementation (~20 lines)

```javascript
const { app } = require('@azure/functions');
const puppeteer = require('puppeteer');

app.http('html-to-pdf', {
  methods: ['POST'],
  handler: async (request) => {
    const { html } = await request.json();
    const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });
    const pdf = await page.pdf({
      format: 'Letter',
      printBackground: true,
      margin: { top: '0', bottom: '0', left: '0', right: '0' },
      preferCSSPageSize: true,
    });
    await browser.close();
    return { body: pdf, headers: { 'Content-Type': 'application/pdf' } };
  }
});
```

### Security

- Function key auth (not anonymous) — Power Automate stores the key in a connection or environment variable
- No data persisted — HTML in, PDF out, nothing stored
- Runs in Azure's sandboxed environment

---

## 6. Power Automate Flow: DCFG DocGen v4

### Trigger

Same as V3: `When a row is added` on `dcfg_document_requests` where `dcfg_request_type eq 100000000` and `dcfg_status eq 100000000`.

### Actions (The Black Box — replaces the Switch)

```
1. [Existing] Trigger → read document request (template_type, record_id, client)
2. [Existing] Set_Status_Processing → update request status to Processing

3. [NEW] Get_Template_Definition
   → Query dcfg_document_templates
   → Filter: dcfg_document_type eq request.template_type
             AND _dcfg_client_value eq request.client_id
             AND dcfg_active_flag eq true

4. [NEW] Parse_Manifest → Parse JSON on field_manifest

5. [NEW] Get_Source_Record
   → HTTP with Azure AD to Dataverse Web API
   → Dynamic URL: {org}/api/data/v9.2/{source_entity}({record_id})?$select={manifest fields}&$expand={expand entities}
   → Prefer: odata.include-annotations=*

6. [NEW] Build_Final_HTML
   → Compose action: replace each {{token}} with formatted data value
   → For children entries: query child records, loop, build repeated HTML blocks
   → Result: complete HTML string with all data merged

7. [NEW] Call_PDF_Function
   → HTTP POST to Azure Function URL
   → Body: { "html": outputs('Build_Final_HTML') }
   → Returns: PDF binary blob

8. [Existing] Build output path: DCFG_Outputs/{Customer}/{Year}/{DocType}
9. [Existing] Create folders if needed
10. [Existing] Save PDF to SharePoint
11. [Existing] Create document output record
12. [Existing] Write audit log
13. [Existing] Update request status → Complete
```

Steps 1-2 and 8-13 already exist in the copied V3 flow. Steps 3-7 replace the entire Switch block. The flow never changes when templates change.

### Error Handling

Existing try-catch-finally Scope pattern carries over from V3:
- **Try Scope:** Steps 3-12
- **Catch Scope:** Log error to audit, update request status → Failed with error message
- **Handle_Flow_Failure:** Already exists in the V3 copy

### Null/Missing Data

| Condition | Behavior |
|-----------|----------|
| Template not found | Update request → Failed, message: "No template found for this document type and client" |
| Source record not found | Update request → Failed, message: "Source record not found" |
| Token value is null | Replace with empty string — document generates with blank field |
| Child query returns 0 rows | Repeating section renders empty (no rows) |
| Azure Function fails | Retry 3x (exponential), then update request → Failed |

---

## 7. The Build Process

### Creating a New Template

1. User uploads an office document (Word, Excel, PDF) to Claude
2. Claude reads it, identifies variable data: "This says 'ABC Plumbing' — is that the vendor name?"
3. User answers: "That's the vendor name, it comes from the contract"
4. Claude produces: HTML template with `{{tokens}}`, print CSS in a `<style>` block, field manifest JSON
5. Claude writes the template to `dcfg_document_templates` via Dataverse API
6. Template is live immediately — next Generate request uses it

### Updating a Template

Same conversation. User gives Claude the revised document. Claude produces updated HTML. Claude overwrites the Dataverse row. Version incremented. Live immediately.

### Who Can Do This

Anyone who can have a Claude conversation. No flow editing. No Word template engineering. No designer activation. No Azure Function changes.

---

## 8. Migration from V3

1. For each of the 12 existing Bancroft templates, Claude reads the current Word template and produces the HTML equivalent + manifest
2. Store as rows in `dcfg_document_templates` with `dcfg_client` = Bancroft
3. Replace the Switch block in the V4 flow with steps 3-7 above
4. Test each template type: compare V4 PDF output against V3 Word output
5. V3 flow remains active during migration — V4 takes over per template type as validated
6. Once all templates validated, V3 Switch block is dead code

---

## 9. DocuSign Integration

The PDF produced by the flow feeds directly into DocuSign:

1. Flow generates PDF (same as above)
2. User downloads PDF from SharePoint or Send Queue
3. User uploads to DocuSign manually (drag-and-drop per April 3rd meeting — no API, $500-600/mo rejected)
4. Future: optional flow action to POST PDF to DocuSign API if pricing changes

---

## 10. What This Does NOT Change

- `dcfg_document_requests` transaction table — same trigger, same status lifecycle
- `createDocumentRequest()` in the SPA — same function
- SharePoint output structure — same `DCFG_Outputs/{Customer}/{Year}/{DocType}`
- Send Queue — same downstream (receives PDF instead of .docx)
- Audit logging — same
- SPA screens and wizards — unchanged

---

## 11. Output Format Change

V3 produces `.docx`. V4 produces `.pdf`. Implications:

| Concern | Resolution |
|---------|-----------|
| Users need to edit documents | They don't — contracts are system-generated, not user-edited. Edits happen in the SPA, then regenerate. |
| DocuSign compatibility | PDF is DocuSign's native format — better than .docx |
| Print quality | PDF prints identically everywhere — better than .docx which renders differently per Word version |
| File size | PDF is typically smaller than .docx with embedded content controls |
| Archival | PDF/A is the standard for document archival |

---

## 12. Azure Function Deployment

### One-Time Setup

1. Create Azure Function App (Consumption plan, Node.js 20, East US)
2. Deploy the html-to-pdf function
3. Get the function URL + key
4. Store URL in `dcfg_configs` as `docgen_v4_pdf_function_url`
5. Store key in Power Automate connection or environment variable (secure)

### Cost Estimate

| Metric | Value |
|--------|-------|
| Executions/month | < 500 |
| Execution time | ~3-5s per document |
| Memory | 256MB |
| Monthly cost | $0.00 (within free grant of 1M executions/400K GB-s) |

Azure Functions Consumption Plan includes 1 million free executions per month. DCFG will use < 0.1% of that.
