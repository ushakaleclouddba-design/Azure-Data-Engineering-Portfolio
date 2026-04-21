# Azure Data Engineering & DBA Portfolio

> Hands-on proof-of-concept portfolio demonstrating end-to-end Azure data platform capabilities across DBA (DP-300) and Data Engineering (DP-203) tracks.

**Usha Kale** — Senior Cloud DBA / Azure Data Engineer
**Certifications:** AZ-104 (Azure Administrator), DP-300 (Database Administrator), AZ-305 (Azure Solutions Architect)
**Targeting:** DP-203 (Azure Data Engineer Associate)

---

## Portfolio at a Glance

| Track | Completed | Total | Progress |
|---|---|---|---|
| **DBA POCs (DP-300)** | 6 | 30 | 20% |
| **Data Engineering POCs (DP-203)** | 8 | 20 | 40% |
| **PowerShell DBA Toolkit** | 1 | 32 | 3% |
| **Appendices (detailed walkthroughs)** | 1 (Q) | 16 | Growing |

---

## Repository Structure

```
Azure-Data-Engineering-Portfolio/
├── README.md                                                  (this file)
├── Bible/
│   └── SQL_Azure_Migration_Technical_Guide_v11.docx          (main reference, 13 migration approaches)
├── Tracker/
│   └── Azure_Portfolio_Master_Tracker_v3_0421.docx           (POC progress tracker)
├── Appendices/
│   └── Appendix_Q_LRS_Migration_to_SQL_MI_v7.docx            (LRS migration walkthrough)
├── Resume/
│   └── UshaKale_Resume_v3.docx
└── archive/
    └── (prior document versions for audit trail)
```

---

## Featured POCs

### POC #6 — Log Replay Service (LRS) Migration to SQL Managed Instance (April 20, 2026)

**Summary:** Executed end-to-end migration of 3 banking-themed databases from on-premises SQL Server 2019 to Azure SQL Managed Instance using raw Log Replay Service with 100% row count parity.

| Metric | Value |
|---|---|
| Rows migrated | 141,050 |
| Tables migrated | 13 across 3 databases |
| Migration method | LRS (continuous mode + tail-log cutover) |
| Row count parity | 100% |
| Azure spend | < $0.50 |
| Key Learnings documented | 14 |
| Microsoft Learn citations | 15 clickable links |

**Read full walkthrough:** [Appendices/Appendix_Q_LRS_Migration_to_SQL_MI_v7.docx](Appendices/Appendix_Q_LRS_Migration_to_SQL_MI_v7.docx)

---

### POC #1-5 — Earlier Completions (April 2026)

- **POC #1:** VHD Lift & Shift (Node5 → Azure VM) — complete server migration via disk capture
- **POC #2:** Azure Database Migration Service (DMS) Online Migration — 14 databases to Azure SQL MI with zero downtime
- **POC #3:** SSIS Integration Services Catalog on SQL MI with Azure-SSIS IR — hybrid SSIS execution via ADF
- **POC #4:** Azure Monitor + Log Analytics + Alerting — diagnostic settings, KQL queries, alert rules
- **POC #5:** Azure Migrate Appliance + 6-node Server Discovery — agentless WinRM-based discovery with 87% PaaS readiness score

Detailed walkthroughs for these POCs are preserved in the main Bible document (`Bible/SQL_Azure_Migration_Technical_Guide_v11.docx`).

---

### Data Engineering POCs (DP-203 Track)

**Completed (8 of 20):**

- ADF + ADLS Gen2 + SSIS + Medallion Architecture
- ADF Master/Branch Loan Processing Pipeline with Azure Key Vault integration
- ForEach iteration across branches (SF/SanRamon/Oakland)
- Bronze → Silver Mapping Data Flow (Conditional Split)
- Silver → Gold Mapping Data Flow (Aggregate)
- Databricks PySpark + Delta Lake + MERGE
- ADF → Databricks Notebook Trigger integration
- GitHub CI/CD for ADF Pipelines

---

## Lab Environment

**On-premises (Intel Mac Pro host):**
- VirtualBox 7-node domain lab (ushadc.com)
- Node1: SQL Server 2019 CU32, AG primary (UshaAg19)
- Node2: SQL Server 2019 CU32, AG secondary
- Node3-4, Node6: SQL Server 2022 CU24 (idle or HA)
- Node5: SQL Server 2019 CU32, SSIS, SHIR, Visual Studio 2026
- Domain Controller: USHADC (Windows Server 2022 Datacenter)

**Azure:**
- Azure Data Factory (usha-adf-poc)
- ADLS Gen2 (ushaadfpocadls — landing/processed/curated)
- Azure SQL Managed Instance (usha-sqlmi-poc) — GP 4 vCore, Free tier
- Azure Blob Storage (ushalrsbackup)
- Key Vault (usha-kv-poc)
- Databricks workspace (usha-databricks-poc)
- Log Analytics workspace (usha-loganalytics-poc)
- Self-Hosted Integration Runtime on Node5

---

## Technical Skills Demonstrated

**SQL Server & Migration:**
- Log Replay Service (LRS) — raw PowerShell/CLI orchestration
- Azure Database Migration Service (DMS)
- Azure Migrate (agentless + WinRM discovery)
- Always On Availability Groups — hybrid AG patterns
- BACKUP TO URL with SAS-based credentials
- Transaction log chain integrity management

**Azure Data Platform:**
- Azure Data Factory (Mapping Data Flows, ForEach, Script activities, Lookups)
- Azure Databricks (PySpark, Delta Lake, MERGE operations)
- Medallion architecture (Bronze → Silver → Gold)
- Azure SQL Managed Instance (VNet + public endpoint configurations)
- Azure Key Vault integration

**Automation & DevOps:**
- PowerShell scripting for Azure resource orchestration
- Azure CLI / Cloud Shell
- Azure Monitor + Log Analytics + KQL queries
- GitHub integration for ADF CI/CD

---

## Documents in This Repository

| Document | Purpose | Size |
|---|---|---|
| [Bible v11](Bible/SQL_Azure_Migration_Technical_Guide_v11.docx) | Main migration reference — 13 migration approaches with detailed comparison | ~820 KB |
| [Master Tracker v3](Tracker/Azure_Portfolio_Master_Tracker_v3_0421.docx) | POC progress across DBA + DE tracks | ~20 KB |
| [Appendix Q v7](Appendices/Appendix_Q_LRS_Migration_to_SQL_MI_v7.docx) | LRS Migration full walkthrough | ~715 KB |
| [Resume](Resume/UshaKale_Resume_v3.docx) | Current resume (v4 with LRS bullets coming soon) | ~30 KB |

---

## Contact

- LinkedIn: [linkedin.com/in/usha-kale](https://linkedin.com/in/usha-kale)
- GitHub: [@ushakaleclouddba-design](https://github.com/ushakaleclouddba-design)

---

*Last updated: April 21, 2026 — after LRS Migration POC completion*
