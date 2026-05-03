# Locators — Choosing Stable Element Selectors

## Priority Order (Most Stable → Least Stable)

### Tier 1: Role-Based (Best)
```typescript
page.getByRole('button', { name: 'Submit' })
page.getByRole('heading', { level: 1 })
page.getByRole('link', { name: 'Dashboard' })
page.getByRole('textbox', { name: 'Email' })
page.getByRole('combobox', { name: 'State' })
page.getByRole('checkbox', { name: 'Remember me' })
page.getByRole('row', { name: /Invoice #1234/ })
```
Mirrors how real users and screen readers see the page. Survives CSS refactors, layout changes, and component library swaps.

### Tier 2: Test IDs (Stable Contract)
```typescript
page.getByTestId('customer-dropdown')
page.getByTestId('contract-fee-input')
page.getByTestId('generate-btn')
```
Requires devs to add `data-testid` attributes. These are an explicit contract between the app and the test suite. They don't break when visual design changes.

**Convention:** Use kebab-case. Name by purpose, not implementation: `data-testid="save-contract"` not `data-testid="blue-button-3"`.

### Tier 3: Content-Based (Good for Specific Cases)
```typescript
page.getByLabel('Contract Fee')        // form inputs with labels
page.getByPlaceholder('Search...')      // inputs with placeholder text
page.getByText('No results found')     // visible text content
page.getByAltText('Company logo')      // images
page.getByTitle('Close dialog')        // title attributes
```

### Tier 4: CSS Selectors (Use Sparingly)
```typescript
page.locator('[data-testid="x"]')      // acceptable — explicit test contract
page.locator('table >> nth=0')         // layout-dependent but sometimes necessary
```

### Tier 5: NEVER USE
```typescript
// All of these break constantly:
page.locator('.btn-primary')           // CSS class changes
page.locator('#auto-generated-id-47')  // dynamic IDs
page.locator('div > div > span:nth-child(3)') // structure dependent
page.locator('//div[@class="wrapper"]/ul/li[2]') // XPath, same problem
```

---

## Chaining and Filtering

Narrow down to the right element by chaining:
```typescript
// Find a row, then click its delete button
const row = page.getByRole('row', { name: 'Acme Corp' });
await row.getByRole('button', { name: 'Delete' }).click();
```

Filter by content or nested locator:
```typescript
// Find list items containing specific text
const item = page.getByRole('listitem').filter({ hasText: 'HVAC Maintenance' });

// Find rows that contain a specific status badge
const activeRows = page.getByRole('row').filter({
  has: page.getByText('Active')
});
```

---

## When Elements Aren't Unique

If `getByRole` matches multiple elements, narrow with chaining:
```typescript
// Multiple "Edit" buttons — scope to a specific section
const customerSection = page.getByTestId('customer-info');
await customerSection.getByRole('button', { name: 'Edit' }).click();
```

Use `.first()`, `.last()`, `.nth(n)` only as a last resort:
```typescript
// Avoid if possible, but sometimes necessary for lists
await page.getByRole('listitem').first().click();
```

---

## Generating Locators

Use Playwright's codegen to discover what locators work for a page:
```bash
npx playwright codegen https://your-site.com
```
This opens a browser + inspector. Click elements to see recommended locators. Codegen prioritizes role → text → testid automatically.

---

## Dynamic Content (Power Pages, SPAs)

For dynamically loaded content:
```typescript
// Wait for element to appear, THEN interact
const dropdown = page.getByRole('combobox', { name: 'Customer' });
await dropdown.waitFor({ state: 'visible' });
await dropdown.click();

// Wait for loading to finish
await expect(page.getByText('Loading...')).toBeHidden();
await page.getByRole('row').first().click();
```

For elements inside Shadow DOM (rare in Power Pages but common in web components):
```typescript
// Playwright pierces open Shadow DOM automatically
// No special handling needed for most cases
```

---

## Flagging Missing Test IDs

When writing tests and the app lacks `data-testid` attributes on key elements, include a comment:
```typescript
// TODO: Developer must add data-testid="contract-status-badge" to the status element
// Using text locator as fallback — fragile
await expect(page.getByText('Generated')).toBeVisible();
```
This becomes a task for the developer agent.
