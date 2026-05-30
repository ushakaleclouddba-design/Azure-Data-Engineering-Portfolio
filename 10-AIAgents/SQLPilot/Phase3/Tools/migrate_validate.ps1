<#
.SYNOPSIS
    SQLPilot - Post-migration validation (DBCC CHECKDB).

.DESCRIPTION
    Runs integrity validation on the migrated databases on the DESTINATION.
    Both engines use the same T-SQL DBCC CHECKDB (dbatools' Invoke-DbaDbCheck
    wraps the same thing); we keep it native for consistency and zero
    dependencies. Reports per-database pass/fail and error counts.

.NOTES
    Author : Kale. Pattern matches the other DC->DC modules.
#>

function Invoke-MigrateValidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Destination,
        [Parameter(Mandatory)] [string[]] $Databases,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native'
    )
    $started = Get-Date
    $common  = @{ TrustServerCertificate=$true; Encrypt='Optional'; QueryTimeout=0; ErrorAction='Stop' }
    $result  = [ordered]@{
        status='ok'; destination=$Destination; databases_checked=0
        all_passed=$true; results=@(); total_errors=0; elapsed_seconds=$null
    }
    if (-not $Databases -or $Databases.Count -eq 0) {
        $result.note='No databases to validate.'; return $result
    }

    # BUG-027 fix: in dbatools mode the SqlServer module can't load (it conflicts
    # with dbatools on SMO assemblies), so Invoke-Sqlcmd is unavailable. Use
    # dbatools' own Invoke-DbaQuery instead. In native mode, use Invoke-Sqlcmd.
    # Both run the same DBCC CHECKDB T-SQL.
    $runQuery = {
        param($Query)
        if ($Engine -eq 'dbatools') {
            Invoke-DbaQuery -SqlInstance $Destination -Query $Query -EnableException
        } else {
            Invoke-Sqlcmd @common -ServerInstance $Destination -Query $Query
        }
    }

    foreach ($db in $Databases) {
        $dbBr = $db -replace ']',']]'
        try {
            # WITH NO_INFOMSGS TABLERESULTS - rows returned = problems found.
            $rows = @(& $runQuery "DBCC CHECKDB([$dbBr]) WITH NO_INFOMSGS, TABLERESULTS")
            $errCount = @($rows | Where-Object { [int]$_.Level -ge 16 }).Count
            $passed = ($errCount -eq 0)
            $result.results += @{ database=$db; passed=$passed; errors=$errCount }
            $result.total_errors += $errCount
            if (-not $passed) { $result.all_passed = $false }
            $result.databases_checked++
        } catch {
            $result.results += @{ database=$db; passed=$false; error="$($_.Exception.Message)" }
            $result.all_passed = $false
        }
    }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    if (-not $result.all_passed) { $result.status='partial' }
    return $result
}
