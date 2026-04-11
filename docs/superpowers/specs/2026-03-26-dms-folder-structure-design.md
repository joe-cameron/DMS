# DMS Folder Structure Design — DCFG_Attachments

## Problem

Current `DCFG_Attachments` layout uses `{property_id}/{doc_type}/` — opaque GUIDs, doesn't scale across 20+ customers and 500+ locations with year-over-year document renewals (insurance, fire inspections, certifications). Staff can't browse it. No versioning strategy.

## Design

### Folder Hierarchy

```
/DCFG_Attachments/
  └── {Customer Display Name}/
      └── {Street Address, City}/
          └── {Year}/
              └── {doc-type-slug}-{date}.{ext}
```

Three levels: **Customer → Location → Year → Files**

### Naming Conventions

| Level | Source | Example |
|---|---|---|
| Customer | `dcfg_customer.dcfg_display_name` | `Bancroft`, `ACP`, `Allies` |
| Location | `dcfg_property.dcfg_name` (address + city) | `1022 Atco Ave, Atco` |
| Year | Calendar year from `dcfg_certification_date`, fallback to upload year | `2025`, `2026` |
| Filename | `{category-slug}-{YYYY-MM-DD}.{ext}` | `insurance-cert-2026-03-15.pdf` |

### Filename Slug Map

| Document Category | Slug |
|---|---|
| Lease / Rental Agreement | `lease` |
| Fire Inspection Report | `fire-inspection` |
| Generator Service Contract | `generator-contract` |
| Roof Warranty | `roof-warranty` |
| Insurance Certificate | `insurance-cert` |
| Vendor Call Sheet | `vendor-callsheet` |
| Equipment Manual | `equipment-manual` |
| Other | `other-{original-filename}` |

### Real Example

```
/DCFG_Attachments/
  ├── Bancroft/
  │   ├── 1022 Atco Ave, Atco/
  │   │   ├── 2025/
  │   │   │   ├── insurance-cert-2025-04-01.pdf
  │   │   │   └── fire-inspection-2025-06-12.pdf
  │   │   └── 2026/
  │   │       ├── insurance-cert-2026-03-15.pdf
  │   │       ├── fire-inspection-2026-07-01.pdf
  │   │       └── lease-2026-01-01.pdf
  │   └── 1089 Main Ave, Clifton/
  │       └── 2026/
  │           └── generator-contract-2026-02-20.pdf
  ├── ACP/
  │   └── 109 Park Ave, Collingswood/
  │       └── 2026/
  │           └── insurance-cert-2026-05-01.pdf
  └── Allies/
      └── ...
```

### Scale Analysis

| Timeframe | Customers | Locations | Year Folders | Est. Files |
|---|---|---|---|---|
| Year 1 | 20 | 500 | 500 | ~2,000 |
| Year 5 | 25 | 625 | 3,125 | ~12,500 |
| Year 10 | 30 | 750 | 7,500 | ~30,000 |

SharePoint Online supports 30 million items per library. This structure will never be a bottleneck.

### Collision Handling

- **Same address, different customer:** No collision — customer is the top-level folder.
- **Same doc type uploaded twice in same year:** Append sequence number: `insurance-cert-2026-03-15.pdf`, `insurance-cert-2026-03-15-2.pdf`. Dataverse `dcfg_location_document` tracks which is active.
- **Special characters in address:** SharePoint auto-sanitizes. Only `" * : < > ? / \ |` are prohibited — standard addresses don't use these.

## Data Layer — Dataverse `dcfg_location_document`

Files land in SharePoint. Metadata lives in Dataverse. Staff search via Dataverse, not SharePoint.

### Existing Columns (already built)

| Column | Purpose |
|---|---|
| `dcfg_property_id` | Lookup → `dcfg_property` (production) or intake staging |
| `dcfg_doc_type` | Category (Insurance, Fire Inspection, etc.) |
| `dcfg_certification_date` | When document was issued |
| `dcfg_expiration_date` | When it expires |
| `dcfg_days_until_expiry` | Calculated — drives alerts and monitoring |
| `dcfg_alert_status` | Green / Yellow / Red |
| `dcfg_is_active` | `true` = current version, `false` = superseded |
| `dcfg_sharepoint_url` | Full URL to file in SharePoint |
| `dcfg_sharepoint_file_name` | Display name |
| `dcfg_sharepoint_item_id` | SP item ID for API operations |
| `dcfg_provider_name` | Who uploaded (customer name for intake uploads) |
| `dcfg_uploaded_at` | Timestamp |
| `dcfg_uploaded_by` | User who uploaded |

### Supersede Logic

When a new document of the same type is uploaded for the same location:

1. New `dcfg_location_document` created with `dcfg_is_active = true`
2. Previous record of same `doc_type` + `property_id` set to `dcfg_is_active = false`
3. Old file stays in SharePoint (audit trail, previous year folder)
4. Only one record per doc type per location is ever `is_active = true`

### Queryable Views for Staff

| Question | Filter |
|---|---|
| All expired insurance | `doc_type eq 'Insurance' and is_active eq true and expiration_date lt today` |
| Expiring within 30 days | `is_active eq true and days_until_expiry lt 30` |
| All docs for a location | `property_id eq {id} and is_active eq true` |
| Full history for audit | `property_id eq {id} and doc_type eq 'Insurance'` ordered by cert date desc |
| Missing fire inspections | Locations with no active Fire Inspection record |
| What did a customer submit via intake? | `provider_name eq 'Bancroft'` and linked to intake session |

## Upload Flow — Intake Portal

Customer uploads via the Onboarding Concierge SPA:

```
Customer selects category + uploads file
  → SPA sends file + metadata to Power Automate flow (via dcfg_document_request)
  → Flow resolves customer display name + location address
  → Flow creates/ensures folder path: {Customer}/{Location}/{Year}/
  → Flow uploads file to SharePoint with slugged filename
  → Flow creates dcfg_location_document record (linked to intake session, NOT production property)
  → SPA shows "Saved" confirmation

Staff QA review:
  → Staff sees document in intake review queue
  → Approves → system matches dcfg_upkeep_location_id to production dcfg_property
  → dcfg_location_document re-linked to matched production dcfg_property
  → File stays in same SharePoint location (never moves)
  → Rejects → dcfg_location_document marked inactive, file stays for audit
```

## QA Promotion — Merge Key

The `dcfg_upkeep_location_id` field is the universal merge key across all systems:

- **Seed script** populates it from UpKeep API when creating the intake session
- **Intake records** carry it through the customer's data entry (read-only, not editable)
- **Production `dcfg_property`** already has `dcfg_upkeep_location_id` from UpKeep sync
- **QA promotion** matches intake → production by this ID — no manual matching needed

When staff approves an intake record:
1. Match `dcfg_property_intake.dcfg_upkeep_location_id` → `dcfg_property.dcfg_upkeep_location_id`
2. Merge approved field values into the production property record
3. Re-link `dcfg_location_document` records from intake session to matched `dcfg_property`
4. Mark intake records as promoted

## Upload Flow — Staff Direct

Staff uploads via dcfg-shell (existing SPA):

```
Staff selects location → Documents tab → Upload
  → Same flow, but skips intake staging
  → dcfg_location_document linked directly to production dcfg_property
  → No QA step needed
```

## Folder Creation Strategy

Folders created **on first upload**, not pre-provisioned:

- Flow checks if `{Customer}/` exists → creates if not
- Flow checks if `{Customer}/{Location}/` exists → creates if not
- Flow checks if `{Customer}/{Location}/{Year}/` exists → creates if not
- Then uploads file

This avoids creating 500 empty folder trees upfront and handles new customers/locations automatically.

## What This Replaces

The current `{property_id}/{doc_type}/` structure in DCFG_Attachments is replaced by `{customer}/{location}/{year}/`. Existing files (if any) should be migrated or the old structure left in place alongside the new one during transition.
