/**
 * sharepointUpload.js — NASA-grade SharePoint file upload endpoint
 *
 * Triple-layer fault tolerance:
 *   Layer 1: Graph API createUploadSession (chunked, any size)
 *   Layer 2: Graph API simple PUT (under 4MB)
 *   Layer 3: SharePoint REST _api with app-only token (server-side, no CORS)
 *
 * After ANY success: read-back verification — GET file metadata to confirm existence.
 * Retry policy: 3 attempts per layer, exponential backoff (1s, 2s, 4s).
 * Circuit breaker: if Graph fails 3x consecutively, skip to Layer 3 for 60s.
 *
 * Env vars required:
 *   SP_TENANT_ID     — Entra tenant ID
 *   SP_CLIENT_ID     — App registration client ID with Sites.ReadWrite.All
 *   SP_CLIENT_SECRET — App registration client secret
 *   SP_SITE_HOST     — e.g., "decadesconstructiongroup.sharepoint.com"
 *   SP_SITE_PATH     — e.g., "/sites/DCFGContractingSuite"
 *
 * POST /api/sharepoint-upload
 * Body (JSON):
 *   {
 *     "file_base64": "<base64 encoded file>",
 *     "customer_name": "Bancroft",
 *     "year": 2026,
 *     "doc_type": "Essential",
 *     "filename": "Bancroft - Essential - 2026-04-18.docx"
 *   }
 *
 * Response (JSON):
 *   {
 *     "success": true,
 *     "url": "https://...sharepoint.com/.../filename.docx",
 *     "method": "graph-chunked|graph-simple|sharepoint-rest",
 *     "verified": true,
 *     "timing_ms": 1234,
 *     "attempts": [{ "layer": 1, "status": "success", "ms": 800 }, ...]
 *   }
 */
const { app } = require('@azure/functions');

// ─── Circuit breaker state (in-memory, resets on function cold start) ───
let graphFailCount = 0;
let graphCircuitOpenUntil = 0;

// ─── Config from env ───
function getConfig() {
  return {
    tenantId:     process.env.SP_TENANT_ID,
    clientId:     process.env.SP_CLIENT_ID,
    clientSecret: process.env.SP_CLIENT_SECRET,
    siteHost:     process.env.SP_SITE_HOST || 'decadesconstructiongroup.sharepoint.com',
    sitePath:     process.env.SP_SITE_PATH || '/sites/DCFGContractingSuite',
  };
}

// ─── Token acquisition (client_credentials grant) ───
async function getGraphToken(config) {
  const tokenUrl = `https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/token`;
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: config.clientId,
    client_secret: config.clientSecret,
    scope: 'https://graph.microsoft.com/.default',
  });
  const resp = await fetch(tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`Token failed: ${resp.status} ${err.slice(0, 200)}`);
  }
  const data = await resp.json();
  return data.access_token;
}

async function getSharePointToken(config) {
  const tokenUrl = `https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/token`;
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: config.clientId,
    client_secret: config.clientSecret,
    scope: `https://${config.siteHost}/.default`,
  });
  const resp = await fetch(tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`SP Token failed: ${resp.status} ${err.slice(0, 200)}`);
  }
  const data = await resp.json();
  return data.access_token;
}

// ─── Retry helper ───
async function retry(fn, maxAttempts = 3) {
  let lastErr;
  for (let i = 0; i < maxAttempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (i < maxAttempts - 1) {
        const delay = Math.pow(2, i) * 1000; // 1s, 2s, 4s
        await new Promise(r => setTimeout(r, delay));
      }
    }
  }
  throw lastErr;
}

// ─── Resolve Graph site ID and drive ID ───
async function resolveSiteAndDrive(token, config, libraryName) {
  // Get site ID
  const siteResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${config.siteHost}:${config.sitePath}?$select=id`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  if (!siteResp.ok) throw new Error(`Site resolve failed: ${siteResp.status}`);
  const site = await siteResp.json();

  // Get document library drives
  const drivesResp = await fetch(
    `https://graph.microsoft.com/v1.0/sites/${site.id}/drives?$select=id,name`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  if (!drivesResp.ok) throw new Error(`Drives list failed: ${drivesResp.status}`);
  const drives = await drivesResp.json();

  // Find target library by name (default: DCFG_Outputs), fall back to first drive
  const targetLib = libraryName || 'DCFG_Outputs';
  const targetDrive = drives.value.find(d => d.name === targetLib) || drives.value[0];
  if (!targetDrive) throw new Error(`No document library '${targetLib}' found`);

  return { siteId: site.id, driveId: targetDrive.id, libraryName: targetDrive.name };
}

// ─── Ensure folder path exists via Graph ───
async function ensureFolderPath(token, driveId, folderPath) {
  // Try to get the folder first
  const checkResp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${driveId}/root:/${encodeURIComponent(folderPath)}`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  if (checkResp.ok) return; // folder exists

  // Create each segment
  const segments = folderPath.split('/');
  let currentPath = '';
  for (const seg of segments) {
    const parentPath = currentPath || 'root';
    const parentUrl = currentPath
      ? `https://graph.microsoft.com/v1.0/drives/${driveId}/root:/${encodeURIComponent(currentPath)}:/children`
      : `https://graph.microsoft.com/v1.0/drives/${driveId}/root/children`;

    const createResp = await fetch(parentUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: seg,
        folder: {},
        '@microsoft.graph.conflictBehavior': 'fail', // don't overwrite existing
      }),
    });
    // 409 = already exists = fine
    if (!createResp.ok && createResp.status !== 409) {
      const err = await createResp.text().catch(() => '');
      throw new Error(`Folder create failed for "${seg}": ${createResp.status} ${err.slice(0, 200)}`);
    }
    currentPath = currentPath ? `${currentPath}/${seg}` : seg;
  }
}

// ─── Layer 1: Graph API chunked upload (createUploadSession) ───
async function uploadGraphChunked(token, driveId, folderPath, filename, buffer) {
  const itemPath = `${folderPath}/${filename}`;
  const sessionResp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${driveId}/root:/${encodeURIComponent(itemPath)}:/createUploadSession`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        item: {
          '@microsoft.graph.conflictBehavior': 'replace',
          name: filename,
        },
      }),
    }
  );
  if (!sessionResp.ok) {
    const err = await sessionResp.text().catch(() => '');
    throw new Error(`Upload session failed: ${sessionResp.status} ${err.slice(0, 200)}`);
  }
  const session = await sessionResp.json();
  const uploadUrl = session.uploadUrl;

  // Upload in chunks of 3.2 MB (multiple of 320 KiB)
  const CHUNK_SIZE = 320 * 1024 * 10; // 3.2 MB
  const totalSize = buffer.length;
  let offset = 0;

  while (offset < totalSize) {
    const end = Math.min(offset + CHUNK_SIZE, totalSize);
    const chunk = buffer.subarray(offset, end);

    const chunkResp = await fetch(uploadUrl, {
      method: 'PUT',
      headers: {
        'Content-Length': String(chunk.length),
        'Content-Range': `bytes ${offset}-${end - 1}/${totalSize}`,
      },
      // NO Authorization header — uploadUrl is pre-authenticated
      body: chunk,
    });

    if (!chunkResp.ok && chunkResp.status !== 200 && chunkResp.status !== 201 && chunkResp.status !== 202) {
      const err = await chunkResp.text().catch(() => '');
      throw new Error(`Chunk upload failed at ${offset}: ${chunkResp.status} ${err.slice(0, 200)}`);
    }
    offset = end;
  }

  return true;
}

// ─── Layer 2: Graph API simple PUT (under 4MB) ───
async function uploadGraphSimple(token, driveId, folderPath, filename, buffer) {
  const itemPath = `${folderPath}/${filename}`;
  const resp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${driveId}/root:/${encodeURIComponent(itemPath)}:/content`,
    {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/octet-stream',
      },
      body: buffer,
    }
  );
  if (!resp.ok) {
    const err = await resp.text().catch(() => '');
    throw new Error(`Simple upload failed: ${resp.status} ${err.slice(0, 200)}`);
  }
  return true;
}

// ─── Layer 3: SharePoint REST _api (app-only, server-side) ───
async function uploadSharePointRest(config, folderPath, filename, buffer) {
  const spToken = await getSharePointToken(config);
  const siteUrl = `https://${config.siteHost}${config.sitePath}`;

  // Get digest
  const digestResp = await fetch(`${siteUrl}/_api/contextinfo`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${spToken}`,
      Accept: 'application/json',
    },
  });
  if (!digestResp.ok) throw new Error(`SP digest failed: ${digestResp.status}`);
  const digestData = await digestResp.json();
  const digest = digestData.d?.GetContextWebInformation?.FormDigestValue || digestData.FormDigestValue;

  // Ensure folder
  const libRelPath = `${config.sitePath}/DCFG_Outputs`;
  const segments = folderPath.split('/');
  let currentPath = libRelPath;
  for (const seg of segments) {
    currentPath += '/' + seg;
    await fetch(`${siteUrl}/_api/web/folders`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${spToken}`,
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-RequestDigest': digest,
      },
      body: JSON.stringify({ ServerRelativeUrl: currentPath }),
    }).catch(() => {}); // ignore if exists
  }

  // Upload
  const fullFolderPath = `${libRelPath}/${folderPath}`;
  const uploadUrl = `${siteUrl}/_api/web/GetFolderByServerRelativeUrl('${encodeURIComponent(fullFolderPath)}')/Files/add(url='${encodeURIComponent(filename)}',overwrite=true)`;
  const uploadResp = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${spToken}`,
      Accept: 'application/json',
      'X-RequestDigest': digest,
    },
    body: buffer,
  });
  if (!uploadResp.ok) {
    const err = await uploadResp.text().catch(() => '');
    throw new Error(`SP REST upload failed: ${uploadResp.status} ${err.slice(0, 200)}`);
  }
  return true;
}

// ─── Verify file exists (read-back) ───
async function verifyFileExists(token, driveId, folderPath, filename) {
  const itemPath = `${folderPath}/${filename}`;
  const resp = await fetch(
    `https://graph.microsoft.com/v1.0/drives/${driveId}/root:/${encodeURIComponent(itemPath)}?$select=id,name,size,webUrl`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  if (!resp.ok) return { verified: false, status: resp.status };
  const item = await resp.json();
  return { verified: true, webUrl: item.webUrl, size: item.size, id: item.id };
}

// ═══════════════════════════════════════════════════════════════
// Main handler
// ═══════════════════════════════════════════════════════════════
app.http('sharepoint-upload', {
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
    const attempts = [];

    try {
      const body = await request.json();
      const { file_base64, customer_name, year, doc_type, filename, library, folder_path } = body;

      if (!file_base64 || !filename) {
        return { status: 400, jsonBody: { success: false, error: 'Missing file_base64 or filename' }, headers: corsHeaders };
      }

      const config = getConfig();
      if (!config.tenantId || !config.clientId || !config.clientSecret) {
        return { status: 500, jsonBody: { success: false, error: 'Server config missing SP_TENANT_ID, SP_CLIENT_ID, or SP_CLIENT_SECRET' }, headers: corsHeaders };
      }

      const buffer = Buffer.from(file_base64, 'base64');
      // Use explicit folder_path if provided, otherwise construct from customer/year/doc_type
      const targetLibrary = library || 'DCFG_Outputs';
      const folderPath = folder_path || `${customer_name || 'Unassigned'}/${year || new Date().getFullYear()}/${doc_type || 'Document'}`;
      const fileUrl = `https://${config.siteHost}${config.sitePath}/${targetLibrary}/${folderPath}/${filename}`;

      context.log(`[SP Upload] Starting: ${filename} (${buffer.length} bytes) → ${folderPath}`);

      let success = false;
      let method = null;
      let graphToken = null;
      let driveId = null;

      // ── Check circuit breaker ──
      const graphCircuitOpen = Date.now() < graphCircuitOpenUntil;
      if (graphCircuitOpen) {
        context.log('[SP Upload] Graph circuit OPEN — skipping to Layer 3');
      }

      // ── Layer 1: Graph chunked (skip if circuit open) ──
      if (!success && !graphCircuitOpen) {
        const lt0 = Date.now();
        try {
          graphToken = await retry(() => getGraphToken(config));
          const resolved = await resolveSiteAndDrive(graphToken, config, targetLibrary);
          driveId = resolved.driveId;
          await ensureFolderPath(graphToken, driveId, folderPath);
          await retry(() => uploadGraphChunked(graphToken, driveId, folderPath, filename, buffer));
          success = true;
          method = 'graph-chunked';
          graphFailCount = 0; // reset circuit
          attempts.push({ layer: 1, method: 'graph-chunked', status: 'success', ms: Date.now() - lt0 });
          context.log(`[SP Upload] Layer 1 SUCCESS: ${Date.now() - lt0}ms`);
        } catch (err) {
          attempts.push({ layer: 1, method: 'graph-chunked', status: 'failed', error: err.message, ms: Date.now() - lt0 });
          context.log(`[SP Upload] Layer 1 FAILED: ${err.message}`);
          graphFailCount++;
        }
      }

      // ── Layer 2: Graph simple PUT (under 4MB, skip if circuit open) ──
      if (!success && !graphCircuitOpen && buffer.length <= 4 * 1024 * 1024) {
        const lt0 = Date.now();
        try {
          if (!graphToken) graphToken = await retry(() => getGraphToken(config));
          if (!driveId) {
            const resolved = await resolveSiteAndDrive(graphToken, config, targetLibrary);
            driveId = resolved.driveId;
          }
          await ensureFolderPath(graphToken, driveId, folderPath);
          await retry(() => uploadGraphSimple(graphToken, driveId, folderPath, filename, buffer));
          success = true;
          method = 'graph-simple';
          graphFailCount = 0;
          attempts.push({ layer: 2, method: 'graph-simple', status: 'success', ms: Date.now() - lt0 });
          context.log(`[SP Upload] Layer 2 SUCCESS: ${Date.now() - lt0}ms`);
        } catch (err) {
          attempts.push({ layer: 2, method: 'graph-simple', status: 'failed', error: err.message, ms: Date.now() - lt0 });
          context.log(`[SP Upload] Layer 2 FAILED: ${err.message}`);
          graphFailCount++;
        }
      }

      // ── Trip circuit breaker if Graph failed too many times ──
      if (graphFailCount >= 3) {
        graphCircuitOpenUntil = Date.now() + 60000;
        context.log('[SP Upload] Circuit breaker TRIPPED — Graph bypassed for 60s');
      }

      // ── Layer 3: SharePoint REST (always available as final fallback) ──
      if (!success) {
        const lt0 = Date.now();
        try {
          await retry(() => uploadSharePointRest(config, folderPath, filename, buffer));
          success = true;
          method = 'sharepoint-rest';
          attempts.push({ layer: 3, method: 'sharepoint-rest', status: 'success', ms: Date.now() - lt0 });
          context.log(`[SP Upload] Layer 3 SUCCESS: ${Date.now() - lt0}ms`);
        } catch (err) {
          attempts.push({ layer: 3, method: 'sharepoint-rest', status: 'failed', error: err.message, ms: Date.now() - lt0 });
          context.log(`[SP Upload] Layer 3 FAILED: ${err.message}`);
        }
      }

      if (!success) {
        return {
          status: 500,
          jsonBody: {
            success: false,
            error: 'All upload layers failed',
            attempts,
            timing_ms: Date.now() - t0,
          },
          headers: corsHeaders,
        };
      }

      // ── Verify file exists (read-back) ──
      let verified = false;
      try {
        if (!graphToken) graphToken = await getGraphToken(config);
        if (!driveId) {
          const resolved = await resolveSiteAndDrive(graphToken, config, targetLibrary);
          driveId = resolved.driveId;
        }
        const verifyResult = await verifyFileExists(graphToken, driveId, folderPath, filename);
        verified = verifyResult.verified;
        if (verified) {
          context.log(`[SP Upload] VERIFIED: ${verifyResult.webUrl} (${verifyResult.size} bytes)`);
        } else {
          context.log(`[SP Upload] Verify FAILED: status ${verifyResult.status}`);
        }
      } catch (err) {
        context.log(`[SP Upload] Verify ERROR: ${err.message}`);
        // Upload succeeded but verify failed — still return success with verified=false
      }

      return {
        status: 200,
        jsonBody: {
          success: true,
          url: fileUrl,
          method,
          verified,
          timing_ms: Date.now() - t0,
          attempts,
        },
        headers: corsHeaders,
      };

    } catch (err) {
      context.log(`[SP Upload] FATAL: ${err.message}`);
      return {
        status: 500,
        jsonBody: {
          success: false,
          error: err.message,
          attempts,
          timing_ms: Date.now() - t0,
        },
        headers: corsHeaders,
      };
    }
  },
});
