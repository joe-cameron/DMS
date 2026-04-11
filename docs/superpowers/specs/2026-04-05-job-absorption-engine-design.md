# Job Absorption Engine — Design Spec

**Date:** 2026-04-05
**Author:** Joseph Cameron / Claude
**Status:** Draft — Pending Review
**Goal:** Absorb 50-100 current fiscal year jobs from Sage, master tracker, and SharePoint file libraries into Dataverse. Enable generation of the $5.5M Bancroft master contract from aggregated job data. Run as a distributed background process across idle user desktops.

---

## 1. What This System Does

Takes the current fiscal year's project data — scattered across Sage reports, Excel trackers, and SharePoint/Teams file libraries with varying levels of compliance — and absorbs it into the DCFG project module. Each absorbed job becomes a complete `dcfg_project` record with financials, compliance status, and document inventory.

The absorbed data enables:
- Per-job Bancroft 7-point compliance visibility (green/amber/red)
- Program-level budget rollup ($5.5M from individual jobs)
- Master contract document generation with real numbers
- Baseline data for the AI vendor matching and cost factor engines

**Core constraint:** This is a slow, background process. User desktops process tasks when idle. No dedicated infrastructure. Work survives interruption.

---

## 2. Distributed Work Queue

### 2.1 Work Queue Table: `dcfg_absorption_task`

| Column | Type | Notes |
|--------|------|-------|
| dcfg_absorption_task_id | PK | |
| dcfg_task_type | Choice | SageImport=1, TrackerMerge=2, FileScan=3, ComplianceCheck=4, DocumentIndex=5 |
| dcfg_job_number | String(50) | Sage job number — the linking key |
| dcfg_project_id | FK → dcfg_project | Populated after Phase 1 creates the record |
| dcfg_status | Choice | Queued=1, InProgress=2, Completed=3, Failed=4, Skipped=5 |
| dcfg_assigned_to | String(200) | Machine name or user who picked it up |
| dcfg_picked_up_at | DateTime | When work started |
| dcfg_completed_at | DateTime | When work finished |
| dcfg_payload | Memo | JSON — input data for this task |
| dcfg_result | Memo | JSON — output/findings from this task |
| dcfg_error | Memo | Error message if failed |
| dcfg_retry_count | Integer | How many times retried |
| dcfg_phase | Integer | 1, 2, or 3 — controls ordering |
| dcfg_priority | Integer | Lower = higher priority |
| dcfg_active_flag | Boolean | Soft delete |

### 2.2 Worker Pattern

Each idle desktop runs a lightweight worker (PowerShell or browser-based):

```
LOOP (while desktop is idle):
  1. Query: GET dcfg_absorption_tasks?$filter=dcfg_status eq 1&$orderby=dcfg_phase,dcfg_priority&$top=1
  2. If no task → sleep 60s → retry
  3. Claim task: PATCH status=InProgress, assigned_to=machineName, picked_up_at=now
  4. Execute task based on dcfg_task_type
  5. On success: PATCH status=Completed, result=JSON, completed_at=now
  6. On failure: PATCH status=Failed, error=message, retry_count++
  7. If retry_count < 3 and failure is transient → PATCH status=Queued (re-queue)
```

**Idle detection:** Worker checks `GetLastInputInfo` (Windows API) — if no keyboard/mouse for 5 minutes, start processing. If user becomes active, finish current task then pause.

### 2.3 Task Dependencies

Phase ordering ensures data builds correctly:

| Phase | Task Type | Depends On | What It Does |
|-------|-----------|------------|-------------|
| 1 | SageImport | Nothing | Creates dcfg_project from Sage job report row |
| 1 | SageImport | Nothing | Links vendor, sets financials |
| 2 | TrackerMerge | Phase 1 complete for this job | Merges tracker data (status, dates, PM, trades) |
| 3 | FileScan | Phase 1 complete for this job | Scans SharePoint folder structure |
| 3 | ComplianceCheck | FileScan complete | Maps folder contents to Bancroft checklist |
| 3 | DocumentIndex | FileScan complete | Indexes individual documents for search |

A Phase 2 task won't be picked up until all Phase 1 tasks for that job number are Completed.

---

## 3. Phase 1 — Sage Import

### 3.1 Input
Staff exports "Job Cost Report" from Sage for current fiscal year. CSV or Excel.

### 3.2 Queue Generation Script
Reads the Sage export, creates one `dcfg_absorption_task` per job:

```
For each job row in Sage export:
  - Create task: type=SageImport, phase=1, job_number=row.JobNumber
  - Payload JSON: { jobNumber, vendorNumber, vendorName, contractAmount, invoicedAmount, paidAmount, startDate, status }
```

### 3.3 Worker Execution (SageImport task)
1. Check if dcfg_project already exists with this job number → skip if exists
2. Find dcfg_vendor by vendor_ref_number or legal_name
3. Find dcfg_property by address match (fuzzy)
4. Create dcfg_project record with Sage financials
5. Store result: { projectId, vendorId, propertyId, matched: true/false }

---

## 4. Phase 2 — Tracker Merge

### 4.1 Input
Staff exports master tracker spreadsheet.

### 4.2 Queue Generation
One task per job number found in the tracker:

```
For each tracker row:
  - Create task: type=TrackerMerge, phase=2, job_number=row.JobNumber
  - Payload JSON: { status, pm, trades, startDate, endDate, notes }
```

### 4.3 Worker Execution (TrackerMerge task)
1. Find dcfg_project by job number
2. PATCH: status, trades, dates, PM assignment, description
3. Store result: { fieldsUpdated: [...] }

---

## 5. Phase 3 — File Library Scan

### 5.1 Input
SharePoint/Teams project sites. Worker uses Graph API to scan.

### 5.2 Queue Generation
One FileScan task per absorbed project that has a known SharePoint site URL:

```
For each project with SharePoint site:
  - Create task: type=FileScan, phase=3, project_id=X
  - Payload JSON: { siteUrl, driveId }
```

### 5.3 Worker Execution (FileScan task)
1. Graph API: list folders in project site document library
2. For each of 14 standard folders, check: exists? has files? file count? newest file date?
3. Store result:
```json
{
  "folders": {
    "01 - Budget": { "exists": true, "fileCount": 3, "newestFile": "2026-02-15" },
    "02 - Proposals": { "exists": true, "fileCount": 7, "newestFile": "2025-11-20" },
    "05 - Invoices": { "exists": false, "fileCount": 0 },
    ...
  }
}
```

### 5.4 Compliance Check Task
After FileScan completes, a ComplianceCheck task is auto-queued:

1. Map folder contents to Bancroft 7-point checklist:
   - Insurance certificates → folder 09
   - Executed contracts → folder 04
   - Invoices → folder 05
   - Permits → folder 10
   - Submittals → folder 08
   - Closeout documentation → folder 13
   - Budget documentation → folder 01

2. Score: Green (file exists, dated within project period), Amber (file exists but outdated or misnamed), Red (missing)

3. Store result:
```json
{
  "complianceScore": 5,
  "maxScore": 7,
  "items": {
    "insurance": { "status": "green", "file": "COI_2026.pdf" },
    "executed_contract": { "status": "red", "note": "Folder empty" },
    ...
  }
}
```

---

## 6. Progress Dashboard

### 6.1 SPA Screen: `/absorption` (under ADMIN nav)

Shows:
- Total jobs to absorb: 78
- Phase 1 (Sage): 78/78 complete ████████████████████ 100%
- Phase 2 (Tracker): 45/78 complete ████████████░░░░░░░░ 58%
- Phase 3 (Files): 12/78 complete ███░░░░░░░░░░░░░░░░░ 15%
- Active workers: 3 (JCAMERON-PC, FRONT-DESK, TBAMFORD-PC)
- Failed tasks: 2 (click to see details)
- Estimated completion: ~4 hours remaining at current pace

### 6.2 Per-Job Detail
Click a job → shows absorption status across all phases, compliance score, any errors.

---

## 7. Master Contract Generation

Once absorption is complete (all Phase 1-3 done for all jobs):

The system has everything needed to produce the $5.5M Bancroft master contract:
- Every job's cost (from Sage)
- Every job's compliance status (from file scan)
- Every job's vendor and property (from linked records)
- Program-level rollup (sum of all job costs grouped by program)

The existing DocGen flow + template system handles document generation. The absorption engine provides the data.

---

## 8. Worker Deployment

### 8.1 Desktop Worker Script
A PowerShell script that:
- Runs as a scheduled task or startup item
- Checks idle status via Windows API
- Authenticates via pac auth (user's existing credentials)
- Picks up and processes absorption tasks
- Pauses when user becomes active
- Logs activity locally + to Dataverse

### 8.2 Installation
```powershell
# One-time setup per desktop
pwsh -File C:\DCFG\scripts\Install-AbsorptionWorker.ps1
# Creates: scheduled task, local log folder, pac auth verification
```

### 8.3 No Agent Required
This is NOT an AI agent. It's a deterministic script that follows rules:
- Sage import = create record from JSON payload
- Tracker merge = patch record from JSON payload
- File scan = Graph API folder listing
- Compliance check = rule-based folder→checklist mapping

The AI layer (vendor document matching, confidence scoring) is a separate future capability that consumes the data this engine produces.

---

## 9. Open Questions

1. **Sage report format** — Need a sample export to build the parser. What columns does the Job Cost Report include?
2. **Tracker format** — Need a sample of the master tracker spreadsheet to map columns.
3. **SharePoint site discovery** — Are all project sites under `decadesconstructiongroup.sharepoint.com/sites/`? Or do some live in Teams channels?
4. **How many desktops** will participate? This affects estimated completion time.
5. **Fiscal year cutoff** — What date range defines "current fiscal year"?
