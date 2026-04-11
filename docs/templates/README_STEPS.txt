DCFG Template Content Control Pipeline
=======================================

FILES IN THIS FOLDER
--------------------
13 x .doc files     - One per template, two-column tables (Field Label | Control Name)
CreateContentControls.bas - VBA macro module
generate_templates.py     - Script that created the .doc files (re-run if tags change)

STEP-BY-STEP PROCESS
--------------------

STEP 1: IMPORT THE VBA MACRO (one time)
  a. Open Word (any document)
  b. Alt+F11 to open VBA Editor
  c. File > Import File > select CreateContentControls.bas
  d. Close VBA Editor

STEP 2: CONVERT EACH TEMPLATE (repeat for each .doc)
  a. Open the .doc file in Word (e.g. Bancroft_Work_Order.doc)
     - Word opens the HTML table natively
  b. Alt+F8 > select "ConvertTableToContentControls" > Run
     - This reads column 2 and creates Plain Text Content Controls
     - Each control gets Title and Tag set to the control name
  c. ALTERNATIVE: Run "ConvertTableInPlace" to keep the table layout
     with content controls embedded in column 2

STEP 3: SAVE AS .DOCX
  a. File > Save As
  b. Change type to "Word Document (.docx)"
  c. Use the SharePoint filename shown in the document header
     (e.g. BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx)

STEP 4: UPLOAD TO SHAREPOINT
  a. Upload each .docx to the DCFG_Templates library
  b. This replaces the existing template files

STEP 5: UPDATE POWER AUTOMATE ADVANCED SETTINGS
  a. Open the DocGen flow in Power Automate designer
  b. Navigate to Switch_Template > the relevant case
  c. Open the "Populate a Microsoft Word template" action
  d. Select the updated template file from SharePoint
  e. Click "Show all" under Advanced parameters
  f. Each content control now appears as a field
  g. Check each field's checkbox to enable it
  h. For each field, switch to Expression tab and paste:
       outputs('Build_Token_Map')?['tag_name']
     (Use tag_builder.html Flow mode to copy expressions)
  i. Save the flow

TEMPLATE INVENTORY
------------------
Work Orders (22 fields each):
  1. Bancroft_Blanket_Work_Order.doc    -> BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx
  2. Bancroft_Work_Order.doc            -> Bancroft_Work_Order.docx
  3. Decades_Work_Order.doc             -> Decades_Work_Order.docx

Amendments (24 fields each):
  4. Bancroft_Work_Order_Amendment.doc              -> Bancroft_Work_Order_Amendment.docx
  5. Bancroft_Blanket_Work_Order_Amendment.doc      -> Bancroft_Blanket_Work_Order_Amendment.docx
  6. Decades_Work_Order_Amendment.doc               -> Decades_Work_Order_Amendment.docx

MSA + Exhibits:
  7. Decades_MSA.doc                          -> Decades_Management_Services_Agreement.docx  (8 fields)
  8. Exhibit_A_Basic_Platform_Package_A.doc   -> Exhibit_A_Basic_Platform_Package_A.docx      (8 fields)
  9. Exhibit_A_Concierge_Package_B.doc        -> Exhibit_A_Concierge_Package_B.docx           (8 fields)
  10. Exhibit_A_Optimized_Package_C.doc       -> Exhibit_A_Optimized_Package_C.docx           (8 fields)
  11. Exhibit_B_Location_List.doc             -> Exhibit_B_Location_List.docx                 (3 fields)
  12. Exhibit_C_Fee_Schedule.doc              -> Exhibit_C_Fee_Schedule.docx                  (7 fields)
  13. Exhibit_D_Insurance_Requirements.doc    -> Exhibit_D_Insurance_Requirements.docx        (2 fields)
