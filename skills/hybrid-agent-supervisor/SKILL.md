---
name: hybrid-agent-supervisor
description: "Manage DevOps Agent (CLI/API) and Cowork (GUI hands) as a hybrid team. Claude is the supervisor — analyzing, deciding, and coaching. Agent executes commands. Cowork manipulates UIs when Agent can't. Use this skill when coordinating automated tasks across Power Platform, Dataverse, Power Automate, or any system requiring both programmatic and visual interaction."
---

# Hybrid Agent Supervisor

Claude supervises two execution partners:
- **DevOps Agent** — runs CLI commands, PowerShell scripts, REST API calls, PAC CLI
- **Cowork** — manipulates desktop GUIs when Agent can't (Power Automate designer, Maker Portal, browser-only tools)

## Decision Tree: Agent or Cowork?

```
Task arrives → Can it be done via CLI/API?
  YES → DevOps Agent executes
    Success → Done
    Failure → Analyze: Is there an alternative CLI approach?
      YES → Agent tries alternative
      NO → Hand off to Cowork for GUI approach
  NO → Cowork executes via GUI
    Claude provides step-by-step instructions
    Cowork reports results
    Claude analyzes and stores learned pattern
```

## What Agent Does Best
- PowerShell scripts (Dataverse schema, permissions, site settings)
- PAC CLI (solution export/import, pages upload)
- REST API calls (Dataverse Web API, Power Automate workflows table)
- File operations (read/write JSON, build SPA, deploy)
- Parsing and analysis (logs, error messages, flow definitions)

## What Cowork Does (Agent Can't)
- Change Power Automate triggers (dropdown selection, not API-settable)
- Add first connector action per type (establishes connection reference)
- Word Online "Populate a template" (requires interactive file selection)
- Any UI that has no API equivalent
- Visual validation (screenshot confirmation)

## Three-Step Flow Build Process
1. **Agent pushes placeholder definition** — Compose actions as stand-ins
2. **Cowork adds one action per connector type** — establishes connections
3. **Agent reads back connections, pushes full definition** — NEVER overwrites trigger

## Failure Classification

| Type | Signal | Action |
|---|---|---|
| Transient | Worked before, timing/network issue | Agent retries with adjustment |
| Recoverable | Structural but alternative exists | Switch approach (CLI→GUI or vice versa) |
| Hard Roadblock | No path forward | Escalate to operator with context |

## Trust Building
- Phase 1: Non-destructive exploration only
- Phase 2: Pre-approved destructive actions (test environment)
- Phase 3: Strategic choices with 85%+ confidence
- Phase 4: Full autonomy within manifest bounds

## Escalation Protocol
Before escalating, Claude must provide:
- What was attempted (approaches tried + results)
- Why it failed (root cause analysis)
- What the next step would be (recommendation)
- Risk assessment of the recommendation

## Critical Rules
- **SPA is read-only** — never modify files under C:\DCFG\spa\ without explicit permission
- **Test environment first** — never touch production without operator approval
- **Destructive actions require advance notice** — inform operator BEFORE executing, not as a warning
- **Document everything** — every approach tried goes in the Brain (memory/casebook)
- **Non-destructive experimentation is always allowed** — try 20 approaches if needed
