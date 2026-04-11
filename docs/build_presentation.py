"""
DCFG Contracting Suite — Leadership Presentation Generator
Generates master deck + department-specific versions using python-pptx.
Decades branding (Navy #1B2A4A, Amber #D4A017, Green #2D8659).
Screenshot placeholders — capture and drop in after generation.
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
import copy
import os

# ── Brand Colors ──
NAVY = RGBColor(0x1B, 0x2A, 0x4A)
NAVY_MID = RGBColor(0x2E, 0x52, 0x95)
NAVY_PALE = RGBColor(0xED, 0xF1, 0xF8)
AMBER = RGBColor(0xD4, 0xA0, 0x17)
GREEN = RGBColor(0x2D, 0x86, 0x59)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
TEXT_PRIMARY = RGBColor(0x1E, 0x29, 0x3B)
TEXT_SECONDARY = RGBColor(0x47, 0x55, 0x69)
TEXT_MUTED = RGBColor(0x94, 0xA3, 0xB8)
BORDER = RGBColor(0xE2, 0xE8, 0xF0)
PAGE_BG = RGBColor(0xF8, 0xFA, 0xFC)

# ── Dimensions ──
SLIDE_WIDTH = Inches(13.333)
SLIDE_HEIGHT = Inches(7.5)


def set_slide_bg(slide, color):
    bg = slide.background
    fill = bg.fill
    fill.solid()
    fill.fore_color.rgb = color


def add_textbox(slide, left, top, width, height, text, font_size=18,
                color=TEXT_PRIMARY, bold=False, alignment=PP_ALIGN.LEFT,
                font_name="Calibri"):
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(font_size)
    p.font.color.rgb = color
    p.font.bold = bold
    p.font.name = font_name
    p.alignment = alignment
    return txBox


def add_bullet_list(slide, left, top, width, height, items, font_size=16,
                    color=TEXT_PRIMARY, font_name="Calibri"):
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        p.text = item
        p.font.size = Pt(font_size)
        p.font.color.rgb = color
        p.font.name = font_name
        p.space_after = Pt(8)
        p.level = 0
    return txBox


def add_screenshot_placeholder(slide, left, top, width, height, label="Screenshot"):
    """Add a bordered rectangle with label indicating where to insert a screenshot."""
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = NAVY_PALE
    shape.line.color.rgb = BORDER
    shape.line.width = Pt(1.5)

    tf = shape.text_frame
    tf.word_wrap = True
    tf.paragraphs[0].alignment = PP_ALIGN.CENTER

    # Icon-style label
    p = tf.paragraphs[0]
    p.text = f"📷  {label}"
    p.font.size = Pt(14)
    p.font.color.rgb = TEXT_MUTED
    p.font.name = "Calibri"

    # Instruction
    p2 = tf.add_paragraph()
    p2.text = "Right-click → Change Picture → From File"
    p2.font.size = Pt(11)
    p2.font.color.rgb = TEXT_MUTED
    p2.font.name = "Calibri"
    p2.alignment = PP_ALIGN.CENTER

    return shape


def add_callout_box(slide, left, top, width, height, text, font_size=13):
    """Small callout annotation near a screenshot."""
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = WHITE
    shape.line.color.rgb = AMBER
    shape.line.width = Pt(2)

    tf = shape.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(font_size)
    p.font.color.rgb = TEXT_PRIMARY
    p.font.name = "Calibri"
    p.alignment = PP_ALIGN.LEFT
    return shape


def add_nav_stripe(slide):
    """Thin amber accent bar at bottom of slide."""
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(0), Inches(7.2), SLIDE_WIDTH, Inches(0.3)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()


def make_title_slide(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
    set_slide_bg(slide, NAVY)

    # Title
    add_textbox(slide, Inches(1.5), Inches(2.0), Inches(10), Inches(1.5),
                "DCFG Contracting Suite", font_size=44, color=WHITE,
                bold=True, alignment=PP_ALIGN.CENTER)

    # Subtitle
    add_textbox(slide, Inches(1.5), Inches(3.5), Inches(10), Inches(1),
                "Streamlining Proposals, Contracts & Onboarding", font_size=22,
                color=AMBER, alignment=PP_ALIGN.CENTER)

    # Decades branding note
    add_textbox(slide, Inches(1.5), Inches(5.0), Inches(10), Inches(0.5),
                "Decades Property Management", font_size=16,
                color=TEXT_MUTED, alignment=PP_ALIGN.CENTER)

    # Amber stripe
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(4.5), Inches(4.5), Inches(4.3), Inches(0.06)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()


def make_problem_slide(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_slide_bg(slide, WHITE)

    add_textbox(slide, Inches(0.8), Inches(0.5), Inches(10), Inches(0.8),
                "The Challenge", font_size=32, color=NAVY, bold=True)

    # Amber underline
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(0.8), Inches(1.2), Inches(2.5), Inches(0.06)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()

    items = [
        "Proposals built manually — inconsistent formatting, slow turnaround",
        "Contracts tracked in spreadsheets — no visibility into pipeline status",
        "Documents sent without review — no approval gate before delivery",
        "Onboarding managed by email — missed steps, no progress tracking",
        "No single system connecting sales → contracts → delivery → onboarding",
    ]
    add_bullet_list(slide, Inches(0.8), Inches(1.6), Inches(11), Inches(4.5),
                    items, font_size=20, color=TEXT_PRIMARY)

    add_nav_stripe(slide)


def make_journey_slide(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_slide_bg(slide, WHITE)

    add_textbox(slide, Inches(0.8), Inches(0.5), Inches(10), Inches(0.8),
                "One System, One Workflow", font_size=32, color=NAVY, bold=True)

    # Amber underline
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(0.8), Inches(1.2), Inches(3.5), Inches(0.06)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()

    # Flow boxes
    stages = ["Proposal", "Contract", "Send Queue", "Onboarding", "Scheduling"]
    box_width = Inches(2.0)
    box_height = Inches(1.2)
    start_left = Inches(0.8)
    top = Inches(3.0)
    gap = Inches(0.4)

    for i, stage in enumerate(stages):
        left = start_left + i * (box_width + gap)

        box = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, box_width, box_height)
        box.fill.solid()
        box.fill.fore_color.rgb = NAVY if i == 0 else NAVY_PALE
        box.line.color.rgb = NAVY
        box.line.width = Pt(2)

        tf = box.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = stage
        p.font.size = Pt(18)
        p.font.bold = True
        p.font.color.rgb = WHITE if i == 0 else NAVY
        p.font.name = "Calibri"
        p.alignment = PP_ALIGN.CENTER

        # Arrow between boxes
        if i < len(stages) - 1:
            arrow_left = left + box_width + Inches(0.05)
            arrow_top = top + Inches(0.45)
            add_textbox(slide, arrow_left, arrow_top, Inches(0.3), Inches(0.3),
                        "→", font_size=22, color=AMBER, bold=True,
                        alignment=PP_ALIGN.CENTER)

    add_textbox(slide, Inches(0.8), Inches(5.0), Inches(11), Inches(1),
                "Full visibility from first proposal to go-live — nothing falls through the cracks.",
                font_size=18, color=TEXT_SECONDARY, alignment=PP_ALIGN.CENTER)

    add_nav_stripe(slide)


def make_section_header(prs, title, section_num, subtitle=""):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_slide_bg(slide, NAVY)

    # Section number
    add_textbox(slide, Inches(1.5), Inches(2.0), Inches(10), Inches(0.8),
                f"SECTION {section_num}", font_size=16, color=AMBER,
                bold=True, alignment=PP_ALIGN.CENTER)

    add_textbox(slide, Inches(1.5), Inches(2.8), Inches(10), Inches(1.5),
                title, font_size=40, color=WHITE, bold=True,
                alignment=PP_ALIGN.CENTER)

    if subtitle:
        add_textbox(slide, Inches(1.5), Inches(4.3), Inches(10), Inches(0.8),
                    subtitle, font_size=18, color=TEXT_MUTED,
                    alignment=PP_ALIGN.CENTER)

    # Amber stripe
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(5.0), Inches(4.1), Inches(3.3), Inches(0.06)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()


def make_screenshot_slide(prs, title, screenshot_label, callouts, subtitle=""):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_slide_bg(slide, WHITE)

    # Title
    add_textbox(slide, Inches(0.8), Inches(0.4), Inches(10), Inches(0.7),
                title, font_size=28, color=NAVY, bold=True)

    # Amber underline
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(0.8), Inches(1.05), Inches(2.5), Inches(0.05)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()

    if subtitle:
        add_textbox(slide, Inches(0.8), Inches(1.15), Inches(10), Inches(0.5),
                    subtitle, font_size=14, color=TEXT_SECONDARY)

    # Screenshot placeholder — left 2/3
    ss_top = Inches(1.5) if not subtitle else Inches(1.8)
    add_screenshot_placeholder(slide, Inches(0.8), ss_top,
                               Inches(8.0), Inches(5.0), screenshot_label)

    # Callout boxes — right column
    callout_left = Inches(9.2)
    callout_top = ss_top + Inches(0.2)
    for i, callout in enumerate(callouts):
        add_callout_box(slide, callout_left, callout_top + Inches(i * 1.5),
                        Inches(3.5), Inches(1.2), callout)

    add_nav_stripe(slide)


def make_whats_next_slide(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_slide_bg(slide, WHITE)

    add_textbox(slide, Inches(0.8), Inches(0.5), Inches(10), Inches(0.8),
                "What's Coming Next", font_size=32, color=NAVY, bold=True)

    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(0.8), Inches(1.2), Inches(2.8), Inches(0.06)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()

    items = [
        "📄  Document Send Pipeline — one-click PDF merge & delivery for proposal packages",
        "📊  Owner Dashboard — KPI cards with drill-down across sales, contracts & onboarding",
        "🔧  Operations Dashboard — real-time sensor alerts & UpKeep work order integration",
        "💾  Save as Draft — resume any wizard mid-progress across sessions",
        "✅  Compliance Automation — table-driven rule validation before document delivery",
    ]
    add_bullet_list(slide, Inches(0.8), Inches(1.6), Inches(11), Inches(4.5),
                    items, font_size=20, color=TEXT_PRIMARY)

    add_nav_stripe(slide)


def make_closing_slide(prs):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_slide_bg(slide, NAVY)

    add_textbox(slide, Inches(1.5), Inches(2.5), Inches(10), Inches(1.5),
                "Thank You", font_size=44, color=WHITE, bold=True,
                alignment=PP_ALIGN.CENTER)

    add_textbox(slide, Inches(1.5), Inches(4.0), Inches(10), Inches(0.8),
                "Questions?", font_size=24, color=AMBER,
                alignment=PP_ALIGN.CENTER)

    # Amber stripe
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(5.0), Inches(4.8), Inches(3.3), Inches(0.06)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = AMBER
    shape.line.fill.background()

    add_textbox(slide, Inches(1.5), Inches(5.5), Inches(10), Inches(0.5),
                "Decades Property Management  •  DCFG Contracting Suite",
                font_size=14, color=TEXT_MUTED, alignment=PP_ALIGN.CENTER)


def build_master_deck():
    prs = Presentation()
    prs.slide_width = SLIDE_WIDTH
    prs.slide_height = SLIDE_HEIGHT

    # ── Section 1: Opening ──
    make_title_slide(prs)       # Slide 1
    make_problem_slide(prs)     # Slide 2
    make_journey_slide(prs)     # Slide 3

    # ── Section 2: Sales Proposals ──
    make_section_header(prs, "Sales Proposals", "01",
                        "From package selection to proposal generation")  # Slide 4

    make_screenshot_slide(prs,
        "New Proposal Wizard — Package Selection",
        "Screenshot: Proposal Wizard Step 1 — Package A / B / C selection",
        [
            "Choose a service package — exhibits auto-populate based on selection",
            "Package summary shows what's included (Exhibits A–D)",
        ])  # Slide 5

    make_screenshot_slide(prs,
        "Pricing & Locations",
        "Screenshot: Proposal Wizard Step 3 — rate grid + location list",
        [
            "Set uniform rates or per-location pricing",
            "Add/remove locations on the fly — totals update live",
        ])  # Slide 6

    make_screenshot_slide(prs,
        "Review & Generate",
        "Screenshot: Proposal Wizard Step 4 — review summary before generation",
        [
            "Review all details before generating",
            "One click creates MSA + all exhibits (A through D)",
            "Document saved to SharePoint automatically",
        ])  # Slide 7

    # ── Section 3: Contracts ──
    make_section_header(prs, "Contracts", "02",
                        "Work orders, amendments & vendor MSAs")  # Slide 8

    make_screenshot_slide(prs,
        "Contract List",
        "Screenshot: Contracts table — status badges, search, sort",
        [
            "Every contract at a glance — search, sort, filter by status",
            "Color-coded status badges: Draft → Generated → Sent → Signed → Closed",
        ])  # Slide 9

    make_screenshot_slide(prs,
        "Contract Detail",
        "Screenshot: Contract detail view — full record with compliance panel",
        [
            "Full lifecycle tracking from creation to close",
            "Built-in compliance validation flags issues before send",
            "Regenerate documents anytime with one click",
        ])  # Slide 10

    make_screenshot_slide(prs,
        "New Contract Wizard",
        "Screenshot: Contract wizard — customer-first 5-step flow",
        [
            "Customer → document type → contractor → line items → generate",
            "Amendment mode auto-fills from parent work order",
            "Save as Draft to resume later",
        ])  # Slide 11

    # ── Section 4: Send Queue ──
    make_section_header(prs, "Send Queue", "03",
                        "Nothing leaves the building without review")  # Slide 12

    make_screenshot_slide(prs,
        "Approval Dashboard",
        "Screenshot: Send Queue — KPI cards + approval table with action buttons",
        [
            "KPI cards show pipeline health at a glance",
            "Every document reviewed before delivery",
            "Filter by category: Sales vs. Operations",
        ])  # Slide 13

    make_screenshot_slide(prs,
        "Approval Actions",
        "Screenshot: Send Queue row — Approve / Return / Request Info buttons",
        [
            "✓ Approve — moves to delivery queue",
            "↩ Return — sends back for revision with notes",
            "? Request Info — email the submitter for clarification",
        ])  # Slide 14

    # ── Section 5: Onboarding ──
    make_section_header(prs, "Onboarding", "04",
                        "Every new customer tracked from kickoff to go-live")  # Slide 15

    make_screenshot_slide(prs,
        "Onboarding Cases",
        "Screenshot: Onboarding list — status filters, case cards",
        [
            "Filter by phase: Not Started → In Progress → Go-Live → Complete",
            "Search by case number, customer, or MSA",
            "Create new cases with template-driven steps",
        ])  # Slide 16

    make_screenshot_slide(prs,
        "Case Detail & Checklist",
        "Screenshot: Onboarding detail — checklist steps with progress bar",
        [
            "Template-driven checklist — every step has due dates and evidence tracking",
            "Voice notes for quick progress updates (works on iPad)",
            "Progress bar shows completion at a glance",
        ])  # Slide 17

    make_screenshot_slide(prs,
        "Concierge Portal",
        "Screenshot: Customer-facing intake wizard — mobile-friendly property form",
        [
            "Customers self-serve property data collection",
            "Mobile-friendly with camera upload for documents",
            "Data flows directly into onboarding case",
        ],
        subtitle="Customer-facing intake — separate portal for new property managers")  # Slide 18

    # ── Section 6: Scheduling ──
    make_section_header(prs, "Scheduling & Tracking", "05",
                        "Auto-calculated due dates and step-by-step progress")  # Slide 19

    make_screenshot_slide(prs,
        "Due Dates & Progress Tracking",
        "Screenshot: Checklist with due dates, completion %, case lifecycle controls",
        [
            "Due dates auto-calculated from kickoff + turnaround days per step",
            "Step-by-step progress with completion percentage",
            "Close case locks everything — reopen restores to In Progress",
        ])  # Slide 20

    # ── Section 7: Closing ──
    make_whats_next_slide(prs)  # Slide 21
    make_closing_slide(prs)     # Slide 22

    return prs


def build_department_deck(master_prs, name, slide_indices):
    """Extract specific slides from master to create a department version."""
    dept_prs = Presentation()
    dept_prs.slide_width = SLIDE_WIDTH
    dept_prs.slide_height = SLIDE_HEIGHT

    for idx in slide_indices:
        # python-pptx doesn't support slide copying natively,
        # so we rebuild department decks from scratch
        pass

    return dept_prs


def main():
    out_dir = r"C:\DCFG\docs"

    # Build master deck
    print("Building master deck...")
    master = build_master_deck()
    master_path = os.path.join(out_dir, "DCFG_Leadership_Presentation.pptx")
    master.save(master_path)
    print(f"  OK Master deck: {master_path} ({len(master.slides)} slides)")

    # Build department versions
    # Sales: Opening + Proposals + Send Queue + Closing
    print("Building Sales deck...")
    sales = build_master_deck_filtered("Sales", [
        "title", "problem", "journey",
        "proposals_header", "proposals_1", "proposals_2", "proposals_3",
        "sendqueue_header", "sendqueue_1", "sendqueue_2",
        "whats_next", "closing"
    ])
    sales_path = os.path.join(out_dir, "DCFG_Presentation_Sales.pptx")
    sales.save(sales_path)
    print(f"  OK Sales deck: {sales_path} ({len(sales.slides)} slides)")

    # Operations: Opening + Contracts + Send Queue + Closing
    print("Building Operations deck...")
    ops = build_master_deck_filtered("Operations", [
        "title", "problem", "journey",
        "contracts_header", "contracts_1", "contracts_2", "contracts_3",
        "sendqueue_header", "sendqueue_1", "sendqueue_2",
        "whats_next", "closing"
    ])
    ops_path = os.path.join(out_dir, "DCFG_Presentation_Operations.pptx")
    ops.save(ops_path)
    print(f"  OK Operations deck: {ops_path} ({len(ops.slides)} slides)")

    # Onboarding: Opening + Onboarding + Scheduling + Closing
    print("Building Onboarding deck...")
    onb = build_master_deck_filtered("Onboarding", [
        "title", "problem", "journey",
        "onboarding_header", "onboarding_1", "onboarding_2", "onboarding_3",
        "scheduling_header", "scheduling_1",
        "whats_next", "closing"
    ])
    onb_path = os.path.join(out_dir, "DCFG_Presentation_Onboarding.pptx")
    onb.save(onb_path)
    print(f"  OK Onboarding deck: {onb_path} ({len(onb.slides)} slides)")

    print(f"\nDone! All decks saved to {out_dir}")
    print("Next steps:")
    print("  1. Open each .pptx in PowerPoint")
    print("  2. Right-click each screenshot placeholder > Change Picture > From File")
    print("  3. Add Decades logo to title slide")


def build_master_deck_filtered(dept_name, include_sections):
    """Build a department-specific deck by only including tagged sections."""
    prs = Presentation()
    prs.slide_width = SLIDE_WIDTH
    prs.slide_height = SLIDE_HEIGHT

    slide_builders = get_slide_builders()
    for tag, builder_fn in slide_builders:
        if tag in include_sections:
            builder_fn(prs)

    return prs


def get_slide_builders():
    """Return tagged list of (section_tag, builder_function) pairs."""
    return [
        ("title", make_title_slide),
        ("problem", make_problem_slide),
        ("journey", make_journey_slide),

        ("proposals_header", lambda prs: make_section_header(prs, "Sales Proposals", "01",
            "From package selection to proposal generation")),
        ("proposals_1", lambda prs: make_screenshot_slide(prs,
            "New Proposal Wizard — Package Selection",
            "Screenshot: Proposal Wizard Step 1 — Package A / B / C selection",
            ["Choose a service package — exhibits auto-populate based on selection",
             "Package summary shows what's included (Exhibits A–D)"])),
        ("proposals_2", lambda prs: make_screenshot_slide(prs,
            "Pricing & Locations",
            "Screenshot: Proposal Wizard Step 3 — rate grid + location list",
            ["Set uniform rates or per-location pricing",
             "Add/remove locations on the fly — totals update live"])),
        ("proposals_3", lambda prs: make_screenshot_slide(prs,
            "Review & Generate",
            "Screenshot: Proposal Wizard Step 4 — review summary before generation",
            ["Review all details before generating",
             "One click creates MSA + all exhibits (A through D)",
             "Document saved to SharePoint automatically"])),

        ("contracts_header", lambda prs: make_section_header(prs, "Contracts", "02",
            "Work orders, amendments & vendor MSAs")),
        ("contracts_1", lambda prs: make_screenshot_slide(prs,
            "Contract List",
            "Screenshot: Contracts table — status badges, search, sort",
            ["Every contract at a glance — search, sort, filter by status",
             "Color-coded status badges: Draft → Generated → Sent → Signed → Closed"])),
        ("contracts_2", lambda prs: make_screenshot_slide(prs,
            "Contract Detail",
            "Screenshot: Contract detail view — full record with compliance panel",
            ["Full lifecycle tracking from creation to close",
             "Built-in compliance validation flags issues before send",
             "Regenerate documents anytime with one click"])),
        ("contracts_3", lambda prs: make_screenshot_slide(prs,
            "New Contract Wizard",
            "Screenshot: Contract wizard — customer-first 5-step flow",
            ["Customer → document type → contractor → line items → generate",
             "Amendment mode auto-fills from parent work order",
             "Save as Draft to resume later"])),

        ("sendqueue_header", lambda prs: make_section_header(prs, "Send Queue", "03",
            "Nothing leaves the building without review")),
        ("sendqueue_1", lambda prs: make_screenshot_slide(prs,
            "Approval Dashboard",
            "Screenshot: Send Queue — KPI cards + approval table with action buttons",
            ["KPI cards show pipeline health at a glance",
             "Every document reviewed before delivery",
             "Filter by category: Sales vs. Operations"])),
        ("sendqueue_2", lambda prs: make_screenshot_slide(prs,
            "Approval Actions",
            "Screenshot: Send Queue row — Approve / Return / Request Info buttons",
            ["✓ Approve — moves to delivery queue",
             "↩ Return — sends back for revision with notes",
             "? Request Info — email the submitter for clarification"])),

        ("onboarding_header", lambda prs: make_section_header(prs, "Onboarding", "04",
            "Every new customer tracked from kickoff to go-live")),
        ("onboarding_1", lambda prs: make_screenshot_slide(prs,
            "Onboarding Cases",
            "Screenshot: Onboarding list — status filters, case cards",
            ["Filter by phase: Not Started → In Progress → Go-Live → Complete",
             "Search by case number, customer, or MSA",
             "Create new cases with template-driven steps"])),
        ("onboarding_2", lambda prs: make_screenshot_slide(prs,
            "Case Detail & Checklist",
            "Screenshot: Onboarding detail — checklist steps with progress bar",
            ["Template-driven checklist — every step has due dates and evidence tracking",
             "Voice notes for quick progress updates (works on iPad)",
             "Progress bar shows completion at a glance"])),
        ("onboarding_3", lambda prs: make_screenshot_slide(prs,
            "Concierge Portal",
            "Screenshot: Customer-facing intake wizard — mobile-friendly property form",
            ["Customers self-serve property data collection",
             "Mobile-friendly with camera upload for documents",
             "Data flows directly into onboarding case"])),

        ("scheduling_header", lambda prs: make_section_header(prs, "Scheduling & Tracking", "05",
            "Auto-calculated due dates and step-by-step progress")),
        ("scheduling_1", lambda prs: make_screenshot_slide(prs,
            "Due Dates & Progress Tracking",
            "Screenshot: Checklist with due dates, completion %, case lifecycle controls",
            ["Due dates auto-calculated from kickoff + turnaround days per step",
             "Step-by-step progress with completion percentage",
             "Close case locks everything — reopen restores to In Progress"])),

        ("whats_next", make_whats_next_slide),
        ("closing", make_closing_slide),
    ]


if __name__ == "__main__":
    main()
