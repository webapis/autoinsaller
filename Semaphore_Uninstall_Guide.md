# Semaphore UI Windows Software Uninstallation Guide

## Overview
This guide documents the setup for uninstalling applications from domain-joined Windows desktops using Semaphore UI.

**Scenario:**
*   **Objective:** Uninstall a specific application (identified by its Product ID/GUID) from the target desktop.
*   **Authentication:** IT Admin provides Local Administrator credentials at runtime via Semaphore Survey.

## Implementation Steps

### 1. Prepare Target Desktops
Ensure WinRM is enabled and listening on the target desktops.
*   **Audit:** Run `Test-WinRMState.ps1`.
*   **Configure:** Run `Configure-WinRM.ps1`.

### 2. Find the Product ID (GUID)
To uninstall software reliably via Ansible, you need the Product ID (GUID). You can find this on a machine where the software is installed by running this PowerShell command:

```powershell
Get-WmiObject -Class Win32_Product | Select-Object Name, IdentifyingNumber
```
*Example Output:* `{23170F69-40C1-2702-1900-000001000000}`

### 3. Configure Semaphore UI

#### Inventory
Use your existing Windows inventory.

#### Task Survey
Enable a **Survey** in the Task settings to capture the credentials and the Product ID:
*   `target_host`: (Type: String) - The target Hostname or IP address.
*   `target_username`: (Type: String) - The Local Admin username.
*   `target_password`: (Type: Password) - The Local Admin password.
*   `product_id`: (Type: String) - The GUID of the application to uninstall (e.g., `{1234...}`).

### 4. Ansible Playbook
Create the playbook `ansible/playbooks/uninstall-software.yml`.

```yaml
---
- name: Uninstall Application
  hosts: "{{ target_host }}"
  gather_facts: no
  vars:
    ansible_user: "{{ target_username }}"
    ansible_password: "{{ target_password }}"
    ansible_connection: winrm
    ansible_winrm_server_cert_validation: ignore
    ansible_winrm_transport: ntlm

  tasks:
    - name: Uninstall Application via Product ID
      win_package:
        product_id: "{{ product_id }}"
        state: absent
        arguments: /quiet /norestart
      register: uninstall_result

    - name: Debug Output
      debug:
        var: uninstall_result
```

### 5. Template Configuration
1.  **Create Template:** Go to **Task Templates** > **New Template**.
2.  **Settings:**
    *   **Name:** `Uninstall Software`
    *   **Playbook Filename:** `ansible/playbooks/uninstall-software.yml`
    *   **Inventory:** Select your Windows inventory.
3.  **Survey:** Ensure the Survey is enabled with the variables defined in Step 3.