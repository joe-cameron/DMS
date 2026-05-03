---
name: auto-research-testing
description: "Karpathy's Auto-Research pattern adapted for DCFG. Run experiments, learn from failures, converge on solutions. Use when debugging failures, investigating root causes, or improving reliability of any automated task. The system runs many attempts, logs each outcome, and builds a playbook of what works."
---

# Auto-Research Testing (Karpathy Pattern)

## Core Principle
Run many experiments. Most fail. That's how you find what works. Each failure teaches something. After N cycles, the system converges on reliable patterns.

## The Loop
```
1. DEFINE hypothesis ("I think the issue is X")
2. DESIGN experiment (non-destructive test)
3. EXECUTE via Agent or Cowork
4. OBSERVE result (success/failure + details)
5. ANALYZE why (root cause)
6. LOG to Brain (what was tried, what happened, what was learned)
7. REFINE hypothesis based on results
8. REPEAT until confidence >= 95% or approaches exhausted
```

## Experiment Rules
- **Non-destructive first** — always try safe approaches before risky ones
- **One variable at a time** — change only one thing per experiment
- **Log everything** — even "obvious" failures teach patterns
- **Timeout limits** — if an approach takes >5 minutes, stop and try another
- **Confidence scoring** — track success rate across attempts

## Failure Classification
```
Attempt failed → Why?
  Timing issue? → Adjust wait time, retry
  Permission issue? → Check table permissions, escalate if needed
  Missing data? → Verify prerequisites exist
  API limitation? → Switch to GUI approach
  Unknown? → Log details, try completely different approach
```

## When to Use
- Flow definition PATCH fails with cryptic error
- Dataverse query returns unexpected 400
- PAC CLI command fails inconsistently
- UI element not found by Cowork
- Any task that fails without clear reason

## Convergence Metrics
- **95% target** — 1 failure per 20 attempts is acceptable
- **Track per task** — each unique task type has its own success rate
- **Declare "learned" at 95%** — store the winning approach in Brain
- **Re-enter learning mode if task breaks** — UI changes, API changes

## Brain Storage Format
```json
{
  "task_id": "update_flow_definition",
  "total_attempts": 47,
  "success_count": 45,
  "success_rate": 0.957,
  "winning_approach": "Deactivate → PATCH clientdata (actions only) → Reactivate",
  "known_failure_modes": [
    {"cause": "ActiveUnpublished state", "fix": "User must Save/Discard in designer first"},
    {"cause": "Missing authentication property", "fix": "Strip auth for Test env, keep for Stage"}
  ],
  "environment_differences": {
    "test": "Uses connectionReferenceName, no authentication on actions",
    "stage": "Uses connectionName, requires authentication on actions"
  }
}
```

## Integration with Supervisor
Claude's /loop uses Auto-Research when a task fails:
1. First attempt fails → normal retry with adjustment
2. Second attempt fails → enter Auto-Research mode
3. Run up to 10 experiments with different approaches
4. If 95% confidence reached → task learned, exit research mode
5. If all approaches fail → escalate to operator with full experiment log
