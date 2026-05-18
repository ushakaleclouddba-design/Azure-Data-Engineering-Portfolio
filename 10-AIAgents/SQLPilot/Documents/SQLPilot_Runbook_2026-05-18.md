# SQLPilot — Runbook
## Wednesday May 13 → demo (postponed to following Friday), 2026

**Last updated:** Monday May 18, 2026 — smoke test on Node5 surfaced and fixed 13 real bugs plus a set of UX gaps; v0.9.1 in flight with the Inputs/Reports folder split, .rpt-only ingestion, terraform auto-init verified live, in-flight banner for long-running jobs, drag-and-drop upload, and a cleaner Source-file link affordance.
**Demo:** Friday May 22, 2026 (postponed from May 15, locked).
**Audience:** DBA team, architecture, sponsor.

---

## Friday May 15 — major pivots

Demo was originally scheduled for today (May 15) but moved one week. Decision: use the buyback time to ship a **self-explanatory setup package** so anyone with the zip can install SQLPilot themselves.

### Decisions locked Friday afternoon

- **Install path standardized**: every SQLPilot deployment now uses `C:\SQLPilot\` as the project root. No more `C:\Users\<user>\Documents\Temp\SQLPilot\` per-user paths.
- **Assessment dir lives inside the project**: `C:\SQLPilot\Assessment\` (not the old separate `SQL_Migration_Assessment_Agent_AI` folder). Recipient extracts the zip, that's the install — no second download.
- **Per-run output folders**: Phase 1 outputs land in `C:\SQLPilot\Assessment\Reports\<yyyy-MM-dd_HHmm>_<server-or-group>\`. Uploaded files land in `Reports\<timestamp>_uploaded\`. No more flat `Migration_Assessment_Report_*.json` mess in the assessment dir.
- **Run modal redesigned**: now tabbed with **Single Server (default)** + **CMS Group (Estate)** tabs. All fields blank with placeholder hints — no hardcoded `Node5` default. Works for recipients who don't have a CMS as well as those who do.
- **Setup doc framing**: "Choose your path" section covering 4 scenarios: A) have CMS, B) no CMS small estate, C) no CMS but can set one up in 10 min, D) upload existing reports (.json/.xlsx/.csv/.rpt).
- **Decks honest about LLM**: tagline is `LLM-driven · DBA-as-pilot, agent-as-copilot`. Slide 4 says "LLM Agent" / "The model does the work." Agent loop slide describes the real Anthropic Messages API tool-use loop. Vendor-neutral language elsewhere; Anthropic named only on the architecture slide.
- **No config-file refactor**: explicitly out of scope for v0.9 — straight find-and-replace patches to standardize paths, not a full config-driven rewrite.
- **For the immediate audience demo**: presenter uses their own Anthropic API key. Setup doc tells recipients to get their own at console.anthropic.com.

### Files patched Friday

- `server.ps1` — path patch (ushakale → SQLPilot), merged with the latest `parse-rpt` endpoint, grafted in `/api/assess/reveal` + `/api/assess/open` endpoints from Wed PM, added per-run folder support to all 4 write paths, added `Find-AssessmentFile` and `New-RunFolderName` helpers, made `Get-LatestPhase1Json` recursive under `Reports\*`. 1228 lines, 17 endpoints, brace balance 315/315.
- `index.html` — rebuilt the Run modal as tabbed (Single Server + CMS Group), removed `Node5` default value, replaced with placeholder hints. Added `setRunTab()` JS, branched `submitRunAssessment()` on tab. 2299 lines, structure validated.
- `Phase1.ps1`, `decide.ps1` — path patch to `C:\SQLPilot\Assessment\`.
- Decks rebuilt — LLM-driven framing throughout (15-min + 30-min).
- `SETUP_GUIDE.md` written from scratch — 10 printed pages, covers prereqs through troubleshooting.
- `RECIPIENT_README.md` — one-page start-here pointer.

### Wrapper params confirmed
`Generate_Assessment_Report.ps1` accepts `-SqlInstanceOverride`, `-CmsGroupOverride`, `-InputRpt`, `-OutputDir`. The `-OutputDir` param means `/api/assess/run` can pass the per-run folder directly to the wrapper — no post-run file moves needed.

### Items deferred to post-demo dev week

- "Pick any server / pick any database for VM restore" feature on the Migration stage
- Wire `.rpt` upload into the UI modal as a 4th option (currently `.rpt` goes through the same upload-raw path but isn't called out in the dropdown)
- Refactor to config-driven (`sqlpilot.config.json` at project root) — declined for v0.9, too much scope; the find-and-replace path standardization solves the immediate problem
- Investigate SRINI-NODE1's thin Phase 1 results

---

## Original demo machine: **Node5** (still the truth source)

After exploring SRINI-NODE1 as an alternative demo machine on Thursday morning, decision made to demo from **Node5** instead. Node5 has the richer dataset and runs the **MultiNode** CMS group: 5 SQL Servers registered (Node1, Node2, Node3, Node4, Node6) which the Phase 1 wrapper fans out to. SRINI-NODE1's freshly-generated Phase 1 report came back oddly thin (1 medium total) and the data needs further validation before it's demo-ready.

**Demo machine for Friday: Node5.** Connect via RDP to `192.168.68.25`. Everything from the Wednesday sprint is intact and running. Thursday afternoon: fire a `MultiNode` CMS group Phase 1 run to produce the multi-server estate report for the demo.

**SRINI-NODE1: kept as fallback, not actively used Friday.**

---

## SRINI-NODE1 setup status (Thursday May 14 — completed as fallback)

The demo machine was explored as an alternative on Thursday morning (originally planned as the new demo target moving from Node5 → SRINI-NODE1). Setup completed end-to-end. Decision reverted to demoing from Node5 due to thin Phase 1 output on the SRINI-NODE1 box that needs investigation before demo. SRINI-NODE1 is documented here as fallback / second working environment.

### Environment

| Property | Value |
|---|---|
| Host | VMware Fusion VM on secondary Mac |
| IP | 192.168.68.8 |
| OS | Windows Server 2022 |
| SQL Server | SQL Server 2022 (16.0.4245.2) |
| Domain | srinidcmaster.local |
| User | srini (SRINIDC\srini) |

### Setup checklist

| # | Step | Status | Notes |
|---|------|--------|-------|
| 1 | Cleanup leftover files (`agent.ps1.bak`, M4/M5 patch txt) | ✅ Done | `SQLPilot\` root now has 3 folders + `agent.ps1` + `kb.json` |
| 2 | Prerequisite check | ✅ Done | Found: only SQL Server installed. Missing: PowerShell 7, Terraform, Azure CLI, dbatools |
| 3a | Install PowerShell 7 | ✅ Done | 7.4.6 via MSI from github.com/PowerShell/PowerShell (needed `-Verb RunAs` — silent `/qn` failed without UAC) |
| 3b | Check winget | ❌ Not present | Server 2022 doesn't ship with winget — using direct downloads instead |
| 3c | Install Terraform | ✅ Done | 1.9.8 via HashiCorp ZIP → extracted to `C:\Tools\terraform`, added to user PATH (the "out of date" warning vs 1.15.3 is cosmetic — 1.9.8 works with the existing .tf files) |
| 3d | Install Azure CLI | ✅ Done | 2.86.0 via aka.ms/installazurecliwindows MSI |
| 3e | Install dbatools | ⏭️ Skipped | No v0.9 tool imports dbatools. Reserved for Phase 3 migrate sub-steps 3.3–3.6 (logins, Agent jobs, SSIS, linked servers). Install when those land. |
| 4 | Recreate `terraform.tfvars` | ✅ Done | File copied from Node5 has all required values (admin_password, vm_size=Standard_D2as_v7, location=westus2). `allowed_source_ip=99.174.175.114/32` matches SRINI-NODE1's outbound IP — no NSG mismatch. |
| 5 | `terraform init` | ✅ Done | Both providers (`azurerm v4.72.0`, `random v3.8.1`) reused from the cached `.terraform\` folder copied from Node5 — no re-download. "Terraform has been successfully initialized!" |
| 6 | `az login --use-device-code` | ✅ Done | Logged in as `ushakaleclouddba@outlook.com`. First attempt hit MFA on the default tenant; re-ran with `--tenant c7977e2f-9265-4918-8141-b81ada10681d` and completed MFA via browser. Subscription `26f7a991-84b3-47b7-966b-f19cbb0379bf` is set as default, `state: Enabled`. |
| 7 | Smoke-test tool loading | ✅ Done | All 7 tools (`kb`, `Phase1`, `restore`, `terraform`, `day2`, `decide`, `handoff`) dot-source clean under pwsh 7.4.6. Confirms the PowerShell code is portable from Node5 → SRINI-NODE1. |
| 7.5 | Patch hardcoded `C:\Users\ushakale\` paths → `srini` | ✅ Done | 9 hits across 3 files (`decide.ps1`, `Phase1.ps1`, `server.ps1`). One global Replace fixed all of them. `.bak-ushakale` backups left next to each file for safety. **TODO post-demo**: parameterize the path so this isn't a per-box hand-edit. |
| 8 | `Invoke-RealDecideTarget -Server 'NODE5'` | ✅ Done | Returns `display = Azure VM (IaaS)`, `label = Conditional`, `key = sql_vm` — exact match for Node5's verdict in the Bible. Agent brain works on SRINI-NODE1. |
| 9 | Launch `ui\server.ps1` | ✅ Done | Server running on port 8765 under **pwsh 7.4.6** (note: first attempt was under Windows PowerShell 5.1, which caused `/api/assess/run` to hang for ~4 min — restarting under pwsh 7 fixed it). |
| 10 | Test `/api/health` + `/api/assess` | ✅ Done | Both respond cleanly. /api/assess returns the latest JSON on disk. |
| 11 | Browser smoke test | ✅ Done | Full UI renders: hero, 5 stage cards in Title Case, VM toolbar, activity feed. |
| 12 | **Phase 1 against SRINI-NODE1 itself** | ⚠️ Ran but suspicious | JSON+XLSX pair generated at 11:08 AM: 1 server · 0 high · **1 medium** · verdict Conditional. The 1-medium finding count seems too thin for any SQL Server install. Decision view rendered Azure VM (IaaS) as Ready/Recommended. **Won't demo from this box Friday**; needs review of the actual JSON contents before trusting (see post-demo follow-ups). |
| 13 | Stage 3 Migration (Azure deploy + destroy via UI) | ⏭️ Skipped on SRINI-NODE1 | Already verified end-to-end on Node5 Wednesday. Re-running on SRINI-NODE1 would add no signal beyond cost. |
| 14 | Snapshot SRINI-NODE1 VM | 🟡 Recommended | VMware Fusion → Snapshots → Take Snapshot. Cheap insurance even though we're not demoing from this box. |
| 12 | End-to-end Azure deploy + destroy via UI | ⏳ Pending | `terraform apply` then `terraform destroy` — ~7 min + ~4 min, costs ~$0.10/hr while running |

### Files on SRINI-NODE1 (verified Thu AM)

```
C:\Users\srini\Documents\Temp\SQLPilot\
├── Terraform\          (14 files incl. versions.tf, variables.tf, network.tf,
│                        vm.tf, storage.tf, outputs.tf, outputs_storage_addendum.tf,
│                        terraform.tfvars, .terraform.lock.hcl, tfplan,
│                        .terraform\ already init'd from Node5 build)
├── Tools\              (7 .ps1: kb, Phase1, restore, terraform, day2, decide, handoff)
├── Ui\                 (index.html 82 KB, server.ps1 45 KB — both LATEST builds)
├── agent.ps1           (36 KB)
└── kb.json             (13 KB)

C:\Users\srini\Documents\Temp\SQL_Migration_Assessment_Agent_AI\
├── Generate_Assessment_Report.ps1            (154 KB Phase 1 wrapper)
├── Migration_Assessment_Report_2026-05-13_1834.json  (36 KB)
└── Migration_Assessment_Report_2026-05-13_1834.xlsx  (21 KB)
```

### Fallback machine: SRINI-NODE1 if Node5 fails

SRINI-NODE1 (192.168.68.8, srinidcmaster.local, VMware Fusion on secondary Mac) has the agent fully installed and one Phase 1 run completed. UI launches and renders correctly. If Node5 goes down between now and Friday:

- RDP to 192.168.68.8 as `srini`
- Open a **PowerShell 7** window (NOT Windows PowerShell 5.1 — that causes the server to hang)
- `cd C:\Users\srini\Documents\Temp\SQLPilot; .\ui\server.ps1`
- Browse to http://localhost:8765/
- The cached Node5 JSON (`Migration_Assessment_Report_2026-05-13_1834.json`) is on this box too, so the assessment data shown can be the richer Node5 dataset if needed

### Post-demo follow-ups (deferred from Thursday setup)

- **Parameterize the user-path** in `decide.ps1`, `Phase1.ps1`, and `server.ps1` so it isn't a per-box hand-edit. Right now those files have `C:\Users\<user>\...` hardcoded; we just hand-replaced `ushakale` → `srini` on SRINI-NODE1. Should read from an env var or config file.
- **Re-validate Phase 1 findings against SRINI-NODE1.** The 11:08 AM run returned 1 medium on a totally fresh Server 2022 + SQL 2022 box. That seems low-fidelity for either direction — could be a noisy default, could be a real soft warning, could be a wrapper rule that fires regardless. Worth running the SQL queries by hand and reconciling against what the JSON contains.
- **dbatools install** — deferred until Phase 3 sub-steps 3.3–3.6 land (logins, Agent jobs, SSIS, linked servers).

---

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
| 2026-05-15 (Fri) | Demo postponed one week to May 22 | Use buyback time for self-contained recipient package + smoke pass |
| 2026-05-15 (Fri) | Path standardization to `C:\SQLPilot\` | No per-user `Documents\Temp\` paths in v0.9 zip |
| 2026-05-15 (Fri) | Tabbed Run modal — Single Server / CMS Group | Works for recipients with or without a CMS |
| 2026-05-15 (Fri) | `SETUP_GUIDE.md` + `RECIPIENT_README.md` written | Self-explanatory install from a zip |
| 2026-05-16 (Sat) | xlsx-direct-open fix + stream-log readability fix | Stage 3 dark log block unreadable; xlsx links opened VS Code instead of Excel |
| 2026-05-16 (Sat) | Title-case sweep across UI | 18 hits cleaned up — buttons, headers, stage labels |
| 2026-05-16 (Sat) | Toast top-center persistent + × dismiss; handoff button gating attempted | Handoff gating later turned out to be only labelled, not enforced — see May 18 notes |
| 2026-05-17 (Sun) | Inputs/Reports folder split shipped | Conceptual cleanliness — raw client material vs analysis output, separate roots |
| 2026-05-17 (Sun) | `/api/assess/upload-raw` reject non-`.rpt` | xlsx/csv have no value to score against the 15-section pipeline |
| 2026-05-17 (Sun) | Drag-and-drop upload on hero + Estate cards | Picker-default-folder was leftover from prior tool; drag-and-drop bypasses |
| 2026-05-17 (Sun) | Source-file link styling — `--accent` → `--info` | `--accent` is stage-scoped and undefined on Estate card; switched to a real link color |
| 2026-05-18 (Mon) | **Terraform auto-init verified end-to-end on Node5** | Deleted `.terraform\`, clicked Create VM, watched init log line, 12 resources up in 6:54 (414s) |
| 2026-05-18 (Mon) | In-flight banner for terraform apply/destroy | Persistent banner + spinner + elapsed timer; previously 6 min of dead-feeling UI during apply |
| 2026-05-18 (Mon) | Preview-window 404 toast suppression | `isServerUnreachable()` helper detects "no server" vs real app errors |
| 2026-05-18 (Mon) | All 5 docs + decks refreshed | SETUP_GUIDE, Bible, Runbook (this file), 15-min deck, 30-min deck — all to v0.9.1 |

---

## May 16–18 work — v0.9.1 smoke pass

The May 15–22 buyback was used for a structured smoke test on Node5. The original "10 untested smoke items" list shrank to 4 by May 18, and 3 of those verified live. The findings turned out to be more substantive than expected — a real (and subtle) Win32 short-name collision in `Find-AssessmentFile`, a UX dead-feel during ~7-minute terraform applies, and a folder-shape decision that needed to be settled before the first demo recipients touched the tool.

### 1. xlsx link opens JSON in Notepad (verified May 16, fixed May 17)

**Symptom:** click the `.xlsx` link in the Estate page Source file card, Notepad opens with the `.json` file's contents.

**Diagnosis:** `Find-AssessmentFile` in `server.ps1` used `Get-ChildItem -Filter <name>` for exact-name lookup. `-Filter` delegates to the Win32 FindFirstFile API, which matches against BOTH the long filename and the auto-generated 8.3 short name. For sibling files like `Migration_Assessment_Report_<ts>.json` and `Migration_Assessment_Report_<ts>.xlsx` in one folder, their short names (e.g. `MIGRAT~1.JSO`, `MIGRAT~2.XLS`) created a collision; a request for the `.xlsx` resolved to the `.json` file.

**Fix:** replaced `-Filter $bare` with `Where-Object { $_.Name -ieq $bare }`, which compares only the long name exactly. Added `Sort-Object LastWriteTime -Descending` so if duplicate filenames ever exist in nested run folders, the most recent wins.

**Lessons:** the gotcha is not in any obvious documentation. Useful piece of folklore: `-Filter` is a Win32 leaky abstraction. Prefer `Where-Object { $_.Name -ieq ... }` for exact-name match where collision risk exists.

### 2. Inputs / Reports folder split (May 17)

**Driver:** the upload picker was defaulting to `Documents\Temp\SQL_Migration_Assessment_Agent_AI\` — leftover from a prior tool's directory — which signalled that "client files vs tool files" hadn't been thought through. Investigation revealed `/api/assess/upload-raw` was writing raw `.rpt` inputs into the same `Reports\<ts>_uploaded\` folder as Phase 1 outputs. The two are conceptually different artifacts and conflating them muddies the file tree for repeat engagements.

**Decision (after a chain of trade-off discussions on May 17):**

- `C:\SQLPilot\Assessment\Inputs\<ts>_uploaded\` — raw client `.rpt` files. Stage A artifacts.
- `C:\SQLPilot\Assessment\Reports\<ts>_parsed_rpt\` — finished assessment outputs (`.json` + `.xlsx`). Stage B output.
- `/api/assess/upload-raw` rejects non-`.rpt` with a clear error: *"Only .rpt files are accepted. The .rpt is the output of `01_Assessment_Script.sql` run via SSMS — it contains the 15 data sections SQLPilot needs to produce findings, SKU recommendations, and the Cloud Migration Matrix."*
- `/api/assess/upload` (JSON-only) kept but de-emphasized in UI — power-user/API path for already-parsed assessments.
- `Find-AssessmentFile` extended to search both `Inputs\` and `Reports\` so clickable filenames on the Estate page resolve uniformly regardless of which root the file lives in.

**Why `.rpt`-only and not also `.xlsx` ingestion:** an arbitrary client-supplied `.xlsx` is whatever they decided to put in it. It cannot carry the 15 specific data sections that `01_Assessment_Script.sql` produces (instance summary, configuration, linked servers, agent jobs, database inventory, DB-level findings, T-SQL code scan, SKU features, CLR assemblies, database files, availability groups, mirroring, log shipping, replication, cloud migration matrix). Without those, the analysis pipeline (findings scoring, SKU recommendations, Cloud Migration Matrix generation) has nothing to score. Accepting xlsx would invite half-empty dashboards from incomplete data — bad outcome. The honest answer is "we accept the `.rpt`; everything else is a different deliverable category." Documented in the UI as a clear inline message rather than a dropdown of formats that would never work.

**Verified end-to-end May 18 11:51 AM PT.** Drag `test.rpt` onto dashboard → server saved to `C:\SQLPilot\Assessment\Inputs\2026-05-18_1151_uploaded\test_uploaded_2026-05-18_1151.rpt` (193,715 bytes, matches UI's 189.2 KB). Clicked Parse → wrapper found rpt via `Find-AssessmentFile` (which now searches both roots) → output written to `C:\SQLPilot\Assessment\Reports\2026-05-18_1152_parsed_rpt\Migration_Assessment_Report_FromUpload_2026-05-18_1152.{json,xlsx}` → Estate page re-rendered with 5 servers, 0 high, 10 medium.

### 3. Terraform auto-init verified live (May 18)

**The most important first-run UX in the build.** `Find-PreparedTerraformDir` in `terraform.ps1` detects a missing `.terraform\` folder on apply and runs `terraform init` automatically. It was specified at Phase 2 close (May 13) but had never been verified end-to-end because every dev environment already had `.terraform\` cached from prior work — the auto-init code path simply never fired.

**Why it matters:** when recipients extract `SQLPilot.zip` and click Create VM, they have no `.terraform\` cache (Terraform's provider plugins are ~200 MB and aren't shipped). Without auto-init, terraform crashes with "Inconsistent dependency lock file. Run terraform init to install the missing providers." A fresh recipient would have to open a terminal, `cd C:\SQLPilot\Terraform`, run `terraform init`, then come back to SQLPilot. That's a terrible first-run experience for a tool whose pitch is "click one button."

**Test sequence on Node5 (May 18 12:17 PM):**

```powershell
# 1. Simulate fresh-recipient state
Remove-Item -Recurse -Force 'C:\SQLPilot\Terraform\.terraform'
Test-Path 'C:\SQLPilot\Terraform\.terraform'  # False

# 2. Hard-refresh browser → status banner flipped to "Terraform not init"

# 3. Click Create VM in the UI → confirm dialog → OK

# 4. Stream log printed:
# [terraform] C:\SQLPilot\Terraform has no .terraform\ marker — running 'terraform init' (one-time)...
# [terraform] Initializing the backend...
# [terraform] Initializing provider plugins...
# [terraform] Terraform has been successfully initialized!
# (then proceeds to normal apply)

# 5. 6:54 later → toast "VM created at 20.29.240.38"
#    Status banner flipped to "VM running"
#    Recent Activity: apply_terraform · action=apply · 12 resources · 414s
```

**Result:** auto-init works exactly as designed. 12 Azure resources provisioned in 6 min 54 sec. Replaces the May 13 figure of 7m43s in all demo materials.

### 4. In-flight banner for terraform jobs (May 18)

**Driver:** `/api/terraform` is a synchronous endpoint. Click Create VM, dialog dismisses, and… nothing visible changes for ~7 minutes. During the May 18 first apply test the only visible feedback was a toast that auto-dismissed after a few seconds. Demo audiences will see this same dead-feeling moment unless we add presence-of-life.

**Implementation:**

- Persistent banner under the top bar (visible on every view, not just the dashboard)
- Animated spinner (blue rotating ring, matches `--info`)
- Banner content: `Creating VM in Azure… · Elapsed mm:ss · typical run ~6 minutes · stay on this page`
- Button text on the Create VM button flips to `Creating VM… mm:ss` with the timer ticking
- `state._tfJob` persists across view navigations; ticker updates every 1s
- Same flow for Destroy VM and for the inline `startMigration()` path on the Migrate stage
- Cleared in a `finally` block so errors don't leave the banner stuck

**Limit:** this is **visual feedback only**. The underlying `await api('/api/terraform', ...)` still blocks the browser for the full apply duration. True streaming progress (server-side job queue + log buffer + client polling) is queued for v1.0.

**Verified May 18 12:42 PM via a deliberate Create VM → Destroy VM cycle.** Banner appeared on click, button text ticked, banner persisted while navigating to Decide and back, cleared cleanly on completion.

### 5. Drag-and-drop upload (May 18)

The file picker's default-folder memory (browser feature, not under our control) was returning users to `Documents\Temp\SQL_Migration_Assessment_Agent_AI\` — a folder leftover from the previous tool. Three legitimate fixes were available:

- **(a) Force initial directory in JS** — not possible; every browser blocks this for security
- **(b) Move to drag-and-drop** — works, bypasses the picker entirely
- **(c) Server-side file picker UI** — too much new code for v0.9.1

Chose (b). Two surfaces now accept drops:

- **Hero banner** — whole-banner drop target. A "Drop .rpt or .json to upload" hint appears only mid-drag (no resting clutter).
- **Estate upload card** — visible dashed drop zone; highlights blue on drag-over; click-to-browse fallback still works.

Window-level `dragover` / `drop` handlers prevent the browser's default of navigating to a file dropped outside the targets (a common UX trap). `accept=".rpt,.json"` on both file inputs locks the picker to the supported types.

### 6. Other fixes (May 16–18)

- **Phase 1 streaming log readability** — the log block used `color: var(--fg-3)` on `background: var(--bg-subtle)`, which is slate-400 on slate-300. Contrast was unreadable mid-stream. Changed to `var(--fg-1)` with `font-weight: 500`.
- **Source-file link styling** — anchor used `color: var(--accent)`, but `--accent` is a per-stage CSS variable only defined inside `.stage-card`. On the Estate Source file card, `--accent` was undefined and the link rendered as plain text. Switched to `var(--info)` (defined in both light and dark themes), added `font-weight:500` and a hover state with thicker underline.
- **Preview-window 404 toast suppression** — when `index.html` is rendered without `server.ps1` behind it (preview tooling, offline review), `loadAssess()`'s fetch returned 404 and toasted an error that confused testers. Added `isServerUnreachable()` helper that distinguishes "no server at all" (network error or bare HTTP 4xx with no `.error` payload) from real application errors and downgrades the former to a console warning.

---

## Known gaps as of May 18 (deferred to post-demo)

### Stage 4 Handoff gating

The Handoff card on the workspace shows `Pending · awaiting migrate` when no migration has run, which is honest information. But the **"Skip to Handoff →" button on the workspace is not disabled** — a user can click through and generate a handoff package for a server that never migrated. Information says "wait," affordance allows "proceed."

Decision deferred. Three options:

- **Hard gate** — disable the button until `state.migrate.steps[restore].status === 'done'`. Cleanest, but demo presenters can't show the Handoff view without running a real migration first.
- **Soft gate** — keep clickable; if the user lands on Handoff before migrate is done, show a confirm dialog: *"Migration hasn't completed yet — handoff package will be incomplete. Continue anyway?"*
- **Leave as is** — "Pending" label is honest enough.

For the May 22 demo: leaving as is. Revisit post-demo.

### True async terraform progress

`/api/terraform` remains synchronous. v0.9.1's in-flight banner is visual-only feedback. v1.0 should move apply/destroy to a background job queue with a `/api/terraform/status?job_id=…` endpoint and a streaming log buffer — same pattern Phase 1 uses today via `/api/assess/status`.

### Config-driven mode (v1.0 roadmap)

Future enhancement: a `pipeline.psd1` in `C:\SQLPilot\config\` defines the full migration end-to-end (Azure subscription, region, target VM size, source rpt path, on-finding-high behavior). Page loads → reads config → runs the 5 stages with no clicks. Interactive mode (the current click-through flow) stays as the default for demos and exploratory work.

PowerShell data file (`.psd1`) chosen over YAML for: native `Import-PowerShellDataFile` (no module dependency), same signing model as the rest of the tool, explicit-failure parse semantics (YAML's whitespace-sensitivity is a foot-gun for hand-edited config files).

### Other v1.0 items

- Live terraform log streaming (see above)
- Cost estimation per target (Azure Retail Prices API integration already in `agent.ps1`; needs a UI surface)
- Email / Slack / Teams handoff delivery
- AWS / GCP target options
- Multi-server assessment UX (the UI handles N servers but the demo flow has only walked the 1-server and CMS-group paths)

---

## Authoritative current stats (replace May 13 figures in demo narrative)

| Stat | May 13 figure | May 18 verified figure |
|---|---|---|
| Stage 3 terraform apply | 12 res / 7m43s | 12 res / **6m54s (414s)** |
| Stage 1 assessment | 1 server (Node5) | **5 servers** from `test.rpt` upload |
| Last apply public IP | 20.59.16.183 | 4.246.61.164 (rotates per apply) |

The May 13 figures remain valid as the historical Wednesday checkpoint baseline. The May 18 figures are what to quote in demo narration.

---

## Demo machine status — May 18

**Node5 is the demo machine.** All May 16–18 fixes deployed and verified live there. `C:\SQLPilot\` contents on Node5 match the staged v0.9.1 build. `terraform.tfstate` is empty (post-destroy May 18 12:46 PM PT). No billable Azure resources running.

**For Friday May 22:**

1. RDP to Node5 (192.168.68.25)
2. Open PowerShell 7 (NOT Windows PowerShell 5.1)
3. `cd C:\SQLPilot\Ui; .\server.ps1`
4. Browse to `http://localhost:8765/`
5. Pre-demo smoke (60 min before):
   - Confirm Inputs\Reports state is clean (or seeded with a known-good `test.rpt`)
   - Verify `.terraform\` exists (so demo Create VM doesn't pause for init; or remove it intentionally to show auto-init narrative)
   - Test Create VM → Destroy VM cycle (~10 min total) to confirm everything still works

SRINI-NODE1 remains the documented fallback machine.
