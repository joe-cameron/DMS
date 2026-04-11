# Onboarding Concierge — Vendors / Dates / Documents Redesign

**Date:** 2026-04-11
**Codebase:** `C:\dcfg\spa\dcfg-property-intake\`
**Live target (Test):** `decadeswelcomesyou.powerappsportals.com` (DCFGSystems-Test, `org0c17e98d`, PAC `[1]`)
**Live target (Portal):** `decades-concierge.powerappsportals.com` (Portal env, `orgf625b080`, PAC `[6]`)
**Solution:** `DCFGSystemTest`

## Purpose

Redesign the Decades Onboarding Concierge customer-facing SPA around the three things that actually matter in onboarding: **vendors, important dates, and documents.** Make location capture secondary. Enable delegation by email and bulk vendor entry via spreadsheet. Replace the existing 4-tab shell with a 4-card dashboard.

Aligns with the project directive: *vendors/dates/docs rank above location setup in onboarding UX.*

## Background

- The Concierge is a customer-facing React SPA at `C:\dcfg\spa\dcfg-property-intake\`, bundled with Vite and deployed to Power Pages.
- Current UI is a 4-tab shell: Locations, Documents, Service Providers, Your Team. Location setup is the lead tab today.
- Data model today:
  - `dcfg_intake_session` — one row per access code, holds `dcfg_access_code`, `dcfg_provider_name`, `dcfg_expires_at`
  - `dcfg_intake_property` — ~85 fields per location (identity, systems, subsystems)
  - `dcfg_intake_vendor` — flat per-session list with name, trade, contact, contract dates
  - `dcfg_intake_field_configs` — admin-controlled per-field visibility per location type
- Auth: Portal **anonymous web role** gated by the access code. No Entra identity. No session user.
- Field config table + Admin UI in `dcfg-shell` already exists and will be reused without schema change.

## Scope Summary

Replace the 4-tab shell with a 4-card dashboard, add delegation via email invites, add vendor spreadsheet upload, add a standalone dates list with per-row file attachment, trim the location form to a focused default set via the existing field-config table.

## Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| **Shell shape** | 4-card dashboard replaces 4-tab shell | Vendors/Dates/Docs > Locations per project priorities memory; cards make each workflow a direct path |
| **Cards** | Vendors, Important Dates, Location Details, Documents | Covers what the customer owes + orphan file catch-all |
| **Feedback** | Header button, not a card | Comments card dropped per operator direction |
| **Delegation placement** | Per-card button + global header button | Both surfaces; captured as delegation rows |
| **Delegation mechanics** | Capture name + email, send email, delegate logs in with same access code | No scoped access; advisory scope field on the row only |
| **Dates model** | Standalone list — users enter labels and dates freely | Explicit operator direction; no auto-surfacing from existing location/vendor date fields |
| **Spreadsheet upload** | Vendors only, fixed Decades-provided `.xlsx` template | Customer-side; flexible column mapping is a separate Decades-internal operator tool |
| **Location fields** | Reduced default set via existing `dcfg_intake_field_configs` — Identity + Site Contact + Systems Y/N + year built / home type / bedrooms / heating; operator toggles others on as needed | No hardcoding; leverage existing machinery |
| **Implementation approach** | Replace shell in place — same repo, same deploy | Concierge hasn't gone live on Portal env yet; no migration risk |
| **New tables** | `dcfg_intake_date` and `dcfg_intake_delegation` | Minimum surface for the two new capabilities |

## Architecture

### Shell & Routing

`App.jsx` is refactored from a tab shell to a hash-routed dashboard container. No router library — hand-rolled hash routing matches the existing Power Pages pattern.

```
/ (login) → /welcome → /home  (4-card dashboard)
                         ├── /home/vendors        → VendorsScreen
                         ├── /home/dates          → DatesScreen
                         ├── /home/locations      → LocationsScreen
                         └── /home/documents      → DocumentsScreen
```

Header is present on every screen after login:
- Left: customer name + back-to-home link
- Right: `💬 Give Feedback` button, `📧 Invite Helpers` button (global delegation)

Each card shows an icon, title, one-line description, and a count footer (e.g. `0 added`, `0 dates`, `4 locations`, `0 files`). No completion percentages, no nags.

### Components

**New files under `src/`:**
- `HomeDashboard.jsx` — the 4-card landing
- `VendorsScreen.jsx` — wraps `VendorList.jsx` with a spreadsheet-upload button + delegate button
- `DatesScreen.jsx` — standalone dates list with file attachment per row
- `LocationsScreen.jsx` — wraps existing `PropertyForm.jsx` list with delegate button
- `DocumentsScreen.jsx` — wraps existing `DocumentCapture.jsx` with delegate button
- `DelegateModal.jsx` — name/email capture + scope select
- `FeedbackModal.jsx` — feedback capture
- `VendorSpreadsheetModal.jsx` — upload → parse → preview → commit

**Reused unchanged:**
- `WelcomeScreen.jsx`, `SegmentedControl.jsx`, `PropertyForm.jsx`, `tokens.js`, `storage.js` save/lock plumbing, `intakeApi.js` infrastructure (new functions added), the field-config machinery in `PropertyForm.jsx`

**Modified:**
- `App.jsx` — swap tab state for hash routing + dashboard container
- `storage.js` — add `dates: []` and `delegations: []` arrays to the provider data blob
- `intakeApi.js` — add `createDate`, `updateDate`, `deleteDate`, `loadDates`, `createDelegation`, `loadDelegations`, `softDeleteDelegation`, annotation uploader for date records

**Retired:**
- `AuthorizedUsers.jsx` (the old "Your Team" tab body — the delegate-capture work moves to `DelegateModal.jsx`)

### Data flow

On login, `App.jsx` loads `session`, `properties`, `vendors`, **`dates`**, **`delegations`** via parallel calls in `intakeApi.js`. Each card reads its slice from the global data state. Writes go through the existing `scheduleSave` debouncer for property edits; vendor / date / delegation writes happen immediately on user action (matches current `VendorList.jsx` pattern).

## Data Model

### New Dataverse table: `dcfg_intake_date`

Purpose: Standalone list of important dates the customer wants Decades to know about.

| Column | Type | Format/Notes |
|---|---|---|
| `dcfg_intake_dateid` | GUID PK | system |
| `dcfg_name` | String 200 | primary name = the label (e.g. "Fire marshal inspection") |
| `dcfg_sessionid` | Lookup → `dcfg_intake_session` | ApplicationRequired |
| `dcfg_due_date` | DateTime (DateOnly) | when it's due |
| `dcfg_category` | OptionSet | Inspection / Cert Expiration / Contract Anniversary / Insurance / Other |
| `dcfg_notes` | Memo 1000 | free text |
| `dcfg_location_ref` | String 100 | optional free-text pointer to a location; not a lookup |
| `dcfg_active_flag` | Boolean | default Active=1, Retired=0 |

**File attachment:** Reuse the existing annotation pattern already used by `VendorList.jsx` for vendor files. Post to `/_api/annotations` with `objectid_dcfg_intake_date@odata.bind`. No new file infrastructure.

### New Dataverse table: `dcfg_intake_delegation`

Purpose: Audit trail of who got delegated to. Not a login/auth table — the delegate logs in with the main session access code.

| Column | Type | Format/Notes |
|---|---|---|
| `dcfg_intake_delegationid` | GUID PK | system |
| `dcfg_name` | String 200 | delegate's full name |
| `dcfg_sessionid` | Lookup → `dcfg_intake_session` | ApplicationRequired |
| `dcfg_delegate_email` | String 200 | Email format |
| `dcfg_sender_name` | String 200 | captured from modal (anonymous sender) |
| `dcfg_sender_email` | String 200 | Email format — used as Reply-To |
| `dcfg_card_scope` | OptionSet | Vendors / Dates / Locations / Documents / All — advisory |
| `dcfg_personal_note` | Memo 1000 | optional |
| `dcfg_sent_at` | DateTime | written by flow after send |
| `dcfg_active_flag` | Boolean | soft delete (revoke) |

### Existing `dcfg_intake_field_configs` — data-level changes only

No schema change. Seed rows that set `dcfg_visible = false` for all fields outside the C-cut:
- **Default visible:** streetAddress, city, state, zipCode, homeType, contactPerson, contactPhone, contactEmail, entryTime, lockBox, lockBoxCode, lockBoxLocation, yearBuilt, bedrooms, heatingType, pool, generator, garage, septicSystem, solarPanels, wellWater, fireAlarmSystem
- **Default hidden (operator toggles on as needed):** every other field (deep detail for pool, generator, solar, septic, trash, landlord, roof, etc.)

### Portal integration

For each new table, on both `org0c17e98d` (Test) and `orgf625b080` (Portal):

**Site settings** — scoped to the site GUID of the deployed concierge site:
- `Webapi/dcfg_intake_date/enabled = true`
- `Webapi/dcfg_intake_date/fields = _dcfg_sessionid_value,createdon,dcfg_active_flag,dcfg_category,dcfg_due_date,dcfg_intake_dateid,dcfg_location_ref,dcfg_name,dcfg_notes,modifiedon,statecode,statuscode`
- `Webapi/dcfg_intake_delegation/enabled = true`
- `Webapi/dcfg_intake_delegation/fields = _dcfg_sessionid_value,createdon,dcfg_active_flag,dcfg_card_scope,dcfg_delegate_email,dcfg_intake_delegationid,dcfg_name,dcfg_personal_note,dcfg_sender_email,dcfg_sender_name,dcfg_sent_at,modifiedon,statecode,statuscode`

Explicit field lists (not wildcards) per `feedback_pick_lane_explicit_or_wildcard.md`.

**Table permissions** — Parent scope via `dcfg_intake_session`, linked to the anonymous web role the existing intake tables use. Verify with `mspp_entitypermission_webroleset` intersect set.

- `dcfg_intake_date` — Create, Read, Write, Delete, Append, AppendTo
- `dcfg_intake_delegation` — Create, Read, Write, Delete, Append, AppendTo

Append/AppendTo on the parent `dcfg_intake_session` is already in place for the existing intake child tables — verify no change needed.

## Delegation Flow

### Front-end

1. User clicks per-card **Delegate** or header **Invite Helpers** button.
2. `<DelegateModal>` opens with fields:
   - **Your name** (required, pre-filled from `localStorage` after first use)
   - **Your email** (required, pre-filled from `localStorage` after first use, email format validated)
   - **Delegate name** (required)
   - **Delegate email** (required, email format validated)
   - **Card scope** (pre-selected if launched from a card, multi-select if launched from global)
   - **Personal note** (optional textarea)
3. Submit calls `createDelegation(sessionId, payload)` — inserts a row into `dcfg_intake_delegation` with `dcfg_active_flag=true`. Persists sender name/email to `localStorage` for next time.
4. Toast: "We've sent an invite to `{delegateName}`. They can use your access code to help fill this out."
5. The header dropdown (and the originating card) shows active delegations with a **Revoke** action (soft delete).

### Back-end

New Power Automate flow **`dcfg_SendIntakeDelegationInvite`**, triggered on **create of `dcfg_intake_delegation`**.

Steps:
1. Read the parent `dcfg_intake_session` to get `dcfg_access_code` and `dcfg_provider_name`.
2. Read `dcfg_configs` for `intake_delegation_from_address` and the concierge portal URL key.
3. Send email via Outlook/Office 365 connector:
   - **From:** Decades shared mailbox (config-driven)
   - **To:** `dcfg_delegate_email`
   - **Reply-To:** `dcfg_sender_email`
   - **Subject:** `[{providerName}] — {senderName} has asked you to help with their Decades onboarding`
   - **Body:** HTML template — greeting, personal note, portal link with `?code={accessCode}`, scoped card name(s), Decades blurb
4. Patch the row: `dcfg_sent_at = utcNow()`.
5. On failure: log to `dcfg_audit_logs` with row ID and error; retry up to 3 times via Scope + run-after configuration per DCFG flow patterns.

Flow build follows the standard DCFG three-step placeholder → manual connection → full definition pattern.

### Audit

- Every delegation insert + update is captured via the existing Dataverse audit on `dcfg_intake_delegation`.
- Flow send success/failure writes a row to `dcfg_audit_logs` with `actor = "Anonymous (session {sessionId}, sender {senderEmail})"`.
- Revokes (soft deletes) write to the same audit log.

## Vendor Spreadsheet Upload

### Template

Static file at `public/templates/decades-vendor-intake.xlsx`, bundled with the build. Downloaded from the Vendors card via a **Download template** link next to the **Upload spreadsheet** button. Template doubles as a collaboration artifact customers can email around to their own team.

**Columns (exact header row required):**

| Header | Type | Required |
|---|---|---|
| `Vendor Name` | text | yes |
| `Trade` | text | yes |
| `Contact Name` | text | no |
| `Contact Phone` | text | no |
| `Contact Email` | text | no |
| `Contract Start` | date | no |
| `Contract End` | date | no |
| `Notes` | text | no |

First sheet only. Extra columns ignored with a non-blocking warning. Missing required headers = hard block.

### Parser

- Library: **`xlsx` (SheetJS Community)** — pinned version in `package.json`.
- Runs 100% in the browser. No server round-trip.
- Parse output = array of candidate vendor objects matching `createEmptyVendor()`.
- Date columns read as Excel serial / JS Date / text — tolerant parse.
- Soft cap of 500 rows; above that, show "Large upload — please split into multiple files."

### Flow

1. Customer clicks **Upload spreadsheet** on the Vendors card.
2. File picker (`.xlsx`, `.xls` only).
3. Parse in memory. Parse failure → error modal with reason + retemplate link.
4. **Preview modal** (`VendorSpreadsheetModal.jsx`):
   - Summary: "Found N rows. M look good. K have problems."
   - Candidate rows table with per-row badges: OK / Warning / Error
   - Error rows not committable; customer fixes the sheet and re-uploads
   - Bulk actions: Select all / Deselect all / Select only OK
   - OK rows pre-checked
5. **Add selected to my vendor list** triggers `createVendor(sessionId, vendorObj)` for each checked row, sequentially.
6. Progress toast: "Adding M vendors… X of M done."
7. On partial failure: committed rows persist; remaining rows marked Retry in the modal.

### Edge cases

| Case | Behavior |
|---|---|
| Empty spreadsheet | Error modal "The spreadsheet looks empty." |
| Duplicate vendor names within the sheet | Both imported (no de-dupe). Decades operator tool handles merges. |
| Existing vendors in the session | Upload always appends, never replaces. |
| Unreadable date | Warning badge (not error); date field blank on import. |
| Unknown trade | Warning badge; trade value imported as-is. |

## Non-Goals

Explicit out-of-scope items for this build:

- **No tabs.** No hybrid mode, no mode flag, no dual shell.
- **No Comments / Special Thoughts card.** Replaced by the header feedback button.
- **No scoped delegate access.** Delegate sees everything; `dcfg_card_scope` is advisory metadata only.
- **No delegate authentication beyond the shared access code.**
- **No auto-surfacing of dates** from existing location/vendor records.
- **No spreadsheet upload for Dates or Locations.** Vendors only.
- **No spreadsheet column-mapping UI** in the concierge. (Decades operator tool is separate scope.)
- **No reply-ingest** from delegation emails.
- **No identity verification** on the sender name/email.
- **No push into Decades' quarterly inspection scheduler.** Concierge collects data; routing into the Decades cadence is a separate downstream flow.
- **No completion percentages or nag prompts.**
- **No migration of in-flight sessions** (concierge hasn't gone live on Portal env).

## Testing

### Unit
- Spreadsheet parser: happy path, missing required headers, bad dates, empty sheet, extra columns, 500+ rows, duplicate names, unknown trades
- Email format validator
- Delegate modal field validation
- `storage.js` additions for `dates` and `delegations` arrays

### Integration
- `dcfg_intake_date` CRUD through `intakeApi.js`
- `dcfg_intake_delegation` CRUD through `intakeApi.js`
- Annotation upload on a date record
- Anonymous web role permission checks against both new tables

### E2E (Playwright against DCFGSystems-Test `decadeswelcomesyou.powerappsportals.com`)
- Login with demo access code → 4 cards render
- Add a vendor manually → shows in list
- Upload vendor spreadsheet fixture → preview modal → commit → list grows
- Add a date with file attachment → round-trips on reload
- Delegate invite → row appears in `dcfg_intake_delegation` (verify via direct Dataverse read)
- Simulate delegate: same access code in a fresh tab → same data visible
- Upload orphan document → annotation visible

### Manual smoke after Portal env deploy
One end-to-end walkthrough via `decades-concierge.powerappsportals.com`.

## Rollout Order

1. Build + local test on `dcfg-property-intake` against DCFGSystems-Test
2. Create `dcfg_intake_date` and `dcfg_intake_delegation` + site settings + permissions in **Test** (`org0c17e98d`, PAC `[1]`)
3. Build flow `dcfg_SendIntakeDelegationInvite` via the DCFG three-step pattern
4. Deploy build to `decadeswelcomesyou.powerappsportals.com`, clear cache, smoke
5. Mirror schema + flow into **Portal env** (`orgf625b080`, PAC `[6]`)
6. Deploy build to `decades-concierge.powerappsportals.com`, clear cache, smoke
7. Stage env is skipped — concierge does not deploy to staging today; flag if that changes

After every `pac auth select` switch, restore to `[1]` per `feedback_verify_pac_auth_before_deploy.md`.

## Rollback

Git revert + redeploy. The two new tables can stay in place — empty tables are harmless. Flow can be disabled via Power Automate UI if it misbehaves.

## Open Questions

- **Spreadsheet template file origin** — Decades-provided vs. generated from column spec at build time. Resolved in implementation plan, not here.
- **Decades shared-mailbox identity** — the exact mailbox and the `dcfg_configs` key name will be set during flow build.
- **Stage env parity** — concierge currently doesn't deploy to Stage. If that needs to change, add a step; otherwise skip.
