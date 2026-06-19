<#
.SYNOPSIS
    SQLPilot - TDE certificate migration (so TDE-encrypted databases can be
    restored on the destination).

.DESCRIPTION
    A TDE-encrypted database CANNOT be restored on a destination instance
    unless the certificate that protects its Database Encryption Key (DEK)
    already exists there. This module migrates those certificates - and the
    destination Database Master Key they depend on - BEFORE any TDE database
    is restored. It runs as a pre-step in both the database-list and the
    whole-server flows, and in both engines (dbatools and native): the key
    chain is identical, only the syntax differs.

    What it does, per TDE database in scope:
      1. Detect TDE databases (sys.databases.is_encrypted = 1) whose DEK is
         protected by a CERTIFICATE (encryptor_type = 'CERTIFICATE').
           - System DBs (database_id <= 4, e.g. tempdb) are SKIPPED: tempdb is
             auto-encrypted by the instance and is never migrated.
           - DEKs protected by an ASYMMETRIC KEY (EKM/Key Vault) are reported
             as 'not supported in v1' - that path needs the external key
             provider, not a file-based cert, and is out of scope here.
      2. De-duplicate: several DBs can share one certificate; migrate each
         distinct cert only once per run.
      3. SOURCE: BACKUP CERTIFICATE <cert> TO FILE + WITH PRIVATE KEY (FILE,
         ENCRYPTION BY PASSWORD=<transfer pwd>) -> writes .cer + .pvk to the
         shared path.
      4. DEST: ensure a Database Master Key exists in master (CREATE MASTER KEY
         ENCRYPTION BY PASSWORD=<dest DMK pwd> if absent), then
         CREATE CERTIFICATE <cert> FROM FILE + WITH PRIVATE KEY (FILE,
         DECRYPTION BY PASSWORD=<transfer pwd>).
      5. CLEANUP: securely delete the .cer/.pvk files from the share - they
         contain private key material.

    Secrets are read from environment variables (never hardcoded, never in the
    repo), through Get-SqlPilotSecret so a real secrets vault (Azure Key Vault
    / HashiCorp Vault) can drop in later:
      SQLPILOT_DMK_PWD       - destination Database Master Key password
      SQLPILOT_TDE_XFER_PWD  - transient password protecting the cert backup
                               files in transit (same value used to back up on
                               the source and create on the destination)

    PRODUCTION NOTE: env vars are an accepted automation pattern, but a
    security-conscious org should source these from a vault, and the
    long-term-best approach for TDE is EKM / Key Vault-backed keys (the key
    never leaves the HSM/vault, so migration is "point the new server at the
    same vault" rather than moving cert files at all).

.NOTES
    Author : Kale
    Pattern: mirrors tools/migrate_logins.ps1. server.ps1 dot-sources this;
             the migration flow calls Invoke-MigrateTdeCertificates as a
             pre-step before restoring databases.
#>

# ---------------------------------------------------------------------------
# Secret resolver. Today: environment variables. Tomorrow: swap the body for a
# vault call (Get-AzKeyVaultSecret, vault API, etc.) - callers don't change.
# ---------------------------------------------------------------------------
function Get-SqlPilotSecret {
    param(
        [Parameter(Mandatory)] [string] $Name,   # logical secret name
        [string] $EnvVar                           # backing env var
    )
    $val = if ($EnvVar) { [Environment]::GetEnvironmentVariable($EnvVar) } else { $null }
    if ([string]::IsNullOrWhiteSpace($val)) {
        throw "Secret '$Name' not available. Set environment variable '$EnvVar' (production: source from a secrets vault)."
    }
    return $val
}

# ---------------------------------------------------------------------------
# Discover TDE databases in scope and the distinct certificates protecting
# them. Returns objects: @{ Database; CertName; Thumbprint; EncryptorType; Supported }
# ---------------------------------------------------------------------------
function Get-TdeCertificateMap {
    param(
        [Parameter(Mandatory)] [string]   $Source,
        [string[]]                         $Databases   # null/empty => all user DBs (whole-server)
    )
    # database_id > 4 excludes system DBs (tempdb auto-encryption must never migrate).
    $filter = ''
    if ($Databases -and $Databases.Count) {
        $list = ($Databases | ForEach-Object { "'" + ($_ -replace "'","''") + "'" }) -join ','
        $filter = "AND d.name IN ($list)"
    }
    $q = @"
SELECT d.name                              AS DbName,
       c.name                              AS CertName,
       CONVERT(VARCHAR(256), dek.encryptor_thumbprint, 1) AS Thumbprint,
       dek.encryptor_type                  AS EncryptorType
FROM sys.databases d
JOIN sys.dm_database_encryption_keys dek ON dek.database_id = d.database_id
LEFT JOIN master.sys.certificates c ON c.thumbprint = dek.encryptor_thumbprint
WHERE d.is_encrypted = 1
  AND d.database_id > 4          -- skip system DBs (tempdb etc.)
  $filter
ORDER BY d.name;
"@
    $rows = Invoke-Sqlcmd -ServerInstance $Source -Query $q -TrustServerCertificate -Encrypt Optional -ErrorAction Stop
    $out = @()
    foreach ($r in @($rows)) {
        $out += [pscustomobject]@{
            Database      = "$($r.DbName)"
            CertName      = "$($r.CertName)"
            Thumbprint    = "$($r.Thumbprint)"
            EncryptorType = "$($r.EncryptorType)"
            Supported     = ("$($r.EncryptorType)" -eq 'CERTIFICATE' -and -not [string]::IsNullOrWhiteSpace("$($r.CertName)"))
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
# Invoke-MigrateTdeCertificates
#   -Source / -Destination  SQL instances
#   -Databases              scope; null/empty => whole-server (all user DBs)
#   -SharedPath             UNC share both servers can read/write (for the
#                           .cer/.pvk transit files)
#   -Engine                 'dbatools' | 'native' (logic is the same; native
#                           uses pure T-SQL, dbatools uses Backup/Restore-DbaDbCertificate)
#   Returns: @{ status; tde_databases[]; certificates_migrated[]; skipped[];
#               dmk_created; engine; notes }
# ---------------------------------------------------------------------------
function Invoke-MigrateTdeCertificates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Source,
        [Parameter(Mandatory)] [string]   $Destination,
        [string[]]                         $Databases,
        [Parameter(Mandatory)] [string]   $SharedPath,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native'
    )

    $result = [ordered]@{
        status='ok'; source=$Source; destination=$Destination; engine=$Engine
        tde_databases=@(); certificates_migrated=@(); skipped=@()
        dmk_created=$false; notes=$null
    }

    # BUG-053: Discover whether any TDE work is actually required BEFORE resolving
    # secrets. The previous order resolved SQLPILOT_DMK_PWD / SQLPILOT_TDE_XFER_PWD
    # up front, so a DB-list migration with zero TDE-encrypted DBs would throw
    # 'secret not available' and surface an error in the audit trail for a step
    # that should have been a clean no-op. TDE should only run when:
    #   1. Whole-server scope (Databases is $null/empty), OR
    #   2. At least one of the selected DBs is TDE-encrypted with a file-cert DEK.
    # When neither is true, return status='ok' with an honest 'no TDE in scope'
    # note and never touch the secrets store.
    try { $map = Get-TdeCertificateMap -Source $Source -Databases $Databases }
    catch { $result.status='error'; $result.error="TDE discovery failed: $($_.Exception.Message)"; return $result }

    $result.tde_databases = @($map | ForEach-Object { @{ database=$_.Database; cert=$_.CertName; type=$_.EncryptorType; supported=$_.Supported } })

    $supported = @($map | Where-Object { $_.Supported })
    if (-not $supported.Count) {
        # No file-certificate TDE work to do. Report any EKM/asymmetric-key DBs
        # for visibility (they're not v1-supported), but exit cleanly.
        $unsupported = @($map | Where-Object { -not $_.Supported })
        if ($unsupported.Count) {
            $result.notes = "No file-certificate TDE databases in scope to migrate; $($unsupported.Count) DB(s) use unsupported EKM/Key Vault encryption and were reported but not handled."
            $result.skipped = @($unsupported | ForEach-Object { @{ database=$_.Database; reason="TDE via $($_.EncryptorType) - not supported (EKM/Key Vault path)" } })
        } else {
            $result.notes = 'No TDE-encrypted databases in scope; TDE step skipped (no work required).'
        }
        return $result
    }

    # 2. Resolve secrets — only now that we know TDE work is required.
    try {
        $dmkPwd  = Get-SqlPilotSecret -Name 'DestDmkPassword'     -EnvVar 'SQLPILOT_DMK_PWD'
        $xferPwd = Get-SqlPilotSecret -Name 'TdeTransferPassword' -EnvVar 'SQLPILOT_TDE_XFER_PWD'
    } catch {
        $result.status='error'; $result.error="$($_.Exception.Message)"; return $result
    }

    # 3. De-dupe certificates (multiple DBs can share one cert).
    $distinctCerts = $supported | Select-Object -ExpandProperty CertName -Unique

    # 3. Ensure destination Database Master Key exists (create once if absent).
    try {
        $hasDmk = Invoke-Sqlcmd -ServerInstance $Destination -TrustServerCertificate -Encrypt Optional -ErrorAction Stop -Query `
            "SELECT COUNT(*) AS n FROM master.sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##'"
        if ([int]$hasDmk.n -eq 0) {
            $escDmk = $dmkPwd -replace "'", "''"
            Invoke-Sqlcmd -ServerInstance $Destination -TrustServerCertificate -Encrypt Optional -ErrorAction Stop -Query `
                "USE master; CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$escDmk';"
            $result.dmk_created = $true
        }
    } catch {
        $result.status='error'; $result.error="Destination master key setup failed: $($_.Exception.Message)"; return $result
    }

    # 4. Migrate each distinct cert: backup on source -> create on dest.
    foreach ($cert in $distinctCerts) {
        $certEsc = $cert -replace "'", "''"
        $safe    = ($cert -replace '[^A-Za-z0-9_]', '_')
        $cerFile = Join-Path $SharedPath "tde_$safe.cer"
        $pvkFile = Join-Path $SharedPath "tde_$safe.pvk"
        $escXfer = $xferPwd -replace "'", "''"

        try {
            if ($Engine -eq 'dbatools') {
                # dbatools equivalent: same key chain, native cmdlets.
                Backup-DbaDbCertificate -SqlInstance $Source -Certificate $cert -Database master `
                    -Path $SharedPath -EncryptionPassword (ConvertTo-SecureString $xferPwd -AsPlainText -Force) `
                    -ErrorAction Stop | Out-Null
                Restore-DbaDbCertificate -SqlInstance $Destination -Path $SharedPath `
                    -Database master -DecryptionPassword (ConvertTo-SecureString $xferPwd -AsPlainText -Force) `
                    -EncryptionPassword (ConvertTo-SecureString $xferPwd -AsPlainText -Force) -ErrorAction Stop | Out-Null
            }
            else {
                # NATIVE T-SQL. Source: back up cert + private key to the share.
                $bkp = @"
USE master;
BACKUP CERTIFICATE [$certEsc]
    TO FILE = N'$cerFile'
    WITH PRIVATE KEY (FILE = N'$pvkFile',
                      ENCRYPTION BY PASSWORD = '$escXfer');
"@
                Invoke-Sqlcmd -ServerInstance $Source -Query $bkp -TrustServerCertificate -Encrypt Optional -ErrorAction Stop

                # Dest: create cert from the files (skip if it already exists).
                $crt = @"
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$certEsc')
    CREATE CERTIFICATE [$certEsc]
        FROM FILE = N'$cerFile'
        WITH PRIVATE KEY (FILE = N'$pvkFile',
                          DECRYPTION BY PASSWORD = '$escXfer');
"@
                Invoke-Sqlcmd -ServerInstance $Destination -Query $crt -TrustServerCertificate -Encrypt Optional -ErrorAction Stop
            }
            $result.certificates_migrated += @{ cert=$cert; status='Success' }
        }
        catch {
            $result.status='error'
            $result.certificates_migrated += @{ cert=$cert; status='Failed'; error="$($_.Exception.Message)" }
            # continue to clean up files even on failure
        }
        finally {
            # 5. CLEANUP - private key material must not linger on the share.
            foreach ($f in @($cerFile, $pvkFile)) {
                try { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } } catch {}
            }
        }
    }

    # Report any unsupported (asymmetric/EKM) TDE DBs we skipped.
    $result.skipped = @($map | Where-Object { -not $_.Supported } | ForEach-Object { @{ database=$_.Database; reason="TDE via $($_.EncryptorType) - not supported (EKM/Key Vault path)" } })

    if ($result.status -eq 'ok') {
        $result.notes = "Migrated $($distinctCerts.Count) TDE certificate(s); destination ready to restore the corresponding TDE database(s)."
    }
    return $result
}
