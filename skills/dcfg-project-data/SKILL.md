---
name: dcfg-project-data
description: "Authoritative source for all DCFG non-SPA project data — flow definitions, schema, permissions, environment config, entity sets, enums, and script templates. All data stored as JSON within this skill. ALWAYS load this skill when working with Dataverse, Power Automate, Power Pages metadata, or any infrastructure task. This skill replaces scattered filesystem files."
---

# DCFG Project Data — Single Source of Truth

All authoritative project data lives in `data/` as JSON files within this skill.
**Never read stale files from C:\DCFG\ when this skill has the current data.**

## Data Files

| File | Contains | Load When |
|---|---|---|
| `data/environments.json` | Org URLs, portal URLs, solution names, cache URLs | Any environment operation |
| `data/entity-sets.json` | All entity set names + logical names | Any Dataverse query |
| `data/enums.json` | All picklist/choice integer values | Any status/type reference |
| `data/flow-definitions.json` | Current flow definitions (v4 pattern) | Any flow work |
| `data/permissions-matrix.json` | Table permissions per role | Permission validation |
| `data/site-settings.json` | Required Web API site settings per table | Portal config |
| `data/schema.json` | Table columns, relationships, corrected names | Schema work |
| `data/scripts.json` | PowerShell script templates (parameterized) | Infrastructure automation |
| `data/audit-columns.json` | dcfg_audit_log correct column names | Any audit logging |

## Rules
- This skill is the authority. If a filesystem file contradicts this skill, this skill wins.
- When updating project data, update the JSON in this skill — not a random .ps1 or .md file.
- All JSON validated before storage.
