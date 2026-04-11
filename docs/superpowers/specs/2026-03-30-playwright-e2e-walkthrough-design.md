# DCFG Playwright E2E Walkthrough — Design Spec

**Date:** 2026-03-30
**Purpose:** Exhaustive E2E test suite covering every path through Proposal and Contract wizards, Send Queue, email triggers, validation errors, and role guards. Full screenshot capture at every state for agent analysis.

---

## Scope

### Proposal Wizard — 6 Full Runs
Each of 3 packages × 2 pricing modes, complete lifecycle:

| Run | Package | Pricing | Email To |
|-----|---------|---------|----------|
| P1 | Package A — Essential | Uniform (flat) | Test1@decades-cg.com |
| P2 | Package A — Essential | Type-Based (differentiated) | Test2@decades-cg.com |
| P3 | Package B — Extended (Concierge) | Uniform | Test1@decades-cg.com |
| P4 | Package B — Extended (Concierge) | Type-Based | Test2@decades-cg.com |
| P5 | Package C — Premium (Optimized) | Uniform | Test1@decades-cg.com |
| P6 | Package C — Premium (Optimized) | Type-Based | Test2@decades-cg.com |

**Each run covers:**
1. Draft landing page → "Start New Proposal"
2. Step 1: Select package
3. Step 2: Search existing customer OR create new customer, fill signer blocks
4. Step 3: Set pricing mode + rates, add locations, verify totals
5. Step 4: Review merge fields, click Generate
6. Save as Draft mid-wizard (step 2 or 3), navigate away, return to drafts list, resume
7. After generate: navigate to MSA detail → Submit for Approval
8. Send Queue: approve → assign WO → mark sent (email to Test1/Test2)
9. Screenshot every state transition

### Contract Wizard — 6 Full Runs
2 families × 3 types, complete lifecycle:

| Run | Family | Type | Email To |
|-----|--------|------|----------|
| C1 | Bancroft | Work Order | Test1@decades-cg.com |
| C2 | Bancroft | Amendment | Test2@decades-cg.com |
| C3 | Bancroft | Contractor MSA | Test1@decades-cg.com |
| C4 | Decades | Work Order | Test2@decades-cg.com |
| C5 | Decades | Amendment | Test1@decades-cg.com |
| C6 | Decades | Contractor MSA | Test2@decades-cg.com |

**Each run covers:**
1. Draft landing page → "Start New" or resume draft
2. Step 1: Select customer (search), view programs + locations
3. Step 2: Select document type, vendor, location, date. If Amendment: select parent WO + amendment number
4. Step 3: Confirm contractor details, signer block, owner contact (auto-filled from location)
5. Step 4: Add Exhibit A line items (cost code, description, amount), verify AP code resolution + totals
6. Step 5: Review merge fields, click Generate
7. Save as Draft mid-wizard (step 3 or 4), navigate away, return to drafts list, resume
8. After generate: navigate to Contract detail → Submit for Approval
9. Send Queue: approve → assign WO (blanket or manual) → mark sent (email to Test1/Test2)
10. Screenshot every state transition

### Send Queue — 3 Email Trigger Runs

| Run | Trigger | Button | Default Recipient → Override |
|-----|---------|--------|------------------------------|
| E1 | Request More Info | "? Info" on Pending Review | team@decades-cg.com → Test1@decades-cg.com |
| E2 | MSA Renewal | "✉ Renew" on Alerts tab | Customer contact → Test2@decades-cg.com |
| E3 | Insurance Renewal | Insurance alert on Alerts tab | Vendor email → Test1@decades-cg.com |

**Each run covers:**
1. Navigate to Send Queue
2. Click appropriate KPI card / tab
3. Click email trigger button
4. Verify modal opens with correct pre-filled fields
5. Override recipient to test email
6. Set reminder option
7. Click Send Email
8. Verify success toast
9. Screenshot modal + result

### Validation Error Testing — 2 Specs

**Proposal Validation:**
- Step 1: Try Next without selecting package → verify disabled
- Step 2: Leave signer fields blank → verify checklist shows red
- Step 3: No locations → verify cannot generate
- Step 3: All locations set to no-charge → verify moTotal = 0 blocks generate
- Step 4: Missing required merge fields → verify red indicators
- Screenshot each validation state

**Contract Validation:**
- Step 1: Try Next without selecting customer → verify disabled
- Step 2: Amendment without parent WO → verify disabled
- Step 4: Empty lines → verify behavior
- Step 5: Missing signerName or contractorLegalName → verify Generate disabled
- Step 5: Missing locationId → verify Generate disabled
- Screenshot each validation state

### Role Guard Testing — 2 Specs

**Viewer Role:**
- Navigate to each screen, verify read-only restrictions
- Attempt create actions → verify blocked
- Attempt approve/return/delete on Send Queue → verify blocked
- Screenshot each restriction

**Manager Role:**
- Navigate to each screen, verify manager-level access
- Verify admin-only features are hidden
- Screenshot each restriction

---

## Architecture

### Directory Structure

```
C:\dcfg\dcfg-resources\tests\
├── playwright.config.ts          (updated: add e2e-walkthrough project)
├── auth-state.json               (saved by auth setup)
├── walkthrough/
│   ├── fixtures/
│   │   ├── walkthrough-base.ts   (auth, page setup, screenshot helper, API interceptor)
│   │   ├── proposal-wizard.po.ts (Page Object: NewProposalWizard)
│   │   ├── contract-wizard.po.ts (Page Object: NewContractWizard)
│   │   ├── send-queue.po.ts      (Page Object: SendQueue)
│   │   ├── msa-detail.po.ts      (Page Object: MsaDetail)
│   │   ├── contract-detail.po.ts (Page Object: ContractDetail)
│   │   └── test-data.ts          (customer names, rates, locations, cost codes for each run)
│   ├── proposal/
│   │   ├── package-a-uniform.spec.ts
│   │   ├── package-a-type-based.spec.ts
│   │   ├── package-b-uniform.spec.ts
│   │   ├── package-b-type-based.spec.ts
│   │   ├── package-c-uniform.spec.ts
│   │   └── package-c-type-based.spec.ts
│   ├── contract/
│   │   ├── bancroft-work-order.spec.ts
│   │   ├── bancroft-amendment.spec.ts
│   │   ├── bancroft-contractor-msa.spec.ts
│   │   ├── decades-work-order.spec.ts
│   │   ├── decades-amendment.spec.ts
│   │   └── decades-contractor-msa.spec.ts
│   ├── send-queue/
│   │   ├── request-info-email.spec.ts
│   │   ├── msa-renewal-email.spec.ts
│   │   └── insurance-renewal-email.spec.ts
│   ├── validation/
│   │   ├── proposal-errors.spec.ts
│   │   └── contract-errors.spec.ts
│   └── role-guards/
│       ├── viewer-restrictions.spec.ts
│       └── manager-restrictions.spec.ts
```

### Screenshot Output

```
C:\dcfg\dcfg-resources\docs\walkthrough-captures\
├── proposal-a-uniform/
│   ├── 01-drafts-landing.png
│   ├── 02-step1-package-select.png
│   ├── 03-step2-customer-search.png
│   ├── ...
│   └── api-log.json
├── proposal-a-type-based/
│   └── ...
├── contract-bancroft-wo/
│   └── ...
├── send-queue-info-email/
│   └── ...
├── validation-proposal/
│   └── ...
└── role-guards-viewer/
    └── ...
```

Each spec captures:
- Full-page screenshot at every navigation/state change
- Element-level screenshots for key UI components (modals, tables, badges)
- `api-log.json` per run: every `_api/` call with URL, method, status, timing
- Console errors captured and written to `console-errors.json`

### Page Objects

#### ProposalWizardPO
```typescript
class ProposalWizardPO {
  // Navigation
  async gotoDraftsLanding()
  async startNewProposal()
  async resumeDraft(index: number)
  async deleteDraft(index: number)
  async nextStep()
  async prevStep()
  async getCurrentStep(): number

  // Step 1
  async selectPackage(pkg: 'PackageA' | 'PackageB' | 'PackageC')

  // Step 2 — Customer
  async searchCustomer(name: string)
  async selectCustomerResult(index: number)
  async switchToNewCustomer()
  async switchToSearch()
  async fillNewCustomer(data: CustomerData)
  async fillCustomerContact(name: string, email: string, phone: string)
  async fillBillingAddress(addr: string, city: string, state: string, zip: string)
  async fillCustomerSigner(name: string, title: string)
  async fillVendorSigner(name: string, title: string)
  async fillMsaDate(date: string)
  async fillMsaName(name: string)

  // Step 3
  async setPricingMode(mode: 'uniform' | 'type')
  async fillUniformRates(monthly: string, onboarding: string)
  async fillTypeRate(typeName: string, monthly: string, onboarding: string)
  async addLocation(data: LocationData)
  async toggleNoCharge(index: number)
  async removeLocation(index: number)
  async getMonthlyTotal(): string
  async getContractValue(): string

  // Step 4
  async clickGenerate()
  async waitForGenerateSuccess()
  async getDocUrl(): string | null
  async getMergeFieldStatus(label: string): 'green' | 'red' | 'gray'

  // Assertions
  async expectStepVisible(step: number)
  async expectDraftSavedIndicator()
  async expectGenerateDisabled()
  async expectGenerateEnabled()
  async expectValidationChecklist(items: {label: string, ok: boolean}[])
}
```

#### ContractWizardPO
```typescript
class ContractWizardPO {
  // Navigation
  async gotoDraftsLanding()
  async startNewContract()
  async resumeDraft(index: number)
  async deleteDraft(index: number)
  async nextStep()
  async prevStep()
  async getCurrentStep(): number

  // Step 1
  async selectCustomer(name: string)
  async createNewCustomer(name: string)
  async selectProgram(name: string)
  async selectLocation(name: string)

  // Step 2
  async selectContractType(type: 'WorkOrder' | 'Amendment' | 'ContractorMSA')
  async selectParentContract(number: string)
  async fillAmendmentNumber(num: string)
  async fillServiceLocationDesc(desc: string)
  async selectVendor(name: string)
  async selectLocationDropdown(name: string)
  async setContractDate(date: string)

  // Step 3
  async fillContractorLegalName(name: string)
  async fillContractorAddress(addr: string)
  async fillContractorPhone(phone: string)
  async fillContractorEmail(email: string)
  async fillPaymentProcess(terms: string)
  async fillSignerName(name: string)
  async fillSignerTitle(title: string)
  async getOwnerContact(): OwnerContactData

  // Step 4
  async addLine()
  async removeLine(index: number)
  async setLineCostCode(index: number, codeName: string)
  async setLineDescription(index: number, desc: string)
  async setLineAmount(index: number, amount: string)
  async getLineApCode(index: number): string
  async getLinesTotal(): string

  // Step 5
  async clickGenerate()
  async waitForGenerateSuccess()
  async getContractNumber(): string
  async getDocUrl(): string | null
  async getMergeFieldStatus(label: string): 'green' | 'red' | 'gray'

  // Assertions
  async expectStepVisible(step: number)
  async expectDraftSavedIndicator()
  async expectGenerateDisabled()
  async expectGenerateEnabled()
  async expectAmendmentFieldsVisible()
  async expectAmendmentFieldsHidden()
}
```

#### SendQueuePO
```typescript
class SendQueuePO {
  // Navigation
  async goto()
  async clickKpiCard(key: 'sales' | 'contracts' | 'onboarding' | 'sendqueue' | 'alerts')
  async selectQueueTab(tab: 'pending' | 'approved' | 'returned' | 'wo-number')
  async openSearch()
  async search(query: string)

  // KPI Cards
  async getKpiValue(key: string): string
  async getAlertBadge(): string | null

  // Detail Strip
  async expectDetailStripOpen()
  async closeDetailStrip()
  async getDetailStripItems(column: number): string[]
  async clickDetailStripItem(column: number, index: number)

  // Alerts
  async clickRenewButton(index: number)
  async expectAlertActioned(index: number)

  // Approval Queue
  async approveContract(index: number)
  async requestInfo(index: number)
  async returnContract(index: number)
  async deleteContract(index: number)
  async openDocument(index: number)
  async confirmAction()
  async cancelAction()

  // WO Assignment
  async applyBlanket(index: number)
  async assignWoNumber(index: number, woNumber: string)

  // Email Modal
  async expectEmailModalOpen()
  async getEmailTo(): string
  async getEmailSubject(): string
  async setEmailBody(body: string)
  async overrideEmailTo(email: string)
  async setReminder(days: 7 | 14 | 30)
  async toggleReminder()
  async clickSendEmail()
  async closeEmailModal()

  // Confirm Modal
  async expectConfirmModalOpen()
  async getConfirmTitle(): string
}
```

#### MsaDetailPO
```typescript
class MsaDetailPO {
  async goto(id: string)
  async expectLoaded()
  async getStatus(): string
  async getDocumentUrl(): string | null
  async submitForApproval()
  async confirmSubmitApproval()
  async expectStatus(status: string)
  async expectSubmitForApprovalVisible()
  async expectSubmitForApprovalHidden()
  async getRatesTable(): { type: string; monthly: string; onboarding: string }[]
  async getContractsTab(): string[]
}
```

#### ContractDetailPO
```typescript
class ContractDetailPO {
  async goto(id: string)
  async expectLoaded()
  async getStatus(): string
  async getContractNumber(): string
  async getDocumentUrl(): string | null
  async submitForApproval()
  async confirmSubmitApproval()
  async expectStatus(status: string)
  async expectSubmitForApprovalVisible()
  async expectSubmitForApprovalHidden()
  async getExhibitALines(): { costCode: string; description: string; amount: string }[]
  async getContractFee(): string
}
```

### Test Data (test-data.ts)

```typescript
export const TEST_EMAILS = {
  test1: 'Test1@decades-cg.com',
  test2: 'Test2@decades-cg.com',
};

export const PROPOSAL_RUNS = [
  { id: 'P1', package: 'PackageA', pricing: 'uniform', email: TEST_EMAILS.test1,
    customer: 'E2E Proposal A-Flat', rates: { monthly: '1250', onboarding: '350' } },
  { id: 'P2', package: 'PackageA', pricing: 'type', email: TEST_EMAILS.test2,
    customer: 'E2E Proposal A-Type' },
  { id: 'P3', package: 'PackageB', pricing: 'uniform', email: TEST_EMAILS.test1,
    customer: 'E2E Proposal B-Flat', rates: { monthly: '1800', onboarding: '500' } },
  { id: 'P4', package: 'PackageB', pricing: 'type', email: TEST_EMAILS.test2,
    customer: 'E2E Proposal B-Type' },
  { id: 'P5', package: 'PackageC', pricing: 'uniform', email: TEST_EMAILS.test1,
    customer: 'E2E Proposal C-Flat', rates: { monthly: '2500', onboarding: '750' } },
  { id: 'P6', package: 'PackageC', pricing: 'type', email: TEST_EMAILS.test2,
    customer: 'E2E Proposal C-Type' },
];

// Contract family is DERIVED from customer, not user-selected:
// - Bancroft family: customer with dcfg_is_tpa=true + dcfg_has_custom_templates=true
// - Decades family: default (non-TPA customers)
// Test data must use the correct customer for each family.
export const CONTRACT_CUSTOMERS = {
  bancroft: 'E2E Bancroft TPA Client',  // Must have dcfg_is_tpa=true, dcfg_has_custom_templates=true
  decades: 'E2E Decades Client',        // Standard non-TPA customer
};

export const CONTRACT_RUNS = [
  { id: 'C1', family: 'Bancroft', type: 'WorkOrder', email: TEST_EMAILS.test1, customer: CONTRACT_CUSTOMERS.bancroft },
  { id: 'C2', family: 'Bancroft', type: 'Amendment', email: TEST_EMAILS.test2, customer: CONTRACT_CUSTOMERS.bancroft },
  { id: 'C3', family: 'Bancroft', type: 'ContractorMSA', email: TEST_EMAILS.test1, customer: CONTRACT_CUSTOMERS.bancroft },
  { id: 'C4', family: 'Decades', type: 'WorkOrder', email: TEST_EMAILS.test2, customer: CONTRACT_CUSTOMERS.decades },
  { id: 'C5', family: 'Decades', type: 'Amendment', email: TEST_EMAILS.test1, customer: CONTRACT_CUSTOMERS.decades },
  { id: 'C6', family: 'Decades', type: 'ContractorMSA', email: TEST_EMAILS.test2, customer: CONTRACT_CUSTOMERS.decades },
];

export const TEST_LOCATIONS = [
  { name: 'E2E Residential Site', type: 'Residential', addr: '100 Test St', city: 'Albany', st: 'NY', zip: '12207' },
  { name: 'E2E Commercial Site', type: 'Commercial', addr: '200 Test Ave', city: 'Troy', st: 'NY', zip: '12180' },
  { name: 'E2E Admin Office', type: 'Admin', addr: '300 Test Blvd', city: 'Schenectady', st: 'NY', zip: '12345' },
];

export const TYPE_RATES = {
  Residential: { monthly: '1500', onboarding: '400' },
  Commercial: { monthly: '2200', onboarding: '600' },
  Admin: { monthly: '0', onboarding: '0' },
};

export const TEST_LINES = [
  { costCode: 'General Maintenance', description: 'E2E monthly maintenance scope', amount: '5000' },
  { costCode: 'Landscaping', description: 'E2E seasonal landscaping', amount: '2500' },
];

export const TEST_SIGNER = { name: 'E2E Test Signer', title: 'Test President' };
export const TEST_VENDOR_SIGNER = { name: 'E2E Vendor Signer', title: 'Test VP Operations' };

export const TEST_CONTACT = {
  name: 'E2E Contact Person', email: 'Test1@decades-cg.com', phone: '(518) 555-9999',
};

export const TEST_BILLING = {
  addr: '400 E2E Billing St', city: 'Albany', state: 'NY', zip: '12207',
};

// Append timestamp to customer names to avoid collisions with stale data
export function uniqueName(base: string): string {
  const ts = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
  return `${base} ${ts}`;
}
```

### Shared Fixture (walkthrough-base.ts)

```typescript
// Extends Playwright test with:
// - Auth state from auth-state.json
// - Screenshot capture at every step (auto-numbered, flow-prefixed)
// - API interceptor logging all _api/ calls + 403s
// - Console error capture
// - Cleanup helper (soft-delete created records)
// - Debug mode enabled (?dcfg_debug=1)

type WalkthroughFixtures = {
  capture: (label: string) => Promise<string>;
  captureElement: (selector: string, label: string) => Promise<string>;
  apiLog: { url: string; status: number; method: string }[];
  consoleErrors: string[];
  createdRecords: { table: string; id: string }[];
  cleanup: () => Promise<void>;
  flowId: string; // e.g. 'proposal-a-uniform'
};
```

### Config Updates

Add to `playwright.config.ts` (reuses existing `auth-setup` project):
```typescript
{
  name: 'walkthrough',
  dependencies: ['auth-setup'],  // reuse existing auth project, no duplicate login
  testDir: './walkthrough',
  timeout: 300_000,  // 5 min per spec — full lifecycle
  use: {
    storageState: './auth-state.json',
    viewport: { width: 1440, height: 900 },
    screenshot: 'off',  // manual capture per step
    video: 'retain-on-failure',
    trace: 'retain-on-failure',
  },
}
```

---

## Test Flow Template

### Proposal Spec (example: package-a-uniform.spec.ts)

```
1. Navigate to /#/proposals/new
2. Screenshot: drafts landing page
3. Click "Start New Proposal"
4. Screenshot: step 1 (empty)

5. SELECT PACKAGE A (Essential)
6. Screenshot: step 1 (package selected)
7. Click Next

8. SEARCH CUSTOMER "E2E Proposal A-Flat"
   - If not found: switch to New, fill name + contact
9. Fill MSA date, MSA name (optional)
10. Fill customer signer: name + title
11. Fill vendor signer: name + title
12. Screenshot: step 2 (complete)
13. Click Next (auto-saves draft)
14. Verify "Draft saved" indicator

--- DRAFT SAVE/RESUME INTERRUPT ---
15. Navigate away to /#/dashboard
16. Screenshot: dashboard
17. Navigate to /#/proposals/new
18. Screenshot: drafts landing (should show our draft)
19. Click Resume on our draft
20. Screenshot: resumed wizard (should be on step 3)
21. Verify all step 2 data restored
--- END INTERRUPT ---

22. SET PRICING: Uniform
23. Fill monthly rate: 1250
24. Fill onboarding rate: 350
25. Screenshot: step 3 (rates filled, no locations)

26. ADD LOCATION: E2E Residential Site
27. Screenshot: step 3 (1 location)
28. ADD LOCATION: E2E Commercial Site
29. ADD LOCATION: E2E Admin Office
30. Toggle Admin to no-charge
31. Screenshot: step 3 (3 locations, totals visible)
32. Verify monthly total = $2500 (1250+1250+0)
33. Verify contract value calculation
34. Click Next

35. REVIEW step 4
36. Screenshot: step 4 (all merge fields)
37. Verify all required fields green
38. Screenshot: fee summary sidebar

39. CLICK GENERATE
40. Wait for success (up to 90s)
41. Screenshot: step 4 (success state)
42. Capture document URL

--- POST-GENERATE LIFECYCLE ---
43. Navigate to MSA detail (from URL or list)
44. Screenshot: MSA detail page
45. Click "Submit for Approval"
46. Screenshot: confirmation modal
47. Confirm
48. Screenshot: MSA in Pending Approval status

49. Navigate to Send Queue
50. Screenshot: send queue landing
51. Click "Pending Review" tab
52. Screenshot: pending review (our proposal should appear)
53. Click Approve on our proposal
54. Screenshot: confirm approve modal
55. Confirm approve
56. Screenshot: approved state

57. Click "Needs Work Order Number" tab
58. Screenshot: WO assignment queue
59. Assign WO or Apply Blanket
60. Screenshot: WO assigned

61. Verify email sent to Test1@decades-cg.com
62. Screenshot: final state

--- CLEANUP ---
63. Soft-delete created MSA, customer (if new), locations, rates
64. Write api-log.json + console-errors.json
```

### Contract Spec follows same pattern with 5 wizard steps

### Amendment Spec additionally:
- **Self-contained setup:** Each amendment spec creates its own parent WO via direct API call (`apiPostReturn` to `dcfg_contracts`) in a `test.beforeAll` hook — no dependency on other spec files running first
- Step 2: selects parent WO, fills amendment number + service location description
- Auto-fill of vendor + location from parent verified
- Cleanup: soft-deletes both the amendment AND the setup parent WO

---

## Pending / Future State Tests

Tests that will be built complete but marked `test.skip()` with reason until the underlying feature is ready:

| Test | Reason for Skip | Unblocks When |
|------|-----------------|---------------|
| Exhibit A Basic generation verification | DocGen Switch case placeholder | Switch case wired |
| Exhibit A Optimized generation verification | DocGen Switch case placeholder | Switch case wired |
| Exhibit B location list in document | Excel paste UX not built | Phase 4 complete |
| Exhibit C fee schedule tokens in document | MSA rates tokens not wired | Phase 2 complete |
| Exhibit D insurance in document | DocGen Switch case placeholder | Switch case wired |
| PDF merge pipeline | Send pipeline not built | Phase 3 complete |
| Full send-to-customer pipeline | Depends on PDF merge | Phase 3 complete |

These tests will still:
- Execute the wizard through to Generate
- Capture screenshots
- Verify the `createDocumentRequest` call was made
- Skip only the document content verification step

---

## Email Override Strategy

The email flow uses `callFlow('dcfg_flow_send_email_url', { to, subject, body })`. The flow URL is loaded dynamically from `dcfg_configs` at boot — it resolves to a Power Automate `*.logic.azure.com` endpoint.

**Two-tier approach:**

**Tier 1 — Network interception (when flow is live):**
```typescript
// Intercept the Power Automate flow POST and rewrite recipient
await page.route(/logic\.azure\.com|flow\.microsoft\.com/, async (route) => {
  const request = route.request();
  if (request.method() === 'POST') {
    const body = JSON.parse(request.postData() || '{}');
    const originalTo = body.to;
    body.to = targetEmail; // Test1 or Test2
    console.log(`📧 Email intercepted: ${originalTo} → ${targetEmail}`);
    await route.continue({ postData: JSON.stringify(body) });
  } else {
    await route.continue();
  }
});
```

**Tier 2 — Verify intent (when flow unavailable):**
If the flow URL is not configured or returns error, the SPA shows "Email action logged (flow unavailable)" toast. In this case the test:
1. Verifies the email modal displayed the correct original recipient
2. Verifies the modal body/subject were correct
3. Captures the toast message confirming the attempt was made
4. Logs `{ intended_to, subject, body, flow_available: false }` to `api-log.json`

The test passes in both tiers — Tier 1 validates delivery, Tier 2 validates intent. Both are logged for agent analysis.

---

## Run Commands

```bash
# Auth first (one-time, headed for Windows Hello)
cd C:\dcfg\dcfg-resources\tests
npx playwright test auth.setup --headed --project=walkthrough-auth

# Run all walkthrough tests (headed for visual verification)
npx playwright test --project=walkthrough --headed

# Run specific flow
npx playwright test walkthrough/proposal/package-a-uniform --project=walkthrough --headed

# Run all proposals
npx playwright test walkthrough/proposal/ --project=walkthrough --headed

# Run all contracts
npx playwright test walkthrough/contract/ --project=walkthrough --headed

# Run validation tests only
npx playwright test walkthrough/validation/ --project=walkthrough --headed

# Run role guard tests only
npx playwright test walkthrough/role-guards/ --project=walkthrough --headed
```

---

## Success Criteria

1. All 6 proposal runs complete create → draft → resume → generate → approve → email
2. All 6 contract runs complete create → draft → resume → generate → approve → WO → email
3. All 3 email triggers send to Test1/Test2@decades-cg.com
4. All validation error states captured with screenshots
5. Role guards verified for viewer and manager
6. Every screenshot captured in `walkthrough-captures/` organized by flow
7. API logs show zero unexpected 403s
8. Console errors captured and flagged
9. All test records soft-deleted after runs (set `SKIP_CLEANUP=1` env var to preserve for investigation)
10. Pending tests marked with `test.skip()` and clear unblock criteria

---

## Additional Coverage (from review)

### Decline-and-Resubmit Path
- Contract detail → Return (decline) → verify status Declined → edit → re-generate → re-submit
- Covered in one contract spec as an extended path after the main WO run

### Void Path
- Admin voids a contract → verify status Void, record hidden from active lists
- Covered in role guard admin spec

### Search Overlay (Ctrl+K)
- Open search overlay on Send Queue → search for created test contract → click result → verify navigation
- Covered in one send queue spec

### Document Generation Polling
- After `createDocumentRequest`, poll MSA/contract record for `dcfg_document_url` becoming non-null (10s interval, 90s timeout)
- Watch for success toast ("generated successfully") as primary signal, poll as fallback
- If timeout: capture screenshot of current state, mark test as soft-fail with `test.info().annotations`

### Role Guard Auth Requirements
- Requires separate test accounts per role (viewer, manager)
- Separate auth state files: `auth-state-viewer.json`, `auth-state-manager.json`
- If accounts not available: role guard specs marked `test.skip('Pending viewer/manager test accounts')`

### Screenshot Helper Reuse
- `walkthrough-base.ts` imports and extends `captureStep`/`captureElement` from existing `screenshot-helpers.ts`
- Overrides base directory to `walkthrough-captures/` instead of `user-manual/screenshots/`
- No duplicate screenshot implementation
