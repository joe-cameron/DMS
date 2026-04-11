# Project Management & Procurement Module — Design Spec

**Date:** 2026-04-04
**Author:** Claude + Joseph Cameron
**Status:** Design Complete — Ready for Build
**Stack:** React + Vite + Dataverse (same as DCFG SPA)
**Location:** New screens within existing DCFG SPA

---

## 1. What This Is

One unified module that covers the full lifecycle: **Setup → Bid → Award → Execute**. This spec MERGES the BidComp module design (2026-04-02) into the DCFG SPA. BidComp is no longer a separate app — it becomes screens within the main SPA, using the BidComp schema (10 tables) as the foundation, plus additions for RFP distribution, vendor discovery, and financial controls.

**Supersedes:** `2026-04-02-bidcomp-module-design.md` (BidComp as isolated module)
**Absorbs:** BidComp's 10 Dataverse tables, screen designs, Excel round-trip pattern

Users model projects using **Excel spreadsheets stored in SharePoint**. The system serves fresh populated spreadsheets on demand, users modify in Excel, re-upload, and the system presents a diff for validation before applying changes.

---

## 2. The Spreadsheet Round-Trip Pattern

This is the core interaction model. Excel is the UI for bulk data entry.

### 2.1 Flow

```
USER: "Give me the tracker spreadsheet"
  → System queries Dataverse for current project data
  → Populates an Excel template with live data
  → Stores in SharePoint (DCFG_WorkingDocs/{user}/{timestamp})
  → Returns download link

USER: Opens in Excel, modifies 15 rows, saves back to SharePoint

USER: "Upload changes"
  → System reads the modified spreadsheet from SharePoint
  → Diffs against Dataverse current state
  → Presents change summary:
      "12 projects updated, 3 new projects, 0 deleted"
      Row-by-row: field | old value | new value
  → User reviews, approves or rejects per-row
  → Approved changes written to Dataverse
  → Audit log entry per change
```

### 2.2 Template Types (from Leon's actual files)

| Template | Purpose | Key Columns |
|----------|---------|-------------|
| Project Tracker | Master project list | Status, PM, Description, Budget, Actuals, Schedule |
| Sage Budget | Cost code breakdown | Phase, Cost Code, Hours, Material, Labor, Equipment, Sub |
| Purchase Order Log | PO tracking | PO#, Phase, Vendor, Qty, Price, Invoice Status |
| Invoice Tracking | Invoice receipt | PO#, Invoice#, Date, Amount, Paid |
| Subcontractor Directory | Vendor + trade list | Trade, Company, Contact, Email |
| Exhibit B | Location list with pricing | Property, Location Type, Rate |

### 2.3 Diff Engine

- Compare by primary key (Phase + WO# for projects, PO# for POs)
- Detect: new rows, modified cells, deleted rows (soft delete)
- Present as a table: row ID | field | before | after | approve?
- Batch approve ("accept all") or per-row
- Rejected changes stay in the spreadsheet for the user to revisit
- Conflict detection: if Dataverse changed since spreadsheet was generated, flag

### 2.4 SharePoint Integration

- Templates stored in: `DCFG_Templates/ProjectTemplates/`
- Working copies stored in: `DCFG_WorkingDocs/{username}/{template}_{date}.xlsx`
- Fresh version = template populated with current Dataverse data
- Old versions kept for audit trail (never deleted)

---

## 3. Data Model

### 3.1 BidComp Tables (FROM 2026-04-02 SPEC — CANONICAL)

These tables are already fully designed. Use them as-is. Full schemas in `2026-04-02-bidcomp-module-design.md`.

| Table | Purpose | Row = |
|-------|---------|-------|
| **dcfg_prime_contract** | Master contract per customer per FY | Bancroft FY26 GHSP |
| **dcfg_phase** | One work item (= Leon's tracker row) | "Replace bathroom #2 at NJ Balfield" |
| **dcfg_exhibit_a** | Awarded work order to a vendor | Signed contract |
| **dcfg_exhibit_b** | Scope of work with line items | Detailed scope per vendor |
| **dcfg_change_order** | Amendment to exhibit A | Change order |
| **dcfg_invoice** | Full billing pipeline | Each invoice |
| **dcfg_rfp** | RFP with procurement checklist | Bid package |
| **dcfg_proposal** | Vendor bid response + AI parsing | Each bid received |
| **dcfg_cadenced_svc** | Recurring service contracts | Monthly landscaping etc. |
| **dcfg_service_period** | Per-period tracking for cadenced | Each billing period |

**Key mapping (BidComp → this spec's concepts):**
- `dcfg_prime_contract` = Program/Contract (replaces dcfg_program for capital projects)
- `dcfg_phase` = Project work item (Leon's tracker rows — already has all his columns)
- `dcfg_exhibit_a` = Awarded contract (links to dcfg_contract for document generation)
- `dcfg_rfp` = RFP bid package (already has procurement checklist booleans)
- `dcfg_proposal` = Vendor bid (already has gaps JSON, AI confidence, award rationale)

### 3.2 New Tables (additions to BidComp schema)

**dcfg_rfp_vendor** — Junction: vendors invited to bid (BidComp didn't have multi-vendor distribution)

| Column | Type | Notes |
|--------|------|-------|
| dcfg_rfp_vendor_id | PK | |
| dcfg_rfp_id | FK → dcfg_rfp | |
| dcfg_vendor_id | FK → dcfg_vendor | |
| dcfg_sent_date | DateTime | When RFP was sent |
| dcfg_response_status | Choice | Pending/Received/Declined/NoResponse |
| dcfg_trades_invited | String(500) | Which trades this vendor was invited for |
| dcfg_distance_miles | Decimal | Distance from project properties |

**dcfg_milestone** — Financial milestones for billing caps

| Column | Type | Notes |
|--------|------|-------|
| dcfg_milestone_id | PK | |
| dcfg_prime_contract_id | FK → dcfg_prime_contract | Or exhibit_a_id |
| dcfg_exhibit_a_id | FK → dcfg_exhibit_a | |
| dcfg_name | String(200) | "Demo & Prep" |
| dcfg_sequence | Integer | Order |
| dcfg_cumulative_cap | Currency | Max billing through this milestone |
| dcfg_period_cap | Currency | Max billing per period |
| dcfg_period_type | Choice | Monthly/Quarterly |
| dcfg_completed | Boolean | |
| dcfg_completed_date | DateTime | |

**dcfg_purchase_order** — PO tracking (BidComp didn't have this)

| Column | Type | Notes |
|--------|------|-------|
| dcfg_purchase_order_id | PK | |
| dcfg_po_number | String(50) | |
| dcfg_phase_id | FK → dcfg_phase | |
| dcfg_vendor_id | FK → dcfg_vendor | |
| dcfg_description | String(500) | |
| dcfg_quantity | Decimal | |
| dcfg_unit_price | Currency | |
| dcfg_total | Currency | |
| dcfg_order_date | DateTime | |
| dcfg_status | Choice | Ordered/Received/Invoiced/Paid |
| dcfg_invoice_received | Boolean | |

### 3.3 Additions to Existing Tables

**dcfg_vendor** — add columns:

| Column | Type | Notes |
|--------|------|-------|
| dcfg_trades | String(500) | CSV multi-select from 20 trade categories |
| dcfg_latitude | Decimal | Geocoded on address save |
| dcfg_longitude | Decimal | |
| dcfg_vendor_status | Choice | Pending/Approved/Flagged/Inactive |
| dcfg_vendor_ref_number | String(50) | Unique reference |

**dcfg_rfp** — add columns to BidComp's existing table:

| Column | Type | Notes |
|--------|------|-------|
| dcfg_trades | String(500) | CSV of applicable trades |
| dcfg_financial_structure | Multiline(max) | JSON: amortization, period caps |
| dcfg_deadline | DateTime | Bid due date |

### 3.4 Trade Categories (20 — Approved)

```
Alarm, Carpentry/Framing, Concrete, Counter Tops, Demolition,
Drywall, Electrical, Fencing, Flooring/Ceramic Tile,
General Maintenance, HVAC, Inspections, Landscaping/Grounds,
Masonry, Paint, Plumbing, Roofing, Siding/Gutters,
Sprinkler/Fire Protection, Tree Removal
```

---

## 4. Screens

### 4.1 Program Dashboard — `/programs/:id`

Leon's "Dashboard" sheet digitized.

- **Budget bar:** Total allocated vs committed vs spent
- **Project status breakdown:** pie/bar by status (Not Started through Completed)
- **Service line breakdown:** Adult North / Adult South / Childrens
- **Sub vs Self split:** how much work is subcontracted vs self-performed
- **Schedule health:** projects on time vs behind vs ahead
- **Quick actions:** New Project, Create RFP, Download Tracker

### 4.2 Project List — `/projects`

Leon's "FY26 Project Tracker" sheet digitized.

- Table with all tracker columns
- Sortable, searchable, filterable by: status, service line, PM, planned/unplanned, trade
- Bulk select → "Create RFP from Selected"
- Status badges matching Leon's vocabulary
- Budget variance column (over/under with red/green)
- **"Download as Excel"** button → fresh populated spreadsheet
- **"Upload Changes"** button → diff engine → validation screen

### 4.3 Project Detail — `/projects/:id`

- Scope description, status, PM, schedule
- Budget breakdown card (Material/Labor/Equipment/Sub/Other vs Actuals)
- Linked RFP (if Out to Bid)
- Linked Contract (if awarded)
- PO list for this project
- Invoice list for this project
- Suggested trades (from description, editable)
- Timeline/activity log

### 4.4 RFP Builder — `/rfps/new`

The multi-project bid package assembly.

**Step 1: Select Projects**
- Pre-populated if user came from bulk select on project list
- Or search/filter/add projects manually
- Shows property names, descriptions, estimated budgets

**Step 2: Set Trades**
- System suggests trades based on project descriptions (AI keyword match)
- User confirms/adjusts
- Multi-select from 20 approved trades

**Step 3: Financial Structure**
- Total contract value (sum of selected project budgets or manual)
- Amortization period (months)
- Billing cap per period (monthly/quarterly)
- Milestone definitions (name, cumulative cap)
- Visual: timeline showing milestone gates + period caps

**Step 4: Vendor Selection**
- System filters: trade match + proximity to project properties + MSA status + vendor status (Approved only)
- Results sorted by distance, showing trade coverage
- Multi-trade vendors appear once with all matching trades shown
- User checks vendors to include
- Override: manually add vendor not in suggestions

**Step 5: Review & Send**
- Summary: X projects, Y vendors, Z trades, $Total budget
- RFP document auto-generated (or template from SharePoint)
- Send → emails blast to selected vendors
- Status → "Sent", deadline countdown starts

### 4.5 RFP Tracking — `/rfps/:id`

- Status board: which vendors responded, which haven't, deadline
- Per-vendor: sent date, opened?, response status, proposal link
- Chase button for non-responders (re-send reminder)
- "Close Bidding" when deadline passes or all responses in

### 4.6 Bid Leveling — `/rfps/:id/compare`

BidComp's leveling matrix.

- Side-by-side proposals: vendor columns, line item rows
- Normalized to common line items (system suggests matches)
- Gap analysis: red cells where a vendor is missing a line item
- Total comparison row
- Scoring: price rank, completeness rank, combined rank
- Notes per vendor per line item
- **"Download Comparison"** → Excel for offline review
- **Award button** per vendor → flows to contract creation

### 4.7 Award → Contract

From bid leveling:
- Select winning vendor(s) — may split by trade
- One click → NewContractWizard pre-filled:
  - Customer (from program)
  - Vendor (award winner)
  - Properties (from RFP projects)
  - Line items (from winning proposal)
  - Financial structure (from RFP milestones + caps)
- Contract type pre-set to Work Order
- Milestones carry forward for billing enforcement

### 4.8 PO & Invoice Tracking

Lightweight screens within project detail:
- PO list: add/edit POs, link to vendor, track receipt
- Invoice list: link to PO, track payment status
- Both available as Excel round-trip (download populated, modify, upload diff)

---

## 5. Financial Engine

### 5.1 Billing Validation

Two simultaneous constraints:
```
max_billable = MIN(
  milestone_cumulative_cap,        -- can't bill past completed milestone
  period_cap × periods_elapsed     -- can't exceed period maximum
)
```

The lower of the two wins. System warns when approaching either cap.

### 5.2 Budget Tracking

Per project:
```
Budget = Material + Labor + Equipment + Sub + Other
Actual = sum of invoiced amounts
Variance = Budget - Actual (negative = over budget)
```

Per program:
```
Program Budget = sum of all project budgets
Committed = sum of awarded contract values
Spent = sum of invoiced/paid amounts
Available = Program Budget - Committed
```

### 5.3 Multi-Year Amortization Display

Visual timeline:
```
|---Q1---|---Q2---|---Q3---|---Q4---|---Q1---|---Q2---|
  $10K     $10K     $10K     $10K     $10K     $10K    ← period caps
  ████     ████     ██                                  ← actual spend
       [M1: $60K cap]     [M2: $180K cap]    [M3: $240K cap]
```

---

## 6. Trade-to-Description AI Assist

Keyword map built from Leon's 91 actual project descriptions:

```javascript
const TRADE_KEYWORDS = {
  'Plumbing':              ['bathroom', 'tub', 'shower', 'plumb', 'water', 'drain', 'walk.in'],
  'Flooring/Ceramic Tile': ['floor', 'tile', 'carpet', 'vinyl', 'lvt', 'ceramic'],
  'Electrical':            ['electric', 'generator', 'wiring', 'panel', 'outlet', 'light'],
  'HVAC':                  ['hvac', 'heating', 'cooling', 'furnace', 'ac ', 'air condition'],
  'Roofing':               ['roof', 'shingle', 'gutter'],
  'Siding/Gutters':        ['siding', 'gutter', 'exterior.*wall'],
  'Paint':                 ['paint', 'wall protection', 'bead.?board'],
  'Carpentry/Framing':     ['door', 'window', 'deck', 'porch', 'stair', 'cabinet', 'kitchen', 'framing', 'structural'],
  'Concrete':              ['concrete', 'driveway', 'sidewalk', 'foundation'],
  'Drywall':               ['drywall', 'ceiling', 'wall.*damage'],
  'Demolition':            ['demo', 'removal.*structure', 'tear.?down'],
  'Fencing':               ['fence', 'fencing', 'gate'],
  'Landscaping/Grounds':   ['landscap', 'yard', 'drainage', 'grad(e|ing)', 'ground'],
  'Counter Tops':          ['counter', 'granite', 'marble'],
  'Alarm':                 ['alarm', 'fire.*alarm', 'security'],
  'Sprinkler/Fire':        ['sprinkler', 'fire.*suppress', 'fire.*comply'],
  'Inspections':           ['inspect', 'licensing', 'punch.?list'],
  'Masonry':               ['brick', 'masonry', 'block', 'stone'],
  'Tree Removal':          ['tree', 'stump', 'limb'],
  'General Maintenance':   ['renovati', 'remodel', 'finish.*basement', 'general'],
};
```

On project description input:
1. Run description against keyword map
2. Return matches sorted by confidence (number of keyword hits)
3. Show as suggested badges: "Suggested: Plumbing, Flooring — confirm?"
4. User clicks to accept/reject/add trades

---

## 7. Vendor Discovery Engine

When building RFP vendor list:

```
INPUT: trades[], property_ids[], radius_miles
PROCESS:
  1. Get lat/lng for each property
  2. Get centroid (or use each property individually)
  3. Query dcfg_vendor where:
     - dcfg_vendor_status = Approved
     - dcfg_trades contains ANY of input trades
     - Haversine distance <= radius_miles
  4. For multi-trade vendors: show ALL matching trades
  5. Sort by: distance ASC, trade_match_count DESC
OUTPUT: vendor list with distance, matched trades, MSA status
```

Geocoding happens on-demand when vendor address is saved (see project_vendor_management.md).

---

## 8. Excel Round-Trip Implementation

### 8.1 Generate Populated Spreadsheet

```javascript
// portalApi.js
export async function generateTracker(programId) {
  // 1. Query all projects for this program
  const projects = await apiGet(`/dcfg_projects?$filter=_dcfg_program_id_value eq '${programId}'&$expand=...`);
  // 2. Fetch Excel template from SharePoint
  const template = await getSharePointFile('ProjectTemplates/Project_Tracker_Template.xlsx');
  // 3. Populate with ExcelJS (client-side) or server-side flow
  // 4. Save to SharePoint working docs
  // 5. Return download URL
}
```

### 8.2 Diff Engine

```javascript
export async function diffTracker(uploadedFile, programId) {
  // 1. Parse uploaded Excel
  // 2. Query current Dataverse state
  // 3. Match rows by primary key (phase_number + wo_number)
  // 4. For each row:
  //    - NEW: row in Excel not in Dataverse → insert candidate
  //    - MODIFIED: row differs → show field-by-field diff
  //    - DELETED: row in Dataverse not in Excel → soft delete candidate
  //    - CONFLICT: Dataverse modified since spreadsheet was generated → flag
  // 5. Return diff summary for validation UI
}
```

### 8.3 Validation Screen

Modal or full-screen diff view:
- Table: Row | Field | Current Value | New Value | Accept?
- Color coding: green (new), amber (modified), red (deleted), purple (conflict)
- Batch controls: Accept All, Reject All, Accept New Only
- On confirm: write accepted changes to Dataverse, audit log each

---

## 9. Navigation Integration

### 9.1 NavPanel Updates

Add to NAV_GROUPS under a new "PROJECTS" section:
```javascript
{
  label: 'PROJECTS',
  items: [
    { to: '/programs',  label: 'Programs',  icon: <ProgramIcon /> },
    { to: '/projects',  label: 'Projects',  icon: <ProjectIcon /> },
    { to: '/rfps',      label: 'RFPs',      icon: <RfpIcon /> },
  ],
}
```

Add to CREATE zone:
```javascript
{ key: 'create-project', label: 'New Project', to: '/projects/new', icon: <NewContractIcon /> },
{ key: 'create-rfp',     label: 'New RFP',     to: '/rfps/new',     icon: <NewContractIcon /> },
```

All items get role switches in Admin Navigation matrix.

### 9.2 Route Registration

Add to AppRouter.jsx:
```
/programs          → ProgramList
/programs/:id      → ProgramDashboard
/projects          → ProjectList
/projects/new      → ProjectForm
/projects/:id      → ProjectDetail
/rfps              → RfpList
/rfps/new          → RfpBuilder
/rfps/:id          → RfpTracking
/rfps/:id/compare  → BidLeveling
```

---

## 10. Agent Build Instructions

### 10.1 Schema Agent

Create all new tables and columns on Test environment (org0c17e98d):
- 8 new tables: dcfg_project, dcfg_rfp, dcfg_rfp_project, dcfg_rfp_vendor, dcfg_proposal, dcfg_proposal_line, dcfg_purchase_order, dcfg_milestone
- 5 new columns on dcfg_vendor: dcfg_trades, dcfg_latitude, dcfg_longitude, dcfg_vendor_status, dcfg_vendor_ref_number
- All choice fields with defined option set values
- All relationships with proper FK columns
- Add to DCFGSystemTest solution

### 10.2 SPA Agent

Build screens in order:
1. ProjectList (table view, search, filter, Excel download/upload)
2. ProjectDetail (budget cards, linked entities)
3. ProgramDashboard (KPIs, budget burn, status breakdown)
4. RfpBuilder (5-step wizard)
5. RfpTracking (vendor response board)
6. BidLeveling (comparison matrix)

Use DCFG Component Library patterns. All elements get data-testid.

### 10.3 Excel Agent

Build the round-trip engine:
1. Template population (Dataverse → Excel)
2. Diff engine (uploaded Excel vs Dataverse)
3. Validation UI (change review screen)
4. SharePoint file operations (read/write templates and working docs)

### 10.4 Test Samples

**Test 1: Spreadsheet Round-Trip**
```
1. Navigate to /projects for Bancroft FY26 program
2. Click "Download Tracker"
3. Open in Excel, change 3 project statuses, add 1 new project
4. Save to SharePoint
5. Click "Upload Changes"
6. Verify diff shows: 3 modified, 1 new
7. Accept all
8. Verify Dataverse updated
9. Download again — verify changes persisted
```

**Test 2: RFP Assembly & Distribution**
```
1. Select 5 projects with "Not Started" status on project list
2. Click "Create RFP"
3. System suggests trades: Plumbing (3 projects), Electrical (2 projects)
4. Set financial structure: $150K total, 12 months, $12.5K/month cap
5. Add 2 milestones: Prep ($50K), Install ($150K)
6. System suggests 4 vendors (2 plumbers, 2 electricians within 25mi)
7. Vendor B does both trades — appears once with both shown
8. Select all, click Send
9. Verify RFP status = Sent, 4 vendor rows created with Pending status
```

**Test 3: Bid Leveling & Award**
```
1. Upload 3 proposal PDFs for an RFP
2. Enter line items for each proposal
3. Navigate to Compare view
4. Verify side-by-side matrix shows all vendors
5. Verify gap detection (Vendor C missing "thermostat replacement")
6. Click Award on Vendor A for Plumbing
7. Verify contract wizard opens pre-filled with:
   - Customer from program
   - Vendor A
   - Properties from RFP
   - Line items from Vendor A's proposal
   - Milestones from RFP financial structure
```

**Test 4: Billing Cap Enforcement**
```
1. Create contract with milestones and monthly cap
2. Attempt to create invoice exceeding monthly cap → system blocks
3. Complete milestone 1 → billing cap rises to milestone 1 cumulative
4. Attempt invoice exceeding new cap → blocked
5. Verify: max_billable = MIN(milestone_cap, period_cap × months)
```

---

## 11. Data Migration: Leon's Existing Data

Seed the system with real data from the analyzed spreadsheets:

- **91 projects** from FY26 Project Tracker → dcfg_project
- **22 POs** from Purchase Order Log → dcfg_purchase_order
- **13 vendors with trades** from Directory of Subcontractors → update dcfg_vendor
- **170+ properties** already in dcfg_property (Bancroft locations)

Import script reads the Excel files, transforms to Dataverse schema, upserts. This provides immediate value — Leon sees his data on day one.

---

## 12. Connection Map (Unified BidComp + DCFG)

```
dcfg_prime_contract (Bancroft FY26 GHSP — budget + customer + FY)
  └── dcfg_phase (work items — Leon's tracker rows)
        ├── dcfg_rfp (bid package — procurement checklist)
        │     ├── dcfg_rfp_vendor (distribution — NEW)
        │     │     └── dcfg_vendor (trades, proximity, MSA status)
        │     ├── dcfg_proposal (bids — with AI parsing + gaps)
        │     └── dcfg_milestone (billing caps — NEW)
        ├── dcfg_exhibit_a (awarded work order)
        │     ├── dcfg_exhibit_b (scope of work + CSI codes)
        │     ├── dcfg_change_order (amendments)
        │     └── dcfg_milestone (payment schedule)
        ├── dcfg_invoice (billing pipeline)
        ├── dcfg_purchase_order (PO tracking — NEW)
        ├── dcfg_cadenced_svc (recurring services)
        │     └── dcfg_service_period (period tracking)
        └── dcfg_contract (DCFG SPA — document generation)
              └── dcfg_contract_line (Exhibit A line items)
```

**Reads from DCFG SPA:** dcfg_vendor, dcfg_customer, dcfg_property
**Writes to DCFG SPA:** dcfg_contract (on Award — pre-filled contract creation)
**BidComp tables (10):** prime_contract, phase, exhibit_a, exhibit_b, change_order, invoice, rfp, proposal, cadenced_svc, service_period
**New tables (3):** rfp_vendor, milestone, purchase_order
