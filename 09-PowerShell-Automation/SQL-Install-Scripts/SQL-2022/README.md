PowerShell scripts for unattended SQL Server 2022 Developer Edition installation with CU24 patch.


 File | Purpose |
|------|---------|
| `2-Install-SQL.ps1` | Per-node install script (runs locally on target via Invoke-Command) |
| `3-Install-All-Nodes.ps1` | Orchestrator — pushes files and runs parallel install across 3 nodes |
| `Install-SQL2022-Node7.ps1` | Standalone single-node install (line-by-line, run on target) |
| `SQL2022-Config.ini` | Unattended setup configuration file |

---

## Build Information

- **SQL Server:** 2022 Developer Edition
- **Cumulative Update:** CU24 (KB5080999)
- **Final Build:** 16.0.4245.2
- **Tested OS:** Windows Server 2022 Datacenter

---

## Use Case 1 — Standalone Single Node Install

Use `Install-SQL2022-Node7.ps1` when:
- Installing on one node at a time
- You're RDP'd into the target node
- You want simple line-by-line steps

**How:**
1. RDP to target node
2. Open PowerShell as Administrator
3. Run the script (or copy-paste each step)

**Time:** ~45 min (install + CU24)

---

## Use Case 2 — Multi-Node Parallel Install

Use `3-Install-All-Nodes.ps1` orchestrator with `2-Install-SQL.ps1` when:
- Installing on 2+ nodes simultaneously
- You have a Domain Controller as control node
- You want parallel execution (faster)

**How:**
1. Place install media on DC at `C:\SQLInstall\`
2. Configure CredSSP delegation
3. Run `3-Install-All-Nodes.ps1` from DC
4. Walk away ~25 min — both nodes install in parallel

**Time:** ~30-45 min for any number of nodes (parallel)

---

## Configuration File (`SQL2022-Config.ini`)

Key settings:
- **Features:** SQLENGINE, REPLICATION, FULLTEXT, CONN, BC
- **Default instance:** MSSQLSERVER (port 1433)
- **Mixed mode auth:** SQL + Windows
- **Data paths:** `C:\data`, `C:\log`, `C:\backup`
- **TempDB:** 4 files, 64 MB initial size
- **TCP/IP:** Enabled
- **Microsoft Update:** Disabled (offline lab — `UPDATEENABLED="False"`)

---

## Verification After Install

```powershell
# Check service is running
Get-Service MSSQLSERVER

# Verify version
& "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe" `
    -S . -E -Q "SELECT @@VERSION"

# Expected output:
# Microsoft SQL Server 2022 (RTM-CU24) (KB5080999) - 16.0.4245.2 (X64)
```

---

## Author

**Usha Kale** — Senior Cloud DBA / Azure Data Engineer

