' =============================================================
' DCFG Batch Content Control Creator
' =============================================================
' Opens each .doc field map, converts the table to content
' controls, saves as _CC.docx, closes. Run once from any
' Word document (Alt+F11 > Import > Alt+F8 > BatchConvert).
'
' Output files go to the same folder as the source .doc files.
' Upload the _CC.docx files to SharePoint DCFG_Templates_Test
' and DCFG_Templates.
' =============================================================

' --- Master mapping: source .doc -> output _CC.docx ---
' Each entry: Array(source_doc_name, output_docx_name)

Private Function GetFileMap() As Variant
    Dim m(0 To 14) As Variant

    ' Work Orders (22 fields each)
    m(0) = Array("Bancroft_Blanket_Work_Order.doc", "Bancroft_Blanket_Work_Order_CC.docx")
    m(1) = Array("Bancroft_Work_Order.doc", "Bancroft_Work_Order_CC.docx")
    m(2) = Array("Decades_Work_Order.doc", "Decades_Work_Order_CC.docx")

    ' Amendments (24 fields each)
    m(3) = Array("Bancroft_Work_Order_Amendment.doc", "Bancroft_Work_Order_Amendment_CC.docx")
    m(4) = Array("Bancroft_Blanket_Work_Order_Amendment.doc", "Bancroft_Blanket_Work_Order_Amendment_CC.docx")
    m(5) = Array("Decades_Work_Order_Amendment.doc", "Decades_Work_Order_Amendment_CC.docx")

    ' MSA (8 fields) - one source, one output
    m(6) = Array("Decades_MSA.doc", "Decades_Vendor_MSA_CC.docx")

    ' Exhibit A variants (8 fields each) - Bancroft active copies
    m(7) = Array("Exhibit_A_Basic_Platform_Package_A.doc", "Bancroft_Exhibit_A_Basic_A_CC.docx")
    m(8) = Array("Exhibit_A_Concierge_Package_B.doc", "Bancroft_Exhibit_A_Concierge_B_CC.docx")
    m(9) = Array("Exhibit_A_Optimized_Package_C.doc", "Bancroft_Exhibit_A_Optimized_C_CC.docx")

    ' Exhibit A - Decades Concierge (same fields, separate DMS record)
    m(10) = Array("Exhibit_A_Concierge_Package_B.doc", "Decades_Exhibit_A_Concierge_B_CC.docx")

    ' Exhibit B (3 fields)
    m(11) = Array("Exhibit_B_Location_List.doc", "Decades_Exhibit_B_Location_List_CC.docx")

    ' Exhibit C (7 fields)
    m(12) = Array("Exhibit_C_Fee_Schedule.doc", "Decades_Exhibit_C_Fee_Schedule_CC.docx")

    ' Exhibit D (2 fields)
    m(13) = Array("Exhibit_D_Insurance_Requirements.doc", "Decades_Exhibit_D_Insurance_CC.docx")

    ' Decades Exhibit A inactive copies (create anyway for completeness)
    m(14) = Array("Exhibit_A_Basic_Platform_Package_A.doc", "Decades_Exhibit_A_Basic_A_CC.docx")

    GetFileMap = m
End Function

Sub BatchConvert()

    Dim srcFolder As String
    Dim fMap As Variant
    Dim i As Long
    Dim srcPath As String
    Dim outPath As String
    Dim doc As Document
    Dim successCount As Long
    Dim failCount As Long
    Dim log As String

    ' Prompt for folder containing the .doc files
    With Application.FileDialog(msoFileDialogFolderPicker)
        .Title = "Select folder containing the .doc field map files"
        .InitialFileName = "C:\dcfg\docs\templates\"
        If .Show = -1 Then
            srcFolder = .SelectedItems(1)
        Else
            MsgBox "Cancelled.", vbInformation
            Exit Sub
        End If
    End With

    If Right(srcFolder, 1) <> "\" Then srcFolder = srcFolder & "\"

    fMap = GetFileMap()
    successCount = 0
    failCount = 0
    log = "DCFG Batch Content Control Creator" & vbCr & String(40, "=") & vbCr & vbCr

    Application.ScreenUpdating = False

    For i = LBound(fMap) To UBound(fMap)
        srcPath = srcFolder & fMap(i)(0)
        outPath = srcFolder & fMap(i)(1)

        ' Check if source exists
        If Dir(srcPath) = "" Then
            log = log & "SKIP: " & fMap(i)(0) & " (not found)" & vbCr
            failCount = failCount + 1
            GoTo NextFile
        End If

        ' Open source .doc
        Set doc = Documents.Open(FileName:=srcPath, ReadOnly:=False, Visible:=False)

        ' Verify it has a table
        If doc.Tables.Count = 0 Then
            log = log & "SKIP: " & fMap(i)(0) & " (no table found)" & vbCr
            doc.Close SaveChanges:=False
            failCount = failCount + 1
            GoTo NextFile
        End If

        ' Convert table to content controls
        Dim tbl As Table
        Set tbl = doc.Tables(1)

        Dim tags() As String
        Dim labels() As String
        Dim rowCount As Long
        rowCount = tbl.Rows.Count - 1 ' skip header

        If rowCount < 1 Then
            log = log & "SKIP: " & fMap(i)(0) & " (empty table)" & vbCr
            doc.Close SaveChanges:=False
            failCount = failCount + 1
            GoTo NextFile
        End If

        ReDim tags(1 To rowCount)
        ReDim labels(1 To rowCount)

        Dim r As Long
        For r = 2 To tbl.Rows.Count
            labels(r - 1) = CleanCell(tbl.Cell(r, 1).Range.Text)
            tags(r - 1) = CleanCell(tbl.Cell(r, 2).Range.Text)
        Next r

        ' Delete table
        tbl.Delete

        ' Clear any remaining content
        doc.Content.Delete

        ' Insert content controls with placeholder text
        Dim rng As Range
        Dim cc As ContentControl
        Dim j As Long

        For j = 1 To rowCount
            Set rng = doc.Content
            rng.Collapse Direction:=wdCollapseEnd

            ' Insert content control
            Set cc = doc.ContentControls.Add(wdContentControlText, rng)
            cc.Title = tags(j)
            cc.Tag = tags(j)
            cc.SetPlaceholderText , , "[" & tags(j) & "]"

            ' Add paragraph break after (except last)
            If j < rowCount Then
                Set rng = doc.Content
                rng.Collapse Direction:=wdCollapseEnd
                rng.InsertAfter vbCr
            End If
        Next j

        ' Save as .docx
        doc.SaveAs2 FileName:=outPath, FileFormat:=wdFormatXMLDocument
        doc.Close SaveChanges:=False

        log = log & "OK: " & fMap(i)(1) & " (" & rowCount & " controls)" & vbCr
        successCount = successCount + 1

NextFile:
    Next i

    Application.ScreenUpdating = True

    log = log & vbCr & String(40, "=") & vbCr
    log = log & "Success: " & successCount & "  |  Failed: " & failCount & vbCr
    log = log & vbCr & "Next steps:" & vbCr
    log = log & "1. Upload all _CC.docx files to SharePoint DCFG_Templates_Test" & vbCr
    log = log & "2. Upload all _CC.docx files to SharePoint DCFG_Templates (prod)" & vbCr
    log = log & "3. Run DMS update script to point records to new files" & vbCr
    log = log & "4. Open Power Automate and select new templates in Switch cases"

    ' Show log
    MsgBox log, vbInformation, "Batch Convert Complete"

    ' Also save log to file
    Dim logPath As String
    logPath = srcFolder & "_batch_convert_log.txt"
    Open logPath For Output As #1
    Print #1, log
    Close #1

End Sub

Private Function CleanCell(ByVal txt As String) As String
    txt = Replace(txt, Chr(13), "")
    txt = Replace(txt, Chr(7), "")
    txt = Trim(txt)
    CleanCell = txt
End Function
