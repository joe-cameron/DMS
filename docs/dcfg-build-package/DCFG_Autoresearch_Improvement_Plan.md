# DCFG Skills — Autoresearch Improvement Plan

**Purpose:** Apply the Karpathy autoresearch pattern to four DCFG custom skills, systematically improving their reliability and accuracy through automated generate → evaluate → mutate loops.

**Pattern recap:** Generate output using the skill → Evaluate against binary criteria → Score → Keep winner or revert → Mutate the SKILL.md instructions → Repeat.

---

## How This Plan Works

Each skill below has:

1. **Test prompts** — Realistic requests that exercise the skill's core capabilities. These replace the "topics" array from the diagram autoresearch. Each cycle picks a random prompt from this list.
2. **Binary eval criteria** — Yes/no questions an evaluator agent answers about each output. These are the skill's "test suite." Every criterion is designed to catch a specific, observed failure mode.
3. **Scoring** — (batch size × criteria count) = max score per cycle. Default: 5 outputs × criteria count.
4. **Mutation focus** — What the mutator should reinforce when a criterion fails repeatedly.

The evaluator model (Claude Sonnet) reads the generated output and answers each criterion. The mutator model reads the failure analysis and rewrites the SKILL.md to close the gaps.

---

---

## SKILL 1: power-pages-content-ops

### What it produces
PowerShell scripts for portal metadata and React/JSX components for the DCFG Power Pages SPA.

### Test Prompts (rotate per cycle)

```
1. "Write a PowerShell script to create a site setting called dcfg_enable_budget_panel with value true"
2. "Write a React component for the Contract Detail page (Page 06) that displays contract status with a color-coded banner and shows the Document Panel"
3. "Write a portalApi.js OData query to fetch all properties for a given MSA, including location type expand"
4. "Write PowerShell to create a table permission for dcfg_contracts with Read scope=Global and link it to the DCFG_Manager web role"
5. "Write a React hook called useContractLines that fetches contract lines for a given contract ID with cost code expansion"
6. "Write the JSX for the Send Queue table (Page 07) showing pending items with Mark Sent functionality"
7. "Write PowerShell to create a web role called DCFG_Viewer and associate it with the DCFG Power Pages site"
8. "Write a React component for the MSA Detail page (Page 05) budget panel that displays budget_total and budget_committed as read-only"
9. "Write an OData PATCH call to update a contract's status to Sent (100000002) including CSRF token and audit log creation"
10. "Write PowerShell to bulk-create table permissions for dcfg_audit_logs (Create only), dcfg_send_queues (Read+Create+Write), and dcfg_customers (Read+Write)"
```

### Eval Criteria (8 binary checks per output)

| # | Criterion | What it catches |
|---|-----------|-----------------|
| 1 | **CONNECT_TRAILING_SLASH** — Does every `Connect` call URL end with `/`? | PS-01 violation: DNS failure from missing slash |
| 2 | **NO_INVOKE_RESILIENT_URI** — Is `Invoke-ResilientRestMethod -Uri` absent from the output? | PS-02 violation: parameter that doesn't exist |
| 3 | **ENTITY_SET_PROPERTYS** — If `dcfg_property` entity set is referenced, is it spelled `dcfg_propertys` (not `dcfg_properties`)? | JS-01 violation: 404 on every location query |
| 4 | **CSRF_TOKEN_PRESENT** — Does every Web API fetch/PATCH/POST include `__RequestVerificationToken`? | JS-03 violation: 403 on every API call |
| 5 | **ODATA_BIND_SYNTAX** — Are all lookup field writes using `@odata.bind` syntax (not plain GUIDs)? | JS-04 violation: relationship not created |
| 6 | **NO_BUDGET_COMMITTED_WRITE** — Is `dcfg_budget_committed` absent from any PATCH/POST body? | JS-07 violation: data conflict with flow_commit |
| 7 | **AUDIT_LOG_CREATE_ONLY** — If audit log operations exist, are they exclusively POST/Create (no PATCH/DELETE)? | JS-09 violation: permission error |
| 8 | **CORRECT_COLUMN_NAMES** — Are column names from the corrected list used (e.g., `dcfg_contact_person` not `dcfg_owner_contact`)? | UL-004 violation: silent Dataverse 400 |

### Scoring

- Batch size: 5 outputs per cycle
- Max score: 5 × 8 = **40 per cycle**
- Target: 38+ sustained across 5 consecutive cycles

### Mutation Focus

When a criterion fails repeatedly, the mutator should:
- **CONNECT_TRAILING_SLASH failures:** Add more prominent warning text, add a second example showing the failure mode
- **ENTITY_SET_PROPERTYS failures:** Bold the gotcha, add it to multiple sections (not just the table)
- **CSRF failures:** Add the token to every code example, not just the reference section
- **COLUMN_NAME failures:** Expand the correction table, add inline comments in code examples

---

---

## SKILL 2: dataverse-schema-ops

### What it produces
PowerShell 7+ scripts using Microsoft PS Helper functions to create/modify Dataverse schema.

### Test Prompts (rotate per cycle)

```
1. "Create a new Dataverse table called dcfg_service_area with columns: dcfg_name (string, required), dcfg_description (string), dcfg_is_active (boolean, default true)"
2. "Add a lookup column from dcfg_contract to dcfg_program with cascade delete=RemoveLink"
3. "Create a local Choice column on dcfg_vendor called dcfg_vendor_type with options: Subcontractor, Supplier, Consultant"
4. "Write a script to add 5 columns to dcfg_property: dcfg_square_footage (whole number), dcfg_county (string), dcfg_division (string), dcfg_year_built (whole number), dcfg_parking_spaces (whole number)"
5. "Create a many-to-many junction table dcfg_property_service linking dcfg_property and dcfg_vendor with additional columns dcfg_start_date and dcfg_end_date"
6. "Write a script to check if dcfg_onboarding_checklist exists, and if not, create it with columns dcfg_name, dcfg_step_number (whole number), dcfg_is_required (boolean)"
7. "Add a currency column dcfg_monthly_rate to dcfg_msa_rate"
8. "Create a lookup from dcfg_location_document to dcfg_property using the correct PK attribute name"
```

### Eval Criteria (7 binary checks per output)

| # | Criterion | What it catches |
|---|-----------|-----------------|
| 1 | **CONNECT_TRAILING_SLASH** — Does the `Connect` URL end with `/`? | DNS failure |
| 2 | **INVOKE_DATAVERSE_COMMANDS_WRAP** — Are all Dataverse operations inside `Invoke-DataverseCommands { }`? | Missing error handling and 429 retry |
| 3 | **BUILD_LABEL_PRESENT** — Is the `Build-Label` helper function defined? | Script fails on first metadata call |
| 4 | **EXISTENCE_CHECK_BULK** — Do existence checks use the bulk GET + iterate pattern (not `$filter` on Attributes)? | False negatives causing duplicate-create errors |
| 5 | **PK_ATTRIBUTE_NO_UNDERSCORE** — Is `ReferencedAttribute` using `{tablename}id` pattern (no underscore before "id")? | Silent relationship creation failure |
| 6 | **SOLUTION_NAME_PASSED** — Is `-solutionUniqueName 'DCFGContractingSuite'` passed to every New-Table/New-Column/New-Relationship? | Components created outside solution |
| 7 | **UNBLOCK_AND_PWSH** — Does the run command include both `Unblock-File` and `pwsh` (not `powershell.exe`)? | Script blocked by policy or PS5.1 parse errors |

### Scoring

- Batch size: 5 outputs per cycle
- Max score: 5 × 7 = **35 per cycle**
- Target: 33+ sustained across 5 consecutive cycles

### Mutation Focus

- **PK_ATTRIBUTE failures:** This is the subtlest gotcha — add more examples showing correct vs incorrect PK naming for multiple tables
- **EXISTENCE_CHECK failures:** Add a "NEVER DO THIS" block with the `$filter` approach explicitly banned
- **SOLUTION_NAME failures:** Add it to the script skeleton so it's impossible to miss

---

---

## SKILL 3: dcfg-ux-psychology

### What it produces
HTML mockups, layout critiques, component designs, and screen specifications for DCFG screens.

### Test Prompts (rotate per cycle)

```
1. "Design the Dashboard (Page 01) KPI section for the Sales sub-app"
2. "Critique this layout: a contract detail page with 15 fields displayed in a single column with no section breaks"
3. "Design the onboarding checklist screen showing steps 1-16 with locked/unlocked states"
4. "Create the MSA Detail budget panel showing budget_total and budget_committed"
5. "Design a table component for the Customer List (Page 02) with appropriate default columns"
6. "Review this mockup: a left nav with 8 ungrouped items, all at the same visual weight"
7. "Design toast notifications for: successful document generation, failed save, and async flow_docgen call"
8. "Create the Type-Based pricing panel for the New MSA Proposal wizard"
```

### Eval Criteria (6 binary checks per output)

| # | Criterion | What it catches |
|---|-----------|-----------------|
| 1 | **MILLERS_LAW_COMPLIANCE** — Are visible items per group/section ≤ 7? (KPIs per row ≤ 4, form fields per section ≤ 4, table columns ≤ 7) | Cognitive overload |
| 2 | **PROGRESSIVE_DISCLOSURE** — Are conditional/optional elements hidden by default (not disabled or grayed)? | Premature complexity exposure |
| 3 | **ROLE_RESTRICTED_REMOVED** — Are admin-only actions completely absent from non-admin views (not just disabled)? | JS-06 pattern violation |
| 4 | **CORRECT_DESIGN_TOKENS** — Are CSS values using token variables (--navy, --amber, etc.) not hardcoded hex? | Design system drift |
| 5 | **BUDGET_COMMITTED_READONLY** — If budget_committed appears, is it displayed as read-only (no input control)? | flow_commit ownership violation |
| 6 | **STATUS_BADGE_NOT_TEXT** — Are status values rendered as colored badges, not plain text? | Von Restorff violation — no visual distinction |

### Scoring

- Batch size: 5 outputs per cycle
- Max score: 5 × 6 = **30 per cycle**
- Target: 27+ sustained across 5 consecutive cycles

### Mutation Focus

- **MILLERS_LAW failures:** Add concrete number caps directly into section headers (not just body text)
- **PROGRESSIVE_DISCLOSURE failures:** Add more WRONG/CORRECT pairs showing hidden vs disabled
- **DESIGN_TOKEN failures:** List tokens at the top of the skill, not just in Part D at the bottom

---

---

## SKILL 4: power-automate-flow-builder

### What it produces
Structured JSON output: FlowInventory[], DesignerSteps[], ValidationRules[], ArtifactsPlan[].

### Test Prompts (rotate per cycle)

```
1. "Process this spec for flow_docgen: HTTP trigger, List rows from dcfg_contracts, Get row by ID for the MSA, Compose the merge payload, Create file in SharePoint, Update contract status, Create audit log row, Response 200"
2. "Process this spec for flow_commit: Dataverse trigger on dcfg_contracts status=SignedReceived, Get MSA row, Get Program row, Update program budget_committed, Create audit log"
3. "Process a spec with a Condition action that branches on contract status equals Void, with true branch doing a Terminate Failed and false branch continuing to next action"
4. "Process a spec with Apply_to_each over List rows results, containing a nested Condition and variable append"
5. "Validate a spec where action Run_Step_3 has runs_after referencing nonexistent action Run_Step_2B"
6. "Process a spec containing a child flow reference to flow_send_email within a parent flow"
```

### Eval Criteria (7 binary checks per output)

| # | Criterion | What it catches |
|---|-----------|-----------------|
| 1 | **VALID_JSON_OUTPUT** — Is the entire output valid, parseable JSON matching the envelope schema? | Broken output — unusable downstream |
| 2 | **ALL_FOUR_SECTIONS_PRESENT** — Does the output contain FlowInventory[], DesignerSteps[], ValidationRules[], and ArtifactsPlan[]? | Incomplete output |
| 3 | **NO_PROSE_IN_OUTPUT** — Is the output free of narrative paragraphs (only JSON + max 1 sentence before/after)? | B.6 Rule 3 violation |
| 4 | **EXPRESSION_VERBATIM** — Are all expressions from the spec reproduced character-for-character? | B.6 Rule 6 violation — reformatted expressions |
| 5 | **IMMUTABLE_TABLE_HONORED** — Is there no UpdateRow action targeting dcfg_audit_logs? | Critical safety violation |
| 6 | **RUNS_AFTER_INTEGRITY** — Does every runs_after reference point to an action that exists in the same flow? | Broken dependency chain |
| 7 | **MANDATORY_VALIDATION_CHECKS** — Are all 13 mandatory validation categories present in ValidationRules[]? | Incomplete audit trail |

### Scoring

- Batch size: 5 outputs per cycle
- Max score: 5 × 7 = **35 per cycle**
- Target: 33+ sustained across 5 consecutive cycles

### Mutation Focus

- **VALID_JSON failures:** Add explicit "emit only JSON" instruction at the very top of Part B
- **NO_PROSE failures:** Add negative examples showing what NOT to do (paragraphs of explanation)
- **EXPRESSION_VERBATIM failures:** Triple-emphasize the passthrough rule, add test cases inline
- **MANDATORY_CHECKS failures:** List all 13 check categories in a checklist format the model can scan

---

---

## Implementation Approach

### Phase 1: Adapt the autoresearch loop

The installed `autoresearch.py` generates images and evaluates them visually. For these four skills, the adaptation is:

- **Generator:** Instead of calling Gemini image gen, call Claude API with the skill's SKILL.md as system prompt and a random test prompt as the user message. The output is text (code, JSON, HTML).
- **Evaluator:** Instead of Claude vision on an image, Claude Sonnet reads the generated text output and answers each binary criterion. Same JSON response format: `{"criterion_1": true, "criterion_2": false, "failures": ["..."]}`.
- **Mutator:** Same pattern — reads failure analysis, rewrites the SKILL.md to close gaps. The SKILL.md replaces `prompt.txt` as the thing being optimized.

### Phase 2: Run schedule

- **Cycle time:** 3–5 minutes per skill (text generation is faster than image gen)
- **Batch size:** 5 outputs per cycle (sufficient for distribution signal, cheaper than 10)
- **Recommended initial run:** 20 cycles per skill (~60-100 minutes each)
- **Cost estimate:** ~$0.15-0.25 per cycle (5 generations + 5 evals + 1 mutation) → ~$3-5 per 20-cycle run per skill → ~$12-20 total for all four skills

### Phase 3: Harvest

After each run:
- The optimized SKILL.md replaces the current version
- The JSONL log preserves every mutation attempt and score
- The mutation log becomes a "lessons learned" document for future model upgrades
- Re-run periodically as you add new features or discover new failure modes

---

## File Structure (per skill)

```
autoresearch-{skill-name}/
  SKILL.md              # Copy of current skill (this is what gets mutated)
  autoresearch.py       # Adapted loop (text gen + text eval)
  dashboard.py          # Same dashboard, reads results.jsonl
  eval_criteria.json    # The binary criteria for this skill
  test_prompts.json     # The prompt rotation list
  data/
    state.json
    results.jsonl
    best_skill.md       # Best-scoring version of SKILL.md
    outputs/
      run_001/          # Raw outputs per cycle
      run_002/
```
