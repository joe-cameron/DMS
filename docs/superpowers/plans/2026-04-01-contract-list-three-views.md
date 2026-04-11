# Contract List — Three Production Views Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current single ContractsList.jsx (866-line split-pane) with three switchable production-ready views: Smart List (expandable rows), Customer Groups, and Split View (queue + search). Management picks their favorite by using the live system.

**Architecture:** One parent component (`ContractsList.jsx`) handles data loading, view switching (localStorage-persisted), and the "+ New Contract" action. Three child view components each receive the same data props and render their own layout. Shared hooks for search, sort, pagination. Server-side pagination via `$skip/$top` for 1000s of records.

**Tech Stack:** React 16.14 (classic JSX), inline styles (project pattern), portalApi.js, useTableControls.jsx, data-testid on all elements.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/ContractsList.jsx` | Rewrite | Parent: data loading, view switcher, shared state |
| `src/contracts/ViewSmartList.jsx` | Create | Option A: table with expandable inline detail rows |
| `src/contracts/ViewCustomerGroups.jsx` | Create | Option B: contracts grouped by customer, collapsible |
| `src/contracts/ViewSplitPanel.jsx` | Create | Option C: left queue + right search split |
| `src/contracts/ContractRowDetail.jsx` | Create | Shared: inline detail panel (contractor, vendor, location, doc link, actions) |
| `src/contracts/useContractData.jsx` | Create | Shared hook: fetch contracts, KPI counts, pagination, search |
| `src/AppRouter.jsx` | No change | Route already points to ContractsList |
| `src/portalApi.js` | Minor edit | Add server-side paginated fetch function |

## Chunk 1: Data Layer + Shared Components

### Task 1: Add paginated fetch to portalApi.js

**Files:**
- Modify: `src/portalApi.js`

- [ ] **Step 1: Add fetchContractsPaginated function**

After the existing `fetchContracts` function (~line 316), add:

```javascript
export function fetchContractsPaginated(skip = 0, top = 50, filter = '') {
  const baseFilter = 'dcfg_active_flag eq true';
  const fullFilter = filter ? `${baseFilter} and ${filter}` : baseFilter;
  return apiGet(`/${EntitySets.contracts}?$filter=${fullFilter}&$select=dcfg_contractid,dcfg_contract_number,dcfg_status,dcfg_contract_fee,dcfg_contract_date,dcfg_contractor_legal_name,dcfg_client_name,dcfg_contract_type,dcfg_document_url,dcfg_created_by_email,dcfg_signer_printed,dcfg_sent_date,dcfg_signed_date,_dcfg_property_id_value,_dcfg_vendor_id_value,_dcfg_program_id_value&$expand=dcfg_msa_id($select=dcfg_name,dcfg_contract_family;$expand=dcfg_customer_id($select=dcfg_customerid,dcfg_name)),dcfg_vendor_id($select=dcfg_vendorid,dcfg_legal_name,dcfg_display_name),dcfg_property_id($select=dcfg_propertyid,dcfg_name,dcfg_address,dcfg_city,dcfg_state),dcfg_program_id($select=dcfg_programid,dcfg_name)&$orderby=dcfg_contract_date desc&$count=true&$skip=${skip}&$top=${top}`);
}
```

- [ ] **Step 2: Verify build**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`

### Task 2: Create useContractData hook

**Files:**
- Create: `src/contracts/useContractData.jsx`

- [ ] **Step 1: Create the contracts directory**

```bash
mkdir -p C:\DCFG\spa\dcfg-shell\src\contracts
```

- [ ] **Step 2: Write the hook**

```javascript
/**
 * useContractData.jsx — Shared data hook for all three contract views.
 * Handles: fetch, pagination, search, "needs attention" filter, KPI counts.
 */
import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  ContractStatus, fetchContractsPaginated,
  fetchActiveContracts, fetchPendingSignatures,
} from '../portalApi';

const PAGE_SIZE = 50;

// "Needs attention" = not signed, not closed, not void, not declined
const ATTENTION_STATUSES = [
  ContractStatus.WIP, ContractStatus.Draft, ContractStatus.Generated,
  ContractStatus.PendingApproval, ContractStatus.Sent,
];

export function useContractData(userEmail) {
  const [contracts, setContracts] = useState([]);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const [viewMode, setViewMode] = useState('attention'); // 'attention' | 'all'
  const [searchTerm, setSearchTerm] = useState('');

  const buildFilter = useCallback(() => {
    const parts = [];
    if (viewMode === 'attention') {
      const statusFilter = ATTENTION_STATUSES.map(s => `dcfg_status eq ${s}`).join(' or ');
      parts.push(`(${statusFilter})`);
    }
    if (searchTerm.trim()) {
      const t = searchTerm.trim().replace(/'/g, "''");
      parts.push(`(contains(dcfg_client_name,'${t}') or contains(dcfg_contract_number,'${t}'))`);
    }
    return parts.join(' and ');
  }, [viewMode, searchTerm]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const filter = buildFilter();
      const r = await fetchContractsPaginated(page * PAGE_SIZE, PAGE_SIZE, filter);
      setContracts(r?.value ?? []);
      setTotalCount(r?.['@odata.count'] ?? r?.value?.length ?? 0);
    } catch (e) {
      console.error('Contract load failed:', e);
      setContracts([]);
    }
    setLoading(false);
  }, [page, buildFilter]);

  useEffect(() => { load(); }, [load]);

  // Reset page when filters change
  useEffect(() => { setPage(0); }, [viewMode, searchTerm]);

  // Group by customer for Option B
  const grouped = useMemo(() => {
    const map = {};
    for (const c of contracts) {
      const custName = c.dcfg_msa_id?.dcfg_customer_id?.dcfg_name || c.dcfg_client_name || 'Unknown';
      const custId = c.dcfg_msa_id?.dcfg_customer_id?.dcfg_customerid || custName;
      if (!map[custId]) map[custId] = { name: custName, contracts: [] };
      map[custId].contracts.push(c);
    }
    return Object.values(map).sort((a, b) => a.name.localeCompare(b.name));
  }, [contracts]);

  const totalPages = Math.ceil(totalCount / PAGE_SIZE);

  return {
    contracts, grouped, loading, totalCount,
    page, setPage, totalPages,
    viewMode, setViewMode,
    searchTerm, setSearchTerm,
    refresh: load,
  };
}
```

- [ ] **Step 3: Verify build**

### Task 3: Create ContractRowDetail (shared inline detail)

**Files:**
- Create: `src/contracts/ContractRowDetail.jsx`

- [ ] **Step 1: Write the component**

Inline detail panel showing: contractor, vendor, location, sent/signed dates, document link, and action buttons (Open Full Detail, Mark as Signed). Used by Option A (expandable rows) and Option C (search results).

```javascript
/**
 * ContractRowDetail.jsx — Inline detail panel for a contract row.
 * Shows key fields + document link + actions without navigating away.
 */
import React from 'react';
import { useNavigate } from 'react-router-dom';
import { ContractStatus, ContractStatusLabel, formatCurrency, formatDate } from '../portalApi';
import Fn from '../FieldName.jsx';

// Design tokens
const T = {
  navy: '#0f2b46', border: '#e2e8f0', text3: '#94a3b8',
  blue: '#2563eb', blueLt: '#dbeafe', radius: 10,
};

const labelStyle = { fontSize: 10, fontWeight: 700, textTransform: 'uppercase', letterSpacing: 0.8, color: T.text3, marginBottom: 3 };
const valueStyle = { fontSize: 13, color: '#1a2332' };
const btnStyle = { background: '#fff', color: T.navy, border: `1px solid ${T.border}`, borderRadius: 6, padding: '7px 14px', fontSize: 12, fontWeight: 600, cursor: 'pointer' };
const docLinkStyle = { display: 'inline-flex', alignItems: 'center', gap: 4, color: T.blue, fontSize: 12, fontWeight: 600, textDecoration: 'none', padding: '4px 10px', borderRadius: 6, background: T.blueLt };

export default function ContractRowDetail({ contract, onAction }) {
  const navigate = useNavigate();
  const c = contract;
  const vendor = c.dcfg_vendor_id?.dcfg_display_name || c.dcfg_vendor_id?.dcfg_legal_name || '—';
  const location = c.dcfg_property_id ? `${c.dcfg_property_id.dcfg_name || c.dcfg_property_id.dcfg_address || ''}, ${c.dcfg_property_id.dcfg_city || ''} ${c.dcfg_property_id.dcfg_state || ''}`.trim().replace(/^,\s*/, '') : '—';
  const program = c.dcfg_program_id?.dcfg_name || '—';

  return React.createElement('div', {
    'data-testid': 'contract-row-detail',
    style: { display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 14, padding: '16px 20px', background: '#fff', borderTop: `1px solid ${T.border}` }
  },
    React.createElement('div', null,
      React.createElement('div', { style: labelStyle }, React.createElement(Fn, { f: 'dcfg_contractor_legal_name' }, 'Contractor')),
      React.createElement('div', { style: valueStyle }, c.dcfg_contractor_legal_name || 'Decades Contracting Group')),
    React.createElement('div', null,
      React.createElement('div', { style: labelStyle }, React.createElement(Fn, { f: 'dcfg_vendor_id' }, 'Vendor')),
      React.createElement('div', { style: valueStyle }, vendor)),
    React.createElement('div', null,
      React.createElement('div', { style: labelStyle }, React.createElement(Fn, { f: 'dcfg_property_id' }, 'Location')),
      React.createElement('div', { style: valueStyle }, location)),
    React.createElement('div', null,
      React.createElement('div', { style: labelStyle }, React.createElement(Fn, { f: 'dcfg_program_id' }, 'Program')),
      React.createElement('div', { style: valueStyle }, program)),
    React.createElement('div', null,
      React.createElement('div', { style: labelStyle }, 'Sent / Signed'),
      React.createElement('div', { style: valueStyle }, `${c.dcfg_sent_date ? formatDate(c.dcfg_sent_date) : '—'} / ${c.dcfg_signed_date ? formatDate(c.dcfg_signed_date) : '—'}`)),
    React.createElement('div', null,
      React.createElement('div', { style: labelStyle }, 'Document'),
      c.dcfg_document_url
        ? React.createElement('a', { href: c.dcfg_document_url, target: '_blank', rel: 'noopener', style: docLinkStyle, 'data-testid': 'contract-doc-link' }, '\uD83D\uDCC4 View Document')
        : React.createElement('span', { style: { fontSize: 13, color: T.text3 } }, '—')),
    React.createElement('div', {
      style: { gridColumn: '1 / -1', display: 'flex', gap: 8, paddingTop: 12, borderTop: `1px solid ${T.border}` }
    },
      React.createElement('button', {
        style: btnStyle, 'data-testid': 'btn-open-detail',
        onClick: (e) => { e.stopPropagation(); navigate(`/contracts/${c.dcfg_contractid}`); }
      }, 'Open Full Detail'),
      (c.dcfg_status === ContractStatus.SignedReceived || c.dcfg_status === ContractStatus.Closed) &&
      React.createElement('button', {
        style: btnStyle, 'data-testid': 'btn-create-amendment',
        onClick: (e) => { e.stopPropagation(); navigate(`/contracts/new?type=amendment&parent=${c.dcfg_contractid}`); }
      }, '+ Amendment'),
    )
  );
}
```

- [ ] **Step 2: Verify build**

## Chunk 2: Three View Components

### Task 4: Create ViewSmartList (Option A)

**Files:**
- Create: `src/contracts/ViewSmartList.jsx`

- [ ] **Step 1: Write the component**

Table layout with sortable columns. Clicking a row expands/collapses an inline `ContractRowDetail`. Columns: Contract #, Customer, Program, Status, Fee, Date, expand chevron. Pagination at bottom.

Key behaviors:
- Only one row expanded at a time
- Expanded row has highlighted background
- Chevron rotates on expand
- All elements have data-testid with `sl-` prefix (smart list)
- Document link visible in expanded detail without opening full page

~150 lines. Uses `useTableControls` for client-side sort within the page of server-side results.

- [ ] **Step 2: Verify build**

### Task 5: Create ViewCustomerGroups (Option B)

**Files:**
- Create: `src/contracts/ViewCustomerGroups.jsx`

- [ ] **Step 1: Write the component**

Uses `grouped` from `useContractData`. Each customer renders as a collapsible section with a navy header bar showing customer name and contract count. Contracts listed inside as a compact grid row with: contract #, program label, description, status badge, fee, date, doc link icon.

Key behaviors:
- All groups expanded by default
- Click header to collapse/expand
- Doc link icon inline per row (visible when document_url exists)
- Click contract row to navigate to detail
- All elements have data-testid with `cg-` prefix (customer groups)

~120 lines.

- [ ] **Step 2: Verify build**

### Task 6: Create ViewSplitPanel (Option C)

**Files:**
- Create: `src/contracts/ViewSplitPanel.jsx`

- [ ] **Step 1: Write the component**

Two-column layout (50/50). Left: "Needs Attention" queue — card-based list of contracts with status ≠ signed/closed/void/declined. Always visible, auto-refreshes. Right: search panel — empty until user types, then shows matching contracts as cards from server-side search. Both panels show: contract #, customer — program, status badge, fee, date, doc link.

Key behaviors:
- Left panel always shows attention items regardless of search
- Right panel searches ALL contracts (including signed, closed, voided)
- Cards are compact: 3 lines (number+status, customer—program, meta)
- Doc link visible inline on cards
- Click card to navigate to detail
- All elements have data-testid with `sp-` prefix (split panel)

~160 lines.

- [ ] **Step 2: Verify build**

## Chunk 3: Parent Component + Wiring

### Task 7: Rewrite ContractsList.jsx (parent)

**Files:**
- Rewrite: `src/ContractsList.jsx`

- [ ] **Step 1: Write the new parent component**

The parent handles:
1. View switching: A/B/C toggle buttons in toolbar, persisted to localStorage key `dcfg-contract-view`
2. Data loading via `useContractData` hook
3. "+ New Contract" button
4. "Needs Attention" / "All Active" toggle (passed to hook)
5. Search bar (passed to hook)
6. Renders the selected view component, passing data as props

View components receive these props:
- `contracts` — array of contract records
- `grouped` — customer-grouped structure (for Option B)
- `loading` — boolean
- `totalCount`, `page`, `setPage`, `totalPages` — pagination
- `onAction` — callback for inline actions (mark signed, etc.)
- `searchTerm`, `setSearchTerm` — for Option C's dedicated search

Toolbar layout:
```
[Contracts]    [View: A | B | C]  [Needs Attention | All Active]  [Search...]  [+ New ▾]
                                                                                  ├─ Work Order
                                                                                  ├─ Amendment
                                                                                  └─ Vendor MSA
```

The "+ New" button is a dropdown with three options:
- **Work Order** → `navigate('/contracts/new')` (default type)
- **Amendment** → `navigate('/contracts/new?type=amendment')`
- **Vendor MSA** → `navigate('/contracts/new?type=msa')`

Dropdown toggles on click, closes on blur or selection. Each option has `data-testid`: `btn-new-workorder`, `btn-new-amendment`, `btn-new-vendor-msa`.

Additionally, the inline detail panel (`ContractRowDetail`) must include a "Create Amendment" action button for contracts with status Signed/Received or later, navigating to `/contracts/new?type=amendment&parent={contractId}`.

~140 lines. Dramatically simpler than the current 866-line split-pane.

- [ ] **Step 2: Verify build**

- [ ] **Step 3: Test in browser**

Navigate to `/#/contracts`. Verify:
- View toggle switches between A, B, C
- Default view loads "Needs Attention" contracts
- "All Active" shows more results
- Search filters results
- Pagination works
- Row expand (A) / customer collapse (B) / split search (C) all functional
- Document links visible and clickable
- "+ New Contract" navigates to wizard

### Task 8: Update E2E test selectors

**Files:**
- Modify: `C:\DCFG\spa\dcfg-playwright\tests\full-e2e-review.spec.ts`

- [ ] **Step 1: Update TC4 contract list selectors**

The test currently uses `contracts-search`, `contracts-btn-new`, `contracts-row`. Update to match new data-testid values. Add view switcher interaction — test should click through all 3 views and screenshot each.

- [ ] **Step 2: Verify test compiles**

### Task 9: Build and deploy to Test

- [ ] **Step 1: Build**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

- [ ] **Step 2: Deploy**

```bash
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 3: Clear cache + provide launch URLs**

Clear: `https://dcfg.powerappsportals.com/_services/about?clearCache=true`
Launch: `https://dcfg.powerappsportals.com/#/contracts`
