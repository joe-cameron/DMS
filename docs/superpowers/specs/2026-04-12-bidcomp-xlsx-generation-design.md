# BidComp XLSX Generation — Design Spec

**Date:** 2026-04-12
**Status:** Approved
**Branch:** code-review-2026-04-09
**Mockup:** `C:\dcfg\clipboard.html`

## Summary

Generate populated multi-trade bid comparison xlsx workbooks from project line items, with on-demand per-trade single-sheet extraction for vendor distribution. Built with ExcelJS on the existing Azure Function host. Follows DocGen V4 pattern: `createDocumentRequest()` → Flow → Azure Function → dual save (SharePoint + Dataverse link) → view link to user. Includes "Import Bids" to read completed spreadsheets back into `dcfg_proposal` records.

## Workflow

1. **RFP Detail screen** → user clicks "Generate Bid Comp"
2. **Configure panel** opens, **pre-loaded with existing linked projects and vendors** from the RFP record. User reviews and adjusts:
   - Customer (pre-filled from RFP)
   - Program (optional — links to budget rollup)
   - Location(s) (mandatory)
   - Projects (pre-loaded from existing rfp_project junctions, user adds/removes)
   - DCG Fee % (default 16.3, overridable)
   - Trades detected (derived from selected projects' `dcfg_trades` field)
   - Vendor assignment (pre-loaded from existing rfp_vendor junctions, user adjusts via trade-tabbed slide-out)
3. **Generate** → SPA pre-saves config to Dataverse, then `createDocumentRequest()`
4. **Flow** reads all data from Dataverse, calls Azure Function
5. **Azure Function** builds full workbook via ExcelJS
6. **Dual save** to SharePoint (`DCFG_Outputs/{Customer}/{Year}/BidComp/{RFP Name}.xlsx`) + link on `dcfg_rfp_package`. SharePoint native versioning preserves prior versions on regeneration.
7. **View link** returned to user
8. **Living document** — user opens in Excel, enters vendor bids per trade, saves back to SharePoint
9. **Import Bids** — user clicks "Import Bids" on RfpDetail, system reads the xlsx from SharePoint, parses PRICING per trade tab, creates/updates `dcfg_proposal` records. Closes the loop between spreadsheet and SPA.
10. **Extract Trade Sheet** — on-demand, per trade. User clicks a trade on RfpDetail → "Extract for Vendor" → generates a single-tab xlsx with just that trade's sheet. No multi-tab per-trade files.

## Data Hierarchy

**Naming note:** The SPA displays "Program" but the Dataverse entity set is `dcfg_programs`. The `dcfg_project` table links to programs via the legacy-named lookup `dcfg_portfolioid`. This is documented in portalApi.js line 886-892. All references to "Program" in this spec use the SPA terminology; the Dataverse lookup name remains `dcfg_portfolioid`.

```
Customer (dcfg_customer)
  └─ Program (entitySet: dcfg_programs) — optional, budget rollup
       │   Fields: dcfg_budget_total, dcfg_budget_committed, dcfg_budget_remaining
       └─ Location(s) (dcfg_property) — mandatory
            └─ Project(s) (dcfg_project) — multi-select
                 │   Links to program via: dcfg_portfolioid (legacy name)
                 │   Field: dcfg_trades (plural, comma-separated String)
                 └─ Line Items (dcfg_project_line_item) — grouped by dcfg_trade
                      Field: dcfg_trade (singular, String)
```

**Vendor field:** `dcfg_vendor.dcfg_trade` (singular, String).

When a bid comp is awarded, the SPA patches the linked program's `budget_committed` with the total awarded cost in the same handler as the Award status transition.

## Data Flow — What Feeds the Workbook

| Source | Data | Destination |
|--------|------|-------------|
| `dcfg_rfp_package` | Name, deadline, DCG Fee %, scope | Workbook header + every trade tab header |
| `dcfg_project` (linked) | Project name, location, cost code | Workbook header. Multiple projects: "Multiple Projects (N)" with full list on EXHIBIT B |
| `dcfg_project_line_item` | Description, trade, type, UOM, qty, rate | SPECIFIC SCOPE section on matching trade tab |
| `dcfg_rfp_vendor` (matched) | Vendor name, license, contact, email | BIDDER columns (up to 5 per trade tab) |
| `dcfg_rfp_package` | DCG Fee % | PRICING formula row on every trade tab |
| Program (dcfg_programs) | Budget total/committed/remaining | Award feeds back to budget_committed |
| Boilerplate (code-side) | General Conditions, Standard Requirements, Documents, Payment Terms | Fixed sections on every trade tab |

## Workbook Structure

### Trade Tabs (one per detected trade)

Each trade tab contains these sections in order:

1. **Header**: Company name (row 1), "BID COMPARISON — {Trade Name} | CSI {code}" (row 2), Project, Location, Date
2. **Bidder grid** (5 columns): Contractor Name, Status, License #, Contact/Email
3. **SPECIFIC SCOPE — {Trade Name}**: Line items from project line items matching this trade
4. **ALTERNATES**: Placeholder rows
5. **GENERAL CONDITIONS**: Fixed boilerplate (field conditions, benchmark/layout, coordination, cleanup, protection)
6. **STANDARD REQUIREMENTS**: Fixed boilerplate (sales tax exempt, code compliance, submittals, liens, smoking, security, cleanup, deliveries, work hours, warranties)
7. **DOCUMENTS**: CD Plans & Specs, Exhibit C (schedule), Exhibit D (lien release)
8. **PAYMENT TERMS**: Net 30 paid-when-paid, AIA format, constructionap@ email, lien release
9. **ACCEPTED EXCLUSIONS / CLARIFICATIONS**: Placeholder rows
10. **PRICING**: Base Contract, Alternates, Allowances → Sub-Total → DCG Fee (%) → DCG Fee ($) → CONTRACT TOTAL → Low Bid / High Bid / Spread

### DASHBOARD Sheet

Roll-up summary across all trades. One row per trade:

| Column | Content |
|--------|---------|
| Trade | Trade name |
| # Bidders | Count of vendors assigned to this trade |
| Low Bid | `=MIN()` across bidder CONTRACT TOTAL cells on that trade tab |
| High Bid | `=MAX()` across bidder CONTRACT TOTAL cells on that trade tab |
| Spread | `=High - Low` |
| Recommended | Empty — user fills in after evaluation |
| Contract Total | `=` reference to recommended bidder's CONTRACT TOTAL |

**Footer row:** Grand total across all trades (sum of Contract Total column). This is the project-level number that feeds back to program budget on award.

### BID TRACKER Sheet

Per-vendor per-trade status grid. Matches the procurement checklist on RfpDetail:

| Column | Content |
|--------|---------|
| Trade | Trade name |
| Vendor | Vendor name |
| Bid Solicited | Empty checkbox (Y/N) — user fills in |
| Bid Received | Empty checkbox (Y/N) |
| Amount | Empty — user fills in or populated by Import Bids |
| Scope Exhibit | Empty checkbox (Y/N) |
| Contract Out | Empty checkbox (Y/N) |
| Contract Executed | Empty checkbox (Y/N) |
| Submittals Received | Empty checkbox (Y/N) |

Pre-populated with one row per vendor-trade assignment. Columns after Vendor are empty at generation — this is a tracking tool the PM fills in as the process progresses.

### BID REQ Sheet

RFP cover sheet / bid solicitation instructions:

| Section | Content |
|---------|---------|
| Header | Company name, "REQUEST FOR BID" |
| Project | Project name(s), Location, Date |
| Scope Summary | `dcfg_scope_description` from rfp_package |
| Trades Included | List of trade names |
| Deadline | `dcfg_deadline` from rfp_package |
| Submission | "Submit bids to constructionap@decades-cg.com by {deadline}" |
| Contact | DCG project contact info |
| Instructions | "Review attached trade-specific scope sheets. Submit pricing per trade on the provided bid form." |
| Terms | Reference to General Conditions, Standard Requirements, Payment Terms |

### EXHIBIT B Sheet

Consolidated scope of work — all line items across all trades in one table:

| Column | Content |
|--------|---------|
| # | Sequence number |
| Trade | Trade name |
| Description | Line item description |
| Type | Material / Labor |
| UOM | Unit of measure |
| Qty | Quantity |
| Unit Rate | Rate (empty — for vendor to fill in) |
| Extended | Formula: Qty × Unit Rate |

Grouped by trade with subtotals per trade group. This is the scope exhibit that accompanies the contract — a single view of all work included in the bid comp.

## Configure Panel — UX

### Pre-loading existing data

When the configure panel opens, it loads:
- Existing `dcfg_rfp_project` junction records → pre-checked in the project list
- Existing `dcfg_rfp_vendor` junction records → pre-populated in the vendor assignment panel
- Existing `dcfg_fee_pct` on the rfp_package → pre-filled (or 16.3 default)
- Existing `dcfg_portfolioid` → pre-selected program

The user reviews and adjusts — they don't start from scratch.

### Steps 1–6: Inline in configure panel

- **Customer**: Pre-filled from RFP's `dcfg_customer_id`. Change button available.
- **Program**: Dropdown of customer's programs via `fetchProgramsByCustomer()`. Shows budget total + % committed. Optional.
- **Location(s)**: Mandatory. Dropdown of customer's active properties. Multi-select chips. Each shows WIP project count.
- **Projects**: Filtered to selected customer + location(s). Grouped by location header. Checkbox multi-select with filter input. Shows job #, trades, estimated cost per row. **Pre-checked** for any projects already linked to this RFP.
- **DCG Fee %**: Number input, default 16.3. Also: Max Bidders Per Trade (default 5).
- **Trades Detected**: Derived from selected projects' `dcfg_trades` field (comma-split, deduplicated). Blue chips with trade name. Trade detection uses the project-level field, NOT individual line items — line items are fetched server-side by the Flow during generation.

### Step 7: Vendor Assignment — Trade-Tabbed SlideOut Panel

This is the primary interaction surface. The user works through every trade assigning vendors.

**Panel behavior:**
- Opens once from the configure panel, stays open
- Trade tabs across the top with progress indicators (e.g., "Plumbing 2/5 ✓", "Fire Alarm 0/5 ←")
- Green tab = has vendors assigned. Amber/active = current. Grey = pending.
- User clicks through tabs to assign vendors for each trade
- **Pre-loaded**: Vendors already in `dcfg_rfp_vendor` with matching `dcfg_trade_assignment` appear as pre-assigned chips

**Per-trade view inside panel:**
- **Assigned area** (top): Removable chips showing vendors already assigned to this trade
- **Search bar**: Filters across vendor name, contact, city, license, trade
- **"Match trade" checkbox**: Pre-checked. Filters vendor list to vendors whose `dcfg_trade` matches current tab (case-insensitive contains). Uncheck to see all vendors.
- **Vendor list**: Scrollable. Each row shows: name, trades, city/state, license, contact. Click to instantly assign (no separate confirm step).
- **"Also on" badge**: Vendors assigned to other trades in this bid comp show a blue badge (still selectable — a vendor can bid multiple trades).
- **Max 5 enforced**: When 5 vendors assigned to current trade, remaining checkboxes disabled.

**Footer:**
- Overall progress chips for all trades at a glance
- "Done — Back to Configure" button returns to configure panel with assignments reflected in trade rows

**Data source:** `fetchVendors()` — existing function, returns all active vendors with `dcfg_trade` field for auto-matching.

## Azure Function — ExcelJS Generation

### Route

New route on existing `html-to-pdf` Azure Function host:
- `POST /api/generateBidComp`

### Input (JSON payload assembled by Flow from Dataverse)

```json
{
  "rfpPackageId": "guid",
  "rfpName": "2026 HVAC + Fire Alarm — Main Campus",
  "customerName": "...",
  "locationName": "Main Campus, Newark",
  "projectDate": "2026-04-12",
  "dcgFeePct": 16.3,
  "projects": [
    { "name": "Full Bathroom Rehab", "jobNumber": "FP-2026-001", "costCode": "..." }
  ],
  "trades": [
    {
      "tradeName": "Plumbing",
      "csiCode": "",
      "scopeItems": [
        { "description": "...", "lineType": "Material", "uom": "Each", "qty": 4, "rate": 250 }
      ],
      "vendors": [
        { "name": "ABC Plumbing", "license": "PL-2024-1234", "contact": "John Doe", "email": "john@abc.com", "status": "Bidding" }
      ]
    }
  ],
  "scopeDescription": "...",
  "deadline": "2026-05-01"
}
```

### Output

- Single full workbook buffer (`.xlsx`) — all trade tabs + DASHBOARD + BID TRACKER + BID REQ + EXHIBIT B
- Returned to Flow as base64 for SharePoint upload

### Implementation Library: ExcelJS

Use `exceljs` (npm) rather than raw OOXML XML authoring. ExcelJS provides a high-level API for:
- Creating workbooks/worksheets programmatically
- Cell formatting (fonts, fills, borders, alignment, number formats)
- Merged cells
- Formulas (`=SUM()`, `=MIN()`, `=MAX()`, etc.)
- Column widths, row heights
- Writing to buffer for upload

Formulas in PRICING section: `=SUM()` for sub-total, `=sub_total * fee_pct` for DCG Fee, `=sub_total + fee` for CONTRACT TOTAL, `=MIN()` / `=MAX()` for Low/High Bid

### SharePoint Save

```
DCFG_Outputs/
  {Customer}/
    {Year}/
      BidComp/
        {RFP Name}.xlsx          ← full workbook (regeneration overwrites, SP versioning preserves history)
```

Per-trade single-sheet files are generated on-demand via "Extract Trade Sheet" and saved alongside:
```
        {RFP Name} — {Trade}.xlsx   ← single-tab, generated on demand
```

## Import Bids — Closing the Loop

After vendor bids are entered into the spreadsheet and saved to SharePoint:

1. User clicks **"Import Bids"** button on RfpDetail
2. SPA (or Azure Function) reads the xlsx from the `dcfg_bidcomp_sp_url`
3. For each trade tab, parses the PRICING section:
   - Reads each bidder column's Base Contract, Alternates, Allowances, Sub-Total, DCG Fee, CONTRACT TOTAL
   - Reads Contractor Name, License, Contact from the bidder grid
4. Creates or updates `dcfg_proposal` records:
   - One proposal per vendor per trade
   - Fields: `dcfg_trade`, `dcfg_base_contract`, `dcfg_sub_total`, `dcfg_contract_total`, `dcfg_bidder_license`, `dcfg_bidder_contact`
   - Linked to `dcfg_rfp_package` and `dcfg_vendor`
5. RfpDetail Vendors tab now shows actual bid values — the existing proposals-by-trade comparison table with low-bid highlighting lights up

**Implementation approach:** New Azure Function route `POST /api/importBidComp` — receives the SP file URL, fetches the xlsx, parses with ExcelJS, returns structured JSON. SPA creates the proposal records.

## Extract Trade Sheet — On Demand

Per-trade single-tab xlsx files are NOT pre-generated. Instead:

1. On RfpDetail, each trade in the Vendors tab shows an **"Extract for Vendor"** button
2. Click triggers a lightweight generation: takes just that trade's sheet from the full workbook structure and produces a standalone single-tab xlsx
3. This can be done client-side (ExcelJS in browser) or server-side. Since it's one sheet, browser-side is fine.
4. Downloaded to the user's browser. Optionally saved to SharePoint alongside the full workbook.

This avoids generating 14 separate files upfront when the user may only need 2-3.

## Award → Budget Rollup

When the user clicks "Award" on RfpDetail (existing `transitionStatus(RfpStatus.Awarded)`):

1. Existing behavior: PATCH `dcfg_rfp_package` status to Awarded
2. **New behavior**: If `dcfg_portfolioid` is set on the rfp_package:
   - Sum the total awarded cost from DASHBOARD grand total (or from proposal records if Import Bids has run)
   - PATCH the program's `dcfg_budget_committed` += awarded total
   - Toast: "Awarded — $X committed to {Program Name} ({pct}% of budget)"

This is SPA-side logic in the existing Award handler on RfpDetail.

## Schema Changes

### Existing Tables (already in Dataverse + SPA)

These tables already exist and are used by RfpList, RfpDetail, NewRfpWizard in dcfg-shell:

- `dcfg_rfp_package` (entitySet: `dcfg_rfp_packages`) — the bid comp record
- `dcfg_rfp_project` (entitySet: `dcfg_rfp_projects`) — junction: rfp ↔ project
- `dcfg_rfp_vendor` (entitySet: `dcfg_rfp_vendors`) — junction: rfp ↔ vendor
- `dcfg_proposal` (entitySet: `dcfg_proposals`) — vendor bids per trade

### dcfg_rfp_package — new fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `dcfg_fee_pct` | Decimal | 16.3 | DCG Fee percentage for this bid comp |
| `dcfg_bidcomp_sp_url` | URL | null | SharePoint link to generated full workbook |
| `dcfg_portfolioid` | Lookup → program (via dcfg_programs) | null | Optional program link for budget rollup |

### dcfg_rfp_vendor — new field

| Field | Type | Purpose |
|-------|------|---------|
| `dcfg_trade_assignment` | String (Memo) | Comma-separated trade names this vendor is assigned to for this RFP. Populated by the vendor assignment panel. |

### dcfg_document_requests — new request type

| Value | Label |
|-------|-------|
| `100000004` | BidComp |

## Existing Code Reused

- `createDocumentRequest()` in portalApi.js — standard transaction pattern
- `SlideOutPanel.jsx` — existing shell component
- `fetchVendors()` — existing in dcfg-shell portalApi (line 481)
- `fetchProgramsByCustomer()` — existing in dcfg-shell portalApi (line 557)
- `fetchProjectLines()` — existing in dcfg-shell portalApi (line 900)
- `fetchRfpProjects()` / `fetchRfpVendors()` — existing, for pre-loading panel
- `createRfpProject()` / `createRfpVendor()` — existing, for saving junctions
- `useTableControls` — for search/sort in vendor list
- Azure Function host (`html-to-pdf`) — new routes added
- New dependency: `exceljs` — npm install on the Azure Function

## Payload Transport — SPA to Azure Function

The SPA does NOT pass the full payload through the document request. Instead:

**SPA pre-save sequence:**
1. PATCH `dcfg_rfp_package` with `dcfg_fee_pct`, `dcfg_portfolioid` (if program selected)
2. POST/DELETE `dcfg_rfp_project` junction records to match selected projects (diff against existing)
3. POST/DELETE `dcfg_rfp_vendor` junction records with `dcfg_trade_assignment` per vendor-trade pair (diff against existing)
4. Call `createDocumentRequest({ type: DocRequestType.BidComp, rfpPackageId })`

**Flow data assembly:**
1. Reads `dcfg_rfp_package` for header fields + fee %
2. Reads `dcfg_rfp_project` junction → expands `dcfg_project_id` for project details
3. For each project, reads `dcfg_project_line_item` where `dcfg_active_flag eq true`
4. Reads `dcfg_rfp_vendor` junction → expands `dcfg_vendor_id` for vendor details
5. Assembles the full payload JSON
6. Calls `POST /api/generateBidComp` with assembled payload
7. Receives xlsx buffer, uploads to SharePoint
8. PATCHes `dcfg_rfp_package.dcfg_bidcomp_sp_url` with SharePoint link
9. Updates document request status to Complete

## Trade Matching Strategy

`dcfg_vendor.dcfg_trade` and `dcfg_project.dcfg_trades` are free-text String fields.

**Panel trade detection:** Uses `dcfg_project.dcfg_trades` (comma-split, deduplicated across selected projects). Does NOT fetch line items — that happens server-side.

**Vendor auto-match:** The "Match trade" checkbox does **case-insensitive contains** matching between the vendor's `dcfg_trade` and the current tab's trade name. Best-effort — user can uncheck to see all vendors.

**Long-term:** Migrate `dcfg_trade` to a Picklist or multi-select Choices column for exact matching.

## Not In Scope

- Email delivery of per-trade RFPs to vendors (future — extract + email in one action)
- Auto-generation on status transition (user-initiated only)
- Boilerplate configurability (General Conditions etc. are code-side for now)
- More than 5 bidders per trade
- CSI code assignment (placeholder in header, user fills in)
