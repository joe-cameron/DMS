# Export dcfg_knowledge brain to local JSON for offline/non-MCP AI access
. "C:/DCFG/PowerApps-Samples/dataverse/webapi/PS/Core.ps1"
Connect "https://org06f5de0b.crm.dynamics.com/"

$resp = Invoke-RestMethod -Uri "$baseURI/dcfg_knowledges?`$filter=dcfg_active_flag eq true&`$select=dcfg_knowledgeid,dcfg_name,dcfg_title,dcfg_body,dcfg_kind,dcfg_source_uri,dcfg_captured_on&`$orderby=dcfg_name asc&`$top=500" -Method Get -Headers $baseHeaders

$records = $resp.value | ForEach-Object {
    @{
        id = $_.dcfg_knowledgeid
        name = $_.dcfg_name
        title = $_.dcfg_title
        body = $_.dcfg_body
        kind = $_.dcfg_kind
        source = $_.dcfg_source_uri
        captured = $_.dcfg_captured_on
    }
}

$output = @{
    exported = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    count = $records.Count
    records = $records
} | ConvertTo-Json -Depth 5

$output | Set-Content "C:/DCFG/brain/knowledge-export.json" -Encoding UTF8
Write-Host "Exported $($records.Count) knowledge records to brain/knowledge-export.json" -ForegroundColor Green
