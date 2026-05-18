# Session Handoff — 2026-05-17

## Branch
`code-review-2026-04-09`

## Summary
Built the Office Document Harness skill (2D spatial review + SDT + formatting tools), fixed 55 WRAP indentation issues across 5 templates, added Contract Fee SDTs to 5 WO/Amendment templates, deployed Phase 2 field alignment to Stage + Prod, fixed dcfg_trade_type permissions gap, and ran E2E document validation.

---

## Phase 0 — Office Document Harness Skill (Built)

Rewrote `skills/office-file-editor/` from a text-only find/replace tool into a full document review and editing harness.

### New Capabilities

| Command | Purpose |
|---------|---------|
| `review <file>` | 2D spatial model of document — XY coordinates for every element, anomaly detection |
| `review-fix <file> "R01,R03"` | Apply approved fixes surgically by finding ID |
| `sdt-list/find/replace/add` | Content control (SDT) operations |
| `format-audit/list-audit/fix-indent` | Paragraph formatting analysis and repair |
| `inspect-deep` | Full structural analysis (SDTs, numbering, styles, images, placeholders) |

### Key Concept — 2D Spatial Plane
Since we can't see documents, the `review` command builds a spatial model with XY coordinates for every paragraph. It computes where text starts, where wrapped lines continue, and flags when those don't match (the WRAP bug). It also detects section breaks that change page geometry mid-document, signature table structure, and mixed justification.

### Files Created/Modified
- `skills/office-file-editor/SKILL.md` — rewritten as controller with review workflow
- `skills/office-file-editor/office_edit.py` — enhanced from 477 to ~1200 lines, 18 CLI commands
- `skills/office-file-editor/references/` — 7 new reference docs (wordprocessingml, content-controls, numbering-and-lists, formatting-preservation, business-presentation-standards, spreadsheetml, presentationml)
- `skills/office-file-editor/droids/` — 8 droid definitions (document-review, word-sdt, word-format, word-numbering, word-table, validation, excel-cell, pptx-slide)

### Originals Backed Up
All original skill files backed up with `.original-2026-05-17` suffix.

---

## Phase 1 — Template Fixes (Applied)

### WRAP Indentation Fixes — 55 paragraphs across 5 templates

List paragraphs had `<w:numPr>` (numbering reference) but no `<w:ind>` (indentation), causing wrapped text to snap to the left margin instead of aligning with first-line text.

| Template | Fixes | High Issues After |
|----------|:---:|:---:|
| Blanket Work Order | 4 | 0 |
| Work Order Amendment | 8 | 0 |
| Decades Vendor Agreement | 19 | 0 |
| Exhibit A — Automated | 12 | 0 |
| Exhibit A — Variable | 12 | 0 |
| Bancroft Vendor Agreement | 0 (clean) | 0 |
| Decades Work Order | 0 (clean) | 0 |

### Contract Fee SDT — Added to 5 templates

Inline plain-text SDT with `tag="contract_fee"` inserted after "shall be" in each fee sentence:
- Blanket Work Order
- Work Order Amendment
- Decades Work Order
- Exhibit A — Automated
- Exhibit A — Variable

The SDT is correctly placed but `ooxmlInject.js` doesn't yet match SDTs — it only matches yellow-highlighted runs. See "Open Items" below.

### Template Backups
- Pre-session originals: `scripts/_backups/2026-05-17_office-harness-before/templates/` (11 files)
- Per-edit backups: `Templates/corrected/*.bak.*` timestamped files
- Dataverse backup: `scripts/_backups/2026-05-17_office-harness-before/document-templates-prod.json` (32 records) + `template-fields-prod.json` (665 records)

### Templates NOT Yet Uploaded
The corrected templates in `Templates/corrected/` have the fixes but have NOT been uploaded to Dataverse. The production templates still have the old formatting. Upload requires replacing the file column on each `dcfg_document_template` record.

---

## Phase 2 — Field Alignment Deployed

SPA code from last session (Phase 2 field alignment) built and deployed.

| Environment | Status | Duration |
|-------------|--------|----------|
| Stage (holding.powerappsportals.com) | Deployed | 746s |
| Prod (dmms1.powerappsportals.com) | Deployed | 626s |

### Schema Changes on Stage
6 new columns created on Stage `dcfg_contract` (already existed on Prod):
- `dcfg_msa_number` (String), `dcfg_msa_date` (DateTime)
- `dcfg_billing_address`, `dcfg_billing_city`, `dcfg_billing_state`, `dcfg_billing_zip` (String)

### Site Settings Updated
- Stage `Webapi/dcfg_contract/fields` — added 7 columns (msa_number, msa_date, billing_*, work_hours)
- Portal cache cleared on both Stage and Prod

pac auth restored to [2] Test.

---

## Phase 3 — Permissions Validation

### Results: 12 PASS, 1 FIXED, 1 not needed

All 14 tables audited on Prod for webapi site settings + table permissions.

**Fixed this session:**
- `dcfg_trade_type` — was missing webapi settings. Created `Webapi/dcfg_trade_type/enabled=true` and `fields` on both Prod and Stage. 40 trade types already populated in table. `fetchTradeTypes()` will now work. Table permission is Read-only (correct — reference data).

**False alarm corrected:**
- `dcfg_cost_code` — Phase 3 initially reported FAIL. Actual table is `dcfg_ap_cost_code` (different name). Already has webapi enabled + 13 fields + Global CRUD permission. PASS.

**Not needed:**
- `dcfg_cost_code` logical name doesn't exist as a table. The SPA uses `dcfg_ap_cost_codes` entity set which maps to `dcfg_ap_cost_code` table.

### Audit artifacts
- `scratch/phase3-webapi-audit.json`
- `scratch/phase3-tableperm-audit.json`

---

## Phase 4 — E2E Document Validation

### Test: WO24168 x Blanket Work Order

| Field | Expected | Injected | Status |
|-------|----------|:---:|:---:|
| VENDOR NAME | Lady Bug Pest Services | Yes | PASS |
| Contractor Printed Name | Zoe Buckridee | Yes | PASS |
| Contractor Title | Commercial Accounts Specialist | Yes | PASS |
| Customer Contact Name | Sarah Mitchell | Yes | PASS |
| Customer Title | Director of Operations | Yes | PASS |
| Tele# | 908-317-8576 | Yes (x2) | PASS |
| email address (Vendor) | office@ladybugpest.com | Yes | PASS |
| Vendor Street Address | 474 North Ave East, Westfield NJ,07091 | Yes | PASS |
| WO Number | WO24168 | Yes | PASS |
| Today's Date | 05/17/2026 | Yes | PASS |
| Contract Fee (written) | Ten Thousand Three Hundred Fifty Dollars ($10,350.00) | Yes (via SDT) | PASS |
| Contract Fee (numeric) | $10,350.00 | Yes (in written format) | PASS |
| Vendor Contact composite | Zoe Buckridee, 908-317-8576, office@ladybugpest.com | Yes | PASS |
| Address composite (city) | Westfield | Yes | PASS |
| DocuSign anchors | Customer_Signature, Vendor_Signature | Already in template | PASS |
| VENDOR NAME placeholder removed | — | Gone | PASS |
| Contract Fee placeholder removed | — | Gone (SDT injected) | PASS |

**18/18 fields PASS** after SDT injection fix + composite flat-field fix.

### E2E Fix Deploys (applied same session)

Strict validation revealed 2 code bugs that were fixed and deployed:

**Fix A — `ooxmlInject.js`: SDT injection pass**
- Added pass after yellow-highlight scalar injection
- Matches `<w:sdt>` elements by `<w:tag>` value (sourceText normalized to snake_case)
- Replaces `<w:sdtContent>` while preserving `<w:sdtPr>`
- Closes Contract Fee written-format gap

**Fix B — `contractDocGen.js`: flat-field composites**
- Updated 4 composite definitions from vendor/customer lookup paths to flat contract fields:
  - `vendor_contact`: `dcfg_signer_printed`, `dcfg_contractor_phone`, `dcfg_contractor_email`
  - `vendor_address_block`: `dcfg_contractor_address`, `dcfg_billing_city/state/zip`
  - `vendor_signer_contact`: same as vendor_contact
  - `customer_billing_address`: `dcfg_billing_address/city/state/zip`
- Aligns with contract-record-as-source-of-truth principle

**Deploy:** SPA commit `8fca2fe` on `joe-cameron/dcfg-shell main`. Deployed to Stage (920s) + Prod (1044s).

### Formatting
- 0 high-severity findings in output document
- Indentation preserved through injection
- Signature table intact (2 cols, 5 rows, 6.50")
- Output file: `scratch/e2e-WO24168-BWO-output.docx`

---

## Open Items

1. **Upload corrected templates to Dataverse** — Templates in `Templates/corrected/` have WRAP fixes + Contract Fee SDTs but haven't been uploaded to production. Need to replace file column on each `dcfg_document_template` record.

2. **Phase 3-4 of field alignment** — Per `docs/superpowers/plans/2026-05-15-docgen-field-alignment.md`:
   - Phase 3: 20 vendor MSA columns (5 slots x number/date/customer/status), VA composer -> slot wiring, DocuSign poll status update
   - Phase 4: Address formatting (State,Zip -> State Zip)

3. **Clear portal cache after template upload** — Once corrected templates are uploaded, clear cache on both environments.

4. **Phase 5 of plan (data-testid coverage)** — Not started. ContractComposer already at 98% coverage. MsaComposer at 85%. Minor gaps only.

5. **"Contact Name, Tele#" template split** — Yellow highlight on comma between "Contact Name," and "Tele#" is missing in BWO template, breaking the run group. Individual fields still inject correctly. Low priority — fix by re-highlighting the comma in Word.

---

## Deploys This Session

| Deploy | Environment | Duration | What |
|--------|-------------|----------|------|
| 1 | Stage | 746s | Phase 2 field alignment |
| 2 | Prod | 626s | Phase 2 field alignment |
| 3 | Stage | 920s | E2E fixes (SDT injection + flat composites) |
| 4 | Prod | 1044s | E2E fixes (SDT injection + flat composites) |

## Files Changed This Session

| File | Change |
|------|--------|
| `spa/dcfg-shell/src/lib/ooxmlInject.js` | Added SDT injection pass (matches by `<w:tag>`) |
| `spa/dcfg-shell/src/lib/contractDocGen.js` | Fixed 4 composite definitions to use flat contract fields |
| `skills/office-file-editor/SKILL.md` | Rewritten as controller with 2D review workflow |
| `skills/office-file-editor/office_edit.py` | Enhanced: 18 commands (was 7), SDT ops, formatting, review |
| `skills/office-file-editor/references/*.md` | 7 new OOXML reference docs |
| `skills/office-file-editor/droids/*.md` | 8 new droid definitions |
| `Templates/corrected/*.docx` | 5 templates: WRAP fixes + Contract Fee SDTs |
| `scripts/_backups/2026-05-17_office-harness-before/` | Pre-session backups (templates + Dataverse JSON) |
| `scratch/phase3-webapi-audit.json` | Webapi site settings audit |
| `scratch/phase3-tableperm-audit.json` | Table permissions audit |
| `scratch/phase4-test-contracts.json` | Test contract data |
| `scratch/phase4-expected-values-wo24168.json` | Expected field values |
| `scratch/e2e-WO24168-BWO-output.docx` | E2E injection output |
| `docs/handoff-session-2026-05-17.md` | This file |
| Dataverse (Prod) | `Webapi/dcfg_trade_type/enabled` + `fields` site settings created |
| Dataverse (Stage) | Same trade_type settings + 6 Phase 2 columns + contract fields setting updated |
| Stage + Prod SPA | 4 deploys (Phase 2 alignment + E2E fixes) |
