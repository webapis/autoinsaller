# Semaphore UI LDAP/Active Directory Integration Guide

## Overview
This document outlines the steps required to integrate an LDAP or Active Directory (AD) provider with Semaphore UI. This allows users to log in to Semaphore using their domain credentials.

## Prerequisites
Before proceeding, ensure you have the following information from your Active Directory environment:

1.  **LDAP Host**: The IP address or FQDN of the Domain Controller (e.g., `dc01.example.com`).
2.  **Port**: Typically `389` for LDAP or `636` for LDAPS.
3.  **Bind DN**: The Distinguished Name of a service account used to query AD (e.g., `CN=Semaphore,OU=ServiceAccounts,DC=example,DC=com`).
4.  **Bind Password**: The password for the Bind DN account.
5.  **Search Base (DN Search)**: The root Distinguished Name where user searches should begin (e.g., `OU=Users,DC=example,DC=com`).
6.  **Search Filter**: The LDAP filter used to map the login username to an AD attribute (usually `sAMAccountName` or `mail`).

## Configuration Steps

### 1. Locate Configuration File
Access the server hosting Semaphore UI. The configuration is typically stored in `config.json`.
*   **Default Location**: `/etc/semaphore/config.json` (may vary based on installation method).

### 2. Edit config.json
Open the configuration file and locate the `ldap` section. If it does not exist, add it to the root JSON object.

#### Example Configuration (Active Directory)

```json
{
  "mysql": { ... },
  "cookie_hash": "...",
  "cookie_encryption": "...",
  ...
  "ldap": {
    "enable": true,
    "host": "dc01.example.local:389",
    "need_tls": false,
    "dn_bind": "CN=SemaphoreBind,OU=ServiceAccounts,DC=example,DC=local",
    "password": "YOUR_BIND_PASSWORD",
    "dn_search": "OU=Users,DC=example,DC=local",
    "search_filter": "(&(objectClass=person)(sAMAccountName=%s))",
    "mail_attribute": "mail"
  }
}
```

### 3. Configuration Parameters

| Parameter | Description | Example |
| :--- | :--- | :--- |
| `enable` | Set to `true` to enable LDAP authentication. | `true` |
| `host` | Hostname and port of the LDAP server. | `192.168.1.10:389` |
| `need_tls` | Set to `true` if using LDAPS (Port 636) or StartTLS. | `false` |
| `dn_bind` | User DN for querying the directory. | `CN=BindUser,CN=Users,DC=domain,DC=local` |
| `password` | Password for the `dn_bind` user. | `SecretPass123!` |
| `dn_search` | The base DN where users are located. | `DC=domain,DC=local` |
| `search_filter` | Filter to find the user. `%s` is replaced by the login input. | `(&(objectClass=user)(sAMAccountName=%s))` |
| `mail_attribute` | (Optional) Attribute to map to the user's email. | `mail` |

### 4. Apply Changes
Save the `config.json` file and restart the Semaphore service to apply the changes.

```bash
# Example for systemd
sudo systemctl restart semaphore
```

## Verification
1.  Open the Semaphore UI login page.
2.  Enter an Active Directory username (matching the `search_filter`) and password.
3.  If successful, a new user account will be created in Semaphore linked to the AD identity.

## Troubleshooting
*   **Login Failed**: Check the Semaphore logs (`journalctl -u semaphore -f` or `docker logs semaphore`) for LDAP bind errors.
*   **Connection Refused**: Ensure the Semaphore server can reach the AD server on the specified port (check firewalls).
