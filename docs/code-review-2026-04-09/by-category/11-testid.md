# Category 11 — data-testid Golden Rule Audit

**Phase:** 2c
**Agent:** phase-2c-testid
**Date:** 2026-04-12
**Finding IDs:** CR-2026-04-09-0500 through 0534

---

## Executive Summary

Audited all in-scope SPA files under `C:\DCFG\spa\dcfg-shell\src\` for interactive elements missing `data-testid` attributes. The codebase has **strong testid coverage overall** -- the majority of high-traffic screens (SalesDashboard, ContractDetail, CustomerDetail, Locations list, SendQueue, Onboarding list, MsaDetail) already have systematic testid attributes on their interactive elements.

**35 findings** cataloged, representing approximately **85+ individual interactive elements** that need testids added. All are P3 severity, auto-fix tier.

---

## Coverage Assessment

### Well-Covered Screens (no findings)
- **SalesDashboard** -- all KPI tiles, pipeline segments, onboarding/prospect rows, activity toggle, activity links
- **ContractDetail** -- all status-action buttons, generate, void, decline, amendment, modal inputs/buttons
- **CustomerDetail** -- tabs, edit form inputs, MSA/contract/onboarding/program sub-tabs all covered
- **Locations list** -- search, filter, new button, table rows, new location panel inputs
- **SendQueue** -- KPI cards, queue tabs, approve/return/delete/open buttons, email modal, confirm modal, search FAB
- **Onboarding list** -- search, status filter, toggle deleted, new case button, table rows, delete/restore buttons
- **LocationDetail** -- all tabs, property info save, document upload, appliance CRUD buttons
- **ProjectDetail** -- edit, save, cancel, line items CRUD, all form inputs
- **RfpDetail** -- tabs, edit/save/cancel, status transition buttons

### Systematic Gap Patterns Found

1. **Panel/modal close (X) buttons** -- 10 occurrences across Admin forms, CustomerList, Locations, Onboarding, LocationDetail, ProjectList. These all use the same `btnClose` pattern without testid.

2. **Admin form inputs** -- StepForm, LocationTypeForm, CostCodeForm, ApplianceTypeForm all have Save/Cancel buttons with testids but their input fields (text, select, checkbox, textarea) do not. This is the largest gap by element count (~30 individual form fields).

3. **Admin CustomerConfig sub-sections** -- BlanketWorkorder and AP Mapping sections have buttons and inputs without testids (9 buttons + 3 inputs in BlanketWO, 3 elements in AP Mapping, 3 in TemplateAssignment).

4. **Composer screens** -- ContractComposer and MsaComposer are complex single-page composers with many interactive elements lacking testids. ContractComposer has ~15 missing, MsaComposer has ~6 missing.

5. **Clickable table rows** -- MsaDetail contracts tab and CustomerDetail LocationsMapTab have navigable rows without testid.

---

## Findings by Component Type

| Component Type | Count | Example |
|---|---|---|
| button (close/X) | 10 | Admin panel close, CustomerList panel close |
| button (action) | 21 | Admin blanket edit, SendQueue strip toggle, VendorsTab add |
| input (text/number) | 15 | Admin form fields, BlanketWO threshold/jobNumber |
| select | 14 | Admin form dropdowns, MsaDetail pricing, ProjectList form |
| textarea | 5 | Admin step notes, MsaDetail notes, ProjectList description |
| checkbox | 4 | Admin active flags, FlowMonitor auto-refresh |
| clickable div/tr | 3 | MsaDetail contract rows, CustomerDetail location rows/card |

**Total individual elements needing testid:** ~72

---

## Findings by File

| File | Findings | Elements |
|---|---|---|
| Admin.jsx | 0500-0514 (15) | ~45 elements |
| MsaDetail.jsx | 0515, 0533 | 4 elements |
| OnboardingDetail.jsx | 0516-0517, 0529 | 7 elements |
| SendQueue.jsx | 0518-0519 | 2 elements |
| FlowMonitor.jsx | 0520 | 2 elements |
| CustomerList.jsx | 0521 | 1 element |
| Locations.jsx | 0522 | 1 element |
| Onboarding.jsx | 0523 | 1 element |
| LocationDetail.jsx | 0524 | 1 element |
| ProjectList.jsx | 0525-0527 | 8 elements |
| VendorsTab.jsx | 0528 | 2 elements |
| ContractComposer.jsx | 0530 | ~15 elements |
| MsaComposer.jsx | 0531 | 6 elements |
| CustomerDetail.jsx | 0532, 0534 | 2 elements |

---

## Naming Convention Applied

All proposed testids follow kebab-case with screen/component prefix:
- `admin-{subtab}-{element}` for Admin sub-tab forms
- `admin-blanket-{element}` for BlanketWorkorder section
- `admin-apmapping-{element}` for AP Mapping section
- `msa-{element}` for MsaDetail
- `onbd-{element}` for OnboardingDetail
- `sq-{element}` for SendQueue
- `flow-{element}` for FlowMonitor
- `cc-{element}` for ContractComposer
- `msa-btn-{element}` for MsaComposer
- `{screen}-btn-close-panel` for all close buttons

For elements in loops/maps, pattern uses `${id}` or `${index}` suffix.

---

## Recommendation

All 35 findings are auto-fix tier. They can be applied in a single batch since they are additive (adding attributes, no behavioral change). A build verification (`npm run build`) is sufficient -- no runtime testing needed since `data-testid` attributes are inert to application behavior.

---

## Out of Scope (Excluded)

Per spec: `_archive/`, `debug/`, `interview/`, `test/`, `NoraCopilot.jsx`, `AbsorptionDashboard.jsx`, `UserManual.jsx`, `CapitalPlan.jsx`. The `interview/` directory has several buttons without testids (QuestionRenderer.jsx) but is explicitly excluded.
