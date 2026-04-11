# DCFG Help System — Implementation Plan (4:00 PM 2026-04-02)

## Goal
Make the PB&J guide accessible to all portal users with context-aware help per screen.

## Prerequisites (Done Before 4 PM)
- [x] Screenshots captured via Playwright against prod
- [x] Landscape PDF generated
- [ ] Operator grants SPA write permission for this feature

## Deliverables

### 1. Dataverse Table: `dcfg_help_articles`
| Column | Type | Purpose |
|--------|------|---------|
| dcfg_name | Text (200) | Article title |
| dcfg_screen_key | Text (50) | Maps to SPA route (e.g. "contracts", "contract-wizard-step1") |
| dcfg_body_html | Multiline (max) | Rich HTML content with inline images |
| dcfg_sort_order | Whole Number | Display order within module |
| dcfg_module | Choice | Dashboard / Contracts / Proposals / Onboarding / Locations / Admin |
| dcfg_is_active | Boolean | Soft delete |

- Add to DCFGSystemTest solution
- Web API site settings for portal read access
- Table permission: Global Read for Authenticated Users

### 2. Seed Data
- Parse `docgen-pbj-guide.html` into individual articles
- One row per section (prereqs, each doc type, behind-the-scenes)
- Screenshots embedded as base64 in body_html or referenced via SharePoint URL
- Total: ~15 articles

### 3. SPA Changes (requires operator permission)

#### a. `portalApi.js` — Add help query function
```javascript
export async function getHelpArticles(screenKey) {
  const filter = screenKey
    ? `$filter=dcfg_screen_key eq '${screenKey}' and dcfg_is_active eq true`
    : `$filter=dcfg_is_active eq true`;
  return odata(`dcfg_help_articles?${filter}&$orderby=dcfg_sort_order`);
}
```

#### b. `HelpPanel.jsx` — New component
- Slide-out panel from right side (480px wide)
- Triggered by `?` icon button in NavPanel
- Shows articles filtered by current route's screen_key
- "View Full Guide" link at bottom opens standalone /help
- Matches DCFG design system (navy/white/gold)

#### c. `HelpPage.jsx` — New route `/help`
- Full standalone page showing all articles in module order
- TOC at top (same as current guide)
- Screenshots inline
- Searchable (client-side filter)
- Accessible to all authenticated users

#### d. `NavPanel.jsx` — Add help button
- `?` icon button at bottom of nav
- Opens HelpPanel
- data-testid="btn-help"

#### e. `App.jsx` — Add /help route
- `<Route path="/help" component={HelpPage} />`

### 4. Build & Deploy
- `npm run build` in dcfg-shell
- `pac pages upload-code-site` to Test
- Clear cache
- Verify on dcfg.powerappsportals.com

## Execution Order
1. Create Dataverse table + permissions (5 min script)
2. Seed articles from parsed guide (script)
3. SPA changes — portalApi, HelpPanel, HelpPage, NavPanel, App (code)
4. Build + deploy to Test
5. Verify
6. Deploy to Prod when approved

## Estimated Scope
- 1 new Dataverse table
- 1 new API function
- 3 new SPA files (HelpPanel, HelpPage, help query)
- 2 modified SPA files (NavPanel, App)
- ~15 seed records
