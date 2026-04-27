# SQL Server 2022 Install — Complete Troubleshooting Log
## Srini VMware Lab — 3-Node Deployment with CU24

**Date:** April 22-23, 2026
**Engineer:** Usha Kale | Senior Cloud DBA / Azure Data Engineer — OrgSpire Inc.
**Outcome:** ✅ **SUCCESS — All 3 nodes running SQL Server 2022 CU24 (16.0.4245.2)**

---

## Final State Achieved

```
✅ SRINI-NODE1: SQL 2022 CU24 (16.0.4245.2) - Running
✅ SRINI-NODE2: SQL 2022 CU24 (16.0.4245.2) - Running
✅ SRINI-NODE3: SQL 2022 CU24 (16.0.4245.2) - Running
✅ SSMS 22 installed on srinidcmaster
✅ Connected to all 3 instances
✅ CredSSP delegation configured for all 3 nodes
✅ Domain: srinidc.com (NetBIOS: SRINIDC)
```

---

## Environment

| Component | Details |
|-----------|---------|
| Domain | srinidc.com (NetBIOS: SRINIDC) |
| Domain Controller | srinidcmaster (192.168.68.7) |
| Target Nodes | SRINI-NODE1 (.8), SRINI-NODE2 (.9), SRINI-NODE3 (.10) |
| Hypervisor | VMware Fusion Pro 13 on Intel Mac |
| Guest OS | Windows Server 2022 Datacenter |
| SQL Version | SQL Server 2022 Developer Edition |
| CU Applied | CU24 (KB5080999) — 16.0.4245.2 |

---

## 8 Errors Resolved

### Error #1 — Kerberos Double-Hop (Mount-DiskImage)

**Error:** HRESULT 0x80070002 - "The system cannot find the file specified"
**Cause:** Kerberos credentials don't forward across double-hop for Mount-DiskImage via UNC
**Fix:** Push-then-install pattern — Copy-Item to admin share, then Invoke-Command with LOCAL paths

### Error #2 — Microsoft Update Download Failure

**Error:** -2022834173 (Facility 1902.3)
**Cause:** UPDATEENABLED="True" requires internet, nodes offline
**Fix:** Set UPDATEENABLED="False" in ConfigurationFile.ini

### Error #3 — Stale Config on Nodes

**Error:** Same -2022834173 after config edit
**Cause:** Edited config on DC didn't propagate to nodes
**Fix:** Explicit re-push via Copy-Item to each node

### Error #4 — Wrong Domain Name

**Error:** -2061893626 (Facility 1306.6) "srini\Domain Admins does not exist"
**Cause:** Hardcoded "srini" but actual NetBIOS is "SRINIDC"
**Fix:** Use `$env:USERDOMAIN\Domain Admins` (dynamic resolution)

### Error #5 — Script File Corruption

**Error:** "C:\Temp\SQL-Scripts\2-Install-SQL.ps1 not found" on nodes (weirdly)
**Cause:** Multi-purpose paste block overwrote install script with orchestration wrapper
**Fix:** Use `Set-Content -Value $variable` instead of piped heredocs

### Error #6 — Session Pollution

**Error:** PSComputerName tags on local commands, ghost remote execution
**Cause:** Unknown stale session state in PowerShell
**Fix:** Close and reopen PowerShell window (fresh session)

### Error #7 — DPAPI Delegation Failure (ROOT CAUSE)

**Error:** -2068774911 (Facility 1201.1) "Error generating XML document"
**Inner:** HRESULT 0x80090345 "Computer must be trusted for delegation"
**Cause:** SQL Setup uses DPAPI to encrypt sa password. Requires credential delegation.
**Fix:** Enable CredSSP (client on DC, server on targets), use `-Authentication Credssp`

### Error #8 — CredSSP Scope Miss on Node1

**Error:** "A computer policy does not allow the delegation of the user credentials"
**Cause:** Node1 wasn't in the `-DelegateComputer` list when CredSSP was first enabled
**Fix:** Re-run `Enable-WSManCredSSP -Role Client -DelegateComputer "NODE1","NODE2","NODE3"`

---

## The Winning Architecture

```
srinidcmaster (Domain Controller)
  │
  ├── 1. Copy-Item to \\NODE\C$\SQLInstall\ (admin share push)
  │
  ├── 2. Enable-WSManCredSSP -Role Client -DelegateComputer ...
  │
  └── 3. Invoke-Command -Credential $cred -Authentication Credssp
          │
          └── Each node runs install script LOCALLY
              ├── DPAPI works (credentials delegated)
              ├── setup.exe succeeds
              └── SQL Server installed
```

---

## Key Learnings (KL-SQL-01 through 08)

| # | Learning |
|---|----------|
| KL-SQL-01 | Mount-DiskImage can't use UNC from remote PS session — use push-then-install |
| KL-SQL-02 | UPDATEENABLED=True needs internet — use False for offline environments |
| KL-SQL-03 | Config edits don't auto-propagate — always re-push after changes |
| KL-SQL-04 | Never hardcode domain names — use $env:USERDOMAIN |
| KL-SQL-05 | Heredoc pastes can corrupt files — use Set-Content -Value $variable |
| KL-SQL-06 | Session pollution needs fresh PowerShell — don't debug ghost states |
| KL-SQL-07 | SQL Setup needs CredSSP for DPAPI sa password encryption |
| KL-SQL-08 | CredSSP delegation list is explicit — include ALL target nodes |

---

## Verification (3 Authoritative Sources)

### Registry
```powershell
(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\Setup").Version
```

### sqlcmd (most reliable)
```powershell
& sqlcmd -S . -E -Q "SELECT @@VERSION, SERVERPROPERTY('ProductUpdateLevel'), SERVERPROPERTY('ProductUpdateReference')"
```

### SSMS T-SQL
```sql
SELECT 
    SERVERPROPERTY('ProductVersion') AS Version,
    SERVERPROPERTY('ProductUpdateLevel') AS CU,
    SERVERPROPERTY('ProductUpdateReference') AS KB
```

### Final Verification Result
```
srini-node1 | 16.0.4245.2 | CU24 | KB5080999  ✅
srini-node2 | 16.0.4245.2 | CU24 | KB5080999  ✅
srini-node3 | 16.0.4245.2 | CU24 | KB5080999  ✅
```

---

## Portfolio Resume Bullets

### Bullet 1 — Enterprise SQL Automation with CredSSP
Architected and implemented enterprise-grade parallel SQL Server 2022 deployment across a 3-node Active Directory domain using PowerShell Invoke-Command with CredSSP authentication delegation, successfully applying Cumulative Update 24 (16.0.4245.2) to all instances through a fully automated push-then-install workflow.

### Bullet 2 — Root Cause Debugging at Scale
Diagnosed and resolved 8 distinct SQL Server installation failures through systematic Setup Bootstrap log analysis and facility/error code interpretation: Kerberos double-hop (HRESULT 0x80070002), Microsoft Update offline (-2022834173), NetBIOS domain mismatch (-2061893626), DPAPI delegation (HRESULT 0x80090345, -2068774911), and additional configuration/session state issues.

### Bullet 3 — Advanced PowerShell Remoting Architecture
Designed a repeatable "push-then-install" enterprise SQL Server deployment architecture: admin-share file distribution (`\\node\C$\`) from a control domain controller, CredSSP delegation configuration for DPAPI credential forwarding during SQL Setup's XML serialization, parallel job orchestration, and dual-source verification (Registry + T-SQL SERVERPROPERTY) — eliminating RDP and interactive sessions.

---

**Document version:** 2.0 FINAL
**Author:** Usha Kale — OrgSpire Inc.
**Session outcome:** ✅ SUCCESS — Three-node SQL Server 2022 CU24 lab operational
