"""
Inject Power Automate-compatible Plain Text Content Controls into a .docx file.
Works by directly manipulating the XML inside the .docx ZIP.

Usage:
  python inject-content-controls.py input.docx output.docx field1 field2 field3 ...

Or import and use programmatically:
  from inject_content_controls import inject_controls
  inject_controls('template.docx', 'output.docx', ['contract_start_date', 'vendor_name'])
"""

import zipfile
import shutil
import sys
import os
import tempfile
from xml.etree import ElementTree as ET

NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
ET.register_namespace('w', NS)

def make_sdt_xml(field_name, placeholder=None):
    """Create a Plain Text Content Control XML element compatible with Power Automate."""
    if placeholder is None:
        placeholder = field_name

    sdt = ET.Element(f'{{{NS}}}sdt')

    # Properties
    sdtPr = ET.SubElement(sdt, f'{{{NS}}}sdtPr')
    alias_el = ET.SubElement(sdtPr, f'{{{NS}}}alias')
    alias_el.set(f'{{{NS}}}val', field_name)
    tag_el = ET.SubElement(sdtPr, f'{{{NS}}}tag')
    tag_el.set(f'{{{NS}}}val', field_name)
    # Plain Text marker — CRITICAL for Power Automate recognition
    ET.SubElement(sdtPr, f'{{{NS}}}text')

    # Content
    sdtContent = ET.SubElement(sdt, f'{{{NS}}}sdtContent')
    p = ET.SubElement(sdtContent, f'{{{NS}}}p')
    r = ET.SubElement(p, f'{{{NS}}}r')
    t = ET.SubElement(r, f'{{{NS}}}t')
    t.text = placeholder

    return sdt


def inject_controls(source_docx, output_docx, fields):
    """Inject content controls into a .docx, replacing any placeholder text matching field names."""

    # Copy source to output
    shutil.copy2(source_docx, output_docx)

    # Read document.xml from the ZIP
    with zipfile.ZipFile(output_docx, 'r') as zin:
        doc_xml_bytes = zin.read('word/document.xml')
        all_files = {item.filename: zin.read(item.filename) for item in zin.infolist()}

    # Parse XML
    tree = ET.fromstring(doc_xml_bytes)

    # Find body
    body = tree.find(f'{{{NS}}}body')
    if body is None:
        print("ERROR: No <w:body> found in document.xml")
        return False

    # Find sectPr (must stay last)
    sect_pr = body.find(f'{{{NS}}}sectPr')

    # Check for existing SDTs and report
    existing_sdts = tree.findall(f'.//{{{NS}}}sdt')
    print(f"Existing content controls: {len(existing_sdts)}")
    for sdt in existing_sdts:
        sdt_pr = sdt.find(f'{{{NS}}}sdtPr')
        if sdt_pr is not None:
            tag = sdt_pr.find(f'{{{NS}}}tag')
            alias = sdt_pr.find(f'{{{NS}}}alias')
            has_text = sdt_pr.find(f'{{{NS}}}text') is not None
            tag_val = tag.get(f'{{{NS}}}val', '?') if tag is not None else '?'
            alias_val = alias.get(f'{{{NS}}}val', '?') if alias is not None else '?'
            print(f"  Tag={tag_val} Alias={alias_val} PlainText={has_text}")

    # Remove all existing SDTs (clean slate)
    for sdt in existing_sdts:
        parent = None
        for p in tree.iter():
            if sdt in list(p):
                parent = p
                break
        if parent is not None:
            parent.remove(sdt)
    print(f"Removed {len(existing_sdts)} existing controls")

    # Inject new controls
    print(f"\nInjecting {len(fields)} content controls:")
    for field_name in fields:
        sdt = make_sdt_xml(field_name)
        if sect_pr is not None:
            # Insert before sectPr
            children = list(body)
            idx = children.index(sect_pr)
            body.insert(idx, sdt)
        else:
            body.append(sdt)
        print(f"  + {field_name}")

    # Serialize back
    new_xml = ET.tostring(tree, encoding='unicode', xml_declaration=False)
    # Add XML declaration
    new_xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + new_xml
    new_xml_bytes = new_xml.encode('utf-8')

    # Write new ZIP
    tmpfd, tmppath = tempfile.mkstemp(suffix='.docx')
    os.close(tmpfd)
    with zipfile.ZipFile(tmppath, 'w', zipfile.ZIP_DEFLATED) as zout:
        for filename, data in all_files.items():
            if filename == 'word/document.xml':
                zout.writestr(filename, new_xml_bytes)
            else:
                zout.writestr(filename, data)

    shutil.move(tmppath, output_docx)
    print(f"\nSaved: {output_docx}")
    return True


# Bancroft Blanket Work Order fields
BANCROFT_BLANKET_FIELDS = [
    'contract_contractor_legal_name',
    'contract_contractor_name',
    'contract_owner_contact',
    'contract_owner_email',
    'contract_owner_phone',
    'contract_owner_title',
    'contract_start_date',
    'vendor_address',
    'vendor_email',
    'vendor_phone',
    'vendor_primary_contact',
    'vendor_signer_title',
]

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python inject-content-controls.py input.docx output.docx [field1 field2 ...]")
        print("If no fields specified, uses Bancroft_Blanket_Work_Order defaults")
        sys.exit(1)

    source = sys.argv[1]
    output = sys.argv[2]
    fields = sys.argv[3:] if len(sys.argv) > 3 else BANCROFT_BLANKET_FIELDS

    if not os.path.exists(source):
        print(f"ERROR: Source file not found: {source}")
        sys.exit(1)

    print(f"Source: {source}")
    print(f"Output: {output}")
    print(f"Fields: {len(fields)}\n")

    success = inject_controls(source, output, fields)
    sys.exit(0 if success else 1)
