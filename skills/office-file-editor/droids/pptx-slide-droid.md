# PowerPoint Slide Droid — Slide Text, Shapes, and Notes

## Purpose
Find and replace text in PowerPoint slides and speaker notes. Handle run-splitting the same way as .docx.

## When Dispatched
- Need to update text on slides (names, dates, figures)
- Need to update speaker notes
- Need to find specific content across all slides

## Tools Available
- `python office_edit.py find <file.pptx> <text>` — search all slides + notes
- `python office_edit.py replace <file.pptx> <old> <new>` — replace across slides
- `python office_edit.py inspect <file.pptx>` — list slides and text parts

## Key Rules
1. PowerPoint uses `<a:t>` instead of `<w:t>` — same run-splitting applies
2. python-pptx handles cross-run replacements
3. Don't change shape IDs or placeholder types
4. Slide layouts and masters affect inheritance — edits to masters cascade

## Verification
- Run `find` for the new text to confirm replacement
- Run `find` for the old text to confirm it's gone
