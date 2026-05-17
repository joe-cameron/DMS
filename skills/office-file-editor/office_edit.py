"""Surgical editor for .docx / .xlsx / .pptx files. See SKILL.md for the contract."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import zipfile
from datetime import datetime
from pathlib import Path

# Lazy imports for python-docx, openpyxl, python-pptx — only loaded when needed
# so 'inspect' / 'find' run without importing them.

# ---------------- helpers ----------------

TEXT_XML_PATTERNS = {
    ".docx": ("word/document.xml", "word/header", "word/footer", "word/footnotes.xml",
              "word/endnotes.xml", "word/comments.xml"),
    ".xlsx": ("xl/sharedStrings.xml", "xl/worksheets/sheet"),
    ".pptx": ("ppt/slides/slide", "ppt/notesSlides/notesSlide", "ppt/slideLayouts/slideLayout"),
}


def file_kind(path: Path) -> str:
    suf = path.suffix.lower()
    if suf in (".docx", ".xlsx", ".pptx"):
        return suf
    raise SystemExit(f"Unsupported file type: {suf}. Supported: .docx .xlsx .pptx")


def text_parts(z: zipfile.ZipFile, kind: str) -> list[str]:
    """Return the names of XML parts in the archive that contain user-visible text."""
    patterns = TEXT_XML_PATTERNS[kind]
    return [n for n in z.namelist() if any(n.startswith(p) or n == p for p in patterns) and n.endswith(".xml")]


def make_backup(path: Path) -> Path:
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = path.with_suffix(path.suffix + f".bak.{ts}")
    shutil.copy2(path, backup)
    if not backup.exists() or backup.stat().st_size != path.stat().st_size:
        raise SystemExit(f"Backup creation failed: {backup}")
    return backup


def latest_backup(path: Path) -> Path | None:
    candidates = sorted(path.parent.glob(f"{path.name}.bak.*"))
    return candidates[-1] if candidates else None


def count_in_zip(path: Path, pattern: str, parts: list[str] | None = None) -> dict[str, int]:
    """Count occurrences of `pattern` per XML part."""
    counts: dict[str, int] = {}
    with zipfile.ZipFile(path) as z:
        names = parts if parts else text_parts(z, file_kind(path))
        for name in names:
            try:
                content = z.read(name).decode("utf-8", errors="replace")
            except KeyError:
                continue
            n = content.count(pattern)
            if n:
                counts[name] = n
    return counts


def is_split_in_runs(xml_content: str, pattern: str) -> bool:
    """True if `pattern` appears in the document text but NOT inside any single <w:t> or <a:t>."""
    text_runs = re.findall(r"<(?:w|a):t[^>]*>([^<]*)</(?:w|a):t>", xml_content)
    if any(pattern in run for run in text_runs):
        return False
    # Stripped text contains pattern? Then it must be split.
    stripped = re.sub(r"<[^>]+>", "", xml_content)
    return pattern in stripped


def xml_escape(text: str) -> str:
    """Escape text for safe XML injection."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def strip_highlight(rpr_xml: str) -> str:
    """Remove highlight from rPr XML, keeping everything else."""
    return re.sub(r"<w:highlight[^/]*/>\s*", "", rpr_xml)


# ------------- SDT helpers ---------------

def find_sdts_in_xml(xml_content: str) -> list[dict]:
    """Find all SDTs in document XML. Returns list of dicts with tag, alias, type, content, position."""
    results = []
    for m in re.finditer(r"<w:sdt>(.*?)</w:sdt>", xml_content, re.DOTALL):
        block = m.group(1)
        tag_m = re.search(r'<w:tag w:val="([^"]*)"', block)
        alias_m = re.search(r'<w:alias w:val="([^"]*)"', block)
        # Determine type
        sdt_type = "richText"
        if "<w:text/>" in block:
            sdt_type = "plainText"
        elif "<w:date" in block:
            sdt_type = "date"
        elif "<w:comboBox" in block or "<w:dropDownList" in block:
            sdt_type = "dropdown"
        elif "<w:picture/>" in block:
            sdt_type = "picture"
        # Extract text from sdtContent
        content_m = re.search(r"<w:sdtContent>(.*?)</w:sdtContent>", block, re.DOTALL)
        text = ""
        if content_m:
            text = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", content_m.group(1)))
        results.append({
            "tag": tag_m.group(1) if tag_m else None,
            "alias": alias_m.group(1) if alias_m else None,
            "type": sdt_type,
            "content": text,
            "start": m.start(),
            "end": m.end(),
        })
    return results


def replace_sdt_content_by_tag(xml_content: str, tag: str, new_text: str) -> tuple[str, int]:
    """Replace SDT content by tag, preserving all properties. Returns (new_xml, count)."""
    escaped = xml_escape(new_text)
    count = 0

    def replacer(m):
        nonlocal count
        full = m.group(0)
        # Check if this SDT has the right tag
        tag_m = re.search(r'<w:tag w:val="([^"]*)"', full)
        if not tag_m or tag_m.group(1) != tag:
            return full
        count += 1
        # Extract rPr from first run in old content for formatting
        content_m = re.search(r"<w:sdtContent>(.*?)</w:sdtContent>", full, re.DOTALL)
        rpr = ""
        if content_m:
            rpr_m = re.search(r"(<w:rPr>.*?</w:rPr>)", content_m.group(1), re.DOTALL)
            if rpr_m:
                rpr = strip_highlight(rpr_m.group(1))
        # Remove showingPlcHdr
        new_sdt = re.sub(r"<w:showingPlcHdr/>\s*", "", full)
        # Replace sdtContent
        new_content = f"<w:r>{rpr}<w:t xml:space=\"preserve\">{escaped}</w:t></w:r>"
        new_sdt = re.sub(
            r"<w:sdtContent>.*?</w:sdtContent>",
            f"<w:sdtContent>{new_content}</w:sdtContent>",
            new_sdt,
            flags=re.DOTALL,
        )
        return new_sdt

    result = re.sub(r"<w:sdt>.*?</w:sdt>", replacer, xml_content, flags=re.DOTALL)
    return result, count


def build_inline_sdt_xml(tag: str, alias: str, placeholder: str) -> str:
    """Build an inline SDT XML fragment for insertion into a paragraph."""
    return (
        f'<w:sdt><w:sdtPr>'
        f'<w:tag w:val="{xml_escape(tag)}"/>'
        f'<w:alias w:val="{xml_escape(alias)}"/>'
        f'<w:text/>'
        f'<w:showingPlcHdr/>'
        f'</w:sdtPr><w:sdtEndPr/>'
        f'<w:sdtContent>'
        f'<w:r><w:rPr><w:rStyle w:val="PlaceholderText"/></w:rPr>'
        f'<w:t>{xml_escape(placeholder)}</w:t></w:r>'
        f'</w:sdtContent></w:sdt>'
    )


# ------------- formatting helpers --------

def audit_paragraphs(xml_content: str) -> list[dict]:
    """Audit every paragraph for indentation, numbering, and style. Returns list of findings."""
    findings = []
    for i, m in enumerate(re.finditer(r"<w:p[ >](.*?)</w:p>", xml_content, re.DOTALL)):
        para_inner = m.group(1)
        ppr_m = re.search(r"<w:pPr>(.*?)</w:pPr>", para_inner, re.DOTALL)
        text = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", para_inner))

        info: dict = {"index": i, "pos": m.start(), "text_preview": text[:60]}

        if ppr_m:
            ppr = ppr_m.group(1)
            style_m = re.search(r'<w:pStyle w:val="([^"]*)"', ppr)
            info["style"] = style_m.group(1) if style_m else None

            numid_m = re.search(r'<w:numId w:val="(\d+)"', ppr)
            ilvl_m = re.search(r'<w:ilvl w:val="(\d+)"', ppr)
            info["numId"] = numid_m.group(1) if numid_m else None
            info["ilvl"] = ilvl_m.group(1) if ilvl_m else None

            ind_m = re.search(r"<w:ind\s+([^/]*)/?>", ppr)
            if ind_m:
                attrs = ind_m.group(1)
                left_m = re.search(r'w:left="(\d+)"', attrs)
                hanging_m = re.search(r'w:hanging="(\d+)"', attrs)
                first_m = re.search(r'w:firstLine="(\d+)"', attrs)
                info["ind_left"] = int(left_m.group(1)) if left_m else None
                info["ind_hanging"] = int(hanging_m.group(1)) if hanging_m else None
                info["ind_firstLine"] = int(first_m.group(1)) if first_m else None
            else:
                info["ind_left"] = None
                info["ind_hanging"] = None

            # Flag: list paragraph without indentation
            if info.get("numId") and info["ind_left"] is None:
                info["issue"] = "LIST_NO_INDENT"
        else:
            info["style"] = None
            info["numId"] = None
            info["ind_left"] = None
            info["ind_hanging"] = None

        findings.append(info)
    return findings


def audit_numbering(numbering_xml: str) -> list[dict]:
    """Parse numbering.xml and return all abstract number definitions with their level info."""
    defs = []
    for m in re.finditer(r'<w:abstractNum w:abstractNumId="(\d+)">(.*?)</w:abstractNum>', numbering_xml, re.DOTALL):
        abs_id = m.group(1)
        body = m.group(2)
        levels = []
        for lvl_m in re.finditer(r'<w:lvl w:ilvl="(\d+)">(.*?)</w:lvl>', body, re.DOTALL):
            lvl_body = lvl_m.group(2)
            fmt_m = re.search(r'<w:numFmt w:val="([^"]*)"', lvl_body)
            left_m = re.search(r'w:left="(\d+)"', lvl_body)
            hang_m = re.search(r'w:hanging="(\d+)"', lvl_body)
            txt_m = re.search(r'<w:lvlText w:val="([^"]*)"', lvl_body)
            levels.append({
                "ilvl": lvl_m.group(1),
                "numFmt": fmt_m.group(1) if fmt_m else None,
                "left": int(left_m.group(1)) if left_m else None,
                "hanging": int(hang_m.group(1)) if hang_m else None,
                "lvlText": txt_m.group(1) if txt_m else None,
            })
        defs.append({"abstractNumId": abs_id, "levels": levels})

    # Map numId -> abstractNumId
    num_map = []
    for m in re.finditer(r'<w:num w:numId="(\d+)">(.*?)</w:num>', numbering_xml, re.DOTALL):
        abs_m = re.search(r'<w:abstractNumId w:val="(\d+)"', m.group(2))
        num_map.append({"numId": m.group(1), "abstractNumId": abs_m.group(1) if abs_m else None})

    return {"abstractNums": defs, "nums": num_map}


# ---------------- commands ----------------

def cmd_inspect(args):
    path = Path(args.file)
    kind = file_kind(path)
    print(f"File: {path}  ({kind}, {path.stat().st_size:,} bytes)")
    with zipfile.ZipFile(path) as z:
        all_parts = z.namelist()
        text_xml = text_parts(z, kind)
        print(f"Total parts in archive: {len(all_parts)}")
        print(f"Text-bearing XML parts: {len(text_xml)}")
        for n in text_xml:
            info = z.getinfo(n)
            print(f"  {n}  ({info.file_size:,} bytes)")
    backup = latest_backup(path)
    if backup:
        print(f"Latest backup: {backup.name}")
    return 0


def cmd_find(args):
    path = Path(args.file)
    kind = file_kind(path)
    pattern = args.pattern
    print(f"Searching for: {pattern!r} in {path}")
    counts = count_in_zip(path, pattern)
    if not counts:
        print("Not found in any text-bearing XML part.")
        return 1
    total = sum(counts.values())
    print(f"Total occurrences: {total}  (across {len(counts)} part(s))")
    with zipfile.ZipFile(path) as z:
        for name, n in counts.items():
            content = z.read(name).decode("utf-8", errors="replace")
            split = is_split_in_runs(content, pattern) if kind in (".docx", ".pptx") else False
            split_label = "  [SPLIT-RUN — needs python-docx fallback]" if split else ""
            print(f"  {name}: {n}{split_label}")
    return 0


def _replace_in_zip(path: Path, replacements: dict[str, str], dry_run: bool) -> tuple[dict[str, int], bool]:
    """Apply replacements across all text XML parts. Returns (per-part-changes, used_fallback)."""
    kind = file_kind(path)
    used_fallback = False

    # First pass: detect any split-run cases that require python-docx fallback
    needs_fallback = False
    if kind in (".docx", ".pptx"):
        with zipfile.ZipFile(path) as z:
            for name in text_parts(z, kind):
                content = z.read(name).decode("utf-8", errors="replace")
                for old in replacements:
                    if is_split_in_runs(content, old):
                        needs_fallback = True
                        break
                if needs_fallback:
                    break

    if needs_fallback and kind == ".docx":
        return _replace_via_python_docx(path, replacements, dry_run), True

    if needs_fallback and kind == ".pptx":
        return _replace_via_python_pptx(path, replacements, dry_run), True

    # Raw zipfile path: rewrite each part with simple string replace
    changes: dict[str, int] = {}
    new_entries: dict[str, bytes] = {}
    with zipfile.ZipFile(path, "r") as zin:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename in text_parts(zin, kind):
                content = data.decode("utf-8")
                changed = 0
                for old, new in replacements.items():
                    n = content.count(old)
                    if n:
                        content = content.replace(old, new)
                        changed += n
                if changed:
                    changes[item.filename] = changed
                    new_entries[item.filename] = content.encode("utf-8")

    if not changes:
        return {}, False

    if dry_run:
        return changes, False

    # Atomic rewrite
    tmp = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path, "r") as zin:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = new_entries.get(item.filename, zin.read(item.filename))
                zout.writestr(item, data)
    tmp.replace(path)
    return changes, False


def _replace_via_python_docx(path: Path, replacements: dict[str, str], dry_run: bool) -> dict[str, int]:
    """Run-aware replace for .docx. Preserves first-run formatting on the matched span."""
    from docx import Document  # type: ignore
    doc = Document(str(path))
    changes_total = 0

    def replace_in_paragraph(para, old: str, new: str) -> int:
        """Replace `old` with `new` in `para`, handling run-splits."""
        if old not in para.text:
            return 0
        runs = list(para.runs)
        run_texts = [r.text for r in runs]
        full = "".join(run_texts)
        count = 0
        while old in full:
            start = full.index(old)
            end = start + len(old)
            # Find run indices covering [start, end)
            pos = 0
            affected = []  # list of (run_index, run_start, run_end)
            for i, t in enumerate(run_texts):
                rstart = pos
                rend = pos + len(t)
                if rend > start and rstart < end:
                    affected.append((i, rstart, rend))
                pos = rend
            first_idx, first_rstart, _ = affected[0]
            last_idx, _, last_rend = affected[-1]
            before = run_texts[first_idx][: start - first_rstart]
            after = run_texts[last_idx][end - last_rend + len(run_texts[last_idx]):]
            if first_idx == last_idx:
                runs[first_idx].text = before + new + after
                run_texts[first_idx] = runs[first_idx].text
            else:
                runs[first_idx].text = before + new
                run_texts[first_idx] = runs[first_idx].text
                for j in range(first_idx + 1, last_idx):
                    runs[j].text = ""
                    run_texts[j] = ""
                runs[last_idx].text = after
                run_texts[last_idx] = after
            full = "".join(run_texts)
            count += 1
        return count

    for para in doc.paragraphs:
        for old, new in replacements.items():
            changes_total += replace_in_paragraph(para, old, new)
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                for para in cell.paragraphs:
                    for old, new in replacements.items():
                        changes_total += replace_in_paragraph(para, old, new)
    # Headers / footers
    for section in doc.sections:
        for header_or_footer in (section.header, section.footer, section.first_page_header,
                                 section.first_page_footer, section.even_page_header,
                                 section.even_page_footer):
            if header_or_footer is None:
                continue
            for para in header_or_footer.paragraphs:
                for old, new in replacements.items():
                    changes_total += replace_in_paragraph(para, old, new)

    if not dry_run:
        doc.save(str(path))
    return {"<via python-docx>": changes_total} if changes_total else {}


def _replace_via_python_pptx(path: Path, replacements: dict[str, str], dry_run: bool) -> dict[str, int]:
    """Run-aware replace for .pptx slides + speaker notes."""
    from pptx import Presentation  # type: ignore
    pres = Presentation(str(path))
    changes_total = 0
    for slide in pres.slides:
        for shape in slide.shapes:
            if not shape.has_text_frame:
                continue
            for para in shape.text_frame.paragraphs:
                for run in para.runs:
                    for old, new in replacements.items():
                        if old in run.text:
                            run.text = run.text.replace(old, new)
                            changes_total += 1
        if slide.has_notes_slide:
            tf = slide.notes_slide.notes_text_frame
            for para in tf.paragraphs:
                for run in para.runs:
                    for old, new in replacements.items():
                        if old in run.text:
                            run.text = run.text.replace(old, new)
                            changes_total += 1
    if not dry_run:
        pres.save(str(path))
    return {"<via python-pptx>": changes_total} if changes_total else {}


def cmd_replace(args):
    path = Path(args.file)
    if not path.exists():
        print(f"File not found: {path}")
        return 2

    pre_count = sum(count_in_zip(path, args.old).values())
    if pre_count == 0:
        print(f"Refusing to edit: {args.old!r} not found in {path}")
        return 1
    print(f"Pre-edit count of {args.old!r}: {pre_count}")

    if args.dry_run:
        print("(dry-run)")
        changes, fallback = _replace_in_zip(path, {args.old: args.new}, dry_run=True)
        for name, n in changes.items():
            print(f"  Would change {name}: {n} occurrences")
        if fallback:
            print("  Would use python-docx/python-pptx fallback (split-run text detected)")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    changes, fallback = _replace_in_zip(path, {args.old: args.new}, dry_run=False)
    if fallback:
        print("Used python-docx/python-pptx fallback (split-run text detected)")
    for name, n in changes.items():
        print(f"  Changed {name}: {n} occurrences")

    post_old = sum(count_in_zip(path, args.old).values())
    post_new = sum(count_in_zip(path, args.new).values())
    print(f"Post-edit count of {args.old!r}: {post_old}")
    print(f"Post-edit count of {args.new!r}: {post_new}")

    if post_old != 0:
        print(f"WARN: {post_old} occurrence(s) of old string remain. Possible split-run miss.")
        return 3
    return 0


def cmd_replace_map(args):
    path = Path(args.file)
    map_path = Path(args.map)
    if not map_path.exists():
        print(f"Map file not found: {map_path}")
        return 2
    mapping = json.loads(map_path.read_text(encoding="utf-8"))
    if not isinstance(mapping, dict) or not mapping:
        print("Map JSON must be a non-empty object {old: new, ...}")
        return 2

    pre = {old: sum(count_in_zip(path, old).values()) for old in mapping}
    missing = [k for k, v in pre.items() if v == 0]
    if missing:
        print("Refusing to edit. Strings not found in file:")
        for k in missing:
            print(f"  - {k!r}")
        return 1
    print("Pre-edit counts:")
    for old, n in pre.items():
        print(f"  {old!r}: {n}")

    if args.dry_run:
        print("(dry-run)")
        changes, fallback = _replace_in_zip(path, mapping, dry_run=True)
        for name, n in changes.items():
            print(f"  Would change {name}: {n} occurrences")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    changes, fallback = _replace_in_zip(path, mapping, dry_run=False)
    for name, n in changes.items():
        print(f"  Changed {name}: {n} occurrences")
    if fallback:
        print("Used python-docx/python-pptx fallback (split-run text detected)")

    print("Post-edit verification:")
    for old, new in mapping.items():
        po = sum(count_in_zip(path, old).values())
        pn = sum(count_in_zip(path, new).values())
        flag = "" if po == 0 else "  WARN: old string remains"
        print(f"  {old!r} -> {new!r}: old={po}, new={pn}{flag}")
    return 0


def cmd_cell(args):
    path = Path(args.file)
    if path.suffix.lower() != ".xlsx":
        print("--cell command is xlsx-only")
        return 2
    from openpyxl import load_workbook  # type: ignore
    if "!" not in args.address:
        print("Address format: 'Sheet1!A1' (sheet name, !, then cell ref)")
        return 2
    sheet_name, cell_ref = args.address.split("!", 1)

    wb = load_workbook(str(path))
    if sheet_name not in wb.sheetnames:
        print(f"Sheet not found: {sheet_name}. Available: {wb.sheetnames}")
        return 2
    ws = wb[sheet_name]
    old_value = ws[cell_ref].value
    print(f"Pre-edit {sheet_name}!{cell_ref}: {old_value!r}")

    if args.dry_run:
        print(f"(dry-run) would set to: {args.value!r}")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    # Coerce numeric strings to numbers if they look numeric (preserves Excel typing)
    val = args.value
    try:
        if val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
            val = int(val)
        else:
            val = float(val)
    except ValueError:
        pass  # keep as string

    ws[cell_ref] = val
    wb.save(str(path))

    wb2 = load_workbook(str(path))
    new_value = wb2[sheet_name][cell_ref].value
    print(f"Post-edit {sheet_name}!{cell_ref}: {new_value!r}")
    return 0 if str(new_value) == str(val) else 3


def cmd_backup(args):
    path = Path(args.file)
    backup = make_backup(path)
    print(f"Backup: {backup}")
    return 0


def cmd_restore(args):
    path = Path(args.file)
    backup = latest_backup(path)
    if not backup:
        print(f"No backup found for {path}")
        return 1
    shutil.copy2(backup, path)
    print(f"Restored {path} from {backup.name}")
    return 0


# ------------ SDT commands ---------------

def cmd_sdt_list(args):
    """List all content controls (SDTs) in a .docx file."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("sdt-list is docx-only")
        return 2
    all_sdts = []
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith(".xml") and name.startswith("word/"):
                content = z.read(name).decode("utf-8", errors="replace")
                sdts = find_sdts_in_xml(content)
                for s in sdts:
                    s["part"] = name
                all_sdts.extend(sdts)
    if not all_sdts:
        print("No SDTs found.")
        return 0
    print(f"Found {len(all_sdts)} SDT(s):")
    for s in all_sdts:
        tag = s["tag"] or "(no tag)"
        alias = s["alias"] or "(no alias)"
        print(f"  [{s['type']}] tag={tag}  alias={alias}  content={s['content'][:50]!r}  part={s['part']}")
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(all_sdts, indent=2), encoding="utf-8")
        print(f"JSON written to {args.json_out}")
    return 0


def cmd_sdt_find(args):
    """Find a specific SDT by tag name."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("sdt-find is docx-only")
        return 2
    found = []
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith(".xml") and name.startswith("word/"):
                content = z.read(name).decode("utf-8", errors="replace")
                for s in find_sdts_in_xml(content):
                    if s["tag"] == args.tag:
                        s["part"] = name
                        found.append(s)
    if not found:
        print(f"SDT with tag={args.tag!r} not found.")
        return 1
    print(f"Found {len(found)} SDT(s) with tag={args.tag!r}:")
    for s in found:
        print(f"  [{s['type']}] alias={s['alias']}  content={s['content'][:80]!r}  part={s['part']}")
    return 0


def cmd_sdt_replace(args):
    """Replace SDT content by tag, preserving formatting."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("sdt-replace is docx-only")
        return 2

    # Verify tag exists
    tag_found = False
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith(".xml") and name.startswith("word/"):
                content = z.read(name).decode("utf-8", errors="replace")
                if any(s["tag"] == args.tag for s in find_sdts_in_xml(content)):
                    tag_found = True
                    break
    if not tag_found:
        print(f"Refusing to edit: SDT with tag={args.tag!r} not found")
        return 1

    if args.dry_run:
        print(f"(dry-run) Would replace SDT tag={args.tag!r} content with: {args.new_text!r}")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    # Apply replacement
    new_entries: dict[str, bytes] = {}
    total = 0
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith(".xml") and name.startswith("word/"):
                content = z.read(name).decode("utf-8")
                new_content, cnt = replace_sdt_content_by_tag(content, args.tag, args.new_text)
                if cnt:
                    total += cnt
                    new_entries[name] = new_content.encode("utf-8")

    if not new_entries:
        print("No replacements made.")
        return 1

    # Atomic rewrite
    tmp = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path, "r") as zin:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = new_entries.get(item.filename, zin.read(item.filename))
                zout.writestr(item, data)
    tmp.replace(path)
    print(f"Replaced {total} SDT(s) with tag={args.tag!r}")

    # Verify
    verify_count = 0
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith(".xml") and name.startswith("word/"):
                content = z.read(name).decode("utf-8", errors="replace")
                for s in find_sdts_in_xml(content):
                    if s["tag"] == args.tag and args.new_text in s["content"]:
                        verify_count += 1
    print(f"Post-edit verification: {verify_count} SDT(s) contain new text")
    return 0


def cmd_sdt_add(args):
    """Add a new inline plain-text SDT after a text match in document.xml."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("sdt-add is docx-only")
        return 2

    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8")

    # Find the anchor text
    if args.after_text not in doc_xml:
        # Check if it's in the stripped text (might be split across tags)
        stripped = re.sub(r"<[^>]+>", "", doc_xml)
        if args.after_text not in stripped:
            print(f"Refusing to edit: anchor text {args.after_text!r} not found in document.xml")
            return 1

    sdt_xml = build_inline_sdt_xml(args.tag, args.alias or args.tag, args.placeholder)

    if args.dry_run:
        print(f"(dry-run) Would insert SDT tag={args.tag!r} after {args.after_text!r}")
        print(f"  SDT XML: {sdt_xml[:120]}...")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    # Find the </w:r> that contains the after_text and insert SDT after it
    # Strategy: find <w:t> containing the text, find the enclosing </w:r>, insert after
    inserted = False
    pattern = re.compile(
        r"(<w:r>(?:<w:rPr>.*?</w:rPr>)?<w:t[^>]*>[^<]*"
        + re.escape(args.after_text)
        + r"[^<]*</w:t></w:r>)"
    , re.DOTALL)
    match = pattern.search(doc_xml)
    if match:
        insert_pos = match.end()
        doc_xml = doc_xml[:insert_pos] + sdt_xml + doc_xml[insert_pos:]
        inserted = True
    else:
        # Fallback: insert after the closing </w:t> that contains the text
        for t_m in re.finditer(r"<w:t[^>]*>([^<]*)</w:t>", doc_xml):
            if args.after_text in t_m.group(1):
                # Find the closing </w:r> after this <w:t>
                r_end = doc_xml.find("</w:r>", t_m.end())
                if r_end != -1:
                    insert_pos = r_end + len("</w:r>")
                    doc_xml = doc_xml[:insert_pos] + sdt_xml + doc_xml[insert_pos:]
                    inserted = True
                    break

    if not inserted:
        print("Could not find a safe insertion point. Anchor text may be split across runs.")
        return 1

    # Write back
    new_entries = {"word/document.xml": doc_xml.encode("utf-8")}
    tmp = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path, "r") as zin:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = new_entries.get(item.filename, zin.read(item.filename))
                zout.writestr(item, data)
    tmp.replace(path)
    print(f"Inserted SDT tag={args.tag!r} after {args.after_text!r}")

    # Verify
    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
    found = [s for s in find_sdts_in_xml(doc_xml) if s["tag"] == args.tag]
    print(f"Post-edit: found {len(found)} SDT(s) with tag={args.tag!r}")
    return 0


# ------------ formatting commands --------

def cmd_format_audit(args):
    """Audit all paragraph indentation, numbering, and styles in a .docx."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("format-audit is docx-only")
        return 2

    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")

    findings = audit_paragraphs(doc_xml)
    issues = [f for f in findings if f.get("issue")]
    list_paras = [f for f in findings if f.get("numId")]

    print(f"Total paragraphs: {len(findings)}")
    print(f"List paragraphs: {len(list_paras)}")
    print(f"Issues found: {len(issues)}")

    if list_paras:
        print("\nList paragraphs:")
        for f in list_paras:
            issue_flag = f"  ** {f['issue']} **" if f.get("issue") else ""
            print(f"  #{f['index']} numId={f['numId']} ilvl={f['ilvl']} "
                  f"left={f['ind_left']} hang={f['ind_hanging']} "
                  f"style={f['style']}  {f['text_preview'][:40]!r}{issue_flag}")

    if issues:
        print("\nISSUES:")
        for f in issues:
            print(f"  #{f['index']} {f['issue']}: numId={f['numId']} but no <w:ind> — "
                  f"text: {f['text_preview'][:40]!r}")

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(findings, indent=2), encoding="utf-8")
        print(f"\nFull audit JSON: {args.json_out}")
    return 0


def cmd_format_list_audit(args):
    """Audit numbering.xml definitions and paragraph references."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("format-list-audit is docx-only")
        return 2

    with zipfile.ZipFile(path) as z:
        if "word/numbering.xml" not in z.namelist():
            print("No word/numbering.xml in this document.")
            return 0
        num_xml = z.read("word/numbering.xml").decode("utf-8", errors="replace")
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")

    num_info = audit_numbering(num_xml)
    para_findings = audit_paragraphs(doc_xml)

    print("=== Numbering Definitions ===")
    for ab in num_info["abstractNums"]:
        print(f"\n  abstractNumId={ab['abstractNumId']}")
        for lvl in ab["levels"]:
            print(f"    ilvl={lvl['ilvl']} fmt={lvl['numFmt']} left={lvl['left']} "
                  f"hanging={lvl['hanging']} text={lvl['lvlText']!r}")

    print("\n=== Num ID Mapping ===")
    for nm in num_info["nums"]:
        print(f"  numId={nm['numId']} -> abstractNumId={nm['abstractNumId']}")

    # Cross-reference
    used_nums = set()
    for f in para_findings:
        if f.get("numId"):
            used_nums.add(f["numId"])
    defined_nums = {nm["numId"] for nm in num_info["nums"]}
    orphaned = used_nums - defined_nums
    if orphaned:
        print(f"\nWARN: Paragraphs reference undefined numIds: {orphaned}")
    unused = defined_nums - used_nums
    if unused:
        print(f"\nNote: Defined but unused numIds: {unused}")

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(num_info, indent=2), encoding="utf-8")
        print(f"\nJSON: {args.json_out}")
    return 0


def cmd_format_fix_indent(args):
    """Fix list paragraphs that have numPr but missing indentation."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("format-fix-indent is docx-only")
        return 2

    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
        has_numbering = "word/numbering.xml" in z.namelist()
        num_xml = z.read("word/numbering.xml").decode("utf-8", errors="replace") if has_numbering else ""

    # Build numId -> indent lookup from numbering.xml
    indent_lookup: dict[tuple[str, str], tuple[int, int]] = {}
    if num_xml:
        num_info = audit_numbering(num_xml)
        abs_map = {nm["numId"]: nm["abstractNumId"] for nm in num_info["nums"]}
        for ab in num_info["abstractNums"]:
            for lvl in ab["levels"]:
                for nm_id, abs_id in abs_map.items():
                    if abs_id == ab["abstractNumId"] and lvl["left"] is not None:
                        indent_lookup[(nm_id, lvl["ilvl"])] = (lvl["left"], lvl["hanging"] or 0)

    # Find and fix paragraphs with numPr but no indent
    fixes = 0

    def fix_para(m):
        nonlocal fixes
        full = m.group(0)
        ppr_m = re.search(r"<w:pPr>(.*?)</w:pPr>", full, re.DOTALL)
        if not ppr_m:
            return full
        ppr = ppr_m.group(1)
        numid_m = re.search(r'<w:numId w:val="(\d+)"', ppr)
        ilvl_m = re.search(r'<w:ilvl w:val="(\d+)"', ppr)
        if not numid_m:
            return full
        # Already has indent?
        if re.search(r"<w:ind\s", ppr):
            return full

        num_id = numid_m.group(1)
        ilvl = ilvl_m.group(1) if ilvl_m else "0"
        key = (num_id, ilvl)
        if key in indent_lookup:
            left, hanging = indent_lookup[key]
            indent_xml = f'<w:ind w:left="{left}" w:hanging="{hanging}"/>'
        else:
            # Default: standard bullet indent
            left = 720 * (int(ilvl) + 1)
            indent_xml = f'<w:ind w:left="{left}" w:hanging="360"/>'

        # Insert indent after numPr
        numpr_end = ppr.find("</w:numPr>")
        if numpr_end != -1:
            new_ppr = ppr[:numpr_end + len("</w:numPr>")] + indent_xml + ppr[numpr_end + len("</w:numPr>"):]
        else:
            new_ppr = ppr + indent_xml
        fixes += 1
        return full.replace(f"<w:pPr>{ppr}</w:pPr>", f"<w:pPr>{new_ppr}</w:pPr>")

    if args.dry_run:
        # Just count issues
        findings = audit_paragraphs(doc_xml)
        issues = [f for f in findings if f.get("issue") == "LIST_NO_INDENT"]
        print(f"(dry-run) Would fix {len(issues)} list paragraph(s) missing indentation")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    new_doc = re.sub(r"<w:p[ >].*?</w:p>", fix_para, doc_xml, flags=re.DOTALL)

    if fixes == 0:
        print("No indentation issues found.")
        return 0

    # Write back
    new_entries = {"word/document.xml": new_doc.encode("utf-8")}
    tmp = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path, "r") as zin:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = new_entries.get(item.filename, zin.read(item.filename))
                zout.writestr(item, data)
    tmp.replace(path)
    print(f"Fixed {fixes} paragraph(s) — added missing <w:ind> based on numbering definitions")

    # Verify
    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
    remaining = [f for f in audit_paragraphs(doc_xml) if f.get("issue") == "LIST_NO_INDENT"]
    print(f"Post-fix: {len(remaining)} list paragraph(s) still missing indent")
    return 0


# ------------ document review (spatial 2D model) --------

# Twip constants
TWIPS_PER_INCH = 1440
TWIPS_PER_PT = 20
DEFAULT_LINE_HEIGHT = 240  # 12pt in twips
DEFAULT_FONT_SIZE_HALF_PTS = 24  # 12pt in half-points

SIG_KEYWORDS = {"in witness whereof", "by:", "printed name:", "title:", "date:"}
HEADER_STYLES = {"Title", "Subtitle", "Heading1", "Heading2", "Heading3"}


def _extract_page_geometry(doc_xml: str) -> dict:
    """Extract page size and margins from section properties."""
    pw_m = re.search(r'<w:pgSz[^>]*w:w="(\d+)"', doc_xml)
    ph_m = re.search(r'<w:pgSz[^>]*w:h="(\d+)"', doc_xml)
    ml_m = re.search(r'<w:pgMar[^>]*w:left="(\d+)"', doc_xml)
    mr_m = re.search(r'<w:pgMar[^>]*w:right="(\d+)"', doc_xml)
    mt_m = re.search(r'<w:pgMar[^>]*w:top="(\d+)"', doc_xml)
    mb_m = re.search(r'<w:pgMar[^>]*w:bottom="(\d+)"', doc_xml)
    pw = int(pw_m.group(1)) if pw_m else 12240
    ph = int(ph_m.group(1)) if ph_m else 15840
    ml = int(ml_m.group(1)) if ml_m else 1440
    mr = int(mr_m.group(1)) if mr_m else 1440
    mt = int(mt_m.group(1)) if mt_m else 1440
    mb = int(mb_m.group(1)) if mb_m else 1440
    return {
        "page_w": pw, "page_h": ph,
        "margin_l": ml, "margin_r": mr, "margin_t": mt, "margin_b": mb,
        "text_w": pw - ml - mr,
        "text_h": ph - mt - mb,
        "text_w_inches": (pw - ml - mr) / TWIPS_PER_INCH,
    }


def _extract_tables(doc_xml: str) -> list[dict]:
    """Extract table structure for spatial analysis."""
    tables = []
    for tbl_m in re.finditer(r"<w:tbl>(.*?)</w:tbl>", doc_xml, re.DOTALL):
        tbl = tbl_m.group(1)
        cols = [int(c) for c in re.findall(r'<w:gridCol w:w="(\d+)"', tbl)]
        rows = []
        for row_m in re.finditer(r"<w:tr[^>]*>(.*?)</w:tr>", tbl, re.DOTALL):
            cells = []
            for cell_m in re.finditer(r"<w:tc>(.*?)</w:tc>", row_m.group(1), re.DOTALL):
                text = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", cell_m.group(1)))
                cells.append(text)
            rows.append(cells)
        # Detect signature table
        is_sig = False
        all_text = " ".join(c for row in rows for c in row).lower()
        if any(kw in all_text for kw in ("printed name:", "by:", "title:")):
            is_sig = True
        # Check borders
        has_visible_border = bool(re.search(r'<w:top w:val="single"', tbl))
        tables.append({
            "start": tbl_m.start(), "end": tbl_m.end(),
            "cols": cols, "col_count": len(cols), "total_w": sum(cols),
            "rows": rows, "row_count": len(rows),
            "is_signature": is_sig, "has_visible_border": has_visible_border,
        })
    return tables


def _classify_paragraph(text: str, style: str, jc: str, index: int, total: int) -> str:
    """Classify a paragraph's semantic role."""
    tl = text.strip().lower()
    if not tl:
        return "spacer"
    if style in HEADER_STYLES or (jc == "center" and index < 6):
        return "header"
    if jc == "right" and index < 3:
        return "doc-number"
    if any(tl.startswith(kw) for kw in ("this work order", "this agreement", "whereas", "this amendment")):
        return "preamble"
    if any(kw in tl for kw in SIG_KEYWORDS):
        return "signature"
    if tl.startswith("contractor:") or tl.startswith("owner:") or tl.startswith("vendor:"):
        return "contact-block"
    return "body"


def _compute_spatial_model(doc_xml: str, numbering_xml: str | None) -> dict:
    """Build a 2D spatial model of the document. Every element gets XY coordinates."""
    geo = _extract_page_geometry(doc_xml)
    tables = _extract_tables(doc_xml)

    # Build numId -> indent lookup
    indent_lookup: dict[tuple[str, str], tuple[int, int]] = {}
    if numbering_xml:
        num_info = audit_numbering(numbering_xml)
        abs_map = {nm["numId"]: nm["abstractNumId"] for nm in num_info["nums"]}
        for ab in num_info["abstractNums"]:
            for lvl in ab["levels"]:
                for nm_id, abs_id in abs_map.items():
                    if abs_id == ab["abstractNumId"] and lvl["left"] is not None:
                        indent_lookup[(nm_id, lvl["ilvl"])] = (lvl["left"], lvl["hanging"] or 0)

    # Detect section breaks — each section can have different margins/columns
    sections = []
    # Final section properties at end of <w:body>
    final_sect = re.search(r"<w:sectPr>(.*?)</w:sectPr>\s*</w:body>", doc_xml, re.DOTALL)
    # Mid-document section breaks (inside paragraphs)
    for sect_m in re.finditer(r"<w:p[ >](.*?)<w:sectPr>(.*?)</w:sectPr>(.*?)</w:p>", doc_xml, re.DOTALL):
        sect_props = sect_m.group(2)
        s_ml = re.search(r'<w:pgMar[^>]*w:left="(\d+)"', sect_props)
        s_mr = re.search(r'<w:pgMar[^>]*w:right="(\d+)"', sect_props)
        s_pw = re.search(r'<w:pgSz[^>]*w:w="(\d+)"', sect_props)
        s_type = re.search(r'<w:type w:val="([^"]*)"', sect_props)
        sections.append({
            "pos": sect_m.start(),
            "type": s_type.group(1) if s_type else "nextPage",
            "margin_l": int(s_ml.group(1)) if s_ml else geo["margin_l"],
            "margin_r": int(s_mr.group(1)) if s_mr else geo["margin_r"],
            "page_w": int(s_pw.group(1)) if s_pw else geo["page_w"],
        })

    elements = []
    y_cursor = geo["margin_t"]
    current_section = 0

    for i, m in enumerate(re.finditer(r"<w:p[ >](.*?)</w:p>", doc_xml, re.DOTALL)):
        # Check if we've crossed a section break — update geometry
        while current_section < len(sections) and m.start() > sections[current_section]["pos"]:
            s = sections[current_section]
            geo["margin_l"] = s["margin_l"]
            geo["margin_r"] = s["margin_r"]
            geo["page_w"] = s["page_w"]
            geo["text_w"] = s["page_w"] - s["margin_l"] - s["margin_r"]
            geo["text_w_inches"] = geo["text_w"] / TWIPS_PER_INCH
            if s["type"] == "nextPage":
                y_cursor = geo["margin_t"]  # new page resets Y
            current_section += 1
        inner = m.group(1)
        text = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", inner))
        ppr_m = re.search(r"<w:pPr>(.*?)</w:pPr>", inner, re.DOTALL)
        ppr = ppr_m.group(1) if ppr_m else ""

        # Extract properties
        jc_m = re.search(r'<w:jc w:val="([^"]*)"', ppr)
        jc = jc_m.group(1) if jc_m else "left"
        style_m = re.search(r'<w:pStyle w:val="([^"]*)"', ppr)
        style = style_m.group(1) if style_m else ""
        numid_m = re.search(r'<w:numId w:val="(\d+)"', ppr)
        ilvl_m = re.search(r'<w:ilvl w:val="(\d+)"', ppr)
        numid = numid_m.group(1) if numid_m else None
        ilvl = ilvl_m.group(1) if ilvl_m else "0"

        # Indentation
        ind_m = re.search(r"<w:ind\s+([^/]*)/?>" , ppr)
        ind_left = 0
        ind_hanging = 0
        ind_first = 0
        if ind_m:
            attrs = ind_m.group(1)
            l_m = re.search(r'w:left="(\d+)"', attrs)
            h_m = re.search(r'w:hanging="(\d+)"', attrs)
            f_m = re.search(r'w:firstLine="(\d+)"', attrs)
            ind_left = int(l_m.group(1)) if l_m else 0
            ind_hanging = int(h_m.group(1)) if h_m else 0
            ind_first = int(f_m.group(1)) if f_m else 0

        # Spacing
        sp_m = re.search(r"<w:spacing\s+([^/]*)/?>" , ppr)
        sp_before = 0
        sp_after = 0
        if sp_m:
            sb_m = re.search(r'w:before="(\d+)"', sp_m.group(1))
            sa_m = re.search(r'w:after="(\d+)"', sp_m.group(1))
            sp_before = int(sb_m.group(1)) if sb_m else 0
            sp_after = int(sa_m.group(1)) if sa_m else 0

        # Font size from rPr
        sz_m = re.search(r'<w:sz w:val="(\d+)"', inner)
        font_size_half_pts = int(sz_m.group(1)) if sz_m else DEFAULT_FONT_SIZE_HALF_PTS
        line_h = font_size_half_pts * TWIPS_PER_PT // 2  # approximate line height

        # Compute X positions
        # First line: left margin + indent_left - hanging + firstLine
        first_line_x = geo["margin_l"] + ind_left - ind_hanging + ind_first
        # Continuation lines: left margin + indent_left
        wrap_line_x = geo["margin_l"] + ind_left

        # Expected indent from numbering
        expected_left = None
        expected_hanging = None
        if numid:
            key = (numid, ilvl)
            if key in indent_lookup:
                expected_left, expected_hanging = indent_lookup[key]

        # Compute expected wrap position if numbering should apply
        expected_wrap_x = None
        if expected_left is not None:
            expected_wrap_x = geo["margin_l"] + expected_left

        # Available width for text
        avail_w = geo["text_w"] - ind_left
        # Approximate char count before wrap (assuming ~120 twips per char at 12pt)
        chars_per_line = max(1, avail_w // 120) if avail_w > 0 else 80
        would_wrap = len(text) > chars_per_line

        # Classify
        total_paras = len(re.findall(r"<w:p[ >]", doc_xml))
        section = _classify_paragraph(text, style, jc, i, total_paras)

        y_cursor += sp_before

        elem = {
            "index": i, "xml_start": m.start(),
            "text": text, "text_len": len(text),
            "section": section, "style": style, "jc": jc,
            "numId": numid, "ilvl": ilvl,
            "ind_left": ind_left, "ind_hanging": ind_hanging, "ind_first": ind_first,
            "expected_left": expected_left, "expected_hanging": expected_hanging,
            "sp_before": sp_before, "sp_after": sp_after,
            "font_size_pt": font_size_half_pts / 2,
            "x_first_line": first_line_x, "x_wrap_line": wrap_line_x,
            "x_expected_wrap": expected_wrap_x,
            "y": y_cursor,
            "would_wrap": would_wrap,
            "avail_width_inches": avail_w / TWIPS_PER_INCH,
        }
        elements.append(elem)
        # Advance Y cursor
        lines = max(1, len(text) // chars_per_line + 1) if text else 1
        y_cursor += lines * line_h + sp_after

    return {"geometry": geo, "tables": tables, "elements": elements, "indent_lookup": indent_lookup}


def _generate_findings(model: dict) -> list[dict]:
    """Analyze the spatial model and generate review findings."""
    findings = []
    fid = 0
    geo = model["geometry"]
    elements = model["elements"]
    tables = model["tables"]

    for elem in elements:
        # --- WRAP: List paragraph without proper indentation ---
        if elem["numId"] and elem["ind_left"] == 0 and elem["ind_hanging"] == 0 and elem["ind_first"] == 0:
            fid += 1
            expected = ""
            if elem["expected_left"] is not None:
                expected = f' Expected: left={elem["expected_left"]}, hanging={elem["expected_hanging"]}.'
            findings.append({
                "id": f"R{fid:02d}", "category": "WRAP", "severity": "high",
                "para_index": elem["index"],
                "x_wrap": elem["x_wrap_line"], "x_expected": elem["x_expected_wrap"],
                "message": (
                    f'Paragraph #{elem["index"]}: List item (numId={elem["numId"]}, level {elem["ilvl"]}) '
                    f'has no indentation. Wrapped text will start at X={elem["x_wrap_line"]} twips '
                    f'(left margin) instead of proper list indent.{expected}'
                ),
                "text_preview": elem["text"][:60],
                "fix": {
                    "type": "add_indent",
                    "left": elem["expected_left"] or 720,
                    "hanging": elem["expected_hanging"] or 360,
                },
            })

        # --- WRAP: List paragraph indent doesn't match numbering definition ---
        elif (elem["numId"] and elem["expected_left"] is not None
              and elem["ind_left"] != 0
              and elem["ind_left"] != elem["expected_left"]):
            fid += 1
            findings.append({
                "id": f"R{fid:02d}", "category": "WRAP", "severity": "medium",
                "para_index": elem["index"],
                "message": (
                    f'Paragraph #{elem["index"]}: List indent mismatch. '
                    f'Has left={elem["ind_left"]} but numbering definition says left={elem["expected_left"]}. '
                    f'Wrap position off by {abs(elem["ind_left"] - elem["expected_left"])} twips '
                    f'({abs(elem["ind_left"] - elem["expected_left"]) / TWIPS_PER_INCH:.2f}").'
                ),
                "text_preview": elem["text"][:60],
                "fix": {
                    "type": "adjust_indent",
                    "left": elem["expected_left"],
                    "hanging": elem["expected_hanging"],
                },
            })

    # --- SIG: Signature table checks ---
    for tbl in tables:
        if not tbl["is_signature"]:
            continue
        # Equal column widths
        if tbl["col_count"] == 2:
            c1, c2 = tbl["cols"]
            if abs(c1 - c2) > 100:  # more than ~0.07" difference
                fid += 1
                findings.append({
                    "id": f"R{fid:02d}", "category": "SIG-WIDTH", "severity": "medium",
                    "message": (
                        f'Signature table columns are unequal: {c1} + {c2} twips '
                        f'({c1/TWIPS_PER_INCH:.2f}" + {c2/TWIPS_PER_INCH:.2f}"). '
                        f'Should be equal for balanced presentation.'
                    ),
                    "fix": {
                        "type": "equalize_sig_cols",
                        "target_each": geo["text_w"] // 2,
                    },
                })
        # Total width vs text width
        diff = abs(tbl["total_w"] - geo["text_w"])
        if diff > 200:  # more than ~0.14" off
            fid += 1
            findings.append({
                "id": f"R{fid:02d}", "category": "SIG-TOTAL", "severity": "low",
                "message": (
                    f'Signature table width ({tbl["total_w"]} twips = {tbl["total_w"]/TWIPS_PER_INCH:.2f}") '
                    f'differs from text body width ({geo["text_w"]} twips = {geo["text_w"]/TWIPS_PER_INCH:.2f}") '
                    f'by {diff} twips ({diff/TWIPS_PER_INCH:.2f}").'
                ),
                "fix": None,  # informational
            })
        # Visible borders on signature table
        if tbl["has_visible_border"]:
            fid += 1
            findings.append({
                "id": f"R{fid:02d}", "category": "SIG-BORDER", "severity": "medium",
                "message": "Signature table has visible borders. Signature tables are conventionally borderless.",
                "fix": {"type": "remove_sig_borders"},
            })

    # --- JUST: Mixed justification in body ---
    body_paras = [e for e in elements if e["section"] == "body" and e["text"].strip()]
    if body_paras:
        jc_values = set(e["jc"] for e in body_paras)
        if len(jc_values) > 1:
            fid += 1
            counts = {}
            for e in body_paras:
                counts[e["jc"]] = counts.get(e["jc"], 0) + 1
            majority = max(counts, key=counts.get)
            outliers = [e["index"] for e in body_paras if e["jc"] != majority]
            findings.append({
                "id": f"R{fid:02d}", "category": "JUST-MIXED", "severity": "low",
                "message": (
                    f'Body text has mixed justification: {dict(counts)}. '
                    f'Majority is "{majority}". '
                    f'Outlier paragraphs: {outliers[:5]}{"..." if len(outliers) > 5 else ""}.'
                ),
                "fix": None,  # needs human judgment
            })

    # --- SPACE: Consecutive empty paragraphs ---
    for idx in range(len(elements) - 1):
        if (elements[idx]["section"] == "spacer"
            and idx + 1 < len(elements)
            and elements[idx + 1]["section"] == "spacer"):
            fid += 1
            findings.append({
                "id": f"R{fid:02d}", "category": "SPACE-EXCESSIVE", "severity": "low",
                "para_index": elements[idx]["index"],
                "message": (
                    f'Consecutive empty paragraphs at #{elements[idx]["index"]} and '
                    f'#{elements[idx+1]["index"]}. Consider using spacing-after instead.'
                ),
                "fix": None,  # cosmetic
            })

    return findings


def cmd_review(args):
    """Review document for business presentation anomalies using 2D spatial analysis."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("review is docx-only")
        return 2

    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
        num_xml = None
        if "word/numbering.xml" in z.namelist():
            num_xml = z.read("word/numbering.xml").decode("utf-8", errors="replace")

    model = _compute_spatial_model(doc_xml, num_xml)
    findings = _generate_findings(model)
    geo = model["geometry"]

    # Print document geometry
    print(f"=== Document Review: {path.name} ===")
    print(f"Page: {geo['page_w']/TWIPS_PER_INCH:.1f}\" x {geo['page_h']/TWIPS_PER_INCH:.1f}\"  "
          f"Margins: L={geo['margin_l']/TWIPS_PER_INCH:.2f}\" R={geo['margin_r']/TWIPS_PER_INCH:.2f}\" "
          f"T={geo['margin_t']/TWIPS_PER_INCH:.2f}\" B={geo['margin_b']/TWIPS_PER_INCH:.2f}\"")
    print(f"Text area: {geo['text_w_inches']:.2f}\" wide")
    print(f"Elements: {len(model['elements'])} paragraphs, {len(model['tables'])} table(s)")
    sig_tables = [t for t in model["tables"] if t["is_signature"]]
    if sig_tables:
        t = sig_tables[0]
        print(f"Signature table: {t['col_count']} cols, {t['row_count']} rows, "
              f"width={t['total_w']/TWIPS_PER_INCH:.2f}\"")

    # Print spatial layout summary
    print(f"\n=== Spatial Layout (X positions in inches from left edge) ===")
    for elem in model["elements"]:
        if not elem["text"].strip() and elem["section"] == "spacer":
            continue  # skip blank spacers for readability
        section_tag = f"[{elem['section']:<12s}]"
        x_first = elem["x_first_line"] / TWIPS_PER_INCH
        x_wrap = elem["x_wrap_line"] / TWIPS_PER_INCH
        y_pos = elem["y"] / TWIPS_PER_INCH
        wrap_flag = " WRAPS" if elem["would_wrap"] else ""
        num_flag = f" numId={elem['numId']}" if elem["numId"] else ""
        anomaly = ""
        if elem["numId"] and elem["x_expected_wrap"] and elem["x_wrap_line"] != elem["x_expected_wrap"]:
            anomaly = f" ** MISALIGNED: wrap@{x_wrap:.2f}\" should be @{elem['x_expected_wrap']/TWIPS_PER_INCH:.2f}\" **"
        print(f"  #{elem['index']:2d} {section_tag} Y={y_pos:5.2f}\" X=[{x_first:.2f}\"->{x_wrap:.2f}\"] "
              f"jc={elem['jc']:<6s}{num_flag}{wrap_flag}{anomaly}  "
              f"{elem['text'][:50]!r}")

    # Print findings
    if not findings:
        print(f"\n=== No presentation issues found ===")
    else:
        high = [f for f in findings if f["severity"] == "high"]
        med = [f for f in findings if f["severity"] == "medium"]
        low = [f for f in findings if f["severity"] == "low"]
        print(f"\n=== Findings: {len(findings)} total ({len(high)} high, {len(med)} medium, {len(low)} low) ===")
        for f in findings:
            sev = {"high": "!!!", "medium": " ! ", "low": "   "}[f["severity"]]
            fix_note = ""
            if f.get("fix"):
                fix_note = "\n      FIX: " + json.dumps(f["fix"])
            preview = ""
            if f.get("text_preview"):
                preview = f"\n      Text: {f['text_preview']!r}"
            print(f"\n  [{f['id']}] {sev} {f['category']} — {f['message']}{preview}{fix_note}")

    # Write full model + findings to JSON if requested
    if args.json_out:
        output = {
            "file": str(path),
            "geometry": geo,
            "tables": [{k: v for k, v in t.items() if k != "rows"} for t in model["tables"]],
            "element_count": len(model["elements"]),
            "findings": findings,
        }
        Path(args.json_out).write_text(json.dumps(output, indent=2, default=str), encoding="utf-8")
        print(f"\nFull report: {args.json_out}")

    print(f"\nTo apply fixes: review approved findings, then run review-fix with finding IDs.")
    return 0


def cmd_review_fix(args):
    """Apply specific approved fixes from a review. Takes comma-separated finding IDs."""
    path = Path(args.file)
    if file_kind(path) != ".docx":
        print("review-fix is docx-only")
        return 2

    approved_ids = set(fid.strip().upper() for fid in args.fix_ids.split(","))

    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
        num_xml = None
        if "word/numbering.xml" in z.namelist():
            num_xml = z.read("word/numbering.xml").decode("utf-8", errors="replace")

    model = _compute_spatial_model(doc_xml, num_xml)
    findings = _generate_findings(model)

    # Filter to approved findings that have fixes
    to_fix = [f for f in findings if f["id"] in approved_ids and f.get("fix")]
    skipped = [fid for fid in approved_ids if not any(f["id"] == fid and f.get("fix") for f in findings)]

    if skipped:
        print(f"Skipping {len(skipped)} IDs (not found or no auto-fix): {skipped}")
    if not to_fix:
        print("No applicable fixes to apply.")
        return 1

    if args.dry_run:
        print(f"(dry-run) Would apply {len(to_fix)} fix(es):")
        for f in to_fix:
            print(f"  {f['id']}: {f['fix']['type']} — {f['message'][:80]}")
        return 0

    backup = make_backup(path)
    print(f"Backup: {backup}")

    applied = 0

    # Apply indent fixes (most common)
    indent_fixes = [f for f in to_fix if f["fix"]["type"] in ("add_indent", "adjust_indent")]
    if indent_fixes:
        # Build a map of paragraph index -> desired indent
        para_indent_map = {}
        for f in indent_fixes:
            para_indent_map[f["para_index"]] = (f["fix"]["left"], f["fix"].get("hanging", 0))

        para_idx = 0

        def fix_para_indent(m):
            nonlocal para_idx, applied
            full = m.group(0)
            current_idx = para_idx
            para_idx += 1
            if current_idx not in para_indent_map:
                return full
            left, hanging = para_indent_map[current_idx]
            indent_xml = f'<w:ind w:left="{left}" w:hanging="{hanging}"/>'
            ppr_m = re.search(r"<w:pPr>(.*?)</w:pPr>", full, re.DOTALL)
            if not ppr_m:
                # No pPr — add one
                # Insert after <w:p...>
                insert = f"<w:pPr>{indent_xml}</w:pPr>"
                if full.startswith("<w:p>"):
                    full = "<w:p>" + insert + full[len("<w:p>"):]
                else:
                    close = full.index(">") + 1
                    full = full[:close] + insert + full[close:]
                applied += 1
                return full
            ppr_content = ppr_m.group(1)
            # Remove existing indent if present
            ppr_content = re.sub(r"<w:ind[^/]*/>\s*", "", ppr_content)
            # Add new indent after numPr if present, else at end
            numpr_end = ppr_content.find("</w:numPr>")
            if numpr_end != -1:
                ppr_content = ppr_content[:numpr_end + len("</w:numPr>")] + indent_xml + ppr_content[numpr_end + len("</w:numPr>"):]
            else:
                ppr_content += indent_xml
            full = full.replace(ppr_m.group(0), f"<w:pPr>{ppr_content}</w:pPr>")
            applied += 1
            return full

        doc_xml = re.sub(r"<w:p[ >].*?</w:p>", fix_para_indent, doc_xml, flags=re.DOTALL)

    # Write back
    new_entries = {"word/document.xml": doc_xml.encode("utf-8")}
    tmp = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path, "r") as zin:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = new_entries.get(item.filename, zin.read(item.filename))
                zout.writestr(item, data)
    tmp.replace(path)
    print(f"Applied {applied} fix(es)")

    # Re-run review to show remaining issues
    with zipfile.ZipFile(path) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
        num_xml = None
        if "word/numbering.xml" in z.namelist():
            num_xml = z.read("word/numbering.xml").decode("utf-8", errors="replace")
    model = _compute_spatial_model(doc_xml, num_xml)
    remaining = _generate_findings(model)
    print(f"Post-fix: {len(remaining)} finding(s) remain")
    return 0


# ------------ deep inspect ---------------

def cmd_inspect_deep(args):
    """Full structural analysis: SDTs, numbering, styles, images, relationships."""
    path = Path(args.file)
    kind = file_kind(path)
    print(f"File: {path}  ({kind}, {path.stat().st_size:,} bytes)")

    report: dict = {"file": str(path), "kind": kind, "size": path.stat().st_size}

    with zipfile.ZipFile(path) as z:
        all_parts = z.namelist()
        text_xml = text_parts(z, kind)
        print(f"Total parts: {len(all_parts)}")
        print(f"Text-bearing parts: {len(text_xml)}")
        report["total_parts"] = len(all_parts)
        report["text_parts"] = text_xml

        if kind == ".docx":
            # SDTs
            doc_xml = z.read("word/document.xml").decode("utf-8", errors="replace")
            sdts = find_sdts_in_xml(doc_xml)
            print(f"\nContent Controls (SDTs): {len(sdts)}")
            report["sdts"] = sdts
            for s in sdts:
                tag = s["tag"] or "(no tag)"
                print(f"  [{s['type']}] tag={tag}  content={s['content'][:40]!r}")

            # Numbering
            if "word/numbering.xml" in all_parts:
                num_xml = z.read("word/numbering.xml").decode("utf-8", errors="replace")
                num_info = audit_numbering(num_xml)
                print(f"\nNumbering definitions: {len(num_info['abstractNums'])} abstract, {len(num_info['nums'])} instances")
                report["numbering"] = num_info
            else:
                print("\nNo numbering.xml (no lists)")
                report["numbering"] = None

            # Paragraph stats
            findings = audit_paragraphs(doc_xml)
            list_paras = [f for f in findings if f.get("numId")]
            issues = [f for f in findings if f.get("issue")]
            print(f"\nParagraphs: {len(findings)} total, {len(list_paras)} list items, {len(issues)} issues")
            report["para_count"] = len(findings)
            report["list_para_count"] = len(list_paras)
            report["issues"] = issues

            # Styles
            if "word/styles.xml" in all_parts:
                styles_xml = z.read("word/styles.xml").decode("utf-8", errors="replace")
                style_names = re.findall(r'<w:style[^>]*w:styleId="([^"]*)"', styles_xml)
                print(f"\nStyles defined: {len(style_names)}")
                report["style_count"] = len(style_names)

            # Images
            images = [n for n in all_parts if n.startswith("word/media/")]
            print(f"\nEmbedded images: {len(images)}")
            report["image_count"] = len(images)

            # Relationships
            if "word/_rels/document.xml.rels" in all_parts:
                rels_xml = z.read("word/_rels/document.xml.rels").decode("utf-8", errors="replace")
                hyperlinks = re.findall(r'Type="[^"]*hyperlink"[^>]*Target="([^"]*)"', rels_xml)
                print(f"Hyperlinks: {len(hyperlinks)}")
                report["hyperlink_count"] = len(hyperlinks)

            # Yellow-highlighted runs (DCFG placeholders)
            yellow_runs = re.findall(r'<w:highlight w:val="yellow"/>\s*</w:rPr>\s*<w:t[^>]*>([^<]*)</w:t>', doc_xml)
            print(f"\nYellow-highlighted runs (DCFG placeholders): {len(yellow_runs)}")
            for yr in yellow_runs:
                print(f"  {yr!r}")
            report["yellow_placeholders"] = yellow_runs

        elif kind == ".xlsx":
            if "xl/sharedStrings.xml" in all_parts:
                ss = z.read("xl/sharedStrings.xml").decode("utf-8", errors="replace")
                count_m = re.search(r'uniqueCount="(\d+)"', ss)
                print(f"\nShared strings: {count_m.group(1) if count_m else 'unknown'}")

            sheets = [n for n in all_parts if n.startswith("xl/worksheets/sheet")]
            print(f"Worksheets: {len(sheets)}")
            report["sheet_count"] = len(sheets)

        elif kind == ".pptx":
            slides = [n for n in all_parts if n.startswith("ppt/slides/slide") and n.endswith(".xml")]
            print(f"\nSlides: {len(slides)}")
            report["slide_count"] = len(slides)
            notes = [n for n in all_parts if n.startswith("ppt/notesSlides/")]
            print(f"Notes slides: {len(notes)}")

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
        print(f"\nFull report: {args.json_out}")

    backup = latest_backup(path)
    if backup:
        print(f"\nLatest backup: {backup.name}")
    return 0


# ---------------- CLI ----------------

def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="OOXML editor for .docx / .xlsx / .pptx")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("inspect", help="List parts and basic info")
    sp.add_argument("file")
    sp.set_defaults(func=cmd_inspect)

    sp = sub.add_parser("find", help="Find text + report run-split status")
    sp.add_argument("file")
    sp.add_argument("pattern")
    sp.set_defaults(func=cmd_find)

    sp = sub.add_parser("replace", help="Replace one string")
    sp.add_argument("file")
    sp.add_argument("old")
    sp.add_argument("new")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_replace)

    sp = sub.add_parser("replace-map", help="Replace many strings from JSON map")
    sp.add_argument("file")
    sp.add_argument("map")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_replace_map)

    sp = sub.add_parser("cell", help="Set xlsx cell value (Sheet1!A1)")
    sp.add_argument("file")
    sp.add_argument("address")
    sp.add_argument("value")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_cell)

    sp = sub.add_parser("backup", help="Make a backup without editing")
    sp.add_argument("file")
    sp.set_defaults(func=cmd_backup)

    sp = sub.add_parser("restore", help="Restore latest backup")
    sp.add_argument("file")
    sp.set_defaults(func=cmd_restore)

    # SDT commands
    sp = sub.add_parser("sdt-list", help="List all content controls (SDTs) in a .docx")
    sp.add_argument("file")
    sp.add_argument("--json", dest="json_out", help="Write full results to JSON file")
    sp.set_defaults(func=cmd_sdt_list)

    sp = sub.add_parser("sdt-find", help="Find SDT by tag name")
    sp.add_argument("file")
    sp.add_argument("tag")
    sp.set_defaults(func=cmd_sdt_find)

    sp = sub.add_parser("sdt-replace", help="Replace SDT content by tag")
    sp.add_argument("file")
    sp.add_argument("tag")
    sp.add_argument("new_text")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_sdt_replace)

    sp = sub.add_parser("sdt-add", help="Add inline SDT after text match")
    sp.add_argument("file")
    sp.add_argument("after_text", help="Text to insert SDT after")
    sp.add_argument("tag", help="SDT tag value")
    sp.add_argument("placeholder", help="Placeholder text shown in SDT")
    sp.add_argument("--alias", help="SDT alias (defaults to tag)")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_sdt_add)

    # Formatting commands
    sp = sub.add_parser("format-audit", help="Audit paragraph indentation, numbering, styles")
    sp.add_argument("file")
    sp.add_argument("--json", dest="json_out", help="Write full audit to JSON file")
    sp.set_defaults(func=cmd_format_audit)

    sp = sub.add_parser("format-list-audit", help="Audit numbering.xml + paragraph cross-refs")
    sp.add_argument("file")
    sp.add_argument("--json", dest="json_out", help="Write results to JSON file")
    sp.set_defaults(func=cmd_format_list_audit)

    sp = sub.add_parser("format-fix-indent", help="Fix list paragraphs missing indentation")
    sp.add_argument("file")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_format_fix_indent)

    # Document review (spatial 2D model)
    sp = sub.add_parser("review", help="Review document for presentation anomalies (2D spatial analysis)")
    sp.add_argument("file")
    sp.add_argument("--json", dest="json_out", help="Write full model + findings to JSON file")
    sp.set_defaults(func=cmd_review)

    sp = sub.add_parser("review-fix", help="Apply approved fixes from review (comma-separated IDs)")
    sp.add_argument("file")
    sp.add_argument("fix_ids", help="Comma-separated finding IDs to fix (e.g. R01,R03,R05)")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_review_fix)

    # Deep inspection
    sp = sub.add_parser("inspect-deep", help="Full structural analysis (SDTs, numbering, styles, images)")
    sp.add_argument("file")
    sp.add_argument("--json", dest="json_out", help="Write full report to JSON file")
    sp.set_defaults(func=cmd_inspect_deep)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
