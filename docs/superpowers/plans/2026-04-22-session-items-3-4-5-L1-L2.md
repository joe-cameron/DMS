# Session 2026-04-22 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 5 SPA/function changes (bold injection, MSA list fix, Decades signer config, SharePoint link, locations template download) then deploy Stage parity.

**Architecture:** Four SPA file edits + one Azure Function edit. All changes are independent and can be done in parallel. Stage parity (Item 8) runs last after all SPA work is complete.

**Tech Stack:** React 16 (JSX + createElement), OOXML/XML regex, XLSX library, Vite bundler

---

## Chunk 1: Azure Function + SPA Code Changes

### Task 1: Global Bold on Injected Data (Item 5)

**Files:**
- Modify: `azure-functions/html-to-pdf/src/functions/htmlToPdf.js:141-157` (Content Control strategy)
- Modify: `azure-functions/html-to-pdf/src/functions/htmlToPdf.js:259-270` (Highlight strategy)
- Modify: `azure-functions/html-to-pdf/src/functions/htmlToPdf.js:183-186` (Merge Field strategy)

**Context:** The OOXML injection function has 5 strategies. Three produce text runs (`<w:r>`) that need bold. The DocuSign strategy uses its own rPr (white 1pt) — do NOT add bold there. The underline-blank strategy preserves signatures — do NOT modify.

- [ ] **Step 1: Add bold to Content Control strategy (lines 144-145)**

Current code extracts rPr from template and preserves it:
```javascript
const rPrMatch = content.match(/<w:rPr>([\s\S]*?)<\/w:rPr>/);
const rPr = rPrMatch ? `<w:rPr>${rPrMatch[1]}</w:rPr>` : '';
```

Replace with:
```javascript
const rPrMatch = content.match(/<w:rPr>([\s\S]*?)<\/w:rPr>/);
let rPrInner = rPrMatch ? rPrMatch[1] : '';
// Add bold to all injected values so filled-in data stands out
if (!/<w:b[\s/>]/.test(rPrInner)) rPrInner = '<w:b/>' + rPrInner;
const rPr = `<w:rPr>${rPrInner}</w:rPr>`;
```

- [ ] **Step 2: Add bold to Highlight strategy (line 262-266)**

Current code builds cleanRPr from the first highlighted run:
```javascript
let cleanRPr = firstRPr.replace(/<w:highlight[^/]*\/>/g, '');
if (!opts.clean_highlights) {
  cleanRPr = firstRPr; // keep highlight
}
const rPrTag = cleanRPr.trim() ? `<w:rPr>${cleanRPr}</w:rPr>` : '';
```

Replace with:
```javascript
let cleanRPr = firstRPr.replace(/<w:highlight[^/]*\/>/g, '');
if (!opts.clean_highlights) {
  cleanRPr = firstRPr; // keep highlight
}
// Add bold to all injected values
if (cleanRPr && !/<w:b[\s/>]/.test(cleanRPr)) cleanRPr = '<w:b/>' + cleanRPr;
else if (!cleanRPr) cleanRPr = '<w:b/>';
const rPrTag = `<w:rPr>${cleanRPr}</w:rPr>`;
```

- [ ] **Step 3: Add bold to Merge Field strategy (line 185)**

Current code creates a bare run with no formatting:
```javascript
return `<w:r><w:t xml:space="preserve">${escapeXml(value)}</w:t></w:r>`;
```

Replace with:
```javascript
return `<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">${escapeXml(value)}</w:t></w:r>`;
```

- [ ] **Step 4: Verify — read back all three changes**

Confirm the edits are correct and no DocuSign or underline-blank strategies were touched.

- [ ] **Step 5: Commit**

```bash
git add azure-functions/html-to-pdf/src/functions/htmlToPdf.js
git commit -m "feat(docgen): bold all injected field values in OOXML output"
```

---

### Task 2: MSA List Fixes (Item 4)

**Files:**
- Modify: `spa/dcfg-shell/src/screens/MsaList.jsx`

**Context:** The MSA status map has wrong labels (was Pending/Active/Expired, actual picklist is Draft/Proposal/Submitted/etc.). The `_typeCounts` column and "Location Mix" are dead scaffolding — remove entirely. Also remove unused `$select` columns `dcfg_location_list` and `dcfg_total_monthly`.

- [ ] **Step 1: Replace MSA_STATUS_MAP (lines 36-40)**

Replace:
```javascript
const MSA_STATUS_MAP = {
  100000000: { label: 'Pending', cls: 'badge-amber' },
  100000001: { label: 'Active',  cls: 'badge-green' },
  100000002: { label: 'Expired', cls: 'badge-red' },
};
```

With (values from Prod baseline picklist):
```javascript
const MSA_STATUS_MAP = {
  100000000: { label: 'Draft',            cls: 'badge-grey' },
  100000001: { label: 'Proposal',         cls: 'badge-amber' },
  100000002: { label: 'Submitted',        cls: 'badge-blue' },
  100000003: { label: 'Approved',         cls: 'badge-green' },
  100000004: { label: 'Closed',           cls: 'badge-grey' },
  100000005: { label: 'Void',             cls: 'badge-red' },
  100000006: { label: 'Declined',         cls: 'badge-red' },
  100000008: { label: 'WIP',              cls: 'badge-amber' },
  100000009: { label: 'Pending Approval', cls: 'badge-amber' },
  324160000: { label: 'Sent',             cls: 'badge-blue' },
  324160001: { label: 'Active',           cls: 'badge-green' },
  324160002: { label: 'Inactive',         cls: 'badge-grey' },
};
```

- [ ] **Step 2: Remove dead `$select` columns from query (line 49)**

In the `apiGet` query, remove `dcfg_location_list,dcfg_total_monthly` from `$select`.

Before:
```
$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_exhibit_type,dcfg_location_count,dcfg_location_list,dcfg_total_monthly
```

After:
```
$select=dcfg_msaid,dcfg_name,dcfg_status,dcfg_exhibit_type,dcfg_location_count
```

- [ ] **Step 3: Remove `_typeCounts` from row mapping (line 58)**

Delete line 58: `_typeCounts: {},`

- [ ] **Step 4: Remove Location Mix column header (line 98)**

Delete: `<th style={sortableThStyle} data-testid="msas-col-mix">Location Mix</th>`

- [ ] **Step 5: Remove Location Mix column rendering (lines 109, 115)**

Delete line 109: `const mixStr = Object.entries(m._typeCounts).map(([t,c]) => ...`
Delete line 115: `<td style={{fontSize:'12px',color:'#64748B'}}>{mixStr || ...}</td>`

- [ ] **Step 6: Update colspan**

Change `colSpan={6}` to `colSpan={5}` on the empty-state row (line 104).

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-shell/src/screens/MsaList.jsx
git commit -m "fix(MsaList): correct status labels from baseline picklist, remove dead Location Mix column"
```

---

### Task 3: Decades Signer Defaults in Admin (Item 3)

**Files:**
- Modify: `spa/dcfg-shell/src/screens/templates/TemplateList.jsx`

**Context:** TemplateList.jsx uses `h()` (React.createElement), NOT JSX. Match this style exactly. Add a "Company Signer" config panel below the header bar. Config keys: `dcfg_decades_signer_name` and `dcfg_decades_signer_title`. Use existing `apiGet`/`apiPatch`/`apiPostReturn` from portalApi.js. The `dcfg_configs` table has schema: `dcfg_key` (text), `dcfg_value` (text), `dcfg_active` (bool). Entity set: `configs` via `EntitySets.configs`.

- [ ] **Step 1: Add imports**

At line 9, add `apiPostReturn` and `getEnvVar` to the import:
```javascript
import { apiGet, apiPatch, apiPostReturn, EntitySets, getEnvVar, writeAuditLog, AuditActionType, formatDate } from '../../portalApi.js';
```

- [ ] **Step 2: Add CompanySignerConfig component before TemplateList export**

Insert before `export default function TemplateList` (before line 70):

```javascript
var SIGNER_KEYS = ['dcfg_decades_signer_name', 'dcfg_decades_signer_title'];

function CompanySignerConfig(props) {
  var toast = props.toast;
  var userEmail = props.userEmail;
  var nameState = useState('');
  var name = nameState[0]; var setName = nameState[1];
  var titleState = useState('');
  var title = titleState[0]; var setTitle = titleState[1];
  var idsState = useState({});
  var ids = idsState[0]; var setIds = idsState[1];
  var savingState = useState(false);
  var saving = savingState[0]; var setSaving = savingState[1];
  var dirtyState = useState(false);
  var dirty = dirtyState[0]; var setDirty = dirtyState[1];

  useEffect(function() {
    apiGet('/' + EntitySets.configs + '?$filter=(dcfg_key eq \'dcfg_decades_signer_name\' or dcfg_key eq \'dcfg_decades_signer_title\') and dcfg_active eq true&$select=dcfg_configid,dcfg_key,dcfg_value')
      .then(function(r) {
        var map = {}; var idMap = {};
        (r?.value || []).forEach(function(c) { map[c.dcfg_key] = c.dcfg_value || ''; idMap[c.dcfg_key] = c.dcfg_configid; });
        setName(map['dcfg_decades_signer_name'] || '');
        setTitle(map['dcfg_decades_signer_title'] || '');
        setIds(idMap);
      })
      .catch(function() {});
  }, []);

  async function saveSigner() {
    setSaving(true);
    try {
      var pairs = [
        { key: 'dcfg_decades_signer_name', val: name },
        { key: 'dcfg_decades_signer_title', val: title },
      ];
      for (var i = 0; i < pairs.length; i++) {
        var p = pairs[i];
        if (ids[p.key]) {
          await apiPatch('/' + EntitySets.configs + '(' + ids[p.key] + ')', { dcfg_value: p.val });
        } else {
          var created = await apiPostReturn('/' + EntitySets.configs, { dcfg_key: p.key, dcfg_value: p.val, dcfg_active: true });
          if (created?.dcfg_configid) {
            ids[p.key] = created.dcfg_configid;
            setIds(Object.assign({}, ids));
          }
        }
      }
      writeAuditLog({ targetTable: 'dcfg_config', targetRecordId: 'dcfg_decades_signer', actionType: AuditActionType.DataUpdated, performedBy: userEmail, newValue: name + ' / ' + title }).catch(function() {});
      setDirty(false);
      toast.show('ok', 'Company signer saved');
    } catch (e) {
      toast.show('err', 'Failed: ' + e.message);
    }
    setSaving(false);
  }

  var inputStyle = {
    padding: '6px 10px', fontSize: '13px', borderRadius: '6px',
    border: '1px solid #CBD5E1', background: '#FFFFFF', color: NAVY,
    fontFamily: "'IBM Plex Sans', sans-serif", width: '200px',
  };

  var labelStyle = { fontSize: '12px', color: '#64748B', marginBottom: 2 };

  return h('div', {
    style: { display: 'flex', alignItems: 'flex-end', gap: 16, padding: '12px 16px', background: '#F8FAFC', borderRadius: 8, marginBottom: 16 },
    'data-testid': 'company-signer-config',
  },
    h('div', { style: { display: 'flex', flexDirection: 'column' } },
      h('label', { style: labelStyle }, 'Company Signer Name'),
      h('input', {
        value: name, onChange: function(e) { setName(e.target.value); setDirty(true); },
        style: inputStyle, placeholder: 'e.g. Bill Bamford',
        'data-testid': 'input-signer-name',
      })
    ),
    h('div', { style: { display: 'flex', flexDirection: 'column' } },
      h('label', { style: labelStyle }, 'Company Signer Title'),
      h('input', {
        value: title, onChange: function(e) { setTitle(e.target.value); setDirty(true); },
        style: inputStyle, placeholder: 'e.g. President',
        'data-testid': 'input-signer-title',
      })
    ),
    dirty && h('button', {
      onClick: saveSigner, disabled: saving,
      style: {
        padding: '6px 16px', borderRadius: '6px', border: 'none',
        background: NAVY, color: '#FFFFFF', fontSize: '13px', fontWeight: 600,
        cursor: saving ? 'wait' : 'pointer', opacity: saving ? 0.6 : 1,
      },
      'data-testid': 'btn-save-signer',
    }, saving ? 'Saving...' : 'Save')
  );
}
```

- [ ] **Step 3: Render CompanySignerConfig in TemplateList**

After the header `h('div', ...)` block (after the closing paren around line 323), add:

```javascript
h(CompanySignerConfig, { toast: toast, userEmail: user?.email || 'admin' }),
```

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-shell/src/screens/templates/TemplateList.jsx
git commit -m "feat(admin): add Company Signer name/title config to Template Management screen"
```

---

### Task 4: SharePoint Library Link on Template Management (Link 1)

**Files:**
- Modify: `spa/dcfg-shell/src/screens/templates/TemplateList.jsx`

**Context:** `getEnvVar('dcfg_sp_site_url')` returns the SharePoint site URL. `getEnvVar('dcfg_sp_templates_library')` returns the library name (e.g., `DCFG_Templates`). Combine to build browseable URL. `getEnvVar` is already imported in Task 3 Step 1.

- [ ] **Step 1: Add SharePoint link to header bar**

In the header div (line 311), add a new button before "Tag Reference":

```javascript
h('a', {
  href: (getEnvVar('dcfg_sp_site_url') || '') + '/' + (getEnvVar('dcfg_sp_templates_library') || 'DCFG_Templates'),
  target: '_blank',
  rel: 'noopener',
  style: Object.assign({}, primaryBtn, {
    background: '#2E5295', textDecoration: 'none', display: 'inline-block',
  }),
  'data-testid': 'btn-sharepoint-library',
}, 'SharePoint Library'),
```

Insert this as the first element inside the `h('div', { style: { display: 'flex', gap: '8px' } }, ...)` on line 311.

- [ ] **Step 2: Commit**

```bash
git add spa/dcfg-shell/src/screens/templates/TemplateList.jsx
git commit -m "feat(admin): add SharePoint Templates library link to Template Management header"
```

**Note:** Tasks 3 and 4 both modify TemplateList.jsx. If done by same agent, combine into one commit. If parallel agents, merge carefully.

---

### Task 5: Locations Template Download Button (Link 2)

**Files:**
- Modify: `spa/dcfg-shell/src/MsaComposer.jsx:949-961`

**Context:** XLSX library is already imported (`import * as XLSX from 'xlsx'`). The LocationsSection function already has access to it. Add a "Download Template" button that generates a minimal .xlsx with the expected headers and triggers a browser download.

- [ ] **Step 1: Add download function inside LocationsSection**

Insert before the `return (` statement in LocationsSection (before line 943):

```javascript
function downloadLocationsTemplate() {
  var ws = XLSX.utils.aoa_to_sheet([['name', 'address', 'city', 'state', 'zip', 'type']]);
  ws['!cols'] = [{ wch: 30 }, { wch: 35 }, { wch: 20 }, { wch: 8 }, { wch: 10 }, { wch: 20 }];
  var wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Locations');
  XLSX.writeFile(wb, 'locations-template.xlsx');
}
```

- [ ] **Step 2: Add download button next to Import Spreadsheet**

In the button container (line 949-961), add a new button before the Import button:

Change from:
```jsx
<div style={{ display: 'flex', gap: 8 }}>
  <input ... />
  <button onClick={() => csvInputRef.current?.click()} ...>Import Spreadsheet</button>
</div>
```

To:
```jsx
<div style={{ display: 'flex', gap: 8 }}>
  <input ... />
  <button onClick={downloadLocationsTemplate} style={{ ...btnStyle(false), padding: '6px 12px' }} data-testid="btn-download-loc-template">
    Download Template
  </button>
  <button onClick={() => csvInputRef.current?.click()} ...>Import Spreadsheet</button>
</div>
```

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-shell/src/MsaComposer.jsx
git commit -m "feat(MsaComposer): add Download Template button for locations spreadsheet"
```

---

## Chunk 2: Stage Parity (Item 8) — Execute LAST

### Task 6: Stage Parity Deploy

**Prerequisite:** All Tasks 1-5 committed. SPA build succeeds.

**Context:** Stage (org88778bb0, pac auth index per `pac auth list`) is behind Prod by: 15 missing tables, 38+ missing columns, 12 missing picklist values, and several SPA deploys. Hybrid approach: solution export/import for Dataverse schema, then SPA deploy.

- [ ] **Step 1: Verify pac auth indices**

```bash
pac auth list
```

Record which index is Stage. Per memory, indices may have shifted — ALWAYS verify.

- [ ] **Step 2: Export DCFGSystemTest solution from Prod**

```bash
pac auth select --index {PROD_INDEX}
pac solution export --name DCFGSystemTest --path C:\dcfg\_stage_solution\DCFGSystemTest_prod.zip --overwrite
```

- [ ] **Step 3: Import solution to Stage**

```bash
pac auth select --index {STAGE_INDEX}
pac solution import --path C:\dcfg\_stage_solution\DCFGSystemTest_prod.zip --force-overwrite --publish-changes
```

If `dcfg_rfp_package` ownership mismatch blocks import: operator must manually change table ownership in Stage admin center before retry.

- [ ] **Step 4: Build SPA**

```bash
cd C:\dcfg\spa\dcfg-shell
npm run build
```

- [ ] **Step 5: Deploy SPA to Stage**

**REQUIRES EXPLICIT OPERATOR APPROVAL — ASK BEFORE RUNNING**

```bash
pac auth select --index {STAGE_INDEX}
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 6: Restore pac auth to Test**

```bash
pac auth select --index {TEST_INDEX}
```

- [ ] **Step 7: Verify Stage — provide launch URL**

Provide: `https://holding.powerappsportals.com` + cache clear instructions.

- [ ] **Step 8: Commit any Stage-specific config scripts**

If PowerShell scripts were created for site settings or table permissions, commit them.
