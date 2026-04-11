# Handoff: Project Section — RFP + Bid Comp Build

**Date:** 2026-04-04
**Session:** Design spec + implementation plan for the DCFG Project Section
**Operator:** Joseph Cameron

---

## What Was Accomplished This Session

### 1. Design Spec Written and Reviewed

**File:** `C:\DCFG\docs\superpowers\specs\2026-04-04-project-setup-to-rfp-design.md`

Full design spec covering project setup through RFP distribution. Key design decisions:

- **Spreadsheet IS the interface.** The system doesn't replace Excel — it produces pre-filled xlsx, SME works in it, system reads it back on save. Tyler's workflow doesn't change.
- **Spreadsheet Understanding Engine.** Auto-research loop: deep parse Open XML → produce → compare cell-by-cell → fix → loop until 100% structural match. Continuously improves from every completed project file saved to SharePoint.
- **Knowledge preservation.** Tyler Bamford (Bill's son) is the remaining SME. The templates built by departed staff (Danielle Juricic, Nicholas Liggio) ARE the institutional knowledge. The system preserves and scales it.
- **Scale spectrum.** Same data model handles a single-trade service call through a $5.8M multi-year program. Phases are opt-in based on scope, not a rigid pipeline.
- **Cost factors.** Structural conditions (union labor, prevailing wage, regulatory tier) tracked separately from performance variance. Enables honest comparison across different job conditions.
- **BidComp schema reconciliation.** Three critical collisions resolved: `dcfg_phase` (PM vs BidComp — different entities), `dcfg_template_id` (use existing `dcfg_originatingtemplateid`), `dcfg_rfp` (replaced with `dcfg_rfp_package` for multi-project support).

### 2. Implementation Plan Written

**File:** `C:\DCFG\docs\superpowers\plans\2026-04-04-rfp-bidcomp-build.md`

Build order: **RFP → Bid Comp → Manage Job**

Four chunks, 10 tasks:
1. Spreadsheet Understanding Engine (parse, produce, compare bid comp template)
2. Dataverse Schema (rfp_package, rfp_project, rfp_vendor, proposal, milestone)
3. SPA Screens + Power Automate integration
4. End-to-end test: one real single-trade plumbing job

### 3. Reference Files Analyzed

Real SME spreadsheets extracted and analyzed via Open XML:

| File | Location | Tabs | Purpose |
|------|----------|------|---------|
| DCG Multi Trade Bid Template | `C:\DCFG\DCG_Multi_Trade_Bid_Template (version 1).xlsx` | 19 | Full bid comparison system — 13 trade tabs + Dashboard + Bid Tracker + Bid Req + Exhibit B |
| Estimate Template | `C:\Users\JosephCameron\Downloads\Copy of estiamte template.xlsx` | 6 | Sage Budget + Budget + Buysheet + Takeoff + Door Takeoff + Material Spent |
| Sage Vendors | `C:\Users\JosephCameron\Downloads\Sage Vendors (1).xlsx` | 2 | 130+ vendors with Sage Vendor#, name, contact, phone, type (Subcontractor/Supplier) |

**Extracted Open XML available at:**
- `C:\DCFG\tmp\bid_template\extracted\` — bid comp template
- `C:\DCFG\tmp\estimate_template\extracted\` — estimate template
- `C:\DCFG\tmp\sage_vendors\extracted\` — Sage vendor list

### 4. Structural Analysis Completed

Full cell-by-cell structural analysis of both templates:

**Bid Comp Template (19 tabs):**
- Trade tabs: 70-row template, bidder columns at D/F/H/J/L (5 bidders max)
- Scope items rows 14-45, pricing rows 59-70
- Dashboard: pulls low bid (MIN formula) from each trade tab
- Bid Tracker: CHOOSE/MATCH dynamic sheet references via dropdown
- Bid Req: INDIRECT cross-sheet refs for recommendation auto-population
- Exhibit B: dynamic scope population from awarded bidder column
- Data validations: Y/N/N.A./Decades checkboxes on scope items

**Estimate Template (6 tabs):**
- Budget tab: 276 rows, dual cost model (labor hours × rate + material qty × unit price)
- Sage Budget tab: rolls up from Budget via cross-sheet SUM references
- Takeoff tab: 616 rows (expandable), 15% waste factor
- Door Takeoff: 89-column grid for door schedule
- Shared formula optimization throughout

---

## Key Discoveries

### SharePoint Project Site Structure

Each project gets its OWN SharePoint Teams site (not a folder in a shared library):
```
decadesconstructiongroup.sharepoint.com/sites/{JobNumber}{Address}.{CityState}/
```

14 standard folders per project (derived from real project 22006 - 41 Huntingdon Way):
Budget, Proposals, Exhibit B Files, Executed Exhibit A, Invoices, Change Orders, Spec Sheets, Submittals, Licensing Paperwork, Permits, Schedule, PL Pictures, Closeout (with FROL + Warranty Letters subfolders), Eagle View

### Sage is System of Record for Vendors

Vendor# from Sage is the canonical ID. Two types: Subcontractor (bid on work) and Supplier (provide materials). The 271 vendors in Test Dataverse were deduped from 500+ — Sage export has the clean canonical list of ~130.

### The $5.8M Program Budget

Joseph showed the Bancroft FY26 capital budget rollup — $6.4M total, broken into Individual Projects ($1.99M), Commercial 42 properties ($1.54M), Group Homes 54 homes ($1.59M), Purchased Maintenance ($273K), General Conditions ($494K). This is the top-level artifact the system ultimately produces automatically from project-level data.

### Dual Cost Model

Project line items aren't single unit rates. They're:
- **Self-performed:** Labor (qty × hours/unit × $/hour) + Materials (qty × unit price × tax)
- **Subcontracted:** Lump sum from vendor bid, but scope items still listed

CSI codes organize everything: 2111 (Demo), 6100 (Carpentry), 9900 (Painting), 22002 (Plumbing), 26001 (Electrical), etc.

---

## Blockers / Decisions Needed

### Before Build Starts

1. **Graph API auth for SharePoint.** Current Azure auth works for Dataverse but returns 401 on Graph API. Need to add Graph permissions to the Azure app registration or use a separate auth flow for SharePoint file operations.

2. **SharePoint site provisioning permissions.** Can the system auto-create Teams sites via Graph API, or does this require admin action? Determines if project site creation is fully automated.

3. **SPA write permission.** Build 2 Chunk 3 requires adding entity sets and screens to the SPA. Operator must grant permission for each SPA modification.

4. **Bid comp template variations.** Is the 19-tab Multi Trade template the ONLY format? Or are there simpler single-trade templates for small jobs? Affects how many templates the understanding engine needs to learn.

5. **Power Automate SharePoint triggers.** The flow needs to watch project-specific SharePoint sites (hundreds of them) for file changes. Need to determine: one flow per site, or a single flow with dynamic site targeting, or a different trigger pattern.

### Open Design Questions (from spec Section 18)

1. Sage vendor sync — one-time or recurring?
2. Invoice parsing complexity — standard format or highly variable?
3. Change order approval workflow — formal chain or PM authority?

---

## Files Created/Modified This Session

| File | Action | Purpose |
|------|--------|---------|
| `docs/superpowers/specs/2026-04-04-project-setup-to-rfp-design.md` | Created + revised | Full design spec |
| `docs/superpowers/plans/2026-04-04-rfp-bidcomp-build.md` | Created | Implementation plan |
| `docs/handoff-project-section-2026-04-04.md` | Created | This handoff |
| `tmp/bid_template/extracted/` | Created | Extracted Open XML from bid comp template |
| `tmp/estimate_template/extracted/` | Created | Extracted Open XML from estimate template |
| `tmp/sage_vendors/extracted/` | Created | Extracted Open XML from Sage vendor list |
| `tmp_list_exhibit_b.ps1` | Created | SharePoint file listing script (Graph API — auth failed) |

---

## What to Do Next

### Immediate (Build 1 + 2)

1. **Resolve Graph API auth** — needed for SharePoint read/write
2. **Execute Chunk 1** — Build the spreadsheet understanding engine (Tasks 1-3)
3. **Execute Chunk 2** — Create Dataverse tables + read-back parser (Tasks 4-5)
4. **Execute Chunk 3** — SPA screens + Power Automate (Tasks 6-9, requires SPA permission)
5. **Execute Chunk 4** — End-to-end test with one real plumbing job (Task 10)

### After Core Loop Works (Build 3)

- Manage Job: invoice tracking, change orders, material spend, closeout metrics
- Separate plan needed: `2026-04-XX-manage-job-build.md`

### After Manage Job (Build 4-6)

- Project + Estimate Pipeline (pre-filled estimate templates, Sage vendor sync)
- Program Rollup + Dashboards (the $5.8M budget auto-generation)
- AI Layer (vendor PDF parsing, confidence scoring, trade suggestion)

---

## Memory Updates Needed

The following should be saved to memory for future sessions:

- **SharePoint project sites** — each project gets its own Teams site, not a folder in shared library
- **Sage is vendor system of record** — Vendor# is canonical, two types (Sub/Supplier)
- **Tyler Bamford is the remaining SME** — Bill's son, built the estimate template
- **Bid comp template is 19 tabs** — structural analysis complete in `tmp/bid_template/extracted/`
- **Estimate template is 6 tabs** — structural analysis complete in `tmp/estimate_template/extracted/`
- **Build order: RFP → Bid Comp → Manage Job** — not templates first, not dashboards first
