# To Be Fixed

Running list of issues found during testing. Updated as discovered.

## DocuSign E2E Test
1. **Location names should use real Bancroft properties** — not "E2E-DOCUSIGN-LOC". Bancroft has 742 locations in Prod. Test should select from existing locations, not create fake ones.
2. **OOXML anchor injection has no console logging** — `injectScalarFields()` doesn't log docusign-type field replacements. Can't verify anchors were placed without downloading the document. Consider adding `console.log` for docusign type injections.
3. **Direct SharePoint upload always fails — CORS blocks `_api/contextinfo`** — `sharePointUpload.js` calls SharePoint REST API directly from the portal domain (`dmms1.powerappsportals.com`). SharePoint CORS rejects cross-origin credentialed requests. The direct path NEVER works — every upload falls through to the 30-45s flow fallback. Word Online link opens prematurely because the fallback hasn't finished yet. **Root fix:** Proxy the upload through the Azure Function (`html-to-pdf`). Server-side, no CORS. Add a `/upload` endpoint that accepts blob + path, uses Graph token, uploads to SharePoint, returns URL. Eliminates both the CORS error and the race condition.

## Pipeline Hygiene
8. **Field value appends across runs instead of resetting** — A field from a previous composition run was not cleared when starting a new one. On the second run, the old value was appended to the new value and presented as concatenated data. Root cause: React component state not resetting on re-navigation to `/#/msa/new`. Fix: ensure all composer state resets on mount (check `useEffect` cleanup or key-based remount).
9. **Stale data in Send Queue from failed/previous runs** — Old document requests from prior tests or failed generations persist in the pipeline and show up as pending items. Need: (a) cleanup mechanism for stale queue rows (age > N days with no action), (b) E2E test should tag its queue rows with a marker so it can identify its own rows vs stale ones, (c) consider a "Purge test data" admin action or auto-expire on abandoned Pending rows.

## SPA Features
10. **SALES → Resource Library** — New nav item under SALES section. Page with card grid of leave-behinds and sales tools. Grows over time.
11. **Admin controls menu visibility** — Admin screen toggles which nav items are visible (per role or globally). Resource Library and any future menu items are enabled/disabled through Admin, not hardcoded. Needs a menu configuration table or dcfg_configs entries that NavPanel reads at boot.

## Trade Cost Analysis (Admin)
13. **Exclude LumpSum line items from analysis** — The Trade Cost Analysis tab under System Admin includes LumpSum (UOM 100000004) entries, which have no quantity or unit rate detail. These pollute the rate averages and provide no comparative value. Fix: filter out `dcfg_uom === 100000004` from the analysis entirely (not just the "With Real UoM" counter). Only show line items with real quantity + UOM.
14. **Group by description + UOM, not just trade + UOM** — Current grouping is trade → UOM (e.g., "Plumbing → SqFt"). The useful grouping is trade → description + UOM (e.g., "Plumbing → Install 3/4 copper supply line → LinearFt"). The line item description is what makes the data comparable across vendors/projects. Without it, you're averaging apples and oranges within the same UOM.

## Vendor Assignment
12. **Customer Detail → Vendor slideout needs distance search** — The slideout panel ("Assign a Vendor to Customer") only has name/trade text search. Missing: customer location dropdown, trade filter, radius selector, Search button — the same distance search controls that exist on the main Vendors page. When assigning a vendor to a customer, the user should be able to find vendors near a specific customer location.

## Scheduler (dcfgscheduler.powerappsportals.com)
15. **Embedded map not showing in detail panel** — The "View Route" tab in the right-side detail panel renders nothing. Root cause: the embed uses an OpenStreetMap iframe (`openstreetmap.org/export/embed.html`) which is likely blocked by Power Pages Content Security Policy. Google Maps API key already exists in site setting `Scheduler/GoogleMapsApiKey`. Fix: replace the OSM iframe with a Google Maps Embed API URL (`google.com/maps/embed/v1/directions?key=...`). Source: `C:\dcfg\dcfg-resources\spa\src\App.jsx` lines 1937–1951.

## Sales Dashboard
16. **Remove all Client Service Agreement (MSA) transactions** — The `/#/msas` list is full of duplicate WIP test records (all Bancroft, Essential, 0 locations, NJ, WIP). These are leftover from MSA composer test runs. All `dcfg_msas` records need to be purged (soft delete via `dcfg_active_flag`). Full name is "Master Services Agreement - Client" but nav buttons stay as-is (too long for buttons).
19. **Projects not showing trades** — Project list/detail doesn't display trades. Many projects have multiple trades — should show "Multiple" or list them. Source: `dcfg_project` likely has child trade records or a multi-select field that isn't being read.
20. **Project screen not showing location** — Location is not populating on the project screen even though most projects are single-location. The location lookup or display is broken/missing.
28. **Onboarding list needs delete button** — The `/#/onboarding` grid has no delete button. Users need to be able to delete onboarding cases (soft delete via `dcfg_active_flag`).
27. **Client Service Agreements list needs delete button** — The `/#/msas` grid has no delete button. Users need to be able to delete MSAs (soft delete via `dcfg_active_flag`).
26. **Contracts list needs delete button** — The `/#/contracts` grid has no delete button. Users need to be able to delete contracts (soft delete via `dcfg_active_flag`). Guard: submitted contracts cannot be deleted unless their Send Queue status is Returned. Check `dcfg_send_queues` for the contract — if status is not Returned (100000005), block delete with a message.
25. **Bid Comparison grid needs delete button** — The `/#/rfps` screen lists active bid comparisons but has no delete button. Users need to be able to delete a bid comparison from the grid (soft delete via `dcfg_active_flag`).
24. **Purge audit logs** — All `dcfg_audit_logs` are from test activity. Purge (soft delete via `dcfg_active_flag`).
23. **Purge document requests** — All `dcfg_document_requests` are test data. Purge (soft delete via `dcfg_active_flag`).
22. **Purge onboarding cases** — All `dcfg_onboarding_cases` are test data. Purge (soft delete via `dcfg_active_flag`).
21. **Purge Send Queue test data** — `dcfg_send_queues` has old test records from prior runs. Purge all (soft delete via `dcfg_active_flag`).
18. **Remove all contract transactions** — All `dcfg_contracts` records are test data and need to be purged (soft delete via `dcfg_active_flag`).
17. **Active Prospects card shows existing customers as prospects** — The query pulls any MSA in WIP/Draft status, but a customer with existing signed/active MSAs is not a prospect — they're an existing client with a new proposal. Fix: filter out MSAs where the customer already has an Active/Signed MSA. Source: `SalesDashboard.jsx:74`.

## DocGen OOXML Injection Gaps (E2E run 2026-05-07)
29. **Dec-Amendment has 9 uninjected fields** — Customer Name, Location Name, Hour of Operations, PO Number, Owner Primary Contract Contact, Customer Contract Contact Info, and date fields all show as yellow-highlighted placeholders. The Decades Amendment template has the most gaps.
30. **Bancroft WO templates (ExhA-Auto, ExhA-Var, BlanketWO) each have 4-5 yellow highlights** — "Owner Primary Contract Contact" info, "Today's Date", and empty placeholder runs near contractor details. Core data (WO#, amounts, vendor, location) populates correctly.
31. **Bancroft & Decades VA templates have 2-4 yellow highlights** — Contractor address area, "Owner Primary Contract Contact" section. Signer names and vendor name inject correctly.
32. **Ban-Amendment has 5 yellow highlights** — Same pattern as WO types: contact info fields not injecting.
33. **MSA proposals (PkgB, PkgC) have 3 yellow highlights each** — "CustomerContact" (Attn: line), and 1-2 placeholder fields. Core proposal data populates correctly.
34. **Dec-WO is the only clean template** — 0 yellow highlights, all fields populated. This is the reference for what "fully working" looks like.

## SharePoint Document Storage
35. **MSA proposals should use a single folder per customer** — Currently each MSA package type (Essential, Extended, Premium) gets its own subfolder under `DCFG_Outputs/{Customer}/{Year}/`. All MSA versions for one customer should go into a single `MSA-{Customer}` folder instead. Multiple proposal versions are expected for the same customer.

## Contracts Grid
36. **"Open Document" button href is `#`** — The "Open Document" button on contract detail sidebar has `href="#"` instead of the SharePoint document URL. Needs to be set to the actual `dcfg_document_url` value.
37. **Doc history "Open" link uses `ms-word:` protocol** — Opens desktop Word instead of Word Online. Should use the SharePoint URL with `?web=1` for browser-based read-only viewing.

## Trades Reference Data
38. **Move trades from hardcoded arrays to Dataverse table** — Trades are hardcoded in 4 separate SPA arrays (`TRADES` in Directory/VendorList/VendorsTab, `KNOWN_TRADES` in NewProjectScreen/ProjectDetail, `TRADE_CATEGORIES` in ContractComposer, `TRADE_OPTIONS` in Admin). Should be a `dcfg_trade_type` reference table (like `dcfg_location_type` pattern) with `dcfg_name`, `dcfg_sort_order`, `dcfg_active_flag`. SPA fetches at boot, Admin screen gets a management card. Authoritative list (40 trades): Housekeeping, Snow Removal, Landscaping, Repair & Maintenance, Purchased Services, Trash and Waste Pickup, Pest Services, Alarm and Security Services, Dumpsters, Septic Systems, Window Cleaning, General Cleanout Services, Abatement Services, Concrete, Masonry, Painting, Elevators, Fire Protection, Plumbing, Water Filtration, Water Wells, Water Testing, HVAC, Electrical, Fire Alarm, Security Card Access, Fences & Gates, Irrigation, Tree Maintenance / Removal, Permits, Gutter Cleaning, Powerwashing, Countertops, Insulation, Roofing, Siding, Window Materials, Window Installation, Flooring & Carpet, Maintenance Supplies.

## Rebuild (Test + Stage)
4. **Phase 3: 2 column creates failed** — check `docs/baseline-2026-04-18/phase3-schema-results.json` for details
5. **Phase 3: 7 lookup columns skipped** — need relationship creation first, then column create
6. **Connection references require manual designer wiring** — DE-019, no API path. Human must open each flow in Power Automate designer.
7. **Table ownership mismatch on dcfg_prime_contract** — DE-018, blocks solution import. Operator decision needed.
