# Billing & Master Scheduling Engine — Design Spec

**Date:** 2026-04-05
**Author:** Joseph Cameron / Claude
**Status:** Draft — Pending Review
**Depends on:** Project module (programs, projects, RFPs, bid comp)
**Stack:** Dataverse tables, Power Automate validation flows, React SPA screens

---

## 1. What This System Does

Manages payment schedules for awarded projects, enforces no-overbill constraints, and provides a cross-program visual scheduler for capacity planning and utilization optimization.

**Three hard constraints:**
1. Payment rates are **fixed at award** — never recalculated
2. System **cannot overbill** — sum(invoiced) must never exceed awarded amount
3. Capacity view shows **all active work** across all programs simultaneously

---

## 2. Payment Schedule Model

When a project is awarded, the system generates a payment schedule based on the billing pattern.

### 2.1 Billing Patterns (from dcfg_project.dcfg_billing_pattern)

| Pattern | How it works | Schedule generation |
|---------|-------------|---------------------|
| Per Unit | Fixed rate × completed units | One row per billing period, qty filled as work completes |
| Monthly Fixed | Fixed amount per month | N rows (one per month for contract duration) |
| Milestone | Fixed amount per milestone | One row per defined milestone |
| Hybrid | Monthly base + milestone bonuses | Combined monthly + milestone rows |

### 2.2 Payment Schedule Table: `dcfg_payment_schedule`

| Column | Type | Notes |
|--------|------|-------|
| dcfg_payment_schedule_id | PK | |
| dcfg_project_id | FK → dcfg_project | Parent project |
| dcfg_program_id | FK → dcfg_program | Denormalized for rollup queries |
| dcfg_sequence | Integer | Order (1, 2, 3…) |
| dcfg_period_label | String(100) | "Month 1", "Milestone: Rough-in Complete", "Unit Batch #3" |
| dcfg_scheduled_date | DateTime | When this payment is expected |
| dcfg_scheduled_amount | Money | Fixed amount for this period |
| dcfg_invoiced_amount | Money | What has been invoiced (≤ scheduled) |
| dcfg_paid_amount | Money | What has been received |
| dcfg_invoice_number | String(50) | Reference to actual invoice |
| dcfg_invoice_date | DateTime | When invoiced |
| dcfg_status | Choice | Scheduled=1, Invoiced=2, Paid=3, Skipped=4 |
| dcfg_notes | Memo | |
| dcfg_active_flag | Boolean | Soft delete |

### 2.3 No-Overbill Rule

```
INVARIANT: SUM(dcfg_invoiced_amount) WHERE dcfg_project_id = X
           ≤ dcfg_project.dcfg_awarded_cost

Enforced at:
  1. SPA — disable "Invoice" button when remaining = 0
  2. Flow — validate before creating invoice record
  3. Dataverse plugin (future) — reject writes that violate
```

The SPA shows remaining billable = awarded_cost - sum(invoiced) prominently on every project detail and program rollup.

---

## 3. Cadence Rules

| Rule | Meaning | Enforcement |
|------|---------|-------------|
| No early billing | Cannot invoice before scheduled_date | SPA greys out future periods |
| No double billing | Cannot invoice same period twice | Status must be "Scheduled" to invoice |
| Sequential billing | Per-unit and monthly must go in order | Cannot skip a period (must mark "Skipped" explicitly) |
| Milestone billing | Milestone periods unlock on completion evidence | Requires dcfg_pctcomplete threshold or manual approval |

---

## 4. Master Scheduling Service

### 4.1 What it shows

A visual calendar/Gantt that aggregates ALL active projects across ALL programs:

```
                    Jan    Feb    Mar    Apr    May    Jun
Program A ($340K)
  ├─ Bath Rehab     ████████████
  ├─ HVAC Replace          ████████████
  └─ Roof Repair                  ████████
Program B ($180K)
  ├─ Paint Interior  ████
  └─ Water Heater         ██
                    ─────────────────────────────────────
Capacity:           ██████ ████████ ████████████ ████ ██
Trades needed:      3      4        5            3    1
```

### 4.2 Data sources

- Project start/end dates (dcfg_startdate, dcfg_enddate)
- Project trades (dcfg_trades — multi-value)
- Project status (only show active: Draft through In Progress)
- Program grouping (dcfg_portfolioid)
- Payment schedule dates (cash flow overlay)

### 4.3 Capacity metrics

| Metric | Calculation |
|--------|-------------|
| Concurrent projects | Count of projects active in each week |
| Trade demand | Count of distinct trades needed per week |
| Cash flow | Sum of scheduled_amount per week |
| Utilization | Active projects / max historical concurrent (configurable) |

### 4.4 SPA Component

**Route:** `/scheduler` (new nav item under PROJECTS)

**Interaction model:**
- Horizontal scroll timeline (weeks or months)
- Programs as collapsible row groups
- Projects as colored bars (color = status)
- Hover shows: project name, trades, cost, % complete
- Click navigates to project detail
- Bottom row: aggregated capacity heatmap
- Toggle: show/hide cash flow overlay (green = income periods, red = gaps)

---

## 5. Program Rollup Views (enhanced ProgramDetail)

### 5.1 Budget Waterfall Tab

```
Total Budget:     $340,000  ████████████████████████████████
Estimated:        $298,500  ██████████████████████████████
Awarded:          $245,000  ████████████████████████
Invoiced:         $112,000  ████████████████
Paid:             $98,000   █████████████
Remaining:        $133,000  ████████████████
```

Each bar is clickable → drills to project list filtered by that status.

### 5.2 Trade Allocation Tab

| Trade | Projects | Estimated | Awarded | % of Budget |
|-------|----------|-----------|---------|-------------|
| Plumbing | 3 | $67,000 | $52,000 | 21% |
| HVAC | 2 | $89,000 | $78,000 | 32% |
| Roofing | 1 | $32,000 | $32,000 | 13% |
| … | | | | |

### 5.3 Payment Schedule Tab

Timeline showing all payment periods across all projects in the program, color-coded by status (grey=scheduled, blue=invoiced, green=paid, red=overdue).

### 5.4 Variance Analysis Tab

| Project | Estimated | Awarded | Δ | Actual | Δ | Status |
|---------|-----------|---------|---|--------|---|--------|
| Bath Rehab | $18,500 | $17,200 | -7% | $16,800 | -2% | ✓ |
| HVAC | $45,000 | $48,500 | +8% | — | — | ⚠ Over |

---

## 6. Build Order

1. **dcfg_payment_schedule table** — schema + permissions + site settings
2. **Payment schedule generation** — flow or script that creates schedule rows when project status → Awarded
3. **ProjectDetail billing tab** — shows payment schedule, invoice buttons, remaining billable
4. **ProgramDetail enhancement** — budget waterfall + trade allocation + variance tabs
5. **Scheduler screen** — cross-program Gantt/timeline
6. **Capacity heatmap** — aggregated bottom bar on scheduler
7. **Cash flow overlay** — payment schedule dates on timeline

---

## 7. Schema Dependencies

| New Table | FK To | Purpose |
|-----------|-------|---------|
| dcfg_payment_schedule | dcfg_project | Payment periods per project |
| dcfg_payment_schedule | dcfg_program | Denormalized for rollup |

| Existing Table | New Column | Purpose |
|----------------|-----------|---------|
| dcfg_project | dcfg_total_invoiced | Denormalized sum for fast display |
| dcfg_project | dcfg_total_paid | Denormalized sum for fast display |
| dcfg_project | dcfg_max_billable | = dcfg_awarded_cost (alias for clarity) |

---

## 8. Open Questions

1. **Invoice integration** — Does Decades use Sage for actual invoicing? If so, the payment schedule tracks Decades' side (what we bill the client), not vendor invoices.
2. **Change orders** — Do change orders increase the awarded_cost ceiling? If yes, the no-overbill rule checks awarded + approved_change_orders.
3. **Retainage** — Does Decades hold retainage (e.g., 10% withheld until closeout)? This affects the scheduled amounts.
4. **Multi-year programs** — Programs spanning fiscal years — does the budget reset or carry over?
