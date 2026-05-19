/**
 * docusignSend.js — DocuSign envelope creation via JWT grant
 *
 * Downloads a document from SharePoint via Graph API, creates a DocuSign
 * envelope with a dynamic recipient list, and sends immediately.
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
 * Body (JSON) — new format (recipients array):
 *   {
 *     "documentUrl": "https://...sharepoint.com/.../file.docx",
 *     "documentName": "Display Name",
 *     "recipients": [
 *       { "email": "...", "name": "...", "role": "signer", "routingOrder": 1,
 *         "anchorSign": "\\Vendor_Signature\\", "anchorDate": "\\Vendor_DateSigned\\" },
 *       { "email": "...", "name": "...", "role": "approver", "routingOrder": 2,
 *         "anchorApprove": "\\Vendor_Signature\\", "approveLabel": "Approve" },
 *       { "email": "...", "name": "...", "role": "cc", "routingOrder": 99 }
 *     ],
 *     "message": "Optional message",
 *     "subject": "Optional subject",
 *     "queueId": "audit-id"
 *   }
 *
 * Body (JSON) — legacy format (still supported):
 *   {
 *     "documentUrl": "...", "documentName": "...",
 *     "signerA": { "email": "...", "name": "..." },
 *     "signerB": { "email": "...", "name": "..." },
 *     "signingOrder": "parallel" | "sequential",
 *     "anchorsA": { "signature": "...", "dateSigned": "..." },
 *     "anchorsB": { "signature": "...", "dateSigned": "..." },
 *     "carbonCopies": [{ "email": "...", "name": "...", "routingOrder": 99 }]
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

// ─── Normalize legacy (signerA/signerB) format to recipients array ───
function normalizeLegacyToRecipients(body) {
  const anchorsA = body.anchorsA || { signature: '\\Vendor_Signature\\', dateSigned: '\\Vendor_DateSigned\\' };
  const anchorsB = body.anchorsB || { signature: '\\Customer_Signature\\', dateSigned: '\\Customer_DateSigned\\' };
  const isParallel = body.signingOrder === 'parallel';

  const recipients = [
    {
      email: body.signerA.email, name: body.signerA.name,
      role: 'signer', routingOrder: 1,
      anchorSign: anchorsA.signature, anchorDate: anchorsA.dateSigned,
    },
    {
      email: body.signerB.email, name: body.signerB.name,
      role: 'signer', routingOrder: isParallel ? 1 : 2,
      anchorSign: anchorsB.signature, anchorDate: anchorsB.dateSigned,
    },
  ];

  const ccList = body.carbonCopies || [];
  for (const cc of ccList) {
    if (cc.email && cc.name) {
      recipients.push({ email: cc.email, name: cc.name, role: 'cc', routingOrder: cc.routingOrder || 99 });
    }
  }

  return recipients;
}

// ─── Create DocuSign envelope ───
// Accepts a dynamic recipients array. Each recipient has:
//   role: "signer" | "approver" | "cc"
//   routingOrder: number (controls sequence)
//   anchorSign / anchorDate: anchor strings for signers
//   anchorApprove / approveLabel: anchor string + button text for approvers
async function createEnvelope(docuSignToken, fileBuffer, body) {
  const { documentName, message, subject } = body;

  const emailSubject = subject || `Signature Required - ${documentName}`;
  const emailBlurb = message || 'Please review and sign the attached document.';

  // Use new recipients array or convert from legacy format
  const recipientList = body.recipients || normalizeLegacyToRecipients(body);

  // Build DocuSign recipient objects
  const signers = [];
  const carbonCopies = [];
  let recipientId = 1;

  for (const r of recipientList) {
    if (!r.email || !r.name) continue;
    const id = String(recipientId++);
    const order = String(r.routingOrder || 1);

    if (r.role === 'signer') {
      const tabs = {};
      if (r.anchorSign) {
        tabs.signHereTabs = [{
          anchorString: r.anchorSign,
          anchorUnits: 'pixels',
          anchorXOffset: String(r.signXOffset || 0),
          anchorYOffset: String(r.signYOffset || -5),
        }];
      }
      if (r.anchorDate) {
        tabs.dateSignedTabs = [{
          anchorString: r.anchorDate,
          anchorUnits: 'pixels',
          anchorXOffset: String(r.dateXOffset || 0),
          anchorYOffset: String(r.dateYOffset || 0),
          fontSize: 'Size10',
        }];
      }
      signers.push({ email: r.email, name: r.name, recipientId: id, routingOrder: order, tabs });

    } else if (r.role === 'approver') {
      // Approvers are signers with approveTabs instead of signHereTabs
      const tabs = {};
      if (r.anchorApprove) {
        tabs.approveTabs = [{
          anchorString: r.anchorApprove,
          anchorUnits: 'pixels',
          anchorXOffset: String(r.approveXOffset || 200),
          anchorYOffset: String(r.approveYOffset || -5),
          buttonText: r.approveLabel || 'Approve',
        }];
      }
      signers.push({ email: r.email, name: r.name, recipientId: id, routingOrder: order, tabs });

    } else if (r.role === 'cc') {
      carbonCopies.push({ email: r.email, name: r.name, recipientId: id, routingOrder: order });
    }
  }

  if (signers.length === 0) {
    throw new Error('No signers in recipients list');
  }

  const envelopeDefinition = {
    emailSubject,
    emailBlurb,
    status: 'sent',
    documents: [{
      documentBase64: fileBuffer.toString('base64'),
      name: documentName,
      fileExtension: documentName.split('.').pop() || 'docx',
      documentId: '1',
    }],
    recipients: {
      signers,
      ...(carbonCopies.length > 0 ? { carbonCopies } : {}),
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
    if (!body.documentUrl && !body.fileBase64) missing.push('documentUrl or fileBase64');
    const hasRecipients = Array.isArray(body.recipients) && body.recipients.length > 0;
    const hasLegacy = body.signerA?.email && body.signerB?.email;
    if (!hasRecipients && !hasLegacy) {
      missing.push('recipients array or signerA/signerB');
    }
    if (missing.length > 0) {
      return {
        status: 400,
        jsonBody: { error: `Missing required fields: ${missing.join(', ')}`, detail: missing },
        headers: corsHeaders,
      };
    }

    try {
      // ── Step 1: Get document bytes (direct upload or SharePoint download) ──
      let fileBuffer;
      if (body.fileBase64) {
        fileBuffer = Buffer.from(body.fileBase64, 'base64');
        context.log(`[DocuSign] Using uploaded file: ${body.documentName} (${fileBuffer.length} bytes)`);
      } else {
        context.log(`[DocuSign] Downloading: ${body.documentUrl}`);
        const graphToken = await getGraphToken();
        fileBuffer = await downloadFromSharePoint(body.documentUrl, graphToken, context);
        context.log(`[DocuSign] Downloaded ${fileBuffer.length} bytes`);
      }

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
      delete safeBody.fileBase64; // strip large base64 payload from error logs
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
