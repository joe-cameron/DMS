"""
Generate landscape PDF from DCFG screenshots.
One page per screenshot, organized by module.
Requires: pip install fpdf2 Pillow
"""
import os
import sys

try:
    from fpdf import FPDF
except ImportError:
    os.system(f'{sys.executable} -m pip install fpdf2 Pillow')
    from fpdf import FPDF

from PIL import Image

SCREENSHOTS_DIR = 'C:/dcfg/docs/screenshots'
OUTPUT_PDF = 'C:/dcfg/docs/DCFG_Guide_Screenshots.pdf'

# Module groupings — order matters
MODULES = [
    {
        'title': 'Decades Work Order',
        'files': [
            ('decades-wo-step1-customer.png', 'Step 1 - Customer Selection'),
            ('decades-wo-step2-doctype.png', 'Step 2 - Document Type & Details'),
            ('decades-wo-step3-contractor.png', 'Step 3 - Contractor & Signer'),
            ('decades-wo-step4-exhibit-a.png', 'Step 4 - Exhibit A Lines'),
            ('decades-wo-step5-review.png', 'Step 5 - Review & Generate'),
        ]
    },
    {
        'title': 'Bancroft TPA Work Order',
        'files': [
            ('bancroft-wo-step1-customer.png', 'Step 1 - Customer Selection'),
            ('bancroft-wo-step2-doctype.png', 'Step 2 - Document Type & Details'),
            ('bancroft-wo-step3-contractor.png', 'Step 3 - Contractor & Signer'),
            ('bancroft-wo-step4-exhibit-a.png', 'Step 4 - Exhibit A Lines'),
            ('bancroft-wo-step5-review.png', 'Step 5 - Review & Generate'),
        ]
    },
    {
        'title': 'Bancroft TPA Work Order Amendment',
        'files': [
            ('bancroft-amend-step1-customer.png', 'Step 1 - Customer Selection'),
            ('bancroft-amend-step2-doctype.png', 'Step 2 - Parent WO & Amendment'),
            ('bancroft-amend-step3-contractor.png', 'Step 3 - Contractor & Signer'),
            ('bancroft-amend-step4-exhibit-a.png', 'Step 4 - Exhibit A Lines'),
            ('bancroft-amend-step5-review.png', 'Step 5 - Review & Generate'),
        ]
    },
    {
        'title': 'Vendor MSA',
        'files': [
            ('vendor-msa-step1-customer.png', 'Step 1 - Customer Selection'),
            ('vendor-msa-step2-doctype.png', 'Step 2 - Document Type & Details'),
            ('vendor-msa-step3-contractor.png', 'Step 3 - Contractor & Signer'),
            ('vendor-msa-step4-exhibit-a.png', 'Step 4 - Exhibit A Lines'),
            ('vendor-msa-step5-review.png', 'Step 5 - Review & Generate'),
        ]
    },
    {
        'title': 'Sales Proposal',
        'files': [
            ('proposal-step1-packages.png', 'Step 1 - Package Selection'),
            ('proposal-step1-selected.png', 'Step 1 - Package Selected'),
            ('proposal-step2-customer.png', 'Step 2 - Customer & Vendor'),
            ('proposal-step3-pricing.png', 'Step 3 - Pricing & Locations'),
            ('proposal-step4-review.png', 'Step 4 - Review & Generate'),
        ]
    },
]


def build_pdf():
    pdf = FPDF(orientation='L', unit='mm', format='A4')
    pdf.set_auto_page_break(auto=False)

    # Title page
    pdf.add_page()
    pdf.set_font('Helvetica', 'B', 36)
    pdf.set_y(80)
    pdf.cell(0, 20, 'DCFG Contracting Suite', align='C', new_x='LMARGIN', new_y='NEXT')
    pdf.set_font('Helvetica', '', 18)
    pdf.set_text_color(100, 100, 100)
    pdf.cell(0, 12, 'Screen Reference Guide', align='C', new_x='LMARGIN', new_y='NEXT')
    pdf.set_font('Helvetica', '', 12)
    pdf.cell(0, 20, f'Generated {__import__("datetime").date.today().isoformat()}', align='C')

    page_w = 297  # A4 landscape width mm
    page_h = 210  # A4 landscape height mm
    margin = 10
    header_h = 18
    img_max_w = page_w - 2 * margin
    img_max_h = page_h - header_h - 2 * margin

    found = 0
    skipped = 0

    for module in MODULES:
        for filename, label in module['files']:
            filepath = os.path.join(SCREENSHOTS_DIR, filename)
            if not os.path.exists(filepath):
                print(f'  SKIP: {filename} (not found)')
                skipped += 1
                continue

            # Get image dimensions
            with Image.open(filepath) as img:
                iw, ih = img.size

            pdf.add_page()

            # Module + screen header
            pdf.set_font('Helvetica', '', 9)
            pdf.set_text_color(150, 150, 150)
            pdf.cell(0, 6, module['title'], new_x='LMARGIN', new_y='NEXT')

            pdf.set_font('Helvetica', 'B', 14)
            pdf.set_text_color(27, 42, 74)  # navy
            pdf.cell(0, 10, label, new_x='LMARGIN', new_y='NEXT')

            # Scale image to fit
            scale_w = img_max_w / (iw * 0.264583)  # px to mm at 96dpi
            scale_h = img_max_h / (ih * 0.264583)
            scale = min(scale_w, scale_h, 1.0)

            disp_w = iw * 0.264583 * scale
            disp_h = ih * 0.264583 * scale

            # Center horizontally
            x = margin + (img_max_w - disp_w) / 2
            y = margin + header_h

            pdf.image(filepath, x=x, y=y, w=disp_w, h=disp_h)

            print(f'  OK: {filename} — {label}')
            found += 1

    pdf.output(OUTPUT_PDF)
    print(f'\nPDF: {found} pages, {skipped} skipped')
    print(f'Saved to: {OUTPUT_PDF}')


if __name__ == '__main__':
    build_pdf()
