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


function Invoke-RealGenerateHandoffDcDc {
    <#
    .SYNOPSIS
        SQLPilot - DC->DC handoff document generator.
    .DESCRIPTION
        The DC->DC counterpart to Invoke-RealGenerateHandoff. A data-center-to-
        data-center migration has NO Azure VM, NO Terraform, NO public IP, and
        NO NSG firewall - the destination is just another SQL Server instance.
        So this function assembles a handoff package shaped for that reality:
          - Target is a named SQL Server instance (e.g. NODE2), not an Azure FQDN
          - Connection strings show BOTH Windows-auth and SQL-auth variants with
            a note that the right choice depends on the app's existing auth model
          - App-side changes are about internal DNS / connection repointing and
            (if relevant) cross-subnet firewall, not Azure NSG rules
          - Receipt, validation, and sign-off blocks mirror the Cloud package so
            the UI and the "Copy as email" formatter can consume either shape
    .NOTES
        Author : Kale. Pairs with Invoke-RealGenerateHandoff (cloud).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $Source,          # source server (e.g. 'NODE1')
        [Parameter(Mandatory)] [string]   $Destination,     # destination server (e.g. 'NODE2')
        [Parameter(Mandatory)] [string[]] $Databases,       # migrated DB name(s)
        [hashtable] $MigrateResult,                         # full DC->DC result hashtable (from the runner)
        [hashtable] $ValidateResult,                        # validate step result (or pulled from MigrateResult)
        [string]    $Engine = 'dbatools',
        [string]    $DbaName = $env:USERNAME
    )

    $started = Get-Date
    $now     = Get-Date

    $dbList = @($Databases)
    $primaryDb = if ($dbList.Count) { $dbList[0] } else { '(unknown)' }

    # Connection strings - DC->DC keeps the app inside the org's network, so
    # Windows (integrated) auth is the common case; SQL auth is the alternative
    # for apps that already use it. Show both; note that it depends.
    $connStrOld    = "Server=$Source;Database=$primaryDb;Integrated Security=True"
    $connStrWinNew = "Server=$Destination;Database=$primaryDb;Integrated Security=True"
    $connStrSqlNew = "Server=$Destination;Database=$primaryDb;User Id=<app_login>;Password=<password>;Encrypt=True;TrustServerCertificate=True"

    # Migration receipt - dig values out of the DC->DC result if present.
    $dbStep = $null; $valStep = $null
    if ($MigrateResult -and $MigrateResult.steps) {
        foreach ($s in $MigrateResult.steps) {
            if ($s.step -eq 'databases') { $dbStep = $s }
            if ($s.step -eq 'validate')  { $valStep = $s }
        }
    }
    if (-not $ValidateResult -and $valStep) {
        if (Get-Command ConvertTo-Hashtable -ErrorAction SilentlyContinue) {
            $ValidateResult = (ConvertTo-Hashtable $valStep.detail)
        } else {
            $ValidateResult = $valStep.detail
        }
    }

    $receipt = @{
        method           = if ($Engine -eq 'dbatools') { 'dbatools (Copy-DbaDatabase / backup-restore)' } else { 'Native T-SQL (BACKUP/RESTORE)' }
        engine           = $Engine
        elapsed_seconds  = if ($MigrateResult) { $MigrateResult.elapsed_seconds } else { $null }
        databases_migrated = $dbList.Count
        overall_status   = if ($MigrateResult) { $MigrateResult.status } else { 'unknown' }
        compatibility_level_note = 'Compatibility level preserved at source value (no upgrade). Re-test on target before requesting an upgrade.'
    }

    # Validation block.
    $validation = if ($ValidateResult) {
        @{
            ran               = $true
            all_passed        = $ValidateResult.all_passed
            databases_checked = $ValidateResult.databases_checked
            total_errors      = $ValidateResult.total_errors
            per_db_results    = $ValidateResult.results
        }
    } else {
        @{ ran=$false; note='DBCC CHECKDB result not available. Recommend running it on the destination before sign-off.' }
    }

    # App-side changes - DC->DC flavor (no Azure).
    $appSideChanges = @(
        @{
            change   = 'Connection strings'
            detail   = "Repoint app connection strings from '$Source' to '$Destination'. If the app uses Windows auth, use the integrated-security string. If it uses SQL auth, create a per-app SQL login on $Destination and use the SQL-auth string. The right choice depends on the app's current auth model."
            severity = 'required'
        }
        @{
            change   = 'DNS / alias (recommended)'
            detail   = "If the app connects via a hostname or SQL client alias rather than the raw server name, update it to point at $Destination. A CNAME or alias avoids having to touch every app config when the server name changes."
            severity = 'recommended'
        }
        @{
            change   = 'Cross-subnet firewall (if applicable)'
            detail   = "If $Destination is in a different subnet/VLAN than the app tier, confirm TCP/1433 (and the SQL Browser UDP/1434 if using named instances) is open between them. Intra-subnet moves usually need no change."
            severity = 'conditional'
        }
        @{
            change   = 'SQL logins / permissions'
            detail   = "SID-preserving logins were migrated, so existing DB users map automatically. Confirm any app service accounts can authenticate against $Destination and have the expected role membership."
            severity = 'required'
        }
        @{
            change   = 'Linked servers / cross-DB (if applicable)'
            detail   = "If migrated databases reference linked servers or other databases by server name, verify those references resolve from $Destination. Linked-server remote passwords are never migrated and must be re-entered."
            severity = 'conditional'
        }
    )

    $signoff = @{
        dba_name       = $DbaName
        prepared_at    = $now.ToString('o')
        decision       = $null
        decided_at     = $null
        decision_notes = $null
    }

    # Per-database detail.
    $dbDetail = @()
    foreach ($d in $dbList) {
        $migratedOk = $true
        if ($dbStep -and $dbStep.detail -and $dbStep.detail.migrated) {
            $migratedOk = (@($dbStep.detail.migrated) -contains $d) -or (@($dbStep.detail.migrated | ForEach-Object { "$($_.name)" }) -contains $d)
        }
        $dbDetail += @{ name=$d; migrated=$migratedOk }
    }

    $package = [ordered]@{
        status           = 'ok'
        mode             = 'dcdc'
        mock             = $false
        generated_at     = $now.ToString('o')
        source = @{
            server                = $Source
            connection_string_old = $connStrOld
        }
        target = @{
            server_name                    = $Destination
            port                           = 1433
            connection_string_new_windows  = $connStrWinNew
            connection_string_new_sql      = $connStrSqlNew
            auth_note                      = 'Use the Windows-auth string if the app currently uses integrated security; use the SQL-auth string (after creating a per-app login) otherwise.'
        }
        databases        = $dbDetail
        receipt          = $receipt
        validation       = $validation
        app_side_changes = $appSideChanges
        signoff          = $signoff
        elapsed_seconds  = [int]((Get-Date) - $started).TotalSeconds
    }

    return $package
}


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
    # Detect by *.tf files. The terraform tool runs `terraform init` before
    # this stage, so we can be confident the dir is initialized — but the
    # marker presence isn't our way of finding the dir, the .tf files are.
    # ---------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# Helper: render a DC->DC handoff package as a plain-text email body.
# Mirrors Format-HandoffAsEmail but for the DC->DC package shape (no Azure).
# ---------------------------------------------------------------------------
function Format-HandoffDcDcAsEmail {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [hashtable] $Package)

    $p = $Package
    $now = $p.generated_at
    $dbNames = (@($p.databases | ForEach-Object { $_.name }) -join ', ')

    $lines = @()
    $lines += "Subject: $dbNames migration complete ($($p.source.server) -> $($p.target.server_name)) - please update connection strings"
    $lines += ""
    $lines += "Hi team,"
    $lines += ""
    $lines += "The following database(s) have been migrated from $($p.source.server) to $($p.target.server_name):"
    $lines += "  $dbNames"
    $lines += ""
    $lines += "Please update your connection strings and verify functionality."
    $lines += ""
    $lines += "=== NEW CONNECTION ($($p.target.server_name)) ==="
    $lines += "  $($p.target.auth_note)"
    $lines += ""
    $lines += "  Windows auth:"
    $lines += "  $($p.target.connection_string_new_windows)"
    $lines += ""
    $lines += "  SQL auth:"
    $lines += "  $($p.target.connection_string_new_sql)"
    $lines += ""
    $lines += "  Previous (deprecated):"
    $lines += "  $($p.source.connection_string_old)"
    $lines += ""
    $lines += "=== MIGRATION RECEIPT ==="
    $lines += "  Method     : $($p.receipt.method)"
    $lines += "  Engine     : $($p.receipt.engine)"
    $lines += "  Databases  : $($p.receipt.databases_migrated)"
    $lines += "  Duration   : $($p.receipt.elapsed_seconds) seconds"
    $lines += "  Status     : $($p.receipt.overall_status)"
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
    $lines += "=== CONDITIONAL / RECOMMENDED ==="
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
