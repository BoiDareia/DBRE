PowerShell Database Automation with dbatools
============================================

This PowerShell script is a comprehensive demonstration of the `dbatools` module, showcasing its power and versatility for a wide range of database administration tasks. It covers everything from initial setup and connection to complex database migrations and configuration management.

This script is based on the presentation materials created by **Anthony Nocentino** for his session "Unlocking Database Automation with dbatools" at SQLBits 2024. You can find the original source files and more in his [Presentations GitHub repository](https://github.com/nocentino/Presentations/tree/master/SQLBits2024/Unlocking-Database-Automation-dbatools).

📜 Script Overview
------------------

This is not a script meant to be run from top to bottom in one go. Instead, it's a collection of **examples** and **recipes** for common DBA tasks. It's designed to be executed in sections, allowing you to understand and adapt each part for your own environment.

**Key features demonstrated:**

-   Installation and setup of the `dbatools` module.

-   Securely connecting to SQL Server instances.

-   Performing database restores and migrations.

-   Copying backups from an AWS S3 bucket.

-   Optimizing database file layouts.

-   Synchronizing instance-level objects like logins.

-   Applying and verifying server configurations.

* * * * *

🛠️ Section 1: Setup and Connection
-----------------------------------

The first part of the script handles the prerequisites for using `dbatools`.

PowerShell

```
# Run this command in a PowerShell window as an Administrator:
Set-ExecutionPolicy UnRestricted -Force

# Trusting Microsoft's default repository
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Run the installation command
Install-Module -Name dbatools

# In the same PowerShell window, import the module
Import-Module dbatools

```

### Key Steps

1.  **Set Execution Policy**: Allows the execution of PowerShell scripts on the system.

2.  **Trust PSGallery**: Sets the official PowerShell Gallery as a trusted repository for installing modules.

3.  **Install `dbatools`**: Downloads and installs the latest version of the module.

### Establishing a Connection

The script demonstrates the best practice for handling credentials interactively using `Get-Credential`. This avoids storing passwords in plain text.

PowerShell

```
# This command will pop up a login window.
$SqlCredential = Get-Credential -UserName "BoiDareia" -Message "Please enter your AD credentials"

# Setting the SQL Trust Certificate that's required for the connection
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true

# This cmdlet lets you persist a connection between executions
$SqlInstance = Connect-DbaInstance -SqlInstance "localhost,1433" -SqlCredential $SqlCredential

```

-   `Get-Credential`: Securely prompts the user for a username and password.

-   `Set-DbatoolsConfig`: Configures `dbatools` to trust the server certificate, a common requirement for modern SQL Server connections.

-   `Connect-DbaInstance`: Establishes a persistent connection (a SMO object) to the target SQL Server instance, which can be reused by subsequent commands without re-authenticating.

* * * * *

🔄 Section 2: Database Migration with `Restore-DbaDatabase`
-----------------------------------------------------------

This is a core section demonstrating a powerful and flexible migration workflow.

### Preparing for Restore

The script shows how to prepare the server to access backup files, including potentially mapping a network drive via `xp_cmdshell`.

> ⚠️ **Security Warning**: Enabling `xp_cmdshell` has security implications. Ensure you understand the risks and that appropriate security measures are in place before enabling it in a production environment.

### Copying Backups from AWS S3

A practical example is included for downloading backup files directly from an AWS S3 bucket before the restore operation.

PowerShell

```
# Prerequisite: Make sure you have the AWS module installed
Install-Module -Name AWS.Tools.S3 -Force

# Define your S3 bucket, the file you want to copy, and the local destination
$bucketName = "data-transfer-bucket"
$s3KeyPrefix = "folder1/folder2"
$localDestination = "Z:\Backups\folder1\"

# To copy an entire folder from S3
Read-S3Object -BucketName $bucketName -KeyPrefix $s3KeyPrefix -Folder $localDestination

```

### Performing the Restore

The `Restore-DbaDatabase` command is used to restore all databases from the specified backup location.

PowerShell

```
# Restoring all backups from a set of backups
Restore-DbaDatabase -SqlInstance $SqlInstance -Path $localDestination -ReuseSourceFolderStructure

```

The script also contains a commented-out section outlining a complete **minimal-downtime migration strategy**:

1.  Take **full backups** of source databases.

2.  Restore them to the target instance using the `-NoRecovery` switch.

3.  At cutover time, take a final **differential backup**.

4.  Restore the differential backup on the target, bringing the databases online and completing the migration.

* * * * *

⚖️ Section 3: Balancing Data Files
----------------------------------

This section demonstrates how to improve I/O performance by distributing data across multiple data files (`.ndf`).

PowerShell

```
# Check the initial database file layout
Get-DbaDbFile -SqlInstance $SqlInstance -Database DBName

# Add new, empty data files to the PRIMARY filegroup
Invoke-DbaQuery -SqlInstance $SqlInstance -Database DBName -Query "ALTER DATABASE..."

# Rebalance the data evenly across all files in the filegroup
Invoke-DbaBalanceDataFiles -SqlInstance $SqlInstance -Database DBName -Verbose -Force

```

This is a powerful technique for alleviating `tempdb` contention or spreading I/O for large user databases, and `dbatools` makes the rebalancing process a single, simple command.

* * * * *

👯 Section 4: Copying Server Objects
------------------------------------

Migrations are more than just databases. This part of the script shows how to copy instance-level objects, using logins as a prime example.

PowerShell

```
# This will copy the password and permissions for logins from source to destination
Copy-DbaLogin -Source $SqlInstance1 -Destination $SqlInstance2

```

This is **critical** for scenarios like Availability Groups, where keeping logins synchronized across replicas is essential for preventing application outages after a failover. `Copy-DbaLogin` handles SIDs, passwords, and server permissions automatically.

* * * * *

⚙️ Section 5: Configuration as Code
-----------------------------------

The final section demonstrates how to manage SQL Server configuration using `dbatools`, treating your server setup as code.

PowerShell

```
# Configure multiple instances at once
$SqlInstances = @($SqlInstance1, $SqlInstance2)
Set-DbaMaxMemory -SqlInstance $SqlInstances

# Use Pester to test for compliance
$container = New-PesterContainer -Path './scripts/postinstallationchecks.tests.ps1' -Data @{...}
Invoke-Pester -Container $container -Output Detailed

```

By defining configurations in a script, you can ensure consistency across all your environments (dev, test, prod). The script also shows how this can be integrated with **Pester**, a testing framework for PowerShell, to validate that your servers remain compliant with your defined standards.