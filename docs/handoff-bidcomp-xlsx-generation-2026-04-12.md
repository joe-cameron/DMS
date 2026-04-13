# Handoff: BidComp XLSX Generation

**Date:** 2026-04-12
**Spec:** `docs/superpowers/specs/2026-04-12-bidcomp-xlsx-generation-design.md`
**Mockup:** `C:\dcfg\clipboard.html`
**Branch:** `code-review-2026-04-09`
**Reference xlsx:** `C:\dcfg\DCG_Multi_Trade_Bid_Template (version 1).xlsx`

## What This Is

Generate populated multi-trade bid comparison xlsx workbooks from project line items. Per-trade single-sheet extraction on demand. Import Bids reads completed spreadsheets back into the SPA. ExcelJS on the existing Azure Function host.

## Implementation Phases

### Phase 1 — Schema + Azure Function

**Goal:** New Dataverse fields + the ExcelJS function that produces the workbook.

1. Add `dcfg_fee_pct` (Decimal, default 16.3), `dcfg_bidcomp_sp_url` (URL), `dcfg_portfolioid` (Lookup → program) to `dcfg_rfp_package`
2. Add `dcfg_trade_assignment` (Memo) to `dcfg_rfp_vendor`
3. Add `100000004` / BidComp to `dcfg_request_type` picklist on `dcfg_document_requests`
4. `npm install exceljs` in `azure-functions/html-to-pdf/`
5. Build `POST /api/generateBidComp` — accepts JSON payload, returns xlsx buffer:
   - Trade tabs (10-section structure per the spec)
   - DASHBOARD (trade roll-up, formulas for Low/High/Spread/Grand Total)
   - BID TRACKER (vendor × trade status grid, empty checkboxes)
   - BID REQ (cover sheet with project/scope/deadline/instructions)
   - EXHIBIT B (consolidated scope table, all line items grouped by trade)
6. Test locally with sample payload from the reference xlsx structure
7. Deploy Azure Function

### Phase 2 — Flow

**Goal:** Dataverse-triggered flow assembles payload and calls the function.

1. New Flow triggered by `dcfg_document_requests` where `dcfg_request_type = 100000004`
2. Flow reads rfp_package → rfp_projects (expand project) → project_line_items per project → rfp_vendors (expand vendor)
3. Assembles JSON payload matching the function's input schema
4. Calls `POST /api/generateBidComp`
5. Uploads returned xlsx to SharePoint: `DCFG_Outputs/{Customer}/{Year}/BidComp/{RFP Name}.xlsx`
6. PATCHes `dcfg_rfp_package.dcfg_bidcomp_sp_url` with SP view link
7. Updates document request status to Complete
8. Three-step flow build process per CLAUDE.md

### Phase 3 — SPA Configure Panel

**Goal:** The "Generate Bid Comp" button and configuration UX on RfpDetail.

1. "Generate Bid Comp" button on RfpDetail (next to existing Edit/Send/Award buttons)
2. Configure panel (SlideOut or inline) with 7 steps:
   - Customer (pre-filled), Program (dropdown), Location(s) (mandatory), Projects (pre-loaded from junctions, grouped by location), DCG Fee %, Trades Detected, Vendor Assignment
3. Pre-load existing rfp_project and rfp_vendor junctions into panel state
4. Trade detection from selected projects' `dcfg_trades` field (comma-split, dedup)
5. Pre-save sequence: PATCH rfp_package → diff/sync rfp_project junctions → diff/sync rfp_vendor junctions → createDocumentRequest
6. Poll for completion, show view link on success

### Phase 4 — Vendor Assignment SlideOut

**Goal:** The trade-tabbed vendor picker that stays open while user works through all trades.

1. Trade tabs with progress indicators (green/amber/grey, N/5 count)
2. Per-trade: assigned chips (removable) + searchable vendor list + "Match trade" filter
3. Instant click-to-assign, instant click-to-remove
4. "Also on" badge for vendors assigned to other trades
5. Max 5 enforced per trade
6. Footer: overall progress chips + "Done" button
7. Pre-loaded from existing rfp_vendor.dcfg_trade_assignment

### Phase 5 — Import Bids

**Goal:** Read the completed xlsx from SharePoint and create/update proposal records.

1. "Import Bids" button on RfpDetail (visible when `dcfg_bidcomp_sp_url` is set)
2. New Azure Function route `POST /api/importBidComp` — receives SP file URL, fetches xlsx, parses with ExcelJS
3. For each trade tab: parse bidder grid (name, license, contact) + PRICING section (base, alternates, allowances, sub-total, fee, total)
4. Return structured JSON to SPA
5. SPA creates/updates `dcfg_proposal` records per vendor per trade
6. Existing Vendors tab on RfpDetail lights up with actual bid values and low-bid highlighting

### Phase 6 — Extract Trade Sheet + Award Budget

**Goal:** On-demand per-trade extraction and award-to-budget rollup.

1. Per-trade "Extract for Vendor" button on RfpDetail Vendors tab
2. Browser-side ExcelJS: takes trade data, builds single-tab xlsx, triggers download
3. Optional: save extracted sheet to SharePoint alongside full workbook
4. Award handler: when status transitions to Awarded and `dcfg_portfolioid` is set, PATCH program's `budget_committed` += awarded total

## Key Files

| File | Purpose |
|------|---------|
| `azure-functions/html-to-pdf/src/functions/generateBidComp.js` | New — ExcelJS workbook builder |
| `azure-functions/html-to-pdf/src/functions/importBidComp.js` | New — xlsx parser for bid import |
| `spa/dcfg-shell/src/screens/RfpDetail.jsx` | Modified — Generate button, Import Bids button, Extract button, Award budget patch |
| `spa/dcfg-shell/src/portalApi.js` | Modified — DocRequestType.BidComp, new fetch/save helpers if needed |
| `spa/dcfg-shell/src/projectConstants.js` | May need shared TRADES constant export |

## Existing Code to Reuse

- `createDocumentRequest()` — portalApi.js line 833
- `SlideOutPanel.jsx` — existing shell component
- `fetchVendors()` — portalApi.js line 481
- `fetchProgramsByCustomer()` — portalApi.js line 557
- `fetchProjectLines()` — portalApi.js line 900
- `fetchRfpProjects()` / `fetchRfpVendors()` / `createRfpProject()` / `createRfpVendor()` — portalApi.js lines 919-923
- `useTableControls` — for vendor search/sort
- Azure Function host pattern from `htmlToPdf.js`

## Dependencies

- `exceljs` npm package on the Azure Function
- SharePoint DCFG_Outputs library (already exists)
- `dcfg_document_requests` flow trigger (existing pattern)

## Decisions Already Made

| Decision | Choice |
|----------|--------|
| Library | ExcelJS (not raw OOXML) |
| Pre-existing data | Pre-load linked projects/vendors into panel |
| Multi-project header | "Multiple Projects (N)" — full list on EXHIBIT B |
| Trade detection | Project-level `dcfg_trades` for panel; line items server-side |
| Import Bids | In scope — reads xlsx back into proposal records |
| Regeneration | SharePoint native versioning (overwrite same path) |
| Per-trade extraction | On-demand single-tab xlsx (no pre-generation) |
| Award → budget | SPA patches program `budget_committed` in Award handler |
| DCG Fee | Default 16.3%, overridable per bid comp |
| Max bidders | 5 per trade |
| Trade matching | Case-insensitive contains on free-text fields |
