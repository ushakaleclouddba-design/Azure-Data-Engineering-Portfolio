# POC #8b — Always On AG and MI Link

> **Hybrid HA/DR solution: Brownfield extension of an existing 2-node Always On Availability Group to 3 replicas, then linking on-premises SQL Server 2022 to Azure SQL Managed Instance via Distributed Availability Group (MI Link).**

---

## TL;DR

This POC demonstrates building a complete hybrid HA/DR solution for SQL Server 2022 across two days:

- **Day 1 — Always On AG Build (POC #8b)**: Audited an existing 2-node SQL Server 2022 Always On AG, identified a latent quorum vulnerability, remediated by extending the WSFC cluster from 2 to 3 nodes, added a File Share Witness, and built a second 3-replica AG (UshaAg22MI) sharing the same cluster — earning portfolio credit for both greenfield design and brownfield remediation patterns.

- **Day 2 — MI Link Attempt (POC #10)**: Established bidirectional certificate trust between on-prem Node3 and Azure SQL MI, configured dual-authentication (Windows + Certificate) on the existing mirroring endpoint, created a Distributed Availability Group, and discovered (during validation) that SQL MI's `AlwaysUpToDate` update policy is irreversibly incompatible with on-prem SQL Server 2022 for MI Link. **Documented as a real-world architectural finding.**

---

## What's in this folder

| File | Purpose |
|------|---------|
| **POC8b_HAdr_Playbook.docx** | Master playbook (~150 pages). Day 1 + Day 2 + all blockers, troubleshooting log, full script library inline. |
| **POC8b_Scripts/** | 36 production-ready PowerShell + T-SQL scripts, organized alphabetically in execution order. |
| **Standalone_Migration_Newbee_Part1_Setup.docx** | Newbee-friendly migration guide (~30 pages). Concepts, prerequisites, MI provisioning. |
| **Standalone_Migration_Newbee_Part2_BackupRestore.docx** | Newbee-friendly migration guide (~30 pages). Method 1: Backup/Restore via Azure Blob, end-to-end. |

---

## Architecture

### Day 1 — UshaAg22MI 3-Replica AG (built on existing Ushaclu22 cluster)

```
                    Ushaclu22 WSFC
                  (3 nodes + witness)
        ┌──────────────┴──────────────┐
        │                             │
   UshaAg22 (existing)          UshaAg22MI (new)
   ┌────────────────┐         ┌──────────────────┐
   │ Node3 PR sync  │         │ Node3 PR sync    │
   │ Node4 SC sync  │         │ Node4 SC sync    │  ← auto-failover
   │                │         │ Node6 SC async   │  ← read-scale
   └────────────────┘         └──────────────────┘
       Loans_OnPrem,                Loans_OnPrem
       HRMgmt_OnPrem
```

- **Cluster**: Ushaclu22 WSFC, 3 nodes + File Share Witness
- **AGs**: UshaAg22 (existing brownfield) + UshaAg22MI (new greenfield)
- **Listener**: UshaAg22MI-Listener at 192.168.68.34:1435
- **Read-only routing**: directs ApplicationIntent=ReadOnly to Node6
- **Failover validated**: Node3 → Node4 → Node3 zero-data-loss

### Day 2 — MI Link Topology (planned vs blocked)

```
                Distributed AG (UshaAg22DAG)  ← created on Node3 ✅
          ┌────────────────┴─────────────────┐
          ▼                                   ▼
     UshaAg22MI                         AG_AzureSQLMI
     (Day 1, working)                   (auto-managed by SQL MI)
     ┌──────────┐                       ┌────────────────┐
     │ Node3 PR │ ←── cert auth ──→     │ usha-sqlmi-poc │
     │ Node4 SC │   (port 5023)         │   PRIMARY      │
     │ Node6 SC │                       │ AlwaysUpToDate │ ← BLOCKER
     └──────────┘                       └────────────────┘
```

**Phase 10.2 hit Microsoft's database format alignment requirement.** SQL Server 2022 source (format 974) cannot link to SQL MI on AlwaysUpToDate update policy (format 998). The policy change is irreversible per Microsoft Learn.

---

## What was built (validated working)

| Component | Status |
|-----------|--------|
| Ushaclu22 cluster extended 2 → 3 nodes | ✅ |
| File Share Witness (`\\USHADC\ClusterWitness\Ushaclu22`) | ✅ |
| UshaAg22MI 3-replica AG with sync + async + readable secondary | ✅ |
| Listener with read-only routing | ✅ |
| Failover Node3 → Node4 (and back) zero-data-loss | ✅ |
| Database master key + cert exchange Node3 ↔ SQL MI | ✅ |
| Cert-based mirroring endpoint (dual-auth pattern on port 5023) | ✅ |
| Distributed AG (UshaAg22DAG) created on Node3 | ✅ |
| MI Link to SQL MI on AlwaysUpToDate | ❌ Blocked (architectural) |

---

## Key learnings (interview gold)

The POC documents 7 senior-level gotchas worth quoting in interviews:

1. **PowerShell ISE is dead** for cluster/SQL admin — modules don't auto-load. Use regular admin console.
2. **SCM WMI provider** is a separate optional component on minimal SQL installs — easy to miss.
3. **Add-ClusterNode** silently fails if cluster service runs as LocalSystem instead of domain account.
4. **dbatools + Az PowerShell conflict** on Windows PowerShell 5.1 (shared `Azure.Identity.dll`). Use PowerShell 7 OR pick one.
5. **Connect-AzAccount** in admin/remote PowerShell sessions fails with "window handle" error. Use `-UseDeviceAuthentication`.
6. **`New-AzSqlInstanceServerTrustCertificate -PublicKey`** expects HEX format with `0x` prefix, NOT base64 (Microsoft docs misleading).
7. **SQL MI's `AlwaysUpToDate` update policy is IRREVERSIBLE.** Once enabled, MI Link with SQL Server 2022 is impossible. **Always run pre-flight diagnostic before cert work.**

The pre-flight diagnostic script (`Phase10-Step02-CheckMIDatabaseFormat-Node3.ps1`) detects this scenario in 5 seconds and saves hours of wasted setup work.

---

## How to use this content

### If you want to follow the build step-by-step
1. Read **`POC8b_HAdr_Playbook.docx`** (master playbook with all phases narrated).
2. Extract **`POC8b_Scripts/`** — scripts sort alphabetically in execution order.
3. Each script has full header documentation explaining purpose, prerequisites, and expected output.

### If you're learning Azure SQL MI migration from scratch
1. Read **`Standalone_Migration_Newbee_Part1_Setup.docx`** for Azure concepts and MI provisioning.
2. Read **`Standalone_Migration_Newbee_Part2_BackupRestore.docx`** for the simplest migration method (Backup → Blob → Restore).
3. Use a fresh test database (`BankDemo` with 5 rows) — no AG complexity needed.

### If you're preparing for an interview
1. Skim Section 10 (Troubleshooting Log) of the playbook — 7 gotchas with full root cause analysis.
2. Practice the "Interview Q&A" included in entry 10.3.7 about the AlwaysUpToDate blocker.
3. Use the resume bullets from Section 11 of the playbook.

---

## Environment used (lab)

- 7-node VirtualBox lab on Intel Mac (San Ramon, CA, PST)
- Windows Server 2022 Datacenter, SQL Server 2022 CU24
- Domain: USHADC0 (NetBIOS), goldfield.local (FQDN)
- Azure: Subscription 1, West US 2, GP_Gen5 4-vCore SQL MI

---

## Status

**Day 1 (POC #8b)**: ✅ COMPLETE  
**Day 2 (POC #10 — MI Link)**: 🟡 PARTIAL — On-prem infrastructure complete; cross-cloud join blocked by SQL MI update policy mismatch. Two paths forward documented (provision new MI with SQL 2022 update policy, or pivot to native backup/restore demo).

Last updated: April 29, 2026

---

## Related POCs in this portfolio

- **POC #03** — ADF Loan Processing / Medallion Architecture (✅)
- **POC #05** — SQL MI Migration via DMS (✅)
- **POC #07** — TDE Migration (✅)
- **POC #08b** — Always On AG and MI Link (this folder)
- **POC #10** — MI Link (consolidated into POC #8b documentation)

---

*Author: Usha Kale — Senior Cloud DBA / Azure Data Engineer · AZ-104 · DP-300 · AZ-305*
