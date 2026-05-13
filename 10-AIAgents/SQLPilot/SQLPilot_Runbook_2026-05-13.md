# SQLPilot — Runbook
## Wednesday May 13 → Friday May 15 demo, 2026

**Last updated:** Wed May 13, 12:30 PM PT — after the full demo was proven end-to-end through the UI.
**Demo:** Friday May 15.
**Audience:** DBA team, architecture, sponsor.

---

## What SQLPilot is

A migration agent for SQL Server estates moving on-prem databases to Azure. The story is **DBA-as-pilot, AI-as-copilot**: the AI handles assessment, decision-making, infrastructure provisioning, and database migration; the DBA approves at gates and owns the outcome.

Scope for v1: Azure-only (AWS / GCP are matrix display only).

---

## Current state — Wed May 13, 12:30 PM PT

### Backend — feature-complete, all 7 tools real and verified

| Tool | File | Status | Last verified live |
|---|---|---|---|
| Phase 1 assessment | `tools/Phase1.ps1` | Real | Wed 9:05 AM — produced JSON for Node5 |
| KB lookups (Microsoft Learn citations) | `tools/kb.ps1` | Real | 8 topics, baseline |
| Apply Terraform (plan/apply/destroy) | `tools/terraform.ps1` | Real | Wed 11:25 AM through UI — 12 resources, 7m43s |
| Restore database (BACKUP TO URL) | `tools/restore.ps1` | Real | Wed 11:57 AM through UI — 2016 rows, 10s |
| Validate database (DBCC CHECKDB) | `tools/day2.ps1` | Real | Wed 11:57 AM through UI — 1 DB, 0 errors |
| Decide target (KB-driven verdicts) | `tools/decide.ps1` | Real | Wed 10:00 AM — Node5 verdicts confirmed |
| Generate handoff document | `tools/handoff.ps1` | Real | Wed 11:58 AM through UI — document generated |
| SKU verification | (inline mock in agent.ps1) | Mock | Not on critical path |

### Infrastructure

- Azure VM destroyed via UI button (Wed 12:03 PM, 12 resources destroyed in ~4 min)
- Terraform state currently empty
- `terraform.tfvars` populated with admin_password
- All `.tf` files in `Terraform/` ready: versions, variables, network, vm, storage, outputs
- Region: westus2, SKU: Standard_D2as_v7
- Storage: SAS-driven blob container minted by IaC (M2.5)
- Wed AM session deployed + destroyed cleanly through UI buttons

### Latest assessment

- File: `C:\Users\ushakale\Documents\Temp\SQL_Migration_Assessment_Agent_AI\Migration_Assessment_Report_2026-05-13_0905.{xlsx,json}`
- Generated: Wed 9:05 AM
- Servers: 1 (Node5 only)
- Cloud Migration Matrix renders correctly in Excel

### UI — fully built and tested live

- **`ui/server.ps1`** — PowerShell HttpListener on port 8765, 10 endpoints, dot-sources all 7 tools
- **`ui/index.html`** — single-file SPA, ~55 KB, vanilla JS, 5 screens
- **All 5 screens working:** Assess / Decide / Migrate / Handoff / Day-to-day operations
- **DBA-approval-gate logic** active — Continue buttons mark stages done
- **Light + dark mode** toggle, persists to localStorage
- **Modern aesthetic** — radial color blooms background, bold hero gradient (indigo→purple→orange→teal), stage identity colors, Stripe/Linear quality
- **VM status toolbar** with real-time polling, Create VM (emerald gradient primary) / Destroy VM (red danger outline)
- **Recent activity feed** with timestamped tool call audit trail

### What's been proven end-to-end through the UI

1. Real Phase 1 assessment loaded
2. Real KB lookups producing per-target verdicts (Node5: Azure VM Conditional, MI Blocked, SQL DB Blocked)
3. Real Terraform apply through Create VM button (~7 min)
4. Real database backup-and-restore through Start Migration button (10 sec)
5. Real DBCC CHECKDB through same button (subsec)
6. Real handoff document generation through Generate Handoff button
7. DBA sign-off flow
8. Real Terraform destroy through Destroy VM button (~4 min)
9. Light + dark mode both visually polished
10. Decision log working

---

## File inventory

```
C:\Users\ushakale\Documents\Temp\SQLPilot\
├── agent.ps1                      (825 lines, M4 + M5 patches applied)
├── kb.json                        (8 KB topics with MS Learn citations)
├── Build_SQLPilotDemoDB.sql
├── tools\
│   ├── kb.ps1
│   ├── Phase1.ps1
│   ├── restore.ps1                (M4, ~17 KB)
│   ├── terraform.ps1              (M5, ~15 KB)
│   ├── day2.ps1                   (Wed AM, ~9 KB)
│   ├── decide.ps1                 (Wed AM, ~13 KB)
│   └── handoff.ps1                (Wed AM, ~11 KB)
├── Terraform\
│   ├── versions.tf, variables.tf, network.tf, vm.tf
│   ├── storage.tf                 (M2.5 — container + SAS)
│   ├── outputs.tf
│   ├── terraform.tfvars           (has admin_password — SECRET, gitignore)
│   └── .terraform/, terraform.tfstate
├── ui\
│   ├── server.ps1                 (Wed AM, ~21 KB, SSE removed)
│   └── index.html                 (Wed PM, ~55 KB, full color palette)
├── docs\historical\               (old May 10 docs archived)
├── SQLPilot_Bible_2026-05-13.docx (current)
├── SQLPilot_Runbook_2026-05-13.md (this file)
└── generated\                     (decision logs)
```

---

## UI design — locked decisions

### 5 screens

| Stage | Name | Function |
|---|---|---|
| 1 | Assess | Phase 1 findings, per-server verdict |
| 2 | Decide | KB-driven target picker with citations |
| 3 | Migrate | 8 sub-steps to stand up equivalent server (3 real, 5 Phase 3) |
| 4 | Handoff | Generated package for app team |
| 5 | Day-to-day operations | Phase 3 roadmap |

### Migrate sub-steps

| # | Sub-step | Friday demo status |
|---|---|---|
| 3.1 | Provision target VM (terraform apply) | Real |
| 3.2 | Restore user databases (BACKUP TO URL) | Real |
| 3.3 | Migrate SQL logins | Phase 3 |
| 3.4 | Migrate SQL Agent jobs | Phase 3 |
| 3.5 | Migrate SSIS packages | Phase 3 |
| 3.6 | Migrate linked servers + configs | Phase 3 |
| 3.7 | Configure Azure Backup | Phase 3 |
| 3.8 | Validate (DBCC CHECKDB) | Real |

### Aesthetic — locked Wed PM

- **Hero gradient:** linear-gradient indigo→purple→orange→teal
- **Background:** radial color blooms in corners (subtle in light, even more subtle in dark)
- **Stage identity colors:** indigo / purple / orange / teal / slate (top stripe per card)
- **Buttons:** Create VM = emerald gradient (primary action), Destroy VM = red outline (danger)
- **Typography:** slate-900 base, gradient SQLPilot wordmark
- **Both light + dark modes polished**

---

## API surface

| Method | Path | Wraps |
|---|---|---|
| GET | `/api/health` | liveness ping |
| GET | `/api/status` | terraform output |
| GET | `/api/assess` | latest Phase 1 JSON, per-server summary |
| GET | `/api/decide?server=<name>` | Invoke-RealDecideTarget |
| POST | `/api/terraform` | Invoke-RealApplyTerraform (plan/apply/destroy) |
| POST | `/api/restore` | Invoke-RealRestoreDatabase |
| POST | `/api/validate` | Invoke-RealValidateDatabase |
| POST | `/api/handoff` | Invoke-RealGenerateHandoff |
| GET | `/api/decision-log` | latest decision log JSON |
| GET | `/api/events` | SSE — DISABLED in v0.9 (returns 410 immediately) |
| GET | `/` | serves index.html |

---

## Issues encountered and resolved during Wed sprint

| Issue | Cause | Fix |
|---|---|---|
| `index.html` saved as `index .html` with space | Browser download quirk | Renamed |
| Unblock-File failing from inside ui\ folder | Path prefix doubled | Used full path |
| "Connection refused" / page won't load | Server stopped (Ctrl+C or window closed) | Server restart; learned to leave server window alone |
| Browser address bar typing "open URL" → Bing search | Edge autocomplete | Clean URL only |
| Stage 1 ✓ when shouldn't be | Patch file didn't replace original on disk | File size verification before launch |
| Invoke-RestMethod hanging indefinitely | **SSE blocked single-threaded HttpListener** | Disabled SSE in both server.ps1 (returns 410) and index.html (no-op connectEvents) |
| Decide screen stuck on "Loading verdicts" | Same SSE bug | Same fix |
| Create VM button silently doing nothing | Same SSE bug | Same fix |
| Files needed unblocking after each download | Files came from browser download | One-line: Get-ChildItem -Recurse -File | Unblock-File |
| Background too pale, then too dark, then right | Iteration on color saturation | Settled on radial blooms + bold hero |
| Create/Destroy button colors inverted | Styling didn't reflect action importance | Create=emerald gradient primary, Destroy=red danger outline |

---

## Outstanding pending work

### Wednesday PM (today, optional polish)

| Task | Priority |
|---|---|
| **Backup checkpoint** — zip + cloud OR git commit | **High** — protect today's work |
| Multi-server pluralization ("1 servers" cosmetic) | Low |
| KB rationale first-sentence positivity bug (cosmetic) | Low |
| Polish Migrate detail page in new palette | Medium |
| Polish Decide cards in dark mode | Medium |
| Demo screenshots for handout | Medium |
| Title change: "Database migration workspace" | Low |

### Thursday May 14 (rehearsal)

- AM: Fresh end-to-end rehearsal #1 — clean deploy through demo
- Decide: live deploy during Friday's demo vs pre-created
- Build talk track: 90 sec per stage
- PM: Rehearsal #2 with talk track
- EOD: docs refresh post-rehearsal

### Friday May 15 (demo)

- 60 min before: pre-demo smoke test
- Demo delivery
- Post-demo: destroy VM, capture audit log
- Q&A prep doc (anticipated questions)

---

## Quick recovery — if starting fresh on a different machine

```powershell
# 1. Pull or copy the SQLPilot folder
cd C:\Users\ushakale\Documents\Temp\SQLPilot

# 2. Verify tools load cleanly
$script:ScriptRoot = (Get-Location).Path
. .\tools\decide.ps1
$d = Invoke-RealDecideTarget -Server 'NODE5'
$d.recommended_target
# Expected: display = Azure VM (IaaS), label = Conditional

# 3. Unblock everything (only if files came from internet)
Get-ChildItem -Path . -Recurse -File | Unblock-File

# 4. Launch UI server
.\ui\server.ps1
# Cyan banner + green "Ready" should appear

# 5. In second PowerShell window, test endpoints
Invoke-RestMethod http://localhost:8765/api/health
Invoke-RestMethod 'http://localhost:8765/api/decide?server=NODE5'

# 6. Open browser
Start-Process "http://localhost:8765/"

# 7. (For demo prep) Deploy VM through UI or directly
cd .\Terraform
terraform apply -auto-approve  # ~7 min, ~$0.10/hr while running
```

---

## Demo narrative (Friday)

### Opening (2 min)
"This is SQLPilot — a migration agent for SQL Server estates moving to Azure. Today I'll walk you through what the AI does and what it leaves to the DBA."

### Stage 1 — Assess (1 min)
Open SQLPilot UI front page. Click Assess card. Walk through estate findings.

### Stage 2 — Decide (2 min)
Click Decide card. Walk through three target cards. Click citations → MS Learn.

### Stage 3 — Migrate (live, 8–10 min)
Click Start migration. Watch terraform apply stream. Watch restore stream. Watch DBCC stream. Phase 3 sub-steps visible with badges.

### Stage 4 — Handoff (1 min)
Generate handoff. Show document. Click Copy as email.

### Stage 5 — Day-to-day operations (1 min)
Phase 3 roadmap.

### Teardown + Q&A
Destroy VM button. Decision log for audit.

---

## Risk register

| Risk | Mitigation |
|---|---|
| Live terraform apply = 7 min of nothing visual during demo | Pre-deploy VM Friday morning; call no-op apply during demo for show |
| Multi-server view (UI says "1 servers") | Run Phase 1 across CMS group Thursday OR tell single-server Node5 story (plenty of substance) |
| Browser cache showing old behavior | Ctrl+Shift+R or fresh tab |
| Server window getting closed accidentally | Three-window discipline locked in |
| KB rationale first-sentence positivity (cosmetic) | Fix Thursday if time permits |
| Code only on Node5 machine | **PENDING — back up to cloud/git Wed PM** |

---

## Decision log (chronological)

| Date | What | Why |
|---|---|---|
| 2026-05-10 (Sat) | Phase 1 + agent skeleton + 4-screen UI mockup | Pre-work for sprint |
| 2026-05-11 (Mon) | M0 — Cloud Migration Matrix in Phase 1 wrapper | Reviewer requested cloud comparison visual |
| 2026-05-11 (Mon) | M2 — first real Terraform apply, 9 resources | Backend baseline |
| 2026-05-11 (Mon) | M2.5 — storage.tf, container + SAS via IaC | Backup handoff needed real blob target |
| 2026-05-11 (Mon) | M3 — manual backup + restore proven end-to-end | Validated mechanics before automating |
| 2026-05-12 (Tue) | M4 — restore.ps1 tested live (6 sec) | BACKUP TO URL automation |
| 2026-05-12 (Tue) | M5 — terraform.ps1 tested live | Live IaC orchestration |
| 2026-05-12 (Tue) | agent.ps1 patched (731→825 lines) | Wired M4+M5 into agent's tool loop |
| 2026-05-13 (Wed) | UI restructured 4→5 screens | Migration/Handoff/Day-to-day are distinct DBA workflows |
| 2026-05-13 (Wed) | day2/decide/handoff tools written; decide verified live | Backend feature-complete for 5 screens |
| 2026-05-13 (Wed) | ui/server.ps1 + ui/index.html written | Foundation for the demo |
| 2026-05-13 (Wed) | **SSE bug discovered and patched** | SSE was blocking single-threaded HttpListener |
| 2026-05-13 (Wed) | **Full end-to-end demo proven through UI** | Real apply + real migrate + real handoff + real destroy |
| 2026-05-13 (Wed) | Visual polish: radial blooms + bold hero gradient + stage colors + button hierarchy | "Looks like a real product" pass |
| 2026-05-13 (Wed) | Light + dark mode both polished | DBA audience appreciates dark |
