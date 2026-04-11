# DCFG Report Specification: Program Budget Performance Report

**Report ID:** RPT-PGM-001  
**Version:** 1.0  
**Date:** 2026-03-15  
**Type:** Multi-slide PowerPoint (6 slides)  
**Trigger:** User requests a program budget report for a specific program name or ID  

---

## Purpose

Show how a program's pre-assigned budget is being spent down across multiple work orders at multiple locations. Programs are budget containers — they group work orders under a ceiling so the customer can see total spend, remaining capacity, and where the money went.

---

## Data Sources

### Primary Record
```
Entity: dcfg_programs
Filter: dcfg_name eq '{PROGRAM_NAME}' (or dcfg_programid eq '{GUID}')
Expand: dcfg_customer_id($select=dcfg_name)
Select: dcfg_name,dcfg_budget,dcfg_budget_committed,dcfg_start_date,dcfg_end_date
```

### Work Orders in Program
```
Entity: dcfg_contracts
Filter: _dcfg_program_id_value eq '{PROGRAM_GUID}' and dcfg_contract_type eq 0
Expand: dcfg_property_id($select=dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_contact_person)
OrderBy: dcfg_contract_date asc
Select: dcfg_contract_number,dcfg_contract_fee,dcfg_status,dcfg_contract_date,dcfg_client_name
```

### Amendments for each WO
```
Entity: dcfg_contracts
Filter: _dcfg_parent_contract_id_value eq '{WO_GUID}' and dcfg_contract_type eq 1
OrderBy: dcfg_amendment_sequence asc
Select: dcfg_contract_number,dcfg_contract_fee,dcfg_status,dcfg_contract_date,dcfg_amendment_sequence
```

### Line Items (for each WO and amendment — optional detail level)
```
Entity: dcfg_contract_lines
Filter: _dcfg_contract_id_value eq '{CONTRACT_GUID}'
Expand: dcfg_cost_code_id($select=dcfg_name)
OrderBy: dcfg_item_number asc
Select: dcfg_item_number,dcfg_description,dcfg_amount
```

---

## Calculated Fields

| Field | Formula |
|---|---|
| Total WO Values | SUM(work_orders.dcfg_contract_fee) where status IN (Signed, Generated, Sent) |
| Total Amendment Values | SUM(all amendments.dcfg_contract_fee) where status IN (Signed, Generated, Sent) |
| Total Committed | Total WO Values + Total Amendment Values |
| Pending Value | SUM(all contracts where status IN (Draft, Sent) and not yet Signed) |
| Remaining | dcfg_budget - Total Committed |
| Remaining After Pending | dcfg_budget - Total Committed - Pending Value |
| Utilization % | (Total Committed / dcfg_budget) * 100 |
| WO Count | COUNT(work orders) |
| Amendment Count | COUNT(all amendments) |
| Location Count | COUNT(DISTINCT work_order.dcfg_property_id) |
| Per-Location Total | SUM(WO + amendments) grouped by dcfg_property_id |
| Monthly Spend | SUM(WO + amendments) grouped by month of dcfg_contract_date |
| Cumulative Spend | Running SUM of monthly spend |

---

## Slide Specifications

### Slide 1 — Program Title (Dark background)

**Background:** #0B1929  
**Top accent:** 0.06" amber bar  

**Left side:**
- "DCFG CONTRACTING SUITE" — Consolas 10pt amber, letter-spacing 4px
- Program name — Georgia 30pt white bold
- "Program Budget Report" — Georgia 22pt gray
- Amber divider line
- Customer name — Calibri 16pt white bold
- "{N} Locations | {N} Work Orders | {N} Amendments" — Calibri 10pt gray
- "Program Period: {start_date} - {end_date}" — Calibri 10pt gray
- "Report as of {today}" — Calibri 10pt gray

**Right side — Budget KPI card (navy-mid background, 2.9" x 3.5"):**
- "PROGRAM BUDGET" — Consolas 8pt gray centered
- Budget amount — Georgia 30pt white bold centered
- Progress bar: amber fill on navy track (height 0.18")
- Utilization % — Consolas 8pt amber bold
- Divider line
- KPI rows (Consolas 13pt + Calibri 9pt): Committed (amber), Remaining (green), Work Orders (white), Amendments (white), Locations (white), Pending Signature (amber-dark)

**Footer:** "Committed = signed WO value + signed amendment values" — Consolas 7.5pt gray

---

### Slide 2 — Budget at a Glance (White background)

**Title:** "Budget at a Glance" Georgia 24pt navy

**Budget Waterfall (4 boxes left-to-right with arrows between):**

| Box | Label | Color | Content |
|---|---|---|---|
| BUDGET | Navy-pale bg, navy accent | Budget amount, "Approved {date}" |
| COMMITTED | Amber-light bg, amber accent | Committed amount, "WO Values: $X / Amendments: +$X" |
| PENDING | Amber-light bg, amber-dark accent | Pending amount, "Awaiting signature" |
| REMAINING | Green-light bg, green accent | Remaining amount, "If pending signs: $X / X% available" |

**Full-width progress bar:** Amber fill (committed), semi-transparent amber (pending), gray (remaining). Labels below: "$0", "Committed X%", "Pending X%", "$Budget"

**Spend by Location horizontal bar chart:**
- One bar per location, sorted by total descending
- Amber bars, navy data labels
- Y-axis: location names (Calibri 8pt)
- Show values at bar end

**Location Summary card (right side):**
- Each location: Name, WO+Amendment count shorthand ("1W+2A"), total value amber bold

---

### Slide 3 — Work Order Detail (White background)

**Header band:** Navy background with clipboard icon, program name, budget/committed/remaining, mini progress bar

**Full-width table:**

| Column | Width | Content |
|---|---|---|
| Ref # | 1.25" | WO number or amendment number (Consolas, navy or amber-dark) |
| Location | 1.3" | Location name (amendments show "↳ {location}" italic) |
| Description | 1.9" | Scope description |
| Type | 0.8" | "Work Order" or "Amendment" |
| Value | 0.75" | Amount (WO = bold navy, amendments = amber-dark) |
| Status | 0.7" | Signed (green bg) / Pending (amber bg) / Draft (gray bg) |
| Date | 0.65" | Signed date or "--" if pending |

**Row styling:**
- Work orders: White background
- Amendments: Amber-light background, location italic with ↳ prefix
- Total row: Navy background, amber text, shows WO+Amendment count and remaining budget

**Footer note:** "Pending items ($X) not counted in committed total. If all sign: remaining = $X."

---

### Slide 4 — Spend by Location (White background)

**Title:** "Spend by Location" Georgia 24pt navy

**8 location cards in 2x4 grid (4.4" x 0.98" each):**

Each card:
- Left accent bar: Green (signed) or amber (pending/mixed)
- Location name — Georgia 10pt navy bold
- Address — Calibri 7pt gray
- Total value — Georgia 14pt navy bold (right-aligned)
- Status — Consolas 7pt (Signed green / Pending amber / Mixed amber)
- WO reference + value — Consolas 7pt navy
- Amendment references — "↳ A1 +$X,XXX (description) | A2 +$X,XXX (description)" — Consolas 6.5pt amber
- Scope summary — Calibri 7.5pt gray italic

---

### Slide 5 — Spend-Down Timeline (White background)

**Title:** "Spend-Down Timeline" Georgia 24pt navy

**Left side — Two charts stacked:**

**Monthly bar chart (top):**
- Amber bars, one per month with activity
- Data labels showing amounts
- Only show months with non-zero values

**Cumulative line chart (bottom):**
- Green line with markers
- Y-axis scaled to budget amount
- Show budget ceiling as reference line (red dashed)

**Right side — Month Detail cards:**
- One card per month with activity
- Month name — Georgia 9pt navy bold
- Monthly total — Consolas 9pt amber-dark bold right-aligned
- List of WOs and amendments committed that month
- Cumulative total at bottom of each card
- Largest-spend month gets amber-light background

---

### Slide 6 — Closing (Dark background)

**Background:** #0B1929  
**Title:** "DCFG CONTRACTING SUITE" tag + Program name Georgia 26pt white

**Body text:** "This report is generated on demand from live Dataverse data. Every work order, amendment, and budget update is reflected the moment it happens."

**Decades contact block**

**Right side — Program Summary card (navy-mid, 3.2" x 3.2"):**
- Budget, Committed, Pending, Remaining, Utilization, Locations, Work Orders, Amendments

---

## Conditional Logic

| Condition | Behavior |
|---|---|
| No amendments exist | Hide amendment rows, timeline shows WO nodes only, simplify financial table |
| Budget > 90% utilized | Show amber warning bar: "Budget XX% utilized — $X remaining" |
| Budget exceeded | Show red warning bar: "OVER BUDGET by $X", progress bar overflows red |
| Pending items exist | Show pending count/value in KPIs, footnote on WO detail slide |
| Only 1 location | Skip Slide 4 (Spend by Location), merge info into Slide 2 |
| Only 1 work order | Simplify to Single WO Budget Report format (RPT-WO-001) instead |
| No activity in a month | Skip that month in timeline, no bar in chart |

---

## Design Tokens

Same as RPT-WO-001 — see that specification for the full token table.

---

## Example Output Reference

See `/mnt/user-data/outputs/DCFG_Program_Report_FacilitiesRefresh.pptx` for the approved visual layout.

Sample data used: Facilities Refresh 2026, $180,000 budget, 8 locations, 11 WOs, 7 amendments, 62.4% utilized.
