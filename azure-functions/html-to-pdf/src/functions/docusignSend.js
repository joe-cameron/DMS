/**
 * docusignSend.js — DocuSign envelope creation via JWT grant
 *
 * Downloads a document from SharePoint via Graph API, creates a DocuSign
 * envelope with two signers, and sends immediately.
 *
 * Env vars required:
 *   DOCUSIGN_INTEGRATION_KEY      — DocuSign app integration key
 *   DOCUSIGN_RSA_PRIVATE_KEY      — RSA private key (PEM, \\n-escaped in Azure)
 *   DOCUSIGN_IMPERSONATED_USER_ID — User ID to impersonate
 *   DOCUSIGN_ACCOUNT_ID           — DocuSign account ID
 *   DOCUSIGN_BASE_URL             — e.g., "https://na4.docusign.net/restapi"
 *   DOCUSIGN_OAUTH_BASE           — e.g., "https://account.docusign.com"
 *   SP_TENANT_ID, SP_CLIENT_ID, SP_CLIENT_SECRET, SP_SITE_HOST, SP_SITE_PATH
 *
 * POST /api/docusign-send
 * Body (JSON):
 *   {
 *     "documentUrl": "https://...sharepoint.com/.../file.docx",
 *     "documentName": "Display Name",
 *     "signerA": { "email": "...", "name": "..." },
 *     "signerB": { "email": "...", "name": "..." },
 *     "signingOrder": "parallel" | "sequential",
 *     "message": "Optional message",
 *     "subject": "Optional subject",
 *     "queueId": "audit-id"
 *   }
 *
 * Response (200): { envelopeId: "...", status: "sent" }
 * Error (4xx/5xx): { error: "...", detail: "..." }
 */
const { app } = require('@azure/functions');
const jwt = require('jsonwebtoken');

// ─── In-memory DocuSign token cache ───
let cachedDocuSignToken = null;
let cachedDocuSignTokenExp = 0;

// ─── Graph token acquisition (client_credentials grant) ───
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

// ─── DocuSign JWT grant with in-memory caching ───
async function getDocuSignToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedDocuSignToken && now < cachedDocuSignTokenExp) {
    return cachedDocuSignToken;
  }

  const oauthBase = process.env.DOCUSIGN_OAUTH_BASE;
  const aud = oauthBase.replace(/^https?:\/\//, '');
  const privateKey = process.env.DOCUSIGN_RSA_PRIVATE_KEY.replace(/\\n/g, '\n');

  const claims = {
    iss: process.env.DOCUSIGN_INTEGRATION_KEY,
    sub: process.env.DOCUSIGN_IMPERSONATED_USER_ID,
    aud: aud,
    iat: now,
    exp: now + 3600,
    scope: 'signature impersonation',
  };

  const assertion = jwt.sign(claims, privateKey, { algorithm: 'RS256' });

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: assertion,
  });

  const resp = await fetch(`${oauthBase}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`DocuSign token failed: ${resp.status} ${err.slice(0, 200)}`);
  }

  const data = await resp.json();
  cachedDocuSignToken = data.access_token;
  cachedDocuSignTokenExp = now + 3600 - 60; // 60s buffer
  return cachedDocuSignToken;
}

// ─── Download document from SharePoint via Graph ───
async function downloadFromSharePoint(documentUrl, graphToken, context) {
  const siteHost = process.env.SP_SITE_HOST;
  const sitePath = process.env.SP_SITE_PATH;

  if (!documentUrl.includes(siteHost)) {
    throw new Error(`Document URL does not match SP_SITE_HOST (${siteHost})`);
  }

  // Resolve site ID
  const siteResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${siteHost}:${sitePath}?$select=id`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!siteResp.ok) throw new Error(`Site resolve failed: ${siteResp.status}`);
  const site = await siteResp.json();

  // Extract relative path from URL — everything after the site path
  const urlObj = new URL(documentUrl);
  const fullPath = decodeURIComponent(urlObj.pathname);
  const sitePathIdx = fullPath.indexOf(sitePath);
  if (sitePathIdx === -1) {
    throw new Error(`Cannot extract relative path from URL — site path not found`);
  }
  const afterSite = fullPath.substring(sitePathIdx + sitePath.length);
  // afterSite is like "/DCFG_Outputs/Customer/2026/DocType/file.docx"
  const trimmed = afterSite.replace(/^\//, '');
  const slashIdx = trimmed.indexOf('/');
  if (slashIdx === -1) {
    throw new Error(`Cannot split library name from item path in: ${trimmed}`);
  }
  const libraryName = trimmed.substring(0, slashIdx);
  const itemPath = trimmed.substring(slashIdx + 1);

  context.log(`[DocuSign] Library: ${libraryName}, Item: ${itemPath}`);

  // List drives, find matching library
  const drivesResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${site.id}/drives?$select=id,name`,
    { headers: { Authorization: `Bearer ${graphToken}` } }
  );
  if (!drivesResp.ok) throw new Error(`Drives list failed: ${drivesResp.status}`);
  const drives = await drivesResp.json();

  const drive = drives.value.find(d => d.name === libraryName);
  if (!drive) {
    throw new Error(`Library "${libraryName}" not found. Available: ${drives.value.map(d => d.name).join(', ')}`);
  }

  // Download file content — encode each path segment individually
  const encodedPath = itemPath.split('/').map(encodeURIComponent).join('/');
  const downloadResp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${drive.id}/root:/${encodedPath}:/content`,
    { headers: { Authorization: `Bearer ${graphToken}` }, redirect: 'follow' }
  );
  if (!downloadResp.ok) {
    throw new Error(`File download failed: ${downloadResp.status}`);
  }

  const arrayBuffer = await downloadResp.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

// ─── Create DocuSign envelope ───
async function createEnvelope(docuSignToken, fileBuffer, body) {
  const {
    documentName,
    signerA,
    signerB,
    signingOrder,
    message,
    subject,
  } = body;

  const isParallel = signingOrder === 'parallel';
  const emailSubject = subject || `Signature Required - ${documentName}`;
  const emailBlurb = message || 'Please review and sign the attached document.';

  // Anchor configuration per signer — caller specifies which anchors to use
  // Defaults: signerA = Customer pattern, signerB = Vendor pattern
  const anchorsA = body.anchorsA || { signature: '\\Customer_Signature\\', dateSigned: '\\Customer_DateSigned\\' };
  const anchorsB = body.anchorsB || { signature: '\\Vendor_Signature\\', dateSigned: '\\Vendor_DateSigned\\' };

  const envelopeDefinition = {
    emailSubject,
    emailBlurb,
    status: 'sent',
    documents: [
      {
        documentBase64: fileBuffer.toString('base64'),
        name: documentName,
        fileExtension: documentName.split('.').pop() || 'docx',
        documentId: '1',
      },
    ],
    recipients: {
      signers: [
        {
          email: signerA.email,
          name: signerA.name,
          recipientId: '1',
          routingOrder: '1',
          tabs: {
            signHereTabs: [
              {
                anchorString: anchorsA.signature,
                anchorUnits: 'pixels',
                anchorXOffset: '0',
                anchorYOffset: '-5',
              },
            ],
            dateSignedTabs: [
              {
                anchorString: anchorsA.dateSigned,
                anchorUnits: 'pixels',
                anchorXOffset: '0',
                anchorYOffset: '0',
                fontSize: 'Size10',
              },
            ],
          },
        },
        {
          email: signerB.email,
          name: signerB.name,
          recipientId: '2',
          routingOrder: isParallel ? '1' : '2',
          tabs: {
            signHereTabs: [
              {
                anchorString: anchorsB.signature,
                anchorUnits: 'pixels',
                anchorXOffset: '0',
                anchorYOffset: '-5',
              },
            ],
            dateSignedTabs: [
              {
                anchorString: anchorsB.dateSigned,
                anchorUnits: 'pixels',
                anchorXOffset: '0',
                anchorYOffset: '0',
                fontSize: 'Size10',
              },
            ],
          },
        },
      ],
    },
  };

  const accountId = process.env.DOCUSIGN_ACCOUNT_ID;
  const baseUrl = process.env.DOCUSIGN_BASE_URL;

  const resp = await fetch(
    `${baseUrl}/v2.1/accounts/${accountId}/envelopes`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${docuSignToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(envelopeDefinition),
    }
  );
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`DocuSign envelope failed: ${resp.status} ${err.slice(0, 500)}`);
  }

  return await resp.json();
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

    const corsHeaders = { 'Access-Control-Allow-Origin': '*' };
    const t0 = Date.now();

    let body;
    try {
      body = await request.json();
    } catch (err) {
      return {
        status: 400,
        jsonBody: { error: 'Invalid JSON body', detail: err.message },
        headers: corsHeaders,
      };
    }

    // ── Validate required fields ──
    const missing = [];
    if (!body.documentUrl) missing.push('documentUrl');
    if (!body.signerA?.email) missing.push('signerA.email');
    if (!body.signerA?.name) missing.push('signerA.name');
    if (!body.signerB?.email) missing.push('signerB.email');
    if (!body.signerB?.name) missing.push('signerB.name');
    if (missing.length > 0) {
      return {
        status: 400,
        jsonBody: { error: `Missing required fields: ${missing.join(', ')}`, detail: missing },
        headers: corsHeaders,
      };
    }

    try {
      // ── Step 1: Download document from SharePoint ──
      context.log(`[DocuSign] Downloading: ${body.documentUrl}`);
      const graphToken = await getGraphToken();
      const fileBuffer = await downloadFromSharePoint(body.documentUrl, graphToken, context);
      context.log(`[DocuSign] Downloaded ${fileBuffer.length} bytes`);

      // ── Step 2: Get DocuSign token ──
      const docuSignToken = await getDocuSignToken();

      // ── Step 3: Create and send envelope ──
      context.log(`[DocuSign] Creating envelope for "${body.documentName}"`);
      const envelope = await createEnvelope(docuSignToken, fileBuffer, body);
      context.log(`[DocuSign] Envelope created: ${envelope.envelopeId} (${Date.now() - t0}ms)`);

      return {
        status: 200,
        jsonBody: { envelopeId: envelope.envelopeId, status: 'sent' },
        headers: corsHeaders,
      };
    } catch (err) {
      // Log full request body (excluding potential large doc content) + error
      const safeBody = { ...body };
      delete safeBody.file_base64; // safety — not expected but just in case
      context.log(`[DocuSign] FAILED: ${err.message}`);
      context.log(`[DocuSign] Request: ${JSON.stringify(safeBody)}`);

      const statusCode = err.message.includes('Missing') || err.message.includes('does not match') ? 400 : 500;
      return {
        status: statusCode,
        jsonBody: { error: err.message, detail: err.stack?.split('\n').slice(0, 3).join(' | ') },
        headers: corsHeaders,
      };
    }
  },
});
