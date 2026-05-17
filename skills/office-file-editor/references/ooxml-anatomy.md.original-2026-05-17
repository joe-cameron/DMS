# OOXML anatomy — what's inside each Office file

A .docx, .xlsx, or .pptx is a zip archive containing XML files plus media. Open one with any zip tool (7-Zip, `unzip`, Python's `zipfile`) to see the contents. The OOXML standard is ECMA-376 / ISO/IEC 29500.

## .docx (Word)

Common parts:

| Path | What it contains |
|---|---|
| `[Content_Types].xml` | MIME types for each part |
| `_rels/.rels` | Top-level relationships |
| `word/document.xml` | **The main body text — most edits target this** |
| `word/_rels/document.xml.rels` | Relationships from document.xml (links, images) |
| `word/styles.xml` | Style definitions |
| `word/numbering.xml` | List numbering definitions |
| `word/header1.xml`, `header2.xml`, ... | Page headers (one per section) |
| `word/footer1.xml`, `footer2.xml`, ... | Page footers |
| `word/footnotes.xml` | Footnote text |
| `word/endnotes.xml` | Endnote text |
| `word/comments.xml` | Comments |
| `word/settings.xml` | Document-wide settings |
| `word/theme/theme1.xml` | Theme (colors, fonts) |
| `word/media/image1.png`, ... | Embedded images |
| `docProps/core.xml`, `docProps/app.xml` | Document metadata (title, author, last-modified) |

Text-bearing parts that may need editing: `document.xml`, `header*.xml`, `footer*.xml`, `footnotes.xml`, `endnotes.xml`, `comments.xml`.

The text inside `document.xml` looks like:
```xml
<w:p>
  <w:r>
    <w:rPr><w:b/></w:rPr>
    <w:t>Bold text</w:t>
  </w:r>
  <w:r>
    <w:t xml:space="preserve"> normal text</w:t>
  </w:r>
</w:p>
```

`<w:p>` = paragraph. `<w:r>` = run (a span of text with consistent formatting). `<w:t>` = text node within a run.

## .xlsx (Excel)

Common parts:

| Path | What it contains |
|---|---|
| `xl/workbook.xml` | Workbook structure (sheet list, defined names) |
| `xl/sharedStrings.xml` | **String table — most cell text lives here, referenced by index** |
| `xl/worksheets/sheet1.xml`, `sheet2.xml`, ... | Per-sheet content (cells, formulas, formatting refs) |
| `xl/styles.xml` | Cell styles |
| `xl/theme/theme1.xml` | Theme |
| `xl/_rels/workbook.xml.rels` | Workbook relationships |
| `docProps/core.xml`, `app.xml` | Metadata |

Cells in `sheet1.xml` reference shared strings by index:
```xml
<c r="A1" t="s"><v>0</v></c>      <!-- t="s" means string; v=0 is index into sharedStrings -->
<c r="A2"><v>42</v></c>           <!-- numeric, no shared string -->
<c r="A3" t="inlineStr"><is><t>literal</t></is></c>  <!-- inline string, rare -->
```

**Implication:** changing a string in `sharedStrings.xml` changes EVERY cell that references it. For one-cell edits, use `openpyxl` instead — it handles this correctly.

## .pptx (PowerPoint)

Common parts:

| Path | What it contains |
|---|---|
| `ppt/presentation.xml` | Presentation structure (slide order) |
| `ppt/slides/slide1.xml`, `slide2.xml`, ... | **Per-slide content** |
| `ppt/slideLayouts/slideLayout*.xml` | Layout templates (Title, Title+Content, etc.) |
| `ppt/slideMasters/slideMaster*.xml` | Master slides |
| `ppt/notesSlides/notesSlide*.xml` | **Speaker notes** |
| `ppt/theme/theme*.xml` | Themes |
| `ppt/media/image*.png`, `image*.jpg`, ... | Embedded media |

Text in slides looks similar to docx but with `<a:t>` instead of `<w:t>`:
```xml
<p:sp>
  <p:txBody>
    <a:p>
      <a:r>
        <a:rPr lang="en-US"/>
        <a:t>Slide title text</a:t>
      </a:r>
    </a:p>
  </p:txBody>
</p:sp>
```

## Why edits break

OOXML is strict. Common ways to corrupt a file:

1. **Wrong zip compression.** Office expects `ZIP_DEFLATED` for most parts. `ZIP_STORED` (no compression) sometimes works but isn't guaranteed.
2. **Reordering parts.** `[Content_Types].xml` must be first in some Word implementations.
3. **Breaking part references.** Editing `word/document.xml` to remove a `<w:hyperlink r:id="rId5"/>` without updating `word/_rels/document.xml.rels` leaves a dangling reference. Word may open it but with warnings.
4. **Editing binary parts.** `vbaProject.bin`, font files, embedded objects — these are not XML and editing them as text corrupts them silently.
5. **Encoding mismatch.** OOXML XML must be UTF-8 with the BOM-less encoding declaration. Writing UTF-16 or adding a BOM corrupts the file.

The `office_edit.py` script avoids all five by:
- Using `ZIP_DEFLATED`
- Preserving original entry order
- Only modifying the text content of XML parts (never structural parts)
- Refusing to operate on binary files
- Reading and writing as UTF-8 explicitly

## Quick zip inspection from the command line

PowerShell:
```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::OpenRead("C:\path\to\file.docx").Entries | Select-Object Name, Length
```

Python one-liner:
```python
import zipfile; print('\n'.join(zipfile.ZipFile('file.docx').namelist()))
```

Or just rename to `.zip` and double-click — Windows treats it as a regular zip.
