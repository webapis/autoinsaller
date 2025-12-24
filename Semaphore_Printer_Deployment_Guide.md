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
    ansible_winrm_transport: ntlm

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

    - name: Restart Spooler Service (Apply Policies)
      win_service:
        name: Spooler
        state: restarted

    - name: Authenticate to Print Server (IPC$)
      # We map the IPC$ share to establish a valid Kerberos/NTLM session with the server
      win_command: 'net use \\{{ print_server }}\IPC$ /user:{{ share_user }} {{ share_password }}'

    - name: Add Printer Globally
      # /ga = Global Add (per-machine connection)
      # /n = Printer Name
      win_command: 'rundll32 printui.dll,PrintUIEntry /ga /n"\\{{ print_server }}\{{ printer_name | replace("[", "") | replace("]", "") | replace("\"", "") }}" /q'

    - name: Wait for Driver Installation
      # Give the background installation time to complete before restarting spooler
      win_shell: Start-Sleep -Seconds 15

    - name: Restart Spooler Service (Finalize Install)
      # Required for Global Add changes to take effect
      win_service:
        name: Spooler
        state: restarted

    - name: Verify Printer Installation
      win_shell: |
        $printerName = "{{ printer_name | replace('[', '') | replace(']', '') | replace('"', '') }}"
        $fullPath = "\\{{ print_server }}\$printerName"
        if (-not (Get-Printer -Name $fullPath -ErrorAction SilentlyContinue)) {
            # Attempt to add via PowerShell to capture the specific error message
            try {
                Add-Printer -ConnectionName $fullPath -ErrorAction Stop
                Write-Warning "Printer was added via PowerShell (Per-User) because Global Add failed silently."
            } catch {
                Write-Error "Printer installation failed. Error: $($_.Exception.Message)"
            }
        }

    - name: Remove Authentication
      win_command: 'net use \\{{ print_server }}\IPC$ /delete'
      ignore_errors: yes
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