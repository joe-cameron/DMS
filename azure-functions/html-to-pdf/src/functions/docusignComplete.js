/**
 * docusignComplete.js — Download signed document from DocuSign and upload to SharePoint
 *
 * Called by the SPA "Mark Complete" action. Downloads the completed/signed PDF
 * from DocuSign using the envelope ID, uploads it to the correct SharePoint
 * folder, and returns the SharePoint URL for the SPA to store on the record.
 *
 * POST /api/docusign-complete
 * Body (JSON):
 *   {
 *     "envelopeId": "DocuSign envelope GUID",
 *     "customerName": "Customer display name (for SP folder path)",
 *     "documentName": "WO-2026-001.docx",
 *     "documentType": "WorkOrder" | "Amendment" | "VendorAgreement" | "MSA",
 *     "queueId": "send_queue GUID (for audit)"
 *   }
 *
 * Response (200): { "sharePointUrl": "https://...sharepoint.com/.../signed.pdf", "fileName": "..." }
 * Error (4xx/5xx): { "error": "...", "detail": "..." }
 *
 * Env vars: same DOCUSIGN_* and SP_* as docusignSend.js
 */
const { app } = require('@azure/functions');
const jwt = require('jsonwebtoken');

// ─── Reuse token caches from docusignSend (each function instance has its own) ───
let cachedDocuSignToken = null;
let cachedDocuSignTokenExp = 0;

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
  return (await resp.json()).access_token;
}

async function getDocuSignToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedDocuSignToken && now < cachedDocuSignTokenExp) return cachedDocuSignToken;

  const oauthBase = process.env.DOCUSIGN_OAUTH_BASE;
  const aud = oauthBase.replace(/^https?:\/\//, '');
  const privateKey = process.env.DOCUSIGN_RSA_PRIVATE_KEY.replace(/\\n/g, '\n');

  const claims = {
    iss: process.env.DOCUSIGN_INTEGRATION_KEY,
    sub: process.env.DOCUSIGN_IMPERSONATED_USER_ID,
    aud,
    iat: now,
    exp: now + 3600,
    scope: 'signature impersonation',
  };

  const assertion = jwt.sign(claims, privateKey, { algorithm: 'RS256' });
  const resp = await fetch(`${oauthBase}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
  });
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`DocuSign token failed: ${resp.status} ${err.slice(0, 200)}`);
  }

  const data = await resp.json();
  cachedDocuSignToken = data.access_token;
  cachedDocuSignTokenExp = now + 3600 - 60;
  return cachedDocuSignToken;
}

// ─── Download combined signed document from DocuSign ───
async function downloadSignedDocument(dsToken, envelopeId, context) {
  const accountId = process.env.DOCUSIGN_ACCOUNT_ID;
  const baseUrl = process.env.DOCUSIGN_BASE_URL;

  // Download combined PDF (all documents merged)
  const url = `${baseUrl}/v2.1/accounts/${accountId}/envelopes/${envelopeId}/documents/combined`;
  context.log(`[DocuSign-Complete] Downloading signed doc: ${url}`);

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${dsToken}`, Accept: 'application/pdf' },
  });
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`DocuSign download failed: ${resp.status} ${err.slice(0, 300)}`);
  }

  const arrayBuffer = await resp.arrayBuffer();
  context.log(`[DocuSign-Complete] Downloaded ${arrayBuffer.byteLength} bytes`);
  return Buffer.from(arrayBuffer);
}

// ─── Upload to SharePoint ───
async function uploadToSharePoint(graphToken, pdfBuffer, folderPath, fileName, context) {
  const siteHost = process.env.SP_SITE_HOST;
  const sitePath = process.env.SP_SITE_PATH;

  // Resolve site ID
  const siteResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${siteHost}:${sitePath}?$select=id`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!siteResp.ok) throw new Error(`Site resolve failed: ${siteResp.status}`);
  const site = await siteResp.json();

  // Find DCFG_Outputs drive
  const drivesResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${site.id}/drives?$select=id,name`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!drivesResp.ok) throw new Error(`Drives list failed: ${drivesResp.status}`);
  const drives = await drivesResp.json();
  const drive = drives.value.find(d => d.name === 'DCFG_Outputs');
  if (!drive) throw new Error(`DCFG_Outputs library not found. Available: ${drives.value.map(d => d.name).join(', ')}`);

  // Upload file — use PUT to create/overwrite
  const uploadPath = `${folderPath}/${fileName}`.split('/').map(encodeURIComponent).join('/');
  context.log(`[DocuSign-Complete] Uploading to: drive=${drive.name}, path=${folderPath}/${fileName}`);

  const uploadResp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${drive.id}/root:/${uploadPath}:/content`,
    {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${graphToken}`,
        'Content-Type': 'application/pdf',
      },
      body: pdfBuffer,
    }
  );
  if (!uploadResp.ok) {
    const err = await uploadResp.text().catch(() => '');
    throw new Error(`SharePoint upload failed: ${uploadResp.status} ${err.slice(0, 300)}`);
  }

  const item = await uploadResp.json();
  // Build the SharePoint URL from the web URL
  const spUrl = item.webUrl || `https://${siteHost}${sitePath}/DCFG_Outputs/${folderPath}/${fileName}`;
  context.log(`[DocuSign-Complete] Uploaded: ${spUrl}`);
  return spUrl;
}

// ═══════════════════════════════════════════════════════════════
// Main handler
// ═══════════════════════════════════════════════════════════════
app.http('docusign-complete', {
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

    const corsHeaders = { 'Access-Control-Allow-Origin': '*' };
    const t0 = Date.now();

    let body;
    try {
      body = await request.json();
    } catch (err) {
      return { status: 400, jsonBody: { error: 'Invalid JSON body', detail: err.message }, headers: corsHeaders };
    }

    // Validate
    const missing = [];
    if (!body.envelopeId) missing.push('envelopeId');
    if (!body.customerName) missing.push('customerName');
    if (!body.documentName) missing.push('documentName');
    if (missing.length > 0) {
      return { status: 400, jsonBody: { error: `Missing required fields: ${missing.join(', ')}` }, headers: corsHeaders };
    }

    try {
      // Step 1: Get tokens
      const [dsToken, graphToken] = await Promise.all([getDocuSignToken(), getGraphToken()]);

      // Step 2: Download signed PDF from DocuSign
      const pdfBuffer = await downloadSignedDocument(dsToken, body.envelopeId, context);

      // Step 3: Build SharePoint folder path — DCFG_Outputs/Customer/Year/DocType
      const year = new Date().getFullYear().toString();
      const docType = body.documentType || 'Contracts';
      const folderPath = `${body.customerName}/${year}/${docType}`;

      // Build signed filename — append "-signed" before extension
      const baseName = body.documentName.replace(/\.[^.]+$/, '');
      const signedFileName = `${baseName}-signed.pdf`;

      // Step 4: Upload to SharePoint
      const sharePointUrl = await uploadToSharePoint(graphToken, pdfBuffer, folderPath, signedFileName, context);

      context.log(`[DocuSign-Complete] Done in ${Date.now() - t0}ms`);
      return {
        status: 200,
        jsonBody: { sharePointUrl, fileName: signedFileName },
        headers: corsHeaders,
      };
    } catch (err) {
      context.log(`[DocuSign-Complete] FAILED: ${err.message}`);
      context.log(`[DocuSign-Complete] Request: ${JSON.stringify({ ...body })}`);
      const statusCode = err.message.includes('Missing') ? 400 : 500;
      return {
        status: statusCode,
        jsonBody: { error: err.message, detail: err.stack?.split('\n').slice(0, 3).join(' | ') },
        headers: corsHeaders,
      };
    }
  },
});
