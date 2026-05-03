---
name: safety-controls
description: "Environment isolation and safety controls for autonomous operations. ALWAYS use when executing tasks that modify Dataverse, Power Automate, or any production-adjacent system. Enforces test-environment-only policy, start-screen validation, and escalation protocols for destructive actions."
---

# Safety Controls & Environment Management

## KIOSK MODE — READ-ONLY BY DEFAULT (established 2026-03-24)

**Full safety model:** `C:\DCFG\ops\safety-model.json`

### Default State: READ_ONLY
- Monitor all systems freely (query, read, audit)
- Write ONLY to agent-owned tables: `dcfg_brain_insights`, `dcfg_agent_audit_log`, `dcfg_agent_session_trace`, `dcfg_agent_diagnostic`
- ALL other writes are BLOCKED until operator approves

### Write Approval: ONE OPERATION AT A TIME
Before any write to business/portal data, present:
```
WRITE REQUEST: [exact description — what table, what change, which environment]
Type 'y' to approve, or anything else to skip.
```
- ONLY `y` or `yes` (case-insensitive) activates the write
- NOT `ok`, `sure`, `go ahead`, `do it` — these are ambiguous
- After the single operation completes → IMMEDIATELY back to READ_ONLY
- If operator walks away → stays READ_ONLY (no approval = no write)

### Why This Exists
- Prevents misinterpreted words from triggering writes
- Data security when operator steps away from laptop
- Every write is audited to dcfg_agent_audit_log (approved, denied, or timed out)

## Environment Policy
- **Test:** org0c17e98d.crm.dynamics.com — free range for experimentation
- **Stage:** org88778bb0.crm.dynamics.com — deploy after test validation
- **Production:** NEVER touched by automated agents

## Pre-Run Checklist (Before ANY Automated Task)
1. Confirm target environment (Test or Stage)
2. Confirm task scope (what will change)
3. Present WRITE REQUEST prompt for each write operation
4. Verify current state (read before write)

## SPA Protection
**C:\DCFG\spa\ is READ-ONLY.** No creates, edits, or deletes without explicit operator permission. This is enforced in settings.json deny rules.

## Destructive Action Classification

| Action | Destructive? | Approval Required? |
|---|---|---|
| Read/query data | No | No (always allowed) |
| Write to agent-owned tables | No | No (always allowed) |
| Create new business records | Mild | Yes — WRITE REQUEST prompt |
| Update existing records | Mild | Yes — WRITE REQUEST prompt |
| Soft delete (active_flag=false) | Mild | Yes — WRITE REQUEST prompt |
| Hard delete records | Yes | Yes — WRITE REQUEST prompt |
| Modify permissions/settings | Yes | Yes — WRITE REQUEST prompt |
| Reset/recreate table | Yes | Yes — WRITE REQUEST prompt |
| Modify production data | Yes | Always — escalate, never auto |
| Push SPA code changes | Yes | Yes — WRITE REQUEST prompt |

## When Natively Destructive Actions Are Required
Some tasks are inherently destructive (e.g., deleting old solution versions, clearing test data). These are allowed IF:
1. The action is required to complete the task (not optional)
2. The WRITE REQUEST prompt was presented and operator typed 'y'
3. The action is scoped to the test environment

## Emergency Stop
If anything unexpected happens:
1. Stop all operations immediately
2. Log what happened (what was attempted, what state the system is in)
3. Do NOT attempt to "fix" the problem automatically
4. Report to operator with full context

## Heartbeat Pattern
For long-running automated tasks:
- Check environment URL every N operations
- If environment doesn't match expected → STOP
- If authentication fails → STOP and re-authenticate
- If unexpected error pattern → STOP and escalate

## Rollback Capability
Before making changes:
- Note the current state (query current values)
- Store rollback data (what to restore if things go wrong)
- After changes, verify the new state matches expectations
