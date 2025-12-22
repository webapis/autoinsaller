# Semaphore UI and Ansible Docker Setup Guide

This document provides a step-by-step guide for setting up a persistent Semaphore UI instance integrated with Ansible using Docker and Docker Compose. This approach containerizes the Semaphore application and its database, and provides a clear structure for managing your Ansible projects.

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
├── .env
└── ansible/
    ├── inventory/
    │   └── hosts.ini
    ├── playbooks/
    │   └── test-playbook.yml
```

1.  Create a root directory named `semaphore-setup`.
2.  Inside `semaphore-setup`, create a subdirectory named `ansible`.
3.  Inside `ansible`, create the `inventory`, `playbooks`, and `ssh_keys` subdirectories.

---

## Step 1: Create the Ansible Project Files

Before launching Semaphore, let's create the Ansible files configured for Windows management.

### 1. Create an Inventory File

For Windows hosts, we typically use WinRM. Create a file named `semaphore-setup/ansible/inventory/hosts.ini`.
Note: Ensure your target Windows PCs have WinRM enabled (see "Preparing Windows Targets" below).

```ini
[windows-desktops]
192.168.1.100

[windows-desktops:vars]
ansible_user=Administrator
ansible_password=YourSecretPassword
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
ansible_port=5985
ansible_winrm_transport=basic
```

**Action:** Replace `server1.example.com` with a target host and `your_remote_user` with the user Ansible should connect as.

### 3. Create a Playbook

Create a file named `semaphore-setup/ansible/playbooks/test-playbook.yml`:

```yaml
---
- hosts: all
  become: yes
  tasks:
    - name: "Ping all hosts"
      ansible.builtin.ping:

    - name: "Print a message"
      ansible.builtin.debug:
        msg: "Hello from Semaphore and Ansible!"
```

---

## Step 2: Create the Environment File (`.env`)

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

**Action Required:** Change the three placeholder passwords to strong, unique values.

---

## Step 3: Create the Docker Compose File (`docker-compose.yml`)

This file defines the `semaphore` application and its `db` dependency. It also maps our local `ansible` project directory into the Semaphore container so it can be used by jobs.

Create a file named `docker-compose.yml` in the `semaphore-setup` root directory:

```yaml
version: '3.7'

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

## Step 4: Start the Services

With all files in place, open a terminal in the `semaphore-setup` directory and run the following command to start the containers.

```bash
docker-compose up -d
```

Docker will build the custom Semaphore image (with Windows support) and create the containers.

## Step 5: Access and Configure Semaphore

1.  **Access Web UI:** Open a web browser and navigate to `http://localhost:3000`.
2.  **Login:** Use the admin credentials you defined in the `.env` file (`SEMAPHORE_ADMIN` and `SEMAPHORE_ADMIN_PASSWORD`).
3.  **Create a Project:** Click the "+ New Project" button to create your first project (e.g., "My Ansible Project").

## Step 6: Set Up Your First Task

Now, let's configure Semaphore to use the Ansible files we created.

1.  **Add Key Store (Credentials):**
    *   In your project, go to **Key Store** and click **"+ New Key"**.
    *   **Name:** `Windows Admin`
    *   **Type:** `Login with password`
    *   **Username:** `Administrator`
    *   **Password:** Enter the password you used in your `hosts.ini` (or leave blank if relying entirely on inventory variables, but a Key is required to save a template).
    *   Click **Save**.

2.  **Add Inventory:**
    *   Go to **Inventory** and click **"+ New Inventory"**.
    *   **Name:** `Test Servers`
    *   **Type:** `File`
    *   **File Path:** Enter the path inside the container: `/ansible/inventory/hosts.ini`.
    *   Click **Save**.

3.  **Add Task Template:**
    *   Go to **Task Templates** and click **"+ New Template"**.
    *   **Playbook:** Select `test-playbook.yml` from the dropdown.
    *   **Inventory:** Select `Test Servers`.
    *   **SSH Key:** Select `Windows Admin`.
    *   Click **Save**.

4.  **Run the Job:**
    *   Click the **Run** button (play icon) next to the template you just created.
    *   You can view the live output as Ansible executes the playbook.

Congratulations! You now have a running Semaphore instance fully configured to execute Ansible playbooks.

## Managing the Environment

*   **To stop the services:**
    ```bash
    docker-compose stop
    ```

*   **To start the services again:**
    ```bash
    docker-compose up -d
    ```

*   **To stop and remove containers (data is preserved in volumes):**
    ```bash
    docker-compose down
    ```

> **Warning:** To completely reset your environment and delete all data (including the database and Semaphore configuration), run `docker-compose down -v`. Use this with caution.