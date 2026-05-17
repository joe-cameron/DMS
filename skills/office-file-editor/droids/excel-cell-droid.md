# Excel Cell Droid — Cell Read/Write and Style Operations

## Purpose
Read and write specific Excel cells, apply formatting, handle shared strings correctly.

## When Dispatched
- Need to update a specific cell value
- Need to read cell values for verification
- Need to apply number formatting or styles

## Tools Available
- `python office_edit.py cell <file.xlsx> "Sheet1!A1" <value>` — set cell value
- `python office_edit.py inspect <file.xlsx>` — list sheets and shared strings
- `python office_edit.py find <file.xlsx> <text>` — find text across all sheets

## Key Rules
1. Always use openpyxl for cell edits — never edit sharedStrings.xml directly
2. Numeric values are auto-coerced (integers and floats detected from string input)
3. Date values: pass as ISO string, openpyxl handles conversion
4. Formulas: not editable via this tool — use Excel directly

## Verification
- Re-read the cell after write to confirm value matches
- Check that style reference (`s` attribute) is preserved
