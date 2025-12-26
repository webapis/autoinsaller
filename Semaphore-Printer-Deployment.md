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

### 2.2. Service Account
Create a dedicated Domain Service Account (e.g., `DOMAIN\svc_semaphore`).
*   **Permissions**:
    *   Must be a member of the local **Administrators** group on the **Target PCs**.
    *   Must have **Read** access to the Print Server shares.

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

## 4. Configuration Steps

### Step 1: Prepare Target PCs
Run the `Configure-WinRM.ps1` script on all target workstations. This script handles:
*   Enabling the WinRM service.
*   Opening Firewall ports.
*   Enabling CredSSP (Server role) if needed.
*   Setting `LocalAccountTokenFilterPolicy` (crucial for local admin access).

You can verify the state using `Test-WinRMState.ps1`.

### Step 2: Configure Semaphore UI
1.  **Key Store**: Create a "Login with Password" key.
    *   Username: `DOMAIN\svc_semaphore`
    *   Password: `YourServiceAccountPassword`
2.  **Inventory**: Create a static inventory or link to a git repository file.
    ```ini
    [workstations]
    pc-01.domain.local
    pc-02.domain.local

    [workstations:vars]
    ansible_user=svc_semaphore@DOMAIN.LOCAL
    ansible_password=YourPassword
    ansible_connection=winrm
    ansible_winrm_transport=ntlm   # or kerberos/credssp
    ansible_winrm_server_cert_validation=ignore
    ```

## 5. Implementation Scenarios

### Scenario A: Install TCP/IP Printer (Best Practice)
This method installs the printer locally on the machine pointing to the printer's IP. It avoids the "Double Hop" issue because it doesn't rely on the Print Server for the queue, only potentially for the driver.

**Ansible Playbook Example:**

```yaml
---
- name: Deploy Printer via TCP/IP
  hosts: workstations
  tasks:
    - name: Ensure Printer Driver is Installed
      win_printer_driver:
        name: "HP Universal Printing PCL 6"
        # If driver is not built-in, you must copy the INF file to the target first
        # or point to a path accessible by the machine account.

    - name: Create TCP/IP Printer Port
      win_printer_port:
        name: "192.168.1.50"
        ip: "192.168.1.50"

    - name: Add Printer
      win_printer:
        name: "Office-Printer-01"
        driver_name: "HP Universal Printing PCL 6"
        port_name: "192.168.1.50"
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