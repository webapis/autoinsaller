<#
.SYNOPSIS
    Audits the local machine to verify the configuration state of Windows Remote
    Management (WinRM) and its associated firewall rules.

.DESCRIPTION
    This script provides a clear, color-coded status report on the key components
    required for WinRM to function correctly. It checks:
    1. If the WinRM service is running and set to start automatically.
    2. If there are active WinRM listeners for HTTP and/or HTTPS.
    3. If the necessary inbound firewall rules are enabled.

    The script must be run with Administrator privileges to access service
    and firewall configurations.

.NOTES
    Author: Gemini Code Assist
    Version: 1.0
#>
[CmdletBinding()]
param ()

#==============================================================================
# PRE-FLIGHT CHECKS
#==============================================================================

# Check for Administrator privileges, which are required for this script.
Write-Verbose "Checking for Administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires Administrator privileges. Please re-run it in an elevated PowerShell session." -ErrorAction Stop
}

# Clear the host for a clean output
Clear-Host

#==============================================================================
# SCRIPT BODY
#==============================================================================

Write-Host "--- WinRM Configuration State Audit ---" -ForegroundColor Cyan

# --- 1. Check WinRM Service State ---
Write-Host "`n[1] Checking WinRM Service Status..." -ForegroundColor Yellow
try {
    $winrmService = Get-Service -Name "WinRM" -ErrorAction Stop
    $isServiceRunning = $winrmService.Status -eq 'Running'
    $isServiceAuto = $winrmService.StartType -eq 'Automatic'

    # Use [PSCustomObject] for better compatibility across PowerShell versions.
    $serviceStatus = [PSCustomObject]@{
        'Service Name' = $winrmService.Name
        'Status'       = $winrmService.Status
        'Start Type'   = $winrmService.StartType
    }

    $serviceStatus | Format-List
    if ($isServiceRunning -and $isServiceAuto) {
        Write-Host "[SUCCESS] WinRM service is running and set to start automatically." -ForegroundColor Green
    }
    else {
        if (-NOT $isServiceRunning) {
            Write-Warning "WinRM service is not running."
        }
        if (-NOT $isServiceAuto) {
            Write-Warning "WinRM service is not set to 'Automatic'. It may not persist after a reboot."
        }
    }
}
catch {
    Write-Error "Could not find the WinRM service. It may not be installed."
}

# --- 2. Check WinRM Listener Configuration ---
Write-Host "`n[2] Checking for WinRM Listeners..." -ForegroundColor Yellow
try {
    # Use Get-WmiObject for compatibility with PowerShell v2. Get-CimInstance requires v3+.
    $listeners = Get-WmiObject -Namespace 'root/cimv2/wsman' -Class '__WinRM_Listener' -ErrorAction Stop

    if ($listeners) {
        Write-Host "[SUCCESS] Active WinRM listeners were found." -ForegroundColor Green
        $listeners | ForEach-Object {
            [PSCustomObject]@{
                'Address'   = $_.Address
                'Transport' = $_.Transport
                'Port'      = $_.Port
                'Enabled'   = $_.IsEnabled
            }
        } | Format-Table -AutoSize
    }
    else {
        Write-Warning "No active WinRM listeners were found. Run 'winrm quickconfig' to create them."
    }
}
catch {
    # This catch block will trigger if the WMI/CIM class doesn't exist or can't be queried.
    Write-Warning "Could not query for WinRM listeners. This may indicate a corrupted installation."
}

# --- 3. Check Firewall Rules ---
Write-Host "`n[3] Checking Firewall Rules..." -ForegroundColor Yellow
# The rule name can be localized. Using the Group name is more reliable across different language packs.
$winrmRuleGroup = "@FirewallAPI.dll,-30267" # This is the internal group name for "Windows Remote Management"
$firewallRules = Get-NetFirewallRule -Group $winrmRuleGroup -ErrorAction SilentlyContinue

if ($firewallRules) {
    $ruleStatus = $firewallRules | Select-Object -Property `
        DisplayName, `
        @{Name = "Enabled"; Expression = { $_.Enabled } }, `
        @{Name = "Profiles"; Expression = { $_.Profile } }, `
        @{Name = "Direction"; Expression = { $_.Direction } }, `
        @{Name = "LocalPort"; Expression = { (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_).LocalPort } }

    $ruleStatus | Format-Table -AutoSize

    # Check if at least one inbound rule is enabled for the current network profile.
    $currentProfileCategory = (Get-NetConnectionProfile | Select-Object -First 1).NetworkCategory
    $isRuleEnabledForProfile = $false
    if ($currentProfileCategory -eq 'DomainAuthenticated') {
        # Handle the case where the category is 'DomainAuthenticated' but the rule profile is just 'Domain'
        $isRuleEnabledForProfile = $firewallRules | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and ($_.Profile -like '*Domain*' -or $_.Profile -contains 'Any') }
    } else {
        $isRuleEnabledForProfile = $firewallRules | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and ($_.Profile -contains $currentProfileCategory -or $_.Profile -contains 'Any') }
    }

    if ($isRuleEnabledForProfile) {
        Write-Host "[SUCCESS] An active inbound firewall rule for WinRM was found for the current network profile category ($currentProfileCategory)." -ForegroundColor Green
    }
    else {
        Write-Warning "No enabled inbound WinRM firewall rule was found for the current network profile ($currentProfileCategory)."
    }
}
else {
    Write-Warning "Could not find any firewall rules in the 'Windows Remote Management' group."
}

Write-Host "`n--- Audit Complete ---" -ForegroundColor Cyan
