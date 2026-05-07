# 10 — AI Agent: SQL Server Migration Assessment

> Self-contained PowerShell agent that fans out across a SQL Server estate via Central Management Server, runs a 17-section read-only assessment per server, computes an MI Readiness Score, and produces a formatted Excel deliverable with executive summary, critical findings, and remediation plan.

**Completed:** May 6, 2026
**Track:** DBA / DP-300 + Engineering Tooling

---

## Why this is an "AI Agent"

This POC moves beyond traditional scripting into agentic patterns:

- **Goal-directed execution** — given a single configuration (CMS host + group), the agent autonomously discovers servers, decides what to assess, executes, captures, and synthesizes
- **Resilient, not brittle** — per-server failure handling means one bad node does not halt the run; the agent reasons about partial success and produces output anyway
- **Multi-stage synthesis** — raw findings get scored, ranked, and translated into actionable recommendations without human intervention
- **Self-explaining output** — the Excel deliverable includes a CIO-facing executive summary auto-generated from the data, not just a raw dump

The agent embodies the migration assessment workflow that a senior DBA would otherwise perform manually across 8 servers — collapsed into a single double-click execution.

---

## At a Glance

| Metric | Value |
| --- | --- |
| Servers assessed in test run | 8 (Node1–Node8 in lab) |
| Assessment sections per server | 17 |
| Total findings identified | 14 High + 28 Medium across the estate |
| Result-set capture method | DataTable via `Invoke-Sqlcmd` (typed columns) |
| Output format | Multi-tab `.xlsx` with executive summary, scoring, remediation |
| External dependencies | Two PowerShell modules, both auto-installed |
| Admin rights required | None (modules install to user profile) |
| Read-only against SQL Server | Yes — SELECT against `sys.*` and `msdb.*` only |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Generate_Assessment_Report.ps1                 │
│                    (PowerShell agent)                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
      ┌──────────────────────────────────────────────┐
      │  CMS Host msdb.dbo.sysmanagement_shared_*    │
      │  Returns list of registered servers          │
      └──────────────────────────────────────────────┘
                            │
                            ▼
      ┌──────────────────────────────────────────────┐
      │  For each server: Invoke-Sqlcmd with         │
      │  01_Assessment_Script.sql                    │
      │  → 17 DataTables captured                    │
      │  Per-server try/catch (resilient)            │
      └──────────────────────────────────────────────┘
                            │
                            ▼
      ┌──────────────────────────────────────────────┐
      │  Score, rank, synthesize:                    │
      │  - MI Readiness Score per server (0-100)     │
      │  - Estate-wide finding aggregation           │
      │  - Top 3 blocker identification              │
      │  - Pattern-matched remediation advice        │
      └──────────────────────────────────────────────┘
                            │
                            ▼
      ┌──────────────────────────────────────────────┐
      │  Excel workbook (ImportExcel + EPPlus):      │
      │  Executive Summary | Summary | Critical      │
      │  Findings | Remediation Plan | Per-server    │
      └──────────────────────────────────────────────┘
```

---

## What the Report Contains

The output `.xlsx` workbook has these tabs (left to right):

| Tab | Audience | Contents |
| --- | --- | --- |
| **Executive Summary** | CIO, hiring manager | Narrative + 6 headline tiles + top 3 blockers + per-server scoreboard |
| **Summary** | DBA team | Per-server roll-up table + estate totals |
| **Critical Findings** | DBA team / consultants | Sortable estate-wide list of all High and Medium findings |
| **Remediation Plan** | Migration engineers | Issue + tailored recommendation per finding |
| **Per-server tabs** | Audit trail | All 17 sections of detail per assessed server |

---

## How the MI Readiness Score Works

Each server starts at 100 and loses points per finding:

- **High severity findings:** -15 each
- **Medium severity findings:** -5 each

Score is mapped to a label:

| Score | Label | Meaning |
| --- | --- | --- |
| ≥ 85 | **Ready** (green) | Migrate first |
| 60 – 84 | **Conditional** (amber) | Remediate first, then migrate |
| < 60 | **Blocked** (red) | Lift-and-shift to Azure VM, or major remediation needed |

---

## The 17 Assessment Sections

Each per-server tab contains 17 sections covering:

1. Instance Summary
2. Instance Configuration (`sp_configure`)
3. Linked Servers
4. SQL Agent Jobs
5. Database Inventory
6. DB-Level Findings (FileStream, CLR, Temporal, CDC)
7. T-SQL Code Scan
8. Per-DB SKU Features
9. CLR Assemblies
10. Database Files
11. Availability Groups
12. Database Mirroring
13a. Log Shipping (Primary)
13b. Log Shipping (Secondary)
14a. Replication Subscribers
14b. Replication Publishers
15. Cloud Migration Matrix (Azure VM, AWS EC2, GCP, Azure SQL MI, Azure SQL DB, AWS RDS, GCP Cloud SQL)

---

## Running the Agent

### 3-Step Quick Start

1. Open `Generate_Assessment_Report.ps1` in Notepad. Edit these lines near the top:

   ```powershell
   $SqlInstance = 'Node5'              # Your SQL Server (or CMS host)
   $CmsGroup    = 'UshaDC_Estate'      # CMS group for fan-out (optional)
   ```

   For single-server mode, leave `$CmsGroup` empty.

2. Right-click `Generate_Assessment_Report.ps1` → **Run with PowerShell**.

3. When it finishes, a `Migration_Assessment_Report_<date>_<time>.xlsx` file appears in the same folder. Open it.

### Requirements

- PowerShell 5.1 or later (built into Windows 10+ / Server 2016+)
- `SqlServer` module (auto-installed)
- `ImportExcel` module (auto-installed)
- Read access to system views on each target SQL Server
- Windows authentication (default) or SQL login (optional)

### CMS Setup (one-time)

If you do not already have a Central Management Server:

1. SSMS → **View** → **Registered Servers** (Ctrl+Alt+G)
2. Right-click **Central Management Servers** → **Register Central Management Server**
3. Server name: your CMS host (e.g. `Node5`), Windows auth, **Test**, **Save**
4. Right-click your CMS host → **New Server Group** (e.g. `UshaDC_Estate`)
5. Right-click the group → **New Server Registration** (add each server)

The CMS registry lives in `msdb` on the host you designated. The agent reads it directly via T-SQL — no SSMS needed at run time.

---

## Sample Output (8-server lab estate)

| Server | Score | Label | High | Medium | Top Issue |
| --- | --- | --- | --- | --- | --- |
| Node7 | 85 | **Ready** | 1 | 0 | SQL Agent Job: syspolicy_purge_history |
| Node8 | 85 | **Ready** | 1 | 0 | SQL Agent Job: syspolicy_purge_history |
| Node1 | 60 | Conditional | 2 | 2 | SQL Agent Job: Output File Cleanup |
| Node2 | 75 | Conditional | 1 | 2 | SQL Agent Job: syspolicy_purge_history |
| Node6 | 75 | Conditional | 1 | 2 | SQL Agent Job: syspolicy_purge_history |
| Node3 | 60 | Conditional | 2 | 2 | SQL Agent Job: Output File Cleanup |
| Node4 | 55 | **Blocked** | 2 | 3 | SQL Agent Job: syspolicy_purge_history |
| Node5 | 0 | **Blocked** | 4 | 17 | SQL Agent Job: syspolicy_purge_history |

**Estate verdict:** 2 Ready, 4 Conditional, 2 Blocked. Most-frequent High blocker estate-wide is Microsoft-shipped `syspolicy_purge_history` job using risky subsystems — single fix replicated across all servers.

---

## Files in This Folder

| File | Purpose |
| --- | --- |
| `Generate_Assessment_Report.ps1` | The agent (1,700+ lines, fully commented) |
| `01_Assessment_Script.sql` | The 17-section read-only T-SQL assessment |
| `README.md` | This file |

---

## Engineering Notes

### Why PowerShell instead of Python

- Target audience runs this on SQL Server hosts where PowerShell is already installed
- `Invoke-Sqlcmd` returns DataTables with typed columns — no string parsing
- No external dependencies beyond two modules that auto-install

### Why `ImportExcel` plus direct EPPlus

- Single Windows binary, no Python install
- Most sheets are written cell-by-cell via `EPPlus` rather than `Export-Excel` because layout requirements (merged banner rows, custom row heights, conditional cell fills) outgrew what `Export-Excel` handles cleanly

### Read-only safety

- Every SQL is `SELECT` against `sys.*` and `msdb.*` system views
- No DDL, no DML, no `sp_configure` changes
- Worst case: 2–10 seconds of DMV CPU on each target server

### Resilience patterns

- Per-server `try`/`catch` — one failure does not halt the run
- Auto-installed modules go to user profile (no admin needed)
- Robust script directory resolution (works under dot-source, ISE, paste-into-PowerShell)
- `-TrustServerCertificate` for self-signed certs in lab environments

---

## What I Would Do Next

1. **Monthly scheduled runs** — track MI Readiness Score trending up as findings get remediated
2. **Cross-server comparison view** — pivot findings by category to spot patterns (e.g., every server with legacy linked-server provider)
3. **Cost integration** — Cloud Migration Matrix tells what is *possible*; cost data tells what is *smart*
4. **HTML companion report** — for stakeholders without Excel access
5. **JSON export** — feed downstream Power BI / Grafana dashboards

---

*Part of the [Azure Data Engineering Portfolio](../README.md)*
