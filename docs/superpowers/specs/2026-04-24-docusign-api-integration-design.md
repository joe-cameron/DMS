# DocuSign API Integration — SendQueue

**Date:** 2026-04-24
**Status:** Approved
**Branch:** TBD

## Overview

Add a "Send via DocuSign" button to each row in the SendQueue grid (both Sales and Operations tabs). This is an **alternative** to the existing manual workflow — not a replacement. The operator chooses which path to use per row.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| API call location | Azure Function | Already have infra (html-to-pdf app). SPA can't hold credentials. Synchronous response. |
| OAuth grant | JWT Grant | Server-to-server, no per-user token management. Single service account sends all envelopes. |
| UX pattern | Confirmation modal | Lets operator verify/edit signer emails + names and set signing order before sending. Catches bad data. |
| Signing order | Operator chooses per envelope | Dropdown in modal: Parallel or Sequential (A then B). Different doc types may need different flows. |
| Completion tracking | Manual (Phase 1) | Operator still uses CompletionQueue to mark complete/void/declined. Webhooks deferred to Phase 2. |
| Config storage | Secrets in Azure env vars only. SPA config (function URL, subject/message templates) in dcfg_configs. No duplication. |
| Function auth from SPA | Function key embedded in URL (same pattern as `dcfg_upload_function_url`). Accepted risk: any authenticated portal user could extract the key from network traffic. The function only performs DocuSign sends — blast radius is limited. |
| Document transfer | Azure Function downloads from SharePoint via Graph API using existing `SP_*` env vars (same credentials as `sharepoint-upload`). SPA passes the SharePoint URL only — no base64 payload. |
| Duplicate-send protection | Phase 1: client-side busy state + button disable. Operator is trained to check DocuSign before retrying a failed send. Phase 2: server-side idempotency check via queueId. |

## Architecture

```
SPA (SendQueue.jsx)
  |
  | POST {dcfg_docusign_function_url} (includes ?code= function key)
  | Body: { documentUrl, signerA, signerB, signingOrder, message, queueId, documentName }
  v
Azure Function (docusign-send)
  |
  |-- CORS: OPTIONS preflight + Access-Control-Allow-Origin for portal domains
  |-- JWT Grant --> DocuSign OAuth (DOCUSIGN_OAUTH_BASE)
  |-- Graph API --> SharePoint: download document bytes using SP_* credentials
  |-- POST /v2.1/accounts/{id}/envelopes --> DocuSign REST API (DOCUSIGN_BASE_URL)
  |
  v
Returns { envelopeId, status: "sent" }
  |
  v
SPA writes dcfg_docusign_envelope_id to queue row, advances status to Sent
```

## Azure Function Endpoint

```
POST /api/docusign-send

Request Body:
{
  documentUrl: string,              // SharePoint full URL (function downloads via Graph API)
  documentName: string,             // Display name for the envelope document
  signerA: { email: string, name: string },
  signerB: { email: string, name: string },
  signingOrder: "parallel" | "sequential",
  message: string,                  // optional custom message to signers
  queueId: string                   // for audit logging
}

Response (200):
{
  envelopeId: string,
  status: "sent"
}

Error (4xx/5xx):
{
  error: string,
  detail: string
}
```

### CORS Handling

The function registers `['POST', 'OPTIONS']` methods (matching `sharepoint-upload` pattern):

- **OPTIONS preflight:** returns 204 with `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods: POST, OPTIONS`, `Access-Control-Allow-Headers: Content-Type, x-functions-key`, `Access-Control-Max-Age: 86400`
- **POST responses:** include `Access-Control-Allow-Origin` header
- **Allowed origins:** `*` for Phase 1 (matching existing `sharepoint-upload`). Phase 2: restrict to known portal domains (`dmms1.powerappsportals.com`, `dcfg.powerappsportals.com`, etc.)

### Function Internals

1. CORS preflight check (OPTIONS → 204)
2. Parse request body, validate required fields
3. Read all config from Azure env vars (no Dataverse reads)
4. **JWT Grant:** Build JWT assertion using `DOCUSIGN_INTEGRATION_KEY` + `DOCUSIGN_RSA_PRIVATE_KEY` + `DOCUSIGN_IMPERSONATED_USER_ID`. POST to `{DOCUSIGN_OAUTH_BASE}/oauth/token`. Cache access token in-memory; cold starts re-authenticate. No shared/persistent token store needed at current volume.
5. **Download document from SharePoint:** Authenticate to Graph API using `SP_CLIENT_ID` / `SP_CLIENT_SECRET` / `SP_TENANT_ID` (same credentials already in the function app for `sharepoint-upload`). Convert the SharePoint URL to a Graph API driveItem path, GET the file content as bytes.
6. **Log on failure:** Log full request body + DocuSign API response on any non-200 outcome (per project verbose-logging default).
7. **Create envelope:** `POST /v2.1/accounts/{DOCUSIGN_ACCOUNT_ID}/envelopes` to `{DOCUSIGN_BASE_URL}`:
   - Attach document as base64 (from step 5)
   - Set recipients with routing order (`1`/`1` for parallel, `1`/`2` for sequential)
   - Set email subject from `documentName` (formatted: `Signature Required — {documentName}`)
   - Set email body from `message` param or default
   - Envelope status: `"sent"` (sends immediately)
8. Return `{ envelopeId, status: "sent" }` with CORS headers

**URL normalization:** The SPA must normalize `meta.docUrl` to a full URL before passing to the function (using `getEnvVar('dcfg_sp_site_url')` prepend for relative paths starting with `/`, matching the existing `handleWordDesktop` pattern). The function should validate the URL belongs to the expected SharePoint site before downloading.

### Environment Variables (Azure Function App)

| Variable | Description | Example |
|----------|-------------|---------|
| `DOCUSIGN_INTEGRATION_KEY` | OAuth integration key (client ID) | GUID |
| `DOCUSIGN_RSA_PRIVATE_KEY` | PEM-encoded RSA private key for JWT | `-----BEGIN RSA PRIVATE KEY-----...` |
| `DOCUSIGN_IMPERSONATED_USER_ID` | GUID of the DocuSign user to impersonate | GUID |
| `DOCUSIGN_ACCOUNT_ID` | DocuSign account ID | GUID |
| `DOCUSIGN_BASE_URL` | API base URL | `https://demo.docusign.net/restapi` (sandbox) |
| `DOCUSIGN_OAUTH_BASE` | OAuth token endpoint base | `https://account-d.docusign.com` (sandbox) |
| `SP_CLIENT_ID` | Already exists — Graph API app reg | (existing) |
| `SP_CLIENT_SECRET` | Already exists — Graph API secret | (existing) |
| `SP_TENANT_ID` | Already exists — tenant ID | (existing) |

**Sandbox to Production transition:** Change `DOCUSIGN_BASE_URL` to `https://na4.docusign.net/restapi` (or regional equivalent) and `DOCUSIGN_OAUTH_BASE` to `https://account.docusign.com`. Update `DOCUSIGN_ACCOUNT_ID` to the production account. No code changes required.

### dcfg_configs Rows

| Key | Value | Purpose |
|-----|-------|---------|
| `dcfg_docusign_function_url` | Azure Function URL with `?code=` key | SPA calls this (same pattern as `dcfg_upload_function_url`) |
| `dcfg_docusign_subject_template` | `Signature Required — {docName}` | Default envelope email subject |
| `dcfg_docusign_message_template` | `Please review and sign the attached document.` | Default message body pre-filled in modal |

No `dcfg_docusign_account_id` or `dcfg_docusign_base_url` — those live exclusively in Azure env vars since only the function consumes them.

## SPA Changes

### New file: DocuSignModal.jsx

Extracted to its own file (SendQueue.jsx is already ~1200 lines). Located at `screens/DocuSignModal.jsx`.

**Modal contents:**
- Document name + type badge (read-only)
- Customer / Vendor names (read-only context)
- **Signer A:** name input + email input (pre-filled from `extractMeta`, editable)
- **Signer B:** name input + email input (pre-filled, editable)
- **Signing Order:** dropdown — `Parallel` / `Sequential (A then B)`
- **Message to signers:** textarea (pre-filled from `dcfg_docusign_message_template` config)
- **Validation:** both signer emails required, basic email format check. Names required (DocuSign requires them).
- Send button / Cancel
- Loading spinner + disabled state while Azure Function executes

### SendQueue.jsx changes

**extractMeta() update:** Add `signerAName` and `signerBName` fields (individual person names, not entity names):
- Contracts: `signerAName` = `c.dcfg_signer_printed || c.dcfg_contractor_legal_name` (fallback), `signerBName` = `c.dcfg_owner_contact`
- MSAs: `signerAName` = `vend.dcfg_legal_name || vend.dcfg_display_name`, `signerBName` = `cust.dcfg_primary_contact_name || cust.dcfg_name` (fallback)

**fetchSendQueue $select updates required:**
- Contract expand: add `dcfg_signer_printed` to the `$select` clause
- MSA > customer expand: add `dcfg_primary_contact_name` to the `$select` clause

**New button per queue row:** "Send DocuSign" button in the Actions column. Styled with DocuSign dark background (`#1a1a2e`), matching the existing DocuSign button. The existing external-link DocuSign button stays as-is for manual fallback.

**New state:** `docuSignModal` — holds the queue row + extracted meta when modal is open. `null` when closed.

**On successful send:**
1. Write `dcfg_docusign_envelope_id` to queue row via `updateSendQueueStatus`
2. Advance queue status to Sent (same as existing Mark Sent)
3. Write audit log entry (actionType: `AuditActionType.Sent`, newValue includes envelope ID + "via DocuSign API")
4. Toast: "Sent via DocuSign — envelope {shortId}"
5. Remove row from pending queue

**On error:**
- Toast with error message from Azure Function response
- Row stays in queue, no status change
- No fake success (per CR-2026-04-09-0274)

### portalApi.js

New export:
```js
export async function sendViaDocuSign(params) {
  const url = getEnvVar('dcfg_docusign_function_url');
  if (!url) throw new Error('DocuSign function URL not configured');
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || err.detail || 'DocuSign send failed');
  }
  return res.json();
}
```

### Test IDs

| Element | data-testid |
|---------|-------------|
| DocuSign button per row | `btn-docusign-send` |
| Modal: Signer A name | `docusign-signer-a-name` |
| Modal: Signer A email | `docusign-signer-a-email` |
| Modal: Signer B name | `docusign-signer-b-name` |
| Modal: Signer B email | `docusign-signer-b-email` |
| Modal: Signing order dropdown | `docusign-signing-order` |
| Modal: Message textarea | `docusign-message` |
| Modal: Send button | `btn-docusign-modal-send` |
| Modal: Cancel button | `btn-docusign-modal-cancel` |
| Modal: Loading indicator | `docusign-loading` |

## What Stays the Same

- Hold, Return, Approve/Mark Sent buttons unchanged
- Envelope ID text input stays (manual paste fallback)
- External DocuSign link button stays (operator can still open DocuSign manually)
- CompletionQueue (UI29) unchanged
- All existing audit logging patterns preserved
- WO number assignment unchanged

## What Changes (Summary)

1. New "Send DocuSign" button in each queue row's action bar
2. New `DocuSignModal.jsx` component
3. `extractMeta()` updated to include signer names
4. New `sendViaDocuSign()` in portalApi.js
5. New Azure Function endpoint `/api/docusign-send` with CORS handling
6. New dcfg_configs rows (function URL, subject/message templates)
7. New Azure Function env vars for DocuSign secrets + OAuth

## Phase 2 (Deferred)

- DocuSign Connect webhooks for automatic completion tracking
- Envelope status polling via Nora
- Void/decline from SPA via DocuSign API
- Multi-document envelopes (package sends)
- Server-side idempotency check (queueId-based duplicate prevention)
- CORS origin restriction to known portal domains
- Sandbox-to-production URL cutover

## Visual Validation

Before/after HTML mockups required before any SPA deploy. Mockups must show:
1. Current queue row action bar vs. new action bar with DocuSign button
2. DocuSign confirmation modal (with signer name + email fields, signing order dropdown, message textarea)
