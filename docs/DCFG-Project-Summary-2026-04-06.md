# DCFG — Decades GO Project Summary
**Date:** April 6, 2026
**Prepared by:** Joseph Cameron / Claude

---

## SALES

### What's Built
- Dashboard — Live KPIs: contract pipeline, budget health, recent activity, warnings
- Customer List — 7 customers, searchable/sortable, inline creation
- Customer Detail — 6 tabs: Overview, Locations, MSAs, Contracts, Onboarding, Programs
- MSA List — 17+ MSAs with budget tracking, amendment counts
- MSA Detail — Contracts + document history tabs
- Capital Plan — Equipment health/service report generator
- New Proposal Wizard — 4 steps: Package → Customer/Vendor → Pricing/Locations → Review/Generate

### Proposal Templates (Exhibit A)
| Template | Correct File | Wired | SetDoc | Status |
|---|---|---|---|---|
| Decades Basic (A) | zz_Decades_Basic_Package_A.docx | Yes | Yes | **Ready** |
| Decades Concierge (B) | zz_Decades_Package_C.docx* | Yes | Yes | **Ready** (filename needs rename) |
| Decades Optimized (C) | zz_Decades_Exhibit_A_Optimized_C.docx | Wrong file | Yes | **Needs designer fix** |
| Bancroft Basic (A) | — | — | — | Not started |
| Bancroft Concierge (B) | — | — | — | Not started |
| Bancroft Optimized (C) | — | — | — | Not started |

### Remaining
1. Fix Decades Optimized C template file in designer
2. Build Bancroft proposal templates (A/B/C) with content controls
3. End-to-end test proposal generation with PennReach (has locations)

---

## CONTRACTS & CLEARANCE

### What's Built
- New Contract Wizard — 5 steps: DocType → Customer → Contractor/Signer → Lines → Review/Generate
- Contracts List — 3 views: Smart List, Customer Groups, Split Panel
- Contract Detail — Status-driven transitions, compliance panel, audit trail
- Send Queue (Clearance) — Document approval queue with revenue metrics, overdue tracking
- Flow Monitor — Document request activity log with auto-refresh
- DocGen v3 Flow — Dataverse trigger, Word Online populate, SharePoint output

### Contract Templates
| Template | Correct File | Wired | SetDoc | Tested | Opens |
|---|---|---|---|---|---|
| Decades Work Order | zz_Decades_Work_Order.docx* | Yes | Yes | **Yes** | **Yes** 27.8KB |
| Decades Amendment | Decades_Amendment.docx | Yes | Yes | No | — |
| Bancroft Work Order | zz_Bancroft_Work_Order.docx | Yes | Yes | No | — |
| Bancroft Amendment | **Wrong file** | Yes | Yes | No | Needs zz_Bancroft_Work_Order_Amendment.docx |
| Bancroft Blanket WO Amend | zz_Bancroft_Blanket_Work_Order_Amendment.docx | Yes | Yes | No | — |
| Bancroft Blanket WO | **No template** | No | No | No | Needs template with content controls |
| Decades Vendor MSA | **Wrong file** | Yes | Yes | No | Needs zz_Decades_Vendor_MSA.docx |
| Bancroft Vendor Agreement | Bancroft MSA (Template).docx | Yes | Yes | No | Just wired, 7 controls |

### Flow Fixes Applied This Session
1. `empty()` on Boolean field → `equals(, null)`
2. `varOutputsLibrary` empty → defaults to `DCFG_Outputs`
3. `varPopulatedDoc` Object→String type + `base64ToBinary` on Create_file
4. Output URL now stores full SharePoint path
5. `Set_Status_Processing` missing body → adds dcfg_status=Processing
6. SetDoc actions added to 10 of 12 Switch cases
7. 76 stale document requests cleared from Prod

### Remaining
1. Swap 3 wrong template files in Power Automate designer
2. Create Bancroft Blanket WO template with content controls
3. Decide on Decades_MSA — does it need its own Switch case?
4. End-to-end test all 12 templates, verify documents open with correct content
5. VBA macro provided for merge field → content control conversion

---

## ONBOARDING

### What's Built
- Onboarding Case List — Status tracking, side panel creation, delete actions
- Onboarding Case Detail — Phase accordion with RACI matrix, speech capture
- Onboarding Steps — 30 default steps configurable in Admin
- Concierge SPA — Built, separate portal site

### Remaining
1. **Blocked** — Power Pages provisioning for Concierge portal
2. Scheduling module — not yet designed
3. Integration with contract lifecycle (contract signed → onboarding case auto-created)

---

## FACILITIES

### What's Built
- Facilities Dashboard — Operations view: work orders, sensor alerts, UpKeep sync
- Locations — 800+ properties, compliance alerts, inline creation
- Location Detail — 6 tabs: Property Info, Facility, Systems, Features, Docs, Appliances
- Location Manager — Mobile-first field ops (temporary until devices arrive)
- Vendor List — 480 vendors (197 Sage imports this session), searchable, clickable
- Vendor Detail — New drill-down screen with contact, trade, address, status
- Map View — Leaflet/OSM with customer-colored property pins
- Sensor Banner — IoT alert display across all screens

### Remaining
1. UpKeep write operations (currently read-only sync)
2. Vendor management — dedup, approval queue, merge tool, trades multi-select
3. Equipment benchmark data population
4. Certificate expiry alerting (flow_cert_alert exists, needs validation)

---

## PROJECTS

### What's Built
- Project Dashboard — KPIs: programs, active projects, open RFPs, budget utilization + status chart
- Program List — Budget progress bars, clickable rows, searchable
- Program Detail — Budget breakdown (total/committed/remaining), linked projects, edit mode
- Project List — Inline "New Project" panel with template selection, 20 trade tags, property link
- Project Detail — Costs (estimated/awarded/actual), progress bar, trades, dates, edit mode
- RFP List — Status badges, trade tags, vendor count, deadline tracking
- RFP Detail — 4 tabs: Overview, Projects, Vendors, Checklist. Edit + status transitions
- New RFP Wizard — 3 steps: Info → Select Projects → Review/Create

### Backend Infrastructure (Built This Session)
- Open XML Parser — 19 sheets, 9,911 cells, 474 formulas mapped from bid comp template
- Bid Comp xlsx Producer — Generates pre-filled workbooks
- Bid Comp Read-Back Parser — Extracts vendor data from completed spreadsheets
- Office Scripts — PreFillBidComp.ts + ReadBackBidComp.ts
- Flow Specs — Produce + read-back definitions ready
- SharePoint Provisioning — Project sites with 14 standard folders
- 2 Estimate Templates — Bathroom Remodel (8 items) + Water Heater (5 items)
- Job Absorption Engine — Schema + queue + worker + dashboard (Test only)

### Data (Test Environment)
- 4 active programs ($540K total budget)
- 5 projects across varied statuses
- 1 RFP package with 2 vendor proposals
- 480 vendors (Sage import complete)
- 2 project templates with 13 line items

### Remaining
1. Deploy Project screens to Stage + Prod
2. Billing/scheduling engine (spec written — payment schedules, no-overbill, capacity view)
3. Job absorption — needs real Sage job cost report
4. AI vendor document matching (spec captured — confidence scoring, learning loop)
5. Provision Copilot Studio agent on Test + Stage

---

## INFRASTRUCTURE & CROSS-CUTTING

### Environment Parity
| Component | Test | Stage | Prod |
|---|---|---|---|
| SPA Codebase | Current | Current | Current |
| Table Permissions | 52 | 52 | 97 |
| DocGen Flow | — | — | Active (partial) |
| Absorption Engine | Built | Not provisioned | Not provisioned |
| Project Data | Seeded | Empty | Empty |
| AI Agent | Not provisioned | Not provisioned | Connection exists |

### SPA Module Summary
| Module | Screens | Routes | Create Actions | Edit | TestIDs |
|---|---|---|---|---|---|
| Sales | 7 | 9 | Proposal, Vendor Agreement, Work Order, Amendment | Customer inline | Full |
| Contracts | 4 | 5 | Work Order, Amendment | Contract status transitions | Full |
| Onboarding | 2 | 2 | Onboarding case | Phase checklist | Full |
| Facilities | 6 | 7 | Location | Vendor detail (read-only) | Full |
| Projects | 7 | 8 | Project, RFP Package | Program, Project, RFP edit | Full |
| Admin | 5 | 6 | — | Templates, config | Full |
| **Total** | **31** | **37** | **7** | | |

### Code Quality (This Session)
- Shared `projectConstants.js` — eliminated duplicate status maps, formatters, colors
- Toast API bug fixed in ProjectList
- Error handling added to screens that silently swallowed errors
- Full data-testid audit — all new screens have Playwright coverage
- 3-agent code review (reuse, quality, efficiency) completed

### Specs Written (Not Yet Built)
1. Billing & Scheduling Engine — `docs/superpowers/specs/2026-04-05-billing-scheduling-engine-design.md`
2. Job Absorption Engine — `docs/superpowers/specs/2026-04-05-job-absorption-engine-design.md`
3. Project Setup to RFP — `docs/superpowers/specs/2026-04-04-project-setup-to-rfp-design.md`

### Architecture Decisions Captured
- Vendors send PDFs/Word, not spreadsheets — staff enters into bid comp
- AI matching: confidence scores per scope item, human reviews low-confidence only
- Payment rates fixed at award, system enforces no-overbill
- Spreadsheet IS the interface — system produces/reads xlsx, SME works in Excel
- Distributed absorption: idle desktops process work queue tasks
