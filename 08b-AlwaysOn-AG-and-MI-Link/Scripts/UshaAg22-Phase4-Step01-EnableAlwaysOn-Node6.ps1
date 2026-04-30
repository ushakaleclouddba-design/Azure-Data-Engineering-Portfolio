# =============================================================================
# UshaAg22-Phase4-Step01-EnableAlwaysOn-Node6.ps1
# =============================================================================
# Phase:    4 — Enable AlwaysOn + Endpoint on Node6
# Step:     4.1 — Enable AlwaysOn at the SQL service level on Node6
# Run on:   Node3 (regular admin Windows PowerShell) — uses Invoke-Command
# Target:   Node6
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Enables Always On Availability Groups feature on Node6's SQL Server
# instance. Without this flag, Node6's SQL refuses to participate in
# any AG. Equivalent to ticking the "Enable AlwaysOn" checkbox in SQL
# Server Configuration Manager.
#
# WHY THIS IS A REGISTRY EDIT NOT A CMDLET
# ----------------------------------------
# We use registry edit instead of Enable-SqlAlwaysOn cmdlet because the
# latter requires the SqlServer PowerShell module, which is missing on
# Node6 (verified during build — Node6 was a minimal SQL install). The
# registry approach achieves the same outcome with no module dependency.
#
# WHAT GETS CHANGED
# -----------------
# Registry value HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\
#   MSSQL16.MSSQLSERVER\MSSQLServer\HADREnabled
# Set from 0 to 1.
#
# A SQL Server service restart is required for the change to take effect.
# This script restarts the service automatically.
#
# WHY -Force
# ----------
# Restart-Service -Force tells the service to stop even if dependent
# services would also be stopped. This is necessary because SQL Agent
# depends on MSSQLSERVER and would otherwise block the restart.
#
# AFTER THIS RUNS
# ---------------
# Verify in SSMS by connecting to Node6 and right-clicking the server
# → Properties. The "Is HADR Enabled" property should show True.
# Or via T-SQL: SELECT SERVERPROPERTY('IsHadrEnabled') = 1
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 4 - Step 4.1 - Enable AlwaysOn on Node6" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

Invoke-Command -ComputerName Node6 -ScriptBlock {

    # Enable AlwaysOn via registry (same as SCM checkbox / Enable-SqlAlwaysOn)
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer'
    Write-Host "Setting HADREnabled = 1 in registry..." -ForegroundColor Yellow
    Set-ItemProperty -Path $regPath -Name 'HADREnabled' -Value 1 -Type DWord -Force

    # Restart SQL Server service to apply
    Write-Host "Restarting SQL Server service..." -ForegroundColor Yellow
    Restart-Service -Name 'MSSQLSERVER' -Force
    Start-Service -Name 'SQLSERVERAGENT' -ErrorAction SilentlyContinue

    # Verify
    Write-Host "Verifying IsHadrEnabled..." -ForegroundColor Yellow
    $result = sqlcmd -S . -E -h -1 -W -Q "SELECT SERVERPROPERTY('IsHadrEnabled')"
    Write-Host "  IsHadrEnabled = $result" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 4.1 complete." -ForegroundColor Green
