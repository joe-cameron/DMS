<#
  Auto-Research: Compare working connector actions vs deployed DocGen actions.
  One variable at a time. Log everything.
#>

$ErrorActionPreference = "Stop"

$envs = @(
    @{ Name = "Test"; DvUrl = "https://org0c17e98d.crm.dynamics.com/"; DocGenWfId = "3d3d278d-7522-f111-8341-7ced8d709731"; ReferenceWfId = "542faeef-7522-f111-8341-7ced8d709173"; RefName = "flow_cert_upload" }
    @{ Name = "Prod"; DvUrl = "https://org06f5de0b.crm.dynamics.com/"; DocGenWfId = "f8e79440-d223-f111-8341-7ced8d7092ad"; ReferenceWfId = "f8e79440-d223-f111-8341-7ced8d7092ad"; RefName = "self (original actions)" }
)

foreach ($env in $envs) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  RESEARCH: $($env.Name)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $tokenObj = Get-AzAccessToken -ResourceUrl $env.DvUrl -AsSecureString
    $token = [System.Net.NetworkCredential]::new("", $tokenObj.Token).Password
    $h = @{
        Authorization = "Bearer $token"; Accept = "application/json"
        "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"
    }
    $api = "$($env.DvUrl)api/data/v9.2"

    # Read DocGen flow
    $docgen = Invoke-RestMethod -Uri "$api/workflows($($env.DocGenWfId))?`$select=clientdata" -Headers $h
    $dgCd = $docgen.clientdata | ConvertFrom-Json

    # Read reference flow (known working)
    if ($env.DocGenWfId -ne $env.ReferenceWfId) {
        $ref = Invoke-RestMethod -Uri "$api/workflows($($env.ReferenceWfId))?`$select=clientdata" -Headers $h
        $refCd = $ref.clientdata | ConvertFrom-Json
    }

    # === EXPERIMENT 1: Compare connectionReferences structure ===
    Write-Host "`n  [EXP 1] Connection References Structure" -ForegroundColor Yellow

    Write-Host "  DocGen connectionReferences:" -ForegroundColor White
    $dgCd.properties.connectionReferences | ConvertTo-Json -Depth 5

    if ($env.DocGenWfId -ne $env.ReferenceWfId) {
        Write-Host "`n  Reference ($($env.RefName)) connectionReferences:" -ForegroundColor White
        $refCd.properties.connectionReferences | ConvertTo-Json -Depth 5
    }

    # === EXPERIMENT 2: Compare a single Dataverse action side-by-side ===
    Write-Host "`n  [EXP 2] Side-by-Side Action Comparison" -ForegroundColor Yellow

    # Find first real connector action in DocGen
    $dgAction = $null
    $dgActionName = $null
    foreach ($a in $dgCd.properties.definition.actions.PSObject.Properties) {
        if ($a.Value.type -in @("ApiConnection", "OpenApiConnection")) {
            $dgAction = $a.Value
            $dgActionName = $a.Name
            break
        }
    }

    if ($dgAction) {
        Write-Host "  DocGen action: $dgActionName" -ForegroundColor White
        Write-Host "    type: $($dgAction.type)" -ForegroundColor DarkGray
        Write-Host "    inputs.host:" -ForegroundColor DarkGray
        $dgAction.inputs.host | ConvertTo-Json -Depth 5
        Write-Host "    inputs.parameters:" -ForegroundColor DarkGray
        $dgAction.inputs.parameters | ConvertTo-Json -Depth 5
        $hasAuth = $null -ne $dgAction.inputs.PSObject.Properties['authentication']
        Write-Host "    has authentication: $hasAuth" -ForegroundColor DarkGray
        if ($hasAuth) { Write-Host "    authentication: $($dgAction.inputs.authentication)" }
    }

    if ($env.DocGenWfId -ne $env.ReferenceWfId) {
        $refAction = $null
        $refActionName = $null
        foreach ($a in $refCd.properties.definition.actions.PSObject.Properties) {
            if ($a.Value.type -in @("ApiConnection", "OpenApiConnection")) {
                $refAction = $a.Value
                $refActionName = $a.Name
                break
            }
        }

        if ($refAction) {
            Write-Host "`n  Reference action: $refActionName" -ForegroundColor White
            Write-Host "    type: $($refAction.type)" -ForegroundColor DarkGray
            Write-Host "    inputs.host:" -ForegroundColor DarkGray
            $refAction.inputs.host | ConvertTo-Json -Depth 5
            Write-Host "    inputs.parameters:" -ForegroundColor DarkGray
            $refAction.inputs.parameters | ConvertTo-Json -Depth 5
            $hasAuth = $null -ne $refAction.inputs.PSObject.Properties['authentication']
            Write-Host "    has authentication: $hasAuth" -ForegroundColor DarkGray
            if ($hasAuth) { Write-Host "    authentication: $($refAction.inputs.authentication)" }
        }

        # === EXPERIMENT 3: Diff the two ===
        Write-Host "`n  [EXP 3] Differences" -ForegroundColor Yellow
        if ($dgAction -and $refAction) {
            # Type
            if ($dgAction.type -ne $refAction.type) {
                Write-Host "    TYPE MISMATCH: DocGen=$($dgAction.type) Ref=$($refAction.type)" -ForegroundColor Red
            } else {
                Write-Host "    type: MATCH ($($dgAction.type))" -ForegroundColor Green
            }

            # Host structure
            $dgHostJson = $dgAction.inputs.host | ConvertTo-Json -Depth 5 -Compress
            $refHostJson = $refAction.inputs.host | ConvertTo-Json -Depth 5 -Compress
            if ($dgHostJson -ne $refHostJson) {
                Write-Host "    HOST MISMATCH:" -ForegroundColor Red
                Write-Host "      DocGen: $dgHostJson" -ForegroundColor Red
                Write-Host "      Ref:    $refHostJson" -ForegroundColor Green
            } else {
                Write-Host "    host: MATCH" -ForegroundColor Green
            }

            # Auth
            $dgHasAuth = $null -ne $dgAction.inputs.PSObject.Properties['authentication']
            $refHasAuth = $null -ne $refAction.inputs.PSObject.Properties['authentication']
            if ($dgHasAuth -ne $refHasAuth) {
                Write-Host "    AUTH MISMATCH: DocGen=$dgHasAuth Ref=$refHasAuth" -ForegroundColor Red
            } else {
                Write-Host "    authentication: MATCH (present=$dgHasAuth)" -ForegroundColor Green
            }
        }
    }

    # === EXPERIMENT 4: Check if DocGen actions have operationId (Test may be missing) ===
    Write-Host "`n  [EXP 4] OperationId Check" -ForegroundColor Yellow
    $missingOps = @()
    foreach ($a in $dgCd.properties.definition.actions.PSObject.Properties) {
        $v = $a.Value
        if ($v.type -in @("ApiConnection", "OpenApiConnection")) {
            $opId = $v.inputs.host.operationId
            $apiId = $v.inputs.host.apiId
            if (-not $opId -and -not $v.inputs.host.connection) {
                # OpenApiConnection needs operationId
                $missingOps += $a.Name
            }
            if ($v.inputs.host.connection -and -not $v.inputs.path) {
                # ApiConnection needs either operationId or path
                # Actually ApiConnection uses method/path or parameters with operationId
            }
            $status = if ($opId) { "op=$opId" } else { "NO-OP" }
            Write-Host "    $($a.Name): $status" -ForegroundColor $(if ($opId -or $v.inputs.host.connection) { "DarkGray" } else { "Red" })
        }
    }

    # Also check inside conditions
    foreach ($a in $dgCd.properties.definition.actions.PSObject.Properties) {
        if ($a.Value.type -eq "If") {
            foreach ($inner in $a.Value.actions.PSObject.Properties) {
                $iv = $inner.Value
                if ($iv.type -in @("ApiConnection", "OpenApiConnection")) {
                    $opId = $iv.inputs.host.operationId
                    $status = if ($opId) { "op=$opId" } else { "NO-OP" }
                    Write-Host "    $($a.Name)/$($inner.Name): $status" -ForegroundColor $(if ($opId) { "DarkGray" } else { "Red" })
                }
            }
            if ($a.Value.else.actions) {
                foreach ($inner in $a.Value.else.actions.PSObject.Properties) {
                    $iv = $inner.Value
                    if ($iv.type -in @("ApiConnection", "OpenApiConnection")) {
                        $opId = $iv.inputs.host.operationId
                        $status = if ($opId) { "op=$opId" } else { "NO-OP" }
                        Write-Host "    $($a.Name)/else/$($inner.Name): $status" -ForegroundColor $(if ($opId) { "DarkGray" } else { "Red" })
                    }
                }
            }
        }
    }
}

Write-Host "`n=== RESEARCH COMPLETE ===" -ForegroundColor Cyan
