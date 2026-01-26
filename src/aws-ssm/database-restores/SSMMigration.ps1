#######################################################################################################################################
# Sérgio Gonçalves - Resilient Database Migration Script for AWS Systems Manager
# Platform: PowerShell on Windows (AWS EC2)
# This script is designed for automation with AWS Secrets Manager for credentials.
#######################################################################################################################################

param(
    [Parameter(Mandatory=$true)]
    [string]$InstanceName,

    [Parameter(Mandatory=$true)]
    [string]$BucketName,

    [Parameter(Mandatory=$true)]
    [string]$SecretName,  # AWS Secrets Manager secret name for SQL credentials

    [Parameter(Mandatory=$false)]
    [switch]$SkipHealthChecks
)

# Output will be logged to CloudWatch Logs automatically in SSM Runbooks
Write-Host "Starting database migration script at $(Get-Date)"

try {

    # Get the DNS domain from the computer system (e.g., dmz.corp.local)
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $dnsDomain = $computerSystem.Domain

    # Find the matching NetBIOS info using Win32_NTDomain
    # We filter for the entry that matches our DNS domain to avoid picking up trusted domains.
    $netBiosInfo = Get-CimInstance Win32_NTDomain | Where-Object { 
        $_.DnsForestName -eq $dnsDomain -or $_.DomainName -eq $dnsDomain 
    } | Select-Object -First 1

    if ($netBiosInfo) {
        $ActiveDirectory = $netBiosInfo.DomainName # This returns 'DMZMGMT'
    }
    else {
        # Fallback if WMI fails or machine is in a Workgroup
        $ActiveDirectory = $dnsDomain.Split('.')[0].ToUpper()
    }

    Write-Output "Detected NetBIOS Domain: $ActiveDirectory"

    # Setup variables
    $localDestination = "Z:\$InstanceName"
    switch ($ActiveDirectory) {
        "AD1" { $s3_gateway_ip = "100.55.6.22" }
        "AD2" { $s3_gateway_ip = "100.57.4.42" }
    }

    # Retrieve credentials from AWS Secrets Manager
    $secret = Get-SECSecretValue -SecretId $SecretName -ErrorAction Stop
    $secretJson = $secret.SecretString | ConvertFrom-Json
    $SqlCredential = New-Object System.Management.Automation.PSCredential ("$ActiveDirectory\$($secretJson.username)", (ConvertTo-SecureString $secretJson.password -AsPlainText -Force))

    # Configure dbatools
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -ErrorAction Stop

    # Connect to SQL Instance
    $SqlInstance = Connect-DbaInstance -SqlInstance "localhost,1433" -SqlCredential $SqlCredential -ErrorAction Stop
    Write-Host "Connected to SQL Instance successfully"

    # Define variables
    $DriveLetter = "Z"
    $RemotePath = "\\$($s3_gateway_ip)\$($BucketName)"

    # Check if the drive already exists using PowerShell native cmdlets
    if (Get-PSDrive -Name $DriveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        Write-Host "Drive $DriveLetter is already mapped. Skipping..."
    }else {
        # Map the drive only if it is missing
        try {
            # Using net use with /Y forces 'yes' to prompts if there's a conflict hidden in the background
            net use "$($DriveLetter):" "$RemotePath"
            
            if ($LASTEXITCODE -ne 0) { 
                throw "Command 'net use' returned exit code $LASTEXITCODE" 
            }
            
            Write-Host "Network drive $DriveLetter mapped successfully"
        } catch {
            Write-Error "Failed to map network drive: $_"
            throw
        }
    }

    # 1. Define the Query (Fixed 'EXE' to 'EXEC' and 'RECONFIG' to 'RECONFIGURE')
    $configQuery = @"
    EXEC sp_configure 'show advanced options', 1; 
    RECONFIGURE; 
    EXEC sp_configure 'xp_cmdshell', 1; 
    RECONFIGURE;
"@

    try {
        # --- STEP 1: EXECUTE THE CHANGE ---
        # We use -ErrorAction Stop to catch connection/syntax errors immediately
        Invoke-DbaQuery -SqlInstance $SqlInstance -Query $configQuery -ErrorAction Stop
        
        Write-Host "Configuration command sent to SQL Server." -ForegroundColor Cyan

        # --- STEP 2: VERIFY THE RESULT ---
        # We query sys.configurations specifically for xp_cmdshell
        # value_in_use = 1 means it is currently active.
        $verificationSql = "SELECT value_in_use FROM sys.configurations WHERE name = 'xp_cmdshell'"
        
        $result = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $verificationSql -ErrorAction Stop

        if ($result.value_in_use -eq 1) {
            Write-Host "SUCCESS: 'xp_cmdshell' is confirmed ENABLED (Active Value: 1)." -ForegroundColor Green

            # Map drive via SQL for verification
            $mapQuery = "EXEC XP_CMDSHELL 'net use Z: $RemotePath'"
            Invoke-DbaQuery -SqlInstance $SqlInstance -Query $mapQuery -ErrorAction Stop

            # Check drive
            $checkQuery = "EXEC XP_CMDSHELL 'Dir Z:'"
            $result = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $checkQuery -ErrorAction Stop
            if (-not $result) { throw "Drive Z: not accessible" }
        }
        else {
            # This catches scenarios where the command ran but the setting didn't stick
            # (e.g., RECONFIGURE failed silently or requires a restart)
            Write-Host "FAILURE: The command ran, but 'xp_cmdshell' is still DISABLED." -ForegroundColor Red
            Write-Host "Current Value: $($result.value_in_use)"
        }
    }
    catch {
        Write-Error "CRITICAL ERROR: The script failed to execute. Details: $_"
    }

    # Ensure local directory exists
    $localDirectory = Split-Path -Path $localDestination -Parent
    if (-not (Test-Path -Path $localDirectory)) {
        New-Item -ItemType Directory -Path $localDirectory -ErrorAction Stop | Out-Null
    }

    # Get the list of folders (Added -Directory to ensure we only get folders, not loose files)
    $databaseFolders = Get-ChildItem -Path $localDestination -Directory | 
                    Where-Object { $_.Name -notmatch '^(master|model|msdb)' } | 
                    Select-Object -ExpandProperty FullName

    # Loop through each folder individually
    foreach ($folder in $databaseFolders) {
        
        Write-Host "--------------------------------" -ForegroundColor Gray
        Write-Host "Processing Folder: $folder" -ForegroundColor Cyan

        # Get .bak files JUST for the current folder in the loop
        $bakFiles = Get-ChildItem -Path $folder -Filter "*.bak" -ErrorAction Stop | 
                    Select-Object -ExpandProperty FullName

        if ($bakFiles) {
            Write-Host "Found $( $bakFiles.Count ) backup file(s). Starting restore..." -ForegroundColor Green

            # READ THE BACKUP HEADERS
            # We scan the file first to find out where the files WANTS to go
            try {
                $backupInfo = Get-DbaBackupInformation -SqlInstance $SqlInstance -Path $bakFiles -ErrorAction Stop
            }
            catch {
                Write-Error "Failed to read backup header: $_"
                continue # Skip to next folder
            }

            # -----------------------------------------------------------
            # FILESTREAM CHECK & ACTIVATION
            # -----------------------------------------------------------
            # Check if any file in the backup list is Type 'S' (Stream)
            if ($backupInfo.FileList | Where-Object { $_.Type -eq 'S' }) {
                Write-Warning "FileStream data detected in backup for database: $( $backupInfo.DatabaseName )"
                
                # CORRECTED SECTION: Check FileStream Effective Level
                # 0 = Disabled
                # 1 = T-SQL Only
                # 2 = T-SQL + Win32 Streaming (Standard for full support)
                # 3 = Remote Access
                
                try {
                    $checkQuery = "SELECT CAST(SERVERPROPERTY('FilestreamEffectiveLevel') AS INT)"
                    $fsLevel = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $checkQuery -ErrorAction Stop | Select-Object -ExpandProperty Column1
                }
                catch {
                    Write-Error "Could not query FileStream status. Skipping auto-activation logic."
                    $fsLevel = 0 # Assume disabled on error
                }

                if ($fsLevel -lt 2) {
                    Write-Host "FileStream Effective Level is '$fsLevel' (Requires 2). Attempting to enable..." -ForegroundColor Yellow
                    
                    try {
                        # Enable-DbaFilestream attempts to set WMI and sp_configure
                        # -Force is required to restart the SQL Service to apply changes
                        Enable-DbaFilestream -SqlInstance $SqlInstance -FileStreamLevel TSqlIoStreaming -Force -ErrorAction Stop
                        
                        Write-Host "SUCCESS: FileStream enabled and SQL Service restarted." -ForegroundColor Green
                        
                        # Give SQL Server a moment to come back online fully before proceeding
                        Write-Host "Waiting 15 seconds for SQL Service to stabilize..." -ForegroundColor Gray
                        Start-Sleep -Seconds 15
                    }
                    catch {
                        # If we can't enable it, we must stop, or the restore will definitely fail
                        Write-Error "CRITICAL: Failed to auto-enable FileStream. Restore cannot proceed. Error: $_"
                        continue # Skip to next folder
                    }
                } else {
                    Write-Host "FileStream is already enabled and active (Level $fsLevel)." -ForegroundColor Green
                }
            }

            # EXTRACT UNIQUE FOLDERS
            # We look at the FileList inside the backup info to find distinct folder paths
            $directoriesToCreate = $backupInfo.FileList | 
                Select-Object -ExpandProperty PhysicalName | 
                ForEach-Object { [System.IO.Path]::GetDirectoryName($_) } | 
                Select-Object -Unique

            # CREATE FOLDERS ON TARGET (Using SQL Server)
            # We use xp_create_subdir because it runs as the SQL Service Account
            foreach ($dir in $directoriesToCreate) {
                Write-Host "Ensuring directory exists: $dir" -ForegroundColor Cyan
                
                # This SQL command forces SQL Server to create the folder
                $query = "EXEC master.sys.xp_create_subdir N'$dir'"
                
                try {
                    # -ErrorAction Stop forces the script to fail immediately if SQL complains
                    Invoke-DbaQuery -SqlInstance $SqlInstance -Query $query -ErrorAction Stop
                }
                catch {
                    # This block runs only if the folder creation failed (e.g. invalid drive)
                    $errorMessage = "CRITICAL ERROR: Failed to create directory '$dir' on target SQL Server. " +
                                    "The drive letter might be missing, or the SQL Service Account lacks permissions. " +
                                    "SQL Error Details: $_"
                    
                    # 'throw' stops the entire script immediately and logs the error
                    throw $errorMessage
                }
            }
            
            # Run the restore for this specific batch of files
            # Added try/catch so if one folder fails, the script continues to the next folder
            try {
                Restore-DbaDatabase -SqlInstance $SqlInstance -Path $bakFiles -WithReplace -NoRecovery -ErrorAction Stop
            }
            catch {
                Write-Error "Failed to restore database from folder '$folder'. Error: $_"
            }
        }
        else {
            Write-Warning "No .bak files found in folder: $folder"
        }

        # Restore diffs/logs
        $difFiles = Get-ChildItem -Path $databaseFolders -Include "*.trn", "*.dif" -Recurse -ErrorAction Stop | Select-Object -ExpandProperty FullName
        if ($difFiles) {
            # Added try/catch so if one folder fails, the script continues to the next folder
            try {
                Restore-DbaDatabase -SqlInstance $SqlInstance -Path $difFiles -Recover -Continue -ErrorAction Stop
            }
            catch {
                Write-Error "Failed to restore database from folder '$folder'. Error: $_"
            }
        }

        # Waiting 3 min so Get-DbaDatabase is able to get any database that got left in Restoring Mode
        Start-Sleep -Seconds 180

        # Recover databases
        # Get the list of databases currently in 'Restoring' mode
        $databases = Get-DbaDatabase -SqlInstance $SqlInstance -Status Restoring

        if ($databases) {
            foreach ($db in $databases) {
                try {
                    Write-Host "Recovering database: $($db.Name)"
                    
                    # Simple T-SQL to bring the database online
                    $recoverQuery = "RESTORE DATABASE [$($db.Name)] WITH RECOVERY"
                    
                    Invoke-DbaQuery -SqlInstance $SqlInstance -Query $recoverQuery -ErrorAction Stop
                    
                    Write-Host "Successfully recovered $($db.Name)" -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to recover database '$($db.Name)'. Error: $_"
                }
            }
        }

        # Set restricted databases to multi-user to make them all available
        Get-DbaDatabase -SqlInstance $SqlInstance | Where-Object { $_.UserAccess -like "*Restricted*" } | Set-DbaDbState -MultiUser -Force -ErrorAction Stop
    }

    # Repair orphaned users
    Repair-DbaDbOrphanUser -SqlInstance $SqlInstance -ErrorAction Stop

    # Set DB owner
    Set-DbaDbOwner -SqlInstance localhost -ErrorAction Stop

    # Create monitoring DB
    $DatabaseParams = @{
        SqlInstance = $SqlInstance
        Name = "FHMonitor"
        RecoveryModel = "Full"
    }
    New-DbaDatabase @DatabaseParams -ErrorAction Stop

    # Install monitoring tools
    Install-DbaFirstResponderKit -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database FHMonitor -ErrorAction Stop
    Install-DbaWhoIsActive -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database FHMonitor -ErrorAction Stop

    # Health checks (if not skipped)
    if (-not $SkipHealthChecks) {
        Write-Host "Checking database health status..."
        # Only get 'Online' databases to avoid crashing on Offline/Restoring DBs
        # We also remove -ErrorAction Stop from the CheckDb command so one failure doesn't kill the script
        $onlineDbs = Get-DbaDatabase -SqlInstance $SqlInstance -Status Online
        
        $CheckResults = $onlineDbs | Get-DbaLastGoodCheckDb -ErrorAction Continue
        foreach ($database in $CheckResults) {
            # Check if > 7 days OR if never checked ($null)
            if ($database.DaysSinceLastGoodCheckDb -gt 7 -or $null -eq $database.DaysSinceLastGoodCheckDb) {
                Write-Host "Running DBCC CHECKDB on $($database.Database)"
                try {
                    # Increase timeout to 0 (infinite) because CHECKDB can take a long time
                    Invoke-DbaQuery -SqlInstance $SqlInstance -Database $database.Database -Query "DBCC CHECKDB('$($database.Database)') WITH NO_INFOMSGS" -SqlCredential $SqlCredential -ErrorAction Stop

                    Write-Host " - passed." -ForegroundColor Green
                }
                catch {
                    Write-Error "Integrity check failed for '$($database.Database)': $_"
                }
            }
            else {
                Write-Host "Skipping '$($database.Database)' (Checked $($database.DaysSinceLastGoodCheckDb) days ago)" -ForegroundColor Gray
            }   
        }
    }

    # Cleanup (Run this regardless of the check outcome)
    # We also remove -ErrorAction Stop from the CheckDb command so one failure doesn't kill the script
    try {
        Invoke-DbaQuery -SqlInstance $SqlInstance -Query "EXEC XP_CMDSHELL 'net use Z: /delete'; EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE; EXEC sp_configure 'show advanced options', 0; RECONFIGURE;" -ErrorAction Continue
        net use Z: /delete 2>$null
    }
    catch {
        Write-Warning "Cleanup failed: $_"
    }

    Write-Host "Migration completed successfully"

} catch {
    Write-Error "An error occurred: $_"
    # In SSM, errors will be logged to CloudWatch
    throw  # Re-throw to mark runbook as failed
}