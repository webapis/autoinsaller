<#
.SYNOPSIS
    Audits and configures Windows Remote Management (WinRM) / PowerShell Remoting.
    By default, automatically fixes issues if found.

.DESCRIPTION
    Checks:
    1. WinRM service status and startup type
    2. Active listeners (with fallback detection for Server Core/minimal installs)
    3. Firewall rules for current network profile

    By default, runs Enable-PSRemoting -Force to fix any issues.
    Use -DisableAutoRemediation for audit-only mode.

    Requires Administrator privileges.

.NOTES
    Author: Enhanced by Grok
    Version: 1.3
    Key improvement: Robust listener detection via Test-WSMan fallback
#>

[CmdletBinding()]
param (
    # Use this switch for audit-only mode (no changes made)
    [switch]$DisableAutoRemediation
)

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

Write-Verbose "Checking for Administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires Administrator privileges. Please run PowerShell as Administrator." -ErrorAction Stop
}

Clear-Host

# =============================================================================
# MAIN AUDIT FUNCTION
# =============================================================================

function Invoke-WinRmAudit {
    [CmdletBinding()]
    param (
        [string]$AuditTitle = "--- WinRM Configuration State Audit ---"
    )

    Write-Host $AuditTitle -ForegroundColor Cyan
    $auditFailed = $false

    # --- 1. WinRM Service Status ---
    Write-Host "`n[1] Checking WinRM Service Status..." -ForegroundColor Yellow
    try {
        $winrmService = Get-Service -Name "WinRM" -ErrorAction Stop
        $isRunning = $winrmService.Status -eq 'Running'
        $isAuto    = $winrmService.StartType -eq 'Automatic'

        [PSCustomObject]@{
            'Service Name' = $winrmService.Name
            'Status'       = $winrmService.Status
            'Start Type'   = $winrmService.StartType
        } | Format-List

        if ($isRunning -and $isAuto) {
            Write-Host "[SUCCESS] WinRM service is running and set to Automatic startup." -ForegroundColor Green
        }
        else {
            $auditFailed = $true
            if (-not $isRunning) { Write-Warning "WinRM service is not running." }
            if (-not $isAuto)    { Write-Warning "WinRM service is not set to Automatic startup." }
        }
    }
    catch {
        $auditFailed = $true
        Write-Error "WinRM service not found or inaccessible."
    }

    # --- 2. WinRM Listeners (with fallback) ---
    Write-Host "`n[2] Checking for WinRM Listeners..." -ForegroundColor Yellow
    $listenersDetected = $false

    try {
        $listeners = Get-WmiObject -Namespace 'root/cimv2/wsman' -Class '__WinRM_Listener' -ErrorAction Stop
        if ($listeners) {
            Write-Host "[SUCCESS] Active WinRM listeners found (via WMI)." -ForegroundColor Green
            $listeners | ForEach-Object {
                [PSCustomObject]@{
                    Address   = $_.Address
                    Transport = $_.Transport
                    Port      = $_.Port
                    Enabled   = $_.IsEnabled
                }
            } | Format-Table -AutoSize
            $listenersDetected = $true
        }
    }
    catch {
        # Fallback to Test-WSMan (more reliable on Server Core/minimal installs)
        try {
            Test-WSMan -ComputerName localhost -ErrorAction Stop | Out-Null
            Write-Host "[SUCCESS] WinRM is responding correctly (verified via Test-WSMan)." -ForegroundColor Green
            Write-Host "Note: WMI listener query unavailable, but functionality confirmed." -ForegroundColor Cyan
            $listenersDetected = $true
        }
        catch {
            $auditFailed = $true
            Write-Warning "WinRM is not responding. Both WMI query and Test-WSMan failed."
        }
    }

    if (-not $listenersDetected) {
        $auditFailed = $true
        Write-Warning "No WinRM listeners detected."
    }

    # --- 3. Firewall Rules ---
    Write-Host "`n[3] Checking Firewall Rules..." -ForegroundColor Yellow
    $winrmRuleGroup = "@FirewallAPI.dll,-30267"
    $firewallRules = Get-NetFirewallRule -Group $winrmRuleGroup -ErrorAction SilentlyContinue

    if ($firewallRules) {
        $ruleStatus = $firewallRules | Select-Object `
            DisplayName,
            @{Name="Enabled";  Expression={$_.Enabled}},
            @{Name="Profiles"; Expression={$_.Profile}},
            @{Name="Direction";Expression={$_.Direction}},
            @{Name="LocalPort"; Expression={(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_).LocalPort}}

        $ruleStatus | Format-Table -AutoSize

        $currentProfile = (Get-NetConnectionProfile | Select-Object -First 1).NetworkCategory

        $hasEnabledInbound = $firewallRules | Where-Object {
            $_.Enabled -eq 'True' -and
            $_.Direction -eq 'Inbound' -and
            ($_.Profile -contains 'Any' -or
             $_.Profile -contains $currentProfile -or
             ($currentProfile -eq 'DomainAuthenticated' -and ($_.Profile -like '*Domain*' -or $_.Profile -contains 'Domain')))
        }

        if ($hasEnabledInbound) {
            Write-Host "[SUCCESS] Enabled inbound firewall rule found for current profile ($currentProfile)." -ForegroundColor Green
        }
        else {
            $auditFailed = $true
            Write-Warning "No enabled inbound WinRM firewall rule for current profile ($currentProfile)."
        }
    }
    else {
        $auditFailed = $true
        Write-Warning "No Windows Remote Management firewall rules found."
    }

    Write-Host "`n--- Audit Complete ---" -ForegroundColor Cyan
    return $auditFailed
}

# =============================================================================
# EXECUTION
# =============================================================================

$initialAuditFailed = Invoke-WinRmAudit

if ($initialAuditFailed -and -not $DisableAutoRemediation) {
    Write-Host "`n[REMEDIATION] Issues detected. Automatically configuring WinRM..." -ForegroundColor Magenta
    try {
        Enable-PSRemoting -Force
        Write-Host "[REMEDIATION] WinRM successfully configured!" -ForegroundColor Green

        Write-Host "`n"
        Invoke-WinRmAudit -AuditTitle "--- Verification Audit After Remediation ---"
    }
    catch {
        Write-Error "Remediation failed: $_"
        Write-Host "Manual intervention may be required (e.g., Group Policy or feature installation)." -ForegroundColor Red
    }
}
elseif ($initialAuditFailed -and $DisableAutoRemediation) {
    Write-Host "`nAudit failed, but auto-remediation was disabled. No changes made." -ForegroundColor Yellow
}
else {
    Write-Host "`nAll checks passed - WinRM is fully configured and ready!" -ForegroundColor Green
}