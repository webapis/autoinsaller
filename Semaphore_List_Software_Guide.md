# Semaphore UI Windows List Software Guide

## Overview
This guide documents the setup for retrieving a list of installed applications from domain-joined Windows desktops using Semaphore UI.

**Scenario:**
*   **Objective:** Generate a list of installed software (Name, Version, Publisher) from a target desktop.
*   **Authentication:** IT Admin provides Local Administrator credentials at runtime via Semaphore Survey.

## Implementation Steps

### 1. Prepare Target Desktops
Ensure WinRM is enabled and listening on the target desktops.
*   **Audit:** Run `Test-WinRMState.ps1`.
*   **Configure:** Run `Configure-WinRM.ps1`.

### 2. Configure Semaphore UI

#### Inventory
Use your existing Windows inventory.

#### Task Survey
Enable a **Survey** in the Task settings to capture the credentials:
*   `target_host`: (Type: String) - The target Hostname or IP address.
*   `target_username`: (Type: String) - The Local Admin username.
*   `target_password`: (Type: Password) - The Local Admin password.

### 3. Ansible Playbook
Create the playbook `ansible/playbooks/list-software.yml`.

```yaml
---
- name: List Installed Software
  hosts: "{{ target_host }}"
  gather_facts: no
  vars:
    ansible_user: "{{ target_username }}"
    ansible_password: "{{ target_password }}"
    ansible_connection: winrm
    ansible_winrm_server_cert_validation: ignore
    ansible_winrm_transport: ntlm

  tasks:
    - name: Gather Installed Software (Registry)
      win_shell: |
        $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty $keys -ErrorAction SilentlyContinue | 
        Select-Object DisplayName, DisplayVersion, Publisher | 
        Where-Object { $_.DisplayName -ne $null } | 
        Sort-Object DisplayName
      register: software_list

    - name: Display Software List
      debug:
        var: software_list.stdout_lines
```

### 4. Template Configuration
1.  **Create Template:** Go to **Task Templates** > **New Template**.
2.  **Settings:**
    *   **Name:** `List Installed Software`
    *   **Playbook Filename:** `ansible/playbooks/list-software.yml`
    *   **Inventory:** Select your Windows inventory.
3.  **Survey:** Ensure the Survey is enabled with the variables defined in Step 2.