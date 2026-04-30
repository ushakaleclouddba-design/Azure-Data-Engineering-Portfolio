# =============================================================================
# UshaAg22-Phase7-Step01-TestSqlMINetwork-Node3.ps1
# =============================================================================
# Phase:    7 — Pre-flight for MI Link
# Step:     7.1 — Test TCP connectivity to SQL MI public endpoint port 3342
# Run on:   Node3 (regular admin Windows PowerShell)
# Date:     April 29, 2026
# =============================================================================
#
# PURPOSE
# -------
# Verifies that Node3 can reach Azure SQL Managed Instance on its public
# endpoint port (3342). This validates:
#   - DNS resolution of the SQL MI public hostname
#   - Outbound network path from Node3 to Azure
#   - NSG inbound rule on the SQL MI subnet allows port 3342
#   - SQL MI public endpoint is enabled and listening
#
# WHY 3342 NOT 1433
# -----------------
# SQL MI uses 3342 specifically for the public endpoint, not the standard
# SQL 1433. This is because port 3342 is what the MI gateway listens on
# for connections from outside the VNet. Internally (from same VNet),
# SQL MI uses 1433.
#
# PUBLIC HOSTNAME FORMAT
# ----------------------
# Public endpoint: <instance>.public.<dns-zone>.database.windows.net,3342
# Private endpoint: <instance>.<dns-zone>.database.windows.net (no .public)
#
# In our case:
#   Public:  usha-sqlmi-poc.public.0f3157bbdbf7.database.windows.net,3342
#   Private: usha-sqlmi-poc.0f3157bbdbf7.database.windows.net
#
# We use public because Node3 is outside the SQL MI VNet (on-prem lab).
# =============================================================================

$SqlMIHost = 'usha-sqlmi-poc.public.0f3157bbdbf7.database.windows.net'
$SqlMIPort = 3342

Write-Host ""
Write-Host "===== Testing connectivity to SQL MI =====" -ForegroundColor Cyan
Write-Host "Host: $SqlMIHost" -ForegroundColor Yellow
Write-Host "Port: $SqlMIPort" -ForegroundColor Yellow
Write-Host ""

Test-NetConnection -ComputerName $SqlMIHost -Port $SqlMIPort

# Expected: TcpTestSucceeded : True
# If False: check NSG rule on the MI subnet for inbound TCP 3342
