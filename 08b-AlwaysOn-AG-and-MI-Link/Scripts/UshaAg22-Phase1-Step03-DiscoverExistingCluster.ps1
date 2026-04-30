# =============================================================================
# UshaAg22-Phase1-Step03-DiscoverExistingCluster.ps1
# =============================================================================
# Phase:    1 — Pre-flight Discovery
# Step:     1.3 / 1.4 / 1.5 — Discover existing cluster + AG state
# Run on:   Node3 (regular admin Windows PowerShell)
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Discovers the existing WSFC cluster, quorum config, and any pre-existing
# availability groups. Phase 1 pre-flight surfaced that Node3/Node4 had
# WSFC + AlwaysOn already enabled — this script reveals exactly WHAT exists
# so we know whether to extend or rebuild.
#
# WHAT WE LEARN FROM THIS
# -----------------------
# - Cluster name (Ushaclu22, lowercase 'clu')
# - Cluster nodes (Node3 + Node4 in our case)
# - Quorum config (Majority with NO witness — gap to fix in Phase 3)
# - Existing AGs (UshaAg22 with HRManagement_OnPrem + Payroll_OnPrem)
# - Endpoint port (5023 — non-standard but consistent)
#
# KEY FINDING DURING ACTUAL RUN
# -----------------------------
# Surprised by:
#   1. Cluster name is "Ushaclu22" (8 chars, lowercase 'clu') — assumed UshaCluster22
#   2. QuorumType = Majority with empty QuorumResource = NO WITNESS configured
#      This is a latent HA gap — loss of either node = cluster offline.
#      Remediated in Phase 3 by adding File Share Witness.
#   3. Endpoints on port 5023 (not textbook 5022) — must reuse for Node6
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 1 - Cluster + AG Discovery" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 1.3 - Discover the cluster
# ---------------------------------------------------------------------
Write-Host "`n--- Cluster ---" -ForegroundColor Yellow

# Try Get-Cluster locally first
Import-Module FailoverClusters -ErrorAction SilentlyContinue
$cluster = Get-Cluster -ErrorAction SilentlyContinue
if ($cluster) {
    $cluster | Format-List Name, Domain, Quorum
    Get-ClusterNode | Format-Table Name, State -AutoSize
} else {
    Write-Host "Get-Cluster found nothing locally — checking via Node4 instead..." -ForegroundColor Yellow
    Invoke-Command -ComputerName Node4 -ScriptBlock {
        Import-Module FailoverClusters -ErrorAction SilentlyContinue
        Get-Cluster | Format-List Name, Domain, Quorum
        Get-ClusterNode | Format-Table Name, State -AutoSize
    }
}

# ---------------------------------------------------------------------
# 1.4 - Quorum config
# ---------------------------------------------------------------------
Write-Host "--- Quorum ---" -ForegroundColor Yellow
Get-ClusterQuorum | Format-List Cluster, QuorumResource, QuorumType

# ---------------------------------------------------------------------
# 1.5 - Check existing AGs on each node
# ---------------------------------------------------------------------
Write-Host "--- Existing AGs across all nodes ---" -ForegroundColor Yellow

foreach ($n in @('Node3','Node4','Node6')) {
    Write-Host "`n  $n :" -ForegroundColor Cyan
    Invoke-Command -ComputerName $n -ScriptBlock {
        sqlcmd -S . -E -Q "SELECT name FROM sys.availability_groups" 2>$null
    }
}

# ---------------------------------------------------------------------
# Bonus: existing endpoints
# ---------------------------------------------------------------------
Write-Host "`n--- Existing AG endpoints ---" -ForegroundColor Yellow
foreach ($n in @('Node3','Node4','Node6')) {
    Write-Host "  $n :" -ForegroundColor Cyan
    Invoke-Command -ComputerName $n -ScriptBlock {
        sqlcmd -S . -E -Q "SELECT name, port FROM sys.tcp_endpoints WHERE type_desc = 'DATABASE_MIRRORING'" 2>$null
    }
}

Write-Host "`nDiscovery complete." -ForegroundColor Green
