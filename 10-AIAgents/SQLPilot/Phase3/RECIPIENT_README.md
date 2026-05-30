# SQLPilot — Start Here

Thanks for trying SQLPilot. This zip contains everything you need to install and run an LLM-driven SQL Server migration agent on your Windows machine.

## What's in this zip

| File / Folder | What it is |
|---|---|
| `SETUP_GUIDE.docx` | **Read this first.** (Word document — open in Word, Google Docs, or LibreOffice) Step-by-step install instructions. ~30 minutes from zero to running. |
| `agent.ps1`, `kb.json` | The LLM agent and its knowledge base |
| `Ui\` | The web UI and HTTP server you'll interact with |
| `Tools\` | Tool scripts the agent calls (Phase 1, Decide, Restore, Terraform, etc.) |
| `Terraform\` | Infrastructure-as-code for the Azure target VM |
| `Assessment\` | The Phase 1 SQL assessment script + wrapper |
| `SQLPilot_Demo_15min.pptx` | 15-min demo deck (audience preview) |
| `SQLPilot_Demo_30min.pptx` | 30-min demo deck (audience preview, deeper) |
| `SQLPilot_Bible_2026-05-18.docx` | Full project reference (architecture, design decisions, May 13 → May 18 update log) |
| `SQLPilot_Runbook_2026-05-18.md` | Operations runbook (development history, v0.9.1 smoke-pass notes, current state) |

## Fast path

1. Extract this zip's contents into `C:\SQLPilot\` (create the folder if it doesn't exist)
2. Open `SETUP_GUIDE.docx`
3. Follow it step by step

## What you absolutely need before starting

- A Windows machine with admin rights
- PowerShell 7 (NOT 5.1)
- Terraform 1.9+
- Azure CLI
- An Azure subscription
- **An Anthropic API key** ← critical, the agent will not run without it

`SETUP_GUIDE.docx` tells you where to get each of these.

## What you'll see when it works

A browser-based workspace at http://localhost:8765 with five stage cards:

**Assess → Decide → Migrate → Handoff → Day-to-Day Ops**

The agent walks the five stages, calling real tools, citing Microsoft Learn for every decision, logging every action for audit.

## Version

SQLPilot v0.9.1 · May 2026
