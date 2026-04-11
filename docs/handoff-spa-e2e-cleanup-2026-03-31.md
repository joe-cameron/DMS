# Handoff: DCFG SPA Session — 2026-03-31

## What was done

### 1. Playwright test rewrite
`C:\DCFG\spa\dcfg-playwright\tests\full-e2e-review.spec.ts`
- Complete rewrite — all 205+ data-testid selectors, zero fragile selectors
- 5 test cases covering every screen, tab, button, field, and action link
- Matches current nav structure (SALES / OPERATIONS / MANAGEMENT / ADMIN)
- TypeScript compiles clean

### 2. Nav restructured
`C:\DCFG\spa\dcfg-shell\src\NavPanel.jsx`
```
SALES:       Dashboard, Customers, MSAs (no vendor column)
OPERATIONS:  Contracts, Work Orders, Onboarding, Locations, Field Ops, Concierge (external link)
MANAGEMENT:  Send Queue
ADMIN:       System Admin
```
- New Proposal / New Contract removed from nav (triggered from within screens)
- Concierge is external link to decadeswelcomesyou.powerappsportals.com
- NavItem supports `external` prop for new-tab links

### 3. Column cleanup
- `C:\DCFG\spa\dcfg-shell\src\screens\ContractList.jsx` — 8 to 5 columns (Contract #, Customer, Status, Fee, Date)
- `C:\DCFG\spa\dcfg-shell\src\screens\MsaList.jsx` — 5 to 3 columns (MSA Name + family badge, Customer, Budget — no vendor)

### 4. Browser modals eliminated (8 files, 0 remain)
- `C:\DCFG\spa\dcfg-shell\src\screens\CustomerDetail.jsx` — alert to toast
- `C:\DCFG\spa\dcfg-shell\src\screens\MsaDetail.jsx` — alert to toast
- `C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx` — alert/confirm to toast + inline confirm
- `C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx` — confirm to inline Confirm/Cancel
- `C:\DCFG\spa\dcfg-shell\src\NewProposalWizard.jsx` — confirm to inline Confirm/Cancel
- `C:\DCFG\spa\dcfg-shell\src\LocationManager.jsx` — confirm to inline Confirm/Cancel

### 5. Camera/upload wired
`C:\DCFG\spa\dcfg-shell\src\LocationManager.jsx`
- Camera button: triggers device camera via capture="environment", creates DocRequestType.CertUpload document request
- Upload button: file picker for PDF/images, same flow trigger
- Both disabled during upload, toast on success/failure

### 6. Stale stub comments removed
- `C:\DCFG\spa\dcfg-shell\src\screens\ContractList.jsx`
- `C:\DCFG\spa\dcfg-shell\src\screens\MsaList.jsx`

### 7. Drift fixes applied to Test environment
- dcfg_contract_attachment — site settings created
- dcfg_blanket_workorder — already had permission + settings
- dcfg_customer_ap_mapping — already had permission + settings
- Script: `C:\DCFG\Fix-DriftIssues-2026-03-31.ps1`

### 8. Master schema reference
`C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\schema.json`
- 35 tables with permission IDs, CRUD flags, site settings, roles

### 9. CLAUDE.md updated
`C:\dcfg\CLAUDE.md`
- curl.exe blocked by endpoint security, use Invoke-RestMethod

### 10. SalesDashboard heading
`C:\DCFG\spa\dcfg-shell\src\screens\SalesDashboard.jsx`
- "Sales Dashboard" renamed to "Sales"

## Deployed
- SPA deployed to Test (dcfg.powerappsportals.com) — all changes live
- PAC auth on index [1] (Test)

## To run the E2E test
```bash
# Clear cache first
# https://dcfg.powerappsportals.com/_services/about?clearCache=true

cd C:\DCFG\spa\dcfg-playwright
npx playwright test full-e2e-review --project=smoke --headed
# Windows Hello login required at pause
# Screenshots output to: C:\DCFG\spa\dcfg-playwright\screenshots\e2e-review\
```

## Not done — carry forward
- **Concierge login**: demo1234 access code does nothing — investigate `C:\dcfg\spa\dcfg-property-intake\` auth flow
- **Operations Dashboard**: pending UpKeep credentials + flow URL wiring (see `C:\Users\JosephCameron\.claude\projects\C--dcfg\memory\project_operations_dashboard.md`)
- **Onboarding Concierge**: USE_DATAVERSE = false — table creation script not run yet (see `C:\Users\JosephCameron\.claude\projects\C--dcfg\memory\project_onboarding_concierge.md`)
- **flow_cert_upload**: camera/upload buttons now create document requests but the flow needs connections wired in Power Automate designer
- **Stage/Prod deploy**: only Test was deployed this session

## All files changed this session
```
C:\DCFG\spa\dcfg-shell\src\NavPanel.jsx
C:\DCFG\spa\dcfg-shell\src\screens\SalesDashboard.jsx
C:\DCFG\spa\dcfg-shell\src\screens\ContractList.jsx
C:\DCFG\spa\dcfg-shell\src\screens\MsaList.jsx
C:\DCFG\spa\dcfg-shell\src\screens\CustomerDetail.jsx
C:\DCFG\spa\dcfg-shell\src\screens\MsaDetail.jsx
C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx
C:\DCFG\spa\dcfg-shell\src\NewContractWizard.jsx
C:\DCFG\spa\dcfg-shell\src\NewProposalWizard.jsx
C:\DCFG\spa\dcfg-shell\src\LocationManager.jsx
C:\DCFG\spa\dcfg-playwright\tests\full-e2e-review.spec.ts
C:\dcfg\CLAUDE.md
C:\Users\JosephCameron\.claude\skills\dcfg-project-data\data\schema.json
C:\DCFG\Fix-DriftIssues-2026-03-31.ps1
```
