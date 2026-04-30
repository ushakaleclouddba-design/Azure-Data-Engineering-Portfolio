# =============================================================================
# UshaAg22-Phase2-Step01-InstallFailoverClustering-Node6.ps1
# =============================================================================
# Phase:    2 — Extend Ushaclu22 Cluster (Add Node6)
# Step:     2.1 — Install Failover-Clustering feature on Node6
# Run on:   Node3 (regular admin Windows PowerShell)
# Target:   Node6
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Installs the Failover Clustering Windows feature on Node6, including the
# management tools (Failover Cluster Manager + PowerShell module). Without
# these, Node6 cannot participate in the cluster — Get-ClusterNode and the
# ClusSvc service simply don't exist.
#
# WHY SEPARATE FROM PHASE 1
# -------------------------
# Phase 1 reported "WSFC_Feature: Available" for Node6 — which means
# "installable, but not installed." Easy to misread as "present." Phase 2.1
# is the explicit install step.
#
# WHAT GETS INSTALLED
# -------------------
# 1. Failover Clustering core feature (the cluster service itself)
# 2. Remote Server Administration Tools (RSAT)
#    - Failover Cluster Management Tools (cluadmin.msc GUI)
#    - Failover Cluster Module for Windows PowerShell (Get-Cluster cmdlets)
#
# The -IncludeManagementTools flag is the difference between "node can
# participate" (just core feature) and "node can manage too" (full RSAT).
# We install both because most DBAs need to run cmdlets from any node.
#
# REBOOT REQUIREMENT
# ------------------
# Failover Clustering requires a reboot to register kernel-mode driver.
# We use -Restart:$false so the script doesn't force-reboot — better to
# reboot manually so you can stagger the operation if Node3 or Node4
# needed similar work (which they don't here, but pattern reuse).
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 2 - Step 2.1 - Install Failover-Clustering on Node6" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# Show before state
Write-Host "Before install — Node6 WSFC feature state:" -ForegroundColor Yellow
Invoke-Command -ComputerName Node6 -ScriptBlock {
    Get-WindowsFeature -Name Failover-Clustering | Select-Object Name, InstallState
}

Write-Host "`nInstalling Failover-Clustering + management tools on Node6..." -ForegroundColor Yellow
Invoke-Command -ComputerName Node6 -ScriptBlock {
    Install-WindowsFeature `
        -Name Failover-Clustering `
        -IncludeManagementTools `
        -Restart:$false
}

Write-Host "`nAfter install — Node6 WSFC feature state:" -ForegroundColor Green
Invoke-Command -ComputerName Node6 -ScriptBlock {
    Get-WindowsFeature -Name Failover-Clustering | Select-Object Name, InstallState
}

Write-Host "`nStep 2.1 complete." -ForegroundColor Green
Write-Host "Next: reboot Node6 (Step 2.2) before continuing to Step 2.4 firewall rules." -ForegroundColor Cyan
