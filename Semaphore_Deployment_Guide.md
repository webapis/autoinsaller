# Semaphore UI Windows Application Deployment Guide

## Overview
This guide documents the setup for deploying applications to domain-joined Windows desktops using Semaphore UI (running in Docker on Windows Server).

**Scenario:**
*   **Controller:** Semaphore UI.
*   **Targets:** Windows Desktops.
*   **Authentication:** IT Admin provides Local Administrator credentials at runtime via Semaphore Survey.
*   **Source:** Applications are installed from a network Shared Folder.

## The Challenge: "Double Hop"
When Ansible connects to a target desktop using a **Local Administrator** account, the session is authenticated locally. This session cannot automatically authenticate to a network share (e.g., `\\FileServer\Apps`) because:
1.  The Local Admin account likely does not exist on the File Server.
2.  Even if it did, NTLM credentials do not pass through to the second hop (the file server).

## The Solution
We must separate the credentials:
1.  **Connection Credentials:** Use the Local Admin credentials (provided via Survey) to connect to the desktop.
2.  **Resource Credentials:** Use a specific Domain Service Account (stored in Semaphore) to map the network drive within the playbook.

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
Store the credentials for the **Shared Folder** in the Semaphore Key Store or Environment variables.
*   `share_user`: A Domain User with Read-Only access to the share (e.g., `DOMAIN\DeployUser`).
*   `share_password`: The password for the domain user.

#### Task Survey
Enable a **Survey** in the Task settings to capture the Local Admin credentials when the task is run:
*   `target_host`: (Type: String) - The target Hostname or IP address.
*   `target_username`: (Type: String) - The Local Admin username.
*   `target_password`: (Type: Password) - The Local Admin password.

### 3. Ansible Playbook
Create a playbook that uses the runtime credentials for the connection and the stored credentials for the share access.

```yaml
---
- name: Install Application on Windows Desktops
  hosts: "{{ target_host }}"
  gather_facts: no
  vars:
    # Connection variables (populated from Semaphore Survey)
    ansible_user: "{{ target_username }}"
    ansible_password: "{{ target_password }}"
    ansible_connection: winrm
    ansible_winrm_server_cert_validation: ignore
    ansible_winrm_transport: ntlm

    # Shared Folder details (Best practice: Store sensitive values in Semaphore Environment/Vault)
    share_path: "\\\\FileServer\\SoftwareShare"
    share_user: "DOMAIN\\DeployUser"
    share_password: "DeployUserPassword"
    installer_name: "MyAppInstaller.msi"

  tasks:
    - name: Check WinRM Connectivity
      win_ping:

    - name: Map Network Drive for Installer Access
      # Explicitly authenticating to the share avoids the Double Hop issue
      win_mapped_drive:
        letter: Z
        path: "{{ share_path }}"
        username: "{{ share_user }}"
        password: "{{ share_password }}"
        state: present

    - name: Install Application
      win_package:
        path: "Z:\\{{ installer_name }}"
        product_id: "{YOUR-APP-GUID-HERE}" # Optional: Prevents reinstall
        arguments: /quiet /norestart
        state: present
      register: install_result

    - name: Unmap Network Drive
      win_mapped_drive:
        letter: Z
        state: absent
```
```