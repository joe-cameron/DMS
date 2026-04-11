# Microsoft Support Ticket — Orphaned Entity Metadata Blocking Table Creation

## Issue Summary

**Environment:** DCFGSystems-Test (Sandbox)
**Org URL:** https://org0c17e98d.crm.dynamics.com
**Org ID:** org0c17e98d
**Tenant:** Decades Construction Group

**Issue:** Unable to create new custom tables (entities) via the Dataverse Web API. All `POST /api/data/v9.2/EntityDefinitions` calls fail with the error:

```
"No rows could be found for the given key"
```

This error occurs for ANY new table creation attempt, regardless of table name, schema, or attributes. The environment is otherwise functional — existing tables, queries, records, and flows all work normally. Only new entity creation is blocked.

---

## Root Cause Analysis (Our Investigation)

We identified **orphaned entity metadata records** in the Default solution that reference entities which no longer exist in the `EntityDefinitions` metadata. These orphans were created during a failed batch table creation operation that was interrupted mid-execution.

### Evidence

**1. Orphan detection script found ghost components:**

We queried solution components (componenttype = 1, which is Entity) in the Default solution and attempted to resolve each `objectid` against `EntityDefinitions`. Multiple components returned 404 — meaning the solution references entities that don't exist in metadata.

Orphan entity IDs found:
```
8c98e3c3-0731-f111-88b4-7ced8d709173
ec2c2df8-0731-f111-88b4-7ced8d709731
3a2d2df8-0731-f111-88b4-7ced8d709731
b22d2df8-0731-f111-88b4-7ced8d709731
178663fd-0731-f111-88b4-7ced8d709173
5e8663fd-0731-f111-88b4-7ced8d709173
073ee092-0831-f111-88b4-7ced8d709731
```

These IDs do not resolve to any entity when queried:
```
GET /api/data/v9.2/EntityDefinitions({id})?$select=LogicalName
→ 404 Not Found
```

**2. Orphan deletion attempted — partially blocked:**

We attempted to remove orphans via two methods:
- `DELETE /api/data/v9.2/solutioncomponents({solutioncomponentid})` — failed (insufficient privileges or locked records)
- `POST /api/data/v9.2/RemoveSolutionComponent` with ComponentId + ComponentType=1 + SolutionUniqueName="Default" — also failed

Neither API method can remove these ghost records. They appear to be in a state that requires backend/platform-level cleanup.

**3. Other environments are clean:**

We verified Stage (org88778bb0) and Prod (org06f5de0b) using the same diagnostic script. Both environments:
- Have zero orphan entity components
- Can create new tables successfully
- Table creation test passed, test table created and cleaned up

This confirms the issue is isolated to the Test/Sandbox environment.

**4. The original tables that caused the orphans:**

The failed creation batch was attempting to create these tables (part of the `dcfg_agent_*` family):
- `dcfg_agent_config`
- `dcfg_agent_capabilities`
- `dcfg_agent_knowledge`
- `dcfg_agent_topics`
- `dcfg_agent_voice`
- `dcfg_agent_guardrails`

The operation was interrupted. Some tables may have partially created metadata entries that are now stuck in a half-created state — visible as solution components but not resolvable as EntityDefinitions.

---

## Workaround Applied

We worked around the issue by creating tables with an alternate naming prefix (`dcfg_ai_*` instead of `dcfg_agent_*`). This worked — suggesting the orphans are specifically tied to the `dcfg_agent_*` namespace, but we are uncertain whether the issue could re-surface or is causing other subtle metadata corruption.

**Tables successfully created with alternate names:**
- `dcfg_ai_capability` (was dcfg_agent_capabilities)
- `dcfg_ai_knowledge` (was dcfg_agent_knowledge)
- `dcfg_ai_topic` (was dcfg_agent_topics)
- `dcfg_ai_voice` (was dcfg_agent_voice)
- `dcfg_ai_guardrail` (was dcfg_agent_guardrails)

---

## What We Need Microsoft To Do

1. **Remove the orphaned solution component records** listed above from the Default solution in org0c17e98d (Test/Sandbox environment)
2. **Clean up any partial entity metadata** associated with the `dcfg_agent_*` prefix that may be stuck in an unpublished or corrupted state
3. **Confirm the environment is clean** — that new table creation (including with the `dcfg_agent_*` prefix) will work after cleanup

---

## Diagnostic Scripts (Available on Request)

| Script | Purpose |
|--------|---------|
| `tmp_find_orphan_tables.ps1` | Identifies orphan entity IDs in Default solution by testing each against EntityDefinitions |
| `tmp_delete_orphans.ps1` | Attempted removal via DELETE and RemoveSolutionComponent (both blocked) |
| `tmp_check_orphans_all_envs.ps1` | Verified Stage and Prod are clean — issue is Test-only |
| `Build-AI-Config-Tables.ps1` | The table creation script that works with `dcfg_ai_*` prefix after workaround |

---

## Environment Details

| Property | Value |
|----------|-------|
| Environment Name | DCFGSystems-Test |
| Environment Type | Sandbox |
| Org URL | https://org0c17e98d.crm.dynamics.com |
| Region | North America (crm.dynamics.com) |
| Solution | DCFGSystemTest (custom solution where tables are tracked) |
| Auth Method | Azure AD / Entra ID with `Get-AzAccessToken` |
| Dataverse API Version | 9.2 |
| Issue Start Date | Approximately April 5, 2026 |
| Affected Operation | `POST /api/data/v9.2/EntityDefinitions` — all new entity creation |
| Error Message | `"No rows could be found for the given key"` |
| Workaround | Rename tables to avoid orphan namespace collision (dcfg_ai_* instead of dcfg_agent_*) |

---

## Impact

This is a development/sandbox environment used for active application development. While we have a workaround, the orphaned records represent metadata corruption that could affect future operations (solution export/import, entity relationship creation, schema publishing). We'd like the environment cleaned up to prevent cascading issues.
