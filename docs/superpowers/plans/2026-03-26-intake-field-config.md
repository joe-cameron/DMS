# Intake Field Configuration & Live Persistence — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add admin config matrix for per-location-type field visibility, refactor intake form to dynamically reshape based on config, replace localStorage with live Dataverse persistence with offline fallback.

**Architecture:** Two-layer config (defaults by location type + per-property overrides) stored in Dataverse. Intake form queries config on load and reshapes sections. All writes go to staging tables (dcfg_property_intake, dcfg_intake_vendor, dcfg_intake_authorized_user) under a parent session record. localStorage serves as offline fallback only. Record locking prevents concurrent edits — full-state push on reconnect is safe.

**Tech Stack:** React 17 (CDN), Vite 5, Power Pages Web API (OData), Dataverse

**Spec:** `docs/superpowers/specs/2026-03-26-intake-field-config-design.md`

**Review fixes applied (round 1 + regulator review):**
- C1: Added `useMemo` to React import in Task 3
- C3: Hidden-field data logic deferred — belongs in "Review/Approve" spec (explicitly out of scope)
- I2: "Set Defaults" button on first config load — pre-populates sensible defaults, no ambiguity
- I4: OData injection guard added — sanitize access code input before filter queries
- I6: `updateData` callers audited — `scheduleSave` signature change handled
- **Record locking replaces merge logic** — lock property on edit, 30-min auto-expire, override with safety warning. Full-state push on reconnect is safe. Per-field timestamps eliminated.
- **Vendors simplified** — contact info (name, service, phone) + document/photo upload. Not full CRUD.
- **Auto-login on mount** — cached code triggers handleLogin automatically
- **Table permissions** — added as Task 4b (real task, not hand-wave)
- **Entity set verification** — added as step after table creation
- **Working PowerShell** — table creation script is real automation, not stubs

**Important constraints:**
- `C:\dcfg\spa\` is READ-ONLY by default. Operator has granted write permission for this plan.
- dcfg-property-intake Power Pages site is NOT yet provisioned. Dataverse persistence can be built but not tested end-to-end until site is live. Build with a `USE_DATAVERSE` flag that falls back to localStorage when the API is unavailable.
- No unit test framework exists in either SPA. Verification is manual + Playwright (future). Each task includes manual verification steps.

---

## Dependency Map

```
Task 1: Field Key Registry (shared constant)
  ↓
Task 2: Entity Sets in portalApi.js (dcfg-shell)
  ↓
Task 3: Admin Config Matrix tab (dcfg-shell) — depends on Task 1, 2
  ↓                                              ↓ (parallel)
Task 4: Dataverse Table Creation (PowerShell)    Task 4a: Verify entity set names
  ↓                                              ↓
Task 4b: Table Permissions (PowerShell)          Task 4a feeds back to Task 2, 5
  ↓
Task 5: Intake API Layer (dcfg-property-intake) — depends on Task 1, 4a
  ↓
Task 6: Intake Form Dynamic Config — depends on Task 1, 5
  ↓
Task 7: Intake Form Dataverse Persistence + Record Locking — depends on Task 5
  ↓
Task 8: Session Resilience + Auto-Login — depends on Task 7
  ↓
Task 9: Vendor & Authorized User Persistence — depends on Task 5
```

Tasks 3 and 4 can run in parallel. Tasks 6-9 are sequential.

---

## Chunk 1: Foundation

### Task 1: Field Key Registry

A shared constant mapping field keys to their display names, section groupings, and default visibility. Used by both the admin config matrix and the intake form.

**Files:**
- Create: `C:\dcfg\spa\dcfg-shell\src\intakeFieldKeys.js`
- Create: `C:\dcfg\spa\dcfg-property-intake\src\intakeFieldKeys.js` (identical copy — no shared module system between SPAs)

- [ ] **Step 1: Create the field key registry file**

```javascript
/**
 * Intake form field keys — shared registry for config matrix and form rendering.
 * Each key maps to a configurable row in the admin Intake Fields matrix.
 * Sections 1 (Location Identity) and 2 (Site Contact) are always shown.
 */
export const INTAKE_FIELD_KEYS = [
  // Section 3: Home Details
  { key: 'structure',       section: 'Home Details',       label: 'Structure',              sectionNum: 3 },
  { key: 'roofExterior',    section: 'Home Details',       label: 'Roof & Exterior',        sectionNum: 3 },
  { key: 'utilitiesAccess', section: 'Home Details',       label: 'Utilities & Access',     sectionNum: 3 },
  // Section 4: Features & Systems
  { key: 'lockBox',         section: 'Features & Systems', label: 'Lock Box',               sectionNum: 4 },
  { key: 'pool',            section: 'Features & Systems', label: 'Pool',                   sectionNum: 4 },
  { key: 'generator',       section: 'Features & Systems', label: 'Generator',              sectionNum: 4 },
  { key: 'garage',          section: 'Features & Systems', label: 'Garage',                 sectionNum: 4 },
  { key: 'septicSystem',    section: 'Features & Systems', label: 'Septic System',          sectionNum: 4 },
  { key: 'solarPanels',     section: 'Features & Systems', label: 'Solar Panels',           sectionNum: 4 },
  { key: 'fireSafetySprinkler', section: 'Features & Systems', label: 'Fire Safety Sprinkler', sectionNum: 4 },
  { key: 'detectorsHardwired',  section: 'Features & Systems', label: 'Hardwired Detectors',   sectionNum: 4 },
  { key: 'waterTreatment',  section: 'Features & Systems', label: 'Water Treatment',        sectionNum: 4 },
  { key: 'wellWater',       section: 'Features & Systems', label: 'Well Water',             sectionNum: 4 },
  // Section 5: Trash & Utilities
  { key: 'trashCollection', section: 'Trash & Utilities',  label: 'Trash Collection',       sectionNum: 5 },
  { key: 'waterSupply',     section: 'Trash & Utilities',  label: 'Water Supply',           sectionNum: 5 },
  // Section 6: Fire & Safety
  { key: 'fireAlarmSystem', section: 'Fire & Safety',      label: 'Fire Alarm System',      sectionNum: 6 },
  // Section 7: Inspections
  { key: 'iddInspection',   section: 'Inspections',        label: 'IDD Inspection',         sectionNum: 7 },
  { key: 'dcaInspection',   section: 'Inspections',        label: 'DCA Inspection',         sectionNum: 7 },
  // Section 1 conditional
  { key: 'landlordInfo',    section: 'Location Identity',  label: 'Landlord Info',          sectionNum: 1 },
];

/** Group field keys by section for rendering */
export function groupBySection() {
  const groups = [];
  let current = null;
  for (const f of INTAKE_FIELD_KEYS) {
    if (!current || current.section !== f.section) {
      current = { section: f.section, sectionNum: f.sectionNum, fields: [] };
      groups.push(current);
    }
    current.fields.push(f);
  }
  return groups;
}
```

- [ ] **Step 2: Copy to dcfg-property-intake**

Copy the identical file to `C:\dcfg\spa\dcfg-property-intake\src\intakeFieldKeys.js`.

- [ ] **Step 3: Verify both files parse**

Run: `cd C:\dcfg\spa\dcfg-shell && npx vite build --mode development 2>&1 | head -5`
Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build --mode development 2>&1 | head -5`
Expected: No import errors (files aren't imported yet, but syntax must be valid).

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-shell/src/intakeFieldKeys.js spa/dcfg-property-intake/src/intakeFieldKeys.js
git commit -m "feat: add intake field key registry for config matrix and form rendering"
```

---

### Task 2: Entity Sets in portalApi.js

Add the new Dataverse table references to the EntitySets object in dcfg-shell's portalApi.js.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-shell\src\portalApi.js:62` (add entries before closing brace)

- [ ] **Step 1: Add entity set entries**

At line 62 in portalApi.js (before the closing `};` of EntitySets), add:

```javascript
  intakeSessions:     'dcfg_intake_sessions',
  intakeProperties:   'dcfg_property_intakes',
  intakeFieldConfigs: 'dcfg_intake_field_configs',
  intakeVendors:      'dcfg_intake_vendors',
  intakeAuthUsers:    'dcfg_intake_authorized_users',
```

**Note:** Entity set names use plural form as Dataverse generates them. Verify actual names after table creation in Task 4. These are provisional — update if Dataverse generates different pluralization.

- [ ] **Step 2: Verify build**

Run: `cd C:\dcfg\spa\dcfg-shell && npx vite build 2>&1 | tail -5`
Expected: Build succeeds. New entity sets aren't referenced yet.

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-shell/src/portalApi.js
git commit -m "feat: add intake staging table entity sets to portalApi"
```

---

## Chunk 2: Admin Config Matrix

### Task 3: Intake Fields Tab in Admin.jsx

Add the 8th tab to the admin screen — a matrix of toggles showing which fields are visible per location type.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-shell\src\screens\Admin.jsx`
  - Line 18: Add 'Intake Fields' to TABS array
  - Line 55: Add conditional render for IntakeFieldsTab
  - After line 1432 (before style objects): Add IntakeFieldsTab and IntakeFieldConfigMatrix components

**Pattern:** Follow LocationTypesTab (lines 515-645) for data loading, save, and overlay patterns. Use existing style objects (btnPrimary, overlayStyle, etc. at lines 1433-1446).

- [ ] **Step 1: Add tab to TABS array**

At line 18, change:
```javascript
const TABS = ['Document Templates', 'Onboarding Steps', 'Location Types', 'Cost Codes', 'Appliance Types', 'Vendors', 'Logging'];
```
To:
```javascript
const TABS = ['Document Templates', 'Onboarding Steps', 'Location Types', 'Cost Codes', 'Appliance Types', 'Vendors', 'Logging', 'Intake Fields'];
```

- [ ] **Step 2: Add tab content render**

At line 55 (after the Logging tab render), add:
```javascript
  {activeTab === 'Intake Fields' && <IntakeFieldsTab userEmail={user?.email} />}
```

- [ ] **Step 3: Add imports for field key registry and useMemo**

At the top of Admin.jsx (after existing imports), add:
```javascript
import { INTAKE_FIELD_KEYS, groupBySection } from '../intakeFieldKeys.js';
```

Verify that `useMemo` is included in the React import. The existing file uses `useState`, `useEffect`, `useCallback` — add `useMemo` if not already present:
```javascript
import React, { useState, useEffect, useCallback, useMemo } from 'react';
```

- [ ] **Step 4: Add IntakeFieldsTab component**

Insert before the style objects block (before line 1433). This is the main component:

```javascript
/* ───── Tab 8: Intake Fields ───── */
function IntakeFieldsTab({ userEmail }) {
  const [locationTypes, setLocationTypes] = useState([]);
  const [configRows, setConfigRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const [ltRes, cfgRes] = await Promise.all([
        apiGet(`/${EntitySets.locationTypes}?$select=dcfg_location_typeid,dcfg_name,dcfg_is_active&$filter=dcfg_is_active eq true&$orderby=dcfg_name asc`),
        apiGet(`/${EntitySets.intakeFieldConfigs}?$select=dcfg_intake_field_configid,dcfg_field_key,dcfg_visible,dcfg_active_flag,_dcfg_location_type_value&$filter=dcfg_active_flag eq true`),
      ]);
      setLocationTypes(ltRes?.value ?? []);
      setConfigRows(cfgRes?.value ?? []);
    } catch (e) { console.error('Load intake config:', e); }
    setLoading(false);
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  // Build lookup: { "fieldKey::locationTypeId" → configRow }
  const configMap = useMemo(() => {
    const m = {};
    for (const row of configRows) {
      m[`${row.dcfg_field_key}::${row._dcfg_location_type_value}`] = row;
    }
    return m;
  }, [configRows]);

  function isVisible(fieldKey, ltId) {
    const row = configMap[`${fieldKey}::${ltId}`];
    return row ? row.dcfg_visible : true; // default visible if no config row exists
  }

  async function handleToggle(fieldKey, lt) {
    setSaving(true);
    const ltId = lt.dcfg_location_typeid;
    const existing = configMap[`${fieldKey}::${ltId}`];
    try {
      if (existing) {
        await apiPatch(`/${EntitySets.intakeFieldConfigs}(${existing.dcfg_intake_field_configid})`, {
          dcfg_visible: !existing.dcfg_visible,
        });
      } else {
        await apiPost(`/${EntitySets.intakeFieldConfigs}`, {
          dcfg_field_key: fieldKey,
          dcfg_visible: false, // toggling from default-visible to off
          dcfg_active_flag: true,
          'dcfg_location_type@odata.bind': `/${EntitySets.locationTypes}(${ltId})`,
        });
      }
      await writeAuditLog({
        targetTable: 'dcfg_intake_field_config',
        targetRecordId: existing?.dcfg_intake_field_configid || 'new',
        actionType: AuditActionType.DataUpdated,
        performedBy: userEmail || 'admin',
        newValue: `${fieldKey} for ${lt.dcfg_name}: ${existing ? !existing.dcfg_visible : false}`,
      }).catch(() => {});
      loadData();
    } catch (e) { console.error('Toggle intake field config:', e); }
    setSaving(false);
  }

  const sections = groupBySection();

  if (loading) return <Skeleton />;

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
        <span style={{ fontSize: '13px', color: '#64748B' }}>
          {INTAKE_FIELD_KEYS.length} configurable fields &middot; {locationTypes.length} location types
        </span>
        <div style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '11px', color: '#94A3B8' }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <span style={{ display: 'inline-block', width: '10px', height: '10px', borderRadius: '2px', background: '#2D8659' }} /> Shown
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <span style={{ display: 'inline-block', width: '10px', height: '10px', borderRadius: '2px', background: '#E2E8F0' }} /> Hidden
          </span>
          <span style={{ marginLeft: '8px' }}>Defaults by location type &mdash; override per-property in Location Detail</span>
        </div>
      </div>

      <div style={{ overflowX: 'auto' }}>
        <table className="dcfg-table" style={{ minWidth: '600px' }}>
          <thead>
            <tr>
              <th style={{ width: '220px', position: 'sticky', left: 0, background: '#F8FAFC', zIndex: 2 }}>Field / Section</th>
              {locationTypes.map(lt => (
                <th key={lt.dcfg_location_typeid} style={{ textAlign: 'center', minWidth: '80px', fontSize: '11px' }}>
                  {lt.dcfg_name}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sections.map(group => (
              <React.Fragment key={group.section}>
                <tr style={{ background: '#F8FAFC' }}>
                  <td colSpan={1 + locationTypes.length} style={{ fontWeight: 600, color: NAVY, padding: '10px 10px', borderBottom: '2px solid #E2E8F0', fontSize: '12px' }}>
                    Section {group.sectionNum}: {group.section}
                    {group.sectionNum <= 2 && <span style={{ color: '#94A3B8', fontWeight: 400 }}> — always shown</span>}
                  </td>
                </tr>
                {group.fields.map(field => (
                  <tr key={field.key}>
                    <td style={{ paddingLeft: '24px', fontSize: '12.5px', color: '#475569', position: 'sticky', left: 0, background: '#fff', zIndex: 1 }}>
                      <Fn f={`dcfg_intake_field_config.${field.key}`}>{field.label}</Fn>
                    </td>
                    {locationTypes.map(lt => {
                      const vis = isVisible(field.key, lt.dcfg_location_typeid);
                      return (
                        <td key={lt.dcfg_location_typeid} style={{ textAlign: 'center', padding: '6px' }}>
                          <button
                            onClick={() => handleToggle(field.key, lt)}
                            disabled={saving}
                            title={vis ? `Hide ${field.label} for ${lt.dcfg_name}` : `Show ${field.label} for ${lt.dcfg_name}`}
                            style={{
                              display: 'inline-block', width: '36px', height: '20px', borderRadius: '10px',
                              border: 'none', cursor: saving ? 'wait' : 'pointer', position: 'relative',
                              background: vis ? '#2D8659' : '#E2E8F0', transition: 'background 0.15s',
                            }}
                          >
                            <span style={{
                              position: 'absolute', width: '16px', height: '16px', borderRadius: '50%',
                              background: '#fff', top: '2px', transition: 'left 0.15s',
                              left: vis ? '18px' : '2px',
                            }} />
                          </button>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Verify build compiles**

Run: `cd C:\dcfg\spa\dcfg-shell && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 6: Manual verification**

Open dcfg-shell in browser → navigate to Admin → verify "Intake Fields" tab appears. It will show an empty matrix until Dataverse tables exist (Task 4), but the tab should render without errors.

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-shell/src/screens/Admin.jsx
git commit -m "feat: add Intake Fields config matrix tab to Admin"
```

---

## Chunk 3: Dataverse Table Creation

### Task 4: PowerShell Scripts for Dataverse Tables

Create scripts to provision the four new Dataverse tables. These run against DCGWorkRequests environment.

**Files:**
- Create: `C:\DCFG\scripts\Create-IntakeTables.ps1`

**Note:** This task requires operator to run the script after review. The script connects to DCGWorkRequests and creates tables + columns in the DCFGSystemTest solution.

- [ ] **Step 1: Write the table creation script**

```powershell
<#
  Create-IntakeTables.ps1
  Creates: dcfg_intake_session, dcfg_intake_field_config, dcfg_property_intake,
           dcfg_intake_vendor, dcfg_intake_authorized_user
  Target: DCGWorkRequests environment, DCFGSystemTest solution

  PREREQUISITES: Connect-CrmOnline to dcgworkrequests.crm.dynamics.com
#>

param(
  [switch]$WhatIf
)

$solutionName = "DCFGSystemTest"
$publisherPrefix = "dcfg"

# Helper: Create entity
function New-Entity {
  param([string]$SchemaName, [string]$DisplayName, [string]$PluralName, [string]$Description)

  if ($WhatIf) {
    Write-Host "[WhatIf] Would create entity: $SchemaName ($DisplayName)" -ForegroundColor Yellow
    return
  }

  Write-Host "Creating entity: $SchemaName..." -ForegroundColor Cyan
  $entity = New-CrmRecord -EntityLogicalName EntityDefinition -Fields @{
    SchemaName = $SchemaName
    DisplayName = (New-CrmLabel $DisplayName)
    DisplayCollectionName = (New-CrmLabel $PluralName)
    Description = (New-CrmLabel $Description)
    OwnershipType = "UserOwned"
    IsActivity = $false
  }

  # Add to solution
  Add-CrmSolutionComponent -SolutionUniqueName $solutionName -ComponentType 1 -ComponentId $entity.EntityId
  Write-Host "  Created and added to $solutionName" -ForegroundColor Green
  return $entity
}

# Helper: Create column
function New-Column {
  param(
    [string]$EntityName, [string]$SchemaName, [string]$DisplayName,
    [string]$Type, [int]$MaxLength = 200, [bool]$Required = $false,
    [hashtable]$Options = @{}
  )

  if ($WhatIf) {
    Write-Host "  [WhatIf] Would create column: $SchemaName ($Type)" -ForegroundColor Yellow
    return
  }

  Write-Host "  Creating column: $SchemaName ($Type)..." -ForegroundColor Gray
  # Column creation varies by type — operator should verify in maker portal
  # This script creates the basic structure; complex types (lookup, picklist) may need manual adjustment
}

Write-Host "`n=== DCFG Intake Tables Creation ===" -ForegroundColor White
Write-Host "Target: dcgworkrequests.crm.dynamics.com" -ForegroundColor Gray
Write-Host "Solution: $solutionName`n" -ForegroundColor Gray

# ─── Table 1: dcfg_intake_session ───
Write-Host "`n─── dcfg_intake_session ───" -ForegroundColor White
$sessionColumns = @(
  @{ Name="${publisherPrefix}_access_code";        Display="Access Code";        Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_provider_name";      Display="Provider Name";      Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_provider_id";        Display="Provider ID";        Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_expires_at";         Display="Expires At";         Type="DateTime" }
  @{ Name="${publisherPrefix}_status";             Display="Status";             Type="Picklist"; Options=@{
    100000000="New"; 100000001="Active"; 100000002="Expired"; 100000003="Revoked"
  }}
  @{ Name="${publisherPrefix}_sent_by";            Display="Sent By";            Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_sent_at";            Display="Sent At";            Type="DateTime" }
  @{ Name="${publisherPrefix}_active_flag";        Display="Active";             Type="Boolean" }
)
foreach ($col in $sessionColumns) {
  Write-Host "  $($col.Name) ($($col.Type))" -ForegroundColor Gray
}

# ─── Table 2: dcfg_intake_field_config ───
Write-Host "`n─── dcfg_intake_field_config ───" -ForegroundColor White
$configColumns = @(
  @{ Name="${publisherPrefix}_field_key";          Display="Field Key";          Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_visible";            Display="Visible";            Type="Boolean" }
  @{ Name="${publisherPrefix}_active_flag";        Display="Active";             Type="Boolean" }
  # Lookup: dcfg_location_type → dcfg_location_types (create relationship manually)
)
foreach ($col in $configColumns) {
  Write-Host "  $($col.Name) ($($col.Type))" -ForegroundColor Gray
}
Write-Host "  + Lookup: dcfg_location_type → dcfg_location_types (manual)" -ForegroundColor Yellow

# ─── Table 3: dcfg_property_intake ───
Write-Host "`n─── dcfg_property_intake ───" -ForegroundColor White
$intakeColumns = @(
  # Session link
  @{ Name="${publisherPrefix}_home_type";          Display="Home Type";          Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_intake_status";      Display="Intake Status";      Type="Picklist"; Options=@{
    100000000="New"; 100000001="In Progress"; 100000002="Complete"; 100000003="Reviewed"; 100000004="Approved"
  }}
  @{ Name="${publisherPrefix}_last_modified_by_customer"; Display="Last Modified By Customer"; Type="DateTime" }
  @{ Name="${publisherPrefix}_field_overrides";    Display="Field Overrides";    Type="Memo" }
  @{ Name="${publisherPrefix}_hidden_field_data";  Display="Hidden Field Data";  Type="Memo" }
  @{ Name="${publisherPrefix}_locked_by";          Display="Locked By";          Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_locked_at";          Display="Locked At";          Type="DateTime" }
  @{ Name="${publisherPrefix}_active_flag";        Display="Active";             Type="Boolean" }
  # UpKeep source
  @{ Name="${publisherPrefix}_upkeep_location_id"; Display="UpKeep Location ID"; Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_upkeep_parent_id";   Display="UpKeep Parent ID";   Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_upkeep_name";        Display="UpKeep Name";        Type="String";   MaxLength=200 }
  # Section 1: Location Identity
  @{ Name="${publisherPrefix}_street_address";     Display="Street Address";     Type="String";   MaxLength=500 }
  @{ Name="${publisherPrefix}_city";               Display="City";               Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_state";              Display="State";              Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_zip_code";           Display="Zip Code";           Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_home_ownership";     Display="Home Ownership";     Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_service_line";       Display="Service Line";       Type="String";   MaxLength=200 }
  # Landlord
  @{ Name="${publisherPrefix}_landlord_name";      Display="Landlord Name";      Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_landlord_phone";     Display="Landlord Phone";     Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_lease_start";        Display="Lease Start";        Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_lease_end";          Display="Lease End";          Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_lease_doc_link";     Display="Lease Doc Link";     Type="String";   MaxLength=500 }
  # Section 2: Site Contact
  @{ Name="${publisherPrefix}_contact_person";     Display="Contact Person";     Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_contact_phone";      Display="Contact Phone";      Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_contact_email";      Display="Contact Email";      Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_entry_time";         Display="Entry Time";         Type="String";   MaxLength=100 }
  # Section 3: Home Details - Structure
  @{ Name="${publisherPrefix}_year_built";         Display="Year Built";         Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_capacity";           Display="Capacity";           Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_bedrooms";           Display="Bedrooms";           Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_stories";            Display="Stories";            Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_basement";           Display="Basement";           Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_attic";              Display="Attic";              Type="String";   MaxLength=5 }
  # Roof & Exterior
  @{ Name="${publisherPrefix}_age_of_roof";        Display="Age of Roof";        Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_type_of_roof";       Display="Type of Roof";       Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_roof_documentation"; Display="Roof Documentation"; Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_gutter_guards";      Display="Gutter Guards";      Type="String";   MaxLength=5 }
  # Utilities & Access
  @{ Name="${publisherPrefix}_heating_type";       Display="Heating Type";       Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_floor_plans";        Display="Floor Plans";        Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_parking";            Display="Parking";            Type="String";   MaxLength=50 }
  # Section 4: Features (Y/N triggers)
  @{ Name="${publisherPrefix}_lock_box";           Display="Lock Box";           Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_lock_box_code";      Display="Lock Box Code";      Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_lock_box_location";  Display="Lock Box Location";  Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_pool";               Display="Pool";               Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_pool_type";          Display="Pool Type";          Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_pool_water_type";    Display="Pool Water Type";    Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_liner_type";         Display="Liner Type";         Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_pool_install_date";  Display="Pool Install Date";  Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_pump_model";         Display="Pump Model";         Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_pool_notes";         Display="Pool Notes";         Type="Memo" }
  @{ Name="${publisherPrefix}_generator";          Display="Generator";          Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_gen_fuel_type";      Display="Generator Fuel Type";Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_gen_make";           Display="Generator Make";     Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_gen_model";          Display="Generator Model";    Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_gen_serial";         Display="Generator Serial";   Type="String";   MaxLength=100 }
  @{ Name="${publisherPrefix}_gen_service_provider"; Display="Gen Service Provider"; Type="String"; MaxLength=200 }
  @{ Name="${publisherPrefix}_garage";             Display="Garage";             Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_garage_size";        Display="Garage Size";        Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_garage_attached";    Display="Garage Attached";    Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_garage_finished";    Display="Garage Finished";    Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_septic_system";      Display="Septic System";      Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_septic_atu";         Display="Septic ATU";         Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_septic_capacity";    Display="Septic Capacity";    Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_septic_install_date";Display="Septic Install Date";Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_septic_drawings";    Display="Septic Drawings";    Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_solar_panels";       Display="Solar Panels";       Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_solar_size";         Display="Solar Size";         Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_solar_installer";    Display="Solar Installer";    Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_solar_install_date"; Display="Solar Install Date"; Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_solar_lease_owned";  Display="Solar Lease/Owned";  Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_solar_monitoring";   Display="Solar Monitoring";   Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_solar_output";       Display="Solar Output";       Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_solar_notes";        Display="Solar Notes";        Type="Memo" }
  @{ Name="${publisherPrefix}_fire_safety_sprinkler"; Display="Fire Safety Sprinkler"; Type="String"; MaxLength=5 }
  @{ Name="${publisherPrefix}_detectors_hardwired"; Display="Detectors Hardwired"; Type="String"; MaxLength=5 }
  @{ Name="${publisherPrefix}_water_treatment";    Display="Water Treatment";    Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_well_water";         Display="Well Water";         Type="String";   MaxLength=5 }
  # Section 5: Trash
  @{ Name="${publisherPrefix}_trash_collection";   Display="Trash Collection";   Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_trash_cans";         Display="Trash Cans";         Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_max_trash_cans";     Display="Max Trash Cans";     Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_recycling_cans";     Display="Recycling Cans";     Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_max_recycling_cans"; Display="Max Recycling Cans"; Type="String";   MaxLength=10 }
  @{ Name="${publisherPrefix}_trash_vendor";       Display="Trash Vendor";       Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_trash_handles_recycling"; Display="Trash Handles Recycling"; Type="String"; MaxLength=5 }
  @{ Name="${publisherPrefix}_trash_contract_start"; Display="Trash Contract Start"; Type="String"; MaxLength=50 }
  @{ Name="${publisherPrefix}_trash_contract_end"; Display="Trash Contract End"; Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_trash_monthly_cost"; Display="Trash Monthly Cost"; Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_water_supply";       Display="Water Supply";       Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_well_certified";     Display="Well Certified";     Type="String";   MaxLength=5 }
  @{ Name="${publisherPrefix}_well_documentation"; Display="Well Documentation"; Type="String";   MaxLength=5 }
  # Section 6: Fire & Safety
  @{ Name="${publisherPrefix}_fire_alarm_system";  Display="Fire Alarm System";  Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_fire_alarm_sprinkler"; Display="Fire Alarm Sprinkler"; Type="String"; MaxLength=5 }
  @{ Name="${publisherPrefix}_fire_alarm_monitoring"; Display="Fire Alarm Monitoring"; Type="String"; MaxLength=5 }
  @{ Name="${publisherPrefix}_fire_extinguishers"; Display="Fire Extinguishers"; Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_co_detectors";       Display="CO Detectors";       Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_smoke_detectors";    Display="Smoke Detectors";    Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_annual_inspection";  Display="Annual Inspection";  Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_chimes_in_home";     Display="Chimes in Home";     Type="String";   MaxLength=5 }
  # Section 7: Inspections
  @{ Name="${publisherPrefix}_last_idd_inspection"; Display="Last IDD Inspection"; Type="String"; MaxLength=50 }
  @{ Name="${publisherPrefix}_last_dca_inspection"; Display="Last DCA Inspection"; Type="String"; MaxLength=50 }
)
Write-Host "  $($intakeColumns.Count) columns defined" -ForegroundColor Gray
Write-Host "  + Lookup: dcfg_intake_session → dcfg_intake_sessions (manual)" -ForegroundColor Yellow

# ─── Table 4: dcfg_intake_vendor (simplified — contact info + document upload) ───
Write-Host "`n─── dcfg_intake_vendor ───" -ForegroundColor White
$vendorColumns = @(
  @{ Name="${publisherPrefix}_vendor_name";        Display="Vendor Name";        Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_service_provided";   Display="Service Provided";   Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_contact_phone";      Display="Contact Phone";      Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_document_note";      Display="Document Note";      Type="Memo" }
  @{ Name="${publisherPrefix}_active_flag";        Display="Active";             Type="Boolean" }
  # Document/photo attachment: use Dataverse Notes (annotation) entity — no custom column needed
)
foreach ($col in $vendorColumns) {
  Write-Host "  $($col.Name) ($($col.Type))" -ForegroundColor Gray
}
Write-Host "  + Lookup: dcfg_intake_session → dcfg_intake_sessions (manual)" -ForegroundColor Yellow

# ─── Table 5: dcfg_intake_authorized_user ───
Write-Host "`n─── dcfg_intake_authorized_user ───" -ForegroundColor White
$userColumns = @(
  @{ Name="${publisherPrefix}_name";               Display="Name";               Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_email";              Display="Email";              Type="String";   MaxLength=200 }
  @{ Name="${publisherPrefix}_phone";              Display="Phone";              Type="String";   MaxLength=50 }
  @{ Name="${publisherPrefix}_access_level";       Display="Access Level";       Type="String";   MaxLength=20 }
  @{ Name="${publisherPrefix}_location_ids";       Display="Location IDs";       Type="Memo" }
  @{ Name="${publisherPrefix}_active_flag";        Display="Active";             Type="Boolean" }
)
foreach ($col in $userColumns) {
  Write-Host "  $($col.Name) ($($col.Type))" -ForegroundColor Gray
}
Write-Host "  + Lookup: dcfg_intake_session → dcfg_intake_sessions (manual)" -ForegroundColor Yellow

# ─── Summary ───
Write-Host "`n=== Summary ===" -ForegroundColor White
Write-Host "Tables to create: 5" -ForegroundColor Cyan
Write-Host "  1. dcfg_intake_session ($(($sessionColumns).Count) columns)"
Write-Host "  2. dcfg_intake_field_config ($(($configColumns).Count) columns + 1 lookup)"
Write-Host "  3. dcfg_property_intake ($(($intakeColumns).Count) columns + 1 lookup)"
Write-Host "  4. dcfg_intake_vendor ($(($vendorColumns).Count) columns + 1 lookup)"
Write-Host "  5. dcfg_intake_authorized_user ($(($userColumns).Count) columns + 1 lookup)"
Write-Host "`nManual steps after script:" -ForegroundColor Yellow
Write-Host "  1. Create lookup relationships (4 total)"
Write-Host "  2. Verify entity set names in Dataverse Web API"
Write-Host "  3. Update portalApi.js EntitySets if names differ"
Write-Host "  4. Set up table permissions for intake portal site"

if ($WhatIf) {
  Write-Host "`n[WhatIf mode] No changes were made." -ForegroundColor Yellow
}
```

- [ ] **Step 2: Run with -WhatIf to verify**

Run: `pwsh C:\DCFG\scripts\Create-IntakeTables.ps1 -WhatIf`
Expected: Prints all tables and columns without creating anything.

- [ ] **Step 3: Commit**

```bash
git add scripts/Create-IntakeTables.ps1
git commit -m "feat: add Dataverse table creation script for intake staging tables"
```

- [ ] **Step 4: Operator creates tables**

**GATE: Operator must run this script (or create tables manually in maker portal) before Tasks 5-8 can be tested against Dataverse.**

---

## Chunk 4: Intake API Layer

### Task 5: Intake API Module for dcfg-property-intake

Create the API layer that the intake form uses to read config and write to Dataverse. Includes the `USE_DATAVERSE` flag and localStorage fallback.

**Files:**
- Create: `C:\dcfg\spa\dcfg-property-intake\src\intakeApi.js`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\storage.js` (keep as localStorage-only fallback, add export for merge logic)

- [ ] **Step 1: Create intakeApi.js**

```javascript
/**
 * Intake API — Dataverse Web API client for the property intake portal.
 * Anonymous access, no Power Pages user session.
 * Falls back to localStorage when Dataverse is unavailable.
 */

// Toggle: set true when Power Pages site is provisioned and tables exist
const USE_DATAVERSE = false;

const API_BASE = '/_api';
let _csrfToken = null;

// ─── CSRF Token ───
async function getToken() {
  if (_csrfToken) return _csrfToken;
  try {
    const resp = await fetch('/', { credentials: 'same-origin' });
    const html = await resp.text();
    const match = html.match(/name="__RequestVerificationToken"[^>]*value="([^"]+)"/);
    if (match) { _csrfToken = match[1]; return _csrfToken; }
  } catch (e) { console.warn('CSRF token fetch failed:', e); }
  // Fallback: check DOM
  const el = document.querySelector('input[name="__RequestVerificationToken"]');
  if (el) { _csrfToken = el.value; return _csrfToken; }
  return null;
}

function invalidateToken() { _csrfToken = null; }

const HEADERS_READ = {
  'Accept': 'application/json',
  'OData-MaxVersion': '4.0',
  'OData-Version': '4.0',
};

async function apiGet(path) {
  const resp = await fetch(`${API_BASE}${path}`, { headers: HEADERS_READ, credentials: 'same-origin' });
  if (!resp.ok) throw new Error(`GET ${path}: ${resp.status}`);
  return resp.json();
}

async function apiPost(path, body) {
  const token = await getToken();
  const resp = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { ...HEADERS_READ, 'Content-Type': 'application/json', '__RequestVerificationToken': token },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
  if (resp.status === 401 || resp.status === 403) invalidateToken();
  if (!resp.ok) throw new Error(`POST ${path}: ${resp.status}`);
}

async function apiPatch(path, body) {
  const token = await getToken();
  const resp = await fetch(`${API_BASE}${path}`, {
    method: 'PATCH',
    headers: { ...HEADERS_READ, 'Content-Type': 'application/json', '__RequestVerificationToken': token },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
  if (resp.status === 401 || resp.status === 403) invalidateToken();
  if (!resp.ok) throw new Error(`PATCH ${path}: ${resp.status}`);
}

// ─── Entity Sets (verify after table creation) ───
const ES = {
  sessions:     'dcfg_intake_sessions',
  properties:   'dcfg_property_intakes',
  fieldConfigs: 'dcfg_intake_field_configs',
  vendors:      'dcfg_intake_vendors',
  authUsers:    'dcfg_intake_authorized_users',
  locationTypes:'dcfg_location_types',
};

// ─── Public API ───

/** Sanitize string for OData filter (prevent injection) */
function sanitizeOData(val) {
  return val.replace(/'/g, "''");
}

/** Load session by access code. Returns session object or null. */
export async function loadSession(code) {
  if (!USE_DATAVERSE) return null;
  const safeCode = sanitizeOData(code);
  try {
    const r = await apiGet(`/${ES.sessions}?$filter=dcfg_access_code eq '${safeCode}' and dcfg_active_flag eq true&$select=dcfg_intake_sessionid,dcfg_access_code,dcfg_provider_name,dcfg_provider_id,dcfg_expires_at,dcfg_status`);
    const sessions = r?.value ?? [];
    if (sessions.length === 0) return null;
    const s = sessions[0];
    // Check expiry
    if (s.dcfg_status === 100000002 || s.dcfg_status === 100000003) return null; // Expired or Revoked
    if (new Date(s.dcfg_expires_at) < new Date()) return null;
    return s;
  } catch (e) {
    console.warn('loadSession failed, falling back to localStorage:', e);
    return null;
  }
}

/** Load properties for a session. Returns array. */
export async function loadProperties(sessionId) {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.properties}?$filter=_dcfg_intake_session_value eq '${sessionId}' and dcfg_active_flag eq true&$orderby=dcfg_street_address asc`);
    return r?.value ?? [];
  } catch (e) {
    console.warn('loadProperties failed:', e);
    return null;
  }
}

/** Load field config for all location types. Returns array of config rows. */
export async function loadFieldConfig() {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.fieldConfigs}?$filter=dcfg_active_flag eq true&$select=dcfg_field_key,dcfg_visible,_dcfg_location_type_value`);
    return r?.value ?? [];
  } catch (e) {
    console.warn('loadFieldConfig failed:', e);
    return null;
  }
}

/** Load active location types for homeType dropdown. Returns array. */
export async function loadLocationTypes() {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.locationTypes}?$filter=dcfg_is_active eq true&$select=dcfg_location_typeid,dcfg_name&$orderby=dcfg_name asc`);
    return r?.value ?? [];
  } catch (e) {
    console.warn('loadLocationTypes failed:', e);
    return null;
  }
}

/** Save a single property field change. Returns true on success. */
export async function savePropertyField(propertyIntakeId, fieldName, value) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      [fieldName]: value,
      dcfg_last_modified_by_customer: new Date().toISOString(),
    });
    return true;
  } catch (e) {
    console.warn('savePropertyField failed:', e);
    invalidateToken(); // might be stale CSRF
    return false;
  }
}

/** Batch save multiple fields on one property. Returns true on success. */
export async function savePropertyBatch(propertyIntakeId, fields) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      ...fields,
      dcfg_last_modified_by_customer: new Date().toISOString(),
    });
    return true;
  } catch (e) {
    console.warn('savePropertyBatch failed:', e);
    invalidateToken();
    return false;
  }
}

/** Load vendors for a session. */
export async function loadVendors(sessionId) {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.vendors}?$filter=_dcfg_intake_session_value eq '${sessionId}' and dcfg_active_flag eq true`);
    return r?.value ?? [];
  } catch (e) { console.warn('loadVendors failed:', e); return null; }
}

/** Load authorized users for a session. */
export async function loadAuthUsers(sessionId) {
  if (!USE_DATAVERSE) return null;
  try {
    const r = await apiGet(`/${ES.authUsers}?$filter=_dcfg_intake_session_value eq '${sessionId}' and dcfg_active_flag eq true`);
    return r?.value ?? [];
  } catch (e) { console.warn('loadAuthUsers failed:', e); return null; }
}

/** Create a vendor record. */
export async function createVendor(sessionId, data) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPost(`/${ES.vendors}`, {
      ...data,
      dcfg_active_flag: true,
      'dcfg_intake_session@odata.bind': `/${ES.sessions}(${sessionId})`,
    });
    return true;
  } catch (e) { console.warn('createVendor failed:', e); return false; }
}

/** Create an authorized user record. */
export async function createAuthUser(sessionId, data) {
  if (!USE_DATAVERSE) return false;
  try {
    await apiPost(`/${ES.authUsers}`, {
      ...data,
      dcfg_active_flag: true,
      'dcfg_intake_session@odata.bind': `/${ES.sessions}(${sessionId})`,
    });
    return true;
  } catch (e) { console.warn('createAuthUser failed:', e); return false; }
}

/** Check if Dataverse is reachable. Used for online/offline detection. */
export async function isOnline() {
  if (!USE_DATAVERSE) return false;
  try {
    await apiGet(`/${ES.locationTypes}?$top=1&$select=dcfg_location_typeid`);
    return true;
  } catch { return false; }
}

export { USE_DATAVERSE };
```

- [ ] **Step 2: Verify file parses**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build --mode development 2>&1 | tail -5`
Expected: Build succeeds (file not imported yet).

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-property-intake/src/intakeApi.js
git commit -m "feat: add Dataverse API layer for intake portal with offline fallback flag"
```

---

## Chunk 5: Dynamic Form Config

### Task 6: PropertyForm Dynamic Field Visibility

Refactor PropertyForm.jsx to accept a visibility config and conditionally render sections based on the selected location type.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\PropertyForm.jsx`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx` (pass config + location types as props)

- [ ] **Step 1: Add config props to PropertyForm**

At line 79 of PropertyForm.jsx, change the function signature from:
```javascript
export default function PropertyForm({ property: p, onChange, onDelete }) {
```
To:
```javascript
export default function PropertyForm({ property: p, onChange, onDelete, fieldConfig, locationTypes }) {
```

- [ ] **Step 2: Add visibility helper inside PropertyForm**

After the `set` helper (line 80), add:
```javascript
  // Check if a field key is visible for the current property's home type
  const isFieldVisible = (fieldKey) => {
    if (!fieldConfig || !p.homeType) return true; // no config loaded or no type selected = show all
    const entry = fieldConfig.find(c => c.key === fieldKey && c.locationType === p.homeType);
    if (!entry) return true; // no config row = default visible
    // Check per-property override first
    if (p._fieldOverrides && p._fieldOverrides[fieldKey] !== undefined) {
      return p._fieldOverrides[fieldKey];
    }
    return entry.visible;
  };
```

- [ ] **Step 3: Update homeType dropdown to use locationTypes prop**

At line 108, change:
```javascript
options={['Apartment', 'Home']}
```
To:
```javascript
options={locationTypes && locationTypes.length > 0 ? locationTypes : ['Apartment', 'Home']}
```

- [ ] **Step 4: Wrap configurable sections with visibility checks**

For each configurable section, wrap with `isFieldVisible()`. Examples:

**Roof & Exterior subsection** (around line 145):
```javascript
{isFieldVisible('roofExterior') && <>
  <div style={{ fontSize: '12px', fontWeight: 600, color: '#475569', marginTop: '8px' }}>Roof & Exterior</div>
  {/* existing roof fields */}
</>}
```

**Pool** (around line 169):
```javascript
{isFieldVisible('pool') && <>
  <Field label="Pool" field="pool" value={p.pool} onChange={set} type="yn" />
  <DetailPanel title="Pool Details" show={p.pool === 'Y'}>
    {/* existing pool detail fields */}
  </DetailPanel>
</>}
```

Apply the same pattern to all 20 configurable field keys:
- `structure` → wraps Structure subsection (lines ~135-143)
- `roofExterior` → wraps Roof & Exterior subsection (lines ~144-151)
- `utilitiesAccess` → wraps Utilities & Access subsection (lines ~152-157)
- `lockBox` → wraps lock box Y/N + detail panel (lines ~161-167)
- `pool` → wraps pool Y/N + detail panel (lines ~169-179)
- `generator` → wraps generator Y/N + detail panel (lines ~181-190)
- `garage` → wraps garage Y/N + detail panel (lines ~192-199)
- `septicSystem` → wraps septic Y/N + detail panel (lines ~201-209)
- `solarPanels` → wraps solar Y/N + detail panel (lines ~211-222)
- `fireSafetySprinkler` → wraps line ~224
- `detectorsHardwired` → wraps line ~225
- `waterTreatment` → wraps line ~226
- `wellWater` → wraps line ~227
- `trashCollection` → wraps trash dropdown + panels (lines ~231-249)
- `waterSupply` → wraps water supply dropdown + panel (lines ~251-257)
- `fireAlarmSystem` → wraps fire alarm dropdown + panel (lines ~261-273)
- `iddInspection` → wraps IDD field (line ~278)
- `dcaInspection` → wraps DCA field (line ~279)
- `landlordInfo` → wraps landlord detail panel (already conditional on homeOwnership, but also controlled by config)

- [ ] **Step 5: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`
Expected: Build succeeds. Form renders identically to before (all fields visible when no config passed).

- [ ] **Step 6: Manual verification**

Run dev server: `cd C:\dcfg\spa\dcfg-property-intake && npx vite dev`
Open in browser. Verify all sections still render (no config = everything visible). Select a property, verify form works as before.

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-property-intake/src/PropertyForm.jsx
git commit -m "feat: add dynamic field visibility to PropertyForm based on config"
```

---

### Task 6b: Wire Config Loading in App.jsx

Load field config and location types on app init, pass to PropertyForm.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx`

- [ ] **Step 1: Add imports**

At top of App.jsx, add:
```javascript
import { loadFieldConfig, loadLocationTypes, USE_DATAVERSE } from './intakeApi.js';
import { INTAKE_FIELD_KEYS } from './intakeFieldKeys.js';
```

- [ ] **Step 2: Add state for config**

After existing state declarations (around line 21), add:
```javascript
const [fieldConfig, setFieldConfig] = useState(null);
const [locationTypeNames, setLocationTypeNames] = useState([]);
```

- [ ] **Step 3: Load config on mount**

Add a useEffect after existing effects:
```javascript
useEffect(() => {
  (async () => {
    // Load location types for homeType dropdown
    const types = await loadLocationTypes();
    if (types) {
      setLocationTypeNames(types.map(t => t.dcfg_name));
    }
    // Load field config matrix
    const configs = await loadFieldConfig();
    if (configs) {
      // Transform Dataverse rows into lookup-friendly format
      setFieldConfig(configs.map(c => ({
        key: c.dcfg_field_key,
        locationType: c._dcfg_location_type_value, // This is the GUID — need to resolve to name
        visible: c.dcfg_visible,
      })));
    }
  })();
}, []);
```

**Note:** The field config uses location type GUIDs from Dataverse. We need to resolve these to names for the PropertyForm lookup. Update the transform:

```javascript
useEffect(() => {
  (async () => {
    const types = await loadLocationTypes();
    const typeMap = {};
    if (types) {
      setLocationTypeNames(types.map(t => t.dcfg_name));
      for (const t of types) typeMap[t.dcfg_location_typeid] = t.dcfg_name;
    }
    const configs = await loadFieldConfig();
    if (configs) {
      setFieldConfig(configs.map(c => ({
        key: c.dcfg_field_key,
        locationType: typeMap[c._dcfg_location_type_value] || c._dcfg_location_type_value,
        visible: c.dcfg_visible,
      })));
    }
  })();
}, []);
```

- [ ] **Step 4: Pass config to PropertyForm**

In the PropertyForm render (around line 245-250), change:
```javascript
<PropertyForm property={selectedProp} onChange={updateProperty} onDelete={deleteProperty} />
```
To:
```javascript
<PropertyForm property={selectedProp} onChange={updateProperty} onDelete={deleteProperty} fieldConfig={fieldConfig} locationTypes={locationTypeNames} />
```

- [ ] **Step 5: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-property-intake/src/App.jsx
git commit -m "feat: load field config and location types on intake app init"
```

---

## Chunk 6: Dataverse Persistence

### Task 7: Replace localStorage with Dataverse Writes

Refactor App.jsx to use Dataverse as primary persistence with localStorage as fallback.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\storage.js` (add field mapping helpers)

- [ ] **Step 1: Add field name mapping to storage.js**

The intake form uses camelCase field names (e.g., `streetAddress`), but Dataverse uses prefixed snake_case (e.g., `dcfg_street_address`). Add a bidirectional map at the end of storage.js:

```javascript
/** Map form field keys (camelCase) to Dataverse column names */
export const FIELD_MAP = {
  streetAddress: 'dcfg_street_address',
  city: 'dcfg_city',
  state: 'dcfg_state',
  zipCode: 'dcfg_zip_code',
  homeType: 'dcfg_home_type',
  homeOwnership: 'dcfg_home_ownership',
  serviceLine: 'dcfg_service_line',
  landlordName: 'dcfg_landlord_name',
  landlordPhone: 'dcfg_landlord_phone',
  leaseStart: 'dcfg_lease_start',
  leaseEnd: 'dcfg_lease_end',
  leaseDocLink: 'dcfg_lease_doc_link',
  contactPerson: 'dcfg_contact_person',
  contactPhone: 'dcfg_contact_phone',
  contactEmail: 'dcfg_contact_email',
  entryTime: 'dcfg_entry_time',
  yearBuilt: 'dcfg_year_built',
  capacity: 'dcfg_capacity',
  bedrooms: 'dcfg_bedrooms',
  stories: 'dcfg_stories',
  basement: 'dcfg_basement',
  attic: 'dcfg_attic',
  ageOfRoof: 'dcfg_age_of_roof',
  typeOfRoof: 'dcfg_type_of_roof',
  roofDocumentation: 'dcfg_roof_documentation',
  gutterGuards: 'dcfg_gutter_guards',
  heatingType: 'dcfg_heating_type',
  floorPlansAvailable: 'dcfg_floor_plans',
  parking: 'dcfg_parking',
  lockBox: 'dcfg_lock_box',
  lockBoxCode: 'dcfg_lock_box_code',
  lockBoxLocation: 'dcfg_lock_box_location',
  pool: 'dcfg_pool',
  poolType: 'dcfg_pool_type',
  poolWaterType: 'dcfg_pool_water_type',
  linerType: 'dcfg_liner_type',
  poolInstallDate: 'dcfg_pool_install_date',
  pumpModel: 'dcfg_pump_model',
  poolNotes: 'dcfg_pool_notes',
  generator: 'dcfg_generator',
  genFuelType: 'dcfg_gen_fuel_type',
  genMake: 'dcfg_gen_make',
  genModel: 'dcfg_gen_model',
  genSerial: 'dcfg_gen_serial',
  genServiceProvider: 'dcfg_gen_service_provider',
  garage: 'dcfg_garage',
  garageSize: 'dcfg_garage_size',
  garageAttached: 'dcfg_garage_attached',
  garageFinished: 'dcfg_garage_finished',
  septicSystem: 'dcfg_septic_system',
  septicAtu: 'dcfg_septic_atu',
  septicCapacity: 'dcfg_septic_capacity',
  septicInstallDate: 'dcfg_septic_install_date',
  septicDrawings: 'dcfg_septic_drawings',
  solarPanels: 'dcfg_solar_panels',
  solarSize: 'dcfg_solar_size',
  solarInstaller: 'dcfg_solar_installer',
  solarInstallDate: 'dcfg_solar_install_date',
  solarLeaseOwned: 'dcfg_solar_lease_owned',
  solarMonitoring: 'dcfg_solar_monitoring',
  solarOutput: 'dcfg_solar_output',
  solarNotes: 'dcfg_solar_notes',
  fireSafetySprinkler: 'dcfg_fire_safety_sprinkler',
  detectorsHardwired: 'dcfg_detectors_hardwired',
  waterTreatmentSystem: 'dcfg_water_treatment',
  wellWater: 'dcfg_well_water',
  trashCollection: 'dcfg_trash_collection',
  trashCans: 'dcfg_trash_cans',
  maxTrashCans: 'dcfg_max_trash_cans',
  recyclingCans: 'dcfg_recycling_cans',
  maxRecyclingCans: 'dcfg_max_recycling_cans',
  trashVendor: 'dcfg_trash_vendor',
  trashHandlesRecycling: 'dcfg_trash_handles_recycling',
  trashContractStart: 'dcfg_trash_contract_start',
  trashContractEnd: 'dcfg_trash_contract_end',
  trashMonthlyCost: 'dcfg_trash_monthly_cost',
  waterSupply: 'dcfg_water_supply',
  wellCertified: 'dcfg_well_certified',
  wellDocumentation: 'dcfg_well_documentation',
  fireAlarmSystem: 'dcfg_fire_alarm_system',
  fireAlarmSprinkler: 'dcfg_fire_alarm_sprinkler',
  fireAlarmMonitoring: 'dcfg_fire_alarm_monitoring',
  fireExtinguishers: 'dcfg_fire_extinguishers',
  coDetectors: 'dcfg_co_detectors',
  smokeDetectors: 'dcfg_smoke_detectors',
  annualInspection: 'dcfg_annual_inspection',
  chimesInHome: 'dcfg_chimes_in_home',
  lastIddInspection: 'dcfg_last_idd_inspection',
  lastDcaInspection: 'dcfg_last_dca_inspection',
};

/** Reverse map: Dataverse column → form field key */
export const REVERSE_FIELD_MAP = Object.fromEntries(
  Object.entries(FIELD_MAP).map(([k, v]) => [v, k])
);

/** Convert a Dataverse record to a form-friendly property object */
export function dataverseToForm(dvRecord) {
  const prop = createEmptyProperty();
  prop.id = dvRecord.dcfg_property_intakeid || prop.id;
  prop._dataverseId = dvRecord.dcfg_property_intakeid;
  prop.upkeepLocationId = dvRecord.dcfg_upkeep_location_id || '';
  prop.upkeepParentId = dvRecord.dcfg_upkeep_parent_id || '';
  prop.upkeepName = dvRecord.dcfg_upkeep_name || '';
  for (const [formKey, dvKey] of Object.entries(FIELD_MAP)) {
    if (dvRecord[dvKey] !== undefined && dvRecord[dvKey] !== null) {
      prop[formKey] = dvRecord[dvKey];
    }
  }
  // Per-property field overrides
  if (dvRecord.dcfg_field_overrides) {
    try { prop._fieldOverrides = JSON.parse(dvRecord.dcfg_field_overrides); } catch {}
  }
  return prop;
}

/** Convert form field changes to Dataverse column names */
export function formFieldToDataverse(fieldName) {
  return FIELD_MAP[fieldName] || null;
}
```

- [ ] **Step 2: Refactor App.jsx handleLogin to try Dataverse first**

Replace the handleLogin function (lines 41-78) with:

```javascript
async function handleLogin() {
  const upper = codeInput.trim().toUpperCase();
  if (!upper) return;
  setCodeError('');

  // Cache code for session recovery
  localStorage.setItem('intake_cached_code', upper);

  // Try Dataverse session first
  const session = await loadSession(upper);
  if (session) {
    const props = await loadProperties(session.dcfg_intake_sessionid);
    const vendors = await loadVendors(session.dcfg_intake_sessionid);
    const authUsers = await loadAuthUsers(session.dcfg_intake_sessionid);
    if (props) {
      const formProps = props.map(dataverseToForm);
      const providerData = {
        properties: formProps,
        vendors: vendors || [],
        authorizedUsers: authUsers || [],
        expiresAt: session.dcfg_expires_at,
        lastModified: new Date().toISOString(),
        _sessionId: session.dcfg_intake_sessionid,
        _source: 'dataverse',
      };
      setCode(upper);
      setProviderName(session.dcfg_provider_name);
      setData(providerData);
      if (formProps.length > 0) setSelectedPropId(formProps[0].id);
      return;
    }
  }

  // Fallback: localStorage (existing behavior)
  const existing = loadProviderData(upper);
  if (existing) {
    setCode(upper);
    setProviderName(existing.providerName || upper);
    setData(existing);
    if (existing.properties?.length > 0) setSelectedPropId(existing.properties[0].id);
    return;
  }

  // Fallback: seed file
  try {
    const resp = await fetch(`./seeds/${upper}.json`);
    if (resp.ok) {
      const seed = await resp.json();
      setCode(upper);
      setProviderName(seed.providerName || upper);
      setData(seed);
      saveProviderData(upper, seed);
      if (seed.properties?.length > 0) setSelectedPropId(seed.properties[0].id);
      return;
    }
  } catch {}

  // Fallback: demo codes
  if (ACCESS_CODES[upper]) {
    const d = createEmptyProvider();
    d.providerName = ACCESS_CODES[upper];
    setCode(upper);
    setProviderName(ACCESS_CODES[upper]);
    setData(d);
    saveProviderData(upper, d);
    return;
  }

  setCodeError('Invalid access code. Please check and try again.');
}
```

- [ ] **Step 3: Add imports to App.jsx**

Add at top:
```javascript
import { loadSession, loadProperties, loadVendors, loadAuthUsers, savePropertyBatch, USE_DATAVERSE } from './intakeApi.js';
import { dataverseToForm, formFieldToDataverse } from './storage.js';
```

- [ ] **Step 4: Refactor scheduleSave to try Dataverse first**

Replace scheduleSave (lines 24-29) with:

```javascript
const pendingChanges = useRef({}); // { propertyId: { field: value, ... } }
const [offline, setOffline] = useState(false);

function scheduleSave(newData, changedPropId, changedField, changedValue) {
  // Always save to localStorage as backup
  if (code) saveProviderData(code, newData);

  // If Dataverse is available, batch and debounce
  if (USE_DATAVERSE && changedPropId && changedField) {
    const dvField = formFieldToDataverse(changedField);
    if (dvField) {
      if (!pendingChanges.current[changedPropId]) pendingChanges.current[changedPropId] = {};
      pendingChanges.current[changedPropId][dvField] = changedValue;
    }

    clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      const batches = { ...pendingChanges.current };
      pendingChanges.current = {};

      for (const [propId, fields] of Object.entries(batches)) {
        // Find the Dataverse ID
        const prop = newData.properties.find(p => p.id === propId);
        const dvId = prop?._dataverseId;
        if (!dvId) continue;

        const ok = await savePropertyBatch(dvId, fields);
        if (!ok) {
          setOffline(true);
          // Changes are already in localStorage from the backup save above
        } else if (offline) {
          setOffline(false);
        }
      }
    }, 800);
  }
}
```

- [ ] **Step 5: Update updateProperty to pass change details**

Replace updateProperty (lines 91-98) with:

```javascript
function updateProperty(propId, field, value) {
  const newData = { ...data, properties: data.properties.map(p =>
    p.id === propId ? { ...p, [field]: value } : p
  )};
  setData(newData);
  scheduleSave(newData, propId, field, value);
}
```

- [ ] **Step 6: Add offline banner to render**

In the main layout (around line 160), add before the two-panel flex div:

```javascript
{offline && (
  <div style={{
    background: '#FEF3C7', color: '#92400E', padding: '8px 16px',
    fontSize: '12px', textAlign: 'center', borderBottom: '1px solid #F59E0B',
  }}>
    Your work is being saved locally. We'll sync when connection returns.
  </div>
)}
```

- [ ] **Step 7: Add session recovery on app mount**

Add a useEffect that checks for a cached code on mount:

```javascript
useEffect(() => {
  const cached = localStorage.getItem('intake_cached_code');
  if (cached) {
    setCodeInput(cached);
    // Auto-login with cached code on next render
  }
}, []);
```

- [ ] **Step 8: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 9: Manual verification**

Run dev server. Verify:
1. Login still works with demo codes (localStorage fallback)
2. Form changes still auto-save to localStorage
3. Offline banner does not show (USE_DATAVERSE is false)
4. No console errors

- [ ] **Step 10: Commit**

```bash
git add spa/dcfg-property-intake/src/storage.js spa/dcfg-property-intake/src/App.jsx
git commit -m "feat: add Dataverse persistence with localStorage fallback for intake form"
```

---

## Chunk 7: Session Resilience

### Task 8: Code Caching and Sync Logic

Handle the case where the customer has been idle for hours, CSRF token is stale, and they start typing again.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\intakeApi.js`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx`

- [ ] **Step 1: Add retry-with-fresh-token to intakeApi.js**

Add a wrapper function in intakeApi.js:

```javascript
/** Retry a write operation after refreshing the CSRF token. */
async function retryWithFreshToken(fn) {
  try {
    return await fn();
  } catch (e) {
    // Token might be stale — refresh and retry once
    invalidateToken();
    _csrfToken = null;
    try {
      return await fn();
    } catch (e2) {
      throw e2; // Give up after second attempt
    }
  }
}
```

Update `savePropertyBatch` to use it:
```javascript
export async function savePropertyBatch(propertyIntakeId, fields) {
  if (!USE_DATAVERSE) return false;
  try {
    await retryWithFreshToken(() =>
      apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
        ...fields,
        dcfg_last_modified_by_customer: new Date().toISOString(),
      })
    );
    return true;
  } catch (e) {
    console.warn('savePropertyBatch failed after retry:', e);
    return false;
  }
}
```

- [ ] **Step 2: Add sync-on-reconnect to App.jsx**

Add a periodic online check that syncs localStorage when connection returns:

```javascript
// Check connection every 30 seconds when offline
useEffect(() => {
  if (!offline || !USE_DATAVERSE) return;
  const interval = setInterval(async () => {
    const online = await isOnline();
    if (online) {
      setOffline(false);
      // Trigger a full save of current state
      if (data && code) {
        for (const prop of data.properties) {
          if (!prop._dataverseId) continue;
          const fields = {};
          for (const [formKey, dvKey] of Object.entries(FIELD_MAP)) {
            if (prop[formKey]) fields[dvKey] = prop[formKey];
          }
          await savePropertyBatch(prop._dataverseId, fields);
        }
      }
    }
  }, 30000);
  return () => clearInterval(interval);
}, [offline, data, code]);
```

- [ ] **Step 3: Add import for isOnline and FIELD_MAP**

In App.jsx imports, add:
```javascript
import { isOnline } from './intakeApi.js';
import { FIELD_MAP } from './storage.js';
```

- [ ] **Step 4: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add spa/dcfg-property-intake/src/intakeApi.js spa/dcfg-property-intake/src/App.jsx
git commit -m "feat: add CSRF retry, offline detection, and sync-on-reconnect for intake form"
```

---

## Chunk 8: Entity Set Verification

### Task 4a: Verify Entity Set Names

After Dataverse tables are created, query the Web API to get actual entity set names.

**Files:**
- Potentially modify: `C:\dcfg\spa\dcfg-shell\src\portalApi.js` (Task 2 entries)
- Potentially modify: `C:\dcfg\spa\dcfg-property-intake\src\intakeApi.js` (Task 5 ES object)

- [ ] **Step 1: Query entity set names**

Run against DCGWorkRequests:
```powershell
# After connecting to dcgworkrequests.crm.dynamics.com
$tables = @('dcfg_intake_session', 'dcfg_intake_field_config', 'dcfg_property_intake', 'dcfg_intake_vendor', 'dcfg_intake_authorized_user')
foreach ($t in $tables) {
  $meta = Get-CrmEntityMetadata -EntityLogicalName $t -EntityFilters Entity
  Write-Host "$t → EntitySetName: $($meta.EntitySetName)"
}
```

- [ ] **Step 2: Update entity set names if different**

If any name differs from what's hardcoded in portalApi.js (Task 2) or intakeApi.js (Task 5), update both files.

- [ ] **Step 3: Commit if changed**

```bash
git add spa/dcfg-shell/src/portalApi.js spa/dcfg-property-intake/src/intakeApi.js
git commit -m "fix: correct entity set names from Dataverse metadata"
```

---

## Chunk 9: Table Permissions

### Task 4b: Table Permissions for Intake Portal

Create table permissions for anonymous portal access to intake staging tables. Uses Enhanced Data Model — `powerpagecomponent` records.

**Files:**
- Create: `C:\DCFG\scripts\Set-IntakeTablePermissions.ps1`

- [ ] **Step 1: Write the table permissions script**

```powershell
<#
  Set-IntakeTablePermissions.ps1
  Creates table permissions for the Decades Onboarding Concierge portal site.
  Enhanced Data Model: powerpagecomponent records with content JSON.

  Target: DCGWorkRequests environment
  Site: Decades Onboarding Concierge (ID TBD after provisioning)

  PREREQUISITES:
  - Connect-CrmOnline to dcgworkrequests.crm.dynamics.com
  - Intake tables created (Task 4)
  - Power Pages site provisioned
#>

param(
  [Parameter(Mandatory)][string]$SiteId,
  [switch]$WhatIf
)

$permissions = @(
  @{
    Name = "Intake Session - Read"
    Table = "dcfg_intake_session"
    Scope = "Global"
    Privileges = @("Read")
    Description = "Anonymous users can read session records by access code"
  },
  @{
    Name = "Property Intake - Read/Write"
    Table = "dcfg_property_intake"
    Scope = "Global"
    Privileges = @("Read", "Write")
    Description = "Anonymous users can read and update property intake records scoped by session"
  },
  @{
    Name = "Intake Vendor - CRUD"
    Table = "dcfg_intake_vendor"
    Scope = "Global"
    Privileges = @("Read", "Write", "Create", "Delete")
    Description = "Anonymous users can manage vendor records within their session"
  },
  @{
    Name = "Intake Authorized User - CRUD"
    Table = "dcfg_intake_authorized_user"
    Scope = "Global"
    Privileges = @("Read", "Write", "Create", "Delete")
    Description = "Anonymous users can manage authorized user records within their session"
  },
  @{
    Name = "Field Config - Read"
    Table = "dcfg_intake_field_config"
    Scope = "Global"
    Privileges = @("Read")
    Description = "Anonymous users can read field configuration to shape the form"
  },
  @{
    Name = "Location Types - Read"
    Table = "dcfg_location_type"
    Scope = "Global"
    Privileges = @("Read")
    Description = "Anonymous users can read location types for homeType dropdown"
  }
)

# Web role for anonymous users
$anonRoleName = "Anonymous Users"

foreach ($perm in $permissions) {
  Write-Host "`nCreating: $($perm.Name)" -ForegroundColor Cyan
  Write-Host "  Table: $($perm.Table)" -ForegroundColor Gray
  Write-Host "  Scope: $($perm.Scope)" -ForegroundColor Gray
  Write-Host "  Privileges: $($perm.Privileges -join ', ')" -ForegroundColor Gray

  if ($WhatIf) {
    Write-Host "  [WhatIf] Would create powerpagecomponent record" -ForegroundColor Yellow
    continue
  }

  $content = @{
    tableName = $perm.Table
    scope = $perm.Scope.ToLower()
    privileges = @{}
  } | ConvertTo-Json -Depth 3

  # Privilege flags
  foreach ($p in $perm.Privileges) {
    $contentObj = $content | ConvertFrom-Json
    $contentObj.privileges | Add-Member -NotePropertyName $p.ToLower() -NotePropertyValue $true
    $content = $contentObj | ConvertTo-Json -Depth 3
  }

  Write-Host "  Content JSON: $content" -ForegroundColor DarkGray

  # Create powerpagecomponent record
  $record = @{
    name = $perm.Name
    powerpagecomponenttype = 18  # Table Permission
    content = $content
    powerpagesiteid = "/powerpagesites($SiteId)"
  }

  try {
    New-CrmRecord -EntityLogicalName powerpagecomponent -Fields $record
    Write-Host "  Created successfully" -ForegroundColor Green
  } catch {
    Write-Host "  FAILED: $_" -ForegroundColor Red
  }
}

# Associate with Anonymous Users web role
Write-Host "`nAssociating permissions with '$anonRoleName' web role..." -ForegroundColor Cyan
Write-Host "  NOTE: Web role association may need to be done in Power Pages admin center" -ForegroundColor Yellow

Write-Host "`n=== Summary ===" -ForegroundColor White
Write-Host "Created $($permissions.Count) table permissions" -ForegroundColor Cyan
Write-Host "IMPORTANT: Verify in Power Pages admin center that:" -ForegroundColor Yellow
Write-Host "  1. All permissions are associated with Anonymous Users web role"
Write-Host "  2. Append/AppendTo set on BOTH sides of session → child relationships"
Write-Host "  3. Test anonymous access from incognito browser"
```

- [ ] **Step 2: Run with -WhatIf**

Run: `pwsh C:\DCFG\scripts\Set-IntakeTablePermissions.ps1 -SiteId "TBD" -WhatIf`
Expected: Lists all permissions without creating.

- [ ] **Step 3: Commit**

```bash
git add scripts/Set-IntakeTablePermissions.ps1
git commit -m "feat: add table permissions script for intake portal anonymous access"
```

- [ ] **Step 4: Operator runs after site provisioning**

**GATE: Requires Power Pages site to be provisioned first. Site ID needed as parameter.**

---

## Chunk 10: Record Locking

### Task 7b: Record Locking on Property Edit

Prevent concurrent edits. Lock a property when a user opens it, auto-expire after 30 min of inactivity, override with safety warning.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\intakeApi.js`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx`

- [ ] **Step 1: Add lock functions to intakeApi.js**

```javascript
const LOCK_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes

/** Generate a unique session identifier for this browser tab */
function getBrowserSessionId() {
  let id = sessionStorage.getItem('intake_browser_session');
  if (!id) {
    id = crypto.randomUUID();
    sessionStorage.setItem('intake_browser_session', id);
  }
  return id;
}

/** Acquire lock on a property. Returns { locked: true } or { locked: false, lockedBy, lockedAt }. */
export async function acquireLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return { locked: true };
  const sessionId = getBrowserSessionId();
  try {
    // Check current lock state
    const r = await apiGet(`/${ES.properties}(${propertyIntakeId})?$select=dcfg_locked_by,dcfg_locked_at`);
    const lockedBy = r?.dcfg_locked_by;
    const lockedAt = r?.dcfg_locked_at ? new Date(r.dcfg_locked_at) : null;

    // No lock, or our own lock, or expired lock
    if (!lockedBy || lockedBy === sessionId || (lockedAt && (Date.now() - lockedAt.getTime() > LOCK_TIMEOUT_MS))) {
      await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
        dcfg_locked_by: sessionId,
        dcfg_locked_at: new Date().toISOString(),
      });
      return { locked: true };
    }

    // Someone else has an active lock
    return { locked: false, lockedBy, lockedAt: lockedAt.toISOString() };
  } catch (e) {
    console.warn('acquireLock failed:', e);
    return { locked: true }; // Fail open — don't block the user if lock check fails
  }
}

/** Force-acquire lock (override). User acknowledged the warning. */
export async function forceAcquireLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return { locked: true };
  const sessionId = getBrowserSessionId();
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      dcfg_locked_by: sessionId,
      dcfg_locked_at: new Date().toISOString(),
    });
    return { locked: true };
  } catch (e) {
    console.warn('forceAcquireLock failed:', e);
    return { locked: true };
  }
}

/** Refresh lock timestamp (call on every save to keep lock alive). */
export async function refreshLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return;
  const sessionId = getBrowserSessionId();
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      dcfg_locked_by: sessionId,
      dcfg_locked_at: new Date().toISOString(),
    });
  } catch {} // Silent — lock refresh is best-effort
}

/** Release lock when user navigates away from property. */
export async function releaseLock(propertyIntakeId) {
  if (!USE_DATAVERSE) return;
  try {
    await apiPatch(`/${ES.properties}(${propertyIntakeId})`, {
      dcfg_locked_by: null,
      dcfg_locked_at: null,
    });
  } catch {} // Silent
}
```

- [ ] **Step 2: Add lock UI to App.jsx**

Add state for lock:
```javascript
const [lockWarning, setLockWarning] = useState(null); // { propertyId, lockedBy, lockedAt }
```

When user selects a property (the click handler that sets `selectedPropId`), add lock acquisition:
```javascript
async function selectProperty(propId) {
  // Release previous lock
  if (selectedPropId) {
    const prev = data.properties.find(p => p.id === selectedPropId);
    if (prev?._dataverseId) await releaseLock(prev._dataverseId);
  }

  const prop = data.properties.find(p => p.id === propId);
  if (prop?._dataverseId) {
    const result = await acquireLock(prop._dataverseId);
    if (!result.locked) {
      setLockWarning({ propertyId: propId, lockedBy: result.lockedBy, lockedAt: result.lockedAt });
      return; // Don't select until user decides
    }
  }
  setSelectedPropId(propId);
  setLockWarning(null);
}
```

Add lock warning banner in render (before PropertyForm):
```javascript
{lockWarning && (
  <div style={{
    background: '#FEF2F2', border: '1px solid #F87171', borderRadius: '6px',
    padding: '12px 16px', margin: '0 0 12px', fontSize: '13px', color: '#991B1B',
  }}>
    <strong>This location is being edited by another session.</strong>
    <br />Changes may be lost if you continue.
    <div style={{ marginTop: '8px', display: 'flex', gap: '8px' }}>
      <button onClick={async () => {
        const prop = data.properties.find(p => p.id === lockWarning.propertyId);
        if (prop?._dataverseId) await forceAcquireLock(prop._dataverseId);
        setSelectedPropId(lockWarning.propertyId);
        setLockWarning(null);
      }} style={{ background: '#DC2626', color: '#fff', border: 'none', borderRadius: '4px', padding: '6px 12px', fontSize: '12px', cursor: 'pointer' }}>
        Edit Anyway
      </button>
      <button onClick={() => setLockWarning(null)} style={{ background: '#F1F5F9', color: '#1E293B', border: '1px solid #E2E8F0', borderRadius: '4px', padding: '6px 12px', fontSize: '12px', cursor: 'pointer' }}>
        Cancel
      </button>
    </div>
  </div>
)}
```

- [ ] **Step 3: Refresh lock on every save**

In the `scheduleSave` debounced write, after successful `savePropertyBatch`, call:
```javascript
await refreshLock(dvId);
```

- [ ] **Step 4: Release lock on page unload**

Add to App.jsx:
```javascript
useEffect(() => {
  const handleUnload = () => {
    if (selectedPropId && data) {
      const prop = data.properties.find(p => p.id === selectedPropId);
      if (prop?._dataverseId) {
        // Use sendBeacon for reliability on page close
        const token = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
        if (token) {
          navigator.sendBeacon(`/_api/${ES.properties}(${prop._dataverseId})`, JSON.stringify({
            dcfg_locked_by: null, dcfg_locked_at: null,
          }));
        }
      }
    }
  };
  window.addEventListener('beforeunload', handleUnload);
  return () => window.removeEventListener('beforeunload', handleUnload);
}, [selectedPropId, data]);
```

**Note:** `sendBeacon` doesn't support PATCH — this needs a fallback. Use `releaseLock` with `keepalive: true` in the fetch options instead:
```javascript
// In intakeApi.js, add a fire-and-forget release for page unload
export function releaseLockSync(propertyIntakeId) {
  if (!USE_DATAVERSE) return;
  const token = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
  fetch(`${API_BASE}/${ES.properties}(${propertyIntakeId})`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', '__RequestVerificationToken': token || '' },
    body: JSON.stringify({ dcfg_locked_by: null, dcfg_locked_at: null }),
    keepalive: true,
  }).catch(() => {});
}
```

- [ ] **Step 5: Add imports**

In App.jsx:
```javascript
import { acquireLock, forceAcquireLock, releaseLock, releaseLockSync, refreshLock } from './intakeApi.js';
```

- [ ] **Step 6: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`

- [ ] **Step 7: Commit**

```bash
git add spa/dcfg-property-intake/src/intakeApi.js spa/dcfg-property-intake/src/App.jsx
git commit -m "feat: add record locking with override and auto-expire for intake properties"
```

---

## Chunk 11: Auto-Login + Session Recovery

### Task 8 (revised): Auto-Login on Mount

When the page loads and a cached code exists, automatically re-authenticate without user action.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx`

- [ ] **Step 1: Replace the cached-code useEffect**

Remove the existing useEffect that just sets `codeInput`. Replace with:
```javascript
useEffect(() => {
  const cached = localStorage.getItem('intake_cached_code');
  if (cached && !code) {
    setCodeInput(cached);
    // Auto-login — simulate the login flow
    (async () => {
      const upper = cached.trim().toUpperCase();
      const session = await loadSession(upper);
      if (session) {
        const props = await loadProperties(session.dcfg_intake_sessionid);
        const vendors = await loadVendors(session.dcfg_intake_sessionid);
        const authUsers = await loadAuthUsers(session.dcfg_intake_sessionid);
        if (props) {
          const formProps = props.map(dataverseToForm);
          setCode(upper);
          setProviderName(session.dcfg_provider_name);
          setData({
            properties: formProps,
            vendors: vendors || [],
            authorizedUsers: authUsers || [],
            expiresAt: session.dcfg_expires_at,
            lastModified: new Date().toISOString(),
            _sessionId: session.dcfg_intake_sessionid,
            _source: 'dataverse',
          });
          if (formProps.length > 0) setSelectedPropId(formProps[0].id);
          return;
        }
      }
      // Dataverse unavailable or session expired — try localStorage
      const existing = loadProviderData(upper);
      if (existing) {
        setCode(upper);
        setProviderName(existing.providerName || upper);
        setData(existing);
        if (existing.properties?.length > 0) setSelectedPropId(existing.properties[0].id);
        return;
      }
      // Code expired or revoked — clear cache, show login
      localStorage.removeItem('intake_cached_code');
      setCodeError('Your session has expired. Please contact Decades for a new access code.');
    })();
  }
}, []);
```

- [ ] **Step 2: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`

- [ ] **Step 3: Manual verification**

1. Login with demo code → verify works as before
2. Refresh page → should auto-login with cached code
3. Clear localStorage → should show login screen

- [ ] **Step 4: Commit**

```bash
git add spa/dcfg-property-intake/src/App.jsx
git commit -m "feat: auto-login from cached access code on page load"
```

---

## Chunk 12: Vendor & Authorized User Persistence

### Task 9: Simplified Vendor + AuthUser Dataverse Writes

Wire vendor and authorized user components to save to Dataverse with the same offline fallback pattern.

**Files:**
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\VendorList.jsx`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\AuthorizedUsers.jsx`
- Modify: `C:\dcfg\spa\dcfg-property-intake\src\App.jsx` (pass sessionId)

- [ ] **Step 1: Simplify VendorList.jsx for intake scope**

The current VendorList has 8 fields. Simplify to 3 fields + document upload:
- Vendor name
- Service provided
- Contact phone
- Document/photo upload (file input → Dataverse note attachment)

Update the vendor form JSX to remove contract dates, email, re-bid fields. Add:
```javascript
<Field label="Upload call sheet or contact document">
  <input type="file" accept="image/*,.pdf,.doc,.docx" onChange={e => handleFileUpload(vendorId, e.target.files[0])} />
</Field>
```

File upload handler:
```javascript
async function handleFileUpload(vendorId, file) {
  if (!file) return;
  // Convert to base64 for Dataverse annotation
  const reader = new FileReader();
  reader.onload = async () => {
    const base64 = reader.result.split(',')[1];
    if (USE_DATAVERSE && sessionId) {
      try {
        await apiPost('/_api/annotations', {
          subject: file.name,
          filename: file.name,
          mimetype: file.type,
          documentbody: base64,
          'objectid_dcfg_intake_vendor@odata.bind': `/${ES.vendors}(${vendorId})`,
        });
      } catch (e) {
        console.warn('File upload failed:', e);
        // Store in localStorage as fallback
      }
    }
  };
  reader.readAsDataURL(file);
}
```

- [ ] **Step 2: Wire vendor add/save to Dataverse**

When adding a vendor, call `createVendor(sessionId, data)` from intakeApi.js. On field changes, debounce PATCH to vendor record (same 800ms pattern as properties).

- [ ] **Step 3: Wire AuthorizedUsers.jsx to Dataverse**

Same pattern — `createAuthUser(sessionId, data)` on add, debounced PATCH on field changes.

- [ ] **Step 4: Pass sessionId from App.jsx**

Add `sessionId={data?._sessionId}` to VendorList and AuthorizedUsers component renders.

- [ ] **Step 5: Verify build**

Run: `cd C:\dcfg\spa\dcfg-property-intake && npx vite build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-property-intake/src/VendorList.jsx spa/dcfg-property-intake/src/AuthorizedUsers.jsx spa/dcfg-property-intake/src/App.jsx
git commit -m "feat: wire vendor and authorized user components to Dataverse with file upload"
```

---

## Post-Implementation Gates

After all tasks complete:

1. **Operator runs Create-IntakeTables.ps1** — creates all 5 tables
2. **Run Task 4a** — verify entity set names, update code if needed
3. **Operator provisions Power Pages site** — tracked separately
4. **Operator runs Set-IntakeTablePermissions.ps1** — with actual site ID
5. **Set USE_DATAVERSE = true** in intakeApi.js
6. **Build and deploy dcfg-shell** — admin config matrix goes live
7. **Build and deploy dcfg-property-intake** — `pac pages upload-code-site`
8. **Admin: open Intake Fields tab, click "Set Defaults"** — populate initial config
9. **End-to-end test** — admin config → customer login → fill form → verify data in Dataverse → lock test → offline fallback → file upload

---

## Files Created/Modified Summary

| Action | File | Task |
|---|---|---|
| Create | `spa/dcfg-shell/src/intakeFieldKeys.js` | 1 |
| Create | `spa/dcfg-property-intake/src/intakeFieldKeys.js` | 1 |
| Modify | `spa/dcfg-shell/src/portalApi.js` | 2, 4a |
| Modify | `spa/dcfg-shell/src/screens/Admin.jsx` | 3 |
| Create | `scripts/Create-IntakeTables.ps1` | 4 |
| Create | `scripts/Set-IntakeTablePermissions.ps1` | 4b |
| Create | `spa/dcfg-property-intake/src/intakeApi.js` | 5, 7b, 8 |
| Modify | `spa/dcfg-property-intake/src/PropertyForm.jsx` | 6 |
| Modify | `spa/dcfg-property-intake/src/App.jsx` | 6b, 7, 7b, 8, 9 |
| Modify | `spa/dcfg-property-intake/src/storage.js` | 7 |
| Modify | `spa/dcfg-property-intake/src/VendorList.jsx` | 9 |
| Modify | `spa/dcfg-property-intake/src/AuthorizedUsers.jsx` | 9 |
