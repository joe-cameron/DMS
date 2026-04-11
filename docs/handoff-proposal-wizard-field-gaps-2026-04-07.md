# Handoff: Proposal Wizard — Missing Field Writes

**Date:** 2026-04-07
**File:** `C:\DCFG\spa\dcfg-shell\src\NewProposalWizard.jsx`
**Function:** `generate()` (line ~293)
**Priority:** High — content controls in generated documents are blank because these fields aren't written

---

## Problem

The Proposal Wizard calculates pricing and collects signer info but only writes `dcfg_budget_total` and `dcfg_service_fee_pct` to the MSA record. The DocGen v3 flow reads many more fields from the MSA, Customer, and Vendor records. All unwritten fields produce blank content controls in the generated Word document.

## What the Flow Reads vs What the Wizard Writes

### MSA Record (`dcfg_msas`)

| Field | Flow Token | Wizard Has Value | Wizard Writes | Fix |
|-------|-----------|-----------------|---------------|-----|
| `dcfg_budget_total` | — | ✅ `totalContractValue` | ✅ | — |
| `dcfg_service_fee_pct` | `msa_service_fee_pct` | ✅ `serviceFee` | ✅ | — |
| `dcfg_effective_date` | `msa_effective_date` | ✅ `msaDate` | ✅ | — |
| `dcfg_monthly_rate` | `msa_monthly_rate` | ✅ `uniRate` or per-type | ❌ | Write `moTotal / billable.length` or `uniRate` |
| `dcfg_total_monthly` | `msa_total_monthly` | ✅ `moTotal` | ❌ | Write `moTotal` |
| `dcfg_onboarding_rate` | `msa_onboarding_rate` | ✅ `uniOnboard` or per-type | ❌ | Write `obTotal / billable.length` or `uniOnboard` |
| `dcfg_total_onboarding` | `msa_total_onboarding` | ✅ `totalOnboarding` | ❌ | Write `totalOnboarding` |
| `dcfg_location_count` | `msa_location_count` | ✅ `billable.length` | ❌ | Write `billable.length` |
| `dcfg_location_list` | `msa_location_list` | ✅ `locs` array | ❌ | Write comma-separated location names |
| `dcfg_expiration_date` | `msa_expiration_date` | ❌ not collected | ❌ | Calculate: effective + 1 year, or add field to wizard |

### Customer Record (`dcfg_customers`) — Existing customer path

| Field | Flow Token | Source | Fix |
|-------|-----------|--------|-----|
| `dcfg_billing_address` | `contract_owner_street` | Admin-type location | ✅ Already fixed — auto-fills from Admin location, patches on generate |
| `dcfg_billing_city` | `contract_owner_city` | Admin-type location | ✅ Already fixed |
| `dcfg_billing_state` | `contract_owner_state` | Admin-type location | ✅ Already fixed |
| `dcfg_billing_zip` | — | Admin-type location | ✅ Already fixed |
| `dcfg_primary_contact_title` | `contract_owner_title` | `cf.title` | Patch to customer on generate (existing customers only) |
| `dcfg_president_name` | `customer_president_name` | `cf.signerName` | Patch to customer on generate |
| `dcfg_president_title` | — | `cf.signerTitle` | Patch to customer on generate |

### Vendor Record (`dcfg_vendors`)

| Field | Flow Token | Source | Fix |
|-------|-----------|--------|-----|
| `dcfg_signer_name` | `vendor_signer_title` | `vf.signerName` | Patch to vendor on generate |
| `dcfg_signer_title` | `vendor_signer_title` | `vf.signerTitle` | Patch to vendor on generate |
| `dcfg_primary_contact` | `vendor_primary_contact` | Not collected | Add to wizard or derive from signer |
| `dcfg_phone` | `vendor_phone` | `vf.phone` (exists in state but may not be editable) | Patch if available |

## Where to Make Changes

### 1. MSA payload in `generate()` (~line 326)

Add to the `mp` object:

```javascript
dcfg_monthly_rate: parseFloat(uniRate) || (billable.length > 0 ? moTotal / billable.length : 0),
dcfg_total_monthly: moTotal,
dcfg_onboarding_rate: parseFloat(uniOnboard) || (billable.length > 0 ? obTotal / billable.length : 0),
dcfg_total_onboarding: totalOnboarding,
dcfg_location_count: billable.length,
dcfg_location_list: billable.map(l => l.name).join(', '),
```

### 2. Customer patch for existing customers (~line 318)

Already partially done (billing address). Extend to include:

```javascript
dcfg_primary_contact_title: cf.title,
dcfg_president_name: cf.signerName,
dcfg_president_title: cf.signerTitle,
```

### 3. Vendor patch (~line 322)

After getting vendorId, patch signer fields:

```javascript
if (vendorId && vf.signerName) {
  await apiPatch(`/${EntitySets.vendors}(${vendorId})`, {
    dcfg_signer_name: vf.signerName,
    dcfg_signer_title: vf.signerTitle,
  }).catch(() => {});
}
```

### 4. Admin location auto-fill (already done)

In `loadLocations()` (~line 132): finds Admin-type location, auto-fills `cf.billAddr/billCity/billState/billZip` if empty.

## Verification

After making these changes:
1. Build: `cd C:\DCFG\spa\dcfg-shell && npm run build`
2. Deploy to Test: `pac auth select --index 1 && pac pages upload-code-site --rootPath . --compiledPath dist`
3. Create a proposal for PennReach with Package A, locations, pricing
4. Generate — check the Word document for populated content controls
5. Verify in Dataverse: MSA record should have monthly_rate, total_monthly, onboarding_rate, total_onboarding, location_count, location_list populated

## Schema Check

Before writing, verify these columns exist on `dcfg_msa` in the target environment:
- `dcfg_monthly_rate` (Decimal or Currency)
- `dcfg_total_monthly` (Decimal or Currency)
- `dcfg_onboarding_rate` (Decimal or Currency)
- `dcfg_total_onboarding` (Decimal or Currency)
- `dcfg_location_count` (Whole Number)
- `dcfg_location_list` (Multi Line Text)

If any are missing, create them before deploying the SPA change.

## Test Data

PennReach (Prod): `730e8f06-3d1c-f111-8341-7ced8d709731`
- 33 locations, 1 Admin type (18 S Main St, Allentown, NJ)
- Vendor: 1-800-GOT-JUNK? (`410ae073-3427-f111-8341-000d3a35c168`) — signer fields empty
- DocGen v3 flow: `a3b5430b-bc2f-f111-88b3-6045bd02d6c7`
