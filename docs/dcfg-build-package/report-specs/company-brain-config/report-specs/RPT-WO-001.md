# DCFG Report Specification: Single Work Order Budget Report

**Report ID:** RPT-WO-001  
**Version:** 1.0  
**Date:** 2026-03-15  
**Type:** Single-page PowerPoint (1 slide)  
**Trigger:** User requests a work order budget report for a specific WO number  

---

## Purpose

Show how a single work order's budget is being consumed by the original scope and its amendments. This is the drill-down view — one location, one WO, every line item, every amendment, budget utilization at a glance.

---

## Data Sources

### Primary Record
```
Entity: dcfg_contract
Filter: dcfg_contract_number eq '{WO_NUMBER}'
Expand: dcfg_customer_id($select=dcfg_name),dcfg_property_id($select=dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_contact_person,dcfg_contact_title),dcfg_vendor_id($select=dcfg_legal_name),dcfg_program_id($select=dcfg_name,dcfg_budget)
Select: dcfg_contract_number,dcfg_contract_fee,dcfg_budget,dcfg_budget_committed,dcfg_status,dcfg_contract_date,dcfg_contract_family,dcfg_signer_printed
```

### Amendments (child contracts)
```
Entity: dcfg_contracts
Filter: _dcfg_parent_contract_id_value eq '{WO_GUID}' and dcfg_contract_type eq 1
OrderBy: dcfg_amendment_sequence asc
Select: dcfg_contract_number,dcfg_contract_fee,dcfg_status,dcfg_contract_date,dcfg_amendment_sequence
```

### Line Items (original WO)
```
Entity: dcfg_contract_lines
Filter: _dcfg_contract_id_value eq '{WO_GUID}'
Expand: dcfg_cost_code_id($select=dcfg_name,dcfg_customer_ap_code)
OrderBy: dcfg_item_number asc
Select: dcfg_item_number,dcfg_description,dcfg_amount
```

### Line Items (each amendment)
```
Entity: dcfg_contract_lines
Filter: _dcfg_contract_id_value eq '{AMENDMENT_GUID}'
Expand: dcfg_cost_code_id($select=dcfg_name,dcfg_customer_ap_code)
OrderBy: dcfg_item_number asc
Select: dcfg_item_number,dcfg_description,dcfg_amount
```

---

## Calculated Fields

| Field | Formula |
|---|---|
| Original WO Value | dcfg_contract.dcfg_contract_fee |
| Total Amendment Value | SUM(amendments.dcfg_contract_fee) |
| Total Committed | Original WO Value + Total Amendment Value |
| Budget | dcfg_contract.dcfg_budget (may be null — WO has no budget ceiling) |
| Remaining | Budget - Total Committed (only if budget is set) |
| Utilization % | (Total Committed / Budget) * 100 (only if budget is set) |
| Line Count | COUNT(all line items across WO + amendments) |
| Amendment Count | COUNT(amendments) |

---

## Layout Specification (Single Slide — 10" x 5.63")

### Top Band (full width, 0.85" tall)
- **Background:** var(--navy) #0F2744
- **Top accent:** 0.06" amber bar across full width
- **Left:** "DCFG" monospace tag, "Work Order Budget Report" Georgia 14pt bold white, WO number Consolas 10pt amber bold
- **Center:** Location name + address + contact — Calibri 8.5pt gray
- **Right — stacked vertically:**
  - "BUDGET" label Consolas 6.5pt gray, right-aligned
  - Budget amount Georgia 14pt white bold, right-aligned
  - "COMMITTED {amount} | {pct}%" Consolas 7pt amber bold
  - Progress bar (amber fill on navy track, height 0.08")
  - "$XXX remaining" Consolas 6pt gray
- **If no budget assigned:** Show "No budget ceiling" instead of amount, hide progress bar

### Left Column (x: 0.35", width: 3.4")

#### Budget Spend-Down Section
- **Header:** "Budget Spend-Down" Consolas 7.5pt navy bold
- **Stacked bar:** Full width, 0.3" tall
  - Navy segment = original WO proportion
  - Amber segment = Amendment 1
  - Dark amber segment = Amendment 2
  - (Continue for each amendment)
  - Labels inside segments if wide enough: "WO $XX,XXX" white Consolas 7pt

#### Financial Table
- **Header row:** Navy-mid background, white text, columns: (blank), Item, Value, Cum., %
- **Budget row:** Gray background — label "Budget", "Approved ceiling", budget amount bold
- **WO row:** White — WO ref, short description, value bold, cumulative, percentage
- **Amendment rows:** Amber-light background — "A1"/"A2" ref, description, "+$X,XXX" amber bold, cumulative, percentage
- **Committed total row:** Navy background — "Committed", total amber, percentage amber
- **Remaining row:** Green-light background — "Remaining", amount green bold, percentage green

#### Timeline Section
- **Header:** "Timeline" Consolas 7.5pt navy bold
- **Horizontal line:** Gray, 2pt, spanning column width
- **Nodes:** One per event (WO signed, each amendment)
  - Circle: 0.14" diameter, colored (navy for WO, amber for amendments)
  - Date above: Consolas 7pt bold
  - Value below: Consolas 7pt bold
  - Label below value: Calibri 6.5pt gray

### Right Column (x: 3.85", width: 5.8")

#### Exhibit A — All Line Items
- **Header:** "Exhibit A — All Line Items" Consolas 7.5pt navy bold
- **Table columns:** #, Source, Cost Code, Description, Amount
- **Row styling:**
  - WO lines: White/steel alternating, source="WO" navy bold
  - Amendment lines: Amber-light background, source="A1"/"A2" dark-amber bold
  - Subtotal after each group: Matching background, right-aligned "Original WO Subtotal" / "Amendment #N Subtotal"
  - Grand total: Navy background, amber text, "Grand Total (N lines)"
- **Line numbering:** Continuous across WO + amendments (1, 2, 3... not resetting per amendment)
- **Descriptions:** Include equipment model/brand and 80% status note where applicable: "Furnace - Carrier 80K BTU gas (was 15yr, past 80%)"

#### Amendment History Section
- **Header:** "Amendment History" Consolas 7.5pt navy bold
- **One card per amendment:**
  - Background: Alternating amber-light / steel
  - Left amber accent bar (0.04" wide)
  - Ref + date + "Signed"/"Pending" status + value
  - Description text: Includes justification — age, 80% threshold status, T&M call count and cost, payback period

### Footer Bar (full width, 0.28" tall)
- **Background:** var(--navy)
- **Text:** "Decades Construction Group | Program: {program_name} | Customer: {customer_name} | Report: {date}" Calibri 7.5pt gray centered

---

## Conditional Logic

| Condition | Behavior |
|---|---|
| No budget on WO | Hide progress bar, show "No budget ceiling", hide Remaining row, hide utilization % |
| No amendments | Hide amendment sections, timeline shows single node, Exhibit A shows WO lines only |
| WO status = Pending | Show "Pending Signature" amber badge instead of "Signed" green |
| WO status = Void | Show "Voided" red badge, all amounts struck through |
| No program assigned | Footer shows "Standalone Work Order" instead of program name |
| Budget > 90% utilized | Add red warning: "⚠ Budget nearly exhausted — $XXX remaining" |
| Budget exceeded | Progress bar overflows in red, "OVER BUDGET by $XXX" red text |

---

## Design Tokens

```
Navy:       #0F2744    (backgrounds, headers)
Navy-mid:   #1B3A5C    (table headers)
Navy-pale:  #EDF1F8    (WO row subtotal background)
Amber:      #C4A24C    (amendment values, progress bars, CTAs)
Amber-dark: #8A6B12    (amendment labels, status)
Amber-light:#FFF8E7    (amendment row backgrounds)
Green:      #2D8659    (remaining budget, signed status)
Green-lt:   #E8F5EE    (remaining row background)
Red:        #C0392B    (overdue, void, warnings)
Steel:      #F5F7FA    (alternating rows)
Border:     #D4D9E2    (table borders)
Text-2:     #3D5080    (secondary text)
Text-3:     #8695AA    (tertiary text, labels)

Font-display:  Fraunces (serif) — headings, large numbers
Font-sans:     IBM Plex Sans — body text, labels
Font-mono:     IBM Plex Mono — reference numbers, data values, tags
```

---

## Example Output Reference

See `/mnt/user-data/outputs/DCFG_WO_Budget_Report.pptx` for the approved visual layout.

Sample data used: WO-2026-0033, Heritage House North, $30,000 budget, 2 amendments, 7 line items, 98.8% utilized.
