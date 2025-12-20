# Rundeck Simple Usage Guide

This guide provides a walkthrough of the basic steps to get started with your new Rundeck instance, including creating a project and running your first job.

## 1. Logging In

First, access the Rundeck web interface and log in.

1.  **Open your browser** and navigate to: `http://localhost:4440`
2.  **Use the default credentials** to log in:
    *   **Username:** `admin`
    *   **Password:** `admin`
3.  **Change your password:** You will be prompted to set a new, secure password for the `admin` account. This is a mandatory security step.

---

## 2. Creating Your First Project

Projects are how Rundeck organizes jobs, nodes, and activity.

1.  Click the **Gear Icon** (System Menu) in the top-right corner.
2.  Select **Projects**.
3.  Click the **"+ New Project"** button.
4.  Enter a **Project Name**, for example: `My First Project`.
5.  You can leave the other settings as default for now.
6.  Scroll to the bottom and click the green **"Create"** button.

You will be taken to the dashboard for your new project.

---

## 3. Creating a "Hello World" Job

Jobs are the core of Rundeck; they define a workflow of steps to be executed.

1.  In your project's dashboard, click on the **"Jobs"** link in the left-hand navigation menu.
2.  Click the **"+ Create a new Job"** button.
3.  In the "Job Name" field, enter: `Hello World`.
4.  Scroll down to the **"Workflow"** section.
5.  Click the **"+ Add a step"** button.
6.  Under the "Script" section, click the **"Script"** option.
7.  A content box will appear. Enter the following simple command:
    ```bash
    echo "Hello from your first Rundeck job!"
    ```
8.  Scroll to the bottom and click the green **"Create"** button to save the job.

---

## 4. Running the Job and Viewing Output

1.  After creating the job, you will be on its definition page. Click the green **"Run Job Now"** button in the top-right corner.
2.  The page will automatically switch to the log output for the running job.
3.  You should see the execution complete successfully. The output will show the "Hello from your first Rundeck job!" message.

Congratulations! You have successfully set up Rundeck, created a project, and executed your first job.

---

*For more advanced topics, such as adding remote nodes to run commands on, please refer to the official Rundeck documentation.*

---

## 5. Adding a Remote Windows Node and Installing Software

This section explains how to configure a remote Windows PC to be managed by Rundeck and how to create a job to install software on it.

### Part A: Prepare the Remote Windows PC

Rundeck communicates with Windows nodes using **WinRM** (Windows Remote Management). You must enable and configure it on the target PC.

1.  **Copy the Audit Script:** Copy the `Test-WinRMState.ps1` script to the remote Windows PC you want to manage.
2.  **Run as Administrator:** Open a PowerShell terminal **as an Administrator** on the remote PC.
3.  **Execute the Script:** Run the script. It will audit your WinRM configuration and, if it finds any issues, it will automatically enable and configure WinRM for you.
    ```powershell
    .\Test-WinRMState.ps1
    ```
4.  **Configure WinRM Security:** By default, WinRM does not allow the connection type Rundeck uses for HTTP. Run these commands in the same Administrator PowerShell window to enable it:
    ```powershell
    # Allow the WinRM service to use Basic authentication
    winrm set winrm/config/service/auth '@{Basic="true"}'
    # Allow the WinRM service to accept unencrypted connections
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    # Restart the service to apply changes
    Restart-Service WinRM
    ```
5.  **Note the Credentials:** You will need the **IP Address**, a **Username**, and the **Password** for an account on that Windows PC to connect from Rundeck.

### Part B: Add the Windows Node to Rundeck

Next, tell your Rundeck project about the new machine.

1.  In your Rundeck project, click **"Project Settings"** in the bottom-left menu.
2.  Under "Edit Configuration", click on **"Nodes"**.
3.  Click **"+ Add a new Node Source"**.
4.  Select **"File"** from the list.
5.  For the "Format", choose **`resourceyaml`**.
6.  For the "Path", enter `/home/rundeck/projects/${project.name}/etc/nodes.yml`. This tells Rundeck to look for a file named `nodes.yml` in your project's configuration directory.
7.  Check the box for **"Generate"** to create an empty file.
8.  Check the box for **"Include Server Node"**.
9.  Click **"Save"** to create the Node Source.
10. Click **"Save"** again at the bottom of the Nodes page.
11. Now, go back to "Project Settings" -> "Nodes" and click the **"Modify"** button next to the `nodes.yml` source you just created.
12. A text editor will appear. Add the configuration for your Windows node below the default `rundeck-server` entry. Replace the placeholder values with your PC's actual details.
    ```yaml
    # The file will already contain an entry for the Rundeck server itself.
    # It will look something like this (DO NOT DELETE IT):
    8f8590dc71c8:
      nodename: 8f8590dc71c8
      hostname: 8f8590dc71c8
      osFamily: unix
      osArch: amd64
      description: Rundeck server node
      osName: Linux
      username: rundeck
      tags: ''
    
    # Add your Windows PC configuration below the server entry:
    TCHMD1017:
      nodename: TCHMD1017.caliksoa.local
      hostname: 'TCHMD1017.caliksoa.local' # <-- IMPORTANT: Replace with your PC's IP Address or a resolvable hostname
      osFamily: windows
      osName: Windows
      username: 'Administrator' # <-- IMPORTANT: Replace with your Windows username
      # For security, the password is not stored here.
      # It is read from Key Storage at the path below.
      winrm-password-storage-path: 'keys/nodes/TCHMD1017/winrm.password' # Standard path format
      # These attributes tell Rundeck HOW to connect to the node.
      winrm-protocol: http
      node-executor: winrm
      file-copier: winrm
    ```
13. Click **"Save"**.

### Part C: Store the Node's Password

For security, you must store the Windows password in Rundeck's Key Storage.

1.  Click the **Gear Icon** (System Menu) in the top-right and select **"Key Storage"**.
2.  Click **"+ Add or Upload a Key"**.
3.  For "Key Type", select **"Password"**.
4.  In the "Enter Text" box, enter the password for the Windows user account.
5.  For "Storage Path", enter **exactly** what you used in the `nodes.yml` file: `keys/nodes/your-pc-name/winrm.password`.
    *   **Important:** Replace `your-pc-name` with the actual node name you used in `nodes.yml` (e.g., `TCHMD1017`). The final path should look like `keys/nodes/TCHMD1017/winrm.password`. This is a standard and recommended path.
    *   This path **must** match the `winrm-password-storage-path` value in your node definition.
6.  For "Name", type a descriptive name like `TCHMD1017-winrm-password`.
7.  Click **"Save"**.

### Part D: Create and Run the Installation Job

Finally, create a job to install an application (e.g., 7-Zip) on the new node.

1.  Go to **"Jobs"** and click **"+ Create a new Job"**.
2.  Name the job, for example, `Install 7-Zip on Windows`.
3.  Go to the **"Nodes"** section of the job editor.
4.  In the "Node Filter" box, type the name of your node: `your-pc-name`. A "1 Matched Node" tag should appear.
5.  Go to the **"Workflow"** section and **"+ Add a step"**.
6.  Choose the **"Script"** step type.
7.  Enter the PowerShell command to download and silently install the software. This example uses `winget`.
    ```powershell
    # Use winget to install 7-Zip silently
    winget install --id=7zip.7zip -e --accept-source-agreements --accept-package-agreements
    ```
8.  Click **"Create"** to save the job.
9.  Click **"Run Job Now"**. The job will execute on your remote Windows PC and install the application.

---

### Part E: Troubleshooting Connection Issues

If your job fails with an error like "The Execution Log could not be found," it usually indicates a connection problem.

1.  **Test Connectivity from the Container:**
    Open a shell into the Rundeck container (`docker exec -it rundeck bash`) and run `curl -v http://your-pc-hostname:5985`.

2.  **Interpreting `curl` Output:**
    *   **`Connection refused`**: This is the most common error. It means the WinRM service on the Windows PC is not running or not listening. To fix this, re-run the `Test-WinRMState.ps1` script on the Windows PC as an Administrator. It will detect the issue and re-configure the service.
    *   **`Connection timed out`**: This means a firewall is blocking the connection. Ensure the firewall on the Windows PC (and any network firewalls between the Docker host and the PC) allows inbound traffic on TCP port 5985.
    *   **`401 Unauthorized`**: This is a good sign! It means you have connectivity, but there is an issue with the username or the password stored in Rundeck's Key Storage. Double-check the credentials and the Key Storage path in your `nodes.yml` file.
    *   **`404 Not Found`**: This also confirms connectivity. It means the WinRM service is running but is not configured to allow the connection type Rundeck is using. Run the security configuration commands from Part A, Step 4 on the Windows PC to fix this.

3.  **Verify User Permissions on the Windows PC:**
    If you receive a `401 Unauthorized` error or the job fails without a log, the user account may lack permissions. Run these commands in PowerShell on the target Windows PC to verify:
    ```powershell
    # Check if the user exists and is enabled (replace 'YourUsername' with the actual username)
    Get-LocalUser -Name "YourUsername"

    # Check if the user is a member of the local Administrators group
    Get-LocalGroupMember -Group "Administrators" | Where-Object { $_.Name -like "*\YourUsername" }
    ```
    If the user is not enabled or not a member of the Administrators group, you must add them for WinRM to work.
---

## 6. Managing Your Rundeck Environment

It is critical to use the correct Docker commands to stop and start your Rundeck services to avoid losing your data (projects, jobs, keys, etc.).

## 6. Managing Your Rundeck Environment

It is critical to use the correct Docker commands to stop and start your Rundeck services to avoid losing your data (projects, jobs, keys, etc.).

### To Safely Stop Your Rundeck Services:

Use this command from your `rundeck-setup` directory. This stops the containers but preserves all your data volumes.

```bash
docker-compose stop
```

### To Start Your Rundeck Services:

This command will start the containers and re-attach them to your existing data volumes.

```bash
docker-compose up -d
```

**IMPORTANT:** Avoid using the `docker-compose down -v` command for routine restarts. The `-v` flag **deletes all data volumes**, which will erase your projects, job history, and stored passwords. Only use `docker-compose down -v` if you intend to completely reset your Rundeck environment to a fresh installation.

---

## 7. (Advanced) Configuring WinRM for Secure HTTPS Connections

For production environments, it is highly recommended to use encrypted HTTPS connections instead of HTTP. This requires creating an SSL certificate on the Windows node and updating the Rundeck node definition.

### Part A: Configure the Windows Node for HTTPS

1.  **Open PowerShell as an Administrator** on the target Windows PC.
2.  **Create a Self-Signed Certificate:** Run the following command. **Important:** Replace `your-pc-hostname.local` with the exact hostname Rundeck will use to connect.
    ```powershell
    $cert = New-SelfSignedCertificate -DnsName "your-pc-hostname.local" -CertStoreLocation "cert:\LocalMachine\My" -KeySpec KeyExchange
    ```
3.  **Create the HTTPS WinRM Listener:** This command uses the new certificate to create a listener on the default HTTPS port `5986`.
    ```powershell
    New-WSManInstance -ResourceURI 'winrm/config/Listener' -SelectorSet @{Address='*';Transport='HTTPS'} -ValueSet @{CertificateThumbprint=$cert.Thumbprint}
    ```
4.  **Disable Insecure Protocols (Recommended):** Once HTTPS is confirmed to be working, you can disable the less secure HTTP options.
    ```powershell
    winrm set winrm/config/service '@{AllowUnencrypted="false"}'
    winrm set winrm/config/service/auth '@{Basic="false"}'
    Restart-Service WinRM
    ```

### Part B: Update the Rundeck Node Definition

1.  In your Rundeck project, go to **Project Settings -> Nodes** and modify your `nodes.yml` file.
2.  Update the configuration for your Windows node to use the `https` protocol and trust the self-signed certificate.

    ```yaml
    # ... (server node definition)

    TCHMD1017:
      nodename: TCHMD1017.caliksoa.local
      hostname: 'TCHMD1017.caliksoa.local'
      osFamily: windows
      osName: Windows
      username: 'Administrator'
      winrm-password-storage-path: 'keys/nodes/TCHMD1017/winrm.password'
      # --- HTTPS Connection Settings ---
      winrm-protocol: https
      # The following two lines are required for self-signed certificates
      winrm-cert-trust: all
      winrm-hostname-verifier: allowAll
      # --- Executor Settings ---
      node-executor: winrm
      file-copier: winrm
    ```
3.  Save the file. Rundeck will now communicate with your Windows node over an encrypted HTTPS connection.