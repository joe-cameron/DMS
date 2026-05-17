---
name: office-file-editor
description: |
  Surgically edit and review Microsoft Office files (.docx, .xlsx, .pptx) via OOXML.
  Two primary capabilities:
  1. REVIEW — Analyze document presentation quality on a 2D spatial plane.
     Identify anomalies (misaligned wraps, unbalanced signatures, inconsistent spacing).
     Suggest specific numbered fixes. Apply surgically after approval.
  2. EDIT — Find/replace text, manage content controls (SDTs), fix indentation,
     update cells, restore from backup. All backup-first, verify-last.
  Trigger phrases: "review this document", "fix the template", "add a content control",
  "update docx", "edit xlsx", "what's wrong with this template", "check formatting",
  "set cell X to Y", "find text in docx".
---

# Office File Editor

## Philosophy

**We cannot see documents, so we experience them as a 2D spatial plane.** Every paragraph, table cell, and run has XY coordinates on the page. Text has visual attributes (font size, bold, alignment, indentation) that determine its spatial presentation. The skill builds this spatial model, detects anomalies against business document conventions, suggests specific fixes, and applies them surgically after human approval.

OOXML is just zip + XML. Office files break loudly when zip metadata or structural integrity is wrong. All editing is backup-first, scope-narrow, verify-last.

## Hard Rules

1. **Backup-first, always.** Every write produces `<file>.bak.<timestamp>` before the edit.
2. **Refuse if target not found.** No silent no-ops.
3. **Detect run-split text.** Word splits text across runs whenever formatting changes. Always check first; fall back to python-docx if split. See `references/run-splitting.md`.
4. **Verify post-edit.** Re-open and confirm counts/state changed as expected.
5. **Suggest before fixing.** Review produces numbered findings. User approves specific IDs. Fixes are surgical — only the approved items change.
6. **Preserve formatting.** Never strip `<w:pPr>`, `<w:rPr>`, `<w:tcPr>`. Only strip `<w:highlight>` during injection. See `references/formatting-preservation.md`.
7. **Section-aware.** Section breaks change page geometry mid-document. Always track which section an element belongs to.

## Workflow

### Step 0 — Read learnings
Read `learnings.md` for past failure patterns.

### Step 1 — Review the document
```
python office_edit.py review <file>
```

This builds a 2D spatial model and outputs:
- **Document geometry**: page size, margins, text area width
- **Spatial layout**: every paragraph with XY coordinates, section classification, wrap predictions
- **Numbered findings**: anomalies sorted by severity (high/medium/low)

Each finding has an ID (R01, R02...) and a severity:
- `!!!` HIGH — Presentation-breaking (wrap alignment, structural issues)
- ` ! ` MEDIUM — Visible quality issue (unbalanced columns, borders)
- `   ` LOW — Cosmetic (mixed justification, excessive spacing)

### Step 2 — Present findings to user

Report findings clearly. Explain the visual impact:
- "R01: Paragraph #11 is a numbered list item but has no indentation. When text wraps to a second line, it will snap to the left margin instead of aligning with the first-line text."
- "R05: Body paragraphs mix left-aligned and justified text — inconsistent appearance."

### Step 3 — Get approval

User selects which findings to fix: "fix R01 through R04" or "fix all high-severity".

### Step 4 — Apply fixes surgically
```
python office_edit.py review-fix <file> "R01,R02,R03,R04" --dry-run
python office_edit.py review-fix <file> "R01,R02,R03,R04"
```

Always dry-run first. Then apply. Tool creates backup automatically.

### Step 5 — Verify
```
python office_edit.py review <file>
```

Re-run review. Confirm finding count decreased. Report remaining items.

## Other Operations

### Content Control (SDT) Operations
```
python office_edit.py sdt-list <file>                          # List all SDTs
python office_edit.py sdt-find <file> <tag>                    # Find by tag
python office_edit.py sdt-replace <file> <tag> <new-text>      # Replace content
python office_edit.py sdt-add <file> <after-text> <tag> <placeholder>  # Add new SDT
```
See `references/content-controls-reference.md`.

### Text Find/Replace
```
python office_edit.py find <file> <pattern>                    # Find + run-split report
python office_edit.py replace <file> <old> <new>               # Single replacement
python office_edit.py replace-map <file> <map.json>            # Bulk from JSON
```

### Formatting Operations
```
python office_edit.py format-audit <file>                      # Audit paragraphs
python office_edit.py format-list-audit <file>                 # Audit numbering
python office_edit.py format-fix-indent <file>                 # Fix missing indents
```

### Deep Inspection
```
python office_edit.py inspect <file>                           # Basic part listing
python office_edit.py inspect-deep <file>                      # Full analysis
```

### Excel Cell Edits
```
python office_edit.py cell <file.xlsx> "Sheet1!A1" <value>
```

### Backup/Restore
```
python office_edit.py backup <file>
python office_edit.py restore <file>
```

All commands accept `--dry-run` where applicable.

## Droid Dispatch

For complex multi-step operations, dispatch specialized droids from `droids/`:

| Operation | Droid | When to use |
|-----------|-------|-------------|
| Document quality review | `document-review-droid.md` | Any template review before production |
| Add/modify content controls | `word-sdt-droid.md` | Adding new field placeholders |
| Fix formatting/indentation | `word-format-droid.md` | Wrap alignment, spacing issues |
| Numbering definitions | `word-numbering-droid.md` | Missing/broken list definitions |
| Table operations | `word-table-droid.md` | Signature blocks, data tables |
| Post-edit verification | `validation-droid.md` | After any write operation |
| Excel cell operations | `excel-cell-droid.md` | Spreadsheet edits |
| PowerPoint edits | `pptx-slide-droid.md` | Slide text updates |

## References

| File | Topic |
|------|-------|
| `references/wordprocessingml-reference.md` | Complete Word XML reference |
| `references/content-controls-reference.md` | SDT patterns and manipulation |
| `references/numbering-and-lists-reference.md` | Bullets, numbers, indentation |
| `references/formatting-preservation.md` | Rules for preserving formatting |
| `references/business-presentation-standards.md` | Document review anomaly definitions |
| `references/spreadsheetml-reference.md` | Excel XML reference |
| `references/presentationml-reference.md` | PowerPoint XML reference |
| `references/ooxml-anatomy.md` | Package structure |
| `references/run-splitting.md` | Run-split detection and handling |
| `references/safe-edit-patterns.md` | Safe editing patterns |

## When NOT to Use This Skill

- **Image/chart/formula edits** — text only
- **Style/theme creation** — use Word directly
- **New document creation** — use python-docx with a template
- **Old binary formats (.doc, .xls, .ppt)** — convert first
- **VBA macros (.docm, .xlsm)** — text edits OK, but never touch vbaProject.bin
