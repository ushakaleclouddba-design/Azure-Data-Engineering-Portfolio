# =============================================================================
# UshaAg22-Phase3-Step01-CreateWitnessShare-USHADC.ps1
# =============================================================================
# Phase:    3 — Configure File Share Witness Quorum
# Steps:    3.1, 3.2, 3.3 — Create folder, share with CNO, set NTFS permissions
# Run on:   USHADC (the domain controller) as Domain Admin
# Date:     April 28, 2026
# =============================================================================
#
# PURPOSE
# -------
# Creates the file share that the Ushaclu22 cluster will use as its
# quorum witness. Two permission layers must both grant the cluster CNO
# (Ushaclu22$) Full Control:
#   - SMB share permissions (network access)
#   - NTFS permissions (file system access)
# Setting only one will result in "access denied" when the cluster tries
# to write its witness file.
#
# WHY THIS RUNS ON USHADC
# -----------------------
# The witness share must be HOSTED on a server that's NOT a cluster member.
# Otherwise losing that node would lose both the node vote AND the witness
# vote simultaneously — defeating the purpose of the witness. USHADC (the
# domain controller) is a stable choice that's not in the cluster.
#
# WHAT GETS CREATED
# -----------------
# 1. Folder C:\ClusterWitness\Ushaclu22 (where cluster writes its witness file)
# 2. SMB share \\USHADC\ClusterWitness (network access path)
# 3. NTFS Full Control to USHADC0\Ushaclu22$ (cluster CNO computer object)
# 4. SMB Full Access to USHADC0\Ushaclu22$ AND USHADC0\Domain Admins
#
# NOTE ON THE $ SUFFIX
# --------------------
# Computer objects in AD are referred to by their hostname followed by $.
# Ushaclu22 is a Cluster Name Object (CNO) — a special computer object
# that represents the cluster itself in AD. Without the $, AD would
# search for a user account named "Ushaclu22" (which doesn't exist) and
# fail with "name not found." The $ is mandatory.
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Phase 3 - Steps 3.1-3.3 - File Share Witness on USHADC" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------
# 3.1 - Create folder
# ---------------------------------------------------------------------
Write-Host "Step 3.1 - Creating folder C:\ClusterWitness\Ushaclu22..." -ForegroundColor Yellow
New-Item -Path 'C:\ClusterWitness\Ushaclu22' -ItemType Directory -Force | Out-Null
Write-Host "  Created." -ForegroundColor Green

# ---------------------------------------------------------------------
# 3.2 - Create SMB share with CNO Full Access
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "Step 3.2 - Creating SMB share with CNO Full Access..." -ForegroundColor Yellow

# If the share already exists from a prior attempt, remove it
if (Get-SmbShare -Name 'ClusterWitness' -ErrorAction SilentlyContinue) {
    Write-Host "  Existing share found — removing for clean recreate..." -ForegroundColor Yellow
    Remove-SmbShare -Name 'ClusterWitness' -Force -Confirm:$false
}

New-SmbShare -Name 'ClusterWitness' `
    -Path 'C:\ClusterWitness' `
    -FullAccess 'USHADC0\Domain Admins', 'USHADC0\Ushaclu22$'

Write-Host "  Share created with these permissions:" -ForegroundColor Green
Get-SmbShareAccess -Name 'ClusterWitness' | Format-Table Name, AccountName, AccessControlType, AccessRight -AutoSize

# ---------------------------------------------------------------------
# 3.3 - Set NTFS permissions on the folder
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "Step 3.3 - Setting NTFS Full Control for Ushaclu22..." -ForegroundColor Yellow

$acl = Get-Acl 'C:\ClusterWitness'
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'USHADC0\Ushaclu22$',
    'FullControl',
    'ContainerInherit,ObjectInherit',
    'None',
    'Allow')
$acl.SetAccessRule($rule)
Set-Acl 'C:\ClusterWitness' $acl

Write-Host "  NTFS ACL applied. Verifying..." -ForegroundColor Green
(Get-Acl 'C:\ClusterWitness').Access | Where-Object { $_.IdentityReference -like '*Ushaclu22*' } |
    Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize

Write-Host ""
Write-Host "Phase 3 prep on USHADC complete." -ForegroundColor Green
Write-Host "Next: switch to Node3 and run Step 3.4 to set the cluster quorum." -ForegroundColor Cyan
