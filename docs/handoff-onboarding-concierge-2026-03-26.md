# Decades Onboarding Concierge — Handoff Document
**Date:** 2026-03-26 | **Session:** Harness build + Operations Dashboard + Onboarding Portal

---

## What This Is

A customer-facing React SPA for property data collection. Replaces a spreadsheet that broke due to Microsoft security/macro issues. Providers receive an access code, enter property data over days/weeks, and data flows into DCFG's location database through a staging → review → approve pipeline.

**This is the first touchpoint with new customers. The portal IS the Decades brand experience.**

## Product Philosophy

- **The user is a low-level office worker** collecting info their boss told them to gather. They are not technical.
- **Never show the full scope at once.** One location, one section, collapsed by default.
- **No mandatory fields. No pressure.** They fill what they know, skip what they don't, come back tomorrow.
- **Suggestions, not demands.** "A photo of the roof would help" — not "upload required."
- **Friendly tone everywhere.** Warm, professional, no jargon. No UpKeep. No Dataverse. No DCFG internal language.
- **Auto-save everything.** Never lose work. Never think about saving.
- **Come and go freely.** Progress bar shows how far along, not how far behind.
- **Photos welcome.** Suggest photo uploads where they'd help (roof, basement, pool, generator nameplate).
- **20+ locations per customer is normal.** The UX must not make this feel huge.

## Architecture

```
Admin (Joe) clicks "Send to Customer" on customer record
  → System generates access code (30-day expiry)
  → Calls UpKeep API for customer's location IDs
  → Pre-populates location addresses into seed file
  → Sends access code + portal link to customer email

Customer opens portal, enters code
  → Loads seed (first visit) or localStorage (returning)
  → Fills in property details, vendors, authorized users
  → Auto-saves to localStorage (debounced 800ms)

Data flow (future):
  Customer data → dcfg_property_intake (staging table)
  → DCFG staff notified of changes
  → Review → Approve → writes to dcfg_property (live table)
  → Customer never sees internal systems
```

## Current Build State

### What's Built and Working

| Component | Status | Location |
|---|---|---|
| React SPA | Built, compiles clean | `C:\dcfg\spa\dcfg-property-intake\` |
| Login screen | Working | Access code gating, JADD2026 + DEMO1234 demo codes |
| Property form | Complete | All 29 main fields + 11 conditional detail sections |
| Vendor list | Complete | All 8 vendor fields per vendor |
| Authorized users | Complete | Name, email, phone, location access (all/specific) |
| localStorage persistence | Working | Auto-save with 800ms debounce |
| Seed file loading | Built | `public/seeds/{CODE}.json` loaded on first login |
| Admin seed script | Built | `C:\DCFG\Seed-CustomerPortal.ps1` |
| Decades corporate branding | Applied | Blue #085097 palette, Roboto font, corporate logo |
| Address parser | Built | Splits UpKeep single-string addresses |
| Design tokens | Updated | `src/tokens.js` — Decades corporate colors |

### What's NOT Built Yet

| Component | Notes |
|---|---|
| Dataverse staging table (`dcfg_property_intake`) | Schema needed — mirrors `dcfg_property` |
| Dataverse Web API integration | Replace localStorage with live Dataverse writes |
| Power Pages site provisioning | Must create via admin center, not API (see deployment issue) |
| Change notification to DCFG staff | When customer updates data, staff needs to know |
| Review/approve workflow | Staging → live push with approval gate |
| "Send to Customer" button | On customer detail page in dcfg-shell |
| Automated welcome email | Sends code + link to customer |
| Photo upload support | Optional but recommended for roof, pool, generator, etc. |
| Playwright E2E test suite | Full field coverage required (see testing section) |

## Deployment Issue (Unresolved)

**Problem:** Power Pages in the DCGWorkRequests environment rejects web file uploads with "not a valid type or too large" — even at 31KB. The site was created via Dataverse API (`New-Record -setName powerpagesites`) which creates a bare record missing Power Pages provisioning infrastructure.

**Solution:** Create the site through the Power Pages admin center (make.powerpages.microsoft.com) which handles full provisioning. Then deploy with `pac pages upload-code-site`.

**Current state:** Bare `powerpagesite` record exists (ID: `fcace412-2b29-f111-8341-000d3a37b112`, name: "Decades Onboarding Concierge"). Should be deleted before creating properly through admin center.

**Environment details:**
- DCGWorkRequests: https://dcgworkrequests.crm.dynamics.com/
- PAC auth profile: index [5]
- Existing sites (DO NOT TOUCH): DCGContracts (`4f70a5c3`), DCGPORTAL (`4d471c10`)

**Lesson learned:** CDN-load React/ReactDOM from unpkg to keep bundle under any file size limit. Current build: 31KB app bundle + React from CDN. Apply this pattern to dcfg-shell if it ever hits the same issue.

## Technical Details

### File Structure

```
C:\dcfg\spa\dcfg-property-intake\
├── index.html          — CDN React, Roboto fonts, Decades title
├── package.json        — React 17, Vite 5, react-router-dom 6.3
├── vite.config.js      — React externalized to CDN, IIFE output
├── public/
│   ├── logo.png        — Decades corporate logo (from website)
│   └── seeds/          — Per-customer seed JSON files
└── src/
    ├── main.jsx        — Entry point
    ├── App.jsx         — Login + master-detail layout + tabs
    ├── PropertyForm.jsx — 7 sections, all fields, conditional panels
    ├── VendorList.jsx  — Vendor card list
    ├── AuthorizedUsers.jsx — User list with location access assignment
    ├── storage.js      — localStorage CRUD + data model factories
    ├── tokens.js       — Decades corporate design tokens
    └── addressParser.js — Splits UpKeep address strings
```

### Design Tokens (Decades Corporate)

```javascript
blue:      '#085097'    // Primary — buttons, headers, sidebar
blueMid:   '#1890D7'    // Accent — links, active states, CTAs
bluePale:  '#E8F1FA'    // Light — open sections, detail panel bg
blueDeep:  '#002D56'    // Dark — sidebar bg, deep text
textLight: '#888A8E'    // Secondary text, labels
border:    '#D4D9E2'    // Field borders, dividers
bg:        '#F5F7FA'    // Page background
green:     '#2D8659'    // Success, Y toggles
red:       '#C0392B'    // Danger, N toggles, remove buttons
Fonts:     Roboto, Open Sans (body) | IBM Plex Mono (code/data)
```

### Data Model — Property (mirrors dcfg_property)

**Section 1: Location Identity** (7 fields)
streetAddress, city, state, zipCode, homeType (Apartment/Home), homeOwnership (Rent/Own), serviceLine

**Section 2: Site Contact** (4 fields)
contactPerson, contactPhone, contactEmail, entryTime

**Section 3: Home Details** (13 fields, sub-grouped)
- Structure: yearBuilt, capacity, bedrooms, stories, basement (N/A/Finished/Unfinished), attic (Y/N)
- Roof & Exterior: ageOfRoof, typeOfRoof, roofDocumentation (Y/N), gutterGuards (Y/N)
- Utilities & Access: heatingType (Oil/Propane/Natural Gas), floorPlansAvailable (Y/N), parking (Driveway/Parking Lot)

**Section 4: Features & Systems** (10 Y/N toggles, each with conditional detail)
- lockBox → lockBoxCode, lockBoxLocation
- pool → poolType (Above Ground/Inground), poolWaterType (Fresh/Salt), linerType, poolInstallDate, pumpModel, poolNotes
- generator → genFuelType (Oil/Propane/Natural Gas), genMake, genModel, genSerial, genServiceProvider
- garage → garageSize (1/2/3 Car), garageAttached (Y/N), garageFinished (Y/N)
- septicSystem → septicAtu (Y/N), septicCapacity, septicInstallDate, septicDrawings (Y/N)
- solarPanels → solarSize, solarInstaller, solarInstallDate, solarLeaseOwned (Lease/Owned), solarMonitoring, solarOutput, solarNotes
- fireSafetySprinkler (Y/N, standalone)
- detectorsHardwired (Y/N, standalone)
- waterTreatmentSystem (Y/N, standalone)
- wellWater (Y/N, standalone)

**Section 5: Trash & Utilities** (2 fields + conditional details)
- trashCollection (Township/Contract)
  - Township → trashCans, maxTrashCans, recyclingCans, maxRecyclingCans
  - Contract → trashVendor, trashHandlesRecycling (Y/N), trashContractStart, trashContractEnd, trashMonthlyCost
- waterSupply (Well/City)
  - Well → wellCertified (Y/N), wellDocumentation (Y/N)

**Section 6: Fire & Safety** (1 field + conditional detail)
- fireAlarmSystem (Localized/Monitored/Both)
  → fireAlarmSprinkler (Y/N), fireAlarmMonitoring (Y/N), fireExtinguishers, coDetectors, smokeDetectors, annualInspection, chimesInHome (Y/N)

**Section 7: Inspections** (2 fields)
lastIddInspection, lastDcaInspection

**UpKeep source fields** (populated by seed, not user-editable)
upkeepLocationId, upkeepParentId, upkeepName

### Data Model — Vendor (8 fields)
vendorName, serviceProvided, contactName, contactPhone, contactEmail, contractStart, contractEnd, requiresReBid (Y/N)

### Data Model — Authorized User (5 fields)
name, email, phone, accessLevel (all/specific), locationIds (array of property IDs)

### Seed File Format

```json
{
  "providerName": "JADD Professional Services",
  "code": "JADD2026",
  "properties": [
    {
      "id": "uuid",
      "upkeepLocationId": "abc123",
      "upkeepParentId": "parent456",
      "upkeepName": "Main Street Group Home",
      "streetAddress": "123 Main St",
      "city": "Denver",
      "state": "CO",
      "zipCode": "80202",
      "homeType": "",
      "...": "all other fields empty"
    }
  ],
  "vendors": [],
  "authorizedUsers": [],
  "expiresAt": "2026-04-25T...",
  "lastModified": "2026-03-26T...",
  "seededFrom": "UpKeep",
  "upkeepAccount": "multi"
}
```

### UpKeep Integration

- **Auth:** POST `https://api.onupkeep.com/api/v2/auth` with `{email, password}` → session token
- **Locations:** GET `https://api.onupkeep.com/api/v2/locations/{id}` with `Session-Token` header
- **Address format:** Single string `"123 Main St, Denver, CO 80202, USA"` — parsed by addressParser.js
- **Accounts:** Multi (service@decades-cg.com) and Bancroft (jcameron@decades-cg.com)
- **Email case sensitivity:** UpKeep API is case-sensitive on email. Use lowercase.
- **Location fields available:** id, name, address, parentLocation, hierarchyLevel
- **No customer filter:** Must fetch all locations and filter by specific IDs

### Login Flow (App.jsx)

```
Enter code → check localStorage (returning user)
  → found → load, show properties
  → not found → fetch seeds/{CODE}.json
    → found → load seed, save to localStorage, show properties
    → not found → check hardcoded ACCESS_CODES (demo)
      → found → empty provider
      → not found → "Invalid access code" error
```

## Testing Requirements

### Playwright E2E — Full Coverage

Every user interaction must be exercised across the test suite:

1. **Login flow** — valid code, invalid code, returning user with existing data, first-time user with seed
2. **Property navigation** — select property, add property, remove property, switch between properties
3. **Every field type:**
   - Free text: type, clear, special characters, long strings
   - Dropdowns: select each option, change selection, clear
   - Y/N toggles: click Y, click N, click same again, verify conditional panels show/hide
4. **All 11 conditional sections:** Trigger each, verify correct fields appear, verify they hide when trigger changes
5. **Vendor tab:** Add vendor, fill all 8 fields, remove vendor, multiple vendors
6. **Users tab:** Add user, fill fields, toggle All/Specific locations, check/uncheck location boxes, remove user
7. **Data persistence:** Fill fields → close browser → reopen → verify data survived
8. **Progress bar:** Verify it updates as fields are filled
9. **Tabs:** Switch between properties/vendors/users, verify correct content shows
10. **Expiry date:** Verify it displays correctly

**Randomization:** Input values should vary across test runs. Dates should accept free text (not enforce format). If a user doesn't fill a field, nothing breaks.

**NOT a single mega-test.** Distribute across scenario-based test files:
- `login.spec.ts`
- `property-form.spec.ts`
- `conditional-sections.spec.ts`
- `vendors.spec.ts`
- `authorized-users.spec.ts`
- `persistence.spec.ts`

## Automated Messaging (Draft)

### Welcome Email (when "Send to Customer" is clicked)

```
Subject: Get Started — Property Information for Decades

Hi [Contact Name],

We're excited to begin working with [Provider Name]. To help us
serve your locations effectively, we've set up a simple portal
where you can share property details at your own pace.

Your access code: [CODE]
Portal link: [URL]

What to expect:
• Your locations are already listed — we've filled in the addresses
• Fill in what you know, skip what you don't
• Your work saves automatically — come back anytime
• This link is active for 30 days

If you have questions, reply to this email or call [DCFG contact].

— The Decades Team
```

### Tone Guidelines
- "We" = Decades. Never "DCFG", never "the system", never technical language.
- "Your locations" not "properties" or "records"
- "Share" not "submit" or "enter data"
- "At your own pace" — repeated theme
- No urgency language. No deadlines in the message (the 30-day expiry is mentioned once, not stressed).

## Resume Checklist

When resuming this work:

1. **Delete bare site record** `fcace412-2b29-f111-8341-000d3a37b112` from DCGWorkRequests
2. **Create site via Power Pages admin center** (make.powerpages.microsoft.com) in DCGWorkRequests environment, name "Decades Onboarding Concierge"
3. **Deploy SPA** — `pac pages upload-code-site` from `C:\dcfg\spa\dcfg-property-intake\`
4. **Verify site loads** — login screen with Decades branding
5. **Create `dcfg_property_intake` staging table** — mirrors dcfg_property schema
6. **Wire SPA to Dataverse** — replace localStorage with Web API calls to staging table
7. **Set up table permissions + site settings** for the new site
8. **Build change notification** — DCFG staff alerted when customer updates data
9. **Build Playwright test suite** — per testing requirements above
10. **Build "Send to Customer" button** on customer detail page in dcfg-shell
11. **UX review** — have Evaluator walk through as a provider office worker

## Session Token Usage

| Activity | Approximate Tokens |
|---|---|
| Harness creation + postmortem | ~50K |
| Operations Dashboard troubleshooting | ~80K |
| Harness revision (Evaluator + Planner + Brainstorm) | ~120K |
| Property Intake Portal build | ~60K |
| Branding + deployment attempts | ~30K |
| **Total session** | **~340K** |

## Also Completed This Session

- Created `dcfg-work-organizer` skill (five-agent harness)
- Retired `hybrid-agent-supervisor` (pending delete)
- Postmortem: `C:\DCFG\docs\postmortem-harness-2026-03-26.md`
- Harness v2 rewrite with: risk-stratified gate, restatement protocol, three-way alignment, SOX principles, permanent skill assignments, diagnosis log, context tripwire
- `dcfg_work_item` table + sync script for Operations Dashboard
- `Operations.jsx` rewritten to read from Dataverse (deployed to test)
- UpKeep flow fixes (email case, parallel auth, schema validation, scope reduction)
- Multiple memory files: user_joseph.md, feedback_sox_principles.md, feedback_token_efficiency.md, feedback_identify_environment.md
