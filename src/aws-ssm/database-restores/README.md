AWS SSM Database Migration Automation
=====================================

This repository contains the automation artifacts required to orchestrate a resilient Microsoft SQL Server database migration and restoration process on AWS EC2 instances. It utilizes **AWS Systems Manager (SSM)** to bootstrap the environment and **PowerShell Core (with dbatools)** to perform the database restoration from an S3 Storage Gateway.

📂 Repository Contents
----------------------

| **File** | **Type** | **Description** |
| --- | --- | --- |
| `SSMDocument.yaml` | SSM Automation Runbook | The entry point. Defines the AWS SSM Document parameters, bootstraps PowerShell 7, and triggers the migration script. |
| `SSMMigration.ps1` | PowerShell Script | The core logic. Downloads from S3, maps network drives, restores databases, and performs health checks. |

🚀 Architecture & Workflow
--------------------------

1.  **Trigger:** The SSM Runbook (`SSMDocument.yaml`) is executed against a target EC2 Instance ID.

2.  **Bootstrap (Phase 1):** The runbook executes in Windows PowerShell 5.1 to:

    -   Enforce TLS 1.2 security protocols.

    -   Check for and install **PowerShell 7 (Core)** if missing.

    -   Install required AWS Modules (`AWS.Tools.SecretsManager`, `AWS.Tools.S3`) and `dbatools`.

3.  **Handover (Phase 2):** execution is handed over to `pwsh.exe` (PowerShell 7) to ensure modern module compatibility.

4.  **Execution (Phase 3 - `SSMMigration.ps1`):**

    -   **Discovery:** Detects the NetBIOS domain (e.g., `AD1`, `AD2`) to determine the correct S3 Gateway IP address.

    -   **Mount:** Maps the S3 Bucket as Network Drive `Z:` using `net use`.

    -   **SQL Config:** Temporarily enables `xp_cmdshell` to allow SQL Server to view the mapped network drive.

    -   **Restore:** Iterates through subfolders to restore Full (`.bak`) and Log (`.trn`) backups using `Restore-DbaDatabase`.

    -   **Post-Processing:** Repairs orphaned users, installs the **First Responder Kit** (`sp_WhoIsActive`), and creates a monitoring database `FHMonitor`.

🛠 Prerequisites
----------------

### AWS Configuration

-   **IAM Roles:** The target EC2 instance must have an instance profile with permissions to:

    -   Read from the specified S3 Bucket.

    -   Read the specified secret from AWS Secrets Manager.

    -   Write logs to CloudWatch.

-   **Network:** Connectivity to the S3 Gateway IPs defined in the script (e.g., `100.55.6.22` for AD1, `100.57.4.42` for AD2).

### Secrets Manager

The script expects a JSON secret (default name: `dba-creds`) containing the SQL credentials:

JSON

```
{
  "username": "sql_admin_user",
  "password": "your_password"
}

```

📖 Usage
--------

### Running via AWS Systems Manager

Execute the automation runbook with the following parameters:

| **Parameter** | **Type** | **Default** | **Description** |
| --- | --- | --- | --- |
| `InstanceId` | String | *(Required)* | The target EC2 Instance ID (e.g., `i-0abcdef12345`). |
| `SecretName` | String | `dba-creds` | The name of the AWS Secret containing SQL credentials. |
| `ScriptBucket` | String | `data-bucket-2026` | The S3 bucket where `SSMMigration.ps1` is stored. |
| `ScriptKey` | String | `src/SSMMigration.ps1` | The S3 path to the script. |
| `SkipHealthChecks` | String | `false` | Set to `true` to skip `DBCC CHECKDB` integrity checks. |

✨ Key Features & Logic
----------------------

### 1\. FileStream Auto-Detection

The script intelligently handles SQL FileStream requirements:

-   Scans backup headers to detect if `Type = 'S'` (Stream) data exists.

-   Checks the current `FilestreamEffectiveLevel` on the instance.

-   **Auto-Remediation:** If FileStream is required but disabled, the script enables `TSqlIoStreaming`, forces a SQL Service restart, and waits 15 seconds for stabilization before proceeding.

### 2\. Directory Handling

-   **creation:** Uses `master.sys.xp_create_subdir` to ensure target data paths exist on the server before attempting restoration.

-   **Mapping:** The Z: drive is mapped both at the OS level and inside SQL Server (via `xp_cmdshell`) to ensure the service account can access the S3 Gateway.

### 3\. Health & Monitoring

Unless `SkipHealthChecks` is set to `true`:

-   The script runs `DBCC CHECKDB` on databases that haven't been checked in the last 7 days.

-   It creates a local database named `FHMonitor`.

-   Installs `sp_Blitz` and `sp_WhoIsActive` for immediate troubleshooting capabilities.

### 4\. Cleanup

To maintain security, the script performs the following cleanup steps upon completion:

-   Removes the `Z:` network drive mapping.

-   Disables `xp_cmdshell` configuration.

-   Disables `show advanced options` in SQL Server.

⚠️ Troubleshooting
------------------

-   **PowerShell Version:** The SSM document installs PowerShell 7 automatically. If the bootstrap fails, ensure the EC2 instance has internet access to reach `aka.ms`.

-   **Drive Mapping Failures:** If `net use` fails, check that the EC2 instance security group allows SMB traffic to the specific Gateway IPs defined in the `switch ($ActiveDirectory)` block.

-   **Secret Errors:** Ensure the secret in AWS Secrets Manager is formatted as valid JSON with keys `username` and `password`.