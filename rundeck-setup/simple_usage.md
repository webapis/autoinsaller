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
4.  **Note the Credentials:** You will need the **IP Address**, a **Username**, and the **Password** for an account on that Windows PC to connect from Rundeck.

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
    # Your Windows PC
    your-pc-name:
      nodename: your-pc-name
      hostname: '192.168.1.100' # <-- Replace with your PC's IP Address
      osFamily: windows
      osName: Windows
      username: 'YourWindowsUser' # <-- Replace with your Windows username
      winrm-password-storage-path: 'keys/nodes/your-pc-name/winrm.password'
      winrm-protocol: http
    ```
13. Click **"Save"**.

### Part C: Store the Node's Password

For security, you must store the Windows password in Rundeck's Key Storage.

1.  Click the **Gear Icon** (System Menu) in the top-right and select **"Key Storage"**.
2.  Click **"+ Add or Upload a Key"**.
3.  For "Key Type", select **"Password"**.
4.  In the "Enter Text" box, enter the password for the Windows user account.
5.  For "Storage Path", enter **exactly** what you used in the `nodes.yml` file: `keys/nodes/your-pc-name/winrm.password`.
6.  For "Name", type `winrm.password`.
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