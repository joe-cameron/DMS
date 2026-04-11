# Session Handoff — 2026-04-04

## Completed This Session

### DocGen v3
- Built and pushed via PA Management API
- 11 Switch cases (Blanket WO + Exhibit B/C/D removed)
- Null guards: Condition_Has_Property, date field guards, MSA day/month/year
- Output URLs: full SharePoint paths
- **160+ successful document generations, 0 failures**

### Template Cleanup
- 198 content control tag renames (human-readable → snake_case)
- 12 templates renamed to clean names (Family_DocType.docx)
- Prod templates copied to Test (real documents with legal text)
- Unused templates prefixed with zz_

### SPA Changes (WITH PERMISSION)
- Nav restructured: Sales / Facilities / Projects / Management / Admin
- Admin section collapsed by default
- Map widget (Magnolia NJ) below logo, clickable
- User Manual moved above Sales
- Amendment added to Create section
- Send Queue → Clearance
- Work Orders removed from Facilities
- Field Ops + Concierge moved to Admin
- Facilities Dashboard + Projects Dashboard (placeholder screens)
- Vendor List screen (271 vendors, searchable by name/trade/address)
- Flow Monitor: type labels (Proposal/Vendor Agreement/Work Order/Amendment/Email)
- Flow Monitor: createdon ordering (fixes null dcfg_requested_at)
- MSA wizard skips Exhibit A step
- MsaList 400 fix (dcfg_contract_msa navigation property)
- Console spam silenced (getEnvVar)
- Nav scrollbar fix (navGroups scrolls, footer stays visible)

### Data Migration
- 7 customers from Prod
- 271 vendors from Prod (deduped from 500+)
- 1010 properties from Prod
- Coded test data created for validation

### Infrastructure
- dcfg_config table permission created (fixes 403)
- sensor_reading permission role link fixed
- DMSTest site provisioned (code-site not working — powerpagesitetype=2 insufficient)
- Site provisioning checklist saved to memory

## Blockers for Next Session

### Prod Upgrade
1. Build SPA for Prod
2. Deploy via pac pages to Prod site (dmms1.powerappsportals.com)
3. Verify/create all table permissions on Prod
4. Verify/create all Webapi site settings on Prod
5. DocGen v3 flow — create in Prod, push definition
6. E2E test 10x on Prod
7. Clean stale web-files from Prod .powerpages-site/ before deploying

### Outstanding Feature Requests
- Customer record: add dcfg_logo_url field
- Vendor screen: driving distance search + trade filtering
- Projects screens: Programs, Projects, RFPs (from 2026-04-04 spec)
- Individual dashboards per section (real KPIs, not placeholders)
- DMSTest2 code-site provisioning

### Known Issues
- Bancroft_WO template: 5 controls Word Online doesn't recognize (programmatic)
- PropA/PropC produce 4-byte empty files (3 templates)
- 19 requests throttled when submitting 80 at once (1s spacing fixes it)
