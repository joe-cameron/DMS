# DCFG Build Plan — Master Handoff for Claude Code CLI

## Session Date: March 28, 2026
## Purpose: Everything designed in this session, organized for implementation.

Read this file completely before starting any work. It references companion files that contain the full specifications. This document tells you WHAT to build and WHERE the details live. The companion files tell you HOW.

---

## OVERVIEW — What Was Designed

This session produced 7 interconnected systems. They build on each other in dependency order:

```
1. Company Brain (SharePoint + Dataverse)     ← Foundation layer
2. Property Location Intelligence Overlay      ← Uses company brain + Dataverse
3. Decades Brain Chat Interface                ← Uses everything above
4. Autoresearch Skill Improvement              ← Optimizes existing DCFG skills
5. Personal OneDrive Brain                     ← Parallel personal system
6. Skills Installation                         ← Third-party skills to install
7. Dispatch/Scheduled Tasks Integration        ← Automation layer on top
```

---

## PHASE 1: Company Brain Infrastructure

### 1A: SharePoint Document Library Setup

**What:** Create a `company-brain` document library in the DCFG SharePoint site with the folder structure and starter JSON files.

**Spec:** `dcfg-company-brain-system-design.md`

**Starter files:** `dcfg-company-brain-sharepoint-starter.zip` — Unzip and upload entire `company-brain/` folder to the new document library.

**Folders to create:**
```
company-brain/
  _config/
    brain-config.json
    document-templates.json
    report-specs/
      RPT-WO-001.md
      RPT-PGM-001.md
      RPT-CAP-001.md
  operations/
    vendor-knowledge.json
    property-knowledge.json
    certification-status.json
    seasonal-calendar.json
    asset-lifespans.json          ← Create from lifespan reference table in property intelligence spec
  sales/
    customer-knowledge.json
    proposal-playbook.json
    market-intelligence.json
  contracts/
    contract-decisions.json
    billing-exceptions.json
    template-notes.json
  company/
    team-directory.json
    procedures.json
    vendor-contacts.json
    system-credentials.json
  projects/
    contracting-suite/
      session-state.json
      decisions-log.json
      schema-changes.json
```

**Files that need to be deployed from today's outputs:**
- `company-brain-config-bundle.zip` → contains `_config/report-specs/` with RPT-WO-001.md, RPT-PGM-001.md, RPT-CAP-001.md
- `document-templates.json` → goes to `_config/document-templates.json`

**Naming rules (MANDATORY):** All lowercase, kebab-case, no spaces anywhere. See system design doc Section 9 for full path safety rules. OneDrive root may contain spaces — always quote paths.

### 1B: Dataverse — dcfg_brain_insight Table

**What:** Create the `dcfg_brain_insight` table in Dataverse with 13 columns, 4 choice fields, and 7 lookup relationships to existing DCFG tables.

**Script:** `OP-Brain-Insight.ps1`

**Run:**
```powershell
Unblock-File C:\DCFG\OP-Brain-Insight.ps1
pwsh -ExecutionPolicy Bypass -File C:\DCFG\OP-Brain-Insight.ps1
```

**Creates lookups to:** dcfg_customer, dcfg_vendor, dcfg_contract, dcfg_msa, dcfg_property, dcfg_program, dcfg_onboarding_case

**After running:** Create table permissions for dcfg_brain_insight (Read for all roles, Write for Admin only).

**Entity set name will be:** `dcfg_brain_insights`

---

## PHASE 2: Property Location Intelligence Overlay

**What:** Add an intelligence section to the existing property location detail screen in the mobile app. Shows recent work history, asset age alerts (against lifespan reference data), and property notes from the company brain.

**Spec:** `feature-spec-property-location-intelligence.md`

**Key technical details:**
- Collapsed by default — shows count chips only: `[4 recent contracts] [🟠 2 asset alerts] [1 note]`
- Expands on tap, max 5 items per section
- Asset age calculated client-side: `age = today - install_date`, compared against lifespan reference by property type
- Status thresholds: beyond-lifespan (red dot), end-of-life (amber dot), aging (no indicator)
- Read-only — no action buttons, no forms
- If nothing to show, the entire section is absent

**Data sources:**
1. `dcfg_contracts` filtered by property (recent work history)
2. `dcfg_property_assets` with lifespan calculation (asset alerts)
3. `company-brain/operations/property-knowledge.json` filtered by property GUID (notes)

**May require new Dataverse table:** `dcfg_property_asset` — schema defined in the spec.

---

## PHASE 3: Decades Brain Chat Interface

**What:** A chat-based AI assistant embedded in the `dcfg-shell` menu system. Operations-primary tool. Reads from Dataverse (20+ tables), SharePoint (company brain), UpKeep (when connected). Generates documents and presentations from registered templates.

**Spec:** `decades-brain-technical-spec.md` — This is the primary build document. It contains:
- Complete entity set name reference with all DCFG gotchas
- All column name corrections
- All choice field integer-to-label mappings
- 6 cross-system query patterns with full OData
- Role-based access model (Operations, Sales, Admin)
- First-use onboarding and capability explorer
- Document generation with production report specs (RPT-WO-001, RPT-PGM-001, RPT-CAP-001)
- Component structure (React files, hooks, utils)
- Error handling table
- Deployment commands

**Key constraints:**
- NO user email access — system accounts only (admin-configured)
- Read-only against Dataverse (Phase 1) — only writes to company brain knowledge files in SharePoint
- Entity set for properties is `dcfg_propertys` NOT `dcfg_properties`
- Budget_committed is NEVER written by the UI
- Audit log is CREATE ONLY
- All status fields display labels, never integers

**Shell integration:**
- Mounts in `dcfg-shell`
- Activates the existing reserved AI button (currently `btn-off`)
- Slide-over or overlay — does not destroy current active sub-app
- Route: `/brain`

**Document generation:**
- Template registry: `company-brain/_config/document-templates.json`
- Production reports: Full specs in `company-brain/_config/report-specs/`
- RPT-CAP-001 (Capital Replacement Plan) has TWO modes:
  - Snapshot: 3 slides, point-in-time equipment health, run anytime
  - Renewal: 6 slides, full customer-facing budget proposal with 3 tiers
  - Mode detected from user language — "snapshot/health/status" vs "renewal/capital plan/budget proposal"

**Deploy:**
```bash
cd C:\dcfg\spa\dcfg-shell
npm run build
pac pages upload-code-site --rootPath . --compiledPath dist --siteId 22947376-be10-4bda-a90f-32b855c43045
```

Clear cache: `https://dcfg.powerappsportals.com/_services/about?clearCache=true`

---

## PHASE 4: Autoresearch Skill Improvement

**What:** Apply the Karpathy autoresearch pattern to optimize 4 existing DCFG skills through automated generate → evaluate → mutate loops.

**Plan:** `DCFG_Autoresearch_Improvement_Plan.md`

**Skills to optimize:**
1. power-pages-content-ops (8 binary eval criteria, 40 max score)
2. dataverse-schema-ops (7 criteria, 35 max)
3. dcfg-ux-psychology (6 criteria, 30 max)
4. power-automate-flow-builder (7 criteria, 35 max)

**Base autoresearch skill:** `autoresearch-diagrams.zip` — Already installed. Needs adaptation from image generation to text/code generation for each DCFG skill.

**Adaptation required:**
- Generator: Call Claude API with SKILL.md as system prompt + random test prompt as user message
- Evaluator: Claude Sonnet reads generated output, answers binary criteria
- Mutator: Reads failure analysis, rewrites SKILL.md
- The SKILL.md replaces `prompt.txt` as the thing being optimized

**Estimated cost:** ~$3-5 per skill for 20 cycles, ~$12-20 total

---

## PHASE 5: Personal OneDrive Brain

**What:** A personal knowledge/memory system stored as JSON files on OneDrive. Portable across any AI tool.

**Spec:** `onedrive-brain-system-design.md`
**Starter files:** `onedrive-brain-starter.zip`

**This is independent of the company brain.** The company brain lives in SharePoint for the team. The personal brain lives in OneDrive for the individual.

---

## PHASE 6: Third-Party Skills Installation

**What:** Install credible third-party skills for development methodology, security, research, and testing.

**Guide:** `dcfg-skills-download-guide.md`

**Install now (Claude Code CLI):**

```bash
# Superpowers — development methodology (Jesse Vincent)
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace

# Anthropic official skills (frontend-design, webapp-testing, skill-creator)
/plugin marketplace add anthropics/skills
/plugin install example-skills@anthropic-agent-skills

# sanjay3290/ai-skills (deep-research, postgres, Google Workspace)
/plugin add https://github.com/sanjay3290/ai-skills
```

**Clone for reference:**
```bash
# Trail of Bits security skills
git clone https://github.com/trailofbits/skills ~/.claude/skills/trailofbits-security
```

---

## PHASE 7: Dispatch + Scheduled Tasks + Computer Use

**What:** Wire the company brain intelligence flows, Decades Brain, and field operations into Anthropic's new primitives.

**No spec produced yet — this is the architectural direction:**

**Scheduled Tasks (cloud, laptop off):**
- Replace Power Automate intelligence flows with Claude scheduled tasks that can reason across systems
- `brain-cert-expiry`: Daily 6 AM — check certs, cross-reference vendor reliability, write insights to dcfg_brain_insights
- `brain-stale-proposals`: Weekly Monday 7 AM — check unsent/unsigned proposals, factor in customer preferences from knowledge files
- `brain-onboarding-stalls`: Daily 7 AM — detect stalled cases, identify which checklist step is blocking
- `brain-budget-health`: Weekly Friday 4 PM — program budget utilization with trend detection
- Connect to DCFG Dataverse via MCP server, SharePoint via Graph API MCP

**Dispatch (phone → desktop):**
- Field staff dispatch work orders from property sites
- Tyler dispatches DocuSign operations
- Ira/Steve dispatch proposal preparation while traveling
- All operations dispatch to Cowork sessions on the DCFG desktop

**Computer Use (no-API tools):**
- DocuSign envelope management (void, resend)
- Vendor portal navigation (insurance certs, licensing)
- State filing systems
- Any browser-based tool that requires clicking through screens

**Build priority:** Scheduled Tasks first (highest value, no desktop dependency), Dispatch second (requires desktop to be on), Computer Use third (highest capability but lowest reliability at ~50% success rate for complex multi-app tasks).

---

## FILE MANIFEST — What Was Produced Today

| File | Purpose | Phase |
|---|---|---|
| `dcfg-company-brain-system-design.md` | Full architecture for the company brain | 1 |
| `dcfg-company-brain-sharepoint-starter.zip` | 18 JSON starter files for SharePoint | 1 |
| `OP-Brain-Insight.ps1` | Dataverse schema script for dcfg_brain_insight table | 1 |
| `document-templates.json` | Template registry with 9 templates (3 production, 6 ad-hoc) | 1/3 |
| `company-brain-config-bundle.zip` | Report specs: RPT-WO-001, RPT-PGM-001, RPT-CAP-001 | 1/3 |
| `feature-spec-property-location-intelligence.md` | Property overlay with asset lifespan tracking | 2 |
| `decades-brain-technical-spec.md` | Complete Decades Brain chat interface spec | 3 |
| `feature-spec-decades-brain-chat.md` | Earlier version (superseded by technical spec) | — |
| `DCFG_Autoresearch_Improvement_Plan.md` | Autoresearch plan for 4 DCFG skills | 4 |
| `autoresearch-diagrams.zip` | Base autoresearch skill (needs adaptation) | 4 |
| `onedrive-brain-system-design.md` | Personal brain architecture | 5 |
| `onedrive-brain-starter.zip` | Personal brain starter files | 5 |
| `dcfg-skills-download-guide.md` | Categorized third-party skills with install commands | 6 |

---

## EXECUTION ORDER

1. Run `OP-Brain-Insight.ps1` to create the Dataverse table
2. Create `company-brain` document library in SharePoint, upload starter files
3. Deploy report specs and document-templates.json to `_config/`
4. Install third-party skills (Superpowers, Trail of Bits, sanjay3290)
5. Build property location intelligence overlay (Phase 2 spec)
6. Build Decades Brain chat interface (Phase 3 spec — this is the largest build)
7. Run autoresearch optimization on DCFG skills (Phase 4 — can run in parallel)
8. Configure scheduled tasks and Dispatch when ready (Phase 7)

---

## CRITICAL REMINDERS FOR THE BUILD AI

- Entity set for properties is `dcfg_propertys` — NOT `dcfg_properties`
- All file paths in company brain: lowercase, kebab-case, no spaces, forward slashes
- Budget_committed is NEVER written by the UI — read-only everywhere
- Audit log is CREATE ONLY — never PATCH or DELETE
- No user email access from Decades Brain — system accounts only
- Connect URL must have trailing slash: `https://org0c17e98d.crm.dynamics.com/`
- All Dataverse operations inside `Invoke-DataverseCommands { }`
- Status fields display labels, never raw integers
- Role-restricted actions are REMOVED from DOM, not disabled
- The Decades Brain design principle: work comes OFF the desk, not ON it. Every interaction should either answer a question completely or offer to take the next action. Never produce output that creates more work for the user to process.
