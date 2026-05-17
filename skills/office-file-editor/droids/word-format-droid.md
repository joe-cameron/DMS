# Word Format Droid — Paragraph + Run Formatting

## Purpose
Audit and fix paragraph formatting: indentation, spacing, styles, numbering references. Primary use: fixing the hanging-indent bug where block injection strips `<w:pPr>`.

## When Dispatched
- Bullet/numbered list text wraps incorrectly (second line at wrong indent)
- Paragraph formatting lost after document generation
- Need to audit template formatting before upload
- Need to verify formatting preservation after injection

## Tools Available
- `python office_edit.py format-audit <file>` — audit all paragraph indentation/numbering
- `python office_edit.py format-fix-indent <file>` — auto-fix missing indentation on list paragraphs
- `python office_edit.py format-list-audit <file>` — audit numbering.xml cross-references
- `python office_edit.py inspect-deep <file>` — full structural analysis

## References to Load
- `references/numbering-and-lists-reference.md`
- `references/formatting-preservation.md`
- `references/wordprocessingml-reference.md` (paragraph properties section)

## Step-by-Step

### Auditing Template Formatting
1. Run `format-audit` — shows all paragraphs with their properties
2. Run `format-list-audit` — shows numbering definitions and cross-references
3. Look for issues:
   - `LIST_NO_INDENT` — list paragraph has `<w:numPr>` but no `<w:ind>`
   - Undefined numId references
   - Mismatched indent values vs numbering definitions
4. Report findings with paragraph index, issue type, text preview

### Fixing Indentation
1. Run `format-fix-indent --dry-run` first — reports how many fixes would apply
2. If dry-run count matches expected, run without `--dry-run`
3. Verify with `format-audit` — issue count should be 0
4. Open in Word to visually confirm bullet/number alignment

### Post-Injection Verification
1. Run `format-audit` on the generated output document
2. Compare issue count to the template's baseline
3. Any new `LIST_NO_INDENT` issues = block injection stripped `<w:pPr>`

## Verification Criteria
- [ ] `format-audit` shows 0 issues after fix
- [ ] All list paragraphs have both `<w:numPr>` AND `<w:ind>`
- [ ] `<w:ind>` values match numbering.xml level definitions
- [ ] File opens in Word — bullet alignment visually correct
- [ ] Second-line text of wrapped bullets aligns with first-line text

## Error Reporting
```json
{
  "status": "error",
  "operation": "format-fix-indent",
  "file": "template.docx",
  "reason": "No numbering.xml — cannot determine correct indent values",
  "suggestion": "Manually add <w:ind w:left='720' w:hanging='360'/> for standard bullets"
}
```
