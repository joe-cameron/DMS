# SPA Audit Logging Fix + Hooks for New Audit Module

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 blocking `writeAuditLog()` calls that can break user actions on audit failure, and add hook points so the new standalone audit module (`C:\DCFG\audit\`) can observe SPA events without modifying business logic.

**Architecture:** Convert 6 blocking `await writeAuditLog(...)` calls (the only ones without `.catch()`) to non-blocking `writeAuditLog(...).catch(e => console.warn('Audit write failed:', e))`. The other 31 `await writeAuditLog(...).catch(()=>{})` calls are already non-blocking (`.catch()` converts rejection to resolution). Add a lightweight event hook in `portalApi.js` that the new audit module can subscribe to — every `writeAuditLog()` call emits both the raw caller entry and the normalized Dataverse payload to the hook, giving the new module a bridge to observe all existing audit events without touching 41 call sites.

**Tech Stack:** React 17, Vite 5.4, Power Pages Portal Web API

**Spec:** `docs/superpowers/specs/2026-03-23-audit-logging-agent-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `spa/dcfg-shell/src/portalApi.js:203-211` | Modify | Add audit hook emitter inside `writeAuditLog()` |
| `spa/dcfg-shell/src/NewContractWizard.jsx:349` | Modify | Convert blocking → non-blocking |
| `spa/dcfg-shell/src/screens/ContractDetail.jsx:128` | Modify | Convert blocking → non-blocking |
| `spa/dcfg-shell/src/screens/SendQueue.jsx:198,225,249` | Modify | Convert 3 blocking → non-blocking |
| `spa/dcfg-shell/src/ContractsList.jsx:241` | Modify | Convert blocking → non-blocking |

---

## Chunk 1: Add Audit Hook Emitter to portalApi.js

### Task 1: Add hook registration and emission to writeAuditLog

**Files:**
- Modify: `spa/dcfg-shell/src/portalApi.js:201-211`

**Why:** The new audit module at `C:\DCFG\audit\` needs to observe every audit event the SPA emits. Rather than modifying 41 call sites, we add a hook inside `writeAuditLog()` itself. Any external module can register a listener via `onAuditEvent()`. The hook fires before the Dataverse write (fire-and-forget), so even if the write fails the new module still sees the event.

- [ ] **Step 1: Add hook registration above writeAuditLog**

Add this immediately before the `// AUDIT LOG — CREATE ONLY` comment block (line 200):

```javascript
// ═══════════════════════════════════════════════════════════════
// AUDIT HOOK — external modules can observe audit events
// ═══════════════════════════════════════════════════════════════
const _auditHooks = [];
export function onAuditEvent(fn) { _auditHooks.push(fn); return () => { const i = _auditHooks.indexOf(fn); if (i >= 0) _auditHooks.splice(i, 1); }; }
function _emitAuditHook(raw, normalized) { for (const fn of _auditHooks) { try { fn({ raw, normalized }); } catch(e) { console.warn('Audit hook error:', e); } } }
```

- [ ] **Step 2: Emit hook inside writeAuditLog before the API call**

Change `writeAuditLog` to call `_emitAuditHook` with the normalized payload before writing to Dataverse:

Current (line 203-211):
```javascript
export async function writeAuditLog(entry) {
  const g = (camel, dcfg) => entry[dcfg] ?? entry[camel];
  const p = { dcfg_target_table:g('targetTable','dcfg_target_table'), dcfg_target_record_id:g('targetRecordId','dcfg_target_record_id'), dcfg_action_type:g('actionType','dcfg_action_type'), dcfg_performed_by:g('performedBy','dcfg_performed_by') || 'unknown', dcfg_performed_at:g('performedAt','dcfg_performed_at')||new Date().toISOString(), dcfg_new_value:g('newValue','dcfg_new_value')||'' };
  const oldVal = g('oldValue','dcfg_old_value'); if(oldVal) p.dcfg_old_value=oldVal;
  const reason = g('reason','dcfg_reason'); if(reason) p.dcfg_reason=reason;
  const relId = g('relatedContractId','dcfg_related_contract_id'); if(relId) p.dcfg_related_contract_id = relId;
  return apiPost(`/${EntitySets.auditLogs}`, p);
}
```

New:
```javascript
export async function writeAuditLog(entry) {
  const g = (camel, dcfg) => entry[dcfg] ?? entry[camel];
  const p = { dcfg_target_table:g('targetTable','dcfg_target_table'), dcfg_target_record_id:g('targetRecordId','dcfg_target_record_id'), dcfg_action_type:g('actionType','dcfg_action_type'), dcfg_performed_by:g('performedBy','dcfg_performed_by') || 'unknown', dcfg_performed_at:g('performedAt','dcfg_performed_at')||new Date().toISOString(), dcfg_new_value:g('newValue','dcfg_new_value')||'' };
  const oldVal = g('oldValue','dcfg_old_value'); if(oldVal) p.dcfg_old_value=oldVal;
  const reason = g('reason','dcfg_reason'); if(reason) p.dcfg_reason=reason;
  const relId = g('relatedContractId','dcfg_related_contract_id'); if(relId) p.dcfg_related_contract_id = relId;
  _emitAuditHook(entry, p);
  return apiPost(`/${EntitySets.auditLogs}`, p);
}
```

- [ ] **Step 3: Verify no regressions**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`
Expected: Clean build, no errors. The hook has zero call sites yet so behavior is unchanged.

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-shell/src/portalApi.js
git commit -m "feat(audit): add onAuditEvent hook for external audit module bridge"
```

---

## Chunk 2: Fix 6 Blocking writeAuditLog Calls

### Task 2: Fix NewContractWizard.jsx — line 349

**Files:**
- Modify: `spa/dcfg-shell/src/NewContractWizard.jsx:349`

**Context:** After contract generation completes (step 4), the audit write blocks `setGenResult()`. If audit fails, the user sees no success confirmation even though the contract was created.

- [ ] **Step 1: Convert to non-blocking**

Change line 349:
```javascript
      await writeAuditLog({
```
To:
```javascript
      writeAuditLog({
```

And after the closing `});` of the writeAuditLog call (line 356), add `.catch(()=>{})`:

Change:
```javascript
      await writeAuditLog({
        targetTable: 'dcfg_contract',
        targetRecordId: contractId,
        actionType: AuditActionType.Generated,
        performedBy: userEmail,
        newValue: `Generated ${contractNumber} via wizard`,
        relatedContractId: contractId,
      });
```
To:
```javascript
      writeAuditLog({
        targetTable: 'dcfg_contract',
        targetRecordId: contractId,
        actionType: AuditActionType.Generated,
        performedBy: userEmail,
        newValue: `Generated ${contractNumber} via wizard`,
        relatedContractId: contractId,
      }).catch(e => console.warn('Audit write failed:', e));
```

- [ ] **Step 2: Verify build**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`
Expected: Clean build.

---

### Task 3: Fix ContractDetail.jsx — line 128

**Files:**
- Modify: `spa/dcfg-shell/src/screens/ContractDetail.jsx:128`

**Context:** Inside `commitTransition()` — the shared function for all contract status changes (Send, Close, Void, etc.). The `await writeAuditLog()` sits between the `apiPatch` (which already succeeded) and `reload()`. If audit fails, the patch succeeded but the UI shows an error and doesn't reload.

- [ ] **Step 1: Convert to non-blocking**

Change lines 128-137:
```javascript
      await writeAuditLog({
        targetTable:       'dcfg_contract',
        targetRecordId:    id,
        actionType:        auditOverride.actionType || AuditActionType.StatusChanged,
        performedBy:       userEmail,
        newValue:          auditOverride.newValue || `Status changed to ${STATUS_CONFIG[newStatus]?.label}`,
        oldValue:          STATUS_CONFIG[oldStatus]?.label,
        reason:            auditOverride.reason,
        relatedContractId: id,
      });
```
To:
```javascript
      writeAuditLog({
        targetTable:       'dcfg_contract',
        targetRecordId:    id,
        actionType:        auditOverride.actionType || AuditActionType.StatusChanged,
        performedBy:       userEmail,
        newValue:          auditOverride.newValue || `Status changed to ${STATUS_CONFIG[newStatus]?.label}`,
        oldValue:          STATUS_CONFIG[oldStatus]?.label,
        reason:            auditOverride.reason,
        relatedContractId: id,
      }).catch(e => console.warn('Audit write failed:', e));
```

- [ ] **Step 2: Verify build**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`
Expected: Clean build.

---

### Task 4: Fix SendQueue.jsx — lines 198, 225, 249

**Files:**
- Modify: `spa/dcfg-shell/src/screens/SendQueue.jsx:198,225,249`

**Context:** Three actions — approve/send, return for revision, soft-delete. All use `await writeAuditLog()` after the `apiPatch` succeeds. Audit failure blocks the success toast and state update.

- [ ] **Step 1: Convert line 198 (approve/send) to non-blocking**

Change:
```javascript
          await writeAuditLog({
            targetTable: 'dcfg_contract', targetRecordId: c.dcfg_contractid,
            actionType: AuditActionType.Sent, performedBy: user?.email,
            newValue: 'Approved and sent', oldValue: 'Generated',
            relatedContractId: c.dcfg_contractid,
          });
```
To:
```javascript
          writeAuditLog({
            targetTable: 'dcfg_contract', targetRecordId: c.dcfg_contractid,
            actionType: AuditActionType.Sent, performedBy: user?.email,
            newValue: 'Approved and sent', oldValue: 'Generated',
            relatedContractId: c.dcfg_contractid,
          }).catch(e => console.warn('Audit write failed:', e));
```

- [ ] **Step 2: Convert line 225 (return) to non-blocking**

Change:
```javascript
          await writeAuditLog({
            targetTable: 'dcfg_contract', targetRecordId: c.dcfg_contractid,
            actionType: AuditActionType.Declined, performedBy: user?.email,
            newValue: 'Returned for revision', oldValue: 'Generated',
            relatedContractId: c.dcfg_contractid,
          });
```
To:
```javascript
          writeAuditLog({
            targetTable: 'dcfg_contract', targetRecordId: c.dcfg_contractid,
            actionType: AuditActionType.Declined, performedBy: user?.email,
            newValue: 'Returned for revision', oldValue: 'Generated',
            relatedContractId: c.dcfg_contractid,
          }).catch(e => console.warn('Audit write failed:', e));
```

- [ ] **Step 3: Convert line 249 (soft-delete) to non-blocking**

Change:
```javascript
          await writeAuditLog({
            targetTable: 'dcfg_contract', targetRecordId: c.dcfg_contractid,
            actionType: AuditActionType.StatusChanged, performedBy: user?.email,
            newValue: 'Soft deleted (active_flag=false)', oldValue: ContractStatusLabel[c.dcfg_status] || 'Unknown',
            relatedContractId: c.dcfg_contractid,
          });
```
To:
```javascript
          writeAuditLog({
            targetTable: 'dcfg_contract', targetRecordId: c.dcfg_contractid,
            actionType: AuditActionType.StatusChanged, performedBy: user?.email,
            newValue: 'Soft deleted (active_flag=false)', oldValue: ContractStatusLabel[c.dcfg_status] || 'Unknown',
            relatedContractId: c.dcfg_contractid,
          }).catch(e => console.warn('Audit write failed:', e));
```

- [ ] **Step 4: Verify build**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`
Expected: Clean build.

---

### Task 5: Fix ContractsList.jsx — line 241

**Files:**
- Modify: `spa/dcfg-shell/src/ContractsList.jsx:241`

**Context:** Void contract action. The `updateContract()` call already succeeded. Audit failure blocks success toast and modal close.

- [ ] **Step 1: Convert to non-blocking**

Change:
```javascript
      await writeAuditLog({
        targetTable: 'dcfg_contract',
        targetRecordId: selected.dcfg_contractid,
        actionType: AuditActionType.Void,
        performedBy: userEmail,
        newValue: `Void. Reason: ${voidReason}`,
        oldValue: ContractStatusLabel[selected.dcfg_status] || 'Unknown',
        reason: voidReason,
        relatedContractId: selected.dcfg_contractid,
      });
```
To:
```javascript
      writeAuditLog({
        targetTable: 'dcfg_contract',
        targetRecordId: selected.dcfg_contractid,
        actionType: AuditActionType.Void,
        performedBy: userEmail,
        newValue: `Void. Reason: ${voidReason}`,
        oldValue: ContractStatusLabel[selected.dcfg_status] || 'Unknown',
        reason: voidReason,
        relatedContractId: selected.dcfg_contractid,
      }).catch(e => console.warn('Audit write failed:', e));
```

- [ ] **Step 2: Verify build**

Run: `cd C:\DCFG\spa\dcfg-shell && npm run build`
Expected: Clean build.

- [ ] **Step 3: Commit all blocking fixes**

```bash
git add spa/dcfg-shell/src/NewContractWizard.jsx spa/dcfg-shell/src/screens/ContractDetail.jsx spa/dcfg-shell/src/screens/SendQueue.jsx spa/dcfg-shell/src/ContractsList.jsx
git commit -m "fix(audit): convert 6 blocking writeAuditLog calls to non-blocking

Audit log failures no longer block user actions. Affected:
- NewContractWizard: contract generation
- ContractDetail: status transitions
- SendQueue: approve, return, soft-delete
- ContractsList: void contract"
```

---

## Chunk 3: Final Build + Deploy

### Task 6: Full build and deploy

**Files:**
- All modified files from Chunks 1-2

- [ ] **Step 1: Clean build**

```bash
cd C:\DCFG\spa\dcfg-shell
npm run build
```
Expected: Clean build, no warnings related to audit changes.

- [ ] **Step 2: Deploy to test environment**

```bash
cd C:\DCFG\spa\dcfg-shell
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 3: Post-deploy**

Clear portal cache and provide launch URLs:
- Test: https://dcfg-test.powerappsportals.com
- Stage: https://holding.powerappsportals.com

- [ ] **Step 4: Smoke test the 6 fixed actions**

Verify in browser that these actions complete without error:
1. Generate contract via wizard (NewContractWizard)
2. Change contract status — Send, Close, or Void (ContractDetail)
3. Approve document in SendQueue
4. Return document in SendQueue
5. Soft-delete document in SendQueue
6. Void contract (ContractsList)

Each should succeed even if `dcfg_audit_logs` table is unreachable.

- [ ] **Step 5: Verify hook is callable**

In browser console on any page:
```javascript
import('/path/to/portalApi.js').then(m => {
  const unsub = m.onAuditEvent(e => console.log('HOOK:', e));
  // Perform any audited action — should see HOOK: {...} in console
});
```

- [ ] **Step 6: Print change summary**

| File | Change |
|------|--------|
| `portalApi.js` | Added `onAuditEvent()` hook — external modules can subscribe to all audit events |
| `NewContractWizard.jsx:349` | `await writeAuditLog` → `writeAuditLog(...).catch(e => console.warn(...))` |
| `ContractDetail.jsx:128` | `await writeAuditLog` → `writeAuditLog(...).catch(e => console.warn(...))` |
| `SendQueue.jsx:198,225,249` | 3x `await writeAuditLog` → `writeAuditLog(...).catch(e => console.warn(...))` |
| `ContractsList.jsx:241` | `await writeAuditLog` → `writeAuditLog(...).catch(e => console.warn(...))` |
