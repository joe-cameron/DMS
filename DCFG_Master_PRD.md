# DCFG Contracting Suite — Master PRD
**Version:** 2.0 — Post-Build Reconciliation  
**Solution:** DCFGContractingSuite v1.0.0.20  
**Date:** March 12, 2026  
**Org:** org0c17e98d.crm.dynamics.com  
**Portal:** https://dcfg.powerappsportals.com  

---

## 1. Product Overview

The DCFG Contracting Suite is a Power Pages SPA for managing construction contracts, MSA proposals, property locations, onboarding, and document generation across the Decades Construction Group portfolio. It serves internal staff (sales, contracts, operations, executive) through a single React application deployed via PAC CLI.

**Architecture:** Single React SPA (`dcfg-shell`) using React Router v6, Vite build, React 16.14 (classic JSX runtime), deployed to Power Pages. Data layer is Dataverse Web API via portal `/_api/` endpoint. Document generation via Power Automate HTTP flows.

---

## 2. Environment

| Item | Value |
|------|-------|
| Org URL | https://org0c17e98d.crm.dynamics.com |
| Portal URL | https://dcfg.powerappsportals.com |
| Portal Site ID | a150bd53-7fbc-423d-a1ad-dd653ab4c435 |
| PAC Site ID | 22947376-be10-4bda-a90f-32b855c43045 |
| Solution Name | DCFGContractingSuite |
| Solution Version | 1.0.0.20 |
| Data Model | Enhanced (EDM — no adx_* tables) |
| SPA Root | C:\dcfg\spa\dcfg-shell\ |
| Deploy Command | `pac pages upload-code-site --rootPath . --compiledPath dist --siteName "DCFG Contracting Suite - dcfg"` |
| React Version | 16.14.0 (classic JSX runtime required) |
| Vite | 5.4.21 with `jsxRuntime: 'classic'` |
| Cache Clear | https://dcfg.powerappsportals.com/_services/about?clearCache=true |

---

## 3. User Roles

| Role | Can Do |
|------|--------|
| DCFG_Admin | Full access including Void, configuration |
| DCFG_Manager | All actions except admin configuration |
| DCFG_Sales | Proposals, customers |
| DCFG_Contracts | Contracts, approvals, send queue |
| DCFG_Operations | Onboarding, locations |

Role enforcement: restricted actions removed from DOM entirely (never disabled/hidden).

---

## 4. Navigation Structure

**Left NavPanel (220px sticky sidebar):**

| Section | Item | Route | Screen |
|---------|------|-------|--------|
| — | Dashboard | / or /dashboard | Sales Dashboard |
| SALES | Customers | /customers | Customer List |
| SALES | New Proposal | /proposals/new | New Customer Proposal Wizard (4-step, Decades only) |
| CONTRACTS | MSAs | /msas | MSA List |
| CONTRACTS | Contracts | /contracts | Contracts Split-Pane |
| CONTRACTS | New Contract | /contracts/new | New Contract Wizard (5-step) |
| CONTRACTS | Send Queue | /send-queue | Contract Delivery Queue |
| OPERATIONS | Locations | /locations | Location List (desktop) |
| OPERATIONS | Field Ops | /field | Location Manager (mobile) |

Additional drill-down routes (not in nav): `/customers/:id`, `/msas/:id`, `/locations/:id`

---

## 5. Screen Specifications

### 5.1 Sales Dashboard (`/dashboard`)
**File:** `screens/SalesDashboard.jsx` (existing v1.0)  
**Status:** Working  
KPI tiles: Active Contracts, Pending Signatures, Contracts This Month, Budget Warnings. Contract Pipeline chart, Budget Health summary, Recent Activity feed. All read-only Dataverse queries.

### 5.2 Customer List (`/customers`)
**File:** `screens/CustomerList.jsx` (existing v1.0)  
**Status:** Working  
Searchable table of `dcfg_customers`. Shows name, primary contact, status, last modified. Click drills to Customer Detail. **Missing:** No "Add Customer" button.

### 5.3 Customer Detail (`/customers/:id`)
**File:** `screens/CustomerDetail.jsx` (existing v1.0)  
**Status:** Working  
Customer info, locations list, MSAs, contracts, onboarding cases. Can create new MSA proposal and new onboarding case from this screen.

### 5.4 New Customer Proposal Wizard (`/proposals/new`)
**File:** `NewProposalWizard.jsx` (new — this session)  
**Status:** Built, needs schema reconciliation + Bancroft filter  
**Decades customers only.** Bancroft customers do not receive package proposals.  
4-step wizard: Package Selection (A/B/C) → Customer & Vendor → Pricing & Locations → Review & Generate. Calls `flow_docgen` on generate. Must filter customer list to Decades family only (`dcfg_contract_family = 100000001`). Reads from `dcfg_customers`, `dcfg_properties`, `dcfg_location_types`, writes to `dcfg_msas`, `dcfg_msa_rates`, `dcfg_audit_logs`.

### 5.5 MSA List (`/msas`)
**File:** `screens/MsaList.jsx` (existing v1.0)  
**Status:** Working  
Table of MSAs with customer, vendor, family, budget columns.

### 5.6 MSA Detail (`/msas/:id`)
**File:** `screens/MsaDetail.jsx` (existing v1.0)  
**Status:** Working  
MSA details, rates, location list, document output, status actions.

### 5.7 Contracts Split-Pane (`/contracts`)
**File:** `ContractsList.jsx` (new — this session)  
**Status:** Built, blocked by schema column name mismatches  
Split-pane layout: left list panel (380px) with search, filter badges, scrollable contract list. Right detail panel with status band, header, Location & Owner card, Contractor card, Exhibit A table, Amendments panel. KPI row: Active, Pending, This Month, Budget Warnings. Includes Void modal with reason requirement.

### 5.8 New Contract Wizard (`/contracts/new`)
**File:** `NewContractWizard.jsx` (new — this session)  
**Status:** Built, needs schema reconciliation  
Contracts are issued TO **vendors** (contractors). Both Bancroft and Decades families supported.  
5-step wizard: Family & Type → Customer/Program/Location → Contractor & Signer → Exhibit A Lines → Review & Generate. Three contract types:  
- **Work Order** — new contract to a vendor for work at a specific location  
- **Amendment** — modifies scope/value of an existing Work Order  
- **MSA Vendor Contract** — master subcontract agreement to a vendor (routes to Tyler → DocuSign)  

Template determined by `dcfg_contract_family` (Bancroft format or Decades format).

### 5.9 Contract Delivery / Send Queue (`/send-queue`)
**File:** `screens/SendQueue.jsx` (existing v1.0)  
**Status:** Working  
Two tabs: Send Queue (pending DocuSign) and Completion Queue (signed awaiting acknowledgment).

### 5.10 Location List — Desktop (`/locations`)
**File:** `screens/Locations.jsx` (existing v1.0)  
**Status:** Working  
List of properties with customer filter, location type badges, compliance status dots.

### 5.11 Location Detail — Desktop (`/locations/:id`)
**File:** `screens/LocationDetail.jsx` (existing v1.0)  
**Status:** Working  
Property details, contact info, address, compliance documents tab.

### 5.12 Location Manager — Mobile (`/field`)
**File:** `LocationManager.jsx` (new — this session)  
**Status:** Built, needs schema reconciliation  
Mobile-first property management: customer search → location list → property hub. Icon-grid hub with 21 drawer types (utilities, features, safety, appliances). Full appliance CRUD with photo capture, aging estimates, compliance document viewer.

---

## 6. Data Layer

### 6.1 Authentication
`window.Microsoft.Dynamic365.Portal.User` — no `isAuthenticated` property. Auth inferred from presence of `contactId`, `userName`, or `email`. Implemented in `usePortalUser.jsx`.

### 6.2 CSRF Token
Every mutating request (POST, PATCH, DELETE) requires `__RequestVerificationToken` header. Obtained via `window.shell.getTokenDeferred()`.

### 6.3 API Pattern
All queries go through `/_api/{entitySetName}`. OData v4 with `$select`, `$filter`, `$expand`, `$orderby`. Lookup fields use `@odata.bind` syntax on writes.

### 6.4 Shared API Module
`portalApi.js` — exports: EntitySets, status enums, `apiGet/Post/Patch/Delete`, `odataBind()` (aliased as `bind()`), `writeAuditLog()`, `callFlow()`, `getEnvVar()`, query builders, `formatCurrency()`, `formatDate()`, `copyToClipboard()`.

### 6.5 Toast System
`Toast.jsx` — `ToastProvider` wraps the app in `App.jsx`. Components use `useToast().show('ok'|'warn'|'err'|'info', message)`.

---

## 7. Power Automate Flows

| Flow | Trigger | Status | Purpose |
|------|---------|--------|---------|
| flow_docgen | HTTP POST | **STUB** (1 action: Compose_Placeholder) | Document generation engine |
| flow_commit | HTTP POST | Real (8 actions) | Budget commit on Signed/Received status |
| flow_cert_upload | HTTP POST | Real (11 actions) | Compliance document upload to SharePoint |
| flow_cert_alert | Recurrence (nightly) | Real (3 actions) | Certificate expiry recalculation |
| flow_send_email | HTTP POST | Real (3 actions) | Onboarding notification emails |
| flow_template_validate | HTTP POST | Real (10 actions) | Template upload validation |

**Missing flow:** `flow_appliance_photo_upload` — not in solution. Location Manager photo uploads fall back to data URL.

### 7.1 Environment Variables

| Variable | Purpose | Has Value |
|----------|---------|-----------|
| dcfg_flow_docgen_url | flow_docgen HTTP trigger URL | Needs URL after flow is built |
| dcfg_flow_cert_upload_url | flow_cert_upload HTTP trigger URL | Set |
| dcfg_flow_send_email_url | flow_send_email HTTP trigger URL | Set |
| dcfg_httpbridge_apikey | HTTP bridge API key | Set |
| dcfg_httpbridge_baseurl | HTTP bridge base URL | Set |
| dcfg_sp_aicache_folder | SharePoint AI cache folder | Set |
| dcfg_sp_site_url | SharePoint site URL | Set |

**Missing variable:** `dcfg_flow_appliance_photo_url` — needs to be created after flow is built.

---

## 8. Business Rules

1. **Budget Committed** — `dcfg_budget_committed` on `dcfg_msa` and `dcfg_program` is written exclusively by `flow_commit`. Never written from UI.
2. **flow_commit trigger** — UI patches `dcfg_status` to Signed/Received (100000003). Dataverse trigger fires `flow_commit` automatically. UI never calls flow_commit directly.
3. **Void requires reason** — Void modal requires non-empty text before confirm button activates.
4. **Amendment parent** — When type = Amendment, parent contract lookup and amendment sequence are required.
5. **Contract family** — Lives on `dcfg_customer.dcfg_contract_family`. Determines which Word template format to use (Bancroft format or Decades format). Both families can have Work Orders, Amendments, and MSA Vendor Contracts. Customer Proposals with packages (A/B/C) are Decades only.
6. **MSA expiry** — Expired MSA blocks new Work Order creation.
7. **Audit log** — CREATE only. Never PATCH or DELETE. Portal entity permission is Create only.
8. **Replace-by status** — `dcfg_replace_by_status`, `dcfg_estimated_replace_by`, `dcfg_months_to_replace_by` on `dcfg_appliance` are flow-only columns.

---

## 9. Document Generation (flow_docgen — NOT YET BUILT)

### Template Map

**Vendor Contracts (both families):**
| Customer Family | Type | Template |
|----------------|------|----------|
| Decades (100000001) | Work Order (0) | Decades_Contract_v1.docx |
| Decades (100000001) | Amendment (1) | Decades_Contract_Amendment_v1.docx |
| Decades (100000001) | MSA Vendor Contract (2) | Decades_MSA_v1.docx |
| Bancroft (100000000) | Work Order (0) | Bancroft_Contract_v1.docx |
| Bancroft (100000000) | Amendment (1) | Bancroft_Contract_Amendment_v1.docx |
| Bancroft (100000000) | MSA Vendor Contract (2) | Bancroft_MSA_v1.docx |

**Customer Proposals (Decades only):**
| Package | Template |
|---------|----------|
| Package A (Essential) | Decades_MSA_PackageA_v1.docx |
| Package B (Extended) | Decades_MSA_PackageB_v1.docx |
| Package C (Premium) | Decades_MSA_PackageC_v1.docx |

**Status:** All 9 Word template files must still be created. `dcfg_document_template` records must be created after upload.

### DocuSign Integration
Manual workflow — no API. Tyler opens document from SharePoint, uses DocuSign for Word add-in, pastes signer email from portal copy button.

---

## 10. Known Constraints

- React 16.14 — no automatic JSX runtime, no hooks newer than 16.8
- Power Pages portal caches aggressively — must clear cache after every deploy
- Portal Web API returns 400 if any `$select` column doesn't exist on the table
- No localStorage/sessionStorage in portal environment
- `dcfg_property` EntitySetName is `dcfg_properties` (standard pluralization — earlier handoff doc was wrong about `dcfg_propertys`)
