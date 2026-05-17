# SpreadsheetML Reference — Excel XML Guide

Reference for editing .xlsx files at the XML level. ECMA-376 Part 1.

## Package Structure

```
xl/workbook.xml              — workbook structure (sheet list, defined names)
xl/sharedStrings.xml         — shared string table (most cell text)
xl/styles.xml                — cell styles (number formats, fonts, fills, borders)
xl/theme/theme1.xml          — theme (colors, fonts)
xl/worksheets/sheet1.xml     — per-sheet data (cells, formulas, row/col sizing)
xl/worksheets/sheet2.xml     — additional sheets
xl/tables/table1.xml         — structured table definitions
xl/_rels/workbook.xml.rels   — workbook relationships
xl/worksheets/_rels/sheet1.xml.rels — per-sheet relationships (hyperlinks, drawings)
[Content_Types].xml          — MIME type registry
docProps/core.xml            — metadata
```

## Shared Strings (`xl/sharedStrings.xml`)

Excel stores string cell values in a shared table. Cells reference strings by index.

```xml
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
     count="5" uniqueCount="4">
  <si><t>Name</t></si>           <!-- index 0 -->
  <si><t>Address</t></si>        <!-- index 1 -->
  <si><t>Acme Corp</t></si>      <!-- index 2 -->
  <si>                            <!-- index 3: rich text -->
    <r><rPr><b/></rPr><t>Bold</t></r>
    <r><t> Normal</t></r>
  </si>
</sst>
```

**CRITICAL:** Changing a string in `sharedStrings.xml` changes EVERY cell that references that index. For single-cell edits, use openpyxl.

## Worksheet (`xl/worksheets/sheet1.xml`)

```xml
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetViews>
    <sheetView tabSelected="1" workbookViewId="0">
      <selection activeCell="A1" sqref="A1"/>
    </sheetView>
  </sheetViews>
  <sheetFormatPr defaultRowHeight="15"/>
  <cols>
    <col min="1" max="1" width="20" customWidth="1"/>
    <col min="2" max="2" width="30" customWidth="1"/>
  </cols>
  <sheetData>
    <row r="1" spans="1:3">
      <c r="A1" t="s"><v>0</v></c>       <!-- string: index 0 in sharedStrings -->
      <c r="B1" t="s"><v>1</v></c>       <!-- string: index 1 -->
    </row>
    <row r="2" spans="1:3">
      <c r="A2" t="s"><v>2</v></c>       <!-- string: "Acme Corp" -->
      <c r="B2"><v>42</v></c>            <!-- number: 42 -->
      <c r="C2" s="3"><v>45000</v></c>   <!-- number with style 3 (maybe date format) -->
    </row>
    <row r="3" spans="1:3">
      <c r="A3" t="str"><f>A1&amp;" "&amp;B1</f><v>Name Address</v></c>  <!-- formula -->
      <c r="B3" t="inlineStr"><is><t>Inline text</t></is></c>  <!-- inline string (rare) -->
    </row>
  </sheetData>
</worksheet>
```

## Cell Types

| `t` attribute | Meaning | `<v>` contains |
|---------------|---------|----------------|
| `s` | Shared string | Index into sharedStrings.xml |
| (none) | Number | Numeric value |
| `str` | Formula string | Calculated text value |
| `b` | Boolean | `0` or `1` |
| `e` | Error | Error code (`#REF!`, `#VALUE!`, etc.) |
| `inlineStr` | Inline string | `<is><t>text</t></is>` instead of `<v>` |

## Cell Style Reference (`s` attribute)

`<c r="A1" s="3">` — the `s` attribute references an index in `xl/styles.xml`:

```xml
<styleSheet>
  <numFmts>
    <numFmt numFmtId="164" formatCode="mm/dd/yyyy"/>
  </numFmts>
  <fonts>
    <font><sz val="11"/><name val="Calibri"/></font>       <!-- index 0 -->
    <font><b/><sz val="11"/><name val="Calibri"/></font>   <!-- index 1 (bold) -->
  </fonts>
  <fills>
    <fill><patternFill patternType="none"/></fill>         <!-- index 0 -->
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFFF00"/></patternFill></fill>  <!-- index 1 (yellow) -->
  </fills>
  <borders>
    <border><!-- thin borders --></border>
  </borders>
  <cellXfs>  <!-- THE STYLE TABLE — index by position -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>   <!-- index 0: default -->
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0"/>   <!-- index 1: bold -->
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0"/> <!-- index 2: date format -->
    <xf numFmtId="4" fontId="0" fillId="1" borderId="0"/>   <!-- index 3: number + yellow fill -->
  </cellXfs>
</styleSheet>
```

## Named Ranges / Defined Names

```xml
<!-- In xl/workbook.xml -->
<definedNames>
  <definedName name="BudgetTotal">Sheet1!$C$100</definedName>
  <definedName name="AllLocations">Sheet1!$A$2:$D$500</definedName>
  <definedName name="_xlnm.Print_Area" localSheetId="0">Sheet1!$A$1:$F$50</definedName>
</definedNames>
```

## Conditional Formatting

```xml
<conditionalFormatting sqref="A1:A100">
  <cfRule type="cellIs" dxfId="0" priority="1" operator="greaterThan">
    <formula>1000</formula>
  </cfRule>
</conditionalFormatting>
```

## Structured Tables

```xml
<!-- xl/tables/table1.xml -->
<table id="1" name="LocationList" displayName="LocationList" ref="A1:D10" totalsRowShown="0">
  <autoFilter ref="A1:D10"/>
  <tableColumns count="4">
    <tableColumn id="1" name="Location"/>
    <tableColumn id="2" name="Address"/>
    <tableColumn id="3" name="City"/>
    <tableColumn id="4" name="State"/>
  </tableColumns>
  <tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" showLastColumn="0" showRowStripes="1"/>
</table>
```

## Edit Safety Rules

1. **Never edit sharedStrings for single-cell changes** — use openpyxl instead
2. **Preserve cell style references** (`s` attribute) — losing them strips formatting
3. **Update `count` and `uniqueCount`** in `<sst>` after adding/removing shared strings
4. **Keep formula `<v>` values** — Word recalculates on open, but other tools may not
5. **Row spans must be accurate** — `spans="1:5"` must cover all cells in the row
6. **Don't remove empty rows/cells** — Excel expects contiguous row numbers in some contexts
