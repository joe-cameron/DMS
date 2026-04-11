# Intake Field Configuration & Live Persistence — Design Spec

**Date:** 2026-03-26
**Status:** Operator-reviewed — decisions locked

---

## Decisions (locked by operator 2026-03-26)

1. Session parent record (`dcfg_intake_session`) — single source for code, provider, expiry, status
2. Vendors and authorized users FK to session, not property — parallel collection streams
3. Anonymous access, code-gated — no customer portal accounts
4. Customers write to staging tables only — never live tables
5. Staff review/approve gate between staging and production
6. Hidden-field data always preserved — tagged, defaults to **excluded** during approval. Staff must opt in.
7. homeType stored as text, validated against `dcfg_location_types.dcfg_name`
8. Last write wins per field — timestamp-based merge on offline sync
9. Seed rows created by Dataverse-triggered flow (not portal Web API)
10. Intake portal scoped to minimal write permissions on staging tables only

---

## Problem

The property intake form shows all 29 fields + 11 conditional sections to every customer regardless of property type. An apartment renter sees pool, generator, septic, and solar questions that don't apply — because DCFG's maintenance scope doesn't extend to those features for that property type. A single room has almost nothing applicable. This makes the form feel huge and irrelevant, which is the opposite of the product philosophy ("no pressure, no noise").

Additionally, the form currently persists to localStorage. This is fragile — data lives only on one browser on one machine. The form will be displayed for hours during long idle periods (customer gathering info, at lunch, end of day). CSRF tokens and connections go stale.

## Solution

### 1. Two-Layer Field Configuration

**Layer 1: Defaults by location type (Admin screen)**

A new "Intake Fields" tab in dcfg-shell Admin. Matrix UI:
- **Rows:** form fields and subsections (grouped by section)
- **Columns:** location types, dynamically pulled from `dcfg_location_types`
- **Cells:** toggle on/off — "does DCFG need to collect this data given maintenance scope for this property type?"

Sections 1 (Location Identity) and 2 (Site Contact) are always shown — not configurable.

Configurable items (20 rows):

| Section | Row | Default notes |
|---|---|---|
| 3: Home Details | Structure | Universal |
| 3: Home Details | Roof & Exterior | Off for apartments, condos |
| 3: Home Details | Utilities & Access | Universal |
| 4: Features | Lock Box | Universal |
| 4: Features | Pool | Off unless DCFG maintains it |
| 4: Features | Generator | Off for apartments, condos, townhouses |
| 4: Features | Garage | Off for apartments, condos |
| 4: Features | Septic System | Off for apartments, condos, townhouses |
| 4: Features | Solar Panels | Off for apartments, condos, townhouses |
| 4: Features | Fire Safety Sprinkler | Universal |
| 4: Features | Hardwired Detectors | Universal |
| 4: Features | Water Treatment | Off for apartments, condos, townhouses |
| 4: Features | Well Water | Off for apartments, condos, townhouses |
| 5: Trash | Trash Collection | Off for apartments, condos |
| 5: Trash | Water Supply | Off for apartments, condos |
| 6: Fire & Safety | Fire Alarm System | Universal |
| 7: Inspections | IDD Inspection | Group Home only |
| 7: Inspections | DCA Inspection | Group Home only |
| 1: Identity | Landlord Info | Conditional on homeOwnership = Rent |

**Layer 2: Per-property override (Location Detail screen)**

On individual property records, staff can override the location-type defaults. Toggle individual fields on/off for edge cases (e.g., "this apartment has a pool we maintain").

Overrides stored per-property in `dcfg_field_overrides` JSON column on `dcfg_property_intake`. If no override exists, defaults from Layer 1 apply.

### 2. Dynamic homeType Dropdown

The intake form's homeType dropdown currently hardcodes `['Apartment', 'Home']`. This changes to pull from `dcfg_location_types` (active records only). When the customer selects a type, the form reshapes based on that type's field config.

Location types are managed in the existing Location Types admin tab. New types automatically appear in:
- The config matrix (as a new column)
- The customer-facing homeType dropdown

homeType stored as text matching `dcfg_location_types.dcfg_name`. Validated on save.

### 3. Live Dataverse Persistence

Replace localStorage with real-time writes to staging tables.

**Write pattern:**
- Every field change triggers a debounced (800ms) PATCH to the property's intake record
- No save button. No submit button. Continuous persistence.
- Batch field changes within the debounce window into a single PATCH
- Each field write includes a `dcfg_last_modified_by_customer` timestamp

**Session resilience (anonymous + code-gated):**
- Access code cached in localStorage on first entry
- No Power Pages user session — portal is anonymous access
- CSRF token expiry handled by auto-refresh on failed write
- If code is expired/revoked: redirect to login screen with explanation
- During re-auth attempt: queue writes, do not drop them

**Offline fallback:**
- If Dataverse write fails, fall back to localStorage
- Show subtle banner: "Your work is being saved locally. We'll sync when connection returns."
- On next successful Dataverse write: sync all localStorage changes using per-field timestamp merge (last write wins per field)
- If conflict detected: keep newer value per field, show brief note "Some fields were updated from another session"
- Customer never loses work under any circumstance

**Seeding (replaces JSON seed files):**
- "Send to Customer" triggers a Dataverse flow
- Flow pulls locations from UpKeep API, writes seed rows to `dcfg_property_intake` with addresses pre-populated
- Creates `dcfg_intake_session` record with access code + 30-day expiry
- `public/seeds/` directory and seed JSON pattern retired

### 4. Hidden-Field Data Handling

When admin changes the config matrix after a customer has already entered data in a now-hidden field:

- **Data is always preserved** in the staging record — never deleted
- **Field is hidden** from the customer on next load — they don't see it anymore
- **During staff approval**, hidden-field data is flagged: "Customer entered this, but field was subsequently hidden for this location type"
- **Default: excluded** from approval into live table. Staff must explicitly opt in to import it.
- Aligns with soft-delete principle — customer's work is never silently discarded

### 5. New Dataverse Tables

**`dcfg_intake_session`** (parent record — one per customer send)

| Column | Type | Description |
|---|---|---|
| dcfg_intake_sessionid | GUID | PK |
| dcfg_access_code | Text (unique) | Customer's entry code |
| dcfg_provider_name | Text | Customer/provider display name |
| dcfg_provider_id | Text | UpKeep account reference |
| dcfg_expires_at | DateTime | Code expiry (30 days from creation) |
| dcfg_status | Picklist | New / Active / Expired / Revoked |
| dcfg_sent_by | Text | Staff email who triggered send |
| dcfg_sent_at | DateTime | When code was sent |
| dcfg_active_flag | Boolean | Soft delete |

**`dcfg_intake_field_config`** (Layer 1 — defaults by location type)

| Column | Type | Description |
|---|---|---|
| dcfg_intake_field_configid | GUID | PK |
| dcfg_location_type | Lookup | FK to dcfg_location_types |
| dcfg_field_key | Text | Identifier matching form field/section (e.g., "pool", "roofExterior", "trashCollection") |
| dcfg_visible | Boolean | Show this field for this location type |
| dcfg_active_flag | Boolean | Soft delete |

**`dcfg_property_intake`** (staging table — one row per property per session)

Mirrors `dcfg_property` schema for all 29 fields + conditional detail fields, plus:

| Additional Column | Type | Description |
|---|---|---|
| dcfg_intake_session | Lookup | FK to dcfg_intake_session |
| dcfg_home_type | Text | Location type selected by customer (validated against dcfg_location_types) |
| dcfg_intake_status | Picklist | New / In Progress / Complete / Reviewed / Approved |
| dcfg_last_modified_by_customer | DateTime | Last customer edit timestamp |
| dcfg_field_overrides | Text (JSON) | Per-property field visibility overrides from Layer 2 |
| dcfg_hidden_field_data | Text (JSON) | Preserves data entered in fields that were later hidden by config change |
| dcfg_active_flag | Boolean | Soft delete |

**`dcfg_intake_vendor`** (staging for vendor data — per session, not per property)

| Column | Type | Description |
|---|---|---|
| dcfg_intake_vendorid | GUID | PK |
| dcfg_intake_session | Lookup | FK to dcfg_intake_session |
| dcfg_vendor_name | Text | |
| dcfg_service_provided | Text | |
| dcfg_contact_name | Text | |
| dcfg_contact_phone | Text | |
| dcfg_contact_email | Text | |
| dcfg_contract_start | Date | |
| dcfg_contract_end | Date | |
| dcfg_requires_rebid | Boolean | |
| dcfg_active_flag | Boolean | Soft delete |

**`dcfg_intake_authorized_user`** (staging for authorized user data — per session)

| Column | Type | Description |
|---|---|---|
| dcfg_intake_authorized_userid | GUID | PK |
| dcfg_intake_session | Lookup | FK to dcfg_intake_session |
| dcfg_name | Text | |
| dcfg_email | Text | |
| dcfg_phone | Text | |
| dcfg_access_level | Text | "all" or "specific" |
| dcfg_location_ids | Text (JSON) | Array of dcfg_property_intake IDs |
| dcfg_active_flag | Boolean | Soft delete |

## Data Flow

```
ADMIN: "Send to Customer" on customer record
  → Creates dcfg_intake_session (code, provider, expiry)
  → Dataverse flow triggers:
    → Pull locations from UpKeep API
    → Write rows to dcfg_property_intake (addresses pre-populated, FK to session)
    → Send welcome email with code + portal link

CUSTOMER: Opens portal
  → Enters code (cached in localStorage)
  → Portal queries dcfg_intake_session WHERE access_code = {code}
  → Validates: not expired, not revoked
  → Queries dcfg_property_intake WHERE intake_session = {session_id}
  → Queries dcfg_intake_field_config for all location types (cached client-side)
  → Locations appear with addresses filled in
  → Customer picks location type → form reshapes per config
  → Every field change → debounced PATCH to dcfg_property_intake
  → Write fails → localStorage fallback + banner
  → Connection restored → per-field timestamp merge + sync + clear banner

VENDORS & AUTHORIZED USERS: Parallel collection
  → Customer adds vendors → writes to dcfg_intake_vendor (FK to session)
  → Customer adds users → writes to dcfg_intake_authorized_user (FK to session)
  → Independent of property data — no cross-dependency

STAFF: Reviews intake data
  → Change notification when customer modifies data
  → Review in dcfg-shell:
    → See all customer-entered data
    → Hidden-field data flagged, defaults to excluded
    → Staff opts in/out per field
  → Approve → write to dcfg_properties / dcfg_vendors (live tables)
  → Customer never sees internal systems
```

## Table Permissions

| Table | Intake Portal (anonymous) | dcfg-shell (staff) |
|---|---|---|
| dcfg_intake_session | Read (scoped by code) | Full CRUD |
| dcfg_property_intake | Read + Update (scoped by session) | Full CRUD |
| dcfg_intake_vendor | Read + Create + Update + Delete (scoped by session) | Full CRUD |
| dcfg_intake_authorized_user | Read + Create + Update + Delete (scoped by session) | Full CRUD |
| dcfg_intake_field_config | Read only | Full CRUD |
| dcfg_location_types | Read only (active records) | Full CRUD (existing) |

## Components Affected

| Component | Change |
|---|---|
| `dcfg-shell/Admin.jsx` | Add "Intake Fields" tab (tab 8) — config matrix, dynamic columns from dcfg_location_types |
| `dcfg-shell/LocationDetail.jsx` | Add per-property field override toggles (Layer 2) |
| `dcfg-shell/portalApi.js` | Add entity sets for new tables |
| `dcfg-property-intake/PropertyForm.jsx` | Read config from Dataverse, reshape form dynamically |
| `dcfg-property-intake/App.jsx` | Replace seed file loading with Dataverse session query, cache access code |
| `dcfg-property-intake/storage.js` | Rewrite: Dataverse primary, localStorage fallback, per-field timestamp sync |

## Not In Scope (separate specs)

- Review/approve workflow (staging → live push)
- "Send to Customer" button + flow
- Welcome email automation
- Photo upload
- Playwright E2E tests
