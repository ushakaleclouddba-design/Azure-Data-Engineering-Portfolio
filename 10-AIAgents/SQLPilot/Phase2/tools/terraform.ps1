<#
.SYNOPSIS
    SQLPilot - Real apply_terraform tool implementation.

.DESCRIPTION
    Replaces the stubbed apply_terraform in agent.ps1 with a real
    terraform plan/apply/destroy pipeline.

    Mechanics:
      - action='plan'    -> terraform plan -out=tfplan -no-color
      - action='apply'   -> terraform plan -out=tfplan -no-color
                            then terraform apply -no-color tfplan
      - action='destroy' -> terraform destroy -auto-approve -no-color

    After a successful apply or plan, reads `terraform output -json` and
    surfaces the SQLPilot deployment bundle (public IP, VM name, RG, etc.)
    so the agent and downstream tools (like restore_database) can use it
    immediately.

    Streaming behaviour:
      terraform is spawned with output going directly to the parent
      console (no -NoNewWindow buffering quirks - we use & operator with
      stdout/stderr inherited). This means the user sees progress in
      real time during a multi-minute apply.

.NOTES
    Author : Kale
    Pattern: mirrors tools/restore.ps1 and tools/kb.ps1 - agent.ps1
             dot-sources this file at startup; if loaded,
             Tool-ApplyTerraform calls Invoke-RealApplyTerraform.
             If this file is missing the agent falls back to its
             inline mock so the loop still runs end-to-end.
#>


# ---------------------------------------------------------------------------
# Resolve the Terraform module directory once and cache it. Same lookup
# strategy as restore.ps1: explicit -TerraformDir, then SQLPilot\Terraform,
# then SQLPilot\, then cwd. The marker we look for is a .terraform/ folder
# (created by `terraform init`).
# ---------------------------------------------------------------------------
$script:TfDir = $null

# Locate the SQLPilot Terraform directory. Strategy:
#   1. If caller passed -TerraformDir, use it.
#   2. Walk a list of candidates (ScriptRoot\Terraform, ScriptRoot, cwd),
#      pick the first one that contains *.tf files.
#   3. If the picked dir has no .terraform\ marker (i.e. `terraform init`
#      was never run), run `terraform init` once automatically. This is
#      the fresh-install case — recipient extracts the zip, has .tf files
#      but no .terraform\ yet.
function Resolve-TerraformDir {
    [CmdletBinding()]
    param (
        [string] $TerraformDir
    )

    function _DirHasTf {
        param([string] $D)
        if (-not $D -or -not (Test-Path $D)) { return $false }
        $tf = Get-ChildItem -Path $D -Filter '*.tf' -ErrorAction SilentlyContinue | Select-Object -First 1
        return [bool] $tf
    }

    function _EnsureInit {
        param([string] $D)
        $marker = Join-Path $D '.terraform'
        if (Test-Path $marker) { return }  # already initialized
        Write-Host "[terraform] $D has no .terraform\ marker — running 'terraform init' (one-time)..." -ForegroundColor DarkCyan
        $proc = Start-Process -FilePath 'terraform' -ArgumentList @("-chdir=$D", 'init', '-input=false') `
            -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            throw "terraform init failed in '$D' (exit $($proc.ExitCode)). Run 'terraform -chdir=$D init' manually for details."
        }
        Write-Host "[terraform] init OK" -ForegroundColor DarkGreen
    }

    if ($TerraformDir -and (_DirHasTf $TerraformDir)) {
        _EnsureInit $TerraformDir
        return $TerraformDir
    }

    $candidates = @()
    if ($script:ScriptRoot) {
        $candidates += (Join-Path $script:ScriptRoot 'Terraform')
        $candidates += $script:ScriptRoot
    }
    $candidates += (Get-Location).Path

    foreach ($c in $candidates) {
        if (_DirHasTf $c) {
            _EnsureInit $c
            return $c
        }
    }
    throw "Could not locate the SQLPilot Terraform directory (looked for *.tf files in: $($candidates -join '; ')). Pass -TerraformDir explicitly."
}


# ---------------------------------------------------------------------------
# Helper - run terraform with -chdir, streaming its output to the parent
# console. Returns @{ ExitCode = N; Output = "..." } so callers can both
# show progress AND parse the captured text for summary lines.
#
# We can't use `terraform.exe | Tee-Object` directly because Tee-Object
# buffers - the apply line "Still creating... [00m30s elapsed]" would
# appear in chunks of minutes. Instead we redirect to a temp file and
# tail it with Out-Host as it grows. That's heavier than needed for short
# commands (plan, destroy of nothing), so we only tail-stream for the
# 'apply' case. plan/destroy run with direct stream (terraform writes to
# the inherited console).
# ---------------------------------------------------------------------------
function Invoke-Terraform {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $TerraformDir,
        [Parameter(Mandatory)] [string[]] $TerraformArgs,
        [switch] $CaptureOutput   # also return the output as a string for parsing
    )

    # Build the full arg vector. -chdir must come FIRST (before the
    # subcommand). -no-color goes inside the subcommand args.
    $allArgs = @("-chdir=$TerraformDir") + $TerraformArgs

    if ($CaptureOutput) {
        # Capture to a temp file, stream lines as they arrive.
        $logPath = [System.IO.Path]::GetTempFileName()
        try {
            # Start terraform; redirect both stdout+stderr to the temp log.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = 'terraform'
            foreach ($a in $allArgs) { [void]$psi.ArgumentList.Add($a) }
            $psi.UseShellExecute        = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.CreateNoWindow         = $true

            $proc = [System.Diagnostics.Process]::Start($psi)

            # Stream each line to host while collecting for return.
            $sb = New-Object System.Text.StringBuilder
            while (-not $proc.StandardOutput.EndOfStream) {
                $line = $proc.StandardOutput.ReadLine()
                Write-Host $line
                [void]$sb.AppendLine($line)
            }
            # Drain any stderr after stdout closes.
            $errText = $proc.StandardError.ReadToEnd()
            if ($errText) {
                Write-Host $errText -ForegroundColor DarkYellow
                [void]$sb.AppendLine($errText)
            }
            $proc.WaitForExit()

            return @{
                ExitCode = $proc.ExitCode
                Output   = $sb.ToString()
            }
        } finally {
            if (Test-Path $logPath) { Remove-Item $logPath -ErrorAction SilentlyContinue }
        }
    } else {
        # Simple inherited-stream path: terraform's output goes to the
        # parent console as it happens. No capture.
        & terraform @allArgs
        return @{ ExitCode = $LASTEXITCODE; Output = '' }
    }
}


# ---------------------------------------------------------------------------
# Parse terraform's "Apply complete!" / "Destroy complete!" / "Plan:" lines
# from captured output to extract resource counts. Returns a hashtable with
# integer counts (zero-defaulted if not found).
# ---------------------------------------------------------------------------
function Get-TerraformCounts {
    [CmdletBinding()]
    param ([string] $Output)

    $counts = @{ to_add = 0; to_change = 0; to_destroy = 0; added = 0; changed = 0; destroyed = 0 }
    if (-not $Output) { return $counts }

    # "Plan: N to add, M to change, K to destroy."
    $planMatch = [regex]::Match($Output, 'Plan:\s+(\d+)\s+to add,\s+(\d+)\s+to change,\s+(\d+)\s+to destroy')
    if ($planMatch.Success) {
        $counts.to_add     = [int]$planMatch.Groups[1].Value
        $counts.to_change  = [int]$planMatch.Groups[2].Value
        $counts.to_destroy = [int]$planMatch.Groups[3].Value
    }

    # "Apply complete! Resources: N added, M changed, K destroyed."
    $applyMatch = [regex]::Match($Output, 'Apply complete!\s+Resources:\s+(\d+)\s+added,\s+(\d+)\s+changed,\s+(\d+)\s+destroyed')
    if ($applyMatch.Success) {
        $counts.added     = [int]$applyMatch.Groups[1].Value
        $counts.changed   = [int]$applyMatch.Groups[2].Value
        $counts.destroyed = [int]$applyMatch.Groups[3].Value
    }

    # "Destroy complete! Resources: N destroyed."
    $destroyMatch = [regex]::Match($Output, 'Destroy complete!\s+Resources:\s+(\d+)\s+destroyed')
    if ($destroyMatch.Success) {
        $counts.destroyed = [int]$destroyMatch.Groups[1].Value
    }

    return $counts
}


# ---------------------------------------------------------------------------
# Read terraform outputs as a flat hashtable: { name -> value }. Skips
# sensitive outputs (we don't want SAS URLs in the agent's decision log).
# Returns $null if no outputs (e.g. immediately after destroy).
# ---------------------------------------------------------------------------
function Get-TerraformOutputs {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string] $TerraformDir)

    $json = & terraform -chdir="$TerraformDir" output -json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json -or $json -eq '{}') {
        return $null
    }
    $obj = $json | ConvertFrom-Json
    $out = @{}
    foreach ($prop in $obj.PSObject.Properties) {
        $val = $prop.Value
        if ($val.sensitive) {
            $out[$prop.Name] = '<sensitive - redacted>'
        } else {
            $out[$prop.Name] = $val.value
        }
    }
    return $out
}


# ---------------------------------------------------------------------------
# Invoke-RealApplyTerraform
#
# The function agent.ps1's Tool-ApplyTerraform checks for via Get-Command.
# Same arg shape as the stub: -Action  (plan | apply | destroy).
# ---------------------------------------------------------------------------
function Invoke-RealApplyTerraform {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [ValidateSet('plan','apply','destroy')] [string] $Action
    )

    $started = Get-Date

    # Resolve and cache the Terraform dir on first use.
    if (-not $script:TfDir) {
        $script:TfDir = Resolve-TerraformDir
    }
    $tfDir = $script:TfDir

    Write-Host "[terraform] dir=$tfDir action=$Action" -ForegroundColor DarkGray

    switch ($Action) {

        'plan' {
            # plan: write to ./tfplan so a follow-up apply can consume it.
            $r = Invoke-Terraform `
                -TerraformDir $tfDir `
                -TerraformArgs @('plan','-out=tfplan','-no-color') `
                -CaptureOutput
            $counts = Get-TerraformCounts -Output $r.Output

            if ($r.ExitCode -ne 0) {
                return @{
                    status    = 'error'
                    mock      = $false
                    action    = 'plan'
                    error     = "terraform plan failed with exit code $($r.ExitCode)"
                    exit_code = $r.ExitCode
                    terraform_dir = $tfDir
                    duration_seconds = [int]((Get-Date) - $started).TotalSeconds
                }
            }

            return @{
                status            = 'ok'
                mock              = $false
                action            = 'plan'
                terraform_dir     = $tfDir
                resources_to_add      = $counts.to_add
                resources_to_change   = $counts.to_change
                resources_to_destroy  = $counts.to_destroy
                plan_file         = (Join-Path $tfDir 'tfplan')
                duration_seconds  = [int]((Get-Date) - $started).TotalSeconds
                next_step_hint    = if ($counts.to_add -gt 0 -or $counts.to_change -gt 0 -or $counts.to_destroy -gt 0) {
                    'Plan has changes. Call apply_terraform with action=apply after the DBA approval gate.'
                } else {
                    'Plan shows no changes. State is in sync with config; apply would be a no-op.'
                }
            }
        }

        'apply' {
            # apply: do a plan first (to capture intent + a fresh tfplan),
            # then apply that exact plan. This is the safe pattern - never
            # let `apply` run an unreviewed plan.
            $planResult = Invoke-Terraform `
                -TerraformDir $tfDir `
                -TerraformArgs @('plan','-out=tfplan','-no-color') `
                -CaptureOutput
            $planCounts = Get-TerraformCounts -Output $planResult.Output
            if ($planResult.ExitCode -ne 0) {
                return @{
                    status    = 'error'
                    mock      = $false
                    action    = 'apply'
                    error     = "terraform plan (pre-apply) failed with exit code $($planResult.ExitCode)"
                    exit_code = $planResult.ExitCode
                    terraform_dir = $tfDir
                    duration_seconds = [int]((Get-Date) - $started).TotalSeconds
                }
            }

            # Now apply the captured plan.
            $applyResult = Invoke-Terraform `
                -TerraformDir $tfDir `
                -TerraformArgs @('apply','-no-color','tfplan') `
                -CaptureOutput
            $applyCounts = Get-TerraformCounts -Output $applyResult.Output

            if ($applyResult.ExitCode -ne 0) {
                return @{
                    status    = 'error'
                    mock      = $false
                    action    = 'apply'
                    error     = "terraform apply failed with exit code $($applyResult.ExitCode)"
                    exit_code = $applyResult.ExitCode
                    terraform_dir = $tfDir
                    plan_summary  = "Plan was: $($planCounts.to_add) to add, $($planCounts.to_change) to change, $($planCounts.to_destroy) to destroy."
                    duration_seconds = [int]((Get-Date) - $started).TotalSeconds
                }
            }

            # Successful apply - pull outputs.
            $outputs = Get-TerraformOutputs -TerraformDir $tfDir

            $result = @{
                status            = 'ok'
                mock              = $false
                action            = 'apply'
                terraform_dir     = $tfDir
                resources_added       = $applyCounts.added
                resources_changed     = $applyCounts.changed
                resources_destroyed   = $applyCounts.destroyed
                duration_seconds  = [int]((Get-Date) - $started).TotalSeconds
            }

            # Surface key deployment fields at the top level for the
            # agent's convenience. These match what apply_terraform's
            # stub returned, so the agent's downstream logic doesn't
            # change.
            if ($outputs) {
                $result['target_resource']      = $outputs['vm_name']
                $result['public_ip']            = $outputs['public_ip_address']
                $result['resource_group_name']  = $outputs['resource_group_name']
                $result['connection_string']    = $outputs['sql_connection_string']
                $result['sqlpilot_deployment']  = $outputs['sqlpilot_deployment']
                $result['sqlpilot_storage']     = $outputs['sqlpilot_storage']
            }

            return $result
        }

        'destroy' {
            $r = Invoke-Terraform `
                -TerraformDir $tfDir `
                -TerraformArgs @('destroy','-auto-approve','-no-color') `
                -CaptureOutput
            $counts = Get-TerraformCounts -Output $r.Output

            if ($r.ExitCode -ne 0) {
                return @{
                    status    = 'error'
                    mock      = $false
                    action    = 'destroy'
                    error     = "terraform destroy failed with exit code $($r.ExitCode)"
                    exit_code = $r.ExitCode
                    terraform_dir = $tfDir
                    duration_seconds = [int]((Get-Date) - $started).TotalSeconds
                }
            }

            return @{
                status            = 'ok'
                mock              = $false
                action            = 'destroy'
                terraform_dir     = $tfDir
                resources_destroyed = $counts.destroyed
                duration_seconds  = [int]((Get-Date) - $started).TotalSeconds
                note              = if ($counts.destroyed -eq 0) { 'Nothing to destroy - state was already empty.' } else { "$($counts.destroyed) resources destroyed cleanly." }
            }
        }
    }
}
