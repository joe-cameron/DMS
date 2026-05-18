# brain-warmup.ps1 — Query Prod brain for recent activity (last N days)
# Used by boot sequence. Outputs one line per knowledge row.
# Usage: pwsh -NoProfile -File brain-warmup.ps1 [-Days 7]

param([int]$Days = 7)

try {
    $token = (Get-AzAccessToken -ResourceUrl 'https://org06f5de0b.crm.dynamics.com' -AsSecureString).Token |
        ConvertFrom-SecureString -AsPlainText
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $since = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $url = "https://org06f5de0b.crm.dynamics.com/api/data/v9.2/dcfg_knowledges" +
        "?`$filter=createdon ge $since" +
        "&`$select=dcfg_name,dcfg_title,dcfg_kind,createdon" +
        "&`$orderby=createdon desc" +
        "&`$top=25"
    $resp = Invoke-RestMethod $url -Headers $headers
    if ($resp.value.Count -eq 0) {
        Write-Host "No brain entries in the last $Days days. Journal may have lapsed."
    } else {
        Write-Host "$($resp.value.Count) brain entries in the last $Days days:"
        foreach ($row in $resp.value) {
            $date = ([datetime]$row.createdon).ToString('MM-dd')
            $label = if ($row.dcfg_title) { $row.dcfg_title } elseif ($row.dcfg_name) { $row.dcfg_name } else { '(untitled)' }
            Write-Host "  $date $label"
        }
    }
} catch {
    Write-Host "Brain warmup failed: $($_.Exception.Message)"
    Write-Host "(Token may be expired - run 'az login' to refresh)"
}
