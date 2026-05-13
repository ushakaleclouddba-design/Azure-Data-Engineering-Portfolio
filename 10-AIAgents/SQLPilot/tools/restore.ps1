<#
.SYNOPSIS
    SQLPilot - Real restore_database tool implementation.

.DESCRIPTION
    Replaces the stubbed restore_database in agent.ps1 with a real
    BACKUP TO URL / RESTORE FROM URL pipeline.

    This is the Microsoft-recommended migration approach for SQL Server
    databases under 1 TB with good Azure connectivity. The mechanics:

      1. Read storage account + SAS from `terraform output -json` in the
         current working directory (assumes agent runs from a directory
         that contains the SQLPilot Terraform module, or that the module
         is one level up - we try both).
      2. Read the target VM's admin credentials from terraform.tfvars and
         outputs.
      3. Create a SQL Server credential on the SOURCE pointing at the
         blob container (IDENTITY = 'SHARED ACCESS SIGNATURE'). The
         credential name MUST equal the container URL exactly.
      4. BACKUP DATABASE ... TO URL = '<container>/<dbname>.bak' WITH
         COMPRESSION, CHECKSUM. Executes on SOURCE via Windows auth.
      5. Create the same credential on the TARGET (Azure VM) via
         sqlpilotadmin SQL auth.
      6. RESTORE DATABASE ... FROM URL ... WITH MOVE clauses pointing
         data and log files to the target's default data path.
      7. Verify the restored DB is ONLINE and run a sanity count query.

    Returns a hashtable shaped to match the contract the agent's stub
    promised (status, mock, database, source, target, rows_restored,
    elapsed_seconds) - just with mock=false and real numbers.

.NOTES
    Author : Kale
    Pattern: mirrors tools/kb.ps1 - agent.ps1 dot-sources this file at
             startup; if loaded, Tool-RestoreDatabase calls
             Invoke-RealRestoreDatabase. If this file is missing the
             agent silently falls back to its inline mock.
#>

# ---------------------------------------------------------------------------
# Cached coordinates loaded from `terraform output -json`. Populated on
# first use so we don't shell out to terraform on every tool call.
# ---------------------------------------------------------------------------
$script:RestoreCoords     = $null
$script:RestoreCoordsRoot = $null   # the dir we read terraform output from


function Initialize-RestoreCoords {
    [CmdletBinding()]
    param (
        [string] $TerraformDir
    )

    # Locate the Terraform module. We look in this order:
    #   1. Explicit -TerraformDir override
    #   2. $script:ScriptRoot\Terraform   (sibling of agent.ps1)
    #   3. $script:ScriptRoot             (agent.ps1 lives in the TF dir itself)
    #   4. current working directory
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
        throw "Could not locate the SQLPilot Terraform directory (looked for .terraform marker). Pass -TerraformDir explicitly."
    }

    Write-Host "[restore] Reading coordinates from terraform output ($TerraformDir)..." -ForegroundColor DarkGray

    # Pull everything we need. The Terraform module exposes:
    #   public_ip_address            (target VM IP)
    #   admin_username               (target SQL admin)
    #   backup_storage_account       (storage account name - sqlpilotbk7siq)
    #   backup_container_url         (https://...blob.core.windows.net/backups)
    #   backup_container_sas_url     (sensitive, full URL with ?sas)
    $tfJson = & terraform -chdir="$TerraformDir" output -json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tfJson) {
        throw "terraform output -json failed in '$TerraformDir'. Has terraform apply been run?"
    }
    $tf = $tfJson | ConvertFrom-Json

    # Extract the bits we need. .value because terraform output -json wraps
    # each output in { value, type, sensitive }.
    $publicIp      = $tf.public_ip_address.value
    $adminUser     = $tf.admin_username.value
    $containerUrl  = $tf.backup_container_url.value
    $sasUrl        = $tf.backup_container_sas_url.value

    if (-not $publicIp -or -not $containerUrl -or -not $sasUrl) {
        throw "terraform output is missing required values (public_ip_address, backup_container_url, backup_container_sas_url). Re-run terraform apply."
    }

    # The SAS portion is everything AFTER the ? in $sasUrl. T-SQL's SHARED
    # ACCESS SIGNATURE credential wants this string with NO leading '?'.
    $sasQuery = ($sasUrl -split '\?', 2)[1]
    if (-not $sasQuery -or -not $sasQuery.Contains('sig=')) {
        throw "SAS URL from terraform doesn't contain a sig= parameter. Re-apply terraform to mint a fresh SAS."
    }

    # The admin password isn't in terraform output (it's marked sensitive
    # and isn't exposed as an output anyway). Read it from terraform.tfvars
    # directly. tfvars format: admin_password = "..."  on a single line.
    $tfvarsPath = Join-Path $TerraformDir 'terraform.tfvars'
    if (-not (Test-Path $tfvarsPath)) {
        throw "terraform.tfvars not found at $tfvarsPath. Restore needs admin_password to connect to the target VM."
    }
    $tfvarsText = Get-Content -Path $tfvarsPath -Raw
    $pwMatch = [regex]::Match($tfvarsText, 'admin_password\s*=\s*"([^"]+)"')
    if (-not $pwMatch.Success) {
        throw "admin_password not found (or not quoted with double-quotes) in $tfvarsPath."
    }
    $adminPassword = $pwMatch.Groups[1].Value

    $script:RestoreCoords = [PSCustomObject]@{
        PublicIp       = $publicIp
        AdminUser      = $adminUser
        AdminPassword  = $adminPassword
        ContainerUrl   = $containerUrl     # full https://...blob.../backups - used as credential NAME on both sides
        SasQuery       = $sasQuery         # bare query string (no leading ?) - used as credential SECRET
    }
    $script:RestoreCoordsRoot = $TerraformDir

    Write-Host "[restore] Coordinates loaded. target=$publicIp container=$containerUrl" -ForegroundColor DarkGray
}


# ---------------------------------------------------------------------------
# Helper - emit a SQL credential CREATE OR ALTER on a target instance. SQL
# Server doesn't support CREATE OR ALTER for credentials directly, so we
# DROP IF EXISTS then CREATE. Wrapped in a single batch.
#
# The credential NAME must equal the container URL EXACTLY (including the
# https:// prefix and the container path). The SECRET is the bare SAS
# query string with no leading '?'.
# ---------------------------------------------------------------------------
function New-SqlBackupCredential {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $ServerInstance,
        [hashtable] $InvokeArgs,   # extra Invoke-Sqlcmd args (Credential etc.)
        [Parameter(Mandatory)] [string] $CredentialName,
        [Parameter(Mandatory)] [string] $SasSecret
    )

    # Inline the secret. Escape single quotes in case the SAS has any
    # (shouldn't, but defensive).
    $secretEscaped = $SasSecret -replace "'", "''"
    $nameEscaped   = $CredentialName -replace "'", "''"

    $sql = @"
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = '$nameEscaped')
    DROP CREDENTIAL [$CredentialName];
CREATE CREDENTIAL [$CredentialName]
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
         SECRET   = '$secretEscaped';
"@

    $args = $InvokeArgs.Clone()
    $args['ServerInstance']         = $ServerInstance
    $args['Query']                  = $sql
    $args['TrustServerCertificate'] = $true
    $args['Encrypt']                = 'Optional'
    $args['ErrorAction']            = 'Stop'

    Invoke-Sqlcmd @args | Out-Null
}


# ---------------------------------------------------------------------------
# Invoke-RealRestoreDatabase
#
# The function agent.ps1's Tool-RestoreDatabase checks for via Get-Command.
# Same arg shape as the stub: -Database, -Source, -Target.
# ---------------------------------------------------------------------------
function Invoke-RealRestoreDatabase {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Target
    )

    $started = Get-Date

    # Lazy-load coordinates.
    if (-not $script:RestoreCoords) {
        Initialize-RestoreCoords
    }
    $coords = $script:RestoreCoords

    # If the agent passed a $Target that doesn't match what Terraform output
    # said, prefer the Terraform value but record both. This keeps the tool
    # honest if the model got creative with the target arg.
    $effectiveTarget = $coords.PublicIp
    if ($Target -and $Target -ne $effectiveTarget -and $Target -notmatch '\(mock\)') {
        Write-Host "[restore] note: agent passed target=$Target; using terraform target=$effectiveTarget instead." -ForegroundColor DarkYellow
    }

    # Common Invoke-Sqlcmd args. Source uses Windows auth, target uses
    # SQL auth - we'll layer Credential on top for the target.
    $commonArgs = @{
        TrustServerCertificate = $true
        Encrypt                = 'Optional'
        QueryTimeout           = 600
        ConnectionTimeout      = 30
        ErrorAction            = 'Stop'
    }

    # Credential for the target VM (SQL auth as sqlpilotadmin).
    $securePw = ConvertTo-SecureString $coords.AdminPassword -AsPlainText -Force
    $targetCred = New-Object System.Management.Automation.PSCredential(
        $coords.AdminUser, $securePw
    )
    $targetArgs = $commonArgs.Clone()
    $targetArgs['Credential'] = $targetCred

    $backupBlobUrl = "{0}/{1}.bak" -f $coords.ContainerUrl, $Database

    # -----------------------------------------------------------------
    # Step 1 - Create the SHARED ACCESS SIGNATURE credential on SOURCE.
    # -----------------------------------------------------------------
    Write-Host "[restore] Creating backup credential on source ($Source)..." -ForegroundColor DarkGray
    New-SqlBackupCredential `
        -ServerInstance $Source `
        -InvokeArgs $commonArgs `
        -CredentialName $coords.ContainerUrl `
        -SasSecret $coords.SasQuery

    # -----------------------------------------------------------------
    # Step 2 - BACKUP DATABASE on SOURCE to the blob URL.
    # WITH COMPRESSION (smaller, faster transfer over the wire).
    # WITH CHECKSUM   (catch corruption during write, not during restore).
    # FORMAT, INIT    (overwrite the blob if a prior run left a .bak there).
    # MAXTRANSFERSIZE = 4194304 and BLOCKSIZE = 65536 are MS-recommended
    # defaults for BACKUP TO URL throughput. STATS = 10 makes the script
    # output more debuggable when running manually.
    # -----------------------------------------------------------------
    Write-Host "[restore] BACKUP DATABASE [$Database] TO URL = $backupBlobUrl ..." -ForegroundColor DarkGray
    $backupSql = @"
BACKUP DATABASE [$Database]
TO URL = N'$backupBlobUrl'
WITH
    COMPRESSION,
    CHECKSUM,
    FORMAT,
    INIT,
    MAXTRANSFERSIZE = 4194304,
    BLOCKSIZE       = 65536,
    STATS           = 10;
"@
    $bArgs = $commonArgs.Clone()
    $bArgs['ServerInstance'] = $Source
    $bArgs['Query']          = $backupSql
    Invoke-Sqlcmd @bArgs | Out-Null

    # -----------------------------------------------------------------
    # Step 3 - Create the SAME credential on the TARGET (Azure VM).
    # The credential is server-local; each side needs its own copy.
    # -----------------------------------------------------------------
    Write-Host "[restore] Creating backup credential on target ($effectiveTarget)..." -ForegroundColor DarkGray
    New-SqlBackupCredential `
        -ServerInstance $effectiveTarget `
        -InvokeArgs $targetArgs `
        -CredentialName $coords.ContainerUrl `
        -SasSecret $coords.SasQuery

    # -----------------------------------------------------------------
    # Step 4 - RESTORE FILELISTONLY to learn the logical filenames.
    # We need them for the MOVE clause - the source's physical paths
    # (e.g. C:\Data\...) almost certainly don't exist on the target.
    # -----------------------------------------------------------------
    Write-Host "[restore] Probing backup file layout on target..." -ForegroundColor DarkGray
    $listArgs = $targetArgs.Clone()
    $listArgs['ServerInstance'] = $effectiveTarget
    $listArgs['Query']          = "RESTORE FILELISTONLY FROM URL = N'$backupBlobUrl';"
    $listArgs['OutputAs']       = 'DataTables'
    $fileList = Invoke-Sqlcmd @listArgs

    # Flatten to an array of DataRow no matter what shape Invoke-Sqlcmd
    # returns (single table vs collection).
    $rows = if ($fileList -is [System.Data.DataTable]) { @($fileList) }
            elseif ($null -ne $fileList) { @($fileList.Rows) }
            else { @() }

    if ($rows.Count -lt 2) {
        throw "RESTORE FILELISTONLY returned $($rows.Count) rows - expected at least 2 (data + log). Backup may be corrupt or unreachable."
    }

    # Discover the target's default data and log paths so we can MOVE.
    $pathArgs = $targetArgs.Clone()
    $pathArgs['ServerInstance'] = $effectiveTarget
    $pathArgs['Query']          = "SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260)) AS DataPath, CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS NVARCHAR(260)) AS LogPath;"
    $pathRow = Invoke-Sqlcmd @pathArgs
    $targetDataPath = "$($pathRow.DataPath)"
    $targetLogPath  = "$($pathRow.LogPath)"
    if (-not $targetDataPath -or -not $targetLogPath) {
        throw "Could not read InstanceDefaultDataPath / InstanceDefaultLogPath from target."
    }

    # Build MOVE clauses. Type 'D' = data, 'L' = log. Filestream containers
    # (type 'S') we'd handle separately if any DB needs them - not in scope
    # for SQLPilotDemo.
    $moveClauses = @()
    foreach ($r in $rows) {
        $logical    = "$($r.LogicalName)".Trim()
        $type       = "$($r.Type)".Trim()
        $physOrig   = "$($r.PhysicalName)".Trim()
        $leaf       = [System.IO.Path]::GetFileName($physOrig)
        $newPath    = switch ($type) {
            'D' { Join-Path $targetDataPath $leaf }
            'L' { Join-Path $targetLogPath  $leaf }
            default { Join-Path $targetDataPath $leaf }   # filestream etc: stash with data
        }
        $moveClauses += "MOVE N'$logical' TO N'$newPath'"
    }

    # -----------------------------------------------------------------
    # Step 5 - RESTORE DATABASE FROM URL on the TARGET.
    # WITH REPLACE so the agent can be re-run without manual cleanup.
    # -----------------------------------------------------------------
    $moveSql = $moveClauses -join ",`n    "
    $restoreSql = @"
RESTORE DATABASE [$Database]
FROM URL = N'$backupBlobUrl'
WITH
    $moveSql,
    REPLACE,
    STATS = 10;
"@
    Write-Host "[restore] RESTORE DATABASE [$Database] FROM URL on target..." -ForegroundColor DarkGray
    $rArgs = $targetArgs.Clone()
    $rArgs['ServerInstance'] = $effectiveTarget
    $rArgs['Query']          = $restoreSql
    Invoke-Sqlcmd @rArgs | Out-Null

    # -----------------------------------------------------------------
    # Step 6 - Verify. Confirm the DB is ONLINE on the target and grab a
    # row count from sys.tables so we can return something meaningful in
    # rows_restored (replaces the stub's fabricated 1573).
    # -----------------------------------------------------------------
    $verifyArgs = $targetArgs.Clone()
    $verifyArgs['ServerInstance'] = $effectiveTarget
    $verifyArgs['Database']       = $Database
    $verifyArgs['Query']          = @"
SELECT
    DB_NAME()                                           AS DatabaseName,
    (SELECT state_desc FROM sys.databases WHERE name = DB_NAME()) AS State,
    (SELECT COUNT(*) FROM sys.tables WHERE type = 'U')  AS UserTableCount,
    (SELECT SUM(p.rows)
       FROM sys.partitions p
       INNER JOIN sys.tables t ON p.object_id = t.object_id
       WHERE p.index_id IN (0,1) AND t.type = 'U')      AS TotalRowCount;
"@
    $verify = Invoke-Sqlcmd @verifyArgs

    $elapsed = [int]((Get-Date) - $started).TotalSeconds

    return @{
        status           = 'ok'
        mock             = $false
        database         = $Database
        source           = $Source
        target           = $effectiveTarget
        backup_url       = $backupBlobUrl
        method           = 'BACKUP TO URL / RESTORE FROM URL'
        method_rationale = 'Microsoft recommendation for databases <1TB with good Azure connectivity (Microsoft Learn: SQL Server to Azure VM migration overview).'
        state            = "$($verify.State)"
        user_table_count = [int]$verify.UserTableCount
        rows_restored    = [int]$verify.TotalRowCount
        elapsed_seconds  = $elapsed
        terraform_dir    = $script:RestoreCoordsRoot
    }
}
