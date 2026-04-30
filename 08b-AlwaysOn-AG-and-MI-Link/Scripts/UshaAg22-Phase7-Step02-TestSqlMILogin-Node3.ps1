# =============================================================================
# UshaAg22-Phase7-Step02-TestSqlMILogin-Node3.ps1
# =============================================================================
# Phase:    7 — Pre-flight for MI Link
# Step:     7.2 — Test SQL authentication to SQL MI from Node3
# Run on:   Node3 (regular admin Windows PowerShell)
# Date:     April 29, 2026
# =============================================================================
#
# PURPOSE
# -------
# Confirms that Node3 can authenticate to SQL MI using SQL authentication.
# Validates:
#   - The SQL MI admin login credentials work
#   - TLS handshake succeeds (Min TLS 1.2 enforced)
#   - sqlcmd from Node3 can issue T-SQL against SQL MI
#
# CREDENTIAL HANDLING
# -------------------
# Use a $pwd variable to handle special characters cleanly in PowerShell.
# Embedding password directly in -P flag breaks if password has @, !, #, etc.
#
# SECURITY NOTE
# -------------
# In production, never hardcode passwords in scripts. Use:
#   - Azure Key Vault
#   - Windows Credential Manager
#   - Get-Credential prompt
# For lab use, hardcoding is acceptable but mark the script as lab-only.
# =============================================================================

$SqlMIPublicEndpoint = 'usha-sqlmi-poc.public.0f3157bbdbf7.database.windows.net,3342'
$SqlMIAdmin          = 'ssisadmin'
$pwd                 = '<your-MI-admin-password>'   # REPLACE before running

Write-Host ""
Write-Host "===== Testing sqlcmd login to SQL MI =====" -ForegroundColor Cyan
Write-Host "Server: $SqlMIPublicEndpoint" -ForegroundColor Yellow
Write-Host "User:   $SqlMIAdmin" -ForegroundColor Yellow
Write-Host ""

sqlcmd -S $SqlMIPublicEndpoint `
       -U $SqlMIAdmin `
       -P $pwd `
       -Q "SELECT @@SERVERNAME AS ServerName, GETDATE() AS CurrentTime"

# Expected: returns ServerName like 'usha-sqlmi-poc.0f3157bbdbf7.database.windows.net'
# If "Login failed": password is wrong, reset via Azure Portal
# If "timeout": NSG/network issue (Step 7.1 should have caught this)
