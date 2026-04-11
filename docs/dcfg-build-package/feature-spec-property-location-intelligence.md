# Feature Spec: Property Location Intelligence Overlay

## For: Mobile Application Builder AI

This document describes a new feature to add to the existing DCFG mobile application. You are not building a new application. You are adding an intelligence layer to the existing property location detail screen so that when a user opens a specific property, contextually relevant historical and predictive information is presented discreetly.

---

## What This Feature Does

When a user taps on a property location in the mobile app, the location detail screen loads as it does today. This feature adds a lightweight intelligence section that surfaces three types of information without overwhelming the primary screen content:

1. **Recent work history** at this property — what was done, when, by whom
2. **Asset age alerts** — appliances, systems, or equipment that are approaching or past their expected lifespan
3. **Historical context** — notable events, issues, or decisions specific to this property

The user sees a small, unobtrusive indicator that information is available. They can tap to expand and read it, or ignore it entirely. The information does not interfere with the primary purpose of the location screen (viewing and managing property data).

---

## Data Sources

### Source 1: Recent Work History

Pull from the existing contract and work order data in Dataverse.

**Query:** All contracts (`dcfg_contracts`) where `dcfg_property_id` matches the current property, ordered by `modifiedon` descending, limited to the most recent 10.

**OData pattern:**
```
GET /api/data/v9.2/dcfg_contracts
  ?$filter=_dcfg_property_id_value eq {propertyId}
  &$orderby=modifiedon desc
  &$top=10
  &$select=dcfg_name,dcfg_status,modifiedon,dcfg_contract_number
  &$expand=dcfg_vendor_id($select=dcfg_name)
```

**Display per entry:** Contract number or name, vendor name, status badge, date. One line per entry. Tappable to open full contract detail if needed.

### Source 2: Asset Lifespan Tracking

This is the core predictive feature. DCFG maintains a reference file of expected lifespans for building systems and appliances across property types (residential, commercial, schools, group homes, apartments). Each property tracks its installed assets with install dates.

**Reference data — Expected Lifespans by Property Type:**

The system contains a reference table (or JSON file in the company brain) with entries like:

| System/Asset | Residential | Commercial | School | Group Home | Apartment |
|---|---|---|---|---|---|
| Furnace / Boiler | 15-20 yrs | 15-25 yrs | 20-25 yrs | 15-20 yrs | 15-20 yrs |
| Central AC | 12-15 yrs | 15-20 yrs | 15-20 yrs | 12-15 yrs | 12-15 yrs |
| Water Heater (Tank) | 8-12 yrs | 10-15 yrs | 10-15 yrs | 8-12 yrs | 8-12 yrs |
| Water Heater (Tankless) | 15-20 yrs | 15-20 yrs | 15-20 yrs | 15-20 yrs | 15-20 yrs |
| Roof (Asphalt Shingle) | 20-25 yrs | N/A | N/A | 20-25 yrs | 20-25 yrs |
| Roof (Flat/Commercial) | N/A | 15-25 yrs | 20-30 yrs | N/A | 15-25 yrs |
| Dishwasher | 9-13 yrs | 10-15 yrs | 8-12 yrs | 8-10 yrs | 8-10 yrs |
| Refrigerator | 10-18 yrs | 10-15 yrs | 10-15 yrs | 10-15 yrs | 10-15 yrs |
| Washer | 10-14 yrs | N/A | N/A | 8-12 yrs | 8-12 yrs |
| Dryer | 10-13 yrs | N/A | N/A | 8-12 yrs | 8-12 yrs |
| Elevator | N/A | 20-25 yrs | 20-25 yrs | N/A | 20-25 yrs |
| Fire Suppression System | N/A | 20-25 yrs | 20-25 yrs | 15-20 yrs | 20-25 yrs |
| Electrical Panel | 25-40 yrs | 25-40 yrs | 25-40 yrs | 25-40 yrs | 25-40 yrs |
| Plumbing (Supply Lines) | 40-70 yrs | 40-70 yrs | 40-70 yrs | 40-70 yrs | 40-70 yrs |
| Carpet | 5-10 yrs | 5-8 yrs | 3-7 yrs | 3-7 yrs | 5-8 yrs |
| Interior Paint | 5-7 yrs | 5-10 yrs | 3-5 yrs | 3-5 yrs | 5-7 yrs |
| Exterior Paint | 5-10 yrs | 7-12 yrs | 7-12 yrs | 5-10 yrs | 7-12 yrs |
| Parking Lot (Asphalt) | 15-20 yrs | 15-20 yrs | 15-20 yrs | 15-20 yrs | 15-20 yrs |
| Windows | 15-30 yrs | 15-30 yrs | 15-30 yrs | 15-30 yrs | 15-30 yrs |
| Garage Door / Opener | 10-15 yrs | 15-20 yrs | N/A | N/A | 15-20 yrs |
| Security System | 10-15 yrs | 10-15 yrs | 10-15 yrs | 10-15 yrs | 10-15 yrs |
| Smoke / CO Detectors | 7-10 yrs | 7-10 yrs | 7-10 yrs | 7-10 yrs | 7-10 yrs |
| Sump Pump | 7-10 yrs | 10-15 yrs | 10-15 yrs | 7-10 yrs | 10-15 yrs |
| Generator | 15-20 yrs | 15-25 yrs | 15-25 yrs | 15-20 yrs | 15-25 yrs |

**How the calculation works:**

1. Read the property's `dcfg_location_type` to determine the property type (residential, commercial, school, group home, apartment)
2. Read the property's tracked assets — each asset has an `install_date` and an `asset_type` that maps to the reference table above
3. Calculate `age = today - install_date` in years
4. Look up the expected lifespan range for that asset type and property type
5. Determine status:
   - **Past lifespan:** Age exceeds the upper bound of the range → status = `beyond-lifespan`
   - **End of life:** Age is within 2 years of the upper bound → status = `end-of-life`
   - **Aging:** Age exceeds the lower bound of the range → status = `aging`
   - **Current:** Age is below the lower bound → status = `current` (do not surface — this is the normal state)

Only surface assets with status `beyond-lifespan`, `end-of-life`, or `aging`. Never show the full asset inventory on this overlay — that belongs in a dedicated asset management screen.

### Source 3: Property Notes from Company Brain

Pull from `company-brain/operations/property-knowledge.json` in the SharePoint document library. Filter entries where `dataverse_ref.record_id` matches the current property GUID.

These are human-written contextual notes — site access instructions, known issues, special circumstances, historical decisions. Display as a simple list of notes with author and date.

---

## UX Design Rules

These rules are mandatory. They come from the DCFG UX psychology principles that govern all screens in the application.

### Rule 1: Progressive Disclosure — Don't Dump Everything on Screen

The intelligence overlay is **collapsed by default**. The user sees only a small indicator showing that information is available, not the information itself.

**What the user sees on load (before any interaction):**

A thin, quiet section below the property header (or at the bottom of the primary content area) containing up to three small chips/badges:

```
[2 work orders this year]  [1 asset alert]  [3 notes]
```

- Each chip shows a count only. No detail until tapped.
- If a count is zero, that chip is absent (not shown as "0 work orders").
- If all counts are zero, the entire section is absent. No empty state. No "no information available" message.
- The asset alert chip uses a warm color (amber) only if any asset is `beyond-lifespan` or `end-of-life`. Otherwise it uses the default muted color.

**What happens when the user taps a chip:**

The chip expands into a brief, scannable list below it. Maximum 5 items visible before a "show more" control. Each item is one line — enough to understand at a glance, tappable for full detail.

### Rule 2: Von Restorff — Asset Alerts Must Be Visually Distinct but Not Alarming

Asset lifespan alerts are important but not emergencies. They are predictive, not failures.

- `beyond-lifespan` → Small red dot indicator (not a banner, not a warning icon, not a modal). Subtle but visible.
- `end-of-life` → Small amber dot indicator.
- `aging` → No special indicator. Listed if the section is expanded, but no visual urgency.

Never use alert dialogs, warning modals, or interruptive UI for lifespan information. This is informational context, not an alarm system. The user is opening a property to do their job — do not hijack their workflow with warnings about a 12-year-old dishwasher.

### Rule 3: Miller's Law — Maximum 7 Items Visible in Any Expanded Section

- Work history: Show the 5 most recent. "Show all" link for the rest.
- Asset alerts: Show up to 5. Sorted by urgency (`beyond-lifespan` first, then `end-of-life`, then `aging`). "Show all" for the rest.
- Property notes: Show the 3 most recent. "Show all" for the rest.

### Rule 4: Hick's Law — No Decisions Required

This overlay is read-only. There are no action buttons, no forms, no edit controls. The user reads the information and makes their own decisions about what to do with it. If they need to act (create a work order, update an asset, contact a vendor), they navigate to the appropriate existing screen. This overlay does not duplicate functionality that exists elsewhere.

### Rule 5: Information Hierarchy

The property's primary data (name, address, type, status, contact info, active contracts) remains the dominant content on the screen. The intelligence overlay is secondary — visually lighter, positioned below the primary content, and never competing for attention.

The overlay should feel like a "by the way" — not a "WARNING."

---

## Asset Data Model

Each property needs a way to track installed assets. If this doesn't exist yet, the minimum viable structure is:

**Table: `dcfg_property_asset` (or similar)**

| Column | Type | Description |
|---|---|---|
| dcfg_property_asset_id | PK | Auto-generated |
| dcfg_property_id | Lookup → dcfg_property | Which property this asset belongs to |
| dcfg_asset_type | Choice | Maps to the lifespan reference table (furnace, AC, water-heater, roof, dishwasher, etc.) |
| dcfg_asset_name | String | Specific name or description ("Carrier Infinity furnace", "Whirlpool dishwasher") |
| dcfg_make_model | String | Manufacturer and model if known |
| dcfg_install_date | Date | When this asset was installed or last replaced |
| dcfg_last_service_date | Date | Most recent maintenance or service |
| dcfg_last_service_notes | Multiline | What was done |
| dcfg_status | Choice | Active / Replaced / Decommissioned |

**Entity set name:** `dcfg_property_assets`

**OData query to get assets approaching end of life for a property:**
```
GET /api/data/v9.2/dcfg_property_assets
  ?$filter=_dcfg_property_id_value eq {propertyId} and dcfg_status eq 100000000
  &$select=dcfg_asset_type,dcfg_asset_name,dcfg_install_date,dcfg_last_service_date
```

The age calculation and lifespan comparison happens client-side (or in a Power Automate flow that pre-computes the status). The reference lifespan table can be a JSON file in the company brain or a Dataverse reference table — either works. The mobile app loads the reference data once and caches it.

---

## Lifespan Reference Data — Storage Options

**Option A: JSON file in company brain (simpler, no schema change)**

Store in `company-brain/operations/asset-lifespans.json`. The mobile app fetches this file once and caches it. Any update to the reference data is just editing the JSON file in SharePoint.

**Option B: Dataverse reference table (more structured, queryable)**

A `dcfg_asset_lifespan` table with columns for asset_type, property_type, min_years, max_years. Queryable via OData. Editable through the Power Pages admin interface.

Either option works. Option A is faster to implement. Option B is better long-term if the lifespan data needs to be managed by non-technical users.

---

## Example: What the User Sees

**Scenario:** Alicia opens the "Cedar Grove Group Home" property in the mobile app.

**On load, she sees the normal property detail screen.** Below the primary content, a thin intelligence bar shows:

```
[4 recent contracts]  [🟠 2 asset alerts]  [1 note]
```

The amber dot on "2 asset alerts" tells her something is aging. She can ignore it or tap it.

**She taps "2 asset alerts":**

The section expands to show:

```
🔴  Water heater (tank) — installed 2013 — 13 years old
    Expected lifespan: 8-12 years (group home)

🟠  Furnace — installed 2011 — 15 years old  
    Expected lifespan: 15-20 years (group home)
```

She now knows the water heater is past its expected life and the furnace is entering its end-of-life window. She decides to mention the water heater to the vendor at their next visit. She collapses the section and continues with her actual task.

**She taps "1 note":**

```
"Access through side entrance only — front door lock unreliable. 
 Vendor should call site manager Maria 30 min before arrival."
 — Alicia, Jan 2026
```

She wrote this note herself months ago but had forgotten. Now every team member who opens this property sees it.

---

## What You Are NOT Building

- Not a new screen or page — this is an addition to the existing property detail screen
- Not an asset management system — this overlay surfaces alerts, it does not manage the asset inventory
- Not a maintenance scheduler — it does not create work orders or schedule service
- Not a notification system — it does not push alerts or send emails about aging assets
- Not a replacement for UpKeep — when the UpKeep integration (OI-06) is live, this feature complements it by adding the lifespan prediction layer that UpKeep does not provide

---

## Summary for the AI Builder

You are adding an intelligence overlay to the existing property location detail screen in the mobile app. The overlay pulls from three sources: recent contract/work history from Dataverse, asset age calculations against a lifespan reference table, and human-written property notes from the company brain. The overlay is collapsed by default, shows only counts in small chips, and expands on tap. Asset alerts use subtle color indicators (red dot for beyond lifespan, amber dot for end of life). The overlay is read-only, secondary to the primary property content, and never interrupts the user's workflow. Maximum 5-7 items visible in any expanded section. If there is nothing to show, the overlay is completely absent.
