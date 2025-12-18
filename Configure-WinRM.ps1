#Next Step: Configure WinRM on Your Windows PC
# Enable WinRM
winrm quickconfig -force
# Allow basic authentication
winrm set winrm/config/service/auth '@{Basic="true"}'
# Allow unencrypted traffic (for testing - use HTTPS in production)
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
# Set trusted hosts (replace with your Rundeck server IP)
winrm set winrm/config/client '@{TrustedHosts="*"}'
# Allow WinRM through firewall
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow

#Verify WinRM is running:
Test-WSMan