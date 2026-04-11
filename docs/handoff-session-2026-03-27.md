# DCFG Session Handoff — 2026-03-27

## What Was Accomplished

### Onboarding Concierge Portal (DCFGSystems-Portal)
- Power Pages site live at `decades-concierge.powerappsportals.com`
- 6 intake tables seeded (location types, field configs, DEMO1234 session, 3 demo properties)
- Table permissions fixed (entitylogicalname + Anonymous/Auth roles)
- Web API site settings populated for all intake tables
- SPA deployed with: null guard, `dcfg_is_active` filter fix, DocumentCapture → Dataverse wiring, WelcomeScreen, mobile layout

### DMS / SharePoint Architecture
- **Gold standard established:** DCFG_Templates (flat), DCFG_Outputs (Customer/Year/DocType), DCFG_Attachments (Customer/Location/Year)
- Config-driven library names via `dcfg_configs` — same code works in any environment
- Config keys set in both Test and Prod: `dcfg_sp_site_url`, `dcfg_sp_templates_library`, `dcfg_sp_outputs_library`, `dcfg_sp_attachments_library`
- Old SharePoint folder structure (category subfolders) flagged for deletion — you need to manually delete and create `_Test` libraries

### Flows
- **flow_cert_upload** — Built, tested, deployed to Test + Prod. Config-driven library. Cross-env wiring (Portal → Prod). Creates Customer/Location/Year folders, uploads with slugged filenames, supersedes old docs.
- **DCFG DocGen v2** — Updated in Test + Prod. Config-driven library. Creates Customer/FiscalYear/DocType folders. Word Online actions preserved in Prod.
- **DCFG Error Reporter** — Completed. Writes to dcfg_audit_log + sends email to jcameron@decades-cg.com.
- **UpKeepWebhookReceiver** — Rebuilt with proper Dataverse connector (not raw HTTP). Deployed to Prod. Location names resolved via dcfg_properties lookup. Webhook URL configured in UpKeep for both Multi and Bancroft accounts.
- **GetUnifiedWorkQueue** — Operations flow URL set in Prod config. SPA resolves location names client-side.

### SPA (dcfg-shell)
- Encoding artifacts fixed (`â€"` → `—`, `â€¦` → `…`) in Locations.jsx, CustomerDetail.jsx, usePortalUser.jsx
- Operations.jsx — client-side location name resolution for work items
- Hardcoded fallback flow URLs + SP site URL removed from portalApi.js — now fails explicitly if config missing
- NewContractWizard — removed hardcoded "DCFG_Outputs" text
- Deployed to Test + Prod

### Data Cleanup
- **Prod:** 82 duplicate properties soft-deleted, 3 duplicate location types deleted, 2 renamed (GroupHome→Group Home, DayProgram→Day Program). Now 961 active properties, 5 clean location types.
- **Test:** 69 properties re-pointed, 3 duplicate location types merged/deleted. 5 clean location types matching Prod.
- **Prod:** 453 work items synced from UpKeep to dcfg_work_items table.

### Tables Created in Prod
- `dcfg_work_item` — 12 columns + Web API settings + table permission
- `dcfg_intake_session` — 6 columns + lookup relationships
- `dcfg_property_intake` — 97 columns + 2 lookups (session, location_type)
- `dcfg_intake_field_config` — 3 columns + 1 lookup (location_type)
- `dcfg_intake_vendor` — 9 columns + 1 lookup (session)
- `dcfg_intake_authorized_user` — 6 columns + 1 lookup (session)
- All with table permissions (Authenticated Users) and Web API settings

## Still Pending

### Manual Steps (You)
1. **SharePoint cleanup** — Delete old folder structure in DCFG_Attachments, delete DMS_Templates/DMS_Outputs/DMS_Uploads libraries, clean DCFG_Templates /holding/ folder
2. **Create test libraries** — DCFG_Templates_Test, DCFG_Outputs_Test, DCFG_Attachments_Test on same SP site
3. **Verify flow_cert_upload connections** in Prod designer — Configure Run After on 3 folder actions (Succeeded+Failed)
4. **Verify UpKeepWebhookReceiver** — Check that webhook URL in UpKeep matches the Prod flow URL you provided
5. **Clear cache** on both portals after SP library cleanup

### Development Work Remaining
1. **DocGen SharePoint — Word Online placeholder** — `Decades_Exhibit_A_Concierge_B` case has placeholder, needs Word Online action
2. **3 missing Bancroft Exhibit templates** — Bancroft_Exhibit_A_Basic_A, Bancroft_Exhibit_A_Concierge_B, Bancroft_Exhibit_A_Optimized_C not in Switch_Template
3. **flow_template_validate** — All placeholder actions, never completed. Not blocking.
4. **QA Promotion Pipeline** (Sub-project #3) — Staff review UI, intake → production merge via UpKeep location ID
5. **Operations screen work orders** — May still show empty if dcfg_configs permission not allowing read on Prod portal
6. **Error handling on flows** — Add failure branches to DocGen and CertUpload

### Environment Map
| Environment | Org URL | Portal URL | Purpose |
|---|---|---|---|
| Test | org0c17e98d.crm.dynamics.com | dcfg.powerappsportals.com | Development |
| Prod | org06f5de0b.crm.dynamics.com | dmms1.powerappsportals.com | Production DMS |
| Portal | orgf625b080.crm.dynamics.com | decades-concierge.powerappsportals.com | Customer-facing intake |
| Stage | org88778bb0.crm.dynamics.com | holding.powerappsportals.com | Staging |

### pac auth profiles
| Index | Environment |
|---|---|
| 1 | Test (default) |
| 2 | Stage |
| 3 | Prod |
| 4 | Demo |
| 5 | DCGWorkRequests |
| 6 | Portal |
