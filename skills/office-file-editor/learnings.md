# office-file-editor — Learnings

Append a structured entry every time an edit hits a failure pattern that wasn't already documented here. Read at Step 0 of every run.

Schema:

```
## YYYY-MM-DD — short title
- File: <name>.<ext>
- Symptom: <what went wrong>
- Root cause: <what was actually broken — usually run-split, wrong part, or zip metadata>
- Fix: <what change resolved it>
- Detector: <heuristic added so future runs catch this earlier>
```

---

## 2026-05-10 — Bootstrap learning: backup-first saved a clean restore path
- File: Portfolio_Addendum.docx
- Symptom: First ad-hoc OOXML edit (before this skill existed) ran cleanly — but only because the target text "Readydocx" was in a single run. Lucky.
- Root cause: N/A — edit succeeded, but the same approach would have silently corrupted formatting if the string had been split across runs.
- Fix: This skill formalizes the backup-first + run-split-detection pattern that the ad-hoc script lacked.
- Detector: For any docx edit, run `find <file> <pattern>` first and check the run-split column before deciding raw vs. python-docx.
