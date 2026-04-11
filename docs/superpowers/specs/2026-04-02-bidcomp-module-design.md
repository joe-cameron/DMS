# BidComp Module — Design Specification

**Date:** 2026-04-02
**Author:** Joseph Cameron / Claude
**Status:** Draft
**Module:** BidComp (isolated from DCFG SPA)

---

## 1. Purpose

BidComp is a construction project management and procurement module that digitizes Decades Construction Group's existing spreadsheet-based processes for:

1. **Monthly client reporting** (immediate Bancroft need)
2. **Invoice tracking and cash flow management**
3. **Budget spend-down tracking by fiscal year, site, and cost code**
4. **RFP creation, vendor bid comparison, and award decisions**
5. **Cadenced service tracking with time-slip billing adjustments**
6. **Contract document generation (Exhibit A, Exhibit B)**

The system serves both B2B (TPA — managing work on behalf of customers like Bancroft) and B2C (homeowner-direct) engagements using the same data model with context-driven UI.

## 2. Design Principles

1. **Spreadsheet vocabulary** — Every screen name, column header, field name, and status value matches the terms used in the existing spreadsheets created by the SME team (Bill, Leon, Tyler, Harry). Users should feel their spreadsheets grew a brain, not that they have to learn a new tool.

2. **Excel is the workspace, the system is the source of truth** — Users can export any view to Excel, work in familiar tools, and import changes back. The system absorbs changes, diffs against source, and maintains audit trail.

3. **No missed revenue** — The system's primary financial value is eliminating the gap between work performed and client billing. Every invoice, every cadenced service period, every completed phase is tracked against billing status. Unbilled work is surfaced immediately.

4. **Fiduciary transparency** — As TPA, Decades spends the customer's money. Every procurement decision has a structured audit trail: what was bid, who responded, what the differences were, why the winner was selected.

5. **AI assists, humans decide** — AI parses proposals, suggests scope items, identifies gaps, normalizes bids. AI never picks winners, approves invoices, or makes financial commitments.

6. **Isolated but connected** — BidComp has its own Dataverse tables. It reads from existing DCFG tables (dcfg_vendor, dcfg_customer, dcfg_property) via lookup. It does not write to SPA tables. Future integration path exists.

## 3. Architecture

### 3.1 Stack

- **Frontend:** React 16.14 + Vite (same as DCFG SPA)
- **Backend:** Dataverse Web API via Power Pages
- **Auth:** Entra ID (same as DCFG SPA)
- **Storage:** Dataverse custom tables (dcfg_ prefixed, new tables only)
- **Files:** SharePoint (existing folder structure, read/write via Graph API)
- **Automation:** Power Automate cloud flows (alerts, reminders, report generation)
- **AI:** Claude API or Azure OpenAI (proposal parsing, scope extraction, gap analysis)
- **Deployment:** Power Pages code site (separate from DCFG SPA site)
- **Environment:** DCFGSystem-Prod (Dataverse), isolated code site

### 3.2 Relationship to DCFG SPA

```
DCFG SPA (existing)              BidComp (new)
────────────────────             ─────────────────
dcfg_vendor          ←── read ── dcfg_exhibit_a
dcfg_customer        ←── read ── dcfg_prime_contract
dcfg_property        ←── read ── dcfg_phase
dcfg_contract        ←── future  dcfg_exhibit_a (award → WO)
```

BidComp reads vendor, customer, and property data from DCFG. It does not write to those tables. Future: an awarded Exhibit A can create a work order in the DCFG contract system, but this is not MVP.

## 4. Data Model

### 4.1 New Tables

All tables use the `dcfg_` prefix and are added to the DCFGSystemTest solution.

#### dcfg_prime_contract (= Sage Budget)
The master contract between Decades and a customer for a fiscal year or project.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_contract_number | String | Contract/project number (e.g., "25010") |
| dcfg_customer | Lookup → dcfg_customer | Customer (e.g., Bancroft) |
| dcfg_fiscal_year | String | Fiscal year (e.g., "FY26") |
| dcfg_total_budget | Currency | Total contract budget |
| dcfg_general_conditions | Currency | General conditions allocation |
| dcfg_contingency | Currency | Contingency allocation |
| dcfg_supervision | Currency | Supervision cost |
| dcfg_design_fees | Currency | Design fees allocation |
| dcfg_contract_type | Choice | TPA / Direct / B2C |
| dcfg_status | Choice | Active / Complete / Closed |
| dcfg_start_date | Date | Contract start |
| dcfg_end_date | Date | Contract end |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_phase (= each row in Sage Budget / Tracker)
A single budget line item — one property + one cost code = one phase.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_prime_contract | Lookup → dcfg_prime_contract | Parent contract |
| dcfg_phase_number | Integer | Phase number (sequential) |
| dcfg_phase_name | String | Phase name (e.g., "310119 NJ Cranford") |
| dcfg_property_address | String | Display address |
| dcfg_property | Lookup → dcfg_property | Link to DCFG property record (optional) |
| dcfg_cost_code | String | Cost code (e.g., "70011") |
| dcfg_cost_code_desc | String | Description (e.g., "Bathroom Remodel") |
| dcfg_description | String | Project description |
| dcfg_hours | Decimal | Estimated man-hours |
| dcfg_material | Currency | Material budget |
| dcfg_labor | Currency | Labor budget |
| dcfg_equipment | Currency | Equipment budget |
| dcfg_sub | Currency | Subcontractor budget |
| dcfg_other | Currency | Other costs |
| dcfg_budget_total | Currency | Total phase budget (computed) |
| dcfg_spent_to_date | Currency | Amount spent (computed from invoices) |
| dcfg_remaining | Currency | Remaining budget (computed) |
| dcfg_service_line | Choice | Adult North / Adult South / Childrens / Lakeside / Corp / Education / Day |
| dcfg_cost_center_id | String | Workday cost center ID (e.g., "310119") |
| dcfg_rent_or_own | Choice | Own / Rent / Lease |
| dcfg_sub_or_self | Choice | Sub / Self |
| dcfg_pm_assigned | String | PM name (e.g., "Nikko", "Mike"). Note: String for MVP to match spreadsheet. Consider Lookup to systemuser if "my projects" filtering is needed. |
| dcfg_status | Choice | Not Started / In Progress / Completed / Out to Bid / Ready to Start / Canceled |
| dcfg_planned_or_unplanned | Choice | Planned / Unplanned |
| dcfg_priority_level | Choice | Priority 1 / Priority 2 |
| dcfg_requester | String | Who requested the work |
| dcfg_notes | String (multiline) | Notes |
| dcfg_wo_number | String | Work order number (when assigned) |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_exhibit_a (= Executed Work Order)
A signed contract awarding work to a vendor.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_phase | Lookup → dcfg_phase | Which phase this serves |
| dcfg_vendor | Lookup → dcfg_vendor | Awarded vendor |
| dcfg_trade | String | Trade (e.g., "HVAC", "Electrical") |
| dcfg_contract_amount | Currency | Total contract amount |
| dcfg_wo_number | String | Work order number |
| dcfg_status | Choice | Draft / Executed / Active / Complete / Closed |
| dcfg_executed_date | Date | Date signed |
| dcfg_payment_frequency | Choice | One-time / Weekly / Biweekly / Monthly / Quarterly / Annual |
| dcfg_first_payment_date | Date | First payment due date |
| dcfg_fy_allocation | String (JSON) | Contract amount by fiscal year |
| dcfg_sp_file_ref | String | SharePoint file URL |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_exhibit_b (= Scope of Work)
Detailed scope breakdown tied to an Exhibit A.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_exhibit_a | Lookup → dcfg_exhibit_a | Parent work order |
| dcfg_phase | Lookup → dcfg_phase | Phase reference |
| dcfg_vendor | Lookup → dcfg_vendor | Vendor |
| dcfg_trade | String | Trade |
| dcfg_csi_code | String | CSI code (e.g., "23010") |
| dcfg_contract_amount | Currency | Contract amount |
| dcfg_contact_name | String | Vendor contact name |
| dcfg_contact_phone | String | Vendor contact phone |
| dcfg_contact_email | String | Vendor contact email |
| dcfg_scope_items | String (JSON) | Array of scope line items with Y/N flags |
| dcfg_general_notes | String (JSON) | Standard general notes with Y/N flags |
| dcfg_sp_file_ref | String | SharePoint file URL |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_change_order
Amendment to an executed Exhibit A.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_exhibit_a | Lookup → dcfg_exhibit_a | Parent work order |
| dcfg_vendor | Lookup → dcfg_vendor | Vendor |
| dcfg_co_number | String | Change order number |
| dcfg_amount | Currency | Change order amount |
| dcfg_description | String | Description of change |
| dcfg_status | Choice | Draft / Executed / Rejected |
| dcfg_sp_file_ref | String | SharePoint file URL |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_invoice (= Invoice Tracking tab)
Every invoice in the billing pipeline.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_phase | Lookup → dcfg_phase | Phase reference |
| dcfg_exhibit_a | Lookup → dcfg_exhibit_a | Related work order (optional) |
| dcfg_vendor | Lookup → dcfg_vendor | Vendor lookup (for cross-project analytics) |
| dcfg_contractor_name | String | Contractor/vendor display name (matches spreadsheet column) |
| dcfg_proposal_number | String | Proposal number |
| dcfg_invoice_number | String | Invoice number |
| dcfg_cost | Currency | Invoice amount |
| dcfg_date_invoiced | Date | Date contractor sent invoice |
| dcfg_approved_for_billing | Date | Date approved for billing |
| dcfg_date_invoiced_to_client | Date | Date billed to client |
| dcfg_paid_or_open | Choice | Paid / Open / Rejected |
| dcfg_date_paid | Date | Date payment received |
| dcfg_notes | String | Notes |
| dcfg_job | String | Job/property reference (free text from spreadsheet — typically property name or address, e.g., "65 Holly Oak", "21 Colgate") |
| dcfg_sp_file_ref | String | SharePoint file URL |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_rfp (= Tracking Log)
An RFP sent to vendors for a scope of work.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_phase | Lookup → dcfg_phase | Phase reference |
| dcfg_trade | String | Trade |
| dcfg_cost_code | String | Cost code |
| dcfg_scope_description | String (multiline) | Scope description |
| dcfg_version | Integer | RFP version number |
| dcfg_bid_solicited | Boolean | Bid solicited Y/N |
| dcfg_bid_received | Boolean | Bid received Y/N |
| dcfg_scope_exhibit_drafted | Boolean | Scope exhibit drafted Y/N |
| dcfg_exhibit_b_issued | Boolean | Exhibit B issued Y/N |
| dcfg_contract_out | Boolean | Contract out Y/N |
| dcfg_contract_fe | Boolean | Contract fully executed Y/N |
| dcfg_submittals_received | Boolean | Submittals received Y/N |
| dcfg_due_date | Date | Response deadline |
| dcfg_status | Choice | Draft / Sent / Responses In / Leveled / Awarded / Canceled |
| dcfg_scope_items | String (JSON) | Structured scope items for this RFP |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_proposal (= Vendor Bid Response)
A vendor's response to an RFP.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_rfp | Lookup → dcfg_rfp | Parent RFP |
| dcfg_vendor | Lookup → dcfg_vendor | Responding vendor |
| dcfg_bid_amount | Currency | Total bid amount |
| dcfg_response_date | Date | Date response received |
| dcfg_status | Choice | Pending / Received / Parsed / Leveled / Awarded / Not Selected |
| dcfg_scope_items | String (JSON) | Parsed scope items from proposal |
| dcfg_gaps | String (JSON) | Identified gaps vs RFP scope |
| dcfg_source_docs | String | Reference to source documents |
| dcfg_leveled_amount | Currency | Normalized amount after leveling |
| dcfg_ai_confidence | Decimal | AI parsing confidence (0-1) |
| dcfg_notes | String (multiline) | Notes |
| dcfg_award_rationale | String (multiline) | Why selected/not selected (fiduciary record) |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_cadenced_svc (= Recurring Service Contract)
A recurring service agreement tied to a phase.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_phase | Lookup → dcfg_phase | Phase reference |
| dcfg_exhibit_a | Lookup → dcfg_exhibit_a | Related work order |
| dcfg_vendor | Lookup → dcfg_vendor | Service vendor |
| dcfg_service_description | String | Service description |
| dcfg_frequency | Choice | Weekly / Biweekly / Monthly / Quarterly / Annual |
| dcfg_unit_price | Currency | Price per period |
| dcfg_total_periods | Integer | Total periods in contract |
| dcfg_contract_start | Date | Service start date |
| dcfg_contract_end | Date | Service end date |
| dcfg_last_performed | Date | Last confirmed service date |
| dcfg_next_due | Date | Next expected service date |
| dcfg_grace_days | Integer | Days after period end before time-slip |
| dcfg_active_flag | Boolean | Soft delete |

#### dcfg_service_period (= Each billing period for a cadenced service)
Individual period tracking for cadenced services.

| Column | Type | Description |
|--------|------|-------------|
| dcfg_cadenced_svc | Lookup → dcfg_cadenced_svc | Parent service |
| dcfg_period_start | Date | Period start date |
| dcfg_period_end | Date | Period end date |
| dcfg_performed | Boolean | Was service performed? |
| dcfg_date_performed | Date | Actual date performed |
| dcfg_time_slipped | Boolean | Was this period time-slipped? |
| dcfg_invoice | Lookup → dcfg_invoice | Linked invoice |
| dcfg_notes | String | Notes |
| dcfg_active_flag | Boolean | Soft delete |

### 4.2 Existing DCFG Tables Referenced (Read-Only)

- `dcfg_vendor` — vendor directory, contact info, trade
- `dcfg_customer` — customer records (Bancroft, homeowners)
- `dcfg_property` — property addresses and details

### 4.3 JSON Field Schemas

#### scope_items (used in dcfg_exhibit_b, dcfg_rfp, dcfg_proposal)
```json
[
  {
    "item": "Supply and Install Fujitsu 12,000 BTU ductless mini split",
    "included": true,
    "category": "Specific Scope Items",
    "quantity": "1",
    "uom": "LS",
    "notes": ""
  },
  {
    "item": "Sales tax - exempt",
    "included": true,
    "category": "General Notes",
    "notes": ""
  }
]
```

#### gaps (used in dcfg_proposal)
```json
[
  {
    "rfp_item": "Quarterly duct inspection",
    "vendor_response": "Not mentioned",
    "status": "Gap",
    "outreach_sent": false,
    "outreach_response": null
  }
]
```

#### fy_allocation (used in dcfg_exhibit_a)
```json
{
  "FY26": 45000,
  "FY27": 30000
}
```

## 5. Screen Architecture

### 5.1 Navigation

Top-level customer/FY selector, then tab-based navigation matching spreadsheet tab names.

```
[Customer: Bancroft ▼]  [FY: 2026 ▼]

Dashboard | Tracker | Buy Sheet | Invoices | Monthly Report
Exhibit A | Exhibit B | Change Orders | Cadenced Services
Proposals | RFP Builder | Vendors | Reports | Settings
```

### 5.2 Screen Specifications

#### Dashboard
- Mirrors the Tracker spreadsheet's Dashboard tab — but working
- Total Planned/Unplanned Projects
- Projects by status: Not Started / In Progress / Completed / Out to Bid
- Grouped by Service Line: Adult North, Adult South, Childrens
- Spend-down summary: budget vs committed vs spent vs remaining
- Unbilled work alerts (highlighted)
- Invoice aging alerts (highlighted)

#### Tracker (= FY26 Project Tracker)
- Grid view with exact same columns as the spreadsheet:
  - Planned/Unplanned | Service Line | PM Assigned | WO# | Phase | Phase Name | Property Address | Description | Status | Notes | Rent/Own | Sub/Self | Cost Code | Hours | Material | Labor | Equipment | Sub | Other
- Inline editable for Status, PM Assigned, Notes
- Sortable/filterable by Service Line, PM, Status
- Color-coded rows by status
- Export to Excel button (produces exact spreadsheet format)

#### Buy Sheet
- CSI/Cost Code budget view:
  - CSI# | Description | Estimate Value | Material | Labor | Expense | Sub | Contract Award | Un-Purchased | Contractor Name | Gain | Loss
- Rollup by cost code across all phases
- Drill-down to individual phases per code

#### Invoices (= Invoice Tracking)
- Grid with exact same columns:
  - Phase | Contractor Name | Proposal# | Cost | Invoice# | Cost | Date Invoiced (Contractor) | Approved for Billing (Y/N) | Date Invoiced to Client | Paid/Open | Notes | Date Paid | Job
- Auto-flags: aging invoices (received > 14 days, not billed to client)
- Auto-flags: unbilled completed work (phase Complete, no invoice)
- Quick-add from SharePoint scan (system finds untracked invoices)

#### Monthly Report
- One-click generator
- Produces multi-tab Excel workbook:
  1. Executive Summary (budget vs spent, status counts, alerts)
  2. Project Tracker (full grid, status changes highlighted)
  3. Invoice Detail (all invoices this period, aging analysis)
  4. Spend-Down (by phase, by cost code, by service line)
  5. Cadenced Services (performed/missed/time-slipped)
  6. Change Orders (this period, cumulative impact)
- Configurable reporting period (default: previous calendar month)
- Attach SharePoint document references

#### Exhibit A (= Executed Work Orders)
- List view: Phase | Vendor | Trade | Contract Amount | Status | WO# | Executed Date
- Detail view: full work order with vendor info, payment terms, FY allocation
- Generate PDF in Decades/customer template format
- Link to SharePoint file

#### Exhibit B (= Scope of Work)
- Uses the existing template structure (Cover Sheet + scope items checklist)
- Per-trade templates pre-loaded (from "Exhibit B Template USE THISSSSS"):
  - Fire Alarm, HVAC, Electrical, Plumbing, Site Work, Concrete, Fire Protection, Waterproofing, Flooring, Painting, Roofing, Countertops, Fence, Cleaning, Siding
- Cover sheet: Project address, project#, CSI code, vendor info, trade, contract amount
- Scope items: checklist with Y/N flags, organized by Specific Scope Items + General Notes
- Generate PDF / Excel export

#### Change Orders
- List: CO#, Exhibit A reference, vendor, amount, description, status
- Impact tracking: original contract + CO1 + CO2 = current contract value

#### Cadenced Services
- Grid: Site | Vendor | Frequency | $/Period | Period columns (✓/✗) | Billed | Expected | Slipped
- Time-slip detection with grace period
- Unbilled service alerts
- Monthly rollup for reporting

#### Proposals
- Per-RFP view: all vendor responses side-by-side
- Leveling matrix: same scope items, different vendors, normalized pricing
- Gap indicators: what's missing from each bid
- AI-parsed scope items with confidence scores
- Award decision capture with rationale field

#### RFP Builder
- Trade selector with scope item suggestions from taxonomy
- Version tracking (v1, v2 as scope changes)
- Per-vendor status tracking (Pending/Received/Parsed)
- Due date and reminder automation
- Send via email (structured form + PDF attachment)

#### Vendors (= Directory of Subcontractors)
- Grid: Trade | Company | PM | Scheduling Contact | Email
- Cross-project history: what work they've done, at what prices
- Performance notes

#### Reports
- Spend-down by FY / site / trade / cost code
- Invoice aging analysis
- Unbilled work summary
- Cadenced service compliance
- Cross-project vendor pricing comparison
- Cash flow projection

### 5.3 Excel Round-Trip

Every grid view has Export and Import buttons:

**Export:**
- Produces .xlsx in the exact format of the current spreadsheet
- Column headers match the spreadsheet column headers
- Formatting matches (currency, dates, conditional colors)

**Import:**
- Accepts .xlsx with same structure
- Diffs against current data, shows changes for review
- User approves/rejects per-change
- New rows flagged as potential new records
- Audit trail: who imported, when, what changed
- Conflict resolution if data changed between export/import

## 6. Automation (Power Automate Flows)

### 6.1 Alert Flows

| Flow | Trigger | Action |
|------|---------|--------|
| Unbilled Work Alert | Phase status → Complete | If no invoice within 7 days, email PM |
| Invoice Aging Alert | Daily schedule | Flag invoices received > 14 days without client billing |
| Cash Flow Alert | Daily schedule | If total unbilled > threshold, email management |
| Cadenced Service Due | Daily schedule | Service approaching due date without confirmation → email PM |
| Time Slip Alert | Period end + grace days | Auto-mark as time-slipped, adjust billing |
| RFP Response Reminder | Due date - 3 days | Email vendors who haven't responded |
| Budget Threshold | Invoice recorded | If phase spend > 80% of budget, alert PM + management |

### 6.2 Report Generation Flow

- Triggered on-demand or scheduled (monthly)
- Queries all relevant tables for the reporting period
- Generates multi-tab Excel workbook
- Stores in SharePoint (reports folder)
- Optionally emails to customer contacts

### 6.3 SharePoint Scan Flow

- Scheduled (daily or weekly)
- Scans SharePoint invoice folders for files not tracked in dcfg_invoice
- Creates "Untracked Invoice" alerts for PM review
- Parses filename for phase/vendor/amount using the naming convention

## 7. AI Integration

### 7.1 Proposal Parsing

**Input:** PDF, .doc, email body from vendor
**Output:** Structured JSON of scope items mapped to RFP categories

Process:
1. Extract text from document (PDF parsing or email body)
2. Send to Claude/OpenAI with RFP scope items as context
3. AI returns: matched items, unmatched items, extracted amounts, confidence scores
4. Human reviews AI output, corrects mapping, confirms
5. Confirmed items stored in dcfg_proposal.scope_items

### 7.2 Scope Suggestion

**Input:** Trade selection + optional site details
**Output:** Suggested scope items for RFP

Sources:
- Past Exhibit B's for this trade (from dcfg_exhibit_b.scope_items)
- Trade taxonomy (pre-loaded by trade category)
- Standard material lists (from existing spreadsheet)

### 7.3 Definition Augmentation

**Input:** Vague scope term (e.g., "comprehensive HVAC maintenance")
**Output:** Specific activities that constitute the term

Sources:
- Vendor's own published service descriptions (if available)
- Industry standard definitions
- Past Exhibit B's where the term was specified in detail

### 7.4 Gap Analysis

**Input:** All proposals for one RFP
**Output:** Gap report showing differences across vendors

Identifies:
- Items in RFP not addressed by vendor
- Items vendor offers beyond RFP scope
- Quantity/specification differences
- Price outliers
- Generates outreach email drafts for missing items

## 8. Phased Delivery

### Phase 1: Bancroft Monthly Reporting (MVP)
- Tables: dcfg_prime_contract, dcfg_phase, dcfg_invoice
- Screens: Dashboard, Tracker, Invoices, Monthly Report, Buy Sheet
- Flows: Invoice Aging Alert, Unbilled Work Alert
- Excel: Export (all views), Import (Tracker, Invoices)
- Data load: Import current Bancroft FY26 data from spreadsheets
- **Immediate value: One-click monthly report, working dashboard, invoice tracking**

### Phase 2: Contract Documents
- Tables: dcfg_exhibit_a, dcfg_exhibit_b, dcfg_change_order
- Screens: Exhibit A, Exhibit B, Change Orders
- Templates: Pre-loaded trade templates from "USE THISSSSS"
- PDF generation for Exhibit A and Exhibit B
- SharePoint integration for document storage/retrieval

### Phase 3: RFP & Bid Comparison
- Tables: dcfg_rfp, dcfg_proposal
- Screens: RFP Builder, Proposals, Vendors
- AI: Proposal parsing, scope suggestion, gap analysis
- Flows: RFP Response Reminder
- Leveling matrix with side-by-side comparison

### Phase 4: Cadenced Services
- Tables: dcfg_cadenced_svc, dcfg_service_period
- Screen: Cadenced Services
- Time-slip logic and billing adjustments
- Flows: Cadenced Service Due, Time Slip Alert

### Phase 5: Intelligence & Integration
- Reports screen with cross-project analytics
- Vendor pricing history across projects
- Cash flow projections
- Customer portal view (read-only)
- DCFG SPA integration (award → work order creation)
- B2C project support (simplified views)

## 9. B2B vs B2C Adaptation

The data model is identical. The UI adapts based on `dcfg_prime_contract.dcfg_contract_type`:

| Feature | B2B (TPA) | B2C (Direct) |
|---------|-----------|--------------|
| Customer selector | Multi-customer | Per-project |
| Fiscal year picker | Visible | Hidden |
| Cost center columns | Visible | Hidden |
| Service line grouping | Visible | Hidden |
| Monthly report | Full package | Simple summary |
| Buy Sheet | By phase/code | By CSI code |
| Dashboard | Portfolio view | Single project |
| Exhibit A/B | Customer templates | Decades templates |
| Cadenced services | Multi-site grid | Single-site list |

## 10. SharePoint Integration

### 10.1 Existing Structure Preserved

The system does not replace SharePoint folder organization. It references it:

```
{Project#} {Name} - Proposals/
{Project#} {Name} - Executed Exhibit A's/
{Project#} {Name} - Exhibit B's/
{Project#} {Name} - Paid Invoices/
{Project#} {Name} - Change Orders/
{Project#} {Name} - Prime Contract & Budget/
```

### 10.2 Integration Points

- **Document references** — `sp_file_ref` fields link to SharePoint files
- **Invoice discovery** — periodic scan finds untracked invoices
- **File upload** — new documents routed to correct folder
- **Report storage** — generated reports saved to SharePoint
- **Read via Graph API** — file metadata (name, date, size)

### 10.3 Access

- Read-only for this session (as directed)
- Write access for file upload and report storage (future, with operator permission)

## 11. Security & Permissions

- Same Entra ID auth as DCFG SPA
- Web roles: BidComp_Admin, BidComp_PM, BidComp_Viewer
- Table permissions per role:
  - **Admin:** Full CRUD on all BidComp tables
  - **PM:** CRUD on dcfg_phase (status, notes), dcfg_invoice, dcfg_rfp, dcfg_proposal, dcfg_service_period. Read on dcfg_prime_contract, dcfg_exhibit_a/b. No delete on dcfg_prime_contract.
  - **Viewer:** Read-only on all BidComp tables (customer portal use case)
- Customer data isolation: users see only their assigned customers/projects
- AI processing: no customer data stored outside Dataverse (API calls only, no training data)
- CRUD matrix to be finalized during Phase 1 planning, following the pattern above

## 12. Cost Code Reference

From the Bancroft GHSP FY26 Sage Budget:

| Code | Description |
|------|-------------|
| 50001 | Contingency |
| 55002 | GC Reserve |
| 1117 | Supervision |
| 1400 | Dumpsters |
| 1901 | Architecture Design |
| 9900 | Painting |
| 70001 | Landscaping / Drainage |
| 70002 | Fence |
| 70003 | Deck Replacement |
| 70004 | Concrete / Asphalt |
| 70005 | Waterproofing |
| 70006 | Roof Replacement |
| 70007 | Siding / Gutters |
| 70008 | Window Replacement |
| 70009 | Exterior Doors / Slider |
| 70010 | Garage Doors / Openers |
| 70011 | Bathroom Remodel |
| 70012 | Kitchen Remodel |
| 70013 | Interior Doors / Finish Trim |
| 70014 | Flooring / Carpet |
| 70015 | Wall Protection |
| 70016 | Plumbing |
| 70017 | Water Heater |
| 70018 | HVAC Replacement |
| 70019 | Electric Upgrade |
| 70020 | Fire Alarm Upgrades |
| 70021 | Appliances |
| 70022 | Building Signage |
| 70023 | Security Systems |
| 70024 | Office Renovation |
| 70025 | Generator |

These are stored as data values in dcfg_phase.cost_code, not as a separate lookup table. Different customers may use different code systems (CSI codes for B2C, Bancroft codes for TPA).

## 13. Naming Convention Preservation

The three-part key from existing file naming is preserved:

```
{Contract#} {Phase#} {Cost Code} = unique identifier

Example: 25010 85 70006
  25010 = Bancroft GHSP FY26 (prime contract)
  85    = Phase 85 (310119 NJ Cranford)
  70006 = Roof Replacement (cost code)
```

This key appears in:
- Invoice filenames (already used)
- Exhibit B references
- Change order references
- The system generates this key automatically from the phase record

## 14. Open Questions (for future sessions)

1. **Sage integration** — Is there an API to sync budget data from Sage, or is it always manual import?
2. **Workday integration** — Can cost center/GL codes be synced from Workday, or manual import?
3. **MS Project** — Are the .mpp schedule files consumed by the system, or stay separate?
4. **ST-13 forms** — What is the ST-13 form structure and when does it get digitized?
5. **Purchase Order Log** — Currently unused. Is it needed, or was it aspirational?
6. **Customer portal timing** — When should Bancroft get read-only access to their data?
7. **Email integration** — Should the system receive vendor emails directly (shared mailbox) or is manual attachment sufficient?
8. **Multi-year contracts** — How do FY rollovers work? New prime contract or amendment? Note: current design is one dcfg_prime_contract per FY. If Bancroft's contract spans FY boundaries, this needs to be confirmed before Phase 1 data load. dcfg_exhibit_a.dcfg_fy_allocation (JSON) supports multi-year splits at the work order level.
