<#
.SYNOPSIS
    SQLPilot - Handoff document generator.

.DESCRIPTION
    Provides Invoke-RealGenerateHandoff: generates the migration handoff
    package — the document the DBA sends to the app team so they can
    repoint connection strings, request firewall changes, and sign off
    that the new server works.

    The handoff contains:
      - Source: the original server name and connection pattern
      - Target: new server FQDN/IP, port, auth mode
      - Connection strings (old struck through, new in mono-box)
      - Databases migrated (name, table count, row count, compatibility level)
      - Migration receipt (method, elapsed time, timestamp)
      - DBCC CHECKDB result (passed/failed, error count)
      - Required app-side changes (firewall, DNS, secrets)
      - Sign-off block (DBA name, timestamp, decision)

    Output is structured (hashtable). The UI renders it as a document; the
    "Copy as email" and "Download as PDF" buttons consume the same data
    in different formats.

.NOTES
    Author : Kale
    Pattern: pure data assembly - no Azure or SQL calls. All inputs come
             from prior tool runs (terraform output, restore result, day2
             result) plus the on-prem source descriptor.
#>


function Invoke-RealGenerateHandoff {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $Source,             # on-prem server name (e.g. 'Node5')
        [Parameter(Mandatory)] [string] $Database,           # migrated DB name
        [string] $TerraformDir,                              # path to Terraform module
        [hashtable] $RestoreResult,                          # result hashtable from Invoke-RealRestoreDatabase
        [hashtable] $ValidateResult,                         # result hashtable from Invoke-RealValidateDatabase
        [string] $DbaName = $env:USERNAME                    # who is signing off
    )

    $started = Get-Date

    # ---------------------------------------------------------------------
    # Locate Terraform dir, pull live outputs.
    # ---------------------------------------------------------------------
    if (-not $TerraformDir) {
        $candidates = @()
        if ($script:ScriptRoot) {
            $candidates += (Join-Path $script:ScriptRoot 'Terraform')
            $candidates += $script:ScriptRoot
        }
        $candidates += (Get-Location).Path
        foreach ($c in $candidates) {
            if ($c -and (Test-Path (Join-Path $c '.terraform'))) {
                $TerraformDir = $c
                break
            }
        }
    }
    if (-not $TerraformDir -or -not (Test-Path (Join-Path $TerraformDir '.terraform'))) {
        throw "Could not locate the SQLPilot Terraform directory. Pass -TerraformDir explicitly."
    }

    $tfJson = & terraform -chdir="$TerraformDir" output -json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tfJson) {
        throw "terraform output -json failed in '$TerraformDir'."
    }
    $tf = $tfJson | ConvertFrom-Json

    $publicIp     = $tf.public_ip_address.value
    $adminUser    = $tf.admin_username.value
    $rgName       = $tf.resource_group_name.value
    $deployment   = $tf.sqlpilot_deployment.value
    $vmName       = $deployment.vm_name
    $vmFqdn       = "$vmName.$($deployment.location).cloudapp.azure.com"

    # ---------------------------------------------------------------------
    # Compose the handoff package.
    # ---------------------------------------------------------------------
    $now = Get-Date

    # Connection strings - old uses Windows auth (typical on-prem), new uses
    # SQL auth (typical for app-tier connecting to Azure VM SQL).
    $connectionStringOld = "Server=$Source;Database=$Database;Integrated Security=True"
    $connectionStringNew = "Server=tcp:$publicIp,1433;Database=$Database;User Id=$adminUser;Encrypt=True"

    # Migration receipt - what got moved, how, when.
    $receipt = @{
        method           = if ($RestoreResult) { $RestoreResult.method } else { 'BACKUP TO URL / RESTORE FROM URL' }
        method_rationale = if ($RestoreResult) { $RestoreResult.method_rationale } else { $null }
        elapsed_seconds  = if ($RestoreResult) { $RestoreResult.elapsed_seconds } else { $null }
        rows_restored    = if ($RestoreResult) { $RestoreResult.rows_restored } else { $null }
        user_table_count = if ($RestoreResult) { $RestoreResult.user_table_count } else { $null }
        state            = if ($RestoreResult) { $RestoreResult.state } else { 'unknown' }
        backup_url       = if ($RestoreResult) { $RestoreResult.backup_url } else { $null }
        compatibility_level_note = 'Compatibility level preserved at source value (no upgrade). Re-test on target before requesting an upgrade.'
    }

    # Validation block - did CHECKDB pass?
    $validation = if ($ValidateResult) {
        @{
            ran               = $true
            all_passed        = $ValidateResult.all_passed
            databases_checked = $ValidateResult.databases_checked
            total_errors      = $ValidateResult.total_errors
            method            = $ValidateResult.method
            per_db_results    = $ValidateResult.results
        }
    } else {
        @{
            ran  = $false
            note = 'DBCC CHECKDB was not run as part of this handoff. Recommend running it before sign-off.'
        }
    }

    # App-side changes required.
    $appSideChanges = @(
        @{
            change   = 'Firewall'
            detail   = "App-tier hosts must be able to reach $publicIp on TCP/1433. Currently the NSG only allows the DBA's source IP."
            severity = 'required'
        }
        @{
            change   = 'Connection strings'
            detail   = "Replace the on-prem string with the new tcp string shown above. New string uses SQL auth, not Windows auth - app pool must be configured accordingly."
            severity = 'required'
        }
        @{
            change   = 'Encryption'
            detail   = "New connection requires Encrypt=True. App's data provider must trust the Azure VM's certificate or set TrustServerCertificate=True (NOT recommended for production)."
            severity = 'required'
        }
        @{
            change   = 'DNS (optional)'
            detail   = "If app config uses a friendly hostname, point it at $vmFqdn (Azure-provided FQDN) or set up a custom CNAME."
            severity = 'optional'
        }
        @{
            change   = 'Credential rotation (recommended)'
            detail   = "Sign-in is currently sqlpilotadmin (used during migration). For production, create per-app SQL logins with least-privilege and rotate the migration admin password."
            severity = 'recommended'
        }
    )

    # Sign-off block. UI fills the timestamp + decision when the DBA clicks.
    $signoff = @{
        dba_name      = $DbaName
        prepared_at   = $now.ToString('o')
        decision      = $null         # filled in on click
        decided_at    = $null
        decision_notes = $null
    }

    # Assemble.
    $package = [ordered]@{
        status           = 'ok'
        mock             = $false
        generated_at     = $now.ToString('o')
        source = @{
            server                 = $Source
            connection_string_old  = $connectionStringOld
        }
        target = @{
            server_name            = $vmName
            fqdn                   = $vmFqdn
            public_ip              = $publicIp
            port                   = 1433
            admin_user             = $adminUser
            resource_group         = $rgName
            location               = $deployment.location
            vm_size                = $deployment.vm_size
            connection_string_new  = $connectionStringNew
        }
        databases = @(
            @{
                name                  = $Database
                user_table_count      = $receipt.user_table_count
                rows_restored         = $receipt.rows_restored
                state                 = $receipt.state
            }
        )
        receipt          = $receipt
        validation       = $validation
        app_side_changes = $appSideChanges
        signoff          = $signoff
        elapsed_seconds  = [int]((Get-Date) - $started).TotalSeconds
    }

    return $package
}


# ---------------------------------------------------------------------------
# Helper: render the handoff package as a plain-text email body.
# UI calls this when the DBA hits "Copy as email".
# ---------------------------------------------------------------------------
function Format-HandoffAsEmail {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [hashtable] $Package)

    $p = $Package
    $now = $p.generated_at

    $lines = @()
    $lines += "Subject: $($p.databases[0].name) migration complete - please update connection strings"
    $lines += ""
    $lines += "Hi team,"
    $lines += ""
    $lines += "Database $($p.databases[0].name) has been migrated from $($p.source.server) to a new Azure SQL VM."
    $lines += "Please update your connection strings and verify functionality in your environment."
    $lines += ""
    $lines += "=== NEW CONNECTION ==="
    $lines += "  Server : $($p.target.fqdn)"
    $lines += "  IP     : $($p.target.public_ip)"
    $lines += "  Port   : $($p.target.port)"
    $lines += "  Auth   : SQL Authentication"
    $lines += ""
    $lines += "  Connection string:"
    $lines += "  $($p.target.connection_string_new)"
    $lines += ""
    $lines += "  Previous (deprecated):"
    $lines += "  $($p.source.connection_string_old)"
    $lines += ""
    $lines += "=== MIGRATION RECEIPT ==="
    $lines += "  Method   : $($p.receipt.method)"
    $lines += "  Duration : $($p.receipt.elapsed_seconds) seconds"
    $lines += "  Tables   : $($p.receipt.user_table_count) tables, $($p.receipt.rows_restored) rows"
    $lines += "  State    : $($p.receipt.state)"
    $lines += ""
    if ($p.validation.ran) {
        $verdict = if ($p.validation.all_passed) { 'Passed' } else { "Failed - $($p.validation.total_errors) errors" }
        $lines += "=== INTEGRITY CHECK ==="
        $lines += "  DBCC CHECKDB : $verdict"
        $lines += "  Databases    : $($p.validation.databases_checked)"
        $lines += ""
    }
    $lines += "=== REQUIRED CHANGES ON YOUR SIDE ==="
    foreach ($change in $p.app_side_changes) {
        if ($change.severity -eq 'required') {
            $lines += "  [REQUIRED] $($change.change)"
            $lines += "             $($change.detail)"
        }
    }
    $lines += ""
    $lines += "=== OPTIONAL / RECOMMENDED ==="
    foreach ($change in $p.app_side_changes) {
        if ($change.severity -ne 'required') {
            $lines += "  [$($change.severity.ToUpper())] $($change.change)"
            $lines += "             $($change.detail)"
        }
    }
    $lines += ""
    $lines += "Please reply confirming app-side cutover is complete, or flag any issues."
    $lines += ""
    $lines += "Thanks,"
    $lines += "$($p.signoff.dba_name)"
    $lines += "Generated $now"

    return ($lines -join "`r`n")
}
