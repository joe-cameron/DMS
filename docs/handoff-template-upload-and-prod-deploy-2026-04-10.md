# Handoff — Template Upload + Prod Deploy Follow-Up

**Date:** 2026-04-10
**Branch:** `code-review-2026-04-09` (SPA repo at `C:\DCFG\spa\dcfg-shell`)
**Status:** Prod deploy complete + hotfixes applied. Template upload feature built end-to-end but pending a small architecture refactor (Option B) before it can be tested.

---

## 1. What Shipped to Prod Today

### 1a. SPA code review — Phase 1 complete, deployed
- 100+ findings fixed across 8 batches
- Merged to SPA main, built, deployed via `pac pages upload-code-site`
- Bundle signature verified post-deploy

### 1b. Hotfix: System Admin link missing
- **Bug:** After Prod deploy, operator lost the System Admin link in nav
- **Root cause:** `usePortalUser.jsx` line 71 was reading `raw.roles`, but Power Pages exposes roles as `raw.userRoles` (plain string array)
- **Fix:** Commit `b87dfc3` — changed to `normaliseRoles(raw.userRoles)`
- **Status:** Deployed, verified, operator sees Admin link again

### 1c. Hotfix: Bind coverage gaps (403 errors)
- **Bug:** 403 on `/_api/dcfg_msas` during NewProposalWizard smoke test
- **Investigation:** Precise audit subagent found 22 missing bind columns across 10 tables in `Webapi/*/fields` powerpagecomponents
- **Fix:** Ran `backport-field-list.ps1` with `-Mode Append -RequiredBinds` for each table:
  - `dcfg_msa`, `dcfg_msa_rate`, `dcfg_contract`, + 7 others
- **Status:** All 22 columns added, cache cleared, deployed, verified

---

## 2. Template Upload Feature — Where It Stands

### 2a. The Ask
Operator wants a round-trip edit/replace UI for production Word templates:
> "a post-processed word template that I can edit what is in production. If a flow is necessary so be it. This is a very low frequency but critical."

### 2b. Architecture Chosen (Option Z / Option A from earlier menus)
- SPA file picker in Admin > Document Templates > Edit
- Converts file to base64, creates `dcfg_document_request` row with the base64 embedded in `dcfg_notes` as JSON
- Power Automate flow picks up the row, uploads to SharePoint, updates `dcfg_document_templates.dcfg_sharepoint_url`, marks request Complete

### 2c. Build Status — SPA side (BUILT, not yet rebuilt/deployed after Option B refactor)
**Modified file:** `C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx`
- `DocumentTemplatesTab > TemplateForm` — added "REPLACE PRODUCTION FILE" section with file picker + Replace button
- Added helpers `fileToBase64()` and `pollDocRequestStatus()`
- Imports `createDocumentRequest, DocRequestType, DocRequestStatus` from `portalApi.js`
- **Currently calls:** `DocRequestType.CertUpload` — **this is what Option B will change**

### 2d. Build Status — Flow side (BUILT, LIVE, not yet tested)
**Flow:** `DCFG Template File Upload`
- `workflowid`: `71c2aef7-fd34-f111-88b3-000d3a308bc8`
- `workflowidunique`: `4cfad356-8a92-4b59-9d9b-d3ca3e9f9b2e`
- `statecode`: 1 (active)
- **Current trigger filter:** `dcfg_request_type eq 100000002 and dcfg_status eq 100000000` — **this is what Option B will change**
- Full actions pushed via Step 3 script — Parse_Notes → Guard_Is_Template (If) → Scope_Main (Set_Processing → Get_Template_Record → List_Library_Config → Upload_To_SharePoint → Compute_New_Url → Update_Template_Record → Mark_Request_Complete) → Handle_Failure
- Operator added both connection refs in the designer and published

**Build scripts for re-reference:**
- `C:\dcfg\scripts\code-review\_create-template-upload-flow.ps1` — Step 1 of 3 (POST new flow with Compose placeholders)
- `C:\dcfg\scripts\code-review\_inspect-new-flow-post-designer.ps1` — Step 2 of 3 (read back after operator connected)
- `C:\dcfg\scripts\code-review\_push-template-upload-flow-step3.ps1` — Step 3 of 3 (PATCH full action definitions)
- `C:\dcfg\scripts\code-review\_find-certupload-flows.ps1` — Discovery script that found the type-100000002 collision
- `C:\dcfg\scripts\code-review\_list-connection-refs.ps1` — Connection reference lookup for operator

**Spec:** `C:\dcfg\docs\templates\flow-template-upload-spec.md`

---

## 3. THE BLOCKER — Option B Refactor (Pending Execution)

### 3a. The Problem Discovered Late Session
The new `DCFG Template File Upload` flow and the existing `flow_cert_upload` flow **both filter on `dcfg_request_type eq 100000002`**:
- `flow_cert_upload` has no status filter — fires on any cert upload row
- `DCFG Template File Upload` additionally requires `dcfg_status eq 100000000` + has `Guard_Is_Template` If-check on `notes.target == 'template'`

Both flows would fire on the same row and race. Operator correctly identified this as architecturally wrong.

### 3b. Operator's Decision: Option B
> "this is a new type document Request" — operator's exact words
> Final choice: **B** (use new `TemplateUpload = 100000004` request type)

### 3c. The 6-Step Refactor (NOT YET STARTED)

| # | Action | Where | Notes |
|---|---|---|---|
| 1 | Add Choice value `TemplateUpload = 100000004` to `dcfg_request_type` Choice column | Prod Dataverse, table `dcfg_document_request` | Use Metadata API `UpdateOptionSet` + `PublishXml` after. Label: "Template Upload". Value: 100000004. |
| 2 | Add `TemplateUpload: 100000004` to `DocRequestType` constant | `C:\DCFG\spa\dcfg-shell\src\portalApi.js` ~line 105 | One-line change |
| 3 | Change `handleReplaceFile` to use `DocRequestType.TemplateUpload` | `C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx` | One-line change |
| 4 | PATCH flow `subscriptionRequest/filterexpression` from `dcfg_request_type eq 100000002` to `dcfg_request_type eq 100000004` | Prod workflows table, flowid `71c2aef7-fd34-f111-88b3-000d3a308bc8` | Preserve everything else in clientdata — only touch the trigger's filter expression. Follow the never-overwrite-trigger rule; read-modify-write the existing trigger object. |
| 5 | Rebuild + deploy SPA | `npm run build` + `pac pages upload-code-site` | Standard deploy |
| 6 | Turn flow OFF then ON | Power Automate UI or `statecode` PATCH | Required to re-register the Dataverse webhook subscription with the new filter |

After step 6: test via SPA Admin > Document Templates > Edit any template > scroll to REPLACE PRODUCTION FILE > pick a small .docx > click Replace. Watch `dcfg_document_requests` for a row with `dcfg_request_type=100000004` transitioning Pending → Processing → Complete.

### 3d. What NOT to touch
- Leave `Guard_Is_Template` in the flow as defense-in-depth (it's cheap insurance)
- Do NOT patch `flow_cert_upload` — under Option B, it never sees template rows
- Do NOT delete the 100000002 Choice value — cert upload still uses it

---

## 4. Known Follow-Ups (Out of Scope Today, Tracked)

- **Config seed rows:** `dcfg_decades_vendor_id`, `dcfg_nora_webchat_url`, `dcfg_team_email`, `dcfg_compliance_email`, `dcfg_leaflet_css_url`, `dcfg_leaflet_js_url`, `dcfg_sp_logo_base_url` — missing from `dcfg_configs` on Prod, screens degrade gracefully but should be populated
- **CompliancePanel SPA bug:** Wrong bind column names (from audit). Not blocking Prod user testing but should be on the list
- **Template UI scoping:** Operator noted templates are a project concept, not sales — remove any template references from NewProposalWizard if they exist
- **`flow_cert_alert` went inactive:** Nora flagged this in the most recent cycle. Not something I deactivated. Needs investigation — is this expected or did something deactivate it?
- **`flow_template_validate` went inactive:** Expected — it was the abandoned Step-1 placeholder from earlier template-upload exploration. Can be safely deleted.

---

## 5. Context for Next Session

### Current Nora state
- Scheduled via `/loop 5m /nora` — cron `*/5 * * * *`, job ID `8451f3d4` (session-only, expires in 3 days)
- Last cycle at 14:18:51 local: flows healthy except the 2 inactive ones noted above; no stuck requests; no new audit errors
- If session restarts, re-run `/loop 5m /nora`

### Environment state
- pac auth index: should be [3] Prod since last deploy — **restore to [1] Test before any test work** per CLAUDE.md mandate
- Active branch: `code-review-2026-04-09` (SPA repo)
- No uncommitted SPA changes that matter; the Option B refactor will produce the next commit

### Files that define this work
- Spec: `C:\dcfg\docs\templates\flow-template-upload-spec.md`
- This handoff: `C:\dcfg\docs\handoff-template-upload-and-prod-deploy-2026-04-10.md`
- SPA source (READ-ONLY reminder — only change what Option B needs):
  - `C:\DCFG\spa\dcfg-shell\src\portalApi.js`
  - `C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx`

### Resume instruction for next Claude
Start here: "Execute Option B refactor per section 3c of `docs/handoff-template-upload-and-prod-deploy-2026-04-10.md`. Operator approved with `B` at end of 2026-04-10 session. Six steps, ~15–20 min. Do not ask for re-approval on the overall plan; do ask for the safety-controls WRITE REQUEST prompt before each write (schema change, flow PATCH, SPA deploy)."
