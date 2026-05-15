/**
 * docusignPoll.js — Timer-triggered function to check DocuSign envelope status
 *
 * Runs hourly from 6AM to midnight ET. Queries Dataverse for send queue rows
 * with status = Sent, checks each envelope's status in DocuSign, and if
 * completed: downloads signed PDF, uploads to SharePoint, marks row Complete.
 *
 * Schedule: "0 0 6-23 * * *" (every hour from 6AM to 11PM, every day)
 *
 * Env vars: same DOCUSIGN_* and SP_* as docusignSend.js
 * Additional: DATAVERSE_URL, DATAVERSE_CLIENT_ID, DATAVERSE_CLIENT_SECRET, DATAVERSE_TENANT_ID
 */
const { app } = require('@azure/functions');
const jwt = require('jsonwebtoken');

// ─── Token caches ───
let cachedDsToken = null, dsTokenExp = 0;
let cachedGraphToken = null, graphTokenExp = 0;
let cachedDvToken = null, dvTokenExp = 0;

async function getDocuSignToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedDsToken && now < dsTokenExp) return cachedDsToken;
  const oauthBase = process.env.DOCUSIGN_OAUTH_BASE;
  const privateKey = process.env.DOCUSIGN_RSA_PRIVATE_KEY.replace(/\\n/g, '\n');
  const assertion = jwt.sign({
    iss: process.env.DOCUSIGN_INTEGRATION_KEY,
    sub: process.env.DOCUSIGN_IMPERSONATED_USER_ID,
    aud: oauthBase.replace(/^https?:\/\//, ''),
    iat: now, exp: now + 3600, scope: 'signature impersonation',
  }, privateKey, { algorithm: 'RS256' });
  const resp = await fetch(`${oauthBase}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
  });
  if (!resp.ok) throw new Error(`DocuSign token: ${resp.status}`);
  const data = await resp.json();
  cachedDsToken = data.access_token;
  dsTokenExp = now + 3600 - 60;
  return cachedDsToken;
}

async function getGraphToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedGraphToken && now < graphTokenExp) return cachedGraphToken;
  const resp = await fetch(`https://login.microsoftonline.com/${process.env.SP_TENANT_ID}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials', client_id: process.env.SP_CLIENT_ID,
      client_secret: process.env.SP_CLIENT_SECRET, scope: 'https://graph.microsoft.com/.default',
    }).toString(),
  });
  if (!resp.ok) throw new Error(`Graph token: ${resp.status}`);
  const data = await resp.json();
  cachedGraphToken = data.access_token;
  graphTokenExp = now + 3600 - 60;
  return cachedGraphToken;
}

// Reuses the same SP_CLIENT_ID / SP_CLIENT_SECRET / SP_TENANT_ID service principal
// that already has Dataverse access (same app registration used for Graph API).
async function getDataverseToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedDvToken && now < dvTokenExp) return cachedDvToken;
  const dvUrl = process.env.DATAVERSE_URL; // e.g. https://org06f5de0b.crm.dynamics.com
  const resp = await fetch(`https://login.microsoftonline.com/${process.env.SP_TENANT_ID}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.SP_CLIENT_ID,
      client_secret: process.env.SP_CLIENT_SECRET,
      scope: `${dvUrl}/.default`,
    }).toString(),
  });
  if (!resp.ok) throw new Error(`Dataverse token: ${resp.status}`);
  const data = await resp.json();
  cachedDvToken = data.access_token;
  dvTokenExp = now + 3600 - 60;
  return cachedDvToken;
}

// ─── Check envelope status in DocuSign ───
async function getEnvelopeStatus(dsToken, envelopeId) {
  const accountId = process.env.DOCUSIGN_ACCOUNT_ID;
  const baseUrl = process.env.DOCUSIGN_BASE_URL;
  const resp = await fetch(`${baseUrl}/v2.1/accounts/${accountId}/envelopes/${envelopeId}`, {
    headers: { Authorization: `Bearer ${dsToken}` },
  });
  if (!resp.ok) return null;
  return await resp.json();
}

// ─── Download signed PDF ───
async function downloadSigned(dsToken, envelopeId) {
  const accountId = process.env.DOCUSIGN_ACCOUNT_ID;
  const baseUrl = process.env.DOCUSIGN_BASE_URL;
  const resp = await fetch(`${baseUrl}/v2.1/accounts/${accountId}/envelopes/${envelopeId}/documents/combined`, {
    headers: { Authorization: `Bearer ${dsToken}`, Accept: 'application/pdf' },
  });
  if (!resp.ok) throw new Error(`Download signed: ${resp.status}`);
  return Buffer.from(await resp.arrayBuffer());
}

// ─── Upload to SharePoint ───
async function uploadToSP(graphToken, pdfBuffer, folderPath, fileName) {
  const siteHost = process.env.SP_SITE_HOST;
  const sitePath = process.env.SP_SITE_PATH;
  const siteResp = await fetch(`https://graph.microsoft.com/v1.0/sites/${siteHost}:${sitePath}?$select=id`, { headers: { Authorization: `Bearer ${graphToken}` } });
  if (!siteResp.ok) throw new Error(`Site: ${siteResp.status}`);
  const site = await siteResp.json();
  const drivesResp = await fetch(`https://graph.microsoft.com/v1.0/sites/${site.id}/drives?$select=id,name`, { headers: { Authorization: `Bearer ${graphToken}` } });
  const drives = await drivesResp.json();
  const drive = drives.value.find(d => d.name === 'DCFG_Outputs');
  if (!drive) throw new Error('DCFG_Outputs not found');
  const uploadPath = `${folderPath}/${fileName}`.split('/').map(encodeURIComponent).join('/');
  const uploadResp = await fetch(`https://graph.microsoft.com/v1.0/drives/${drive.id}/root:/${uploadPath}:/content`, {
    method: 'PUT', headers: { Authorization: `Bearer ${graphToken}`, 'Content-Type': 'application/pdf' }, body: pdfBuffer,
  });
  if (!uploadResp.ok) throw new Error(`Upload: ${uploadResp.status}`);
  const item = await uploadResp.json();
  return item.webUrl;
}

// ═══════════════════════════════════════════════════════════════
app.timer('docusign-poll', {
  // Every hour from 6AM to 11PM (UTC — adjust offset for ET if needed)
  schedule: '0 0 10-4 * * *',  // 10:00 UTC = 6AM ET, 4:00 UTC next day = midnight ET
  handler: async (timer, context) => {
    const t0 = Date.now();
    const dvUrl = process.env.DATAVERSE_URL;
    if (!dvUrl) { context.log('[DocuSign-Poll] DATAVERSE_URL not set, skipping'); return; }

    try {
      const dvToken = await getDataverseToken();
      const dvHeaders = { Authorization: `Bearer ${dvToken}`, Accept: 'application/json' };
      const dvBase = `${dvUrl}/api/data/v9.2`;

      // Query Sent queue rows
      const qResp = await fetch(
        `${dvBase}/dcfg_send_queues?$filter=dcfg_queue_status eq 100000001&$select=dcfg_send_queueid,dcfg_docusign_envelope_id,dcfg_notes,_dcfg_contract_id_value,_dcfg_msa_id_value,_dcfg_customer_id_value` +
        `&$expand=dcfg_contract_id($select=dcfg_contract_number,dcfg_client_name,dcfg_contract_type),dcfg_customer_id($select=dcfg_name)` +
        `&$top=100`,
        { headers: dvHeaders }
      );
      if (!qResp.ok) { context.log(`[DocuSign-Poll] Dataverse query failed: ${qResp.status}`); return; }
      const rows = (await qResp.json()).value || [];
      context.log(`[DocuSign-Poll] Found ${rows.length} sent rows to check`);

      if (rows.length === 0) return;

      const dsToken = await getDocuSignToken();
      const graphToken = await getGraphToken();
      let completed = 0, declined = 0;

      for (const row of rows) {
        const envId = row.dcfg_docusign_envelope_id;
        if (!envId) continue;

        try {
          const envelope = await getEnvelopeStatus(dsToken, envId);
          if (!envelope) continue;

          if (envelope.status === 'completed') {
            // Download signed doc + upload to SharePoint
            const customerName = row.dcfg_customer_id?.dcfg_name || 'Unknown';
            const docName = row.dcfg_contract_id?.dcfg_contract_number || 'Document';
            const docTypeMap = { 100000000: 'WorkOrder', 100000001: 'Amendment', 100000002: 'VendorAgreement' };
            const docType = row.dcfg_contract_id?.dcfg_contract_type != null
              ? (docTypeMap[row.dcfg_contract_id.dcfg_contract_type] || 'Contracts') : 'MSA';
            const year = new Date().getFullYear().toString();
            const folderPath = `${customerName}/${year}/${docType}`;
            const fileName = `${docName}-signed.pdf`;

            const pdfBuffer = await downloadSigned(dsToken, envId);
            const spUrl = await uploadToSP(graphToken, pdfBuffer, folderPath, fileName);

            // Update queue row → Complete
            await fetch(`${dvBase}/dcfg_send_queues(${row.dcfg_send_queueid})`, {
              method: 'PATCH',
              headers: { ...dvHeaders, 'Content-Type': 'application/json' },
              body: JSON.stringify({
                dcfg_queue_status: 100000002, // Complete
                dcfg_envelope_proof_url: spUrl,
              }),
            });

            // Update contract → SignedReceived
            if (row._dcfg_contract_id_value) {
              await fetch(`${dvBase}/dcfg_contracts(${row._dcfg_contract_id_value})`, {
                method: 'PATCH',
                headers: { ...dvHeaders, 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  dcfg_status: 100000003, // SignedReceived
                  dcfg_signed_date: new Date().toISOString(),
                  dcfg_signed_document_url: spUrl,
                }),
              });
            }

            context.log(`[DocuSign-Poll] COMPLETED: ${docName} → ${spUrl}`);
            completed++;
          } else if (envelope.status === 'declined' || envelope.status === 'voided') {
            await fetch(`${dvBase}/dcfg_send_queues(${row.dcfg_send_queueid})`, {
              method: 'PATCH',
              headers: { ...dvHeaders, 'Content-Type': 'application/json' },
              body: JSON.stringify({
                dcfg_queue_status: envelope.status === 'declined' ? 100000004 : 100000003,
                dcfg_notes: `DocuSign ${envelope.status}: ${envelope.voidedReason || envelope.declinedReason || ''}`.trim(),
              }),
            });
            context.log(`[DocuSign-Poll] ${envelope.status.toUpperCase()}: ${envId}`);
            declined++;
          }
          // 'sent', 'delivered', 'created' — still in progress, skip
        } catch (err) {
          context.log(`[DocuSign-Poll] Error processing ${envId}: ${err.message}`);
        }
      }

      context.log(`[DocuSign-Poll] Done in ${Date.now() - t0}ms — ${completed} completed, ${declined} declined/voided, ${rows.length - completed - declined} still pending`);
    } catch (err) {
      context.log(`[DocuSign-Poll] FATAL: ${err.message}`);
    }
  },
});
