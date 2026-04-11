"""
Generate Word-compatible HTML files for each DCFG template.
Each file has a two-column table: Field Label | Content Control Name
Open in Word, run VBA macro, save as .docx, upload to SharePoint.
"""

import os

TEMPLATES = [
    {
        "filename": "Bancroft_Blanket_Work_Order",
        "title": "Bancroft Blanket Work Order",
        "sharepoint_file": "BANCROFT_BLANKET_WORKORDER_TEMPLATE.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Contractor Name", "contract_contractor_name"),
            ("Description of Work", "contract_description_of_work"),
            ("Contract End Date", "contract_end_date"),
            ("Contract Fee", "contract_fee"),
            ("Owner City", "contract_owner_city"),
            ("Owner Contact", "contract_owner_contact"),
            ("Owner Email", "contract_owner_email"),
            ("Owner Phone", "contract_owner_phone"),
            ("Owner State", "contract_owner_state"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Contract Start Date", "contract_start_date"),
            ("Contract Type", "contract_type"),
            ("Property Name", "property_name"),
            ("Vendor Address", "vendor_address"),
            ("Vendor Email", "vendor_email"),
            ("Vendor Payment Terms", "vendor_payment_terms"),
            ("Vendor Phone", "vendor_phone"),
            ("Vendor Primary Contact", "vendor_primary_contact"),
            ("Vendor Signer Title", "vendor_signer_title"),
        ],
    },
    {
        "filename": "Bancroft_Work_Order",
        "title": "Bancroft Work Order",
        "sharepoint_file": "Bancroft_Work_Order.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Contractor Name", "contract_contractor_name"),
            ("Description of Work", "contract_description_of_work"),
            ("Contract End Date", "contract_end_date"),
            ("Contract Fee", "contract_fee"),
            ("Owner City", "contract_owner_city"),
            ("Owner Contact", "contract_owner_contact"),
            ("Owner Email", "contract_owner_email"),
            ("Owner Phone", "contract_owner_phone"),
            ("Owner State", "contract_owner_state"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Contract Start Date", "contract_start_date"),
            ("Contract Type", "contract_type"),
            ("Property Name", "property_name"),
            ("Vendor Address", "vendor_address"),
            ("Vendor Email", "vendor_email"),
            ("Vendor Payment Terms", "vendor_payment_terms"),
            ("Vendor Phone", "vendor_phone"),
            ("Vendor Primary Contact", "vendor_primary_contact"),
            ("Vendor Signer Title", "vendor_signer_title"),
        ],
    },
    {
        "filename": "Decades_Work_Order",
        "title": "Decades Work Order",
        "sharepoint_file": "Decades_Work_Order.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Contractor Name", "contract_contractor_name"),
            ("Description of Work", "contract_description_of_work"),
            ("Contract End Date", "contract_end_date"),
            ("Contract Fee", "contract_fee"),
            ("Owner City", "contract_owner_city"),
            ("Owner Contact", "contract_owner_contact"),
            ("Owner Email", "contract_owner_email"),
            ("Owner Phone", "contract_owner_phone"),
            ("Owner State", "contract_owner_state"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Contract Start Date", "contract_start_date"),
            ("Contract Type", "contract_type"),
            ("Property Name", "property_name"),
            ("Vendor Address", "vendor_address"),
            ("Vendor Email", "vendor_email"),
            ("Vendor Payment Terms", "vendor_payment_terms"),
            ("Vendor Phone", "vendor_phone"),
            ("Vendor Primary Contact", "vendor_primary_contact"),
            ("Vendor Signer Title", "vendor_signer_title"),
        ],
    },
    {
        "filename": "Bancroft_Work_Order_Amendment",
        "title": "Bancroft Work Order Amendment",
        "sharepoint_file": "Bancroft_Work_Order_Amendment.docx",
        "fields": [
            ("Amendment Sequence", "contract_amendment_sequence"),
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Contractor Name", "contract_contractor_name"),
            ("Description of Service", "contract_description_of_service"),
            ("Description of Work", "contract_description_of_work"),
            ("Contract End Date", "contract_end_date"),
            ("Contract Fee", "contract_fee"),
            ("Owner City", "contract_owner_city"),
            ("Owner Contact", "contract_owner_contact"),
            ("Owner Email", "contract_owner_email"),
            ("Owner Phone", "contract_owner_phone"),
            ("Owner State", "contract_owner_state"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("PO Number", "contract_po_number"),
            ("Contract Start Date", "contract_start_date"),
            ("Work Category", "contract_work_category"),
            ("Property Name", "property_name"),
            ("Vendor Address", "vendor_address"),
            ("Vendor Email", "vendor_email"),
            ("Vendor Phone", "vendor_phone"),
            ("Vendor Primary Contact", "vendor_primary_contact"),
            ("Vendor Signer Title", "vendor_signer_title"),
        ],
    },
    {
        "filename": "Bancroft_Blanket_Work_Order_Amendment",
        "title": "Bancroft Blanket Work Order Amendment",
        "sharepoint_file": "Bancroft_Blanket_Work_Order_Amendment.docx",
        "fields": [
            ("Amendment Sequence", "contract_amendment_sequence"),
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Contractor Name", "contract_contractor_name"),
            ("Description of Service", "contract_description_of_service"),
            ("Description of Work", "contract_description_of_work"),
            ("Contract End Date", "contract_end_date"),
            ("Contract Fee", "contract_fee"),
            ("Owner City", "contract_owner_city"),
            ("Owner Contact", "contract_owner_contact"),
            ("Owner Email", "contract_owner_email"),
            ("Owner Phone", "contract_owner_phone"),
            ("Owner State", "contract_owner_state"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("PO Number", "contract_po_number"),
            ("Contract Start Date", "contract_start_date"),
            ("Work Category", "contract_work_category"),
            ("Property Name", "property_name"),
            ("Vendor Address", "vendor_address"),
            ("Vendor Email", "vendor_email"),
            ("Vendor Phone", "vendor_phone"),
            ("Vendor Primary Contact", "vendor_primary_contact"),
            ("Vendor Signer Title", "vendor_signer_title"),
        ],
    },
    {
        "filename": "Decades_Work_Order_Amendment",
        "title": "Decades Work Order Amendment",
        "sharepoint_file": "Decades_Work_Order_Amendment.docx",
        "fields": [
            ("Amendment Sequence", "contract_amendment_sequence"),
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Contractor Name", "contract_contractor_name"),
            ("Description of Service", "contract_description_of_service"),
            ("Description of Work", "contract_description_of_work"),
            ("Contract End Date", "contract_end_date"),
            ("Contract Fee", "contract_fee"),
            ("Owner City", "contract_owner_city"),
            ("Owner Contact", "contract_owner_contact"),
            ("Owner Email", "contract_owner_email"),
            ("Owner Phone", "contract_owner_phone"),
            ("Owner State", "contract_owner_state"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("PO Number", "contract_po_number"),
            ("Contract Start Date", "contract_start_date"),
            ("Work Category", "contract_work_category"),
            ("Property Name", "property_name"),
            ("Vendor Address", "vendor_address"),
            ("Vendor Email", "vendor_email"),
            ("Vendor Phone", "vendor_phone"),
            ("Vendor Primary Contact", "vendor_primary_contact"),
            ("Vendor Signer Title", "vendor_signer_title"),
        ],
    },
    {
        "filename": "Decades_MSA",
        "title": "Decades Management Services Agreement",
        "sharepoint_file": "Decades_Management_Services_Agreement.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Owner City", "contract_owner_city"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Customer President Name", "customer_president_name"),
            ("MSA Effective Date", "msa_effective_date"),
            ("MSA Expiration Date", "msa_expiration_date"),
        ],
    },
    {
        "filename": "Exhibit_A_Basic_Platform_Package_A",
        "title": "Exhibit A \u2014 Basic Platform Package A",
        "sharepoint_file": "Exhibit_A_Basic_Platform_Package_A.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Owner City", "contract_owner_city"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Customer President Name", "customer_president_name"),
            ("MSA Effective Date", "msa_effective_date"),
            ("MSA Expiration Date", "msa_expiration_date"),
        ],
    },
    {
        "filename": "Exhibit_A_Concierge_Package_B",
        "title": "Exhibit A \u2014 Concierge Package B",
        "sharepoint_file": "Exhibit_A_Concierge_Package_B.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Owner City", "contract_owner_city"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Customer President Name", "customer_president_name"),
            ("MSA Effective Date", "msa_effective_date"),
            ("MSA Expiration Date", "msa_expiration_date"),
        ],
    },
    {
        "filename": "Exhibit_A_Optimized_Package_C",
        "title": "Exhibit A \u2014 Optimized Package C",
        "sharepoint_file": "Exhibit_A_Optimized_Package_C.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
            ("Owner City", "contract_owner_city"),
            ("Owner Street", "contract_owner_street"),
            ("Owner Title", "contract_owner_title"),
            ("Customer President Name", "customer_president_name"),
            ("MSA Effective Date", "msa_effective_date"),
            ("MSA Expiration Date", "msa_expiration_date"),
        ],
    },
    {
        "filename": "Exhibit_B_Location_List",
        "title": "Exhibit B \u2014 Location List",
        "sharepoint_file": "Exhibit_B_Location_List.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Property Name", "property_name"),
            ("MSA Effective Date", "msa_effective_date"),
        ],
    },
    {
        "filename": "Exhibit_C_Fee_Schedule",
        "title": "Exhibit C \u2014 Fee Schedule",
        "sharepoint_file": "Exhibit_C_Fee_Schedule.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Membership Quantity", "membership_qty"),
            ("Membership Rate", "membership_rate"),
            ("Onboarding Quantity", "onboarding_qty"),
            ("Onboarding Rate", "onboarding_rate"),
            ("Onboarding Total", "onboarding_total"),
            ("MSA Effective Date", "msa_effective_date"),
        ],
    },
    {
        "filename": "Exhibit_D_Insurance_Requirements",
        "title": "Exhibit D \u2014 Insurance Requirements",
        "sharepoint_file": "Exhibit_D_Insurance_Requirements.docx",
        "fields": [
            ("Client Name", "contract_client_name"),
            ("Contractor Legal Name", "contract_contractor_legal_name"),
        ],
    },
]

HTML_TEMPLATE = """<html xmlns:o="urn:schemas-microsoft-com:office:office"
xmlns:w="urn:schemas-microsoft-com:office:word"
xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta charset="UTF-8">
<meta name="ProgId" content="Word.Document">
<meta name="Generator" content="DCFG Tag Builder">
<style>
body {{ font-family: Calibri, sans-serif; margin: 1in; }}
h1 {{ font-size: 16pt; color: #1a3a5c; margin-bottom: 4pt; }}
.meta {{ font-size: 9pt; color: #666; margin-bottom: 12pt; }}
table {{ border-collapse: collapse; width: 100%; }}
th {{ background: #1a3a5c; color: white; font-size: 11pt; padding: 6pt 10pt;
     text-align: left; border: 1px solid #1a3a5c; }}
td {{ font-size: 11pt; padding: 5pt 10pt; border: 1px solid #ccc; }}
tr:nth-child(even) td {{ background: #f5f7fa; }}
.tag {{ font-family: Consolas, monospace; color: #2d6a4f; font-weight: bold; }}
.note {{ font-size: 9pt; color: #888; margin-top: 16pt; font-style: italic; }}
</style>
</head>
<body>
<h1>{title}</h1>
<p class="meta">SharePoint file: <b>{sharepoint_file}</b> &mdash; {field_count} fields</p>
<table>
<tr><th>#</th><th>Field Label</th><th>Content Control Name</th></tr>
{rows}
</table>
<p class="note">Open in Word &rarr; Alt+F8 &rarr; ConvertTableToContentControls &rarr; Save As .docx &rarr; Upload to DCFG_Templates</p>
</body>
</html>"""

ROW_TEMPLATE = '<tr><td>{num}</td><td>{label}</td><td class="tag">{tag}</td></tr>'

output_dir = os.path.dirname(os.path.abspath(__file__))

for t in TEMPLATES:
    rows = "\n".join(
        ROW_TEMPLATE.format(num=i + 1, label=label, tag=tag)
        for i, (label, tag) in enumerate(t["fields"])
    )
    html = HTML_TEMPLATE.format(
        title=t["title"],
        sharepoint_file=t["sharepoint_file"],
        field_count=len(t["fields"]),
        rows=rows,
    )
    path = os.path.join(output_dir, f"{t['filename']}.doc")
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  Created: {t['filename']}.doc ({len(t['fields'])} fields)")

print(f"\nDone. {len(TEMPLATES)} template documents created in {output_dir}")
