# DocuSign API Integration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Send via DocuSign" button to SendQueue rows that creates and sends a DocuSign envelope via an Azure Function, as an alternative to the existing manual workflow.

**Architecture:** Azure Function (`docusign-send`) handles JWT auth, SharePoint doc download, and DocuSign envelope creation. SPA gets a new `DocuSignModal.jsx` component and `sendViaDocuSign()` API function. Config splits: secrets in Azure env vars, runtime URLs/templates in `dcfg_configs`.

**Tech Stack:** Node.js Azure Function (@azure/functions v4), DocuSign eSignature REST API v2.1, Microsoft Graph API, React 16 (Power Pages SPA), `jsonwebtoken` npm package for JWT signing.

**Spec:** `docs/superpowers/specs/2026-04-24-docusign-api-integration-design.md`

---

## Chunk 1: Azure Function — docusign-send

### Task 1: Add jsonwebtoken dependency

**Files:**
- Modify: `azure-functions/html-to-pdf/package.json`

- [ ] **Step 1: Add jsonwebtoken to dependencies**

```json
"jsonwebtoken": "^9.0.0"
```

Add to the `dependencies` object in `package.json` alongside existing deps.

- [ ] **Step 2: Install**

Run: `cd C:\dcfg\azure-functions\html-to-pdf && npm install`
Expected: `added 1 package` (jsonwebtoken)

- [ ] **Step 3: Commit**

```bash
git add azure-functions/html-to-pdf/package.json azure-functions/html-to-pdf/package-lock.json
git commit -m "chore: add jsonwebtoken dep for DocuSign JWT grant"
```

---

### Task 2: Create the docusign-send Azure Function

**Files:**
- Create: `azure-functions/html-to-pdf/src/functions/docusignSend.js`

**Reference files:**
- `azure-functions/html-to-pdf/src/functions/sharepointUpload.js` — CORS pattern (lines 326-343), Graph token acquisition (lines 58-77), site/drive resolution (lines 118-140)

- [ ] **Step 1: Create the function file**

```js
/**
 * docusignSend.js — DocuSign envelope creation endpoint
 *
 * Receives a SharePoint document URL + signer info from the SPA,
 * downloads the document via Graph API, creates a DocuSign envelope
 * via JWT grant, and returns the envelope ID.
 *
 * Env vars required:
 *   DOCUSIGN_INTEGRATION_KEY     — OAuth client ID
 *   DOCUSIGN_RSA_PRIVATE_KEY     — PEM RSA private key for JWT
 *   DOCUSIGN_IMPERSONATED_USER_ID — DocuSign user GUID to impersonate
 *   DOCUSIGN_ACCOUNT_ID          — DocuSign account ID
 *   DOCUSIGN_BASE_URL            — e.g., https://demo.docusign.net/restapi
 *   DOCUSIGN_OAUTH_BASE          — e.g., https://account-d.docusign.com
 *   SP_TENANT_ID, SP_CLIENT_ID, SP_CLIENT_SECRET — Graph API (existing)
 *   SP_SITE_HOST, SP_SITE_PATH                   — SharePoint site (existing)
 *
 * POST /api/docusign-send
 * Body (JSON):
 *   {
 *     "documentUrl":   "https://...sharepoint.com/.../file.docx",
 *     "documentName":  "WO-2026-001",
 *     "signerA":       { "email": "a@example.com", "name": "Alice Smith" },
 *     "signerB":       { "email": "b@example.com", "name": "Bob Jones" },
 *     "signingOrder":  "parallel" | "sequential",
 *     "message":       "Please review and sign.",
 *     "queueId":       "guid"
 *   }
 *
 * Response: { "envelopeId": "...", "status": "sent" }
 */
const { app } = require('@azure/functions');
const jwt = require('jsonwebtoken');

// ─── In-memory token cache (resets on cold start) ───
let cachedToken = null;
let tokenExpiresAt = 0;

// ─── CORS headers ───
const corsHeaders = { 'Access-Control-Allow-Origin': '*' };

function corsResponse(status, body) {
  return {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

function errorResponse(status, error, detail, context) {
  context.log(`[docusign-send] ERROR ${status}: ${error} — ${detail}`);
  return corsResponse(status, { error, detail });
}

// ─── DocuSign JWT Grant ───
async function getDocuSignToken(context) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && tokenExpiresAt > now + 60) return cachedToken;

  const integrationKey = process.env.DOCUSIGN_INTEGRATION_KEY;
  const privateKey     = process.env.DOCUSIGN_RSA_PRIVATE_KEY;
  const userId         = process.env.DOCUSIGN_IMPERSONATED_USER_ID;
  const oauthBase      = process.env.DOCUSIGN_OAUTH_BASE || 'https://account-d.docusign.com';

  if (!integrationKey || !privateKey || !userId) {
    throw new Error('Missing DOCUSIGN env vars (INTEGRATION_KEY, RSA_PRIVATE_KEY, or IMPERSONATED_USER_ID)');
  }

  // Build JWT assertion
  const payload = {
    iss: integrationKey,
    sub: userId,
    aud: oauthBase.replace('https://', ''),
    iat: now,
    exp: now + 3600,
    scope: 'signature impersonation',
  };

  // Handle escaped newlines in env var (Azure stores \\n as literal)
  const key = privateKey.replace(/\\n/g, '\n');
  const assertion = jwt.sign(payload, key, { algorithm: 'RS256' });

  // Exchange for access token
  const resp = await fetch(`${oauthBase}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });

  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    context.log(`[docusign-send] JWT token request failed: ${resp.status} ${err}`);
    throw new Error(`DocuSign JWT auth failed: ${resp.status}`);
  }

  const data = await resp.json();
  cachedToken = data.access_token;
  tokenExpiresAt = now + (data.expires_in || 3600);
  context.log(`[docusign-send] JWT token acquired, expires in ${data.expires_in}s`);
  return cachedToken;
}

// ─── Graph API: get token (reuses pattern from sharepointUpload.js) ───
async function getGraphToken() {
  const tokenUrl = `https://login.microsoftonline.com/${process.env.SP_TENANT_ID}/oauth2/v2.0/token`;
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: process.env.SP_CLIENT_ID,
    client_secret: process.env.SP_CLIENT_SECRET,
    scope: 'https://graph.microsoft.com/.default',
  });
  const resp = await fetch(tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`Graph token failed: ${resp.status} ${err.slice(0, 200)}`);
  }
  const data = await resp.json();
  return data.access_token;
}

// ─── Download document from SharePoint via Graph API ───
async function downloadFromSharePoint(documentUrl, context) {
  const siteHost = process.env.SP_SITE_HOST || 'decadesconstructiongroup.sharepoint.com';
  const sitePath = process.env.SP_SITE_PATH || '/sites/DCFGContractingSuite';

  // Validate URL belongs to expected SharePoint site
  if (!documentUrl.includes(siteHost)) {
    throw new Error(`Document URL does not belong to expected SharePoint site (${siteHost})`);
  }

  const graphToken = await getGraphToken();

  // Resolve site ID
  const siteResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${siteHost}:${sitePath}?$select=id`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!siteResp.ok) throw new Error(`Site resolve failed: ${siteResp.status}`);
  const site = await siteResp.json();

  // Extract relative path from the full URL
  // URL format: https://host/sites/SiteName/LibraryName/folder/file.docx
  const urlObj = new URL(documentUrl);
  const fullPath = decodeURIComponent(urlObj.pathname);
  // Strip /sites/SiteName/ prefix to get library-relative path
  const sitePrefix = sitePath.endsWith('/') ? sitePath : sitePath + '/';
  const idx = fullPath.indexOf(sitePrefix);
  if (idx === -1) throw new Error(`Cannot extract relative path from URL: ${documentUrl}`);
  const relativePath = fullPath.substring(idx + sitePrefix.length);

  // Split into library name and item path
  const slashIdx = relativePath.indexOf('/');
  if (slashIdx === -1) throw new Error(`Cannot parse library/item from path: ${relativePath}`);
  const libraryName = relativePath.substring(0, slashIdx);
  const itemPath = relativePath.substring(slashIdx + 1);

  // Find the drive for this library
  const drivesResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${site.id}/drives?$select=id,name`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!drivesResp.ok) throw new Error(`Drives list failed: ${drivesResp.status}`);
  const drives = await drivesResp.json();
  const drive = drives.value.find(d => d.name === libraryName) || drives.value[0];
  if (!drive) throw new Error(`No drive found for library: ${libraryName}`);

  // Download file content
  context.log(`[docusign-send] Downloading: drive=${drive.name}, path=${itemPath}`);
  const contentResp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${drive.id}/root:/${encodeURIComponent(itemPath)}:/content`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!contentResp.ok) {
    const err = await contentResp.text().catch(() => '');
    throw new Error(`File download failed: ${contentResp.status} ${err.slice(0, 200)}`);
  }

  const arrayBuffer = await contentResp.arrayBuffer();
  context.log(`[docusign-send] Downloaded ${arrayBuffer.byteLength} bytes`);
  return Buffer.from(arrayBuffer);
}

// ─── Create DocuSign envelope ───
async function createEnvelope(token, documentBuffer, body, context) {
  const accountId = process.env.DOCUSIGN_ACCOUNT_ID;
  const baseUrl   = process.env.DOCUSIGN_BASE_URL || 'https://demo.docusign.net/restapi';

  if (!accountId) throw new Error('Missing DOCUSIGN_ACCOUNT_ID env var');

  const isSequential = body.signingOrder === 'sequential';
  const subject = `Signature Required — ${body.documentName || 'Document'}`;

  const envelope = {
    emailSubject: subject,
    emailBlurb: body.message || 'Please review and sign the attached document.',
    status: 'sent',
    documents: [
      {
        documentId: '1',
        name: body.documentName || 'Document',
        fileExtension: 'docx',
        documentBase64: documentBuffer.toString('base64'),
      },
    ],
    recipients: {
      signers: [
        {
          email: body.signerA.email,
          name: body.signerA.name,
          recipientId: '1',
          routingOrder: '1',
          tabs: {
            signHereTabs: [
              { documentId: '1', pageNumber: '1', xPosition: '100', yPosition: '700' },
            ],
          },
        },
        {
          email: body.signerB.email,
          name: body.signerB.name,
          recipientId: '2',
          routingOrder: isSequential ? '2' : '1',
          tabs: {
            signHereTabs: [
              { documentId: '1', pageNumber: '1', xPosition: '300', yPosition: '700' },
            ],
          },
        },
      ],
    },
  };

  const url = `${baseUrl}/v2.1/accounts/${accountId}/envelopes`;
  context.log(`[docusign-send] Creating envelope: ${url}`);

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(envelope),
  });

  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    context.log(`[docusign-send] Envelope creation failed: ${resp.status} ${err}`);
    context.log(`[docusign-send] Request body (excluding doc base64): ${JSON.stringify({
      ...body,
      documentBuffer: `[${documentBuffer.byteLength} bytes]`,
    })}`);
    throw new Error(`DocuSign envelope creation failed: ${resp.status} — ${err.slice(0, 300)}`);
  }

  const result = await resp.json();
  context.log(`[docusign-send] Envelope created: ${result.envelopeId}, status: ${result.status}`);
  return result;
}

// ═══════════════════════════════════════════════════════════════
// Main handler
// ═══════════════════════════════════════════════════════════════
app.http('docusign-send', {
  methods: ['POST', 'OPTIONS'],
  authLevel: 'function',
  handler: async (request, context) => {
    // CORS preflight
    if (request.method === 'OPTIONS') {
      return {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, x-functions-key',
          'Access-Control-Max-Age': '86400',
        },
      };
    }

    const t0 = Date.now();

    try {
      const body = await request.json();

      // ── Validate required fields ──
      const missing = [];
      if (!body.documentUrl) missing.push('documentUrl');
      if (!body.signerA?.email) missing.push('signerA.email');
      if (!body.signerA?.name) missing.push('signerA.name');
      if (!body.signerB?.email) missing.push('signerB.email');
      if (!body.signerB?.name) missing.push('signerB.name');
      if (missing.length > 0) {
        return errorResponse(400, 'Missing required fields', missing.join(', '), context);
      }

      // ── Step 1: DocuSign JWT auth ──
      context.log(`[docusign-send] Starting for queueId=${body.queueId || 'none'}`);
      const dsToken = await getDocuSignToken(context);

      // ── Step 2: Download document from SharePoint ──
      const docBuffer = await downloadFromSharePoint(body.documentUrl, context);

      // ── Step 3: Create and send envelope ──
      const result = await createEnvelope(dsToken, docBuffer, body, context);

      context.log(`[docusign-send] Complete in ${Date.now() - t0}ms`);
      return corsResponse(200, {
        envelopeId: result.envelopeId,
        status: result.status || 'sent',
      });

    } catch (err) {
      context.log(`[docusign-send] FAILED after ${Date.now() - t0}ms: ${err.message}`);
      context.log(`[docusign-send] Stack: ${err.stack}`);
      return errorResponse(500, 'DocuSign send failed', err.message, context);
    }
  },
});
```

- [ ] **Step 2: Verify function loads locally**

Run: `cd C:\dcfg\azure-functions\html-to-pdf && npx func start --javascript`
Expected: Console shows `docusign-send: [POST,OPTIONS] http://localhost:7071/api/docusign-send` alongside existing functions.
Stop after verifying (Ctrl+C).

- [ ] **Step 3: Commit**

```bash
git add azure-functions/html-to-pdf/src/functions/docusignSend.js
git commit -m "feat: add docusign-send Azure Function endpoint"
```

---

### Task 3: Create Azure Function test harness

**Files:**
- Create: `azure-functions/html-to-pdf/test/test-docusign-send.js`

**Note:** This is an integration test that validates the request/response contract. It does NOT call real DocuSign — it tests validation, error paths, and response shape. Real E2E testing happens after env vars are configured in Azure.

- [ ] **Step 1: Write the test file**

```js
/**
 * test-docusign-send.js — Contract tests for docusign-send function
 *
 * Tests validation logic and response shapes without calling real APIs.
 * Run: node test/test-docusign-send.js
 */

const BASE = process.env.FUNC_URL || 'http://localhost:7071/api/docusign-send';

async function post(body) {
  const resp = await fetch(BASE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: resp.status, data: await resp.json() };
}

async function runTests() {
  let pass = 0, fail = 0;

  function assert(name, condition) {
    if (condition) { pass++; console.log(`  PASS: ${name}`); }
    else { fail++; console.log(`  FAIL: ${name}`); }
  }

  console.log('\n=== docusign-send contract tests ===\n');

  // Test 1: Missing fields returns 400
  console.log('Test 1: Missing required fields');
  const r1 = await post({});
  assert('status is 400', r1.status === 400);
  assert('error field present', !!r1.data.error);
  assert('detail lists missing fields', r1.data.detail.includes('documentUrl'));

  // Test 2: Missing signer name returns 400
  console.log('\nTest 2: Missing signer name');
  const r2 = await post({
    documentUrl: 'https://example.sharepoint.com/sites/Test/Lib/file.docx',
    signerA: { email: 'a@test.com' },
    signerB: { email: 'b@test.com', name: 'Bob' },
  });
  assert('status is 400', r2.status === 400);
  assert('detail mentions signerA.name', r2.data.detail.includes('signerA.name'));

  // Test 3: CORS preflight returns 204
  console.log('\nTest 3: OPTIONS preflight');
  const r3 = await fetch(BASE, { method: 'OPTIONS' });
  assert('status is 204', r3.status === 204);
  assert('CORS origin header present', !!r3.headers.get('access-control-allow-origin'));
  assert('CORS methods header present', !!r3.headers.get('access-control-allow-methods'));

  // Test 4: Valid body but missing env vars returns 500 with clear error
  // (only works if DOCUSIGN_* env vars are NOT set)
  console.log('\nTest 4: Valid body, missing env vars');
  const r4 = await post({
    documentUrl: 'https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite/DCFG_Outputs/test.docx',
    documentName: 'Test Doc',
    signerA: { email: 'a@test.com', name: 'Alice' },
    signerB: { email: 'b@test.com', name: 'Bob' },
    signingOrder: 'parallel',
    queueId: 'test-123',
  });
  assert('status is 500', r4.status === 500);
  assert('error mentions DocuSign or env', r4.data.error === 'DocuSign send failed');

  console.log(`\n=== Results: ${pass} passed, ${fail} failed ===\n`);
  process.exit(fail > 0 ? 1 : 0);
}

runTests().catch(e => { console.error(e); process.exit(1); });
```

- [ ] **Step 2: Run tests against local function** (requires `func start` in another terminal)

Run: `cd C:\dcfg\azure-functions\html-to-pdf && node test/test-docusign-send.js`
Expected: 4 tests pass (validation + CORS + env-var-missing error path)

- [ ] **Step 3: Commit**

```bash
git add azure-functions/html-to-pdf/test/test-docusign-send.js
git commit -m "test: add docusign-send contract tests"
```

---

## Chunk 2: SPA Changes — portalApi + extractMeta + DocuSignModal + SendQueue wiring

### Task 4: Add sendViaDocuSign to portalApi.js

**Files:**
- Modify: `spa/dcfg-shell/src/portalApi.js`

**Note:** SPA is READ-ONLY per CLAUDE.md. This task requires explicit operator permission before editing.

- [ ] **Step 1: Get operator permission to edit SPA files**

Ask: "I need to edit `portalApi.js`, `SendQueue.jsx`, and create `DocuSignModal.jsx`. Permission to edit SPA?"

- [ ] **Step 2: Add sendViaDocuSign export after the existing updateSendQueueStatus function**

Insert after `updateSendQueueStatus` (around line 738):

```js
/**
 * Send a document for eSignature via DocuSign API (Azure Function proxy).
 * @param {object} params - { documentUrl, documentName, signerA: {email,name}, signerB: {email,name}, signingOrder, message, queueId }
 * @returns {Promise<{envelopeId: string, status: string}>}
 */
export async function sendViaDocuSign(params) {
  const url = getEnvVar('dcfg_docusign_function_url');
  if (!url) throw new Error('DocuSign function URL not configured — add dcfg_docusign_function_url to dcfg_configs');
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

- [ ] **Step 3: Add dcfg_signer_printed to fetchSendQueue contract $select**

In `fetchSendQueue` (line ~693), inside the contract `$expand` `$select` clause, add `dcfg_signer_printed` after `dcfg_created_by_email`.

- [ ] **Step 4: Add dcfg_primary_contact_name to fetchSendQueue MSA customer $select**

In `fetchSendQueue` (line ~693), inside the MSA > `dcfg_customer_id` `$expand` `$select` clause, add `dcfg_primary_contact_name` after `dcfg_primary_contact_email`.

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-shell/src/portalApi.js
git commit -m "feat: add sendViaDocuSign API + expand signer fields in fetchSendQueue"
```

---

### Task 5: Update extractMeta in SendQueue.jsx

**Files:**
- Modify: `spa/dcfg-shell/src/screens/SendQueue.jsx`

- [ ] **Step 1: Add signerAName and signerBName to the contract branch of extractMeta**

In `extractMeta` (around line 283), in the `if (q._dcfg_contract_id_value)` block, add after `createdBy`:

```js
signerAName: c.dcfg_signer_printed || c.dcfg_contractor_legal_name || '',
signerBName: c.dcfg_owner_contact || '',
```

- [ ] **Step 2: Add signerAName and signerBName to the MSA branch of extractMeta**

In the `if (q._dcfg_msa_id_value)` block, add after `createdBy`:

```js
signerAName: vend.dcfg_legal_name || vend.dcfg_display_name || '',
signerBName: cust.dcfg_primary_contact_name || cust.dcfg_name || '',
```

- [ ] **Step 3: Add signerAName/signerBName to the fallback return**

In the final return of `extractMeta`, add:

```js
signerAName: '', signerBName: '',
```

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-shell/src/screens/SendQueue.jsx
git commit -m "feat: add signer names to extractMeta for DocuSign modal"
```

---

### Task 6: Create DocuSignModal.jsx

**Files:**
- Create: `spa/dcfg-shell/src/screens/DocuSignModal.jsx`

- [ ] **Step 1: Create the modal component**

```jsx
/**
 * DocuSignModal.jsx — Confirmation modal for sending documents via DocuSign API.
 * Displays signer info (editable), signing order, and custom message.
 * Calls sendViaDocuSign() on confirm.
 */
import React, { useState, useMemo } from 'react';
import { sendViaDocuSign, getEnvVar, updateSendQueueStatus, writeAuditLog, SendQueueStatus, AuditActionType } from '../portalApi.js';

const NAVY    = '#1B2A4A';
const GREEN   = '#2d6a4f';
const DARK    = '#1a3a2a';
const BORDER  = '#e0ddd5';
const MUTED   = '#888';
const BODY    = "'IBM Plex Sans', sans-serif";
const HEAD    = "'Fraunces', Georgia, serif";
const MONO    = "'IBM Plex Mono', monospace";

const overlayStyle = { position:'fixed', inset:0, backgroundColor:'rgba(0,0,0,0.4)', display:'flex', alignItems:'center', justifyContent:'center', zIndex:2000 };
const inputStyle   = { border:`1px solid ${BORDER}`, borderRadius:6, padding:'8px 12px', fontSize:13, fontFamily:BODY, outline:'none', width:'100%', boxSizing:'border-box' };
const labelStyle   = { fontWeight:600, color:MUTED, fontSize:9, textTransform:'uppercase', display:'block', marginBottom:2, letterSpacing:0.5 };

function isValidEmail(e) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e); }

/**
 * @param {object} props
 * @param {object} props.queueRow — raw dcfg_send_queue row
 * @param {object} props.meta — output of extractMeta(queueRow)
 * @param {object} props.user — portal user { email, fullname }
 * @param {function} props.onClose — called on cancel or after successful send
 * @param {function} props.onSent — called with (queueId) after successful send so parent can remove the row
 * @param {function} props.toast — toast.show function
 */
export default function DocuSignModal({ queueRow, meta, user, onClose, onSent, toast }) {
  const defaultMessage = useMemo(() => getEnvVar('dcfg_docusign_message_template') || 'Please review and sign the attached document.', []);

  const [signerAName, setSignerAName]   = useState(meta.signerAName || '');
  const [signerAEmail, setSignerAEmail] = useState(meta.signerA || '');
  const [signerBName, setSignerBName]   = useState(meta.signerBName || '');
  const [signerBEmail, setSignerBEmail] = useState(meta.signerB || '');
  const [signingOrder, setSigningOrder] = useState('parallel');
  const [message, setMessage]           = useState(defaultMessage);
  const [sending, setSending]           = useState(false);

  const canSend = signerAName.trim() && isValidEmail(signerAEmail) &&
                  signerBName.trim() && isValidEmail(signerBEmail) && !sending;

  // Normalize document URL (prepend site URL for relative paths)
  function normalizeDocUrl(url) {
    if (!url) return '';
    if (url.startsWith('/')) {
      const siteUrl = getEnvVar('dcfg_sp_site_url') || 'https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite';
      return siteUrl + url;
    }
    return url;
  }

  async function handleSend() {
    if (!canSend) return;
    setSending(true);
    try {
      const docUrl = normalizeDocUrl(meta.docUrl);
      if (!docUrl) throw new Error('No document URL on this row');

      const result = await sendViaDocuSign({
        documentUrl: docUrl,
        documentName: meta.docName || 'Document',
        signerA: { email: signerAEmail.trim(), name: signerAName.trim() },
        signerB: { email: signerBEmail.trim(), name: signerBName.trim() },
        signingOrder,
        message: message.trim(),
        queueId: queueRow.dcfg_send_queueid,
      });

      // Update queue row: mark sent + store envelope ID
      await updateSendQueueStatus(queueRow.dcfg_send_queueid, {
        dcfg_queue_status: SendQueueStatus.Sent,
        dcfg_sent_date: new Date().toISOString(),
        dcfg_sent_by: user?.email || '',
        dcfg_docusign_envelope_id: result.envelopeId,
      });

      // Audit log
      writeAuditLog({
        targetTable: 'dcfg_send_queue',
        targetRecordId: queueRow.dcfg_send_queueid,
        actionType: AuditActionType.Sent,
        performedBy: user?.email,
        newValue: `Sent via DocuSign API (envelope: ${result.envelopeId})`,
        oldValue: 'Pending',
        relatedContractId: queueRow._dcfg_contract_id_value || null,
      }).catch(() => {});

      const shortId = result.envelopeId ? result.envelopeId.slice(0, 8) + '...' : '';
      toast.show('ok', `Sent via DocuSign — envelope ${shortId}`);
      onSent(queueRow.dcfg_send_queueid);
      onClose();
    } catch (err) {
      toast.show('err', `DocuSign send failed: ${err.message}`);
    }
    setSending(false);
  }

  // Type badge for display
  const tb = meta.docType != null
    ? { 100000000:{ bg:'#e3f2fd', color:'#1565c0', label:'Work Order' },
        100000001:{ bg:'#fff3e0', color:'#e65100', label:'Amendment' },
        100000002:{ bg:'#f3e5f5', color:'#7b1fa2', label:'Vendor Agreement' } }[meta.docType] || { bg:'#f5f5f0', color:'#666', label: meta.typeLabel }
    : { bg:'#e1f5fe', color:'#01579b', label: meta.typeLabel };

  return (
    <div style={overlayStyle} onClick={e => { if (e.target === e.currentTarget && !sending) onClose(); }}>
      <div style={{ background:'#fff', borderRadius:12, width:520, boxShadow:'0 8px 40px rgba(0,0,0,0.25)', overflow:'hidden' }}>
        {/* Header */}
        <div style={{ padding:'14px 18px', borderBottom:`1px solid ${BORDER}`, display:'flex', justifyContent:'space-between', alignItems:'center', background:'#1a1a2e' }}>
          <div style={{ display:'flex', alignItems:'center', gap:8 }}>
            <span style={{ fontSize:14, fontWeight:700, color:'#fff', fontFamily:HEAD }}>Send via DocuSign</span>
            <span style={{ fontSize:9, padding:'2px 8px', borderRadius:3, fontWeight:600, background:tb.bg, color:tb.color }}>{tb.label}</span>
          </div>
          <button data-testid="btn-docusign-modal-cancel" onClick={onClose} disabled={sending}
            style={{ background:'none', border:'none', fontSize:18, cursor:'pointer', color:'rgba(255,255,255,0.6)' }}>&times;</button>
        </div>

        {/* Context */}
        <div style={{ padding:'12px 18px', background:'#fafaf7', borderBottom:`1px solid ${BORDER}` }}>
          <div style={{ fontSize:13, fontWeight:700, color:DARK }}>{meta.docName}</div>
          <div style={{ fontSize:11, color:MUTED, marginTop:2 }}>
            {meta.customer}{meta.vendor ? ` — ${meta.vendor}` : ''}
          </div>
        </div>

        {/* Form */}
        <div style={{ padding:'14px 18px' }}>
          {/* Signer A */}
          <div style={{ marginBottom:12 }}>
            <label style={{ ...labelStyle, color:DARK }}>Signer A</label>
            <div style={{ display:'flex', gap:8 }}>
              <div style={{ flex:1 }}>
                <label style={labelStyle}>Name</label>
                <input data-testid="docusign-signer-a-name" value={signerAName} onChange={e => setSignerAName(e.target.value)}
                  placeholder="Full name" style={inputStyle} disabled={sending} />
              </div>
              <div style={{ flex:1 }}>
                <label style={labelStyle}>Email</label>
                <input data-testid="docusign-signer-a-email" value={signerAEmail} onChange={e => setSignerAEmail(e.target.value)}
                  placeholder="email@example.com" style={{ ...inputStyle, fontFamily:MONO, fontSize:11,
                    borderColor: signerAEmail && !isValidEmail(signerAEmail) ? '#c62828' : BORDER }} disabled={sending} />
              </div>
            </div>
          </div>

          {/* Signer B */}
          <div style={{ marginBottom:12 }}>
            <label style={{ ...labelStyle, color:DARK }}>Signer B</label>
            <div style={{ display:'flex', gap:8 }}>
              <div style={{ flex:1 }}>
                <label style={labelStyle}>Name</label>
                <input data-testid="docusign-signer-b-name" value={signerBName} onChange={e => setSignerBName(e.target.value)}
                  placeholder="Full name" style={inputStyle} disabled={sending} />
              </div>
              <div style={{ flex:1 }}>
                <label style={labelStyle}>Email</label>
                <input data-testid="docusign-signer-b-email" value={signerBEmail} onChange={e => setSignerBEmail(e.target.value)}
                  placeholder="email@example.com" style={{ ...inputStyle, fontFamily:MONO, fontSize:11,
                    borderColor: signerBEmail && !isValidEmail(signerBEmail) ? '#c62828' : BORDER }} disabled={sending} />
              </div>
            </div>
          </div>

          {/* Signing Order */}
          <div style={{ marginBottom:12 }}>
            <label style={labelStyle}>Signing Order</label>
            <select data-testid="docusign-signing-order" value={signingOrder} onChange={e => setSigningOrder(e.target.value)}
              style={{ ...inputStyle, cursor:'pointer' }} disabled={sending}>
              <option value="parallel">Parallel — both receive simultaneously</option>
              <option value="sequential">Sequential — Signer A first, then Signer B</option>
            </select>
          </div>

          {/* Message */}
          <div style={{ marginBottom:8 }}>
            <label style={labelStyle}>Message to signers</label>
            <textarea data-testid="docusign-message" value={message} onChange={e => setMessage(e.target.value)}
              style={{ ...inputStyle, minHeight:70, resize:'vertical', lineHeight:1.5 }} disabled={sending} />
          </div>
        </div>

        {/* Footer */}
        <div style={{ padding:'10px 18px', borderTop:`1px solid ${BORDER}`, display:'flex', justifyContent:'flex-end', gap:8, background:'#fafaf7' }}>
          <button data-testid="btn-docusign-modal-cancel" onClick={onClose} disabled={sending}
            style={{ padding:'7px 14px', fontSize:12, border:`1px solid #ccc`, borderRadius:6, background:'#fff', color:'#666', cursor:'pointer', fontFamily:BODY }}>
            Cancel
          </button>
          <button data-testid="btn-docusign-modal-send" onClick={handleSend} disabled={!canSend}
            style={{ padding:'7px 18px', fontSize:12, fontWeight:600, border:'none', borderRadius:6,
              background: canSend ? '#1a1a2e' : '#ccc', color:'#fff', cursor: canSend ? 'pointer' : 'default',
              fontFamily:BODY, display:'flex', alignItems:'center', gap:6 }}>
            {sending && <span data-testid="docusign-loading" style={{ display:'inline-block', width:12, height:12, border:'2px solid rgba(255,255,255,0.3)', borderTopColor:'#fff', borderRadius:'50%', animation:'spin 0.8s linear infinite' }} />}
            {sending ? 'Sending...' : 'Send via DocuSign'}
          </button>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-shell/src/screens/DocuSignModal.jsx
git commit -m "feat: add DocuSignModal component"
```

---

### Task 7: Wire DocuSignModal into SendQueue.jsx

**Files:**
- Modify: `spa/dcfg-shell/src/screens/SendQueue.jsx`

- [ ] **Step 1: Add import for DocuSignModal**

At the top of SendQueue.jsx, after the existing imports (around line 26):

```js
import DocuSignModal from './DocuSignModal.jsx';
```

- [ ] **Step 2: Add docuSignModal state**

In the state declarations section (around line 113), add:

```js
const [docuSignModal, setDocuSignModal] = useState(null); // { queueRow, meta }
```

- [ ] **Step 3: Add the "Send DocuSign" button to the queue row actions**

In the queue row render (around line 761-776), add a new `DocBtn` between the existing DocuSign external link button and the envelope ID input:

```jsx
<DocBtn data-testid="btn-docusign-send"
  bg="#1a1a2e" color="#fff" border="#1a1a2e"
  onClick={() => setDocuSignModal({ queueRow: q, meta })}
  disabled={busy || missingDoc}
  label="Send DocuSign" icon="✍" />
```

- [ ] **Step 4: Render DocuSignModal at the bottom of the component (before search overlay)**

Before the `{/* ─── SEARCH OVERLAY ─── */}` comment (around line 880), add:

```jsx
{/* ─── DOCUSIGN MODAL ─── */}
{docuSignModal && (
  <DocuSignModal
    queueRow={docuSignModal.queueRow}
    meta={docuSignModal.meta}
    user={user}
    onClose={() => setDocuSignModal(null)}
    onSent={(queueId) => setQueueRows(prev => prev.filter(r => r.dcfg_send_queueid !== queueId))}
    toast={toast}
  />
)}
```

- [ ] **Step 5: Add CSS keyframe for spinner animation**

The DocuSignModal uses a `spin` animation. Add this to the component or use an inline style approach. Since the SPA uses `injectBaseStyles()`, add the keyframe there, OR use a simpler approach — add a `<style>` tag in the modal. The simplest approach for Phase 1: add this in the DocuSignModal.jsx file, at the top level after imports:

```js
// Inject spinner keyframe if not already present
if (typeof document !== 'undefined' && !document.getElementById('dcfg-spin-keyframe')) {
  const style = document.createElement('style');
  style.id = 'dcfg-spin-keyframe';
  style.textContent = '@keyframes spin { to { transform: rotate(360deg); } }';
  document.head.appendChild(style);
}
```

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-shell/src/screens/SendQueue.jsx spa/dcfg-shell/src/screens/DocuSignModal.jsx
git commit -m "feat: wire DocuSign send button + modal into SendQueue grid"
```

---

## Chunk 3: Visual Validation + Config + Deploy

### Task 8: Build before/after HTML mockup

**Files:**
- Create: `docs/mockups/docusign-send-before-after.html`

**Note:** This mockup must be reviewed and approved by the operator BEFORE any SPA build or deploy.

- [ ] **Step 1: Create the mockup HTML**

Build a self-contained HTML file showing:
1. **Before:** Current SendQueue row action bar (Hold, DocuSign link, Envelope ID input, Mark Sent/Approve, Return)
2. **After:** Same row with the new "Send DocuSign" button added
3. **DocuSign Modal:** Full rendering of the confirmation modal with all fields

Use the same design tokens (colors, fonts, spacing) from the SPA.

- [ ] **Step 2: Get operator approval**

Open the mockup in browser and get explicit approval before proceeding to build/deploy.

- [ ] **Step 3: Commit**

```bash
git add docs/mockups/docusign-send-before-after.html
git commit -m "docs: before/after mockup for DocuSign send button + modal"
```

---

### Task 9: Provision dcfg_configs rows

**Note:** This task provisions the config rows that the SPA reads at boot. The `dcfg_docusign_function_url` value will be set after the Azure Function is deployed. For now, create the rows with placeholder values.

**Environments:** Test first, then Prod when ready.

- [ ] **Step 1: Verify pac auth target**

Run: `pac auth list`
Confirm which index is Test.

- [ ] **Step 2: Create dcfg_configs rows via PowerShell**

```powershell
# Connect to Test environment
$token = (pac auth token --environment (pac org who | Select-String 'org0c17e98d').ToString().Trim()).Trim()

# Create config rows (adjust for your Dataverse API pattern)
# dcfg_docusign_function_url — placeholder until Azure Function is deployed
# dcfg_docusign_subject_template
# dcfg_docusign_message_template
```

Use the existing `dcfg_configs` table pattern — check how `dcfg_upload_function_url` was created.

- [ ] **Step 3: Commit config documentation**

Document the config row GUIDs for reference.

---

### Task 10: Configure Azure Function env vars

**Note:** This requires access to the Azure portal or Azure CLI. The operator must provide the DocuSign credentials (integration key, RSA private key, account ID, user ID) from the DocuSign admin console.

- [ ] **Step 1: Collect DocuSign credentials from operator**

Required values:
- `DOCUSIGN_INTEGRATION_KEY` — from DocuSign Admin > Apps and Keys
- `DOCUSIGN_RSA_PRIVATE_KEY` — generated during app setup
- `DOCUSIGN_IMPERSONATED_USER_ID` — from DocuSign Admin > Users
- `DOCUSIGN_ACCOUNT_ID` — from DocuSign Admin > Account
- `DOCUSIGN_BASE_URL` — `https://demo.docusign.net/restapi` for sandbox
- `DOCUSIGN_OAUTH_BASE` — `https://account-d.docusign.com` for sandbox

- [ ] **Step 2: Set env vars in Azure Function App**

Via Azure Portal: Function App > Configuration > Application settings, or via Azure CLI:

```bash
az functionapp config appsettings set --name <function-app-name> --resource-group <rg> --settings \
  DOCUSIGN_INTEGRATION_KEY=<value> \
  DOCUSIGN_RSA_PRIVATE_KEY=<value> \
  DOCUSIGN_IMPERSONATED_USER_ID=<value> \
  DOCUSIGN_ACCOUNT_ID=<value> \
  DOCUSIGN_BASE_URL=https://demo.docusign.net/restapi \
  DOCUSIGN_OAUTH_BASE=https://account-d.docusign.com
```

- [ ] **Step 3: Deploy Azure Function**

```bash
cd C:\dcfg\azure-functions\html-to-pdf
func azure functionapp publish <function-app-name>
```

- [ ] **Step 4: Update dcfg_docusign_function_url config row**

After deploy, get the function URL with key from Azure portal and update the `dcfg_docusign_function_url` config row in Dataverse.

---

### Task 11: Build and deploy SPA (requires operator approval)

**STOP:** Do not proceed without:
1. Mockup approval (Task 8)
2. Azure Function deployed and tested (Task 10)
3. Explicit "deploy to {env}" approval from operator

- [ ] **Step 1: Verify pac auth**

Run: `pac auth list` — confirm target environment.

- [ ] **Step 2: Build**

```bash
cd C:\dcfg\spa\dcfg-shell
npm run build
```

- [ ] **Step 3: Deploy**

```bash
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 4: Post-deploy**

Clear portal cache. Provide launch URL. Restore pac auth to Test.

---

### Task 12: E2E verification

- [ ] **Step 1: Navigate to Send Queue in the portal**

Open the SPA and go to `/#/send-queue`.

- [ ] **Step 2: Verify "Send DocuSign" button appears on queue rows**

Both Sales and Operations tabs should show the button.

- [ ] **Step 3: Click "Send DocuSign" on a test row**

Verify the modal opens with pre-filled signer info.

- [ ] **Step 4: Send a test envelope**

Fill in test signer emails (use DocuSign sandbox test addresses), select signing order, click Send.

- [ ] **Step 5: Verify envelope created in DocuSign**

Check DocuSign admin or sandbox dashboard for the created envelope.

- [ ] **Step 6: Verify queue row updated**

Row should be removed from pending queue. `dcfg_docusign_envelope_id` should be populated.

- [ ] **Step 7: Verify existing manual flow still works**

Use the manual envelope ID paste + Mark Sent flow to confirm it's unaffected.
