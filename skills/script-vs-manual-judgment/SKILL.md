---
name: script-vs-manual-judgment
description: Apply this skill whenever Claude is about to write, run, or debug a script to accomplish a task in a GUI environment (Power Apps, Power Pages, Dataverse admin portal, Azure portal, SharePoint, Excel, browser-based tools, etc.). ALWAYS use this skill before proposing a script for any task that might be faster to do manually. Trigger on phrases like "script to...", "automate this", "write a PowerShell to...", "can you make a script that...", or any time a script is proposed as the solution to a small configuration or data task. The skill evaluates whether scripting is worth the overhead given the effort to manually accomplish the same result.
---

# Script vs. Manual Judgment

## The Core Problem

Scripts are debugged iteratively. Every iteration costs: write → run → read error → fix → repeat. When the manual path is short, this loop costs more than just doing the thing.

This skill prevents over-engineering by applying a simple cost model before recommending a scripted approach.

---

## The Decision Rule

Evaluate the **manual path** first. Count screens and keystrokes honestly.

| Manual Effort | Verdict |
|---|---|
| **1 screen, ≤ 20 keystrokes/clicks** | Do it manually. No script. |
| **2 screens, ≤ 10 keystrokes/clicks each** | Do it manually. No script. |
| **Repetitive across 3+ records or rows** | Script is justified. |
| **Requires logic, conditionals, or lookups** | Script is justified. |
| **Needs to run on a schedule or trigger** | Script is justified. |
| **Will need to run again in the future** | Script is justified. |

**Default to manual** when in doubt. The debug loop overhead is real.

---

## How to Apply This

When a script is proposed (by the user or by Claude), Claude should:

1. **Sketch the manual path** — what screens, what clicks, what fields.
2. **Apply the decision rule** above.
3. **If manual wins**, say so clearly and walk the user through the manual steps instead.
4. **If script wins**, proceed — but acknowledge why (volume, recurrence, complexity).

---

## Examples

### ✅ Do it manually
> "Write a PowerShell to add the 'Inactive' option to the Status choice column in Dataverse."

Manual path: Dataverse admin → Table → Column → Edit choices → Add option → Save. That's 1 screen, ~6 clicks. **Do it manually.**

---

> "Script to grant a web role to one user in Power Pages."

Manual path: Power Pages admin → Security → Contacts → find user → assign role. That's 2 screens, ~8 clicks. **Do it manually.**

---

### ✅ Script is justified
> "Add the 'Inactive' option to 14 different choice columns across 5 tables."

Volume makes manual error-prone and slow. **Script it.**

---

> "Grant the same web role to 40 contacts imported from a CSV."

Repetition across many records. **Script it.**

---

> "Write a script to create all Dataverse tables from the ERD."

Complex, multi-step, one-time infrastructure build. **Script it.**

---

## When Already Mid-Debug on a Script

If the user is already debugging a script that covers a small task, Claude should:

1. **Note the manual alternative** — briefly and without lecturing.
2. **Still help debug the script** — the user may have already invested time, or may have a reason.
3. **Only recommend abandoning the script** if the debug loop has clearly cost more than the manual path already would have.

Tone: practical, not preachy. One sentence is enough: *"This is also quick to do manually via [path] if the script keeps fighting you."*

---

## DCFG-Specific Notes

Common DCFG tasks that are almost always faster manually:

- Adding/editing a single choice option in Dataverse
- Assigning a web role to one user in Power Pages
- Updating a single site setting
- Enabling/disabling a table permission for one web role
- Adding one column to a Dataverse table
- Toggling a feature flag in the Power Platform admin center

Common DCFG tasks where scripting is worth it:

- Creating multiple tables or columns from the ERD schema spec
- Provisioning web roles and table permissions for a full solution deployment
- Bulk-updating records (10+) from a spreadsheet or spec
- Any task that needs to be repeatable across environments (dev → test → prod)
