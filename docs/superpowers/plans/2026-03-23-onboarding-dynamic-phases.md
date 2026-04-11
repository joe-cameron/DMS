# Dynamic Onboarding Phases Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make onboarding phases fully table-driven — phases derived from step data, not hardcoded arrays.

**Architecture:** The `dcfg_phase` column already exists on `dcfg_onboarding_checklists` and is already read by OnboardingDetail.jsx (hybrid fallback). This plan promotes `dcfg_phase` to the primary grouping mechanism: Admin UI gets a phase picker per step, OnboardingDetail derives phase groups from step data, and the hardcoded PHASES constant with step-number ranges is removed.

**Tech Stack:** React 17 (classic JSX), Dataverse Web API, Vite

**Key constraint:** SPA at `C:\DCFG\spa\dcfg-shell\src\` is READ-ONLY by default. All edits require operator approval.

---

## Current State

### What already works (no changes needed)
- `dcfg_phase` column exists on `dcfg_onboarding_checklists` (picklist, nullable, uses OnboardingPhase enum)
- `copyTemplateStepsToCase()` already copies `dcfg_phase` from template to case steps (portalApi.js:409)
- `fetchOnboardingChecklist()` already selects `dcfg_phase` (portalApi.js:363)
- OnboardingDetail.jsx:356 already prefers `dcfg_phase` over step-number lookup when present

### What needs to change
1. **Admin.jsx** — OnboardingStepsTab needs a phase dropdown per step
2. **OnboardingDetail.jsx** — Derive phases from step data instead of hardcoded PHASES constant
3. **portalApi.js** — OnboardingPhase/OnboardingPhaseLabel enums stay (they map to Dataverse picklist values), but add a PHASE_COLORS map
4. **Backfill** — Set `dcfg_phase` on existing template steps that currently have it null

---

## Chunk 1: Admin Phase Picker + Backfill Script

### Task 1: Add phase dropdown to Admin OnboardingStepsTab

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\Admin.jsx` (StepForm component, ~lines 383-507)

- [ ] **Step 1: Add dcfg_phase to StepForm initial state**

In Admin.jsx StepForm component (~line 387), add `dcfg_phase` to the form state:

```javascript
const [form, setForm] = useState({
  dcfg_step_number: step?.dcfg_step_number ?? nextNumber,
  dcfg_step_name: step?.dcfg_step_name || '',
  dcfg_responsible_role: step?.dcfg_responsible_role || '',
  dcfg_assigned_email: step?.dcfg_assigned_email || '',
  dcfg_action_type: step?.dcfg_action_type ?? 100000000,
  dcfg_predecessor_step: step?.dcfg_predecessor_step ?? 0,
  dcfg_dependency_type: step?.dcfg_dependency_type ?? 100000000,
  dcfg_phase: step?.dcfg_phase ?? null,  // <-- ADD THIS
  dcfg_notes: step?.dcfg_notes || '',
});
```

- [ ] **Step 2: Add phase dropdown UI to StepForm render**

After the dependency_type dropdown and before notes, add a Phase dropdown. Use the OnboardingPhase enum values. Import `OnboardingPhase` and `OnboardingPhaseLabel` from portalApi if not already imported.

```jsx
<div>
  <label style={labelStyle}>Phase</label>
  <select value={form.dcfg_phase ?? ''} onChange={e => setForm(f => ({ ...f, dcfg_phase: e.target.value ? parseInt(e.target.value) : null }))} style={inputStyle}>
    <option value="">— Select Phase —</option>
    {Object.entries(OnboardingPhase).map(([key, val]) => (
      <option key={val} value={val}>{OnboardingPhaseLabel[val]}</option>
    ))}
  </select>
</div>
```

- [ ] **Step 3: Include dcfg_phase in save payload**

In the StepForm save handler (~line 292-318 area), ensure `dcfg_phase` is included in both create and update payloads:

```javascript
dcfg_phase: form.dcfg_phase ?? null,
```

- [ ] **Step 4: Add dcfg_phase to Admin loadSteps query**

In the `loadSteps` function (~line 270), add `dcfg_phase` to the `$select` list so existing phase values load into the form:

```
$select=dcfg_onboarding_checklistid,dcfg_step_number,dcfg_step_name,...,dcfg_phase
```

- [ ] **Step 5: Build and verify**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

Expected: Clean build, no errors.

- [ ] **Step 6: Commit**

```bash
git add spa/dcfg-shell/src/screens/Admin.jsx
git commit -m "feat(admin): add phase dropdown to onboarding step template editor"
```

---

### Task 2: Backfill existing template steps with dcfg_phase

**Files:**
- Create: `C:\DCFG\scripts\backfill-onboarding-phase.ps1`

- [ ] **Step 1: Write backfill script**

This script reads all template steps (where `_dcfg_case_id_value eq null`) that have `dcfg_phase eq null`, and sets `dcfg_phase` based on the current hardcoded step-number ranges. Run against both environments.

```powershell
# Maps the old hardcoded ranges to phase picklist values
$phaseMap = @{
  # Steps 1-5 → Sales & Proposal (100000000)
  # Steps 6-9 → Contract Execution (100000001)
  # Steps 10-14 → Account Setup (100000002)
  # Steps 15-19 → Site Onboarding (100000003)
  # Steps 20-25 → Vendor & Compliance (100000004)
  # Steps 26-30 → Go-Live & Monitoring (100000005)
}

function Get-Phase($stepNum) {
  if ($stepNum -ge 1  -and $stepNum -le 5)  { return 100000000 }
  if ($stepNum -ge 6  -and $stepNum -le 9)  { return 100000001 }
  if ($stepNum -ge 10 -and $stepNum -le 14) { return 100000002 }
  if ($stepNum -ge 15 -and $stepNum -le 19) { return 100000003 }
  if ($stepNum -ge 20 -and $stepNum -le 25) { return 100000004 }
  if ($stepNum -ge 26)                      { return 100000005 }
  return 100000005  # fallback
}
```

Query: `dcfg_onboarding_checklists?$filter=dcfg_phase eq null&$select=dcfg_onboarding_checklistid,dcfg_step_number,dcfg_phase`

For each row: PATCH `dcfg_phase` = `Get-Phase($stepNum)`.

Run against **both** environments (stage org88778bb0, test org0c17e98d). Use `Connect` with trailing slash per PS-01.

- [ ] **Step 2: Run against stage**

```powershell
Unblock-File C:\DCFG\scripts\backfill-onboarding-phase.ps1
pwsh -File C:\DCFG\scripts\backfill-onboarding-phase.ps1
```

- [ ] **Step 3: Run against test (change org URL)**

- [ ] **Step 4: Verify — query template steps and confirm dcfg_phase is populated**

- [ ] **Step 5: Commit**

```bash
git add scripts/backfill-onboarding-phase.ps1
git commit -m "chore: backfill dcfg_phase on existing onboarding template steps"
```

---

## Chunk 2: OnboardingDetail Dynamic Phase Grouping

### Task 3: Remove hardcoded PHASES constant, derive from step data

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\OnboardingDetail.jsx` (lines 52-66, 354-361)
- Modify: `C:\DCFG\spa\dcfg-shell\src\portalApi.js` (add PHASE_COLORS export)

- [ ] **Step 1: Add PHASE_COLORS to portalApi.js**

After the OnboardingPhaseLabel export (~line 78), add:

```javascript
export const OnboardingPhaseColor = {
  [OnboardingPhase.SalesProposal]:    '#3B82F6',
  [OnboardingPhase.ContractExecution]:'#D4A017',
  [OnboardingPhase.AccountSetup]:     '#2E5295',
  [OnboardingPhase.SiteOnboarding]:   '#8B5CF6',
  [OnboardingPhase.VendorCompliance]: '#0D9488',
  [OnboardingPhase.GoLive]:           '#2d6a4f',
};
```

- [ ] **Step 2: Import new exports in OnboardingDetail.jsx**

Add `OnboardingPhaseColor` to the import from portalApi.js (line 10).

- [ ] **Step 3: Remove the hardcoded PHASES constant**

Delete lines 52-59 (the `const PHASES = [...]` array).

- [ ] **Step 4: Remove the getPhaseForStep function**

Delete lines 61-66 (the `function getPhaseForStep(stepNum)` function). It's no longer needed — phase comes from the data.

- [ ] **Step 5: Replace phase grouping logic**

Replace the existing phaseGroups computation (~lines 354-361) with dynamic derivation:

```javascript
// Derive phases from step data — no hardcoded step ranges
const phaseGroups = useMemo(() => {
  if (!checklist.length) return [];

  // Group steps by their dcfg_phase value
  const grouped = {};
  for (const step of checklist) {
    const phaseId = step.dcfg_phase;
    if (phaseId == null) continue; // skip steps with no phase assigned
    if (!grouped[phaseId]) {
      grouped[phaseId] = {
        id: phaseId,
        label: OnboardingPhaseLabel[phaseId] || `Phase ${phaseId}`,
        color: OnboardingPhaseColor[phaseId] || '#64748B',
        stepsData: [],
        done: 0,
        total: 0,
      };
    }
    grouped[phaseId].stepsData.push(step);
    grouped[phaseId].total++;
    if (step.dcfg_is_complete) grouped[phaseId].done++;
  }

  // Sort phases by their enum value (which preserves logical order)
  return Object.values(grouped).sort((a, b) => a.id - b.id);
}, [checklist]);
```

- [ ] **Step 6: Update auto-expand logic**

The auto-expand logic (~lines 149-154) currently references `PHASES`. Update it to use `phaseGroups`:

```javascript
// Auto-expand first phase with incomplete steps
useEffect(() => {
  if (phaseGroups.length > 0 && expandedPhase == null) {
    const first = phaseGroups.find(g => g.done < g.total);
    if (first) setExpandedPhase(first.id);
    else setExpandedPhase(phaseGroups[0].id);
  }
}, [phaseGroups]);
```

- [ ] **Step 7: Verify all references to PHASES and getPhaseForStep are removed**

Search the file for any remaining references to `PHASES` or `getPhaseForStep`. All phase information should now come from `phaseGroups`.

Check these locations:
- ProgressSummaryBar component — receives phases as prop, should use `phaseGroups`
- Phase accordion headers — already iterate phaseGroups
- Step row phase color — should use `step.dcfg_phase` → `OnboardingPhaseColor[step.dcfg_phase]`

- [ ] **Step 8: Build and verify**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

Expected: Clean build, no errors.

- [ ] **Step 9: Commit**

```bash
git add spa/dcfg-shell/src/screens/OnboardingDetail.jsx spa/dcfg-shell/src/portalApi.js
git commit -m "feat(onboarding): derive phases from step data, remove hardcoded 30-step structure"
```

---

### Task 4: Handle edge case — steps without dcfg_phase

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\OnboardingDetail.jsx`

- [ ] **Step 1: Add "Unassigned" phase group for steps without dcfg_phase**

In the phase grouping logic from Task 3 Step 5, handle steps where `dcfg_phase` is null (legacy data that wasn't backfilled):

```javascript
// After the main grouping loop, collect orphan steps
const orphans = checklist.filter(s => s.dcfg_phase == null);
if (orphans.length > 0) {
  grouped[-1] = {
    id: -1,
    label: 'Unassigned Steps',
    color: '#94A3B8',
    stepsData: orphans,
    done: orphans.filter(s => s.dcfg_is_complete).length,
    total: orphans.length,
  };
}
```

This ensures no steps are silently dropped if backfill missed some records or new steps are added without a phase.

- [ ] **Step 2: Build and verify**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add spa/dcfg-shell/src/screens/OnboardingDetail.jsx
git commit -m "feat(onboarding): show unassigned steps in fallback phase group"
```

---

## Chunk 3: Onboarding List Phase Display + Deploy

### Task 5: Update Onboarding.jsx case list progress to use phases from data

**Files:**
- Modify: `C:\DCFG\spa\dcfg-shell\src\screens\Onboarding.jsx`

- [ ] **Step 1: Review current progress calculation**

The current list screen (~lines 70-88) calculates progress as simple done/total counts. This doesn't need phase data — it's just step completion counts. Verify it does NOT reference the hardcoded PHASES constant.

If it does not reference PHASES, no changes needed here. Mark as verified.

- [ ] **Step 2: Commit (if changes needed)**

---

### Task 6: Build, deploy, verify

**Files:**
- Build: `C:\DCFG\spa\dcfg-shell\`

- [ ] **Step 1: Final build**

```bash
cd C:\DCFG\spa\dcfg-shell && npm run build
```

- [ ] **Step 2: Deploy to stage**

```bash
pac pages upload-code-site --rootPath . --compiledPath dist
```

- [ ] **Step 3: Clear cache**

Navigate to: `https://holding.powerappsportals.com/_services/about?clearCache=true`

- [ ] **Step 4: Deploy to test**

Switch PAC auth to test environment and repeat deploy + cache clear.

- [ ] **Step 5: Verify on stage**

1. Open Admin > Onboarding Steps tab — confirm phase dropdown appears on each step
2. Edit a step — change its phase, save, verify it persists
3. Open an existing onboarding case — confirm phases group correctly from step data
4. Add a new step with a different phase — confirm it appears in the correct group
5. Verify ProgressSummaryBar shows correct phase segments

- [ ] **Step 6: Provide launch URLs**

```
Stage: https://holding.powerappsportals.com/#/onboarding
Test:  https://dcfg-test.powerappsportals.com/#/onboarding
Cache: https://holding.powerappsportals.com/_services/about?clearCache=true
```

---

## Summary of Changes

| File | Change | Lines |
|------|--------|-------|
| `Admin.jsx` | Add phase dropdown to StepForm | ~10 lines added |
| `OnboardingDetail.jsx` | Remove PHASES constant + getPhaseForStep, derive from data | ~30 lines removed, ~25 added |
| `portalApi.js` | Add OnboardingPhaseColor export | ~7 lines added |
| `backfill-onboarding-phase.ps1` | One-time migration of existing steps | New script |

**Net effect:** ~5 fewer lines of code. No new dependencies. No schema changes (dcfg_phase already exists).
