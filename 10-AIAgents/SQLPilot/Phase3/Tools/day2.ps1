<#
.SYNOPSIS
    SQLPilot - Day-2 / migration validation tool.

.DESCRIPTION
    Provides Invoke-RealValidateDatabase: runs DBCC CHECKDB across all user
    databases on a target SQL Server instance (the Azure VM by default).
    Returns a structured per-database result with pass/fail status, error
    counts, and elapsed time.

    This is the "real Day-2" task from Stage 3 of the agent flow. Microsoft
    recommends DBCC CHECKDB after any restore (and weekly thereafter) - we
    run it post-restore as the final migration sub-step.

    Skips system databases (master, model, msdb, tempdb) - those are baked
    into the VM image and don't move with a user migration.

.PARAMETER Target
    Connection target. Defaults to terraform output (public_ip_address).
    Pass an IP/hostname to override.

.PARAMETER Database
    Optional single-DB scope. If omitted, runs against ALL user databases
    on the target.

.NOTES
    Author : Kale
    Pattern: mirrors tools/restore.ps1 - agent.ps1 dot-sources this file at
             startup; if loaded, Tool-ValidateDatabase calls
             Invoke-RealValidateDatabase. If this file is missing, the agent
             falls back to a stub.
#>

# ---------------------------------------------------------------------------
# Reuse the coordinate resolver from restore.ps1 if it's already loaded; if
# not, we re-read terraform output ourselves. Keeps the two tools loosely
# coupled (you could run either alone) without duplicating the read on every
# call when both are loaded.
# ---------------------------------------------------------------------------
$script:Day2Coords = $null

function Initialize-Day2Coords {
    [CmdletBinding()]
    param ([string] $TerraformDir)

    # Locate the Terraform module. Detect by *.tf files (not .terraform marker).
    if (-not $TerraformDir) {
        $candidates = @()
        if ($script:ScriptRoot) {
            $candidates += (Join-Path $script:ScriptRoot 'Terraform')
            $candidates += $script:ScriptRoot
        }
        $candidates += (Get-Location).Path
        foreach ($c in $candidates) {
            if ($c -and (Test-Path $c)) {
                $tf = Get-ChildItem -Path $c -Filter '*.tf' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($tf) {
                    $TerraformDir = $c
                    break
                }
            }
        }
    }
    if (-not $TerraformDir -or -not (Test-Path $TerraformDir)) {
        throw "Could not locate the SQLPilot Terraform directory (looked for *.tf files). Pass -TerraformDir explicitly."
    }

    $tfJson = & terraform -chdir="$TerraformDir" output -json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tfJson) {
        throw "terraform output -json failed in '$TerraformDir'. Has terraform apply been run?"
    }
    $tf = $tfJson | ConvertFrom-Json

    $publicIp  = $tf.public_ip_address.value
    $adminUser = $tf.admin_username.value
    if (-not $publicIp) {
        throw "terraform output missing public_ip_address. Re-run terraform apply."
    }

    # Read admin password from tfvars - same pattern as restore.ps1.
    $tfvarsPath = Join-Path $TerraformDir 'terraform.tfvars'
    if (-not (Test-Path $tfvarsPath)) {
        throw "terraform.tfvars not found at $tfvarsPath."
    }
    $tfvarsText = Get-Content -Path $tfvarsPath -Raw
    $pwMatch = [regex]::Match($tfvarsText, 'admin_password\s*=\s*"([^"]+)"')
    if (-not $pwMatch.Success) {
        throw "admin_password not found in $tfvarsPath."
    }
    $adminPassword = $pwMatch.Groups[1].Value

    $script:Day2Coords = [PSCustomObject]@{
        PublicIp      = $publicIp
        AdminUser     = $adminUser
        AdminPassword = $adminPassword
    }
}


function Invoke-RealValidateDatabase {
    [CmdletBinding()]
    param (
        [string] $Target,
        [string] $Database     # optional - omit to run against all user DBs
    )

    $started = Get-Date

    # Lazy-load coordinates.
    if (-not $script:Day2Coords) {
        Initialize-Day2Coords
    }
    $coords = $script:Day2Coords

    # If Target wasn't explicitly passed, use the one from terraform.
    if (-not $Target) {
        $Target = $coords.PublicIp
    }

    # Auth setup - SQL auth as sqlpilotadmin.
    $securePw = ConvertTo-SecureString $coords.AdminPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($coords.AdminUser, $securePw)
    $commonArgs = @{
        ServerInstance         = $Target
        Credential             = $cred
        TrustServerCertificate = $true
        Encrypt                = 'Optional'
        QueryTimeout           = 3600
        ConnectionTimeout      = 30
        ErrorAction            = 'Stop'
    }

    # Discover which DBs to check.
    if ($Database) {
        $dbList = @($Database)
    } else {
        # Skip system DBs - they're per-instance, not part of the migration.
        $listArgs = $commonArgs.Clone()
        $listArgs['Query']    = "SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE' ORDER BY name;"
        $listArgs['OutputAs'] = 'DataTables'
        $listResult = Invoke-Sqlcmd @listArgs
        $rows = if ($listResult -is [System.Data.DataTable]) { @($listResult) }
                elseif ($null -ne $listResult) { @($listResult.Rows) }
                else { @() }
        $dbList = @($rows | ForEach-Object { "$($_['name'])" })
    }

    if ($dbList.Count -eq 0) {
        return @{
            status            = 'ok'
            mock              = $false
            target            = $Target
            databases_checked = 0
            all_passed        = $true
            note              = 'No user databases found on target. Nothing to validate.'
            elapsed_seconds   = [int]((Get-Date) - $started).TotalSeconds
        }
    }

    # Run DBCC CHECKDB per database. We do them sequentially - CHECKDB is I/O
    # heavy and parallel runs would just thrash the disk. For an 8 MB demo DB
    # this is sub-second; for real estates it scales linearly with DB size.
    $results = @()
    $totalErrors = 0

    foreach ($db in $dbList) {
        Write-Host "[day2] DBCC CHECKDB [$db] on $Target..." -ForegroundColor DarkGray
        $dbStart = Get-Date
        $dbResult = [ordered]@{
            database        = $db
            passed          = $true
            allocation_errors = 0
            consistency_errors = 0
            error_messages    = @()
            elapsed_seconds   = 0
        }

        # DBCC CHECKDB output goes to messages, not result set. We use
        # -Verbose to capture them, then count "Msg" / "error" patterns.
        #
        # WITH NO_INFOMSGS suppresses the per-table "Service: 0 rows; X
        # pages" output - we only want errors. ALL_ERRORMSGS shows every
        # error rather than stopping at the first.
        $checkArgs = $commonArgs.Clone()
        $checkArgs['Database'] = $db
        $checkArgs['Query']    = "DBCC CHECKDB(N'$($db -replace "'", "''")') WITH NO_INFOMSGS, ALL_ERRORMSGS;"

        try {
            # Invoke-Sqlcmd writes informational/error messages to the
            # Verbose stream. Capture by routing 4>&1 (verbose to success).
            $output = Invoke-Sqlcmd @checkArgs -Verbose 4>&1
            $errorLines = $output | Where-Object {
                $_ -match 'Msg \d+' -or $_ -match 'Errors found' -or $_ -match 'consistency error'
            }
            $dbResult.error_messages = @($errorLines | ForEach-Object { "$_" })

            if ($dbResult.error_messages.Count -gt 0) {
                $dbResult.passed = $false
                # Crude classification: allocation vs consistency.
                $dbResult.allocation_errors  = @($errorLines | Where-Object { $_ -match 'allocation' }).Count
                $dbResult.consistency_errors = @($errorLines | Where-Object { $_ -match 'consistency' }).Count
                $totalErrors += $dbResult.error_messages.Count
            }
        } catch {
            $dbResult.passed = $false
            $dbResult.error_messages = @("CHECKDB failed to execute: $($_.Exception.Message)")
            $totalErrors++
        }

        $dbResult.elapsed_seconds = [int]((Get-Date) - $dbStart).TotalSeconds
        $results += $dbResult
    }

    $allPassed = $totalErrors -eq 0

    return @{
        status            = 'ok'
        mock              = $false
        target            = $Target
        databases_checked = $dbList.Count
        all_passed        = $allPassed
        total_errors      = $totalErrors
        results           = $results
        elapsed_seconds   = [int]((Get-Date) - $started).TotalSeconds
        method            = 'DBCC CHECKDB WITH NO_INFOMSGS, ALL_ERRORMSGS'
        method_rationale  = 'Microsoft-recommended page-level integrity check after restore. Run weekly thereafter as part of normal maintenance.'
    }
}
