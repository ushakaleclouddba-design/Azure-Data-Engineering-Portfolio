# Migration Walkthrough — Newbee Edition

> **A practical, step-by-step guide for self-learners migrating a SQL Server database from on-premises to Azure SQL Managed Instance.**

---

## Who is this for?

This documentation is for you if any of these apply:

- You're new to Azure but you know SQL Server
- You've heard about "SQL MI" but don't know what it really is or how to migrate to it
- You want a complete, working example from start to finish — not piece together blog posts
- You learn best by doing, with someone explaining each step
- You can write `SELECT * FROM Customers` and run `BACKUP DATABASE`, but everything else about Azure feels overwhelming

If that sounds like you, this guide will take you from zero to a working migration — methodically, one step at a time.

---

## What's in this folder

| File | Pages | Purpose |
|------|-------|---------|
| **Standalone_Migration_Newbee_Part1_Setup.docx** | ~30 | Concepts, prerequisites, creating SQL MI, setting up source database |
| **Standalone_Migration_Newbee_Part2_BackupRestore.docx** | ~30 | Method 1 — full Backup/Restore migration via Azure Blob Storage |

**Total**: 60 pages of patient, friendly, beginner-focused content.

---

## What you'll learn

By the end of this guide, you'll be able to:

- Explain what Azure SQL Managed Instance is in plain language
- Identify the right migration method for your scenario
- Provision a SQL Managed Instance from scratch in the Azure Portal
- Set up a source SQL Server database for migration
- Migrate a database using the Backup/Restore via Azure Blob method
- Validate that your migration succeeded
- Diagnose and fix the most common errors

---

## The migration scenario (kept simple)

You'll use a single, simple database called **`BankDemo`** with one table (`Customers`) and 5 rows throughout the entire guide.

```sql
-- The whole database
CREATE TABLE Customers (
    CustomerID    INT IDENTITY(1,1) PRIMARY KEY,
    FirstName     NVARCHAR(50) NOT NULL,
    LastName      NVARCHAR(50) NOT NULL,
    Email         NVARCHAR(100) NOT NULL,
    AccountType   NVARCHAR(20) NOT NULL,
    Balance       DECIMAL(15,2) NOT NULL,
    OpenedDate    DATE NOT NULL DEFAULT GETDATE()
);
```

**Why so simple?** Because the goal is learning the **migration mechanics**, not dealing with multi-gigabyte data movement, schema complexity, or performance tuning. Once you can move 5 rows successfully, scaling to millions of rows uses the same steps with longer wait times.

---

## Document structure

### Part 1 — Setup (read this first)

| Chapter | Topic |
|---------|-------|
| 1 | What is SQL Managed Instance? Why migrate? |
| 2 | Prerequisites (knowledge, software, Azure, network) |
| 3 | Creating SQL MI from scratch — every Azure Portal click |
| 4 | Setting up the source SQL Server with BankDemo |

### Part 2 — Migration via Backup/Restore

| Chapter | Topic |
|---------|-------|
| 5 | Method 1: Backup & Restore via Azure Blob (full walkthrough) |
| 8 | Validating the migration succeeded |
| 9 | Querying the migrated database |
| 10 | Common errors and what they mean (7 scenarios) |
| 11 | Decision guide — when to use this method |
| 12 | Glossary (27 terms in plain language) |

---

## How to read it

This guide uses 6 callout types throughout — each color coded:

- **PAUSE FOR UNDERSTANDING** — explains a concept before showing you how to use it
- **TIP** — helpful nudges and shortcuts
- **COMMON PITFALL** — gotchas that have tripped up others
- **SQL SERVER ANALOGY** — connects new cloud concepts to familiar on-prem SQL Server
- **REMEMBER THIS** — key takeaways
- **CHECKPOINT** — verify before moving on

If you're skim-reading, focus on the **REMEMBER THIS** and **COMMON PITFALL** boxes — they save the most pain.

---

## Time investment

| Activity | Estimated time |
|----------|---------------|
| Reading both documents end-to-end | 60-90 minutes |
| Following Part 1 (creating SQL MI) | 5-7 hours (mostly waiting for Azure provisioning) |
| Following Part 2 (running the migration) | 30-45 minutes |
| Total active work time | ~2 hours |
| Total elapsed time | 1 day (with breaks while Azure provisions) |

> **Don't try to rush this in one sitting.** Migration is methodical work. Plan to take breaks. The SQL MI provisioning step alone takes 4-6 hours of waiting — start it before lunch, come back later.

---

## What you'll need

### Software
- SQL Server 2016 or later (Developer Edition is free for learning)
- SSMS 20+ (SQL Server Management Studio — free)
- A web browser (for Azure Portal)
- PowerShell 7 or Windows PowerShell 5.1 with Az module

### Cloud
- An Azure account (free tier works — sign up at https://azure.microsoft.com/free/)
- Permission to create resources in your subscription

### Knowledge
- Basic SQL Server knowledge (create databases, run queries, understand backups)
- That's it. Everything else is explained as we go.

---

## Cost awareness

> **IMPORTANT**: Azure costs are real. SQL MI is one of the more expensive Azure services (~$365/month for a 4-vCore General Purpose instance running 24/7).

If you're using **free tier** (eligible for new customers):
- $0 for the first 12 months, up to 720 vCore hours/month
- More than enough for this entire walkthrough

If you're not on free tier:
- Watch your usage carefully
- Delete resources when you're done practicing
- Part 2 includes a "Cleanup" section to walk you through tearing everything down

---

## What's NOT covered (yet)

This guide is focused on **Method 1 — Backup/Restore via Azure Blob** because it's the simplest path for a beginner. Two other migration methods are intentionally left for future expansion:

| Method | Status | Best for |
|--------|--------|----------|
| Method 1 — Backup/Restore via Blob | ✅ Covered in Part 2 | Small to medium DBs, downtime acceptable |
| Method 2 — Log Replay Service (LRS) | 🔜 Future expansion | Larger DBs, minimal downtime needed |
| Method 3 — Managed Instance Link | 🔜 Future expansion | Production with near-zero downtime |

Once you're comfortable with Method 1, the other methods build on the same foundations (storage accounts, credentials, SAS tokens). They're more advanced but not fundamentally different.

---

## Companion technical content

For an expert-level deep dive into Always On Availability Groups + MI Link (with all the architectural complexity removed from this newbee guide), see:

- **POC #8b — Always On AG and MI Link** in the parent portfolio (`08b-AlwaysOn-AG-and-MI-Link` folder)

That POC documents the full hybrid HA/DR scenario, including 7 senior-level gotchas worth knowing for interviews. It's the "grad school version" of the migration story this newbee guide tells gently.

---

## Feedback

If you find errors, unclear sections, or steps that no longer match Azure's UI (Microsoft updates the portal regularly), please open an issue or send feedback.

---

## Status

**Part 1 (Setup)**: ✅ Complete  
**Part 2 (Backup/Restore)**: ✅ Complete  
**Part 3 (LRS)**: 🔜 Planned  
**Part 4 (MI Link)**: 🔜 Planned

Last updated: April 29, 2026

---

*Author: Usha Kale — Senior Cloud DBA / Azure Data Engineer · AZ-104 · DP-300 · AZ-305*
