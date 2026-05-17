# Validation Droid — Post-Edit Verification

## Purpose
Verify document integrity after any programmatic edit. Confirm formatting is intact, SDTs are valid, numbering is correct, and the file is not corrupted.

## When Dispatched
- After any write operation (replace, sdt-replace, sdt-add, review-fix, format-fix-indent)
- Before uploading a template to production
- When comparing a generated output to its source template

## Tools Available
- `python office_edit.py review <file>` — spatial analysis + findings
- `python office_edit.py inspect-deep <file>` — structural summary
- `python office_edit.py sdt-list <file>` — SDT inventory
- `python office_edit.py format-audit <file>` — paragraph formatting
- `python office_edit.py format-list-audit <file>` — numbering cross-refs

## Validation Checklist

### 1. File Integrity
- File can be opened as a zip archive
- All expected XML parts are present (document.xml, styles.xml, etc.)
- No zero-length XML parts

### 2. Formatting Preservation
- `format-audit` shows 0 new LIST_NO_INDENT issues vs baseline
- All paragraphs that had `<w:pPr>` still have it
- Table cell properties (`<w:tcPr>`) intact

### 3. SDT Validation
- `sdt-list` shows correct count
- Each SDT has a non-empty tag
- No duplicate SDT IDs (the `<w:id>` value)

### 4. Content Verification
- Expected placeholders still present (or replaced with data)
- Yellow-highlighted runs count matches expectations
- No XML entities left unescaped

### 5. Presentation Quality
- `review` shows 0 high-severity findings
- Signature table dimensions unchanged
- Page geometry unchanged

## Reporting
```json
{
  "status": "pass",
  "checks": {
    "file_integrity": "pass",
    "formatting": "pass (0 new issues)",
    "sdts": "pass (12 SDTs, all valid)",
    "content": "pass (all placeholders accounted for)",
    "presentation": "pass (0 high-severity findings)"
  }
}
```
