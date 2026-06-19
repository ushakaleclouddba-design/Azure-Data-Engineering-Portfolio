<#
.SYNOPSIS
    SQLPilot - SSIS package migration (dbatools only; native honestly declines).

.DESCRIPTION
    SSIS is the one step that CANNOT be done in pure T-SQL. The SSIS Catalog
    (SSISDB) is protected by a database master key that is itself encrypted by
    the source instance's Service Master Key; its catalog encryption cannot be
    extracted and re-established on another server with T-SQL. This is a SQL
    Server architecture fact, not a SQLPilot limitation.

      dbatools : Copy-DbaSsisPackage (msdb / file-system package store). NOTE:
                 even dbatools does not transparently move an SSISDB catalog -
                 that requires the documented manual master-key procedure.
      native   : NOT SUPPORTED. Returns a clear, honest message with the two
                 real options, rather than failing silently or pretending.

.NOTES
    Author : Kale. Honest-framing module - see SQLPilot Bible Appendix A.
#>

function Invoke-MigrateSsis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native'
    )
    $started = Get-Date
    $result  = [ordered]@{
        status='ok'; engine=$Engine; source=$Source; destination=$Destination
        supported=$false; migrated=@(); note=$null
    }

    if ($Engine -eq 'native') {
        $result.status   = 'skipped'
        $result.supported= $false
        $result.note     = "SSIS migration is NOT supported in native (T-SQL) mode. The SSISDB catalog's key hierarchy cannot be moved via T-SQL. Options: (1) use dbatools mode (Copy-DbaSsisCatalog, which migrates the SSISDB catalog), or (2) migrate the SSISDB catalog manually via Microsoft's documented procedure (back up SSISDB + back up its master key with a password, restore both on the destination, re-open the master key)."
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # dbatools: BUG-022 fix.
    # Modern dbatools (1.0+) replaced Copy-DbaSsisPackage with Copy-DbaSsisCatalog,
    # which migrates the SSISDB catalog DB (the modern store for SSIS). Legacy
    # msdb / file-system packages have NO dbatools cmdlet in current versions —
    # those need manual migration.
    try {
        $haveCatalog = Get-Command Copy-DbaSsisCatalog -ErrorAction SilentlyContinue
        $havePackage = Get-Command Copy-DbaSsisPackage -ErrorAction SilentlyContinue

        if (-not $haveCatalog -and -not $havePackage) {
            $result.status = 'skipped'
            $result.note   = 'No SSIS migration cmdlet available in this dbatools build (neither Copy-DbaSsisCatalog nor Copy-DbaSsisPackage). Manual migration required: see Microsoft docs for the SSISDB master-key procedure.'
            $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
            return $result
        }

        # Detect SSISDB on source — drives whether Catalog migration applies.
        $hasSsisdb = $false
        try {
            $r = Invoke-Sqlcmd -ServerInstance $Source -Query "SELECT 1 AS x FROM sys.databases WHERE name='SSISDB'" -TrustServerCertificate -Encrypt Optional -ErrorAction Stop
            $hasSsisdb = [bool]@($r).Count
        } catch {
            # If the probe fails, assume no SSISDB; the catalog migration will
            # fail explicitly if we're wrong and that's clearer than a silent skip.
        }

        if ($haveCatalog -and $hasSsisdb) {
            # BUG-035: before attempting the catalog copy, confirm the DESTINATION
            # can host SSISDB. dbatools cannot create the catalog (that needs the
            # Integration Services feature installed on the destination + CLR +
            # catalog.create_catalog). If the destination has no SSISDB, give an
            # honest, actionable message instead of letting Copy-DbaSsisCatalog
            # throw a generic error. (MS docs: the SQL installer does not create
            # the catalog; it must be created manually on an instance that has IS
            # installed.)
            $destHasSsisdb = $false
            try {
                $rd = Invoke-Sqlcmd -ServerInstance $Destination -Query "SELECT 1 AS x FROM sys.databases WHERE name='SSISDB'" -TrustServerCertificate -Encrypt Optional -ErrorAction Stop
                $destHasSsisdb = [bool]@($rd).Count
            } catch {
                # Probe failed; treat as 'unknown' and let the explicit check below
                # report the most likely cause.
            }
            if (-not $destHasSsisdb) {
                $result.status    = 'skipped'
                $result.supported = $false
                $result.note      = "Source has an SSISDB catalog, but the destination ($Destination) does not. dbatools (and SQLPilot) cannot create it: an SSISDB catalog requires the Integration Services feature installed on the destination, CLR enabled, and the catalog created (catalog.create_catalog). Set up SSISDB on $Destination first (SSMS > Integration Services Catalogs > Create Catalog, or Microsoft's documented procedure), then re-run. For small estates SSIS and the DB engine commonly share one server; for larger estates the catalog may live on a dedicated Integration Services instance."
                $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
                return $result
            }
            $cls = Copy-DbaSsisCatalog -Source $Source -Destination $Destination -ErrorAction Stop
            foreach ($p in @($cls)) { $result.migrated += @{ name="$($p.Name)"; status="$($p.Status)" } }
            $result.supported = $true
            $result.note = 'dbatools Copy-DbaSsisCatalog migrated the SSISDB catalog. Note: msdb/file-system stored packages are NOT supported by current dbatools — manual migration only.'
        } elseif ($havePackage) {
            $sp = Copy-DbaSsisPackage -Source $Source -Destination $Destination -ErrorAction Stop
            foreach ($p in @($sp)) { $result.migrated += @{ name="$($p.Name)"; status="$($p.Status)" } }
            $result.supported = $true
            $result.note = 'dbatools Copy-DbaSsisPackage migrated msdb/file packages (legacy cmdlet path).'
        } else {
            # Catalog cmdlet available but no SSISDB on source -> nothing to do.
            $result.status    = 'skipped'
            $result.supported = $false
            $result.note      = 'No SSISDB catalog found on source. msdb/file-system package migration is not supported by current dbatools — manual migration only if you use them.'
        }
    } catch {
        $result.status = 'partial'
        $result.error  = "$($_.Exception.Message)"
        $result.note   = 'SSIS migration hit an error; SSISDB catalog migration may require the manual master-key procedure.'
    }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    return $result
}
