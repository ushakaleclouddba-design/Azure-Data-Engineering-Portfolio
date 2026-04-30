# =============================================================================
# UshaAg22-Phase10-Step02-CheckMIDatabaseFormat-Node3.ps1
# =============================================================================
# Phase:    10 — Distributed AG creation
# Step:     10.2 — Diagnostic — verify SQL MI's update policy / database format
# Run on:   Node3 PowerShell (authenticated to Azure)
# Date:     April 29, 2026
# Purpose:  Identify the AlwaysUpToDate blocker BEFORE attempting MI Link
# =============================================================================
#
# WHY THIS STEP MATTERS
# ---------------------
# MI Link requires database format alignment between the on-prem SQL Server
# version and the SQL MI's update policy. If they don't match, the wizard
# will reject the link with the cryptic error:
#   "SQL Managed Instance link feature requires database format alignment
#    between SQL Server and SQL Managed Instance."
#
# Run this BEFORE attempting MI Link to avoid hours of cert/endpoint setup
# only to discover at the last step that the link will not establish.
#
# COMPATIBILITY MATRIX
# --------------------
# On-prem SQL Server 2022 (CU24, format 974) requires SQL MI to be on:
#   ✅ DatabaseFormat = SQLServer2022     (compatible — works)
#   ❌ DatabaseFormat = SQLServer2025     (mismatch — doesn't work)
#   ❌ DatabaseFormat = AlwaysUpToDate    (mismatch — doesn't work)
#
# THE BIG GOTCHA
# --------------
# AlwaysUpToDate is IRREVERSIBLE. Once a SQL MI is set to AlwaysUpToDate,
# you cannot switch it back to SQL Server 2022 update policy. The internal
# database format has been upgraded permanently.
#
# IF YOU FIND ALWAYSUPTODATE, your options are:
#   1. Provision a NEW SQL MI with explicit SQL Server 2022 update policy
#      (must select on Additional Settings tab — default changed in March 2026)
#   2. Pivot to a different migration method (native backup/restore, LRS)
#   3. Upgrade source SQL Server to SQL Server 2025 (matches AlwaysUpToDate)
# =============================================================================

# Connect to Azure (use device code if browser unavailable)
# Connect-AzAccount -UseDeviceAuthentication -SubscriptionId '<sub-id>'

# Get the MI configuration
$mi = Get-AzSqlInstance -Name 'usha-sqlmi-poc' -ResourceGroupName 'Usha_SQLMI_POC'

Write-Host ""
Write-Host "===== SQL MI Configuration =====" -ForegroundColor Cyan
Write-Host "Name:           $($mi.ManagedInstanceName)" -ForegroundColor Yellow
Write-Host "Location:       $($mi.Location)" -ForegroundColor Yellow
Write-Host "Service Tier:   $($mi.Sku.Tier)" -ForegroundColor Yellow
Write-Host "Edition:        $($mi.Sku.Name)" -ForegroundColor Yellow
Write-Host "DatabaseFormat: $($mi.DatabaseFormat)" -ForegroundColor Green
Write-Host ""

# Decision logic — flag the result
switch ($mi.DatabaseFormat) {
    'SQLServer2022' {
        Write-Host "✅ COMPATIBLE — MI Link with SQL Server 2022 should work" -ForegroundColor Green
        Write-Host "Proceed with cert exchange and MI Link wizard." -ForegroundColor Green
    }
    'SQLServer2025' {
        Write-Host "⚠️  REQUIRES SQL Server 2025 ON SOURCE" -ForegroundColor Yellow
        Write-Host "Your Node3 must be SQL Server 2025 (not 2022) for MI Link to work." -ForegroundColor Yellow
    }
    'AlwaysUpToDate' {
        Write-Host "❌ HARD BLOCKER — IRREVERSIBLE POLICY MISMATCH" -ForegroundColor Red
        Write-Host "MI Link from SQL Server 2022 cannot work with this MI." -ForegroundColor Red
        Write-Host "AlwaysUpToDate cannot be reversed — provision a NEW MI" -ForegroundColor Red
        Write-Host "with SQL Server 2022 update policy explicitly selected" -ForegroundColor Red
        Write-Host "on the Additional Settings tab." -ForegroundColor Red
    }
    default {
        Write-Host "Unknown DatabaseFormat: $($mi.DatabaseFormat)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Full MI properties:" -ForegroundColor Cyan
$mi | ConvertTo-Json -Depth 2
