# Safe edit patterns

The discipline of editing Office files in place without breaking them or losing data. These are the load-bearing patterns the script enforces and the ones you should follow if you're operating outside the script.

## 1. Backup before any write

**Pattern:** every write operation creates `<file>.bak.<timestamp>` first. If backup creation fails (disk full, permission denied), the operation aborts before touching the original.

**Why:** OOXML files are dense. A bad write can corrupt the file in ways Word can't recover from. The backup is the rollback path. The timestamp lets you keep multiple backups across iterations of an editing session.

**Implementation:**
```python
backup = path.with_suffix(path.suffix + f".bak.{datetime.now():%Y%m%d-%H%M%S}")
shutil.copy2(path, backup)
if not backup.exists() or backup.stat().st_size != path.stat().st_size:
    raise SystemExit("Backup creation failed")
```

**Don't:** use `shutil.move()` to "rename" the original out of the way. If the script crashes, the original is gone.

## 2. Refuse to edit if target not found

**Pattern:** before any replace, count occurrences of the target string. If zero, exit non-zero with a clear message. Do not proceed.

**Why:** silent no-ops are worse than failures. A script that "succeeds" while doing nothing teaches the user that the script worked when it didn't. The next time they run it, they'll trust an output that's wrong.

**Implementation:**
```python
pre_count = sum(count_in_zip(path, old).values())
if pre_count == 0:
    print(f"Refusing to edit: {old!r} not found")
    return 1
```

## 3. Atomic write via temp + rename

**Pattern:** write the new file to `<file>.tmp`, then `tmp.replace(file)` atomically. Don't open the original for write directly.

**Why:** if the write crashes mid-stream, the original is intact. The OS-level rename is atomic on a single filesystem, so observers either see the old file or the new file — never a partial write.

**Implementation:**
```python
tmp = path.with_suffix(path.suffix + ".tmp")
with zipfile.ZipFile(path, "r") as zin:
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            zout.writestr(item, modified_data.get(item.filename, zin.read(item.filename)))
tmp.replace(path)
```

**Don't:** open the original zip for write mode. Python's zipfile module's "a" (append) mode has surprising edge cases on Office files.

## 4. Verify post-edit

**Pattern:** after every write, re-open the file and count occurrences of the OLD string and the NEW string. Old should be 0; new should equal pre-count. Print both.

**Why:** verification catches three classes of failure: split-run misses (old > 0 after edit), encoding bugs (new count wrong), and zip-rewrite corruption (file won't open).

**Implementation:**
```python
post_old = sum(count_in_zip(path, old).values())
post_new = sum(count_in_zip(path, new).values())
print(f"Post-edit count of {old!r}: {post_old}")
print(f"Post-edit count of {new!r}: {post_new}")
if post_old != 0:
    print("WARN: old string remains. Possible split-run miss.")
    return 3
```

## 5. Preserve zip metadata

**Pattern:** when rewriting a zip, copy the `ZipInfo` from each original entry. Don't construct new `ZipInfo` objects from scratch.

**Why:** Office files include zip-level metadata (compression method, file size, modification time, external attributes) that some Office implementations are sensitive to. Reconstructing them risks creating a file that opens in Word but fails in Office Online or LibreOffice.

**Implementation:**
```python
with zipfile.ZipFile(src, "r") as zin:
    with zipfile.ZipFile(dst, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():        # ZipInfo carries the metadata
            data = modified.get(item.filename, zin.read(item.filename))
            zout.writestr(item, data)       # writestr(ZipInfo, data) preserves metadata
```

**Don't:** use `zout.write(filename, arcname=...)` — that constructs new metadata.

## 6. Use the right tool per file type

| Scenario | Right tool |
|---|---|
| Find/replace text in docx (single run) | Raw zipfile + string replace |
| Find/replace text in docx (split runs) | python-docx |
| Set specific xlsx cell | openpyxl |
| Find/replace text across xlsx | Raw zipfile on `sharedStrings.xml` (BUT remember every cell sharing the string changes) |
| Replace slide text in pptx | python-pptx |
| Edit slide layout / master | python-pptx (or hand-edit) |
| Update document properties (title, author) | Raw zipfile on `docProps/core.xml` |

The `office_edit.py` script picks the right tool automatically for `replace`, `replace-map`, and `cell` commands.

## 7. Never edit binary parts

**Pattern:** before editing a part, check that it's an XML file (extension `.xml`, `.rels`). If not, refuse.

**Why:** image files, embedded objects, fonts, and macro VBA (`vbaProject.bin`) are binary. Treating them as UTF-8 text and writing back will corrupt them silently — but the file may still open in Word, with the binary parts replaced by garbage.

**Implementation:**
```python
if not name.endswith((".xml", ".rels")):
    continue  # binary; never modify as text
```

## 8. Document encoding is UTF-8 — handle errors

**Pattern:** when decoding, use `errors="replace"` for inspection (so you can see the file content even if it has unexpected bytes), but use `errors="strict"` (the default) for the actual write path. Catch decode errors as a hard failure.

**Why:** OOXML XML must be valid UTF-8. If decoding strictly fails, the file is already corrupt — you should not write it back, because writing back with `errors="replace"` would silently lose data.

**Implementation:**
```python
# For inspection (find, count):
content = data.decode("utf-8", errors="replace")
# For edit (read, modify, write back):
content = data.decode("utf-8")  # strict; raises if invalid
```

## 9. Confirm Office can open the file

**Pattern:** after the script confirms verification passed, the human opens the file in Word/Excel/PowerPoint to confirm it actually displays correctly. Verification at the script level only confirms text content — it doesn't catch layout corruption, missing images, or rendering glitches.

**Why:** OOXML has thousands of edge cases. A script that handles 99% can still produce a file that opens with "this file appears to be corrupt — recover?" Word's recovery is generally reliable, but it's a signal that something subtle was wrong.

**Recommendation:** for any first-time edit on a new template, open in Word as a final check. After the same template has survived 5+ edit cycles, you can trust the script.

## 10. Restore is one command

**Pattern:** the script has a `restore` command that finds the latest `*.bak.*` file and copies it back. No manual file juggling.

**Why:** when you realize an edit was wrong, you want one command, not a process. Manual restore is where mistakes get made (overwriting the backup with the corrupted file by accident is a painful one to debug).

**Implementation:**
```python
def latest_backup(path):
    return max(path.parent.glob(f"{path.name}.bak.*"), default=None)

# CLI:
shutil.copy2(latest_backup(path), path)
```
