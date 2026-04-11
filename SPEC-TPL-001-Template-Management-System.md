# SPEC-TPL-001: Template Management System

**Version:** 1.0
**Date:** April 7, 2026
**Author:** Joe Cameron, Director of AI Integration — DCFG
**Audience:** Builder (Claude Code CLI or developer)
**Status:** Ready for build

---

## 1. Purpose

DCFG generates contract documents (MSAs, Work Orders, Exhibits, Amendments) by merging Dataverse data into Word templates. Today, templates are manually maintained Word files with yellow-highlighted placeholders. This spec defines a Template Management screen in the DCFG Contracting Suite SPA that lets users upload source templates, map highlighted placeholders to Dataverse fields, and save the mapping so `flow_docgen` can populate documents automatically.

**This system manages templates and their field mappings. It does not generate documents.** Document generation is handled by `flow_docgen` (Power Automate), which consumes the template records and field mappings created here.

---

## 2. Scope

**In scope:**
- Upload .docx template files
- Detect highlighted placeholders (yellow = merge field, cyan = instructional/static text)
- Present a mapping UI where the document preview mirrors the original layout
- Map detected fields to Dataverse columns using user-friendly labels
- Handle composite highlights (multiple logical fields in one highlight span)
- Save template + field mapping records to Dataverse
- Edit existing template mappings
- Template versioning (replace source file, re-map)

**Out of scope (handled elsewhere):**
- .xlsx amendment templates (future phase)
- Document generation (`flow_docgen`)
- DocuSign integration
- Template file storage (SharePoint — already configured)

---

## 3. User roles

| Role | Can do |
|------|--------|
| DCFG_Admin | Full access: upload, map, activate, deactivate, delete templates |
| DCFG_Manager | Upload, map, activate. Cannot delete or deactivate. |
| All other roles | No access. Template Management nav item is suppressed (JS-06). |

---

## 4. Dataverse schema

Two tables already exist in the `DCFGContractingSuite` solution. Confirm schema matches below; if columns are missing, create them using the dataverse-schema-ops skill.

### 4.1 `dcfg_document_template`

EntitySetName: `dcfg_document_templates`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `dcfg_document_templateid` | PK (GUID) | Auto | |
| `dcfg_name` | String 200 | Yes | User-facing template name (e.g., "Exhibit A — Automated (2026)") |
| `dcfg_template_type` | Choice | Yes | See picklist below |
| `dcfg_version` | Integer | Yes | Auto-incremented on re-upload. Starts at 1. |
| `dcfg_source_file_url` | String 500 | Yes | SharePoint URL to the uploaded .docx |
| `dcfg_source_file_name` | String 200 | Yes | Original filename |
| `dcfg_field_count` | Integer | Yes | Total detected merge fields (yellow highlights) |
| `dcfg_mapped_count` | Integer | Yes | Fields with confirmed Dataverse mapping |
| `dcfg_is_active` | Boolean | Yes | Only active templates appear in `flow_docgen` |
| `dcfg_uploaded_by` | String 200 | Yes | Email of uploader |
| `dcfg_uploaded_at` | DateTime | Yes | UTC upload timestamp |
| `dcfg_notes` | Multiline 2000 | No | Optional admin notes |
| `dcfg_customer_id` | Lookup → dcfg_customer | No | If template is customer-specific (e.g., Bancroft). Null = generic. |

**`dcfg_template_type` picklist:**

| Label | Int |
|-------|-----|
| MSA | 100000000 |
| Blanket Work Order | 100000001 |
| Exhibit A — Automated | 100000002 |
| Exhibit A — Variable | 100000003 |
| Amendment | 100000004 |

### 4.2 `dcfg_template_field`

EntitySetName: `dcfg_template_fields`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `dcfg_template_fieldid` | PK (GUID) | Auto | |
| `dcfg_document_template_id` | Lookup → dcfg_document_template | Yes | Parent template |
| `dcfg_field_order` | Integer | Yes | Position in document (1-based, top to bottom) |
| `dcfg_source_text` | String 500 | Yes | Raw highlighted text from source doc (e.g., "Today's Date") |
| `dcfg_user_label` | String 200 | Yes | User-friendly label (e.g., "Today's date") |
| `dcfg_dataverse_path` | String 300 | No | Dataverse column path. Null = unmapped. See Section 6. |
| `dcfg_field_category` | Choice | Yes | See picklist below |
| `dcfg_is_composite` | Boolean | Yes | True if this field resolves to multiple Dataverse columns |
| `dcfg_composite_parts` | Multiline 2000 | No | JSON array of sub-field paths when `dcfg_is_composite = true`. See Section 7. |
| `dcfg_highlight_color` | Choice | Yes | Yellow (100000000) or Cyan (100000001) |
| `dcfg_is_mapped` | Boolean | Yes | Computed: true when `dcfg_dataverse_path` is not null |
| `dcfg_is_repeated` | Boolean | Yes | True if same logical field appears multiple times in doc |
| `dcfg_repeat_group_key` | String 100 | No | Shared key for repeated instances (e.g., "wo_number") |

**`dcfg_field_category` picklist:**

| Label | Int |
|-------|-----|
| Contract identifier | 100000000 |
| Vendor information | 100000001 |
| Decades information | 100000002 |
| Work order terms | 100000003 |
| Amendment financials | 100000004 |
| Instructional text | 100000005 |

---

## 5. User-friendly field label registry

The mapping UI **never** shows Dataverse schema names to the user. Dropdowns display the "User label" column. The Dataverse path is stored on save but hidden from the UI.

### 5.1 Contract identifiers

| User label | Dataverse path | Notes |
|------------|---------------|-------|
| MSA number | `dcfg_msa.dcfg_msa_number` | Via contract → MSA lookup |
| Work order number | `dcfg_wo_number` | Direct on work order |
| Amendment number | `dcfg_amendment_no` | Direct on amendment |
| Today's date | `[SYSTEM:TODAY]` | Generated at merge time, not stored |
| MSA date | `dcfg_msa.createdon` | Via contract → MSA lookup |

### 5.2 Vendor information

| User label | Dataverse path | Notes |
|------------|---------------|-------|
| Vendor legal name | `dcfg_vendor.dcfg_legal_name` | Via MSA → Vendor lookup |
| Vendor full address | `dcfg_vendor.dcfg_address_composite` | Composite: street + city + state + zip |
| Vendor street address | `dcfg_vendor.address1_line1` | Sub-field of address |
| Vendor city, state, zip | `dcfg_vendor.address1_city_state_zip` | Sub-field of address |
| Vendor contact info | `dcfg_vendor_contact.*` | Composite. See Section 7. |

### 5.3 Decades information

| User label | Dataverse path | Notes |
|------------|---------------|-------|
| Account handler info | `dcfg_account_handler.*` | Composite. See Section 7. |
| Bancroft PO number | `dcfg_po_number` | Amendment only |

### 5.4 Work order terms

| User label | Dataverse path | Notes |
|------------|---------------|-------|
| Contract start date | `dcfg_start_date` | |
| Contract end date | `dcfg_end_date` | |
| Contract value | `dcfg_contract_value` | Formatted as "$X,XXX.XX (Written Dollars)" at merge |
| Service days and hours | `dcfg_schedule_description` | Free text |
| Description of service | `dcfg_service_description` | Amendment |
| Properties included | `dcfg_properties_list` | Amendment — computed from child locations |
| Original work order date | `dcfg_wo.createdon` | Amendment — via WO lookup |

### 5.5 Amendment financials

| User label | Dataverse path | Notes |
|------------|---------------|-------|
| Original contract amount | `dcfg_original_amount` | |
| Previously approved changes | `dcfg_prev_changes_amount` | |
| Current contract amount | `dcfg_current_amount` | Calculated: original + previous |
| This change amount | `dcfg_change_amount` | |
| Approved contract amount | `dcfg_approved_amount` | Calculated: current + this change |

---

## 6. Dataverse path resolution

`flow_docgen` uses the `dcfg_dataverse_path` value to resolve data at merge time. Paths follow this convention:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `column_name` | Direct column on the source record | `dcfg_wo_number` |
| `lookup.column_name` | Traverse a lookup, then read a column | `dcfg_vendor.dcfg_legal_name` |
| `lookup.nested_lookup.column` | Two-hop traversal | `dcfg_msa.dcfg_vendor_id.dcfg_legal_name` |
| `[SYSTEM:TODAY]` | Runtime system value | Current date at generation time |
| `[COMPOSITE:key]` | Resolved by composite definition | See Section 7 |

The builder does NOT need to implement path resolution — that is `flow_docgen`'s job. The UI only stores the path string.

---

## 7. Composite field handling

A composite field is a single highlighted span in the source document that maps to multiple Dataverse columns assembled into one output string.

### 7.1 Detection

The upload parser identifies composites by reading the source text for patterns:
- Text containing commas separating distinct data types: "Contact Name, Tele#, email address"
- Text containing parenthetical role identifiers: "(Vendor)", "(Decades)"
- Consecutive highlights that should have been separate: "VENDOR NAME Vendor Street Address City, State, Zip Code"

### 7.2 Storage

When `dcfg_is_composite = true`, the `dcfg_composite_parts` column stores a JSON array:

```json
{
  "format": "{name}, {phone}, {email}",
  "parts": [
    { "key": "name",  "label": "Contact name",  "path": "dcfg_vendor_contact.fullname" },
    { "key": "phone", "label": "Contact phone", "path": "dcfg_vendor_contact.telephone1" },
    { "key": "email", "label": "Contact email", "path": "dcfg_vendor_contact.emailaddress1" }
  ]
}
```

The `format` string tells `flow_docgen` how to assemble the parts. `{key}` placeholders are replaced with resolved values.

### 7.3 Known composites

| Source text pattern | Composite key | Parts |
|---|---|---|
| "Contact Name, Tele#, email address (Vendor)" | `vendor_contact` | fullname, telephone1, emailaddress1 from vendor contact |
| "Account Handler Name, # Tele, Email (Decades)" | `decades_handler` | fullname, telephone1, emailaddress1 from account handler |
| "VENDOR NAME + Vendor Street Address + City, State, Zip Code" | `vendor_address_block` | dcfg_legal_name, address1_line1, address1_city + address1_stateorprovince + address1_postalcode |
| "Contract Value Dollars ($X.XX)" | `contract_value_written` | dcfg_contract_value (formatted as written dollars + numeric) |

### 7.4 UI behavior for composites

In the mapping panel, a composite field displays as a single card with an expandable section:

**Collapsed (default):**
> **10** Vendor contact info — *Mapped (3 sub-fields)*
> → Vendor contact (name, phone, email)

**Expanded (click to expand):**
> **10** Vendor contact info — *Mapped (3 sub-fields)*
> → Contact name: `dcfg_vendor_contact.fullname`
> → Contact phone: `dcfg_vendor_contact.telephone1`
> → Contact email: `dcfg_vendor_contact.emailaddress1`
> Format: "{name}, {phone}, {email}"

The user confirms the composite mapping as a unit. They do not individually map each sub-field in the dropdown — the system proposes the mapping based on the detected pattern, and the user confirms or overrides.

---

## 8. UI specification

### 8.1 Navigation

Template Management lives under **Admin nav** as a left-panel tab alongside Data Administration. Suppressed for non-Admin/Manager roles (JS-06).

### 8.2 Screen: Template list

**Route:** `/admin/templates`

**Layout:** Standard DCFG table screen.

| Element | Spec |
|---------|------|
| Header | "Template management" + "Upload template" button (primary, right-aligned) |
| Table columns | Name, Type (badge), Version, Fields (mapped/total as "9/11"), Status (Active/Inactive badge), Uploaded (date), Customer (or "Generic") |
| Default sort | Most recently uploaded first |
| Row click | Navigate to template detail/mapping screen |
| Empty state | "No templates uploaded yet. Upload a .docx template to get started." with upload button |
| Filters | Type dropdown, Status toggle (Active/Inactive/All) |

**Status badges:**
- Active = green badge
- Inactive = gray badge
- Mapping incomplete = amber badge (when mapped_count < field_count)

### 8.3 Screen: Template upload + mapping

**Route:** `/admin/templates/:id` (new or existing)

**Step bar:** 4 steps — Upload → Detect fields → Map fields → Save template

This is the primary screen. It uses a **split-pane layout**:

#### Left pane: Document preview

- Renders the uploaded .docx content preserving the **original document layout** — same text flow, paragraph structure, section ordering, and visual hierarchy as the source file
- Yellow-highlighted spans are rendered with a warm yellow background (`#FFF3B0`) and a numbered badge (top-right corner of the span, navy circle with white number)
- Cyan-highlighted spans are rendered with a light blue background (`#D6F0FF`) and a lettered badge (i, ii, iii...)
- Non-highlighted body text is rendered as plain text at reduced opacity (the document context, not editable)
- Clicking a highlighted span scrolls the right pane to the corresponding mapping card and highlights it
- Legend at top: yellow swatch = "Merge field", blue swatch = "Instructional text"

**Critical UX rule:** The preview must resemble the original document. The user needs to verify field placement in context. A reformatted table of field names divorced from the document structure defeats the purpose. Preserve paragraph breaks, section numbering, bold/italic formatting, and the general visual rhythm of the source document.

#### Right pane: Field mapping panel

- Summary stats at top: Mapped (green), Unmapped (amber), Instructional (blue) — as metric tiles
- Below stats: scrollable list of field mapping cards, one per detected field, in document order
- Each card contains:
  - **Number badge** matching the document preview
  - **Source text** (what was highlighted in the document)
  - **Status** — Mapped (green) / Unmapped (amber) / Instructional (blue)
  - **Mapping dropdown** — shows user-friendly labels from Section 5. Grouped by category (Contract identifiers, Vendor information, etc.)
  - For composites: collapsed by default showing "Mapped (N sub-fields)", expandable to show individual part paths
  - For instructional (cyan) fields: no dropdown, just a note: "Static text — varies by template variant"
  - For repeated fields (e.g., WO NUMBER appearing 3x): first instance has the dropdown, subsequent instances show "Same as field #1" with a link

#### Bottom bar

- Left: warning text when unmapped fields remain — "N fields need mapping before save"
- Right: "Back" button (secondary), "Save template" button (primary, disabled until all merge fields are mapped)

### 8.4 Upload flow (Step 1 → Step 2)

1. User clicks "Upload template" or drags a .docx file
2. File uploads to SharePoint (existing document library)
3. System extracts document content preserving structure
4. System scans for highlighted runs in the Word XML:
   - `<w:highlight w:val="yellow"/>` = merge field
   - `<w:highlight w:val="cyan"/>` = instructional text
5. Adjacent highlighted runs with the same color are merged into a single field (Word often splits a single highlighted phrase across multiple XML runs)
6. Composite detection runs (Section 7.1)
7. Repeated field detection runs (same normalized text appearing multiple times)
8. System creates `dcfg_template_field` records for each detected field
9. System auto-maps fields where the source text clearly matches a known field label (e.g., "Today's Date" → `[SYSTEM:TODAY]`, "MSA Date" → `dcfg_msa.createdon`)
10. UI advances to Step 3 (Map fields) with auto-mapped fields pre-populated

### 8.5 Auto-mapping rules

The system should attempt to auto-map fields based on the source text. This reduces user effort for well-formatted templates.

| Source text contains | Auto-map to | Confidence |
|---|---|---|
| "MSA#" or "MSA Number" | `dcfg_msa.dcfg_msa_number` | High |
| "Today's Date" | `[SYSTEM:TODAY]` | High |
| "MSA Date" | `dcfg_msa.createdon` | High |
| "Vendor" + "Legal Name" | `dcfg_vendor.dcfg_legal_name` | High |
| "Vendor" + "Address" | `dcfg_vendor.dcfg_address_composite` | High |
| "WO Number" or "Work Order#" | `dcfg_wo_number` | High |
| "Contract Start" + "Date" | `dcfg_start_date` | High |
| "Contract End" + "Date" | `dcfg_end_date` | High |
| "Contract Value" | `dcfg_contract_value` | High |
| "Contact" + "(Vendor)" | Composite: `vendor_contact` | Medium |
| "Contact" + "(Decades)" or "Account Handler" | Composite: `decades_handler` | Medium |
| "Days" + "Times" | `dcfg_schedule_description` | Medium |

Medium-confidence auto-maps should be flagged visually (amber outline on the dropdown) so the user knows to verify.

### 8.6 Edit existing template

Same screen as upload/mapping, but:
- Step 1 (Upload) shows the current file with a "Replace file" button
- Step 2 (Detect) shows "Re-scan" option if user replaced the file
- Step 3 (Map) shows existing mappings, with any new/changed fields flagged
- If a field was present in the old version but missing in the new version, show it as "Removed" (red strikethrough) so the user is aware
- If a new field appeared, show it as "New" (amber badge)

### 8.7 Template activation

- Activate/Deactivate toggle on the template list (inline) and on the detail screen header
- Deactivating a template: modal confirmation — "This template will no longer be available for document generation. Existing generated documents are not affected."
- Only fully-mapped templates (mapped_count = field_count for all merge fields) can be activated
- Audit log entry on activate/deactivate: `dcfg_action_type` = Template Activated (100000007) or Template Deactivated (100000008)

---

## 9. Word XML parsing — technical guidance

The builder needs to parse .docx files to extract highlighted fields. A .docx is a ZIP archive; the document body is at `word/document.xml`.

### 9.1 Highlight detection

```xml
<!-- A highlighted run looks like this -->
<w:r>
  <w:rPr>
    <w:highlight w:val="yellow"/>  <!-- or "cyan" -->
  </w:rPr>
  <w:t>Today's Date</w:t>
</w:r>
```

### 9.2 Run merging

Word frequently splits a single highlighted phrase across multiple `<w:r>` elements. For example, "MSA Date" might be:

```xml
<w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t>M</w:t></w:r>
<w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t>SA </w:t></w:r>
<w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t>D</w:t></w:r>
<w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t>ate</w:t></w:r>
```

**Rule:** Consecutive `<w:r>` elements within the same `<w:p>` that share the same highlight color MUST be merged into a single field. The merged text is "MSA Date".

### 9.3 Document structure preservation

For the preview pane, the parser must also extract:
- Paragraph text (all `<w:t>` content within each `<w:p>`)
- Bold/italic formatting (`<w:b/>`, `<w:i/>` in `<w:rPr>`)
- Paragraph alignment (`<w:jc w:val="center"/>`)
- Section breaks / page breaks (for visual separation)
- List numbering (`<w:numPr>` in `<w:pPr>`)

This does NOT need to be a pixel-perfect Word renderer. It needs to preserve the reading flow so the user recognizes where each field sits in the document.

### 9.4 Where parsing runs

This parsing should happen **server-side** (Power Automate or Azure Function) on upload, not client-side in the browser. The SPA receives the parsed field list and a structured document representation (JSON) from the backend. The SPA renders it.

Suggested document representation payload:

```json
{
  "templateId": "guid",
  "fileName": "Exhibit A — Automated (2026).docx",
  "paragraphs": [
    {
      "index": 0,
      "alignment": "left",
      "isBold": false,
      "runs": [
        { "text": "This work order dated ", "bold": false, "highlight": null },
        { "text": "Today's Date", "bold": true, "highlight": "yellow", "fieldIndex": 2 },
        { "text": ", supplements the Master...", "bold": false, "highlight": null }
      ]
    }
  ],
  "detectedFields": [
    {
      "fieldIndex": 1,
      "sourceText": "WO NUMBER",
      "highlightColor": "yellow",
      "paragraphIndex": 0,
      "isComposite": false,
      "isRepeated": true,
      "repeatGroupKey": "wo_number",
      "autoMapSuggestion": {
        "path": "dcfg_wo_number",
        "label": "Work order number",
        "confidence": "high"
      }
    }
  ]
}
```

---

## 10. Audit logging

All template management actions write to `dcfg_audit_logs`. Use the correct column names per the power-pages-content-ops skill (JS-09, audit log section).

| Action | `dcfg_action_type` | `dcfg_new_value` |
|--------|--------------------|------------------|
| Template uploaded | Data Updated (100000009) | "Template 'Exhibit A — Automated (2026)' uploaded v1, 14 fields detected" |
| Field mapped | Data Updated (100000009) | "Field 'Today's Date' mapped to [SYSTEM:TODAY]" |
| Template activated | Template Activated (100000007) | "Template 'Exhibit A — Automated (2026)' activated" |
| Template deactivated | Template Deactivated (100000008) | "Template 'Exhibit A — Automated (2026)' deactivated" |
| Template file replaced | Data Updated (100000009) | "Template file replaced, version incremented to v2" |

`dcfg_target_table` = `dcfg_document_template` for all template actions.

---

## 11. Table permissions (portal)

Create `mspp_entitypermissions` records for both tables:

| Table | Scope | DCFG_Admin | DCFG_Manager |
|-------|-------|------------|--------------|
| `dcfg_document_template` | Global | CRUD | CR (no Update/Delete) |
| `dcfg_template_field` | Parent (via `dcfg_document_template_id`) | CRUD | CR (no Update/Delete) |

No permissions for other roles — these tables are invisible to non-admin users.

---

## 12. Existing template files

Five Bancroft templates have been analyzed and are ready for initial upload once the system is built. Their field inventories are documented in Section 5 and used as the basis for the auto-mapping rules. The source files are:

| File | Type | Merge fields | Instructional fields |
|------|------|-------------|---------------------|
| Bancroft Master Services Agreement — MSA (Template) (2026).docx | MSA | 3 | 0 |
| Bancroft Blanket Work Order Template (2026).docx | Blanket Work Order | 6 | 0 |
| Exhibit A Template — Automated (2026).docx | Exhibit A — Automated | 11 | 2 |
| Exhibit A Template — Variable (2026).docx | Exhibit A — Variable | 11 | 1 |
| Contracted Services Work Order Amendment (Template).xlsx | Amendment | Deferred (xlsx) | Deferred |

---

## 13. Design constraints

These are non-negotiable. They come from the DCFG UX psychology skill and locked screen patterns.

1. **Review mirrors entry.** The mapping screen preserves the original document layout in the preview pane. Users verify field placement in context, not in a disconnected table.
2. **No Dataverse names in UI.** Every dropdown shows user-friendly labels. Dataverse paths are stored, never displayed.
3. **Progressive disclosure.** Composites are collapsed by default. Instructional fields have no mapping dropdown. Repeated fields link to their first instance.
4. **Role suppression, not disabling (JS-06).** Non-admin users never see the Template Management nav item.
5. **Save gate.** Save button disabled until all yellow-highlighted merge fields are mapped. Cyan instructional fields do not block save.
6. **Status badges follow locked semantics.** Green = active/mapped. Amber = incomplete/pending. Gray = inactive. No new colors.
7. **Toasts are specific.** "Template 'Exhibit A — Automated' saved with 11 field mappings." Not "Saved."
8. **Audit log is insert-only (JS-09).** No edit or delete operations on audit records.
9. **`dcfg_propertys` not `dcfg_properties` (JS-01).** If any OData query touches the properties table, use the correct entity set name.

---

## 14. Open questions for Joe

These items need a decision before build. The builder should flag them, not guess.

1. **Customer-specific vs generic templates.** The `dcfg_customer_id` lookup on `dcfg_document_template` supports customer-specific templates (e.g., Bancroft templates vs a generic DCFG template). Should `flow_docgen` prefer customer-specific templates when available, falling back to generic? Or is template selection always explicit?

2. **Template file storage location.** Spec assumes SharePoint document library. Confirm the library name and folder structure, or if templates should be stored as Dataverse file columns instead.

3. **Parsing engine.** Server-side Word XML parsing could be: (a) a Power Automate cloud flow with Office Script, (b) an Azure Function (Node.js or Python), or (c) a Power Automate desktop flow. Recommend (b) for reliability and speed, but Joe decides.

4. **Version history.** When a template file is replaced, should the old version be retained in SharePoint (versioned file), or overwritten? Spec currently increments `dcfg_version` but does not specify file retention.

5. **Maximum fields per template.** The Exhibit A templates have ~14 fields. Is there a realistic upper bound to plan for? This affects the right pane scroll behavior and whether pagination is needed.

---

## 15. File manifest

Deliver the following:

| Deliverable | Purpose |
|-------------|---------|
| `dcfg-admin/templates/TemplateList.jsx` | Template list screen component |
| `dcfg-admin/templates/TemplateDetail.jsx` | Upload + mapping screen (split-pane) |
| `dcfg-admin/templates/DocumentPreview.jsx` | Left pane — renders parsed document structure with highlights |
| `dcfg-admin/templates/FieldMappingPanel.jsx` | Right pane — mapping cards with dropdowns |
| `dcfg-admin/templates/FieldMappingCard.jsx` | Individual field card (handles simple, composite, instructional, repeated) |
| `dcfg-admin/templates/CompositeExpander.jsx` | Expandable sub-field display for composites |
| `dcfg-admin/templates/fieldRegistry.js` | Static registry of user labels → Dataverse paths (Section 5 as code) |
| `dcfg-admin/templates/autoMapper.js` | Auto-mapping logic (Section 8.5 rules) |
| `dcfg-admin/templates/useTemplateFields.js` | Hook: fetches/saves template field records via portalApi |
| `C:\DCFG\Schema-TPL-001.ps1` | PowerShell: verify/create missing columns on both tables |
| `C:\DCFG\Permissions-TPL-001.ps1` | PowerShell: create table permissions for Admin and Manager roles |
