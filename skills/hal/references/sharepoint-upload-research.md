# SharePoint Upload from Power Pages — Research 2026-04-18

## The Definitive Answer

**Direct browser → SharePoint REST (`_api/`) upload is impossible cross-origin. Period.**

SharePoint Online does not support configurable CORS whitelisting. No tenant setting, no admin option, no API. Confirmed in GitHub `sp-dev-docs` issues and Microsoft Q&A through 2025.

## What Doesn't Work

| Approach | Why It Fails |
|----------|-------------|
| Direct `_api/contextinfo` from portal domain | CORS blocks credentialed cross-origin requests |
| Graph `createUploadSession` from browser | Session URL points to SharePoint CDN — PUT to that URL is CORS-blocked |
| MSAL.js in-browser token for SharePoint scope | Token works, but upload PUT still blocked by CORS on the target URL |

## What DOES Work

### Option A: Power Automate Cloud Flow (current fallback, 30-45s)
- `POST /_api/cloudflow/v1.0/trigger/{guid}` from portal (same-origin, no CORS)
- Pass file as base64 `contentBytes`
- Flow uses SharePoint "Create file" action
- Limit: ~20-30 MB practical (base64 overhead)

### Option B: Azure Function Proxy (recommended fix)
- Extend existing `html-to-pdf` Azure Function with `/upload` endpoint
- Configure CORS `allowedOrigins` to include portal domain(s)
- Use Managed Identity → Graph API server-side
- Simple upload: `PUT /sites/{siteId}/drive/items/{parentId}:/{filename}:/content` (under 4 MB)
- Large files: `createUploadSession` + chunked PUT (any size)
- Chunk size: multiple of 320 KiB, max 60 MiB per chunk
- **Do NOT include Authorization header on chunk PUTs** — URL is pre-authenticated
- Required Graph permissions: `Sites.ReadWrite.All` (application)

### Option C: Power Pages Native SharePoint Integration
- Enable server-based integration in PPAC
- Uses Document Locations subgrid on Dataverse forms
- 50 MB max, form-bound, limited path control
- Not suitable for custom `DCFG_Outputs/Customer/Year/DocType` hierarchy

## Graph Upload API Reference

Simple (under 4 MB):
```
PUT https://graph.microsoft.com/v1.0/sites/{siteId}/drive/items/{parentId}:/{filename}:/content
Authorization: Bearer {token}
Content-Type: application/octet-stream
```

Chunked (over 4 MB):
```
POST https://graph.microsoft.com/v1.0/sites/{siteId}/drive/items/{parentId}:/{filename}:/createUploadSession
→ returns uploadUrl

PUT {uploadUrl}
Content-Range: bytes 0-{N-1}/{total}
(no Authorization header — URL is pre-auth)
```

## Key Sources
- learn.microsoft.com/en-us/power-pages/configure/manage-sharepoint-documents
- learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession
- learn.microsoft.com/en-us/power-pages/configure/cloud-flow-integration
- github.com/SharePoint/sp-dev-docs/issues/9650 (CORS not configurable)
- learn.microsoft.com/en-us/answers/questions/912690 (CORS workaround guidance)
