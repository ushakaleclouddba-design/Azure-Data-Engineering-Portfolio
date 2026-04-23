# Appendix O — Azure Monitor, Log Analytics & Alerting

Enterprise-grade observability POC for Azure SQL Managed Instance and Azure Data Factory.

## POC Summary

**Status:** ✅ Complete (April 8, 2026)
**POC #:** DBA Tracker #4
**DP-300 Domain:** D3 — Monitoring & Performance

## What Was Built

| Component | Name | Region |
|-----------|------|--------|
| Log Analytics Workspace | `usha-loganalytics-poc` | West US 2 |
| SQL MI Diagnostic Setting | SQLMI-Diagnostics (allLogs) | West US 2 |
| ADF Diagnostic Setting | ADF-Diagnostics (PipelineRuns + ActivityRuns) | East US |
| Alert — SQL MI High CPU | Alert-SQLMI-HighCPU (>80%, Severity 2) | East US |
| Alert — ADF Pipeline Failure | Alert-ADF-PipelineFailure (>0, Severity 2) | East US |

## Validated KQL Queries

5 production KQL queries validated against live Log Analytics data:

1. **ADF Activity Run History** — base query returning all activities
2. **ADF Pipeline Failures Filter** — failed activities in last 24 hours
3. **Activity Duration Analysis** — performance trend analysis
4. **SQL MI High CPU Events** — CPU monitoring via AzureMetrics table
5. Pipeline run history for audit trails

## Key Learnings (KL-O-01 through KL-O-05)

- **KL-O-01:** ADF data lives in `ADFSandboxActivityRun`, NOT `AzureDiagnostics`
- **KL-O-02:** SQL MI CPU lives in `AzureMetrics`, NOT regular Log Analytics tables
- **KL-O-03:** 15-60 minute propagation delay after saving diagnostic settings (normal)
- **KL-O-04:** ADF activity Status has 4 values: Queued, InProgress, Succeeded, Failed
- **KL-O-05:** Cross-region data transfer incurs egress charges (East US ADF → West US 2 LAW)

## Files in This Folder

| File | Purpose |
|------|---------|
| `Appendix_O_Azure_Monitor_v1.docx` | Full POC walkthrough with embedded KQL screenshot |
| `README.md` | This file |

## Resume Bullets Earned

- Implemented Azure Monitor observability for Azure SQL MI and Azure Data Factory with Log Analytics workspace, SQL MI allLogs diagnostic settings, ADF pipeline/activity diagnostics, and 5 validated production KQL queries — establishing enterprise-grade observability foundation for regulated banking workloads.

- Created metric-based Azure Monitor alert rules for Azure SQL Managed Instance (CPU >80%, Severity 2) and Azure Data Factory (PipelineFailedRuns >0, Severity 2) with 5-minute evaluation frequency — establishing proactive monitoring pattern replacing legacy SQL Agent alert infrastructure.

- Authored and validated 5 production KQL queries for Log Analytics covering activity history, failure filtering, duration analysis, and CPU metrics — discovering and documenting the `ADFSandboxActivityRun` table (Microsoft documentation gap) as a Key Learning.

## References

- [Azure Monitor overview](https://learn.microsoft.com/en-us/azure/azure-monitor/overview)
- [Log Analytics workspace overview](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview)
- [KQL query reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)

## Related Portfolio Documents

- **Bible v14** — Full migration guide with Appendix O integrated (00-Portfolio-Docs/)
- **Appendix Q (LRS Migration)** — Sibling POC in 06-LRS-Migration/
- **Appendix S (TDE Migration)** — Sibling POC in 07-TDE-Migration/

## Author

Usha Kale | Senior Cloud DBA / Azure Data Engineer | OrgSpire Inc.

GitHub: [ushakaleclouddba-design/Azure-Data-Engineering-Portfolio](https://github.com/ushakaleclouddba-design/Azure-Data-Engineering-Portfolio)
