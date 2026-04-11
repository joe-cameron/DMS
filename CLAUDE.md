# DCFG Project — Claude Code Instructions

## MANDATES — Non-Negotiable
1. **Look before you leap.** READ current state before every write. Query the table before creating a record. Check if the column exists before adding it. Verify which environment you're connected to before running anything. The investigation step is not optional — it IS the work.
2. **Limit token usage for database activity.** Use the fewest tokens possible for Dataverse operations. One targeted query beats a verbose script. Use known record IDs instead of searching when you have them. Never build a 200-line script when a 5-line inline command does the job. Every API call costs tokens — justify each one.

## READ FIRST
Load `~/.claude/projects/C--DCFG/memory/reference_system_snapshot.json` for complete system state.
Load `~/.claude/projects/C--DCFG/memory/reference_engineering_journal.md` for engineering lessons.

## SPA IS READ-ONLY
**C:\DCFG\spa\ is READ-ONLY. Do not create, edit, or delete any file under spa/.**
Read and search are allowed. All SPA changes require explicit permission from the operator.

## Current Architecture
- **Flow pattern:** Dataverse transaction table (`dcfg_document_requests`), NOT HTTP triggers
- **SPA function:** `createDocumentRequest()` — never `callFlow()`
- **Config:** `dcfg_configs` table read at boot via `loadConfig()` — no hardcoded URLs
- **Entity set:** `dcfg_properties` (NOT dcfg_propertys)
- **Solution name:** `DCFGSystemTest` (both environments)
- **Soft delete:** `dcfg_active_flag` — never hard delete

## Environments

| Env | Org URL | pac auth | Sites |
|-----|---------|----------|-------|
| **Test** (Sandbox) | org0c17e98d.crm.dynamics.com | `[1]` | dcfg.powerappsportals.com (SPA), decadeswelcomesyou.powerappsportals.com (Concierge SPA) |
| **Stage** | org88778bb0.crm.dynamics.com | `[2]` | holding.powerappsportals.com (SPA) |
| **Prod** | org06f5de0b.crm.dynamics.com | `[3]` | dmms1.powerappsportals.com (SPA) |
| **Portal** (READ-ONLY) | orgf625b080.crm.dynamics.com | `[6]` | decades.powerappsportals.com (legacy, non-SPA), decades-concierge.powerappsportals.com (Concierge SPA) |

- **Deploy order:** Test → Stage → Prod (operator specifies which envs per deploy)
- **Always restore pac auth to Test (index 1) after deploying**
- **Solution name:** `DCFGSystemTest` (all environments)

## Deploy Commands
```bash
cd C:\DCFG\spa\dcfg-shell
npm run build
pac pages upload-code-site --rootPath . --compiledPath dist
```
After deploy: clear cache + provide launch URLs.

## Flow Build Process (Three Steps)
1. Push placeholder definition (Compose actions for connection-dependent actions)
2. User manually adds one action per connector type in designer
3. Read back connection format, push full definition — NEVER overwrite triggers

## Rules
- Script vs Manual: evaluate manual path first (see script-vs-manual-judgment skill)
- Audit logging: Close/Delete/Restore all write to dcfg_audit_logs
- Table permissions: Append AND AppendTo on BOTH sides of relationships
- PowerShell: Connect() MUST have trailing slash, use pwsh not powershell
- **curl.exe is BLOCKED by endpoint security.** Use `Invoke-RestMethod` in pwsh instead. Never attempt curl.exe.
- Always clear portal cache after metadata changes
