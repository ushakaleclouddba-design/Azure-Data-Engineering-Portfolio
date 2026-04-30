# =============================================================================
# UshaAg22-Phase5-Step01-VerifyDirectories-Node3.ps1
# =============================================================================
# Phase:    5 — Create UshaAg22MI + Banking Schema
# Step:     5.1 — Verify (and create if missing) C:\data, C:\log, C:\Backup
# Run on:   Node3 (regular admin Windows PowerShell)
# Target:   Node3 — local directories
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Ensures the 3 directories needed for the new Loans_OnPrem database exist
# on Node3 before we run any T-SQL that writes to those paths. Failing
# this check after we've already started CREATE DATABASE leaves us in a
# partial state — better to verify upfront.
#
# DIRECTORIES AND THEIR ROLES
# ---------------------------
# C:\data      — Houses the .mdf data file (Loans_OnPrem.mdf).
# C:\log       — Houses the .ldf transaction log file (Loans_OnPrem.ldf).
# C:\Backup    — Destination for full + log backups taken in steps 5.6 and 5.7.
#                AG seeding doesn't strictly need these files (automatic
#                seeding streams data directly), but Microsoft's MI Link
#                guide does require a recent backup on disk before the link
#                is established — so we take them for Day 2 readiness.
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 5 - Step 5.1 - Verify directories on Node3" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# Required directories for Loans_OnPrem
$dirs = @(
    @{ Path = 'C:\data';   Purpose = 'SQL Server .mdf data file' }
    @{ Path = 'C:\log';    Purpose = 'SQL Server .ldf transaction log file' }
    @{ Path = 'C:\Backup'; Purpose = 'Full + log backups for AG seeding fallback and Day 2 MI Link' }
)

foreach ($d in $dirs) {
    $path = $d.Path
    $purpose = $d.Purpose

    Write-Host "Checking $path  ($purpose)..." -ForegroundColor White

    if (Test-Path $path) {
        Write-Host "  EXISTS" -ForegroundColor Green
    } else {
        Write-Host "  Missing — creating..." -ForegroundColor Yellow
        try {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-Host "  CREATED" -ForegroundColor Green
        } catch {
            Write-Host "  FAILED to create: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

Write-Host "Step 5.1 complete." -ForegroundColor Green
Write-Host "Next step: 5.2 — Create Loans_OnPrem on Node3" -ForegroundColor Cyan
