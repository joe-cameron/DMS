"""
Update DCFG DocGen flow: set correct _CC.docx file paths on all Switch cases.
Uses dynamicFileSchema approach (not designer item IDs).
"""
import json

with open("C:/dcfg/docs/templates/_flow_v2.json", "r", encoding="utf-8") as f:
    flow = json.loads(f.read())

# Navigate to Switch_Template cases
actions = flow["properties"]["definition"]["actions"]
switch = actions["Switch_Template"]
cases = switch["cases"]

# Map: case_value -> correct file path
# The case value equals dcfg_name, file = /{dcfg_name}_CC.docx
FILE_MAP = {
    "Bancroft_Blanket_Work_Order_Amendment": "/Bancroft_Blanket_Work_Order_Amendment_CC.docx",
    "Bancroft_Blanket_Work_Order": "/Bancroft_Blanket_Work_Order_CC.docx",
    "Bancroft_Work_Order": "/Bancroft_Work_Order_CC.docx",
    "Bancroft_Work_Order_Amendment": "/Bancroft_Work_Order_Amendment_CC.docx",
    "Decades_Work_Order": "/Decades_Work_Order_CC.docx",
    "Decades_Work_Order_Amendment": "/Decades_Work_Order_Amendment_CC.docx",
    "Decades_Vendor_MSA": "/Decades_Vendor_MSA_CC.docx",
    "Decades_Exhibit_C_Fee_Schedule": "/Decades_Exhibit_C_Fee_Schedule_CC.docx",
    "Decades_Exhibit_A_Basic_A": "/Decades_Exhibit_A_Basic_A_CC.docx",
    "Decades_Exhibit_A_Optimized_C": "/Decades_Exhibit_A_Optimized_C_CC.docx",
    "Decades_Exhibit_A_Concierge_B": "/Decades_Exhibit_A_Concierge_B_CC.docx",
    "Decades_Exhibit_B_Location_List": "/Decades_Exhibit_B_Location_List_CC.docx",
    "Decades_Exhibit_D_Insurance": "/Decades_Exhibit_D_Insurance_CC.docx",
    "Bancroft_Exhibit_A_Basic_A": "/Bancroft_Exhibit_A_Basic_A_CC.docx",
    "Bancroft_Exhibit_A_Concierge_B": "/Bancroft_Exhibit_A_Concierge_B_CC.docx",
    "Bancroft_Exhibit_A_Optimized_C": "/Bancroft_Exhibit_A_Optimized_C_CC.docx",
}

STANDARD_PARAMS = {
    "source": "sites/decadesconstructiongroup.sharepoint.com,59956094-d818-4896-868e-4ef6cfc77ab3,70178d3c-5878-48ab-a340-5329e696c3e9",
    "drive": "b!lGCVWRjYlkiGjk72z8d6szyNF3B4WKtIo0BTKeaWw-k0gmQTkZA9QKdMLo-aANXH",
}

STANDARD_HOST = {
    "apiId": "/providers/Microsoft.PowerApps/apis/shared_wordonlinebusiness",
    "operationId": "CreateFileItem",
    "connectionName": "shared_wordonlinebusiness",
}

updated = 0
for case_key, case_obj in cases.items():
    case_value = case_obj.get("case", "")
    if case_value not in FILE_MAP:
        print(f"  WARN: no mapping for case '{case_value}' (key: {case_key})")
        continue

    new_file = FILE_MAP[case_value]

    # Find the Populate action in this case
    for action_name, action in case_obj.get("actions", {}).items():
        if not action_name.startswith("Populate_"):
            continue

        # Set correct parameters
        action["type"] = "OpenApiConnection"
        action["inputs"] = {
            "parameters": {
                **STANDARD_PARAMS,
                "file": new_file,
                "dynamicFileSchema": "@outputs('Build_Token_Map')",
            },
            "host": STANDARD_HOST,
        }

        # Remove metadata block if designer added one
        if "metadata" in action:
            del action["metadata"]

        print(f"  OK: {case_key} -> {new_file}")
        updated += 1

print(f"\nUpdated {updated} Populate actions")

# Save updated flow
with open("C:/dcfg/docs/templates/_flow_v2_updated.json", "w", encoding="utf-8") as f:
    json.dump(flow, f, ensure_ascii=False)

print("Saved to _flow_v2_updated.json")
