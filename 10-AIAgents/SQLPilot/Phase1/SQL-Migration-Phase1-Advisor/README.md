# SQL Server → Azure Migration Assessment

## AI-Augmented Migration POC — Phase 1 of 2

> An LLM-augmented assessment and recommendation tool for SQL Server-to-Azure migration. This is **Phase 1**: the data + decision layer. **Phase 2** (in development) builds an agentic loop on top of this foundation.

---

## What this is, honestly

This tool runs a deterministic SQL Server assessment pipeline that calls Anthropic Claude at three specific decision points:

1. To recommend an Azure SQL Managed Instance SKU per server
2. To pick the best migration target per server and write a justification narrative
3. To synthesize an estate-wide migration strategy

**Total LLM calls per 8-server run: ~17. Total LLM cost: ~$0.50-0.70.**

The AI is **bounded and auditable**. It does not generate SQL, compute costs, or make any claim that isn't backed by a number the deterministic pipeline produced. The architect retains decision authority; the AI provides reasoning support and consistent narrative writing.

This is **AI-augmented automation**, not an autonomous agent. The Phase 2 deliverable adds genuine agentic capabilities (planning loop, tool use, self-correction) on top of this foundation.

---

## How much AI is actually in this?

Honest breakdown:

| Component | Approx. Lines | AI involvement |
|---|---|---|
| Connection / CMS handling | ~200 | None |
| 17-section T-SQL queries | ~800 (separate .sql) | None — hand-written |
| Severity scoring rules | ~150 | None — rule-based |
| Cost calculations (DC, VM, MI) | ~300 | None — deterministic math |
| Azure Retail Prices API integration | ~150 | None — REST call |
| Excel rendering | ~1,200 | None |
| **AI calls (Claude API)** | **~250** | **Yes** |
| Methodology / metadata tracking | ~150 | None |

**~8% of the code is AI.** The other 92% is the plumbing that lets the AI reason over real data.

This is intentional. AI helps where judgment matters; deterministic code handles everything that needs to be reproducible and auditable.

---

## What it does

For every SQL Server it can reach (single instance or fanned out via Central Management Server):

1. **Assesses** — runs a 17-section read-only T-SQL assessment covering instance config, security, schema, agent jobs, HA topology, replication, etc.
2. **Prices** — calculates 1-year cost for four migration targets (DC-DC, Azure VM PAYG, Azure VM BYOL, Azure SQL Managed Instance) using the **live Azure Retail Prices API** for cloud and industry reference rates for on-prem.
3. **Reasons** — calls Claude (or Azure OpenAI; provider-abstracted) to recommend an MI SKU, pick the best target, write a per-server justification narrative, and synthesize an estate-wide migration strategy.
4. **Reports** — produces a polished Excel workbook with Executive Summary, per-server detail tabs, methodology/sources, and remediation plan.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│           Generate_Assessment_Report.ps1  (Phase 1)                  │
│                                                                      │
│  1. Assessment    →  T-SQL queries (17 sections, hand-written)       │
│                      ↓                                               │
│  2. Pricing       →  Azure Retail Prices API   (live)                │
│                      Industry reference rates  (on-prem)             │
│                      ↓                                               │
│  3. AI reasoning  →  Anthropic Claude / Azure OpenAI                 │
│                      • MI SKU sizing                                 │
│                      • Target recommendation + narrative             │
│                      • Estate-wide strategy synthesis                │
│                      ↓                                               │
│  4. Reporting     →  Excel via ImportExcel module                    │
└──────────────────────────────────────────────────────────────────────┘

                              ↓ Phase 2 (in development)

┌──────────────────────────────────────────────────────────────────────┐
│              Migration Agent  (Phase 2 — coming soon)                │
│                                                                      │
│  Genuine agentic loop:                                               │
│    • Observes assessment data from Phase 1                           │
│    • Plans remediation/migration steps                               │
│    • Calls tools dynamically (assessment, costing, etc)              │
│    • Verifies each step, self-corrects on failure                    │
│    • Operates with human approval gates                              │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Sample output

The Phase 1 tool produces an Excel workbook with these tabs:

| Tab | What's in it |
|---|---|
| Executive Summary | Estate at a glance + AI-generated migration strategy + cost summary table |
| How to Read This Report | 60-second orientation tab |
| Summary | Per-server inventory + estate totals |
| Critical Findings | Every High-severity finding across the estate |
| Remediation Plan | Mapped fixes for each finding |
| Methodology & Sources | Pricing sources, AI config, caveats |
| One per server | 17 sections of assessment data + AI recommendation block |

See [`docs/Architecture_Board_Guide.md`](docs/Architecture_Board_Guide.md) for the full guide written for an architecture review board audience.

---

## Quick start

### Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- PowerShell modules: `SqlServer`, `ImportExcel`
- An Anthropic API key (for AI features) — or Azure OpenAI deployment
- Read access to the SQL Server(s) being assessed

### Setup

```powershell
# Install required modules
Install-Module SqlServer -Scope CurrentUser
Install-Module ImportExcel -Scope CurrentUser

# Set your Anthropic API key as an environment variable
$env:ANTHROPIC_API_KEY = 'sk-ant-...'
```

### Configure

Edit two variables at the top of `Generate_Assessment_Report.ps1`:

```powershell
$SqlInstance = 'YourServerName'        # The SQL Server you connect to
$CmsGroup    = 'YourEstateGroupName'   # CMS group to fan out to (or '' for single-server)
```

### Run

```powershell
.\Generate_Assessment_Report.ps1
```

Output: `Migration_Assessment_Report_YYYY-MM-DD_HHMM.xlsx`. Typical 8-server estate: ~3 minutes runtime, ~$0.50-0.70 in Anthropic API cost.

---

## Cost validation

Cloud cost numbers are cross-validated against the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator):

| Target | Calculator | Tool | Delta |
|---|---|---|---|
| Azure SQL MI (8 vCore GP) | $10,977/yr | $10,976/yr | within $1 ✓ |
| Azure VM (D8s v5 Windows) | $6,587/yr | $7,191/yr | +$604 (storage + egress, expected) ✓ |

Pricing is fetched live at run time. Each report's Methodology & Sources tab shows the exact fetch timestamp.

---

## Provider switching

Default provider is Anthropic Claude. Switching to Azure OpenAI requires changing one variable:

```powershell
$LlmProvider = 'AzureOpenAi'   # was 'Claude'
```

And setting three environment variables for the Azure OpenAI deployment.

For deployments where data residency matters, Azure OpenAI keeps the assessment data inside the customer's Azure tenant.

---

## What this is NOT

To set expectations honestly:

- **Not a complete AI agent.** This is Phase 1 — an LLM-augmented decision-support pipeline. The agentic loop is Phase 2.
- **Not a migration tool.** Read-only assessment; never modifies anything.
- **Not a replacement for human judgment.** The AI narrative supports the architect's decision; it doesn't make it.
- **Not for non-SQL-Server engines.** Oracle, PostgreSQL, etc. are out of scope.
- **Not enterprise scale yet.** Sequential per-server runs ~5-10 sec/server. For 100+ server estates, parallelization and a database-backed reporting layer would be the next investment.

---

## Roadmap

### Phase 1 (this repo) — AI-Augmented Assessment ✅

The deterministic assessment + LLM-augmented recommendation pipeline. Working today.

### Phase 2 — Migration Agent (in development)

A genuinely agentic system on top of Phase 1's output:

- Reads Phase 1 findings as input
- Plans a multi-step remediation/migration sequence
- Calls tools dynamically (re-runs assessments, fetches updated pricing, generates fix scripts)
- Verifies each step's outcome and self-corrects on failure
- Operates with human approval gates at each major milestone

This is what most people mean when they say "AI Agent" in 2026 — autonomous decision-making in a loop, not just calling an LLM at fixed checkpoints.

---

## Repository contents

```
.
├── README.md                          ← you are here
├── Generate_Assessment_Report.ps1     ← the Phase 1 tool
├── 01_Assessment_Script.sql           ← the T-SQL assessment that powers it
├── docs/
│   ├── Architecture_Board_Guide.md    ← detailed reading guide for the report
│   └── methodology.md                 ← cost methodology deep-dive
├── examples/
│   └── README.md                      ← description of sample outputs
├── .gitignore
└── LICENSE
```

---

## License

MIT. See [LICENSE](LICENSE).

---

## Acknowledgments

Built on top of:

- [Anthropic Claude](https://www.anthropic.com) — primary LLM provider
- [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) — live cloud pricing
- [ImportExcel PowerShell module](https://github.com/dfinke/ImportExcel) — Excel rendering
- [SqlServer PowerShell module](https://learn.microsoft.com/en-us/powershell/sqlserver/) — SQL Server connectivity

---

## Author

Usha Kale

This is a portfolio project demonstrating practical, calibrated application of LLMs to real database administration work. Feedback and discussion welcome via Issues.
