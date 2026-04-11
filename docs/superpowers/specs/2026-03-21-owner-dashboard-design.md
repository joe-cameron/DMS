# Owner Dashboard — Design Spec

**Date:** 2026-03-21
**Screen:** SalesDashboard.jsx (redesign)
**Audience:** Owner, Administrator
**Route:** `/#/dashboard` (existing)

---

## Overview

Single-screen command center for the business owner. Top half shows KPI cards with drill-down detail strips. Bottom half is the Document Approval Queue — the primary workflow for reviewing, approving, and dispatching generated contracts, proposals, and MSAs.

---

## Layout

```
┌─────────────────────────────────────────────────────────┐
│  Dashboard                                              │
├───────┬───────┬───────┬───────┬───────┤                 │
│ Sales │Contracts│Onboard│SendQ │Alerts │  ← 5 KPI cards │
├───────┴───────┴───────┴───────┴───────┤                 │
│  Detail Strip (3 columns, persistent) │  ← swaps on    │
│  Links navigate to full screens       │     card click  │
├───────────────────────────────────────┤                 │
│  Document Approval Queue             │  ← primary      │
│  [All] [Sales] [Operations]           │     workflow    │
│  Pending | Approved | Returned        │                 │
│  ┌──┬────────┬────┬────┬────┬────────┐│                 │
│  │# │Document│Type│Cust│Date│Actions ││                 │
│  ├──┼────────┼────┼────┼────┼────────┤│                 │
│  │  │        │    │    │    │✓?↩✕📄 ││                 │
│  └──┴────────┴────┴────┴────┴────────┘│                 │
├───────────────────────────────────────┤                 │
│                              [🔍]     │  ← floating FAB │
└───────────────────────────────────────┘
```

---

## 1. KPI Cards (5 across)

Cards are compact (105px height). Clicking a card swaps the detail strip content below. Active card has a green bottom border. No open/close cycle — strip stays persistent.

### 1.1 Sales
- **Main metric:** Active pipeline dollar value
- **Sub-metrics:** Proposals count, New customers (month), Monthly revenue
- **Drill-down strip columns:**
  - Active Proposals (name, value, status badge, link to contract/MSA detail)
  - New Customers this month (name, date added, link to customer detail)
  - Revenue summary (monthly + Q/YTD)

### 1.2 Contracts
- **Main metric:** Active contract count
- **Sub-metrics:** Draft, Sent, Signed counts
- **Drill-down strip columns:**
  - Awaiting signature (name, days since sent, link)
  - Recently generated (name, type, date, link)
  - By status (summary counts)

### 1.3 Onboarding
- **Main metric:** Active case count
- **Sub-metrics:** Go-Live pending, In Progress, New (business metrics only — no IT/system alerts)
- **Drill-down strip columns:**
  - Go-Live Pending (name, target date, on-track/at-risk badge)
  - In Progress (name, current phase)
  - New (name, phase)

### 1.4 Send Queue
- **Main metric:** Pending delivery count
- **Sub-metrics:** Today, This week
- **Drill-down strip columns:**
  - Today (name, type)
  - This week (name, type, date)
  - Recently sent (name, type, date sent)

### 1.5 Alerts
- **Main metric:** Total items needing attention
- **Sub-metrics:** MSA expiring, Insurance expiring, Unsigned contracts
- **Drill-down strip columns:**
  - Expiring MSAs — each with ✉ Renew button → email modal
  - Expiring Vendor Insurance — each with ✉ Request button → email modal
  - Unsigned Contracts — each clickable → navigates to contract detail
- **Actioned items** show: "✓ Sent Mar 19 · Remind Mar 26" with muted styling
- **No IT/system alerts** on this card

---

## 2. Detail Strip

Persistent panel below the KPI cards. Content swaps instantly when clicking a different card.

### Behavior
- **Default:** Shows Sales strip on page load
- **Click card:** Strip content swaps (no animation delay, instant)
- **Minimize:** Toggle button (▼) collapses strip to zero height
- **Max height:** 260px with scroll
- **Layout:** 3-column grid with section titles

### Item interactions
- **Clickable names** → navigate to full detail screen (HashRouter link)
- **Alert action buttons** → open centered email modal
- **No side panels** — avoids repetitive wrist motion

---

## 3. Alert Email Actions

### Email Modal (centered overlay)
- **Fields:** To (pre-filled), Subject (pre-filled), Message (editable textarea)
- **Footer:** Reminder checkbox + days selector (7/14/30) | Cancel + Send buttons
- **Templates:**
  - **MSA Renewal:** Canned renewal request to client contact
  - **Insurance Request:** Canned certificate request to vendor contact
  - **Request Info:** Blank body for internal team communication

### After sending
- Alert item transitions to actioned state (muted, no action button)
- Shows: "✓ Sent [date] · Remind [date]"
- Reminder creates a follow-up alert on the specified date

### Data flow
- Email sent via `createDocumentRequest()`:
  ```js
  createDocumentRequest({
    requestType: DocRequestType.Email,       // 100000001
    name: 'MSA Renewal — Bancroft Madison',
    requestedBy: user.email,
    notes: JSON.stringify({
      to: 'client@example.com',
      subject: 'MSA Renewal — Bancroft Madison',
      body: '...(editable text from modal)...',
      sourceEntity: 'dcfg_msa',
      sourceRecordId: msaId
    })
  })
  ```
- Reminder: creates a second `dcfg_document_request` with type=Email, `dcfg_scheduled_date` set to reminder date (new column needed on `dcfg_document_request` — Date type)
- Sent status: PATCH source record (MSA → `dcfg_renewal_email_sent` or Vendor → `dcfg_insurance_request_sent`) with date. Display on alert item.

### Reminder prerequisite
- New column: `dcfg_scheduled_date` (Date) on `dcfg_document_request`
- Scheduled flow checks daily for requests where `dcfg_scheduled_date = today` and `dcfg_status = Pending`

---

## 4. Document Approval Queue

The primary function of this screen. Owner reviews generated documents and takes action.

### 4.1 Document Types and Picklist Mapping

| Category | Document Type | `dcfg_document_type` value | Source |
|---|---|---|---|
| **Sales** | Proposal | 100000003 | NewProposalWizard |
| **Sales** | Customer MSA | 100000002 | Proposal approval converts |
| **Operations** | Work Order | 100000000 | NewContractWizard |
| **Operations** | Work Order Amendment | 100000001 | NewContractWizard |
| **Operations** | Vendor MSA | 100000002 | NewContractWizard |
| **Operations** | Exhibit (A, C) | via `dcfg_exhibit_type` | Template-driven |

**Distinguishing Customer MSA vs Vendor MSA:** Both use `dcfg_document_type = 100000002`. Differentiate by `dcfg_contract_family`: Decades (100000001) = Customer/Sales, Bancroft (100000000) = Vendor/Operations.

**Exhibit documents:** Exhibit A and Exhibit C are generated as part of a contract but appear separately in the queue. Identified by `dcfg_exhibit_type` on the template. Exhibits fall under Operations.

TPA work uses the same Operations document types — filtered by customer relationship, not document type.

### 4.2 Filter Bar

```
[All] [Sales] [Operations]
```

- **All:** No filter, shows all document types
- **Sales:** `dcfg_document_type eq 100000003` (Proposal) OR (`dcfg_document_type eq 100000002` AND `dcfg_contract_family eq 100000001`) (Customer MSA / Decades family)
- **Operations:** `dcfg_document_type eq 100000000` (WO) OR `dcfg_document_type eq 100000001` (Amendment) OR (`dcfg_document_type eq 100000002` AND `dcfg_contract_family eq 100000000`) (Vendor MSA / Bancroft family)
- Active filter has green background
- Filter persists across tab changes
- Filter applied client-side (data already loaded)

### 4.3 Status Tabs

```
Pending Review (5) | Approved (12) | Returned (2)
```

- Counts shown in tab badges
- **Pending:** Documents awaiting owner review (Generated status)
- **Approved:** Owner approved, moved to Send Queue
- **Returned:** Sent back for revision

### 4.4 Table Columns

| Column | Content |
|---|---|
| # | Row number |
| Document | Name (clickable → navigates to detail) |
| Type | Badge: Work Order, Amendment, MSA, Proposal, Exhibit |
| Customer / Vendor | Customer name + vendor name below |
| Generated | Date generated |
| Status | Badge: Generated, Approved, Returned |
| Actions | Action buttons |

### 4.5 Action Buttons (Pending tab only)

| Button | Label | Behavior |
|---|---|---|
| ✓ Approve | Green | Confirm dialog → moves to Approved tab + Send Queue |
| ? Info | Blue outline | Opens email modal (Request More Information) |
| ↩ Return | Orange outline | Confirm dialog → moves to Returned tab |
| ✕ Delete | Red outline | Confirm dialog (destructive) → soft deletes document |
| 📄 Open | Gray outline | Opens document in Word via SharePoint URL |

### 4.6 Action Buttons (Approved/Returned tabs)

| Button | Label |
|---|---|
| 📄 Open | Opens document in Word |

### 4.7 Confirmation Dialogs

Centered modal with title, message, Cancel + Confirm buttons. Delete confirmation uses red button.

### 4.8 Data Flow

- **Source:** `dcfg_document_outputs` filtered by `dcfg_approval_status`
  - Pending tab: `dcfg_approval_status eq 100000000`
  - Approved tab: `dcfg_approval_status eq 100000001`
  - Returned tab: `dcfg_approval_status eq 100000002`
- **Approve:** PATCH `dcfg_document_outputs(id)` → `dcfg_approval_status = 100000001`, write audit log (action=Approved)
- **Return:** PATCH `dcfg_document_outputs(id)` → `dcfg_approval_status = 100000002`, write audit log (action=Returned)
- **Delete:** PATCH `dcfg_document_outputs(id)` → `dcfg_active_flag = false` (soft delete), write audit log
- **Open:** `window.open(dcfg_output_file_url)` → opens SharePoint document in Word Online
- **Note:** Approve does NOT change contract status or write to `dcfg_send_queues`. Contract status changes happen separately on the SendQueue screen.

---

## 5. Document Search (Floating)

### Trigger
- **FAB button:** Bottom-right corner (🔍), 44px circle, green
- **Keyboard:** Ctrl+K / Cmd+K

### Search Modal (centered overlay)
- Search input with placeholder: "Search contracts, MSAs, documents..."
- Results list below, max 380px scroll
- Each result shows: type badge, document name, date
- Click result → navigates to detail screen
- Esc closes

### Search Scope
- `dcfg_contracts` — by name, client name, contractor name
- `dcfg_msas` — by name
- `dcfg_document_outputs` — by name, output file URL
- `dcfg_document_templates` — by name
- `dcfg_location_documents` — by name (compliance docs)

---

## 6. Data Queries

### KPI Cards (on page load, parallel fetch)
```
# Sales — pipeline + revenue
GET /dcfg_contracts?$select=dcfg_contractid,dcfg_status,dcfg_contract_fee,dcfg_contract_date,
    dcfg_client_name,_dcfg_customer_id_value,_dcfg_msa_id_value
    &$filter=dcfg_status lt 100000004

# Revenue calculation: SUM(dcfg_contract_fee) WHERE dcfg_contract_date in current month
# Pipeline: SUM(dcfg_contract_fee) WHERE dcfg_status lt 100000003 (Draft/Generated/Sent)

# New customers (last 30 days)
GET /dcfg_customers?$select=dcfg_customerid,dcfg_name&$filter=createdon gt {30d ago ISO date}

# MSAs (for expiration alerts)
GET /dcfg_msas?$select=dcfg_msaid,dcfg_name,dcfg_expiration_date,
    _dcfg_customer_id_value,_dcfg_vendor_id_value

# Onboarding (active cases)
GET /dcfg_onboarding_cases?$select=dcfg_onboarding_caseid,dcfg_name,dcfg_status,
    dcfg_initiated_date,dcfg_target_go_live_date,_dcfg_customer_id_value
    &$filter=dcfg_status lt 100000005

# Send queue (pending)
GET /dcfg_send_queues?$select=dcfg_send_queueid,dcfg_queue_status,dcfg_added_to_queue_date
    &$filter=dcfg_queue_status eq 100000000

# Vendors (insurance expiry for alerts)
GET /dcfg_vendors?$select=dcfg_vendorid,dcfg_display_name,dcfg_insurance_expiry
    &$filter=dcfg_insurance_expiry ne null
```

### Document Approval Queue
```
GET /dcfg_document_outputs?$select=dcfg_name,dcfg_output_file_url,dcfg_source_entity,
    dcfg_source_record_id,dcfg_generated_at,dcfg_approval_status,dcfg_active_flag,
    dcfg_template_version,_dcfg_template_id_value
    &$filter=dcfg_active_flag eq true
    &$orderby=dcfg_generated_at desc
```

Client-side: for each output, look up the source contract/MSA from the already-fetched KPI data to get customer/vendor names and document type. No additional queries needed.

### Document Search (300ms debounce, case-insensitive)
```
# Parallel queries, $top=10 each, merge + sort by date
GET /dcfg_contracts?$filter=contains(dcfg_client_name,'{query}')&$select=dcfg_contractid,dcfg_client_name,dcfg_status&$top=10
GET /dcfg_msas?$filter=contains(dcfg_name,'{query}')&$select=dcfg_msaid,dcfg_name&$top=10
GET /dcfg_document_outputs?$filter=contains(dcfg_name,'{query}')&$select=dcfg_name,dcfg_output_file_url,dcfg_generated_at&$top=10
```

---

## 7. Component Structure

```
SalesDashboard.jsx (redesign)
├── KpiCard.jsx (×5, reusable)
├── DetailStrip.jsx
│   ├── SalesStrip.jsx
│   ├── ContractsStrip.jsx
│   ├── OnboardingStrip.jsx
│   ├── SendQueueStrip.jsx
│   └── AlertsStrip.jsx
│       └── AlertEmailModal.jsx
├── ApprovalQueue.jsx
│   ├── QueueFilterBar.jsx
│   ├── QueueTable.jsx
│   ├── QueueRow.jsx
│   ├── ConfirmDialog.jsx
│   └── RequestInfoModal.jsx (reuses AlertEmailModal)
└── DocSearchModal.jsx
```

### File size management
- SalesDashboard.jsx: orchestrator only (~150 lines)
- Each strip: ~80-120 lines
- ApprovalQueue.jsx: ~200 lines
- Each sub-component: ~50-100 lines
- Total: ~1200 lines across 12 files (manageable)

---

## 8. Prerequisites — Schema Changes Required

### 8.1 New picklist value: `dcfg_document_type` on `dcfg_document_template`

Add `Proposal = 100000003` to the `dcfg_document_type` choice. Current values:
- WorkOrder = 100000000
- Amendment = 100000001
- ContractorMSA = 100000002
- **Proposal = 100000003** (NEW)

### 8.2 New column: `dcfg_approval_status` on `dcfg_document_output`

New Choice column to track owner approval independently from contract lifecycle:
- Pending = 100000000
- Approved = 100000001
- Returned = 100000002

This avoids conflating "owner approved" with `ContractStatus.Sent` (which means "sent to client for signature" in SendQueue.jsx).

### 8.3 New column: `dcfg_insurance_expiry` on `dcfg_vendor`

Date column. Required for the Alerts card "Expiring Vendor Insurance" feature. Must be deployed to staging and prod before implementation.

### 8.4 Approval → Send Queue relationship

**Approve does NOT write to `dcfg_send_queues`.** Approve sets `dcfg_document_output.dcfg_approval_status = Approved`. The existing SendQueue.jsx reads contracts by `ContractStatus` — the owner separately changes contract status to `Sent` from the SendQueue screen when actually dispatching. Approval and dispatch are distinct steps.

### 8.5 No New Tables Required

All data comes from existing tables:
- `dcfg_contracts` — contract status, customer/vendor lookups
- `dcfg_msas` — expiration dates, customer/vendor
- `dcfg_document_outputs` — generated documents
- `dcfg_document_requests` — email triggers
- `dcfg_send_queues` — delivery queue
- `dcfg_onboarding_cases` — case status
- `dcfg_vendors` — insurance expiry
- `dcfg_audit_logs` — action logging
- `dcfg_configs` — config values

### New columns needed
- `dcfg_vendor.dcfg_insurance_expiry` — Date, if not already present
- `dcfg_document_output.dcfg_approval_status` — Choice (Pending/Approved/Returned), if approval state tracked separately from contract status

---

## 9. Loading and Error States

- **Initial load:** Skeleton placeholders for all 5 KPI cards (gray boxes) + "Loading..." in strip and queue
- **Partial failure:** If one query fails (e.g., onboarding), show error text in that KPI card only. Other cards render normally. Toast with error detail.
- **Queue loading:** Skeleton rows in table while fetching document outputs
- **Search:** "Searching..." placeholder while debounced query runs

## 10. Responsive Behavior

Desktop-first. Minimum viewport: 1200px. Below that:
- KPI cards: wrap to 3+2 layout
- Detail strip: 2 columns instead of 3
- Queue table: horizontal scroll
- No mobile optimization (iPad landscape minimum)

## 11. Quick Actions

Preserve the existing quick action buttons from current SalesDashboard, placed in the dashboard header row:
- New Customer → `/#/customers` (with new panel open)
- New Contract → `/#/contracts/new`
- New Proposal → `/#/proposals/new`
- Start Onboarding → `/#/onboarding` (with new panel open)

Compact button bar, right-aligned next to "Dashboard" title.

## 12. Mockup Reference

Interactive HTML mockup: `C:\DCFG\dashboard_mockup.html`
