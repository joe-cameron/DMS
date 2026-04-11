# DCFG Report Specification: Capital Replacement Plan (Renewal Report)

**Report ID:** RPT-CAP-001  
**Version:** 1.0  
**Date:** 2026-03-15  
**Type:** Multi-slide PowerPoint (6 slides) + optional Interactive HTML  
**Trigger:** User requests a capital replacement plan or renewal report for a customer  

---

## Purpose

This is the renewal document. It shows a property owner the complete picture of their portfolio's equipment health, what's due for replacement, what repair history supports the recommendation, what staff are saying, and three budget tiers to choose from. The framing is mission-driven — these organizations serve people with intellectual and physical disabilities, and every facility failure impacts residents and pulls budget from care.

This report is the differentiator. No other contractor delivers this level of visibility.

---

## Data Sources

### Customer + Locations
```
Entity: dcfg_customers
Filter: dcfg_customerid eq '{CUSTOMER_GUID}'
Select: dcfg_name,dcfg_primary_contact_name,dcfg_primary_contact_email

Entity: dcfg_properties (entity set: dcfg_propertys — NOT dcfg_properties)
Filter: _dcfg_customer_id_value eq '{CUSTOMER_GUID}' and dcfg_active_flag eq true
Expand: dcfg_location_type_id($select=dcfg_name)
Select: dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_contact_person,dcfg_contact_title
```

### Equipment / Appliances
```
Entity: dcfg_appliances
Filter: _dcfg_property_id_value eq '{PROPERTY_GUID}'
Expand: dcfg_appliance_type_id($select=dcfg_name,dcfg_expected_lifespan_years;$expand=dcfg_benchmark_id($select=dcfg_max_life_years,dcfg_planned_replace_years,dcfg_failure_modes,dcfg_top_brands,dcfg_category))
Select: dcfg_name,dcfg_install_date,dcfg_replace_by_status,dcfg_estimated_replace_by,dcfg_months_to_replace_by
```

### T&M Repair History (FY work orders — type = Work Order, not part of a program, has T&M cost codes)
```
Entity: dcfg_contracts
Filter: _dcfg_customer_id_value eq '{CUSTOMER_GUID}' and dcfg_contract_type eq 0 and dcfg_contract_date ge '{FY_START}' and dcfg_contract_date le '{FY_END}'
Expand: dcfg_property_id($select=dcfg_name)
Select: dcfg_contract_number,dcfg_contract_fee,dcfg_contract_date,dcfg_client_name

-- Then for each T&M WO, get line items:
Entity: dcfg_contract_lines
Filter: _dcfg_contract_id_value eq '{WO_GUID}'
Expand: dcfg_cost_code_id($select=dcfg_name)
Select: dcfg_description,dcfg_amount
```

### Equipment Benchmarks (reference data)
```
Entity: dcfg_equipment_benchmarks
Select: dcfg_name,dcfg_max_life_years,dcfg_planned_replace_years,dcfg_failure_modes,dcfg_top_brands,dcfg_category,dcfg_setting,dcfg_benchmark_type
```

### Staff Satisfaction (if survey data exists — may be manual input or future table)
```
-- Future: dcfg_survey_responses or manual data entry
-- For now: passed as input parameters or maintained in a config table
```

---

## Calculated Fields

| Field | Formula |
|---|---|
| Asset Age | YEAR(today) - YEAR(dcfg_install_date) |
| 80% Threshold | dcfg_benchmark.dcfg_planned_replace_years (= floor(max_life * 0.80)) |
| Max Life | dcfg_benchmark.dcfg_max_life_years |
| Status | If age > max_life: "REPLACE NOW". If age >= 80% threshold: "BUDGET FY{next}". Else: "HEALTHY" |
| Replace Now Count | COUNT(assets where age > max_life) |
| Budget FY Count | COUNT(assets where age >= 80% threshold AND age <= max_life) |
| Healthy Count | COUNT(assets where age < 80% threshold) |
| Total Assets | COUNT(all assets) |
| Total T&M Spend | SUM(T&M work orders.dcfg_contract_fee) for FY |
| Repeat T&M | SUM(cost) for assets with 2+ T&M work orders in FY |
| Repeat T&M Asset Count | COUNT(DISTINCT assets with 2+ T&M WOs) |
| Tier High | SUM(replacement cost for ALL replace-now + ALL budget-FY items) |
| Tier Medium | SUM(replacement cost for ALL replace-now + TOP N highest-risk budget-FY items) |
| Tier Low | SUM(replacement cost for ALL replace-now items only — or items with repeat T&M) |
| Payback Period | replacement_cost / annual_TM_cost_for_that_asset |
| Location Type Counts | GROUP BY dcfg_location_type.dcfg_name |

### Scope Rules by Location Type

| Location Type | Scope |
|---|---|
| Group Home | Building Systems + Appliances |
| Day Program | Building Systems + Appliances |
| Admin Office | Building Systems + Appliances |
| School | Building Systems + Appliances |
| Apartment | Appliances Only (building systems are landlord responsibility) |

---

## Slide Specifications

### Slide 1 — Title (Dark background #0B1929)

**Left side:**
- "DCFG CONTRACTING SUITE" tag
- "Capital Replacement Plan" Georgia 28pt white bold
- "FY {year} Facilities Budget Proposal" Georgia 18pt gray
- Amber divider
- Customer name, location count, asset count, 80% rule mention
- Property type breakdown: "{N} Group Homes · {N} Apartments · ..."
- Renewal period
- **Mission box** (navy-mid bg, amber left border, heart icon): "Your mission is the people you serve. Every unplanned repair pulls budget from programs, staffing, and resident care. This plan replaces equipment proactively so your operating budget stays predictable and your homes stay safe."

**Right side — 3 tier preview cards:**
- Full Protection: ${tier_high} — "Zero deferred maintenance / Every home protected"
- Priority Items: ${tier_medium} — "Clear the backlog + highest failure-risk items"
- Essential Only: ${tier_low} — "Failed + safety items / Minimum responsible spend"
- Each card: colored left accent, arrow icon, label/cost/description

**Footer:** Source attributions — ASHRAE, BOMA, InterNACHI, JD Power, FY T&M history

---

### Slide 2 — By Location Type (White background)

**Title:** "By Location Type" Georgia 24pt navy  
**Subtitle:** "Each property type has unique equipment, compliance, and resident-impact considerations"

**One card per location type (expandable in interactive version):**

Each card contains:
- Left accent bar: Red if has replace/budget items, green if all healthy
- Location type name + count — Georgia 16pt navy bold
- Scope badge — "Systems + Appliances" (green) or "Appliances Only" (amber)
- Stats: Replace count (red), Budget count (amber), Asset count (navy)
- Staff satisfaction score — Georgia 16pt in colored badge
- T&M: call count + spend — Consolas 10pt amber

**Two side-by-side panels per card:**
- **REPORTED PROBLEMS** (red-light background): Real incident reports from staff. Include date, location name, what happened, impact on residents. Example: "Elm St: Resident in wheelchair could not access bathroom for 3 hours during water heater flood (Jan 15)."
- **COMPLETED SUCCESSFULLY** (green-light background): Work completed that made a difference. Include measurable outcomes. Example: "Heritage N: 3 water heaters replaced — zero hot water complaints since."

**Data for problems/successes:** Pulled from dcfg_audit_logs (action_type = Other, Data Updated) or a future dcfg_incident_report table. For now, may be manually curated per customer.

---

### Slide 3 — What Your Staff Is Saying (White background)

**Title:** "What Your Staff Is Saying" Georgia 24pt navy  
**Subtitle:** "FY{year} facilities satisfaction survey — house managers, program directors, admin staff"

**Left — Overall Score card (navy background):**
- "OVERALL SATISFACTION" Consolas tag
- Score — Georgia 56pt amber bold (e.g., "4.1")
- "/ 5" — Georgia 18pt gray
- Star visualization (★★★★☆)
- "{N} of {N} staff responded ({pct}%)"

**Right — Category bar chart:**
- One horizontal bar per survey category
- Categories: Emergency response time, Quality of completed work, Communication/updates, Preventive maintenance, Equipment condition overall, Disruption to residents
- Score value + colored fill bar (green > 4.0, amber 3.5-4.0, red < 3.5)

**Staff Quotes (2x2 grid):**
- Each quote card: colored left accent + background based on sentiment
  - Green: Positive / success story
  - Amber: Concern / constructive feedback
  - Red: Urgent safety issue
- Opening quotation mark — Georgia 28pt
- Quote text — Calibri 11pt italic
- Attribution — name, role, location — bold in accent color

**Data source:** Survey results from annual facilities survey (future: dcfg_survey table). Quotes manually curated or pulled from survey free-text responses.

---

### Slide 4 — What's Due for Replacement (White background)

**Title:** "What's Due for Replacement" Georgia 22pt navy  
**Subtitle:** "Staff reports and T&M history confirm every recommendation"

**80% Rule compact explainer:** Navy-pale background bar — "80% RULE: Replace at 80% of rated life. Below 80% = safe. 80-100% = budget now. Over 100% = overdue."

**Replace Now section:**
- Red header band: "Past Industry Max — Replace Now" + item count + est. total
- Table columns: Equipment, Location, 80%, Max, Age, **Staff Report / Impact**, Est.
- Each row includes the real staff report or T&M history in the impact column
- Age column: red bold for overdue items

**Past 80% section:**
- Amber header or callout box
- Compact list or table of items past the 80% threshold
- If many items: show top 6 in table + "N more past 80% (see appendix)" note

**Portfolio Summary box (right column on dense layouts):**
- Total Assets, Past Max, Past 80%, Healthy, FY T&M Spend, Repeat T&M

---

### Slide 5 — Your Options (White background)

**Title:** "Your Options" Georgia 24pt navy  
**Subtitle:** "Protect your residents, your staff, and your operating budget"

**Three tier columns (equal width, side by side):**

Each tier column:
- **Header band** (tier color): Label (Consolas tag), tier name, price (Georgia 22pt white bold)
- **Coverage bar:** "{N} of {total} items | {pct}%" with fill bar
- **INCLUDES section:** Bullet list (4 items max)
- **OUTCOME section:** Colored background, 3-line description
- **RESIDENT IMPACT section:** Bold text in tier color describing risk to residents

| Tier | Items | Includes | Risk Label |
|---|---|---|---|
| Full Protection (green) | All replace + all budget items | All overdue, all approaching, eliminates repeat T&M, zero emergency risk | "None — every home is protected" |
| Priority Items (amber) | All replace + highest-risk budget items | All overdue, highest-risk approaching, covers staff complaints, defers lower-risk | "Low — deferred items between 80-90% of life" |
| Essential Only (brown) | Replace items only (or items with T&M history) | Past-max proven failures, repeat T&M items, stops recurring spend, defers all 80% items | "Elevated — mid-winter furnace or A/C failure could impact residents who depend on routine" |

---

### Slide 6 — Closing (Dark background #0B1929)

**Left side:**
- "DCFG CONTRACTING SUITE" tag
- **"Protect your budget."** Georgia 26pt white bold
- **"Focus on the people you serve."** Georgia 26pt amber bold
- Body text: "Select a tier and DCFG generates work orders automatically across all {N} locations. Every replacement is scheduled during normal hours, competitively bid, and tracked through completion. Your house managers stay focused on residents — not contractors."
- Amber divider + Decades contact block

**Right side — Plan Summary card (navy-mid, full height):**
- Locations, Assets, Past Max (red), Past 80% (amber), FY T&M (amber), Staff Satisfaction (amber)
- Divider
- Three tier prices: Full (green), Priority (amber), Essential (red)

---

## Interactive HTML Version (RPT-CAP-001-HTML)

Same content as the PowerPoint, delivered as a single self-contained HTML file that opens in any browser.

**Navigation:** Fixed top bar with 5 tabs — Overview, By Location Type, What's Due, Staff Voices, Your Options. Click to switch sections.

**Interactivity:**
- Location type cards: Click to expand/collapse problem and success panels
- Tier cards on overview: Click to jump to Your Options
- Survey bars: Animated fill on page load
- Responsive: Works on desktop, tablet, phone
- Printable: Ctrl+P prints all sections

**Self-contained:** All CSS inline, Google Fonts loaded from CDN, no JavaScript dependencies. Works offline after first load.

---

## Tier Pricing Logic

The AI generating this report must calculate tier pricing from actual data:

```
Tier High (Full Protection):
  = SUM(estimated_replacement_cost) for ALL assets where status = REPLACE_NOW
  + SUM(estimated_replacement_cost) for ALL assets where status = BUDGET_FY
  
Tier Medium (Priority Items):
  = SUM(estimated_replacement_cost) for ALL assets where status = REPLACE_NOW
  + SUM(estimated_replacement_cost) for TOP N assets where status = BUDGET_FY
    ranked by: (1) has_repeat_TM = true first, (2) staff_complaint = true, 
               (3) highest replacement_cost, (4) closest to max_life

Tier Low (Essential Only):
  = SUM(estimated_replacement_cost) for assets where status = REPLACE_NOW
    AND (has_repeat_TM = true OR is_safety_critical = true)
  -- If no T&M history: use all REPLACE_NOW items
```

**Estimated replacement cost** comes from dcfg_equipment_benchmark average costs (future field) or from historical WO line item amounts for the same equipment type at other locations.

---

## Staff Report / Impact Data

For each asset recommended for replacement, the report should include a human-readable impact statement. Sources (in priority order):

1. **Incident reports** — dcfg_audit_logs or future dcfg_incident table
2. **T&M call count + cost** — derived from dcfg_contracts (T&M type) linked to the same equipment
3. **Staff survey free-text** — if available
4. **Default statement** — "Past {N}yr rated life; {N} years overdue. Industry failure modes: {benchmark.failure_modes}"

The impact column is what makes this report different from a spreadsheet. It connects data to people.

---

## Consistency Rules (MANDATORY for all report generations)

1. **Same layout every time.** Only data changes. Slide structure, element positions, font sizes, colors, and spacing are locked to this spec.
2. **Same design tokens.** Never substitute fonts or colors. Use the token table exactly.
3. **Same slide order.** Title → Location Types → Staff Voices → What's Due → Options → Closing.
4. **Same tier structure.** Always three tiers: Full/Priority/Essential. Always show coverage bar, includes, outcome, resident impact.
5. **Same mission framing.** Every report opens with the mission statement and closes with "Protect your budget. Focus on the people you serve."
6. **Same data connections.** Staff quotes, problem reports, and T&M history are always tied to specific equipment and locations — never generic.
7. **80% rule is always explained.** Every report includes the lifecycle bar and the "below 80% = safe, 80-100% = budget, over 100% = overdue" explanation.

---

## Design Tokens

```
Navy:        #0F2744    backgrounds, headers
Navy-mid:    #1B3A5C    table headers, card backgrounds
Navy-pale:   #EDF1F8    light card backgrounds, WO subtotals
Amber:       #C4A24C    CTAs, progress bars, amendment values
Amber-dark:  #8A6B12    amendment labels, warning text
Amber-light: #FFF8E7    amendment row backgrounds, warning callouts
Green:       #2D8659    signed status, healthy, remaining budget, Tier High
Green-light: #E8F5EE    success panels, remaining row
Red:         #C0392B    overdue, void, urgent quotes, Tier Low risk
Red-light:   #FDEDED    problem panels, overdue row backgrounds
Steel:       #F5F7FA    alternating rows, section backgrounds
Border:      #D4D9E2    table borders, dividers
Text-2:      #3D5080    secondary body text
Text-3:      #8695AA    tertiary text, labels, timestamps
Tier-High:   #1A6B3C    Full Protection accent
Tier-High-Lt:#E6F4EC    Full Protection backgrounds
Tier-Med:    #B8860B    Priority Items accent
Tier-Med-Lt: #FFF8E1    Priority Items backgrounds
Tier-Low:    #8B4513    Essential Only accent
Tier-Low-Lt: #FDF0E6    Essential Only backgrounds
Background:  #0B1929    dark slide backgrounds

Font-display: Fraunces (serif) — headings, large numbers, tier prices
Font-sans:    IBM Plex Sans — body text, labels, descriptions
Font-mono:    IBM Plex Mono — reference numbers, data values, tags, percentages
```

---

## Example Output References

- PowerPoint: `/mnt/user-data/outputs/DCFG_Capital_Plan_Full.pptx`
- Interactive HTML: `/mnt/user-data/outputs/DCFG_Capital_Plan_Interactive.html`
- Equipment benchmarks: `/mnt/user-data/outputs/DCFG_Schema_OP29_EquipmentBenchmarks.ps1` (206 records)

Sample data: Albany Capital Partners, 25 locations, 142 assets, $87,400/$52,800/$31,200 tiers, 4.1/5 staff satisfaction.
