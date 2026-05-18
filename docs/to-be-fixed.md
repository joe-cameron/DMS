# To Be Fixed

Running list of open issues. Updated as discovered. Completed items removed.
Last cleaned: 2026-05-12.

## DocuSign E2E Test
1. **Location names should use real properties** — not "E2E-DOCUSIGN-LOC". Test should select from existing locations, not create fake ones.

## SPA Features
10. **SALES → Resource Library** — New nav item under SALES. Card grid of leave-behinds and sales tools.
11. **Admin controls menu visibility** — Admin screen toggles which nav items are visible per role. Needs menu config table or `dcfg_configs` entries.

## Scheduler
15. **Embedded map not showing** — OSM iframe blocked by CSP. Fix: use Google Maps Embed API (key exists in `Scheduler/GoogleMapsApiKey`).

## Sales Dashboard
19. **Projects not showing trades** — Project list/detail doesn't display trades.
20. **Project screen not showing location** — Location not populating on project screen.

## Data Cleanup
24. **Purge audit logs** — `dcfg_audit_logs` from test activity.

## Trades Reference Data
38. **Admin management card for trades** — `dcfg_trade_type` table built, SPA wired (2026-05-11). Still needed: Admin screen card to add/edit/deactivate trades.

## Data Gaps (found 2026-05-15 Prod E2E)
39. **Contracts list empty** — Smart List shows no rows. May be a query/filter issue or data timing.
40. **Locations TYPE column all dashes** — `dcfg_location_type` not set on any Bancroft location. Needs bulk assignment or default.
41. **PCDI missing primary contact** — Customer record shows "-" for primary contact.

