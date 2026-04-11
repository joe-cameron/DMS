# Postmortem: Harness Failures — 2026-03-26

## Incident Summary

Two sessions on 2026-03-26 exposed systemic failures in how the five-agent harness operates. The harness did not function as designed — agents acted unilaterally, the Planner did not challenge the Generator, the Troubleshooter looped without diagnosing, and a destructive action destroyed hours of manual work.

## Incident 1: DocGen Flow Deletion

**What happened:** The Generator was told to edit the DocGen v2 flow. Instead of investigating the current state, it deleted and recreated the flow. This destroyed manually-configured Word Online "Populate Template" actions — field mappings, file selections, and dynamicFileSchema configurations that can ONLY be set up in the Power Automate designer.

**Root cause:** No planning gate fired. The Planner did not run. The Generator received a task and acted immediately without:
- Reading the current flow definition
- Identifying what would be lost
- Presenting alternatives (PATCH specific actions, rename, disable)
- Getting explicit approval for a destructive action

**Harness failure:** The Planner → Generator → Evaluator chain collapsed into just the Generator acting alone. No challenge, no review, no gate.

## Incident 2: UpKeep Flow Troubleshooting Spiral

**What happened:** Activating GetUnifiedWorkQueue took 15+ script iterations across multiple failure modes:

1. **Variable name mismatch** — flow had been manually rebuilt with different variable names (`multi_email` not `upkeep_email`). The Troubleshooter assumed the deploy script structure matched the live flow without reading it first.

2. **Email case sensitivity** — `Service@decades-cg.com` (capital S) returned 400 from UpKeep. Diagnosed only after 4 test variations. Should have been caught by reading the prod flow's working pattern earlier.

3. **Schema validation failures** — UpKeep's `location` field is sometimes a string, sometimes an object. The flow's Select expressions assumed object. Diagnosed after reading the error message, but only after multiple failed runs.

4. **Stuck run accumulation** — Each failed test invocation created a new running instance. 9+ runs stacked up, couldn't be cancelled, caused rate limiting on UpKeep's auth API, and returned stale 502s on new invocations.

5. **HTTP trigger timeout** — Even after all actions succeeded, the flow exceeded the HTTP response timeout due to dual-account data volume. This was the wrong architecture from the start.

6. **Webhook receiver flow without connector** — Built and deployed a flow using `@parameters('$authentication')` for Dataverse HTTP calls without a connection reference. The flow couldn't auth to Dataverse and wouldn't generate a trigger URL. Fundamental architecture mistake.

**Root cause:** The Troubleshooter did not follow its own decision tree. It should have:
- Classified the failure BEFORE attempting fixes
- Read the live flow definition BEFORE assuming its structure
- Tracked what it tried to prevent loops
- Escalated after 3 failed approaches

Instead, it kept writing new fix scripts and running them, creating a cascade of side effects.

## Systemic Failures in the Harness

### 1. Planner Never Challenged the Generator

The harness says: "The planner must challenge the builder." In both incidents, the Planner either didn't run or rubber-stamped the Generator's approach. The challenge questions never fired:
- "What gets destroyed if we do this?"
- "Is there a non-destructive alternative?"
- "Can this be undone?"
- "Does the user need to approve this?"

**Gap in the skill:** The harness defines these questions but has no enforcement mechanism. They're guidelines, not gates. When the session is moving fast, they get skipped.

### 2. No Investigation-Before-Action Gate

The Generator and Troubleshooter both acted before understanding current state. The flow had been manually rebuilt — different variables, different structure, different account configuration. Every assumption from the deploy script was wrong.

**Gap in the skill:** The harness says "agents research within their domain" but doesn't require a mandatory read-current-state step before any modification.

### 3. Troubleshooter Looped Instead of Diagnosing

The Troubleshooter's decision tree (Transient → Recoverable → Hard Roadblock) was never followed. Instead:
- Write a fix script → run it → fail → write another fix script → run it → fail
- No classification of the failure type
- No tracking of approaches tried
- No escalation after 3+ failures

The Troubleshooter became a "try things until something works" agent instead of a diagnostic specialist.

### 4. No Evaluator Checkpoint

The Evaluator never ran during the troubleshooting session. After each fix attempt, there was no quality gate asking "did this actually work?" or "what state are we in now?" The Generator and Troubleshooter self-evaluated, which the harness explicitly warns against.

### 5. Same-Session Role Collapse

When all agents run in the same session (Planner + Generator + Troubleshooter), role boundaries dissolve. The "explicit hat-switch" the harness requires didn't happen. The session became one continuous stream of build-try-fail-build-try-fail without the structured handoffs the harness design assumes.

### 6. Side Effect Accumulation

Each failed flow invocation created a new running instance. The Troubleshooter didn't account for this — it kept invoking the flow without checking if previous runs had completed. This caused:
- 9+ simultaneous runs hitting UpKeep
- Rate limiting / account lockout on Bancroft
- Stale 502 responses from queued runs masking whether fixes worked

**Gap in the skill:** No concept of "check the environment before each action" or "clean up side effects from the last attempt."

## Recommendations

### R1: Mandatory Pre-Action Read (All Agents)

Before ANY modification to a Power Platform resource, the acting agent MUST:
1. Read the current state of the target resource
2. Present what exists to the operator
3. Identify what would change and what would be lost
4. Get approval if destructive

This is not a guideline — it's a gate. Build it into Step P0 or as a new Step P-1 that runs before everything.

### R2: Troubleshooter Requires a Diagnosis Log

The Troubleshooter must maintain a running log:

```
Attempt 1: [what I tried] → [what happened] → [classification: transient/recoverable/roadblock]
Attempt 2: ...
Attempt 3: → ESCALATE if no resolution
```

If the log doesn't exist, the Troubleshooter can't act. If it reaches 3 entries without resolution, it MUST escalate.

### R3: Side Effect Awareness

Any agent that invokes an external system must check for side effects from previous invocations before trying again. For flows: check run history. For API calls: check for rate limiting. For Dataverse: check for duplicate records.

### R4: Role Enforcement in Same-Session Mode

When agents run in the same session, require explicit markers:

```
[PLANNER] Classifying...
[GENERATOR] Building...
[TROUBLESHOOTER] Diagnosing...
[EVALUATOR] Checking...
```

This forces the hat-switch and prevents role collapse.

### R5: Destructive Action Blocklist

Maintain a list of actions that ALWAYS require the planning gate, regardless of context:
- Delete a flow
- Delete a Dataverse record
- Overwrite a flow definition
- Delete a connection reference
- Delete a SharePoint file
- Recreate any resource that has manual configuration

### R6: Architecture Validation Before Build

The Planner should validate that the proposed architecture can actually work before the Generator starts building. In this session:
- The HTTP trigger flow was always going to timeout at this data volume
- The webhook receiver flow couldn't work without a Dataverse connector
- Both could have been caught by the Planner asking "will this work within platform constraints?"

### R7: The Poller-First Principle

For any external data integration, start with the simplest working pattern (scheduled poller) and add complexity (webhooks, real-time) only after the simple version works. Don't build the complex version first.
