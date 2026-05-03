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

## Rebuild (Test + Stage)
4. **Phase 3: 2 column creates failed** — check `docs/baseline-2026-04-18/phase3-schema-results.json` for details
5. **Phase 3: 7 lookup columns skipped** — need relationship creation first, then column create
6. **Connection references require manual designer wiring** — DE-019, no API path. Human must open each flow in Power Automate designer.
7. **Table ownership mismatch on dcfg_prime_contract** — DE-018, blocks solution import. Operator decision needed.
