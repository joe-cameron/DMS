# DCFG Build Package — Security & Quality Review

**Reviewed:** March 28, 2026
**Package:** DCFG-Complete-Build-Package.zip
**Files:** 46 files, 382K total
**Reviewer:** Claude (pre-deployment audit)

---

## PASS / FAIL Summary

| Check | Result | Details |
|---|---|---|
| Secrets scan | ✅ PASS | No hardcoded API keys, passwords, or tokens. All sensitive values use placeholders. |
| Entity set name correctness | ✅ PASS | Zero instances of incorrect `dcfg_properties`. All references use correct `dcfg_propertys`. |
| Connect trailing slash | ✅ PASS | All `Connect` calls include the mandatory trailing slash. |
| Unauthorized write operations | ✅ PASS | Decades Brain spec enforces read-only against Dataverse. Only authorized write is to SharePoint company brain files. |
| Email access restriction | ✅ PASS | Email access blocked for all users. System accounts only, admin-configured. Scripted refusal responses defined. |
| Budget_committed protection | ✅ PASS | Consistently documented as read-only / never written by UI across all specs. |
| Audit log protection | ✅ PASS | Consistently documented as CREATE ONLY across all specs. |
| Fictional example data | ✅ PASS | All example email addresses use example.com. WiFi password is fictional. GUIDs in examples are obviously synthetic (a1b2c3d4 patterns) or zero-GUIDs. |
| Org-specific constants | ✅ EXPECTED | Dataverse org URL, PAC site ID, powerpagesites ID, and tenant ID are present — these are required build targets, not leaks. |

---

## Detailed Findings

### 1. No Secrets Leaked

- `.env.example` contains `your_gemini_api_key_here` and `your_anthropic_api_key_here` — placeholder only ✓
- No bearer tokens, OAuth secrets, or connection strings anywhere in the package
- The `system-credentials.json` starter file in the company brain is empty and its `_meta` description explicitly says "NOT passwords"

### 2. Org-Specific Data (Intentional)

These values appear across the package and are **required** for the build to target the correct environment:

| Value | Purpose | Files containing it |
|---|---|---|
| `org0c17e98d.crm.dynamics.com` | Dataverse org URL | 5 files |
| `22947376-be10-4bda-a90f-32b855c43045` | PAC pages site ID | 2 files |
| `a150bd53-7fbc-423d-a1ad-dd653ab4c435` | powerpagesites record ID | 0 files in package (referenced in skills, not duplicated here) |
| `71ccf1ec-8b0a-4419-9a45-a617aa1a66d6` | Azure tenant ID | 1 file (OP-Brain-Insight.ps1) |
| `DCFGContractingSuite` | Solution name | 1 file (OP-Brain-Insight.ps1) |

**Risk assessment:** These are environment identifiers, not credentials. They identify which Dataverse org to connect to but do not grant access. Access requires an authenticated Azure AD session (interactive browser login). An attacker knowing these values alone cannot access any data.

### 3. Write Operation Boundary

The package defines a strict write boundary:

**Authorized writes:**
- SharePoint `company-brain` knowledge files via Graph API PUT (Decades Brain "Save to Brain" feature)
- `dcfg_brain_insight` table via scheduled Power Automate flows (not user-triggered)

**Explicitly blocked writes:**
- No PATCH or DELETE to `dcfg_audit_logs` (CREATE ONLY)
- No write to `dcfg_budget_committed` (flow_commit exclusive)
- No Dataverse writes from Decades Brain UI (Phase 1 is read-only)
- No email sending capability
- No flow triggering from the chat interface

### 4. Role-Based Access

The package correctly enforces role-based visibility:
- DCFG_Sales cannot see vendor reliability scores, contract financials, or billing exceptions
- DCFG_Operations cannot see customer sales intelligence
- Email access is blocked for ALL roles — system accounts only
- Company brain write permissions are scoped by role and domain

### 5. Third-Party Skill Risk

The skills download guide recommends 3 third-party installs:
- **obra/superpowers** — MIT licensed, 93K+ stars, author credibility verified (Jesse Vincent, Perl pumpking, Keyboardio co-founder)
- **Trail of Bits security skills** — Institutional author, professional security firm
- **sanjay3290/ai-skills** — Community author, 39 stars, lower credibility tier but functional

**Recommendation:** Apply the backward-reading security scan to all third-party SKILL.md files before loading. Check for:
- External URLs that data could be sent to
- `fetch`, `curl`, `wget`, or `Invoke-RestMethod` calls to non-DCFG domains
- Instructions that override permissions or bypass restrictions
- Hidden base64-encoded content
- Instructions to ignore or override system prompts

### 6. Items Flagged for Human Decision

| Item | Decision Needed |
|---|---|
| Tenant ID in PowerShell script | Is this acceptable to include in a file that may be shared? The tenant ID is not secret but does identify the Azure AD tenant. |
| SharePoint drive ID | Not yet in the package — will need to be added at deployment time. Should be treated as a configuration value, not hardcoded. |
| UpKeep API credentials | Referenced as "provided at deployment." Ensure these go into environment variables or Azure Key Vault, never into skill files or JSON configs. |
| AI model API key | Referenced as deployment config item #4. Same — environment variable only. |

---

## Recommendation

**The package is clear for handoff to Claude Code CLI.**

No secrets, no unauthorized write paths, no incorrect entity set names, no missing trailing slashes, no unprotected email access. The org-specific constants are required build targets and do not grant access on their own.

The one procedural recommendation: before installing any third-party skill (Superpowers, Trail of Bits, sanjay3290), read each SKILL.md file backward — last line to first — to detect any embedded prompt injection payloads before encountering their social engineering framing.
