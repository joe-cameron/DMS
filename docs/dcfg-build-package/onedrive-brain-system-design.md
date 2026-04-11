# OneDrive Brain — Personal Knowledge & Memory System

## System Design Document

**Version:** 1.0
**Date:** March 2026
**Purpose:** A portable, AI-agent-readable personal knowledge system that lives entirely in the user's OneDrive file system, syncs to every device, and works with any AI tool.

---

## 1. Design Principles

**1.1 No spaces in any path or filename.** OneDrive allows spaces. Shell commands, scripts, APIs, and many tools break on them. Every folder and file name in this system uses kebab-case (hyphens). This is non-negotiable.

**1.2 JSON for agent-written data, Markdown for human-written notes.** JSON constrains the agent — it edits fields surgically instead of rewriting the whole file. Markdown is for longer-form content where human readability matters more than agent precision.

**1.3 The files are the system.** No database. No middleware. No sync layer. OneDrive IS the persistence layer. Any AI reads the files. Any human browses them in File Explorer, the OneDrive mobile app, or a viewer. Both doors hit the same files.

**1.4 Every file is self-describing.** Each JSON file includes a `_meta` block at the top that tells any AI what the file is, what the schema means, and how to update it. An agent encountering the file cold can understand it without external documentation.

**1.5 Append-friendly, merge-safe.** The system assumes multiple sessions may add entries. Entries have unique IDs and timestamps. Duplicate detection is by ID, not by content matching.

---

## 2. Folder Structure

```
OneDrive/
  brain/
    _system/
      brain-config.json          # Global config, categories, agent instructions
      session-log.jsonl          # Append-only log of every agent interaction
    household/
      knowledge.json             # Paint colors, wifi passwords, shoe sizes, etc.
      maintenance.json           # Appliances, service dates, warranty expiry
      contacts.json              # Plumber, electrician, pediatrician, etc.
    professional/
      relationships.json         # Professional network with last-contact tracking
      conferences.json           # Events attended, people met, notes
      career.json                # Skills, certifications, resume versions
    projects/
      dcfg/
        session-state.json       # Current DCFG project state and next actions
        decisions-log.json       # Architecture decisions with rationale
        schema-changes.json      # Pending/completed Dataverse schema ops
      personal-apps/
        ideas.json               # App ideas with status tracking
    finance/
      subscriptions.json         # Active subscriptions, renewal dates, costs
      insurance.json             # Policies, coverage, renewal dates
    health/
      providers.json             # Doctors, dentists, specialists
      schedule.json              # Appointments, recurring checkups
    learning/
      reading-list.json          # Books, articles, videos with status
      skills-tracker.json        # Skills being developed, progress
      research-notes/
        autoresearch-plan.md     # Notes on autoresearch methodology
    _templates/
      entry-template.json        # Template for creating new knowledge files
```

### Naming Rules (enforced everywhere)

- Folders: lowercase, kebab-case (`my-folder` not `My Folder`)
- Files: lowercase, kebab-case with extension (`my-file.json` not `My File.json`)
- No spaces, no special characters except hyphens and underscores
- No emoji in filenames
- Max depth: 4 levels from `brain/` root

---

## 3. File Schemas

### 3.1 brain-config.json — System Configuration

This is the first file any agent should read. It describes the entire brain structure.

```json
{
  "_meta": {
    "type": "brain-config",
    "version": "1.0",
    "description": "Root configuration for the OneDrive Brain system. Read this first to understand the folder structure, categories, and rules for interacting with brain files.",
    "owner": "Joe",
    "created": "2026-03-15T00:00:00Z",
    "last_modified": "2026-03-15T00:00:00Z"
  },
  "categories": [
    {
      "id": "household",
      "path": "brain/household/",
      "description": "Home and family knowledge — physical items, maintenance, service contacts",
      "files": ["knowledge.json", "maintenance.json", "contacts.json"]
    },
    {
      "id": "professional",
      "path": "brain/professional/",
      "description": "Career, network, conferences, professional relationships",
      "files": ["relationships.json", "conferences.json", "career.json"]
    },
    {
      "id": "projects",
      "path": "brain/projects/",
      "description": "Active project state, decisions, and session handoffs",
      "files": []
    },
    {
      "id": "finance",
      "path": "brain/finance/",
      "description": "Subscriptions, insurance, recurring financial items",
      "files": ["subscriptions.json", "insurance.json"]
    },
    {
      "id": "health",
      "path": "brain/health/",
      "description": "Healthcare providers, appointments, recurring checkups",
      "files": ["providers.json", "schedule.json"]
    },
    {
      "id": "learning",
      "path": "brain/learning/",
      "description": "Reading list, skill development, research notes",
      "files": ["reading-list.json", "skills-tracker.json"]
    }
  ],
  "agent_rules": {
    "path_format": "All paths use forward slashes. No spaces in any path or filename. Kebab-case only.",
    "id_format": "UUIDv4 for all entry IDs. Never reuse an ID.",
    "timestamp_format": "ISO 8601 UTC (e.g., 2026-03-15T14:30:00Z)",
    "update_protocol": "Read the file, find the entry by ID, update in place, write the full file back. Never append a duplicate.",
    "new_entry_protocol": "Generate a new UUIDv4 ID. Set created and last_modified to current UTC time. Append to the entries array.",
    "never_delete": "Entries are never deleted. Set status to 'archived' instead.",
    "file_encoding": "UTF-8, no BOM"
  }
}
```

### 3.2 knowledge.json — General Household Knowledge

```json
{
  "_meta": {
    "type": "household-knowledge",
    "version": "1.0",
    "description": "Household facts and institutional knowledge. Each entry is a discrete fact captured from conversation or manual entry. Agent: when the user mentions a household fact in passing, save it here.",
    "file": "brain/household/knowledge.json"
  },
  "entries": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "category": "paint",
      "subcategory": "living-room",
      "fact": "Living room paint is Benjamin Moore Hale Navy HC-154",
      "source": "Purchased at Sherwin Williams, October 2025",
      "tags": ["paint", "living-room", "benjamin-moore"],
      "created": "2025-10-14T09:00:00Z",
      "last_modified": "2025-10-14T09:00:00Z",
      "status": "active"
    },
    {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "category": "network",
      "subcategory": "wifi",
      "fact": "Guest WiFi password: SunflowerHouse2024",
      "source": "Router admin panel",
      "tags": ["wifi", "network", "guest"],
      "created": "2025-06-01T12:00:00Z",
      "last_modified": "2025-06-01T12:00:00Z",
      "status": "active"
    }
  ]
}
```

### 3.3 maintenance.json — Home Maintenance Tracker

```json
{
  "_meta": {
    "type": "maintenance-tracker",
    "version": "1.0",
    "description": "Appliances, systems, and items requiring periodic maintenance. Each entry tracks the item, its maintenance interval, last service date, warranty info, and next action date. Agent: flag anything overdue or expiring within 30 days when asked about home maintenance.",
    "file": "brain/household/maintenance.json"
  },
  "entries": [
    {
      "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
      "item": "HVAC system",
      "location": "basement-utility-room",
      "make_model": "Carrier Infinity 24ACC636A003",
      "install_date": "2021-04-15",
      "warranty_expiry": "2031-04-15",
      "maintenance_interval_months": 6,
      "last_service_date": "2025-09-20",
      "last_service_notes": "Filter replaced, coils cleaned, refrigerant checked",
      "service_provider_id": "d4e5f6a7-b8c9-0123-defa-234567890123",
      "next_due": "2026-03-20",
      "estimated_cost": 150,
      "tags": ["hvac", "heating", "cooling", "filter"],
      "status": "active",
      "created": "2025-09-20T14:00:00Z",
      "last_modified": "2025-09-20T14:00:00Z"
    }
  ]
}
```

### 3.4 relationships.json — Professional Network

```json
{
  "_meta": {
    "type": "professional-relationships",
    "version": "1.0",
    "description": "Professional contacts with relationship health tracking. Agent: when asked 'who have I been neglecting' or 'who should I reach out to', scan for contacts where days since last_contact exceeds the warmth_threshold_days. Flag any where the gap is approaching or past threshold.",
    "file": "brain/professional/relationships.json"
  },
  "entries": [
    {
      "id": "e5f6a7b8-c9d0-1234-efab-345678901234",
      "name": "James Chen",
      "title": "VP Engineering",
      "company": "Acme Corp",
      "relationship_type": "professional-peer",
      "how_met": "AWS re:Invent 2024, data engineering track",
      "topics_of_interest": ["distributed-systems", "team-scaling", "rust"],
      "last_contact": "2025-12-10",
      "last_contact_context": "Coffee chat, he mentioned team reorg stress. Said hiring would resume Q2.",
      "warmth_threshold_days": 60,
      "warmth_status": "cooling",
      "next_action": "Check in about Q2 hiring plans",
      "linkedin_url": "https://linkedin.com/in/jameschen",
      "email": "james.chen@acmecorp.example.com",
      "tags": ["engineering", "leadership", "aws", "potential-referral"],
      "status": "active",
      "created": "2024-12-05T18:00:00Z",
      "last_modified": "2025-12-10T11:00:00Z"
    }
  ]
}
```

### 3.5 session-state.json — Project Session Handoff

```json
{
  "_meta": {
    "type": "project-session-state",
    "version": "1.0",
    "description": "Session handoff file for the DCFG Contracting Suite project. Read this at the start of every session to know where things stand. Update it at the end of every session. JSON format chosen deliberately — agent should edit fields, not rewrite the structure.",
    "file": "brain/projects/dcfg/session-state.json"
  },
  "project": "DCFG Contracting Suite",
  "last_session": {
    "date": "2026-03-14T22:00:00Z",
    "summary": "Completed baseline spec for Screen 2 property onboarding. Identified gaps in conditional rendering and missing JS functions. Seed script for dcfg_template_field returned 400 errors — likely column propagation timing issue.",
    "model_used": "claude-opus-4-6",
    "session_duration_minutes": 90
  },
  "current_state": {
    "active_workstream": "Phase 1 — Property Onboarding Screen",
    "blocked_items": [
      {
        "id": "block-001",
        "description": "dcfg_template_field seed script 400 errors",
        "likely_cause": "Column propagation timing or name mismatch",
        "next_step": "Verify column names against live schema, retry with propagation sleep"
      }
    ],
    "in_progress": [
      "Screen 2 baseline spec gap closure (conditional rendering)",
      "New MSA Sales Proposal wizard — React component wiring"
    ],
    "completed_recently": [
      "DCFG_P1_OB_Baseline.md reviewed",
      "DCFG_Schema_Consolidated.md produced",
      "PowerShell schema scripts OP-26 through OP-30 delivered"
    ]
  },
  "features": [
    {
      "id": "feat-001",
      "name": "Property onboarding screen (Screen 2)",
      "status": "in-progress",
      "passing": false,
      "notes": "Baseline spec complete, gaps identified at edges"
    },
    {
      "id": "feat-002",
      "name": "New MSA Sales Proposal wizard",
      "status": "in-progress",
      "passing": false,
      "notes": "Production React component exists, Dataverse schema scripts delivered"
    },
    {
      "id": "feat-003",
      "name": "Dashboard KPI tiles (Page 01)",
      "status": "not-started",
      "passing": false,
      "notes": ""
    }
  ],
  "decisions_pending": [
    "How to handle vendor-property service junction table UX"
  ],
  "next_session_should": [
    "Resolve dcfg_template_field seed script 400 errors",
    "Close conditional rendering gaps in Screen 2 spec",
    "Continue New MSA wizard — wire remaining Dataverse calls"
  ]
}
```

### 3.6 session-log.jsonl — Append-Only Interaction Log

This is the equivalent of the autoresearch `results.jsonl`. One line per session, append only.

```jsonl
{"session_id":"s-20260314-001","date":"2026-03-14T22:00:00Z","tool":"claude-opus-4-6","interface":"claude.ai","category":"projects/dcfg","summary":"Screen 2 baseline spec review, gap identification, schema script delivery","entries_created":3,"entries_modified":1,"duration_minutes":90}
{"session_id":"s-20260315-001","date":"2026-03-15T10:00:00Z","tool":"claude-opus-4-6","interface":"claude.ai","category":"learning","summary":"Autoresearch skill review, improvement plan created for 4 DCFG skills","entries_created":1,"entries_modified":0,"duration_minutes":120}
```

---

## 4. Path Safety Rules

### 4.1 The Problem

OneDrive syncs to Windows, macOS, and mobile. The sync client creates local paths like:

```
C:\Users\Joe\OneDrive\brain\household\knowledge.json       ← works
C:\Users\Joe\OneDrive\My Brain\House Hold\my file.json     ← breaks everything
```

Spaces in paths break: PowerShell commands without proper quoting, bash/shell scripts, Python `subprocess` calls, `os.path` operations when string-concatenated, API URL encoding, and many MCP tool implementations.

### 4.2 The Rules

These are enforced at every layer — file creation, agent output, scripts, documentation:

1. **No spaces.** Use hyphens: `maintenance-log.json` not `maintenance log.json`
2. **All lowercase.** `household/` not `Household/`
3. **Kebab-case only.** `reading-list.json` not `readingList.json` or `reading_list.json`
4. **No special characters** except hyphens in names and dots before extensions
5. **Forward slashes in all documentation and agent output.** Windows resolves them correctly. Backslashes cause escaping nightmares in JSON and scripts.
6. **Always quote paths in shell commands.** Even with no spaces, quoting is defensive:

```powershell
# CORRECT — always quote, even when no spaces
$brainRoot = "$env:OneDrive/brain"
$file = "$brainRoot/household/knowledge.json"
$data = Get-Content -Path "$file" -Raw | ConvertFrom-Json

# WRONG — unquoted path, breaks if OneDrive root has spaces
$data = Get-Content -Path $env:OneDrive/brain/household/knowledge.json
```

```bash
# CORRECT
BRAIN_ROOT="$HOME/OneDrive/brain"
cat "$BRAIN_ROOT/household/knowledge.json"

# WRONG
cat $HOME/OneDrive/brain/household/knowledge.json
```

7. **The OneDrive root itself may have spaces** (e.g., `OneDrive - Business`). Always resolve via environment variable and quote:

```powershell
# Windows — resolve OneDrive root safely
$oneDriveRoot = $env:OneDrive  # e.g., "C:\Users\Joe\OneDrive - Decades"
$brainRoot = Join-Path -Path $oneDriveRoot -ChildPath "brain"
```

```python
# Python — resolve safely
import os
onedrive_root = os.environ.get("OneDrive", os.path.expanduser("~/OneDrive"))
brain_root = os.path.join(onedrive_root, "brain")
```

---

## 5. Agent Integration Patterns

### 5.1 Pattern A: Upload at Session Start (Works Today)

User downloads the relevant file(s) from OneDrive and uploads to the AI conversation.

**Workflow:**
1. Open conversation with Claude / ChatGPT / etc.
2. Upload `brain-config.json` + the relevant domain file(s)
3. Say: "Read my brain config and the household knowledge file. I want to add some entries."
4. AI reads, reasons, produces updated JSON
5. User saves the updated JSON back to OneDrive

**Automation opportunity:** A simple script that zips the relevant brain files and copies them to clipboard/downloads for quick upload:

```powershell
# quick-brain-export.ps1 — grab brain files for upload
$brainRoot = Join-Path -Path $env:OneDrive -ChildPath "brain"
$exportDir = Join-Path -Path $env:TEMP -ChildPath "brain-export"

New-Item -ItemType Directory -Path "$exportDir" -Force | Out-Null
Copy-Item -Path "$brainRoot/_system/brain-config.json" -Destination "$exportDir/"

# Copy specific category — pass as argument
$category = $args[0]  # e.g., "household"
if ($category) {
    Copy-Item -Path "$brainRoot/$category/*" -Destination "$exportDir/" -Recurse
}

Write-Host "Brain files exported to: $exportDir" -ForegroundColor Cyan
explorer.exe "$exportDir"
```

### 5.2 Pattern B: Claude Memory + Sync Script (Near-Term)

Claude's built-in memory captures facts from conversations. A periodic script reads Claude's memory exports (if available) and structures them into brain files.

This pattern depends on Anthropic exposing memory export — not available today but likely coming.

### 5.3 Pattern C: MCP Server + Microsoft Graph (Full Automation)

A local MCP server authenticates to Microsoft Graph API and exposes OneDrive file operations as tools. Any MCP-compatible client can read/write brain files directly.

**MCP Tool Surface:**

| Tool | Description |
|------|-------------|
| `brain_read` | Read a brain file by relative path (e.g., `household/knowledge.json`) |
| `brain_write` | Write updated content to a brain file |
| `brain_search` | Search across all brain files for entries matching a query |
| `brain_list` | List all files in a brain category |
| `brain_add_entry` | Add a new entry to a specific brain file (handles ID generation, timestamps) |
| `brain_update_entry` | Update an existing entry by ID |
| `brain_log_session` | Append a session summary to session-log.jsonl |

**Graph API Operations Used:**

| Operation | Graph Endpoint |
|-----------|---------------|
| Read file | `GET /me/drive/root:/brain/{path}:/content` |
| Write file | `PUT /me/drive/root:/brain/{path}:/content` |
| List folder | `GET /me/drive/root:/brain/{folder}:/children` |
| Search | `GET /me/drive/root/search(q='{query}')` |

**Auth:** OAuth 2.0 device code flow (same pattern you use for DCFG PowerShell — interactive browser auth, token cached locally).

---

## 6. Getting Started — Phase 1 Checklist

Phase 1 requires zero infrastructure. Just files on OneDrive.

1. Create the `brain/` folder in your OneDrive root
2. Create subfolders: `_system/`, `_templates/`, `household/`, `professional/`, `projects/`, `finance/`, `health/`, `learning/`
3. Drop `brain-config.json` into `_system/`
4. Create your first knowledge file — start with `household/knowledge.json` using the schema above
5. Start a conversation with Claude, upload the config + knowledge file, and say: "Read these. I'm going to mention some household facts. Save each one as a new entry in the knowledge file format."
6. At the end of the conversation, save the updated JSON back to OneDrive
7. Next conversation with any AI: upload the same files. The AI picks up where you left off.

**The habit that makes this work:** Every time you mention a fact in conversation that you'd want to find later, say "save this to brain." Over a few weeks, the files fill up with your institutional knowledge. The value compounds.

---

## 7. Viewer App (Phase 2 — When Ready)

When you want a visual layer, use any AI to generate a small web app:

**Prompt to generate the viewer:**
"Build me a mobile-friendly single-page web app that reads JSON files from a configurable base URL. It should display a search bar at the top, category cards below, and when you tap a category it shows all entries as scannable cards. Use Tailwind CSS. The app should handle household knowledge, maintenance tracking, and professional relationships schemas. Make it work as a static site I can deploy to Vercel or open from a local file."

The viewer reads the same JSON files. No database. No API layer. Just fetch the files and render them. If hosted on Vercel, point it at your OneDrive public links or a simple API route that reads from Graph.

---

## 8. File Format Decision: Why JSON, Not Markdown

Per the Anthropic findings discussed earlier: agents treat JSON as data to edit surgically. They treat markdown as text to rewrite wholesale. For structured entries with IDs, timestamps, and status fields, JSON prevents the agent from reorganizing, adding commentary, or restructuring what's already there. It just updates the field it needs to and leaves everything else alone.

Markdown files are reserved for long-form notes, research summaries, and decision rationale — content where human readability matters more than agent precision.
