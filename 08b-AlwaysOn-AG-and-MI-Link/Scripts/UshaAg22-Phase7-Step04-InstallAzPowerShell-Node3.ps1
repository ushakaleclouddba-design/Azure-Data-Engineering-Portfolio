# =============================================================================
# UshaAg22-Phase7-Step04-InstallAzPowerShell-Node3.ps1
# =============================================================================
# Phase:    7 — Pre-flight for MI Link
# Step:     7.4 — Install Az PowerShell on Node3
# Run on:   Node3 (regular admin Windows PowerShell)
# Date:     April 29, 2026
# =============================================================================
#
# PURPOSE
# -------
# Installs the Az PowerShell meta-module (~70 sub-modules including Az.Sql)
# on Node3. Az.Sql provides cmdlets needed for MI Link cert exchange:
#   - New-AzSqlInstanceServerTrustCertificate (upload cert to SQL MI)
#   - Get-AzSqlInstanceEndpointCertificate (download SQL MI cert)
#
# DBATOOLS CONFLICT WARNING
# -------------------------
# Az PowerShell + dbatools share Azure.Identity.dll on Windows PowerShell 5.1.
# Loading both in the same session causes "Method not found" errors.
# This script assumes dbatools is NOT installed on Node3.
# Verify before running:
#   Get-Module -ListAvailable dbatools
# Should return nothing.
#
# If dbatools IS installed, options:
#   1. Use PowerShell 7 (isolated AssemblyLoadContexts solve the conflict)
#   2. Uninstall dbatools from Node3
#   3. Use a different node for Az operations (e.g., Node5)
#
# INSTALLATION DETAILS
# --------------------
# Scope AllUsers: requires admin, installs to Program Files
# AllowClobber:   permits overwriting older Az command versions if any
# Force:          skips confirmation prompts
# Repository:     PSGallery is the official PowerShell package repo
#
# Time: 5-15 minutes depending on internet speed (~150 MB)
# =============================================================================

#Requires -RunAsAdministrator

# Pre-check: ensure no dbatools conflict
$dbatools = Get-Module -ListAvailable dbatools
if ($dbatools) {
    Write-Host "WARNING: dbatools is installed. Az + dbatools conflict in PS 5.1." -ForegroundColor Red
    Write-Host "Uninstall dbatools or use PS7 before installing Az." -ForegroundColor Red
    return
}

# Trust PSGallery to silence prompts during install
Write-Host "Setting PSGallery as trusted..." -ForegroundColor Yellow
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install Az meta-module
Write-Host "Installing Az PowerShell module (will take 5-15 min)..." -ForegroundColor Yellow
Install-Module -Name Az `
    -Scope AllUsers `
    -AllowClobber `
    -Force `
    -Repository PSGallery

# Verify
Write-Host ""
Write-Host "===== Verification =====" -ForegroundColor Green
Get-Module -ListAvailable Az.Sql | Select-Object Name, Version | Format-Table -AutoSize
Get-Module -ListAvailable Az.Accounts | Select-Object Name, Version | Format-Table -AutoSize

# Expected: Az.Sql 4.x or higher (we got 6.4.1 in the build)
