# Enable WinRM
Enable-PSRemoting -Force

# Configure WinRM service
winrm quickconfig -force

# Set WinRM to start automatically
Set-Service WinRM -StartupType Automatic

# Start the WinRM service
Start-Service WinRM

# Enable Basic authentication (for initial setup)
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Allow unencrypted traffic (only if using HTTP on port 5985)
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Enable CredSSP on the server side
Enable-WSManCredSSP -Role Server -Force

# Configure WinRM for CredSSP
Set-Item -Path "WSMan:\localhost\Service\Auth\CredSSP" -Value $true

# Add Administrator to Remote Management Users
net localgroup "Remote Management Users" Administrator /add

# Enable remote admin access for local accounts
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name LocalAccountTokenFilterPolicy `
    -Value 1 `
    -PropertyType DWord `
    -Force

# Check if WinRM firewall rule is enabled
Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"

# Restart WinRM Service
Restart-Service WinRM

# Test WinRM locally
Test-WSMan -ComputerName localhost