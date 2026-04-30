# =============================================================================
# UshaAg22-Phase2-Step07-AddClusterNode-Node6.ps1
# =============================================================================
# Phase:    2 — Extend Ushaclu22 Cluster (Add Node6)
# Step:     2.7 — Add Node6 to existing Ushaclu22 cluster
# Run on:   Node3 (regular admin Windows PowerShell)
# Target:   Adds Node6 as 3rd member of existing Ushaclu22
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Adds Node6 to the existing 2-node Ushaclu22 cluster, taking it to 3
# nodes. This is a NON-DISRUPTIVE operation — Node3, Node4, and the
# existing UshaAg22 (HRManagement_OnPrem, Payroll_OnPrem) stay online
# throughout. Node6 simply registers itself with the cluster's CNO
# (Cluster Name Object) in AD and starts participating in heartbeat.
#
# WHAT HAPPENS
# ------------
# 1. Add-ClusterNode contacts the cluster's CNO (Ushaclu22$) in AD
# 2. Node6's computer object gets cluster permissions via the CNO
# 3. ClusSvc service on Node6 starts (currently Stopped)
# 4. Node6 begins exchanging heartbeats with Node3 and Node4
# 5. Cluster votes recalculated: now 3 nodes = 3 votes (no witness yet)
#
# WHY -NoStorage
# --------------
# We're not adding any shared/cluster storage to Node6. AGs use local
# disks on each replica. -NoStorage tells WSFC not to look for shared
# disks (which don't exist) — avoids spurious storage-related errors.
#
# QUORUM AFTER THIS STEP
# ----------------------
# Cluster will go from 2 votes (Majority, no witness) to 3 votes
# (Majority, still no witness). Phase 3 adds the File Share Witness
# to make it 4 votes total — better resilience.
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 2 - Step 2.7 - Add Node6 to Ushaclu22" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# Show current cluster state BEFORE adding
Write-Host "Cluster state BEFORE adding Node6:" -ForegroundColor Yellow
Get-ClusterNode -Cluster Ushaclu22 | Format-Table Name, State, NodeWeight

Write-Host ""
Write-Host "Adding Node6 to Ushaclu22 (this takes ~30 seconds)..." -ForegroundColor Yellow
Write-Host ""

Add-ClusterNode -Cluster Ushaclu22 -Name Node6 -NoStorage

Write-Host ""
Write-Host "Cluster state AFTER adding Node6:" -ForegroundColor Green
Get-ClusterNode -Cluster Ushaclu22 | Format-Table Name, State, NodeWeight

Write-Host ""
Write-Host "Step 2.7 complete." -ForegroundColor Green
Write-Host "Verify in Failover Cluster Manager (cluadmin.msc) that all" -ForegroundColor Cyan
Write-Host "3 nodes show under Nodes with State=Up and green icons." -ForegroundColor Cyan
