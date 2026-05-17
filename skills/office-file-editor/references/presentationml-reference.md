# PresentationML Reference — PowerPoint XML Guide

Reference for editing .pptx files at the XML level. ECMA-376 Part 1.

## Package Structure

```
ppt/presentation.xml                — presentation structure (slide order, sizes)
ppt/slides/slide1.xml               — per-slide content
ppt/slides/slide2.xml
ppt/slideLayouts/slideLayout1.xml   — layout templates
ppt/slideMasters/slideMaster1.xml   — master slides (global formatting)
ppt/notesSlides/notesSlide1.xml     — speaker notes
ppt/theme/theme1.xml                — theme
ppt/media/                          — images, videos
ppt/_rels/presentation.xml.rels     — relationships
[Content_Types].xml                 — MIME types
```

## Namespace Prefixes

| Prefix | URI | Used for |
|--------|-----|----------|
| `a` | `http://schemas.openxmlformats.org/drawingml/2006/main` | Drawing elements (text, shapes) |
| `p` | `http://schemas.openxmlformats.org/presentationml/2006/main` | Presentation elements |
| `r` | `http://schemas.openxmlformats.org/officeDocument/2006/relationships` | Relationships |

## Slide Structure

```xml
<p:sld xmlns:a="..." xmlns:p="..." xmlns:r="...">
  <p:cSld>
    <p:spTree>                            <!-- shape tree (all content) -->
      <p:nvGrpSpPr>...</p:nvGrpSpPr>     <!-- group shape properties -->
      <p:grpSpPr>...</p:grpSpPr>

      <!-- Text shape -->
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Title 1"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
          <p:nvPr><p:ph type="title"/></p:nvPr>  <!-- placeholder type -->
        </p:nvSpPr>
        <p:spPr/>                          <!-- shape visual properties -->
        <p:txBody>                         <!-- text content -->
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p>                            <!-- paragraph -->
            <a:pPr algn="ctr"/>            <!-- alignment -->
            <a:r>                          <!-- run -->
              <a:rPr lang="en-US" dirty="0"/>
              <a:t>Slide Title Text</a:t>  <!-- text -->
            </a:r>
          </a:p>
        </p:txBody>
      </p:sp>

      <!-- Image shape -->
      <p:pic>
        <p:nvPicPr>
          <p:cNvPr id="3" name="Picture 1"/>
          <p:cNvPicPr/>
          <p:nvPr/>
        </p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rId2"/>         <!-- image reference -->
          <a:stretch><a:fillRect/></a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm>
            <a:off x="0" y="0"/>           <!-- position in EMUs -->
            <a:ext cx="9144000" cy="6858000"/>  <!-- size in EMUs -->
          </a:xfrm>
        </p:spPr>
      </p:pic>
    </p:spTree>
  </p:cSld>
</p:sld>
```

## Text Elements

### Paragraph (`<a:p>`)

```xml
<a:p>
  <a:pPr algn="l" lvl="0">         <!-- alignment: l|ctr|r|just, indent level -->
    <a:buFont typeface="Arial"/>     <!-- bullet font -->
    <a:buChar char="&#8226;"/>       <!-- bullet character -->
    <a:spcBef><a:spcPts val="600"/></a:spcBef>  <!-- space before (hundredths of a point) -->
  </a:pPr>
  <a:r>
    <a:rPr lang="en-US" sz="2400" b="1" i="0" dirty="0">  <!-- 24pt, bold -->
      <a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>
    </a:rPr>
    <a:t>Red bold text</a:t>
  </a:r>
</a:p>
```

### Run Properties (`<a:rPr>`)

| Attribute/Element | Purpose |
|-------------------|---------|
| `sz` | Font size in hundredths of a point (2400 = 24pt) |
| `b="1"` | Bold |
| `i="1"` | Italic |
| `u="sng"` | Underline (sng=single, dbl=double) |
| `lang` | Language code |
| `dirty="0"` | Spell-check flag |
| `<a:solidFill>` | Text color |
| `<a:latin typeface="..."/>` | Font family |
| `<a:hlinkClick r:id="..."/>` | Hyperlink |

## Placeholder Types

The `<p:ph>` element in `<p:nvPr>` identifies placeholder type:

| `type` | Meaning |
|--------|---------|
| `title` | Slide title |
| `body` | Body text |
| `subTitle` | Subtitle |
| `dt` | Date |
| `ftr` | Footer |
| `sldNum` | Slide number |
| `ctrTitle` | Centered title |
| (none) | Generic content |

## Speaker Notes

```xml
<!-- ppt/notesSlides/notesSlide1.xml -->
<p:notes>
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Notes Placeholder 1"/>
          <p:cNvSpPr/>
          <p:nvPr><p:ph type="body" idx="1"/></p:nvPr>
        </p:nvSpPr>
        <p:spPr/>
        <p:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p><a:r><a:rPr lang="en-US"/><a:t>Speaker notes here</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:notes>
```

## Units: EMUs (English Metric Units)

PowerPoint uses EMUs for position and size:
- 1 inch = 914400 EMU
- 1 cm = 360000 EMU
- 1 pt = 12700 EMU

Standard slide size (10" x 7.5"):
- `cx="9144000"` (width)
- `cy="6858000"` (height)

## Edit Safety Rules

1. **Don't change shape IDs** — `<p:cNvPr id="...">` must be unique per slide
2. **Preserve placeholder type** — removing `<p:ph>` disconnects the shape from the layout
3. **Run-splitting applies** — same as .docx; use python-pptx for cross-run edits
4. **Keep `dirty="0"`** — forces spell-check re-run; harmless but prevents green squiggles
5. **EMU precision** — don't approximate; use exact values from the original
6. **Slide relationships** — adding images requires both the `<a:blip>` element and a relationship entry in `ppt/slides/_rels/slide1.xml.rels`
