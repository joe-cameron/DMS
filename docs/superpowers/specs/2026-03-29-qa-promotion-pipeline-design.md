# QA Promotion Pipeline — Design Spec

**Date:** 2026-03-29
**Status:** Draft — pending operator review

---

## What It Is

A review screen on dmms (Prod) where staff processes customer-submitted property intake data. Staff approves → production location records update. Designed for bulk triage of 20-200 properties per session.

## Decisions

1. Review screen lives on **dmms** (`/#/intake-review`)
2. SPA reads intake data from Portal's Dataverse via **Power Automate bridge** flow (Prod flow with "selected environment" connector to Portal org)
3. Field-level merge — non-empty intake values overwrite production, blanks preserved
4. Vendors and authorized users are informational only — never promote
5. Documents always promote to production property, even on exception dismiss
6. **Record locking** at location level prevents concurrent merges
7. **Stuck > 24 hours** → notification with plain-language explanation
8. Bulk approve as default action — exceptions excluded
9. Priority hierarchy: property type + field priority, table-driven via admin UI
10. Simple undo — reverts intake status only, no production rollback
11. All rules, categories, thresholds table-driven with admin UI

---

## How It Works

### Data Flow

```
Customer fills intake on Portal site
  → data in Portal's Dataverse (dcfg_property_intakes)

Staff opens dmms → Intake Review screen
  → SPA writes read-request to dcfg_intake_queue_requests
  → Flow on Prod reads from Portal via "selected environment" connector
  → Flow writes results as JSON to the request row
  → SPA displays the data

Staff approves property
  → SPA writes approve-request to dcfg_intake_queue_requests
  → Flow reads intake record from Portal
  → Flow reads production dcfg_property on Prod (before-state)
  → Flow PATCHes production record (non-empty field merge)
  → Flow re-links documents from intake to production property
  → Flow writes dcfg_audit_logs with before/after JSON
  → Flow updates intake status on Portal to Approved
  → Flow releases location lock

Stuck > 24 hours
  → Scheduled flow checks for locked/pending items older than 24h
  → Sends notification: "Property X at 123 Main St has been pending approval
    for 3 days. Reason: [conflict detected / flow error / locked by user Y]"
```

### The Screen (3 levels)

**Level 1 — Session Queue**

| Column | Description |
|---|---|
| Provider Name | Customer who submitted |
| Properties | Total count |
| Progress | "X/Y reviewed" |
| Top Priority | Highest priority category in unreviewed items |
| Submitted | Date |
| Exceptions | Count of flagged items |

Click row → drill into session.

**Level 2 — Property List**

Sorted by priority score (highest first). Each row:

| Column | Description |
|---|---|
| Property Name | Address or name |
| Type | Location type |
| Priority | Badge — red (Safety), orange (Dated), yellow (Municipal), blue (Inspection), gray (General) |
| Status | Pending / Approved / Rejected / Dismissed |
| Exception | Flag if age or conflict |
| Attachments | Document count |

**Actions:**
- **Approve All Eligible** — bulk approves non-exception properties. Confirmation dialog.
- **Approve / Reject / Dismiss** — per row
- **Reject** — optional note modal

**Level 3 — Property Detail**

Side-by-side diff: production snapshot (from seed time) vs intake values. Fields grouped by priority category. Changed fields highlighted. Click-to-copy on any value.

**Context panel (collapsed):** vendor list + authorized users from intake (read-only).

### Record Locking

- When a flow begins processing a property, it sets `dcfg_locked_by` and `dcfg_locked_at` on the intake record
- SPA checks lock before allowing approve/reject — if locked, shows "Being processed by [user] since [time]"
- Flow releases lock on completion (success or failure)
- Locks older than 1 hour auto-expire (stale lock from crashed flow)

### Exception Detection

Computed by the bridge flow when fetching intake data:

- **Age:** intake `dcfg_last_modified_by_customer` older than `dcfg_intake_stale_days` config (default 90 days)
- **Conflict:** production `dcfg_property.modifiedon` is after intake `dcfg_last_modified_by_customer`

Exceptions are excluded from bulk approve. Staff sees click-to-copy values and manually pastes into production record using existing tools, or dismisses (documents still promote).

### Undo

Simple — reverts intake status from Approved back to Complete on Portal. If the promotion flow already ran, staff uses existing production editing tools to correct. Audit log records the undo for traceability. No automated production rollback.

### 24-Hour Stuck Notification

A scheduled flow (daily) on Prod:
1. Queries intake records where status = Approved AND `dcfg_locked_at` > 24 hours ago, OR status = Approved AND no corresponding audit log entry (flow never completed)
2. Sends email/Teams notification to configured recipient (`dcfg_intake_notify_email` config key)
3. Plain language: "The following intake items need attention: [Property Name] at [Address] — [reason]. Please check the Intake Review screen or contact support."

---

## One Flow, One Condition Branch

A single flow handles all cross-org operations:

**Trigger:** `dcfg_intake_queue_requests` row created on Prod

**Condition on request type:**

| Request Type | Action |
|---|---|
| Read Session List | Query Portal's `dcfg_intake_sessions` where status = Active, return as JSON |
| Read Session Detail | Query Portal's `dcfg_property_intakes` for session + production snapshots, compute exceptions, return as JSON |
| Approve Property | Lock → read intake from Portal → read production from Prod → merge fields → re-link docs → audit log → update intake status on Portal → unlock |
| Reject Property | Update intake status on Portal to Rejected + note |
| Dismiss Exception | Re-link documents on Portal → update intake status to Dismissed → audit log |
| Undo | Revert intake status on Portal to Complete → audit log |

**Error handling:** On failure, release lock, write error to request row, set status to Failed with plain-language error message.

---

## Priority Configuration

Extend `dcfg_intake_field_config` with:

| Column | Type | Description |
|---|---|---|
| `dcfg_priority_category` | Choice | Safety / Dated / Municipal-Civil / Inspection / General |
| `dcfg_priority_rank` | Integer | Sort order within category |

Managed in existing Admin screen → Intake Fields tab. Same screen handles field visibility and priority.

Property-level priority = highest priority category among fields that actually changed. A Group Home only ranks high if a safety or inspection field changed, not just because it's a Group Home.

---

## Schema Changes

**Extend `dcfg_property_intake` (on Portal):**
- `dcfg_rejection_note` — Text, multiline
- `dcfg_production_property_id` — Text (GUID of Prod record, cross-org reference)
- `dcfg_production_snapshot` — Text (JSON of production field values at seed time)
- `dcfg_production_modifiedon` — DateTime (production record timestamp at seed time)
- `dcfg_locked_by` — Text (user who initiated processing)
- `dcfg_locked_at` — DateTime (when lock was acquired)
- Extend `dcfg_intake_status` picklist: add Approved (100000003), Rejected (100000004), Dismissed (100000005)

**Extend `dcfg_intake_field_config` (on Portal):**
- `dcfg_priority_category` — Choice
- `dcfg_priority_rank` — Integer

**New table on Prod: `dcfg_intake_queue_request`**
- `dcfg_request_type` — Choice (Read Session List / Read Detail / Approve / Reject / Dismiss / Undo)
- `dcfg_request_payload` — Text (JSON parameters)
- `dcfg_response_payload` — Text (JSON result from flow)
- `dcfg_status` — Choice (Pending / Processing / Complete / Failed)
- `dcfg_error_message` — Text (plain-language error)
- `dcfg_requested_by` — Text

**Extend `dcfg_audit_logs` action type (on Prod):**
- 100000011: Intake Promote
- 100000012: Intake Reject
- 100000013: Intake Dismiss
- 100000014: Intake Undo

**New `dcfg_configs` keys:**
- `dcfg_intake_stale_days` = 90
- `dcfg_intake_notify_email` = (recipient for stuck notifications)
- `dcfg_intake_lock_timeout_minutes` = 60

---

## What This Is Not

- Vendors/authorized users never promote
- No automated cross-org production rollback
- No send-back to customer
- No WIP merging — stale items get click-to-copy
- No hardcoded rules — all table-driven
- No property creation from intake — only updates existing production records
