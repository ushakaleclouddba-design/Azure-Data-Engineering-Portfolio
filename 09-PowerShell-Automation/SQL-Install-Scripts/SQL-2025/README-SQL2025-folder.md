# SQL Server 2025 Install Scripts

PowerShell scripts for unattended SQL Server 2025 Enterprise Developer Edition installation with CU2 patch.

---

## Files

| File | Purpose |
|------|---------|
| `Install-SQL2025-LocalNode.ps1` | Single-node install (run on target node) |
| `Install-SQL2025-FromNode4.ps1` | Orchestrator — parallel install on 2 nodes via CredSSP |
| `SQL2025-Config.ini` | Unattended setup configuration file |

---

## Build Information

- **SQL Server:** 2025 Enterprise Developer Edition
- **Cumulative Update:** CU2 (KB5075211)
- **Final Build:** 17.0.4015.4
- **Compatibility Level:** 170
- **Tested OS:** Windows Server 2022 Datacenter
- **SSMS:** Version 22 (required for SQL 2025)

---

## What's New in SQL Server 2025

This script installs the AI-ready database with new features:
- **VECTOR data type** — native vector storage for embeddings
- **EXTERNAL MODEL** — register Azure OpenAI / external models in SQL
- **DiskANN vector index** — high-performance approximate nearest neighbor search
- **VECTOR_SEARCH** — semantic queries in T-SQL
- **JSON enhancements** — native JSON type, JSON index (up to 2GB per row)
- **RegEx support** — regular expressions built into T-SQL
- **REST API support** — system stored procedure for REST calls
- **ZSTD backup compression** — modern compression algorithm
- **Optimized locking** — reduced lock escalation issues

---

## Use Case 1 — Single Node Install

Use `Install-SQL2025-LocalNode.ps1` when:
- Installing on one node
- You're RDP'd into the target
- You want simple line-by-line steps

**How:**
1. RDP to target node
2. Open PowerShell as Administrator
3. Run script (or copy-paste each step)

**Time:** ~50 min (install + CU + reboot)

**Note:** CU2 returns exit code **3010** which means "success, reboot required." Script handles this automatically.

---

## Use Case 2 — Parallel Install on Multiple Nodes

Use `Install-SQL2025-FromNode4.ps1` when:
- Installing on Node5 AND Node6 simultaneously
- You have an existing SQL 2025 install on Node4 (with files)
- You want parallel execution

**How:**
1. Ensure files are on Node4 at `C:\SQLInstall\`
2. RDP to Node4
3. Run script from Node4
4. Both nodes install in parallel (~50 min total instead of 100 min sequential)

**Time:** ~50 min for both nodes (parallel via CredSSP)

---

## Configuration File (`SQL2025-Config.ini`)

Key settings (matches SQL 2022 config style):
- **Features:** SQLENGINE, REPLICATION, FULLTEXT, CONN, BC
- **Default instance:** MSSQLSERVER (port 1433)
- **Mixed mode auth:** SQL + Windows
- **Data paths:** `C:\data`, `C:\log`, `C:\backup`
- **TempDB:** 4 files, 64 MB initial size
- **TCP/IP:** Enabled
- **Microsoft Update:** Disabled (offline lab — `UPDATEENABLED="False"`)

---

## Prerequisites

### On source/control node
- `C:\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso` (~1.18 GB)
- `C:\SQLInstall\SQL2025-Config.ini`
- `C:\SQLInstall\SQLServer2025-KB5075211-x64.exe` (~394 MB)

### On target nodes
- Joined to AD domain
- Min 4 GB RAM (8 GB recommended)
- Min 80 GB free C: drive
- WinRM enabled
- For CredSSP install: server role enabled on target

### Tooling
- **SSMS 22** required to connect to SQL 2025 (older SSMS won't work properly)
- ODBC Driver 18 (installed with SQL 2025)

---

## Download URLs

- **SQL Server 2025 ISO:** https://www.microsoft.com/en-us/sql-server/sql-server-downloads → "Download Enterprise Developer edition"
- **CU2 (KB5075211):** https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2025/cumulativeupdate2
- **SSMS 22:** https://aka.ms/ssms/22/release/vs_SSMS.exe
- **Build versions reference:** https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2025/build-versions

---

## Verification After Install

```powershell
# After reboot, verify version (note: ODBC 180 path, not 170)
& "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\SQLCMD.EXE" `
    -S . -E -C `
    -Q "SELECT @@VERSION"

# Expected output:
# Microsoft SQL Server 2025 (RTM-CU2) (KB5075211) - 17.0.4015.4 (X64)
```

**Important flag:** `-C` (capital C) means "trust server certificate." Required because ODBC 18 defaults to encrypted connections with strict certificate validation, and SQL Server's self-signed cert isn't in the trust store.

---

## Quick Test — VECTOR Data Type

```sql
USE master;
CREATE DATABASE AITest;
USE AITest;

CREATE TABLE Embeddings (
    id INT IDENTITY PRIMARY KEY,
    description NVARCHAR(200),
    embedding VECTOR(3)
);

INSERT INTO Embeddings (description, embedding) VALUES 
    ('apple',  CAST('[0.1, 0.2, 0.3]'  AS VECTOR(3))),
    ('banana', CAST('[0.15, 0.25, 0.35]' AS VECTOR(3))),
    ('car',    CAST('[0.9, 0.8, 0.7]'  AS VECTOR(3)));

SELECT id, description, embedding FROM Embeddings;
```

If this works, vector storage is operational. From here you can:
- Create DiskANN indexes
- Register EXTERNAL MODELs (Azure OpenAI)
- Run VECTOR_SEARCH queries

---

## Known Issues / Tips

1. **CU2 requires reboot** — exit code 3010 is normal, not an error
2. **ODBC path differs from SQL 2022** — use `\180\` not `\170\`
3. **Self-signed cert** — use `-C` flag with sqlcmd or import certificate
4. **CU1 was pulled by Microsoft** — install CU2 (KB5075211) directly, skip CU1 (KB5074901)
5. **SSMS 20.x won't work properly** — must upgrade to SSMS 22

---

## Related Files

- Parent README: `../README.md`
- SQL 2022 versions: `../SQL-2022/`
- Troubleshooting: `../Documentation/SQL_Install_Troubleshooting_Log.md`
