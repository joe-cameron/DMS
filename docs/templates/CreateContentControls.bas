' =============================================================
' DCFG Template Content Control Converter
' =============================================================
' STEP 1: Open a template .doc/.html file in Word
' STEP 2: Run ConvertTableToContentControls
'         - Reads column 2 (Tag/Control Name) from the table
'         - Inserts a Plain Text Content Control for each tag
'         - Sets both Title and Tag to the value from column 2
' STEP 3: Save As .docx
' STEP 4: Upload to SharePoint DCFG_Templates library
' =============================================================

Sub ConvertTableToContentControls()

    Dim doc As Document
    Dim tbl As Table
    Dim r As Long
    Dim tagName As String
    Dim fieldLabel As String
    Dim cc As ContentControl

    Set doc = ActiveDocument

    ' Verify document has a table
    If doc.Tables.Count = 0 Then
        MsgBox "No table found in this document. Open a template field map first.", vbExclamation
        Exit Sub
    End If

    Set tbl = doc.Tables(1)

    ' Clear the table and replace with content controls
    ' First, collect all tag names from column 2 (skip header row)
    Dim tags() As String
    Dim labels() As String
    Dim count As Long
    count = tbl.Rows.Count - 1 ' minus header

    If count < 1 Then
        MsgBox "Table has no data rows.", vbExclamation
        Exit Sub
    End If

    ReDim tags(1 To count)
    ReDim labels(1 To count)

    For r = 2 To tbl.Rows.Count
        ' Clean cell text (remove end-of-cell markers)
        labels(r - 1) = CleanCellText(tbl.Cell(r, 1).Range.Text)
        tags(r - 1) = CleanCellText(tbl.Cell(r, 2).Range.Text)
    Next r

    ' Delete the table
    tbl.Delete

    ' Build the document with content controls
    Dim rng As Range
    Set rng = doc.Content
    rng.Collapse Direction:=wdCollapseStart

    ' Add title
    rng.InsertAfter "DCFG Template — Content Control Map" & vbCr
    rng.Paragraphs(1).Style = doc.Styles("Heading 1")

    Set rng = doc.Content
    rng.Collapse Direction:=wdCollapseEnd
    rng.InsertAfter vbCr

    ' Insert each field label followed by its content control
    Dim i As Long
    For i = 1 To count
        Set rng = doc.Content
        rng.Collapse Direction:=wdCollapseEnd

        ' Insert label as bold text
        rng.InsertAfter labels(i) & ": "
        rng.Font.Bold = True

        ' Move to end and insert content control
        Set rng = doc.Content
        rng.Collapse Direction:=wdCollapseEnd

        Set cc = doc.ContentControls.Add(wdContentControlText, rng)
        cc.Title = tags(i)
        cc.Tag = tags(i)
        cc.SetPlaceholderText , , "[" & tags(i) & "]"

        ' Add line break after
        Set rng = doc.Content
        rng.Collapse Direction:=wdCollapseEnd
        rng.InsertAfter vbCr
    Next i

    MsgBox count & " content controls created successfully!" & vbCr & vbCr & _
           "Next steps:" & vbCr & _
           "1. File > Save As > .docx" & vbCr & _
           "2. Upload to SharePoint DCFG_Templates", vbInformation

End Sub

' Alt version: keeps the table layout but adds content controls IN column 2
Sub ConvertTableInPlace()

    Dim doc As Document
    Dim tbl As Table
    Dim r As Long
    Dim tagName As String
    Dim cc As ContentControl

    Set doc = ActiveDocument

    If doc.Tables.Count = 0 Then
        MsgBox "No table found.", vbExclamation
        Exit Sub
    End If

    Set tbl = doc.Tables(1)

    For r = 2 To tbl.Rows.Count
        tagName = CleanCellText(tbl.Cell(r, 2).Range.Text)

        If Len(tagName) > 0 Then
            ' Clear column 2 cell
            tbl.Cell(r, 2).Range.Delete

            ' Insert content control in column 2
            Dim cellRng As Range
            Set cellRng = tbl.Cell(r, 2).Range
            cellRng.Collapse Direction:=wdCollapseStart

            Set cc = doc.ContentControls.Add(wdContentControlText, cellRng)
            cc.Title = tagName
            cc.Tag = tagName
            cc.SetPlaceholderText , , "[" & tagName & "]"
        End If
    Next r

    MsgBox "Content controls inserted in table column 2." & vbCr & _
           "Save As .docx when ready.", vbInformation

End Sub

Private Function CleanCellText(ByVal txt As String) As String
    ' Remove Word table cell end markers (Chr(13) + Chr(7))
    txt = Replace(txt, Chr(13), "")
    txt = Replace(txt, Chr(7), "")
    txt = Trim(txt)
    CleanCellText = txt
End Function
