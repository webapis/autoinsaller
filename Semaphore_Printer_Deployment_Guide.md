# Semaphore UI Windows Printer Deployment Guide

## Overview
This guide documents the setup for deploying network printers to domain-joined Windows desktops using Semaphore UI.

**Scenario:**
*   **Objective:** Install a shared network printer (`\\PrintServer\PrinterName`) on the target desktop.
*   **Authentication:** IT Admin provides Local Administrator credentials at runtime via Semaphore Survey.

## The Challenge: "Double Hop"
When Ansible connects to a target desktop using a **Local Administrator** account, the session is authenticated locally. This session cannot automatically authenticate to the Print Server to download drivers or connect to the queue because NTLM credentials do not pass through to the second hop.

## The Solution
1.  **Authenticate:** Establish an authenticated session to the Print Server (using `IPC$`) within the playbook.
2.  **Install:** Use the Windows `printui.dll` command to perform a "Global Add" (`/ga`) of the printer. This makes the printer available to all users on that machine.
3.  **Restart:** Restart the Print Spooler service to apply changes.

## Implementation Steps

### 1. Prepare Target Desktops
Ensure WinRM is enabled and listening on the target desktops.
*   **Audit:** Run `Test-WinRMState.ps1` to check status.
*   **Configure:** Run `Configure-WinRM.ps1` or `Enable-PSRemoting -Force`.
*   **Firewall:** Ensure port 5985 (HTTP) or 5986 (HTTPS) is open.

### 2. Configure Semaphore UI

#### Inventory
Create an inventory in Semaphore containing the IP addresses or hostnames of the target desktops.

#### Environment / Secrets
Store the credentials for the **Print Server** in the Semaphore Key Store or Environment variables.
*   `share_user`: A Domain User with Read access to the print server (e.g., `DOMAIN\DeployUser`).
*   `share_password`: The password for the domain user.

#### Task Survey
Enable a **Survey** in the Task settings to capture the Local Admin credentials when the task is run:
*   `target_host`: (Type: String) - The target Hostname or IP address.
*   `target_username`: (Type: String) - The Local Admin username.
*   `target_password`: (Type: Password) - The Local Admin password.
*   `printer_name`: (Type: Select) - The printer to install. In the **Options** field, provide a JSON list of printer names (e.g., `["MRK-K0-BT-Konica-224-Color", "Office-Printer-01"]`).

### 3. Ansible Playbook
Create the playbook `ansible/playbooks/install-printer.yml`.

```yaml
---
- name: Deploy Network Printer
  hosts: "{{ target_host }}"
  gather_facts: no
  vars:
    # Connection variables (populated from Semaphore Survey)
    ansible_user: "{{ target_username }}"
    ansible_password: "{{ target_password }}"
    ansible_connection: winrm
    ansible_winrm_server_cert_validation: ignore
    ansible_winrm_transport: credssp
    ansible_winrm_read_timeout_sec: 90

    # Printer Details
    print_server: "HVTRM-WS-PRNT.caliksoa.local"
    # Domain Credentials for Print Server Access
    share_user: "DOMAIN\\DeployUser"
    share_password: "DeployUserPassword"

  tasks:
    - name: Configure Point and Print Policies (Prevent Driver Prompts)
      win_shell: |
        $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (!(Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "RestrictDriverInstallationToAdministrators" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $p -Name "UpdatePromptSettings" -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $p -Name "NoWarningNoElevationOnInstall" -Value 1 -Type DWord -Force

    - name: Restart Spooler Service (Apply Policies)
      win_service:
        name: Spooler
        state: restarted

    - name: Install Printer (Authenticated Session)
      # Consolidating Auth, Install, and Verify into one task ensures the session persists
      win_shell: |
        $ErrorActionPreference = 'Stop'
        $server = "{{ print_server }}"
        $printer = "{{ printer_name | replace('[', '') | replace(']', '') | replace('\"', '') }}"
        $user = "{{ share_user }}"
        $pass = "{{ share_password }}"
        $fullPath = "\\$server\$printer"

        try {
            # 1. Authenticate
            & cmdkey /add:$server /user:$user /pass:$pass | Out-Null
            $netArgs = @("use", "\\$server\IPC$", "/user:$user", "$pass")
            & net.exe $netArgs 2>&1 | Out-Null
            $netArgsPrint = @("use", "\\$server\print$", "/user:$user", "$pass")
            & net.exe $netArgsPrint 2>&1 | Out-Null

            # 2. Pre-check RPC
            try { 
                $remotePrinters = Get-Printer -ComputerName $server -ErrorAction Stop 
                $targetPrinter = $remotePrinters | Where-Object { $_.Name -eq $printer -or $_.ShareName -eq $printer } | Select-Object -First 1
                if ($targetPrinter) {
                    $printer = $targetPrinter.ShareName
                    $fullPath = "\\$server\$printer"
                    Write-Host "Resolved Share: $printer"
                }
            } catch { Write-Warning "RPC check failed." }

            # 3. Install (Global Add)
            $printArgs = "printui.dll,PrintUIEntry /ga /n`"$fullPath`" /q"
            Start-Process rundll32.exe -ArgumentList $printArgs
            Start-Sleep -Seconds 60

            # 4. Restart Spooler
            Restart-Service Spooler -Force
            $timeout = 0
            while ((Get-Service Spooler).Status -ne 'Running' -and $timeout -lt 30) {
                Start-Sleep -Seconds 1
                $timeout++
            }
            Start-Sleep -Seconds 10

            # 5. Verify and Fallback
            $installed = Get-Printer | Where-Object { $_.Name -eq $fullPath -or $_.Name -like "*$printer*" }
            if (-not $installed) {
                Write-Warning "Global Add verification failed. Attempting PowerShell Add-Printer..."
                try {
                    Add-Printer -ConnectionName $fullPath -ErrorAction Stop
                } catch {
                    try {
                        # Try WMI
                        ([wmiclass]"\\.\root\cimv2:Win32_Printer").AddPrinterConnection($fullPath)
                    } catch {
                        try {
                            # Try COM Object
                            (New-Object -ComObject WScript.Network).AddWindowsPrinterConnection($fullPath)
                        } catch {
                            if ($serverIP) {
                                Add-Printer -ConnectionName "\\$serverIP\$printer" -ErrorAction Stop
                            } else { throw $_ }
                        }
                    }
                }
            }
            Write-Host "Printer installed successfully."
        }
        finally {
            # 6. Cleanup
            & net.exe use "\\$server\IPC$" /delete 2>&1 | Out-Null
            & net.exe use "\\$server\print$" /delete 2>&1 | Out-Null
            & cmdkey /delete:$server 2>&1 | Out-Null
            & cmdkey /delete:$shortServer 2>&1 | Out-Null
            if ($serverIP) { & cmdkey /delete:$serverIP 2>&1 | Out-Null }
        }
```

### 4. Template Configuration
To run this playbook in Semaphore:

1.  **Create Template:** Go to **Task Templates** > **New Template**.
2.  **Settings:**
    *   **Name:** `Deploy Network Printer`
    *   **Playbook Filename:** `ansible/playbooks/install-printer.yml`
    *   **Inventory:** Select your Windows inventory.
3.  **Survey:** Click **Add** to define the following survey variables:
    *   **Variable:** `target_host` | **Type:** String | **Title:** Target PC IP
    *   **Variable:** `target_username` | **Type:** String | **Title:** Local Admin User
    *   **Variable:** `target_password` | **Type:** Password | **Title:** Local Admin Password
    *   **Variable:** `printer_name` | **Type:** Select | **Title:** Select Printer
        *   **Options:** `["MRK-K0-BT-Konica-224-Color"]`