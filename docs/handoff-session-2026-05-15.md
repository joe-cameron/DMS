# Session Handoff — 2026-05-15

## Branch
`code-review-2026-04-09`

## Summary
Debugged production data issues (ghost line items on contracts WO24168 and WO26010). Built and deployed 4 code fixes to Stage and Prod. Template update for Fix 4 is a manual Word step — see below.

---

## Fixes (Deployed to Stage + Prod)

### Fix 1 — SendQueue.jsx: Silent catch → Logged errors
**File:** `C:\DCFG\spa\dcfg-shell\src\screens\SendQueue.jsx`

Six `.catch(() => ({ value: [] }))` blocks replaced with logged versions that emit `[SendQueue]` prefixed console errors with HTTP status and message. This surfaces the actual failure reason when the Pending/Awaiting queue API calls fail — previously all failures were swallowed silently.

**Why:** 5 Pending send queue records exist in Dataverse but were not appearing in the SPA. Root cause is likely a failing `$expand` on one of the fetch calls, but we can't confirm without console output from a live session. Fix 1 makes the next failure visible.

---

### Fix 2 — ContractComposer.jsx + portalApi.js: PATCH-or-create line sync
**Files:**
- `C:\DCFG\spa\dcfg-shell\src\ContractComposer.jsx`
- `C:\DCFG\spa\dcfg-shell\src\portalApi.js`

**Root cause identified:** The 6-second auto-save cycle was calling `fetchContractLines` (active only) then soft-deleting all returned rows and re-creating all items from scratch. Every cycle produced N new `dcfg_contract_line` rows. Over time, contracts accumulated hundreds of ghost rows (most inactive). WO26010 had 10 rows: 9 inactive, 1 active at $35,804.

**Fix applied:**
- `portalApi.js`: `createContractLine()` changed from `apiPost` → `apiPostReturnId` so the returned GUID is available
- `ContractComposer.jsx` — `addItem`: new items initialized with `lineId: null`
- `ContractComposer.jsx` — `resumeDraft`: items loaded from Dataverse include `lineId` from `dcfg_contract_lineid`
- `ContractComposer.jsx` — `saveDraft` line sync block: replaced delete-all/create-all with PATCH-or-create:
  - Items with a known `lineId` → PATCH in place
  - New items (lineId null) → POST, returned GUID stored back into items state
  - Rows in Dataverse not in current items set → soft-delete (active_flag=false)
- `ContractComposer.jsx` — `handleGenerate` line sync block: same PATCH-or-create pattern (no state backfill needed since composer closes after generate)

---

### Fix 3 — ContractDetail.jsx: Add active_flag filter on line items
**File:** `C:\DCFG\spa\dcfg-shell\src\screens\ContractDetail.jsx`

The `fetchLines` call at line ~67 was missing `dcfg_active_flag eq true` in the OData filter. This caused the detail screen to display all line items including the soft-deleted ghost rows created by the old auto-save pattern.

**Fix:**
```
Before: $filter=_dcfg_contract_id_value eq ${id}&$orderby=dcfg_item_number asc
After:  $filter=_dcfg_contract_id_value eq ${id} and dcfg_active_flag eq true&$orderby=dcfg_item_number asc
```

---

### Fix 4 — contractDocGen.js: Fee written format (Option A)
**File:** `C:\DCFG\spa\dcfg-shell\src\lib\contractDocGen.js`

**Requirement:** Work order `[Contract Fee]` field should output fee spelled out in text plus numeric in parens.
Example: `Ten Thousand Three Hundred Fifty Dollars ($10,350.00)` instead of `$10,350.00`

**Code changes applied:**
- Added `numberToWords(n)` — converts integer to English words (handles up to billions)
- Added `fmtCurrencyWritten(val)` — returns `"Written Dollars ($X,XXX.XX)"` format. With cents: `"Written and XX/100 Dollars ($X,XXX.XX)"` (standard legal format)
- Written format applied in `buildContractFieldMap()` (NOT in `resolveFieldValue()`) — this is where both the placeholder name (`dcfg_source_text`) and the contract data are available
- Trigger conditions (ALL must be true): contract type is WO (100000000) or Amendment (100000001) AND `dcfg_dataverse_path` contains `contract_fee` AND `dcfg_source_text` is exactly "Contract Fee"

**Two placeholder names map to `dcfg_contract_fee` — each gets different formatting:**

Dataverse query confirmed these field mappings across all templates:

| Placeholder (dcfg_source_text) | Format Applied | Where Used |
|-------------------------------|----------------|------------|
| `Contract Fee` | Written: "Ten Thousand... Dollars ($10,350.00)" | Body text (fee sentence) |
| `Contract Value Dollars ($X.XX)` | Numeric only: "$10,350.00" | Summary/table display |

The code distinguishes by matching `dcfg_source_text` exactly — only "Contract Fee" gets the written format. "Contract Value Dollars ($X.XX)" is unaffected.

**Template update (manual — add new content control):**
Joseph will add a NEW `Contract Fee` content control in each WO/Amendment template where the written-out fee text should appear. The existing `Contract Value Dollars ($X.XX)` placeholders stay as-is for numeric display.

7 templates to update (4 Bancroft WO + 1 Decades WO + 2 Amendments):
1. Bancroft Work Order
2. Bancroft Blanket Work Order
3. Exhibit A - Automated (Bancroft)
4. Exhibit A - Variable (Bancroft)
5. Decades Work Order
6. Bancroft Work Order Amendment
7. Decades Work Order Amendment

For each: add a content control with source text "Contract Fee" mapped to `dcfg_contract_fee` in Admin > Templates where the written text should appear. Then add the field mapping row in Admin > Templates > Fields.

Expected outputs in generated docs:
- **`Contract Fee` placeholder** → "Ten Thousand Three Hundred Fifty Dollars ($10,350.00)"
- **`Contract Value Dollars ($X.XX)` placeholder** → "$10,350.00"

---

## Data State — WO24168 and WO26010

Both contracts were investigated directly in Dataverse. State at investigation time:

| Field | WO24168 | WO26010 |
|-------|---------|---------|
| Status | Draft | Draft |
| Generated date | null | null |
| Vendor | null | null |
| Property | null | null |
| Document URL | set | set |
| Send queue row | none | none |
| Line items | 3 rows (2 inactive ghosts, 1 active @ $10,350) | 10 rows (9 inactive, 1 active @ $35,804) |

These records were created during the ghost-row accumulation period. They are in Draft state and have no send queue rows, so they are not blocking operations. The 9 inactive rows on WO26010 are already soft-deleted (`dcfg_active_flag=false`) — they were the ghost rows left by the old auto-save. Fix 3 filters them from the UI, so no further data cleanup needed.

---

## Deploy Instructions (when ready)

All 4 code-complete fixes are in `C:\DCFG\spa\dcfg-shell\src\`. Deploy sequence:

**Deployed 2026-05-15:**

| Environment | Status | Duration |
|-------------|--------|----------|
| Stage (holding.powerappsportals.com) | Deployed | 632s |
| Prod (dmms1.powerappsportals.com) | Deployed | 592s |

pac auth restored to [2] Test after deploy. Clear portal cache on both environments if needed.

---

## Open Items

- **Template update (Joseph):** Add new "Contract Fee" content control + field mapping to each of the 7 WO/Amendment templates where written-out fee text should appear. Existing "Contract Value Dollars ($X.XX)" placeholders stay for numeric display. Code is safe to deploy independently.
- **WO24168 data state (confirmed):** 3 line items — 2 inactive ghosts ($0 "P", $1 "Pest Control Services"), 1 active ($10,350 "Pest Control Services"). Same ghost-row pattern as WO26010. Fix 3 filters them correctly.
- **SendQueue Pending not showing:** Fix 1 now live — check browser console on Prod for `[SendQueue]` errors to get actual failure reason.

## Verification Plan (add to e2e)

After deploy, verify each fix:
- **Fix 1:** Open SendQueue in browser DevTools console. Look for `[SendQueue]` prefixed errors if Pending tab is empty. If errors appear, they reveal the actual API failure.
- **Fix 2:** Open a WO contract in composer, add a line item, save. Wait 12+ seconds (two auto-save cycles). Query `dcfg_contract_lines` for that contract — row count should remain stable, not grow each cycle.
- **Fix 3:** Open ContractDetail for WO26010. Should show 1 active line item at $35,804, not 10 rows.
- **Fix 4:** Generate a Work Order document. Open the .docx and find the fee sentence. Should read "the liquidated sum of Ten Thousand Three Hundred Fifty Dollars ($10,350.00) inclusive..." — no nested parens, words capitalized, numeric in parens.

## Files Changed This Session

| File | Change |
|------|--------|
| `spa/dcfg-shell/src/screens/SendQueue.jsx` | Fix 1: logged catches |
| `spa/dcfg-shell/src/screens/ContractDetail.jsx` | Fix 3: active_flag filter |
| `spa/dcfg-shell/src/ContractComposer.jsx` | Fix 2: PATCH-or-create line sync |
| `spa/dcfg-shell/src/portalApi.js` | Fix 2: createContractLine returns ID |
| `spa/dcfg-shell/src/lib/contractDocGen.js` | Fix 4: numberToWords + fmtCurrencyWritten |
| `docs/handoff-session-2026-05-15.md` | This file |
