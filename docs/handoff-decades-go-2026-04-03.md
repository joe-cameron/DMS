# Handoff: Decades GO (BidComp) — 2026-04-03

## Status: SPA Running, API 403 Pending Resolution

The React SPA is deployed and rendering on a native Power Pages code site. Web API calls return 403. All permissions are configured. Likely cache propagation on a brand new site.

---

## What Was Built

### Design & Spec
- **Spec:** `C:\DCFG\docs\superpowers\specs\2026-04-02-bidcomp-module-design.md`
- **Plan:** `C:\DCFG\docs\superpowers\plans\2026-04-02-bidcomp-phase1-mvp.md`
- **Visual mockups:** `C:\DCFG\.superpowers\brainstorm\777-1775177372\`

### React App
- **Location:** `C:\DCFG\spa\dcfg-bidcomp\`
- **Stack:** React 16.14.0 + Vite 5.2.0 + SheetJS
- **Tests:** 12/12 passing (`npx vitest run tests/`)
- **Build:** `npx vite build` → `dist/` (467KB bundle)
- **Screens:** Dashboard, Tracker, Invoices, BuySheet, MonthlyReport
- **Shared utils:** portalApi.js, usePortalUser, useTableControls, Toast, FieldName (copied from dcfg-shell)

### Dataverse Tables (on Prod: org06f5de0b)
- `dcfg_prime_contract` → entity set: `dcfg_prime_contracts`
- `dcfg_phase` → entity set: `dcfg_phases` (pre-existing from solution, columns added)
- `dcfg_invoice` → entity set: `dcfg_invoices`

### Data Loaded (Prod)
- 1 prime contract (Bancroft 25010 FY26, $5.99M)
- 76 phases
- 24 invoices

### Phase Status Picklist Values (IMPORTANT — different from plan)
```
100000020 = Not Started
100000021 = In Progress
100000022 = Completed
100000024 = Out to Bid
100000025 = Ready to Start
100000026 = Canceled
```
These are reflected in `src/constants.js`.

---

## Deployment

### Site: Decades GO
- **URL:** https://site-nnbam.powerappsportals.com
- **Site ID:** `9de8c23e-4cb1-4fc8-b4a9-8b655a546bb7`
- **Environment:** DCFGSystems-Prod (`org06f5de0b.crm.dynamics.com`)
- **Data Model:** Enhanced
- **Created by:** `pac pages upload-code-site` (native code site)
- **Application ID:** `b30c2608-65a6-4ab7-b879-e5b42cb4bbe6`

### How It Was Deployed
```bash
cd C:\DCFG\spa\dcfg-bidcomp
npm run build
pac auth select --index 3  # Prod
pac pages upload-code-site --rootPath . --compiledPath dist --siteName "Decades GO"
# Then activated from make.powerpages.microsoft.com → Inactive sites → Reactivate
pac auth select --index 1  # Restore to Test
```

### Key Lesson: Code Sites
`pac pages upload-code-site` CREATES a new site when run fresh (no existing .powerpages-site folder). The site appears in Inactive sites. Activate it. This is the correct way to deploy SPAs to Enhanced Data Model — NOT by deploying to an existing portal site.

### powerpages.config.json
```json
{
    "siteName": "Decades GO",
    "compiledPath": "C:\\DCFG\\spa\\dcfg-bidcomp\\dist",
    "defaultLandingPage": "index.html"
}
```

---

## Current Issue: 403 on Web API

### Symptoms
- SPA loads, nav renders, screens show "Loading..."
- `/_api/dcfg_prime_contracts?$filter=...` returns 403
- User is authenticated (Entra ID, incognito tested)

### What's Configured (verified)
- **Web roles:** Authenticated Users (mspp_authenticatedusersrole = true) on site `9de8c23e`
- **Table permissions:** All 6 tables (prime_contract, phase, invoice, vendor, customer, property) with full CRUD, linked to Authenticated Users role
- **Intersection records:** 6 records in `mspp_entitypermission_webroleset` linking permissions to role
- **powerpagecomponent content JSON:** All 6 type-18 components have `adx_entitypermission_webrole` array with role GUID
- **Site settings:** `Webapi/{table}/enabled = true` and `Webapi/{table}/fields = *` for all 6 tables
- **JS uploads:** Not blocked in environment settings

### Likely Cause
Cache propagation on a brand new code site. The DCFG Contracting Suite site works with the same tables/environment — the only difference is age. Try again after several hours.

### If Still 403 Tomorrow
1. Compare the DCFG Contracting Suite's permission setup detail-by-detail against Decades GO
2. Check if the Authenticated Users role on Decades GO has the same internal structure as on the working DCFG site
3. Try creating a test record via Dataverse API (not portal) and querying via `/_api/` to isolate whether it's a permission issue or a data issue
4. Check `/_services/about` on the site for diagnostic info

---

## Other Sites Created During This Session (cleanup needed)

Multiple orphan/test sites were created on Prod. Clean up when ready:

| Site | ID | Status |
|------|-----|--------|
| Builder - dmsbuilder | f09df2c1-e3b3-456f-88ee-6059c2445ecd | Enhanced, not working — delete |
| Builder - dmsbuilder | 04603ba0-aaec-44ef-8255-a49f50daa5ac | Orphan — already deleted |
| Builder - dmsbuilder | d64352f4-d6aa-4db6-9abb-93e4669e5c6c | Orphan — delete |
| DMSBuilder - dmsbuilder | 18e7c722-1170-47b9-ac42-c5068f5cdabe | Another orphan — delete |
| BYOC Blank Site | d24e550a-10d2-4a24-b0c9-0340443425d6 | Unknown — investigate |
| **Decades GO** | **9de8c23e-4cb1-4fc8-b4a9-8b655a546bb7** | **KEEP — this is the real site** |

---

## Scripts Created

| Script | Purpose |
|--------|---------|
| `scripts/bidcomp/create-prime-contract.ps1` | Create dcfg_prime_contract on Test |
| `scripts/bidcomp/create-phase.ps1` | Create dcfg_phase on Test |
| `scripts/bidcomp/create-invoice.ps1` | Create dcfg_invoice on Test |
| `scripts/bidcomp/verify-tables.ps1` | Verify tables exist |
| `scripts/bidcomp/create-prod-tables.ps1` | Create prime_contract + invoice on Prod |
| `scripts/bidcomp/add-phase-columns-prod.ps1` | Add BidComp columns to dcfg_phase on Prod |
| `scripts/bidcomp/import-bancroft-fy26-v2.ps1` | Import data to Test |
| `scripts/bidcomp/import-bancroft-fy26-prod.ps1` | Import data to Prod |
| `scripts/bidcomp/setup-prod-permissions.ps1` | Permissions for DMSBuilder (deprecated) |
| `scripts/bidcomp/fix-home-page.ps1` | Fix Home page copy (DMSBuilder, deprecated) |
| `scripts/bidcomp/drop-prod-tables.ps1` | Drop tables (partially worked) |

---

## Research Data

| Path | Contents |
|------|----------|
| `C:\DCFG\research\tyler-drive\` | Tyler Drive project: budget SOV, exhibit B samples, proposals |
| `C:\DCFG\research\bancroft-ghsp-fy26\` | Bancroft FY26: Sage Budget, Tracker, Master Exhibit B, Cost Center GL, etc. |

---

## Memory Files Updated
- `project_bidcomp_module.md` — BidComp module overview
- `project_decades_go_architecture.md` — Decades GO = external name, 3-layer architecture
- `feedback_enhanced_data_model_webfiles.md` — Lessons on Enhanced model web file deployment
- `MEMORY.md` — Index updated

---

## Next Steps

1. **Resolve 403** — check if cache propagation fixes it overnight
2. **Configure Entra ID auth** — ensure redirect URI for site-nnbam.powerappsportals.com is in the Entra app registration
3. **Clean up orphan sites** on Prod
4. **Wire Excel export/import** buttons to excelEngine.js (TODOs in Tracker/Invoices/BuySheet screens)
5. **Phase 2:** Exhibit A, Exhibit B, Change Orders
6. **Bancroft compliance:** 7-point checklist integration (see project_bancroft_compliance.md)
