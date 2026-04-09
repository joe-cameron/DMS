"""
Convert the SPA code review spec markdown into a presentable Word document.

Usage:
    python md-to-docx-spa-review.py

Produces:
    C:\\dcfg\\docs\\superpowers\\specs\\2026-04-09-spa-review-cleanup-design.docx

Styling: DCFG brand palette, IBM Plex Sans body, Fraunces-equivalent (Georgia
fallback) headings, styled tables, code blocks, callout boxes.
"""

import re
import os
from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

SRC = r"C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.md"
OUT = r"C:\dcfg\docs\superpowers\specs\2026-04-09-spa-review-cleanup-design.docx"

# DCFG brand palette (from decades-go-user-manual-standalone.html)
NAVY = RGBColor(0x1B, 0x2A, 0x4A)
BLUE = RGBColor(0x2E, 0x52, 0x95)
SLATE = RGBColor(0x3D, 0x50, 0x80)
MUTED = RGBColor(0x86, 0x95, 0xAA)
GOLD = RGBColor(0xC4, 0xA2, 0x4C)
BORDER = RGBColor(0xD4, 0xD9, 0xE2)
SHADE = RGBColor(0xF8, 0xFA, 0xFC)
TIP_BG = RGBColor(0xED, 0xF1, 0xF8)
WARN_BG = RGBColor(0xFF, 0xF8, 0xE7)
CODE_BG = RGBColor(0xF5, 0xF7, 0xFA)

BODY_FONT = "Segoe UI"   # IBM Plex Sans fallback; Segoe UI is on all Windows
HEAD_FONT = "Georgia"    # Fraunces fallback
MONO_FONT = "Consolas"


def set_cell_shading(cell, color_hex):
    """Apply background color to a table cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), color_hex)
    tc_pr.append(shd)


def set_cell_borders(cell, color_hex="D4D9E2", size=4):
    """Apply 4-sided borders to a table cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        border = OxmlElement(f"w:{edge}")
        border.set(qn("w:val"), "single")
        border.set(qn("w:sz"), str(size))
        border.set(qn("w:color"), color_hex)
        tc_borders.append(border)
    tc_pr.append(tc_borders)


def add_page_break(doc):
    """Insert a page break."""
    p = doc.add_paragraph()
    run = p.add_run()
    run.add_break(WD_BREAK.PAGE)


def setup_document():
    """Create a Document with margins and default styles configured."""
    doc = Document()

    # Margins
    for section in doc.sections:
        section.top_margin = Cm(2.0)
        section.bottom_margin = Cm(2.0)
        section.left_margin = Cm(2.2)
        section.right_margin = Cm(2.2)

    # Normal style
    normal = doc.styles["Normal"]
    normal.font.name = BODY_FONT
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = NAVY
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.25

    # Headings
    for level, size, color, space_before, space_after in [
        (1, 22, NAVY, 18, 8),
        (2, 16, NAVY, 14, 6),
        (3, 13, BLUE, 10, 4),
        (4, 11, SLATE, 8, 3),
    ]:
        style = doc.styles[f"Heading {level}"]
        style.font.name = HEAD_FONT
        style.font.size = Pt(size)
        style.font.color.rgb = color
        style.font.bold = True
        style.paragraph_format.space_before = Pt(space_before)
        style.paragraph_format.space_after = Pt(space_after)
        style.paragraph_format.keep_with_next = True

    return doc


INLINE_CODE = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
ITALIC = re.compile(r"(?<!\*)\*([^*]+)\*(?!\*)")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def add_inline_text(paragraph, text, base_color=None):
    """Add text to a paragraph, respecting inline markdown (code, bold, italic, links)."""
    # Tokenize: split on inline markers in order
    # Simple approach: repeatedly find the earliest match among patterns
    pos = 0
    while pos < len(text):
        # Find next match of any inline marker
        matches = []
        for label, pattern in [("code", INLINE_CODE), ("bold", BOLD), ("italic", ITALIC), ("link", LINK)]:
            m = pattern.search(text, pos)
            if m:
                matches.append((m.start(), label, m))
        if not matches:
            # No more inline markers — plain text rest
            run = paragraph.add_run(text[pos:])
            run.font.name = BODY_FONT
            if base_color:
                run.font.color.rgb = base_color
            break

        # Pick earliest
        matches.sort(key=lambda x: x[0])
        start, label, m = matches[0]
        # Plain text before the match
        if start > pos:
            run = paragraph.add_run(text[pos:start])
            run.font.name = BODY_FONT
            if base_color:
                run.font.color.rgb = base_color
        # Handle the match
        if label == "code":
            run = paragraph.add_run(m.group(1))
            run.font.name = MONO_FONT
            run.font.size = Pt(9.5)
            run.font.color.rgb = BLUE
            # Background shading for inline code is painful in python-docx
            # Leave as colored monospace
        elif label == "bold":
            run = paragraph.add_run(m.group(1))
            run.font.name = BODY_FONT
            run.bold = True
            if base_color:
                run.font.color.rgb = base_color
            else:
                run.font.color.rgb = NAVY
        elif label == "italic":
            run = paragraph.add_run(m.group(1))
            run.font.name = BODY_FONT
            run.italic = True
            if base_color:
                run.font.color.rgb = base_color
        elif label == "link":
            run = paragraph.add_run(m.group(1))
            run.font.name = BODY_FONT
            run.font.color.rgb = BLUE
            run.underline = True
        pos = m.end()


def parse_markdown(md_text):
    """Parse markdown into a list of block tokens.
    Each token is a dict: {"type": "...", "text"/"rows"/"lines"/"level"/"items": ...}
    """
    lines = md_text.splitlines()
    tokens = []
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()

        # Code fence
        if stripped.startswith("```"):
            lang = stripped[3:].strip()
            i += 1
            code_lines = []
            while i < len(lines) and not lines[i].rstrip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            i += 1  # skip closing fence
            tokens.append({"type": "code", "lang": lang, "text": "\n".join(code_lines)})
            continue

        # Horizontal rule
        if stripped == "---":
            tokens.append({"type": "hr"})
            i += 1
            continue

        # Heading
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1))
            text = m.group(2).strip()
            tokens.append({"type": "heading", "level": level, "text": text})
            i += 1
            continue

        # Table (pipe-delimited, at least 2 lines with |---|)
        if stripped.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|?\s*$", lines[i+1]):
            table_lines = [stripped]
            i += 1
            # skip separator
            i += 1
            # collect body rows
            while i < len(lines) and lines[i].strip().startswith("|"):
                table_lines.append(lines[i].strip())
                i += 1
            # Parse
            rows = []
            for tl in table_lines:
                cells = [c.strip() for c in tl.strip("|").split("|")]
                rows.append(cells)
            tokens.append({"type": "table", "rows": rows})
            continue

        # Unordered list
        if re.match(r"^[-*]\s+", stripped):
            items = []
            while i < len(lines) and re.match(r"^[-*]\s+", lines[i].strip()):
                item_text = re.sub(r"^[-*]\s+", "", lines[i].strip())
                items.append(item_text)
                i += 1
            tokens.append({"type": "ul", "items": items})
            continue

        # Ordered list
        if re.match(r"^\d+\.\s+", stripped):
            items = []
            while i < len(lines) and re.match(r"^\d+\.\s+", lines[i].strip()):
                item_text = re.sub(r"^\d+\.\s+", "", lines[i].strip())
                items.append(item_text)
                i += 1
            tokens.append({"type": "ol", "items": items})
            continue

        # Blank line
        if not stripped:
            i += 1
            continue

        # Paragraph — gather consecutive non-special lines
        para_lines = [stripped]
        i += 1
        while i < len(lines):
            nxt = lines[i].rstrip()
            if not nxt:
                break
            if re.match(r"^(#{1,6})\s+", nxt):
                break
            if nxt.startswith("```"):
                break
            if nxt == "---":
                break
            if nxt.startswith("|"):
                break
            if re.match(r"^[-*]\s+", nxt):
                break
            if re.match(r"^\d+\.\s+", nxt):
                break
            para_lines.append(nxt)
            i += 1
        tokens.append({"type": "p", "text": " ".join(para_lines)})

    return tokens


def render_table(doc, rows):
    if not rows:
        return
    table = doc.add_table(rows=len(rows), cols=len(rows[0]))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = True

    for r_idx, row in enumerate(rows):
        for c_idx, cell_text in enumerate(row):
            if c_idx >= len(table.rows[r_idx].cells):
                continue
            cell = table.rows[r_idx].cells[c_idx]
            cell.vertical_alignment = WD_ALIGN_VERTICAL.TOP
            # Clear default paragraph, add formatted one
            cell.text = ""
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            # Inline formatting
            add_inline_text(p, cell_text, base_color=(NAVY if r_idx == 0 else SLATE))
            # Header row styling
            if r_idx == 0:
                set_cell_shading(cell, "1B2A4A")
                for run in p.runs:
                    run.bold = True
                    run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                    run.font.size = Pt(10)
            else:
                # Alternating row shading
                if r_idx % 2 == 0:
                    set_cell_shading(cell, "F8FAFC")
                for run in p.runs:
                    run.font.size = Pt(9.5)
            set_cell_borders(cell)


def render_code_block(doc, text):
    """Render a monospace code block in a shaded single-cell table."""
    table = doc.add_table(rows=1, cols=1)
    cell = table.rows[0].cells[0]
    set_cell_shading(cell, "F5F7FA")
    set_cell_borders(cell, color_hex="D4D9E2")
    cell.text = ""
    for line in text.split("\n"):
        p = cell.add_paragraph()
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.line_spacing = 1.15
        run = p.add_run(line if line else "\u00A0")
        run.font.name = MONO_FONT
        run.font.size = Pt(9)
        run.font.color.rgb = NAVY
    # Remove the initial empty paragraph
    first = cell.paragraphs[0]
    if not first.text:
        first._element.getparent().remove(first._element)
    # Space after the table
    doc.add_paragraph().paragraph_format.space_after = Pt(4)


def render_document(doc, tokens):
    """Walk the token stream and emit into the docx document."""
    for tok in tokens:
        t = tok["type"]

        if t == "heading":
            level = tok["level"]
            # Map markdown heading levels: # -> title, ## -> h1, ### -> h2, etc.
            # We use the doc's built-in heading styles 1-4 for ## through #####
            if level == 1:
                # Title
                p = doc.add_paragraph()
                p.paragraph_format.space_before = Pt(0)
                p.paragraph_format.space_after = Pt(10)
                run = p.add_run(tok["text"])
                run.font.name = HEAD_FONT
                run.font.size = Pt(28)
                run.font.color.rgb = NAVY
                run.bold = True
            else:
                p = doc.add_paragraph(style=f"Heading {min(level-1, 4)}")
                add_inline_text(p, tok["text"])
                # Re-apply color since add_inline_text colors runs individually
                color = [NAVY, NAVY, BLUE, SLATE][min(level-2, 3)]
                for run in p.runs:
                    run.font.color.rgb = color
                    run.bold = True
                    run.font.name = HEAD_FONT

        elif t == "p":
            p = doc.add_paragraph()
            add_inline_text(p, tok["text"])

        elif t == "ul":
            for item in tok["items"]:
                p = doc.add_paragraph(style="List Bullet")
                add_inline_text(p, item)

        elif t == "ol":
            for item in tok["items"]:
                p = doc.add_paragraph(style="List Number")
                add_inline_text(p, item)

        elif t == "table":
            render_table(doc, tok["rows"])
            doc.add_paragraph().paragraph_format.space_after = Pt(4)

        elif t == "code":
            render_code_block(doc, tok["text"])

        elif t == "hr":
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(6)
            p.paragraph_format.space_after = Pt(6)
            p_pr = p._p.get_or_add_pPr()
            p_bdr = OxmlElement("w:pBdr")
            bottom = OxmlElement("w:bottom")
            bottom.set(qn("w:val"), "single")
            bottom.set(qn("w:sz"), "6")
            bottom.set(qn("w:color"), "D4D9E2")
            p_bdr.append(bottom)
            p_pr.append(p_bdr)


def add_cover(doc):
    """Cover page block at the top of the document."""
    # Eyebrow
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(48)
    p.paragraph_format.space_after = Pt(4)
    run = p.add_run("DCFG — CONTRACTING SUITE")
    run.font.name = BODY_FONT
    run.font.size = Pt(9)
    run.font.color.rgb = GOLD
    run.bold = True

    # Title
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    run = p.add_run("SPA Code Review & Cleanup")
    run.font.name = HEAD_FONT
    run.font.size = Pt(34)
    run.font.color.rgb = NAVY
    run.bold = True

    # Subtitle
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(24)
    run = p.add_run("Design Specification")
    run.font.name = HEAD_FONT
    run.font.size = Pt(18)
    run.font.color.rgb = BLUE
    run.italic = True

    # Meta block
    meta = [
        ("Date", "2026-04-09"),
        ("Author", "Joseph Cameron / Claude"),
        ("Status", "Draft — approved by spec-document-reviewer (iteration 2)"),
        ("In scope", "63 files in C:\\DCFG\\spa\\dcfg-shell\\src\\"),
        ("Target", "dmms1.powerappsportals.com (Prod) — external user testing readiness"),
    ]
    table = doc.add_table(rows=len(meta), cols=2)
    table.autofit = False
    for i, (k, v) in enumerate(meta):
        kc = table.rows[i].cells[0]
        vc = table.rows[i].cells[1]
        kc.text = ""
        vc.text = ""
        kp = kc.paragraphs[0]
        vp = vc.paragraphs[0]
        kp.paragraph_format.space_after = Pt(2)
        vp.paragraph_format.space_after = Pt(2)
        kr = kp.add_run(k)
        kr.font.name = BODY_FONT
        kr.font.size = Pt(9)
        kr.bold = True
        kr.font.color.rgb = MUTED
        vr = vp.add_run(v)
        vr.font.name = BODY_FONT
        vr.font.size = Pt(10)
        vr.font.color.rgb = NAVY
        set_cell_borders(kc, color_hex="F8FAFC", size=2)
        set_cell_borders(vc, color_hex="F8FAFC", size=2)

    # Page break
    add_page_break(doc)


def main():
    with open(SRC, "r", encoding="utf-8") as f:
        md = f.read()

    # Strip the markdown's own H1 (we replace with cover)
    md = re.sub(r"^#\s+SPA Code Review & Cleanup — Design Spec\s*\n", "", md, count=1)
    # Strip the leading metadata block until the first ---
    md = re.sub(r"^\*\*Date:\*\*.*?\n\n---\n", "", md, count=1, flags=re.DOTALL)

    doc = setup_document()
    add_cover(doc)

    tokens = parse_markdown(md)
    render_document(doc, tokens)

    # Footer
    section = doc.sections[0]
    footer = section.footer
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("DCFG Contracting Suite — SPA Code Review & Cleanup Design Spec — 2026-04-09")
    run.font.name = BODY_FONT
    run.font.size = Pt(8)
    run.font.color.rgb = MUTED

    doc.save(OUT)
    size_kb = os.path.getsize(OUT) / 1024
    print(f"Wrote: {OUT}")
    print(f"Size : {size_kb:.1f} KB")


if __name__ == "__main__":
    main()
