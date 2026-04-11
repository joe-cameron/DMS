"""
Update DCFG DocGen flow: use SharePoint item IDs (designer format) for all Switch cases.
"""
import json

with open("C:/dcfg/docs/templates/_flow_v2.json", "r", encoding="utf-8") as f:
    flow = json.loads(f.read())

actions = flow["properties"]["definition"]["actions"]
switch = actions["Switch_Template"]
cases = switch["cases"]

# Map: case_value -> (item_id, display_path)
# From Graph API query of the drive
ITEM_MAP = {
    "Bancroft_Blanket_Work_Order_Amendment": ("01D4QOAQNEO4VCLMH6OJEZK5MFTK36YA46", "/Bancroft_Blanket_Work_Order_Amendment_CC.docx"),
    "Bancroft_Blanket_Work_Order": ("01D4QOAQMVCF4DZPZJZJFYFCVVOESTS5RL", "/Bancroft_Blanket_Work_Order_CC.docx"),
    "Bancroft_Work_Order": ("01D4QOAQNP7BVCELA6XNBLX47T6UEI5HHZ", "/Bancroft_Work_Order_CC.docx"),
    "Bancroft_Work_Order_Amendment": ("01D4QOAQMCUHBSEV3EGVALJBGUW3JERB2S", "/Bancroft_Work_Order_Amendment_CC.docx"),
    "Decades_Work_Order": ("01D4QOAQJ75ICUOWCDNVFK2BERZRUR3OJY", "/Decades_Work_Order_CC.docx"),
    "Decades_Work_Order_Amendment": ("01D4QOAQMG45IQ6JGU35AIINJE2UKKO4IY", "/Decades_Work_Order_Amendment_CC.docx"),
    "Decades_Vendor_MSA": ("01D4QOAQL5QIW7GR3JKZDYHEOTAWUOJXGH", "/Decades_Vendor_MSA_CC.docx"),
    "Decades_Exhibit_C_Fee_Schedule": ("01D4QOAQOKEOJRSQFBTFGIVHZRZ2Z6PD52", "/Decades_Exhibit_C_Fee_Schedule_CC.docx"),
    "Decades_Exhibit_A_Basic_A": ("01D4QOAQO2OPINWWRIWBF2EAE5AOUSFHWT", "/Decades_Exhibit_A_Basic_A_CC.docx"),
    # SKIP Decades_Exhibit_A_Optimized_C — inactive, no _CC version, original has no content controls
    "Decades_Exhibit_A_Concierge_B": ("01D4QOAQKHWLSIYNL57VHJIX4Z7QKNCZJV", "/Decades_Exhibit_A_Concierge_B_CC.docx"),
    "Decades_Exhibit_B_Location_List": ("01D4QOAQPYLUXEL5PYOZCKVPDBJGD4R3DJ", "/Decades_Exhibit_B_Location_List_CC.docx"),
    "Decades_Exhibit_D_Insurance": ("01D4QOAQIAMC6RCMOQ45EZ4WMLFPGVTCAB", "/Decades_Exhibit_D_Insurance_CC.docx"),
    "Bancroft_Exhibit_A_Basic_A": ("01D4QOAQMBIYKHGAUCYFG2XWW3M23EKUCF", "/Bancroft_Exhibit_A_Basic_A_CC.docx"),
    "Bancroft_Exhibit_A_Concierge_B": ("01D4QOAQK6GFYXPCW65JD3JZXR6GNCUEIT", "/Bancroft_Exhibit_A_Concierge_B_CC.docx"),
    "Bancroft_Exhibit_A_Optimized_C": ("01D4QOAQLZAOVWLRLJE5HK67SLFOOJSKTG", "/Bancroft_Exhibit_A_Optimized_C_CC.docx"),
}

STANDARD_HOST = {
    "apiId": "/providers/Microsoft.PowerApps/apis/shared_wordonlinebusiness",
    "operationId": "CreateFileItem",
    "connectionName": "shared_wordonlinebusiness",
}

SOURCE = "sites/decadesconstructiongroup.sharepoint.com,59956094-d818-4896-868e-4ef6cfc77ab3,70178d3c-5878-48ab-a340-5329e696c3e9"
DRIVE = "b!lGCVWRjYlkiGjk72z8d6szyNF3B4WKtIo0BTKeaWw-k0gmQTkZA9QKdMLo-aANXH"

updated = 0
for case_key, case_obj in cases.items():
    case_value = case_obj.get("case", "")
    if case_value not in ITEM_MAP:
        print(f"  WARN: no mapping for case '{case_value}' (key: {case_key})")
        continue

    item_id, display_path = ITEM_MAP[case_value]

    for action_name, action in case_obj.get("actions", {}).items():
        if not action_name.startswith("Populate_"):
            continue

        # Use designer format: item ID as file, metadata for display
        action["type"] = "OpenApiConnection"
        action["inputs"] = {
            "parameters": {
                "source": SOURCE,
                "drive": DRIVE,
                "file": item_id,
            },
            "host": STANDARD_HOST,
        }
        action["metadata"] = {
            item_id: display_path
        }

        print(f"  OK: {case_key} -> {item_id} ({display_path})")
        updated += 1

print(f"\nUpdated {updated} Populate actions")

with open("C:/dcfg/docs/templates/_flow_v2_updated.json", "w", encoding="utf-8") as f:
    json.dump(flow, f, ensure_ascii=False)

print("Saved to _flow_v2_updated.json")
