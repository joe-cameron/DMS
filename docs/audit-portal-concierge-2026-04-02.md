# Portal Concierge Security Audit — 2026-04-02

## CRITICAL FINDINGS

### 1. CREDENTIALS EXPOSED IN SITE SETTINGS
```
UPKeepAPIAuth = service@decades-cg.com,UpKeep123!
```
**UpKeep API credentials stored in plain text as a site setting.** Anyone with read access to site settings (any authenticated portal user, or anyone who can hit the Web API) can read this. This is a **credential exposure vulnerability**.

**ACTION:** Remove this site setting immediately. Store UpKeep credentials in Azure Key Vault or Dataverse encrypted column. Rotate the UpKeep password NOW — it must be considered compromised.

### 2. OPEN REGISTRATION ENABLED
```
Authentication/Registration/OpenRegistrationEnabled = true
Authentication/Registration/Enabled = true
Authentication/Registration/ExternalLoginEnabled = true
Authentication/Registration/InvitationEnabled = true
Authentication/Registration/LocalLoginEnabled = true
```
**Anyone can create an account on this portal.** The Concierge portal is supposed to be access-code-gated, but the underlying Power Pages auth allows self-registration. A user who registers gets a portal contact, which may grant them table permissions.

**ACTION:** Set `OpenRegistrationEnabled = false`. The Concierge SPA manages access via codes, not portal registration.

### 3. LEGACY FLOW URLs EXPOSED
```
dcg/flow/createWorkOrder = https://...
dcg/flow/getLocations = https://...
dcg/flow/getWorkOrders = https://...
dcg/flow/uploadFile = https://...
dcg/flow/getFileUrl = https://...
dcg/flow/scheduledVisits = https://...
```
**Six legacy HTTP-triggered flow URLs** stored in site settings. These are from the old DCG Portal (pre-DCFG). If these flows are still active, anyone who reads these site settings can invoke them directly — no auth required on HTTP triggers by default.

**ACTION:** Verify if these flows are still active. If not needed, delete the site settings and deactivate the flows. If needed, migrate to Dataverse-triggered pattern.

### 4. LEGACY SURVEY URL
```
dcg/survey/baseUrl = https://dcgportal.powerappsportals.com/survey
```
Points to the old DCG portal. May be dead or redirecting.

### 5. WEBAPI ERROR DETAILS ENABLED
```
Webapi/Error/InnerError = true
```
**Inner error details exposed to API consumers.** In production, this should be `false` — it leaks stack traces and internal error messages to anyone calling the Web API.

**ACTION:** Set to `false`.

### 6. DUPLICATE SITE SETTINGS
Almost every setting appears 3x (one per site/portal in the environment). This is expected for multi-site environments but makes auditing harder. No action needed, but be aware that changes must be made to the correct site's copy.

## NON-ISSUES (Confirmed OK)

- `Webapi/dcfg_intake_*/Enabled = true` + `Fields = *` — correct for Concierge SPA to work
- `Webapi/dcfg_property_intake/Enabled = true` — needed
- `Webapi/dcfg_location_type/Enabled = true` — needed for type dropdowns
- `X-Frame-Options = SAMEORIGIN` — correct, prevents clickjacking
- `Authentication/LoginThrottling` settings — present and reasonable (1000 attempts, 10 min lockout)

## PRIORITY ACTIONS

| # | Action | Severity | Effort |
|---|--------|----------|--------|
| 1 | **Rotate UpKeep password** and remove `UPKeepAPIAuth` site setting | CRITICAL | 15 min |
| 2 | Set `OpenRegistrationEnabled = false` | HIGH | 2 min |
| 3 | Set `Webapi/Error/InnerError = false` | MEDIUM | 2 min |
| 4 | Audit legacy `dcg/flow/*` URLs — deactivate if unused | MEDIUM | 30 min |
| 5 | Remove `dcg/survey/baseUrl` if legacy | LOW | 2 min |
