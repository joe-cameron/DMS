# Formatting Preservation Reference

Rules for preserving document formatting during every type of edit. The #1 cause of template corruption in DCFG is losing formatting properties during injection.

## The Three Levels of Formatting

```
Document
  └── Paragraph properties (<w:pPr>)     — indentation, numbering, spacing, alignment, style
        └── Run properties (<w:rPr>)      — bold, italic, font, size, color, highlight
              └── Text (<w:t>)            — the actual content
```

Each level inherits from the one above. Losing any level's properties cascades to everything below.

## Rule 1: Scalar Injection — Preserve Run Properties

**Scenario:** Replacing placeholder text inside a single run (e.g., yellow-highlighted "Contractor Name" → "Acme Corp").

**What to preserve:** `<w:rPr>` from the matched run, MINUS the highlight.

```xml
<!-- BEFORE -->
<w:r>
  <w:rPr>
    <w:b/>
    <w:sz w:val="22"/>
    <w:highlight w:val="yellow"/>
  </w:rPr>
  <w:t>Contractor Name</w:t>
</w:r>

<!-- AFTER (correct) -->
<w:r>
  <w:rPr>
    <w:b/>
    <w:sz w:val="22"/>
    <!-- highlight REMOVED — injected text should not be highlighted -->
  </w:rPr>
  <w:t>Acme Corp</w:t>
</w:r>
```

**Current `ooxmlInject.js` behavior:** CORRECT — `injectScalarFields` preserves `<w:rPr>` and strips highlight.

### Implementation Pattern

```python
def strip_highlight(rpr_xml):
    """Remove highlight from rPr, keeping everything else."""
    return re.sub(r'<w:highlight[^/]*/>', '', rpr_xml)

def inject_scalar(run_xml, new_text):
    """Replace run text, preserve formatting minus highlight."""
    # Extract rPr
    rpr_m = re.search(r'(<w:rPr>.*?</w:rPr>)', run_xml, re.DOTALL)
    rpr = strip_highlight(rpr_m.group(1)) if rpr_m else ''
    return f'<w:r>{rpr}<w:t xml:space="preserve">{new_text}</w:t></w:r>'
```

## Rule 2: Block Injection — Preserve Paragraph Properties

**Scenario:** Replacing an entire paragraph (e.g., scope description, amendment text block).

**What to preserve:** `<w:pPr>` from the original paragraph, including ALL of:
- `<w:pStyle>` — paragraph style
- `<w:numPr>` — list numbering
- `<w:ind>` — indentation
- `<w:spacing>` — before/after/line spacing
- `<w:jc>` — justification
- `<w:keepNext/>`, `<w:keepLines/>` — pagination control
- `<w:tabs>` — tab stops
- `<w:rPr>` inside pPr — default run formatting for the paragraph mark

**Current `ooxmlInject.js` behavior:** BROKEN — `injectBlockField` replaces the entire `<w:p>` without extracting/preserving `<w:pPr>`. This is the root cause of the hanging indent bug.

### Implementation Pattern

```python
def inject_block(original_para_xml, replacement_text, keep_rpr=True):
    """Replace paragraph content while preserving all paragraph properties."""
    # 1. Extract original pPr (MUST keep)
    ppr_m = re.search(r'(<w:pPr>.*?</w:pPr>)', original_para_xml, re.DOTALL)
    ppr = ppr_m.group(1) if ppr_m else ''

    # 2. Extract rPr from first run (for text formatting)
    rpr = ''
    if keep_rpr:
        rpr_m = re.search(r'<w:r>\s*(<w:rPr>.*?</w:rPr>)', original_para_xml, re.DOTALL)
        rpr = strip_highlight(rpr_m.group(1)) if rpr_m else ''

    # 3. Build replacement paragraph
    return f'<w:p>{ppr}<w:r>{rpr}<w:t xml:space="preserve">{replacement_text}</w:t></w:r></w:p>'
```

### Multi-Paragraph Block Injection

When replacing one paragraph with multiple paragraphs (e.g., multi-line scope text):

```python
def inject_multi_para_block(original_para_xml, lines):
    """Replace one paragraph with multiple, all inheriting original formatting."""
    ppr_m = re.search(r'(<w:pPr>.*?</w:pPr>)', original_para_xml, re.DOTALL)
    ppr = ppr_m.group(1) if ppr_m else ''

    rpr_m = re.search(r'<w:r>\s*(<w:rPr>.*?</w:rPr>)', original_para_xml, re.DOTALL)
    rpr = strip_highlight(rpr_m.group(1)) if rpr_m else ''

    paras = []
    for line in lines:
        paras.append(f'<w:p>{ppr}<w:r>{rpr}<w:t xml:space="preserve">{line}</w:t></w:r></w:p>')
    return ''.join(paras)
```

## Rule 3: SDT Injection — Preserve SDT Properties

**Scenario:** Replacing content inside a content control.

**What to preserve:** Everything in `<w:sdtPr>` — tag, alias, type, lock, id. Only `<w:sdtContent>` children change.

```python
def inject_sdt(sdt_xml, new_text):
    """Replace SDT content, preserve all SDT properties."""
    # Keep everything before </w:sdtPr> and after <w:sdtContent>
    # Replace only the content between <w:sdtContent> and </w:sdtContent>

    # Also remove <w:showingPlcHdr/> since we're replacing the placeholder
    sdt_xml = sdt_xml.replace('<w:showingPlcHdr/>', '')

    return re.sub(
        r'(<w:sdtContent>).*?(</w:sdtContent>)',
        lambda m: m.group(1) + f'<w:r><w:t xml:space="preserve">{new_text}</w:t></w:r>' + m.group(2),
        sdt_xml,
        flags=re.DOTALL
    )
```

## Rule 4: Table Cell Injection — Preserve Cell Properties

**Scenario:** Injecting into table cells (location list, amendment changes table).

**What to preserve:**
- `<w:tcPr>` — cell width, borders, vertical alignment, merge
- `<w:pPr>` inside the cell — paragraph formatting
- `<w:trPr>` — row height, header repeat

```python
def inject_table_cell(cell_xml, new_text):
    """Replace cell text content, preserve cell and paragraph properties."""
    tcpr_m = re.search(r'(<w:tcPr>.*?</w:tcPr>)', cell_xml, re.DOTALL)
    tcpr = tcpr_m.group(1) if tcpr_m else ''

    ppr_m = re.search(r'(<w:pPr>.*?</w:pPr>)', cell_xml, re.DOTALL)
    ppr = ppr_m.group(1) if ppr_m else ''

    return f'<w:tc>{tcpr}<w:p>{ppr}<w:r><w:t xml:space="preserve">{new_text}</w:t></w:r></w:p></w:tc>'
```

## Rule 5: Never Strip These Elements

The following elements must NEVER be removed during any injection operation:

| Element | Why |
|---------|-----|
| `<w:pStyle>` | Loses paragraph style (Normal, Heading, ListBullet) |
| `<w:numPr>` | Loses bullet/number formatting |
| `<w:ind>` | Loses indentation — causes hanging indent bug |
| `<w:spacing>` | Loses before/after paragraph spacing |
| `<w:jc>` | Loses text alignment (center, right, justified) |
| `<w:rFonts>` | Loses font family |
| `<w:sz>` / `<w:szCs>` | Loses font size |
| `<w:b/>` / `<w:i/>` | Loses bold/italic |
| `<w:tblPr>` | Loses table formatting |
| `<w:tcPr>` | Loses cell formatting |

## Rule 6: Highlight Is the Only Property to Strip

During injection, the ONLY formatting property that should be removed is `<w:highlight>`. This is the visual marker that identifies placeholders. After injection:

- Highlight = REMOVED (data fields shouldn't be highlighted)
- Everything else = PRESERVED

```python
def clean_rpr_for_injection(rpr_xml):
    """Clean run properties for injection — strip only highlight."""
    if not rpr_xml:
        return ''
    cleaned = re.sub(r'<w:highlight[^/]*/>', '', rpr_xml)
    # If rPr is now empty, don't emit it
    if re.match(r'^\s*<w:rPr>\s*</w:rPr>\s*$', cleaned):
        return ''
    return cleaned
```

## Rule 7: XML Entity Escaping

Injected text MUST be XML-escaped:

| Character | Escape | Example |
|-----------|--------|---------|
| `&` | `&amp;` | "AT&T" → "AT&amp;T" |
| `<` | `&lt;` | Not common in contract text |
| `>` | `&gt;` | Not common in contract text |
| `"` | `&quot;` | Only inside attribute values |

```python
def xml_escape(text):
    """Escape text for safe XML injection."""
    return (text
        .replace('&', '&amp;')
        .replace('<', '&lt;')
        .replace('>', '&gt;'))
```

## Verification Checklist

After any injection, verify:

1. [ ] Every `<w:p>` that had `<w:pPr>` still has it
2. [ ] Every list paragraph still has `<w:numPr>` and matching `<w:ind>`
3. [ ] No `<w:highlight>` remains on injected text
4. [ ] All other `<w:rPr>` properties preserved (bold, font, size)
5. [ ] Table cells still have `<w:tcPr>` with correct widths
6. [ ] File opens in Word without corruption warnings
7. [ ] Bullet alignment: second-line text aligns with first-line text (not with bullet)
