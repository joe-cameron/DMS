# WordprocessingML Reference — Complete Word XML Guide

The authoritative reference for editing .docx files at the XML level. ECMA-376 Part 1 / ISO 29500.

## Document Structure

A .docx is a zip containing these key XML parts:

```
word/document.xml       — body content (paragraphs, tables, SDTs)
word/styles.xml         — style definitions (Normal, Heading1, ListBullet, etc.)
word/numbering.xml      — bullet/number list definitions
word/settings.xml       — document settings (compatibility, zoom, proofing)
word/header1.xml        — header content (one per section)
word/footer1.xml        — footer content
word/footnotes.xml      — footnote content
word/endnotes.xml       — endnote content
word/comments.xml       — comment content
word/theme/theme1.xml   — theme (colors, fonts, effects)
word/media/             — embedded images
word/_rels/document.xml.rels — relationships (hyperlinks, images, headers)
[Content_Types].xml     — MIME type registry
```

## Namespace Prefixes

| Prefix | URI | Used for |
|--------|-----|----------|
| `w` | `http://schemas.openxmlformats.org/wordprocessingml/2006/main` | All body elements |
| `r` | `http://schemas.openxmlformats.org/officeDocument/2006/relationships` | Relationship IDs |
| `mc` | `http://schemas.openxmlformats.org/markup-compatibility/2006` | Compatibility |
| `w14` | `http://schemas.microsoft.com/office/word/2010/wordml` | Word 2010+ extensions |
| `w15` | `http://schemas.microsoft.com/office/word/2012/wordml` | Word 2013+ extensions |
| `wp` | `http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing` | Images/drawings |

## Core Elements

### Paragraph (`<w:p>`)

The fundamental block-level element. Contains runs and paragraph properties.

```xml
<w:p w14:paraId="1A2B3C4D" w14:textId="5E6F7A8B">
  <w:pPr>
    <w:pStyle w:val="Normal"/>
    <w:jc w:val="left"/>           <!-- justification: left|center|right|both -->
    <w:ind w:left="720" w:hanging="360"/>  <!-- indentation in twips -->
    <w:spacing w:before="120" w:after="120" w:line="240" w:lineRule="auto"/>
    <w:numPr>                      <!-- numbering (bullets/lists) -->
      <w:ilvl w:val="0"/>
      <w:numId w:val="1"/>
    </w:numPr>
    <w:rPr>                        <!-- default run properties for this paragraph -->
      <w:b/>
    </w:rPr>
  </w:pPr>
  <w:r>
    <w:rPr><w:b/></w:rPr>
    <w:t>Bold text</w:t>
  </w:r>
</w:p>
```

**Key properties (`<w:pPr>`):**

| Element | Purpose | Values |
|---------|---------|--------|
| `<w:pStyle>` | Named style reference | Style ID from styles.xml |
| `<w:jc>` | Justification | `left`, `center`, `right`, `both` (justified) |
| `<w:ind>` | Indentation | `w:left`, `w:right`, `w:firstLine`, `w:hanging` (twips) |
| `<w:spacing>` | Spacing | `w:before`, `w:after` (twips), `w:line`, `w:lineRule` |
| `<w:numPr>` | List numbering | `<w:ilvl>` (level), `<w:numId>` (definition ref) |
| `<w:keepNext/>` | Keep with next paragraph | Boolean (presence = true) |
| `<w:keepLines/>` | Keep lines together | Boolean |
| `<w:pageBreakBefore/>` | Page break before | Boolean |
| `<w:outlineLvl>` | Outline level | 0-8 (for TOC) |
| `<w:tabs>` | Tab stops | `<w:tab w:val="left" w:pos="4320"/>` |
| `<w:rPr>` | Default run formatting | Applies to paragraph mark and any run without its own rPr |

**Twips:** 1 twip = 1/20 point = 1/1440 inch. 720 twips = 0.5 inch.

### Run (`<w:r>`)

An inline span of text with consistent formatting.

```xml
<w:r>
  <w:rPr>
    <w:b/>                         <!-- bold -->
    <w:i/>                         <!-- italic -->
    <w:u w:val="single"/>          <!-- underline -->
    <w:sz w:val="24"/>             <!-- font size in half-points (24 = 12pt) -->
    <w:color w:val="FF0000"/>      <!-- text color -->
    <w:rFonts w:ascii="Arial"/>    <!-- font -->
    <w:highlight w:val="yellow"/>  <!-- text highlight -->
    <w:strike/>                    <!-- strikethrough -->
    <w:vertAlign w:val="superscript"/>  <!-- super/subscript -->
  </w:rPr>
  <w:t xml:space="preserve">Text content </w:t>
</w:r>
```

**Key properties (`<w:rPr>`):**

| Element | Purpose | Notes |
|---------|---------|-------|
| `<w:b/>` | Bold | Presence = on, `<w:b w:val="false"/>` = off |
| `<w:i/>` | Italic | Same toggle pattern |
| `<w:u>` | Underline | `w:val`: single, double, wave, dash, dotted, none |
| `<w:sz>` | Font size | In half-points: val="24" = 12pt |
| `<w:szCs>` | Complex-script size | Same scale |
| `<w:color>` | Font color | Hex RGB or theme ref |
| `<w:highlight>` | Highlight color | yellow, green, cyan, etc. |
| `<w:rFonts>` | Font family | `w:ascii`, `w:hAnsi`, `w:cs`, `w:eastAsia` |
| `<w:rStyle>` | Character style | References styles.xml |

**CRITICAL for DCFG DocGen:** The yellow highlight (`<w:highlight w:val="yellow"/>`) is how `ooxmlInject.js` identifies placeholder runs. During injection, the highlight is stripped and the text is replaced, but all other `<w:rPr>` properties are preserved.

### Text (`<w:t>`)

Always inside a `<w:r>`. The `xml:space="preserve"` attribute is required when the text has leading/trailing spaces.

```xml
<w:t xml:space="preserve"> text with spaces </w:t>
```

Without `xml:space="preserve"`, XML parsers strip leading/trailing whitespace.

### Table (`<w:tbl>`)

```xml
<w:tbl>
  <w:tblPr>
    <w:tblStyle w:val="TableGrid"/>
    <w:tblW w:w="9360" w:type="dxa"/>      <!-- width in twips -->
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>
      <w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>
      <w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>
      <w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>
    </w:tblBorders>
  </w:tblPr>
  <w:tblGrid>
    <w:gridCol w:w="4680"/>
    <w:gridCol w:w="4680"/>
  </w:tblGrid>
  <w:tr>                                    <!-- table row -->
    <w:tc>                                  <!-- table cell -->
      <w:tcPr>
        <w:tcW w:w="4680" w:type="dxa"/>
      </w:tcPr>
      <w:p><w:r><w:t>Cell 1</w:t></w:r></w:p>
    </w:tc>
    <w:tc>
      <w:tcPr>
        <w:tcW w:w="4680" w:type="dxa"/>
      </w:tcPr>
      <w:p><w:r><w:t>Cell 2</w:t></w:r></w:p>
    </w:tc>
  </w:tr>
</w:tbl>
```

**Table elements:**
- `<w:tblPr>` — table properties (style, width, borders, alignment)
- `<w:tblGrid>` — column width definitions
- `<w:tr>` — row (contains cells)
- `<w:trPr>` — row properties (height, header row repeat)
- `<w:tc>` — cell (contains paragraphs)
- `<w:tcPr>` — cell properties (width, borders, vertical alignment, merge)
- `<w:vMerge>` — vertical merge (`w:val="restart"` starts, empty continues)
- `<w:gridSpan>` — horizontal merge (span N columns)

### Hyperlink

```xml
<w:hyperlink r:id="rId7">
  <w:r>
    <w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>
    <w:t>Click here</w:t>
  </w:r>
</w:hyperlink>
```

The `r:id` references an entry in `word/_rels/document.xml.rels`:
```xml
<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/.../hyperlink" Target="https://example.com" TargetMode="External"/>
```

### Section Properties (`<w:sectPr>`)

Appears at the end of `<w:body>` (or inside a paragraph for section breaks):

```xml
<w:sectPr>
  <w:pgSz w:w="12240" w:h="15840"/>              <!-- letter: 8.5" x 11" -->
  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
  <w:headerReference w:type="default" r:id="rId8"/>
  <w:footerReference w:type="default" r:id="rId9"/>
  <w:cols w:space="720"/>
</w:sectPr>
```

### Bookmarks

```xml
<w:bookmarkStart w:id="0" w:name="contract_fee_location"/>
<w:r><w:t>text inside bookmark</w:t></w:r>
<w:bookmarkEnd w:id="0"/>
```

Used for cross-references and as DocuSign anchor targets.

## Relationships (`document.xml.rels`)

```xml
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type=".../styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type=".../numbering" Target="numbering.xml"/>
  <Relationship Id="rId3" Type=".../settings" Target="settings.xml"/>
  <Relationship Id="rId4" Type=".../image" Target="media/image1.png"/>
  <Relationship Id="rId5" Type=".../hyperlink" Target="https://example.com" TargetMode="External"/>
  <Relationship Id="rId6" Type=".../header" Target="header1.xml"/>
</Relationships>
```

Adding a new image or hyperlink requires both the element in document.xml AND a new Relationship entry.

## Content Types (`[Content_Types].xml`)

```xml
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>
```

Adding a new part (like numbering.xml if it doesn't exist) requires adding an Override entry here.

## Styles (`styles.xml`)

```xml
<w:style w:type="paragraph" w:styleId="ListBullet">
  <w:name w:val="List Bullet"/>
  <w:basedOn w:val="Normal"/>
  <w:pPr>
    <w:numPr><w:numId w:val="1"/></w:numPr>
    <w:ind w:left="720" w:hanging="360"/>
  </w:pPr>
</w:style>
```

Style types: `paragraph`, `character`, `table`, `numbering`. The `w:styleId` is the machine name; `<w:name>` is the display name.

## Edit Safety Rules

1. **Never remove `<w:pPr>`** from a paragraph — this loses indentation, numbering, spacing, style
2. **Never remove `<w:rPr>`** from a run — this loses bold, italic, font, size, color
3. **Preserve `xml:space="preserve"`** on `<w:t>` elements with spaces
4. **Match namespace declarations** — the root `<w:document>` must keep all `xmlns:` attributes
5. **Keep relationship IDs stable** — don't renumber rId values; add new ones at the end
6. **UTF-8 only** — no BOM, no UTF-16
