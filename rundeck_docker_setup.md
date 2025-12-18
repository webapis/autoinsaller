# Rundeck Docker Setup Plan

This document outlines the plan for setting up a persistent and reliable Rundeck instance using Docker and Docker Compose. This method is recommended as it separates the application from its database and simplifies management.

## Prerequisites

Before starting, ensure the following software is installed and running on your host machine.

### 1. Docker Engine

Docker is the containerization platform that will run the Rundeck and database containers.

*   **For Windows and macOS:**
    The recommended method is to install **Docker Desktop**. It includes the Docker Engine, the `docker` command-line tool, and Docker Compose.
    *   Download from the official Docker website: https://www.docker.com/products/docker-desktop
    *   Follow the installation instructions for your operating system.

*   **For Linux:**
    You will need to install the Docker Engine and Docker CLI tools manually. Follow the official guide for your specific Linux distribution (e.g., Ubuntu, CentOS, Debian).
    *   Find instructions here: https://docs.docker.com/engine/install/

*   **Verification:**
    After installation, open a terminal or command prompt and run the following command to verify that Docker is installed correctly:
    ```bash
    docker --version
    ```
    You should see an output like `Docker version 20.10.17, build 100c701`.

### 2. Docker Compose

Docker Compose is the tool used to define and run multi-container applications from a single `YAML` file.

*   **For Windows and macOS:**
    Docker Compose is **included by default** with the Docker Desktop installation. No separate installation is needed.

*   **For Linux:**
    If you installed Docker Engine manually, you might also need to install Docker Compose separately. Follow the official guide for Linux:
    *   Find instructions here: https://docs.docker.com/compose/install/

*   **Verification:**
    To verify the installation, run the following command:
    ```bash
    docker-compose --version
    ```
    You should see an output like `Docker Compose version v2.10.2`.

## Directory Structure

We will use a simple directory structure to keep our configuration files organized.

```
/rundeck-setup/
├── docker-compose.yml
└── .env
```

Create a directory named `rundeck-setup` and navigate into it. All subsequent files will be created here.

---

## Step 1: Create the Environment File (`.env`)

First, we will create an environment file to store sensitive information like database credentials. This is a security best practice that keeps secrets out of your main configuration file.

Create a file named `.env`:

```
# PostgreSQL Database Settings for Rundeck
# These values are used by both the 'db' and 'rundeck' services in docker-compose.yml

POSTGRES_DB=rundeck
POSTGRES_USER=rundeck
POSTGRES_PASSWORD=a_very_secure_password_change_me
```

**Action Required:** Change `a_very_secure_password_change_me` to a strong, unique password.

---

## Step 2: Create the Docker Compose File (`docker-compose.yml`)

Next, create the `docker-compose.yml` file. This file defines the services, networking, and volumes needed to run Rundeck. It will define two services: `rundeck` (the application) and `db` (the PostgreSQL database).

Create a file named `docker-compose.yml`:

```yaml
version: '3.7'

services:
  rundeck:
    image: rundeck/rundeck:latest
    container_name: rundeck
    ports:
      - "4440:4440"
    environment:
      - RUNDECK_GRAILS_URL=http://localhost:4440
      - RUNDECK_DATABASE_DRIVER=org.postgresql.Driver
      - RUNDECK_DATABASE_URL=jdbc:postgresql://db:5432/${POSTGRES_DB}
      - RUNDECK_DATABASE_USERNAME=${POSTGRES_USER}
      - RUNDECK_DATABASE_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - rundeck_data:/home/rundeck/server/data
      - rundeck_logs:/home/rundeck/var/logs
      - rundeck_plugins:/home/rundeck/libext
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:13
    container_name: postgres_db
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  rundeck_data:
  rundeck_logs:
  rundeck_plugins:
  postgres_data:
```

---

## Step 3: Start the Services

With both files in place, open a terminal in the `rundeck-setup` directory and run the following command to start the containers in the background:

```bash
docker-compose up -d
```

Docker will download the necessary images and create the containers, volumes, and network.

## Step 4: Verify and Access Rundeck

1.  **Check Logs:** To ensure everything is starting correctly, you can view the logs for the Rundeck container:
    ```bash
    docker-compose logs -f rundeck
    ```
    Wait for a message indicating `Grails application running at http://localhost:4440`. This may take a minute or two on the first start.

2.  **Access Web UI:** Open a web browser and navigate to `http://localhost:4440`.

3.  **Login:** The default credentials are:
    *   **Username:** `admin`
    *   **Password:** `admin`

You will be required to change the default password immediately after your first login.

## Step 5: Managing the Environment

*   **To stop the services:**
    ```bash
    docker-compose down
    ```
    *(Your data will be preserved in the Docker volumes.)*

*   **To restart the services:**
    ```bash
    docker-compose restart
    ```