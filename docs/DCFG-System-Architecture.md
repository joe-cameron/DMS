# DCFG Contracting Suite — System Architecture

**Prepared for:** Audit / Compliance Review
**Date:** April 27, 2026
**Organization:** Decades Construction & Facilities Group
**Tenant:** decades-cg.com

---

## 1. System Overview

The DCFG Contracting Suite is a facilities management platform that supports the full lifecycle of contract management, inspection scheduling, document generation, and vendor operations. The system spans four Microsoft Power Platform environments, an Azure Functions compute layer, and integrations with UpKeep (CMMS), SharePoint (DMS), and Google Maps.

### 1.1 Architecture Diagram (Logical)

```
                        +--------------------------+
                        |     End Users (Browser)  |
                        +--------+---------+-------+
                                 |         |
                    HTTPS/TLS 1.2|         |HTTPS/TLS 1.2
                                 v         v
              +------------------+--+   +--+------------------+
              | Power Pages SPA     |   | Power Pages SPA     |
              | Contracting Suite   |   | Inspection Scheduler|
              | dmms1.powerapps     |   | dcfgscheduler.      |
              | portals.com         |   | powerappsportals.com|
              +--------+--------+--+   +--+--------+---------+
                       |        |         |        |
                       v        v         v        v
              +--------+--------+---------+--------+---------+
              |           Microsoft Dataverse                 |
              |           (Power Platform)                    |
              |  Prod | Test | Stage | Portal environments    |
              +--------+--------+---------+--------+---------+
                       |                  |
                       v                  v
              +--------+--------+  +------+--------+
              | Azure Functions |  | SharePoint     |
              | (Document Gen,  |  | Online         |
              |  Inspection     |  | (DCFG_Templates|
              |  Sync)          |  |  DCFG_Outputs) |
              +--------+--------+  +---------------+
                       |
                       v
              +--------+--------+
              | UpKeep CMMS     |
              | (Read-Only      |
              |  Integration)   |
              +-----------------+
```

---

## 2. Environments

### 2.1 Microsoft Power Platform

| Environment | Purpose | Org URL | Power Pages Sites |
|-------------|---------|---------|-------------------|
| **DCFGSystems-Prod** | Production | org06f5de0b.crm.dynamics.com | dmms1.powerappsportals.com (Contracting Suite), dcfgscheduler.powerappsportals.com (Inspection Scheduler) |
| **DCFGSystems-Test** | Development/Testing (Sandbox) | org0c17e98d.crm.dynamics.com | dcfg.powerappsportals.com |
| **DCFGSystems-Stage** | Staging/UAT | org88778bb0.crm.dynamics.com | holding.powerappsportals.com |
| **DCFGSystems-Portal** | Customer Portal & Onboarding | orgf625b080.crm.dynamics.com | decades.powerappsportals.com (Customer Portal), decades-concierge.powerappsportals.com (Onboarding Concierge SPA) |

**Deployment Order:** Test -> Stage -> Prod
**Solution Name:** DCFGSystemTest (all environments)
**Data Model:** Enhanced Data Model (EDM) for all Power Pages sites

### 2.2 Azure

| Resource | Type | Location | Resource Group |
|----------|------|----------|----------------|
| **dcfg-html-to-pdf** | Function App (Linux, Node.js) | East US | dcfg-docgen |
| **ASP-dcfgdocgen-a01b** | App Service Plan | East US | dcfg-docgen |
| **dcfgdocgen930b** | Storage Account | East US | dcfg-docgen |
| **Application Insights** | Monitoring | Global | dcfg-docgen |

**Subscription:** Decades Contracting System (`4599db3e-dd92-4a8d-8f32-df6ed6c422bf`)

### 2.3 External Services

| Service | Purpose | Access Level | Auth Method |
|---------|---------|--------------|-------------|
| **UpKeep CMMS** | Work order management, inspection scheduling | READ-ONLY | Email/password session token |
| **SharePoint Online** | Document storage (templates, outputs, attachments) | Read/Write | MSAL client credentials |
| **Google Maps Platform** | Route optimization, drive time calculation | Read-Only | API key (referrer-restricted) |

---

## 3. Azure Functions

### 3.1 Function App: dcfg-html-to-pdf

**Runtime:** Node.js on Linux
**Framework:** Azure Functions v4
**TLS:** Minimum 1.2 enforced
**FTP:** FTPS-only (plain FTP disabled)
**Host:** dcfg-html-to-pdf-d9bwchakhgduf4gc.eastus-01.azurewebsites.net

| Function | Trigger | Purpose |
|----------|---------|---------|
| **html-to-pdf** | HTTP | Document generation — OOXML injection into Word templates via jszip |
| **sharepoint-upload** | HTTP | Upload generated documents to SharePoint DCFG_Outputs |
| **docusign-send** | HTTP | Send documents for electronic signature via DocuSign |
| **inspectionSync** | Timer (every 30 min) | Sync inspection work orders from UpKeep to Dataverse |

### 3.2 Function Security

- All HTTP-triggered functions require a function key in the request
- Timer-triggered functions (inspectionSync) run automatically with no external trigger surface
- Secrets stored in Azure Function App Configuration (Application Settings), not in code
- No secrets in source control

---

## 4. Identity & Authentication

### 4.1 Azure AD Tenant

| Property | Value |
|----------|-------|
| **Tenant ID** | 71ccf1ec-8b0a-4419-9a45-a617aa1a66d6 |
| **Domain** | decades-cg.com |
| **Display Name** | Decades Construction Group |

### 4.2 App Registration: Decades Management System

| Property | Value |
|----------|-------|
| **Application (Client) ID** | 327ac710-2d2a-4912-a5ee-9b7f51ee7a7b |
| **Sign-in Audience** | AzureADMyOrg (single tenant) |
| **Client Secret** | Configured (expires 2028) |
| **Dataverse Application User** | Registered on Prod (ID: 3587027f-4c42-f111-88b4-000d3a31ac1d) |

**API Permissions:**
- Dynamics CRM — user_impersonation (Delegated)
- SharePoint — AllSites.Write (Delegated)
- Microsoft Graph — User.Read (Delegated)

### 4.3 Authentication Flows

| Flow | Used By | Method |
|------|---------|--------|
| **Browser SSO** | Power Pages SPA users | Microsoft Entra ID via Power Pages built-in auth |
| **Client Credentials** | Azure Function (inspectionSync) | App registration + client secret → Dataverse token |
| **Session Token** | Azure Function (inspectionSync) | UpKeep email/password → session token (API-level) |
| **Anti-Forgery Token** | SPA Dataverse API calls | Power Pages fetchAntiForgeryToken → __RequestVerificationToken header |
| **PAC CLI** | Developer deployment | pac auth (interactive, per-environment) |

---

## 5. Data Architecture

### 5.1 Dataverse Tables (Primary)

| Table | Logical Name | Purpose | Record Estimate |
|-------|-------------|---------|-----------------|
| Properties | dcfg_property | Managed locations | ~983 |
| Customers | dcfg_customer | Client organizations | ~8 |
| Contracts | dcfg_contract | Work orders, amendments | ~200+ |
| MSAs | dcfg_msa | Master service agreements | ~50+ |
| Vendors | dcfg_vendor | Service providers | ~100+ |
| Document Requests | dcfg_document_request | DocGen transaction table | ~500+ |
| Send Queue | dcfg_send_queue | Contract delivery workflow | ~100+ |
| Inspectors | dcfg_im_inspector | Inspection staff profiles | 2 |
| Inspection Scenarios | dcfg_im_scenario | What-if scheduling parameters | 1 |
| Inspection Schedule | dcfg_im_schedule | Scheduled/completed inspections | ~2,500+ |
| Audit Logs | dcfg_audit_log | System audit trail | Growing |
| Configs | dcfg_config | Runtime configuration | ~20 |
| Knowledge | dcfg_knowledge | System knowledge base | ~230 |

### 5.2 SharePoint Document Libraries

| Library | Purpose | Structure |
|---------|---------|-----------|
| **DCFG_Templates** | Word document templates | Flat |
| **DCFG_Outputs** | Generated documents | Customer/Year/DocType |
| **DCFG_Attachments** | Uploaded attachments | Customer/Location/Year |

**SharePoint Site:** decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite

### 5.3 Data Flow — Document Generation

```
User clicks Generate
  -> SPA creates dcfg_document_request record (Dataverse)
  -> Power Automate flow triggers on create
  -> Flow reads template from SharePoint DCFG_Templates
  -> Flow calls Azure Function (html-to-pdf) for OOXML injection
  -> Azure Function returns populated document
  -> Flow saves to SharePoint DCFG_Outputs
  -> Flow updates dcfg_document_request with result URL
  -> SPA polls for completion, shows link
```

### 5.4 Data Flow — Inspection Sync

```
UpKeep (source of truth for scheduled work)
  -> Azure Function inspectionSync (every 30 min, timer trigger)
  -> Authenticates to UpKeep (session token)
  -> Pulls all inspection WOs (paginated)
  -> Authenticates to Dataverse (client credentials)
  -> Compares against dcfg_im_schedule records
  -> Creates new records / updates changed records
  -> Scheduler SPA reads dcfg_im_schedule via Web API
  -> User clicks Refresh to pull latest
```

---

## 6. Network & Security

### 6.1 Transport Security

| Component | Protocol | TLS Version |
|-----------|----------|-------------|
| Power Pages sites | HTTPS | 1.2+ (enforced by Microsoft) |
| Azure Functions | HTTPS | 1.2 minimum (configured) |
| Dataverse API | HTTPS | 1.2+ (enforced by Microsoft) |
| UpKeep API | HTTPS | 1.2+ |
| SharePoint API | HTTPS | 1.2+ (enforced by Microsoft) |
| Google Maps API | HTTPS | 1.2+ |

### 6.2 Access Controls

| Layer | Control |
|-------|---------|
| **Power Pages** | Microsoft Entra ID SSO, role-based table permissions, CSRF tokens on all API calls |
| **Dataverse** | Table permissions per web role, field-level site settings, solution-scoped |
| **Azure Functions** | Function keys for HTTP triggers, App Service authentication available |
| **SharePoint** | Site-level permissions, app-only access via client credentials |
| **UpKeep** | Account-level credentials, API session tokens, READ-ONLY policy enforced in code |
| **Google Maps** | API key restricted to dcfgscheduler.powerappsportals.com referrer |

### 6.3 Secrets Management

| Secret | Storage Location | Rotation |
|--------|-----------------|----------|
| Dataverse client secret | Azure Function App Settings | 2-year expiry (created April 2026) |
| UpKeep credentials | Azure Function App Settings | Manual |
| SharePoint client credentials | Azure Function App Settings | Per app registration policy |
| Google Maps API key | Dataverse site setting (Scheduler/GoogleMapsApiKey) | Manual |
| PAC CLI auth | Local developer machine only | Per-session |

### 6.4 Data Residency

All data resides in the United States:
- **Dataverse:** US region (crm.dynamics.com)
- **Azure Functions:** East US
- **SharePoint:** US geography (per Microsoft 365 tenant)
- **UpKeep:** US-hosted SaaS

---

## 7. SPA Architecture

### 7.1 Contracting Suite SPA (dmms1.powerappsportals.com)

| Property | Value |
|----------|-------|
| **Framework** | React 16.14 |
| **Build Tool** | Vite 5.x (IIFE bundle) |
| **Hosting** | Power Pages Enhanced Data Model code-site |
| **API** | Dataverse Web API via Power Pages proxy (/_api/) |
| **Auth** | Power Pages built-in (Entra ID SSO) |
| **Bundle Size** | ~200 KB |

#### Functional Modules

**MSA Composer** — Master Service Agreement creation wizard. The MSA defines the management fee relationship between Decades and the customer. Produces a multi-exhibit contract package (MSA, Exhibit A service plan, Exhibit B location list, Exhibit C fee schedule, Exhibit D insurance requirements). Customer signer auto-populated from customer record. Supports two contract families: Bancroft (TPA — third party administrator) and Decades (direct management). Generated documents are OOXML-injected Word files saved to SharePoint.

**Contract Composer** — Work order and vendor agreement creation. Generates the service income side: work orders, amendments, blanket work orders, and vendor agreements. Each contract carries a vendor assignment from the bid comparison process. Contract types include: Bancroft Work Order, Bancroft Amendment, Bancroft Blanket WO, Decades Work Order, Decades Amendment, Decades Vendor Agreement. All documents flow through the DocGen V4 pipeline (Dataverse trigger → Power Automate → Azure Function OOXML injection → SharePoint).

**Send Queue** — Contract delivery and tracking workflow. Staff assign WO numbers, manage hold/release status, track DocuSign signature status (sent, signed, returned, declined). The Send Queue acknowledgment of a returned signed contract is the **trigger that creates schedulable work** — acknowledged contracts flow into the Inspection Scheduler as contract work items.

**Sales Dashboard** — Customer pipeline overview with KPI cards. Entry point for new proposals and customer onboarding.

**Customer & Vendor Management** — Customer list/detail with contact information, contract family assignment, and property associations. Vendor records with trade qualifications, insurance tracking, and geographic coverage.

**Locations** — Property management with address, compliance fields (fire alarm, sprinkler, DCA, IDD dates), UpKeep integration, and property detail records for equipment/system tracking. Desktop and mobile views.

**Operations** — Facilities operations dashboard combining UpKeep work order data with Dataverse contract and compliance data. Role-switchable views.

#### Document Generation Pipeline (DocGen V4)

| Step | Component | Action |
|------|-----------|--------|
| 1 | SPA | User clicks Generate → creates `dcfg_document_request` record |
| 2 | Power Automate | Flow triggers on Dataverse record creation |
| 3 | Flow | Reads template from SharePoint `DCFG_Templates` |
| 4 | Flow | Reads entity data (customer, vendor, contract, properties) |
| 5 | Flow | Calls Azure Function `html-to-pdf` with template + field map |
| 6 | Azure Function | OOXML injection via jszip — 5 strategies: scalar fields, block fields, amendment blocks, location tables, DocuSign anchors |
| 7 | Flow | Saves populated document to SharePoint `DCFG_Outputs/{Customer}/{Year}/{DocType}` |
| 8 | Flow | Updates `dcfg_document_request` with result URL and status |
| 9 | SPA | Polls for completion, displays SharePoint view link |

**Template Types:** MSA Package A (Basic), MSA Package B (Concierge), MSA Package C (Optimized), Bancroft Work Order, Bancroft Amendment, Bancroft Blanket WO, Decades Work Order, Decades Amendment, Decades Vendor Agreement, Exhibit A (Automated), Exhibit A (Variable)

#### Revenue Model Context

The Contracting Suite supports a management fee business model:
- **MSA Composer** generates the fee agreement (customer pays Decades 10-15% management fee)
- **Contract Composer** generates the service contracts (Decades pays vendors or performs work directly)
- **Send Queue** tracks contract execution lifecycle
- **Inspection Scheduler** drives the work pipeline: inspections find deficiencies → punch lists → bid comparisons → contracts → management fees

### 7.2 Inspection Scheduler SPA (dcfgscheduler.powerappsportals.com)

| Property | Value |
|----------|-------|
| **Framework** | React 16.14 |
| **Build Tool** | Vite 5.x (IIFE bundle) |
| **Hosting** | Power Pages Enhanced Data Model code-site |
| **API** | Dataverse Web API via Power Pages proxy (/_api/) |
| **Auth** | Power Pages built-in (Entra ID SSO) |
| **Bundle Size** | ~204 KB |

#### Functional Modules

**3-Week Scrolling Calendar** — Interactive weekly planner showing Mon-Fri across 3 visible weeks. Two visual states: solid cells for UpKeep-scheduled work, dashed cells for tool-modeled recommendations. Individual work order stops visible inside each day cell with customer color dots, trade icons, and hours. Mouse wheel scrolls weeks. Navigation includes ◄Week, Week►, +90 Days, Next Inspection, and Today jump buttons.

**Drag-and-Drop Scheduling** — Individual work orders are draggable between calendar days, from the contract work pool to the calendar, and from the "Needs Inspection" countdown to the calendar. Moving an UpKeep-scheduled item triggers a confirmation modal describing the unschedule action. Drag navigation zones appear during drag for time-scrolling while holding an item. Cancel zone restores pre-drag state.

**Compliance Countdown (30/60/90 Days)** — Bottom panel showing properties approaching their next inspection due date, organized by urgency: 30-day (urgent/red), 60-day (warning/amber), 90-day (planning). Each row is draggable to the calendar. Scoreboard ticker shows live 30d/60d/90d counts at all times. Items automatically surface as the time horizon approaches — the list is derived from last inspection date + frequency, not manually maintained.

**Contract Work Pool** — Tabbed section showing two sources of unscheduled work: (1) Contract Work — acknowledged signed contracts from the Send Queue that need trade-specific scheduling, and (2) Unscheduled — work orders removed from existing days via drag. Both are draggable to calendar days.

**Compliance Action Center** — Slide-out panel with progress bar showing % compliant. Lists never-inspected and behind-schedule locations with suggested dates. Schedule/Edit/Accept All buttons for one-click compliance resolution.

**Trade Iconography** — SVG icons for each trade type: inspection, plumbing, painting, electrical, HVAC, general maintenance, safety, door/hardware. Visible in calendar cells, detail panel, and countdown board. Hover shows trade name.

**Delta Refresh** — Refresh button in the ticker bar performs a delta sync from Dataverse, pulling only schedule records modified since the last fetch. Merges changes into existing state without full reload.

**Route Integration** — Google Directions API for real drive times (with haversine fallback). View Route links use full addresses for accurate Google Maps routing. Route planning follows furthest-first strategy (drive to most distant location first, work back toward home base for safety/alertness).

#### Two Classes of Scheduled Work

| Class | Source | Trigger | Examples |
|-------|--------|---------|----------|
| **Inspections** | Compliance requirements | 4 visits/year per property | Quarterly facility inspections |
| **Contract Work** | Send Queue acknowledgment | Signed contract returned | Plumbing repair, painting, electrical, HVAC service |

#### Resource Model

The scheduler manages three resource types simultaneously:
- **Decades Inspectors** — internal staff performing facility inspections
- **Decades Trade Crews** — internal teams performing direct maintenance work (painting, general handyman)
- **Awarded Vendors** — external contractors from the bid comparison process, with trade-specific qualifications and concurrent job capacity constraints

### 7.3 Customer Portal (decades.powerappsportals.com)

| Property | Value |
|----------|-------|
| **Environment** | DCFGSystems-Portal (orgf625b080.crm.dynamics.com) |
| **Type** | Power Pages HTML site (non-SPA) |
| **Purpose** | Customer-facing portal for service requests, document access, property information |
| **Auth** | Microsoft Entra ID, customer web roles |
| **Data Model** | Enhanced Data Model |

### 7.4 Onboarding Concierge SPA (decades-concierge.powerappsportals.com)

| Property | Value |
|----------|-------|
| **Environment** | DCFGSystems-Portal (orgf625b080.crm.dynamics.com) |
| **Framework** | React SPA |
| **Purpose** | New customer onboarding workflow — vendor setup, document collection, property intake |
| **Auth** | Power Pages built-in (Entra ID) |
| **Status** | Built, deployed to Test site (decadeswelcomesyou.powerappsportals.com) |

### 7.5 Portal Environment Sites Summary

| Site | URL | Purpose | Type |
|------|-----|---------|------|
| Customer Portal | decades.powerappsportals.com | Customer service access | HTML |
| Onboarding Concierge | decades-concierge.powerappsportals.com | New customer onboarding | React SPA |
| BidComp Builder | dmsbuilder.powerappsportals.com | Bid comparison module | React SPA |
| DCFG Resources | (internal) | Internal team resource site | Power Pages |

---

## 8. Monitoring & Observability

| Component | Monitoring |
|-----------|-----------|
| **Azure Functions** | Application Insights (built-in), function execution logs |
| **Power Platform** | Dataverse audit logs (dcfg_audit_log), Power Automate flow run history |
| **SPA** | Browser console logging, Dataverse error records |
| **UpKeep Sync** | inspectionSync function logs in Application Insights, delta counts per run |

---

## 9. Backup & Recovery

| Data Store | Backup Method | Retention |
|-----------|---------------|-----------|
| **Dataverse** | Microsoft-managed automatic backups | 28 days (system), manual backups available |
| **SharePoint** | Microsoft-managed, versioning enabled | Per Microsoft 365 retention policy |
| **Azure Functions** | Code in source control (git), configuration in App Settings | Git history + Azure backup |
| **UpKeep** | Vendor-managed SaaS | Per UpKeep retention policy |

---

## 10. Change Management

| Activity | Process |
|----------|---------|
| **SPA Code Changes** | Edit source -> Vite build -> pac pages upload -> cache clear |
| **Dataverse Schema Changes** | Solution-scoped (DCFGSystemTest), deployed via solution import |
| **Azure Function Changes** | Edit source -> func azure functionapp publish |
| **Power Automate Flows** | Managed via solution, Dataverse-triggered (not HTTP) |
| **Environment Promotion** | Test -> Stage -> Prod, manual verification at each stage |

**Source Control:** Git repository at C:\DCFG, mirrored to GitHub (github.com/decades-cg)
**Deploy Authorization:** Operator (Joseph Cameron) approves each deployment

---

## 11. AI Development & Operations Agents

The DCFG system is developed and maintained with the assistance of AI agents operating under human authorization. All agents operate in a read-first, verify-before-write discipline with explicit operator approval for deployments.

### 11.1 Primary Development Agent

| Property | Value |
|----------|-------|
| **Platform** | Claude Code (Anthropic CLI) |
| **Model** | Claude Opus 4.6 (1M context) |
| **Role** | Senior technical admin assistant — code, schema, deployment, troubleshooting |
| **Authorization** | Operator approves all production writes and deployments |
| **Project Config** | CLAUDE.md at project root defines mandates, rules, environment table |
| **Memory** | File-based persistent memory at ~/.claude/projects/C--DCFG/memory/ |
| **Skills** | 40+ specialized skills for Power Platform, design, testing, monitoring |

### 11.2 Specialized Agents (Droid Roster)

| Agent | Purpose | Tier | Model |
|-------|---------|------|-------|
| **HAL** | Self-learning technical assistant, commander of droid army | Supervisor | Opus |
| **Portal SPA Droid** | React SPA development, pac pages deployment | 2 | Sonnet |
| **Schema Droid** | Dataverse table/column creation, seed data | 2 | Haiku |
| **Portal Admin Droid** | Site settings, table permissions, web roles | 2 | Haiku |
| **Flows Droid** | Power Automate flow design and compilation | 2 | Haiku |
| **Auth Droid** | Session management, token health, identity verification | 2 | Haiku |
| **Scout Droid** | Read-only state queries and environment assessment | 2 | Haiku |
| **Research Droid** | Web research, API documentation, external sources | 2 | Sonnet |
| **Test Droid** | Playwright E2E tests, path probes, screen captures | 2 | Sonnet |
| **Design Droid** | UI/UX via Impeccable skill suite (18 sub-skills) | 2 | Sonnet |
| **Safety Droid** | Environment guards, blast radius assessment | 2 | Haiku |
| **Monitor Droid (Nora)** | Production monitoring — audit logs, DocGen health, flow status | 2 | Haiku |
| **Judgment Droid** | Script-vs-manual decisions, classification, trade-offs | 1 | Opus |

### 11.3 Monitoring Agent: Nora

| Property | Value |
|----------|-------|
| **Purpose** | Continuous production monitoring |
| **Checks** | Audit logs, document request status, flow health |
| **Auto-Fix** | Verified stuck document requests |
| **Output** | Writes findings to dcfg_brain_insights table |
| **Schedule** | On-demand or /loop 5m for continuous monitoring |

### 11.4 Inspection Sync Agent (Azure Function)

| Property | Value |
|----------|-------|
| **Function** | inspectionSync |
| **Trigger** | Timer — every 30 minutes |
| **Pipeline** | UpKeep API → compare → Dataverse dcfg_im_schedule |
| **Operations** | Create new records, update date/status changes, link to properties |
| **Auth** | Service principal (client credentials) to Dataverse, session token to UpKeep |
| **Monitoring** | Application Insights, function execution logs |

### 11.5 Agent Safety Controls

| Control | Description |
|---------|-------------|
| **Read Before Write** | All agents must investigate current state before any modification |
| **Operator Approval** | Production deployments require explicit human authorization |
| **Environment Isolation** | Test environment is default; Prod requires stated intent + approval |
| **Soft Delete Only** | No hard deletes — all records use dcfg_active_flag |
| **Before-State Capture** | Backup scripts save state before bulk changes |
| **Audit Trail** | All modifications logged to dcfg_audit_log |
| **Rollback Capability** | Before-state JSON files enable manual rollback |
| **pac auth Restore** | After any Prod operation, pac auth index restored to Test |

### 11.6 Development Skills Library

| Category | Skills |
|----------|--------|
| **Power Platform** | dcfg-project-data, dcfg-spa-reference, power-pages-content-ops, power-automate-flow-design, safety-controls |
| **Engineering** | auto-research-testing, playwright-syntax-design, script-vs-manual-judgment |
| **Design (Impeccable)** | shape, adapt, animate, audit, critique, delight, distill, harden, layout, optimize, overdrive, polish, typeset, clarify, colorize, bolder, quieter, impeccable |
| **Orchestration** | dcfg-work-organizer, hybrid-agent-supervisor, nora, resource-site-publish |
| **Process** | brainstorming, writing-plans, executing-plans, test-driven-development, systematic-debugging, verification-before-completion, code-review |

---

*Document generated from live system state on April 27, 2026.*
