# office-file-editor

Edit Microsoft Office files (`.docx`, `.xlsx`, `.pptx`) in place via OOXML — without opening Word/Excel/PowerPoint, without a paid Office license, without paying for a third-party converter.

A Claude Code skill plus a standalone Python CLI.

## Why this exists

Three real situations:

1. **You need to fix a date in a polished resume that lives in three different Word versions.** Opening, editing, saving, and re-checking each is 20 minutes per file. A surgical find/replace is 5 seconds.
2. **You need to bulk-update statuses in an Excel sheet from a JSON map.** Excel's macro path is heavy; openpyxl is right.
3. **You're on a machine without Office installed.** Linux, server, CI pipeline, low-end laptop — Office files are still readable and editable; you just need to know they're zip+XML underneath.

This tool makes all three painless and safe.

## What it does

- **Find/replace text** across an entire `.docx`, `.xlsx`, or `.pptx` — handles run-split text correctly (the #1 reason naive find/replace fails on Word docs)
- **Update specific xlsx cells** by `Sheet1!A1` notation
- **Inspect** file structure (what XML parts are inside, what text-bearing parts exist)
- **Backup-first, verify-last** — every edit produces `<file>.bak.<timestamp>` before writing, then re-opens the file to confirm the edit landed
- **One-command restore** if something goes wrong

## Install

```bash
git clone https://github.com/joec8125-alt/office-file-editor.git
cd office-file-editor
pip install python-docx openpyxl python-pptx
```

That's it. No Office license required. Works on Windows, macOS, Linux.

## Use

```bash
# Look around
python office_edit.py inspect resume.docx
python office_edit.py find resume.docx "Old Title"

# Edit safely (auto-backup, auto-verify)
python office_edit.py replace resume.docx "Old Title" "New Title" --dry-run
python office_edit.py replace resume.docx "Old Title" "New Title"

# Bulk find/replace from a JSON map
python office_edit.py replace-map resume.docx changes.json

# Set a specific xlsx cell
python office_edit.py cell tracker.xlsx "Sheet1!L42" "Contacted"

# Recover from the latest backup
python office_edit.py restore resume.docx
```

`changes.json` format:

```json
{
  "Old Company Name": "New Company Name",
  "2021–Present": "2021–2025",
  "Director of Foo": "VP of Foo"
}
```

## Safety properties

The script enforces ten patterns documented in `references/safe-edit-patterns.md`. Highlights:

1. Backup before any write — refuses to write if backup creation fails
2. Refuses to edit if target string not found (no silent no-ops)
3. Detects run-split text in `.docx`/`.pptx` and falls back to `python-docx`/`python-pptx` automatically (preserves first-run formatting on the matched span)
4. Atomic write via temp + rename — original is intact if write crashes mid-stream
5. Verifies post-edit by re-opening the file and counting old/new occurrences
6. Refuses to edit binary parts (images, embedded objects, font files, VBA macros)
7. Uses the right tool per format — `openpyxl` for xlsx cells, `python-pptx` for slides, raw zipfile for fast docx find/replace
8. Preserves zip metadata (compression method, entry order)

## What this skill is NOT

- Not for creating new documents from scratch — use `python-docx` directly with a template
- Not for image / chart / formula edits
- Not for style or formatting changes — use Word/Excel directly
- Not for old binary formats (`.doc`, `.xls`, `.ppt`) — convert to modern OOXML first
- Not for editing macro VBA in `.docm`/`.xlsm` — script will refuse to touch `vbaProject.bin`

## Use as a Claude Code skill

If you use Claude Code, this folder also functions as a project-scoped or global skill. Drop into `~/.claude/skills/` (or symlink) and Claude will auto-discover it. The `SKILL.md` describes the workflow, hard rules, and self-check rubric Claude follows when invoked.

## License

MIT. See `LICENSE`.

## Author

Joe Cameron — joe-cameron-leadership.netlify.app
