# DCFG DOCUMENT GENERATION — OOXML-Native Architecture
## CLI Build Handoff

---

## Executive Summary

Replace the current document generation pipeline with native OOXML injection. Instead of converting templates through a format translation layer and PDF converter, the Azure Function reads the .docx template as a ZIP, injects Dataverse values directly into the XML nodes, and outputs a completed .docx. Formatting fidelity is perfect because we never leave the Word format.

The Template Mapper feature (see companion handoff `DCFG_TEMPLATE_MAPPER_CLI_HANDOFF.md` and `DCFG_TEMPLATE_MAPPER_ADDENDUM.md`) produces the field maps that drive this injection. Together they form a closed loop: admins map templates → Joe wires Dataverse paths → the Azure Function generates documents.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SPA (React)                              │
│  Page 04/05/06 → POST to flow_docgen with:                     │
│    • template_id (GUID → dcfg_document_template)                │
│    • record_id   (GUID → source Dataverse record)               │
│    • document_type (VSA/WO/AWO/SPA/SPB/SPC)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTP POST
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Power Automate: flow_docgen                   │
│  1. Receives request                                            │
│  2. Queries dcfg_template_fields for the template_id            │
│  3. Queries source record + related records for field values    │
│  4. Builds payload: { template_ref, field_map[] }               │
│  5. Calls Azure Function                                        │
│  6. Receives completed .docx binary                             │
│  7. Stores in SharePoint + creates dcfg_document_output record  │
│  8. Returns download URL to SPA                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTP POST (binary payload)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                Azure Function: docgen-ooxml                      │
│                                                                  │
│  INPUT:                                                          │
│    • template .docx (from SharePoint or blob)                   │
│    • field_map[]: array of { marker_type, tag, placeholder,     │
│                               value, format_hint }              │
│                                                                  │
│  PROCESS:                                                        │
│    1. Read .docx as ZIP (ArrayBuffer → JSZip or System.IO.Comp) │
│    2. Parse word/document.xml (+ headers/footers)               │
│    3. For each field in field_map:                               │
│       - Locate marker in XML by type-specific strategy          │
│       - Replace marker content with value                       │
│       - Optionally clean marker formatting (remove highlight)   │
│    4. Re-pack ZIP                                                │
│                                                                  │
│  OUTPUT:                                                         │
│    • Completed .docx binary                                     │
│                                                                  │
│  DOES NOT: convert to PDF, touch formatting, restructure doc    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Azure Function: docgen-ooxml

### Language Choice

C# (.NET 8 isolated worker) or Node.js 20 — CLI decides based on existing Azure Function runtime. Both have mature ZIP and XML libraries.

**If C# (.NET):**
- `System.IO.Compression.ZipArchive` for .docx ZIP handling
- `System.Xml.Linq` (LINQ to XML) for OOXML manipulation
- No third-party dependencies needed

**If Node.js:**
- `jszip` for ZIP handling
- Built-in `DOMParser` or `fast-xml-parser` for XML
- Lightweight, same library the client-side parser uses

### Input Contract

```json
{
  "template_url": "https://sharepoint.com/.../VSA_Template_2026.docx",
  "field_map": [
    {
      "marker_type": "content-control",
      "tag": "CustomerName",
      "placeholder": null,
      "value": "Bancroft, A New Jersey Nonprofit Corporation",
      "format_hint": null
    },
    {
      "marker_type": "highlight",
      "tag": null,
      "placeholder": "Today's Date",
      "value": "April 7, 2026",
      "format_hint": "date"
    },
    {
      "marker_type": "highlight",
      "tag": null,
      "placeholder": "LEGAL VENDOR NAME",
      "value": "ABC Plumbing LLC",
      "format_hint": null
    },
    {
      "marker_type": "merge-field",
      "tag": "ContractValue",
      "placeholder": null,
      "value": "45,000.00",
      "format_hint": "currency"
    },
    {
      "marker_type": "underline-blank",
      "tag": null,
      "placeholder": "____________________________",
      "value": "",
      "format_hint": "signature"
    }
  ],
  "options": {
    "clean_highlights": true,
    "preserve_signature_blanks": true,
    "output_format": "docx"
  }
}
```

### Output Contract

```json
{
  "success": true,
  "document_base64": "<base64 encoded .docx>",
  "filename": "VSA_Bancroft_ABC_Plumbing_2026-04-07.docx",
  "fields_injected": 12,
  "fields_skipped": 2,
  "warnings": [
    "Field 'Vendor Signer Title' had no value — left blank"
  ]
}
```

---

## Injection Strategies By Marker Type

Each marker type requires a different XML manipulation strategy. These are the five strategies the Azure Function implements.

### Strategy 1: Content Controls (`w:sdt`)

Content controls are the cleanest — they have explicit tags and structured content.

**Find:** `w:sdt` element where child `w:sdtPr/w:tag[@w:val]` matches the field's `tag` value.

**Inject:** Replace all `w:t` text nodes inside `w:sdtContent` with the new value. Preserve the existing run formatting (`w:rPr`) — just swap the text.

```xml
<!-- BEFORE -->
<w:sdt>
  <w:sdtPr>
    <w:tag w:val="CustomerName"/>
    <w:alias w:val="Customer Name"/>
  </w:sdtPr>
  <w:sdtContent>
    <w:r>
      <w:rPr><w:b/></w:rPr>
      <w:t>[Customer Name]</w:t>
    </w:r>
  </w:sdtContent>
</w:sdt>

<!-- AFTER -->
<w:sdt>
  <w:sdtPr>
    <w:tag w:val="CustomerName"/>
    <w:alias w:val="Customer Name"/>
  </w:sdtPr>
  <w:sdtContent>
    <w:r>
      <w:rPr><w:b/></w:rPr>
      <w:t>Bancroft, A New Jersey Nonprofit Corporation</w:t>
    </w:r>
  </w:sdtContent>
</w:sdt>
```

**Edge case:** If the content control contains multiple runs, collapse them into a single run with the first run's formatting. This prevents value text from inheriting mixed formatting.

---

### Strategy 2: Merge Fields (`MERGEFIELD`)

Merge fields span multiple XML elements: `w:fldChar` (begin), `w:instrText`, `w:fldChar` (separate), result runs, `w:fldChar` (end).

**Find:** Scan for `w:instrText` containing `MERGEFIELD {tag}`. Then identify the complete field span — from the `begin` `fldChar` to the `end` `fldChar`.

**Inject:** Replace the text in the result runs (between `separate` and `end` fldChar elements) with the new value. Alternatively, replace the entire field complex with a simple text run. The second approach is cleaner — once a document is generated, the merge field machinery is no longer needed.

```xml
<!-- BEFORE: merge field complex -->
<w:r><w:fldChar w:fldCharType="begin"/></w:r>
<w:r><w:instrText> MERGEFIELD ContractValue \* MERGEFORMAT </w:instrText></w:r>
<w:r><w:fldChar w:fldCharType="separate"/></w:r>
<w:r><w:t>«ContractValue»</w:t></w:r>
<w:r><w:fldChar w:fldCharType="end"/></w:r>

<!-- AFTER: simple text run (field complex removed) -->
<w:r><w:t>$45,000.00</w:t></w:r>
```

---

### Strategy 3: Yellow Highlights

This is the primary marker method in DCFG's real templates. The critical challenge is that Word fragments highlighted text across multiple runs.

**Find:** Scan each `w:p` (paragraph). Walk its `w:r` (run) children sequentially. When a run has `w:rPr/w:highlight[@w:val="yellow"]`, start accumulating text. Continue accumulating through consecutive highlighted runs. When a non-highlighted run appears (or paragraph ends), flush the accumulated text and match against the field map's `placeholder` value.

**Inject:** Replace all the accumulated highlighted runs with a single new run containing the injected value. Copy the run formatting (`w:rPr`) from the first original run, but remove the `w:highlight` element (so the output text is not yellow).

```xml
<!-- BEFORE: "Today's Date" fragmented across 3 highlighted runs -->
<w:r>
  <w:rPr><w:highlight w:val="yellow"/></w:rPr>
  <w:t>Today's</w:t>
</w:r>
<w:r>
  <w:rPr><w:highlight w:val="yellow"/></w:rPr>
  <w:t xml:space="preserve"> </w:t>
</w:r>
<w:r>
  <w:rPr><w:highlight w:val="yellow"/></w:rPr>
  <w:t>Date</w:t>
</w:r>

<!-- AFTER: single run, highlight removed -->
<w:r>
  <w:rPr/>
  <w:t>April 7, 2026</w:t>
</w:r>
```

**Option `clean_highlights: false`:** Keep the yellow highlight on injected values. Useful for draft/review mode where users want to see which values were auto-filled.

**False positive guard:** The field_map only contains fields the Template Mapper confirmed. The function matches highlighted text against the field_map's `placeholder` values — it does not inject into any highlighted text not in the map. This prevents accidental replacement of highlighted instructional text.

---

### Strategy 4: Bracket/Brace/Angle Placeholders

Text patterns like `[Customer Name]`, `{StartDate}`, `<<ContractValue>>`.

**Find:** Text search within `w:t` elements for the exact `placeholder` string from the field map.

**Inject:** Simple string replacement within the `w:t` text content. Replace `[Customer Name]` with `Bancroft, A New Jersey Nonprofit Corporation`.

```xml
<!-- BEFORE -->
<w:r><w:t>This agreement with [Customer Name] is effective</w:t></w:r>

<!-- AFTER -->
<w:r><w:t>This agreement with Bancroft, A New Jersey Nonprofit Corporation is effective</w:t></w:r>
```

**Caveat:** The placeholder may span multiple `w:t` elements if Word split the run. The function should first attempt exact match in a single `w:t`. If not found, concatenate adjacent `w:t` elements within the same paragraph and search the concatenated text, then reconstruct the runs after replacement.

---

### Strategy 5: Underline Blanks (Signature Lines)

Runs of underscores (`____________________________`) in signature blocks.

**Find:** Match `w:t` content against the exact underscore string from the field map.

**Inject:** Two modes controlled by `preserve_signature_blanks`:
- **true (default):** Leave signature blanks as-is. These are for wet signatures — the document prints with blank lines.
- **false:** Replace underscores with the signer name value. Used when signatures are applied digitally (DocuSign fills these separately anyway).

If value is provided AND `preserve_signature_blanks` is false:
```xml
<!-- BEFORE -->
<w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>____________________________</w:t></w:r>

<!-- AFTER -->
<w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>John Smith</w:t></w:r>
```

---

## Processing Headers, Footers, and Multi-Part Documents

A .docx ZIP contains more than just `word/document.xml`. Fields may appear in:

```
word/document.xml        ← main body (always process)
word/header1.xml         ← header (process all headerN.xml)
word/header2.xml
word/footer1.xml         ← footer (process all footerN.xml)
word/footer2.xml
```

The function must enumerate all XML parts matching `word/header*.xml` and `word/footer*.xml` and run the same injection strategies against each.

Do NOT process:
- `word/styles.xml` — formatting definitions, no user content
- `word/settings.xml` — document settings
- `word/numbering.xml` — list definitions
- `[Content_Types].xml` — MIME mappings

---

## Data Assembly: How flow_docgen Builds the field_map

The Power Automate flow is responsible for querying Dataverse and assembling the `field_map` array that the Azure Function consumes. The flow does NOT do any OOXML work — it only builds the data payload.

### Flow Input (from SPA)

```json
{
  "template_id": "guid-of-dcfg_document_template",
  "record_id": "guid-of-source-record",
  "document_type": "WO"
}
```

### Flow Logic

1. **Get template metadata:**
   Query `dcfg_document_templates({template_id})` for template name, source filename, SharePoint URL.

2. **Get field map:**
   Query `dcfg_template_fields?$filter=_dcfg_template_id_value eq {template_id}&$orderby=dcfg_field_index asc`
   This returns every mapped field with its `dcfg_dataverse_path`.

3. **Get source record data:**
   The `dcfg_dataverse_path` column tells the flow which table and column to query. Paths follow the pattern: `{table}.{column}` or `{table}.{relationship}.{column}` for lookups.

   Examples:
   - `dcfg_contract.dcfg_name` → direct column on the contract record
   - `dcfg_contract.dcfg_customer_id.dcfg_name` → navigate customer lookup, get name
   - `dcfg_contract.dcfg_vendor_id.dcfg_legal_name` → navigate vendor lookup, get legal name
   - `dcfg_contract.dcfg_property_id.dcfg_address` → navigate property lookup, get address
   - `dcfg_msa.dcfg_effective_date` → column on the parent MSA

   The flow resolves each path by:
   - Querying the source record with `$expand` for related entities
   - OR making separate queries per relationship
   
   CLI decides the most efficient query pattern.

4. **Build field_map array:**
   For each `dcfg_template_field` row, emit:
   ```json
   {
     "marker_type": "<from dcfg_marker_type picklist label>",
     "tag": "<dcfg_tag>",
     "placeholder": "<dcfg_placeholder_text>",
     "value": "<resolved value from Dataverse>",
     "format_hint": "<date|currency|null based on column type>"
   }
   ```

5. **Call Azure Function** with template URL + field_map.

6. **Store output:**
   - Save completed .docx to SharePoint document library
   - Create `dcfg_document_output` record linking to template, source record, and SharePoint URL
   - Return download URL to SPA

---

## Dataverse Schema Additions

### Existing tables to verify/extend

**dcfg_document_template** — add column if missing:

| Column | Type | Notes |
|---|---|---|
| dcfg_sharepoint_url | String (500) | URL to the template .docx in SharePoint |

**dcfg_template_field** — add column if missing:

| Column | Type | Notes |
|---|---|---|
| dcfg_dataverse_path | String (500) | Dot-notation path, e.g. `dcfg_contract.dcfg_customer_id.dcfg_name` |
| dcfg_format_hint | Choice | date / currency / text / signature — tells the function how to format the value |

**dcfg_format_hint picklist:**

| Label | Value |
|---|---|
| Text | 100000000 |
| Date | 100000001 |
| Currency | 100000002 |
| Signature | 100000003 |

### dcfg_document_output (may already exist — verify)

Stores each generated document instance.

| Column | Type | Notes |
|---|---|---|
| dcfg_name | String (200) | Auto-generated: "{DocType}_{Customer}_{Date}" |
| dcfg_template_id | Lookup → dcfg_document_template | Which template was used |
| dcfg_source_record_id | String (100) | GUID of the source record |
| dcfg_source_table | String (100) | Logical name of source table |
| dcfg_sharepoint_url | String (500) | URL to completed .docx in SharePoint |
| dcfg_generated_on | DateTime | Timestamp |
| dcfg_generated_by | String (200) | User email |
| dcfg_fields_injected | Whole Number | Count of successfully injected fields |
| dcfg_status | Choice | Generated / Sent / Signed / Void |

---

## Format Hints and Value Formatting

The Azure Function applies formatting based on `format_hint` before injection:

| Hint | Input Value | Formatted Output |
|---|---|---|
| text | `ABC Plumbing LLC` | `ABC Plumbing LLC` (no change) |
| date | `2026-04-07T00:00:00Z` | `April 7, 2026` |
| currency | `45000` | `$45,000.00` |
| currency (written) | `45000` | `Forty-Five Thousand and 00/100` (for "Dollars" fields) |
| signature | `` (empty) | Leave blank or preserve underlines |

**Currency written form:** Some contract templates have a pattern like "Contract Value Dollars ($X.XX)" where the written-out amount and numeric amount are adjacent fields. The format_hint handles this — a field marked `currency` gets `$45,000.00`, while a companion field could be marked with a `currency_written` hint (add to picklist if needed) for the word form.

Date formatting should match Bancroft's convention (seen in templates as "Today's Date" — presumably Month Day, Year). The function should accept an optional `date_format` in options, defaulting to `MMMM d, yyyy`.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Template .docx not found in SharePoint | Return error, do not generate |
| Template .docx is not a valid ZIP | Return error with message |
| Field in map not found in document | Skip field, add to `warnings` array |
| Dataverse path resolves to null | Inject empty string, add to `warnings` |
| Multiple matches for same placeholder | Inject into ALL matches (some fields appear more than once, e.g. WO NUMBER appears on each exhibit page) |
| Highlighted text fragmentation doesn't match placeholder exactly | Attempt fuzzy match: normalize whitespace, trim, case-insensitive compare |

---

## Options Object

```json
{
  "clean_highlights": true,
  "preserve_signature_blanks": true,
  "output_format": "docx",
  "date_format": "MMMM d, yyyy",
  "draft_mode": false
}
```

| Option | Default | Effect |
|---|---|---|
| clean_highlights | true | Remove yellow highlighting from injected values |
| preserve_signature_blanks | true | Leave underline blanks as-is for wet/digital signatures |
| output_format | "docx" | Future: could add "pdf" if a conversion step is ever needed |
| date_format | "MMMM d, yyyy" | How ISO dates are formatted for display |
| draft_mode | false | If true, keeps highlights and adds "[DRAFT]" watermark |

---

## What This Replaces

The current `flow_docgen` flow (described in SPA skill as "15 variables, parallel data lookups, 31-token merge field map") is restructured:

| Before | After |
|---|---|
| Hardcoded merge field map in flow | Dynamic field map from `dcfg_template_fields` table |
| Format translation through converter | Direct OOXML injection — no conversion |
| Fixed to known templates | Any template the admin maps via Template Mapper |
| Adding a template requires Joe | Adding a template requires Brook + Template Mapper |
| PDF output | Native .docx output (PDF conversion optional, separate step) |

The flow still orchestrates — it still queries Dataverse, still calls the function, still stores the output. But the intelligence about *which fields go where* moves from hardcoded flow variables to the Dataverse field map. And the document manipulation moves from format conversion to native XML injection.

---

## Integration Points

### SPA Changes

The SPA call signature stays the same — Pages 04, 05, 06 still POST to `dcfg_flow_docgen_url`. The request body adds `template_id`:

```javascript
// Current (assumed)
await apiPost(FLOW_DOCGEN_URL, {
  record_id: contractId,
  document_type: 'WO',
});

// New
await apiPost(FLOW_DOCGEN_URL, {
  template_id: selectedTemplateId,  // from dcfg_document_template
  record_id: contractId,
  document_type: 'WO',
});
```

If no `template_id` is provided, the flow should look up the active template for that document type (`dcfg_template_status = Active`). This maintains backward compatibility.

### Template Mapper Connection

The Template Mapper (companion handoff) writes to `dcfg_document_template` and `dcfg_template_field`. Joe fills in `dcfg_dataverse_path` on each field. Once paths are populated and template status is set to Active, the template is live for document generation.

### DocuSign

DocuSign accepts .docx uploads directly. If the current pipeline converts to PDF specifically for DocuSign, that step can be removed — DocuSign will process the .docx and apply its own signature fields. If DocuSign tag placement depends on specific text markers in the document, those markers should be included as fields in the template map with `format_hint: signature`.

---

## CLI Execution Sequence

1. **Audit existing Azure Function** — examine current code, runtime, language, what it does today
2. **Verify/extend Dataverse schema** — check `dcfg_document_template`, `dcfg_template_field`, `dcfg_document_output` tables; add missing columns
3. **Build Azure Function `docgen-ooxml`** — implement the five injection strategies, ZIP handling, header/footer processing, format hints
4. **Test against real templates** — use the five Bancroft templates from the Contracts.zip upload as test fixtures:
   - Bancroft Blanket Work Order Template (2026)
   - Bancroft Master Services Agreement (2026)
   - EXHIBIT A TEMPLATE - AUTOMATED (2026)
   - EXHIBIT A TEMPLATE - VARIABLE (2026)
   - Work Order Amendment (.xlsx — deferred, .docx only for v1)
5. **Rebuild flow_docgen** — replace hardcoded merge map with dynamic field_map assembly from Dataverse
6. **Update SPA call** — add `template_id` to request body on Pages 04, 05, 06
7. **Seed test data** — create a template record + field records for one template, populate `dcfg_dataverse_path` values, run end-to-end test

### Test Validation

For each template, verify:
- All highlighted fields are correctly merged (no fragmentation)
- All values appear in the output .docx at the correct positions
- Formatting is preserved (bold, italic, font size, tables, headers)
- Highlights are cleaned (if option set)
- Signature blanks are preserved
- Output opens cleanly in Word with no corruption warnings
- Headers and footers are processed

---

## Out of Scope for v1

- **.xlsx template support** — the Amendment template is Excel; defer to v2
- **PDF output** — native .docx is the output; PDF conversion is a separate optional step if ever needed
- **Repeating sections** — line item tables (Exhibit B) where rows repeat per cost code; defer to v2 after Exhibit B template is provided
- **Template versioning** — tracking which version of a template was used for a historical document; the `dcfg_document_output` lookup to `dcfg_document_template` provides this implicitly
- **Watermarks** — draft_mode watermark injection is a nice-to-have, not v1

---

## Files Included in This Handoff

| File | Purpose |
|---|---|
| `DCFG_TEMPLATE_MAPPER_CLI_HANDOFF.md` | Template Mapper component spec (React UI, Dataverse schema, parser, predictor) |
| `DCFG_TEMPLATE_MAPPER_ADDENDUM.md` | Real template analysis — parser fixes needed, field-by-field breakdown |
| `DCFG_DOCGEN_OOXML_CLI_HANDOFF.md` | **This document** — OOXML-native generation architecture |
| `Contracts.zip` (uploaded) | Five real Bancroft templates for testing |
