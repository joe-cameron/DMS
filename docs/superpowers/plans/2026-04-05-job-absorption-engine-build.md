# Job Absorption Engine — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a distributed work queue that absorbs current fiscal year jobs from Sage reports, master tracker, and SharePoint file libraries into Dataverse — enabling Bancroft compliance visibility and $5.5M master contract generation.

**Architecture:** A `dcfg_absorption_task` table holds discrete work items processed by idle desktop workers. Three phases build data incrementally: Sage financials → tracker context → file library compliance scan. An SPA dashboard shows progress. Workers are PowerShell scripts using pac auth + Graph API.

**Tech Stack:** PowerShell (workers + queue generation), Dataverse Web API, Microsoft Graph API (SharePoint file scanning), React 16.14 + Vite (absorption dashboard)

**Spec:** `C:\dcfg\docs\superpowers\specs\2026-04-05-job-absorption-engine-design.md`

**Target Environment:** Test (org0c17e98d.crm.dynamics.com) only

---

## Chunk 1: Dataverse Schema + Queue Infrastructure

### Task 1: Create dcfg_absorption_task table

**Files:**
- Create: `C:\DCFG\scripts\absorption\Build-AbsorptionSchema.ps1`

- [ ] **Step 1: Check if table already exists**

```powershell
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\CommonFunctions.ps1"
Connect "https://org0c17e98d.crm.dynamics.com/"
$OrgUrl = "https://org0c17e98d.crm.dynamics.com/api/data/v9.2"
Invoke-DataverseCommands {
    try {
        $r = Invoke-RestMethod -Uri "$OrgUrl/EntityDefinitions(LogicalName='dcfg_absorption_task')?`$select=LogicalName,EntitySetName" -Headers $baseHeaders
        Write-Host "EXISTS: $($r.EntitySetName)"
    } catch { Write-Host "NEEDS CREATE" }
}
```

- [ ] **Step 2: Create the table with all columns**

Create `dcfg_absorption_task` with columns per spec Section 2.1:
- dcfg_task_type (Choice: SageImport=100000000, TrackerMerge=100000001, FileScan=100000002, ComplianceCheck=100000003, DocumentIndex=100000004)
- dcfg_job_number (String 50)
- dcfg_status (Choice: Queued=100000000, InProgress=100000001, Completed=100000002, Failed=100000003, Skipped=100000004)
- dcfg_assigned_to (String 200)
- dcfg_picked_up_at (DateTime)
- dcfg_completed_at (DateTime)
- dcfg_payload (Memo)
- dcfg_result (Memo)
- dcfg_error (Memo)
- dcfg_retry_count (Integer)
- dcfg_phase (Integer)
- dcfg_priority (Integer)
- dcfg_active_flag (Boolean)
- dcfg_project_id (Lookup → dcfg_project)

- [ ] **Step 3: Add table to DCFGSystemTest solution**

- [ ] **Step 4: Create table permissions + site settings for portal access**

Create mspp_entitypermission for dcfg_absorption_task (RWCDApAT, Global scope). Link to DCFG_Admin role via content JSON. Add Webapi site settings (enabled + fields).

- [ ] **Step 5: Verify by querying the new table**

Run: Query dcfg_absorption_tasks entity set, confirm 0 records, no errors.

---

### Task 2: Build the queue generation scripts

**Files:**
- Create: `C:\DCFG\scripts\absorption\Generate-SageQueue.ps1`
- Create: `C:\DCFG\scripts\absorption\Generate-TrackerQueue.ps1`
- Create: `C:\DCFG\scripts\absorption\Generate-FileScanQueue.ps1`

- [ ] **Step 1: Write Generate-SageQueue.ps1**

Takes a Sage job cost report CSV/Excel and creates one absorption task per job row.

```powershell
param(
    [Parameter(Mandatory=$true)][string]$SageReportPath,
    [switch]$DryRun
)
```

Parses the report, for each job:
- Creates dcfg_absorption_task with task_type=SageImport, phase=1, status=Queued
- Payload JSON contains all Sage fields: jobNumber, vendorNumber, vendorName, contractAmount, invoicedAmount, paidAmount, startDate
- DryRun mode: outputs what WOULD be created without writing to Dataverse

- [ ] **Step 2: Write Generate-TrackerQueue.ps1**

Same pattern — takes master tracker export, creates TrackerMerge tasks (phase=2) for each row.

- [ ] **Step 3: Write Generate-FileScanQueue.ps1**

Queries all dcfg_projects that have Phase 1 completed, creates FileScan tasks (phase=3) for each.

- [ ] **Step 4: Test with sample data**

Create a small 3-row sample Sage CSV and run Generate-SageQueue.ps1 with -DryRun to verify output.

Then run without -DryRun to create 3 real tasks in Dataverse.

Query dcfg_absorption_tasks to verify 3 records created with status=Queued.

---

## Chunk 2: Desktop Worker

### Task 3: Build the absorption worker

**Files:**
- Create: `C:\DCFG\scripts\absorption\Start-AbsorptionWorker.ps1`
- Create: `C:\DCFG\scripts\absorption\workers\Invoke-SageImport.ps1`
- Create: `C:\DCFG\scripts\absorption\workers\Invoke-TrackerMerge.ps1`
- Create: `C:\DCFG\scripts\absorption\workers\Invoke-FileScan.ps1`
- Create: `C:\DCFG\scripts\absorption\workers\Invoke-ComplianceCheck.ps1`
- Create: `C:\DCFG\scripts\absorption\workers\Invoke-DocumentIndex.ps1`

- [ ] **Step 1: Write Start-AbsorptionWorker.ps1 (the main loop)**

```powershell
param(
    [int]$IdleThresholdSeconds = 300,  # 5 minutes idle before processing
    [int]$PollIntervalSeconds = 60,
    [switch]$IgnoreIdle  # For testing — process immediately
)
```

Main loop:
1. Check idle status (GetLastInputInfo via Add-Type P/Invoke, or skip if -IgnoreIdle)
2. If idle: query next Queued task ordered by phase, priority
3. Claim task (PATCH status=InProgress, assigned_to=$env:COMPUTERNAME)
4. Dispatch to worker script based on task_type
5. On success: PATCH status=Completed, result=JSON
6. On failure: PATCH status=Failed, error=message; if retry_count < 3, re-queue
7. If user becomes active mid-task: finish current task, then pause
8. Loop

- [ ] **Step 2: Write Invoke-SageImport.ps1**

Takes a task payload JSON. Creates dcfg_project record:
1. Parse payload (jobNumber, vendorNumber, vendorName, contractAmount, etc.)
2. Check if project already exists by job number (dcfg_cost_code match) → skip if exists
3. Find dcfg_vendor by dcfg_legal_name (fuzzy match — contains)
4. Find dcfg_property by address (fuzzy — optional, many won't match)
5. Create dcfg_project with financials
6. Return result JSON: { projectId, vendorMatched, propertyMatched }

- [ ] **Step 3: Write Invoke-TrackerMerge.ps1**

Takes a task payload JSON. Updates existing dcfg_project:
1. Find project by job number
2. PATCH: status, trades, dates, PM, description from payload
3. Return result JSON: { projectId, fieldsUpdated: [...] }

- [ ] **Step 4: Write Invoke-FileScan.ps1**

Takes a task payload JSON with SharePoint site URL. Scans folders:
1. Get Graph API token via Get-AzAccessToken
2. List drives on the project site
3. For each of 14 standard folders: check exists, count files, get newest file date
4. Return result JSON: { folders: { "01 - Budget": { exists, fileCount, newestFile }, ... } }
5. Auto-queue ComplianceCheck task for this project

- [ ] **Step 5: Write Invoke-ComplianceCheck.ps1**

Takes FileScan result. Maps to Bancroft 7-point checklist:
1. Read the FileScan result from parent task
2. Map each compliance item to its expected folder:
   - Insurance certificates → 09 - Licensing Paperwork
   - Executed contracts → 04 - Executed Exhibit A
   - Invoices → 05 - Invoices
   - Permits → 10 - Permits
   - Submittals → 08 - Submittals
   - Closeout → 13 - Closeout
   - Budget → 01 - Budget
3. Score: green (files present, dated within project period), amber (exists but concerns), red (missing/empty)
4. Return result JSON: { complianceScore: 5, maxScore: 7, items: {...} }

- [ ] **Step 6: Write Invoke-DocumentIndex.ps1**

Takes a task payload with file list. For each document:
1. Download file content via Graph API
2. Extract text (PDF → text, Word → text, Excel → cell values)
3. Classify document type (invoice, permit, COI, contract, submittal)
4. Extract key fields (amounts, dates, vendor names)
5. Store as dcfg_location_document or similar record
6. Return result JSON: { documentsIndexed: N, types: { invoice: 3, permit: 1, ... } }

Note: Document text extraction may need external service for PDFs. Start with simple file metadata (name, size, date, type) and add content extraction later.

- [ ] **Step 7: Test the worker with the 3 sample tasks**

Run: `pwsh -File C:\DCFG\scripts\absorption\Start-AbsorptionWorker.ps1 -IgnoreIdle`

Expected: Worker picks up 3 SageImport tasks, creates 3 dcfg_project records, marks tasks Completed.

---

## Chunk 3: SPA Absorption Dashboard

### Task 4: Build the absorption progress screen

**Files:**
- Create: `C:\DCFG\spa\dcfg-shell\src\screens\AbsorptionDashboard.jsx`
- Modify: `C:\DCFG\spa\dcfg-shell\src\AppRouter.jsx` (add route)
- Modify: `C:\DCFG\spa\dcfg-shell\src\NavPanel.jsx` (add nav item under ADMIN)
- Modify: `C:\DCFG\spa\dcfg-shell\src\portalApi.js` (add fetch functions)

- [ ] **Step 1: Add API functions to portalApi.js**

```javascript
// Absorption task queries
export function fetchAbsorptionSummary() {
  return apiGet(`/dcfg_absorption_tasks?$apply=groupby((dcfg_phase,dcfg_status),aggregate($count as count))`);
}
export function fetchAbsorptionTasks(phase, status) {
  let filter = `dcfg_active_flag eq true`;
  if (phase) filter += ` and dcfg_phase eq ${phase}`;
  if (status) filter += ` and dcfg_status eq ${status}`;
  return apiGet(`/dcfg_absorption_tasks?$filter=${filter}&$select=dcfg_absorption_taskid,dcfg_job_number,dcfg_task_type,dcfg_status,dcfg_phase,dcfg_assigned_to,dcfg_completed_at,dcfg_error&$orderby=dcfg_phase,dcfg_priority&$top=200`);
}
export function fetchAbsorptionWorkers() {
  return apiGet(`/dcfg_absorption_tasks?$filter=dcfg_status eq 100000001&$select=dcfg_assigned_to,dcfg_picked_up_at,dcfg_job_number`);
}
```

- [ ] **Step 2: Create AbsorptionDashboard.jsx**

Shows:
- Three phase progress bars (Sage / Tracker / Files) with counts
- Active workers list (machine names currently processing)
- Failed tasks table (click to see error details)
- Per-job status grid: job number, phase 1/2/3 status (green/yellow/red dots)
- Overall compliance summary (once Phase 3 data exists)

- [ ] **Step 3: Add route and nav item**

AppRouter.jsx: `<Route path="absorption" element={<AbsorptionDashboard />} />`
NavPanel.jsx: Add under ADMIN group: `{ to: '/absorption', label: 'Job Absorption', icon: <AdminIcon /> }`

- [ ] **Step 4: Build and deploy to Test**

```bash
cd C:\DCFG\spa\dcfg-shell
npm run build
pac auth select --index 1
pac pages upload-code-site --rootPath . --compiledPath dist
```

Clear cache: `https://dcfg.powerappsportals.com/_services/about?clearCache=true`

---

## Chunk 4: Worker Installer + End-to-End Test

### Task 5: Build the worker installer

**Files:**
- Create: `C:\DCFG\scripts\absorption\Install-AbsorptionWorker.ps1`

- [ ] **Step 1: Write installer script**

```powershell
param(
    [string]$InstallPath = "C:\DCFG\scripts\absorption",
    [switch]$Uninstall
)
```

Does:
1. Verifies pac auth is configured (can connect to Dataverse)
2. Verifies Graph API access (Get-AzAccessToken)
3. Creates Windows scheduled task: runs Start-AbsorptionWorker.ps1 at logon
4. Creates local log folder: C:\DCFG\logs\absorption\
5. Outputs: "Worker installed. Will process tasks when desktop is idle."

Uninstall: removes scheduled task.

- [ ] **Step 2: End-to-end test**

1. Create a sample Sage report CSV with 3 test jobs
2. Run Generate-SageQueue.ps1 to create 3 tasks
3. Run Start-AbsorptionWorker.ps1 -IgnoreIdle to process them
4. Verify 3 dcfg_project records created
5. Run Generate-TrackerQueue.ps1 with matching tracker data
6. Run worker again — verify projects updated with tracker data
7. Check SPA dashboard shows progress
8. Verify all tasks show Completed status

---

## Chunk 5: Sage Report Parser (sample-driven)

### Task 6: Parse actual Sage report format

**Files:**
- Create: `C:\DCFG\scripts\absorption\Parse-SageJobReport.ps1`

This task depends on receiving an actual Sage Job Cost Report export. The parser must handle the actual format (likely similar to the Sage vendor export we already parsed — Excel with header rows, merged cells, section separators).

- [ ] **Step 1: Analyze the Sage report structure**

Same Open XML parsing approach used for the vendor import:
1. Extract xlsx
2. Read sharedStrings.xml
3. Parse sheet1.xml cells
4. Identify header row, data rows, section markers
5. Map columns to expected fields

- [ ] **Step 2: Build the parser**

Outputs structured JSON per job: jobNumber, vendorNumber, vendorName, contractAmount, invoicedAmount, paidAmount, status, dates.

- [ ] **Step 3: Wire into Generate-SageQueue.ps1**

Update the queue generator to use the parser instead of assuming CSV format.

---

## Execution Notes

- **Chunk 1** (schema + queue) can be built immediately
- **Chunk 2** (worker) can be built immediately
- **Chunk 3** (SPA) can be built immediately
- **Chunk 4** (installer + E2E test) depends on Chunks 1-3
- **Chunk 5** (Sage parser) depends on receiving an actual Sage report file

Start with Chunks 1-3 in parallel, then Chunk 4 for integration testing.
