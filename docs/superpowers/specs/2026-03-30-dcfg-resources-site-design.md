# DCFG Resources Site — Design Spec

## Overview

A standalone internal utility site hosted on Power Pages (Prod environment) for sharing user guides, review links, tools, and an AI teaching assistant with DCFG staff. Anonymous access — no login required.

**This is a silo.** It has no association with the SPA (`C:\DCFG\spa\`). It does not touch the SPA codebase, does not share components, and does not deploy through the SPA pipeline. It can read Dataverse databases but never writes to them.

## Three Deliverables

### 1. User Manual (for humans)

Modular Markdown guides documenting all four DMS document creation flows, with screenshots captured via Playwright tests against curated demo data.

**Guides:**

| Guide | Source Wizard | Steps | Est. Screenshots |
|-------|--------------|-------|-----------------|
| Getting Started | — | Login, navigation, dashboard | ~6 |
| Sales Proposal | NewProposalWizard | Package → Customer & Vendor → Pricing & Locations → Review | ~8 |
| Work Order | NewContractWizard | Customer → DocType → Contractor & Signer → Exhibit A Lines → Review | ~10 |
| Amendment | NewContractWizard (amendment mode) | Customer → DocType + Parent WO → Contractor → Exhibit A → Review | ~10 |
| Vendor MSA | NewContractWizard (MSA mode) | Customer → DocType → Vendor + Signer → Review | ~8 |

Total: ~42 screenshots.

**Each guide follows this template:**

1. **Overview** — what this document is, when to create one, who is involved
2. **Prerequisites** — what must exist before starting (customer, vendor, location, parent WO)
3. **Step-by-step walkthrough** — each wizard step with screenshot, what to fill in, what auto-fills, what is required vs optional
4. **Field reference** — every field on every step: display name, purpose, valid values, Dataverse column name
5. **After generation** — what happens next: Send Queue, status transitions, document lifecycle
6. **Common mistakes** — what goes wrong and how to fix it
7. **Draft and resume** — how to save as draft, find WIP items, resume later

**Output formats:** Markdown (source of truth) → HTML (for resource site) → PDF (for onboarding packets).

**Audience:** Internal DCFG staff and new hires. Self-contained enough for someone new to follow without prior system knowledge.

### 2. DMS Knowledge Base (for Copilot)

A self-contained set of documents that Claude builds and maintains. Copilot Studio consumes them as grounding data. Copilot becomes a DMS specialist — not a general chatbot.

**Knowledge base documents are updated alongside user manual guides.** When the SPA changes and Playwright tests are re-run, the knowledge base documents must also be reviewed and updated to match. Both deliverables describe the same system — they must stay in sync.

**Grounding documents (uploaded to Copilot Studio as knowledge sources):**

| Document | Contents |
|----------|----------|
| `dms-processes.md` | All 4 document creation flows, step-by-step with decision points |
| `dms-field-reference.md` | Every field, every screen: name, purpose, valid values, required/optional, Dataverse column |
| `dms-business-rules.md` | Contract families, TPA logic, amendment parent rules, soft delete, WO number lifecycle, submitted docs locked |
| `dms-status-lifecycles.md` | All status transitions: contracts, MSAs, document requests, send queue items |
| `dms-troubleshooting.md` | Common errors, what they mean, resolution steps |
| `dms-glossary.md` | Every term, acronym, entity name in plain language |

**System configuration (applied in Copilot Studio's system prompt field, NOT uploaded as a knowledge source):**

| Document | Purpose |
|----------|---------|
| `dms-copilot-system-prompt.md` | Defines Copilot's scope, tone, read-only rules, and out-of-scope deflection. This is configuration, not grounding data — it must not be surfaced in answers to users. |

**Copilot scoping rules:**

In scope:
- Document creation (Sales Proposal, Work Order, Amendment, Vendor MSA)
- Document lifecycle (Draft → Generated → Sent → Signed → Closed)
- Send Queue operations
- Customer, vendor, location lookups (read-only)
- Field explanations and valid values
- Process guidance and step-by-step help

Out of scope:
- General IT help
- Anything outside the DMS
- Operations, compliance, onboarding screens
- System administration
- Flow design or debugging
- Any write, modify, create, or delete action

**Core principle for Copilot:** "I can show you how to do it, look up what exists, and explain what things mean — but I cannot make changes for you. I am observation-only."

### 3. Resource Site (for staff access)

Power Pages site in the Prod environment. Anonymous access. Serves as a general-purpose internal utility hub.

**Site pages:**

| Path | Content |
|------|---------|
| `/` | Home — card grid linking to all sections |
| `/guides/getting-started` | Login and navigation guide |
| `/guides/sales-proposal` | Sales Proposal walkthrough |
| `/guides/work-order` | Work Order walkthrough |
| `/guides/amendment` | Amendment walkthrough |
| `/guides/vendor-msa` | Vendor MSA walkthrough |
| `/reviews` | Sites and pages shared for staff review (frequently updated) |
| `/tools` | Tag builder, quick links, admin shortcuts |
| `/assistant` | Copilot Studio DMS assistant chat widget |

**Site properties:**
- Anonymous access — no login required
- Static HTML content generated from Markdown build pipeline
- Screenshots embedded inline
- Copilot Studio widget on `/assistant` page
- No Dataverse tables exposed through the site itself
- Responsive — desktop and tablet
- `*.powerappsportals.com` domain — already whitelisted by corporate security

### Copilot Studio Configuration

**Embedding:** The Copilot is embedded on the `/assistant` page via the Copilot Studio web chat JavaScript snippet. This is a standard Microsoft-provided embed — no custom iframe or component needed.

**Knowledge ingestion:** The 6 grounding documents (`dms-processes.md` through `dms-glossary.md`) are uploaded to Copilot Studio as file-based knowledge sources. When documents are updated, re-upload replaces the previous versions.

**System prompt:** The content of `dms-copilot-system-prompt.md` is pasted into Copilot Studio's system message configuration. It is not uploaded as a knowledge source.

**Dataverse access:** Copilot Studio connects to Dataverse via its built-in Dataverse connector. Tables are configured with **read-only** topic actions — no create, update, or delete actions are permitted. Tables exposed for read:

- `dcfg_contracts` — contract records, status, metadata
- `dcfg_msas` — MSA records
- `dcfg_customers` — customer names, programs
- `dcfg_vendors` — vendor names
- `dcfg_properties` — locations (entity set: `dcfg_properties`, NOT `dcfg_propertys`)
- `dcfg_document_requests` — document generation status
- `dcfg_ap_cost_codes` — AP cost code lookups

**No other tables are exposed.** Specifically: no audit logs, no user records, no config tables, no flow metadata.

**Licensing:** Copilot Studio requires a license for the Prod environment. The operator will verify licensing availability during the provisioning prerequisite step.

### Guide Page Navigation

Each guide page includes:
- **Sticky sidebar table of contents** — auto-generated from headings, visible on desktop
- **Anchor links per wizard step** — enables staff to share deep links to specific instructions (e.g., `/guides/work-order#step-3-contractor-and-signer`)
- **Previous / Next navigation** — links between guide pages in sequence

## Power Pages Site Creation

Claude creates the Power Pages site via Dataverse API in an **inactive state** (`statecode=1`). The operator activates it when ready.

| Property | Value |
|----------|-------|
| Environment | Prod (`org06f5de0b.crm.dynamics.com`) |
| Desired subdomain | `dcfg-resources.powerappsportals.com` (final name assigned by Power Pages) |
| Data model | Enhanced Data Model (consistent with all DCFG sites) |
| Authentication | Anonymous access enabled, no authentication required |
| pac auth index | `[3]` (Prod) — restore to `[1]` (Test) after any deployment |
| Solution | `DCFGSystemTest` (same as all environments) |
| Initial state | **Inactive** (`statecode=1`) — Claude creates, operator activates |

**Workflow:** Claude creates the `powerpagessite` record and all content in inactive state. Operator reviews, then activates the site when satisfied. This eliminates the provisioning prerequisite and keeps the operator in control of go-live.

## Operating Modes

The resource site operates in two modes. **Base Mode is fully functional without Copilot.** Copilot is an optional enhancement layer.

### Base Mode (no Copilot)
- User guides (HTML + screenshots)
- Review items (shared links for staff review)
- Tools & quick links
- The `/assistant` page shows a message: "AI Assistant coming soon — for now, use the guides above"
- **No Copilot Studio license required**
- **No Dataverse read access needed**

### Copilot Mode (optional add-on)
- Everything in Base Mode, plus:
- `/assistant` page embeds the Copilot Studio chat widget
- Copilot answers DMS questions grounded on the knowledge base
- Copilot queries Dataverse tables (read-only)
- **Requires:** Copilot Studio license, KB docs uploaded, system prompt configured

**The user manual must also work in both modes.** The "Need Help?" section in the manual references the AI Assistant, but must gracefully handle the case where Copilot is not yet configured — linking to the guides instead.

**Transition:** The operator activates Copilot Mode by:
1. Creating the Copilot in Copilot Studio
2. Uploading the 6 KB grounding documents
3. Pasting the system prompt
4. Providing Claude with the Copilot embed snippet
5. Claude updates the `/assistant` page to embed the widget

## Deployment Mechanism

Content is published to the Power Pages resource site via Dataverse API, creating and updating `powerpagecomponent` records. This is the same Enhanced Data Model pattern used across all DCFG sites.

**How Claude publishes content:**

1. **Screenshots and static assets:** Uploaded as `powerpagecomponent` web file records. Referenced by URL in HTML content. Never base64-inline — keeps page records small and cacheable.
2. **Guide pages (HTML from Markdown):** Create `powerpagecomponent` records with `type = webpage` and HTML content in the `content` JSON field. Screenshots referenced as `<img src="/{web-file-path}">`.
3. **Review items and link cards:** Same mechanism — `powerpagecomponent` records with HTML content following the appropriate template.
4. **Removal:** Set `statecode = 1` (inactive) on the `powerpagecomponent` record. Never delete.

**All `powerpagecomponent` records must include the `powerpagesiteid` lookup** pointing to the resource site. This associates pages and files with the correct site. The websiteId is obtained after provisioning and stored in the `resource-site-publish` skill configuration.

**Deployment commands:**

```bash
# Authenticate to Prod
pac auth select --index 3

# For bulk content updates (guides with screenshots):
# Use PowerShell + Dataverse API to create/update powerpagecomponent records
# See resource-site-publish skill for exact API calls

# Always restore to Test after deployment
pac auth select --index 1
```

**This site does NOT use `pac pages upload-code-site`.** That command is for SPA deployments only. The resource site is pure content — web pages created via Dataverse API, not compiled code.

## Architecture

### Silo Boundaries

```
┌─────────────────────────────────────┐
│  DCFG Resources Site (this spec)    │
│                                     │
│  - Power Pages site in Prod         │
│  - Static HTML guides               │
│  - Copilot Studio (read-only)       │
│  - Reviews, tools, links            │
│                                     │
│  CAN READ:                          │
│    - Dataverse tables (via Copilot) │
│    - User manual content            │
│    - Screenshot library             │
│                                     │
│  CANNOT:                            │
│    - Write to any database          │
│    - Touch the SPA codebase         │
│    - Modify any environment         │
│    - Share code with the SPA        │
│    - Deploy through SPA pipeline    │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  DCFG SPA (separate, untouched)     │
│                                     │
│  - C:\DCFG\spa\dcfg-shell\         │
│  - Own build pipeline               │
│  - Own deployment                   │
│  - No knowledge of resource site    │
└─────────────────────────────────────┘
```

### Roles

| Role | Access | Responsibility |
|------|--------|---------------|
| **Claude** (Publisher) | Write access to resource site content | Builds guides, captures screenshots, creates pages, manages content, writes knowledge base |
| **Copilot** (Assistant) | Read-only Dataverse, read knowledge base | Answers DMS questions, references guides, looks up records. Zero write access. |
| **Staff** (Consumer) | Anonymous read access to site | Reads guides, clicks review links, uses tools, asks Copilot questions |
| **Operator** (Joseph) | Directs Claude | Decides what gets published, reviewed, or removed |

### Publishing Workflow

The resource site is a frequently-used internal utility. Claude must support rapid content publishing via a skill.

**Skill: `resource-site-publish`**

Triggers: "publish X to the resource site", "share this with the team", "add this to resources", "put this on the internal site", "send this for review"

Claude's steps when triggered:
1. Determine content type (review, link, guide, tool)
2. Create page from the appropriate template
3. Add title, description, URL, notes, screenshot if applicable
4. Publish to the correct section of the resource site
5. Provide direct link for operator to share with staff

For removal: soft-deactivate the page (never hard delete).

**Content templates:**

- **Review Item** — title, posted date, description, URL (clickable), checklist of what to review
- **Link Card** — icon, title, description, URL
- **Guide Page** — full HTML rendered from Markdown with inline screenshots
- **Tool Page** — embedded HTML tool or iframe

## Screenshot Capture

### Playwright Test Architecture

Screenshots are captured by Playwright tests running against the Test environment with curated demo data. The tests produce the screenshots; the screenshots are then embedded in the Markdown guides and published to the resource site as static images.

**Authentication:** Manual-pause pattern for Windows Hello. Test opens browser, pauses, operator authenticates, test resumes.

**File structure:**

```
C:\dcfg\tests\user-manual\
  playwright.config.ts      — base URL (test portal), screenshot output path
  auth.setup.ts             — manual pause for Windows Hello, saves auth state
  demo-data.ts              — curated demo dataset constants
  tests\
    getting-started.spec.ts — dashboard, nav, common UI (~6 screenshots)
    sales-proposal.spec.ts  — 4 wizard steps + review (~8 screenshots)
    work-order.spec.ts      — 5 wizard steps + review (~10 screenshots)
    amendment.spec.ts        — 5 wizard steps + review (~10 screenshots)
    vendor-msa.spec.ts      — 5 wizard steps + review (~8 screenshots)
```

**Screenshot output:** Saved directly to `C:\dcfg\docs\user-manual\screenshots\{flow-name}\` so Markdown can reference them with relative paths.

**Capture pattern per step:**
1. Navigate to wizard / advance to step
2. Fill fields with demo data
3. Wait for UI to settle (no spinners, dropdowns populated)
4. Capture full-page screenshot
5. Capture focused element screenshots where useful (e.g., a specific dropdown, the Exhibit A table)
6. Advance to next step

### Demo Dataset

Curated fake data created in the Test environment only. Designed to look professional and realistic in screenshots.

| Entity | Demo Record | Used In |
|--------|------------|---------|
| Customer | Parkview Properties LLC | All 4 flows |
| Vendor | Summit Mechanical Services | WO, Amendment, Vendor MSA |
| Location | Parkview Tower — 500 Commerce Dr, Atlanta GA | WO, Amendment, Proposal |
| Signer | Maria Chen, VP Operations | All 4 flows |
| Parent WO | WO-2026-DEMO-001 (Parkview HVAC Retrofit) | Amendment |
| Cost Codes | 5100 (HVAC Labor), 5200 (HVAC Materials) | WO, Amendment |
| MSA Package | Package B — Extended Service | Sales Proposal |

Demo data is created by the Playwright test suite as part of its setup phase — not a manual prerequisite. The tests create records if they don't exist, and reuse them on subsequent runs. Never created in Prod — screenshots are static images published to the resource site.

## File Map

### Documentation

```
C:\dcfg\docs\user-manual\
  index.md                          — master index linking all guides
  getting-started.md                — login, navigation, common UI
  guide-sales-proposal.md           — Sales Proposal walkthrough
  guide-work-order.md               — Work Order walkthrough
  guide-amendment.md                — Amendment walkthrough
  guide-vendor-msa.md               — Vendor MSA walkthrough
  build.mjs                         — Node script: Markdown → HTML + PDF (see Build Toolchain)
  screenshots\
    getting-started\*.png
    sales-proposal\*.png
    work-order\*.png
    amendment\*.png
    vendor-msa\*.png
```

### Copilot Knowledge Base

```
C:\dcfg\docs\copilot-kb\
  dms-processes.md                  — all 4 creation flows step-by-step
  dms-field-reference.md            — every field, every screen
  dms-business-rules.md             — contract families, TPA, soft delete, WO lifecycle
  dms-status-lifecycles.md          — all status transitions
  dms-troubleshooting.md            — common errors and resolutions
  dms-glossary.md                   — terms, acronyms, entity names
  dms-copilot-system-prompt.md      — system prompt for Copilot Studio
```

### Playwright Tests

```
C:\dcfg\tests\user-manual\
  playwright.config.ts
  auth.setup.ts
  demo-data.ts
  tests\
    getting-started.spec.ts
    sales-proposal.spec.ts
    work-order.spec.ts
    amendment.spec.ts
    vendor-msa.spec.ts
```

## Build Pipeline

```
1. Create demo data in Test env (one-time)
2. Run Playwright tests → screenshots saved to docs/user-manual/screenshots/
3. Write/update Markdown guides referencing screenshots
4. Run build.mjs → generates HTML + PDF from Markdown
5. Publish HTML to resource site Power Pages (via Claude skill / Dataverse API)
6. Update knowledge base docs if SPA behavior changed
7. Re-upload knowledge base docs to Copilot Studio
8. Staff accesses at *.powerappsportals.com — no login
```

To update after SPA changes: re-run steps 2–7. The Playwright tests are the single source of screenshot truth. The knowledge base must stay in sync with the guides.

### Build Toolchain

The build script is a cross-platform Node.js script (`build.mjs`), not a shell script. The environment is Windows 11.

| Tool | Purpose | Package |
|------|---------|---------|
| `markdown-it` | Markdown → HTML rendering | `npm i markdown-it` |
| `markdown-it-anchor` | Heading anchor links for deep linking | `npm i markdown-it-anchor` |
| `markdown-it-toc-done-right` | Auto-generated table of contents | `npm i markdown-it-toc-done-right` |
| `puppeteer` | HTML → PDF generation | `npm i puppeteer` |

The build script:
1. Reads each `.md` guide
2. Renders to HTML with a shared template (nav header, sidebar TOC, prev/next links)
3. Embeds screenshots as relative `<img>` references
4. Writes HTML files to `docs/user-manual/dist/`
5. Generates PDF files to `docs/user-manual/dist/pdf/`

```bash
# Build all guides
node docs/user-manual/build.mjs

# Output
# docs/user-manual/dist/*.html
# docs/user-manual/dist/pdf/*.pdf
# docs/user-manual/dist/screenshots/ (copied)
```

## Constraints

- **Read-only is a core principle.** Copilot reads Dataverse but never writes. The resource site exposes no Dataverse tables. No component of this system creates, edits, or deletes records in any environment.
- **Standalone silo.** No association with the SPA. No shared code, no shared deployment, no shared components. The SPA does not know this system exists.
- **DMS-scoped.** The Copilot assistant answers questions about the Document Management System only. It is not a general chatbot. Out-of-scope questions get a polite redirect.
- **Soft delete only.** Content removal on the resource site deactivates pages, never deletes them.
- **Review item lifecycle.** Review items on `/reviews` are active until the operator says to take them down. No auto-expiration. Operator manages the lifecycle — Claude deactivates on request.
- **Test env for screenshots, Prod for hosting.** Demo data and Playwright run against Test. The resource site lives in Prod. Screenshots cross the boundary as static image files only.
- **Anonymous access.** No login required for the resource site. Staff access via direct URL.
- **Two modes.** Base Mode works without Copilot (guides, reviews, tools only). Copilot Mode is an optional add-on requiring separate licensing and configuration. The site and manual must be fully functional in Base Mode.
- **Inactive creation.** Claude creates the site and all content in inactive state. The operator activates when ready. Claude never activates a site.
