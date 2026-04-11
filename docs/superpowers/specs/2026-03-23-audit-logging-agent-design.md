# DCFG Audit Logging Agent — Design Spec

**Date:** 2026-03-23
**Status:** Approved
**Location:** `C:\DCFG\audit\`

## Problem

The SPA has ~50 `writeAuditLog()` call sites scattered across 12 files. Six screens have zero audit coverage. Audit writes lack retry and structured error handling (one uses `.catch(console.error)`, others await inline with no fallback). There is no session replay, no pattern detection, no self-healing, and no diagnostic visibility for operators.

## Goals

1. Standalone audit module at `C:\DCFG\audit\` — independent from the SPA codebase
2. Two-tier logging: business audit events + session interaction traces
3. Reliable delivery: client-side queue with retry, `sessionStorage` persistence for crash safety
4. Full coverage: typed events for all screens + flow operations
5. Diagnostic analyzers: detect stuck records, flow failures, coverage gaps
6. Self-improving: propose threshold adjustments for admin approval, track resolution rates
7. UI: "Logging" tab in Admin screen showing diagnostics and session data
8. Verbose now, tunable later — start with full logging, dial back once stable

## Architecture

### Dataverse Tables (owned by this module)

| Table | Purpose | Write Pattern |
|-------|---------|---------------|
| `dcfg_agent_audit_logs` | Business audit events | Buffered sequential POSTs |
| `dcfg_agent_session_traces` | Interaction replay data | Flushed on error/demand |
| `dcfg_agent_diagnostics` | Analyzer findings + suggestions | Written by analyzers |
| `dcfg_agent_configs` | Settings: sample rate, buffer size, thresholds, promoted messages | Read at boot, updated via admin approval |

### Table Schemas

**`dcfg_agent_audit_logs`**
| Column | Type | Required | Notes |
|--------|------|----------|-------|
| `dcfg_event_name` | String (200) | Yes | From event catalog (e.g., `contract.sent`) |
| `dcfg_event_data` | Multiline text | No | JSON payload — fields vary per event type |
| `dcfg_severity` | Choice | Yes | Info (0), Warning (1), Error (2), Critical (3) |
| `dcfg_performed_by` | String (200) | Yes | User email |
| `dcfg_screen` | String (100) | No | Route hash where event occurred |
| `dcfg_timestamp` | DateTime | Yes | ISO 8601 |
| `dcfg_session_id` | String (50) | Yes | Links events to session traces |
| `dcfg_status` | Choice | Yes | Sent (0), Failed (1), Pending (2) |
| `dcfg_retry_count` | Whole Number | No | Number of delivery attempts |
| `dcfg_active_flag` | Boolean | Yes | Soft delete (default true) |

**`dcfg_agent_session_traces`**
| Column | Type | Required | Notes |
|--------|------|----------|-------|
| `dcfg_session_id` | String (50) | Yes | Links to audit logs |
| `dcfg_trace_data` | Multiline text | Yes | JSON array of interactions |
| `dcfg_trigger_type` | Choice | Yes | Error (0), Manual (1), Analyzer (2) |
| `dcfg_trigger_event` | String (200) | No | Event name that caused the flush |
| `dcfg_timestamp` | DateTime | Yes | When trace was captured |
| `dcfg_duration_seconds` | Whole Number | No | Window of trace data |
| `dcfg_active_flag` | Boolean | Yes | Soft delete (default true) |

**`dcfg_agent_diagnostics`**
| Column | Type | Required | Notes |
|--------|------|----------|-------|
| `dcfg_analyzer_name` | String (100) | Yes | Which analyzer produced this |
| `dcfg_finding_type` | String (100) | Yes | Category of finding |
| `dcfg_severity` | Choice | Yes | Info (0), Warning (1), Error (2), Critical (3) |
| `dcfg_suggestion` | Multiline text | Yes | Human-readable recommended action |
| `dcfg_status` | Choice | Yes | New (0), Acknowledged (1), Resolved (2), Dismissed (3) |
| `dcfg_related_record_id` | String (50) | No | Dataverse record ID if applicable |
| `dcfg_related_table` | String (100) | No | Entity logical name |
| `dcfg_resolution_outcome` | Multiline text | No | What was done to resolve |
| `dcfg_created_at` | DateTime | Yes | When finding was created |
| `dcfg_resolved_at` | DateTime | No | When finding was resolved/dismissed |
| `dcfg_active_flag` | Boolean | Yes | Soft delete (default true) |

**`dcfg_agent_configs`**
| Column | Type | Required | Notes |
|--------|------|----------|-------|
| `dcfg_config_key` | String (100) | Yes | Unique key |
| `dcfg_config_value` | Multiline text | Yes | JSON value |
| `dcfg_updated_by` | String (200) | Yes | Who last changed it |
| `dcfg_updated_at` | DateTime | Yes | When last changed |
| `dcfg_active_flag` | Boolean | Yes | Soft delete (default true) |

### Dataverse Permissions

The following table permissions must be configured for the portal Web API:

| Table | Scope | Privileges | Roles |
|-------|-------|------------|-------|
| `dcfg_agent_audit_logs` | Global | Create, Read | All authenticated |
| `dcfg_agent_session_traces` | Global | Create, Read | All authenticated |
| `dcfg_agent_diagnostics` | Global | Create, Read, Write | Admin only |
| `dcfg_agent_configs` | Global | Read | All authenticated |
| `dcfg_agent_configs` | Global | Write | Admin only |
| `dcfg_document_requests` | Global | Read | Admin only (for flowHealth analyzer) |

### Module Structure

```
C:\DCFG\audit\
  index.js              — public API: exports auditService + useAudit
  auditService.js       — core: log(), flush(), getBuffer(), getDiagnostics()
  useAudit.js           — React hook: auto-injects user context + registers trace listeners
  eventCatalog.js       — typed event definitions for all screens + flows
  sessionTrace.js       — passive DOM listener, ring buffer, trace serialization
  polyfills.js          — requestIdleCallback shim for Safari
  analyzers/
    index.js            — orchestrator: runs all analyzers, returns findings
    staleRecords.js     — detects records stuck in intermediate states
    flowHealth.js       — detects stuck document requests / flow failures
    coverage.js         — compares logged vs expected events, flags gaps
    selfTuning.js       — proposes threshold changes for admin approval
  ui/
    LoggingTab.jsx      — Admin tab: diagnostics list, session trace viewer, config controls
```

### Tier 1: Business Audit Events

- Screens emit typed events: `audit('contract.sent', { contractId })`
- Service validates against event catalog — unknown events throw in dev, warn in prod
- Required fields enforced per event type
- Buffer in memory (max 200, FIFO overflow)
- **Crash safety:** buffer written to `sessionStorage` on each append, cleared on successful flush. On next page load, any orphaned buffer entries are flushed first.
- Auto-flush: every 30s or when buffer hits 10 events
- **Flush is sequential POSTs** — Portal Web API does not support OData `$batch`. Each event is a separate POST to `/_api/dcfg_agent_audit_logs` with 50ms throttle between requests.
- Retry: exponential backoff (1s, 2s, 4s), max 3 attempts per event
- Failed events after 3 retries marked `failed` in buffer — available to analyzers, never dropped
- **Page unload:** `beforeunload` uses `fetch(url, { keepalive: true })` with headers (CSRF token + Content-Type). Falls back to writing buffer to `sessionStorage` for next-load recovery if `keepalive` is unavailable.
- Writes to `dcfg_agent_audit_logs`

### Tier 2: Session Trace

- Passive DOM listeners (`{ passive: true }`): clicks, focus/blur, form changes, route changes (via `hashchange` event on `window`), scroll, tab visibility, JS errors, failed API calls
- Excludes: passwords, fields on configurable exclusion list
- Ring buffer: last 500 interactions (~50KB ceiling)
- Processing via `requestIdleCallback` with setTimeout fallback for Safari (see `polyfills.js`)
- Never written to Dataverse by default — stays in memory
- Flushed to `dcfg_agent_session_traces` on trigger: error, analyzer finding, or user "Report Issue" action from Logging tab
- Flush includes last 60 seconds of trace context

### React Hook (`useAudit`)

```js
const audit = useAudit();
audit('contract.sent', { contractId, newValue: 'Sent' });
```

Auto-injects:
- `performedBy` from `usePortalUser()` (email, name, roles)
- `screen` from `window.location.hash` (parsed to route name — no React Router dependency)
- `timestamp`
- `sessionId` (generated once per page load)

Registers session trace listeners on first mount. Subsequent hook instances share the singleton trace via the service.

**Constraint:** `useAudit` must be called from within a component rendered inside the portal user context. This is documented but not enforced at runtime (graceful fallback to `performedBy: 'unknown'` if context is unavailable).

### Non-React Usage

```js
import { audit } from '../audit';  // relative import from SPA src
audit.log('interview.generated', { contractId }, { performedBy: email });
```

The module is imported via relative path. When wired into the SPA build, a Vite alias (`@dcfg/audit` → `C:/DCFG/audit`) will be added to `vite.config.js` (requires SPA modification with operator permission).

### Event Catalog

| Screen | Events |
|--------|--------|
| SalesDashboard | `dashboard.viewed`, `dashboard.kpiClicked`, `dashboard.refreshed` |
| CustomerList | `customer.created`, `customer.updated` |
| CustomerDetail | `customer.edited`, `customer.tabChanged` |
| ContractList | `contract.softDeleted` |
| ContractDetail | `contract.statusChanged`, `contract.fieldEdited`, `contract.docGenerated` |
| NewContractWizard | `contract.wizardCompleted`, `contract.wizardAbandoned` |
| NewProposalWizard | `proposal.created`, `proposal.msaCreated`, `proposal.docGenerated`, `proposal.stepCompleted` |
| MsaList | `msa.viewed`, `msa.filtered` |
| MsaDetail | `msa.edited`, `msa.rateChanged`, `msa.docGenerated` |
| Locations | `location.filtered`, `location.searched` |
| LocationDetail | `location.edited`, `location.certUploaded`, `location.complianceChanged` |
| Onboarding | `onboarding.created`, `onboarding.softDeleted`, `onboarding.restored`, `onboarding.filtered` |
| OnboardingDetail | `onboarding.closed`, `onboarding.reopened`, `onboarding.stepUpdated`, `onboarding.deleted` |
| SendQueue | `sendqueue.sent`, `sendqueue.completed`, `sendqueue.declined` |
| Admin | `admin.templateSaved`, `admin.stepSaved`, `admin.configChanged` |
| CompliancePanel | `compliance.checked`, `compliance.alertViewed` |
| Operations | `operations.viewed`, `operations.actionTaken` |
| Flows | `flow.docRequestCreated`, `flow.docRequestCompleted`, `flow.docRequestFailed`, `flow.docRequestStuck` |

Note: "Flows" is not a screen — these events are emitted by `createDocumentRequest()` and flow status polling. All other entries correspond to SPA screens/wizards.

Each event definition specifies: required fields, optional fields, severity level, and whether it triggers a trace flush.

### Analyzers

**staleRecords** — Queries Dataverse for records stuck in intermediate states (e.g., contract generated >3 days ago, never sent). Configurable thresholds per entity/status. Runs only for admin users (requires read access to business tables).

**flowHealth** — Queries `dcfg_document_requests` for stuck/failed requests. Correlates with `dcfg_agent_audit_logs` to identify which user action triggered the failure. Suggests: retry, escalate, or data fix. Admin-only (requires read access to `dcfg_document_requests`).

**coverage** — Compares events logged in the current session against the event catalog. Flags screens visited but with no events emitted — indicates missing instrumentation. Runs for all users (uses local buffer only, no Dataverse queries).

**selfTuning** — Tracks: which findings were acted on vs dismissed, false positive rate per analyzer, time-to-resolution. **Proposes** threshold changes (does not auto-apply) — admin reviews and approves from Logging tab. Writes learning records to `dcfg_agent_diagnostics`.

### Diagnostics UI — "Logging" Tab in Admin

- **Findings list:** Table of recent analyzer findings with severity, suggestion, and status (new/acknowledged/resolved/dismissed)
- **Session trace viewer:** Expandable timeline of user interactions attached to error events
- **Config controls:** Sliders/toggles for sample rate, buffer size, analyzer thresholds
- **Proposed changes:** Self-tuning suggestions awaiting admin approval
- **Promoted messages:** List of diagnostic messages approved for inline display on other screens
- **Report Issue button:** Manually triggers session trace flush + creates diagnostic finding
- **Retention:** Findings use `dcfg_active_flag` soft delete. Findings older than 90 days are soft-deleted by the selfTuning analyzer.

**SPA wiring (requires operator permission):** Add `'Logging'` to `TABS` array in `Admin.jsx`, import `LoggingTab` from `C:\DCFG\audit\ui\`. Alternatively, could be a standalone route (`/#/logging`) to avoid modifying Admin.jsx — operator decides.

### Self-Improving Behavior

1. Analyzers run via `requestIdleCallback` (with Safari polyfill) and on-demand from the Logging tab
2. Each finding is written to `dcfg_agent_diagnostics` with a suggested action
3. When an operator resolves or dismisses a finding, that outcome is recorded
4. `selfTuning` analyzer reviews outcomes periodically and **proposes** changes (never auto-applies):
   - High false-positive findings → propose raising threshold
   - Consistently resolved findings → propose as candidate for auto-fix or inline promotion
   - Patterns that precede failures → propose new detection rules
5. Admin reviews proposals in Logging tab, approves or rejects
6. Approved changes written to `dcfg_agent_configs` with audit trail

### Coexistence with Existing SPA Logging

- The SPA continues using `writeAuditLog()` → `dcfg_audit_logs` unchanged
- This module writes to its own `dcfg_agent_*` tables
- No naming collisions: module uses `dcfgAudit` / `DcfgAuditEvent` / `DcfgAuditAction` prefixes
- When ready to wire in: add `'Logging'` to Admin TABS (or standalone route), import from `C:\DCFG\audit\ui\`
- Gradual migration: replace `writeAuditLog()` calls one screen at a time

### Overhead Controls

- Session trace: `requestIdleCallback` (+ Safari polyfill) batching, passive listeners, fixed 50KB ring buffer
- Audit flush: buffered sequential POSTs with 50ms throttle, not per-event
- Analyzers: `requestIdleCallback`, never during user interactions
- Configurable sample rate: 100% in dev (default), tunable for prod
- All settings in `dcfg_agent_configs`, changeable from Logging tab without redeploy
