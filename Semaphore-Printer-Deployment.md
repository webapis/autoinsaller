# Deploying Printers to Remote Windows PCs using Semaphore UI

This document outlines the procedures, prerequisites, and scenarios for installing printers from a Print Server onto remote Windows Desktop PCs using **Semaphore UI**.

## 1. Architecture Overview

*   **Controller**: Semaphore UI (running in Docker on Windows Server).
*   **Source**: Print Server (Windows Server hosting shared printers and drivers).
*   **Targets**: Remote Windows Desktop PCs (Domain Joined).
*   **Protocol**: WinRM (Windows Remote Management) via Ansible.

## 2. Prerequisites

### 2.1. Network & Domain
*   **Standard Setup**: All machines (Semaphore Host, Print Server, Target PCs) must be joined to the same **Active Directory Domain**.
*   **Non-Domain Exception**: See *Scenario D* for Workgroup/Non-Domain PCs.
*   **DNS Resolution** must be functioning correctly between all parties.
*   **Firewall Ports**:
    *   **TCP 5985** (WinRM HTTP) or **TCP 5986** (WinRM HTTPS) must be open on Target PCs inbound from the Semaphore Server.
    *   **TCP 445** (SMB) and RPC ports must be open between Target PCs and the Print Server (for driver downloads).

### 2.2. Accounts & Credentials
You can use either a dedicated service account or a combination of Local Admin and Standard Domain credentials.

**Option A: Domain Service Account (Best Practice)**
*   A single domain account (e.g., `DOMAIN\svc_semaphore`) that is a Local Admin on targets and has Read access to the Print Server.

**Option B: Hybrid (Local Admin + Domain User)**
*   **Connection Account**: The **Local Administrator** account for the Target PCs (used to run the installation commands).
*   **Resource Account**: A **Standard Domain User** (e.g., `caliksoa\u13589`) to authenticate to the Print Server share to download drivers (bypassing the Double Hop).

### 2.3. Semaphore UI (Docker)
*   The Docker container must have network access to the domain network.
*   The Ansible environment inside Semaphore must have the `pywinrm` library installed to communicate with Windows hosts.

### 2.4. Target PCs Configuration
WinRM must be enabled and configured to allow remote management.

> **Note**: Use the provided `Configure-WinRM.ps1` script on target PCs to automate this setup.

## 3. Authentication Requirements

### 3.1. WinRM Authentication
When Semaphore connects to Target PCs, it uses WinRM.
*   **Kerberos**: The most secure method for domain environments. Requires correct DNS and time synchronization.
*   **Basic**: Less secure, transmits credentials (encrypted over HTTPs or if `AllowUnencrypted` is set). Often easier to set up for initial testing.
*   **CredSSP**: Required if you need to pass credentials *through* the Target PC to a third server (The "Double Hop" issue).

### 3.2. The "Double Hop" Issue
This is the most critical challenge in this setup.
1.  Semaphore authenticates to Target PC (Hop 1).
2.  Target PC tries to contact Print Server to pull drivers (Hop 2).

By default, Windows **does not** allow the credentials from Hop 1 to be passed to Hop 2.

**Solutions:**
1.  **Use TCP/IP Port Printers (Recommended)**: The Target PC talks directly to the Printer IP, or pulls drivers from a local source/public share that doesn't require auth.
2.  **CredSSP**: Enable CredSSP on the Client (Semaphore) and Server (Target PC). *Note: This has security implications.*
3.  **Kerberos Delegation**: Configure the Target PC computer objects in AD to be trusted for delegation.
4.  **Explicit Authentication**: Provide specific Domain Credentials inside the playbook (e.g., `win_mapped_drive`) to create a new session. This is the method used in **Scenario B**.

## 4. Configuration Steps

### Step 1: Prepare Target PCs
Run the `Configure-WinRM.ps1` script on all target workstations. This script handles:
*   Enabling the WinRM service.
*   Opening Firewall ports.
*   Enabling CredSSP (Server role) if needed.
*   Setting `LocalAccountTokenFilterPolicy` (crucial for local admin access).

> **Important**: Do **not** run these scripts on the **Print Server**. The Print Server only requires standard "File and Printer Sharing" ports (TCP 445/RPC) to be open, which is typically the default for a server in this role.

You can verify the state using `Test-WinRMState.ps1`.

### Step 2: Configure Semaphore UI

#### For Option A (Domain Service Account)
1.  **Key Store**: Create a key for `DOMAIN\svc_semaphore`.
2.  **Inventory**: Use this key for the connection.

#### For Option B (Hybrid - Your Setup)
1.  **Key Store (Resource Account)**: Create a "Login with Password" key for your Standard Domain User (e.g., `caliksoa\u13589`) to access the share.
2.  **Task Survey (Connection Account)**: Enable the **Survey** in your Task Template to capture the target details at runtime.
    *   **Variable**: `target_host`
        *   **Title**: Target IP Address or Hostname
        *   **Type**: String
        *   **Required**: Yes
    *   **Variable**: `target_username`
        *   **Title**: Local Admin Username
        *   **Type**: String
        *   **Required**: Yes
    *   **Variable**: `target_password`
        *   **Title**: Local Admin Password
        *   **Type**: Password
        *   **Required**: Yes

3.  **Playbook Structure (Dynamic Inventory)**:
    Since the target IP is provided at runtime, use the `add_host` module in your playbook to register it dynamically.

    ```yaml
    - name: Register Target Host
      hosts: localhost
      gather_facts: no
      tasks:
        - name: Add Dynamic Host
          add_host:
            name: "{{ target_host }}"
            groups: deployment_targets
            ansible_user: "{{ target_username }}"
            ansible_password: "{{ target_password }}"
            ansible_connection: winrm
            ansible_winrm_transport: ntlm
            ansible_winrm_server_cert_validation: ignore

    - name: Deploy Printer
      hosts: deployment_targets
      gather_facts: yes
      vars:
        # Resource Account (for accessing Print Server)
        share_user: "caliksoa\\u13589"
        share_password: "YourDomainPassword" # Ideally use Ansible Vault or Semaphore Environment
      tasks:
        # ... tasks follow ...
    ```

## 5. Implementation Scenarios

### Scenario B: Shared Network Printer (Global/Per-Machine)
**Goal:** Map `\\HVTRM-WS-PRNT\PrinterName` on the target PC so it appears for **all users**.

**The Challenge:**
Standard printer mapping is "Per-User". If Ansible runs as Admin, the user won't see the printer.
**The Solution:**
We use the `rundll32 printui.dll /ga` command (Global Add) to create a machine-wide connection to the print server.

**Playbook for Shared Printers:**

```yaml
---
- name: Deploy Shared Printers (Global)
  hosts: deployment_targets
  gather_facts: no
  vars:
    # Configuration
    print_server: "HVTRM-WS-PRNT.caliksoa.local"
    printer_1: "MRK-K0-BT-Konica-224-Color"
    printer_2: "MRK-K1-Vize-Konica-C301-Color"
    
    # Credentials (for authenticating to the Print Server share)
    share_user: "caliksoa\\u13589"
    share_password: "{{ share_password }}" 

  tasks:
    - name: Authenticate to Print Server
      # We map the 'print$' share to establish a valid session with Domain Credentials
      ansible.windows.win_mapped_drive:
        letter: P
        path: "\\\\{{ print_server }}\\print$"
        username: "{{ share_user }}"
        password: "{{ share_password }}"
        state: present

    # FIX: Disable "Point and Print" restrictions to prevent driver install prompts (which cause hangs)
    - name: Allow Point and Print (RestrictDriverInstallationToAdministrators = 0)
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint
        name: RestrictDriverInstallationToAdministrators
        data: 0
        type: dword
        state: present

    - name: Disable Point and Print Warnings (UpdatePromptSettings = 2)
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint
        name: UpdatePromptSettings
        data: 2
        type: dword
        state: present

    - name: Add Printer 1 (Global Machine Connection)
      win_shell: |
        rundll32 printui.dll,PrintUIEntry /ga /n"\\{{ print_server }}\{{ printer_1 }}" /q
      # /ga = Global Add (per machine)
      # /n = UNC Path
      register: p1_out
      failed_when: p1_out.rc != 0 and p1_out.rc != 0x00000057 # Ignore 'already exists' errors

    - name: Add Printer 2 (Global Machine Connection)
      win_shell: |
        rundll32 printui.dll,PrintUIEntry /ga /n"\\{{ print_server }}\{{ printer_2 }}" /q
      register: p2_out
      failed_when: p2_out.rc != 0 and p2_out.rc != 0x00000057

    - name: Restart Spooler
      # Required for Global connections to appear in the UI immediately
      win_service:
        name: Spooler
        state: restarted

    - name: Unmap Auth Drive
      ansible.windows.win_mapped_drive:
        letter: P
        state: absent

    # Security Cleanup: Revert Point and Print restrictions to defaults
    - name: Revert Point and Print (RestrictDriverInstallationToAdministrators)
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint
        name: RestrictDriverInstallationToAdministrators
        state: absent

    - name: Revert Point and Print Warnings (UpdatePromptSettings)
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint
        name: UpdatePromptSettings
        state: absent
```

### Scenario B: Map Shared Printer (Requires CredSSP)
This maps `\\PrintServer\SharedPrinter`. This is usually a **per-user** setting. Running this via Semaphore (which runs as the service account) will install the printer for the *Service Account*, not the logged-in user, unless you use specific "Global" flags which are deprecated or unreliable in Windows 10/11.

**Warning**: This approach is generally **not recommended** for deployment via Semaphore/Ansible for end-users. It is better handled via Group Policy (GPO).

If you must proceed (e.g., for a Kiosk machine or Lab):

1.  **Enable CredSSP** in Semaphore Inventory:
    `ansible_winrm_transport=credssp`
2.  **Playbook**:
    ```yaml
    - name: Add Shared Printer
      win_printer:
        name: "\\\\PrintServer\\SharedPrinterName"
        connection_enabled: true
    ```

### Scenario C: Point and Print (Driver Pre-load)
To allow users to add printers easily later (or via GPO) without Admin prompts:

1.  Use Semaphore to copy the Driver files to the Target PC.
2.  Use `pnputil.exe` to add the driver to the Driver Store.
3.  Use `Add-PrinterDriver` to install it.

```yaml
- name: Pre-load Printer Drivers
  hosts: workstations
  tasks:
    - name: Copy Driver Files
      win_copy:
        src: "\\\\PrintServer\\Drivers\\HP_Universal\\"
        dest: "C:\\Temp\\Drivers\\HP\\"
        remote_src: yes # Requires CredSSP if pulling from remote share

    - name: Install Driver to Store
      win_shell: pnputil.exe /add-driver "C:\Temp\Drivers\HP\*.inf" /install
```

## 6. Best Practices Checklist

| Requirement | Recommendation |
| :--- | :--- |
| **Protocol** | Use **WinRM over HTTP (5985)** inside a secure LAN. Use HTTPS (5986) if crossing segments. |
| **Authentication** | Use **Kerberos** where possible. Use **CredSSP** only if accessing network shares from the script is unavoidable. |
| **Drivers** | Pre-install drivers using `pnputil` or `win_printer_driver` to avoid prompt issues. |
| **Deployment Type** | Prefer **TCP/IP Port** printers (Machine-wide) over Shared Printers (User-specific) for automated deployment. |
| **GPO** | Use Group Policy Preferences for mapping Shared Printers to specific users; use Semaphore for installing the underlying Drivers and System configurations. |

## 7. Troubleshooting

**Error: "Access is Denied" during WinRM connection**
*   Check if the Service Account is in the Local Administrators group.
*   Verify `LocalAccountTokenFilterPolicy` is set to 1 (See `Configure-WinRM.ps1`).

**Error: "Access Denied" when accessing \\PrintServer**
*   This is the Double Hop issue.
*   Switch `ansible_winrm_transport` to `credssp`.
*   Ensure `Enable-WSManCredSSP -Role Server` was run on the Target PC.

**Error: Printer installs but user cannot see it**
*   You likely installed it as the Service Account.
*   Use the TCP/IP Port method (Scenario A) which creates a machine-wide printer queue.