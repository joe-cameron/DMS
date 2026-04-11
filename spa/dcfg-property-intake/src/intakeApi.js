/**
 * Intake API — Dataverse Web API client for the property intake portal.
 * Anonymous access, no Power Pages user session.
 * Falls back to localStorage when Dataverse is unavailable.
 */

// Toggle: set true when Power Pages site is provisioned and tables exist
const USE_DATAVERSE = true;

const API_BASE = '/_api';
let _csrfToken = null;

// ─── CSRF Token ───
async function getToken() {
  if (_csrfToken) return _csrfToken;
  try {
    const resp = await fetch('/', { credentials: 'same-origin' });
    const html = await resp.text();
    const match = html.match(/name="__RequestVerificationToken"[^>]*value="([^"]+)"/);
    if (match) { _csrfToken = match[1]; return _csrfToken; }
  } catch (e) { console.warn('CSRF token fetch failed:', e); }
  const el = document.querySelector('input[name="__RequestVerificationToken"]');
  if (el) { _csrfToken = el.value; return _csrfToken; }
  return null;
}

function invalidateToken() { _csrfToken = null; }

const HEADERS_READ = {
  'Accept': 'application/json',
  'OData-MaxVersion': '4.0',
  'OData-Version': '4.0',
};

async function apiGet(path) {
  const resp = await fetch(`${API_BASE}${path}`, { headers: HEADERS_READ, credentials: 'same-origin' });
  if (!resp.ok) throw new Error(`GET ${path}: ${resp.status}`);
  return resp.json();
}

async function apiPost(path, body) {
  const token = await getToken();
  const resp = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { ...HEADERS_READ, 'Content-Type': 'application/json', '__RequestVerificationToken': token },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
  if (resp.status === 401 || resp.status === 403) invalidateToken();
  if (!resp.ok) throw new Error(`POST ${path}: ${resp.status}`);
}

async function apiPatch(path, body) {
  const token = await getToken();
  const resp = await fetch(`${API_BASE}${path}`, {
    method: 'PATCH',
    headers: { ...HEADERS_READ, 'Content-Type': 'application/json', '__RequestVerificationToken': token },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
  if (resp.status === 401 || resp.status === 403) invalidateToken();
  if (!resp.ok) throw new Error(`PATCH ${path}: ${resp.status}`);
}

/** Retry a write operation after refreshing the CSRF token. */
async function retryWithFreshToken(fn) {
  try {
    return await fn();
  } catch (e) {
    invalidateToken();
    try { return await fn(); } catch (e2) { throw e2; }
  }
}

/** Sanitize string for OData filter (prevent injection) */
function sanitizeOData(val) {
  return val.replace(/'/g, "''");
}

// ─── Entity Sets (verify after table creation) ───
const ES = {
  sessions:     'dcfg_intake_sessions',
  properties:   'dcfg_property_intakes',
  fieldConfigs: 'dcfg_intake_field_configs',
  vendors:      'dcfg_intake_vendors',
  authUsers:    'dcfg_intake_authorized_users',
  locationTypes:'dcfg_location_types',
};

// ─── Record Locking ───
const LOCK_TIMEOUT_MS = 3 * 60 * 1000; // 3 minutes — auto-clears after inactivity

function getBrowserSessionId() {
  let id = sessionStorage.getItem('intake_browser_session');
  if (!id) {
    id = crypto.randomUUID();
    sessionStorage.setItem('intake_browser_session', id);
  }
  return id;
}

export async function acquireLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return { locked: true };
  const sessionId = getBrowserSessionId();
  try {
    const r = await apiGet(`/${ES.properties}(${propertyIntakeId})?$select=dcfg_locked_by,dcfg_locked_at`);
    const lockedBy = r?.dcfg_locked_by;
    const lockedAt = r?.dcfg_locked_at ? new Date(r.dcfg_locked_at) : null;
    if (!lockedBy || lockedBy === sessionId || (lockedAt && (Date.now() - lockedAt.getTime() > LOCK_TIMEOUT_MS))) {
      await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
        dcfg_locked_by: sessionId,
        dcfg_locked_at: new Date().toISOString(),
      });
      return { locked: true };
    }
    return { locked: false, lockedBy, lockedAt: lockedAt.toISOString() };
  } catch (e) {
    console.warn('acquireLock failed:', e);
    return { locked: true };
  }
}

export async function forceAcquireLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return { locked: true };
  const sessionId = getBrowserSessionId();
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      dcfg_locked_by: sessionId,
      dcfg_locked_at: new Date().toISOString(),
    });
    return { locked: true };
  } catch (e) {
    console.warn('forceAcquireLock failed:', e);
    return { locked: true };
  }
}

export async function refreshLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return;
  const sessionId = getBrowserSessionId();
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      dcfg_locked_by: sessionId,
      dcfg_locked_at: new Date().toISOString(),
    });
  } catch {}
}

export async function releaseLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return;
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      dcfg_locked_by: null,
      dcfg_locked_at: null,
    });
  } catch {}
}

export function releaseLockSync(propertyIntakeId) {
  if (!USE_DATAVERSE) return;
  const token = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
  fetch(`${API_BASE}/${ES.properties}(${propertyIntakeId})`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', '__RequestVerificationToken': token || '' },
    body: JSON.stringify({ dcfg_locked_by: null, dcfg_locked_at: null }),
    keepalive: true,
  }).catch(() => {});
}

// ─── Public API ───

export async function loadSession(code) {
  if (!USE_DATAVERSE) return null;
  const safeCode = sanitizeOData(code);
  try {
    const r = await apiGet(`/${ES.sessions}?$filter=dcfg_access_code eq '${safeCode}' and dcfg_active_flag eq true&$select=dcfg_intake_sessionid,dcfg_access_code,dcfg_provider_name,dcfg_provider_id,dcfg_expires_at,dcfg_status`);
    const sessions = r?.value ?? [];
    if (sessions.length === 0) return null;
    const s = sessions[0];
    if (s.dcfg_status === 100000002 || s.dcfg_status === 100000003) return null;
    if (new Date(s.dcfg_expires_at) < new Date()) return null;
    return s;
  } catch (e) {
    console.warn('loadSession failed, falling back to localStorage:', e);
    return null;
  }
}

export async function loadProperties(sessionId) {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.properties}?$filter=_dcfg_intake_session_value eq '${sessionId}' and dcfg_active_flag eq true&$orderby=dcfg_street_address asc`);
    return r?.value ?? [];
  } catch (e) {
    console.warn('loadProperties failed:', e);
    return null;
  }
}

export async function loadFieldConfig() {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.fieldConfigs}?$filter=dcfg_active_flag eq true&$select=dcfg_field_key,dcfg_visible,_dcfg_location_type_value`);
    return r?.value ?? [];
  } catch (e) {
    console.warn('loadFieldConfig failed:', e);
    return null;
  }
}

export async function loadLocationTypes() {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.locationTypes}?$select=dcfg_location_typeid,dcfg_name&$orderby=dcfg_name asc`);
    return r?.value ?? [];
  } catch (e) {
    console.warn('loadLocationTypes failed:', e);
    return null;
  }
}

export async function savePropertyBatch(propertyIntakeId, fields) {
  if (!USE_DATAVERSE) return false;
  try {
    await retryWithFreshToken(() =>
      apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
        ...fields,
        dcfg_last_modified_by_customer: new Date().toISOString(),
      })
    );
    return true;
  } catch (e) {
    console.warn('savePropertyBatch failed after retry:', e);
    return false;
  }
}

export async function loadVendors(sessionId) {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.vendors}?$filter=_dcfg_intake_session_value eq '${sessionId}' and dcfg_active_flag eq true`);
    return r?.value ?? [];
  } catch (e) { console.warn('loadVendors failed:', e); return null; }
}

export async function loadAuthUsers(sessionId) {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.authUsers}?$filter=_dcfg_intake_session_value eq '${sessionId}' and dcfg_active_flag eq true`);
    return r?.value ?? [];
  } catch (e) { console.warn('loadAuthUsers failed:', e); return null; }
}

export async function createVendor(sessionId, data) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPost(`/${ES.vendors}`, {
      ...data,
      dcfg_active_flag: true,
      'dcfg_intake_session@odata.bind': `/${ES.sessions}(${sessionId})`,
    });
    return true;
  } catch (e) { console.warn('createVendor failed:', e); return false; }
}

export async function createAuthUser(sessionId, data) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPost(`/${ES.authUsers}`, {
      ...data,
      dcfg_active_flag: true,
      'dcfg_intake_session@odata.bind': `/${ES.sessions}(${sessionId})`,
    });
    return true;
  } catch (e) { console.warn('createAuthUser failed:', e); return false; }
}

// ─── Category → doc_type picklist mapping ───
const DOC_TYPE_MAP = {
  'Fire Inspection Report': 100000000,
  'Generator Service Contract': 100000002,
  'Roof Warranty': 100000009,
};
const DOC_TYPE_OTHER = 100000010;

export async function createDocumentRequest(propertyId, category, fileName, base64Content, expiryDate) {
  if (!USE_DATAVERSE) return false;
  const docType = DOC_TYPE_MAP[category] || DOC_TYPE_OTHER;
  const notes = JSON.stringify({
    property_id: propertyId,
    doc_type: docType,
    file_name: fileName,
    file_content: base64Content,
    expiry_date: expiryDate || '',
  });
  try {
    await apiPost(`/dcfg_document_requests`, {
      dcfg_name: `${category} - ${fileName}`,
      dcfg_request_type: 100000002,
      dcfg_notes: notes,
      dcfg_requested_by: 'intake-portal',
      dcfg_status: 100000000,
    });
    return true;
  } catch (e) {
    console.warn('createDocumentRequest failed:', e);
    return false;
  }
}

export async function isOnline() {
  if (!USE_DATAVERSE) return false;
  try {
    await apiGet(`/${ES.locationTypes}?$top=1&$select=dcfg_location_typeid`);
    return true;
  } catch { return false; }
}

export { USE_DATAVERSE, ES };
