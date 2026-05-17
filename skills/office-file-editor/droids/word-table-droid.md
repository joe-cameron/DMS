# Word Table Droid — Table Structure and Cell Operations

## Purpose
Inspect, modify, and validate table structures in .docx files. Handle signature tables, data tables, and location list tables.

## When Dispatched
- Signature block table needs column equalization
- Location list table needs row insertion
- Table borders need adding/removing
- Cell content needs replacement while preserving formatting

## Tools Available
- `python office_edit.py review <file>` — identifies signature tables and checks dimensions
- `python office_edit.py inspect-deep <file>` — shows table count
- Raw zip inspection for direct XML manipulation of `<w:tbl>` elements

## Common Operations

### Equalize Signature Table Columns
Find the `<w:tblGrid>` inside the signature table, set both `<w:gridCol>` widths to equal values (text_width / 2). Also update each `<w:tcW>` in every row.

### Remove Table Borders
Replace `<w:tblBorders>` content with `<w:top w:val="none"/>` etc. for all border positions.

### Insert Table Row
Clone an existing `<w:tr>`, update cell content, insert at the correct position within `<w:tbl>`.

## Verification Criteria
- [ ] Column widths sum to text body width
- [ ] All cells have `<w:tcPr>` with correct width
- [ ] Row count matches expectations
- [ ] File opens in Word — table renders correctly
