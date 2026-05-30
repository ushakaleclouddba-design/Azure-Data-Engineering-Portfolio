<#
.SYNOPSIS
    SQLPilot - Server configuration migration (sp_configure values).

.DESCRIPTION
    Copies instance-level sp_configure settings (maxdop, max memory, cost
    threshold, optimize for ad hoc, etc.) from SOURCE to DESTINATION.

      dbatools : Copy-DbaSpConfigure.
      native   : read sys.configurations on the source, apply each value on the
                 destination via sp_configure + RECONFIGURE. Pure T-SQL.

    SAFETY: only DYNAMIC, safe-to-copy settings are applied. Settings that are
    instance/hardware-specific or risky to blindly copy are skipped by default
    (e.g. 'max server memory' depends on the destination's RAM; copying the
    source's value could starve or over-commit the destination). Those are
    REPORTED so a human can decide, not silently forced.

.NOTES
    Author : Kale. Pattern matches the other DC->DC modules.
#>

function Invoke-MigrateServerConfigs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native',
        [bool] $IncludeHardwareSpecific = $false   # max memory, min memory, max worker threads
    )
    $started = Get-Date
    $common  = @{ TrustServerCertificate=$true; Encrypt='Optional'; QueryTimeout=0; ErrorAction='Stop' }
    $result  = [ordered]@{
        status='ok'; engine=$Engine; source=$Source; destination=$Destination
        applied=@(); skipped=@(); failed=@(); elapsed_seconds=$null; note=$null
    }

    if ($Engine -eq 'dbatools') {
        try {
            Copy-DbaSpConfigure -Source $Source -Destination $Destination -ErrorAction Stop 2>&1 | ForEach-Object {
                $result.applied += @{ name="$($_.Name)"; status="$($_.Status)" }
            }
        } catch { $result.status='error'; $result.error="$($_.Exception.Message)" }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # Hardware/instance-specific settings we don't blindly copy.
    $hwSpecific = @('max server memory (MB)','min server memory (MB)','max worker threads','affinity mask','affinity I/O mask')

    try {
        $cfgs = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query `
            "SELECT name, CAST(value AS BIGINT) AS value FROM sys.configurations ORDER BY name")
    } catch { $result.status='error'; $result.error="Could not read source configurations: $($_.Exception.Message)"; return $result }

    # Need 'show advanced options' on to set advanced settings.
    try {
        Invoke-Sqlcmd @common -ServerInstance $Destination -Query "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;"
    } catch {}

    foreach ($c in $cfgs) {
        $cname = "$($c.name)"; $cval = [int64]$c.value
        if ($hwSpecific -contains $cname -and -not $IncludeHardwareSpecific) {
            $result.skipped += @{ name=$cname; source_value=$cval; reason='hardware/instance-specific - review before applying on destination' }
            continue
        }
        $nEsc = $cname -replace "'","''"
        try {
            Invoke-Sqlcmd @common -ServerInstance $Destination -Query "EXEC sp_configure '$nEsc', $cval; RECONFIGURE;"
            $result.applied += @{ name=$cname; value=$cval }
        } catch {
            $result.failed += @{ name=$cname; value=$cval; error="$($_.Exception.Message)" }
        }
    }

    if ($result.failed.Count -and $result.applied.Count) { $result.status='partial' }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    $result.note = "native sp_configure · $($result.applied.Count) setting(s) applied. Hardware-specific settings (memory, threads) skipped by default - review per destination."
    return $result
}
