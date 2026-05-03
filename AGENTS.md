# DCFG Project — AI Agent Instructions

This file is read by OpenAI Codex and other AI agents. It mirrors the rules in CLAUDE.md (for Claude Code) and the Dataverse brain (dcfg_knowledge table, for any AI with MCP access).

## BOOT SEQUENCE — Execute Before ANY Response

1. **Query the brain.** Use the MCP `knowledge_search` tool to load `system_boot_sequence`, `system_rules_never_do`, `system_rules_always_do`, `system_key_file_locations`. These contain the full rules of the road.
2. **Read `docs/to-be-fixed.md`** — the running SPA issues/todos list. Know what's outstanding.
3. **Read the most recent `docs/handoff-*.md`** — context from the last session.
4. **If using pac CLI, run `pac auth list`** — verify which environment is active. Indices shift.
5. **Report what you found** before proceeding.

## BRAIN ACCESS

The DCFG Dataverse brain is configured as an MCP server (`dcfg-brain` in `.codex/config.toml`). It exposes these tools:

| Tool | Purpose |
|------|---------|
| `knowledge_search` | Search brain by keyword or name |
| `knowledge_get` | Get a specific knowledge record by ID |
| `brain_warm_context` | Load essential context for a topic |
| `dataverse_query` | Run any OData query against Dataverse |

**First query every session:** `knowledge_search` with query `system_` to load all system rules.

If MCP is not available, read `brain/knowledge-export.json` as a fallback (refresh with `pwsh -File scripts/export-brain.ps1`).

## CRITICAL RULES (summary — full rules in brain)

- **Prod is protected.** No writes to DCFGSystems-Prod without explicit operator authorization.
- **Never hard delete.** Soft delete via `dcfg_active_flag = false`.
- **SPA source (`spa/`) is read-only** unless explicitly authorized.
- **Investigate before asking.** Search repo and brain before asking the user for anything.
- **`docs/to-be-fixed.md` is the todo list.** Don't create new tracking files.
- **pac auth indices shift.** Always run `pac auth list` before any environment operation.

## ENVIRONMENTS

| Env | Org URL |
|-----|---------|
| Prod | org06f5de0b.crm.dynamics.com |
| Test | org0c17e98d.crm.dynamics.com |
| Stage | org88778bb0.crm.dynamics.com |
| Portal (READ-ONLY) | orgf625b080.crm.dynamics.com |

## KEY FILES

| What | Where |
|------|-------|
| SPA issues / todos | `docs/to-be-fixed.md` |
| Design specs | `docs/superpowers/specs/` |
| Session handoffs | `docs/handoff-*.md` |
| Prod baseline | `docs/baseline-2026-04-16/` |
| Brain export (offline) | `brain/knowledge-export.json` |
| PowerShell helpers | `PowerApps-Samples/dataverse/webapi/PS/Core.ps1` |
| SPA source (READ-ONLY) | `spa/dcfg-shell/src/` |
