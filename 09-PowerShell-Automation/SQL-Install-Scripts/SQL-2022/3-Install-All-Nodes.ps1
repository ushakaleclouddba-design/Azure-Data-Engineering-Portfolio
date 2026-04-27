# Master SQL Install Orchestrator - Push ISO locally, then install remotely
# Run ONCE from SriniDc

$nodes = "SRINI-NODE1", "SRINI-NODE2", "SRINI-NODE3"

# Source files on SriniDc
$sourceIso    = "C:\SQLInstall\SQLServer2022-x64-ENU-Dev.iso"
$sourceConfig = "C:\SQLInstall\SQL2022-Config.ini"
$sourceScript = "C:\SQLInstall\2-Install-SQL.ps1"

# Verify source files exist
foreach ($f in $sourceIso, $sourceConfig, $sourceScript) {
    if (-not (Test-Path $f)) { throw "Source file missing: $f" }
}

# STEP 1: Push files to each node's local C:\SQLInstall
Write-Host "`n=== STEP 1: Pushing files to all 3 nodes ===" -ForegroundColor Cyan

foreach ($node in $nodes) {
    Write-Host "`nPushing to $node..." -ForegroundColor Yellow

    # Create target folder
    New-Item -Path "\\$node\C$\SQLInstall" -ItemType Directory -Force | Out-Null

    # Copy files (ISO takes 2-5 min over network)
    Write-Host "  Copying ISO (1.1 GB)..." -ForegroundColor Gray
    Copy-Item $sourceIso    "\\$node\C$\SQLInstall\" -Force
    Copy-Item $sourceConfig "\\$node\C$\SQLInstall\" -Force
    Copy-Item $sourceScript "\\$node\C$\SQLInstall\" -Force

    # Verify
    $test = Test-Path "\\$node\C$\SQLInstall\SQLServer2022-x64-ENU-Dev.iso"
    Write-Host "  $node ready: $test" -ForegroundColor Green
}

# STEP 2: Fire off installs in parallel
Write-Host "`n=== STEP 2: Starting parallel installs ===" -ForegroundColor Cyan

$jobs = Invoke-Command -ComputerName $nodes -FilePath $sourceScript -AsJob

Write-Host "Jobs started. Install takes 20-30 min per node (parallel)." -ForegroundColor Yellow
Write-Host "`nMonitor with:" -ForegroundColor Yellow
Write-Host "  Get-Job" -ForegroundColor White
Write-Host "  Get-Job | Receive-Job -Keep" -ForegroundColor White
Write-Host "  Get-Job | Wait-Job  # blocks until all done" -ForegroundColor White

Get-Job
