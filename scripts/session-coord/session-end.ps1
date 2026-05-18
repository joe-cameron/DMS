# scripts/session-coord/session-end.ps1
# SessionEnd hook — runs when Claude Code ends a session.
# Reads JSON from stdin (event payload — content ignored).
# Outputs nothing to stdout (SessionEnd is silent).
#
# On any error: exit 0 silently (never interrupt session end).

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

try {
    # Drain stdin
    $null = $input | Out-String

    # Load libraries
    . "$PSScriptRoot/lib/dataverse-auth.ps1"
    . "$PSScriptRoot/lib/session-ops.ps1"
    . "$PSScriptRoot/lib/lock-ops.ps1"

    Initialize-DataverseAuth

    # -----------------------------------------------------------------------
    # 1. Read session ID and log ID from session file
    # -----------------------------------------------------------------------
    $sessionId = Get-CurrentSessionId
    $logId     = Get-CurrentSessionLogId

    if (-not $sessionId) {
        # No session to close
        exit 0
    }

    # -----------------------------------------------------------------------
    # 2. Release all locks held by this session
    # -----------------------------------------------------------------------
    try { Release-AllSessionLocks } catch {}

    # -----------------------------------------------------------------------
    # 3. Snapshot git state
    # -----------------------------------------------------------------------
    $gitBranch   = ''
    $gitStatusRaw = ''
    $gitDiffStat  = ''
    try {
        $gitBranch    = (git -C C:/dcfg branch --show-current 2>&1) -join ''
        $rawStatus    = git -C C:/dcfg status --porcelain 2>&1
        $gitStatusRaw = ($rawStatus -join "`n").Trim()
        $rawDiff      = git -C C:/dcfg diff --stat 2>&1
        $gitDiffStat  = ($rawDiff -join "`n").Trim()
    } catch {}

    # -----------------------------------------------------------------------
    # 4. Determine files touched (compare start git status vs now)
    # -----------------------------------------------------------------------
    $startGitStatus = ''
    $filesTouched   = @()
    try {
        $sessionPath = Join-Path $env:LOCALAPPDATA 'dcfg-session\current-session.json'
        if (Test-Path $sessionPath) {
            $sessionObj    = Get-Content $sessionPath -Raw | ConvertFrom-Json
            $startGitStatus = $sessionObj.gitStatus
        }
    } catch {}

    try {
        # Extract filenames from porcelain git status (columns 4+ after 2-char status code + space)
        $parseStatus = {
            param([string]$statusText)
            if ([string]::IsNullOrWhiteSpace($statusText)) { return @() }
            $files = @()
            foreach ($line in ($statusText -split '\r?\n')) {
                $line = $line.Trim()
                if ($line.Length -gt 3) { $files += $line.Substring(3).Trim() }
            }
            return $files
        }
        $startFiles = & $parseStatus $startGitStatus
        $endFiles   = & $parseStatus $gitStatusRaw
        # Union: files that appear in either state
        $filesTouched = ($startFiles + $endFiles | Sort-Object -Unique)
    } catch {}

    # -----------------------------------------------------------------------
    # 4b. Read session journal entries
    # -----------------------------------------------------------------------
    $journalFile    = Join-Path $env:LOCALAPPDATA 'dcfg-session\journal.jsonl'
    $journalEntries = @()
    if (Test-Path $journalFile) {
        try {
            $lines = Get-Content $journalFile -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }
            foreach ($line in $lines) {
                $journalEntries += ($line | ConvertFrom-Json)
            }
        } catch {}
    }

    # -----------------------------------------------------------------------
    # 5. AI compress summary (if ANTHROPIC_API_KEY is available)
    # -----------------------------------------------------------------------
    $summary = ''
    $apiKey  = $env:ANTHROPIC_API_KEY

    # Build journal context for Haiku
    $journalText = ''
    if ($journalEntries.Count -gt 0) {
        $journalText = "`nWork completed this session:`n"
        foreach ($je in $journalEntries) {
            $journalText += "- [$($je.cat)] $($je.item)`n"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        try {
            $promptText = @"
Summarize this Claude Code session in 2-3 sentences. Be concise and factual.

Git branch: $gitBranch
Files changed (git status):
$gitStatusRaw

Git diff stat:
$gitDiffStat
$journalText
Provide only the summary text, no preamble.
"@
            $apiBody = @{
                model      = 'claude-haiku-4-5-20251001'
                max_tokens = 300
                messages   = @(
                    @{ role = 'user'; content = $promptText }
                )
            } | ConvertTo-Json -Depth 10 -Compress
            $apiBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($apiBody)

            $apiHeaders = @{
                'x-api-key'         = $apiKey
                'anthropic-version' = '2023-06-01'
                'content-type'      = 'application/json'
            }
            $apiResponse = Invoke-RestMethod `
                -Uri 'https://api.anthropic.com/v1/messages' `
                -Method POST `
                -Headers $apiHeaders `
                -Body $apiBodyBytes `
                -TimeoutSec 20 `
                -ErrorAction Stop
            $summary = $apiResponse.content[0].text.Trim()
        } catch {
            # Fall through to template summary
            $summary = ''
        }
    }

    # -----------------------------------------------------------------------
    # 6. Fallback template summary
    # -----------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $fileCount  = if ($filesTouched.Count -gt 0) { $filesTouched.Count } else { 0 }
        $cleanLabel = if ([string]::IsNullOrWhiteSpace($gitStatusRaw)) { 'clean' } else { 'uncommitted changes' }
        $summary    = "Session on branch '$gitBranch'. $fileCount file(s) touched. Git status: $cleanLabel."
    }

    # -----------------------------------------------------------------------
    # 7. Update session log row
    # -----------------------------------------------------------------------
    if ($logId) {
        $nowUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $fieldsToUpdate = @{
            dcfg_ended_at             = $nowUtc
            dcfg_summary              = $summary
            dcfg_active_branch        = $gitBranch
            dcfg_uncommitted_changes  = $gitStatusRaw
            dcfg_git_diff_stat        = $gitDiffStat
            dcfg_files_touched        = ($filesTouched | ConvertTo-Json -Compress)
        }
        try { Update-SessionLogEntry -LogId $logId -Fields $fieldsToUpdate } catch {}
    }

    # -----------------------------------------------------------------------
    # 8. Clear work item assignments for this session
    # -----------------------------------------------------------------------
    try { Clear-SessionAssignments -SessionId $sessionId } catch {}

    # -----------------------------------------------------------------------
    # 8b. Append journal entries to dashboard/worklog.json
    # -----------------------------------------------------------------------
    if ($journalEntries.Count -gt 0) {
        try {
            $worklogPath = 'C:/dcfg/dashboard/worklog.json'
            $worklog = @()
            if (Test-Path $worklogPath) {
                $worklog = Get-Content $worklogPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }

            $sessionDate = (Get-Date).ToString('yyyy-MM-dd')
            $newEntries  = @()
            foreach ($je in $journalEntries) {
                $newEntries += @{ cat = $je.cat; item = $je.item; status = 'Done' }
            }

            # Check if a session block for today already exists
            $existingBlock = $worklog | Where-Object { $_.session -eq $sessionDate }
            if ($existingBlock) {
                # Append to existing block
                $merged = @($existingBlock.entries) + $newEntries
                $existingBlock.entries = $merged
            } else {
                $worklog += @{ session = $sessionDate; entries = $newEntries }
            }

            $worklog | ConvertTo-Json -Depth 5 | Set-Content -Path $worklogPath -Encoding UTF8
        } catch {}
    }

    # -----------------------------------------------------------------------
    # 8c. Write session record to Dataverse brain (dcfg_knowledge) in PROD
    #     Brain table only exists in Prod. Uses dedicated auth, not active env.
    # -----------------------------------------------------------------------
    try {
        $sessionDate = (Get-Date).ToString('yyyy-MM-dd')
        $brainTitle  = "Session $sessionDate`: $summary"
        if ($brainTitle.Length -gt 450) { $brainTitle = $brainTitle.Substring(0, 447) + '...' }

        $brainBody = @{
            sessionId     = $sessionId
            date          = $sessionDate
            branch        = $gitBranch
            summary       = $summary
            journal       = $journalEntries
            filesTouched  = $filesTouched
        } | ConvertTo-Json -Depth 5 -Compress

        $brainRecord = @{
            dcfg_title       = $brainTitle
            dcfg_name        = "session-$sessionId"
            dcfg_body         = $brainBody
            dcfg_kind         = 100000000
            dcfg_active_flag  = $true
        }

        # Get Prod token directly (brain lives in Prod only)
        $prodOrgUrl = 'https://org06f5de0b.crm.dynamics.com'
        $prodToken  = (pac auth create-token --environment $prodOrgUrl 2>&1) -join ''
        $prodToken  = $prodToken.Trim()
        if ($prodToken -and $prodToken.Length -gt 50) {
            $prodHeaders = @{
                'Authorization'   = "Bearer $prodToken"
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
                'Accept'           = 'application/json'
                'Content-Type'     = 'application/json'
            }
            $prodUri   = "$prodOrgUrl/api/data/v9.2/dcfg_knowledges"
            $jsonBody  = $brainRecord | ConvertTo-Json -Depth 10 -Compress
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
            Invoke-RestMethod -Uri $prodUri -Method POST -Headers $prodHeaders -Body $bodyBytes -ErrorAction Stop | Out-Null
        }
    } catch {}

    # -----------------------------------------------------------------------
    # 9. Generate markdown handoff
    # -----------------------------------------------------------------------
    try {
        $handoffDate = (Get-Date).ToString('yyyy-MM-dd')
        $handoffPath = "C:/dcfg/docs/handoff-session-$handoffDate.md"

        $fileList = if ($filesTouched.Count -gt 0) { ($filesTouched | ForEach-Object { "- $_" }) -join "`n" } else { '- (none)' }
        $handoffContent = @"
# Session Handoff — $handoffDate

## Session
- **ID:** $sessionId
- **Branch:** $gitBranch
- **Ended:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC

## Summary
$summary

## Files Touched
$fileList

## Git Status (end of session)
``````
$gitStatusRaw
``````

## Git Diff Stat
``````
$gitDiffStat
``````
"@
        Set-Content -Path $handoffPath -Value $handoffContent -Encoding UTF8
    } catch {}

    # -----------------------------------------------------------------------
    # 10. Kill heartbeat process
    # -----------------------------------------------------------------------
    try {
        # Find pwsh processes running heartbeat.ps1 with our session ID
        $heartbeatProcs = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe' OR Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'heartbeat\.ps1' -and $_.CommandLine -match [regex]::Escape($sessionId) }

        foreach ($proc in $heartbeatProcs) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    } catch {}

} catch {
    # Silent — never interrupt session end
}

exit 0
