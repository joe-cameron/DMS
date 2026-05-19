# Session Handoff — 2026-05-19

## Branch
`code-review-2026-04-09`

## Summary
DocuSign developer account configured and validated. Built table-driven 8-step signing workflow editor in Admin. Fixed code review Phase 1 runtime/logic bugs. Updated template tag reference page to match actual production templates. Prepared 7 templates with corrected yellow tags for re-upload. Built UpKeep read-only MCP for Claude Desktop/Teams with installer. Rotated Azure Function key and removed hardcoded secrets from source. Added PostToolUse hook for automatic session journaling.

---

## DocuSign Developer Account — Configured

| Setting | Value |
|---------|-------|
| Integration Key | `928426e0-7cba-412e-9879-3ff95e4b301a` |
| User ID | `4558c906-9dd2-4de8-bb5b-d9d95f61729d` |
| Account ID | `9c7b45ed-703a-45b7-b5ab-e157eb30a988` |
| Base URL | `https://demo.docusign.net/restapi` |
| OAuth Base | `https://account-d.docusign.com` |
| RSA Key | Set in Azure Function App settings |
| JWT Consent | Granted via `https://account-d.docusign.com/oauth/auth` |
| Redirect URI | `https://localhost/callback` (added to DocuSign app) |

All 6 env vars set on `dcfg-html-to-pdf` Azure Function App. JWT token acquisition validated — HTTP 200, Bearer token, 3600s expiry.

### E2E Tests Sent
- **Envelope `0e6d2f8d`** — 2-signer sequential test (test1 → jcameron)
- **Envelope `948f2d6b`** — 3-step test: approver → vendor sign → customer sign
- **Envelope `650b2bc2`** — New recipients API format validation

Dev sandbox limits total recipients to ~3-4 per envelope. Production DocuSign supports full 8-step flow.

---

## DocuSign 8-Step Signing Workflow — Built

### Azure Function (`docusignSend.js`)
Rewrote `createEnvelope()` to accept a dynamic `recipients` array instead of hardcoded signerA/signerB. Each recipient has:
- `role`: "signer" | "approver" | "cc"
- `routingOrder`: controls sequence
- `anchorSign` / `anchorDate`: for signers
- `anchorApprove` / `approveLabel`: for approvers (review button, no visible signature)

Legacy `signerA`/`signerB` format still supported via `normalizeLegacyToRecipients()`.

### Admin UI (`SigningWorkflowEditor.jsx`)
New panel in Admin → Templates screen. Features:
- Dropdown to select document type (WO TPA, Amendment, VA TPA, WO Direct, VA Direct)
- Add/remove/reorder steps with up/down arrows
- Per step: label, role (signer/approver/cc), name source, email source, sign anchor, date anchor
- Source presets dropdown: config values, contract fields, customer fields
- Anchor presets dropdown: all 6 DocuSign anchor strings
- Save stores JSON in `dcfg_configs` table

### SPA (`DocuSignModal.jsx`)
Updated to read workflow config at send time:
1. Looks up `dcfg_docusign_workflow_{contractType}` from config
2. If found, resolves each step's name/email from the configured source
3. Builds `recipients` array and sends via new API format
4. Falls back to legacy 2-signer flow if no workflow configured

Source resolution: `config:key` → dcfg_configs, `contract:field` → contract record, `customer:field` → customer record.

### Workflows Seeded on Prod
6 workflow configs created in `dcfg_configs`:

| Key | Document Type | Steps |
|-----|--------------|:-----:|
| `dcfg_docusign_workflow_100000000` | WO/BWO (TPA) | 6 |
| `dcfg_docusign_workflow_100000001` | Amendment | 6 |
| `dcfg_docusign_workflow_100000002` | VA (TPA) | 6 |
| `dcfg_docusign_workflow_100000005` | VA (Direct) | 4 |
| `dcfg_docusign_workflow_100000006` | WO (Direct) | 4 |
| `dcfg_docusign_workflow_100000007` | Amendment (Direct) | 4 |

**TPA 6-step flow** (maps to the 8-step business process):
1. Financial Review (Tyler) — approver, routing 1
2. Vendor Signs — signer, routing 2, `\Vendor_Signature\`
3. President Approval (Bill) — approver, routing 3
4. Customer Signs — signer, routing 4, `\Customer_Signature\`
5. Filing Copy (Decades) — cc, routing 5
6. Customer AP Copy — cc, routing 5

Step 1 (Sender/Preparer) and Step 7 (SharePoint storage) are system-handled, not in the workflow config.

---

## Code Review Phase 1 — Bugs Fixed

Source: `docs/code-review-2026-05-18.md` (full review by 4 parallel agents).

### Fixed This Session

| Bug | File | Fix |
|-----|------|-----|
| Path encoding breaks Graph API | `sharepointUpload.js:179` | `encodeURIComponent(path)` → segment-by-segment |
| KPI queries include soft-deleted records | `portalApi.js:992-994` | Added `dcfg_active_flag eq true` to 3 functions |
| Hardcoded Prod URL fallback | `inspectionSync.js:244` | Removed fallback, fail explicitly |
| Customer name in code | `SigningWorkflowEditor.jsx` | "Bancroft" → "TPA", "Decades" → "Direct" |
| Wrong safety delete key | `docusignSend.js:397` | `file_base64` → `fileBase64` (linter fix) |

### False Positives from Review (Already Correct)
- Admin.jsx toast scope — `useToast()` at line 126, in scope at line 156
- CustomerDetail.jsx OnboardingTab toast — `useToast()` at line 355, in scope
- NavPanel.jsx `isAdmin` — already uses `isAdmin()` with parentheses
- `fetchAmendments` filter — already `100000001`

### Remaining from Code Review (Phase 2-5)
See `docs/code-review-2026-05-18.md` sections 3-9 for:
- Dead code deletion: `_archive/` (4 files), root JSX (8 files), orphan spa/ files (12), sub-app portalApi copies (3)
- ~70 CR-2026-04-09 comment prefixes to strip
- Customer names in 4 more files (CustomerDetail LOGO_MAP, autoMapper, inspectionSync, sharepointUpload)
- Auth code dedup across 4 Azure Function files
- `var` → `const/let` in inspectionSync + 3 screen files
- ~130 PS1 scripts to archive

---

## Template Tag Reference — Rewritten

`template-tags.js` + `template-tags.html` completely rewritten to match actual yellow tags in production templates.

**Before:** 40 reference tags not in any template, 36 template tags not on reference page.
**After:** Every tag on the page matches actual yellow text. "Used in" line shows which templates use each tag. Retired section removed.

Deployed to Stage + Prod.

---

## Template Yellow Tag Fixes

7 templates prepared in `Templates/for-reupload/` with yellow tag corrections:

| Template | Changes |
|----------|---------|
| Blanket Work Order | Added `Contract Fee` tag (replaces "per approved proposals" text) |
| Decades Work Order | Added `Contract Fee` tag, cleaned broken anchor + trailing underscores |
| Decades Vendor Agreement | Added `Decades Printed Name` + `Decades Title` (replaced hardcoded "William Bamford" / "President") |
| Work Order Amendment | Added `Work Order Fee` yellow highlight |
| ExhA-Auto, ExhA-Var | Cleaned empty yellow runs |
| All 7 | Removed yellow from empty/whitespace runs, fixed stray backslash highlights |

**Templates NOT yet uploaded to Dataverse.** User will review formatting in Word, then re-upload. Review page at `scratch/template-review.html`.

---

## UpKeep MCP — Built for Claude Desktop/Teams

Read-only MCP server at `tools/upkeep-mcp/server.py`. 8 tools across 2 UpKeep accounts:

| Tool | Description |
|------|-------------|
| `list_work_orders` | Query WOs with filters (status, category, location, date) |
| `get_work_order` | Full details for a single WO |
| `list_locations` | All locations in an account |
| `get_location` | Full details for a single location |
| `list_users` | All technicians and admins |
| `list_assets` | Equipment/assets by location |
| `get_wo_counts_by_status` | Dashboard summary by status |
| `list_preventive_maintenance` | Recurring PM schedules |

**Accounts:** `bancroft` (single customer) and `multisite` (PennReach, J-ADD, Arc Mercer, PCDI, Newgrange).

**Installer:** `tools/upkeep-mcp/install.ps1` — one-click setup for team members. Prompts for credentials at install time (not stored in script). Copies server.py to `%LOCALAPPDATA%\dcfg-upkeep-mcp\`, adds to Claude Desktop config, tests auth.

**Install email template:** `scratch/upkeep-mcp-install-email.html` — ready to send to team.

Both accounts validated — Bancroft and Multi-site auth + WO queries confirmed working.

---

## Security — Azure Function Key Rotated

- Old key (`nn-eCIr...`) rotated via `az functionapp keys set`
- `dcfg_docusign_function_url` updated on Prod with new key
- `nora/nora-monitor-prod.ps1` changed to read key from `$env:DCFG_AZURE_FN_KEY` or fetch via `az CLI` at runtime — no hardcoded secrets in source
- Old key is permanently invalid

---

## Session Journaling Hook — Configured

PostToolUse hook added to `.claude/settings.local.json`. Fires after every Bash command and auto-logs to `scratch/session-journal.md`:

| Tag | Triggers on |
|-----|------------|
| `DEPLOY` | `pac pages upload` or `func azure functionapp publish` |
| `COMMIT` | `git commit` |
| `PUSH` | `git push` |
| `DATAVERSE` | `Invoke-RestMethod` with Patch/Post |
| `AUTH` | `pac auth select` |
| `AZURE` | `az functionapp` commands |

Requires session restart to activate. Memory rule saved at `feedback_realtime_memory_logging.md`.

---

## Deploys This Session

| Deploy | Environment | Duration | What |
|--------|-------------|----------|------|
| 1 | Stage | 608s | Tag reference + workflow editor |
| 2 | Prod | 788s | Tag reference + workflow editor |
| 3 | Azure Function | 146s | Dynamic recipients + path fix + URL fallback |
| 4 | Stage | 681s | Code review Phase 1 fixes |
| 5 | Prod | 737s | Code review Phase 1 fixes |
| 6 | Azure Function | 146s | Code review fixes (path encoding, URL fallback) |

## Dataverse Changes

| What | Environment |
|------|-------------|
| 6 `dcfg_docusign_workflow_*` config rows created | Prod |
| 6 DocuSign env vars updated (new dev account) | Azure Function App |
| `dcfg_docusign_function_url` updated with rotated key | Prod |
| Azure Function default key rotated | Azure Function App |

## Git

| Repo | Commit | Branch |
|------|--------|--------|
| dcfg-shell (SPA) | `9cc871e` | `main` |
| DMS (root) | `e623c97` | `code-review-2026-04-09` |
| Key rotation | `d2b4058` | `code-review-2026-04-09` |
| Handoff + code review fixes | `08784cc` | `code-review-2026-04-09` |
| Earlier commit | `8f6e482` | `code-review-2026-04-09` (template fixes, azure functions, docs) |

## Open Items

1. **Upload corrected templates to Dataverse** — 7 templates in `Templates/for-reupload/` ready after user reviews formatting in Word.
2. **Code review Phase 2-5** — Dead code deletion, comment cleanup, customer names, auth dedup. See `docs/code-review-2026-05-18.md`.
3. **DocuSign production migration** — Current config points to `demo.docusign.net`. When ready for production, update 2 env vars: `DOCUSIGN_BASE_URL` → `https://na4.docusign.net/restapi`, `DOCUSIGN_OAUTH_BASE` → `https://account.docusign.com`.
4. **Phase 3-4 field alignment** — MSA columns, VA composer wiring, address formatting. Per `docs/superpowers/plans/2026-05-15-docgen-field-alignment.md`.
5. **Distribute UpKeep MCP to team** — Send `scratch/upkeep-mcp-install-email.html` with `install.ps1` + `server.py` attached. Provide credentials separately.
