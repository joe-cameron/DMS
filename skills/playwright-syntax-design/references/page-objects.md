# Page Object Model — Structuring Reusable Test Helpers

## Why POM Matters

When the UI changes (and it will), you update ONE file instead of every test. Page objects encapsulate locators and actions so tests read like workflows, not DOM manipulation.

---

## Base Page Pattern

```typescript
// pages/BasePage.ts
import { Page, Locator } from '@playwright/test';

export class BasePage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  async waitForPageReady() {
    await this.page.waitForLoadState('networkidle');
  }
}
```

---

## Page Object Example

```typescript
// pages/ContractDetailPage.ts
import { Page, Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class ContractDetailPage extends BasePage {
  // Locators — defined once, used everywhere
  readonly customerDropdown: Locator;
  readonly msaDropdown: Locator;
  readonly propertyDropdown: Locator;
  readonly contractFeeInput: Locator;
  readonly descriptionInput: Locator;
  readonly generateButton: Locator;
  readonly statusBadge: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    super(page);
    this.customerDropdown = page.getByTestId('customer-select');
    this.msaDropdown = page.getByTestId('msa-select');
    this.propertyDropdown = page.getByTestId('property-select');
    this.contractFeeInput = page.getByTestId('contract-fee');
    this.descriptionInput = page.getByTestId('description-of-service');
    this.generateButton = page.getByTestId('generate-btn');
    this.statusBadge = page.getByTestId('contract-status');
    this.saveButton = page.getByRole('button', { name: 'Save' });
  }

  // Actions — high-level user workflows
  async selectCustomer(name: string) {
    await this.customerDropdown.click();
    await this.page.getByRole('option', { name }).click();
    await this.waitForPageReady();
  }

  async selectMSA(name: string) {
    await this.msaDropdown.click();
    await this.page.getByRole('option', { name }).click();
    await this.waitForPageReady();
  }

  async fillContractDetails(details: {
    fee: string;
    description: string;
    property?: string;
  }) {
    if (details.property) {
      await this.propertyDropdown.click();
      await this.page.getByRole('option', { name: details.property }).click();
    }
    await this.contractFeeInput.fill(details.fee);
    await this.descriptionInput.fill(details.description);
  }

  async clickGenerate() {
    await this.generateButton.click();
    // Wait for the generation flow to complete
    await this.page.waitForResponse(
      resp => resp.url().includes('flow_docgen') && resp.status() === 200
    );
  }

  async getStatus(): Promise<string> {
    return await this.statusBadge.innerText();
  }
}
```

---

## Component Objects (For Shared UI Elements)

Reusable components that appear on multiple pages:

```typescript
// components/DataTable.ts
import { Page, Locator } from '@playwright/test';

export class DataTable {
  readonly container: Locator;

  constructor(page: Page, testId: string) {
    this.container = page.getByTestId(testId);
  }

  async getRowCount(): Promise<number> {
    return await this.container.getByRole('row').count() - 1; // minus header
  }

  getRow(name: string): Locator {
    return this.container.getByRole('row', { name });
  }

  async clickRow(name: string) {
    await this.getRow(name).click();
  }

  async isRowVisible(name: string): Promise<Locator> {
    return this.getRow(name);
  }
}
```

---

## Using Page Objects in Tests

Tests should read like plain-English workflows:

```typescript
// tests/contract-lifecycle.spec.ts
import { test, expect } from '@playwright/test';
import { ContractDetailPage } from '../pages/ContractDetailPage';

test('should generate Bancroft contract with all required fields', async ({ page }) => {
  const contractPage = new ContractDetailPage(page);

  await page.goto('/contracts/new');
  await contractPage.selectCustomer('Bancroft');
  await contractPage.selectMSA('MSA-2024-001');
  await contractPage.fillContractDetails({
    property: '1255 Caldwell Road',
    fee: '12500.00',
    description: 'Annual HVAC maintenance',
  });

  await contractPage.clickGenerate();
  await expect(contractPage.statusBadge).toHaveText('Generated');
});
```

---

## Rules

1. **Locators are properties, actions are methods.** Don't mix them.
2. **Page objects never contain assertions.** Assertions live in test files. Page objects return locators or data — tests verify them.
3. **One page object per screen or major section.** Don't create a god object for the whole app.
4. **Component objects for reusable widgets.** Modals, data tables, dropdowns, navigation — extract into components.
5. **Constructors take `Page` only.** No test data in constructors. Pass data through method arguments.
6. **Use fixtures to inject page objects** (see `fixtures-auth.md`) instead of instantiating in every test.
