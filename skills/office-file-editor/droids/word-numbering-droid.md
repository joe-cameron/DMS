# Word Numbering Droid — Bullets, Numbers, List Definitions

## Purpose
Inspect, create, and fix numbering definitions in `word/numbering.xml`. Ensure list paragraphs reference valid definitions with correct indentation.

## When Dispatched
- Need to add bullet/number list support to a document that lacks numbering.xml
- Numbering.xml exists but has missing/broken level definitions
- Cross-referencing numId values between paragraphs and definitions
- Creating new list styles for document templates

## Tools Available
- `python office_edit.py format-list-audit <file>` — audit numbering definitions
- `python office_edit.py format-audit <file>` — audit paragraph numbering references
- `python office_edit.py inspect-deep <file>` — structural analysis including numbering
- Raw zip inspection for direct numbering.xml manipulation

## References to Load
- `references/numbering-and-lists-reference.md` (primary)
- `references/wordprocessingml-reference.md` (numbering section)

## Step-by-Step

### Auditing Numbering Health
1. Run `format-list-audit` — shows all abstract definitions, num instances, and usage
2. Check for orphaned references (paragraphs referencing undefined numIds)
3. Check for unused definitions (defined but never referenced)
4. Check each level's indent values match standard patterns

### Creating numbering.xml (if missing)
1. Verify `word/numbering.xml` does NOT exist in the archive
2. Create the XML with standard bullet definitions
3. Add to `[Content_Types].xml`
4. Add relationship to `word/_rels/document.xml.rels`
5. Write all three parts back atomically

### Standard Level Definitions
Level 0: `left=720, hanging=360, bullet=symbol`
Level 1: `left=1440, hanging=360, bullet=circle`
Level 2: `left=2160, hanging=360, bullet=square`

## Verification Criteria
- [ ] Every paragraph with `<w:numPr>` references a valid numId
- [ ] Every numId maps to a valid abstractNumId
- [ ] Every abstractNum has levels with correct indent values
- [ ] Document opens in Word — lists display correctly

## Error Reporting
```json
{
  "status": "error",
  "operation": "numbering-create",
  "file": "template.docx",
  "reason": "numbering.xml already exists — use numbering-fix instead",
  "suggestion": "Run format-list-audit to diagnose existing definitions"
}
```
