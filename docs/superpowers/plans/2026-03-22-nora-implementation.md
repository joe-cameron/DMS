# Nora AI Monitoring System — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Nora — a read-only AI monitoring agent that watches system health, teaches users, and provides friendly in-app assistance.

**Architecture:** Nora is a Claude Code `/loop` skill running on a dedicated PC. She reads from Dataverse (audit logs, document requests, flows), writes only to her own tables (dcfg_brain_insights, dcfg_nora_training, dcfg_nora_messages), and can auto-fix verified stuck requests. She communicates in plain, warm language at a high school reading level.

**Tech Stack:** PowerShell + Dataverse Web API, Claude Code `/loop` skill, Node.js (mammoth for doc extraction), Playwright (future — UX testing + screenshots)

**Spec:** `C:\DCFG\docs\superpowers\specs\2026-03-22-nora-ai-monitor-design.md`

---

## File Structure

```
C:\DCFG\
├── nora/
│   ├── nora-monitor.ps1          # Phase 1: Main monitoring loop script
│   ├── nora-incident.ps1         # Phase 1: Incident investigation + auto-fix
│   ├── nora-test-runner.ps1      # Phase 1: DocGen test pipeline (reuses existing)
│   ├── nora-training-gen.ps1     # Phase 2: Generate training content from SPA source
│   └── nora-training-viewer.html # Phase 2: Standalone HTML training viewer
├── docs/
│   └── superpowers/
│       └── plans/
│           └── 2026-03-22-nora-implementation.md  # This file
```

**Existing files reused:**
- `C:\DCFG\DCFG_Merged_Test_Pipeline.ps1` — proven DocGen test + scoring
- `C:\DCFG\docs\DCFG_Component_Library.md` — UI patterns for training content
- `C:\DCFG\spa\dcfg-shell\src\` — SPA source (READ-ONLY) for training generation

**SPA modification (Phase 3 only, requires operator permission):**
- `C:\DCFG\spa\dcfg-shell\src\App.jsx` — add Nora floating button + message polling

---

## Chunk 1: Phase 1 — Monitor

### Task 1: Create Nora's schema (new columns on existing tables)

**Files:**
- Create: `C:\DCFG\nora\nora-schema.ps1`

- [ ] **Step 1: Write the schema script**

```powershell
# Adds dcfg_nora_retry_count and dcfg_nora_message to dcfg_document_request
# Seeds nora_last_check in dcfg_configs
# Targets: staging (org88778bb0)
```

Script creates:
- Column `dcfg_nora_retry_count` (Integer) on `dcfg_document_request`
- Column `dcfg_nora_message` (String, 500 chars) on `dcfg_document_request`
- Config record `nora_last_check` in `dcfg_configs` with value = current UTC timestamp

- [ ] **Step 2: Run schema script against staging**

Run: `pwsh -File C:\DCFG\nora\nora-schema.ps1`
Expected: 2 columns created, 1 config record seeded

- [ ] **Step 3: Verify schema**

Run: Query `EntityDefinitions(LogicalName='dcfg_document_request')/Attributes` for the new columns
Expected: Both columns exist

---

### Task 2: Build the monitoring loop

**Files:**
- Create: `C:\DCFG\nora\nora-monitor.ps1`

- [ ] **Step 1: Write the monitoring script**

The script performs one monitoring cycle. It will be called by `/loop` or `cron`.

```
INPUT: none (reads nora_last_check from dcfg_configs)
OUTPUT: writes findings to dcfg_brain_insights, updates nora_last_check

SEQUENCE:
1. Connect to staging Dataverse
2. Read nora_last_check from dcfg_configs
3. Query dcfg_audit_logs WHERE createdon > lastCheck → count by action type
4. Query dcfg_document_requests WHERE dcfg_status = 100000001 (Processing) → find stuck
5. Query workflows WHERE category=5 AND statecode=1 → compare to known active list
6. For each anomaly found → write to dcfg_brain_insights
7. Update nora_last_check to now
8. Print summary to console (for Claude Code terminal visibility)
```

Key queries:
- Audit scan: `dcfg_audit_logs?$filter=createdon gt {lastCheck}&$select=dcfg_action_type,dcfg_new_value,dcfg_performed_by,createdon&$orderby=createdon desc`
- Stuck requests: `dcfg_document_requests?$filter=dcfg_status eq 100000001&$select=dcfg_document_requestid,dcfg_name,dcfg_nora_retry_count,modifiedon`
- Flow health: `workflows?$filter=category eq 5 and statecode eq 1&$select=workflowid,name`

Known active flows (baseline):
```
DCFG DocGen v2, DCFG - Compute Metrics, DCFG - SharePoint Write Cache,
DCFG - HTTP Bridge Query Active Portfolio, flow_cert_upload,
flow_onboarding_init, flow_send_email, DCFG - Error Reporter,
flow_cert_alert, flow_commit, flow_template_validate, flow_sensor_ingest
```

- [ ] **Step 2: Run one monitoring cycle manually**

Run: `pwsh -File C:\DCFG\nora\nora-monitor.ps1`
Expected: Console output showing audit count, stuck requests, flow health. nora_last_check updated.

- [ ] **Step 3: Verify brain_insights written**

Query: `dcfg_brain_insights?$orderby=createdon desc&$top=5`
Expected: New insight records from the monitoring cycle (if anomalies found)

---

### Task 3: Build incident investigation + auto-fix

**Files:**
- Create: `C:\DCFG\nora\nora-incident.ps1`

- [ ] **Step 1: Write the incident response script**

```
INPUT: document_request_id (GUID of stuck request)
OUTPUT: auto-fix if verified, escalation insight if not

SEQUENCE:
1. Read the stuck request record
2. Check dcfg_nora_retry_count — if >= 3, mark Failed + Escalated, create Urgent insight, STOP
3. Get source record ID from request (contract_id or msa_id)
4. Query dcfg_document_outputs WHERE dcfg_source_record_id = source_id → did output get created?
5. If output exists → check SharePoint via Graph API for the file
6. ASSESS:
   - Output + file both exist → PATCH request status to Complete, log insight "Auto-fixed"
   - Output exists, no file → log insight "Partial — file missing in SharePoint"
   - No output → increment dcfg_nora_retry_count, create new document_request to retry
7. Write insight to dcfg_brain_insights with full context
```

- [ ] **Step 2: Test with a stuck request**

Create a document request manually with status=Processing (simulating a stuck request).
Run: `pwsh -File C:\DCFG\nora\nora-incident.ps1 -RequestId {guid}`
Expected: Nora investigates, finds no output, increments retry count, logs insight.

- [ ] **Step 3: Test auto-fix path**

Create a request at Processing status that HAS a matching document output and SharePoint file.
Run: `pwsh -File C:\DCFG\nora\nora-incident.ps1 -RequestId {guid}`
Expected: Nora detects completed work, patches status to Complete, logs "Auto-fixed" insight.

- [ ] **Step 4: Test escalation path**

Set dcfg_nora_retry_count = 3 on a stuck request.
Run: `pwsh -File C:\DCFG\nora\nora-incident.ps1 -RequestId {guid}`
Expected: Nora marks as Failed, creates Urgent insight, does NOT retry.

---

### Task 4: Wire the test pipeline into Nora

**Files:**
- Create: `C:\DCFG\nora\nora-test-runner.ps1`

- [ ] **Step 1: Adapt the merged test pipeline for Nora**

Wraps `DCFG_Merged_Test_Pipeline.ps1` logic into a Nora-compatible script that:
- Runs one DocGen test cycle
- Scores fields (COMPLETE/BROKEN/MISSING)
- Writes results to dcfg_brain_insights as type=TestResult
- Compares to previous TestResult — detects regressions
- If regression found → creates Urgent insight

- [ ] **Step 2: Run one test cycle**

Run: `pwsh -File C:\DCFG\nora\nora-test-runner.ps1`
Expected: DocGen pipeline runs, document generated, text extracted, fields scored, insight written.

- [ ] **Step 3: Verify regression detection**

Run twice with same data.
Expected: Second run shows "No regression — scores stable" (no Urgent insight).

---

### Task 5: Create the Nora Claude Code skill

**Files:**
- Create: `C:\Users\JosephCameron\.claude\skills\nora\skill.md`

- [ ] **Step 1: Write the Nora skill definition**

The skill defines Nora's personality, access rules, and monitoring loop. When invoked via `/nora` or `/loop 5m /nora`, it:
1. Connects to staging
2. Runs nora-monitor.ps1
3. For each stuck request found → runs nora-incident.ps1
4. Every 12th cycle (hourly) → runs nora-test-runner.ps1
5. Prints a status summary to the terminal
6. Repeats

- [ ] **Step 2: Test the skill**

Run: Invoke the nora skill manually
Expected: One monitoring cycle completes, summary printed

- [ ] **Step 3: Test with `/loop`**

Run: `/loop 5m /nora`
Expected: Nora runs every 5 minutes, printing status each cycle

---

## Chunk 2: Phase 2 — Mentor

### Task 6: Create dcfg_nora_training table

**Files:**
- Modify: `C:\DCFG\nora\nora-schema.ps1` (add training table creation)

- [ ] **Step 1: Add training table to schema script**

Columns:
- `dcfg_name` (String, required) — display name
- `dcfg_screen` (String) — screen identifier (Dashboard, CustomerList, etc.)
- `dcfg_task` (String) — what user is trying to do
- `dcfg_steps` (Multiline String) — JSON array of step objects
- `dcfg_difficulty` (Choice: Beginner/Intermediate/Advanced)
- `dcfg_estimated_time` (String) — "2 minutes"
- `dcfg_prerequisites` (String) — what to know first
- `dcfg_version` (String) — tracks freshness
- `dcfg_active_flag` (Boolean, default true)

- [ ] **Step 2: Run schema update**

Run: `pwsh -File C:\DCFG\nora\nora-schema.ps1`
Expected: dcfg_nora_training table created in staging

---

### Task 7: Generate training content for all 13 screens

**Files:**
- Create: `C:\DCFG\nora\nora-training-gen.ps1`

- [ ] **Step 1: Write the training generator**

The script:
1. Reads SPA source files (READ-ONLY) for each screen
2. Reads `C:\DCFG\docs\DCFG_Component_Library.md` for UI patterns
3. For each screen, generates training tasks in Nora's voice (high school vocabulary, friendly)
4. Creates JSON step arrays describing how to perform each task
5. POSTs training records to dcfg_nora_training

Training inventory per spec: 13 screens × 2-5 tasks each ≈ 40-50 training records.

- [ ] **Step 2: Run the generator**

Run: `pwsh -File C:\DCFG\nora\nora-training-gen.ps1`
Expected: 40-50 records created in dcfg_nora_training

- [ ] **Step 3: Verify content quality**

Query: `dcfg_nora_training?$top=5&$select=dcfg_screen,dcfg_task,dcfg_steps`
Expected: Records with clear, friendly instructions in JSON step format

---

### Task 8: Build training viewer

**Files:**
- Create: `C:\DCFG\nora\nora-training-viewer.html`

- [ ] **Step 1: Write standalone HTML viewer**

A self-contained HTML page that:
- Lists all screens in a sidebar
- Click a screen → shows available tasks
- Click a task → shows step-by-step instructions
- Styled with DCFG design tokens (navy, amber, IBM Plex Sans)
- Fetches from Dataverse `/_api/dcfg_nora_trainings` (portal Web API)
- OR loads from a static JSON export (for offline use)

- [ ] **Step 2: Test the viewer**

Open: `C:\DCFG\nora\nora-training-viewer.html`
Expected: Training content displays, navigation works, instructions readable

---

## Chunk 3: Phase 3 — Assistant (UI Presence)

### Task 9: Create dcfg_nora_messages table

**Files:**
- Modify: `C:\DCFG\nora\nora-schema.ps1`

- [ ] **Step 1: Add messages table to schema script**

Columns per spec:
- `dcfg_name` (String) — display name
- `dcfg_user` (String) — target user contact GUID or email
- `dcfg_message` (String) — friendly text
- `dcfg_context_screen` (String) — screen this applies to
- `dcfg_context_record_id` (String) — record being waited on
- `dcfg_severity` (Choice: Info / Heads-up / Resolved)
- `dcfg_status` (Choice: Active / Dismissed / Expired)
- `dcfg_expires_at` (DateTime)
- `dcfg_active_flag` (Boolean, default true)

- [ ] **Step 2: Run schema update + add Web API site settings**

Need Webapi/dcfg_nora_message/enabled = true and Webapi/dcfg_nora_message/fields = * for the SPA to read.
Need Webapi/dcfg_nora_training/enabled = true and Webapi/dcfg_nora_training/fields = * for training viewer.

Run schema script.
Expected: Table created, site settings created.

---

### Task 10: Add Nora to the SPA (requires operator permission)

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\App.jsx` (add NoraBubble component)
- Create: `C:\DCFG\spa\dcfg-shell\src\NoraBubble.jsx` (floating button + panel)

**NOTE:** SPA is READ-ONLY. This task requires explicit operator permission before execution.

- [ ] **Step 1: Write NoraBubble component**

```
NoraBubble.jsx (~120 lines):
- Floating button: 40px circle, bottom-left, soft blue (#5B8DEF)
- Polls dcfg_nora_messages every 30 seconds for current user
- Green dot = all clear, amber pulse = has message
- Click → small panel slides up:
  - Message area (if active messages)
  - "Need help?" section with contextual training tasks for current screen
  - For operator (isAdmin): link to brain_insights
- Dismiss button on each message → PATCH status to Dismissed
- Warm styling — rounded corners, soft shadows, no red
```

- [ ] **Step 2: Add NoraBubble to App.jsx**

Add `<NoraBubble />` inside the authenticated shell, after the main content area.
Must pass: current user, current route/screen, isAdmin flag.

- [ ] **Step 3: Build + deploy to staging**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build && pac pages upload-code-site`
Expected: Nora's floating button appears in bottom-left of staging SPA.

- [ ] **Step 4: Test message display**

Manually create a dcfg_nora_messages record for the current user.
Expected: Nora's button pulses, click shows the message, dismiss works.

---

## Execution Checklist

| Phase | Tasks | Estimated |
|---|---|---|
| Phase 1: Monitor | Tasks 1-5 | ~30 min |
| Phase 2: Mentor | Tasks 6-8 | ~20 min |
| Phase 3: Assistant | Tasks 9-10 | ~10 min |
| **Total** | **10 tasks** | **~60 min** |

### Dependencies
- Task 1 (schema) must complete before Tasks 2-4
- Tasks 2-4 are independent of each other (can parallel)
- Task 5 (skill) depends on Tasks 2-4
- Task 6 must complete before Tasks 7-8
- Task 9 must complete before Task 10
- Task 10 requires SPA write permission from operator

### Operator Gates
- **Before Task 10:** Confirm SPA write permission
- **Before `/loop` activation:** Confirm dedicated PC is available
