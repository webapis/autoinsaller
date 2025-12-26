# Semaphore UI and Ansible Docker Setup Guide for Windows Management

This document provides a comprehensive step-by-step guide for setting up a persistent Semaphore UI instance integrated with Ansible using Docker and Docker Compose for managing Windows desktops. This approach containerizes the Semaphore application and its database, and provides a clear structure for managing your Ansible projects with Windows hosts.

## Prerequisites

Ensure the following software is installed and running on your host machine.

### 1. Docker Engine

Docker is the containerization platform that will run the Semaphore and database containers.

*   **For Windows and macOS:** Install **Docker Desktop**. It includes the Docker Engine, the `docker` command-line tool, and Docker Compose.
    *   Download from the official Docker website: https://www.docker.com/products/docker-desktop

*   **For Linux:** Install the Docker Engine and Docker CLI tools by following the official guide for your distribution.
    *   Find instructions here: https://docs.docker.com/engine/install/

*   **Verification:**
    ```bash
    docker --version
    ```

### 2. Docker Compose

Docker Compose is used to define and run multi-container applications from a single `YAML` file.

*   **For Windows and macOS:** Docker Compose is included with Docker Desktop.
*   **For Linux:** You may need to install it separately. Follow the official guide: https://docs.docker.com/compose/install/

*   **Verification:**
    ```bash
    docker-compose --version
    ```

## Directory Structure

To keep all configuration files organized, we will use the following directory structure.

```
/semaphore-setup/
├── docker-compose.yml
├── Dockerfile
├── .env
└── ansible/
    ├── inventory/
    │   └── hosts.ini
    └── playbooks/
        └── install-chrome.yml
```

1.  Create a root directory named `semaphore-setup`.
2.  Inside `semaphore-setup`, create a subdirectory named `ansible`.
3.  Inside `ansible`, create the `inventory` and `playbooks` subdirectories.

---

## Step 1: Prepare Windows Target Machines

Before configuring Semaphore, you must prepare your Windows desktop machines to accept remote management via WinRM with CredSSP authentication.

### Option A: Automated Setup (Recommended)

Use the provided PowerShell scripts to automate the configuration.

1.  Copy `Configure-WinRM.ps1` and `Test-WinRMState.ps1` to the target machine.
2.  Open PowerShell as Administrator.
3.  Run `.\Configure-WinRM.ps1` to apply all necessary settings.
4.  Run `.\Test-WinRMState.ps1` to verify the configuration.

### Option B: Manual Setup

### 1.1 Enable WinRM on Windows

On each Windows desktop you want to manage, run PowerShell as Administrator and execute:

```powershell
# Enable WinRM
Enable-PSRemoting -Force

# Configure WinRM service
winrm quickconfig -force

# Set WinRM to start automatically
Set-Service WinRM -StartupType Automatic

# Start the WinRM service
Start-Service WinRM
```

### 1.2 Configure WinRM Authentication

Enable the necessary authentication methods:

```powershell
# Enable Basic authentication (for initial setup)
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Allow unencrypted traffic (only if using HTTP on port 5985)
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
```

### 1.3 Enable CredSSP Authentication (Critical for Elevation)

CredSSP is required to allow Ansible to perform elevated tasks (like installing software):

```powershell
# Enable CredSSP on the server side
Enable-WSManCredSSP -Role Server -Force

# Configure WinRM for CredSSP
Set-Item -Path "WSMan:\localhost\Service\Auth\CredSSP" -Value $true

# Verify CredSSP is enabled
Get-WSManCredSSP
```

### 1.4 Configure User Permissions

Add the Administrator account to the Remote Management Users group:

```powershell
# Add Administrator to Remote Management Users
net localgroup "Remote Management Users" Administrator /add

# Verify the account was added
net localgroup "Remote Management Users"
```

### 1.5 Configure Registry for Remote Administration

Set the `LocalAccountTokenFilterPolicy` to allow remote administrative access:

```powershell
# Enable remote admin access for local accounts
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name LocalAccountTokenFilterPolicy `
    -Value 1 `
    -PropertyType DWord `
    -Force
```

### 1.6 Configure Windows Firewall

Ensure the WinRM port is open:

```powershell
# Check if WinRM firewall rule is enabled
Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP" | Select-Object Name, Enabled, Direction, Action

# Enable the rule if it's disabled
Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"
```

### 1.7 Restart WinRM Service

After making all changes, restart the WinRM service:

```powershell
Restart-Service WinRM
```

### 1.8 Test WinRM Connectivity

From your Windows machine, test local WinRM connectivity:

```powershell
# Test WinRM locally
Test-WSMan -ComputerName localhost

# Test network connectivity to WinRM port
Test-NetConnection -ComputerName localhost -Port 5985
```

---

## Step 2: Create the Ansible Project Files

Now let's create the Ansible configuration files for Windows management.

### 2.1 Create an Inventory File

Create a file named `semaphore-setup/ansible/inventory/hosts.ini`:

```ini
[windows-desktops]
10.100.64.16

[windows-desktops:vars]
ansible_user=Administrator
ansible_password=1234567890
ansible_connection=winrm
ansible_port=5985
ansible_winrm_transport=credssp
ansible_winrm_server_cert_validation=ignore
```

**Important Notes:**
- Replace `10.100.64.16` with your Windows desktop's IP address
- Replace `1234567890` with your actual Administrator password
- `ansible_winrm_transport=credssp` is critical for elevation support
- For production, use Semaphore's Key Store instead of hardcoded passwords

### 2.2 Create a Chrome Installation Playbook

Create a file named `semaphore-setup/ansible/playbooks/install-chrome.yml`:

```yaml
---
- hosts: windows-desktops
  gather_facts: no
  tasks:
    - name: Create temp directory
      ansible.windows.win_file:
        path: C:\temp
        state: directory

    - name: Download Google Chrome installer
      ansible.windows.win_get_url:
        url: https://dl.google.com/chrome/install/latest/chrome_installer.exe
        dest: C:\temp\chrome_installer.exe

    - name: Install Google Chrome
      ansible.windows.win_package:
        path: C:\temp\chrome_installer.exe
        arguments: /silent /install
        state: present
        product_id: '{8A69D345-D564-463c-AFF1-A69D9E530F96}'

    - name: Clean up installer
      ansible.windows.win_file:
        path: C:\temp\chrome_installer.exe
        state: absent
```

---

## Step 3: Create the Dockerfile

Create a custom Dockerfile to add Windows management capabilities to Semaphore.

Create a file named `Dockerfile` in the `semaphore-setup` root directory:

```dockerfile
FROM semaphoreui/semaphore:latest
USER root
RUN apk add --no-cache build-base libffi-dev openssl-dev python3-dev py3-pip krb5-dev
RUN pip3 install --break-system-packages pywinrm[credssp]
USER 1001
RUN ansible-galaxy collection install ansible.windows
RUN ansible-galaxy collection install community.windows
```

**Key Components:**
- `krb5-dev`: Required for CredSSP authentication support
- `pywinrm[credssp]`: Python library with CredSSP support for Windows management
- `ansible.windows` and `community.windows`: Ansible collections for Windows modules

---

## Step 4: Create the Environment File (`.env`)

This file stores credentials for the database and the initial Semaphore admin user. Create it in the `semaphore-setup` root directory.

Create a file named `.env`:

```
# MariaDB/MySQL Database Settings for Semaphore
MYSQL_ROOT_PASSWORD=a_very_secure_root_password_change_me
MYSQL_DATABASE=semaphore
MYSQL_USER=semaphore
MYSQL_PASSWORD=a_very_secure_password_change_me

# Semaphore Admin User (created on first run)
SEMAPHORE_ADMIN_NAME=admin
SEMAPHORE_ADMIN_EMAIL=admin@localhost
SEMAPHORE_ADMIN=admin
SEMAPHORE_ADMIN_PASSWORD=admin_password_change_me
```

**Action Required:** Change all placeholder passwords to strong, unique values.

---

## Step 5: Create the Docker Compose File (`docker-compose.yml`)

This file defines the `semaphore` application and its `db` dependency. It also maps our local `ansible` project directory into the Semaphore container.

Create a file named `docker-compose.yml` in the `semaphore-setup` root directory:

```yaml
services:
  db:
    image: mariadb:10.6
    container_name: semaphore_db
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
    volumes:
      - semaphore_db_data:/var/lib/mysql
    restart: unless-stopped

  semaphore:
    build: .
    container_name: semaphore_ui
    ports:
      - "3000:3000"
    depends_on:
      - db
    environment:
      - SEMAPHORE_DB_HOST=db
      - SEMAPHORE_DB_PORT=3306
      - SEMAPHORE_DB_USER=${MYSQL_USER}
      - SEMAPHORE_DB_PASS=${MYSQL_PASSWORD}
      - SEMAPHORE_DB_DIALECT=mysql
      - SEMAPHORE_DB=${MYSQL_DATABASE}
      - SEMAPHORE_PLAYBOOK_PATH=/ansible/
      - SEMAPHORE_ADMIN_NAME=${SEMAPHORE_ADMIN_NAME}
      - SEMAPHORE_ADMIN_EMAIL=${SEMAPHORE_ADMIN_EMAIL}
      - SEMAPHORE_ADMIN=${SEMAPHORE_ADMIN}
      - SEMAPHORE_ADMIN_PASSWORD=${SEMAPHORE_ADMIN_PASSWORD}
      - ANSIBLE_HOST_KEY_CHECKING=False
    volumes:
      - semaphore_config_data:/etc/semaphore
      - ./ansible:/ansible
    restart: unless-stopped

volumes:
  semaphore_db_data:
  semaphore_config_data:
```

---

## Step 6: Build and Start the Services

With all files in place, open a terminal in the `semaphore-setup` directory and run:

```bash
# Build the custom Semaphore image with Windows support
docker-compose build --no-cache

# Start the containers
docker-compose up -d

# Verify containers are running
docker ps
```

### 6.1 Verify CredSSP Support

After the containers start, verify that CredSSP support is installed:

```bash
# PowerShell (Windows):
docker exec -it semaphore_ui python3 -c "from winrm.protocol import Protocol; print('CredSSP support available')"

# Bash (Linux/Mac):
docker exec -it semaphore_ui python3 -c "from winrm.protocol import Protocol; print('CredSSP support available')"
```

You should see: `CredSSP support available`

---

## Step 7: Access and Configure Semaphore

### 7.1 Access Web UI

1.  Open a web browser and navigate to `http://localhost:3000`
2.  Login with the admin credentials from your `.env` file

### 7.2 Create a Project

1.  Click the **"+ New Project"** button
2.  Enter a project name (e.g., "Windows Management")
3.  Click **Create**

---

## Step 8: Configure Your First Task

### 8.1 Add Repository

1.  In your project, go to **Repositories** and click **"+ New Repository"**
2.  **Name:** `Windows Ansible Repo`
3.  **URL:** Enter your Git repository URL (e.g., `https://github.com/your-username/your-repo.git`)
4.  **Branch:** `main` (or your default branch)
5.  Click **Save**

### 8.2 Add Key Store (Credentials)

1.  Go to **Key Store** and click **"+ New Key"**
2.  **Name:** `Windows Admin`
3.  **Type:** `Login with password`
4.  **Login (Optional):** `Administrator` (important: no `.\` prefix)
5.  **Password:** Enter your Windows Administrator password
6.  Click **Save**

### 8.3 Add Inventory

1.  Go to **Inventory** and click **"+ New Inventory"**
2.  **Name:** `Windows Desktops`
3.  **Type:** `File`
4.  **Inventory:** Select your repository
5.  **Inventory File Path:** `/ansible/inventory/hosts.ini`
6.  Click **Save**

### 8.4 Create Task Template

1.  Go to **Task Templates** and click **"+ New Template"**
2.  **Name:** `Install Chrome on Windows`
3.  **Playbook Filename:** `ansible/playbooks/install-chrome.yml`
4.  **Inventory:** Select `Windows Desktops`
5.  **Repository:** Select your repository
6.  **Environment:** Leave empty or select default
7.  Click **Save**

### 8.5 Run the Task

1.  Click the **Run** button (play icon) next to your template
2.  Watch the live output as Ansible executes the playbook
3.  Verify Chrome is installed on your Windows desktop

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: "Access is denied, Win32ErrorCode 5"

**Symptoms:** Task fails with authentication or elevation errors

**Solution:**
1. Verify Administrator is in Remote Management Users group (see Step 1.4)
2. Ensure `LocalAccountTokenFilterPolicy` is set (see Step 1.5)
3. Confirm CredSSP is enabled (see Step 1.3)
4. Verify the inventory uses `ansible_winrm_transport=credssp`

#### Issue 2: "basic: the specified credentials were rejected by the server"

**Symptoms:** Cannot connect to Windows host

**Solution:**
1. Verify WinRM is running: `Get-Service WinRM`
2. Check authentication settings (see Step 1.2)
3. Ensure username format is correct (use `Administrator`, not `.\Administrator`)
4. Test WinRM connectivity: `Test-WSMan -ComputerName localhost`

#### Issue 3: Chocolatey Checksum Errors

**Symptoms:** Package installation fails with checksum mismatch

**Solution:**
Use direct download method instead of Chocolatey (see the Chrome installation playbook in Step 2.2). This approach is more reliable and doesn't depend on Chocolatey package maintainers.

#### Issue 4: Port 5985 Not Accessible

**Symptoms:** Connection timeout or refused

**Solution:**
1. Check Windows Firewall (see Step 1.6)
2. Verify WinRM listener: `winrm enumerate winrm/config/listener`
3. Test network connectivity: `Test-NetConnection -ComputerName <IP> -Port 5985`

#### Issue 5: CredSSP Not Working

**Symptoms:** Still getting elevation errors after enabling CredSSP

**Solution:**
1. Verify `pywinrm[credssp]` is installed in Semaphore container:
   ```bash
   docker exec -it semaphore_ui pip3 list | grep pywinrm
   ```
2. Rebuild the Docker image if needed:
   ```bash
   docker-compose down
   docker-compose build --no-cache
   docker-compose up -d
   ```
3. Ensure inventory uses `ansible_winrm_transport=credssp`

---

## Managing the Environment

### Stop the Services
```bash
docker-compose stop
```

### Start the Services
```bash
docker-compose start
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f semaphore
```

### Stop and Remove Containers
```bash
docker-compose down
```

### Complete Reset (WARNING: Deletes all data)
```bash
docker-compose down -v
```

### Rebuild After Changes
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

## Security Best Practices

### For Production Use

1. **Use HTTPS for WinRM (Port 5986):**
   - Generate and install SSL certificates on Windows hosts
   - Update inventory to use port 5986
   - Set `ansible_winrm_server_cert_validation=validate`

2. **Store Credentials Securely:**
   - Use Semaphore's Key Store instead of hardcoding passwords
   - Never commit `.env` file to version control
   - Use strong, unique passwords for all accounts

3. **Network Security:**
   - Use VPN or private network for Semaphore-to-Windows communication
   - Implement firewall rules to restrict WinRM access
   - Consider using Kerberos authentication in domain environments

4. **Minimal Permissions:**
   - Create dedicated service accounts with minimal required permissions
   - Avoid using built-in Administrator account when possible
   - Regularly audit and rotate credentials

5. **Monitoring and Logging:**
   - Enable WinRM logging on Windows hosts
   - Monitor Semaphore task execution logs
   - Set up alerts for failed authentication attempts

---

## Advanced Configuration

### Using Domain Accounts

For domain-joined Windows machines, use domain credentials:

```ini
[windows-desktops:vars]
ansible_user=DOMAIN\username
ansible_password=password
ansible_connection=winrm
ansible_port=5986
ansible_winrm_transport=kerberos
ansible_winrm_server_cert_validation=validate
```

### Multiple Windows Groups

Organize different types of Windows hosts:

```ini
[windows-workstations]
10.100.64.10
10.100.64.11

[windows-servers]
10.100.64.20
10.100.64.21

[windows:children]
windows-workstations
windows-servers

[windows:vars]
ansible_connection=winrm
ansible_port=5985
ansible_winrm_transport=credssp
```

### Using Ansible Vault for Secrets

Encrypt sensitive data:

```bash
# Create encrypted password file
ansible-vault create group_vars/windows.yml

# Add to the file:
ansible_password: your_password_here
ansible_become_password: your_password_here
```

---

## Summary of Critical Configuration Requirements

### Windows Host Requirements
✅ WinRM enabled and running  
✅ Basic authentication enabled (for initial connection)  
✅ CredSSP authentication enabled (for elevation)  
✅ Administrator in "Remote Management Users" group  
✅ LocalAccountTokenFilterPolicy registry key set to 1  
✅ Windows Firewall allows WinRM (port 5985)  
✅ WinRM service restarted after configuration  

### Semaphore Container Requirements
✅ Custom Dockerfile with `pywinrm[credssp]` installed  
✅ krb5-dev package installed  
✅ ansible.windows collection installed  
✅ community.windows collection installed  

### Inventory Requirements
✅ `ansible_connection=winrm`  
✅ `ansible_winrm_transport=credssp` (not basic or ntlm)  
✅ `ansible_port=5985` (or 5986 for HTTPS)  
✅ Username format: `Administrator` (no `.\` prefix)  
✅ `ansible_winrm_server_cert_validation=ignore` (for HTTP)  

---

## Conclusion

You now have a fully functional Semaphore instance configured for Windows management with proper authentication, elevation support, and secure practices. This setup allows you to automate software installation, configuration management, and other administrative tasks across your Windows desktop fleet.

For additional help or advanced configurations, refer to:
- Ansible Windows Guide: https://docs.ansible.com/ansible/latest/os_guide/windows.html
- Semaphore Documentation: https://docs.semaphoreui.com/
- WinRM Configuration: https://docs.microsoft.com/en-us/windows/win32/winrm/