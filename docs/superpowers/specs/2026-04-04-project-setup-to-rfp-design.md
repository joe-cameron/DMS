# Project Setup to RFP Distribution — Design Spec

**Date:** 2026-04-04
**Author:** Joseph Cameron / Claude
**Status:** Draft — Pending Review
**Supersedes:** `2026-04-04-project-procurement-module-design.md` (screen-focused, lacks data collection depth)
**Builds on:** `2026-04-02-bidcomp-module-design.md` (BidComp schema — referenced, not absorbed verbatim; see Section 13 for reconciliation notes)
**Stack:** React 16.14 + Vite + Dataverse Web API via Power Pages (same as DCFG SPA)

---

## 1. What This System Does

Collects project data efficiently from first identification through RFP distribution, producing fully populated SharePoint artifacts at every stage. The SME's deliverable is always a document in a SharePoint folder. The system's job is to make that document complete, accurate, and effortless to produce.

**Core principle:** Data enters the system once. Every downstream artifact — tracker spreadsheets, bid packages, exhibit documents, invoices — is populated from that single source. No re-keying.

---

## 2. The Data Collection Cascade

Each step adds data. No step re-enters data. Later steps consume what earlier steps captured.

```
1. TEMPLATE        defines line items + UoM + base rates
2. PROPERTY        carries location factors (union, regulatory, access)
3. PROJECT         template + property + takeoff quantities = scoped work
4. ESTIMATE        template rates x quantities x factors = real cost
5. RFP ASSEMBLY    selected projects + financial structure + vendors
6. DISTRIBUTION    populated bid package to selected vendors
7. BID RECEIPT     vendor rates against your quantities
8. AWARD           locked rates + billing structure -> contract
9. EXECUTION       change orders (categorized) + schedule + invoices
10. CLOSEOUT       final cost + duration + punch list + callbacks
11. LEARNING       feeds back into factor weights + template rates
```

This spec covers steps 1-6. Steps 7-11 are future specs that consume the data foundation built here.

---

## 3. Project Templates — The Bill of Quantities Skeleton

A template is NOT a blank form. It is a reusable definition of a type of work, carrying line items, units of measure, and base rates.

### 3.1 Template Structure

| Field | Purpose |
|-------|---------|
| Name | "Full Bathroom Rehab", "Roof Replacement", "HVAC System Install" |
| Description | Standard scope text, pre-written |
| Trades | Which trades this work requires (multi-select from 20 approved) |
| Cost Code | Default Bancroft/CSI code |
| Phases | Ordered work phases (Demo -> Rough-in -> Fixtures -> Finish) |
| Line Items | Bill of quantities skeleton (see below) |
| Base Duration | Typical calendar days per unit |
| Billing Pattern | Suggested: per-unit / monthly fixed / milestone |

### 3.2 Template Line Items (Bill of Quantities Skeleton)

Each line item defines WHAT gets measured and HOW:

| Field | Purpose |
|-------|---------|
| Description | "Floor tile", "Tub/shower unit", "Dumpster haul" |
| UoM | sq ft, each, linear ft, load, hour, lump sum |
| Quantity Type | **fixed** (1 tub per bathroom) or **measured** (sq ft from takeoff) |
| Default Qty | For fixed items: the standard count. For measured: blank (requires takeoff) |
| Base Rate | $/unit from historical average or vendor pricing |
| Trade | Which trade performs this line item |

**Example: Full Bathroom Rehab template**

| Line Item | UoM | Qty Type | Default | Base Rate |
|-----------|-----|----------|---------|-----------|
| Floor tile | sq ft | measured | — | $8.00 |
| Wall tile | sq ft | measured | — | $10.00 |
| Tub/shower unit | each | fixed | 1 | $1,200 |
| Vanity + sink | each | fixed | 1 | $800 |
| Plumbing fixtures | each | fixed | 3 | $150 |
| Demo - floor | sq ft | measured | — | $3.00 |
| Demo - wall | sq ft | measured | — | $2.50 |
| Haul-off | load | fixed | 1 | $450 |

### 3.3 Bundle Templates

A bundle template groups multiple templates for compound efforts:

**"Standard Unit Turnover"** = Bathroom Rehab + Interior Paint + Flooring Replacement + Appliance Swap

Selecting a bundle + N properties creates N x (templates in bundle) project records, all pre-filled, grouped, and trade-tagged.

### 3.4 Dataverse Tables (Existing PM Module)

These tables are already built via `DCFG_PM_Module_Build_v5.5.ps1`:

- `dcfg_projecttemplate` — template header
- `dcfg_projecttemplatephase` — template phases (ordered steps)
- `dcfg_projecttemplatetask` — template tasks within phases

**New columns needed on `dcfg_projecttemplate`:**

| Column | Type | Notes |
|--------|------|-------|
| dcfg_trades | String(500) | CSV of applicable trades |
| dcfg_cost_code | String(50) | Default cost code |
| dcfg_base_duration_days | Integer | Typical duration |
| dcfg_billing_pattern | Choice | PerUnit / MonthlyFixed / Milestone |
| dcfg_bundle_flag | Boolean | True if this is a bundle of other templates |

**New table: `dcfg_template_line_item`**

| Column | Type | Notes |
|--------|------|-------|
| dcfg_template_line_item_id | PK | |
| dcfg_project_template_id | FK -> dcfg_projecttemplate | Parent template |
| dcfg_description | String(500) | Line item description |
| dcfg_uom | Choice | SqFt / Each / LinearFt / Load / Hour / LumpSum |
| dcfg_quantity_type | Choice | Fixed / Measured |
| dcfg_default_qty | Decimal | Default quantity (for fixed items) |
| dcfg_base_rate | Currency | Historical average $/unit |
| dcfg_trade | String(100) | Which trade |
| dcfg_sequence | Integer | Display order |
| dcfg_active_flag | Boolean | Soft delete |

**New table: `dcfg_template_bundle_member`** (junction)

| Column | Type | Notes |
|--------|------|-------|
| dcfg_template_bundle_member_id | PK | |
| dcfg_bundle_template_id | FK -> dcfg_projecttemplate | The bundle |
| dcfg_member_template_id | FK -> dcfg_projecttemplate | A template in the bundle |
| dcfg_sequence | Integer | Order within bundle |

---

## 4. Cost Factors — Why Things Cost What They Cost

Factors are structural conditions that raise or lower cost for reasons outside project management quality. They separate "this job is expensive because it's a union site" from "this job is expensive because it was poorly managed."

### 4.1 Factor Sources

**Property-level factors** (persist across all jobs at that location):

| Factor | Type | Example |
|--------|------|---------|
| Union labor required | Boolean + classification | IBEW Local 164 |
| Prevailing wage site | Boolean | Davis-Bacon Act applies |
| Regulatory jurisdiction tier | Choice | Tier 1 (basic) / Tier 2 (enhanced) / Tier 3 (strict) |
| Access difficulty | Choice | Standard / Occupied / High-rise / Restricted hours |
| Historic preservation | Boolean | Additional approval steps |

**Program/customer-level factors:**

| Factor | Type | Example |
|--------|------|---------|
| Insurance/bonding threshold | Currency | $1M bond required |
| Compliance mandates | String | Bancroft 7-point checklist |
| Reporting overhead | Choice | Standard / Enhanced / Full audit |

**Job-level factors** (unique to a specific project, discovered during execution):

| Factor | Type | Example |
|--------|------|---------|
| Hazmat discovered | Boolean + type | Asbestos in ceiling tile |
| Structural surprise | String | Rotten subfloor under tile |
| Weather/seasonal impact | String | Winter concrete pour |

### 4.2 Factor Data Model

Factors start as tagged flags. Over time, historical data quantifies their cost impact.

**New columns on `dcfg_property`:**

| Column | Type | Notes |
|--------|------|-------|
| dcfg_union_required | Boolean | Union labor required at this site |
| dcfg_union_classification | String(200) | Union local / classification |
| dcfg_prevailing_wage | Boolean | Prevailing wage applies |
| dcfg_regulatory_tier | Choice | Tier1 / Tier2 / Tier3 |
| dcfg_access_difficulty | Choice | Standard / Occupied / HighRise / RestrictedHours |
| dcfg_historic_preservation | Boolean | Historic preservation rules apply |

**New columns on `dcfg_customer`:**

| Column | Type | Notes |
|--------|------|-------|
| dcfg_bonding_threshold | Currency | Insurance/bonding requirement |
| dcfg_compliance_profile | String(500) | Compliance requirements summary |
| dcfg_reporting_level | Choice | Standard / Enhanced / FullAudit |

**New table: `dcfg_project_factor`** (per-project factor tags)

| Column | Type | Notes |
|--------|------|-------|
| dcfg_project_factor_id | PK | |
| dcfg_project_id | FK -> dcfg_project | |
| dcfg_factor_name | String(200) | "Union labor", "Hazmat - asbestos", etc. |
| dcfg_factor_source | Choice | Property / Customer / Discovered |
| dcfg_cost_impact_estimated | Currency | Estimated cost impact (nullable until known) |
| dcfg_cost_impact_actual | Currency | Actual impact (filled at closeout) |
| dcfg_notes | String(max) | Details |
| dcfg_discovered_date | DateTime | When factor was identified |
| dcfg_active_flag | Boolean | Soft delete |

### 4.3 Factor Learning (Deferred — Steps 7-11)

**This spec (Steps 1-6) captures factors as boolean flags and free-text tags.** No automated weight calculation, no `dcfg_factor_weight` table, no historical trending. The `dcfg_project_factor` table records what factors existed on each job and their estimated/actual cost impact — that's the raw data.

Automated factor learning (calculating average cost impact per factor across completed jobs, adjusting template base rates, preserving historical factor values for fair comparison) requires closeout data from Steps 9-10. It will be specified in the Steps 7-11 spec once sufficient completed job data exists.

**What this spec provides:** the structured data capture that makes future learning possible. Every project records its factors, every closeout records actual cost/duration/change orders. The learning engine will query this data — but building the engine before having the data is premature.

---

## 5. Project Creation — Template + Property + Takeoff

### 5.1 Quick Entry (30-second field capture)

Minimum viable project record — what a field person on an iPad can log:

| Field | Source | Required |
|-------|--------|----------|
| Property | Pick from list (already in Dataverse) | Yes |
| Description | Free text ("Full bathroom rehab - tub, tile, vanity") | Yes |
| Urgency | Emergency / Planned / Deferred | Yes |
| Reported by | Auto-fill from logged-in user | Auto |
| Template | System suggests from description, user confirms | Suggested |
| Trades | Auto-suggested from template or description keywords | Suggested |
| Budget estimate | Auto-calculated if template + quantities known | Suggested |

### 5.2 Template Application

When a template is selected (at creation or later):

1. Line items copy from template to project, with fixed quantities pre-filled
2. Measured items flagged as **needs takeoff** (blank quantity, highlighted)
3. Phases copy from template to project
4. Trades auto-populate from template
5. Cost code auto-populates from template
6. Base duration sets the initial schedule estimate

### 5.3 Takeoff / Measurement Capture

For measured line items, quantities come from:

1. **Property record** — if room dimensions are stored (reusable across projects)
2. **Field measurement** — entered on the project line item directly
3. **Historical similar** — system shows what similar projects at similar properties measured

Once quantities are entered, the estimate becomes real:

```
Project estimate = SUM(line_item_qty x line_item_rate) x factor_adjustments
```

### 5.4 Bulk Creation (Template + Multiple Properties)

User selects:
1. A template (or bundle template)
2. Multiple properties from the property list (filter by customer, service line, location type)

System creates one project per property (or N projects per property for bundles), each pre-filled from the template. User reviews, adjusts any that differ from standard, confirms.

15 bathroom rehabs created in 2 minutes, not 30 individual entries.

### 5.5 Project Data Model (Existing + Additions)

`dcfg_project` already exists. **New columns needed:**

| Column | Type | Notes |
|--------|------|-------|
| dcfg_propertyid | FK -> dcfg_property | Property where work occurs (required) |
| dcfg_urgency | Choice | Emergency / Planned / Deferred |
| dcfg_reported_by | String(200) | Who identified the need |
| dcfg_trades | String(500) | CSV from 20 approved trades (see Section 10). Delimiter: comma-space. Validated by SPA — no freeform entry. |
| dcfg_cost_code | String(50) | Cost code |
| dcfg_estimated_cost | Currency | Calculated from line items x factors. Distinct from existing `dcfg_budget` (approved/allocated amount). Estimated = calculated from line items; budget = what's approved to spend. |
| dcfg_estimated_duration_days | Integer | From template or manual |
| dcfg_actual_cost | Currency | Filled during/after execution |
| dcfg_actual_duration_days | Integer | Filled at closeout |
| dcfg_awarded_cost | Currency | Contract award amount |
| dcfg_awarded_duration_days | Integer | Contracted timeline |
| dcfg_final_cost | Currency | All invoices + change orders |
| dcfg_change_order_count | Integer | Total change orders |
| dcfg_planning_miss_count | Integer | Change orders tagged as planning miss |
| dcfg_punch_list_count | Integer | Items at completion |
| dcfg_callback_count | Integer | Post-completion callbacks |
| dcfg_closeout_date | DateTime | When project was formally closed |
| dcfg_factor_adjustment | Decimal | Product of applicable factors at execution time |
| dcfg_billing_pattern | Choice | PerUnit / MonthlyFixed / Milestone |

**Note on existing columns:** `dcfg_project` already has `dcfg_originatingtemplateid` (FK -> dcfg_projecttemplate) from PM Module Build v5.5. Use this existing column for the template relationship — do NOT create a new `dcfg_template_id`. Also has `dcfg_budget` (Currency) — this is the approved/allocated budget, distinct from `dcfg_estimated_cost` (calculated from line items and factors).

**New table: `dcfg_project_line_item`** (instantiated from template line items)

| Column | Type | Notes |
|--------|------|-------|
| dcfg_project_line_item_id | PK | |
| dcfg_project_id | FK -> dcfg_project | Parent project |
| dcfg_template_line_item_id | FK -> dcfg_template_line_item | Source (nullable) |
| dcfg_description | String(500) | Line item description |
| dcfg_uom | Choice | SqFt / Each / LinearFt / Load / Hour / LumpSum |
| dcfg_quantity | Decimal | Actual quantity (from takeoff or default) |
| dcfg_quantity_source | Choice | TemplateDefault / FieldMeasurement / PropertyRecord / Historical |
| dcfg_unit_rate | Currency | $/unit (from template base rate, adjustable) |
| dcfg_extended_cost | Currency | qty x rate (calculated) |
| dcfg_trade | String(100) | Which trade |
| dcfg_needs_takeoff | Boolean | True if measured item without quantity |
| dcfg_sequence | Integer | Display order |
| dcfg_active_flag | Boolean | Soft delete |

---

## 6. Estimation Engine

### 6.1 Estimate Calculation

```
base_cost = SUM(project_line_items: quantity x unit_rate)

factor_adjustment = PRODUCT(applicable_factors)
  where each factor is (1 + factor_percentage)
  Example: union(+17%) x prevailing_wage(+12%) x occupied(+5%)
         = 1.17 x 1.12 x 1.05 = 1.376 (+37.6%)

estimated_cost = base_cost x factor_adjustment
```

### 6.2 Estimate Sources (Priority Order)

1. **Actual takeoff + current rates** — if line items have quantities and rates
2. **Template defaults + factor adjustment** — if template applied but no takeoff yet
3. **Historical similar** — system average for same template + similar factor profile
4. **Manual entry** — PM enters a number based on experience

The system shows which source was used and the confidence level. A takeoff-based estimate is more reliable than a historical guess.

### 6.3 Historical Comparison

When estimating a new project, the system shows:

> "Full Bathroom Rehab at union sites: 8 completed jobs"
> "Average cost: $21,450 (range $19,200 - $23,800)"
> "Average duration: 14 days (range 11 - 18)"
> "Your estimate: $22,100 — within normal range"

This gives the PM immediate context for whether their estimate is reasonable.

---

## 7. Project Organization and RFP Preparation

### 7.1 Project List — The Staging Ground

The project list is where work accumulates and gets organized for bidding. Key capabilities:

- **Filter by:** status, trade, service line, customer, property, urgency, PM
- **Sort by:** any column
- **Search:** description text, property name, cost code
- **Group by:** trade (natural RFP bundling), service line, status
- **Bulk select** for RFP assembly
- **Visual indicators:** needs takeoff (orange), ready to bid (green), missing data (red)

### 7.2 RFP Assembly Flow

**Step 1: Select Projects**

User filters the project list and selects projects to bundle into one RFP. Or: system suggests groupings based on trade overlap and geographic proximity.

Pre-selection validation:
- All selected projects have quantities (no "needs takeoff" items)
- All selected projects have trades confirmed
- All selected projects are in biddable status (Identified or Scoped)
- Warnings (non-blocking): missing cost estimates, missing phases

**Step 2: Review Aggregated Scope**

System rolls up across all selected projects:

| Aggregation | Source |
|-------------|--------|
| Total line items | Union of all project line items, grouped by trade |
| Total quantities | Sum per line item description + UoM |
| Properties involved | Distinct properties from selected projects |
| Trades needed | Union of all project trades |
| Estimated total | Sum of all project estimated costs |
| Factor summary | Common factors across properties (e.g., "12 of 15 properties are union sites") |

User can adjust: add/remove projects, modify quantities, add RFP-specific notes.

**Step 3: Define Financial Structure**

The system suggests based on scope. User makes the business decision:

| Pattern | When to Use | System Pre-fill |
|---------|-------------|-----------------|
| Per-unit completion | Repetitive work (15 bathrooms) | Unit count x per-unit estimate |
| Monthly fixed | Predictable cash flow needed | Total / months = monthly amount |
| Milestone-based | Large projects with natural gates | Phases from template → milestone gates |
| Hybrid | Bancroft standard | Monthly cap + milestone gates |

**Financial structure fields:**

| Field | Type | Notes |
|-------|------|-------|
| Total contract value | Currency | From aggregated estimate or manual |
| Billing pattern | Choice | PerUnit / MonthlyFixed / Milestone / Hybrid |
| Period type | Choice | Monthly / Quarterly |
| Period cap | Currency | Max billing per period |
| Contract duration months | Integer | |
| Milestones | Child records | Name, sequence, cumulative cap, completion criteria |

**Step 4: Select Vendors**

System queries vendors where:
- Trades include ANY of the RFP's required trades
- Status = Approved
- Has active MSA (flagged if not — they'll need one)
- Within configurable radius of project properties

Results ranked by:
1. Trade coverage (vendors matching more trades rank higher)
2. Distance from project centroid
3. Historical performance on similar work (future — from closeout data)

User checks vendors to include. Manual add available for vendors not in suggestions.

**Step 5: Review and Send**

Summary screen:
- X projects across Y properties
- Z total line items, $Total estimated value
- N vendors selected across M trades
- Financial structure summary
- Submission deadline
- Factor disclosure (which cost factors apply to this work)

**Generate RFP package** → system produces:
1. Populated RFP document (Word template with all scope, quantities, financial terms, property list)
2. Bill of quantities spreadsheet (Excel — vendors fill in their unit rates)
3. Property list with addresses and relevant details

All documents deposited in SharePoint: `DCFG_Outputs/{Customer Display Name}/{Year}/RFP/` (follows gold standard — calendar year, not fiscal year label)

**Send** → creates `dcfg_rfp_package` record + `dcfg_rfp_project` junction records + `dcfg_rfp_vendor` junction records, distributes to vendors.

---

## 8. Performance Measurement Framework

Every completed job feeds the learning loop. This section defines what gets measured and when.

### 8.1 Four Dimensions

| Dimension | Formula | Captured At |
|-----------|---------|-------------|
| **Cost accuracy** | estimated_cost / awarded_cost | Award |
| **Cost performance** | final_cost / awarded_cost | Closeout |
| **Schedule performance** | actual_days / awarded_days | Closeout |
| **Plan stability** | (awarded + change_orders) / awarded | Closeout |

### 8.2 Change Order Classification

Every change order is tagged with a reason:

| Category | Meaning | Counts Against Planning? |
|----------|---------|--------------------------|
| Unforeseen condition | Opened wall, found mold | No |
| Owner scope change | Customer upgraded fixtures | No |
| Planning miss | Didn't account for permit | **Yes** |
| Vendor-driven | Material cost increase claim | Evaluate |
| Factor discovery | New regulatory requirement found | No (becomes new factor) |

### 8.3 Factor-Adjusted Comparison

Raw metrics are useful but misleading across different factor profiles. The system calculates factor-adjusted metrics:

```
adjusted_cost = actual_cost / factor_adjustment
```

Comparing two PMs:
- PM Alpha: 8 jobs, avg adjusted cost variance +4%
- PM Beta: 8 jobs, avg adjusted cost variance +19%
- Same templates, same factor profiles — the variance is operational

### 8.4 Multi-Dimensional Insight

A union job that costs 18% more but delivers:
- 22% faster schedule
- 60% fewer change orders
- Zero callbacks

...may be the BETTER outcome. The system surfaces all dimensions so the evaluator sees the full picture, not just the bottom line.

**Closeout metric columns** are defined in the consolidated `dcfg_project` column list in Section 5.5 (dcfg_awarded_cost, dcfg_awarded_duration_days, dcfg_final_cost, dcfg_actual_duration_days, dcfg_change_order_count, dcfg_planning_miss_count, dcfg_punch_list_count, dcfg_callback_count, dcfg_closeout_date, dcfg_factor_adjustment). They are populated at closeout, not at project creation.

---

## 9. SharePoint Integration — Artifact Production

### 9.1 Document Types Produced by the System

| Artifact | Template Source | Trigger | Destination |
|----------|---------------|---------|-------------|
| Project Tracker (Excel) | DCFG_Templates/Project_Tracker.xlsx | "Download Tracker" button | DCFG_Outputs/{Customer Display Name}/{Year}/Tracker/ |
| RFP Package (Word) | DCFG_Templates/RFP_Package.docx | "Generate RFP" on RFP review | DCFG_Outputs/{Customer Display Name}/{Year}/RFP/ |
| Bill of Quantities (Excel) | DCFG_Templates/Bill_of_Quantities.xlsx | Generated with RFP | DCFG_Outputs/{Customer Display Name}/{Year}/RFP/ |
| Exhibit A (Word) | Existing DocGen templates | Award -> contract creation | DCFG_Outputs/{Customer Display Name}/{Year}/Contract/ |
| Exhibit B (Word) | DCFG_Templates/Exhibit_B_{Trade}.docx | Award -> scope document | DCFG_Outputs/{Customer Display Name}/{Year}/Contract/ |
| Monthly Report (Excel) | DCFG_Templates/Monthly_Report.xlsx | Scheduled or on-demand | DCFG_Outputs/{Customer Display Name}/{Year}/Report/ |
| PO Log (Excel) | DCFG_Templates/PO_Log.xlsx | "Download PO Log" button | DCFG_Outputs/{Customer Display Name}/{Year}/Tracker/ |

### 9.2 Populated, Not Blank

Every document produced by the system is FULLY POPULATED with current Dataverse data. The SME opens a ready-to-use document, not a blank template. The system:

1. Queries Dataverse for all relevant data
2. Populates the template (Word content controls or Excel cells)
3. Deposits in the correct SharePoint folder per the gold standard structure
4. Returns the download/open URL to the user

### 9.3 Excel Round-Trip (Tracker and PO Log)

For Excel artifacts that the SME modifies and returns:

1. **Download** — system produces populated spreadsheet
2. **SME works in Excel** — modifies rows, adds new entries
3. **Upload** — system reads modified spreadsheet
4. **Diff** — compares against current Dataverse state
5. **Validate** — presents changes for review (new / modified / deleted / conflict)
6. **Apply** — approved changes written to Dataverse with audit trail

---

## 10. Trade Categories (20 Approved)

```
Alarm, Carpentry/Framing, Concrete, Counter Tops, Demolition,
Drywall, Electrical, Fencing, Flooring/Ceramic Tile,
General Maintenance, HVAC, Inspections, Landscaping/Grounds,
Masonry, Paint, Plumbing, Roofing, Siding/Gutters,
Sprinkler/Fire Protection, Tree Removal
```

### 10.1 Trade-to-Description AI Suggest

Keyword map built from Leon's 91 actual project descriptions. On project description input, system matches keywords and suggests trades as badges. User confirms with one tap.

| Trade | Keywords (from actual project descriptions) |
|-------|---------------------------------------------|
| Plumbing | bathroom, tub, shower, plumb, water, drain |
| Flooring/Ceramic Tile | floor, tile, carpet, vinyl, lvt, ceramic |
| Electrical | electric, generator, wiring, panel, outlet, light |
| HVAC | hvac, heating, cooling, furnace, ac, air condition |
| Roofing | roof, shingle, gutter |
| Paint | paint, wall protection, bead board |
| Carpentry/Framing | door, window, deck, porch, stair, cabinet, kitchen |
| Concrete | concrete, driveway, sidewalk, foundation |
| Demolition | demo, removal, tear down |

Remaining 11 trades follow the same pattern. The keyword map is stored as configuration data (dcfg_configs or a JSON file), not hardcoded.

---

## 11. Screens

### 11.1 Template Manager — `/admin/templates`

Admin screen for creating and managing project templates.

- Template list with trade badges, line item count, usage count
- Template detail: edit name, description, trades, phases, billing pattern
- Line item editor: add/edit/reorder line items with UoM, qty type, default qty, base rate
- Bundle builder: select templates to include in a bundle, set order
- "Clone template" for variations (Bathroom Rehab Standard vs Bathroom Rehab ADA)

### 11.2 Project List — `/projects`

The staging ground for all project work.

- Table view with all tracker columns (matches Leon's Excel vocabulary)
- Filter/sort/search/group by trade, status, service line, customer, PM, urgency
- Visual indicators: needs takeoff (orange dot), ready to bid (green), missing data (red)
- Bulk select → "Prepare RFP" button
- "Download Tracker" → populated Excel to SharePoint
- "Upload Changes" → diff engine → validation screen
- "New Project" → quick entry or template-based creation
- "Bulk Create" → template + multiple properties

### 11.3 Project Detail — `/projects/:id`

Single project view with all data and linked entities.

- Header: property, template, status, PM, urgency, trades
- **Line Items tab:** bill of quantities with quantities, rates, extended cost. "Needs takeoff" items highlighted. Inline editable.
- **Factors tab:** property-inherited factors + job-specific factors. Each with cost impact (estimated or blank).
- **Estimate card:** base cost + factor adjustment = estimated cost. Comparison to historical similar.
- **Phases tab:** from template, with status tracking
- **Documents tab:** linked SharePoint artifacts
- **Metrics tab** (post-execution): cost/schedule/stability/quality dimensions with factor-adjusted values

### 11.4 RFP Builder — `/rfps/new`

Five-step wizard (described in Section 7.2):
1. Select Projects (with validation)
2. Review Aggregated Scope (rollup with adjustments)
3. Define Financial Structure (pattern + milestones)
4. Select Vendors (trade + proximity + MSA matching)
5. Review and Send (summary + document generation)

### 11.5 Program Dashboard — `/programs/:id`

Leon's "Dashboard" sheet digitized with real KPIs:

- Budget bar: allocated vs committed vs spent vs remaining
- Project status breakdown by status and service line
- Factor-adjusted cost performance across all program projects
- Schedule health: on-time vs behind
- Change order summary: total count, categorized by reason
- Unbilled work alerts
- Quick actions: New Project, Create RFP, Download Tracker

### 11.6 Project Dashboard — `/project-dashboard`

Cross-program overview (replaces current placeholder):

- Active programs with budget health
- Projects needing attention: needs takeoff, overdue, over budget
- Recent completions with performance metrics
- Vendor performance summary (factor-adjusted)

---

## 12. Navigation Integration

Add to existing SPA NavPanel under PROJECTS section:

```
PROJECTS
  Dashboard        /project-dashboard
  Programs         /programs
  Projects         /projects
  RFPs             /rfps

ADMIN (existing, add to):
  Project Templates  /admin/templates
```

Add to CREATE zone:
```
New Project     /projects/new
New RFP         /rfps/new
```

Route registration in AppRouter.jsx:
```
/project-dashboard    ProjectDashboard (replace placeholder)
/programs             ProgramList
/programs/:id         ProgramDashboard
/projects             ProjectList
/projects/new         ProjectCreate
/projects/:id         ProjectDetail
/rfps                 RfpList
/rfps/new             RfpBuilder
/rfps/:id             RfpTracking
/admin/templates      TemplateManager
```

---

## 13. Schema Summary — All New/Modified Tables

### 13.1 BidComp Schema Reconciliation (CRITICAL)

The BidComp spec (`2026-04-02`) designed tables before the PM Module was built. Three naming collisions must be resolved:

**`dcfg_phase` — TWO DIFFERENT ENTITIES**

| Context | PM Module (built) | BidComp (designed) |
|---------|--------------------|--------------------|
| Parent | dcfg_project | dcfg_prime_contract |
| Meaning | Ordered work step within a project | Budget line item (property + cost code) |
| Columns | name, sequence, status, dates | 25+ columns: cost_code, material, labor, sub, budget_total, pm_assigned, wo_number |

**Resolution:** The PM module's `dcfg_phase` stays as-is (work phases within a project). BidComp's concept — the budget line item / tracker row — maps to `dcfg_project` in this spec. Leon's tracker rows ARE projects, not phases. The BidComp `dcfg_phase` table will NOT be created. Its columns (cost_code, material, labor, equipment, sub, budget_total, service_line, pm_assigned, wo_number, etc.) are absorbed into `dcfg_project` as new columns where they don't already exist.

**`dcfg_rfp` — SCOPE MISMATCH**

BidComp's `dcfg_rfp` has a single `dcfg_phase` FK (one RFP per budget line). This spec's RFP bundles multiple projects. Resolution: create `dcfg_rfp_package` as the multi-project RFP wrapper. BidComp's `dcfg_rfp` is NOT used. The new table carries all BidComp's procurement checklist booleans PLUS the multi-project and financial structure fields.

**`dcfg_proposal` — COMPATIBLE**

BidComp's `dcfg_proposal` works as designed. Change its `dcfg_rfp` FK to point to `dcfg_rfp_package` instead.

### 13.2 New Tables

| Table | Purpose | Row Count Estimate |
|-------|---------|-------------------|
| dcfg_template_line_item | Bill of quantities skeleton per template | ~200 (20 templates x 10 items) |
| dcfg_template_bundle_member | Junction: templates in a bundle | ~50 |
| dcfg_project_line_item | Instantiated line items per project | ~5,000 (500 projects x 10 items) |
| dcfg_project_factor | Cost factors per project | ~1,500 (500 projects x 3 factors) |
| dcfg_rfp_package | Multi-project RFP with financial structure | ~100 |
| dcfg_rfp_project | Junction: projects included in an RFP | ~500 |
| dcfg_rfp_vendor | Junction: vendors invited to bid | ~500 |
| dcfg_milestone | Billing milestones per RFP/contract | ~200 |

**`dcfg_rfp_package`** — full definition:

| Column | Type | Notes |
|--------|------|-------|
| dcfg_rfp_package_id | PK | |
| dcfg_name | String(200) | RFP title |
| dcfg_prime_contract_id | FK -> dcfg_prime_contract | Parent program (nullable) |
| dcfg_customer_id | FK -> dcfg_customer | Customer |
| dcfg_trades | String(500) | Aggregated trades (CSV) |
| dcfg_scope_description | String(max) | Overall scope narrative |
| dcfg_total_estimated_value | Currency | Sum of selected project estimates |
| dcfg_billing_pattern | Choice | PerUnit / MonthlyFixed / Milestone / Hybrid |
| dcfg_period_type | Choice | Monthly / Quarterly |
| dcfg_period_cap | Currency | Max billing per period |
| dcfg_contract_duration_months | Integer | |
| dcfg_deadline | DateTime | Bid submission deadline |
| dcfg_status | Choice | Draft / Sent / ResponsesIn / Leveled / Awarded / Canceled |
| dcfg_bid_solicited | Boolean | BidComp procurement checklist |
| dcfg_bid_received | Boolean | |
| dcfg_scope_exhibit_drafted | Boolean | |
| dcfg_exhibit_b_issued | Boolean | |
| dcfg_contract_out | Boolean | |
| dcfg_contract_fe | Boolean | Fully executed |
| dcfg_submittals_received | Boolean | |
| dcfg_scope_items | String(max) | JSON: structured scope items |
| dcfg_financial_structure | String(max) | JSON: amortization, period caps detail |
| dcfg_version | Integer | RFP version number |
| dcfg_sp_file_ref | String(500) | SharePoint document URL |
| dcfg_active_flag | Boolean | Soft delete |

**`dcfg_rfp_project`** — junction:

| Column | Type | Notes |
|--------|------|-------|
| dcfg_rfp_project_id | PK | |
| dcfg_rfp_package_id | FK -> dcfg_rfp_package | |
| dcfg_project_id | FK -> dcfg_project | |

**`dcfg_milestone`** — full definition:

| Column | Type | Notes |
|--------|------|-------|
| dcfg_milestone_id | PK | |
| dcfg_rfp_package_id | FK -> dcfg_rfp_package | Or exhibit_a_id (one must be set) |
| dcfg_exhibit_a_id | FK -> dcfg_exhibit_a | Post-award, milestone transfers to contract |
| dcfg_name | String(200) | "Demo & Prep", "Rough-in Complete" |
| dcfg_sequence | Integer | Order |
| dcfg_cumulative_cap | Currency | Max billing through this milestone |
| dcfg_period_cap | Currency | Max billing per period within this milestone |
| dcfg_completion_criteria | String(500) | What defines completion |
| dcfg_completed | Boolean | |
| dcfg_completed_date | DateTime | |
| dcfg_active_flag | Boolean | Soft delete |

### 13.3 Modified Tables (New Columns)

| Table | New Columns |
|-------|-------------|
| dcfg_projecttemplate | trades, cost_code, base_duration_days, billing_pattern, bundle_flag |
| dcfg_project | propertyid, urgency, reported_by, trades, cost_code, estimated_cost, estimated_duration_days, actual_cost, actual_duration_days, billing_pattern, awarded_cost, awarded_duration_days, final_cost, change_order_count, planning_miss_count, punch_list_count, callback_count, closeout_date, factor_adjustment. Uses EXISTING `dcfg_originatingtemplateid` for template FK and `dcfg_budget` for approved budget. |
| dcfg_property | union_required, union_classification, prevailing_wage, regulatory_tier, access_difficulty, historic_preservation |
| dcfg_customer | bonding_threshold, compliance_profile, reporting_level |

### 13.4 BidComp Tables Used As-Is (from 2026-04-02 spec)

| Table | Purpose | Notes |
|-------|---------|-------|
| dcfg_prime_contract | Program-level budget + customer + FY | No changes |
| dcfg_proposal | Vendor bid responses | FK changed to dcfg_rfp_package |
| dcfg_exhibit_a | Awarded work orders | No changes |
| dcfg_exhibit_b | Scope of work documents | No changes |
| dcfg_change_order | Amendments to executed work | No changes |
| dcfg_invoice | Billing pipeline | No changes |
| dcfg_cadenced_svc | Recurring service contracts | No changes |
| dcfg_service_period | Per-period tracking | No changes |

### 13.5 BidComp Tables NOT Used (superseded)

| Table | Reason |
|-------|--------|
| dcfg_phase (BidComp version) | Concept absorbed into dcfg_project. PM module's dcfg_phase (work steps) is a different entity and remains. |
| dcfg_rfp (BidComp version) | Replaced by dcfg_rfp_package with multi-project support |

---

## 14. UoM Choice Values

| Value | Label | Typical Use |
|-------|-------|-------------|
| 1 | Square Foot (sq ft) | Tile, flooring, demo, paint |
| 2 | Each | Fixtures, units, appliances |
| 3 | Linear Foot (lin ft) | Fencing, baseboard, pipe |
| 4 | Load | Haul-off, dumpster |
| 5 | Hour | Labor |
| 6 | Lump Sum | Fixed-price items |
| 7 | Cubic Yard (cu yd) | Concrete, fill |
| 8 | Square (roofing) | Roofing (100 sq ft) |
| 9 | Gallon | Paint, coating |
| 10 | Ton | Asphalt, aggregate |

---

## 15. Core Design Principle: Spreadsheet as Interface

The SMEs (Tyler Bamford and predecessors) built the estimate template, the bid comp template, and the project tracker as working tools in Excel. These spreadsheets are NOT data entry forms — they are thinking tools that represent years of accumulated expertise. The people who built them are largely gone. The templates are the institutional knowledge that survived.

### 15.1 The System Does Not Replace Excel

The SME works in Excel because Excel is the tool they know. The system:

1. **Produces** a populated xlsx (filled with current Dataverse data, pre-filled from templates)
2. **SME works** in it (adds lines, changes quantities, enters vendor responses — in Excel)
3. **System reads** on save (Power Automate watches SharePoint, parses Open XML by known template layout, writes structured data to Dataverse)

The SharePoint project folder is the handoff point. The SME's workflow doesn't change.

### 15.2 Spreadsheet Understanding Engine (Auto-Improving)

Before the system can produce a single xlsx on demand, it must understand every cell, formula, label, merge, style, and cross-sheet reference — perfectly. One wrong column header and the SME loses trust.

**Auto-research loop:**

1. **Deep Parse** — Unzip xlsx as Open XML. Extract every structural element: cell values/types/positions, formulas (with cross-sheet refs), merged ranges, styles, named ranges, data validations, conditional formatting, print areas, column widths, frozen panes. Output: template schema in JSON.
2. **Produce** — Generate populated xlsx from schema + test data.
3. **Compare** — Cell-by-cell structural comparison against original. Score mismatches.
4. **Fix and Re-run** — Update schema for each mismatch. Re-produce, re-compare. Loop until 100% structural match.
5. **Validate with Real Data** — Produce using actual completed project data. Compare against the real spreadsheet the SME created for that project.

**Continuous improvement:** Every completed project spreadsheet saved to SharePoint becomes another example. The system reads it, compares against its schema understanding, and refines. No special effort from the user — the files they save as part of normal work ARE the training set.

### 15.3 Project Site Provisioning

Each project gets its own SharePoint Teams site: `{JobNumber}{Address}.{CityState}`

Standard folder set (derived from real project 22006 - 41 Huntingdon Way):

```
Shared Documents/General/
  ├── Budget/
  ├── Proposals/
  ├── Exhibit B Files/
  ├── Executed Exhibit A/
  ├── Invoices/
  ├── Change Orders/
  ├── Spec Sheets/
  ├── Submittals/
  ├── Licensing Paperwork/
  ├── Permits/
  ├── Schedule/
  ├── PL Pictures/
  ├── Closeout/
  │     ├── FROL/
  │     └── Warranty Letters/
  └── Eagle View/  (if roofing scope)
```

System auto-provisions on project creation. Human can add project-specific folders.

### 15.4 Source Systems

| System | Role | Integration |
|--------|------|-------------|
| **Sage** | System of record for vendors (Vendor#, name, contact, phone, type) | Read — vendor sync to Dataverse |
| **SharePoint** | System of record for project files (estimates, bid comps, invoices, contracts) | Read on save, write on produce |
| **Dataverse** | System of record for structured data (projects, line items, proposals, metrics) | Central database |
| **Excel** | The user interface | Produced by system, read back by system |
| **SPA** | Management view (dashboards, cross-project analytics, vendor performance) | Reads Dataverse |

---

## 16. Human Process Flow (End-to-End)

Work starts small and compounds. A single-trade service call uses the same data model as a $5.8M multi-year program. The phases are opt-in based on scope, not a rigid pipeline.

### Scale Spectrum

| Scale | Trades | Properties | Process Phases Used |
|-------|--------|------------|---------------------|
| Service call | 1 | 1 | Create project → assign vendor → invoice → close |
| Small repair | 1-2 | 1 | Create → get quotes → pick vendor → invoice → close |
| Project | 3-5 | 1 | Create → estimate → bid comp → award → execute → close |
| Bundled projects | 3-5 | 5-15 | Templates → multi-property bid comp → split awards → execute → close |
| Program | 13+ | 50-200 | Full lifecycle → Sage Budget rollup |

### Phase-by-Phase Process

**Phase 1: Create Project**
- Human: identify work at a property (description + urgency)
- System: create project record, suggest template + trades from description

**Phase 2: Estimate** (optional for small jobs)
- Human: open pre-filled estimate template, do takeoffs, enter quantities
- System: produce populated xlsx, read back on save
- Artifact: estimate template (6 tabs) → SharePoint `{Project}/Budget/`

**Phase 3: RFP + Bid Comp** (the first thing to build)
- Human: identify trades needing subs, select vendors from Sage list
- System: produce pre-filled bid comp template (19 tabs) with scope items from estimate + vendor columns
- Human: send RFP to vendors, enter responses into BIDDER columns, compare on Dashboard tab, write recommendation on Bid Req tab
- System: read back on save, parse vendor responses to Dataverse
- AI: parse vendor PDF proposals → pre-fill BIDDER columns → flag confidence
- Artifact: completed bid comp → SharePoint `{Project}/Proposals/`

**Phase 4: Award + Contract Documents**
- Human: select winning vendor on Bid Req tab, sign recommendation
- System: produce Exhibit A (DocGen — already built), auto-populate Exhibit B from bid comp's awarded BIDDER column
- Artifact: Exhibit A → `{Project}/Executed Exhibit A/`, Exhibit B → `{Project}/Exhibit B Files/`

**Phase 5: Execute (Manage Job)**
- Human: file invoices, document change orders (ADD/DEDUCT with category tag), track material spend, manage submittals + permits
- System: parse invoices on save → match to project + vendor + CSI → update budget tracking → flag overruns
- Artifact: invoices, COs, submittals → standard project folders

**Phase 6: Closeout**
- Human: punch list walk + photos, collect FROL from every sub, collect warranty letters, final permits
- System: capture closeout metrics (final cost, duration, CO count by category, punch list count)
- Artifact: closeout docs → `{Project}/Closeout/`

**Phase 7: Program Rollup**
- System: query all projects for a program → aggregate by CSI code → produce Sage Budget rollup
- Artifact: the $5.8M Bancroft budget presentation — generated, not manually assembled

---

## 17. Revised Build Order

Build order follows the core loop: **RFP → Bid Comp → Manage Job**. Everything else layers on after the loop works.

### Build 1: Spreadsheet Understanding Engine
- Deep parse the Multi Trade Bid Template (19 tabs)
- Deep parse the Estimate Template (6 tabs)
- Build the auto-research compare loop
- Produce test copies, validate against originals
- Output: verified template schemas for both workbooks

### Build 2: RFP + Bid Comp (First thing that works)
- Schema: dcfg_rfp_package, dcfg_rfp_project, dcfg_rfp_vendor, dcfg_proposal
- Produce pre-filled bid comp xlsx from Dataverse data (project scope → trade tabs, vendor list → BIDDER columns)
- Power Automate: watch SharePoint Proposals folder → parse completed bid comp on save → write vendor responses to Dataverse
- SPA: RFP list, bid comp status view, award capture
- Test: one real single-trade job end-to-end (RFP out → bids back → comparison → award)

### Build 3: Manage Job
- Schema: dcfg_invoice, dcfg_change_order (from BidComp spec, used as-is)
- Power Automate: watch Invoices + Change Orders folders → parse → write to Dataverse
- SPA: project detail with budget tracking (estimated vs awarded vs actual), invoice list, change order list
- Exhibit A: already built (DocGen v3)
- Exhibit B: auto-populate from bid comp award
- Test: track one job from award through invoicing to closeout

### Build 4: Project + Estimate Pipeline
- Schema: dcfg_project_line_item, dcfg_template_line_item, new columns on dcfg_project
- Produce pre-filled estimate template from project templates
- Power Automate: watch Budget folder → parse estimate on save → write line items to Dataverse
- SPA: project list, project create (quick entry + template), project detail with line items
- Sage vendor sync: import vendor list, map Vendor# to dcfg_vendor records

### Build 5: Program Rollup + Dashboards
- Produce Sage Budget rollup xlsx from Dataverse (all projects for a program → aggregate by CSI → category totals)
- SPA: Program Dashboard (budget bar, status breakdown, variance)
- SPA: Project Dashboard (cross-project health, needs attention list)
- Factor columns on dcfg_property (union, prevailing wage, regulatory tier)
- Historical comparison: average cost by template type + factor profile

### Build 6: AI Layer
- Vendor proposal PDF parsing → pre-fill bid comp BIDDER columns
- Confidence scoring per cell (high/inferred/gap)
- Trade suggestion from project description
- Estimate outlier flagging against historical data

---

## 18. Open Questions

1. **Sage vendor sync frequency** — One-time import or recurring sync? Sage is system of record — does the system check for new vendors periodically or on demand?

2. **SharePoint site provisioning** — Can we automate Teams site creation via Graph API, or does this require admin action? Affects whether Phase 3 (project site) is fully automated or semi-manual.

3. **Bid comp template variations** — Is the 19-tab Multi Trade template the only format, or are there trade-specific single-tab templates for simple single-trade RFPs?

4. **Invoice parsing complexity** — Are invoices consistently formatted (standard vendor invoice PDFs) or highly variable? Determines whether the system can auto-parse or needs human mapping.

5. **Change order approval workflow** — Is there a formal approval chain for change orders, or does the PM have authority? Affects whether the system needs an approval flow or just capture + categorize.

4. **Vendor proximity calculation** — Haversine from vendor address to property centroid? Requires geocoding on vendor and property addresses. Google Maps API or manual lat/lng entry?

5. **RFP email distribution** — Power Automate flow sending emails, or manual "here's the package, email it yourself" for now?
