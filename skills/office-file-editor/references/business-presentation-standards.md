# Business Presentation Standards — Document Review Rules

How to evaluate whether a business document (contract, work order, agreement, amendment) is well-presented. These rules drive the `review` command.

## Philosophy

Assume the document author's intent is correct. The review looks for **anomalies** — places where the XML produces a visual result that doesn't match the structure's implied intent. A signature block that uses a 2-column table is correct by design; a signature block where the columns are different widths is an anomaly.

## Document Sections (Heuristic Detection)

### 1. Header Block
- **Detection:** First N paragraphs that are center-justified (`jc=center`) or right-justified (`jc=right`)
- **Conventions:**
  - Document number/reference: right-justified
  - Title/subtitle: centered, often bold
  - Empty paragraphs between title lines are spacers — OK but should be consistent height

### 2. Preamble / Recital
- **Detection:** Paragraphs starting with "This work order", "This agreement", "WHEREAS"
- **Conventions:**
  - Should be justified (`jc=both`) or left-aligned
  - First-line indent of 0.5" (720 twips) is standard for legal
  - Consistent spacing throughout

### 3. Body / Numbered Sections
- **Detection:** Paragraphs with `<w:numPr>` or text starting with "1.", "2.", etc.
- **Conventions:**
  - Every list paragraph MUST have `<w:ind>` matching its numbering level
  - Continuation lines (wrapped text) MUST align with the text start, NOT the bullet/number
  - Sub-items must be indented further than parent items
  - Consistent spacing between items

### 4. Contact Information Block
- **Detection:** "Contractor:", "Owner:", address-like text, phone/email patterns
- **Conventions:**
  - Labeled fields should align vertically (using tabs or consistent indent)
  - Address block should be indented from the label
  - Consistent formatting within the block

### 5. Signature Block
- **Detection:** "IN WITNESS WHEREOF", "By:", "Printed Name:", "Title:", "Date:", signature lines
- **Conventions:**
  - Two-column table for dual-signature (Customer + Contractor)
  - Columns should be EQUAL width
  - Table width should match or be close to text body width
  - Table should have NO visible borders (signature tables are invisible)
  - "By:" lines should have consistent underline length
  - Labels ("Printed Name:", "Title:", "Date:") should be consistent between columns
  - Table should be positioned at the bottom of the content, after "IN WITNESS WHEREOF"

### 6. Tables (Data)
- **Detection:** `<w:tbl>` elements that aren't signature blocks
- **Conventions:**
  - Column widths should sum to text body width (or close)
  - Header row should be bold or styled differently
  - Consistent cell padding
  - If table has borders, they should be consistent (all cells same border style)

## Anomaly Categories

### A. Wrap Alignment (WRAP)
A line that wraps to the next line should continue at the SAME horizontal position as the first word of the first line (not the bullet/number). If `<w:ind>` is missing on a list paragraph, the wrapped text jumps to the page margin.

**Detection:** Paragraph has `<w:numPr>` but no `<w:ind>`, OR `<w:ind>` left value doesn't match the numbering level definition.

**Fix:** Add or correct `<w:ind w:left="X" w:hanging="Y"/>` based on the numbering.xml level definition.

### B. Signature Block Issues (SIG)
- **SIG-WIDTH**: Columns not equal width
- **SIG-TOTAL**: Table width doesn't match text body width
- **SIG-BORDER**: Visible borders on signature table
- **SIG-ALIGN**: Cell content not consistently aligned
- **SIG-MISSING**: Missing expected elements (no "By:" line, no "Title:" line)
- **SIG-ORPHAN**: Signature block paragraphs outside of a table (should be in table)

### C. Spacing Anomalies (SPACE)
- **SPACE-INCONSISTENT**: Different before/after spacing on paragraphs within the same section
- **SPACE-EXCESSIVE**: Multiple empty paragraphs used as spacers (better: use spacing-after)
- **SPACE-MISSING**: No space between sections that should have visual separation

### D. Justification Issues (JUST)
- **JUST-MIXED**: Body text paragraphs mixing left and justified in the same section
- **JUST-HEADER**: Header/title paragraphs not centered
- **JUST-LEGAL**: Legal body text should typically be justified (`both`)

### E. Indent Issues (INDENT)
- **INDENT-MISSING**: List paragraph without indentation (= WRAP issue)
- **INDENT-INCONSISTENT**: Paragraphs at same logical level with different indent values
- **INDENT-ORPHAN**: Indented paragraph not part of any list (manual indent that should be a list)

### F. Font/Style Issues (STYLE)
- **STYLE-MIXED**: Different fonts within what should be uniform body text
- **STYLE-SIZE**: Unexpected font size change within a section

## Review Output Format

Each finding is a numbered suggestion:

```
[R01] WRAP — Paragraph #11: List item (numId=2, level 0) has no indentation.
      Wrapped text will snap to left margin instead of aligning with first-line text.
      FIX: Add <w:ind w:left="720" w:hanging="360"/> to match numbering definition.

[R02] SIG-WIDTH — Signature table: columns are 4680+4320 twips (unequal).
      Should be 4680+4680 for balanced dual-signature presentation.
      FIX: Set second gridCol to w:w="4680".

[R03] SPACE-EXCESSIVE — Paragraphs #3, #5, #10 are empty spacer paragraphs.
      Consider using spacing-after on the preceding paragraph instead.
      FIX: Optional — cosmetic improvement only.
```

Priority: WRAP and SIG issues are presentation-breaking. SPACE and JUST are cosmetic. STYLE issues are informational.

## Fix Workflow

1. `review` outputs numbered findings
2. User reviews and approves specific fixes: "fix R01, R02"
3. `review-fix` applies only the approved fixes, surgically
4. Post-fix verification: re-run `review` to confirm issue count decreased
