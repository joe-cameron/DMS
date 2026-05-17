# Content Controls (SDT) Reference

Structured Document Tags (`<w:sdt>`) are Word's mechanism for labeled, typed, reusable placeholders. They're the preferred way to mark document fields for programmatic replacement because they carry metadata (tag, alias, type) that survives formatting changes.

## Why SDTs Over Yellow-Highlight Placeholders

| Feature | Yellow-highlight runs | SDTs |
|---------|----------------------|------|
| Machine-readable tag | No — match by text content | Yes — `<w:tag w:val="..."/>` |
| Survives reformatting | Fragile — highlight can be lost | Yes — tag is in `<w:sdtPr>`, not in content |
| Typed (text, date, dropdown) | No | Yes |
| Visible boundary in Word UI | No | Yes (blue border in design mode) |
| Run-split immune | No — text may split across runs | Yes — content is inside `<w:sdtContent>` |

## SDT Structure

### Block-level SDT (paragraph level)

```xml
<w:sdt>
  <w:sdtPr>
    <w:tag w:val="contract_fee"/>
    <w:alias w:val="Contract Fee"/>
    <w:lock w:val="sdtLocked"/>
    <w:text/>                          <!-- plain text type -->
    <w:showingPlcHdr/>                 <!-- currently showing placeholder -->
    <w:id w:val="123456789"/>
    <w:rPr>                            <!-- default formatting for placeholder -->
      <w:sz w:val="24"/>
      <w:highlight w:val="yellow"/>
    </w:rPr>
  </w:sdtPr>
  <w:sdtEndPr/>
  <w:sdtContent>
    <w:p>
      <w:pPr>
        <w:rPr><w:highlight w:val="yellow"/></w:rPr>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:rStyle w:val="PlaceholderText"/>
          <w:highlight w:val="yellow"/>
        </w:rPr>
        <w:t>Contract Fee</w:t>
      </w:r>
    </w:p>
  </w:sdtContent>
</w:sdt>
```

### Inline SDT (run level)

```xml
<w:p>
  <w:r><w:t xml:space="preserve">The fee is </w:t></w:r>
  <w:sdt>
    <w:sdtPr>
      <w:tag w:val="contract_fee"/>
      <w:alias w:val="Contract Fee"/>
      <w:text/>
    </w:sdtPr>
    <w:sdtContent>
      <w:r>
        <w:rPr><w:highlight w:val="yellow"/></w:rPr>
        <w:t>Contract Fee</w:t>
      </w:r>
    </w:sdtContent>
  </w:sdt>
  <w:r><w:t xml:space="preserve"> per annum.</w:t></w:r>
</w:p>
```

Inline SDTs sit inside `<w:p>` as siblings to `<w:r>` elements.

## SDT Properties (`<w:sdtPr>`)

| Element | Purpose | Notes |
|---------|---------|-------|
| `<w:tag>` | Machine-readable identifier | **Primary lookup key.** Maps to `dcfg_source_text` in DCFG. |
| `<w:alias>` | Human-readable label | Shown in Word's Properties panel |
| `<w:id>` | Unique numeric ID | Auto-assigned; must be unique within document |
| `<w:text/>` | Plain text type | Content is raw text |
| `<w:date>` | Date picker type | Includes `w:fullDate`, `w:dateFormat`, `w:lid` |
| `<w:comboBox>` | Dropdown type | Contains `<w:listItem>` children |
| `<w:dropDownList>` | Strict dropdown | Same as comboBox but no free-text |
| `<w:richText/>` | Rich text type | Content can contain formatted paragraphs |
| `<w:picture/>` | Picture type | Content is a drawing |
| `<w:showingPlcHdr/>` | Placeholder visible | Present = showing gray placeholder text |
| `<w:lock>` | Lock mode | `sdtLocked` (can't delete), `contentLocked` (can't edit), `sdtContentLocked` (both) |
| `<w:rPr>` | Default run properties | Applied to placeholder text |

## SDT Types for DCFG

For contract document generation, use **plain text** SDTs (`<w:text/>`). They're the simplest to inject into and don't carry type-specific validation that could interfere.

## Operations

### Find SDTs by Tag

```python
import re

def find_sdts(xml_content):
    """Find all SDTs in document XML. Returns list of {tag, alias, content, start_pos, end_pos}."""
    results = []
    # Match the full <w:sdt>...</w:sdt> block
    for m in re.finditer(r'<w:sdt>(.*?)</w:sdt>', xml_content, re.DOTALL):
        block = m.group(1)
        tag_m = re.search(r'<w:tag w:val="([^"]*)"', block)
        alias_m = re.search(r'<w:alias w:val="([^"]*)"', block)
        # Extract text content from <w:t> elements inside <w:sdtContent>
        content_m = re.search(r'<w:sdtContent>(.*?)</w:sdtContent>', block, re.DOTALL)
        text = ''
        if content_m:
            text = ''.join(re.findall(r'<w:t[^>]*>([^<]*)</w:t>', content_m.group(1)))
        results.append({
            'tag': tag_m.group(1) if tag_m else None,
            'alias': alias_m.group(1) if alias_m else None,
            'content': text,
            'start': m.start(),
            'end': m.end(),
        })
    return results

def find_sdt_by_tag(xml_content, tag):
    """Find a specific SDT by its tag value."""
    return [s for s in find_sdts(xml_content) if s['tag'] == tag]
```

### Replace SDT Content

**Rule:** Replace ONLY the content inside `<w:sdtContent>`. NEVER modify `<w:sdtPr>`.

```python
def replace_sdt_content(xml_content, tag, new_text):
    """Replace the text content of an SDT while preserving all properties and formatting."""
    pattern = (
        r'(<w:sdt>\s*<w:sdtPr>(?:(?!<w:sdt>).)*?'
        r'<w:tag w:val="' + re.escape(tag) + r'"[^/]*/>'
        r'(?:(?!<w:sdt>).)*?</w:sdtPr>'
        r'(?:\s*<w:sdtEndPr[^/]*/>\s*)?'
        r'<w:sdtContent>)'
        r'(.*?)'
        r'(</w:sdtContent>\s*</w:sdt>)'
    )

    def replacer(m):
        prefix = m.group(1)
        old_content = m.group(2)
        suffix = m.group(3)

        # Extract rPr from the first run in old content to preserve formatting
        rpr_m = re.search(r'(<w:rPr>.*?</w:rPr>)', old_content, re.DOTALL)
        rpr = rpr_m.group(1) if rpr_m else ''

        # Strip highlight from preserved rPr (injected text shouldn't be highlighted)
        rpr_clean = re.sub(r'<w:highlight[^/]*/>', '', rpr)
        # Remove showingPlcHdr — we're replacing the placeholder
        prefix_clean = prefix.replace('<w:showingPlcHdr/>', '')

        # Build new content — single paragraph with single run
        new_content = (
            f'<w:p><w:r>'
            f'{rpr_clean}'
            f'<w:t xml:space="preserve">{new_text}</w:t>'
            f'</w:r></w:p>'
        )
        return prefix_clean + new_content + suffix

    return re.sub(pattern, replacer, xml_content, flags=re.DOTALL)
```

### Add a New SDT

Insert an inline SDT after a text match within a paragraph:

```python
def build_inline_sdt(tag, alias, placeholder_text):
    """Build an inline SDT XML fragment."""
    return (
        f'<w:sdt>'
        f'<w:sdtPr>'
        f'<w:tag w:val="{tag}"/>'
        f'<w:alias w:val="{alias}"/>'
        f'<w:text/>'
        f'<w:showingPlcHdr/>'
        f'</w:sdtPr>'
        f'<w:sdtEndPr/>'
        f'<w:sdtContent>'
        f'<w:r>'
        f'<w:rPr><w:rStyle w:val="PlaceholderText"/></w:rPr>'
        f'<w:t>{placeholder_text}</w:t>'
        f'</w:r>'
        f'</w:sdtContent>'
        f'</w:sdt>'
    )
```

### Remove an SDT (Keep Content)

To "unwrap" an SDT — remove the SDT wrapper but keep the content as regular paragraphs/runs:

```python
def unwrap_sdt(xml_content, tag):
    """Remove SDT wrapper, keeping content as regular document elements."""
    pattern = (
        r'<w:sdt>\s*<w:sdtPr>(?:(?!<w:sdt>).)*?'
        r'<w:tag w:val="' + re.escape(tag) + r'"[^/]*/>'
        r'(?:(?!<w:sdt>).)*?</w:sdtPr>'
        r'(?:\s*<w:sdtEndPr[^/]*/>\s*)?'
        r'<w:sdtContent>(.*?)</w:sdtContent>'
        r'\s*</w:sdt>'
    )
    return re.sub(pattern, r'\1', xml_content, flags=re.DOTALL)
```

## DCFG Integration

### How ooxmlInject.js Uses SDTs

Currently, `ooxmlInject.js` does NOT use SDTs — it uses yellow-highlighted text runs. The plan is to add SDT awareness so that:

1. **Field mapping** uses `<w:tag>` values instead of text content matching
2. **Replacement** uses `replace_sdt_content` which is immune to run-splitting
3. **New fields** can be added via `sdt-add` without opening Word

### Migration Path

Templates can support BOTH yellow-highlight runs AND SDTs during transition:
1. `ooxmlInject.js` first tries SDT tag match
2. Falls back to yellow-highlight text match
3. Over time, templates are converted to SDT-only

### Tag Naming Convention

SDT tags should match the `dcfg_source_text` values in `dcfg_template_fields`:
- `contract_fee` → maps to "Contract Fee" source text
- `contractor_legal_name` → maps to "Contractor Name" source text
- Use snake_case, no spaces, no special characters

## Edge Cases

1. **Nested SDTs** — not supported by Word; don't attempt
2. **SDT inside table cell** — works fine; the SDT is inside the cell's `<w:p>`
3. **Multiple SDTs with same tag** — allowed; operations apply to all matches
4. **SDT with no content** — valid but Word may show placeholder text; always include at least one `<w:r><w:t/></w:r>`
5. **SDT crossing paragraph boundaries** — only block-level SDTs can contain multiple `<w:p>` elements; inline SDTs cannot
