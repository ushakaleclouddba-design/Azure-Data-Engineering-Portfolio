# Appendix S — TDE Migration Scripts

Companion automation scripts for Appendix S: TDE Certificate Migration from on-premises SQL Server to Azure SQL Managed Instance.

## Files in This Folder

| File | Purpose |
|------|---------|
| `Invoke-TDEMigration.ps1` | Master orchestrator — automates Phases S.1 through S.7 |
| `README.md` | This file — usage instructions |

## What the Master Script Does

`Invoke-TDEMigration.ps1` automates all 9 phases of the Microsoft-documented native TDE migration method:

| Phase | Description | Where It Runs |
|-------|-------------|----------------|
| S.1 | Create source database (optional) | Node1 PowerShell |
| S.2 | Enable TDE on source (optional) | Node1 PowerShell |
| S.3 | Export certificate + private key (BACKUP CERTIFICATE) | Node1 PowerShell → SQL |
| S.4 | Convert .pvk + .cer → .pfx (pvk2pfx) | Node1 PowerShell |
| S.5 | Convert .pfx → Base64 string | Node1 PowerShell |
| S.6 | Upload certificate to SQL MI (Az PowerShell) | Node1 PowerShell → Azure |
| S.7 | BACKUP DATABASE TO URL | Node1 PowerShell → SQL |
| S.8 | RESTORE DATABASE FROM URL | **Manual on MI via SSMS** |
| S.9 | Validate TDE state + row parity | **Manual on MI via SSMS** |

**Why S.8 and S.9 are manual:** PowerShell on Node1 cannot execute T-SQL on Azure SQL MI remotely for these operations. The master script auto-generates a T-SQL file for the operator to run in SSMS connected to MI.

## Prerequisites

### On Node1 (or wherever you run the script)

1. **Windows SDK — FULL install**
   Download: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/
   ⚠️ The "Signing Tools for Desktop Apps" sub-component alone does NOT include `pvk2pfx.exe` (see KL-S-08). Install the complete SDK (~3.6 GB).

2. **Az PowerShell module**
   ```powershell
   Install-Module -Name Az.Sql -Force
   ```

3. **Active Azure session**
   ```powershell
   Connect-AzAccount
   ```

4. **SqlServer module** (for Invoke-Sqlcmd)
   ```powershell
   Install-Module -Name SqlServer -Force
   ```

### In Azure (pre-create)

1. **SQL Managed Instance in Ready state**
2. **Storage account with blob container** for backup staging
3. **SAS token for the container** with permissions: Read, Add, Create, Write, Delete, List
   - HTTPS only
   - 24+ hour expiry
   - Do NOT include leading `?` when copying the token

## Usage

### Basic Example

```powershell
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
```

### Get Help

```powershell
Get-Help .\Invoke-TDEMigration.ps1 -Full
Get-Help .\Invoke-TDEMigration.ps1 -Examples
```

### After Running

The script will output several files in your `WorkingFolder`:

| File | Contents |
|------|----------|
| `<CertName>.cer` | X.509 public certificate (DER) |
| `<CertName>.pvk` | Private key (Microsoft format, encrypted) |
| `<CertName>.pfx` | PKCS#12 bundle (industry standard) |
| `<CertName>.pfx.base64.txt` | Base64 encoding of .pfx for JSON transport |
| `Execute_On_MI_<DBName>.sql` | T-SQL script for manual MI-side execution |
| `logs\TDE_Migration_<DBName>_<timestamp>.log` | Full audit log |

### Complete the Migration (Manual Step)

After the master script completes Phases S.1–S.7:

1. Open SSMS
2. Connect to MI: `<MIName>.public.<dns-zone>.database.windows.net,3342`
3. Open the auto-generated script: `C:\TDE_Backup\Execute_On_MI_<DBName>.sql`
4. Execute (F5)
5. Verify results:
   - `encryption_state = 3` (Encrypted)
   - `Algorithm = AES`, `KeyLength = 256`
   - Row counts match source

## Parameters Reference

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-SourceServer` | Yes | On-prem SQL Server hostname or IP |
| `-SourceDatabase` | Yes | TDE database name |
| `-CertificateName` | Yes | TDE certificate name on source |
| `-PVKPassword` | Yes | Password for .pvk encryption |
| `-MIResourceGroup` | Yes | Azure RG containing the MI |
| `-MIName` | Yes | MI name (not FQDN) |
| `-BackupStorageAccount` | Yes | Azure storage account name |
| `-BackupContainer` | Yes | Container name (must exist) |
| `-SASToken` | Yes | SAS token (without leading `?`) |
| `-WorkingFolder` | No | Default: `C:\TDE_Backup` |
| `-SDKVersion` | No | Default: `10.0.28000.0` |
| `-SkipPhaseS1S2` | No | Default: `$true` (skip DB creation) |
| `-LogFolder` | No | Default: `C:\TDE_Backup\logs` |

## Key Learnings Embedded in This Script

The script includes inline references to Key Learnings documented in Appendix S:

- **KL-S-03**: SQL service account permissions on working folder (ACL set automatically)
- **KL-S-08**: Windows SDK full install required for pvk2pfx (validated at startup)
- **KL-S-09**: Certificate must reach target BEFORE database (enforced by phase order)
- **KL-S-10**: Base64 is encoding, not encryption (documented in Phase S.5 comments)
- **KL-S-11**: Az.Sql cmdlet naming (uses correct `ManagedInstance` form)
- **KL-S-12**: `-PrivateBlob` and `-Password` are SecureString (handled)
- **KL-S-13**: Uploaded cert not visible in sys.certificates (noted in log output)
- **KL-S-14**: IDENTITY reserved keyword (handled in generated T-SQL)

## Error Handling

The script uses `$ErrorActionPreference = "Stop"` — any failure halts execution and logs the error. Common issues:

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| `pvk2pfx.exe not found` | Signing Tools only install | Full Windows SDK install |
| `No Azure session` | `Connect-AzAccount` not run | Connect first |
| `Az.Sql missing` | Module not installed | `Install-Module Az.Sql -Force` |
| OS Error 5 on BACKUP CERTIFICATE | Service account permissions | Verify working folder ACL |
| Error 33111 on RESTORE | Cert upload failed | Re-run Phase S.6 |

## Reference Documents

- **Bible v14** — `SQL_Azure_Migration_Technical_Guide_v14.docx` (Appendix S full walkthrough)
- **Standalone Appendix S** — `Appendix_S_TDE_Options_Playbook_v5.docx`
- **Microsoft Learn** — https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/tde-certificate-migrate

## Author

Usha Kale | Senior Cloud DBA / Azure Data Engineer | OrgSpire Inc.

GitHub: [ushakaleclouddba-design/Azure-Data-Engineering-Portfolio](https://github.com/ushakaleclouddba-design/Azure-Data-Engineering-Portfolio)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 22, 2026 | Initial release — 9-phase orchestrator with auto-generated MI-side script |
