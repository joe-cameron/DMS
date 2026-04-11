# DCFG SPA Full Test Battery — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full unit + E2E test coverage for the DCFG Power Pages SPA (dcfg-shell).

**Architecture:** Vitest unit tests (mocked fetch, jsdom) for all logic/hooks/components. Playwright E2E tests against dmms1.powerappsportals.com for screen smoke + CRUD flows with self-cleaning soft-delete. Tests live inside `spa/` (write access granted by operator).

**Tech Stack:** Vitest 1.4 + @testing-library/react 12 + jsdom 24 (unit), Playwright 1.52 + TypeScript (E2E)

**Spec:** `docs/superpowers/specs/2026-03-27-spa-test-battery-design.md`

---

## Chunk 1: Vitest Core — portalApi Tests

### Task 1: portalApi.test.js — CSRF + HTTP Methods + Helpers

**Files:**
- Create: `spa/dcfg-shell/tests/core/portalApi.test.js`
- Read: `spa/dcfg-shell/src/portalApi.js`

- [ ] **Step 1: Create the test file with all test cases**

```javascript
// tests/core/portalApi.test.js
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  getToken, invalidateToken, ApiError,
  apiGet, apiPost, apiPostReturn, apiPatch, apiDelete,
  odataBind, bind, formatCurrency, formatDate,
  EntitySets, resolveTemplate,
  ContractStatus, ContractStatusLabel, ContractFamily, ContractFamilyLabel,
  ContractType, ContractTypeLabel, AlertStatus, AlertStatusLabel,
} from '../../src/portalApi.js';

// ─── Helper: mock fetch ──────────────────────────────────────────────────────
function mockFetch(response) {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => response,
    text: async () => JSON.stringify(response),
    headers: new Headers(),
    ...response._overrides,
  });
}

function mockFetchError(status, errorBody = {}) {
  return vi.fn().mockResolvedValue({
    ok: false,
    status,
    json: async () => ({ error: { message: errorBody.message || 'Error' } }),
    text: async () => JSON.stringify(errorBody),
    headers: new Headers(),
  });
}

// ─── CSRF Token ──────────────────────────────────────────────────────────────
describe('getToken', () => {
  beforeEach(() => {
    invalidateToken();
    delete window.shell;
    delete window.top;
    document.body.innerHTML = '';
  });

  it('reads token from window.shell.getTokenDeferred()', async () => {
    window.shell = { getTokenDeferred: () => Promise.resolve('tok-shell') };
    const token = await getToken();
    expect(token).toBe('tok-shell');
  });

  it('caches token on second call — no second resolution', async () => {
    let callCount = 0;
    window.shell = {
      getTokenDeferred: () => { callCount++; return Promise.resolve('tok-cached'); }
    };
    await getToken();
    await getToken();
    expect(callCount).toBe(1);
  });

  it('falls back to DOM input element', async () => {
    document.body.innerHTML = '<input name="__RequestVerificationToken" value="tok-dom" />';
    // Make shell fail
    window.shell = { getTokenDeferred: () => Promise.reject('no') };
    // Make fetch fail
    global.fetch = vi.fn().mockRejectedValue(new Error('network'));
    const token = await getToken();
    expect(token).toBe('tok-dom');
  });

  it('falls back to fetching / and parsing HTML', async () => {
    window.shell = { getTokenDeferred: () => Promise.reject('no') };
    global.fetch = vi.fn().mockResolvedValue({
      text: async () => '<input name="__RequestVerificationToken" value="tok-fetch" />',
    });
    const token = await getToken();
    expect(token).toBe('tok-fetch');
  });

  it('throws when all 3 sources fail', async () => {
    window.shell = { getTokenDeferred: () => Promise.reject('no') };
    global.fetch = vi.fn().mockRejectedValue(new Error('no'));
    document.body.innerHTML = '';
    await expect(getToken()).rejects.toThrow(/CSRF token unavailable/);
  });

  it('invalidateToken clears cache', async () => {
    window.shell = { getTokenDeferred: () => Promise.resolve('tok-1') };
    await getToken();
    invalidateToken();
    window.shell = { getTokenDeferred: () => Promise.resolve('tok-2') };
    const token = await getToken();
    expect(token).toBe('tok-2');
  });
});

// ─── apiGet ──────────────────────────────────────────────────────────────────
describe('apiGet', () => {
  it('sends GET with OData headers to /_api + path', async () => {
    global.fetch = mockFetch({ value: [] });
    await apiGet('/dcfg_contracts');
    const [url, opts] = global.fetch.mock.calls[0];
    expect(url).toBe('/_api/dcfg_contracts');
    expect(opts.headers['OData-Version']).toBe('4.0');
    expect(opts.headers.Accept).toBe('application/json');
    expect(opts.credentials).toBe('same-origin');
  });

  it('passes through absolute URLs unchanged', async () => {
    global.fetch = mockFetch({ value: [] });
    await apiGet('https://org.crm.dynamics.com/api/data/v9.2/dcfg_contracts');
    expect(global.fetch.mock.calls[0][0]).toBe('https://org.crm.dynamics.com/api/data/v9.2/dcfg_contracts');
  });

  it('returns parsed JSON on success', async () => {
    global.fetch = mockFetch({ value: [{ dcfg_contractid: 'abc' }] });
    const result = await apiGet('/dcfg_contracts');
    expect(result.value[0].dcfg_contractid).toBe('abc');
  });

  it('throws ApiError on non-200 with Dataverse error message', async () => {
    global.fetch = mockFetchError(404, { message: 'Resource not found' });
    const err = await apiGet('/dcfg_contracts').catch(e => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(404);
    expect(err.message).toContain('Resource not found');
  });

  it('propagates network errors from fetch', async () => {
    global.fetch = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
    await expect(apiGet('/dcfg_contracts')).rejects.toThrow('Failed to fetch');
  });
});

// ─── apiPost ─────────────────────────────────────────────────────────────────
describe('apiPost', () => {
  beforeEach(() => {
    invalidateToken();
    window.shell = { getTokenDeferred: () => Promise.resolve('csrf-tok') };
  });

  it('sends POST with CSRF token and trimmed body', async () => {
    global.fetch = vi.fn()
      .mockResolvedValueOnce(Promise.resolve('csrf-tok')) // getToken may call fetch
      .mockResolvedValue({ ok: true, status: 200, json: async () => ({}) });
    // Override: direct mock
    global.fetch = mockFetch({});
    // Need token first
    invalidateToken();
    window.shell = { getTokenDeferred: () => Promise.resolve('csrf-tok') };

    await apiPost('/dcfg_contracts', { dcfg_client_name: '  Acme Corp  ', dcfg_contract_fee: 5000 });
    const [url, opts] = global.fetch.mock.calls[0];
    expect(url).toBe('/_api/dcfg_contracts');
    expect(opts.method).toBe('POST');
    expect(opts.headers['__RequestVerificationToken']).toBe('csrf-tok');
    const body = JSON.parse(opts.body);
    expect(body.dcfg_client_name).toBe('Acme Corp'); // trimmed
    expect(body.dcfg_contract_fee).toBe(5000); // number unchanged
  });

  it('invalidates token on 401', async () => {
    global.fetch = mockFetchError(401);
    await expect(apiPost('/dcfg_contracts', {})).rejects.toThrow();
    // Token cache should be cleared — next getToken should re-resolve
    window.shell = { getTokenDeferred: () => Promise.resolve('new-tok') };
    const tok = await getToken();
    expect(tok).toBe('new-tok');
  });

  it('invalidates token on 403', async () => {
    global.fetch = mockFetchError(403);
    await expect(apiPost('/dcfg_contracts', {})).rejects.toThrow();
    window.shell = { getTokenDeferred: () => Promise.resolve('new-tok') };
    const tok = await getToken();
    expect(tok).toBe('new-tok');
  });

  it('throws ApiError with Dataverse message', async () => {
    global.fetch = mockFetchError(400, { message: 'Bad field' });
    const err = await apiPost('/dcfg_contracts', {}).catch(e => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(400);
  });

  it('handles null body without throwing (trimBody null path)', async () => {
    global.fetch = mockFetch({});
    await apiPost('/dcfg_contracts', null);
    const body = global.fetch.mock.calls[0][1].body;
    expect(body).toBe('null');
  });
});

// ─── apiPostReturn ───────────────────────────────────────────────────────────
describe('apiPostReturn', () => {
  beforeEach(() => {
    invalidateToken();
    window.shell = { getTokenDeferred: () => Promise.resolve('csrf-tok') };
  });

  it('sends Prefer: return=representation header', async () => {
    global.fetch = mockFetch({ dcfg_msaid: 'new-id' });
    await apiPostReturn('/dcfg_msas', { dcfg_name: 'Test MSA' });
    const opts = global.fetch.mock.calls[0][1];
    expect(opts.headers.Prefer).toBe('return=representation');
  });

  it('handles 204 by reading OData-EntityId header and fetching record', async () => {
    const headers204 = new Headers();
    headers204.set('OData-EntityId', 'https://org.crm.dynamics.com/api/data/v9.2/dcfg_msas(abc-123)');
    let callNum = 0;
    global.fetch = vi.fn().mockImplementation(async () => {
      callNum++;
      if (callNum === 1) {
        // The POST returns 204
        return { ok: true, status: 204, headers: headers204, json: async () => null };
      }
      // The follow-up GET
      return { ok: true, status: 200, json: async () => ({ dcfg_msaid: 'abc-123', dcfg_name: 'Fetched' }), headers: new Headers({ 'content-type': 'application/json' }) };
    });
    const result = await apiPostReturn('/dcfg_msas', {});
    expect(result.dcfg_msaid).toBe('abc-123');
  });

  it('returns empty object when no OData-EntityId on 204', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 204, headers: new Headers(), json: async () => null,
    });
    const result = await apiPostReturn('/dcfg_msas', {});
    expect(result).toEqual({});
  });
});

// ─── apiPatch ────────────────────────────────────────────────────────────────
describe('apiPatch', () => {
  beforeEach(() => {
    invalidateToken();
    window.shell = { getTokenDeferred: () => Promise.resolve('csrf-tok') };
  });

  it('sends PATCH with correct method and trimmed body', async () => {
    global.fetch = mockFetch({});
    await apiPatch('/dcfg_contracts(guid-1)', { dcfg_client_name: '  Updated  ' });
    const opts = global.fetch.mock.calls[0][1];
    expect(opts.method).toBe('PATCH');
    expect(JSON.parse(opts.body).dcfg_client_name).toBe('Updated');
  });
});

// ─── apiDelete ───────────────────────────────────────────────────────────────
describe('apiDelete', () => {
  beforeEach(() => {
    invalidateToken();
    window.shell = { getTokenDeferred: () => Promise.resolve('csrf-tok') };
  });

  it('sends DELETE with no body', async () => {
    global.fetch = mockFetch({});
    await apiDelete('/dcfg_contracts(guid-1)');
    const opts = global.fetch.mock.calls[0][1];
    expect(opts.method).toBe('DELETE');
    expect(opts.body).toBeUndefined();
  });
});

// ─── odataBind ───────────────────────────────────────────────────────────────
describe('odataBind / bind', () => {
  it('2-arg form returns /entitySet(guid) string', () => {
    expect(odataBind('dcfg_customers', 'abc-123')).toBe('/dcfg_customers(abc-123)');
  });

  it('3-arg form returns { field@odata.bind: /entitySet(guid) } object', () => {
    const result = odataBind('dcfg_customer_id', 'dcfg_customers', 'abc-123');
    expect(result).toEqual({ 'dcfg_customer_id@odata.bind': '/dcfg_customers(abc-123)' });
  });

  it('bind is an alias for odataBind', () => {
    expect(bind).toBe(odataBind);
  });
});

// ─── formatCurrency ──────────────────────────────────────────────────────────
describe('formatCurrency', () => {
  it('formats number to USD string', () => {
    expect(formatCurrency(1234.5)).toBe('$1,234.50');
  });

  it('returns $0.00 for NaN', () => {
    expect(formatCurrency('not-a-number')).toBe('$0.00');
  });

  it('returns $0.00 for null', () => {
    expect(formatCurrency(null)).toBe('$0.00');
  });

  it('handles zero', () => {
    expect(formatCurrency(0)).toBe('$0.00');
  });
});

// ─── formatDate ──────────────────────────────────────────────────────────────
describe('formatDate', () => {
  it('formats ISO string to short date', () => {
    const result = formatDate('2026-03-15T00:00:00Z');
    expect(result).toMatch(/Mar\s+15,\s+2026/);
  });

  it('returns empty string for null', () => {
    expect(formatDate(null)).toBe('');
  });

  it('returns empty string for undefined', () => {
    expect(formatDate(undefined)).toBe('');
  });
});

// ─── EntitySets ──────────────────────────────────────────────────────────────
describe('EntitySets', () => {
  it('properties is dcfg_properties (not dcfg_propertys)', () => {
    expect(EntitySets.properties).toBe('dcfg_properties');
  });

  it('has 37 entity sets, all non-empty strings', () => {
    const entries = Object.entries(EntitySets);
    expect(entries.length).toBe(37);
    for (const [key, val] of entries) {
      expect(typeof val).toBe('string');
      expect(val.length).toBeGreaterThan(0);
    }
  });

  it('has no duplicate entity set values', () => {
    const values = Object.values(EntitySets);
    expect(new Set(values).size).toBe(values.length);
  });
});

// ─── Enum completeness ───────────────────────────────────────────────────────
describe('Enum label maps have no gaps', () => {
  it('ContractStatus ↔ ContractStatusLabel', () => {
    for (const val of Object.values(ContractStatus)) {
      expect(ContractStatusLabel[val]).toBeDefined();
    }
  });

  it('ContractFamily ↔ ContractFamilyLabel', () => {
    for (const val of Object.values(ContractFamily)) {
      expect(ContractFamilyLabel[val]).toBeDefined();
    }
  });

  it('ContractType ↔ ContractTypeLabel', () => {
    for (const val of Object.values(ContractType)) {
      expect(ContractTypeLabel[val]).toBeDefined();
    }
  });

  it('AlertStatus ↔ AlertStatusLabel', () => {
    for (const val of Object.values(AlertStatus)) {
      expect(AlertStatusLabel[val]).toBeDefined();
    }
  });
});

// ─── resolveTemplate ─────────────────────────────────────────────────────────
describe('resolveTemplate', () => {
  it('resolves all 6 family/type combos to .docx filenames', () => {
    for (const fam of Object.values(ContractFamily)) {
      for (const typ of Object.values(ContractType)) {
        const result = resolveTemplate(fam, typ);
        expect(result).toMatch(/\.docx$/);
      }
    }
  });

  it('returns null for unknown combo', () => {
    expect(resolveTemplate(999, 999)).toBeNull();
  });
});
```

- [ ] **Step 2: Run the tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/core/portalApi.test.js`
Expected: All tests PASS (testing existing code, not TDD for new code)

- [ ] **Step 3: Commit**

```bash
cd C:\DCFG\spa\dcfg-shell
git add tests/core/portalApi.test.js
git commit -m "test: add portalApi unit tests — CSRF, HTTP methods, helpers, entity sets, enums"
```

---

### Task 2: portalApi-config.test.js — Config Loading

**Files:**
- Create: `spa/dcfg-shell/tests/core/portalApi-config.test.js`

- [ ] **Step 1: Create test file**

```javascript
// tests/core/portalApi-config.test.js
// NOTE: loadConfig and getEnvVar use module-level cache. Each test must
// re-import the module to get fresh state, or call the internal reset.
// Since there's no exported reset, we use vi.resetModules() between tests.
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('loadConfig', () => {
  let loadConfig, getEnvVar, apiGet;

  beforeEach(async () => {
    vi.resetModules();
    // Mock getToken so apiGet works
    global.fetch = vi.fn();
    const mod = await import('../../src/portalApi.js');
    loadConfig = mod.loadConfig;
    getEnvVar = mod.getEnvVar;
    // Need to mock window.shell for CSRF
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
  });

  it('fetches dcfg_configs with active filter', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({
        value: [
          { dcfg_key: 'dcfg_flow_docgen_url', dcfg_value: 'https://flow/docgen' },
          { dcfg_key: 'dcfg_sp_site_url', dcfg_value: 'https://sp/site' },
        ],
      }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });

    const config = await loadConfig();
    expect(config.dcfg_flow_docgen_url).toBe('https://flow/docgen');
    expect(config.dcfg_sp_site_url).toBe('https://sp/site');
    expect(global.fetch.mock.calls[0][0]).toContain('dcfg_configs');
    expect(global.fetch.mock.calls[0][0]).toContain('dcfg_active');
  });

  it('caches on second call — no second fetch', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ value: [{ dcfg_key: 'k', dcfg_value: 'v' }] }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });

    await loadConfig();
    await loadConfig();
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('returns empty map on fetch failure', async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error('network'));
    const config = await loadConfig();
    expect(config).toEqual({});
  });
});

describe('getEnvVar', () => {
  let loadConfig, getEnvVar;

  beforeEach(async () => {
    vi.resetModules();
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ value: [{ dcfg_key: 'mykey', dcfg_value: 'myval' }] }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });
    const mod = await import('../../src/portalApi.js');
    loadConfig = mod.loadConfig;
    getEnvVar = mod.getEnvVar;
    await loadConfig();
  });

  it('returns value from cache', () => {
    expect(getEnvVar('mykey')).toBe('myval');
  });

  it('returns null for missing key', () => {
    expect(getEnvVar('nonexistent')).toBeNull();
  });

  it('returns null and warns when config not loaded', async () => {
    vi.resetModules();
    const mod2 = await import('../../src/portalApi.js');
    expect(mod2.getEnvVar('anything')).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/core/portalApi-config.test.js`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/core/portalApi-config.test.js
git commit -m "test: add config loading + getEnvVar tests"
```

---

### Task 3: portalApi-audit.test.js — Audit Log + Hooks

**Files:**
- Create: `spa/dcfg-shell/tests/core/portalApi-audit.test.js`

- [ ] **Step 1: Create test file**

```javascript
// tests/core/portalApi-audit.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { writeAuditLog, onAuditEvent, EntitySets } from '../../src/portalApi.js';

describe('writeAuditLog', () => {
  beforeEach(() => {
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({}) });
  });

  it('posts to dcfg_audit_logs with dcfg_ prefixed columns', async () => {
    await writeAuditLog({
      targetTable: 'dcfg_contracts',
      targetRecordId: 'rec-001',
      actionType: 100000000, // Generated
      performedBy: 'admin@test.com',
      newValue: 'Document generated',
    });

    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body.dcfg_target_table).toBe('dcfg_contracts');
    expect(body.dcfg_target_record_id).toBe('rec-001');
    expect(body.dcfg_action_type).toBe(100000000);
    expect(body.dcfg_performed_by).toBe('admin@test.com');
    expect(body.dcfg_performed_at).toBeDefined();
    expect(body.dcfg_new_value).toBe('Document generated');
  });

  it('accepts dcfg_ prefixed keys directly', async () => {
    await writeAuditLog({
      dcfg_target_table: 'dcfg_msas',
      dcfg_target_record_id: 'rec-002',
      dcfg_action_type: 100000001,
      dcfg_performed_by: 'mgr@test.com',
    });

    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body.dcfg_target_table).toBe('dcfg_msas');
  });

  it('binds related contract ID via @odata.bind', async () => {
    await writeAuditLog({
      targetTable: 'dcfg_contracts',
      targetRecordId: 'rec-001',
      actionType: 100000000,
      performedBy: 'admin@test.com',
      relatedContractId: 'con-guid-1',
    });

    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body['dcfg_related_contract_id@odata.bind']).toBe('/dcfg_contracts(con-guid-1)');
  });

  it('includes optional fields when provided', async () => {
    await writeAuditLog({
      targetTable: 'dcfg_contracts',
      targetRecordId: 'r',
      actionType: 100000003,
      performedBy: 'a@b.com',
      oldValue: 'old',
      reason: 'voided by request',
    });

    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body.dcfg_old_value).toBe('old');
    expect(body.dcfg_reason).toBe('voided by request');
  });

  it('only calls POST — never PATCH or DELETE', async () => {
    await writeAuditLog({
      targetTable: 'dcfg_contracts', targetRecordId: 'r',
      actionType: 100000010, performedBy: 'a@b.com',
    });
    const method = global.fetch.mock.calls[0][1].method;
    expect(method).toBe('POST');
  });
});

describe('onAuditEvent', () => {
  beforeEach(() => {
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({}) });
  });

  it('fires listener with raw + normalized payload on writeAuditLog', async () => {
    const spy = vi.fn();
    const unsub = onAuditEvent(spy);

    await writeAuditLog({
      targetTable: 'dcfg_contracts', targetRecordId: 'r',
      actionType: 100000000, performedBy: 'a@b.com',
    });

    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0][0]).toHaveProperty('raw');
    expect(spy.mock.calls[0][0]).toHaveProperty('normalized');
    unsub();
  });

  it('unsubscribe stops future calls', async () => {
    const spy = vi.fn();
    const unsub = onAuditEvent(spy);
    unsub();

    await writeAuditLog({
      targetTable: 'dcfg_contracts', targetRecordId: 'r',
      actionType: 100000000, performedBy: 'a@b.com',
    });

    expect(spy).not.toHaveBeenCalled();
  });

  it('listener errors do not break audit write', async () => {
    const unsub = onAuditEvent(() => { throw new Error('boom'); });

    // Should not throw — the audit write should still succeed
    await expect(writeAuditLog({
      targetTable: 'dcfg_contracts', targetRecordId: 'r',
      actionType: 100000000, performedBy: 'a@b.com',
    })).resolves.not.toThrow();

    unsub(); // Clean up to avoid leaking into other tests
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/core/portalApi-audit.test.js`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/core/portalApi-audit.test.js
git commit -m "test: add writeAuditLog + onAuditEvent tests"
```

---

### Task 4: portalApi-flow.test.js — callFlow

**Files:**
- Create: `spa/dcfg-shell/tests/core/portalApi-flow.test.js`

- [ ] **Step 1: Create test file**

```javascript
// tests/core/portalApi-flow.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('callFlow', () => {
  let callFlow, loadConfig;

  beforeEach(async () => {
    vi.resetModules();
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
    // Pre-load config with a flow URL
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({
        value: [{ dcfg_key: 'dcfg_flow_docgen_url', dcfg_value: 'https://flow.example.com/docgen' }],
      }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });
    const mod = await import('../../src/portalApi.js');
    callFlow = mod.callFlow;
    loadConfig = mod.loadConfig;
    await loadConfig();
  });

  it('resolves env var name to URL and sends POST', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ result: 'ok' }),
    });
    const result = await callFlow('dcfg_flow_docgen_url', { template: 'test' });
    expect(global.fetch.mock.calls[0][0]).toBe('https://flow.example.com/docgen');
    expect(global.fetch.mock.calls[0][1].method).toBe('POST');
    expect(result.result).toBe('ok');
  });

  it('accepts direct URL', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => ({}),
    });
    await callFlow('https://direct.flow.com/run', {});
    expect(global.fetch.mock.calls[0][0]).toBe('https://direct.flow.com/run');
  });

  it('throws when env var not found', async () => {
    await expect(callFlow('nonexistent_key', {})).rejects.toThrow(/Flow URL not found/);
  });

  it('throws on non-200 response', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: false, status: 500, text: async () => 'Internal error',
    });
    await expect(callFlow('dcfg_flow_docgen_url', {})).rejects.toThrow(/500/);
  });

  it('returns null when response body is not JSON', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => { throw new Error('no json'); },
    });
    const result = await callFlow('dcfg_flow_docgen_url', {});
    expect(result).toBeNull();
  });
});

describe('createDocumentRequest', () => {
  let createDocumentRequest;

  beforeEach(async () => {
    vi.resetModules();
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
    // Pre-load config
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ value: [] }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });
    const mod = await import('../../src/portalApi.js');
    createDocumentRequest = mod.createDocumentRequest;
    await mod.loadConfig();
  });

  it('posts to dcfg_document_requests with Pending status', async () => {
    // Mock apiPostReturn response (204 path)
    const headers204 = new Headers();
    headers204.set('OData-EntityId', 'https://org/api/data/v9.2/dcfg_document_requests(new-id)');
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 204, headers: headers204, json: async () => null,
    });

    await createDocumentRequest({
      requestedBy: 'admin@test.com',
      contractId: 'con-1',
      templateId: 'tmpl-1',
      customerId: 'cust-1',
    });

    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body.dcfg_status).toBe(100000000); // DocRequestStatus.Pending
    expect(body.dcfg_requested_by).toBe('admin@test.com');
    expect(body['dcfg_contract_id@odata.bind']).toBe('/dcfg_contracts(con-1)');
    expect(body['dcfg_template_id@odata.bind']).toBe('/dcfg_document_templates(tmpl-1)');
    expect(body['dcfg_customer_id@odata.bind']).toBe('/dcfg_customers(cust-1)');
  });

  it('omits @odata.bind keys when IDs not provided', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ dcfg_document_requestid: 'new' }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });

    await createDocumentRequest({ requestedBy: 'a@b.com' });
    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body['dcfg_contract_id@odata.bind']).toBeUndefined();
    expect(body['dcfg_msa_id@odata.bind']).toBeUndefined();
  });

  it('binds MSA ID when provided', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({}),
      headers: new Headers({ 'content-type': 'application/json' }),
    });

    await createDocumentRequest({ requestedBy: 'a@b.com', msaId: 'msa-1' });
    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body['dcfg_msa_id@odata.bind']).toBe('/dcfg_msas(msa-1)');
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/core/portalApi-flow.test.js`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/core/portalApi-flow.test.js
git commit -m "test: add callFlow tests"
```

---

## Chunk 2: Vitest Hooks

### Task 5: useTableControls.test.js

**Files:**
- Create: `spa/dcfg-shell/tests/hooks/useTableControls.test.js`
- Read: `spa/dcfg-shell/src/useTableControls.jsx`

- [ ] **Step 1: Create test file**

```javascript
// tests/hooks/useTableControls.test.js
import { describe, it, expect } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useTableControls } from '../../src/useTableControls.jsx';

const ROWS = [
  { dcfg_name: 'Charlie', dcfg_status: 'Active', _customer: { dcfg_display_name: 'Acme' } },
  { dcfg_name: 'Alpha',   dcfg_status: 'Draft',  _customer: { dcfg_display_name: 'Beta' } },
  { dcfg_name: 'Bravo',   dcfg_status: 'Active', _customer: { dcfg_display_name: 'Gamma' } },
];

describe('useTableControls', () => {
  it('sorts by defaultSort ascending on first render', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { defaultSort: 'dcfg_name' })
    );
    expect(result.current.filtered[0].dcfg_name).toBe('Alpha');
    expect(result.current.filtered[2].dcfg_name).toBe('Charlie');
  });

  it('toggleSort on same column reverses direction', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { defaultSort: 'dcfg_name' })
    );
    act(() => result.current.toggleSort('dcfg_name'));
    expect(result.current.sortDir).toBe('desc');
    expect(result.current.filtered[0].dcfg_name).toBe('Charlie');
  });

  it('toggleSort on different column sorts ascending', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { defaultSort: 'dcfg_name' })
    );
    act(() => result.current.toggleSort('dcfg_status'));
    expect(result.current.sortCol).toBe('dcfg_status');
    expect(result.current.sortDir).toBe('asc');
  });

  it('search filters rows by searchFields', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { searchFields: ['dcfg_name', 'dcfg_status'] })
    );
    act(() => result.current.setSearchTerm('active'));
    expect(result.current.filtered.length).toBe(2);
  });

  it('search is case-insensitive', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { searchFields: ['dcfg_name'] })
    );
    act(() => result.current.setSearchTerm('ALPHA'));
    expect(result.current.filtered.length).toBe(1);
  });

  it('supports dot-notation for expanded entities', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { searchFields: ['_customer.dcfg_display_name'] })
    );
    act(() => result.current.setSearchTerm('Acme'));
    expect(result.current.filtered.length).toBe(1);
    expect(result.current.filtered[0].dcfg_name).toBe('Charlie');
  });

  it('returns all rows when search term is empty', () => {
    const { result } = renderHook(() =>
      useTableControls(ROWS, { searchFields: ['dcfg_name'] })
    );
    act(() => result.current.setSearchTerm(''));
    expect(result.current.filtered.length).toBe(3);
  });

  it('handles null rows gracefully', () => {
    const { result } = renderHook(() =>
      useTableControls(null, { defaultSort: 'dcfg_name' })
    );
    expect(result.current.filtered).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/hooks/useTableControls.test.js`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/hooks/useTableControls.test.js
git commit -m "test: add useTableControls hook tests"
```

---

### Task 6: usePortalUser.test.jsx

**Files:**
- Create: `spa/dcfg-shell/tests/hooks/usePortalUser.test.jsx`
- Read: `spa/dcfg-shell/src/usePortalUser.jsx`

- [ ] **Step 1: Create test file**

```jsx
// tests/hooks/usePortalUser.test.jsx
import { describe, it, expect, beforeEach } from 'vitest';
import React from 'react';
import { renderHook } from '@testing-library/react';
import { PortalUserProvider, usePortalUser } from '../../src/usePortalUser.jsx';

function wrapper({ children }) {
  return <PortalUserProvider>{children}</PortalUserProvider>;
}

describe('usePortalUser', () => {
  beforeEach(() => {
    delete window.Microsoft;
    delete window.__dcfgUser; // Clear setup.js default to avoid interference
  });

  it('reads user from window.Microsoft.Dynamic365.Portal.User', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'admin@test.com', userName: 'admin',
      firstName: 'Test', lastName: 'Admin', roles: ['DCFG_Admin'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.user.isAuthenticated).toBe(true);
    expect(result.current.user.email).toBe('admin@test.com');
    expect(result.current.user.name).toBe('Test Admin');
  });

  it('isAdmin() returns true for DCFG_Admin', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com', roles: ['DCFG_Admin'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.isAdmin()).toBe(true);
  });

  it('isAdmin() returns false for DCFG_Manager', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com', roles: ['DCFG_Manager'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.isAdmin()).toBe(false);
  });

  it('isManager() returns true for DCFG_Admin (Admin ⊃ Manager)', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com', roles: ['DCFG_Admin'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.isManager()).toBe(true);
  });

  it('isManager() returns true for DCFG_Manager', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com', roles: ['DCFG_Manager'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.isManager()).toBe(true);
  });

  it('isManager() returns false for DCFG_Viewer', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com', roles: ['DCFG_Viewer'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.isManager()).toBe(false);
  });

  it('hasRole matches exact role name', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com', roles: ['DCFG_Admin', 'DCFG_Custom'],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.hasRole('DCFG_Custom')).toBe(true);
    expect(result.current.hasRole('NonExistent')).toBe(false);
  });

  it('handles role objects with .name property', () => {
    window.Microsoft = { Dynamic365: { Portal: { User: {
      contactId: 'c-1', email: 'a@b.com',
      roles: [{ name: 'DCFG_Admin', id: 'role-1' }],
    }}}};
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.isAdmin()).toBe(true);
  });

  it('returns unauthenticated user when Portal.User is absent', () => {
    // No window.Microsoft set
    const { result } = renderHook(() => usePortalUser(), { wrapper });
    expect(result.current.user.isAuthenticated).toBe(false);
    expect(result.current.user.roles).toEqual([]);
  });

  it('throws when used outside provider', () => {
    expect(() => {
      renderHook(() => usePortalUser());
    }).toThrow(/PortalUserProvider/);
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/hooks/usePortalUser.test.jsx`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/hooks/usePortalUser.test.jsx
git commit -m "test: add usePortalUser hook tests — roles, auth, provider"
```

---

### Task 7: toast.test.jsx

**Files:**
- Create: `spa/dcfg-shell/tests/hooks/toast.test.jsx`
- Read: `spa/dcfg-shell/src/Toast.jsx`

- [ ] **Step 1: Create test file**

```jsx
// tests/hooks/toast.test.jsx
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import React from 'react';
import { render, screen, act } from '@testing-library/react';
import { ToastProvider, useToast } from '../../src/Toast.jsx';

// Test component that exposes toast controls
function ToastTrigger({ type, message }) {
  const { show, dismiss } = useToast();
  return (
    <>
      <button onClick={() => show(type, message)}>Show</button>
      <button onClick={dismiss}>Dismiss</button>
    </>
  );
}

describe('Toast', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('show() renders toast with message text', () => {
    render(
      <ToastProvider>
        <ToastTrigger type="ok" message="Saved!" />
      </ToastProvider>
    );
    act(() => screen.getByText('Show').click());
    expect(screen.getByText('Saved!')).toBeDefined();
  });

  it('ok/warn/info auto-dismiss at 4 seconds', () => {
    render(
      <ToastProvider>
        <ToastTrigger type="ok" message="Done" />
      </ToastProvider>
    );
    act(() => screen.getByText('Show').click());
    expect(screen.getByText('Done')).toBeDefined();
    act(() => vi.advanceTimersByTime(4100));
    expect(screen.queryByText('Done')).toBeNull();
  });

  it('err auto-dismisses at 5.5 seconds', () => {
    render(
      <ToastProvider>
        <ToastTrigger type="err" message="Failed" />
      </ToastProvider>
    );
    act(() => screen.getByText('Show').click());
    // Still visible at 4s
    act(() => vi.advanceTimersByTime(4100));
    expect(screen.getByText('Failed')).toBeDefined();
    // Gone at 5.5s
    act(() => vi.advanceTimersByTime(1500));
    expect(screen.queryByText('Failed')).toBeNull();
  });

  it('dismiss() removes toast immediately', () => {
    render(
      <ToastProvider>
        <ToastTrigger type="ok" message="Bye" />
      </ToastProvider>
    );
    act(() => screen.getByText('Show').click());
    expect(screen.getByText('Bye')).toBeDefined();
    act(() => screen.getByText('Dismiss').click());
    expect(screen.queryByText('Bye')).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/hooks/toast.test.jsx`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/hooks/toast.test.jsx
git commit -m "test: add Toast hook tests — show, auto-dismiss, manual dismiss"
```

---

## Chunk 3: Vitest Components

### Task 8: RoleGuard.test.jsx

**Files:**
- Create: `spa/dcfg-shell/tests/components/RoleGuard.test.jsx`

- [ ] **Step 1: Create test file**

```jsx
// tests/components/RoleGuard.test.jsx
import { describe, it, expect, beforeEach } from 'vitest';
import React from 'react';
import { render, screen } from '@testing-library/react';
import { PortalUserProvider } from '../../src/usePortalUser.jsx';
import RoleGuard from '../../src/RoleGuard.jsx';

function setUser(roles) {
  window.Microsoft = { Dynamic365: { Portal: { User: {
    contactId: 'c-1', email: 'a@b.com', roles,
  }}}};
}

function renderGuard(require) {
  return render(
    <PortalUserProvider>
      <RoleGuard require={require}>
        <span data-testid="protected">Secret Content</span>
      </RoleGuard>
    </PortalUserProvider>
  );
}

describe('RoleGuard', () => {
  beforeEach(() => { delete window.Microsoft; });

  it('admin user sees admin-guarded content', () => {
    setUser(['DCFG_Admin']);
    renderGuard('admin');
    expect(screen.getByTestId('protected')).toBeDefined();
  });

  it('viewer cannot see admin-guarded content', () => {
    setUser(['DCFG_Viewer']);
    renderGuard('admin');
    expect(screen.queryByTestId('protected')).toBeNull();
  });

  it('manager user sees manager-guarded content', () => {
    setUser(['DCFG_Manager']);
    renderGuard('manager');
    expect(screen.getByTestId('protected')).toBeDefined();
  });

  it('admin user also sees manager-guarded content', () => {
    setUser(['DCFG_Admin']);
    renderGuard('manager');
    expect(screen.getByTestId('protected')).toBeDefined();
  });

  it('unauthenticated user sees nothing', () => {
    // No window.Microsoft
    renderGuard('viewer');
    expect(screen.queryByTestId('protected')).toBeNull();
  });

  it('elements are removed from DOM, not display:none (C-06)', () => {
    setUser(['DCFG_Viewer']);
    const { container } = renderGuard('admin');
    // The span should not exist at all — not hidden, not disabled
    expect(container.querySelector('[data-testid="protected"]')).toBeNull();
  });

  it('unknown require value defaults to deny', () => {
    setUser(['DCFG_Admin']);
    renderGuard('superadmin');
    expect(screen.queryByTestId('protected')).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/components/RoleGuard.test.jsx`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/components/RoleGuard.test.jsx
git commit -m "test: add RoleGuard component tests — DOM suppression (C-06)"
```

---

### Task 9: FieldName.test.jsx

**Files:**
- Create: `spa/dcfg-shell/tests/components/FieldName.test.jsx`
- Read: `spa/dcfg-shell/src/FieldName.jsx`, `spa/dcfg-shell/src/debug/index.js`

- [ ] **Step 1: Create test file**

```jsx
// tests/components/FieldName.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import React from 'react';
import { render, screen } from '@testing-library/react';

// Mock the debug module — controls isDebugActive return
vi.mock('../../src/debug/index.js', () => ({
  isDebugActive: vi.fn(() => false),
  initDebug: vi.fn(),
  getDebugState: vi.fn(() => ({ active: false })),
  subscribe: vi.fn(() => () => {}),
}));

import Fn, { FnTh } from '../../src/FieldName.jsx';
import { isDebugActive } from '../../src/debug/index.js';

describe('Fn (FieldName)', () => {
  beforeEach(() => {
    vi.mocked(isDebugActive).mockReturnValue(false);
  });

  it('renders the field name text', () => {
    render(<Fn f="dcfg_contract_fee">$5,000</Fn>);
    expect(screen.getByText('dcfg_contract_fee')).toBeDefined();
  });

  it('renders children alongside field name', () => {
    render(<Fn f="dcfg_name">Acme Corp</Fn>);
    expect(screen.getByText('Acme Corp')).toBeDefined();
    expect(screen.getByText('dcfg_name')).toBeDefined();
  });

  it('sets data-field attribute for automation', () => {
    const { container } = render(<Fn f="dcfg_status">Active</Fn>);
    const span = container.querySelector('[data-field="dcfg_status"]');
    expect(span).not.toBeNull();
  });

  it('color matches background by default (invisible)', () => {
    const { container } = render(<Fn f="dcfg_fee" />);
    const span = container.querySelector('[data-field="dcfg_fee"]');
    // jsdom normalizes hex to rgb
    expect(span.style.color).toMatch(/rgb\(255,\s*255,\s*255\)|#fff/);
  });

  it('shows blue color when debug mode is active', () => {
    vi.mocked(isDebugActive).mockReturnValue(true);
    const { container } = render(<Fn f="dcfg_fee" />);
    const span = container.querySelector('[data-field="dcfg_fee"]');
    // #3b82f6 = rgb(59, 130, 246) in jsdom
    expect(span.style.color).toMatch(/rgb\(59,\s*130,\s*246\)|#3b82f6/);
  });

  it('returns null when f prop is empty', () => {
    const { container } = render(<Fn f="">content</Fn>);
    expect(container.textContent).toBe('content');
    expect(container.querySelector('[data-field]')).toBeNull();
  });
});

describe('FnTh', () => {
  it('renders inside a th element', () => {
    const { container } = render(
      <table><thead><tr><FnTh f="dcfg_name">Name</FnTh></tr></thead></table>
    );
    const th = container.querySelector('th');
    expect(th).not.toBeNull();
    expect(th.textContent).toContain('Name');
    expect(th.textContent).toContain('dcfg_name');
  });

  it('passes extra props to th', () => {
    const { container } = render(
      <table><thead><tr><FnTh f="dcfg_name" className="custom">Name</FnTh></tr></thead></table>
    );
    expect(container.querySelector('th.custom')).not.toBeNull();
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/components/FieldName.test.jsx`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/components/FieldName.test.jsx
git commit -m "test: add FieldName + FnTh component tests"
```

---

### Task 10: debugHarness.test.js

**Files:**
- Create: `spa/dcfg-shell/tests/debug/debugHarness.test.js`
- Read: `spa/dcfg-shell/src/debug/index.js`

- [ ] **Step 1: Create test file**

```javascript
// tests/debug/debugHarness.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('Debug harness', () => {
  let initDebug, isDebugActive, getDebugState;

  beforeEach(async () => {
    vi.resetModules();
    // Clean up globals
    delete window.DCFG;
    sessionStorage.clear();
    // Reset location mock
    Object.defineProperty(window, 'location', {
      value: { search: '', hash: '', href: 'http://localhost/' },
      writable: true,
      configurable: true,
    });

    const mod = await import('../../src/debug/index.js');
    initDebug = mod.initDebug;
    isDebugActive = mod.isDebugActive;
    getDebugState = mod.getDebugState;
  });

  it('is inactive by default — no fetch patching', () => {
    initDebug();
    expect(isDebugActive()).toBe(false);
    expect(window.DCFG?.debug).toBeUndefined();
  });

  it('activates when ?dcfg_debug=1 is in URL search', () => {
    window.location.search = '?dcfg_debug=1';
    initDebug();
    expect(isDebugActive()).toBe(true);
    expect(window.DCFG.debug).toBeDefined();
    expect(window.DCFG.debug.active).toBe(true);
  });

  it('persists activation via sessionStorage', () => {
    sessionStorage.setItem('dcfg_debug_active', '1');
    initDebug();
    expect(isDebugActive()).toBe(true);
  });

  it('exposes calls, errors, logs arrays on window.DCFG.debug', () => {
    window.location.search = '?dcfg_debug=1';
    initDebug();
    expect(Array.isArray(window.DCFG.debug.calls)).toBe(true);
    expect(Array.isArray(window.DCFG.debug.errors)).toBe(true);
    expect(Array.isArray(window.DCFG.debug.logs)).toBe(true);
  });

  it('clearCalls empties the call log', () => {
    window.location.search = '?dcfg_debug=1';
    initDebug();
    // Manually push a fake call
    const state = getDebugState();
    state.calls.push({ id: 1, method: 'GET', url: '/test', status: 200 });
    expect(window.DCFG.debug.calls.length).toBe(1);
    window.DCFG.debug.clearCalls();
    expect(window.DCFG.debug.calls.length).toBe(0);
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run tests/debug/debugHarness.test.js`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/debug/debugHarness.test.js
git commit -m "test: add debug harness activation + namespace tests"
```

---

## Chunk 4: Playwright Foundation — Config + Page Objects

### Task 11: Update Playwright .env and config

**Files:**
- Modify: `spa/dcfg-playwright/.env`
- Modify: `spa/dcfg-playwright/playwright.config.ts`

- [ ] **Step 1: Set portal URL in .env**

Add or update in `spa/dcfg-playwright/.env`:
```
DCFG_PORTAL_URL=https://dmms1.powerappsportals.com
```

- [ ] **Step 2: Add crud project to playwright.config.ts**

Add after the `smoke` project definition:

```typescript
// CRUD tests — write operations with self-cleaning soft-delete
// Runs serially to prevent cross-test interference
{
  name: 'crud',
  testMatch: /\.crud\.spec\.ts/,
  fullyParallel: false,
  use: {
    ...devices['Desktop Chrome'],
    storageState: 'playwright/.auth/user.json',
  },
  dependencies: ['setup'],
},
```

- [ ] **Step 3: Commit**

```bash
cd C:\DCFG\spa\dcfg-playwright
git add .env playwright.config.ts
git commit -m "config: add dmms1 portal URL + crud project for write tests"
```

---

### Task 12: New Page Objects (batch)

**Files:**
- Create: `spa/dcfg-playwright/pages/MsaListPage.ts`
- Create: `spa/dcfg-playwright/pages/MsaDetailPage.ts`
- Create: `spa/dcfg-playwright/pages/CustomerDetailPage.ts`
- Create: `spa/dcfg-playwright/pages/LocationsPage.ts`
- Create: `spa/dcfg-playwright/pages/LocationDetailPage.ts`
- Create: `spa/dcfg-playwright/pages/OnboardingPage.ts`
- Create: `spa/dcfg-playwright/pages/OnboardingDetailPage.ts`
- Create: `spa/dcfg-playwright/pages/AdminPage.ts`
- Create: `spa/dcfg-playwright/pages/ContractDetailPage.ts`
- Create: `spa/dcfg-playwright/pages/ContractWizardPage.ts`
- Create: `spa/dcfg-playwright/pages/ProposalWizardPage.ts`
- Create: `spa/dcfg-playwright/pages/LocationManagerPage.ts`

- [ ] **Step 1: Create all page objects**

Each page object follows the same pattern — extends BasePage, defines route and key locators. Create all 12 files. Example pattern:

```typescript
// pages/MsaListPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class MsaListPage extends BasePage {
  readonly searchInput: Locator;
  readonly tableRows: Locator;

  constructor(page: Page) {
    super(page);
    this.searchInput = page.getByRole('textbox', { name: /search/i });
    this.tableRows = page.locator('tr[data-row]');
  }

  async goto(): Promise<void> {
    await super.goto('/msas');
  }
}
```

```typescript
// pages/MsaDetailPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class MsaDetailPage extends BasePage {
  readonly heading: Locator;
  readonly ratesTable: Locator;
  readonly contractsSection: Locator;

  constructor(page: Page) {
    super(page);
    this.heading = page.getByRole('heading').first();
    this.ratesTable = page.getByText(/rates/i).locator('..');
    this.contractsSection = page.getByText(/linked contracts/i).locator('..');
  }

  async goto(id: string): Promise<void> {
    await super.goto(`/msas/${id}`);
  }
}
```

```typescript
// pages/CustomerDetailPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class CustomerDetailPage extends BasePage {
  readonly nameHeading: Locator;
  readonly contactsSection: Locator;
  readonly programsSection: Locator;
  readonly locationsTab: Locator;
  readonly contractsTab: Locator;

  constructor(page: Page) {
    super(page);
    this.nameHeading = page.getByRole('heading').first();
    this.contactsSection = page.getByText(/contacts/i).first();
    this.programsSection = page.getByText(/programs/i).first();
    this.locationsTab = page.getByRole('button', { name: /locations/i });
    this.contractsTab = page.getByRole('button', { name: /contracts/i });
  }

  async goto(id: string): Promise<void> {
    await super.goto(`/customers/${id}`);
  }
}
```

```typescript
// pages/LocationsPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class LocationsPage extends BasePage {
  readonly searchInput: Locator;
  readonly gridRows: Locator;

  constructor(page: Page) {
    super(page);
    this.searchInput = page.getByRole('textbox', { name: /search/i });
    this.gridRows = page.locator('tr[data-row]');
  }

  async goto(): Promise<void> {
    await super.goto('/locations');
  }
}
```

```typescript
// pages/LocationDetailPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class LocationDetailPage extends BasePage {
  readonly propertyInfo: Locator;
  readonly applianceList: Locator;
  readonly photosSection: Locator;

  constructor(page: Page) {
    super(page);
    this.propertyInfo = page.getByText(/property/i).first();
    this.applianceList = page.getByText(/appliance/i).first();
    this.photosSection = page.getByText(/photo/i).first();
  }

  async goto(id: string): Promise<void> {
    await super.goto(`/locations/${id}`);
  }
}
```

```typescript
// pages/OnboardingPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class OnboardingPage extends BasePage {
  readonly caseRows: Locator;
  readonly phaseBadges: Locator;

  constructor(page: Page) {
    super(page);
    this.caseRows = page.locator('tr[data-row]');
    this.phaseBadges = page.locator('[data-phase]');
  }

  async goto(): Promise<void> {
    await super.goto('/onboarding');
  }
}
```

```typescript
// pages/OnboardingDetailPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class OnboardingDetailPage extends BasePage {
  readonly timeline: Locator;
  readonly checklists: Locator;

  constructor(page: Page) {
    super(page);
    this.timeline = page.getByText(/timeline/i).first();
    this.checklists = page.getByText(/checklist/i).first();
  }

  async goto(id: string): Promise<void> {
    await super.goto(`/onboarding/${id}`);
  }
}
```

```typescript
// pages/AdminPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class AdminPage extends BasePage {
  readonly usersTab: Locator;
  readonly auditTab: Locator;
  readonly configTab: Locator;
  readonly templatesTab: Locator;
  readonly fieldsTab: Locator;

  constructor(page: Page) {
    super(page);
    this.usersTab = page.getByRole('button', { name: /users/i });
    this.auditTab = page.getByRole('button', { name: /audit/i });
    this.configTab = page.getByRole('button', { name: /config/i });
    this.templatesTab = page.getByRole('button', { name: /template/i });
    this.fieldsTab = page.getByRole('button', { name: /field/i });
  }

  async goto(): Promise<void> {
    await super.goto('/admin');
  }
}
```

```typescript
// pages/ContractDetailPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class ContractDetailPage extends BasePage {
  readonly statusBanner: Locator;
  readonly linesTable: Locator;
  readonly complianceSection: Locator;

  constructor(page: Page) {
    super(page);
    this.statusBanner = page.locator('[data-status]').first();
    this.linesTable = page.getByText(/line/i).first();
    this.complianceSection = page.getByText(/compliance/i).first();
  }

  async goto(id: string): Promise<void> {
    await super.goto(`/contracts/${id}`);
  }
}
```

```typescript
// pages/ContractWizardPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class ContractWizardPage extends BasePage {
  readonly familySelector: Locator;
  readonly typeSelector: Locator;
  readonly nextButton: Locator;
  readonly backButton: Locator;
  readonly generateButton: Locator;
  readonly stepIndicator: Locator;

  constructor(page: Page) {
    super(page);
    this.familySelector = page.getByText(/family/i).locator('..').locator('select, [role="listbox"]').first();
    this.typeSelector = page.getByText(/type/i).locator('..').locator('select, [role="listbox"]').first();
    this.nextButton = page.getByRole('button', { name: /next/i });
    this.backButton = page.getByRole('button', { name: /back/i });
    this.generateButton = page.getByRole('button', { name: /generate/i });
    this.stepIndicator = page.locator('[data-step]');
  }

  async goto(): Promise<void> {
    await super.goto('/contracts/new');
  }
}
```

```typescript
// pages/ProposalWizardPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class ProposalWizardPage extends BasePage {
  readonly nextButton: Locator;
  readonly backButton: Locator;
  readonly generateButton: Locator;

  constructor(page: Page) {
    super(page);
    this.nextButton = page.getByRole('button', { name: /next/i });
    this.backButton = page.getByRole('button', { name: /back/i });
    this.generateButton = page.getByRole('button', { name: /generate/i });
  }

  async goto(): Promise<void> {
    await super.goto('/proposals/new');
  }
}
```

```typescript
// pages/LocationManagerPage.ts
import { type Page, type Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class LocationManagerPage extends BasePage {
  readonly customerSearch: Locator;
  readonly locationList: Locator;
  readonly addButton: Locator;

  constructor(page: Page) {
    super(page);
    this.customerSearch = page.getByRole('textbox', { name: /customer|search/i }).first();
    this.locationList = page.locator('[data-location]');
    this.addButton = page.getByRole('button', { name: /add/i }).first();
  }

  async goto(): Promise<void> {
    await super.goto('/field');
  }
}
```

- [ ] **Step 2: Update fixtures to include new page objects**

Add new page objects to `spa/dcfg-playwright/fixtures/fixtures.ts`. Add imports and fixture definitions following the existing pattern.

- [ ] **Step 3: Commit**

```bash
cd C:\DCFG\spa\dcfg-playwright
git add pages/ fixtures/fixtures.ts
git commit -m "test: add 12 new Playwright page objects"
```

---

## Chunk 5: Playwright Read-Only Specs

### Task 13: Screen smoke specs (batch)

**Files:**
- Create: `spa/dcfg-playwright/tests/msa-screens.spec.ts`
- Create: `spa/dcfg-playwright/tests/customer-detail.spec.ts`
- Create: `spa/dcfg-playwright/tests/location-screens.spec.ts`
- Create: `spa/dcfg-playwright/tests/onboarding-screens.spec.ts`
- Create: `spa/dcfg-playwright/tests/admin-panel.spec.ts`
- Create: `spa/dcfg-playwright/tests/contract-detail.spec.ts`
- Create: `spa/dcfg-playwright/tests/sensor-banner.spec.ts`
- Create: `spa/dcfg-playwright/tests/debug-panel.spec.ts`
- Create: `spa/dcfg-playwright/tests/role-guard.spec.ts`

Each spec follows this pattern — navigate, wait for data load, assert key elements present. No writes.

- [ ] **Step 1: Create all read-only spec files**

Example pattern (adapt for each screen):

```typescript
// tests/msa-screens.spec.ts
import { test, expect } from '../fixtures/fixtures';

test.describe('MSA Screens', () => {
  test('MSA list loads with rows', async ({ page }) => {
    await page.goto('/?dcfg_debug=1#/msas');
    await page.waitForLoadState('networkidle');
    // Should have at least one table row or list item
    const rows = page.locator('tr').filter({ hasText: /.+/ });
    await expect(rows.first()).toBeVisible({ timeout: 15000 });
  });

  test('click MSA navigates to detail', async ({ page }) => {
    await page.goto('/?dcfg_debug=1#/msas');
    await page.waitForLoadState('networkidle');
    const firstRow = page.locator('tr[data-row]').first();
    if (await firstRow.isVisible()) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/#\/msas\//);
    }
  });

  test('MSA detail shows header and rates table', async ({ page }) => {
    await page.goto('/?dcfg_debug=1#/msas');
    await page.waitForLoadState('networkidle');
    const firstRow = page.locator('tr[data-row]').first();
    if (await firstRow.isVisible()) {
      await firstRow.click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('heading').first()).toBeVisible();
    }
  });
});
```

Apply the same pattern for each screen:
- **customer-detail.spec.ts**: Navigate to `/customers`, click first row, verify contact info, programs, tabs
- **location-screens.spec.ts**: Navigate to `/locations`, verify grid, click to detail, verify appliances
- **onboarding-screens.spec.ts**: Navigate to `/onboarding`, verify case rows, click to detail
- **admin-panel.spec.ts**: Navigate to `/admin`, click each tab, verify content renders
- **contract-detail.spec.ts**: Navigate to `/contracts`, click first row, verify status banner, lines, compliance
- **sensor-banner.spec.ts**: Navigate to `/dashboard`, check if banner exists (conditional on alerts)
- **debug-panel.spec.ts**: Navigate with `?dcfg_debug=1`, verify debug panel opens, API log visible
- **role-guard.spec.ts**: Navigate to screens with admin-only actions, verify buttons present for admin user

- [ ] **Step 2: Run smoke tests**

Run: `cd C:\DCFG\spa\dcfg-playwright && npx playwright test --project=setup --headed` (auth first)
Run: `cd C:\DCFG\spa\dcfg-playwright && npx playwright test --project=smoke`
Expected: All existing + new specs PASS

- [ ] **Step 3: Commit**

```bash
cd C:\DCFG\spa\dcfg-playwright
git add tests/
git commit -m "test: add 8 new Playwright smoke specs — all screens covered"
```

---

## Chunk 6: Playwright CRUD Specs

### Task 14: contract-wizard.crud.spec.ts

**Files:**
- Create: `spa/dcfg-playwright/tests/contract-wizard.crud.spec.ts`

- [ ] **Step 1: Create the CRUD spec**

```typescript
// tests/contract-wizard.crud.spec.ts
import { test, expect } from '../fixtures/fixtures';

test.describe.serial('Contract Wizard CRUD', () => {
  const createdRecords: Array<{ entitySet: string; id: string }> = [];

  test.afterEach(async ({ page }) => {
    // Wait for async flows to settle
    if (createdRecords.length > 0) {
      await page.waitForTimeout(10000);
    }
    for (const rec of [...createdRecords].reverse()) {
      try {
        await page.evaluate(async ({ entitySet, id }) => {
          const tokenEl = document.querySelector('input[name="__RequestVerificationToken"]');
          const token = (tokenEl as HTMLInputElement)?.value || '';
          await fetch(`/_api/${entitySet}(${id})`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json', '__RequestVerificationToken': token },
            body: JSON.stringify({ dcfg_active_flag: false }),
          });
        }, rec);
      } catch { console.warn(`Cleanup failed: ${rec.entitySet}(${rec.id})`); }
    }
    createdRecords.length = 0;
  });

  test('complete Decades Work Order wizard', async ({ page }) => {
    await page.goto('/?dcfg_debug=1#/contracts/new');
    await page.waitForLoadState('networkidle');

    // Step 1: Family + Type
    // Select Decades family, Work Order type (exact selectors depend on component)
    const familySelect = page.locator('select').first();
    if (await familySelect.isVisible()) {
      await familySelect.selectOption({ label: /decades/i });
    }
    // Click Next
    await page.getByRole('button', { name: /next/i }).click();
    await page.waitForLoadState('networkidle');

    // Steps 2-4: Fill required fields (selectors vary by component)
    // This test verifies the wizard completes without errors
    // Capture any created record IDs from the debug API log
    // ... (implementation details depend on exact wizard UI)

    // After wizard completes, check for success toast
    // Record created IDs for cleanup
  });

  test('validation prevents empty submit', async ({ page }) => {
    await page.goto('/?dcfg_debug=1#/contracts/new');
    await page.waitForLoadState('networkidle');

    // Try to advance without selecting family/type
    const nextBtn = page.getByRole('button', { name: /next/i });
    if (await nextBtn.isVisible()) {
      await nextBtn.click();
      // Should still be on step 1 (validation blocks)
      await expect(page).toHaveURL(/#\/contracts\/new/);
    }
  });
});
```

**NOTE:** The exact selectors and wizard flow depend on the actual component DOM structure. The implementing agent should read `NewContractWizard.jsx` to determine the correct selectors for family/type/customer/contractor fields, step indicators, and Next/Back/Generate buttons. The pattern above provides the framework.

- [ ] **Step 2: Create proposal-wizard.crud.spec.ts, location-manager.crud.spec.ts, audit-trail.crud.spec.ts**

Follow the same self-cleaning pattern for each. Key differences:
- **proposal-wizard.crud.spec.ts**: Navigate to `/#/proposals/new`, 4-step flow, capture MSA ID
- **location-manager.crud.spec.ts**: Navigate to `/#/field`, search customer, add property, add appliance
- **audit-trail.crud.spec.ts**: Create contract, query debug API log for audit log POST, verify columns

- [ ] **Step 3: Create cleanup.crud.spec.ts**

```typescript
// tests/cleanup.crud.spec.ts
import { test } from '../fixtures/fixtures';

// Map entity set to the display field to search for [TEST] prefix
// dcfg_contracts has NO dcfg_name — use dcfg_client_name
const CLEANUP_TARGETS: Array<{ entitySet: string; searchField: string; idField: string }> = [
  { entitySet: 'dcfg_contracts', searchField: 'dcfg_client_name', idField: 'dcfg_contractid' },
  { entitySet: 'dcfg_contract_lines', searchField: 'dcfg_description', idField: 'dcfg_contract_lineid' },
  { entitySet: 'dcfg_msas', searchField: 'dcfg_name', idField: 'dcfg_msaid' },
  { entitySet: 'dcfg_properties', searchField: 'dcfg_name', idField: 'dcfg_propertyid' },
  { entitySet: 'dcfg_appliances', searchField: 'dcfg_name', idField: 'dcfg_applianceid' },
];

test('cleanup orphaned [TEST] records', async ({ page }) => {
  await page.goto('/?dcfg_debug=1#/dashboard');
  await page.waitForLoadState('networkidle');

  const oneHourAgo = new Date(Date.now() - 3600000).toISOString();

  for (const { entitySet, searchField, idField } of CLEANUP_TARGETS) {
    const records = await page.evaluate(async ({ entitySet, searchField, idField, cutoff }) => {
      const resp = await fetch(
        `/_api/${entitySet}?$filter=contains(${searchField},'[TEST]') and dcfg_active_flag eq true and createdon lt ${cutoff}&$select=${idField}`
      );
      if (!resp.ok) return [];
      const data = await resp.json();
      return (data.value || []).map((r: any) => r[idField]);
    }, { entitySet, searchField, idField, cutoff: oneHourAgo });

    for (const id of records) {
      await page.evaluate(async ({ entitySet, recordId }) => {
        const tokenEl = document.querySelector('input[name="__RequestVerificationToken"]');
        const token = (tokenEl as HTMLInputElement)?.value || '';
        await fetch(`/_api/${entitySet}(${recordId})`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', '__RequestVerificationToken': token },
          body: JSON.stringify({ dcfg_active_flag: false }),
        });
      }, { entitySet, recordId: id });
    }
  }
});
```

- [ ] **Step 4: Run CRUD tests**

Run: `cd C:\DCFG\spa\dcfg-playwright && npx playwright test --project=crud`
Expected: PASS (or skip if wizard selectors need refinement)

- [ ] **Step 5: Commit**

```bash
cd C:\DCFG\spa\dcfg-playwright
git add tests/
git commit -m "test: add CRUD specs — contract wizard, proposal, location, audit, cleanup"
```

---

## Chunk 7: Remaining Vitest Screen + Wizard Tests (Skeleton)

Screen and wizard tests are repetitive — all follow the same pattern (mock fetch, render, assert). Rather than writing all ~18 files inline (which would be 2000+ lines of plan), the implementing agent should follow this template for each:

### Task 15: Screen test template

**Pattern for every screen test:**

```jsx
// tests/screens/<screenName>.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { PortalUserProvider } from '../../src/usePortalUser.jsx';
import { ToastProvider } from '../../src/Toast.jsx';

// Mock debug to avoid import side effects
vi.mock('../../src/debug/index.js', () => ({
  isDebugActive: vi.fn(() => false),
  initDebug: vi.fn(),
  getDebugState: vi.fn(() => ({ active: false })),
  subscribe: vi.fn(() => () => {}),
}));

import ScreenComponent from '../../src/screens/ScreenComponent.jsx';

function renderScreen(route = '/') {
  // Set up portal user
  window.Microsoft = { Dynamic365: { Portal: { User: {
    contactId: 'c-1', email: 'admin@test.com', roles: ['DCFG_Admin'],
  }}}};

  return render(
    <MemoryRouter initialEntries={[route]}>
      <PortalUserProvider>
        <ToastProvider>
          <ScreenComponent />
        </ToastProvider>
      </PortalUserProvider>
    </MemoryRouter>
  );
}

describe('ScreenComponent', () => {
  beforeEach(() => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ value: [/* mock data matching screen's apiGet calls */] }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });
    window.shell = { getTokenDeferred: () => Promise.resolve('tok') };
  });

  it('renders heading', async () => {
    renderScreen();
    await waitFor(() => expect(screen.getByRole('heading')).toBeDefined());
  });

  it('renders data after loading', async () => {
    renderScreen();
    await waitFor(() => expect(screen.getByText(/* expected text */)).toBeDefined());
  });

  it('renders empty state when no data', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ value: [] }),
      headers: new Headers({ 'content-type': 'application/json' }),
    });
    renderScreen();
    await waitFor(() => expect(screen.getByText(/no.*found|empty/i)).toBeDefined());
  });
});
```

**Apply this template to create these files:**

| # | File | Component Import | Mock Data Shape |
|---|---|---|---|
| 1 | `screens/salesDashboard.test.jsx` | `screens/SalesDashboard.jsx` | Contracts, customers, pipeline data |
| 2 | `screens/contractsList.test.jsx` | `ContractsList.jsx` (root level) | Contracts with status/family |
| 3 | `screens/contractDetail.test.jsx` | `screens/ContractDetail.jsx` | Single contract + lines + amendments |
| 4 | `screens/customerList.test.jsx` | `screens/CustomerList.jsx` | Customer rows |
| 5 | `screens/customerDetail.test.jsx` | `screens/CustomerDetail.jsx` | Single customer + contacts + programs |
| 6 | `screens/msaList.test.jsx` | `screens/MsaList.jsx` | MSA rows with status |
| 7 | `screens/msaDetail.test.jsx` | `screens/MsaDetail.jsx` | Single MSA + rates + contracts |
| 8 | `screens/locations.test.jsx` | `screens/Locations.jsx` | Location rows |
| 9 | `screens/locationDetail.test.jsx` | `screens/LocationDetail.jsx` | Property + appliances + photos |
| 10 | `screens/onboarding.test.jsx` | `screens/Onboarding.jsx` | Onboarding cases with phases |
| 11 | `screens/onboardingDetail.test.jsx` | `screens/OnboardingDetail.jsx` | Single case + timeline + checklists |
| 12 | `screens/sendQueue.test.jsx` | `screens/SendQueue.jsx` | Queue items with status |
| 13 | `screens/compliancePanel.test.jsx` | `screens/CompliancePanel.jsx` | Rules + checks (pass props, not routed) |
| 14 | `screens/admin.test.jsx` | `screens/Admin.jsx` | Users, audit log, config, templates |

**For each file:**
1. Read the actual component source to determine its imports, API calls, and DOM structure
2. Create mock data matching the actual OData response shape
3. Write 3-5 assertions per screen (heading, data rows, empty state, key interactive elements)

- [ ] **Step 1: Create all 14 screen test files following the template**
- [ ] **Step 2: Run all tests**: `npx vitest run tests/screens/`
- [ ] **Step 3: Commit**

```bash
git add tests/screens/
git commit -m "test: add screen rendering tests for all 14 screens"
```

### Task 16: Wizard test files

Follow the same template pattern but with step-specific assertions:

| File | Component | Key Assertions |
|---|---|---|
| `wizards/newContractWizard.test.jsx` | `NewContractWizard.jsx` | Step rendering, validation, navigation, generate call |
| `wizards/newProposalWizard.test.jsx` | `NewProposalWizard.jsx` | 4 steps, field editability, generate call |
| `wizards/locationManager.test.jsx` | `LocationManager.jsx` | Customer search, location list, appliance CRUD |

**For each wizard:**
1. Read the component source to understand step flow, required fields, and submit action
2. Mock all API calls the wizard makes (customer list, vendor list, etc.)
3. Test each step renders, validation prevents empty advance, final submit calls correct API

- [ ] **Step 1: Create all 3 wizard test files**
- [ ] **Step 2: Run**: `npx vitest run tests/wizards/`
- [ ] **Step 3: Commit**

```bash
git add tests/wizards/
git commit -m "test: add wizard tests — contract, proposal, location manager"
```

### Task 17: Interview + Debug component tests

| File | Component | Key Assertions |
|---|---|---|
| `interview/interviewEngine.test.js` | `interview/InterviewEngine.js` | Question registry, conditional flow, validation |
| `interview/interviewShell.test.jsx` | `interview/InterviewShell.jsx` | Mode switching |
| `interview/interviewGenerate.test.js` | `interview/interviewGenerate.js` | Payload build, API calls, audit |
| `interview/questionRenderer.test.jsx` | `interview/QuestionRenderer.jsx` | Type rendering, onChange |
| `debug/debugPanel.test.jsx` | `debug/DebugPanel.jsx` | Renders when active, shows calls/errors/user |
| `components/App.test.jsx` | `App.jsx` | Auth guard, config boot, provider tree |
| `components/SensorBanner.test.jsx` | `SensorBanner.jsx` | No alerts=null, alert count, acknowledge |
| `components/NavPanel.test.jsx` | `NavPanel.jsx` | Nav groups, active state, link targets |

- [ ] **Step 1: Create all 8 test files following component patterns**
- [ ] **Step 2: Run**: `npx vitest run`
- [ ] **Step 3: Commit**

```bash
git add tests/
git commit -m "test: add interview, debug panel, App, SensorBanner, NavPanel tests"
```

---

## Chunk 8: Final Verification

### Task 18: Run full test suite and verify coverage

- [ ] **Step 1: Run all Vitest tests**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run`
Expected: All tests PASS

- [ ] **Step 2: Run coverage report**

Run: `cd C:\DCFG\spa\dcfg-shell && npx vitest run --coverage`
Expected: portalApi.js ~90%, hooks ~95%, screens ~70%

- [ ] **Step 3: Run all Playwright smoke tests**

Run: `cd C:\DCFG\spa\dcfg-playwright && npx playwright test --project=smoke`
Expected: All specs PASS

- [ ] **Step 4: Run Playwright CRUD tests**

Run: `cd C:\DCFG\spa\dcfg-playwright && npx playwright test --project=crud`
Expected: CRUD tests PASS, all test records soft-deleted

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "test: complete SPA test battery — full unit + E2E coverage"
```
