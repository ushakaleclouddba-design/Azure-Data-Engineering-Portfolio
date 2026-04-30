# =============================================================================
# UshaAg22-Phase3-Step04-SetQuorumWitness.ps1
# =============================================================================
# Phase:    3 — Configure File Share Witness Quorum
# Step:     3.4 — Set the file share witness on Ushaclu22
# Run on:   Node3 (regular admin Windows PowerShell)
# Target:   Ushaclu22 (configures cluster, doesn't modify nodes)
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Reconfigures Ushaclu22 quorum from 'Node Majority' (3 nodes, 3 votes,
# no witness) to 'Node and File Share Majority' (3 nodes + witness =
# 4 votes total). This remediates the pre-existing missing witness
# discovered during Phase 1.
#
# WHY THIS MATTERS
# ----------------
# Before this step:
#   - 3 nodes, 3 votes, no witness
#   - Tolerates loss of 1 node (2 of 3 still vote = majority)
#
# After this step:
#   - 3 nodes + witness = 4 votes
#   - Tolerates loss of 1 node OR loss of witness
#   - More resilient — Microsoft best practice
#
# WHAT HAPPENS UNDER THE HOOD
# ---------------------------
# The cluster service writes a small marker file to the witness share.
# It uses the cluster's CNO (Ushaclu22$) credentials — that's why we
# spent Steps 3.2-3.3 granting it Full Control. If permissions are
# wrong, this command fails with 'access denied' on the witness path.
#
# COMMON FAILURES
# ---------------
# - "The user name or password is incorrect" / "access denied"
#   → CNO doesn't have Full Control. Re-check both SMB share AND
#     NTFS permissions on USHADC. Both layers need it.
# - "The network path was not found"
#   → Witness path typo or share doesn't exist. Verify path with:
#     Test-Path '\\USHADC\ClusterWitness\Ushaclu22'
# - "Already configured for this quorum type"
#   → Already done. Verify with Get-ClusterQuorum and skip.
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 3 - Step 3.4 - Set Quorum Witness" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# Show current quorum state BEFORE
Write-Host "Quorum config BEFORE:" -ForegroundColor Yellow
Get-ClusterQuorum -Cluster Ushaclu22 | Format-List Cluster, QuorumResource, QuorumType

Write-Host ""
Write-Host "Setting File Share Witness to \\USHADC\ClusterWitness\Ushaclu22..." -ForegroundColor Yellow
Write-Host ""

# Configure the witness
Set-ClusterQuorum -Cluster Ushaclu22 `
    -FileShareWitness '\\USHADC\ClusterWitness\Ushaclu22'

Write-Host ""
Write-Host "Quorum config AFTER:" -ForegroundColor Green
Get-ClusterQuorum -Cluster Ushaclu22 | Format-List Cluster, QuorumResource, QuorumType

Write-Host ""
Write-Host "Step 3.4 complete." -ForegroundColor Green
