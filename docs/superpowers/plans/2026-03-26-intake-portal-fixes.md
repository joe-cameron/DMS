# Intake Portal Console Error Fixes

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 console errors preventing the Onboarding Concierge SPA from loading on decades-concierge.powerappsportals.com

**Architecture:** Two code fixes in the SPA (filter removal + null guard), plus one operator-side permissions fix. All fixes are backward-compatible with both environments (Portal POC + Test).

**Tech Stack:** React 17, Vite 5, Power Pages Web API, Dataverse

**Environments affected:**
- Portal POC: `orgf625b080.crm.dynamics.com` / `decades-concierge.powerappsportals.com`
- Test: `org0c17e98d.crm.dynamics.com` / `dcfg.powerappsportals.com`

---

## Error Summary

| # | Error | Cause | Fix Location |
|---|---|---|---|
| 1 | 400 on `dcfg_location_types` | `dcfg_is_active` column doesn't exist in Portal env | `intakeApi.js:214` |
| 2 | 403 on `dcfg_intake_sessions` + `dcfg_intake_field_configs` | Missing anonymous read table permissions | Power Pages admin (operator) |
| 3 | Crash: `Cannot read properties of null (reading 'expiresAt')` | `data` is null when `code` is set but all load paths fail | `App.jsx:354` |

---

## Task 1: Fix `loadLocationTypes` filter (400 error)

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\intakeApi.js:214`

**Problem:** The `loadLocationTypes()` function filters by `dcfg_is_active eq true`, but the Portal POC environment's `dcfg_location_type` table has no `dcfg_is_active` column — only `dcfg_name`. The Test environment does have `dcfg_is_active`, but the column is named differently there too (it uses `statecode` for active/inactive via standard Dataverse mechanisms).

**Fix:** Remove the `dcfg_is_active` filter. All location types in the table are active — inactive ones would be deleted or use Dataverse's built-in `statecode`. This is safe for both environments.

- [ ] **Step 1: Edit intakeApi.js line 214**

Change:
```javascript
const r = await apiGet(`/${ES.locationTypes}?$filter=dcfg_is_active eq true&$select=dcfg_location_typeid,dcfg_name&$orderby=dcfg_name asc`);
```
To:
```javascript
const r = await apiGet(`/${ES.locationTypes}?$select=dcfg_location_typeid,dcfg_name&$orderby=dcfg_name asc`);
```

- [ ] **Step 2: Verify no other references to `dcfg_is_active` in SPA**

Search for `dcfg_is_active` in `src/` — should only appear in this one location. The `isOnline()` function at line 281 queries `dcfg_location_types` but doesn't use this filter (already clean).

---

## Task 2: Fix null `data` crash (TypeError)

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx:354`

**Problem:** When `code` is set (user entered DEMO1234) but all data sources fail (Dataverse 403, no localStorage, no seed file), the `ACCESS_CODES` fallback at line 226 creates data via `createEmptyProvider()`. However, there's a race condition: if the auto-login effect fires (line 126) with a cached code but Dataverse and localStorage both fail, `code` could be set from a previous render while `data` remains null.

**Fix:** Add optional chaining on `data` at line 354. This is a defensive guard — the login flow should always set `data` before `code`, but the async nature of React state updates means a brief null window is possible.

- [ ] **Step 1: Edit App.jsx line 354**

Change:
```jsx
{data.expiresAt && (
```
To:
```jsx
{data?.expiresAt && (
```

- [ ] **Step 2: Audit for other unguarded `data.` references in the main layout**

The main layout (line 337+) renders when `code` is truthy. Check all `data.` references after line 337 for optional chaining. Key locations:
- Line 354: `data.expiresAt` — **fix above**
- Line 377: `data.properties.map` — needs `data?.properties?.map` or guard
- Line 415: `data.vendors.length` — needs `data?.vendors?.length ?? 0`
- Line 422: `data.authorizedUsers` — already uses `(data.authorizedUsers || [])`
- Line 453: `tab === 'properties' && selectedProp` — safe (selectedProp derived from `data?.`)
- Line 467: `data.vendors` — needs `data?.vendors ?? []`
- Line 475: `data.authorizedUsers` — needs `data?.authorizedUsers ?? []`
- Line 476: `data.properties` — needs `data?.properties ?? []`

Add a single early return after the login screen guard:

```jsx
// After line 297's login screen return, add:
if (!data) {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: T.bg }}>
      <p style={{ color: T.textLight, fontSize: 14 }}>Loading...</p>
    </div>
  );
}
```

This is cleaner than adding optional chaining to every `data.` reference — one guard handles all cases.

- [ ] **Step 3: Insert loading guard at App.jsx after line 334 (after login screen return)**

Insert after `}` closing the login screen block (after line 334), before `// ── Main Layout ──`:

```jsx
// Loading state — code set but data not yet loaded
if (!data) {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: T.bg }}>
      <p style={{ color: T.textLight, fontSize: 14 }}>Loading...</p>
    </div>
  );
}
```

---

## Task 3: Table permissions (operator action — NOT a code fix)

**Environment:** `decades-concierge.powerappsportals.com` (Portal POC, `orgf625b080`)

**Problem:** Anonymous users get 403 when reading `dcfg_intake_session` and `dcfg_intake_field_config`. These tables need anonymous read access for the portal to function — the SPA is used by unauthenticated providers.

**Tables needing anonymous READ permission:**
| Table | Permission Needed | Why |
|---|---|---|
| `dcfg_intake_session` | Read | Login: look up access code |
| `dcfg_intake_field_config` | Read | Field visibility config |
| `dcfg_location_type` | Read | Location type dropdown + field config joins |
| `dcfg_property_intake` | Read, Write | Load + save property data |
| `dcfg_intake_vendor` | Read, Write | Load + save vendor data |
| `dcfg_intake_authorized_user` | Read, Write | Load + save authorized users |

- [ ] **Step 1: Operator verifies anonymous table permissions in Power Pages admin**

URL: `https://make.powerpages.microsoft.com` → DCFGSystems-Portal environment → Decades Onboarding Concierge site → Security → Table permissions

Check that each table above has a permission record with:
- Access type: Global
- Permission to: Read (and Write where noted)
- Roles: Anonymous Users

- [ ] **Step 2: Clear portal cache after permission changes**

```
https://decades-concierge.powerappsportals.com/_services/about?clearCache=true
```

---

## Task 4: Build, deploy, verify

- [ ] **Step 1: Build SPA**

```bash
cd C:\dcfg\spa\dcfg-property-intake
npm run build
```

- [ ] **Step 2: Deploy to Portal POC**

```bash
pac pages upload-code-site --rootPath . --compiledPath dist
```

(Requires pac auth pointed at orgf625b080 environment)

- [ ] **Step 3: Clear cache**

```
https://decades-concierge.powerappsportals.com/_services/about?clearCache=true
```

- [ ] **Step 4: Verify — open decades-concierge.powerappsportals.com**

Expected:
- No 400 errors in console (location types load)
- No 403 errors (after operator fixes permissions)
- No crash on null data
- Login with DEMO1234 works
- Location type dropdown shows: Group Home, Apartment, Home

---

## Deploy to Test (if also needed)

Same build, different pac auth target:

```bash
pac pages upload-code-site --rootPath . --compiledPath dist
```

Clear cache: `https://dcfg.powerappsportals.com/_services/about?clearCache=true`
