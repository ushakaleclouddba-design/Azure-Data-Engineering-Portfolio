# Cost Methodology Deep-Dive

> Detailed walkthrough of how the agent computes each cost number. Companion to the Methodology & Sources tab in the generated Excel report.

---

## Pricing data sources

### Azure cloud pricing (live)

The agent calls the [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) at the moment the report is generated. Endpoint: `https://prices.azure.com/api/retail/prices`. No authentication required.

The agent fetches:

- VM hourly rate (Windows-priced) for the SKU sized to match the AI-recommended MI vCore count.
- Azure SQL MI hourly rate for the AI-recommended tier and vCore count.

Both calls are filtered to PAYG/Consumption pricing, exclude Spot/Low Priority variants, and use the `westus2` region (configurable).

### On-prem reference rates

Industry-typical 2026 reference rates for a mid-market enterprise. Used only for the DC-to-DC cost line.

| Component | Default Rate | Source |
|---|---|---|
| Hardware refresh | $12,000 / 5-year amortization | Industry estimate |
| Colocation + power | $3,600/year | Mid-market datacenter rate |
| Operational labor | $4,000/year | Allocated DBA labor per server |
| Storage (SAN) | $0.30/GB-month | Mid-tier SAN allocation |
| SQL Standard license | $3,586 per 2-core pack | Microsoft list price |
| SQL Enterprise license | $14,256 per 2-core pack | Microsoft list price |

These can be overridden in the agent script before running.

---

## VM cost calculation

```
Total VM Cost (annual) =
    (BaseHourly + LicenseHourlyAddOn) × 8760 hours
  + Storage GB × $0.135 × 12 months
  + $600 egress allowance
```

Where:

- **BaseHourly** comes from the Retail Prices API for the selected VM SKU (Windows-priced).
- **LicenseHourlyAddOn** is Microsoft's per-edition PAYG SQL license rate per core, multiplied by the core count of the VM:
  - Developer: $0.000/core/hour
  - Web: $0.020/core/hour
  - Standard: $0.115/core/hour
  - Enterprise: $0.460/core/hour
- For BYOL (Azure Hybrid Benefit), the LicenseHourlyAddOn is set to $0.

VM SKU is sized to **match the AI-recommended MI vCore count** so VM and MI are compared at equivalent compute.

### Calculator validation (D8s v5 Windows, 8 vCore)

| Source | Annual Cost |
|---|---|
| Azure Pricing Calculator (VM only) | $6,587 |
| This agent (VM + storage + egress) | $7,191 |
| Delta | +$604 (storage + egress overhead) |

The agent's number is intentionally slightly higher because the calculator's bare VM cost doesn't include managed disk storage or egress allowance.

---

## Azure SQL MI cost calculation

```
Total MI Cost (annual) =
    HourlyPrice × 8760 hours
  + AllocatedStorage GB × $0.1006 × 12 months
```

Where:

- **HourlyPrice** comes from the Retail Prices API for the AI-recommended tier (GeneralPurpose or BusinessCritical) and vCore count.
- **AllocatedStorage** is `max(database_size × 1.5, vCore × 32 GB)` — minimum allocation enforced.
- Storage rate of $0.1006/GB-month is calculator-validated (256 GB at 8 vCore GP shows $25.76/month in the calculator = $0.1006/GB-month).
- Backup storage is 100% of database size included free — not added.

### MI sizing floor

The agent enforces an **8 vCore minimum** for MI sizing. Both the LLM prompt and the parser code apply this floor. Below 8 vCore, the right answer is Azure SQL Database, not MI — 4 vCore MI is sub-minimal for production workloads.

### Calculator validation (8 vCore GP, 256 GB)

| Source | Annual Cost |
|---|---|
| Azure Pricing Calculator | $10,977 |
| This agent | $10,976 |
| Delta | -$1 |

Within $1 of calculator output. The MI cost number is the most defensible in the entire report.

### Hourly rate fallback table (calculator-validated)

If the live API filter fails, the agent uses a fallback table validated against the calculator:

| vCore | GeneralPurpose | BusinessCritical |
|---|---|---|
| 4 | $0.609/hr | $1.64/hr |
| **8** | **$1.218/hr** | **$3.29/hr** |
| 16 | $2.436/hr | $6.58/hr |
| 24 | $3.654/hr | $9.87/hr |
| 32 | $4.872/hr | $13.16/hr |
| 40 | $6.090/hr | $16.45/hr |
| 64 | $9.741/hr | $26.32/hr |
| 80 | $12.180/hr | $32.90/hr |

The 8 vCore GP rate ($1.218/hr) is the anchor: $888.95/month / 730 hours = $1.218/hour. Other rates extrapolate linearly.

---

## DC-to-DC cost calculation

```
Total DC Cost (annual) =
    HardwareRefresh / HardwareLifeYears
  + Colocation
  + OperationalLabor
  + StorageGB × StorageRate × 12
  + (SQL License if not Developer)
```

The SQL license cost depends on edition:

- **Developer**: $0 (free)
- **Standard**: SqlStdLicensePer2Cores × ceiling(coreCount / 2)
- **Enterprise**: SqlEntLicensePer2Cores × ceiling(coreCount / 2)

For a typical 8-core Standard server: 4 × $3,586 = $14,344/year just for the SQL license.

---

## Edition detection

The agent reads `SERVERPROPERTY('Edition')` and matches the string to assign the edition flag. **Order matters here** — SQL Server 2025 introduces the string "Enterprise Developer Edition" which contains both "Enterprise" and "Developer". This is licensed as Developer (free), not Enterprise.

The agent checks for "Developer" before "Enterprise" to avoid misclassification:

```powershell
if ($editionText -match 'Developer') { Edition = 'Developer' }
elseif ($editionText -match 'Enterprise') { Edition = 'Enterprise' }
elseif ($editionText -match 'Standard') { Edition = 'Standard' }
elseif ($editionText -match 'Web') { Edition = 'Web' }
```

This was a real bug discovered during validation — a SQL 2025 server's "Enterprise Developer Edition" was being priced as paid Enterprise (~$32K/year more expensive than reality).

---

## Caveats & Limitations

1. **PAYG list pricing only.** Real customer cost is typically 20-40% lower after Reserved Instances, Azure Hybrid Benefit, EA discounts, or Dev/Test pricing.

2. **On-prem rates are estimates.** Actual customer on-prem cost varies significantly based on hardware vendor, datacenter contract, existing operational scale, and whether DBA labor is shared across servers.

3. **Migration project cost not included.** Data transfer, application changes, dual-running, testing, and licensing transition are NOT in these numbers. Plan separately.

4. **AI narratives are non-deterministic.** Same input produces semantically equivalent but textually different output across runs. Recommendations themselves are stable.

5. **90-day freshness.** Azure pricing changes monthly. For decisions that depend on these numbers, regenerate the report within 90 days.

6. **VM sizing parity may overstate VM cost** for genuinely smaller workloads. The agent sizes the VM to match MI for fair comparison; if the workload genuinely needs less, the VM cost shown is conservative.
