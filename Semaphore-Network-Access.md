# How to Make Semaphore UI Accessible Over the Network

By default, Docker maps port 3000 to all network interfaces (`0.0.0.0`). However, Windows Server usually blocks incoming connections to this port by default.

Follow these steps to allow access from other computers on the domain.

## Step 1: Open Port 3000 in Windows Firewall

You need to create an Inbound Rule to allow TCP traffic on port 3000.

### Option A: Using PowerShell (Recommended/Fastest)
Run this command as **Administrator** on the Windows Server hosting Semaphore:

```powershell
New-NetFirewallRule -DisplayName "Semaphore UI" `
    -Direction Inbound `
    -LocalPort 3000 `
    -Protocol TCP `
    -Action Allow `
    -Profile Domain,Private
```

### Option B: Using Windows GUI
1.  Open **Windows Defender Firewall with Advanced Security**.
2.  Click **Inbound Rules** > **New Rule...**
3.  Select **Port** and click Next.
4.  Select **TCP** and enter **3000** in "Specific local ports".
5.  Select **Allow the connection**.
6.  Check **Domain** and **Private** (uncheck Public for security).
7.  Name it "Semaphore UI" and click Finish.

## Step 2: Find Your Server's IP Address

1.  Open Command Prompt or PowerShell.
2.  Run: `ipconfig`
3.  Look for the **IPv4 Address** of your main network adapter (e.g., `10.100.64.20`).

## Step 3: Access from Remote PC

Go to another computer on the network and open the browser:

`http://<YOUR_SERVER_IP>:3000`

*Example:* `http://10.100.64.20:3000`