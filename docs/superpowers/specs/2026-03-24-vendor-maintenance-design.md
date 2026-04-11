# Vendor Maintenance Screen — Design Spec

**Date:** 2026-03-24
**Status:** Approved

## Goal

A vendor contact book with compliance status, accessible from Operations and Send Queue. Staff can search vendors by name, filter by trade, see insurance/MSA compliance at a glance, and optionally sort by distance from a location.

## Components

### 1. Full Vendor Screen (`/#/vendors`)

**Nav location:** Operations group

**Table view:**
- Search box (filters by name)
- Trade filter dropdown (Pest Control, Landscaping, HVAC, Electricians, etc. — derived from data)
- Sortable columns: Name, Trade, Contact, Phone, Email, Insurance Status, MSA Status
- Insurance badge: green (valid), amber (expiring <30 days), red (expired/missing)
- MSA badge: green (active) or grey (none)
- CLE status: active/inactive filter toggle

**Detail view (click row):**
- Full vendor info: name, trade, contact, address, phone, email, notes, net terms
- MSA date
- Insurance GL expiration with status badge
- **Documents section:** list of attachments with label, expiration date, SharePoint link
  - Add document: user types label, sets expiration date, provides SharePoint URL
  - Delete document
  - Expiration badges per document (green/amber/red)

**Distance (optional):**
- If navigated from a location context (query param `?from=propertyId`), calculates haversine distance from that location to each vendor
- Shows "~X miles" column, sorted nearest first
- If standalone (no location context), no distance column, sort alphabetical

### 2. Quick Panel (Slide-out)

**Triggered by:** Clicking vendor name in Operations, Send Queue, or any screen

**Content:**
- Vendor name, trade
- Phone, email (clickable)
- Insurance status badge + expiration date
- MSA status badge
- CLE active/inactive
- "Open Full Profile" link → navigates to `/#/vendors/:id`

### 3. Operations Dashboard Integration

**New section:** "Vendor Compliance" card on Operations screen
- Shows vendors with insurance expiring within 30 days or expired
- Columns: Vendor, Trade, Expiration Date, Status (amber/red)
- Click → opens vendor quick panel
- Flows handle monitoring and alerting (no Nora involvement)

## New Table: `dcfg_vendor_document`

| Column | Type | Description |
|--------|------|-------------|
| `dcfg_vendor_documentid` | PK | Auto |
| `dcfg_vendor_id` | Lookup → dcfg_vendor | Parent vendor |
| `dcfg_label` | String(200) | User-typed label ("GL Insurance", "W-9", etc.) |
| `dcfg_expiration_date` | DateOnly | When this document expires |
| `dcfg_sharepoint_url` | String(500) | Link to file in SharePoint |
| `dcfg_uploaded_at` | DateTime | When uploaded |
| `dcfg_uploaded_by` | String(200) | Who uploaded |

No fixed document type categories — user labels each document freely.

## Existing Table Changes: `dcfg_vendor`

New columns already added:
- `dcfg_trade` (String) — trade/specialty
- `dcfg_insurance_gl_expiration` (DateOnly) — GL insurance expiration
- `dcfg_net_terms` (String) — payment terms
- `dcfg_cle_status` (Boolean) — CLE active
- `dcfg_msa_date` (DateOnly) — MSA date
- `dcfg_contact_name` (String) — contact full name

Future: `dcfg_latitude`, `dcfg_longitude` — for distance calculations after geocoding.

## Distance Calculation

Haversine formula, client-side JavaScript. No external API.

```javascript
function haversine(lat1, lon1, lat2, lon2) {
  const R = 3959; // miles
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) * Math.sin(dLon/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}
```

Only used when vendor and location both have lat/lon. Shows "N/A" otherwise. Geocoding deferred to later.

## Access Control

- **Operations + Management:** Full CRUD on vendors and documents
- **Viewer:** Read-only vendor list, no document management
- Per JS-06: edit/delete actions removed from DOM for viewers, not disabled

## What This Is NOT

- Not a dispatch system
- Not a routing/directions tool
- No service area tracking
- No automated vendor assignment
- No vendor portal/login
