# Decades Brain — Technical Specification

## Component Type
Chat interface added to the existing `dcfg-shell` menu system. This is a new panel/route within the shell, not a standalone application.

## Access Roles
- **DCFG_Operations** — Primary users. Full read access to all brain-connected data sources.
- **DCFG_Sales** — Secondary access. Read access scoped to customers, MSAs, proposals, properties (basic), and company-wide knowledge files. No access to contract financials, billing exceptions, vendor reliability scores, or email.
- **DCFG_Admin** — Full access to everything including brain configuration.

Role detection uses the existing `usePortalUser.js` hook:
```javascript
import { usePortalUser } from '../dcfg-shell/src/usePortalUser';

const { user, hasRole, isAdmin } = usePortalUser();
const isOperations = hasRole('DCFG_Operations') || isAdmin();
const isSales      = hasRole('DCFG_Sales') || isAdmin();
const canUseBrain  = isOperations || isSales || isAdmin();
```

If `canUseBrain` is false, the chat icon is absent from the shell menu. Not disabled — absent (JS-06 pattern).

---

## Shell Integration

The chat panel mounts inside `dcfg-shell`. It is accessible from the shell's left navigation or a persistent icon in the header bar. The existing reserved AI button position (bottom-right header, currently `btn-off` with "AI (coming soon)") activates this component.

Route: `/brain` or panel overlay — defer to the shell's existing navigation pattern.

The chat panel must not interfere with the current active sub-app. If the user has Page 06 (Contract Detail) open and opens the brain chat, the contract detail remains loaded underneath. The brain panel is either a slide-over, a modal overlay, or a secondary panel — not a page navigation that destroys the current view.

---

## Data Sources — Connection Details

### Source 1: Dataverse

**Base URL:** `https://org0c17e98d.crm.dynamics.com/api/data/v9.2/`

**Authentication:** Use the existing `portalApi.js` pattern. Every request requires the CSRF token via `getToken()` (JS-03). Use `apiGet()` for all read operations.

**Entity set names (complete list — use these exactly):**

| Table | Entity Set Name |
|---|---|
| dcfg_contract | dcfg_contracts |
| dcfg_contract_line | dcfg_contract_lines |
| dcfg_customer | dcfg_customers |
| dcfg_msa | dcfg_msas |
| dcfg_msa_rate | dcfg_msa_rates |
| dcfg_vendor | dcfg_vendors |
| dcfg_property | **dcfg_propertys** |
| dcfg_property_detail | dcfg_property_details |
| dcfg_property_asset | dcfg_property_assets |
| dcfg_location_type | dcfg_location_types |
| dcfg_location_document | dcfg_location_documents |
| dcfg_ap_cost_code | dcfg_ap_cost_codes |
| dcfg_audit_log | dcfg_audit_logs |
| dcfg_send_queue | dcfg_send_queues |
| dcfg_onboarding_case | dcfg_onboarding_cases |
| dcfg_onboarding_checklist | dcfg_onboarding_checklists |
| dcfg_program | dcfg_programs |
| dcfg_document_template | dcfg_document_templates |
| dcfg_document_output | dcfg_document_outputs |
| dcfg_template_field | dcfg_template_fields |
| dcfg_brain_insight | dcfg_brain_insights |

`dcfg_propertys` is correct. Not `dcfg_properties`. Using `dcfg_properties` returns 404.

**Column name corrections — use the right column, never the left:**

| Table | Wrong (from spec) | Correct (in Dataverse) |
|---|---|---|
| dcfg_property | dcfg_owner_contact | dcfg_contact_person |
| dcfg_property | dcfg_owner_title | dcfg_contact_title |
| dcfg_property | dcfg_owner_street | dcfg_address |
| dcfg_property | dcfg_owner_city | dcfg_city |
| dcfg_property | dcfg_owner_state | dcfg_state |
| dcfg_property | dcfg_owner_email | dcfg_contact_email |
| dcfg_vendor | dcfg_contractor_legal_name | dcfg_legal_name |
| dcfg_customer / dcfg_vendor | dcfg_is_active | dcfg_active_flag |
| dcfg_contract_line | dcfg_line_description | dcfg_description |
| dcfg_contract_line | dcfg_line_amount | dcfg_amount |

**Choice field integer-to-label mappings:**

dcfg_contract.dcfg_status:
```
100000000 = Draft
100000001 = Generated
100000002 = Sent
100000003 = Signed/Received
100000004 = Closed
100000005 = Void
100000006 = Declined
```

dcfg_audit_log.dcfg_action_type:
```
100000000 = Generated
100000001 = Sent
100000002 = Signed
100000003 = Void
100000004 = Declined
100000005 = Override
100000006 = Status Changed
100000007 = Template Activated
100000008 = Template Deactivated
100000009 = Data Updated
100000010 = Other
```

dcfg_send_queue.dcfg_queue_status:
```
100000000 = Pending
100000001 = Sent
100000002 = Complete
100000003 = Cancelled
```

dcfg_brain_insight.dcfg_domain:
```
100000000 = Sales
100000001 = Operations
100000002 = Contracts
100000003 = Finance
100000004 = Company
```

dcfg_brain_insight.dcfg_priority:
```
100000000 = Critical
100000001 = High
100000002 = Medium
100000003 = Low
100000004 = Info
```

dcfg_brain_insight.dcfg_insight_type:
```
100000000 = Expiring
100000001 = Overdue
100000002 = Anomaly
100000003 = Opportunity
100000004 = Reminder
100000005 = Trend
```

dcfg_brain_insight.dcfg_insight_status:
```
100000000 = Active
100000001 = Acknowledged
100000002 = Resolved
100000003 = Archived
```

**Columns that DO NOT EXIST on dcfg_audit_log:** `dcfg_entity_type`, `dcfg_entity_id`, `dcfg_action`, `dcfg_details`. Querying these returns silent 400 errors.

**Audit log is CREATE ONLY.** Never PATCH or DELETE `dcfg_audit_logs`. Table permission is Create only.

**dcfg_budget_committed is NEVER written by the UI.** Read-only everywhere. Written exclusively by `flow_commit`.

**Lookup filter syntax:** OData filters on lookup columns require `_column_value` format:
```
$filter=_dcfg_property_id_value eq {guid}
$filter=_dcfg_customer_id_value eq {guid}
$filter=_dcfg_vendor_id_value eq {guid}
```

### Source 2: SharePoint — Company Brain Knowledge Files

**Connection:** Microsoft Graph API.

**Drive ID:** Will be provided at deployment. Use drive ID, never string-concatenated SharePoint URLs.

**Read a knowledge file:**
```
GET https://graph.microsoft.com/v1.0/drives/{driveId}/root:/company-brain/{path}:/content
```

Returns JSON. Parse and use the `entries` array. Each entry has a `_meta` block describing the file, and each entry within `entries` has an `id` (UUIDv4), `status`, `created_by`, `last_modified_by`, and timestamps.

Entries with `dataverse_ref.record_id` link back to a Dataverse record. Use this to join knowledge file context with transactional data.

**Search across all knowledge files:**
```
GET https://graph.microsoft.com/v1.0/drives/{driveId}/root/search(q='{searchTerm}')
```

**File paths (all kebab-case, no spaces):**

| Path | Contents | Roles |
|---|---|---|
| company-brain/operations/vendor-knowledge.json | Vendor notes, reliability, pricing intelligence | Operations, Admin |
| company-brain/operations/property-knowledge.json | Property quirks, access instructions, site contacts | Operations, Admin |
| company-brain/operations/certification-status.json | Cross-system cert tracking | Operations, Admin |
| company-brain/operations/seasonal-calendar.json | Annual operational patterns | Operations, Admin |
| company-brain/sales/customer-knowledge.json | Customer preferences, decision-maker dynamics | Sales, Admin |
| company-brain/sales/proposal-playbook.json | Pricing guidance, what works | Sales, Admin |
| company-brain/sales/market-intelligence.json | Competitor info, market rates | Sales, Admin |
| company-brain/contracts/contract-decisions.json | Term precedents, rationale | Admin only |
| company-brain/contracts/billing-exceptions.json | Non-standard billing arrangements | Admin only |
| company-brain/contracts/template-notes.json | Template version history | Admin only |
| company-brain/company/procedures.json | How-to for recurring processes | All roles |
| company-brain/company/team-directory.json | Extended team info | All roles |
| company-brain/company/vendor-contacts.json | Vendor reps, emergency contacts | All roles |

**Write to company brain (the ONE write operation the brain performs):**

When the user says "save this", "note that", "remember this about [entity]", write a new entry to the appropriate knowledge file.

```
PUT https://graph.microsoft.com/v1.0/drives/{driveId}/root:/company-brain/{path}:/content
Content-Type: application/json
Body: [full updated JSON file with new entry appended to entries array]
```

New entry structure:
```json
{
  "id": "[generated UUIDv4]",
  "dataverse_ref": {
    "entity_set": "[if linked to a Dataverse record]",
    "record_id": "[GUID]"
  },
  "note": "[user's text]",
  "tags": ["[extracted from context]"],
  "created_by": "[authenticated user name from usePortalUser]",
  "last_modified_by": "[same]",
  "created": "[UTC ISO 8601]",
  "last_modified": "[UTC ISO 8601]",
  "status": "active"
}
```

Write permission enforcement:

| Role | Can Write To |
|---|---|
| DCFG_Operations | operations/*, company/* |
| DCFG_Sales | sales/*, company/* |
| DCFG_Admin | * |

If the user's role does not have write permission to the target file, respond: "I can save this to the company-wide notes instead. For [domain]-specific knowledge, ask someone on that team to add it."

### Source 3: UpKeep

**Connection:** UpKeep REST API. Base URL and API key provided at deployment.

**Available endpoints (read-only):**

| Endpoint | Use |
|---|---|
| `/work-orders` | Open, in-progress, completed work orders per property |
| `/preventive-maintenance` | PM schedules and compliance |
| `/assets` | Equipment inventory per property with install dates |
| `/vendors` | Vendor certification records (insurance, licenses) |

**If UpKeep is not connected:** When a query requires UpKeep data, respond: "UpKeep data is not connected yet. I can check Dataverse and the company brain for what we have. For real-time maintenance data, check UpKeep directly." Do not fabricate maintenance data. Do not guess.

### Source 4: Email — RESTRICTED

**No user email access.** Decades Brain cannot read, search, or reference any individual's email, calendar, or Exchange data.

**System accounts only.** A configuration list of shared functional mailbox addresses will be provided at deployment. Decades Brain can ONLY query mailboxes on that list. These are shared operational mailboxes (e.g., `contracts@decades.com`), not personal accounts.

**Connection for system accounts:** Microsoft Graph API, application-level permissions scoped to the configured mailboxes.

**When a user asks an email question:** Respond: "I don't have access to email. You can check Outlook directly, or if this is something the team should track, I can save a note about it in the company brain."

**When a user asks about calendar/meetings:** Respond: "I don't have access to calendars. Check your Outlook for scheduling details."

### Source 5: Asset Lifespan Reference

**Location:** `company-brain/operations/asset-lifespans.json` in SharePoint OR `dcfg_asset_lifespan` Dataverse reference table.

**Contains:** Expected lifespan ranges for 25+ building systems/appliances across 5 property types (residential, commercial, school, group home, apartment).

**Usage:** Calculate asset age from `dcfg_property_assets.dcfg_install_date`, compare against reference lifespan for the property's `dcfg_location_type`, classify as `beyond-lifespan` (past upper bound), `end-of-life` (within 2 years of upper bound), `aging` (past lower bound), or `current` (below lower bound). Only surface `beyond-lifespan`, `end-of-life`, and `aging` in responses.

---

## Query Patterns

The brain must handle multi-source queries. For each pattern below, execute the listed queries and synthesize into a single response.

### Pattern: Vendor Lookup
Trigger: User asks about a vendor by name.
1. `GET dcfg_vendors?$filter=contains(dcfg_name,'{name}')&$select=dcfg_name,dcfg_legal_name,dcfg_active_flag`
2. `GET dcfg_contracts?$filter=_dcfg_vendor_id_value eq {vendorId}&$orderby=modifiedon desc&$top=5&$select=dcfg_name,dcfg_status,dcfg_contract_number,modifiedon`
3. Read `company-brain/operations/vendor-knowledge.json`, filter entries by `dataverse_ref.record_id == vendorId`
4. If UpKeep connected: `GET /vendors/{upkeepId}/certifications`

### Pattern: Property Lookup
Trigger: User asks about a property by name or address.
1. `GET dcfg_propertys?$filter=contains(dcfg_name,'{name}')&$select=dcfg_name,dcfg_address,dcfg_city,dcfg_state,dcfg_contact_person,dcfg_contact_email&$expand=dcfg_location_type_id($select=dcfg_name)`
2. `GET dcfg_contracts?$filter=_dcfg_property_id_value eq {propertyId}&$orderby=modifiedon desc&$top=10&$select=dcfg_name,dcfg_status,dcfg_contract_number,modifiedon`
3. `GET dcfg_property_assets?$filter=_dcfg_property_id_value eq {propertyId} and dcfg_status eq 100000000&$select=dcfg_asset_type,dcfg_asset_name,dcfg_install_date,dcfg_last_service_date`
4. Read `company-brain/operations/property-knowledge.json`, filter by `dataverse_ref.record_id == propertyId`
5. If UpKeep connected: `GET /assets?propertyId={upkeepPropertyId}`

Calculate asset ages against lifespan reference. Include only `beyond-lifespan` and `end-of-life` assets in response. Mention `aging` count as a number only ("3 other assets are aging but within expected range").

### Pattern: Customer Lookup
Trigger: User asks about a customer.
1. `GET dcfg_customers?$filter=contains(dcfg_name,'{name}')&$select=dcfg_name,dcfg_active_flag,dcfg_contact_person`
2. `GET dcfg_msas?$filter=_dcfg_customer_id_value eq {customerId}&$select=dcfg_name,dcfg_status`
3. `GET dcfg_contracts?$filter=_dcfg_customer_id_value eq {customerId}&$orderby=modifiedon desc&$top=5&$select=dcfg_name,dcfg_status,dcfg_contract_number`
4. Read `company-brain/sales/customer-knowledge.json`, filter by `dataverse_ref.record_id == customerId` (DCFG_Sales and DCFG_Admin only)

If the user's role is DCFG_Operations, do NOT return customer knowledge file entries (sales intelligence). Return only Dataverse transactional data and company-wide knowledge.

### Pattern: Operations Briefing
Trigger: User asks "what should I know", "anything due", "what's going on", or similar broad operational question.
1. `GET dcfg_brain_insights?$filter=dcfg_insight_status eq 100000000&$orderby=dcfg_priority asc&$top=10&$select=dcfg_title,dcfg_detail,dcfg_domain,dcfg_priority,dcfg_insight_type`
2. `GET dcfg_send_queues?$filter=dcfg_queue_status eq 100000000&$select=dcfg_name,dcfg_added_to_queue_date&$orderby=dcfg_added_to_queue_date asc`
3. `GET dcfg_onboarding_cases?$filter=statecode eq 0&$select=dcfg_name,modifiedon`
4. Read `company-brain/operations/certification-status.json`, filter for entries with `status == expiring-soon` or `status == expired`

Prioritize: critical/high brain insights first, then expiring certs, then pending send queue items, then stalled onboarding.

### Pattern: Contract Status Check
Trigger: User asks about a specific contract.
1. `GET dcfg_contracts?$filter=contains(dcfg_name,'{name}') or contains(dcfg_contract_number,'{number}')&$select=dcfg_name,dcfg_status,dcfg_contract_number,modifiedon&$expand=dcfg_msa_id($select=dcfg_name),dcfg_property_id($select=dcfg_name),dcfg_vendor_id($select=dcfg_name)`
2. `GET dcfg_contract_lines?$filter=_dcfg_contract_id_value eq {contractId}&$select=dcfg_description,dcfg_amount`
3. `GET dcfg_audit_logs?$filter=dcfg_related_contract_id eq '{contractId}'&$orderby=dcfg_performed_at desc&$top=5&$select=dcfg_action_type,dcfg_performed_by,dcfg_performed_at,dcfg_new_value`

Translate all integer status/action_type values to labels before including in response.

### Pattern: Budget Check
Trigger: User asks about budget, program spending, or budget health.
1. `GET dcfg_programs?$filter=contains(dcfg_name,'{name}')&$select=dcfg_name,dcfg_budget_total,dcfg_budget_committed`
2. Calculate: `remaining = budget_total - budget_committed`, `pct_committed = budget_committed / budget_total * 100`
3. `GET dcfg_brain_insights?$filter=dcfg_insight_type eq 100000005 and _dcfg_program_id_value eq {programId}&$top=3`

If `pct_committed > 85`, flag as high utilization. If `pct_committed > 95`, flag as critical.

`dcfg_budget_committed` is read-only. Never include it in any write operation.

---

## Response Behavior

### Translate system data to business language.
Display labels, not integers. Display names, not GUIDs. Never expose OData URLs, entity set names, or API paths to the user.

### Cite the source system naturally.
"The contract is in Sent status (from Dataverse). The team notes this customer prefers updated numbers before quarterly reviews (from company brain)."

### Concise first.
First response: 2-4 sentences. Offer to go deeper. Never open with a wall of data.

### Honest about gaps.
If a system is not connected or returns no data, say so. Never fabricate. "I don't have UpKeep data yet — check UpKeep directly for work order status."

### Operations language, not technical language.
Say "property" not "dcfg_propertys". Say "contract" not "dcfg_contracts". Say "the vendor's reliability notes mention..." not "the vendor-knowledge.json entry states..."

### Cross-reference when relevant.
When answering about one entity, mention related entities that add context. "This contract is under the Garden State MSA. The company brain has a note about side entrance access at this property — want me to pull that up?"

---

## Write Operations — Exhaustive List

Decades Brain performs exactly ONE type of write:

**Append an entry to a company brain knowledge file in SharePoint.**

Triggered by: "save this", "note that", "remember this about [entity]", or similar.

Method: `PUT` to Graph API with the full updated file contents (read → append → write back).

No other writes. Decades Brain does NOT:
- Create, update, or delete Dataverse records
- Trigger Power Automate flows
- Send emails
- Modify UpKeep data
- Change brain insights (those are written by scheduled flows only)

---

## Error Handling

| Error | User-Facing Response |
|---|---|
| Dataverse 404 on entity set | "I couldn't find that record. It may have been removed or I may have the wrong name. Can you be more specific?" |
| Dataverse 403 | "You don't have permission to view that data. Contact your admin if you think this is an error." |
| SharePoint file not found | "I don't have any [domain] knowledge files available yet. This is where team notes would live once the team starts capturing them." |
| UpKeep not connected | "UpKeep data isn't connected yet. I can check Dataverse and the company brain for what we have." |
| Graph API auth failure | "I'm having trouble connecting to the document library. Try again in a moment." |
| User asks for email access | "I don't have access to email. You can check Outlook directly, or I can save a note about it in the company brain." |
| User asks to create/edit a Dataverse record | "I can look up information but I can't make changes to records. You can do that in the Contracting Suite directly. Want me to find the record for you?" |
| Query returns zero results | "I didn't find anything matching that. Can you try a different name or be more specific?" Never say "no records exist" — the absence of results may be a query issue, not a data issue. |

---

## Chat UI Technical Requirements

### Component Structure
```
DecadesBrain/
  DecadesBrainPanel.jsx     # Main panel component (mounts in shell)
  DecadesBrainInput.jsx     # Text input with send button
  DecadesBrainMessage.jsx   # Individual message bubble (user or brain)
  DecadesBrainSuggestions.jsx # Contextual suggested questions
  hooks/
    useBrainQuery.js        # Orchestrates multi-source queries
    useKnowledgeFiles.js    # Reads/writes SharePoint company brain files
    useAssetLifespan.js     # Lifespan calculation logic
  utils/
    statusLabels.js         # Integer-to-label maps for all choice fields
    sourceFormatter.js      # Formats source attribution tags
```

### State Management
- Conversation history: React state (`useState` array of message objects). Reset on panel close.
- No `localStorage`, no `sessionStorage`, no persistent client-side cache (JS-10 pattern — brain data must reflect live state).
- Knowledge file contents: Fetched fresh on first query that needs them per session. Held in memory for the session duration.
- Lifespan reference data: Fetched once on first property query, held in memory.

### Loading States
- Typing indicator appears immediately on send.
- If query takes >2 seconds, show: "Checking [system name]..." as the indicator text updates per source being queried.
- Never show a blank or frozen panel while waiting.

### Suggested Questions (shown on empty conversation)

DCFG_Operations user:
```
"Any certifications expiring soon?"
"Are there stalled onboarding cases?"
"Show me properties with aging equipment"
"What's in the send queue?"
```

DCFG_Sales user:
```
"Any proposals needing follow-up?"
"What's new with my customers?"
"Show me onboarding cases in progress"
```

DCFG_Admin user:
```
"Give me an operations briefing"
"Any critical brain insights?"
"Budget health across all programs"
```

Suggestions update after the first exchange. If user asked about a customer, show: "Show me their properties", "Any open contracts?", "What do we know about them?"

### Tappable Entity References
When a response mentions a customer, vendor, property, contract, or MSA by name, render it as a tappable link that navigates to the corresponding screen in the Contracting Suite:

| Entity | Target Route |
|---|---|
| Customer | Page 03 Customer Detail |
| MSA | Page 05 MSA Detail |
| Contract | Page 06 Contract Detail |
| Property | Page 08 Location Management (filtered) |

Use the existing shell navigation. Do not open new windows or tabs.

### Save to Brain Action
When the brain detects the user is sharing knowledge (mentions a fact about a vendor, customer, or property with intent to remember), show a subtle "Save to Brain" chip below the input. Tapping it confirms the save. The brain determines the appropriate knowledge file based on the entity type and user role, appends the entry, and confirms: "Saved to [domain] knowledge."

---

## First-Use Onboarding & Capability Discovery

Users will not know what Decades Brain can do. The interface must teach them through guided examples, not documentation. This section defines the onboarding experience, the persistent capability menu, and the document generation capabilities.

### First-Use Welcome (shown once per user, then dismissed)

On first open, before the suggested questions, show a brief welcome card:

```
Welcome to Decades Brain

I can help you find information across all DCFG systems — contracts, 
properties, vendors, certifications, onboarding cases, and more.

Try asking me a question, pick from the suggestions below, or tap 
"Explore" to see everything I can do.

[Got it]  [Explore what I can do →]
```

"Got it" dismisses the card and shows the role-based suggested questions. "Explore what I can do" opens the Capability Explorer.

Track dismissal state per user. After the user taps "Got it" or "Explore", do not show the welcome card again. Store this flag via a lightweight user preference — either a cookie (acceptable here since it is UI state, not cached data) or a single-row Dataverse record per user.

### Capability Explorer

Accessible at any time via a persistent icon in the chat panel header (a compass or lightbulb icon next to the close/minimize button). Tapping it opens a scrollable panel that replaces the conversation temporarily. Tapping "Back to chat" returns to the conversation.

The explorer is organized into capability categories. Each category shows 3-5 example prompts the user can tap to execute immediately.

**Category structure:**

```
┌─────────────────────────────────────────┐
│  🔍  EXPLORE DECADES BRAIN              │
│                                         │
│  ► Operations Intelligence              │
│  ► Property & Asset Lookups             │
│  ► Vendor & Certification Tracking      │
│  ► Contract & MSA Queries               │
│  ► Budget & Program Health              │
│  ► Onboarding Case Tracking             │
│  ► Team Knowledge & Notes               │
│  ► Document Generation                  │
│                                         │
│  [Back to chat]                         │
└─────────────────────────────────────────┘
```

Tapping a category expands it to show example prompts:

```
► Operations Intelligence

  "Give me an operations briefing"
  "Anything urgent I should know about today?"
  "Which certifications are expiring this month?"
  "Are there any stalled onboarding cases?"
  "Show me the send queue"

  Each of these is tappable — tapping sends it as a 
  message and returns to the chat view.
```

**Full category definitions:**

| Category | Example Prompts |
|---|---|
| Operations Intelligence | "Give me an operations briefing" · "Anything urgent today?" · "Which certifications are expiring this month?" · "Are there stalled onboarding cases?" · "Show me the send queue" |
| Property & Asset Lookups | "Tell me about [property name]" · "Which properties have aging equipment?" · "What assets are past their lifespan at [property]?" · "Who's the site contact at [property]?" · "Show me all properties for [customer]" |
| Vendor & Certification Tracking | "What do we know about [vendor]?" · "Is [vendor]'s insurance current?" · "Which vendors have expiring certs?" · "Show me [vendor]'s contract history" · "Any team notes on [vendor]?" |
| Contract & MSA Queries | "What's the status of [contract]?" · "Show me the last 5 contracts for [customer]" · "Any contracts pending signature over 14 days?" · "Pull up the audit trail for [contract]" · "What are the line items on [contract]?" |
| Budget & Program Health | "Budget health for [program]" · "Which programs are over 85% committed?" · "Show me budget across all programs" · "How much is remaining on [program]?" |
| Onboarding Case Tracking | "Show me active onboarding cases" · "What step is [case] on?" · "Which cases haven't moved in over a week?" · "Show me the checklist for [case]" |
| Team Knowledge & Notes | "What do we know about [customer]?" · "Any notes on [property]?" · "Save this: [fact about a vendor/property/customer]" · "What procedures do we have for [topic]?" · "Who handles [process]?" |
| Document Generation | "Generate a Work Order Budget Report for WO-2026-0033" · "Create a Program Budget Report for Facilities Refresh 2026" · "Equipment health snapshot for Albany Capital Partners" · "Build a Capital Replacement Plan for Albany Capital Partners" · "Vendor performance summary for ABC Cleaning" · "Property condition report for Cedar Grove" |

Tapping any example prompt sends it directly to the chat as a user message and returns to the conversation view. The brain processes it like any other question.

**Role filtering in the explorer:** Only show categories and prompts relevant to the user's role. DCFG_Sales does not see "Vendor & Certification Tracking" or "Operations Intelligence." DCFG_Operations does not see customer sales intelligence prompts. DCFG_Admin sees everything.

| Category | DCFG_Operations | DCFG_Sales | DCFG_Admin |
|---|---|---|---|
| Operations Intelligence | Yes | No | Yes |
| Property & Asset Lookups | Yes | Basic only (no asset details) | Yes |
| Vendor & Certification Tracking | Yes | No | Yes |
| Contract & MSA Queries | Yes | Yes | Yes |
| Budget & Program Health | Yes | No | Yes |
| Onboarding Case Tracking | Yes | Yes | Yes |
| Team Knowledge & Notes | Yes | Yes | Yes |
| Document Generation | Yes | Yes (limited templates) | Yes |

### Contextual Suggestions — Enhanced

The existing suggested questions (shown on empty conversation) remain. Additionally, after every brain response, show 2-3 contextual follow-up suggestions below the response as tappable chips.

Logic for contextual suggestions:

| After response about... | Suggest |
|---|---|
| A specific vendor | "Show their contract history" · "Any team notes?" · "Certification status?" |
| A specific property | "What assets are tracked here?" · "Recent work history?" · "Any site notes?" |
| A specific customer | "Show their properties" · "Active contracts?" · "Any team notes?" |
| A specific contract | "Show line items" · "Audit trail?" · "Which property?" |
| A specific program | "Budget breakdown?" · "Which contracts are under this?" |
| An operations briefing | "Tell me more about [top insight]" · "Show all expiring certs" · "Open onboarding cases" |
| A document generation request | "Email this to me" · "Generate another for [entity]" · "Save to SharePoint" |

These chips appear below the brain's response message. They disappear when the user types a new message or taps one.

---

## Document Generation

Decades Brain can generate documents and presentations on request by querying live data from connected systems and producing formatted output. This is a read operation (querying data) combined with a file creation operation (building the document).

### How It Works

1. User requests a document: "Create a property condition report for Cedar Grove"
2. Brain queries the relevant data sources (same query patterns as conversational responses)
3. Brain assembles the data into a structured document using a registered template
4. Document is generated and offered for download or save to SharePoint

### Template Registry

Templates are defined in a configuration file stored in the company brain:

**File:** `company-brain/_config/document-templates.json`

This file contains two categories of templates:

**Category 1: Production report templates.** These have full slide/page layout specifications, exact data queries, calculated fields, conditional logic, and design tokens. They produce pixel-accurate output matching approved designs. The specifications for these templates are stored as separate files in `company-brain/_config/report-specs/` and referenced by ID.

**Category 2: Ad-hoc report templates.** These define data sources and general structure but allow the AI to compose the layout. They produce useful output without requiring a pre-approved design.

**Production report specs are stored as separate markdown files:**

```
company-brain/
  _config/
    document-templates.json          # Template registry (index)
    report-specs/
      RPT-WO-001.md                  # Single Work Order Budget Report spec
      RPT-PGM-001.md                 # Program Budget Performance Report spec
      RPT-RNW-001.md                 # Contract Renewal Pipeline Report spec (pending)
```

When a user triggers a production report, the brain reads the full spec from `report-specs/` and follows it exactly — queries, calculations, layout, conditional logic, design tokens. No creative interpretation. The spec is the source of truth.

**Template registry (document-templates.json):**

```json
{
  "_meta": {
    "type": "document-template-registry",
    "version": "1.1",
    "description": "Registry of all document and presentation templates available through Decades Brain. Production templates reference full specs in report-specs/. Ad-hoc templates define data sources and let the AI compose the layout."
  },
  "templates": [
    {
      "id": "RPT-WO-001",
      "name": "Single Work Order Budget Report",
      "description": "Single-slide PowerPoint showing how one work order's budget is consumed by original scope and amendments. Includes budget spend-down bar, financial table, timeline, Exhibit A line items, and amendment history.",
      "category": "production",
      "spec_file": "company-brain/_config/report-specs/RPT-WO-001.md",
      "output_format": "pptx",
      "slide_count": 1,
      "trigger_phrases": [
        "work order budget report",
        "WO budget report for",
        "work order report for",
        "show me the budget on WO",
        "pull up WO budget"
      ],
      "required_entity": "contract",
      "required_fields": ["dcfg_contract_number"],
      "data_sources": [
        {"system": "dataverse", "entity_set": "dcfg_contracts", "role": "primary + amendments"},
        {"system": "dataverse", "entity_set": "dcfg_contract_lines", "role": "line items"},
        {"system": "dataverse", "entity_set": "dcfg_programs", "role": "program context via expand"}
      ],
      "roles": ["DCFG_Operations", "DCFG_Admin"],
      "design_tokens": "defined in spec file"
    },
    {
      "id": "RPT-PGM-001",
      "name": "Program Budget Performance Report",
      "description": "6-slide PowerPoint covering program budget health across multiple work orders and locations. Includes title slide, budget waterfall, WO detail table, spend by location cards, spend-down timeline with monthly/cumulative charts, and closing summary.",
      "category": "production",
      "spec_file": "company-brain/_config/report-specs/RPT-PGM-001.md",
      "output_format": "pptx",
      "slide_count": 6,
      "trigger_phrases": [
        "program budget report",
        "program report for",
        "program performance report",
        "budget report for program",
        "show me the program budget"
      ],
      "required_entity": "program",
      "required_fields": ["dcfg_name or dcfg_programid"],
      "data_sources": [
        {"system": "dataverse", "entity_set": "dcfg_programs", "role": "primary"},
        {"system": "dataverse", "entity_set": "dcfg_contracts", "role": "work orders + amendments"},
        {"system": "dataverse", "entity_set": "dcfg_contract_lines", "role": "optional line detail"}
      ],
      "conditional_logic": [
        "Only 1 WO → fall back to RPT-WO-001 format",
        "Only 1 location → skip Slide 4, merge into Slide 2",
        "Budget > 90% → amber warning bar",
        "Budget exceeded → red warning bar with overflow"
      ],
      "roles": ["DCFG_Operations", "DCFG_Admin"]
    },
    {
      "id": "RPT-CAP-001",
      "name": "Capital Replacement Plan",
      "description": "Equipment health and replacement report for a customer's portfolio. Runs in two modes: (1) Point-in-time snapshot — run anytime to see current equipment status, what's overdue, what's approaching end of life, and T&M repair spend. Used by operations for ongoing visibility. (2) Renewal/budget proposal — full 6-slide customer-facing presentation with three budget tiers, staff satisfaction data, mission framing, and fiscal year T&M history. Used for annual renewal conversations.",
      "category": "production",
      "spec_file": "company-brain/_config/report-specs/RPT-CAP-001.md",
      "output_format": "pptx",
      "alternate_format": "html",
      "modes": {
        "snapshot": {
          "description": "Point-in-time operational view. Current equipment health, overdue items, approaching items, recent T&M spend. No tier pricing, no staff survey, no mission framing. Fewer slides — condensed to the data that matters for an operational check.",
          "slide_count": 3,
          "slides": ["Title + KPI summary", "What's Due for Replacement (full asset table)", "T&M Repair History (recent spend, repeat calls)"],
          "includes": ["Equipment age vs lifespan status", "Replace Now + Budget FY counts", "T&M spend to date", "Repeat T&M flagging", "Location breakdown"],
          "excludes": ["Tier pricing cards", "Staff satisfaction survey", "Mission framing text", "Your Options slide", "Closing slide with mission language"],
          "title_format": "Equipment Health Snapshot — {customer_name} — as of {date}",
          "t_and_m_window": "Rolling 12 months from report date (not fiscal year)"
        },
        "renewal": {
          "description": "Full customer-facing renewal proposal. All 6 slides including three budget tiers, staff satisfaction, mission framing, problem/success panels, and closing. This is the sales document.",
          "slide_count": 6,
          "slides": ["Title + Tier Preview", "By Location Type", "What Your Staff Is Saying", "What's Due for Replacement", "Your Options (3 Tiers)", "Closing"],
          "includes": ["Everything in snapshot PLUS tier pricing, staff survey, mission language, problem/success panels, payback periods"],
          "title_format": "Capital Replacement Plan — FY {year} Facilities Budget Proposal — {customer_name}",
          "t_and_m_window": "Current fiscal year (FY_START to FY_END)"
        }
      },
      "trigger_phrases_snapshot": [
        "equipment health for",
        "equipment status for",
        "what's due at",
        "asset health for",
        "show me equipment for",
        "what needs replacing at",
        "capital snapshot for"
      ],
      "trigger_phrases_renewal": [
        "capital replacement plan",
        "renewal report for",
        "replacement plan for",
        "facilities budget proposal",
        "renewal presentation for",
        "capital plan for",
        "budget proposal for"
      ],
      "mode_detection": "If the user says 'snapshot', 'health', 'status', 'what's due', or 'check on' → snapshot mode. If the user says 'renewal', 'budget proposal', 'capital plan', 'presentation', or 'FY' → renewal mode. If ambiguous, ask: 'Do you want a quick equipment health snapshot, or the full renewal budget proposal?'",
      "required_entity": "customer",
      "required_fields": ["dcfg_customerid or dcfg_name"],
      "data_sources": [
        {"system": "dataverse", "entity_set": "dcfg_customers", "role": "customer record"},
        {"system": "dataverse", "entity_set": "dcfg_propertys", "role": "all active properties for customer"},
        {"system": "dataverse", "entity_set": "dcfg_appliances", "role": "equipment with install dates and replace-by status"},
        {"system": "dataverse", "entity_set": "dcfg_equipment_benchmarks", "role": "lifespan reference data with failure modes and brands"},
        {"system": "dataverse", "entity_set": "dcfg_contracts", "role": "T&M repair history"},
        {"system": "dataverse", "entity_set": "dcfg_contract_lines", "role": "line items per T&M work order"},
        {"system": "dataverse", "entity_set": "dcfg_audit_logs", "role": "incident reports and impact statements"},
        {"system": "dataverse", "entity_set": "dcfg_location_types", "role": "scope rules (Systems+Appliances vs Appliances Only)"}
      ],
      "data_sources_renewal_only": [
        {"system": "manual_or_config", "type": "staff_survey", "role": "Staff satisfaction scores and quotes — required for renewal mode, not used in snapshot"}
      ],
      "conditional_logic": [
        "Apartments scope = Appliances Only (building systems are landlord responsibility)",
        "All other location types scope = Building Systems + Appliances",
        "Assets past max life → REPLACE NOW (red)",
        "Assets past 80% threshold → BUDGET FY (amber)",
        "Assets below 80% → HEALTHY (green, not shown unless requested)",
        "Repeat T&M (2+ WOs on same asset) increases priority ranking",
        "Snapshot mode: T&M window = rolling 12 months from today",
        "Renewal mode: T&M window = current fiscal year (FY_START to FY_END)",
        "Staff survey data may be manual input — handle gracefully if not present",
        "If only 1 location type, skip location type breakdown slide",
        "Snapshot mode: if no overdue or approaching items, say so clearly — do not generate empty slides"
      ],
      "roles": ["DCFG_Operations", "DCFG_Sales", "DCFG_Admin"]
    },
    {
      "id": "tmpl-vendor-performance",
      "name": "Vendor Performance Summary",
      "description": "Summary of a vendor's contract history, certification status, team notes, and reliability assessment",
      "category": "ad-hoc",
      "output_format": "docx",
      "trigger_phrases": [
        "vendor performance summary",
        "vendor report",
        "vendor summary for"
      ],
      "required_entity": "vendor",
      "data_sources": [
        {"system": "dataverse", "query_pattern": "vendor-lookup"},
        {"system": "sharepoint", "file": "company-brain/operations/vendor-knowledge.json"},
        {"system": "upkeep", "endpoint": "/vendors/{id}/certifications"}
      ],
      "roles": ["DCFG_Operations", "DCFG_Admin"]
    },
    {
      "id": "tmpl-property-condition",
      "name": "Property Condition Report",
      "description": "Property details, tracked assets with lifespan status, recent work history, compliance documents, and site notes",
      "category": "ad-hoc",
      "output_format": "docx",
      "trigger_phrases": [
        "property condition report",
        "property report for",
        "condition report"
      ],
      "required_entity": "property",
      "data_sources": [
        {"system": "dataverse", "query_pattern": "property-lookup"},
        {"system": "dataverse", "entity_set": "dcfg_property_assets"},
        {"system": "sharepoint", "file": "company-brain/operations/property-knowledge.json"},
        {"system": "sharepoint", "file": "company-brain/operations/asset-lifespans.json"},
        {"system": "upkeep", "endpoint": "/assets?propertyId={id}"}
      ],
      "roles": ["DCFG_Operations", "DCFG_Admin"]
    },
    {
      "id": "tmpl-contract-status",
      "name": "Contract Status Report",
      "description": "All contracts for a customer or MSA with current status, line items, and audit trail",
      "category": "ad-hoc",
      "output_format": "docx",
      "trigger_phrases": [
        "contract status report",
        "contract report for",
        "contract summary"
      ],
      "required_entity": "customer",
      "data_sources": [
        {"system": "dataverse", "query_pattern": "customer-lookup"},
        {"system": "dataverse", "entity_set": "dcfg_contracts"},
        {"system": "dataverse", "entity_set": "dcfg_contract_lines"},
        {"system": "dataverse", "entity_set": "dcfg_audit_logs"}
      ],
      "roles": ["DCFG_Operations", "DCFG_Sales", "DCFG_Admin"]
    },
    {
      "id": "tmpl-cert-expiry",
      "name": "Certification Expiry Report",
      "description": "All vendor and property certifications with expiry dates, sorted by urgency",
      "category": "ad-hoc",
      "output_format": "docx",
      "trigger_phrases": [
        "certification expiry report",
        "cert report",
        "expiring certifications report"
      ],
      "required_entity": null,
      "data_sources": [
        {"system": "sharepoint", "file": "company-brain/operations/certification-status.json"},
        {"system": "dataverse", "entity_set": "dcfg_vendors"},
        {"system": "dataverse", "entity_set": "dcfg_propertys"},
        {"system": "upkeep", "endpoint": "/vendors/certifications"}
      ],
      "roles": ["DCFG_Operations", "DCFG_Admin"]
    },
    {
      "id": "tmpl-onboarding-status",
      "name": "Onboarding Status Report",
      "description": "Active onboarding cases with checklist progress, stall detection, and next actions",
      "category": "ad-hoc",
      "output_format": "docx",
      "trigger_phrases": [
        "onboarding status report",
        "onboarding report",
        "case status report"
      ],
      "required_entity": null,
      "data_sources": [
        {"system": "dataverse", "entity_set": "dcfg_onboarding_cases"},
        {"system": "dataverse", "entity_set": "dcfg_onboarding_checklists"},
        {"system": "dataverse", "entity_set": "dcfg_customers"}
      ],
      "roles": ["DCFG_Operations", "DCFG_Sales", "DCFG_Admin"]
    }
  ]
}
```

### Production vs Ad-Hoc Report Behavior

**Production reports (category = "production"):**
1. Brain reads the full spec from `report-specs/{id}.md`
2. Brain follows the spec exactly: data queries, calculated fields, layout, conditional logic, design tokens
3. No creative interpretation. The spec defines every element, color, font, position, and conditional behavior
4. If the spec defines 6 slides, generate 6 slides. If the spec says "hide progress bar when no budget", hide it
5. The spec includes example output references — match those layouts

**Ad-hoc reports (category = "ad-hoc"):**
1. Brain queries the listed data sources using the standard query patterns
2. Brain composes a clean, professional document using DCFG design tokens (navy/amber/green palette, Consolas for data values, Calibri for body text)
3. Structure follows common sense: title page, executive summary, detail tables, closing
4. The brain has latitude on layout and structure but must use the DCFG color palette and maintain professional formatting

### Document Generation Flow

```
User: "Create a vendor performance summary for ABC Cleaning"
                    │
                    ▼
    Match "vendor performance summary" → tmpl-vendor-performance
                    │
                    ▼
    Check user role against template.roles → DCFG_Operations ✓
                    │
                    ▼
    Resolve entity: query dcfg_vendors for "ABC Cleaning" → vendorId
                    │
                    ▼
    Execute data source queries (same as vendor-lookup pattern):
      1. dcfg_vendors → vendor record
      2. dcfg_contracts → contract history
      3. vendor-knowledge.json → team notes
      4. UpKeep → certifications (if connected)
                    │
                    ▼
    Assemble document content from query results
                    │
                    ▼
    Generate docx/pptx file
                    │
                    ▼
    Offer to user:
      [Download]  [Save to SharePoint]
```

### Document Output Delivery

When a document is generated, the brain responds with:

```
"I've created the Vendor Performance Summary for ABC Cleaning. 
It covers 3 active contracts, current certifications, and team 
notes including the pricing concern Alicia flagged.

[Download]  [Save to SharePoint]"
```

**Download:** Serves the file directly for download to the user's device.

**Save to SharePoint:** Writes the generated file to a designated output folder in the DCFG SharePoint document library:
```
PUT /drives/{driveId}/root:/generated-reports/{template-name}/{entity-name}-{date}.{ext}:/content
```

Example path: `generated-reports/vendor-performance/abc-cleaning-2026-03-15.docx`

### Presentation-Specific Requirements (pptx output)

When generating PowerPoint presentations:
- Use a DCFG-branded slide master if one exists in SharePoint (path to be provided at deployment)
- If no master exists, use a clean professional layout with DCFG colors: navy (#1B2A4A) headers, white backgrounds, amber (#C4A24C) accents
- Data tables in slides must be actual table objects, not images of tables
- Chart slides must use embedded chart objects when possible
- Speaker notes on each slide summarizing the key talking points from the data
- First slide: title + date + entity name + "Generated by Decades Brain"
- Last slide: "Data sources: [list of systems queried]" + generation timestamp

### Component Addition for Document Generation

Add to the component structure:

```
DecadesBrain/
  ...existing components...
  DecadesBrainExplorer.jsx    # Capability explorer panel
  DecadesBrainWelcome.jsx     # First-use welcome card
  DecadesBrainDocAction.jsx   # Download/Save to SharePoint action buttons
  hooks/
    ...existing hooks...
    useDocumentGeneration.js  # Template matching, data assembly, file generation
    useTemplateRegistry.js    # Loads and caches document-templates.json
    useFirstUse.js            # Tracks whether user has seen the welcome card
  utils/
    ...existing utils...
    templateMatcher.js        # Matches user input to template trigger phrases
    docxBuilder.js            # Assembles docx from structured data
    pptxBuilder.js            # Assembles pptx from structured data
```

---

## Deployment

This component deploys as part of `dcfg-shell`. After integration:

```bash
cd C:\dcfg\spa\dcfg-shell
npm run build
pac pages upload-code-site --rootPath . --compiledPath dist --siteId 22947376-be10-4bda-a90f-32b855c43045
```

Clear portal cache after deployment:
```
https://dcfg.powerappsportals.com/_services/about?clearCache=true
```

### Configuration Required at Deployment
1. SharePoint drive ID for the company-brain document library
2. UpKeep API base URL and key (when available)
3. System email account mailbox list (when available)
4. AI model API key and endpoint for the conversational layer (Claude API or similar)
5. Path to DCFG-branded PowerPoint slide master in SharePoint (if exists)
6. Deploy `company-brain/_config/document-templates.json` with initial template registry
7. Deploy `company-brain/_config/report-specs/RPT-WO-001.md` (Single Work Order Budget Report)
8. Deploy `company-brain/_config/report-specs/RPT-PGM-001.md` (Program Budget Performance Report)
9. Deploy `company-brain/_config/report-specs/RPT-CAP-001.md` (Capital Replacement Plan / Renewal Report)
10. Create `generated-reports/` folder in SharePoint document library for saved document output
