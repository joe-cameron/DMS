# Run-splitting — the most common docx/pptx edit failure

Word and PowerPoint store text inside **runs** (`<w:r>` for Word, `<a:r>` for PowerPoint). A run is a span of text with consistent formatting. The moment formatting changes — bold, italic, color, font, font size, language, hyperlink — Word splits the text into a new run.

This is the #1 reason naive find/replace on `document.xml` fails silently.

## The setup

You have a paragraph that visually reads:

> Currently **Director of AI Integration** at DCFG.

In the XML, that might be:

```xml
<w:p>
  <w:r><w:t xml:space="preserve">Currently </w:t></w:r>
  <w:r>
    <w:rPr><w:b/></w:rPr>
    <w:t>Director of AI Integration</w:t>
  </w:r>
  <w:r><w:t xml:space="preserve"> at DCFG.</w:t></w:r>
</w:p>
```

Three runs. The bold formatting around "Director of AI Integration" forced a split.

## The failure mode

You want to replace `"AI Integration"` with `"AI Strategy"`. Naive approach:

```python
content = z.read('word/document.xml').decode('utf-8')
content = content.replace('AI Integration', 'AI Strategy')  # works — text is in one run
```

But if you want to replace `"Currently Director of AI"` (a phrase that crosses the bold boundary):

```python
content.replace('Currently Director of AI', 'Recently Director of AI')  # FAILS SILENTLY
```

The string `"Currently Director of AI"` doesn't exist anywhere in the XML — it spans two runs. Your replace returns the file unchanged, but you'd think it succeeded if you didn't verify.

Worse: if you tried to be clever and used a regex with `.*` to span runs, you'd risk capturing XML tags as part of the match and corrupt the file when you write back.

## The detection

Before any edit, check whether the target string lives inside a single `<w:t>`:

```python
import re
def is_split_in_runs(xml_content: str, pattern: str) -> bool:
    text_runs = re.findall(r'<(?:w|a):t[^>]*>([^<]*)</(?:w|a):t>', xml_content)
    if any(pattern in run for run in text_runs):
        return False  # at least one run contains the full pattern
    stripped = re.sub(r'<[^>]+>', '', xml_content)
    return pattern in stripped  # pattern exists in document text but not in any single run
```

If `is_split_in_runs(...)` returns True, raw replace will fail. Use `python-docx` instead.

## The fix — python-docx run reconstruction

`python-docx` exposes paragraph text as the concatenation of all run text. You can do find/replace on the paragraph string, then rewrite the runs:

```python
def replace_in_paragraph(para, old: str, new: str) -> int:
    if old not in para.text:
        return 0
    runs = list(para.runs)
    run_texts = [r.text for r in runs]
    full = ''.join(run_texts)
    # Find the run indices spanning the match
    start = full.index(old)
    end = start + len(old)
    pos = 0
    affected = []
    for i, t in enumerate(run_texts):
        rstart = pos
        rend = pos + len(t)
        if rend > start and rstart < end:
            affected.append((i, rstart, rend))
        pos = rend
    first_idx, first_rstart, _ = affected[0]
    last_idx, _, last_rend = affected[-1]
    # Text before the match in the first affected run
    before = run_texts[first_idx][:start - first_rstart]
    # Text after the match in the last affected run
    after = run_texts[last_idx][end - last_rend + len(run_texts[last_idx]):]
    # Apply
    if first_idx == last_idx:
        runs[first_idx].text = before + new + after
    else:
        runs[first_idx].text = before + new
        for j in range(first_idx + 1, last_idx):
            runs[j].text = ''
        runs[last_idx].text = after
    return 1
```

## Formatting consequence

When the matched span crosses runs with different formatting, the replacement text inherits the formatting of the **first** run in the span. The other runs in the span are emptied.

Example: replacing `"Currently Director of AI Integration"` (which spans a non-bold run + a bold run) puts the new text into the first run (non-bold). The bold formatting on the second run is lost for that span — the rest of the bold run is preserved as `after`.

This is acceptable for most fact corrections (date updates, name changes, role corrections). It's NOT acceptable when you specifically want to preserve mid-string formatting — but that's a much rarer case, and there's no general solution that doesn't risk worse problems.

## When the cost of run-splitting is too high

Some scenarios are not worth automating:

- **Replacements inside hyperlinks.** Hyperlinks have their own structure (`<w:hyperlink>`) that wraps runs. Editing the visible text of a hyperlink is one thing; changing the URL needs `_rels/document.xml.rels` updates too.
- **Replacements inside fields.** Word can have computed fields (auto-numbers, table-of-contents entries). Editing the visible text of a field doesn't update the underlying field code.
- **Replacements that need to insert new formatting.** "Make this bold and add it to the paragraph" requires creating a new run with `<w:rPr>` properties — that's a different operation entirely. Don't conflate it with find/replace.

For these cases: open in Word and edit there, or accept the limitations.

## Test cases worth running before trusting any new edit script

1. **Plain text in a single run** — should work via raw replace.
2. **Text spanning a bold/non-bold boundary** — should detect split, use python-docx fallback.
3. **Text spanning three runs (bold-italic, italic, plain)** — same as above; verify the affected-runs list correctly identifies all three.
4. **Text appearing twice in the document, once split, once not** — should handle both occurrences.
5. **Text appearing in a header/footer, not in main body** — should detect via `text_parts()` enumeration.
6. **Text in a table cell** — python-docx iteration over `doc.tables` covers this.
7. **Text in a comment or footnote** — currently NOT covered by python-docx fallback (those parts have separate XML); raw replace works for these.

The `office_edit.py` script handles cases 1-6. Case 7 — comment/footnote edits with split runs — is a known gap. Document it in `learnings.md` if you hit it.
