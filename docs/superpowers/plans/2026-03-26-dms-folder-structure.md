# DMS Folder Structure Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure DCFG_Attachments from flat uploads to `{Customer}/{Location}/{Year}/` hierarchy with supersede logic for annual renewals.

**Architecture:** Modify the existing `flow_cert_upload_v2` flow to resolve customer display name and location address, build a dynamic folder path, create folders if needed, upload with slugged filenames, and deactivate previous versions of the same doc type. The SPA and Dataverse schema are unchanged — only the flow's folder path and a new supersede step.

**Tech Stack:** Power Automate (Dataverse trigger, SharePoint Online connector), PowerShell for flow definition updates

**Spec:** `C:\DCFG\docs\superpowers\specs\2026-03-26-dms-folder-structure-design.md`

---

## Scope

This plan covers **Sub-project #1 only**: the SharePoint folder creation flow. It modifies the existing `flow_cert_upload_v2` flow definition. The SPA wiring (sub-project #2) and QA promotion pipeline (sub-project #3) are separate plans.

## Current State

`flow_cert_upload_v2` (`C:\DCFG\FlowDefs\flow_cert_upload_v2.json`) currently:
1. Triggers on `dcfg_document_request` creation
2. Parses `dcfg_notes` JSON for: `property_id`, `doc_type`, `file_name`, `file_content`, `expiry_date`
3. Uploads file flat to `/DCFG_Attachments/{filename}`
4. Gets file web URL
5. Creates `dcfg_location_document` record
6. Writes audit log
7. Marks request complete

## What Changes

| Step | Current | New |
|---|---|---|
| After parse | Jump to upload | **New:** Resolve customer name + location address from property_id |
| Upload path | `/DCFG_Attachments/` | `/DCFG_Attachments/{CustomerDisplay}/{LocationAddress}/{Year}/` |
| Filename | Raw `varFileName` | Slugged: `{doc-type-slug}-{date}.{ext}` |
| After upload | Create record | **New:** Deactivate previous active doc of same type for same property |
| Create record | Same | Same (already correct) |

## File Structure

```
Modify: C:\DCFG\FlowDefs\flow_cert_upload_v2.json
  - Add actions: Lookup_Property, Lookup_Customer, Build_Folder_Path, Create_Folders, Slugify_Filename, Deactivate_Previous
  - Modify action: Upload_File_To_Attachments (folderPath + name)
```

No new files. No SPA changes. No schema changes.

---

## Chunk 1: Flow Definition Changes

### Task 1: Read current flow from environment

Before modifying, capture the current live flow definition as our baseline.

**Files:**
- Read: `C:\DCFG\FlowDefs\flow_cert_upload_v2.json` (existing baseline)

- [ ] **Step 1: Identify the flow in the environment**

```powershell
# Find flow_cert_upload in Test environment
pwsh -Command '
$dvUrl = "https://org0c17e98d.crm.dynamics.com/"
$sec = (Get-AzAccessToken -ResourceUrl $dvUrl -AsSecureString).Token
$token = [System.Net.NetworkCredential]::new("", $sec).Password
$h = @{ Authorization = "Bearer $token"; Accept = "application/json"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
$api = "${dvUrl}api/data/v9.2"
$flows = (Invoke-RestMethod -Uri "$api/workflows?`$filter=name eq ''flow_cert_upload''&`$select=workflowid,name,statecode" -Headers $h).value
$flows | ForEach-Object { Write-Host "$($_.name) | $($_.workflowid) | state=$($_.statecode)" }
'
```

Expected: Flow ID and current state (1=Active or 0=Draft)

- [ ] **Step 2: Read back current clientdata**

Per feedback_flow_rebuild_pattern: always read the source flow first, never construct from scratch.

```powershell
# Read current flow clientdata
pwsh -Command '
# ... auth same as above ...
$flow = Invoke-RestMethod -Uri "$api/workflows($flowId)?`$select=clientdata" -Headers $h
$flow.clientdata | Out-File -FilePath "C:\DCFG\FlowDefs\flow_cert_upload_v2_live.json" -Encoding utf8
'
```

---

### Task 2: Add property + customer lookup actions

After `Parse_Notes`, the flow needs to resolve the property record to get the customer and address for folder naming.

- [ ] **Step 1: Add Lookup_Property action**

Insert after `Parse_Notes`. Fetches the property record to get address and customer lookup.

```json
"Lookup_Property": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_commondataserviceforapps",
      "operationId": "GetItem",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
    },
    "parameters": {
      "entityName": "dcfg_properties",
      "recordId": "@variables('varPropertyId')",
      "$select": "dcfg_name,dcfg_address,dcfg_city,dcfg_state,_dcfg_customer_id_value"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Init_varPropertyId": ["Succeeded"],
    "Init_varDocType": ["Succeeded"],
    "Init_varFileName": ["Succeeded"],
    "Init_varFileContent": ["Succeeded"],
    "Init_varExpiryDate": ["Succeeded"],
    "Init_varUploadedBy": ["Succeeded"]
  }
}
```

- [ ] **Step 2: Add Lookup_Customer action**

Fetches customer display name for the top-level folder.

```json
"Lookup_Customer": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_commondataserviceforapps",
      "operationId": "GetItem",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
    },
    "parameters": {
      "entityName": "dcfg_customers",
      "recordId": "@outputs('Lookup_Property')?['body/_dcfg_customer_id_value']",
      "$select": "dcfg_display_name"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Lookup_Property": ["Succeeded"]
  }
}
```

---

### Task 3: Build folder path and slugged filename

- [ ] **Step 1: Add Build_Folder_Path compose action**

Constructs the dynamic path: `/DCFG_Attachments/{Customer}/{Location}/{Year}/`

```json
"Build_Folder_Path": {
  "type": "Compose",
  "inputs": "@concat('/DCFG_Attachments/', outputs('Lookup_Customer')?['body/dcfg_display_name'], '/', outputs('Lookup_Property')?['body/dcfg_name'], '/', formatDateTime(utcNow(), 'yyyy'))",
  "runAfter": {
    "Lookup_Customer": ["Succeeded"]
  }
}
```

- [ ] **Step 2: Add Doc_Type_Slug compose action**

Maps the integer doc_type picklist to a filename slug.

```json
"Doc_Type_Slug": {
  "type": "Compose",
  "inputs": "@if(equals(variables('varDocType'), 100000000), 'fire-extinguisher', if(equals(variables('varDocType'), 100000001), 'elevator-cert', if(equals(variables('varDocType'), 100000002), 'fire-inspection', if(equals(variables('varDocType'), 100000003), 'insurance-cert', if(equals(variables('varDocType'), 100000004), 'generator-contract', if(equals(variables('varDocType'), 100000005), 'roof-warranty', if(equals(variables('varDocType'), 100000006), 'lease', if(equals(variables('varDocType'), 100000007), 'vendor-callsheet', if(equals(variables('varDocType'), 100000008), 'equipment-manual', 'other')))))))))",
  "runAfter": {
    "Lookup_Customer": ["Succeeded"]
  }
}
```

Note: Picklist values must be verified against the actual `dcfg_doc_type` choice column. The mapping above is a placeholder — read the real values from the environment before deploying.

- [ ] **Step 3: Add Build_Filename compose action**

Constructs: `{slug}-{date}.{ext}`

```json
"Build_Filename": {
  "type": "Compose",
  "inputs": "@concat(outputs('Doc_Type_Slug'), '-', formatDateTime(utcNow(), 'yyyy-MM-dd'), '.', last(split(variables('varFileName'), '.')))",
  "runAfter": {
    "Doc_Type_Slug": ["Succeeded"]
  }
}
```

---

### Task 4: Create folders if needed

SharePoint `CreateFile` fails if the folder doesn't exist. Use the SharePoint connector's `CreateNewFolder` action with error handling — 409 (already exists) is success.

- [ ] **Step 1: Add Create_Customer_Folder action**

```json
"Create_Customer_Folder": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_sharepointonline",
      "operationId": "CreateNewFolder",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"
    },
    "parameters": {
      "dataset": "https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite",
      "table": "DCFG_Attachments",
      "parameters/path": "@outputs('Lookup_Customer')?['body/dcfg_display_name']"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Build_Folder_Path": ["Succeeded"]
  }
}
```

- [ ] **Step 2: Add Create_Location_Folder action**

```json
"Create_Location_Folder": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_sharepointonline",
      "operationId": "CreateNewFolder",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"
    },
    "parameters": {
      "dataset": "https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite",
      "table": "DCFG_Attachments",
      "parameters/path": "@concat(outputs('Lookup_Customer')?['body/dcfg_display_name'], '/', outputs('Lookup_Property')?['body/dcfg_name'])"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Create_Customer_Folder": ["Succeeded", "Failed"]
  }
}
```

Note: `runAfter` includes `"Failed"` because 409 (folder exists) is expected. The Configure Run After setting must allow "has failed" for idempotent folder creation.

- [ ] **Step 3: Add Create_Year_Folder action**

```json
"Create_Year_Folder": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_sharepointonline",
      "operationId": "CreateNewFolder",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"
    },
    "parameters": {
      "dataset": "https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite",
      "table": "DCFG_Attachments",
      "parameters/path": "@concat(outputs('Lookup_Customer')?['body/dcfg_display_name'], '/', outputs('Lookup_Property')?['body/dcfg_name'], '/', formatDateTime(utcNow(), 'yyyy'))"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Create_Location_Folder": ["Succeeded", "Failed"]
  }
}
```

---

### Task 5: Update upload action to use dynamic path

- [ ] **Step 1: Modify Upload_File_To_Attachments**

Change `folderPath` and `name`:

```json
"Upload_File_To_Attachments": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_sharepointonline",
      "operationId": "CreateFile",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"
    },
    "parameters": {
      "dataset": "https://decadesconstructiongroup.sharepoint.com/sites/DCFGContractingSuite",
      "folderPath": "@outputs('Build_Folder_Path')",
      "name": "@outputs('Build_Filename')",
      "body": "@base64ToBinary(variables('varFileContent'))"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Create_Year_Folder": ["Succeeded", "Failed"]
  }
}
```

---

### Task 6: Add supersede logic

Before creating the new `dcfg_location_document` record, deactivate any existing active record of the same doc type for the same property.

- [ ] **Step 1: Add Find_Previous_Active action**

```json
"Find_Previous_Active": {
  "type": "OpenApiConnection",
  "inputs": {
    "host": {
      "connectionName": "shared_commondataserviceforapps",
      "operationId": "ListRecords",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
    },
    "parameters": {
      "entityName": "dcfg_location_documents",
      "$filter": "_dcfg_property_id_value eq '@{variables('varPropertyId')}' and dcfg_doc_type eq @{variables('varDocType')} and dcfg_is_active eq true",
      "$select": "dcfg_location_documentid"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": {
    "Get_File_Web_URL": ["Succeeded"]
  }
}
```

- [ ] **Step 2: Add Deactivate_Previous apply-to-each**

Loop over results (usually 0 or 1) and set `dcfg_is_active = false`.

```json
"Deactivate_Previous": {
  "type": "Foreach",
  "foreach": "@outputs('Find_Previous_Active')?['body/value']",
  "actions": {
    "Set_Inactive": {
      "type": "OpenApiConnection",
      "inputs": {
        "host": {
          "connectionName": "shared_commondataserviceforapps",
          "operationId": "UpdateRecord",
          "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        },
        "parameters": {
          "entityName": "dcfg_location_documents",
          "recordId": "@items('Deactivate_Previous')?['dcfg_location_documentid']",
          "item/dcfg_is_active": false
        },
        "authentication": "@parameters('$authentication')"
      }
    }
  },
  "runAfter": {
    "Find_Previous_Active": ["Succeeded"]
  }
}
```

- [ ] **Step 3: Update Create_Location_Document_Record runAfter**

Change from running after `Get_File_Web_URL` to running after `Deactivate_Previous`:

```json
"Create_Location_Document_Record": {
  ...
  "runAfter": {
    "Deactivate_Previous": ["Succeeded"]
  }
}
```

---

### Task 7: Build and deploy the updated flow

This follows the 3-step flow build process (CLAUDE.md).

- [ ] **Step 1: Verify picklist values for dcfg_doc_type**

```powershell
# Query the doc_type choice column options
pwsh -Command '
# ... auth ...
$url = "$api/EntityDefinitions(LogicalName=%27dcfg_location_document%27)/Attributes(LogicalName=%27dcfg_doc_type%27)/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet"
$meta = Invoke-RestMethod -Uri $url -Headers $h
$meta.OptionSet.Options | ForEach-Object { Write-Host "$($_.Value) = $($_.Label.UserLocalizedLabel.Label)" }
'
```

Update the `Doc_Type_Slug` mapping with real values.

- [ ] **Step 2: Push updated flow definition**

Per feedback_flow_rebuild_pattern: copy prod clientdata, replace connectionReferences only, include schemaVersion. Never overwrite triggers.

```powershell
# Read live clientdata, merge new actions, push update
pwsh -File Update-CertUploadFlow.ps1
```

- [ ] **Step 3: Test with a document_request record**

Create a `dcfg_document_request` with notes JSON containing test data. Verify:
- Customer folder created in SharePoint
- Location folder created
- Year folder created
- File uploaded with slugged name
- `dcfg_location_document` record created with correct `sharepoint_url`
- Previous active record (if any) deactivated

---

## Chunk 2: Verification

### Task 8: End-to-end verification

- [ ] **Step 1: Create test document request via PowerShell**

```powershell
$notes = @{
    property_id  = "{test-property-guid}"
    doc_type     = 100000003  # Insurance
    file_name    = "test-insurance.pdf"
    file_content = "{base64-of-small-test-pdf}"
    expiry_date  = "2027-03-26"
} | ConvertTo-Json -Compress

# Create document_request
$body = @{
    dcfg_name         = "Test Cert Upload"
    dcfg_request_type = 100000005  # CertUpload
    dcfg_notes        = $notes
    dcfg_requested_by = "test-script"
    dcfg_status       = 100000000  # Pending
} | ConvertTo-Json
# POST to dcfg_document_requests
```

- [ ] **Step 2: Verify SharePoint folder structure**

Check that the file landed at:
`/DCFG_Attachments/{CustomerDisplay}/{LocationAddress}/2026/insurance-cert-2026-03-26.pdf`

- [ ] **Step 3: Verify Dataverse records**

- `dcfg_location_document` created with `is_active = true`
- `sharepoint_url` points to correct path
- Audit log entry exists

- [ ] **Step 4: Test supersede — upload second insurance cert**

Repeat step 1. Verify:
- New file uploaded (different date in name if different day, or `-2` suffix if same day)
- New `dcfg_location_document` with `is_active = true`
- Previous record now has `is_active = false`

---

## Dependencies for Sub-projects #2 and #3

Once this plan is complete:

- **Sub-project #2 (SPA wiring):** Wire `DocumentCapture.jsx` to create `dcfg_document_request` records instead of storing base64 in localStorage. The flow handles everything from there.
- **Sub-project #3 (QA promotion):** Build staff review UI + merge logic using `dcfg_upkeep_location_id` as the key. Re-link `dcfg_location_document` from intake to production `dcfg_property`.
