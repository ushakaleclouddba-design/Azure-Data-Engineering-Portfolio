# =============================================================================
# UshaAg22-Phase2-Step04-FirewallRules-Node6.ps1
# =============================================================================
# Phase:    2 — Extend Ushaclu22 Cluster (Add Node6)
# Step:     2.4 — Create firewall rules on Node6
# Run on:   Node3 (regular admin Windows PowerShell)
# Target:   Node6
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Opens the three TCP/UDP ports on Node6 that Failover Clustering and
# Always On Availability Groups require for inter-node communication.
# Without these rules, the Windows Firewall on Node6 will block:
#   - Cluster heartbeat traffic between Node3, Node4, and Node6
#   - AG endpoint replication on the chosen mirroring port
# ...which causes WSFC validation failures and AG sync failures with
# vague "communication error" messages that are hard to debug.
#
# WHAT EACH PORT DOES
# -------------------
# TCP 5023 — SQL Server AG endpoint (HADR_Endpoint)
#            This is the port the AG replicas use to send transaction log
#            blocks to each other. Node3 and Node4 already use 5023 for
#            the existing UshaAg22, so Node6 must match for consistency.
#            Note: 5023 is non-standard. Microsoft default is 5022. We
#            use 5023 because the existing AG was built on 5023.
#
# TCP 3343 — WSFC cluster heartbeat (TCP)
#            Cluster nodes use this port to detect when a peer is healthy.
#            If a node misses several heartbeats, the cluster considers
#            it failed and triggers failover.
#
# UDP 3343 — WSFC cluster heartbeat (UDP)
#            Same purpose as TCP 3343, but UDP is used for lightweight
#            keepalive packets. Both protocols on the same port are
#            normal for WSFC — Microsoft uses both for redundancy.
#
# WHY Invoke-Command
# ------------------
# Running this from Node3 (the control node) and using Invoke-Command
# to push the firewall changes to Node6 over WinRM. This avoids needing
# to RDP into Node6 just to run firewall commands. Same outcome, less
# session juggling.
#
# IDEMPOTENCY
# -----------
# If a rule with the same DisplayName already exists, New-NetFirewallRule
# will error. That's intentional — it prevents accidental duplicates.
# If you need to re-run this script, first remove the existing rules:
#   Remove-NetFirewallRule -DisplayName 'SQL AG Endpoint TCP 5023'
#   Remove-NetFirewallRule -DisplayName 'WSFC Heartbeat TCP 3343'
#   Remove-NetFirewallRule -DisplayName 'WSFC Heartbeat UDP 3343'
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 2 - Step 2.4 - Firewall Rules on Node6" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

Invoke-Command -ComputerName Node6 -ScriptBlock {

    Write-Host "Creating firewall rule: SQL AG Endpoint TCP 5023..." -ForegroundColor Yellow
    New-NetFirewallRule `
        -DisplayName 'SQL AG Endpoint TCP 5023' `
        -Description 'Allow inbound TCP 5023 for SQL Server Always On AG endpoint replication' `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   5023 `
        -Action      Allow `
        -Profile     Any

    Write-Host "Creating firewall rule: WSFC Heartbeat TCP 3343..." -ForegroundColor Yellow
    New-NetFirewallRule `
        -DisplayName 'WSFC Heartbeat TCP 3343' `
        -Description 'Allow inbound TCP 3343 for Windows Server Failover Cluster heartbeat' `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   3343 `
        -Action      Allow `
        -Profile     Any

    Write-Host "Creating firewall rule: WSFC Heartbeat UDP 3343..." -ForegroundColor Yellow
    New-NetFirewallRule `
        -DisplayName 'WSFC Heartbeat UDP 3343' `
        -Description 'Allow inbound UDP 3343 for Windows Server Failover Cluster heartbeat (keepalive)' `
        -Direction   Inbound `
        -Protocol    UDP `
        -LocalPort   3343 `
        -Action      Allow `
        -Profile     Any
}

Write-Host ""
Write-Host "All 3 firewall rules created on Node6." -ForegroundColor Green

# Verification
Write-Host "`nVerifying rules:" -ForegroundColor Cyan
Invoke-Command -ComputerName Node6 -ScriptBlock {
    Get-NetFirewallRule -DisplayName 'SQL AG Endpoint*','WSFC Heartbeat*' |
        Format-Table DisplayName, Direction, Action, Enabled -AutoSize
}
