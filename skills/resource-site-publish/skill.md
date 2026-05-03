---
name: resource-site-publish
description: Publish content to the DCFG internal resource site (Power Pages in Prod). Manages guides, review items, links, and tools. Uses Dataverse API to create/update powerpagecomponent records. Trigger on "publish to resource site", "share with the team", "add to resources", "send for review".
---

# Resource Site Publisher

## When to Use
Trigger on: "publish to resource site", "share with the team", "add to resources",
"put on the internal site", "send for review", "update the resource site",
"take down [item] from resource site"

## Site Configuration
Read `data/site-config.json` for websiteId, org URL, and pac auth indexes.
If websiteId is "PENDING_PROVISIONING", inform the operator that the Power Pages
site must be created first (run `pwsh C:\dcfg\dcfg-resources\scripts\create-resource-site.ps1`).

## Operating Modes

Check `mode` in site-config.json:

- **"base"** (default): Guides + Reviews + Tools only. The /assistant page shows "AI Assistant coming soon."
  Do NOT reference Copilot as active in any published content.
- **"copilot"**: Everything in base, plus /assistant embeds the Copilot Studio widget using `copilotEmbedSnippet`.

## Silo Rules
- This site is COMPLETELY SEPARATE from the SPA (C:\DCFG\spa\)
- Do NOT use `pac pages upload-code-site` — that is SPA-only
- Content is published via Dataverse API (powerpagecomponent records)
- Always include `powerpagesiteid` lookup in every record
- Always restore pac auth to index 1 (Test) after deployment

## Content Types

### Review Item
For sharing sites/pages for staff to review.
- Template: `templates/review-item.html`
- Replace: {{TITLE}}, {{DATE}}, {{DESCRIPTION}}, {{URL}}, {{CHECKLIST_ITEMS}}
- Publish to /reviews section

### Link Card
For adding quick-reference links to the tools page.
- Template: `templates/link-card.html`
- Replace: {{ICON}}, {{TITLE}}, {{DESCRIPTION}}, {{URL}}, {{URL_DISPLAY}}
- Publish to /tools section

### Guide Page
For publishing user manual HTML.
- Build guides first: `cd C:\dcfg\dcfg-resources\docs\user-manual && node build.mjs`
- Template: `templates/guide-page.html`
- Upload built HTML from `dist/` directory
- Upload screenshots as web file powerpagecomponent records
- Publish to /guides section

## Publishing Steps

1. Read `data/site-config.json` for websiteId and auth
2. Verify websiteId is not "PENDING_PROVISIONING"
3. Switch pac auth: `pac auth select --index {pacAuthIndex}`
4. Get auth token: `pac auth token --format json`
5. Create/update powerpagecomponent via Dataverse Web API:

```powershell
$token = (pac auth token --format json | ConvertFrom-Json).token
$body = @{
    name = "content-type-YYYY-MM-DD-slug"
    powerpagesiteid = "WEBSITEID"
    content = "RENDERED_HTML_CONTENT"
} | ConvertTo-Json -Depth 10

curl.exe -s -X POST "https://ORG_URL/api/data/v9.2/powerpagecomponents" `
    -H "Authorization: Bearer $token" `
    -H "Content-Type: application/json" `
    -d $body
```

6. Restore pac auth: `pac auth select --index {pacAuthRestoreIndex}`
7. Report the page URL to the operator
8. Remind operator to clear portal cache if needed

## Removal
Set `statecode = 1` (inactive) via PATCH. NEVER delete records.

```powershell
curl.exe -s -X PATCH "https://ORG_URL/api/data/v9.2/powerpagecomponents(RECORD_ID)" `
    -H "Authorization: Bearer $token" `
    -H "Content-Type: application/json" `
    -d '{"statecode": 1}'
```

## After Publishing
Always provide:
- Direct URL to the published page
- Reminder to clear portal cache if needed
- Confirmation of pac auth restored to Test (index 1)

## Project Location
All source files: `C:\dcfg\dcfg-resources\`
- Docs: `docs/user-manual/` (Markdown guides, build script, screenshots)
- KB: `docs/copilot-kb/` (Copilot knowledge base)
- Tests: `tests/` (Playwright screenshot capture)
- Scripts: `scripts/` (PowerShell deployment)
