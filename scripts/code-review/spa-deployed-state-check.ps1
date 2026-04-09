<#
.SYNOPSIS
  Fetches each portal's main JS bundle and greps for the handoff Change 3/4
  $select clauses. Reports whether Test/Stage have the current SPA deployed.
.NOTES
  Read-only. No auth required for the bundle fetch (public asset). Uses
  Invoke-WebRequest, not curl (curl.exe is blocked).
#>

$ErrorActionPreference = 'Stop'
$outPath = 'C:\dcfg\docs\code-review-2026-04-09\spa-deployed-state.json'

$portals = @(
    @{ Name = 'Prod';  Base = 'https://dmms1.powerappsportals.com' },
    @{ Name = 'Test';  Base = 'https://dcfg.powerappsportals.com' },
    @{ Name = 'Stage'; Base = 'https://holding.powerappsportals.com' }
)

# Distinct string fragments unique to the handoff Changes 3/4
$signatures = @{
    'change-3-useTemplateFields-select' = '_dcfg_template_id_value,dcfg_field_order,dcfg_source_text'
    'change-4-templateDetail-select'    = 'dcfg_document_templateid,dcfg_name,dcfg_template_type,dcfg_notes,_dcfg_customer_id_value'
}

$result = @{ generatedAt = (Get-Date).ToUniversalTime().ToString('o'); portals = @{}; drift = @() }

foreach ($p in $portals) {
    Write-Host ""
    Write-Host "=== $($p.Name) ($($p.Base)) ===" -ForegroundColor Cyan

    # Fetch the portal index and find the main JS asset URL
    try {
        $html = (Invoke-WebRequest -Uri $p.Base -UseBasicParsing).Content
    } catch {
        Write-Host "  FAIL: index fetch: $($_.Exception.Message)" -ForegroundColor Red
        $result.portals[$p.Name] = @{ status = 'fetch-failed'; error = $_.Exception.Message }
        continue
    }

    # Find all <script src="...assets/....js"> entries - Vite output pattern
    $scriptMatches = [regex]::Matches($html, 'src="([^"]+?\.js)"')
    $jsUrls = @()
    foreach ($m in $scriptMatches) {
        $src = $m.Groups[1].Value
        if ($src -match '^https?://') {
            $jsUrls += $src
        } else {
            $jsUrls += "$($p.Base)$src"
        }
    }
    if ($jsUrls.Count -eq 0) {
        Write-Host "  FAIL: no script tags in index" -ForegroundColor Red
        $result.portals[$p.Name] = @{ status = 'no-scripts'; indexLength = $html.Length }
        continue
    }
    Write-Host "  Found $($jsUrls.Count) script URL(s)"

    # Fetch each and check each signature
    $portalResult = @{ status = 'ok'; scriptUrls = $jsUrls; signatures = @{} }
    foreach ($sigName in $signatures.Keys) {
        $needle = $signatures[$sigName]
        $found = $false
        foreach ($url in $jsUrls) {
            try {
                $body = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
                if ($body -match [regex]::Escape($needle)) { $found = $true; break }
            } catch {
                continue
            }
        }
        $portalResult.signatures[$sigName] = $found
        if ($found) {
            Write-Host "  OK   : $sigName present" -ForegroundColor Green
        } else {
            Write-Host "  DRIFT: $sigName NOT FOUND" -ForegroundColor Yellow
            $result.drift += @{ env = $p.Name; signature = $sigName; kind = 'spa-bundle-drift' }
        }
    }
    $result.portals[$p.Name] = $portalResult
}

$result | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding UTF8
Write-Host ""
Write-Host "SPA bundle drift count: $($result.drift.Count)"
Write-Host "Report: $outPath"
