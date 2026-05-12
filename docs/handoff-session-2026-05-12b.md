# Session Handoff — 2026-05-12 (afternoon)

## Branch
- **DMS**: `code-review-2026-04-09` — commit `cc01ee3`
- **dcfg-shell**: `main` — commit `3f901d4`

## Summary
Reviewed all outstanding todo items against codebase, validated status, then fixed DocGen OOXML template field mapping gaps (items 29-33). Two fixes deployed to Prod and verified with full 11-type E2E run.

## What Was Done

### 1. To-Be-Fixed Review & Cleanup
- Validated all 18 items in `docs/to-be-fixed.md` against actual codebase via 3 parallel exploration agents
- **Closed item 2**: DocuSign anchor logging already implemented in `ooxmlInject.js:110-113`
- **Closed items 4-7**: Rebuild issues all resolved or platform limitations (ownership mismatch = API limitation `0x80060888`)
- **Net**: 18 items → 8 remaining

### 2. DocGen Template Field Mapping Fixes (Prod Dataverse)
Queried all 12 document templates and their field mappings. Found 9 records with valid `dcfg_dataverse_path` but `dcfg_is_mapped = false`, preventing OOXML injection.

**PATCHed 9 records (all verified):**

| Template | Field | Path |
|----------|-------|------|
| Decades Vendor Agreement | Decades Datesigned | `[DOCUSIGN:\Decades_DateSigned\]` |
| Decades Vendor Agreement | Decades Signature | `[DOCUSIGN:\Decades_Signature\]` |
| Decades Vendor Agreement | Vendor Date Signed | `[DOCUSIGN:\Vendor_DateSigned\]` |
| Decades Vendor Agreement | Vendor Signature | `[DOCUSIGN:\Vendor_Signature\]` |
| Decades Workorder Amendment | Hour of Operations | `dcfg_work_hours` |
| Exhibit A - Automated | Days, Times | `dcfg_work_hours` |
| Exhibit A - Variable | Days, Times | `dcfg_work_hours` |
| Work Order Amendment | Hour of Operations | `dcfg_work_hours` |
| Work Order Amendment | Service Location Description | `dcfg_service_location_description` |

Updated `dcfg_mapped_count` on all 5 parent template records.

### 3. Unicode Apostrophe Fix (ooxmlInject.js)
E2E test revealed 4 yellow "Today's Date" highlights on ExhA-Auto. Root cause: Word templates use curly apostrophe U+2019 (`'`), Dataverse stores ASCII U+0027 (`'`). The OOXML injector's text matching failed on the mismatch.

**Fix:** Added `normQuotes()` helper to `ooxmlInject.js` that normalizes U+2018/2019 → `'` and U+201C/201D → `"` before matching. Applied to both `injectScalarFields` (line 105) and `injectBlockField` (line 176).

### 4. E2E Verification
- **Field validation test (ExhA-Auto)**: 0 yellow highlights (was 4). "Days, Times" now injecting. 9/13 fields found (4 missing = customer contact fields that need template placeholders — separate issue).
- **Full 11-type E2E**: All 11 generated and submitted successfully. Send Queue count assertion failed (10 vs 11 visible — known timing/status label issue from 2026-05-08).

## Deploys This Session
| Target | What | Status |
|--------|------|--------|
| Prod Dataverse | 9 template field mapping fixes + 5 template count updates | Complete |
| Prod SPA | ooxmlInject.js Unicode apostrophe normalization | Complete |

## Commits
| Repo | Commit | Message |
|------|--------|---------|
| dcfg-shell | `3f901d4` | fix(docgen): normalize Unicode smart quotes in OOXML field matching |
| DMS | `cc01ee3` | docs: close DocGen OOXML items 29-33, clean up to-be-fixed |

## Remaining Items (docs/to-be-fixed.md — 8 items)
1. DocuSign E2E — use real properties instead of fake locations
10. SALES → Resource Library screen (approved for build)
11. Admin controls menu visibility per role (partially built)
15. Scheduler embedded map — Google Maps API (approved for build)
19. Projects not showing trades (verify when E2E tests start)
20. Project screen not showing location (verify when E2E tests start)
24. Purge audit logs from test activity
38. Trades admin card (approved for build)

## Key Discovery
- `spa/dcfg-shell/` is a **separate git repo** (`github.com/joe-cameron/dcfg-shell.git`) nested inside the DMS repo. SPA source changes must be committed and pushed in that repo independently.
- The contract table is `dcfg_contract` (EntitySet: `dcfg_contracts`, 103 dcfg columns) — not `dcfg_contract_line`.
- `fetchTemplateFieldMappings()` in `portalApi.js:168` filters on `dcfg_is_mapped eq true` — fields with `false` are silently excluded from injection.
