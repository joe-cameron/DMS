# DCFG Component Library

**Source of truth for all UI patterns in the DCFG Contracting Suite SPA.**
Every new screen, feature, or modification must use these components. No exceptions without documented justification.

---

## Design Tokens

### Colors

```
BRAND
  Navy:           #1B2A4A   (primary actions, text, nav)
  Navy Mid:       #2E5295   (secondary dark, active borders)
  Navy Pale:      #EDF1F8   (light backgrounds, hover)
  Navy Deep:      #0F1A30   (toast bg, darkest)
  Amber:          #D4A017   (accent, active indicator)
  Amber Light:    #FFF8E7   (highlight background)
  Green:          #2D8659   (success, active status)

STATUS BADGES
  Draft:          bg #F1F5F9   text #475569
  Generated:      bg #DBEAFE   text #1E40AF
  Sent/Pending:   bg #FEF3C7   text #92400E
  Signed/Active:  bg #DCFCE7   text #166534
  Closed:         bg #F1F5F9   text #1E293B
  Void/Declined:  bg #FEE2E2   text #991B1B
  Navy:           bg #1B2A4A   text #FFFFFF

NEUTRAL
  Page bg:        #F8FAFC
  Card bg:        #FFFFFF
  Border:         #E2E8F0
  Light border:   #F1F5F9
  Text primary:   #1E293B
  Text secondary: #475569
  Text muted:     #94A3B8

ALERTS
  Error:          #C0392B
  Error bg:       #FEE2E2
  Warning:        #D4A017
  Warning bg:     #FFFBEB
  Success:        #2D8659
  Success bg:     #DCFCE7
  Info:           #2E5295
  Info bg:        #DBEAFE
```

### Typography

```
FONTS
  Body:           IBM Plex Sans (400, 450, 500, 600, 700)
  Display:        Fraunces (700, serif)
  Mono:           IBM Plex Mono (IDs, codes, amounts)

SIZES
  Page title:     22-24px  Fraunces 700
  Section head:   16px     IBM Plex Sans 600
  Label:          14px     600
  Body:           13-14px  400-500
  Small:          12-13px  400
  Tiny/uppercase: 10-11px  600  letter-spacing 0.05em

LINE HEIGHT
  Compact:        1.0-1.1
  Readable:       1.4-1.5
```

### Spacing

```
Page padding:       28px 32px
Card padding:       20px 24px
Section gap:        16-24px
Form field gap:     12px
Table cell:         11px 16px
Button (primary):   10px 24px
Button (compact):   4px 10px
Modal padding:      20-24px

BORDER RADIUS
  Inputs/cards:     6-8px
  Badges:           12px
  Avatars:          50%
  Bottom drawer:    24px 24px 0 0
```

---

## Components

### 1. Badge

Status indicator pill. Used in tables, cards, headers.

```
CLASS: .badge .badge-{color}
SIZE: padding 2px 8px, fontSize 11px, fontWeight 600, borderRadius 12px
COLORS: green, amber, red, blue, purple, grey, navy
USAGE: <span className="badge badge-green">Active</span>
```

**When to use:** Any status that maps to the ContractStatus, OnboardingStatus, or document state enums.

### 2. Status Banner

Full-width banner at top of detail screens showing record status.

```
CLASS: .status-banner .status-banner-{status}
SIZE: width 100%, padding 12px 24px, fontSize 14px, fontWeight 600
STATUSES: draft, generated, sent, signed, closed, void, declined
USAGE: <div className="status-banner status-banner-sent">Sent to Client</div>
```

**When to use:** Detail screens (ContractDetail, MsaDetail) to show current lifecycle state.

### 3. Card

Container for grouped content sections.

```
CLASS: .card
SIZE: bg white, border 1px solid #E2E8F0, borderRadius 8px, padding 20px 24px
USAGE: <div className="card">...</div>
```

**When to use:** Any content section that needs visual grouping on a page.

### 4. Table (dcfg-table)

Data table with sort headers, search, hover rows.

```
CLASS: .table-wrapper > .dcfg-table
HEADER: bg #F8FAFC, 11px uppercase, 600 weight, letter-spacing 0.05em
CELLS: 13.5px, padding 11px 16px, border-bottom #F1F5F9
ROW HOVER: bg #F8FAFC, cursor pointer
ROW VARIANTS: .row-amber (warning), .row-red (error)
```

**Paired with:** `useTableControls` hook for sort + search.

**When to use:** Any list of records (contracts, customers, MSAs, locations, onboarding cases).

### 5. Button — Primary

Main action button. One per form/section.

```
STYLE: bg #1B2A4A, color white, border none, borderRadius 6px
SIZE: padding 9-10px 18-24px, fontSize 13.5px, fontWeight 600
DISABLED: opacity 0.5, cursor not-allowed
USAGE: Save, Create, Generate, Approve
```

### 6. Button — Secondary

Cancel, back, dismiss actions.

```
STYLE: bg #F1F5F9, color #1E293B, border 1px solid #E2E8F0
SIZE: same as primary
USAGE: Cancel, Back, Close
```

### 7. Button — Compact

Inline actions in tables and forms.

```
STYLE: same colors as primary or secondary
SIZE: padding 4px 10px, fontSize 11-12px, fontWeight 600
USAGE: Edit, Remove, Add Line, ✕
```

### 8. Button — Ghost/Icon

Minimal buttons for close, delete, link actions.

```
STYLE: bg none, border none, cursor pointer
COLOR: #94A3B8 (neutral), #C0392B (destructive)
SIZE: fontSize 12-18px
USAGE: ✕ close, 🗑 delete, link icons
```

### 9. Text Input

Standard form input.

```
STYLE: border 1px solid #E2E8F0, borderRadius 6px, padding 10px 14px
FONT: 14px IBM Plex Sans, color #1B2A4A
WIDTH: 100% or fixed
VARIANTS: type="text", "date", "email", "number"
```

### 10. Select Dropdown

```
STYLE: same as text input
FIRST OPTION: "Select..." or "— Choose —" (disabled, placeholder)
```

### 11. Textarea

```
STYLE: same as text input, height 80px, resize vertical
PAIRED WITH: SpeechMic component (optional voice input)
```

### 12. Modal Overlay

Full-screen overlay with centered panel.

```
OVERLAY: position fixed, inset 0, bg rgba(15,26,48,0.55), zIndex 100
PANEL: bg white, borderRadius 8px, padding 20-24px, max-width 520px
CLOSE: top-right ✕ button
HEADER: flex row, space-between, fontWeight 700, 16px, navy
FOOTER: flex row, justify-content flex-end, gap 8px
```

**When to use:** Confirmations, email previews, request-info forms. NOT for browsing lists (use detail strip instead).

### 13. Bottom Drawer

Slides up from bottom. Used in LocationManager.

```
STYLE: position fixed, bottom 0, borderRadius 24px 24px 0 0
SIZE: width 390px, maxHeight 85-92vh
HANDLE: 40×4px gray bar at top
OVERLAY: dark semi-transparent
```

**When to use:** Focused editing tasks on detail screens (property details, appliance management).

### 14. Toast Notification

Auto-dismissing notification in bottom-right corner.

```
COMPONENT: <ToastProvider> + useToast() hook
TYPES: ok (green), warn (amber), err (red), info (blue)
POSITION: fixed, bottom 24px, right 24px
DURATION: 4000ms (error: 5500ms)
BG: #0F1A30 (dark), white text, colored dot indicator
```

### 15. Search Bar

Above tables for client-side filtering.

```
STYLE: width 220px, borderRadius 6px, padding 7px 12px
BORDER: 1px solid #E2E8F0
PLACEHOLDER: "Search..."
HOOK: useTableControls (searchInputStyle export)
```

### 16. Sort Header

Clickable table header with direction indicator.

```
STYLE: cursor pointer, userSelect none
ICONS: ↕ (neutral), ↑ (asc), ↓ (desc)
HOOK: useTableControls (SortIcon export, sortableThStyle)
```

### 17. Warning Banner

Inline alert for non-blocking warnings.

```
CLASS: .warn-banner
STYLE: border-left 4px solid #D4A017, bg #FFFBEB, padding 10px 14px
FONT: 13px, color #92400E
RADIUS: 0 4px 4px 0
```

### 18. NavPanel

Left sidebar navigation. Sticky, full height.

```
WIDTH: 220px
BG: white, border-right 1px solid #E2E8F0
ITEM: padding 10px 16px, fontSize 13.5px
ACTIVE: left border 3px solid #2E5295, bg navy pale
HOVER: bg #EDF1F8
USER FOOTER: avatar circle (30px, navy bg, white initials)
```

### 19. SpeechMic

Voice-to-text button attached to textareas.

```
COMPONENT: <SpeechMic onResult={text => ...} />
INACTIVE: bg #F1F5F9, color #64748B
ACTIVE: bg #DC2626, color white
DISABLED: opacity 0.4
SIZE: padding 4px 8px, borderRadius 4px
```

### 20. KPI Card (NEW — Dashboard)

Compact metric card with click-to-drill-down.

```
SIZE: minHeight 105px, padding 12-14px 14-16px
BG: white, border 1px solid #E2E8F0, borderRadius 8px 8px 0 0
ACTIVE: border-bottom 3px solid #2D6A4F, bg #FAFFF8
ALERT BADGE: position absolute, top 8px, right 8px, bg #D32F2F, color white
LABEL: 9-10px uppercase, letter-spacing 1px, color #888
MAIN METRIC: 24-28px, fontWeight 700, color #1B2A4A (navy)
SUB-METRICS: flex row, gap 8-10px, fontSize 9-10px
```

### 21. Detail Strip (NEW — Dashboard)

Persistent expandable panel below KPI cards.

```
BG: white, border 1px solid #E2E8F0 (no top border — connected to cards)
RADIUS: 0 0 8px 8px
MAX HEIGHT: 260px, overflow-y auto
LAYOUT: 3-column grid
SECTION TITLE: 8-9px uppercase, color #888, border-bottom #F0EDE5
ITEMS: clickable rows with name + meta + badge, link to detail screen
MINIMIZE: toggle button (▼) collapses to 0 height
```

### 22. Approval Queue Table (NEW — Dashboard)

Document review table with action buttons.

```
EXTENDS: .dcfg-table pattern
FILTER BAR: [All] [Sales] [Operations] toggle buttons above table
TABS: Pending | Approved | Returned with count badges
ACTION BUTTONS: Approve (green), Info (blue), Return (orange), Delete (red), Open (gray)
```

---

## Layout Templates

### List Screen
```
Page Header (title + create button)
Search Bar
Table Wrapper > dcfg-table
  sortable columns + row click → navigate to detail
```

### Detail Screen
```
Status Banner
Page Header (title + action buttons)
Card sections (vertically stacked, gap 16px)
  Labels + values or form inputs
  Tabs for related data (contracts, MSAs, locations)
```

### Wizard Screen
```
Step indicator (numbered circles + progress bar)
Card with current step content
  Form fields
Back / Next buttons (flex row, space-between)
Final step: Review summary + Generate button
```

### Dashboard Screen (NEW)
```
Title + Quick Action buttons
KPI Cards (5 across)
Detail Strip (persistent, 3 columns)
Document Approval Queue (table + filters + tabs + actions)
Floating Search FAB (bottom-right)
```

---

## Rules

1. **Use existing components.** Don't invent new patterns when these exist.
2. **Inline styles only.** No CSS modules, no external frameworks. Color constants at top of file.
3. **Navy + Amber + Green palette.** No other brand colors without justification.
4. **IBM Plex Sans body, Fraunces display.** No other fonts.
5. **Every table gets useTableControls.** Sort + search is standard.
6. **Every destructive action gets confirmation.** Modal with Cancel + Confirm.
7. **Toast for all async results.** Success, warning, error — user always knows what happened.
8. **Badges for all statuses.** Consistent color mapping across all screens.
9. **No side panels for drill-down.** Use detail strips or navigate to full screen.
10. **Actions follow workflow.** Only show buttons the user would commonly use in this context.
