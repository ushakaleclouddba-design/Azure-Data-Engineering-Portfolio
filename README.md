# ☁️ Azure Data Engineering Portfolio

A production-grade Azure Data Engineering portfolio covering 12 end-to-end POCs — SQL Server to Azure migrations, ADF medallion pipelines, Azure Monitor, LRS, TDE, Always On AG with MI Link, PowerShell automation, and AI agent integration. Built by a Senior Cloud DBA with 15+ years in banking and financial services.

---

## 🌟 What This Portfolio Demonstrates

- SQL Server to Azure SQL Managed Instance migration via DMS, LRS, and Azure Migrate
- ADF Medallion Architecture — Bronze/Silver/Gold on ADLS Gen2 with SHIR
- Azure Monitor with KQL queries, alerts, and Log Analytics
- Always On Availability Groups with MI Link (Distributed AG pattern)
- TDE migration with certificate export/import to Azure SQL MI
- PowerShell automation for SQL Server installation and configuration
- AI agent integration — SQLMigratePlus built on Claude API ReAct loop
- SOX/PCI audit trail patterns for banking compliance

---

## 🏗️ Architecture Overview

```
On-Premises SQL Server (VirtualBox Lab — 9 nodes)
         |
         v
Azure Data Factory (usha-adf-poc) — SHIR-Node5
         |
         v
ADLS Gen2 (ushaadfpocadls) — Bronze / Silver / Gold
         |
         v
Azure SQL Managed Instance (usha-sqlmi-poc)
         |
         v
Azure Monitor + Log Analytics — KQL alerting
         |
         v
Databricks (usha-databricks-poc) — Gold Analysis notebook
```

---

## 📁 Repository Structure

```
Azure-Data-Engineering-Portfolio/
│
├── 00-Portfolio-Docs/                    # Master tracker, Bible, resume, session starters
├── 01-VHD-LiftShift/                     # Azure Migrate agentless VM lift-and-shift
├── 02-ADF-ADLS-Pipeline/                 # ADF Medallion pipeline — 8 POCs, SHIR, Key Vault
├── 04-Azure-Monitor/                     # Log Analytics, KQL queries, CPU/pipeline alerts
├── 05-SQLMI-Migration/                   # DMS online migration — 14 banking databases
├── 06-LRS-Migration/                     # Log Replay Service — 141K rows, 3 DBs, 100% parity
├── 07-TDE-Migration/                     # TDE certificate migration to Azure SQL MI
├── 08b-AlwaysOn-AG-and-MI-Link/          # Always On AG + Distributed AG → MI Link
├── 09-PowerShell-Automation/             # SQL Server install scripts, dbatools automation
├── 10-AIAgents/                          # SQLMigratePlus AI migration agent (Claude API)
├── InterviewPreparation/                 # 73 DE/DBA interview questions with answers
├── Newbee-Documentation/                 # Onboarding guides for new DBAs
│
├── archive/                              # Older tracker versions
├── .gitignore
└── README.md
```

---

## 📋 POC Summary

| # | POC | Key Tech | Status |
|---|-----|----------|--------|
| 01 | VHD Lift-and-Shift | Azure Migrate, VirtualBox | ✅ Complete |
| 02 | ADF Medallion Pipeline | ADF, ADLS Gen2, SHIR, Key Vault, Databricks | ✅ Complete |
| 04 | Azure Monitor | Log Analytics, KQL, Alert Rules | ✅ Complete |
| 05 | SQL MI Migration via DMS | DMS online, 14 DBs, SSISDB, Azure-SSIS IR | ✅ Complete |
| 06 | LRS Migration | Log Replay Service, continuous mode, tail-log cutover | ✅ Complete |
| 07 | TDE Migration | TDE cert export/import, Azure SQL MI | ✅ Complete |
| 08b | Always On AG + MI Link | WSFC, Distributed AG, SQL MI Link | ✅ Complete |
| 09 | PowerShell Automation | SQL install scripts, CredSSP, dbatools | ✅ Complete |
| 10 | AI Agents (SQLMigratePlus) | Claude API, PowerShell ReAct loop, Excel TCO | ✅ Complete |

---

## 🔑 Key POC Highlights

### POC 02 — ADF Medallion Pipeline
- Master/Branch orchestration pattern with ForEach over 3 branches
- SHIR-Node5 ingestion from on-premises SQL Server 2019
- Key Vault Managed Identity for secret management
- Mapping Data Flows: Bronze → Silver (Conditional Split) → Gold (aggregate + interest rate)
- Databricks notebook triggered from ADF for Gold analysis
- SOX audit trail via StoredProc_AuditLog
- GitHub CI/CD integration + Azure Monitor alerting

### POC 05 — SQL MI Migration via DMS
- Online migration (CDC) of 14 banking databases — zero data loss
- SSISDB deployed on Azure SQL MI
- SSIS packages validated via Azure-SSIS Integration Runtime
- Azure Migrate assessment: 87% PaaS readiness, $60K annual savings

### POC 06 — LRS Migration
- 141,050 rows migrated across 3 databases with 100% row count parity
- Continuous-mode LRS with transaction log chain integrity
- Tail-log backup with NORECOVERY for cutover
- Full AG coexistence pattern — migrated without removing from AG

### POC 10 — SQLMigratePlus (AI Migration Agent)
- 5-stage workflow: Assess → Decide → Migrate → Handoff → Day-2 Ops
- Claude API tool-use agent with PowerShell ReAct loop
- Anti-hallucination grounding with real server data
- 11-sheet Excel TCO report (Azure/AWS/GCP)
- Automated Handoff stage: connection strings + migration receipts
- Append-only JSON audit log for compliance
- Live at: [sqlmigrateplus.com](https://sqlmigrateplus.com)

---

## 🏦 Banking Domain Context

All POCs are designed around banking and financial services compliance requirements:

- **SOX** — append-only audit logs, pipeline audit trail
- **PCI DSS** — data masking, encrypted backups, TDE
- **FFIEC** — database security controls, access governance
- **HMDA** — fair lending data patterns (see Banking Lakehouse repo)

---

## 🧪 Lab Environment

| Component | Details |
|-----------|---------|
| VirtualBox Lab | 9 VMs — USHADC, Node1–Node8 (192.168.68.20–.28) |
| Domain | ushadc.com |
| SQL Versions | SQL Server 2019 (Node1–Node6), SQL Server 2025 (Node7–Node8) |
| Existing AG | UshaAg19 (Node1–Node2, SQL 2019) — healthy |
| SHIR | SHIR-Node5 (3 nodes, v5.64.9558.1) |
| Azure SQL MI | usha-sqlmi-poc (West US 2, General Purpose 4 vCores, free tier) |
| ADF | usha-adf-poc (East US) |
| ADLS Gen2 | ushaadfpocadls (landing / processed / curated) |
| Databricks | usha-databricks-poc |

---

## 🚀 Quick Start

1. Clone this repository
2. Navigate to the POC folder of interest
3. Follow the `README.md` or playbook `.docx` inside each folder
4. Scripts are organized by phase/step — execute in numbered order

### Prerequisites
- Azure subscription with SQL MI, ADF, ADLS Gen2
- VirtualBox or VMware lab with SQL Server 2019+
- PowerShell 7+ with Az module
- Self-Hosted Integration Runtime configured on lab node

---

## 📚 Related Repositories

| Repo | Description |
|------|-------------|
| [Banking-Lakehouse-Databricks](https://github.com/ushakaleclouddba-design/Banking-Lakehouse-Databricks) | 2.26M loan records, Bronze/Silver/Gold, Claude API risk narratives |
| [SQLMigratePlus](https://github.com/ushakaleclouddba-design/SQLMigratePlus) | AI migration agent portfolio site |

---

## 👤 Author

**Usha Kale**
Azure Data Engineer & Senior Cloud DBA | 15+ years in Banking & Financial Services

- 🌐 [sqlmigrateplus.com](https://sqlmigrateplus.com)
- 💼 [LinkedIn](https://www.linkedin.com/in/usha-kale-56a336a)
- 🐙 [GitHub](https://github.com/ushakaleclouddba-design)

---

## 📜 License

MIT License. See `LICENSE` for details.
