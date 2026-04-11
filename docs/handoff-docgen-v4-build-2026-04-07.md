# Handoff: DocGen V4 — OOXML Injection Engine Build

**Date:** 2026-04-07
**Session:** Azure Function build + template analysis + flow research
**Operator:** Joseph Cameron

---

## What Was Accomplished

### 1. Azure Function: OOXML Injection Engine — LIVE

**URL:** `https://dcfg-html-to-pdf-d9bwchakhgduf4gc.eastus-01.azurewebsites.net/api/html-to-pdf`
**Key:** `<REDACTED — stored in dcfg_configs as dcfg_ooxml_function_key>`
**Resource Group:** `dcfg-docgen`
**Function App:** `dcfg-html-to-pdf` (Flex Consumption, Node.js 22, Linux, East US)
**Code:** `C:\dcfg\azure-functions\html-to-pdf\src\functions\htmlToPdf.js`
**Size:** 1.1MB deployed

**What it does:** Receives a .docx as base64 + a field_map array. Opens the .docx as ZIP, injects values into XML nodes using 5 strategies, returns the completed .docx as base64. Never leaves Word format — formatting is perfect.

**Five injection strategies implemented:**
1. **Content Controls** (`w:sdt`) — find by `w:tag` value, replace `w:t` text
2. **Merge Fields** (`MERGEFIELD`) — replace entire field complex with text run
3. **Yellow Highlights** — find consecutive highlighted runs matching placeholder, inject value, remove highlight
4. **Bracket/Brace Placeholders** — text replacement in `w:t` elements
5. **Underline Blanks** — signature line handling (preserve or replace)

**Tested successfully:**
- Local: MSA template, 11 fields injected, output opens clean in Word
- Azure: MSA template, 2-field quick test + full 11-field test, both successful

### 2. Template Analysis Complete

**All 23 templates from Templates library + Contracts.zip analyzed:**

| Template | Marker Type | Marker Count |
|----------|------------|-------------|
| Decades MSA (Contracts.zip) | Yellow highlights | 10 |
| Exhibit C Fee Schedule | Underline blanks | 4 |
| Bancroft BWO Amendment | Content controls | 2 |
| All other Templates library files | Empty shells or static | 0 |

**Key finding:** The Templates library `.docx` files are mostly empty shells designed for Word Online connector. The real content templates are in Contracts.zip and the root-level standardized files.

### 3. V4 Flow Fully Analyzed

**Flow:** `DCFG DocGen v4` — ID `a9b7da25-0c32-f111-88b3-000d3a308e39`
**Environment:** Prod `6ee0cd74-e2b2-e429-ac4b-27123cd20d19`
**Status:** Active (copy of V3, not yet modified)

**Current structure (from V3):**
- Trigger: `dcfg_document_request` row creation (request_type=DocGen, status=Pending)
- 6 variable initializations
- Condition_No_Template → fail if no template linked
- Condition_Is_Contract → Get_Contract + Get_Contract_Lines OR Get_MSA
- Get_Customer, Get_Vendor, Get_Property (parallel)
- Build_Token_Map (45 fields, Compose action)
- **Switch_Template** (11 cases, each with Word Online Populate + SetVariable)
- Build output folder path → Create SharePoint folders → Create_file
- Create_Document_Output_Record → Write_Audit_Log → Update_Request_Complete
- Handle_Flow_Failure (error handler)

**What needs to change:**
- Remove Switch_Template + all Word Online Populate actions
- Add: Read template .docx from SharePoint → Read field_map from dcfg_template_fields → Query source data per field paths → Call Azure Function → Save output .docx
- Keep: everything before Switch and after Create_file

### 4. Dataverse Schema Verified

**Tables confirmed on Prod:**

| Table | Entity Set | Status |
|-------|-----------|--------|
| `dcfg_document_template` | `dcfg_document_templates` | 20 records, has `dcfg_sharepoint_url` |
| `dcfg_template_field` | `dcfg_template_fields` | 0 records, 22 custom columns |
| `dcfg_document_request` | `dcfg_document_requests` | Active, working |
| `dcfg_document_output` | `dcfg_document_outputs` | 1+ records |

**dcfg_template_field columns (key ones):**
- `dcfg_template_id` — Lookup to template
- `dcfg_merge_field_name` — Tag/placeholder in Word doc
- `dcfg_source_entity` + `dcfg_source_column` — Dataverse path
- `dcfg_field_type` — Picklist: SystemValue, Text, MultiLineText, Number, Currency, Date, YesNo, Dropdown, Paragraph
- `dcfg_display_label` — User-friendly name
- `dcfg_is_required` — Required flag

### 5. Design Evolution

Session started with HTML/PDF approach → spec review killed it (Word Online can't inject OOXML) → pivoted to PDFKit (worked but formatting issues) → user directed to OOXML handoff doc → rebuilt as native OOXML injection. Final architecture preserves Word format perfectly.

**Approaches tried and discarded:**
- HTML templates + html2pdf.js (rasterized, not real PDF)
- HTML templates + Paged.js (client-side, no server save)
- HTML templates + Azure Function Puppeteer (sandbox missing libs)
- HTML templates + PDFKit (quality/formatting issues)
- **Winner:** OOXML injection via jszip (native Word, perfect fidelity)

### 6. Spec Documents

| File | Status |
|------|--------|
| `docs/superpowers/specs/2026-04-06-docgen-v4-blackbox-design.md` | Outdated — was HTML approach, superseded |
| `DCFG_DOCGEN_OOXML_CLI_HANDOFF.md` | **Authoritative** — OOXML injection architecture |
| `SPEC-TPL-001-Template-Management-System.md` | **Authoritative** — Template Management UI spec, ready for build |

### 7. Processed Output

All template PDFs (from earlier HTML approach) at `C:\dcfg\tmp\v4_processed\` — obsolete now that we're using OOXML.

OOXML injection test output: `C:\dcfg\tmp\v4_processed\contracts\MSA_INJECTED.docx` — open in Word to verify quality.

---

## What's Next

### Immediate: Template Management UI (SPEC-TPL-001)

**Blocked on:** Operator UX requirements (Joseph said to pause before UX work)

The spec defines:
- Template list screen (`/admin/templates`)
- Upload + split-pane mapping screen (document preview left, field mapping right)
- Auto-mapping rules for common fields
- Composite field handling
- 11 React components

### After UI: Flow Wiring

Replace the V4 flow's Switch_Template with:
1. Read template .docx from SharePoint (using `dcfg_sharepoint_url`)
2. Read field_map from `dcfg_template_fields` (filtered by template_id)
3. Query source data per `dcfg_source_entity` + `dcfg_source_column`
4. POST to Azure Function (template_base64 + field_map)
5. Save returned .docx to SharePoint

### Open Questions (from SPEC-TPL-001 Section 14)

1. Customer-specific vs generic template selection
2. Template file storage (SharePoint library name/structure)
3. Parsing engine location (Azure Function recommended)
4. Version history retention
5. Maximum fields per template

---

## Auth Profile Reference (CHANGED from earlier sessions)

| Index | Environment | Org URL |
|-------|-------------|---------|
| 1 | **Prod** | `org06f5de0b.crm.dynamics.com` |
| 2 | **Test** | `org0c17e98d.crm.dynamics.com` |
| 3 | **Stage** | `org88778bb0.crm.dynamics.com` |

**IMPORTANT:** Indices have changed from previous sessions. Verify with `pac auth list` before any deploy.

---

## SPA data-testid Patches (also done this session)

19 data-testid attributes added across 4 files, deployed to all 3 sites:
- ContractDetail.jsx: btn-void, btn-decline, btn-create-amendment
- Onboarding.jsx: onb-btn-toggle-deleted, onb-btn-restore, onb-btn-delete, new-case-customer-select, new-case-btn-cancel, new-case-btn-save
- SendQueue.jsx: email-reminder-check, email-reminder-days
- Admin.jsx: 7 edit/delete buttons across tabs
