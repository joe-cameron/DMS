# Word SDT Droid — Content Control Operations

## Purpose
Find, add, replace, and remove Structured Document Tags (content controls) in .docx files.

## When Dispatched
- User asks to add a new field/placeholder to a Word template
- User asks to find or list content controls
- User asks to replace placeholder content in a content control
- Template migration from yellow-highlight placeholders to SDTs

## Tools Available
- `python office_edit.py sdt-list <file>` — list all SDTs
- `python office_edit.py sdt-find <file> <tag>` — find SDT by tag
- `python office_edit.py sdt-replace <file> <tag> <new-text>` — replace SDT content
- `python office_edit.py sdt-add <file> <after-text> <tag> <placeholder>` — add inline SDT
- `python office_edit.py inspect-deep <file>` — full structural analysis

## References to Load
- `references/content-controls-reference.md`
- `references/wordprocessingml-reference.md` (SDT section)

## Step-by-Step

### Adding a New SDT
1. Run `inspect-deep` to understand document structure
2. Run `sdt-list` to see existing SDTs (avoid duplicate tags)
3. Identify the anchor text where the new SDT should go
4. Run `sdt-add <file> <after-text> <tag> <placeholder> --dry-run` first
5. If dry-run OK, run without `--dry-run`
6. Verify with `sdt-find <file> <tag>`
7. Report: tag name, position, verification result

### Replacing SDT Content
1. Run `sdt-find <file> <tag>` to confirm the tag exists
2. Run `sdt-replace <file> <tag> <new-text> --dry-run`
3. If dry-run OK, run without `--dry-run`
4. Verify with `sdt-find` — content should show new text
5. Report: old content, new content, verification result

### Listing/Finding SDTs
1. Run `sdt-list` or `sdt-find`
2. Report: tag, alias, type, content preview, which XML part

## Verification Criteria
- [ ] SDT appears in `sdt-list` output with correct tag
- [ ] SDT content matches expected text
- [ ] File opens in Word without corruption warnings
- [ ] No duplicate SDT tags (unless intentional for multi-location fields)
- [ ] Surrounding text/formatting is undisturbed

## Error Reporting
```json
{
  "status": "error",
  "operation": "sdt-add",
  "file": "template.docx",
  "reason": "Anchor text not found in document.xml",
  "attempted": "after_text='Contract Fee Amount'",
  "suggestion": "Check if text is split across runs; try a shorter anchor"
}
```
