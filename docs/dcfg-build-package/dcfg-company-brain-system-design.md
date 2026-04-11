# DCFG Company Brain — System Design

## Enterprise Knowledge & Cross-System Intelligence Layer

**Version:** 1.0
**Date:** March 2026
**Purpose:** A company-wide knowledge system that connects all DCFG data sources, gives every team member a single place to find institutional knowledge, and enables AI agents to reason across systems on behalf of the business.

---

## 1. What Problem This Solves

DCFG runs on scattered information. Contract details live in Dataverse. Document templates live in SharePoint. Vendor certifications live in UpKeep. Customer communications live in Outlook. Billing history lives in the accounting system. HR records live somewhere else entirely.

No single person holds the full picture. When Tyler needs to know if a vendor's insurance is current before approving a contract, he checks one system. When Ira needs to know if a customer has outstanding issues before pitching a new MSA, he checks a different system. When Alicia needs to know which properties are due for recertification this quarter, she checks a third.

The company brain doesn't replace any of these systems. It sits alongside them as a connective tissue layer that does three things:

1. **Captures institutional knowledge** that lives nowhere — tribal knowledge, decisions, context, the "why" behind the "what"
2. **Cross-references data across systems** so an AI agent (or a person) can ask questions that span Dataverse + SharePoint + Outlook + UpKeep and get one answer
3. **Surfaces time-sensitive intelligence** — expiring certs, neglected relationships, stalled onboarding, approaching renewal dates — before anyone has to remember to ask

---

## 2. Architecture — Two Layers

### Layer 1: Knowledge Files (SharePoint Document Library)

A SharePoint document library called `company-brain` that every DCFG team member has access to. Contains structured JSON files organized by domain. This is the "institutional memory" — facts, decisions, contacts, procedures, and context that don't belong in any transactional system.

**Why SharePoint:**
- Everyone already has access through Microsoft 365
- Syncs to OneDrive on any device for offline access
- Versioned automatically (every edit creates a recoverable version)
- Power Automate can read/write it natively
- Microsoft Graph API provides programmatic access
- Permissions are inherited from the SharePoint site — no new auth system
- AI agents access it through MCP, Graph API, or file upload

**Why JSON files (not Dataverse tables for this layer):**
- Zero schema overhead — add a new knowledge domain by creating a file, not a table migration
- Agents treat JSON surgically — they edit fields, not rewrite structure
- Human-readable without any tool — open in browser, Notepad, VS Code
- Portable — the files work with Claude, ChatGPT, Copilot, or any future AI
- No licensing cost — SharePoint storage is included in Microsoft 365

### Layer 2: Cross-System Intelligence (Power Automate + Dataverse Views)

Power Automate scheduled flows that query across systems (Dataverse, SharePoint, Outlook, UpKeep, accounting) and write summarized intelligence into a Dataverse table called `dcfg_brain_insight`. The Power Pages SPA gets a new screen (Page 09 — Company Brain) that displays these insights alongside the knowledge files.

**Why Dataverse for insights (not just more JSON files):**
- Insights reference live transactional data (contracts, properties, vendors) — they need lookup relationships
- Role-based visibility — sales sees sales insights, operations sees operations insights
- Queryable via OData — the SPA can filter, sort, and paginate
- Power Automate writes to it natively
- The existing DCFG security model (web roles, table permissions) applies

---

## 3. SharePoint Library Structure

```
SharePoint Site: DCFG (existing)
  Document Library: company-brain/
    _config/
      brain-config.json              # System manifest — agent reads this first
    operations/
      vendor-knowledge.json          # Vendor notes, preferences, reliability scores
      property-knowledge.json        # Property quirks, access instructions, site contacts
      certification-status.json      # Cross-system cert tracking (populated by flow)
      seasonal-calendar.json         # Annual operational patterns, peak periods
    sales/
      customer-knowledge.json        # Customer preferences, history, relationship notes
      proposal-playbook.json         # What works, what doesn't, pricing guidance
      market-intelligence.json       # Competitor info, market rates, regional trends
    contracts/
      contract-decisions.json        # Why specific terms were chosen, precedents
      billing-exceptions.json        # Non-standard billing arrangements with context
      template-notes.json            # Template version history, field mapping notes
    company/
      team-directory.json            # Extended team info beyond HR basics
      procedures.json                # How-to knowledge for recurring processes
      vendor-contacts.json           # Vendor reps, account managers, emergency contacts
      system-credentials.json        # Non-secret system info (URLs, account names, NOT passwords)
    projects/
      contracting-suite/
        session-state.json           # Dev project session handoff (existing pattern)
        decisions-log.json           # Architecture decisions
        schema-changes.json          # Pending/completed schema work
```

### Naming Rules (same as personal brain — enforced everywhere)

- All lowercase, kebab-case (hyphens, no spaces)
- No special characters except hyphens and dots
- Forward slashes in all documentation and agent output
- Max depth: 3 levels from `company-brain/` root

---

## 4. Key File Schemas

### 4.1 brain-config.json — Company Brain Manifest

```json
{
  "_meta": {
    "type": "company-brain-config",
    "version": "1.0",
    "description": "Root configuration for the DCFG Company Brain. Read this first. It describes the folder structure, connected systems, team roles, and rules for interacting with brain files.",
    "company": "Decades Construction & Facilities Group",
    "created": "2026-03-15T00:00:00Z",
    "last_modified": "2026-03-15T00:00:00Z"
  },
  "connected_systems": [
    {
      "id": "dataverse",
      "name": "Dataverse — DCFGContractingSuite",
      "type": "primary-transactional",
      "url": "https://org0c17e98d.crm.dynamics.com",
      "access": "OData Web API, Power Automate Dataverse connector",
      "contains": "Contracts, MSAs, customers, vendors, properties, onboarding cases, audit logs, send queue, programs, templates"
    },
    {
      "id": "sharepoint",
      "name": "SharePoint — DCFG Site",
      "type": "document-storage",
      "access": "Graph API, Power Automate SharePoint connector",
      "contains": "Document templates, generated contracts, uploaded certs, company-brain knowledge files"
    },
    {
      "id": "outlook",
      "name": "Outlook / Exchange",
      "type": "communication",
      "access": "Graph API, Power Automate Outlook connector",
      "contains": "Customer correspondence, vendor communications, internal discussions, calendar events"
    },
    {
      "id": "upkeep",
      "name": "UpKeep",
      "type": "maintenance-management",
      "access": "UpKeep API (OI-06 — integration deferred but schema ready)",
      "contains": "Property maintenance records, vendor certifications, work orders"
    },
    {
      "id": "accounting",
      "name": "Accounting System",
      "type": "financial",
      "access": "TBD — API or manual sync",
      "contains": "Billing history, AP/AR, cost codes, payment status"
    }
  ],
  "team_roles": [
    {
      "role": "sales",
      "members_example": ["Ira", "Steve"],
      "brain_access": ["sales/*", "company/*", "operations/property-knowledge.json"],
      "description": "Customer-facing. Needs customer history, proposal guidance, market rates, property basics."
    },
    {
      "role": "contracts",
      "members_example": ["Tyler", "Bill"],
      "brain_access": ["contracts/*", "company/*", "operations/vendor-knowledge.json", "operations/certification-status.json"],
      "description": "Contract lifecycle. Needs billing context, template notes, vendor reliability, cert status."
    },
    {
      "role": "operations",
      "members_example": ["Alicia", "Leon"],
      "brain_access": ["operations/*", "company/*"],
      "description": "Property and vendor management. Needs vendor knowledge, cert tracking, property details, seasonal patterns."
    },
    {
      "role": "admin",
      "members_example": ["Joe", "Jennifer Walsh"],
      "brain_access": ["*"],
      "description": "Full access to all brain files and system configuration."
    }
  ],
  "domains": [
    {
      "id": "operations",
      "path": "company-brain/operations/",
      "description": "Vendor intelligence, property knowledge, certification tracking, operational patterns"
    },
    {
      "id": "sales",
      "path": "company-brain/sales/",
      "description": "Customer intelligence, proposal strategies, market data"
    },
    {
      "id": "contracts",
      "path": "company-brain/contracts/",
      "description": "Contract decisions, billing exceptions, template documentation"
    },
    {
      "id": "company",
      "path": "company-brain/company/",
      "description": "Cross-functional — team directory, procedures, vendor contacts, system info"
    },
    {
      "id": "projects",
      "path": "company-brain/projects/",
      "description": "Active project state and technical decisions"
    }
  ],
  "agent_rules": {
    "path_format": "All lowercase, kebab-case, no spaces. Forward slashes only.",
    "id_format": "UUIDv4 for all entry IDs.",
    "timestamp_format": "ISO 8601 UTC",
    "update_protocol": "Read file, find entry by ID, update in place, write full file back. Never duplicate.",
    "new_entry_protocol": "New UUIDv4, set created and last_modified, set created_by to authenticated user, append to entries array.",
    "never_delete": "Set status to archived. Never remove entries.",
    "attribution": "Every entry must have created_by and last_modified_by fields identifying the person or system that wrote it.",
    "cross_reference": "When an entry relates to a Dataverse record, include the entity set name and record GUID in a references array so the relationship is queryable."
  }
}
```

### 4.2 vendor-knowledge.json — Vendor Intelligence

```json
{
  "_meta": {
    "type": "vendor-knowledge",
    "version": "1.0",
    "description": "Institutional knowledge about vendors that doesn't live in Dataverse. Reliability notes, preferred contacts, quirks, pricing intelligence, relationship history. Agent: cross-reference with dcfg_vendors in Dataverse for transactional data. This file holds the context and judgment layer.",
    "file": "company-brain/operations/vendor-knowledge.json"
  },
  "entries": [
    {
      "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "vendor_name": "ABC Cleaning Services",
      "dataverse_ref": {
        "entity_set": "dcfg_vendors",
        "record_id": "00000000-0000-0000-0000-000000000000"
      },
      "reliability_rating": "good",
      "notes": "Reliable for routine work. Struggles with large-scale deep cleans. Best for properties under 50K sqft. Their account rep Maria is responsive — always go through her, not the general line.",
      "pricing_intelligence": "Their standard rate is competitive for NJ. They quoted 15% above market for the Trenton portfolio in 2025 — push back on large-portfolio pricing.",
      "preferred_contact": {
        "name": "Maria Rodriguez",
        "role": "Account Manager",
        "phone": "555-0123",
        "email": "maria@abccleaning.example.com"
      },
      "flags": ["push-back-on-portfolio-pricing"],
      "tags": ["cleaning", "nj", "routine-maintenance"],
      "created_by": "Alicia",
      "last_modified_by": "Alicia",
      "created": "2026-01-15T10:00:00Z",
      "last_modified": "2026-02-20T14:00:00Z",
      "status": "active"
    }
  ]
}
```

### 4.3 customer-knowledge.json — Customer Intelligence

```json
{
  "_meta": {
    "type": "customer-knowledge",
    "version": "1.0",
    "description": "Customer relationship intelligence beyond Dataverse transactional data. Preferences, decision-maker dynamics, renewal likelihood, historical context. Agent: cross-reference with dcfg_customers for contract and MSA data. This file holds the relationship layer.",
    "file": "company-brain/sales/customer-knowledge.json"
  },
  "entries": [
    {
      "id": "a2b3c4d5-e6f7-8901-bcde-f12345678901",
      "customer_name": "Garden State Group Homes",
      "dataverse_ref": {
        "entity_set": "dcfg_customers",
        "record_id": "00000000-0000-0000-0000-000000000000"
      },
      "decision_maker": "Patricia Nguyen, VP Operations",
      "decision_style": "Data-driven. Always wants cost comparisons. Responds well to ROI framing, not relationship selling.",
      "renewal_likelihood": "high",
      "notes": "Been with DCFG since 2022. Expanded from 12 to 28 properties. Patricia prefers email over phone. Her team does quarterly vendor reviews — always have updated numbers ready by March, June, September, December.",
      "sensitivities": "Had a billing dispute in Q3 2024 over a contract line misclassification. Resolved but still references it. Lead with accuracy.",
      "upsell_opportunities": ["additional-properties-south-jersey", "maintenance-tier-upgrade"],
      "tags": ["group-homes", "nj", "high-value", "data-driven-buyer"],
      "created_by": "Ira",
      "last_modified_by": "Steve",
      "created": "2025-06-01T09:00:00Z",
      "last_modified": "2026-01-10T16:00:00Z",
      "status": "active"
    }
  ]
}
```

### 4.4 procedures.json — Company Procedures

```json
{
  "_meta": {
    "type": "company-procedures",
    "version": "1.0",
    "description": "How-to knowledge for recurring business processes. Each entry documents a procedure that someone figured out and shouldn't have to figure out again. Agent: when someone asks how to do X, search here first before guessing.",
    "file": "company-brain/company/procedures.json"
  },
  "entries": [
    {
      "id": "b3c4d5e6-f7a8-9012-cdef-234567890123",
      "title": "How to process a contract void after DocuSign",
      "applies_to": ["contracts"],
      "steps": [
        "Open the contract in the Contracting Suite (Page 06)",
        "Click Void — requires DCFG_Admin role",
        "Enter the reason in the modal (required field)",
        "System auto-creates audit log entry with reason",
        "System does NOT recall the DocuSign envelope — Tyler must void it manually in DocuSign",
        "Notify the customer via email (not automated — manual step)"
      ],
      "gotchas": "The DocuSign void is manual. The system only updates Dataverse status. Tyler owns the DocuSign side. Do not tell the customer the contract is voided until Tyler confirms the envelope is voided in DocuSign.",
      "related_flows": ["flow_commit does NOT fire on void — budget is not affected"],
      "tags": ["void", "docusign", "contract-lifecycle"],
      "created_by": "Tyler",
      "last_modified_by": "Joe",
      "created": "2025-11-01T12:00:00Z",
      "last_modified": "2026-02-15T09:00:00Z",
      "status": "active"
    }
  ]
}
```

---

## 5. Cross-System Intelligence — The Dataverse Layer

### 5.1 dcfg_brain_insight Table

A new Dataverse table that receives cross-system intelligence from scheduled Power Automate flows. This is where the "agent surfaces, human decides" pattern lives.

**Columns:**

| Column | Type | Description |
|--------|------|-------------|
| dcfg_brain_insightid | PK | Auto-generated |
| dcfg_title | String (200) | Short headline: "3 vendor certs expiring this month" |
| dcfg_detail | Multiline (4000) | Full context including specific records and recommended actions |
| dcfg_domain | Choice | Sales / Operations / Contracts / Finance / Company |
| dcfg_priority | Choice | Critical / High / Medium / Low / Info |
| dcfg_source_systems | String (500) | Comma-separated list of systems queried: "dataverse,upkeep,outlook" |
| dcfg_insight_type | Choice | Expiring / Overdue / Anomaly / Opportunity / Reminder / Trend |
| dcfg_target_roles | String (200) | Which roles should see this: "operations,admin" |
| dcfg_related_records | Multiline (2000) | JSON array of entity_set + record_id references |
| dcfg_action_taken | Boolean | Has someone acknowledged/acted on this insight? |
| dcfg_action_notes | Multiline (2000) | What was done about it |
| dcfg_generated_by | String (100) | Which flow generated this insight |
| dcfg_generated_at | DateTime | When the insight was generated |
| dcfg_expires_at | DateTime | When the insight is no longer relevant (auto-archive) |
| dcfg_status | Choice | Active / Acknowledged / Resolved / Archived |

### 5.2 Scheduled Intelligence Flows

These Power Automate flows run on schedule, query across systems, and write insights to `dcfg_brain_insight`:

| Flow | Schedule | Cross-References | Example Insight |
|------|----------|-----------------|-----------------|
| brain-cert-expiry | Daily 6 AM | Dataverse properties + UpKeep certs + vendor records | "5 properties have fire certs expiring within 30 days. 2 vendors responsible. Contact list attached." |
| brain-stale-proposals | Weekly Monday 7 AM | Dataverse MSAs + Outlook sent emails | "3 proposals sent 14+ days ago with no response. Last email to Garden State was 18 days ago." |
| brain-onboarding-stalls | Daily 7 AM | Dataverse onboarding_cases + onboarding_checklists | "Case #OB-2026-014 has been on step 7 for 12 days. Average completion is 3 days. Possible blocker." |
| brain-contract-renewals | Weekly Monday 7 AM | Dataverse contracts + MSAs + customer knowledge file | "8 contracts renewing in the next 60 days. 2 customers flagged as 'high-value' in knowledge base." |
| brain-budget-health | Weekly Friday 4 PM | Dataverse programs + contracts + contract_lines | "Program 'NJ Group Homes 2026' is at 87% budget committed with 4 months remaining." |
| brain-vendor-performance | Monthly 1st at 8 AM | Dataverse vendors + contracts + operations knowledge file | "Vendor ABC Cleaning has 3 active contracts. Knowledge base flags portfolio pricing concern. Review recommended." |

### 5.3 Page 09 — Company Brain (Power Pages SPA)

A new screen in the DCFG Contracting Suite that displays:

**Section A: Active Insights (from dcfg_brain_insight)**
- Cards sorted by priority, filtered by the current user's role
- Each card shows: title, detail preview, source systems badges, action button
- "Mark Resolved" writes action_notes and flips status
- Critical/High insights get Von Restorff treatment (red/amber left border)

**Section B: Knowledge Search (from SharePoint company-brain files)**
- Search bar that queries across all knowledge files the user's role can access
- Results show the entry with source file, created_by, and last_modified date
- Clicking an entry opens an inline detail panel

**Section C: Quick Capture**
- A simple form: domain dropdown, title, notes, tags
- Writes a new entry to the appropriate knowledge file via Graph API
- This is how team members contribute knowledge without editing JSON directly

---

## 6. How Team Members Actually Use It

### Ira (Sales) opens Page 09 on Monday morning:

He sees:
- **Insight card:** "3 proposals sent 14+ days ago with no response" — he clicks through, sees which customers, decides to follow up with two and let one go
- **Insight card:** "Garden State quarterly vendor review is in 2 weeks" — he pulls up customer-knowledge.json, sees Patricia's preferences, prepares updated numbers
- He searches "group homes south jersey" in Knowledge Search — finds Steve's note from a conference about a new operator opening 6 locations. Adds a tag "prospect" and a follow-up note

### Alicia (Operations) checks it at 7 AM:

She sees:
- **Insight card (Critical):** "2 fire certs expired yesterday, 3 more expiring this week" — she sees the vendor contacts from vendor-knowledge.json embedded in the insight, makes calls
- **Insight card:** "Onboarding case OB-2026-014 stalled at step 7 for 12 days" — she checks the case, finds the vendor hasn't returned documents, escalates
- She opens Quick Capture and logs: "ABC Cleaning missed the cert deadline for Trenton properties again — third time this year. Consider backup vendor for Trenton portfolio."

### Tyler (Contracts) checks before approving a batch:

He searches "vendor ABC Cleaning" — sees Alicia's note about missed deadlines, the reliability rating, and the pricing pushback flag. He adds a note to the contract decision file: "Approved ABC renewal with 90-day cert compliance clause added per operations concern."

---

## 7. Access Model

SharePoint permissions control who sees which knowledge files. The existing DCFG web roles in Power Pages control who sees which insights on Page 09.

| Role | SharePoint Access | Page 09 Insights |
|------|------------------|-----------------|
| Sales (DCFG_Sales) | sales/*, company/*, operations/property-knowledge.json | domain = Sales or Company |
| Contracts (DCFG_Contracts) | contracts/*, company/*, operations/vendor-knowledge.json, operations/certification-status.json | domain = Contracts or Company |
| Operations (DCFG_Operations) | operations/*, company/* | domain = Operations or Company |
| Admin (DCFG_Admin) | Everything | Everything |

---

## 8. Implementation Phases

### Phase 1 — Knowledge Files (Week 1-2)

- Create `company-brain` document library in SharePoint
- Create the folder structure (all kebab-case, no spaces)
- Deploy starter JSON files with empty entries arrays and _meta blocks
- Share the library with the team
- Start capturing knowledge in conversations — "save this to the company brain"
- Knowledge files work immediately with any AI via file upload

### Phase 2 — Cross-System Intelligence (Week 3-5)

- Create `dcfg_brain_insight` table in Dataverse (schema script via dataverse-schema-ops skill)
- Build the first 2-3 Power Automate intelligence flows (cert-expiry and stale-proposals are highest value)
- Create table permissions for dcfg_brain_insight (role-filtered read, admin write)
- Test flows, verify insights land correctly

### Phase 3 — Page 09 Company Brain Screen (Week 5-7)

- Design the screen using dcfg-ux-psychology skill (Miller's Law: max 4 insight cards visible before scroll, progressive disclosure on detail panels)
- Build the React component: insights feed + knowledge search + quick capture
- Wire insights feed to dcfg_brain_insights OData query (filtered by role)
- Wire knowledge search to Graph API SharePoint search
- Wire quick capture to Graph API file write
- Deploy via pac pages

### Phase 4 — Expand Intelligence Flows (Ongoing)

- Add remaining scheduled flows (budget health, vendor performance, contract renewals)
- Connect UpKeep API when OI-06 is ready
- Connect accounting system when API access is available
- Tune flow schedules and insight priority thresholds based on team feedback

---

## 9. Path Safety (Same Rules as Personal Brain)

OneDrive and SharePoint both allow spaces. Every path in this system avoids them.

- All folders and files: lowercase, kebab-case
- All shell commands and scripts: quote every path
- SharePoint document library name: `company-brain` (no spaces)
- The SharePoint site URL itself may contain spaces or encoded characters — always use the Graph API site ID or drive ID, never string-concatenate URLs

```powershell
# CORRECT — use Graph API with drive ID
$driveId = "b!xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$filePath = "company-brain/operations/vendor-knowledge.json"
$graphUrl = "https://graph.microsoft.com/v1.0/drives/$driveId/root:/$filePath`:/content"

# WRONG — string-concatenated SharePoint URL
$url = "https://dcfg.sharepoint.com/Shared Documents/company-brain/operations/vendor-knowledge.json"
```

---

## 10. What This Gets You

**Today (Phase 1):** A shared knowledge base that any team member can search and any AI can read. Tribal knowledge stops living in people's heads.

**Next month (Phase 2-3):** Cross-system intelligence surfaced automatically. Expiring certs, stalled deals, budget warnings, and vendor red flags show up before anyone has to remember to look.

**Over time (Phase 4+):** Every time you connect a new system or log a new fact, the brain gets smarter. Every time a model improves, the reasoning over your data improves automatically. The knowledge compounds. The intelligence compounds. The team stops losing information to turnover, forgotten conversations, and system silos.
