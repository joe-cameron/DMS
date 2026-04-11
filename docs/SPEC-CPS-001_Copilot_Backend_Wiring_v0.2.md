# SPEC-CPS-001 — Copilot Studio Backend Wiring

## HR AI & Nora: Claude-Powered Agent Configuration

**Status:** Draft | **Version:** 0.2 | **Date:** April 5, 2026
**Changes in v0.2:** Added Project Section wiring (nora-015 through nora-026), new knowledge sources (k-nora-006 through k-nora-013), new topics (t-nora-009 through t-nora-020), new guardrails (g-011 through g-016), document request write capability, SPA navigation, custom vocabulary additions  
**Author:** Joe Cameron, Director of AI Integration  
**Organization:** Decades Construction & Facilities Group

---

## 1. Executive Summary

This document specifies how to configure two Copilot Studio agents — **HR AI** and **Nora** — with Claude as the primary reasoning engine and the DCFG multi-agent harness (Planner, Generator, Evaluator, Cowork) integrated where appropriate. Both agents deploy via Microsoft Teams and surface through the Living Vans interface (SPEC-VAN-001).

Both vans support voice interaction via click-and-hold mic activation. Nora is voice-primary (enabled by default). HR AI has voice capability built in but disabled by default.

Both agents are **table-driven** — their behaviors, capabilities, knowledge sources, and access controls are defined in configuration tables, not hardcoded. This enables rapid iteration without redeploying the agents.

**DCFG has access to:**

- Microsoft Copilot Studio (M365 license)
- Claude models via Copilot Studio model selector (available natively since late 2025)
- Azure AI Foundry (Claude API access, billed through Azure/MACC)
- ChatGPT Enterprise (couple of seats)
- Gemini Nano (device-level inference)

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                      LIVING VANS UI                       │
│                (SPEC-VAN-001 overlay layer)                │
│                                                            │
│   HR Van                                Nora Van           │
│   [click → text chat]          [click-hold → mic active]   │
│   [click-hold → mic (disabled  [click → text fallback]     │
│    by default, enable in cfg)]                              │
└──────────┬────────────────────────────────┬────────────────┘
           │                                │
           ▼                                ▼
┌────────────────────────┐   ┌──────────────────────────────┐
│    COPILOT STUDIO      │   │      COPILOT STUDIO          │
│     HR AI Agent        │   │       Nora Agent              │
│                        │   │                                │
│  Config: HR_CONFIG     │   │  Config: NORA_CONFIG           │
│  table-driven          │   │  table-driven                  │
│                        │   │                                │
│  Model: per config tbl │   │  Model: per config tbl         │
│  Knowledge: per cfg    │   │  Knowledge: per cfg            │
│  Voice: per cfg        │   │  Voice: per cfg                │
│  Channel: Teams        │   │  Channel: Teams + Power Pages  │
└────────────────────────┘   └──────────────┬───────────────┘
                                             │
                                             │ Joe only
                                             ▼
                              ┌──────────────────────────┐
                              │    DCFG AGENT HARNESS     │
                              │                            │
                              │  Planner  → route/research │
                              │  Generator → build/create  │
                              │  Evaluator → verify/check  │
                              │  Cowork   → GUI automation │
                              └──────────────────────────┘
```

---

## 3. Table-Driven Configuration

Both agents read their behavior from configuration tables. Nothing about how these agents act is hardcoded — every capability, knowledge source, access permission, and behavioral rule is a row in a table. Change a row, change the behavior. No redeployment.

### 3.1 Configuration Table Location

These tables live in Dataverse within the `DCFGContractingSuite` solution. They are admin-editable, not user-facing.

| Table | Purpose |
|-------|---------|
| `dcfg_agent_config` | Master config per agent: model, voice settings, channels, active/inactive |
| `dcfg_agent_capabilities` | What each agent can do, per role |
| `dcfg_agent_knowledge` | Which knowledge sources are connected, per agent |
| `dcfg_agent_topics` | Trigger phrases, response rules, escalation paths |
| `dcfg_agent_voice` | Voice settings per agent: enabled/disabled, TTS voice, STT model, mic behavior |
| `dcfg_agent_guardrails` | Hard rules that cannot be overridden: read-only firewall, contact restrictions, escalation requirements |

### 3.2 Master Agent Config Table (`dcfg_agent_config`)

| Column | HR AI | Nora |
|--------|-------|------|
| `agent_id` | `dcfg-hr-ai` | `dcfg-nora` |
| `display_name` | DCFG HR Assistant | Nora |
| `van_binding` | HR Van | Nora Van |
| `primary_model_default` | Claude Sonnet 4.6 | Claude Sonnet 4.6 |
| `primary_model_joe` | Claude Sonnet 4.6 | Claude Opus 4.6 |
| `fallback_model` | GPT-4o | GPT-4o |
| `voice_enabled` | `false` | `true` |
| `voice_input_gesture` | click-hold | click-hold |
| `text_input_gesture` | click | click |
| `channels` | Teams | Teams, Power Pages |
| `audience` | All roles | All roles (role-differentiated) |
| `proactive_allowed` | `false` | `true` (Joe only) |
| `dataverse_write` | `false` | `false` |
| `status` | Active | Active |

### 3.3 Capabilities Table (`dcfg_agent_capabilities`)

Each row = one capability. `enabled` flag per role.

**HR AI Capabilities:**

| capability_id | capability | admin | sales | ops | field | notes |
|---------------|-----------|-------|-------|-----|-------|-------|
| hr-001 | Answer policy questions | ✅ | ✅ | ✅ | ✅ | Search knowledge base |
| hr-002 | Benefits enrollment guidance | ✅ | ✅ | ✅ | ✅ | Seasonal — activate during open enrollment |
| hr-003 | PTO balance inquiry | ✅ | ✅ | ✅ | ✅ | Requires HRIS connector (future) |
| hr-004 | Onboarding checklist | ✅ | ✅ | ✅ | ✅ | New hire orientation steps |
| hr-005 | Expense policy lookup | ✅ | ✅ | ✅ | ✅ | Link to submission tool |
| hr-006 | Escalation to HR contact | ✅ | ✅ | ✅ | ✅ | Provide contact info, offer to draft email |
| hr-007 | Draft HR email for user | ✅ | ✅ | ✅ | ✅ | User reviews before sending |
| hr-008 | Redirect to Nora | ✅ | ✅ | ✅ | ✅ | For operational questions outside HR scope |
| hr-009 | Voice interaction | ❌ | ❌ | ❌ | ❌ | Built but disabled by default. Enable per row. |

**Nora Capabilities:**

| capability_id | capability | admin (Brook) | sales | ops | field | joe | notes |
|---------------|-----------|---------------|-------|-----|-------|-----|-------|
| nora-001 | Read contracts from Dataverse | ✅ | ✅ | ✅ | ❌ | ✅ | Read-only. Entity set: `dcfg_propertys` (NOT properties) |
| nora-002 | Read locations from Dataverse | ✅ | ✅ | ✅ | ✅ | ✅ | Read-only |
| nora-003 | Read work orders | ✅ | ❌ | ✅ | ✅ | ✅ | Field sees only their assigned WOs |
| nora-004 | Read programs & budgets | ✅ | ❌ | ✅ | ❌ | ✅ | Budget refs programs, not MSAs |
| nora-005 | Read asset lifecycle data | ✅ | ❌ | ✅ | ✅ | ✅ | For capital planning queries |
| nora-006 | Document building (pptx, docx) | ✅ | ✅ | ❌ | ❌ | ✅ | Brook primary target |
| nora-007 | Answer operational process Qs | ✅ | ✅ | ✅ | ✅ | ✅ | From playbook knowledge |
| nora-008 | HubSpot queries (via Cowork) | ❌ | ❌ | ❌ | ❌ | ✅ | Future phase. Joe only initially. |
| nora-009 | Route to Agent Harness | ❌ | ❌ | ❌ | ❌ | ✅ | Planner/Generator/Evaluator |
| nora-010 | Proactive initiation | ❌ | ❌ | ❌ | ❌ | ✅ | ONLY Joe. Nora comes to you. |
| nora-011 | Schema diagnostics | ❌ | ❌ | ❌ | ❌ | ✅ | Full Dataverse schema read |
| nora-012 | Voice interaction | ✅ | ✅ | ✅ | ✅ | ✅ | Enabled by default for all |
| nora-013 | Redirect to HR AI | ✅ | ✅ | ✅ | ✅ | ✅ | For HR questions outside Nora scope |
| nora-014 | Post-job content generation | ❌ | ✅ | ❌ | ❌ | ✅ | LinkedIn/FB/X posts + YouTube script on job close |
| nora-015 | Read RFP packages | ✅ | ❌ | ✅ | ❌ | ✅ | RFP status, vendor responses, bid amounts. Entity set: dcfg_rfp_packages |
| nora-016 | Read proposals/bid comp data | ✅ | ❌ | ✅ | ❌ | ✅ | Side-by-side vendor comparison from parsed bid comps |
| nora-017 | Produce bid comp xlsx | ✅ | ❌ | ✅ | ❌ | ✅ | Pre-filled 19-tab Multi Trade Bid Template. Uses bid_comp_schema.json. |
| nora-018 | Produce estimate xlsx | ✅ | ❌ | ✅ | ❌ | ✅ | Pre-filled 6-tab Estimate Template. Uses estimate_schema.json. |
| nora-019 | Produce Sage Budget rollup | ✅ | ❌ | ✅ | ❌ | ✅ | Program-level CSI rollup — aggregates all projects into the budget presentation format |
| nora-020 | Search SharePoint project sites | ✅ | ✅ | ✅ | ✅ | ✅ | Find any file across all {JobNumber}{Address} sites via Graph API |
| nora-021 | Create document request (contracts) | ✅ | ✅ | ✅ | ❌ | ✅ | Guided: fuzzy-match customer/vendor → prompt fields → confirm → write dcfg_document_requests |
| nora-022 | Create document request (proposals) | ✅ | ✅ | ❌ | ❌ | ✅ | Guided: fuzzy-match customer/vendor → rates → confirm → write dcfg_document_requests |
| nora-023 | Navigate SPA screens | ✅ | ✅ | ✅ | ✅ | ✅ | Change active screen on "take me to" / "show me". Pause and flag issues on arrival. |
| nora-024 | Project budget vs actual analysis | ✅ | ❌ | ✅ | ❌ | ✅ | Cross-project cost comparison, factor-adjusted for union/prevailing wage/regulatory |
| nora-025 | Vendor performance analysis | ✅ | ❌ | ✅ | ❌ | ✅ | On-time rate, cost variance, change order rate — factor-adjusted across completed jobs |
| nora-026 | Produce project tracker xlsx | ✅ | ❌ | ✅ | ❌ | ✅ | Tracker with Dashboard, populated from Dataverse project data |

### 3.4 Knowledge Sources Table (`dcfg_agent_knowledge`)

| knowledge_id | agent | source_type | source_ref | description | active |
|--------------|-------|-------------|------------|-------------|--------|
| k-hr-001 | HR AI | SharePoint | `/sites/DCFG/HR/Policies` | Employee handbook, HR policies | ✅ |
| k-hr-002 | HR AI | SharePoint | `/sites/DCFG/HR/Benefits` | Benefits guides, enrollment docs | ✅ |
| k-hr-003 | HR AI | File upload | `HR_FAQ.md` | Structured Q&A for common questions | ✅ |
| k-nora-001 | Nora | Dataverse | `org0c17e98d.crm.dynamics.com` | DCFGContractingSuite — all read-only tables | ✅ |
| k-nora-002 | Nora | SharePoint | `/sites/DCFG/Operations/Playbooks` | Operational procedures | ✅ |
| k-nora-003 | Nora | SharePoint | `/sites/DCFG/Contracts/Templates` | Contract templates, Exhibit docs | ✅ |
| k-nora-004 | Nora | File upload | `DCFG_Schema_Consolidated.md` | Dataverse schema reference | ✅ |
| k-nora-005 | Nora | File upload | `DCFG_Merge_Field_Registry.md` | Document merge field registry | ✅ |
| k-nora-006 | Nora | File upload | `bid_comp_schema.json` | Verified structural schema — 19-tab bid comp template (9,911 cells, 577 formulas) | ✅ |
| k-nora-007 | Nora | File upload | `estimate_schema.json` | Verified structural schema — 6-tab estimate template (11,038 cells, 601 formulas) | ✅ |
| k-nora-008 | Nora | File upload | `project-setup-to-rfp-design.md` | Project section spec — data model, process flow, RFP/BidComp architecture | ✅ |
| k-nora-009 | Nora | File upload | `spa-inventory.json` | SPA component inventory — routes, screens, features, API functions | ✅ |
| k-nora-010 | Nora | File upload | `decades-go-user-manual.html` | Complete user manual — every screen and workflow | ✅ |
| k-nora-011 | Nora | File upload | `DCFG_Component_Library.md` | UI component patterns and standards | ✅ |
| k-nora-012 | Nora | SharePoint | `decadesconstructiongroup.sharepoint.com/sites/*` | All project sites — each project has own Teams site with 14 standard folders (Budget, Proposals, Exhibit A/B, Invoices, Change Orders, Closeout, etc.) | ✅ |
| k-nora-013 | Nora | File upload | `nora-operations-agent-definition.md` | Nora's full operations role — help desk, document retrieval, business analyst, guided creation, navigation | ✅ |

### 3.5 Topics Table (`dcfg_agent_topics`)

**HR AI Topics:**

| topic_id | trigger_phrases | action | escalation |
|----------|----------------|--------|------------|
| t-hr-001 | "benefits", "health insurance", "dental", "vision", "401k", "FSA" | Search k-hr-002, return relevant policy excerpt | None |
| t-hr-002 | "PTO", "vacation", "sick day", "time off", "holiday" | Return PTO policy, link to request form | None |
| t-hr-003 | "new hire", "first day", "onboarding", "I'm new" | Return onboarding checklist, key contacts | None |
| t-hr-004 | "expense", "reimbursement", "receipt", "mileage" | Return expense policy, link to submission tool | None |
| t-hr-005 | "talk to HR", "complaint", "harassment", "discrimination" | Provide HR contact info directly. Do NOT attempt to mediate. | Immediate |
| t-hr-006 | "contract", "work order", "location", "job site", "facilities" | Redirect: "That's outside my area — Nora can help." | Redirect to Nora |
| t-hr-007 | "payroll", "direct deposit", "W2", "pay stub" | Provide payroll contact. Do not access payroll data. | None |

**Nora Topics:**

| topic_id | trigger_phrases | action | escalation |
|----------|----------------|--------|------------|
| t-nora-001 | "contract status", "where is the contract", "contract for [customer]" | Query dcfg_contracts, return status + key dates | None |
| t-nora-002 | "locations for [customer]", "how many locations", "property list" | Query dcfg_propertys, return location summary | None |
| t-nora-003 | "work order", "open jobs", "job status" | Query dcfg_workorders, filter by role | None |
| t-nora-004 | "budget", "program budget", "how much left" | Query dcfg_programs for budget health | None |
| t-nora-005 | "asset age", "replacement", "capital plan", "end of life" | Query dcfg_assets, apply RPT-CAP-001 thresholds | None |
| t-nora-006 | "build a presentation", "make a doc", "create a report" | Invoke document building capability (nora-006) | None |
| t-nora-007 | "HR", "benefits", "PTO", "time off", "payroll" | Redirect: "That's an HR question — let me hand you to the HR assistant." | Redirect to HR AI |
| t-nora-008 | "job completed", "job done", "we finished [project]" | Trigger post-job content generation (nora-014) | None |
| t-nora-009 | "RFP status", "bid status", "who responded", "any bids back" | Query dcfg_rfp_packages + dcfg_rfp_vendors, return status summary (nora-015) | None |
| t-nora-010 | "compare bids", "bid comparison", "who's the low bidder", "vendor comparison for" | Query dcfg_proposals for RFP, present side-by-side pricing + gaps (nora-016) | None |
| t-nora-011 | "build me a bid comp", "create bid comp", "bid comp for" | Produce pre-filled 19-tab bid comp xlsx, save to SharePoint Proposals folder (nora-017) | None |
| t-nora-012 | "build me an estimate", "create estimate", "estimate for" | Produce pre-filled 6-tab estimate xlsx, save to SharePoint Budget folder (nora-018) | None |
| t-nora-013 | "find the exhibit", "where's the invoice", "pull up the", "get me the" | Search SharePoint project sites by document type + project/vendor/customer (nora-020) | None |
| t-nora-014 | "create a contract", "new work order", "I need a work order for" | Guided document request: verify names → prompt fields → confirm → submit (nora-021) | None |
| t-nora-015 | "create a proposal", "new proposal for", "MSA for" | Guided document request: verify names → rates → confirm → submit (nora-022) | None |
| t-nora-016 | "take me to", "show me", "go to", "open the" | Navigate SPA to requested screen/record. Pause and flag issues on arrival. (nora-023) | None |
| t-nora-017 | "Sage budget", "program budget", "how much spent", "budget rollup" | Query programs + projects, produce Sage Budget rollup or answer inline (nora-019) | None |
| t-nora-018 | "how do I", "where do I", "help me with", "walk me through" | Context-aware help from user manual + SPA inventory. Navigate to relevant screen. | None |
| t-nora-019 | "vendor performance", "how is [vendor] doing", "best plumber", "compare vendors" | Factor-adjusted vendor analysis across completed projects (nora-025) | None |
| t-nora-020 | "project tracker", "give me the tracker", "download tracker" | Produce populated project tracker xlsx, save to SharePoint (nora-026) | None |

### 3.6 Voice Config Table (`dcfg_agent_voice`)

| setting | HR AI | Nora |
|---------|-------|------|
| `voice_enabled` | `false` (built, not active) | `true` |
| `mic_gesture` | click-hold | click-hold |
| `stt_provider` | Azure Speech Services | Azure Speech Services |
| `stt_language` | en-US | en-US |
| `stt_custom_vocabulary` | DCFG, Decades, Dataverse | DCFG, Decades, Dataverse, Claude, Nora, dcfg_propertys |
| `tts_provider` | Azure Speech Services | Azure Speech Services |
| `tts_voice` | `en-US-JennyNeural` | `en-US-JennyNeural` |
| `tts_rate` | 1.0 | 0.95 (slightly slower for clarity) |
| `voice_fingerprint` | `false` | `true` |
| `barge_in` | `true` | `true` |
| `van_listening_animation` | headlights glow, pulse | headlights glow, pulse |
| `van_speaking_animation` | subtle body movement | subtle body movement, eye tracking |

### 3.7 Guardrails Table (`dcfg_agent_guardrails`)

These are non-negotiable rules. They cannot be overridden by any configuration change.

| guardrail_id | agent | rule | severity |
|--------------|-------|------|----------|
| g-001 | HR AI | Never write to Dataverse | ABSOLUTE |
| g-001a | Nora | Write to dcfg_document_requests ONLY, after guided verification + user confirmation (see g-011, g-012, g-013). All other tables read-only. | ABSOLUTE |
| g-002 | Both | Never contact anyone other than current user without Joe explicitly initiating | ABSOLUTE |
| g-003 | HR AI | Never access individual employee records, payroll, or compensation data | ABSOLUTE |
| g-004 | HR AI | Never provide legal advice | ABSOLUTE |
| g-005 | Nora | `dcfg_budget_committed` is read-only everywhere — written by `flow_commit` only | ABSOLUTE |
| g-006 | Nora | Entity set name is `dcfg_propertys` NOT `dcfg_properties` | ABSOLUTE |
| g-007 | Nora | Proactive initiation allowed ONLY for Joe's instance | ABSOLUTE |
| g-008 | Nora | End-User Nora is read-only firewall — no diagnostic or write operations | ABSOLUTE |
| g-009 | Both | During Living Vans Button Mode Locked (meeting/share active), agents respond to text only — no voice activation permitted | ABSOLUTE |
| g-010 | Both | All responses must be auditable — log every query and response | HIGH |
| g-011 | Nora | Document request creation requires fuzzy-match verification of customer AND vendor names against Dataverse before submission — never accept raw text as a record reference | ABSOLUTE |
| g-012 | Nora | Document request creation requires explicit user confirmation of full summary before writing | ABSOLUTE |
| g-013 | Nora | Nora writes ONLY to dcfg_document_requests — no other table, ever. Read-only on all other dcfg_* tables. | ABSOLUTE |
| g-014 | Nora | Produced xlsx files must use verified template schemas (bid_comp_schema.json, estimate_schema.json) — every formula, merge, style, and cell position preserved exactly | HIGH |
| g-015 | Nora | When navigating to a screen, pause and flag visible issues (missing fields, $0 fees, stuck statuses, blank required fields) before continuing | HIGH |
| g-016 | Nora | Entity set for properties is dcfg_properties (corrected from earlier dcfg_propertys reference) | ABSOLUTE |

---

## 4. Model Selection Strategy

### 4.1 Selecting Claude in Copilot Studio

Claude models are available directly in Copilot Studio's model selector dropdown.

**Steps:**
1. Open agent in Copilot Studio
2. Go to agent's **Overview** page
3. In the **Model** section, open dropdown
4. Select Claude model (Sonnet 4.6 or Opus 4.6)
5. Agent now reasons with Claude

**Admin prerequisite:** Anthropic models must be enabled in **Microsoft 365 Admin Center**. Available by default in most geographies as of January 2026. EU/UK/EFTA may require admin opt-in.

**Fallback:** If Anthropic models are disabled by admin, agents automatically fall back to GPT-4o. No breakage.

### 4.2 Model Assignment Table

| agent | user_role | model | rationale |
|-------|-----------|-------|-----------|
| HR AI | all | Claude Sonnet 4.6 | Fast, accurate for policy Q&A. Cost-efficient. |
| Nora | admin (Brook) | Claude Sonnet 4.6 | Responsive, efficient for read-only queries and doc building. |
| Nora | sales | Claude Sonnet 4.6 | Contract status lookups, post-job content generation. |
| Nora | ops | Claude Sonnet 4.6 | Budget/WO queries, operational process answers. |
| Nora | field | Claude Sonnet 4.6 | Work order status, asset queries. Limited scope. |
| Nora | joe | Claude Opus 4.6 | Deep reasoning, multi-step planning, design partner. Full capability. |
| Agent Harness (Planner) | system | Claude Sonnet 4.6 | Routing and research. Doesn't need Opus. |
| Agent Harness (Generator) | system | Claude Sonnet 4.6 | Building/creating artifacts. |
| Agent Harness (Evaluator) | system | Claude Haiku 4.5 | Verification/checking. Fast, cheap. |
| Agent Harness (Cowork) | system | Gemini Nano | Local device inference for GUI automation decisions. No cloud round-trip. |

### 4.3 Cost Strategy

| Path | Use Case | Cost Model |
|------|----------|------------|
| Copilot Studio native | HR AI + Nora (all users) | M365 Copilot license or Copilot Credit Commit Units |
| Azure AI Foundry API | Agent harness (Planner/Generator/Evaluator) | Pay-per-token, counts toward Azure MACC |
| Gemini Nano | Cowork GUI automation inference | Device-level, zero cloud cost |

**Cost governors:**
- Console monthly caps on Azure AI Foundry
- `max_tokens` per call limits
- Model routing: Haiku for cheap tasks, Sonnet for complex, Opus for Joe's Nora only
- Gemini Nano for latency-sensitive local decisions (Cowork)

---

## 5. Voice Interaction Model

### 5.1 Both Vans are Voice-Capable

Both the HR Van and Nora Van have the same voice infrastructure. The difference is activation state.

| Feature | HR Van | Nora Van |
|---------|--------|----------|
| Voice infrastructure built | ✅ | ✅ |
| Voice enabled by default | ❌ | ✅ |
| Enable/disable | `dcfg_agent_voice` table | `dcfg_agent_voice` table |
| Mic gesture | Click-and-hold | Click-and-hold |
| Text fallback | Single click | Single click |

### 5.2 Click-and-Hold Mic Activation

| Gesture | Action |
|---------|--------|
| **Click-and-hold** van | Mic activates. Van headlights glow brighter, subtle pulse = listening. User speaks. Release to send. |
| **Release** after speaking | Audio captured → STT → transcribed text → Copilot Studio agent → Claude → response text → TTS → audio playback. |
| **Single click** van | Opens text chat panel (fallback/alternative mode). |
| **Click-and-hold** while agent is responding | Barge-in. Agent stops speaking immediately. |

### 5.3 Voice Fingerprint & Role Detection (Nora)

Nora uses voice fingerprint to identify the speaker and load the correct capability set from the tables.

| Voice | Nora mode | Model | Capabilities loaded from |
|-------|-----------|-------|------------------------|
| Joe | Proactive / Admin-Dev | Opus 4.6 | `dcfg_agent_capabilities` WHERE joe = ✅ |
| Brook | Reactive / End-User | Sonnet 4.6 | `dcfg_agent_capabilities` WHERE admin = ✅ |
| Ira, Steve | Reactive / End-User | Sonnet 4.6 | `dcfg_agent_capabilities` WHERE sales = ✅ |
| Alicia, Leon | Reactive / End-User | Sonnet 4.6 | `dcfg_agent_capabilities` WHERE ops = ✅ |
| Unknown | Reactive / End-User | Sonnet 4.6 | Minimal default capability set |

**Implementation:** Azure Speech Services speaker verification (text-independent). Enrollment requires ~30 seconds of speech per person.

### 5.4 Speech Pipeline

```
User speaks (mic active via click-hold on van)
    → Browser MediaRecorder API captures audio
    → Audio → Azure Speech Services STT
    → (Optional) Voice fingerprint check → role determination
    → Transcribed text → Copilot Studio agent
    → Claude model processes (model selected per config table)
    → Response text generated
    → Response text → Azure Speech Services TTS
    → Audio plays through browser
    → Van animates while speaking (body movement, headlight pulse)
    → Response text also displayed in chat panel for reference
```

### 5.5 Custom Vocabulary

Both agents share a custom speech model vocabulary for DCFG-specific terms:

| Spoken | Correct transcription | Notes |
|--------|----------------------|-------|
| "clawed" / "claw" / "clod" | Claude | Joe's voice-to-text artifact |
| "decades" | Decades | Company name |
| "dee see eff gee" | DCFG | Acronym |
| "data verse" | Dataverse | Platform |
| "dee see eff gee propertys" | dcfg_propertys | Sacred gotcha — the S matters |
| "nora" | Nora | Agent name |
| "upkeep" | UpKeep | CMMS system |
| "bid comp" | bid comp | Bid comparison template |
| "exhibit A" / "exhibit B" | Exhibit A / Exhibit B | Contract scope documents |
| "sage budget" | Sage Budget | Cost code rollup format |
| "CSI code" / "see ess eye" | CSI code | Construction Specifications Institute |
| "FROL" / "frawl" | FROL | Final Release of Liens |
| "takeoff" / "take off" | takeoff | Material quantity measurement |
| "GPS plumbing" | GPS Plumbing | Vendor (Sage #11) |
| "Starr general" | Starr General | Vendor (Sage #59) |
| "Rahn" / "Ron" | Rahn | Vendor — Rahn Companies (Sage #8) |
| "MDM" / "em dee em" | MDM | Vendor — MDM Electric (Sage #4) |
| "Protech" | Protech | Vendor — Protech Floors (Sage #5) |
| "Bancroft" | Bancroft | Customer |
| "Huntingdon" | Huntingdon | Property name reference |

---

## 6. Agent System Prompts

### 6.1 HR AI System Prompt

Configured in Copilot Studio **Instructions** field:

```
You are the DCFG HR Assistant. You help Decades Construction & Facilities Group 
employees with human resources questions.

RULES:
- Answer questions about company policies, benefits, PTO, onboarding, and HR 
  procedures using the knowledge sources connected to you.
- Always reference the specific policy document when answering.
- If you don't know the answer, say so and direct the employee to contact HR directly.
- Never speculate about individual employment situations.
- Never provide legal advice — direct legal questions to HR or legal counsel.
- Never access or discuss individual payroll, compensation, or performance data.
- Keep answers concise and actionable.
- If someone asks about contracts, facilities, work orders, or IT, tell them you're 
  the HR assistant and suggest they talk to Nora for operational questions.

TONE: Professional, warm, approachable. You represent Decades' culture — a company 
that supports the people who support IDD providers and the individuals they serve.

WHEN USING VOICE: Keep responses brief. 2-3 sentences max unless the user asks for 
more detail. Voice responses should be conversational, not like reading a document.
```

### 6.2 Nora System Prompt — End-User

```
You are Nora, the operational assistant for Decades Construction & Facilities Group. 
You help DCFG team members with contract information, location details, work orders, 
budgets, and operational processes.

RULES:
- You have READ-ONLY access to Dataverse. You can look up information. You cannot 
  change, create, or delete any records.
- Always use entity set name dcfg_propertys (NOT dcfg_properties).
- Budget health references dcfg_programs, not MSAs.
- dcfg_budget_committed is read-only — written by flow_commit only. Never suggest 
  editing it.
- Never contact anyone other than the person you're talking to.
- You only respond when spoken to. You never initiate.
- If someone asks about HR, benefits, PTO, or payroll, redirect them to the HR 
  assistant.
- Keep answers concise. Lead with the answer, then context if needed.

TONE: Capable, direct, warm. You know the business. You're the person who always 
knows where to find the answer.

WHEN USING VOICE: Be conversational. Short sentences. Don't read table data aloud — 
summarize it and offer to show details in the chat panel.
```

### 6.3 Nora System Prompt — Joe (Admin/Developer)

```
You are Nora, Joe Cameron's AI partner at DCFG. You are his executive function 
layer, design partner, and operational copilot.

RULES:
- You have full read access to Dataverse schema and data.
- You can proactively surface information, reminders, and suggestions.
- You route complex tasks to the Agent Harness: Planner for research/routing, 
  Generator for building, Evaluator for verification.
- Entity set: dcfg_propertys (sacred gotcha).
- Org URL: org0c17e98d.crm.dynamics.com, Solution: DCFGContractingSuite.
- Joe has dyscalculia — you own all numeric work. Present numbers structurally. 
  Flag math explicitly.
- Joe thinks verbally and uses voice-to-text. Expect phonetic artifacts. 
  "Clawed/claw/clod" = Claude.
- Joe cuts in mid-thought when ideas fire. Stop immediately without finishing 
  your sentence.
- Production artifacts over explanations. Fix violations silently. Limit 
  post-delivery commentary to one sentence.
- Never contact anyone other than Joe without Joe explicitly initiating.

TONE: Direct, competent, efficient. You're the one person in the room who always 
has the answer and never wastes time getting to it.
```

---

## 7. Post-Job Content Generation (nora-014)

When a job completes, Nora generates social/marketing content. This capability is enabled for Sales and Joe roles.

### 7.1 Trigger

User says something like "the [project name] job is done" or a work order status changes to Complete in Dataverse (autonomous trigger, future phase).

### 7.2 Output Package

Nora generates a single output package with alternatives:

| Output | Platform | Format | Tone |
|--------|----------|--------|------|
| Post Alternative 1 | LinkedIn | Professional, 150-200 words | Industry credibility, facility management expertise |
| Post Alternative 2 | Facebook | Warm, community-focused, 100-150 words | Human impact, provider support story |
| Post Alternative 3 | X (Twitter) | Sharp, concise, <280 chars | Punchy accomplishment + IDD mission hook |
| Alternative 4 (moonshot) | YouTube script | 30-second script for Decades president | On-camera energy, personal pride, mission framing |
| Close message | Sales team internal | Brief, share-ready with links to all alternatives | "Here's what we accomplished and how to share it" |

### 7.3 Content Rules

- Every piece frames the work through the lens of **empowering IDD providers and the independence of individuals they serve**
- Never generic "we completed a job." Always: "we made it possible for [provider type] to better serve [individuals]."
- The YouTube script addresses camera directly, uses the president's natural voice, keeps it human
- Close message includes one-click share links per platform
- All content is presented for human review before posting — Nora never auto-publishes

### 7.4 Data Nora Pulls for Content

From the completed work order and related records:

- Customer name and type (group home, school, daycare, housing)
- Location(s) served
- Work performed (scope summary)
- Program name if applicable
- Any notable assets replaced or upgraded (for capital work)
- Geographic region (for local pride angle)

---

## 8. Agent Harness Integration (Joe's Nora Only)

### 8.1 Routing

When Joe asks Nora something that exceeds simple Dataverse lookup or conversation, Nora routes to the appropriate harness agent:

| Request type | Routes to | Model | Example |
|-------------|-----------|-------|---------|
| "Research how to..." / planning questions | Planner | Sonnet 4.6 | "Research the best approach for the provider portal auth" |
| "Build me a..." / creation tasks | Generator | Sonnet 4.6 | "Build the PowerShell script for the new asset columns" |
| "Check if..." / verification tasks | Evaluator | Haiku 4.5 | "Check if all merge fields are in the registry" |
| "Update HubSpot..." / GUI tasks | Cowork | Gemini Nano + browser | "Update the contact record for Sunrise Group Home" |

### 8.2 Bright Line

Reasoning tasks → skills (Planner, Generator, Evaluator decide what to do).  
Execution tasks → scripts (actual PowerShell, actual CLI commands).  
Nora never blurs this line.

---

## 9. Deployment Checklist

### 9.1 Prerequisites

- [ ] M365 Copilot license active for DCFG tenant
- [ ] Anthropic models enabled in M365 Admin Center
- [ ] Azure subscription with Azure AI Foundry access (for agent harness API calls)
- [ ] Azure Speech Services resource provisioned (for voice pipeline)
- [ ] Dataverse connector configured in Copilot Studio (read-only)
- [ ] SharePoint document libraries organized (HR docs, operational playbooks)
- [ ] Configuration tables created in Dataverse (`dcfg_agent_config`, etc.)

### 9.2 Build Order

| Step | Task | Owner | Dependency |
|------|------|-------|------------|
| 1 | Create configuration tables in Dataverse | Joe (CLI) | Schema access |
| 2 | Populate config tables with values from this spec | Joe | Step 1 |
| 3 | Create HR AI agent in Copilot Studio | Joe | M365 Copilot license |
| 4 | Select Claude Sonnet 4.6 as model | Joe | Anthropic enabled in MAC |
| 5 | Connect HR knowledge sources (SharePoint) | Joe | HR docs organized |
| 6 | Configure HR topics and system prompt | Joe | Step 3 |
| 7 | Create Nora agent in Copilot Studio | Joe | Step 3 complete |
| 8 | Select Claude Sonnet 4.6 as default model | Joe | Step 4 |
| 9 | Connect Dataverse read-only connector | Joe | Dataverse permissions |
| 10 | Connect operational knowledge sources | Joe | SharePoint organized |
| 11 | Configure Nora topics and system prompt (end-user) | Joe | Step 7 |
| 12 | Configure Joe's Nora variant (Opus 4.6, admin prompt) | Joe | Step 11 |
| 13 | Provision Azure Speech Services | Joe | Azure subscription |
| 14 | Implement voice pipeline (STT/TTS) | Joe (CLI) | Step 13 |
| 15 | Enroll voice fingerprints (Joe, Brook, key staff) | Joe + staff | Step 14 |
| 16 | Integrate with Living Vans overlay (callbacks) | Joe (CLI) | SPEC-VAN-001 |
| 17 | Test HR AI via Teams | Joe + Brook | Steps 3-6 |
| 18 | Test Nora via Teams | Joe + Brook | Steps 7-12 |
| 19 | Test voice interaction | Joe | Steps 14-15 |
| 20 | Enable HR voice (flip config table row) | Joe | When ready |
| 21 | Create RFP/BidComp Dataverse tables | Claude (CLI) | Schema access |
| 22 | Add nora-015 through nora-026 capability rows | Joe | Step 21 |
| 23 | Upload knowledge files k-nora-006 through k-nora-013 | Joe | Files built |
| 24 | Add topics t-nora-009 through t-nora-020 | Joe | Step 22 |
| 25 | Add guardrails g-011 through g-016 | Joe | Step 24 |
| 26 | Configure Dataverse connector for dcfg_document_requests write | Joe | Step 21 |
| 27 | Configure SharePoint connector for project site search | Joe | Graph API auth |
| 28 | Add custom vocabulary (bid comp, FROL, CSI, vendor names) | Joe | Step 19 |
| 29 | Test Nora bid comp production | Joe + Tyler | Steps 21-27 |
| 30 | Test Nora document request creation (contract) | Joe | Steps 26-27 |
| 31 | Test Nora SharePoint document retrieval | Joe | Step 27 |
| 32 | Test Nora SPA navigation | Joe | Steps 22-24 |

### 9.3 Testing Milestones

| Milestone | Validates | Pass criteria |
|-----------|-----------|---------------|
| HR AI answers policy question | Knowledge retrieval + Claude reasoning | Correct answer with source citation |
| HR AI redirects ops question to Nora | Topic routing + agent handoff | Clean redirect message |
| Nora returns contract status | Dataverse read connector + query | Correct data, matches manual lookup |
| Nora respects `dcfg_propertys` gotcha | Entity set name handling | No 404/error on property queries |
| Nora blocks write attempt | Guardrail g-001 | Polite refusal, no data change |
| Voice input → correct transcription | STT pipeline | Accurate text including DCFG vocabulary |
| Voice fingerprint → correct role | Speaker verification | Joe gets Opus, Brook gets Sonnet |
| Post-job content generates | nora-014 capability | 4 alternatives + close message produced |
| Emergency exit during voice | Living Vans integration | Voice stops, vans park instantly |
| Nora produces bid comp xlsx | Template engine + schema | 19-tab file opens in Excel, all formulas intact, bidder columns populated |
| Nora produces estimate xlsx | Template engine + schema | 6-tab file opens in Excel, all formulas intact, line items populated |
| Nora creates document request via guided flow | Dataverse write + verification | Fuzzy-match finds correct vendor, summary shown, user confirms, record created |
| Nora navigates to contract detail | SPA navigation | Screen changes, correct record displayed, issues flagged |
| Nora finds invoice in SharePoint | Graph API + project site search | Correct file returned with link, from correct project folder |
| Nora answers "how much spent on plumbing this FY" | Dataverse read + aggregation | Correct dollar amount, matches manual query |
| Nora blocks write to non-document-request table | Guardrail g-013 | Polite refusal, no data change |
| "Take me to" + voice via Nora van | Voice + navigation | STT transcribes correctly, screen changes, van animates |

---

## 10. Related Documents

| Document | Description |
|----------|-------------|
| SPEC-VAN-001 | Living Vans — Ambient AI Interface Specification |
| DCFG_Schema_Consolidated.md | Dataverse schema reference (19 tables) |
| DCFG_Merge_Field_Registry.md | ~70 merge field tags for document generation |
| DCFG_Lessons_Learned.md | Platform gotchas and corrections |
| RPT-CAP-001 | Capital Replacement Plan report spec |
| project-setup-to-rfp-design.md | Project Section spec — data model, RFP/BidComp, process flow |
| rfp-bidcomp-build.md | Implementation plan — spreadsheet engine, schema, SPA screens |
| nora-operations-agent-definition.md | Nora's full operations role definition |
| bid_comp_schema.json | Verified 19-tab bid comp template schema (9,911 cells, 577 formulas) |
| estimate_schema.json | Verified 6-tab estimate template schema (11,038 cells, 601 formulas) |

---

*End of SPEC-CPS-001 v0.2*
