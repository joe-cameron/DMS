# Numbering and Lists Reference — Bullets, Numbers, Indentation

How Word stores bullet lists, numbered lists, and multi-level lists in OOXML. This is the reference for fixing the hanging-indent bug where block injection strips paragraph properties and breaks list alignment.

## Architecture

List definitions live in TWO places:

1. **`word/numbering.xml`** — defines the abstract numbering (bullet character, number format, indentation) and concrete numbering instances
2. **`word/document.xml`** — each paragraph references a numbering instance via `<w:numPr>` inside `<w:pPr>`

## numbering.xml Structure

```xml
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">

  <!-- Abstract definition: what the list LOOKS like -->
  <w:abstractNum w:abstractNumId="0">
    <w:multiLevelType w:val="hybridMultilevel"/>

    <!-- Level 0 (top level) -->
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>                           <!-- start number -->
      <w:numFmt w:val="bullet"/>                     <!-- bullet | decimal | lowerLetter | upperLetter | lowerRoman | upperRoman -->
      <w:lvlText w:val="&#61623;"/>                  <!-- bullet character (Symbol font) -->
      <w:lvlJc w:val="left"/>                        <!-- justification of the number/bullet -->
      <w:pPr>
        <w:ind w:left="720" w:hanging="360"/>        <!-- THE CRITICAL INDENTATION -->
      </w:pPr>
      <w:rPr>
        <w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/>
      </w:rPr>
    </w:lvl>

    <!-- Level 1 (first sub-level) -->
    <w:lvl w:ilvl="1">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="o"/>                         <!-- open circle -->
      <w:lvlJc w:val="left"/>
      <w:pPr>
        <w:ind w:left="1440" w:hanging="360"/>       <!-- 1 inch total, 0.25" hanging -->
      </w:pPr>
      <w:rPr>
        <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:hint="default"/>
      </w:rPr>
    </w:lvl>

    <!-- Levels 2-8 follow the same pattern -->
  </w:abstractNum>

  <!-- Concrete instance: links to the abstract definition -->
  <w:num w:numId="1">
    <w:abstractNumId w:val="0"/>
    <!-- Optional level overrides -->
  </w:num>

</w:numbering>
```

## How Paragraphs Reference Lists

A paragraph becomes a list item by including `<w:numPr>` in its `<w:pPr>`:

```xml
<w:p>
  <w:pPr>
    <w:numPr>
      <w:ilvl w:val="0"/>        <!-- indentation level (0 = top) -->
      <w:numId w:val="1"/>       <!-- references <w:num w:numId="1"> -->
    </w:numPr>
    <w:ind w:left="720" w:hanging="360"/>  <!-- explicit indent (may override or duplicate lvl def) -->
  </w:pPr>
  <w:r><w:t>First bullet point</w:t></w:r>
</w:p>
```

**The `<w:numId>` + `<w:ilvl>` pair is what makes a paragraph a list item.** Without them, the paragraph is plain text even if it has the same indentation.

## The Hanging Indent Model

This is the core concept that breaks when block injection strips `<w:pPr>`:

```
                    w:hanging (360 twips = 0.25")
                    |<-------->|
    |               |          |
    |  Left margin  |  Bullet  |  Text starts here
    |               |          |  Continuation lines also start here
    |               |          |
    0              360        720
                              ^
                              w:left (720 twips = 0.5")
```

- **`w:left`** = total distance from page margin to where TEXT starts (720 twips = 0.5")
- **`w:hanging`** = how far the FIRST LINE (bullet/number) hangs LEFT of `w:left` (360 twips = 0.25")
- **Result**: bullet at 0.25", text at 0.5", continuation lines at 0.5"

### The Bug

When `ooxmlInject.js` does block injection (replacing an entire `<w:p>`) and the replacement paragraph omits `<w:ind>` or `<w:numPr>`:

```
BEFORE (correct):
    •  First line of bullet text that wraps to
       second line aligned with first line text

AFTER (broken):
    •  First line of bullet text that wraps to
second line snaps to left margin (0")
```

The second line loses its left indent because `w:left` defaults to 0 when `<w:ind>` is missing.

### The Fix

**Always preserve `<w:pPr>` when replacing a paragraph.** Extract the original paragraph's `<w:pPr>` block and inject it into the replacement:

```python
def preserve_ppr_on_replace(original_para_xml, new_text):
    """Replace paragraph text while keeping all paragraph properties."""
    # Extract original pPr
    ppr_match = re.search(r'<w:pPr>(.*?)</w:pPr>', original_para_xml, re.DOTALL)
    ppr = f'<w:pPr>{ppr_match.group(1)}</w:pPr>' if ppr_match else ''

    # Extract rPr from first run for text formatting
    rpr_match = re.search(r'<w:r>\s*(<w:rPr>.*?</w:rPr>)', original_para_xml, re.DOTALL)
    rpr = rpr_match.group(1) if rpr_match else ''
    # Strip highlight from rPr
    rpr = re.sub(r'<w:highlight[^/]*/>', '', rpr)

    return f'<w:p>{ppr}<w:r>{rpr}<w:t xml:space="preserve">{new_text}</w:t></w:r></w:p>'
```

## Common Indentation Patterns

| List Type | Level | w:left | w:hanging | Bullet/Number Position | Text Position |
|-----------|-------|--------|-----------|----------------------|---------------|
| Bullet L0 | 0 | 720 | 360 | 0.25" | 0.5" |
| Bullet L1 | 1 | 1440 | 360 | 0.75" | 1.0" |
| Bullet L2 | 2 | 2160 | 360 | 1.25" | 1.5" |
| Number L0 | 0 | 720 | 360 | 0.25" | 0.5" |
| Legal Indent | 0 | 1440 | 720 | 0.5" | 1.0" |

## Auditing List Formatting

To check if a document has broken list indentation:

```python
def audit_list_formatting(xml_content, numbering_xml):
    """Check every list paragraph has matching indentation from its numbering definition."""
    issues = []

    # Parse numbering definitions
    num_defs = {}  # numId -> {ilvl -> {left, hanging}}
    for num_m in re.finditer(r'<w:num w:numId="(\d+)">(.*?)</w:num>', numbering_xml, re.DOTALL):
        num_id = num_m.group(1)
        abs_m = re.search(r'<w:abstractNumId w:val="(\d+)"', num_m.group(2))
        if abs_m:
            num_defs[num_id] = abs_m.group(1)

    # Check each paragraph
    for p_m in re.finditer(r'<w:p[^>]*>(.*?)</w:p>', xml_content, re.DOTALL):
        ppr = p_m.group(1)
        num_m = re.search(r'<w:numId w:val="(\d+)"', ppr)
        if not num_m:
            continue  # not a list paragraph

        ind_m = re.search(r'<w:ind\s+([^/]*)/>', ppr)
        if not ind_m:
            issues.append({
                'position': p_m.start(),
                'issue': 'List paragraph missing <w:ind> — will have no indentation',
                'numId': num_m.group(1),
            })

    return issues
```

## Creating a New Numbering Definition

If `numbering.xml` doesn't exist or you need a new list style:

1. Add an `<w:abstractNum>` with unique `w:abstractNumId`
2. Add a `<w:num>` with unique `w:numId` referencing the abstract
3. If `numbering.xml` doesn't exist, create it AND add to `[Content_Types].xml` AND add a relationship in `word/_rels/document.xml.rels`

```xml
<!-- Add to [Content_Types].xml -->
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>

<!-- Add to word/_rels/document.xml.rels -->
<Relationship Id="rIdN" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
```

## Standard Bullet Characters

| Character | Unicode | Font | Description |
|-----------|---------|------|-------------|
| &#61623; | U+F0B7 | Symbol | Filled circle (default L0) |
| o | U+006F | Courier New | Open circle (default L1) |
| &#61607; | U+F0A7 | Wingdings | Filled square (default L2) |
| – | U+2013 | (any) | En dash |
| &#8226; | U+2022 | (any) | Standard bullet |

## Restart vs. Continue Numbering

```xml
<!-- Restart numbering (new list) -->
<w:num w:numId="2">
  <w:abstractNumId w:val="0"/>
  <w:lvlOverride w:ilvl="0">
    <w:startOverride w:val="1"/>
  </w:lvlOverride>
</w:num>

<!-- Continue numbering (same list, different instance) -->
<w:num w:numId="3">
  <w:abstractNumId w:val="0"/>
  <!-- No override = continues from last instance of same abstractNum -->
</w:num>
```

## DCFG Template Implications

1. **Block injection MUST preserve `<w:pPr>`** — especially `<w:numPr>` and `<w:ind>`
2. **Location table builder** should not strip `<w:pPr>` from surrounding list items
3. **Amendment builder** should preserve list formatting in scope descriptions
4. **Formatting audit** before upload — every list paragraph must have matching `<w:ind>` and `<w:numPr>`
