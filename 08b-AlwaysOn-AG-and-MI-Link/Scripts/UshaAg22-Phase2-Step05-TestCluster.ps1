# =============================================================================
# UshaAg22-Phase2-Step05-TestCluster.ps1
# =============================================================================
# Phase:    2 — Extend Ushaclu22 Cluster (Add Node6)
# Step:     2.5 — Run Test-Cluster validation across Node3 + Node4 + Node6
# Run on:   Node3 (regular admin Windows PowerShell)
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Validates that Node3, Node4, and Node6 are eligible to form a 3-node
# Windows Server Failover Cluster together. Pre-check before adding
# Node6 to the cluster in Step 2.7.
#
# WHY -Include AND NOT -Storage
# ------------------------------
# We deliberately exclude the Storage tests by listing only:
#   - Inventory             - gathers hardware/OS/software inventory
#   - Network               - validates IP, DNS, network adapters
#   - System Configuration  - validates AD, DCOM, services, OS patches
#
# Always On AGs do NOT use shared storage (each replica has its own
# local disk). Including the Storage tests would generate false-positive
# errors about "no shared disks found" that don't apply to AG clusters.
#
# OUTPUT
# ------
# 1. Console summary of test progress
# 2. HTML report saved to a Temp folder, full path printed at the end
#
# Open the HTML report and look for:
#   - All sections green or yellow (no red errors)
#   - Acceptable lab warnings: single network adapter, software update levels
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 2 - Step 2.5 - Test-Cluster Validation" -ForegroundColor Cyan
Write-Host "  Targets: Node3, Node4, Node6" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will take 2-5 minutes. Be patient." -ForegroundColor Yellow
Write-Host ""

# Run validation across all 3 future cluster nodes
Test-Cluster `
    -Node Node3, Node4, Node6 `
    -Include 'Inventory', 'Network', 'System Configuration'

Write-Host ""
Write-Host "Test-Cluster complete." -ForegroundColor Green
Write-Host ""
Write-Host "REVIEW THE HTML REPORT:" -ForegroundColor Cyan
Write-Host "  1. The full path is shown above (in C:\Users\<you>\AppData\Local\Temp\)" -ForegroundColor Cyan
Write-Host "  2. Open it in a browser" -ForegroundColor Cyan
Write-Host "  3. Confirm zero ERRORS (warnings are usually OK)" -ForegroundColor Cyan
Write-Host "  4. Capture screenshot of the summary section for the playbook" -ForegroundColor Cyan
