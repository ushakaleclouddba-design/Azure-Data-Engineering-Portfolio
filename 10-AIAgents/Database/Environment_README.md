# Environment

Lab environment notes for the AI Agent assessment POC.

## Test Lab (VirtualBox 7-node domain `ushadc.com`)

| Node | Role | SQL Version | Notes |
| --- | --- | --- | --- |
| Node1 | AG Primary | SQL 2019 CU32 | UshaAg19 availability group |
| Node2 | AG Secondary | SQL 2019 CU32 | Synchronous commit |
| Node3 | Standalone | SQL 2022 CU24 | Idle |
| Node4 | Standalone | SQL 2022 CU24 | Idle (occasional CMS connection drops) |
| Node5 | CMS Host + SSIS | SQL 2019 CU32 | Hub for fan-out, has SSIS catalog |
| Node6 | Standalone | SQL 2022 CU24 | Idle |
| Node7 | Standalone | SQL 2025 RTM | Newer install |
| Node8 | Standalone | SQL 2025 RTM | Newer install |

## CMS Configuration

- CMS Host: `Node5`
- CMS Group: `UshaDC_Estate`
- Domain: `ushadc.com` (Windows Server 2022 Datacenter DC)
- All servers registered via Windows authentication

## Run Statistics

- Single-server assessment: ~2–10 seconds per server (depending on DB count)
- Full estate fan-out (8 servers): ~30–60 seconds end-to-end
- Output `.xlsx`: 8 per-server tabs + 4 estate-level tabs

## Known Issues Encountered During Development

- **SSPI Kerberos errors after VM resume:** Time skew from suspended VMs caused transient "Cannot generate SSPI context" failures. Resolved by `w32tm /resync /force` on affected nodes; agent's per-server try/catch meant the partial run still produced output.
- **EPPlus indexer overload ambiguity in PowerShell:** `Cells[$row, $col]` with expression-based column index occasionally bound to the wrong overload. Resolved with `[int]` casts and `.Item(...)` method calls. See inline comments in the agent.

---

*Part of the [Azure Data Engineering Portfolio](../../README.md) — `10-AIAgents` POC*
