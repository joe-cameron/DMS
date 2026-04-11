# DCFG SPA Full Test Battery — Design Spec

**Date:** 2026-03-27
**Target environment:** DCFGSystems-Prod — dmms1.powerappsportals.com
**Write access:** Authorized by operator (create-and-soft-delete pattern)
**Layers:** Vitest unit tests + Playwright E2E tests

---

## 1. Architecture

### 1.1 Important Notes

- **Two AppRouter files exist:** `src/AppRouter.jsx` (active, used by App.jsx) and `src/screens/AppRouter.jsx` (stale). All tests target the active `src/AppRouter.jsx`.
- **CompliancePanel is NOT a routable screen.** It is a child component that takes `contractId`/`customerId` props. Unit tests provide these props directly; E2E tests access it through a contract detail screen.
- **Existing test files** (`dcfg-core.test.js`, `operations.test.js`, `setup.js`) are confirmed on disk at `spa/dcfg-shell/tests/`.

### 1.2 File Tree

```
spa/dcfg-shell/tests/          ← Vitest unit + component tests
  setup.js                     ← Global test setup (existing)
  core/
    dcfg-core.test.js          ← Existing — 298 lines
    portalApi.test.js           ← NEW — API layer (CSRF, HTTP methods, helpers)
    portalApi-config.test.js    ← NEW — Config loading + env vars
    portalApi-audit.test.js     ← NEW — writeAuditLog, onAuditEvent
    portalApi-flow.test.js      ← NEW — callFlow, createDocumentRequest
  hooks/
    useTableControls.test.js    ← NEW
    usePortalUser.test.js       ← NEW
    toast.test.js               ← NEW
  components/
    App.test.jsx                ← NEW — Root component auth guard + config boot
    RoleGuard.test.jsx          ← NEW
    FieldName.test.jsx          ← NEW
    SensorBanner.test.jsx       ← NEW
    NavPanel.test.jsx           ← NEW
  screens/
    operations.test.js          ← Existing — 128 lines
    salesDashboard.test.jsx     ← NEW
    contractsList.test.jsx      ← NEW — tests root-level src/ContractsList.jsx
    contractDetail.test.jsx     ← NEW
    customerList.test.jsx       ← NEW
    customerDetail.test.jsx     ← NEW
    msaList.test.jsx            ← NEW
    msaDetail.test.jsx          ← NEW
    locations.test.jsx          ← NEW
    locationDetail.test.jsx     ← NEW
    onboarding.test.jsx         ← NEW
    onboardingDetail.test.jsx   ← NEW
    sendQueue.test.jsx          ← NEW
    compliancePanel.test.jsx    ← NEW — rendered with required props, not routed
    admin.test.jsx              ← NEW
  wizards/
    newContractWizard.test.jsx  ← NEW
    newProposalWizard.test.jsx  ← NEW
    locationManager.test.jsx    ← NEW
  interview/
    interviewEngine.test.js     ← NEW
    interviewShell.test.jsx     ← NEW — mode switching (Conversational/Guided/Chat)
    interviewGenerate.test.js   ← NEW — record creation + flow trigger + audit
    questionRenderer.test.jsx   ← NEW
  debug/
    debugHarness.test.js        ← NEW — debug/index.js fetch patching
    debugPanel.test.jsx         ← NEW — DebugPanel.jsx React component

spa/dcfg-playwright/            ← Playwright E2E
  tests/
    auth.setup.ts               ← Existing
    dashboard.spec.ts           ← Existing
    contracts-list.spec.ts      ← Existing
    customer-list.spec.ts       ← Existing
    send-queue.spec.ts          ← Existing
    navigation.spec.ts          ← Existing
    create-documents.spec.ts    ← Existing (load test)
    msa-screens.spec.ts         ← NEW
    customer-detail.spec.ts     ← NEW
    location-screens.spec.ts    ← NEW
    onboarding-screens.spec.ts  ← NEW
    admin-panel.spec.ts         ← NEW
    contract-detail.spec.ts     ← NEW — includes compliance panel assertions
    contract-wizard.crud.spec.ts ← NEW — creates contract, soft-deletes
    proposal-wizard.crud.spec.ts ← NEW — creates proposal, soft-deletes
    location-manager.crud.spec.ts← NEW — creates property + appliance, soft-deletes
    audit-trail.crud.spec.ts    ← NEW — verifies audit log after write ops
    role-guard.spec.ts          ← NEW — role-based DOM suppression
    sensor-banner.spec.ts       ← NEW
    debug-panel.spec.ts         ← NEW
    cleanup.crud.spec.ts        ← NEW — safety net for orphaned [TEST] records
  pages/
    BasePage.ts                 ← Existing
    DashboardPage.ts            ← Existing
    ContractsListPage.ts        ← Existing
    CustomerListPage.ts         ← Existing
    SendQueuePage.ts            ← Existing
    MsaListPage.ts              ← NEW
    MsaDetailPage.ts            ← NEW
    CustomerDetailPage.ts       ← NEW
    LocationsPage.ts            ← NEW
    LocationDetailPage.ts       ← NEW
    OnboardingPage.ts           ← NEW
    OnboardingDetailPage.ts     ← NEW
    AdminPage.ts                ← NEW
    ContractDetailPage.ts       ← NEW — includes compliance panel locators
    ContractWizardPage.ts       ← NEW
    ProposalWizardPage.ts       ← NEW
    LocationManagerPage.ts      ← NEW
```

**File count:** ~31 new Vitest files, ~12 new Playwright specs, ~12 new page objects.

---

## 2. Vitest Unit Tests — Detail

### 2.1 portalApi.test.js — API Layer

All tests mock `global.fetch`. No network calls.

| Test Group | Tests |
|---|---|
| **CSRF token (`getToken`)** | Returns cached token on second call. Falls back from `window.shell` to DOM to fetch. `invalidateToken()` clears cache. Throws when all 3 sources fail. |
| **`apiGet`** | Sends GET with correct OData headers. Prepends `/_api` when path is relative. Passes through absolute URLs. Throws `ApiError` on non-200. Parses error message from Dataverse JSON. |
| **`apiPost`** | Sends POST with CSRF token in `__RequestVerificationToken` header. Calls `trimBody` (trims string values). Invalidates token on 401/403. Throws `ApiError` with message. |
| **`apiPostReturn`** | Same as POST plus: sends `Prefer: return=representation`. Handles 204 by reading `OData-EntityId` header and fetching record. Returns empty object when no `OData-EntityId`. Parses GUID from entityId URL. |
| **`apiPatch`** | Sends PATCH with CSRF + OData headers. Trims body. Invalidates token on 401/403. |
| **`apiDelete`** | Sends DELETE with CSRF + OData headers. No body. Invalidates token on 401/403. |
| **`trimBody`** | Trims leading/trailing whitespace on all string values. Passes non-strings through unchanged. Handles null/undefined input. |
| **Network failure** | `fetch` throwing (offline, DNS) propagates error correctly from apiGet/apiPost/apiPatch/apiDelete. |
| **`odataBind` / `bind`** | 2-arg form returns string `/entitySet(guid)`. 3-arg form returns object `{ "field@odata.bind": "/entitySet(guid)" }`. |
| **`formatCurrency`** | Formats numbers to `$X,XXX.XX`. Returns `$0.00` for NaN/null. |
| **`formatDate`** | Formats ISO string to `Mon DD, YYYY`. Returns empty string for null/undefined. |
| **Entity sets** | `EntitySets.properties === 'dcfg_properties'` (not `dcfg_propertys`). All 37 entity set values are non-empty strings. No duplicates. |
| **Enum completeness** | Every enum has matching label map with no gaps (every key in enum has a label). |
| **`resolveTemplate`** | All 6 family/type combos resolve to a `.docx` filename. Unknown combo returns null. |

### 2.2 portalApi-config.test.js — Config & Environment

| Test Group | Tests |
|---|---|
| **`loadConfig`** | Fetches `dcfg_configs` with `$filter=dcfg_active eq true`. Builds key-value map. Caches on second call (no second fetch). Logs error and returns empty map on failure. |
| **`getEnvVar`** | Returns value from cache. Returns null and warns when key missing. Returns null and warns when config not loaded. |

### 2.3 portalApi-audit.test.js — Audit & Hooks

| Test Group | Tests |
|---|---|
| **`writeAuditLog`** | Accepts both camelCase and dcfg_ prefixed keys. Posts to `/dcfg_audit_logs`. Includes `dcfg_performed_at` default. Binds `dcfg_related_contract_id` via `@odata.bind`. |
| **`onAuditEvent`** | Registers listener, fires on writeAuditLog. Returns unsubscribe function. Listener errors don't break audit write. |

### 2.4 portalApi-flow.test.js — Flow & Document Requests

| Test Group | Tests |
|---|---|
| **`callFlow`** | Resolves env var name to URL via `getEnvVar`. Sends POST with JSON body. Throws when URL not found. Throws on non-200 response. Returns parsed JSON or null for empty body. |
| **`createDocumentRequest`** | Posts to `dcfg_document_requests` entity set. Correct payload shape. (If this is a convenience wrapper — verify it exists; if not, test the pattern used by wizards.) |

### 2.5 Hooks

**useTableControls.test.js**
| Test | Detail |
|---|---|
| Default sort | Sorts by default column on first render |
| Toggle sort | Clicking same column reverses direction |
| Toggle sort new col | Clicking different column sorts ascending |
| Search filter | Filters rows by search term across `searchFields` |
| Dot notation | Supports `_customer.dcfg_display_name` for expanded entities |
| Empty input | Returns all rows when search term is empty |
| Case insensitive | Search is case-insensitive |

**usePortalUser.test.jsx** (render with provider)
| Test | Detail |
|---|---|
| Reads portal user | Extracts contactId, email, name from `window.Microsoft.Dynamic365.Portal.User` |
| Role helpers | `isAdmin()` true for DCFG_Admin, false for others |
| `isManager()` | True for DCFG_Admin AND DCFG_Manager |
| `hasRole(name)` | Matches exact role name |
| No user | Returns null user when Portal.User not present |

**toast.test.jsx**
| Test | Detail |
|---|---|
| `show()` renders toast | Toast visible with correct text |
| Type colors | ok=green, warn=yellow, err=red, info=blue |
| Auto-dismiss | ok/warn/info dismiss at 4s, err at 5.5s (fake timers) |
| `dismiss()` removes toast | Toast hidden after manual dismiss |

### 2.6 Components

**App.test.jsx**
| Test | Detail |
|---|---|
| Auth guard | Renders loading state, then content when user resolved |
| Config boot | Calls `loadConfig()` on mount |
| Provider tree | Wraps children in HashRouter + PortalUserProvider + ToastProvider |
| No user | Shows auth-required message when portal user absent |

**RoleGuard.test.jsx**
| Test | Detail |
|---|---|
| Admin sees admin content | Children render for DCFG_Admin |
| Viewer cannot see admin content | Children NOT rendered for DCFG_Viewer |
| Manager sees manager content | Children render for DCFG_Manager |
| No role = no content | Null user renders nothing |
| DOM suppression | Elements are removed, not `display:none` |

**FieldName.test.jsx**
| Test | Detail |
|---|---|
| Renders field name | `<Fn name="dcfg_contract_fee" />` renders text |
| Invisible by default | Color matches background (effectively invisible) |
| FnTh in table header | `<FnTh>` renders inside `<th>` with field name |

**SensorBanner.test.jsx** (mock fetch for sensor readings)
| Test | Detail |
|---|---|
| No alerts = no banner | Returns null when no active alerts |
| Shows alert count | Displays badge with count |
| Acknowledge removes alert | Click dismiss calls PATCH with acknowledged=true |
| Scrolling animation | Alert ticker has CSS animation class |

**NavPanel.test.jsx**
| Test | Detail |
|---|---|
| Renders all nav groups | Dashboard, Sales, Contracts, Operations, Admin groups present |
| Active state | Current route highlights nav item |
| Link targets | Each nav item links to correct hash route |

### 2.7 Screens (Component Rendering Tests)

Each screen test follows the same pattern:
1. Mock `fetch` to return sample Dataverse response
2. Render component inside **MemoryRouter** + PortalUserProvider (Note: app uses HashRouter, but MemoryRouter is standard for unit tests — any hash-dependent behavior tested in E2E)
3. Assert key elements render (headings, tables, KPI tiles, buttons)
4. Assert loading state renders then resolves
5. Assert empty state renders gracefully

| Screen | Key Assertions |
|---|---|
| **SalesDashboard** | 4 KPI tiles, pipeline section, recent activity table, quick action buttons |
| **ContractsList** | Split pane layout, search input, filter dropdowns, contract rows render. **Imports from `src/ContractsList.jsx`** (root level, not screens/) |
| **ContractDetail** | Status banner, location, program, contractor, lines table, amendments |
| **CustomerList** | Customer grid, search bar, sort headers, click triggers navigation |
| **CustomerDetail** | Customer name, contacts section, programs, locations, contracts, MSAs tabs |
| **MsaList** | MSA grid with columns, status badges |
| **MsaDetail** | Header, terms, rates table, linked contracts |
| **Locations** | Location grid, search, sort headers |
| **LocationDetail** | Property info, appliance list, photos section, compliance checks |
| **Onboarding** | Case list with phase badges, status indicators |
| **OnboardingDetail** | Timeline, checklists, compliance, document requests |
| **SendQueue** | Queue table, status column, retry button for failed items |
| **CompliancePanel** | Rendered with `contractId` and `customerId` props (NOT routed). Rules list, check status grid, pass/fail indicators. |
| **Admin** | Tab navigation (users, audit, config, templates, fields), each tab renders |

### 2.8 Wizards

**newContractWizard.test.jsx**
| Test | Detail |
|---|---|
| Step 1 renders | Family + Type selection visible |
| Family selection enables Type | Selecting Decades shows WO/Amendment/MSA |
| Step navigation | Next/Back buttons advance/retreat steps |
| Step 2 loads customers | Customer dropdown populated from mock API |
| Step 3 loads contractors | Contractor dropdown populated |
| Step 4 renders line items | Add/remove line item rows |
| Step 5 shows review | All selections displayed in summary |
| Validation blocks advance | Empty required fields prevent Next |
| Generate calls createDocumentRequest | Final submit POSTs to dcfg_document_requests |

**newProposalWizard.test.jsx**
| Test | Detail |
|---|---|
| Step 1 package selection | Package type visible |
| Step 2 customer + vendor | Dropdowns populated |
| Step 3 pricing + locations | Rate table, location multi-select |
| Step 4 review | Summary of all inputs |
| All fields editable | Can go back and change any field |

**locationManager.test.jsx**
| Test | Detail |
|---|---|
| Customer search | Debounced search input triggers API call |
| Location list renders | Locations appear after customer selected |
| Property detail card | Shows property fields |
| Appliance CRUD | Add/edit/remove appliance rows |
| Auto-PATCH on change | Field change triggers debounced PATCH |
| Photo capture stub | Camera button renders (mobile) |

### 2.9 Interview Module

**interviewEngine.test.js** (pure logic, no JSX)
| Test | Detail |
|---|---|
| Question registry | All registered questions accessible by ID |
| Conditional flow | Skip rules evaluated correctly |
| Validation | Required fields reject empty, format validators work |
| Answer collection | Answers stored and retrievable by question ID |

**interviewShell.test.jsx**
| Test | Detail |
|---|---|
| Renders default mode | Shows correct presentation mode on mount |
| Mode switching | Toggling mode re-renders with correct sub-component |
| Passes engine to child | Child mode receives engine instance |

**interviewGenerate.test.js**
| Test | Detail |
|---|---|
| Builds contract payload | Transforms interview answers into contract create body |
| Calls createDocumentRequest | Posts to dcfg_document_requests with correct fields |
| Writes audit log | Calls writeAuditLog after successful creation |
| Handles flow errors | Propagates errors from API calls |

**questionRenderer.test.jsx**
| Test | Detail |
|---|---|
| Renders by type | customerSearch, choice, dateInput each render correct input |
| Choice options | Options populated from question definition |
| onChange fires | Value changes propagate to parent |

### 2.10 Debug Module

**debugHarness.test.js** (tests `debug/index.js`)
| Test | Detail |
|---|---|
| No-op when inactive | `?dcfg_debug=1` absent = no fetch patching, no console interception |
| Patches fetch when active | `window.DCFG.debug.calls` populated after fetch |
| Records method, url, status, duration | Call log has correct shape |
| Console interception | `console.warn`/`error` captured in debug log |

**debugPanel.test.jsx** (tests `debug/DebugPanel.jsx`)
| Test | Detail |
|---|---|
| Renders when debug active | Panel visible when `window.DCFG.debug` exists |
| API call log section | Shows captured API calls |
| Error section | Shows captured errors |
| User snapshot | Displays current user info |

---

## 3. Playwright E2E Tests — Detail

### 3.1 Configuration Changes

**`.env` update:**
```
DCFG_PORTAL_URL=https://dmms1.powerappsportals.com
```

**`playwright.config.ts` update:** Add `crud` project for write tests. **CRUD tests run serially** (`fullyParallel: false`, `workers: 1`) to prevent cross-test interference:
```typescript
{
  name: 'crud',
  testMatch: /\.crud\.spec\.ts/,
  fullyParallel: false,
  use: {
    ...devices['Desktop Chrome'],
    storageState: 'playwright/.auth/user.json',
  },
  dependencies: ['setup'],
},
```

### 3.2 Auth

Existing `auth.setup.ts` — Windows Hello manual-pause pattern. No changes needed.

### 3.3 Read-Only Screen Specs

Each spec navigates to screen, asserts data loads, checks key elements. No writes.

**msa-screens.spec.ts**
- MSA list loads with rows
- Click MSA navigates to detail
- Detail shows header, terms, rates table
- Linked contracts section populated

**customer-detail.spec.ts**
- Navigate from customer list to detail
- Contact information visible
- Programs section with budget KPIs
- Locations tab loads
- Contracts tab loads

**location-screens.spec.ts**
- Location list loads
- Search filters locations
- Click navigates to detail
- Appliance list renders
- Photo gallery renders (or empty state)

**onboarding-screens.spec.ts**
- Case list loads with phase badges
- Click case opens detail
- Timeline renders phases
- Checklist items visible

**admin-panel.spec.ts**
- Admin tab navigation works
- Users tab lists users + roles
- Audit log tab loads with entries
- Config tab shows key-value pairs
- Template tab lists templates

**contract-detail.spec.ts** (replaces standalone compliance.spec.ts)
- Contract detail loads with status banner
- Location and program sections populated
- Contract lines table renders
- **CompliancePanel** section renders within the detail view (not standalone route)
- Compliance rules and check status visible

**sensor-banner.spec.ts**
- Banner appears when alerts exist (or hidden when none)
- Alert count badge correct
- Ticker scrolls

**debug-panel.spec.ts**
- Navigate with `?dcfg_debug=1`
- Debug panel opens
- API call log populated
- User snapshot section shows current user

**role-guard.spec.ts**
- Admin user sees all action buttons
- Verify action buttons present on screens where RoleGuard wraps them
- (Note: testing non-admin suppression requires a non-admin account or mock — defer to unit tests for full role matrix)

### 3.4 Write Specs (CRUD — Self-Cleaning)

**CSRF token for cleanup:** The cleanup code reads the token from the DOM (`document.querySelector('input[name="__RequestVerificationToken"]').value`), NOT from `window.DCFG.portalApi` (which does not exist on `window`).

**Cascade cleanup:** Write tests that create contracts must also soft-delete related contract lines and document outputs. The cleanup pattern tracks all created record IDs.

**Flow timing:** After creating a document request (which triggers an async Power Automate flow), tests wait 10 seconds before soft-deleting the parent record to allow the flow to complete.

Each write test follows this pattern:
```typescript
const createdRecords: Array<{ entitySet: string; id: string }> = [];

test.afterEach(async ({ page }) => {
  // Wait for async flows to settle
  if (createdRecords.length > 0) {
    await page.waitForTimeout(10000);
  }
  // Soft-delete all created records (reverse order for referential integrity)
  for (const rec of [...createdRecords].reverse()) {
    try {
      await page.evaluate(async ({ entitySet, id }) => {
        const tokenEl = document.querySelector('input[name="__RequestVerificationToken"]');
        const token = tokenEl?.value || '';
        await fetch(`/_api/${entitySet}(${id})`, {
          method: 'PATCH',
          headers: {
            'Content-Type': 'application/json',
            '__RequestVerificationToken': token,
          },
          body: JSON.stringify({ dcfg_active_flag: false }),
        });
      }, rec);
    } catch {
      console.warn(`Cleanup failed for ${rec.entitySet}(${rec.id})`);
    }
  }
});
```

**contract-wizard.crud.spec.ts**
| Test | Detail |
|---|---|
| Complete Decades Work Order wizard | Step through all 5 steps with valid data. Capture created contract ID + contract line IDs + document request ID from API log. Verify redirects to contract detail. Soft-delete all in afterEach. |
| Complete Bancroft Amendment wizard | Same flow for Bancroft family, Amendment type. |
| Validation prevents empty submit | Leave required fields empty, verify Next is blocked. (No records created — no cleanup.) |

**proposal-wizard.crud.spec.ts**
| Test | Detail |
|---|---|
| Complete Decades proposal wizard | All 4 steps, capture MSA ID + related record IDs, verify redirect. Soft-delete. |
| Edit fields after going back | Complete step 3, go back to step 1, change value, verify step 3 reflects change. |

**location-manager.crud.spec.ts**
| Test | Detail |
|---|---|
| Create property via LocationManager | Navigate to `/#/field`, search customer, add new location, fill details. Capture property ID. Soft-delete. |
| Add appliance to property | Navigate to existing property, add appliance. Capture appliance ID. Soft-delete appliance. |
| Auto-PATCH on field change | Change a field, wait for networkidle, verify no error toast. (No new records — no cleanup.) |

**audit-trail.crud.spec.ts**
| Test | Detail |
|---|---|
| Audit log written after contract create | Create contract via wizard, query `dcfg_audit_logs` via debug API log for matching target_record_id. Verify action_type = Generated. Soft-delete contract + lines (audit log is CREATE-only, no cleanup needed/possible). |

**cleanup.crud.spec.ts** — Safety net
| Test | Detail |
|---|---|
| Clean orphaned test records | Query each write-target entity set for records where `dcfg_client_name` or display field contains `[TEST]` AND `dcfg_active_flag = true` AND `createdon lt` 1 hour ago. Soft-delete each. Run manually or on schedule. |

### 3.5 New Page Objects

Each extends `BasePage`. Key locators per page:

| Page Object | Route | Key Locators |
|---|---|---|
| **MsaListPage** | `/#/msas` | table rows, search input, status badges |
| **MsaDetailPage** | `/#/msas/:id` | header, terms section, rates table, contracts section |
| **CustomerDetailPage** | `/#/customers/:id` | name heading, contacts, programs, locations tab, contracts tab |
| **LocationsPage** | `/#/locations` | grid rows, search input, sort headers |
| **LocationDetailPage** | `/#/locations/:id` | property info, appliance list, photos |
| **OnboardingPage** | `/#/onboarding` | case rows, phase badges |
| **OnboardingDetailPage** | `/#/onboarding/:id` | timeline, checklists, compliance |
| **AdminPage** | `/#/admin` | tab buttons (users/audit/config/templates/fields), tab content |
| **ContractDetailPage** | `/#/contracts/:id` | status banner, lines table, compliance panel, amendments |
| **ContractWizardPage** | `/#/contracts/new` | step indicators, family/type selectors, next/back, customer/contractor dropdowns, line item table, review, generate button |
| **ProposalWizardPage** | `/#/proposals/new` | step indicators, package selector, customer/vendor dropdowns, pricing table, location multi-select, review |
| **LocationManagerPage** | `/#/field` | customer search, location list, property detail, appliance section, add buttons |

---

## 4. Test Data Strategy

**Vitest (unit):** All data mocked via `vi.fn()` on `global.fetch`. Mock responses follow actual Dataverse OData shape:
```javascript
{ value: [{ dcfg_contractid: 'guid', dcfg_client_name: 'Test Corp', ... }] }
```

**Playwright (E2E reads):** Uses existing prod data. Assertions check structure (elements exist, tables have rows), not specific values.

**Playwright (E2E writes):** Each write test:
1. Creates records with identifiable values (e.g., `[TEST] Auto-generated 2026-03-27T...`)
2. Tracks ALL created record IDs (parent + child records) in `createdRecords` array
3. Waits 10s for async flows to settle before cleanup
4. Soft-deletes all records in reverse order (child first) via `PATCH { dcfg_active_flag: false }` in `afterEach`
5. CSRF token acquired from DOM `input[name="__RequestVerificationToken"]`
6. If soft-delete fails, test logs warning but does not fail (cleanup is best-effort)

**Cleanup safety net:** `cleanup.crud.spec.ts` queries for `[TEST]` prefixed records with `dcfg_active_flag = true` older than 1 hour and soft-deletes them. Run manually or on schedule.

**Test isolation:** CRUD Playwright tests run serially (`workers: 1`, `fullyParallel: false`) to prevent parallel tests from interfering with each other's records.

---

## 5. Execution

```bash
# Unit tests
cd C:\DCFG\spa\dcfg-shell
npm run test              # all unit tests
npm run test:coverage     # with coverage report

# E2E smoke (read-only)
cd C:\DCFG\spa\dcfg-playwright
npx playwright test --project=setup --headed   # auth first
npx playwright test --project=smoke            # read-only screens

# E2E CRUD (write tests — serial)
npx playwright test --project=crud             # wizard + CRUD tests

# E2E load (150-doc generation)
npx playwright test --project=load             # existing load test

# Cleanup orphaned test records
npx playwright test --project=crud --grep cleanup
```

---

## 6. Coverage Targets

| Layer | Current | After |
|---|---|---|
| **portalApi.js** | 0% | ~90% (all public functions + error paths + network failures) |
| **Hooks** | 0% | ~95% (pure logic, easy to cover) |
| **Components** | 0% | ~80% (render + key interactions) |
| **Screens** | ~5% (operations only) | ~75% (render + loading + empty states + ContractDetail) |
| **Wizards** | 0% | ~60% (step navigation, validation, submit) |
| **Interview** | 0% | ~70% (engine + shell + generate + renderer) |
| **Debug** | 0% | ~80% (harness + panel) |
| **E2E screen coverage** | 5/20 screens | 20/20 screens |
| **E2E write flows** | 1 (create-documents) | 5 (contract, proposal, location, appliance, audit) |

---

## 7. Implementation Order

1. **portalApi.test.js + portalApi-config.test.js + portalApi-audit.test.js + portalApi-flow.test.js** — Foundation. Tests the layer everything depends on.
2. **Hook tests** (useTableControls, usePortalUser, toast) — Pure logic, fast to write.
3. **Component tests** (App, RoleGuard, FieldName, SensorBanner, NavPanel) — Small components.
4. **Screen rendering tests** — All 15 screens. Repetitive pattern, can parallelize.
5. **Wizard tests** — Most complex unit tests. Depend on understanding step flow.
6. **Interview module tests** (engine, shell, generate, renderer) — Write path coverage.
7. **Debug module tests** (harness + panel) — Lower priority, smaller surface area.
8. **Playwright page objects** — 12 new page objects. Foundation for E2E specs.
9. **Playwright read-only specs** — 8 new specs. Safe, no cleanup needed.
10. **Playwright write specs** — 4 CRUD specs + cleanup utility. Most risky, run last.

---

## 8. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Soft-delete cleanup fails in E2E | `cleanup.crud.spec.ts` safety net + `[TEST]` prefix for manual identification |
| Cascade orphans (contract lines, doc outputs) | `createdRecords` array tracks ALL record IDs, cleanup deletes child records first |
| Async flow races with cleanup | 10-second wait before soft-delete in afterEach |
| Auth token expires mid-test | Existing observer layer catches 401, soft-assert flags it |
| Prod data changes break assertions | E2E tests assert structure (elements exist, tables have rows) not specific values |
| Wizard steps change | Page objects encapsulate locators — single place to update |
| React 17 testing quirks | Setup.js already configures `IS_REACT_ACT_ENVIRONMENT` |
| HashRouter vs MemoryRouter | Unit tests use MemoryRouter (standard practice). Hash-dependent behavior covered by E2E. |
| Parallel CRUD test interference | CRUD project runs serial (`workers: 1`), smoke project remains parallel |
| Two AppRouter files | Tests import from `src/AppRouter.jsx` only. Stale `screens/AppRouter.jsx` ignored. |

---

## 9. Out of Scope

These items are intentionally excluded:
- **SpeechMic.jsx** — stub component, not implemented
- **intakeFieldKeys.js** — static registry, trivial to verify by inspection
- **Error boundary testing** — SPA does not currently have error boundaries. Adding them is a feature, not a test.
- **Retry/offline testing** — portalApi has no retry logic. Unit tests verify errors propagate; adding retry is a feature.
