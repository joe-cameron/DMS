# Nora — DCFG AI Monitoring System Design Spec

**Date:** 2026-03-22
**Build Order:** Phase 1 (Monitor) → Phase 2 (Mentor) → Phase 3 (Assistant)
**Why this order:** Monitor is the foundation. Mentor content must exist before Assistant can serve it. Assistant UI is last because it consumes both.
**Runtime:** Claude Code session on dedicated PC, continuous loop
**Estimated Build:** ~1 hour total across phases

---

## Overview

Nora is a read-only AI that monitors DCFG system health, teaches users how to use the system, and provides friendly real-time assistance when processes are delayed. She runs as a Claude Code `/loop` session on a dedicated PC, reading from Dataverse and writing only to her own operational tables.

---

## Access Model

| Scope | Permission | Tables | Condition |
|---|---|---|---|
| **Read** | All | Every dcfg_* table, flows, audit logs, document requests, configs | — |
| **Write (own)** | Unrestricted | dcfg_brain_insights, dcfg_nora_training (new), dcfg_nora_messages (new) | — |
| **Write (auto-fix)** | Automatic | dcfg_document_requests: PATCH status Processing→Complete | ONLY when output file verified in SharePoint AND dcfg_document_outputs record exists |
| **Write (auto-fix)** | Automatic | dcfg_document_requests: PATCH status Processing→Failed | ONLY when dcfg_nora_retry_count >= 3 |
| **Write (escalation)** | Automatic | dcfg_document_requests: POST type=Email | For operator notification only — Nora sends status alerts, not business emails |
| **Write (checkpoint)** | Automatic | dcfg_configs: key='nora_last_check' | Timestamp for monitoring loop persistence |
| **Write (business)** | NEVER without explicit operator authorization | Everything else | Operator must specify exactly what to change |
| **No access** | — | Customer communications, financial decisions, relationship context | — |

### Auto-Fix Boundary (Critical Rule)
Nora may auto-fix ONLY when she has **verified the work actually completed** (output exists in both Dataverse and SharePoint). All other system writes require operator authorization. If `dcfg_nora_retry_count >= 3`, Nora stops retrying, marks as Escalated, creates Urgent insight, and does not touch the record again.

---

## Phase 1: Monitor

### What It Does

A Claude Code `/loop` session (every 5 minutes) that:

1. **Polls audit logs** — new entries since last check
2. **Polls document requests** — stuck at Processing, failed, pending too long
3. **Checks flow health** — active flows still active, error rates
4. **Investigates failures** — before declaring failure, checks what actually completed
5. **Self-heals where possible** — flips status, retries simple operations
6. **Writes findings** to `dcfg_brain_insights`
7. **Learns patterns** — tracks recurring failures, time-based issues, common user errors

### Monitoring Loop Script

```
EVERY 5 MINUTES:

  1. AUDIT LOG SCAN
     - Query: dcfg_audit_logs WHERE createdon > lastCheckTime
     - Detect: error patterns, unusual action frequency, new error types
     - Track: action counts by type, user activity levels

  2. DOCUMENT REQUEST HEALTH
     - Query: dcfg_document_requests WHERE dcfg_status = Processing AND modifiedon < 10min ago
     - For each stuck request:
       → Check: did the document output get created? (query dcfg_document_outputs)
       → Check: did the file land in SharePoint? (Graph API)
       → IF work completed: PATCH status to Complete, log insight
       → IF partially completed: identify gap, retry missing step
       → IF nothing happened: retry request (max 2 retries), then escalate

  3. FLOW HEALTH
     - Query: workflows WHERE category=5 AND statecode=1
     - Compare against known active flow list
     - Detect: flows that went inactive unexpectedly

  4. PATTERN ANALYSIS
     - Compare current metrics to historical baseline
     - Detect: spike in errors, unusual user behavior, time-of-day patterns
     - Write learned patterns to dcfg_brain_insights (type=Pattern)

  5. UPDATE CHECKPOINT
     - Store lastCheckTime for next iteration
```

### Incident Response Pattern

```
Problem detected (e.g., stuck document request)
  → Step 1: INVESTIGATE — what actually happened?
    - Check dcfg_document_outputs for this request's source record
    - Check SharePoint for the output file
    - Check audit logs for related entries
  → Step 2: ASSESS — did the work complete despite the "failure"?
    - IF YES: fix the status, log what happened, done
    - IF PARTIAL: identify what's missing, attempt to complete
    - IF NO: retry (respect limits)
  → Step 3: ESCALATE (only if needed)
    - Write insight with full context: what failed, what was tried, what Nora recommends
    - Severity: Info / Warning / Urgent
    - IF urgent: trigger email notification to operator via flow_send_email
  → Step 4: CONTINUE MONITORING
    - Don't block on escalation — keep checking other things
```

### dcfg_brain_insights Schema

| Column | Type | Values |
|---|---|---|
| dcfg_title | String | Short description |
| dcfg_detail | String | Full context — what happened, what was tried, what Nora recommends |
| dcfg_domain | Choice | System / DocGen / Onboarding / Compliance / UX / Training |
| dcfg_priority | Choice | Info / Warning / Urgent |
| dcfg_insight_type | Choice | Anomaly / Pattern / TestResult / Recommendation / Incident / TrainingGap |
| dcfg_insight_status | Choice | New / Acknowledged / Resolved / Dismissed |
| dcfg_source_entity | String | Table name that triggered the insight |
| dcfg_source_record_id | String | Record GUID |
| dcfg_is_actionable | Boolean | Can Nora do something about this? |
| dcfg_created_by_flow | String | 'nora-monitor' / 'nora-mentor' / 'nora-assistant' |

### UX Testing (Part of Monitor)

Nora runs the merged test pipeline on a schedule:

```
EVERY HOUR (or on-demand):
  - Create document request with test data
  - Poll until Complete/Failed
  - Download output document
  - Extract text with mammoth
  - Score fields: COMPLETE / BROKEN / MISSING
  - Write results to dcfg_brain_insights (type=TestResult)
  - Compare to previous run — detect regressions
  - IF regression: create Urgent insight
```

Uses the proven test harness (`DCFG_Merged_Test_Pipeline.ps1`) and scoring model.

### Playwright Screen Testing

```
EVERY 4 HOURS:
  - Launch Playwright against staging SPA
  - Navigate each screen: Dashboard, Customers, Contracts, MSAs, Locations, Onboarding, SendQueue, Admin
  - For each screen:
    → Page loads without error?
    → Data table populates?
    → Search works?
    → Navigation links work?
  - Score: Screen-level COMPLETE / BROKEN / MISSING
  - Write results to dcfg_brain_insights (type=TestResult, domain=UX)
```

---

## Phase 2: Mentor (Training System)

### What It Does

Nora builds contextual training content that teaches users how to perform every system activity. She is the expert user — she knows every screen, every workflow, every button.

### Voice & Vocabulary

- **High school graduate reading level** — no jargon, no technical terms
- **Friendly expert colleague** — not a manual, not a chatbot
- **Tell AND show** — text instructions paired with screenshots or annotated UI mockups
- Example: "To create a new contract, click 'New Contract' in the left menu. You'll see a form with five steps. Let's walk through each one."

### Training Content Structure

```
dcfg_nora_training table:
  - dcfg_screen: which screen this training covers (Dashboard, CustomerList, etc.)
  - dcfg_task: what the user is trying to do ("Create a new customer", "Generate a work order")
  - dcfg_steps: JSON array of step objects [{step, instruction, screenshot_url, element_highlight}]
  - dcfg_difficulty: Beginner / Intermediate / Advanced
  - dcfg_estimated_time: "2 minutes"
  - dcfg_prerequisites: what the user should know first
  - dcfg_version: tracks content freshness against SPA changes
```

### How Training Is Built

Nora generates training by:
1. **Reading the SPA source** — she knows every component, every route, every form field
2. **Reading the component library** — she knows the UI patterns
3. **Running the workflow herself** (Playwright) — she walks through each task step by step
4. **Capturing screenshots** at each step (Playwright screenshot API)
5. **Writing instructions** in plain language
6. **Storing in dcfg_nora_training** — queryable by screen and task

### Training Content Inventory (Initial Build)

| Screen | Tasks |
|---|---|
| Dashboard | Read KPIs, drill down to details, use document search, review alerts |
| Customers | Create customer, edit customer, view contracts/MSAs/locations |
| Contracts | View contract list, search, filter by status |
| Contract Detail | View status, review Exhibit A lines, generate document, void contract |
| New Contract | Complete 5-step wizard (family, location, vendor, lines, review) |
| New Proposal | Complete interview wizard, create MSA |
| MSAs | View MSA list, view MSA detail, review rates |
| Locations | View locations, filter by customer, check compliance |
| Location Detail | Edit property, upload certificates, manage appliances |
| Onboarding | Create case, view progress, filter by status, soft delete/restore |
| Onboarding Detail | Edit case, complete steps, add notes (voice), close/reopen |
| Send Queue | Review pending, mark sent, mark signed, request info |
| Admin | Manage templates, steps, location types, cost codes, vendors |

### Contextual Help

Training content is tagged by screen. When the user opens Nora's help on a specific screen, she shows training relevant to WHERE THEY ARE — not a generic help menu.

```
User is on CustomerList → Nora shows:
  "How to create a new customer"
  "How to search for a customer"
  "How to edit customer details"

User is on NewContractWizard Step 3 → Nora shows:
  "How to select a vendor"
  "How to fill in signer information"
  "What is payment process?"
```

---

## Phase 3: Assistant (UI Presence)

### What It Does

A small floating presence in the SPA that:
- Shows Nora's status (monitoring, investigating, all clear)
- Displays friendly inline messages when processes are delayed
- Provides access to contextual training (Phase 3)
- Links to brain_insights for the operator

### UI Element

```
FLOATING BUTTON (bottom-left, next to search FAB on bottom-right):
  - Small circle (40px), Nora's icon/avatar
  - Soft blue or warm gray (NOT red, NOT alarming)
  - Subtle pulse animation when she has something to say
  - Click → opens Nora panel (slides up from bottom or small popover)

NORA PANEL:
  - "Everything looks good" (default — green dot)
  - OR: "Working on something for you..." (amber dot, with context)
  - OR: "Heads up — [friendly message]" (info, with detail)
  - Training section: "Need help with this screen?" → contextual tasks
  - For operator: link to full brain_insights view
```

### Message Tone Examples

| Situation | Nora Says |
|---|---|
| Document generating normally | (nothing — silence means working) |
| Document taking longer than usual | "Your document is taking a bit longer than usual. I'm keeping an eye on it." |
| Document completed after delay | (document appears — receipt is notification) |
| Document failed, Nora retried | "That took an extra try, but your document is ready now." |
| Document failed, can't fix | "I wasn't able to finish this one. I've let Joseph know and saved what I have." |
| User on unfamiliar screen | "First time here? I can walk you through it." (subtle, dismissible) |
| System healthy | Small green dot on Nora's icon. No message. |

### Messages Are NOT Toasts

- They appear **inline** where the user is looking (near the progress indicator or status area)
- They are **persistent** until the situation resolves (not auto-dismiss)
- They are **warm** — no error codes, no red, no technical language
- They are **Nora's voice** — first person, friendly, brief

### Data Flow

```
Nora Monitor (Claude Code loop)
  → writes to dcfg_brain_insights
  → writes user-facing messages to dcfg_nora_messages (new table)

SPA polls dcfg_nora_messages:
  → WHERE dcfg_user = current user email
  → AND dcfg_status = Active
  → AND dcfg_context_screen = current screen (or null for global)
  → Display in Nora panel

User dismisses → SPA patches dcfg_nora_messages status to Dismissed
```

### dcfg_nora_messages Schema

| Column | Type | Purpose |
|---|---|---|
| dcfg_user | String | Target user email (or 'all' for broadcast) |
| dcfg_message | String | Friendly text (Nora's voice) |
| dcfg_context_screen | String | Screen this applies to (null = global) |
| dcfg_context_record_id | String | Record being waited on (optional) |
| dcfg_severity | Choice | Info / Heads-up / Resolved |
| dcfg_status | Choice | Active / Dismissed / Expired |
| dcfg_expires_at | DateTime | Auto-expire old messages |

---

## New Tables Required

| Table | Purpose | Phase |
|---|---|---|
| dcfg_brain_insights | Already exists — Nora's findings, patterns, test results. Per-field scoring stored as JSON in dcfg_detail column. | 1 |
| dcfg_nora_training | Training content by screen and task | 2 |
| dcfg_nora_messages | User-facing messages from Nora | 3 |

**Note:** `dcfg_nora_test_results` is NOT a separate table. Test scoring detail (per-field COMPLETE/BROKEN/MISSING) is stored as a JSON array in `dcfg_brain_insights.dcfg_detail` with `dcfg_insight_type = TestResult`. This avoids table sprawl while keeping all Nora findings in one queryable location.

### All New Tables Include
- `dcfg_active_flag` (Boolean, default true) — consistent with project-wide soft delete pattern

### New Columns on Existing Tables

| Table | Column | Type | Purpose |
|---|---|---|---|
| dcfg_document_request | dcfg_nora_retry_count | Integer | Track Nora's retry attempts. Hard ceiling: 3. |
| dcfg_document_request | dcfg_nora_message | String | Friendly status message for waiting user |
| dcfg_config | nora_last_check | String (key/value) | Monitoring loop checkpoint — survives session restarts |

---

## Implementation Approach

### Phase 1: Monitor (~30 min)

1. Create `/loop` skill or script for Claude Code
2. Build the polling queries (audit logs, document requests, flow health)
3. Build the incident response logic (investigate → fix → escalate)
4. Wire the test pipeline (reuse DCFG_Merged_Test_Pipeline.ps1)
5. Store nora_last_check in dcfg_configs for persistence across restarts
6. Test: create a stuck request, verify Nora detects and handles it

### Phase 2: Mentor (~20 min)

1. Create dcfg_nora_training table (with dcfg_active_flag)
2. Nora reads SPA source + component library
3. Nora generates training content for all 13 screens
4. Store in Dataverse with screen/task tagging
5. Build simple training viewer (HTML page or SPA component)

### Phase 3: Assistant (~10 min)

1. Create dcfg_nora_messages table (with dcfg_active_flag)
2. Add Nora floating button to SPA shell (first floating element — search FAB may not exist yet)
3. Add polling for user-specific messages (use portal contact GUID as user ID, email as fallback)
4. Add contextual training lookup from dcfg_nora_training
5. Style: warm, calm, Nora's voice

### Playwright Authentication Note

Playwright tests against the staging SPA require portal authentication. Options:
- **Portal local login** — Playwright fills email/password on the sign-in page
- **AAD SSO** — Playwright uses stored browser state/cookies from a prior login
- **Service account** — Dedicated portal contact with DCFG_Admin role for testing

This is not blocking for Phase 1 (which uses Dataverse API auth) but must be resolved before Phases 2/3 screenshot capture.

### Build Approach

All phases are built by a Claude Code session (not manual development). Table creation is scripted via PowerShell to Dataverse API. The time estimates assume AI-assisted development with existing tooling.

---

## Design Tests (Per Joseph's Philosophy)

1. **Is Nora friction?** If users think about Nora instead of their work → she's broken
2. **Is every element purposeful?** Nora only appears when she has something useful to say
3. **Is she augmenting, not automating?** She presents solutions for human decisions
4. **Does she learn?** Patterns tracked over time, not just point-in-time alerts
5. **Does she investigate before escalating?** Never cry wolf — check what actually happened first

---

## Mockup Reference

Nora's UI elements to be added to `C:\DCFG\dashboard_mockup.html` during Phase 2 build.
