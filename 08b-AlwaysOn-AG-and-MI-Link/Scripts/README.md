# UshaAg22MI Build Scripts — Day 1 + Day 2

Complete script library for the UshaAg22 + MI Link build covering:
- **Day 1 (April 28, 2026)**: POC #8b — UshaAg22MI 3-replica AG built brownfield on Ushaclu22 cluster
- **Day 2 (April 29, 2026)**: POC #10 — MI Link to Azure SQL MI (Phase 7-8-9 complete, Phase 10.1 success, Phase 10.2 blocked by AlwaysUpToDate)

**Total: 36 scripts + this README**

---

## Companion Document

The master playbook covering all phases is shipped as a separate Word document:
`UshaAg22_BuildPlaybook_v7.docx`

This README provides a quick index. The playbook has full execution narrative, troubleshooting log, and 7 senior-level gotchas captured.

---

## Execution Order

Scripts are named so they sort alphabetically in execution order:
`UshaAg22-Phase<N>-Step<NN>-<Description>-<TargetNode>.<ext>`

### Day 1 — UshaAg22MI Build (24 scripts)

| Phase | Scripts | Purpose |
|-------|---------|---------|
| 1 — Pre-flight | 2 | Cluster discovery, baseline checks |
| 2 — Cluster extension | 4 | Add Node6 to Ushaclu22 |
| 3 — Quorum | 2 | File share witness |
| 4 — AlwaysOn enable | 2 | Enable Hadr on Node6 + endpoint |
| 5 — AG creation | 7 | Loans_OnPrem + UshaAg22MI 3-replica |
| 6 — Listener + failover | 5 | Listener, read-only routing, failover/failback |

### Day 2 — MI Link Build (12 scripts)

| Phase | Scripts | Purpose | Status |
|-------|---------|---------|--------|
| 7 — Pre-flight | 3 | SQL MI network/auth tests + Az install | OK |
| 8 — Cert exchange | 7 | Bidirectional cert exchange Node3 / SQL MI | OK |
| 9 — Endpoint | 1 | Dual-auth (Windows + Cert) on existing endpoint | OK |
| 10 — DAG creation | 2 | Distributed AG (10.1 success) + diagnostic (10.2) | Partial |

---

## Critical Pre-flight Script (Run First!)

If repeating this build with a different SQL MI, **run this BEFORE Phase 7**:

```
UshaAg22-Phase10-Step02-CheckMIDatabaseFormat-Node3.ps1
```

It validates the SQL MI's update policy is compatible with on-prem SQL Server 2022 BEFORE you spend 25 minutes on cert exchange. The script will explicitly flag:
- COMPATIBLE (DatabaseFormat = SQLServer2022)
- HARD BLOCKER (DatabaseFormat = AlwaysUpToDate or SQLServer2025)

This is the gotcha that ended Day 2. AlwaysUpToDate is **irreversible** — discovering it AFTER cert work is wasted effort.

---

## Day 2 Blockers Documented (in playbook)

| Blocker | Where | Lesson |
|---------|-------|--------|
| Single endpoint per instance | 10.3.4 | Use ALTER ENDPOINT with WINDOWS NEGOTIATE CERTIFICATE |
| WAM/MFA token loop in SSMS | 10.3.5 | Pre-auth via portal browser before launching wizard |
| Public endpoint (docs vs reality) | 10.3.6 | SSMS wizard accepts public endpoint despite docs saying VNet-local only |
| AlwaysUpToDate irreversible | 10.3.7 | Run pre-flight diagnostic; explicitly select SQL Server 2022 update policy on new MI |

---

## Environment Notes

### Day 1 Lab
- 7-node VirtualBox lab, Intel Mac, San Ramon CA (PST)
- USHADC0 domain (NetBIOS), goldfield.local AD
- Ushaclu22 WSFC cluster with file share witness at \\\\USHADC\\ClusterWitness\\Ushaclu22
- Node3, Node4, Node6 running SQL Server 2022 CU24 (16.0.4245.2)
- Node3 = current primary of UshaAg22MI

### Day 2 Azure Resources
- Subscription: Azure subscription 1 (26f7a991-84b3-47b7-966b-f19cbb0379bf)
- Resource Group: Usha_SQLMI_POC
- SQL MI: usha-sqlmi-poc (West US 2, GP_Gen5, 4 vCore)
- Public endpoint: usha-sqlmi-poc.public.0f3157bbdbf7.database.windows.net,3342
- IMPORTANT: DatabaseFormat = AlwaysUpToDate (incompatible with SQL 2022 source)

### Passwords used (lab only - rotate for production!)
- DMK on Node3: UshaMK@2026!Banking#Strong
- Cert backup .pvk: CertBackup@2026!Banking#Strong
- SQL MI admin (ssisadmin): reset Apr 29, value in private notes

---

## How to Run

### PowerShell scripts (.ps1)
- Run from elevated Windows PowerShell on the indicated node
- Most run on Node3; some on Node5 (control node) or USHADC (DC)
- Az.Sql 6.4.1 required for Phase 8.4 cert upload

### T-SQL scripts (.sql)
- Run via SSMS connected to the indicated node
- Always check the database dropdown matches the script comment header
- Most run against master database

---

## Companion Newbee Migration Guide

For the practical migration walkthrough using a simple BankDemo database, see the separate documents:
- Migration_Walkthrough_Newbee_Phase1_v1.docx — Concepts + Prerequisites + MI Provisioning
- Migration_Walkthrough_Newbee_Phase2_v1.docx — Method 1: Backup/Restore via Azure Blob

These are standalone newbee-friendly guides, separate from this expert-level UshaAg22 build.

---

**Version**: v3 (April 29, 2026 — End of Day 2)
**Author**: Usha Kale, Senior Cloud DBA / Azure Data Engineer
**Project**: Azure Data Engineering Portfolio
