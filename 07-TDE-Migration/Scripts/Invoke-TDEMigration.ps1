<#
.SYNOPSIS
    End-to-end Transparent Data Encryption (TDE) migration from on-premises SQL Server
    to Azure SQL Managed Instance.

.DESCRIPTION
    Master orchestrator for Appendix S TDE Certificate Migration POC.
    Automates all 9 phases of the Microsoft-documented native TDE migration method:
      S.1  Create source database (OPTIONAL - skipped by default)
      S.2  Enable TDE on source (OPTIONAL - skipped by default)
      S.3  Export certificate and private key
      S.4  Convert .pvk + .cer to .pfx using pvk2pfx
      S.5  Convert .pfx to Base64 string
      S.6  Upload certificate to Azure SQL Managed Instance
      S.7  BACKUP DATABASE TO URL (on-prem SQL Server -> Azure Blob)
      S.8  RESTORE DATABASE FROM URL (Azure Blob -> SQL MI) *** RUN ON MI ***
      S.9  Validate TDE state and row parity *** RUN ON MI ***

    Phases S.8 and S.9 require T-SQL execution on the target SQL MI via SSMS
    because they cannot be run remotely from an on-prem PowerShell session.
    The script generates those T-SQL scripts as separate files for the operator
    to execute on MI manually.

.PARAMETER SourceServer
    On-premises SQL Server hostname or IP (e.g., "Node1" or "192.168.68.21")

.PARAMETER SourceDatabase
    Name of the TDE-encrypted database on the source server

.PARAMETER CertificateName
    Name of the TDE certificate on the source server

.PARAMETER PVKPassword
    Password used to encrypt the .pvk file during BACKUP CERTIFICATE (Phase S.3)

.PARAMETER MIResourceGroup
    Azure resource group name containing the target SQL MI

.PARAMETER MIName
    Azure SQL Managed Instance name (not FQDN)

.PARAMETER BackupStorageAccount
    Azure storage account name for blob-based backup staging

.PARAMETER BackupContainer
    Container name within the storage account (created if not exists externally)

.PARAMETER SASToken
    Shared Access Signature token for the container (without leading '?')
    Must have permissions: Read, Add, Create, Write, Delete, List
    Must use HTTPS only

.PARAMETER WorkingFolder
    Local folder for certificate export files (default: C:\TDE_Backup)
    Must have SQL Server service account write permissions

.PARAMETER SDKVersion
    Windows SDK version folder name where pvk2pfx.exe is located
    Default: 10.0.28000.0
    Full path derivation: C:\Program Files (x86)\Windows Kits\10\bin\<SDKVersion>\x64\pvk2pfx.exe

.PARAMETER SkipPhaseS1S2
    If set, skips database creation and TDE enablement (assumes they're already done)
    Default: $true (most migrations start with an existing TDE database)

.PARAMETER LogFolder
    Folder where the master log file will be written
    Default: C:\TDE_Backup\logs

.EXAMPLE
    .\Invoke-TDEMigration.ps1 `
        -SourceServer "Node1" `
        -SourceDatabase "TDE_Demo_DB_Banking" `
        -CertificateName "TDE_Demo_Cert_Banking" `
        -PVKPassword "PvkExp0rt#Pass2026!Banking" `
        -MIResourceGroup "Usha_SQLMI_POC" `
        -MIName "usha-sqlmi-poc" `
        -BackupStorageAccount "ushalrsbackup" `
        -BackupContainer "tdebackup" `
        -SASToken "sv=2024-11-04&ss=b&srt=co&sp=rwdlac&..." `
        -WorkingFolder "C:\TDE_Backup"

.NOTES
    Author:  Usha Kale | Senior Cloud DBA / Azure Data Engineer
    Created: April 22, 2026
    Version: 1.0

    Prerequisites:
      - Windows SDK FULL install (not just Signing Tools) — see KL-S-08
      - Az.Sql PowerShell module 6.4.1 or later
      - Connect-AzAccount already executed (active Azure session)
      - SQL MI in Ready state
      - Target blob container exists (create via Azure Portal before running)
      - Valid SAS token generated and copied (without leading '?')

    Companion Documents:
      - SQL_Azure_Migration_Technical_Guide_v14.docx (Bible v14 - Appendix S section)
      - Appendix_S_TDE_Options_Playbook_v5.docx (standalone version)

    GitHub: ushakaleclouddba-design/Azure-Data-Engineering-Portfolio

.LINK
    https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/tde-certificate-migrate
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceServer,
    [Parameter(Mandatory=$true)][string]$SourceDatabase,
    [Parameter(Mandatory=$true)][string]$CertificateName,
    [Parameter(Mandatory=$true)][string]$PVKPassword,
    [Parameter(Mandatory=$true)][string]$MIResourceGroup,
    [Parameter(Mandatory=$true)][string]$MIName,
    [Parameter(Mandatory=$true)][string]$BackupStorageAccount,
    [Parameter(Mandatory=$true)][string]$BackupContainer,
    [Parameter(Mandatory=$true)][string]$SASToken,
    [Parameter(Mandatory=$false)][string]$WorkingFolder = "C:\TDE_Backup",
    [Parameter(Mandatory=$false)][string]$SDKVersion = "10.0.28000.0",
    [Parameter(Mandatory=$false)][bool]$SkipPhaseS1S2 = $true,
    [Parameter(Mandatory=$false)][string]$LogFolder = "C:\TDE_Backup\logs"
)

# ============================================================================
# #region MASTER LOGGING SETUP
# ============================================================================
# All phases write to a single timestamped log file for audit purposes.
# Banking compliance requires full migration audit trails.
# ============================================================================

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not (Test-Path $LogFolder)) { New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $LogFolder "TDE_Migration_${SourceDatabase}_${timestamp}.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $entry | Tee-Object -FilePath $logFile -Append | Write-Host
}

function Write-Phase {
    param([string]$PhaseName)
    Write-Log ""
    Write-Log ("=" * 78)
    Write-Log "  $PhaseName"
    Write-Log ("=" * 78)
}

Write-Log "TDE Migration Orchestrator - Starting"
Write-Log "Log file: $logFile"
Write-Log "Parameters:"
Write-Log "  SourceServer:          $SourceServer"
Write-Log "  SourceDatabase:        $SourceDatabase"
Write-Log "  CertificateName:       $CertificateName"
Write-Log "  MIResourceGroup:       $MIResourceGroup"
Write-Log "  MIName:                $MIName"
Write-Log "  BackupStorageAccount:  $BackupStorageAccount"
Write-Log "  BackupContainer:       $BackupContainer"
Write-Log "  WorkingFolder:         $WorkingFolder"
Write-Log "  SDKVersion:            $SDKVersion"
Write-Log "  SkipPhaseS1S2:         $SkipPhaseS1S2"

# #endregion

# ============================================================================
# #region PREREQUISITE VALIDATION
# ============================================================================
# Fails fast if any dependency is missing. Checks in order:
#   1. Az.Sql PowerShell module present
#   2. Active Azure session (Connect-AzAccount was run)
#   3. pvk2pfx.exe exists at expected SDK location (KL-S-08)
#   4. SQL MI is in Ready state
#   5. Working folder is accessible
# ============================================================================

Write-Phase "PREREQUISITE VALIDATION"

# Check 1: Az.Sql module
Write-Log "Checking Az.Sql module..."
$azSql = Get-Module -ListAvailable -Name Az.Sql | Select-Object -First 1
if (-not $azSql) {
    Write-Log "Az.Sql module NOT installed. Run: Install-Module -Name Az.Sql -Force" "ERROR"
    throw "Missing Az.Sql module"
}
Write-Log "Az.Sql version: $($azSql.Version)"

# Check 2: Azure session
Write-Log "Checking Azure session..."
$azContext = Get-AzContext
if (-not $azContext -or -not $azContext.Account) {
    Write-Log "No active Azure session. Run: Connect-AzAccount" "ERROR"
    throw "No Azure session"
}
Write-Log "Azure account: $($azContext.Account.Id)"
Write-Log "Subscription:  $($azContext.Subscription.Name) ($($azContext.Subscription.Id))"

# Check 3: pvk2pfx.exe exists (KL-S-08)
$pvk2pfxPath = "C:\Program Files (x86)\Windows Kits\10\bin\$SDKVersion\x64\pvk2pfx.exe"
Write-Log "Checking pvk2pfx.exe at: $pvk2pfxPath"
if (-not (Test-Path $pvk2pfxPath)) {
    Write-Log "pvk2pfx.exe NOT found at expected location." "ERROR"
    Write-Log "Per KL-S-08: Install FULL Windows SDK (not just Signing Tools sub-component)" "ERROR"
    Write-Log "Download: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/" "ERROR"
    throw "pvk2pfx.exe not found"
}
Write-Log "pvk2pfx.exe found"

# Check 4: SQL MI state
Write-Log "Checking SQL MI state..."
try {
    $mi = Get-AzSqlInstance -ResourceGroupName $MIResourceGroup -Name $MIName -ErrorAction Stop
    Write-Log "SQL MI FQDN: $($mi.FullyQualifiedDomainName)"
    Write-Log "Note: Check Azure Portal for authoritative Status (State property may return empty in some Az.Sql versions)"
} catch {
    Write-Log "Failed to query SQL MI: $($_.Exception.Message)" "ERROR"
    throw
}

# Check 5: Working folder
Write-Log "Checking working folder: $WorkingFolder"
if (-not (Test-Path $WorkingFolder)) {
    Write-Log "Creating working folder..."
    New-Item -Path $WorkingFolder -ItemType Directory -Force | Out-Null
}
Write-Log "Working folder ready"

Write-Log "All prerequisites satisfied"

# #endregion

# ============================================================================
# #region PHASE S.1 - CREATE SOURCE DATABASE (OPTIONAL - SKIPPED BY DEFAULT)
# ============================================================================
# Creates a demo database with banking schema for POC purposes.
# Most real migrations skip this phase because the database already exists.
# Controlled by -SkipPhaseS1S2 parameter (default: $true).
# ============================================================================

if (-not $SkipPhaseS1S2) {
    Write-Phase "PHASE S.1 - CREATE SOURCE DATABASE"

    $s1Sql = @"
USE master;
GO

IF DB_ID('$SourceDatabase') IS NOT NULL
BEGIN
    ALTER DATABASE [$SourceDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$SourceDatabase];
END
GO

CREATE DATABASE [$SourceDatabase]
ON PRIMARY (
    NAME = '${SourceDatabase}_Data',
    FILENAME = 'C:\data\$SourceDatabase.mdf',
    SIZE = 100MB
)
LOG ON (
    NAME = '${SourceDatabase}_Log',
    FILENAME = 'C:\log\$SourceDatabase.ldf',
    SIZE = 20MB
);
GO

ALTER DATABASE [$SourceDatabase] SET RECOVERY FULL;
GO
"@

    Write-Log "Executing CREATE DATABASE on $SourceServer..."
    Invoke-Sqlcmd -ServerInstance $SourceServer -Database master -Query $s1Sql
    Write-Log "Database created with FULL recovery model"
} else {
    Write-Log "Phase S.1 SKIPPED (SkipPhaseS1S2 = true)"
}

# #endregion

# ============================================================================
# #region PHASE S.2 - ENABLE TDE ON SOURCE (OPTIONAL - SKIPPED BY DEFAULT)
# ============================================================================
# Establishes the cryptographic chain: DMK -> Certificate -> DEK -> Encrypted Data
# Only runs if -SkipPhaseS1S2 is $false AND the database is not already encrypted.
# Generates strong random passwords for DMK (encryption of DEK happens via cert).
# ============================================================================

if (-not $SkipPhaseS1S2) {
    Write-Phase "PHASE S.2 - ENABLE TDE ON SOURCE"

    $dmkPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 24 | ForEach-Object {[char]$_})
    Write-Log "Generated random DMK password (length: $($dmkPassword.Length))"
    Write-Log "DMK password saved to: $WorkingFolder\dmk_password.txt (SECURE this file!)"
    $dmkPassword | Out-File "$WorkingFolder\dmk_password.txt" -Encoding ASCII

    $s2Sql = @"
USE master;
GO

IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE symmetric_key_id = 101)
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$dmkPassword';
GO

IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = '$CertificateName')
    CREATE CERTIFICATE [$CertificateName]
        WITH SUBJECT = 'TDE Certificate for $SourceDatabase migration';
GO

USE [$SourceDatabase];
GO

IF NOT EXISTS (SELECT * FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$SourceDatabase'))
BEGIN
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE [$CertificateName];
END
GO

ALTER DATABASE [$SourceDatabase] SET ENCRYPTION ON;
GO
"@

    Write-Log "Executing TDE enablement on $SourceServer..."
    Invoke-Sqlcmd -ServerInstance $SourceServer -Database master -Query $s2Sql
    Write-Log "TDE enabled. Waiting 10 seconds for initial encryption scan..."
    Start-Sleep -Seconds 10
} else {
    Write-Log "Phase S.2 SKIPPED (SkipPhaseS1S2 = true - assumed already encrypted)"
}

# #endregion

# ============================================================================
# #region PHASE S.3 - EXPORT CERTIFICATE AND PRIVATE KEY
# ============================================================================
# BACKUP CERTIFICATE writes files using the SQL Server service account.
# KL-S-03: The working folder MUST have NT SERVICE\MSSQLSERVER Full Control.
# Grant permissions BEFORE executing BACKUP CERTIFICATE to prevent OS Error 5.
# ============================================================================

Write-Phase "PHASE S.3 - EXPORT CERTIFICATE AND PRIVATE KEY"

# Grant SQL service account write access (KL-S-03)
Write-Log "Granting NT SERVICE\MSSQLSERVER FullControl on $WorkingFolder..."
try {
    $acl = Get-Acl $WorkingFolder
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT SERVICE\MSSQLSERVER", "FullControl",
        "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $WorkingFolder $acl
    Write-Log "ACL updated successfully"
} catch {
    Write-Log "Warning: Could not set ACL. If BACKUP CERTIFICATE fails with OS Error 5, grant manually." "WARN"
}

$cerPath = "$WorkingFolder\$CertificateName.cer"
$pvkPath = "$WorkingFolder\$CertificateName.pvk"

$s3Sql = @"
USE master;
GO

BACKUP CERTIFICATE [$CertificateName]
TO FILE = '$cerPath'
WITH PRIVATE KEY (
    FILE = '$pvkPath',
    ENCRYPTION BY PASSWORD = '$PVKPassword'
);
GO
"@

Write-Log "Exporting certificate and private key..."
Invoke-Sqlcmd -ServerInstance $SourceServer -Database master -Query $s3Sql
Write-Log "Verifying export files..."

if (-not (Test-Path $cerPath)) { throw ".cer file not created at $cerPath" }
if (-not (Test-Path $pvkPath)) { throw ".pvk file not created at $pvkPath" }

$cerSize = (Get-Item $cerPath).Length
$pvkSize = (Get-Item $pvkPath).Length
Write-Log "  .cer created: $cerPath ($cerSize bytes)"
Write-Log "  .pvk created: $pvkPath ($pvkSize bytes)"

# #endregion

# ============================================================================
# #region PHASE S.4 - CONVERT .PVK + .CER TO .PFX
# ============================================================================
# pvk2pfx.exe bundles Microsoft-proprietary .pvk + .cer into industry-standard
# PKCS#12 .pfx format that Azure can consume.
#
# KL-S-08: pvk2pfx.exe requires FULL Windows SDK install — the "Signing Tools
# for Desktop Apps" sub-component alone does NOT include pvk2pfx.
#
# Parameters:
#   -pvk: input private key file (from Phase S.3)
#   -pi:  input password (decrypts the .pvk)
#   -spc: input public cert file ("Software Publisher Certificate" - legacy term)
#   -pfx: output PKCS#12 file
#   -po:  output password (encrypts the new .pfx)
# ============================================================================

Write-Phase "PHASE S.4 - CONVERT .PVK + .CER TO .PFX"

$pfxPath = "$WorkingFolder\$CertificateName.pfx"

Write-Log "Running pvk2pfx.exe..."
Write-Log "  Tool: $pvk2pfxPath"
Write-Log "  Input .pvk: $pvkPath"
Write-Log "  Input .cer: $cerPath"
Write-Log "  Output .pfx: $pfxPath"

# Using same password for PFX as PVK (procedural simplicity for POC)
# In production: generate separate PFX password and store both in Key Vault
& $pvk2pfxPath -pvk $pvkPath -pi $PVKPassword -spc $cerPath -pfx $pfxPath -po $PVKPassword

if (-not (Test-Path $pfxPath)) { throw ".pfx file not created at $pfxPath" }
$pfxSize = (Get-Item $pfxPath).Length
Write-Log "  .pfx created: $pfxPath ($pfxSize bytes)"

# #endregion

# ============================================================================
# #region PHASE S.5 - CONVERT .PFX TO BASE64 STRING
# ============================================================================
# Azure REST APIs use JSON (text) payloads — binary .pfx cannot be transmitted
# directly. Base64 encoding creates a text-safe representation using 64 printable
# characters (A-Z, a-z, 0-9, +, /).
#
# KL-S-10: Base64 is ENCODING, not encryption. Adds 33% size overhead but
# provides zero security. The .pfx password remains the actual protection.
#
# Expected: 2,678-byte .pfx -> 3,572-char Base64 string (approx 33% expansion)
# ============================================================================

Write-Phase "PHASE S.5 - CONVERT .PFX TO BASE64"

$base64Path = "$WorkingFolder\$CertificateName.pfx.base64.txt"

Write-Log "Reading .pfx bytes..."
$pfxBytes = [System.IO.File]::ReadAllBytes($pfxPath)
Write-Log "  Read $($pfxBytes.Length) bytes from .pfx"

Write-Log "Converting to Base64..."
$pfxBase64 = [System.Convert]::ToBase64String($pfxBytes)
Write-Log "  Base64 length: $($pfxBase64.Length) characters"

# Sanity check: PKCS#12 files always start with MII when Base64 encoded
if ($pfxBase64.Substring(0, 3) -ne "MII") {
    Write-Log "WARNING: Base64 does not start with 'MII' - may not be valid PKCS#12" "WARN"
} else {
    Write-Log "  Valid PKCS#12 signature (starts with MII)"
}

Write-Log "Saving Base64 to: $base64Path"
$pfxBase64 | Out-File -FilePath $base64Path -Encoding ASCII

# #endregion

# ============================================================================
# #region PHASE S.6 - UPLOAD CERTIFICATE TO SQL MI
# ============================================================================
# Add-AzSqlManagedInstanceTransparentDataEncryptionCertificate uploads the
# Base64-encoded certificate to the MI's internal Azure-managed cryptographic
# store. After upload, the cert is NOT visible in sys.certificates on MI —
# this is deliberate Azure security design (KL-S-13).
#
# KL-S-11: Cmdlet name uses "ManagedInstance" not "Instance" (Az.Sql 6.4.1+)
# KL-S-12: Both -PrivateBlob and -Password require SecureString
#
# The silent completion of this cmdlet is authoritative confirmation of upload.
# The only definitive verification is a successful RESTORE in Phase S.8.
# ============================================================================

Write-Phase "PHASE S.6 - UPLOAD CERTIFICATE TO SQL MI"

Write-Log "Loading Base64 string..."
$pfxBase64String = Get-Content $base64Path -Raw
$pfxBase64String = $pfxBase64String.Trim()
Write-Log "  Loaded $($pfxBase64String.Length) characters"

Write-Log "Converting to SecureString (KL-S-12)..."
$securePrivateBlob = ConvertTo-SecureString -String $pfxBase64String -AsPlainText -Force
$securePassword = ConvertTo-SecureString -String $PVKPassword -AsPlainText -Force

Write-Log "Uploading certificate to SQL MI..."
Write-Log "  This takes 30-60 seconds as Azure propagates to MI internal store..."

try {
    Add-AzSqlManagedInstanceTransparentDataEncryptionCertificate `
        -ResourceGroupName $MIResourceGroup `
        -ManagedInstanceName $MIName `
        -PrivateBlob $securePrivateBlob `
        -Password $securePassword | Out-Null
    Write-Log "Certificate upload completed (silent success = authoritative confirmation)"
    Write-Log "Note: Cert is NOT visible in sys.certificates on MI - Azure internal store (KL-S-13)"
} catch {
    Write-Log "Certificate upload failed: $($_.Exception.Message)" "ERROR"
    throw
}

# #endregion

# ============================================================================
# #region PHASE S.7 - BACKUP DATABASE TO URL
# ============================================================================
# Creates a SAS-authenticated SQL credential on the source server, then backs
# up the encrypted database directly to Azure Blob Storage.
#
# Credential NAME must match the blob URL EXACTLY — SQL Server matches by URL
# prefix to locate the right credential for the BACKUP command.
#
# Security note: the backup file remains encrypted in the blob. TDE does NOT
# decrypt during backup — the backup file contains encrypted data pages.
# This preserves the compliance guarantee throughout transit.
#
# KL-S-14: 'IDENTITY' is reserved in T-SQL — bracket it as [Identity] when
# used as a column alias.
# ============================================================================

Write-Phase "PHASE S.7 - BACKUP DATABASE TO URL"

$blobBaseUrl = "https://$BackupStorageAccount.blob.core.windows.net/$BackupContainer"
$bakUrl = "$blobBaseUrl/$SourceDatabase.bak"

$s7Sql = @"
USE master;
GO

-- Drop existing credential if present (idempotent)
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = '$blobBaseUrl')
BEGIN
    DROP CREDENTIAL [$blobBaseUrl];
    PRINT 'Existing credential dropped';
END
GO

-- Create credential with SAS token
CREATE CREDENTIAL [$blobBaseUrl]
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET = '$SASToken';
GO

-- Backup encrypted database directly to blob
BACKUP DATABASE [$SourceDatabase]
TO URL = '$bakUrl'
WITH COMPRESSION,
     STATS = 10,
     FORMAT,
     INIT,
     NAME = '$SourceDatabase - Full Database Backup (TDE)';
GO
"@

Write-Log "Creating credential + BACKUP DATABASE TO URL on $SourceServer..."
Write-Log "  Target: $bakUrl"
Invoke-Sqlcmd -ServerInstance $SourceServer -Database master -Query $s7Sql -Verbose
Write-Log "Backup completed. .bak file now in blob storage (still encrypted)"

# #endregion

# ============================================================================
# #region PHASE S.8 PREP - GENERATE MI-SIDE T-SQL SCRIPT
# ============================================================================
# Phase S.8 (RESTORE on MI) must be executed via SSMS connected to SQL MI —
# PowerShell on Node1 cannot run T-SQL on MI remotely for this operation.
# This section generates the T-SQL script the operator will run on MI.
#
# The script includes:
#   - Credential creation on MI (same SAS token, different server)
#   - RESTORE DATABASE FROM URL (no MOVE clause needed — MI manages files)
#   - Validation queries (Phase S.9)
# ============================================================================

Write-Phase "PHASE S.8 PREP - GENERATE MI-SIDE T-SQL SCRIPT"

$miSqlPath = "$WorkingFolder\Execute_On_MI_${SourceDatabase}.sql"

$miSql = @"
-- ============================================================================
-- TDE MIGRATION - EXECUTE ON SQL MI ONLY
-- Database: $SourceDatabase
-- Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
-- ============================================================================
-- Prerequisites (verify before running):
--   - Connected to: $MIName.public.<dns-zone>.database.windows.net,3342
--   - Login with restore privileges on MI
--   - Certificate was uploaded via Add-AzSqlManagedInstance...Certificate
-- ============================================================================

USE master;
GO

-- ============================================================================
-- Phase S.8 Step 1: Create matching credential on MI
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = '$blobBaseUrl')
BEGIN
    DROP CREDENTIAL [$blobBaseUrl];
    PRINT 'Existing credential dropped on MI';
END
GO

CREATE CREDENTIAL [$blobBaseUrl]
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET = '$SASToken';
GO

SELECT name AS CredentialName,
       credential_identity AS IdentityType,
       create_date AS CreatedOn
FROM sys.credentials
WHERE name LIKE '%$BackupContainer%';
GO

-- ============================================================================
-- Phase S.8 Step 2: RESTORE DATABASE FROM URL
-- ============================================================================
-- MI reads the encrypted .bak, uses the certificate uploaded in Phase S.6
-- to decrypt the data pages, and materializes the database.
-- If this fails with error 33111, the certificate upload did not work -
-- re-run Phase S.6 of the master script.
-- ============================================================================

RESTORE DATABASE [$SourceDatabase]
FROM URL = '$bakUrl';
GO

-- ============================================================================
-- Phase S.9 Step 1: Validate TDE state is preserved
-- Expected: encryption_state=3, Algorithm=AES, KeyLength=256, EncryptorType=CERTIFICATE
-- ============================================================================

SELECT
    DB_NAME(database_id) AS DatabaseName,
    encryption_state,
    CASE encryption_state
        WHEN 0 THEN 'No DEK present'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
    END AS StateDescription,
    key_algorithm AS Algorithm,
    key_length AS KeyLength,
    encryptor_type AS EncryptorType
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID('$SourceDatabase');
GO

-- ============================================================================
-- Phase S.9 Step 2: Validate database is online and accessible
-- ============================================================================

SELECT
    name AS DatabaseName,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel,
    is_encrypted AS IsEncrypted,
    create_date AS CreatedOn
FROM sys.databases
WHERE name = '$SourceDatabase';
GO

-- ============================================================================
-- Phase S.9 Step 3: Row count validation (update with your table names)
-- Replace table names below with your actual schema
-- ============================================================================

USE [$SourceDatabase];
GO

-- Example validation - REPLACE WITH ACTUAL TABLE NAMES FROM YOUR SCHEMA
-- SELECT 'Table1' AS TableName, COUNT(*) AS RowCnt FROM dbo.Table1
-- UNION ALL
-- SELECT 'Table2', COUNT(*) FROM dbo.Table2;

-- Alternative: auto-discover all tables
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    p.rows AS RowCnt
FROM sys.schemas s
INNER JOIN sys.tables t ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
ORDER BY s.name, t.name;
GO

PRINT 'TDE Migration validation complete';
PRINT 'Compare row counts above with source server to confirm parity';
GO
"@

$miSql | Out-File -FilePath $miSqlPath -Encoding UTF8
Write-Log "MI-side T-SQL script generated: $miSqlPath"
Write-Log ""
Write-Log "NEXT STEPS FOR OPERATOR:" "ACTION"
Write-Log "  1. Open SSMS and connect to: $MIName.public.<dns-zone>.database.windows.net,3342" "ACTION"
Write-Log "  2. Open script: $miSqlPath" "ACTION"
Write-Log "  3. Execute (F5)" "ACTION"
Write-Log "  4. Verify encryption_state=3, Algorithm=AES, KeyLength=256" "ACTION"
Write-Log "  5. Verify row counts match source" "ACTION"

# #endregion

# ============================================================================
# #region MIGRATION SUMMARY
# ============================================================================

Write-Phase "MIGRATION SUMMARY"

Write-Log "On-prem phases (S.1 through S.7): COMPLETE"
Write-Log "Remaining phases (S.8 and S.9):   REQUIRE MANUAL EXECUTION ON MI"
Write-Log ""
Write-Log "Artifacts produced in $WorkingFolder :"
Get-ChildItem $WorkingFolder -File | ForEach-Object {
    Write-Log "  $($_.Name) ($($_.Length) bytes)"
}
Write-Log ""
Write-Log "Cert in blob: $bakUrl"
Write-Log "Log file:     $logFile"
Write-Log "MI script:    $miSqlPath"
Write-Log ""
Write-Log "TDE Migration orchestration complete. Execute MI-side script to finish." "SUCCESS"

# #endregion
