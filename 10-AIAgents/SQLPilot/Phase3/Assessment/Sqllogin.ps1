<#
.SYNOPSIS
  Creates the sqlpilot SQL Auth login on every server in a list.
  Adds it to sysadmin role. Idempotent: re-running just resets password.

.EXAMPLE
  .\Create-SqlPilotLogin.ps1 -Servers 'Node1','Node2','Node3','Node4','Node5','Node6'
#>
param(
    [Parameter(Mandatory)]
    [string[]] $Servers,

    [string] $LoginName = 'SqlPilot'
)

# Prompt for password once. Not stored anywhere.
$password = Read-Host "Enter password for [$LoginName] (will be applied to all servers)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
$plainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrWhiteSpace($plainPwd)) {
    Write-Host "Password cannot be empty. Exiting." -ForegroundColor Red
    return
}

# Escape any single-quotes in the password (rare but possible)
$escapedPwd = $plainPwd.Replace("'", "''")

# Idempotent T-SQL: create if missing, otherwise reset password.
# Then ensure sysadmin membership.
$sql = @"
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$LoginName')
BEGIN
    CREATE LOGIN [$LoginName]
        WITH PASSWORD = '$escapedPwd',
        CHECK_POLICY = OFF,
        CHECK_EXPIRATION = OFF,
        DEFAULT_DATABASE = [master],
        DEFAULT_LANGUAGE = [us_english];
    PRINT 'Created login [$LoginName]';
END
ELSE
BEGIN
    ALTER LOGIN [$LoginName]
        WITH PASSWORD = '$escapedPwd',
        CHECK_POLICY = OFF,
        CHECK_EXPIRATION = OFF;
    PRINT 'Updated password for existing login [$LoginName]';
END

IF NOT EXISTS (
    SELECT 1 FROM sys.server_role_members rm
    INNER JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
    WHERE r.name = 'sysadmin' AND m.name = '$LoginName'
)
BEGIN
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [$LoginName];
    PRINT 'Added [$LoginName] to sysadmin role';
END
ELSE
BEGIN
    PRINT '[$LoginName] is already in sysadmin role';
END

SELECT
    SUSER_SNAME() AS RunAs,
    @@SERVERNAME AS ServerName,
    (SELECT name FROM sys.server_principals WHERE name = '$LoginName') AS LoginExists,
    (SELECT IIF(EXISTS(
        SELECT 1 FROM sys.server_role_members rm
        INNER JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
        INNER JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
        WHERE r.name = 'sysadmin' AND m.name = '$LoginName'
    ), 'Yes', 'No')) AS IsSysadmin;
"@

# Loop over servers, run via Windows Auth (your current domain user has sysadmin everywhere)
$results = @()
foreach ($srv in $Servers) {
    Write-Host "`n--- $srv ---" -ForegroundColor Cyan
    try {
        $r = Invoke-Sqlcmd -ServerInstance $srv -Query $sql `
            -TrustServerCertificate -Encrypt Optional `
            -ErrorAction Stop -QueryTimeout 30
        Write-Host "  OK - login: $($r.LoginExists), sysadmin: $($r.IsSysadmin)" -ForegroundColor Green
        $results += [pscustomobject]@{
            Server = $srv
            Status = 'OK'
            LoginExists = $r.LoginExists
            IsSysadmin = $r.IsSysadmin
        }
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $results += [pscustomobject]@{
            Server = $srv
            Status = 'FAILED'
            LoginExists = ''
            IsSysadmin = ''
        }
    }
}

# Clear plaintext password from memory
$plainPwd = $null
$escapedPwd = $null

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize