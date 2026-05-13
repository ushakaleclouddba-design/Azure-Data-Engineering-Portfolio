# SQLPilot

**SQL Server migration agent — DBA-as-pilot, AI-as-copilot.**

Migrates SQL Server estates from on-prem to Azure. The AI handles assessment, target decision-making, infrastructure provisioning, and database migration; the DBA approves at gates and owns the outcome.

**Status:** v0.9 — feature-complete demo. End-to-end demo proven Wed May 13, 2026.

---

## What's in the box

```
SQLPilot/
├── agent.ps1                      # Agent loop with tool-calling
├── kb.json                        # 8 Microsoft Learn citation topics
├── Build_SQLPilotDemoDB.sql       # Demo DB schema for the source server
├── tools/                         # The 7 real tools
│   ├── kb.ps1                     # KB lookups
│   ├── Phase1.ps1                 # Phase 1 wrapper integration
│   ├── restore.ps1                # BACKUP TO URL / RESTORE FROM URL
│   ├── terraform.ps1              # Terraform plan/apply/destroy wrapper
│   ├── day2.ps1                   # DBCC CHECKDB on all user DBs
│   ├── decide.ps1                 # KB-driven verdict aggregator
│   └── handoff.ps1                # Generates handoff document for app team
├── Terraform/                     # IaC for the Azure target VM
│   ├── versions.tf, variables.tf, network.tf, vm.tf, outputs.tf
│   ├── storage.tf                 # Blob container + SAS for backups
│   └── terraform.tfvars           # SECRET — gitignored
├── ui/                            # Single-page web UI
│   ├── server.ps1                 # HttpListener + 10 API endpoints
│   └── index.html                 # 5-screen SPA with light + dark mode
├── SQLPilot_Bible_2026-05-13.docx # Full project reference (13 pages)
└── SQLPilot_Runbook_2026-05-13.md # Working runbook
```

---

## Quick start

Requires: Windows + PowerShell 7+ + Terraform CLI + Azure CLI logged in.

```powershell
# 1. Generate Phase 1 assessment (separate repo, run from there)
cd ..\SQL_Migration_Assessment_Agent_AI
.\Generate_Assessment_Report.ps1

# 2. Start the UI server
cd ..\SQLPilot
.\ui\server.ps1

# 3. Open browser
Start-Process http://localhost:8765/
```

---

## Architecture

5-stage workflow:

| Stage | Name | What it does |
|---|---|---|
| 1 | Assess | Phase 1 estate findings, per-server verdict |
| 2 | Decide | KB-driven target picker (Azure VM / MI / SQL DB) with citations |
| 3 | Migrate | 8 sub-steps to stand up equivalent server (3 real, 5 Phase 3) |
| 4 | Handoff | Generated package for the app team |
| 5 | Day-to-day operations | Phase 3 roadmap |

The agent uses 7 real tools that wrap PowerShell cmdlets, SQL Server commands, and Terraform — all callable independently or orchestrated through the UI.

---

## What's proven end-to-end

- Real Phase 1 assessment with Microsoft Learn citations
- Real Terraform apply through UI button (~7 min, 12 Azure resources)
- Real database backup-and-restore through UI button (BACKUP TO URL / RESTORE FROM URL)
- Real DBCC CHECKDB through UI button
- Real handoff document generation
- Real Terraform destroy
- Light + dark mode UI

See `SQLPilot_Bible_2026-05-13.docx` for the complete reference.

---

## Demo

5-stage walk-through, ~15 minutes total. See section 9 of the bible for talk track.

---

## Phase 3 roadmap (not yet implemented)

- SQL logins migration (SID-preserving)
- SQL Agent jobs migration
- SSIS packages + SSISDB migration
- Linked servers + sp_configure + credentials migration
- Azure Backup vault auto-config
- Day-to-day tooling (dbatools, Ola Hallengren, First Responder Kit)
- Multi-DB and multi-server picker in UI
- Async HttpListener (for SSE support, fixing the v0.9 single-thread blocker)

---

## License

Internal Anthropic / proprietary.
