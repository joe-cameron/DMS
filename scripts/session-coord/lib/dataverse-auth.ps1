# scripts/session-coord/lib/dataverse-auth.ps1
# Shared Dataverse auth library for Session Coordinator scripts.
# Dot-source this file, then call Initialize-DataverseAuth before making API calls.
#
# Usage:
#   . C:/dcfg/scripts/session-coord/lib/dataverse-auth.ps1
#   Initialize-DataverseAuth
#   $result = Invoke-DataverseGet 'WhoAmI'

$script:OrgUrl  = $null
$script:BaseUri = $null

# ---------------------------------------------------------------------------
# Get-ActiveOrgUrl
# Parses 'pac auth list' output and returns the org URL for the active (*) row.
# ---------------------------------------------------------------------------
function Get-ActiveOrgUrl {
    $lines = pac auth list 2>&1
    foreach ($line in $lines) {
        # Active row has '*' in the second column (Active column)
        if ($line -match '^\[(\d+)\]\s+\*\s+.*?(https://\S+\.crm\.dynamics\.com/)') {
            return $Matches[2].TrimEnd('/')
        }
    }
    throw "[dataverse-auth] Could not find active (*) environment in 'pac auth list'. Run 'pac auth select --index N' first."
}

# ---------------------------------------------------------------------------
# Initialize-DataverseAuth
# Sets script-scoped $OrgUrl and $BaseUri from the active pac auth profile.
# Call once per script before any API operations.
# ---------------------------------------------------------------------------
function Initialize-DataverseAuth {
    $script:OrgUrl  = Get-ActiveOrgUrl
    $script:BaseUri = $script:OrgUrl + '/api/data/v9.2'
    Write-Verbose "[dataverse-auth] Initialized: OrgUrl=$($script:OrgUrl)"
}

# ---------------------------------------------------------------------------
# Get-DataverseToken
# Returns a bearer token string for the active org URL.
# Acquires a fresh token each call — no caching (tokens expire in ~1h).
# ---------------------------------------------------------------------------
function Get-DataverseToken {
    if (-not $script:OrgUrl) { Initialize-DataverseAuth }
    $audience    = $script:OrgUrl + '/'
    $secureToken = (Get-AzAccessToken -ResourceUrl $audience -AsSecureString -ErrorAction Stop).Token
    return [System.Net.NetworkCredential]::new('', $secureToken).Password
}

# ---------------------------------------------------------------------------
# Get-DataverseHeaders
# Returns a hashtable of HTTP headers for Dataverse Web API calls.
# Includes Authorization, OData negotiation, Content-Type, and solution name.
# ---------------------------------------------------------------------------
function Get-DataverseHeaders {
    $token = Get-DataverseToken
    return @{
        'Authorization'                = "Bearer $token"
        'Accept'                       = 'application/json'
        'OData-MaxVersion'             = '4.0'
        'OData-Version'                = '4.0'
        'Content-Type'                 = 'application/json; charset=utf-8'
        'MSCRM.SolutionUniqueName'     = 'DCFGSystemTest'
    }
}

# ---------------------------------------------------------------------------
# Invoke-DataverseGet
# GET a relative path under the Dataverse Web API base URI.
# Returns the parsed response object.
#
# Example: Invoke-DataverseGet 'WhoAmI'
#          Invoke-DataverseGet 'accounts?$top=1'
# ---------------------------------------------------------------------------
function Invoke-DataverseGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $uri     = "$($script:BaseUri)/$RelativePath"
    $headers = Get-DataverseHeaders
    try {
        return Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
    } catch {
        $body = $_.ErrorDetails.Message
        Write-Error "[dataverse-auth] GET $uri failed: $($_.Exception.Message)`nBody: $body"
        throw
    }
}

# ---------------------------------------------------------------------------
# Invoke-DataversePost
# POST to a relative path under the Dataverse Web API base URI.
# Body is a hashtable — serialized to JSON internally.
# Returns the parsed response (or $null for 204 No Content).
#
# Example: Invoke-DataversePost 'accounts' @{ name = 'Test' }
# ---------------------------------------------------------------------------
function Invoke-DataversePost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][hashtable]$Body
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $uri     = "$($script:BaseUri)/$RelativePath"
    $headers = Get-DataverseHeaders
    $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    try {
        return Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $bytes -ErrorAction Stop
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $body   = $_.ErrorDetails.Message
        Write-Error "[dataverse-auth] POST $uri failed (HTTP $status): $($_.Exception.Message)`nBody: $body"
        throw
    }
}

# ---------------------------------------------------------------------------
# Invoke-DataversePatch
# PATCH a relative path under the Dataverse Web API base URI.
# Body is a hashtable — serialized to JSON internally.
# Optional ETag for optimistic concurrency (If-Match header).
# Returns $null (PATCH returns 204 No Content on success).
#
# Example: Invoke-DataversePatch 'accounts(guid)' @{ name = 'Updated' }
# ---------------------------------------------------------------------------
function Invoke-DataversePatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][hashtable]$Body,
        [string]$ETag = $null
    )
    if (-not $script:BaseUri) { Initialize-DataverseAuth }
    $uri     = "$($script:BaseUri)/$RelativePath"
    $headers = Get-DataverseHeaders
    if ($ETag) { $headers['If-Match'] = $ETag }
    $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    try {
        Invoke-RestMethod -Uri $uri -Method PATCH -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null
        return $null
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $body   = $_.ErrorDetails.Message
        Write-Error "[dataverse-auth] PATCH $uri failed (HTTP $status): $($_.Exception.Message)`nBody: $body"
        throw
    }
}
