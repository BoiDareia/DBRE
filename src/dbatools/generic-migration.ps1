#######################################################################################################################################
# Sérgio Gonçalves
# Platform: PowerShell on Windows, Mac or Linux
#######################################################################################################################################

## Run this command in a PowerShell window as an Administrator:
Set-ExecutionPolicy UnRestricted -Force

## Trusting Microsoft’s default repository
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted 

## Run the installation command
Install-Module -Name dbatools

## In the same PowerShell window, import the module (this is sometimes needed the very first time)

Import-Module dbatools

#Set password variable used for sa password for SQL Server
##$PASSWORD='S0methingS@Str0ng!'

#######################################################################################################################################
# Building Connections - Working with Connect-DbaInstance 
#   - Persistent connection to your instance which can be used over and over again.
#   - Can give you a ton of information about your instance.
#   - Its a SMO object so you can do things that may not yet be implemented in dbatools
#######################################################################################################################################


# Yea, I'm using sa... 
##$sqluser = 'sa' 
##$sqlpasswd = ConvertTo-SecureString $PASSWORD -AsPlainText -Force
##$SqlCredential = New-Object System.Management.Automation.PSCredential ($sqluser, $sqlpasswd)

# This command will pop up a login window.
# The message in the dialog will be "Please enter your AD credentials".
$SqlCredential = Get-Credential -UserName "BoiDareia" -Message "Please enter your AD credentials"

# --- Displaying the created credential object (for verification) ---
if ($SqlCredential) {
    Write-Host "Credential created securely using Get-Credential:"
    Write-Host "Username: $($SqlCredential.UserName)"
    Write-Host "This is the recommended method for interactive scripts."
} else {
    Write-Host "Credential creation was cancelled."
}

# Setting the SQL Trust Certificate that's required for the connetion globally for the session currently running
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true
# We can use the -Register switch to make it permanent
## Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register

# This cmdlet lets you persist a connection between executions
$SqlInstance = Connect-DbaInstance -SqlInstance "localhost,1433" -SqlCredential $SqlCredential
$SqlInstance

# You can see the connection here and it's its SPIDs.
##Get-DbaProcess -SqlInstance $SqlInstance -ExcludeSystemSpids | 
##    Where-Object { $_.Program -eq 'dbatools PowerShell module - dbatools.io' }

# The connection is a SMO object. 
##$SqlInstance | Get-Member | more

# Its got a ton of info and also can be used for things not yet implemented in dbatools
##$SqlInstance.Databases | Format-Table

#######################################################################################################################################


#######################################################################################################################################
# Getting information - Using the Get-* cmdlets - Get-DbaDatabase
#   - Let's get a listing of what's on this instance...just the system databases. 
#   - This is using our $SqlInstance variable - so it's using the existing SMO object and doesn't require authentication again. 
#   - Get for inventory and auditing...like when was the last backup and much more.
#   - Core to migration techniques since you can pipe output into other cmdlets to create objects on other instances
#######################################################################################################################################

##Get-Command -Module dbatools -Verb Get

Get-DbaDatabase -SqlInstance $SqlInstance | Format-Table

#######################################################################################################################################

# We need to configure xp_cmdshell to access the network share that has the backups in case you're using one
# Enabling xp_cmdshell can have security implications, so ensure you understand the risks and have appropriate security measures in place.
# RUN IN SSMS or Azure Data Studio
EXEC sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
EXEC sp_configure 'xp_cmdshell',1
GO
RECONFIGURE
GO

EXEC XP_CMDSHELL 'net use Z: \\share.company.com\share'

# Check if instance is visible from the server
EXEC XP_CMDSHELL 'Dir Z:' 

# Delete the mapped drive when finished
EXEC XP_CMDSHELL 'net use Z: /delete'


#######################################################################################################################################
# Back to the future with Restore-DbaDatabase
# The most versitile cmdlet in the bunch. Supports many use cases...
#   - Restore all databases.
#   - Foundation to migration scenarios
#   - Restoring a subset of backups, and here we're restoring from file
#   - Restoring from object (blob) and building a restore sequence without msdb 
#    
#    What is this useful for? Disaster recovery scenarios!!!
#    Also, supports complex restore patterns - file group, page, point in time ... with a much simpler syntax
#######################################################################################################################################

Write-Host "`n--- Copying a file from AWS S3 ---" -ForegroundColor Cyan

# Prerequisite: Make sure you have the AWS module installed
# You can install it by running: 

Install-Module -Name AWS.Tools.S3 -Force

# Step 1: Set up your AWS Credentials (replace with your actual keys) - NO NEED ON EC2 INSTANCES
# For security, avoid hardcoding credentials. Consider environment variables or AWS credential files.
##$AccessKey = "YOUR_AWS_ACCESS_KEY_ID"
##$SecretKey = "YOUR_AWS_SECRET_ACCESS_KEY"

# Set the credentials for the current PowerShell session
##Set-AWSCredential -AccessKey $AccessKey -SecretKey $SecretKey -StoreAs "Default"

# Map Drive in Powershell
net use Z: "\\share.company.com\share"

# Step 2: Define your S3 bucket, the file you want to copy, and the local destination
$bucketName = "data-transfer-bucket" # Replace with your bucket name
$s3ObjectKey = "backups/your-backup-file.zip" # This is the full path to the file in the bucket
$s3KeyPrefix = "folder1/folder2" # This is the path where the files in the bucket are
$localDestination = "Z:\Backups\folder1\"   # The local path to save the file

# Ensure the local directory exists
$localDirectory = Split-Path -Path $localDestination -Parent
if (-not (Test-Path -Path $localDirectory)) {
    New-Item -ItemType Directory -Path $localDirectory | Out-Null
}

# Step 3: Copy the object from S3 to your local file system
Write-Host "Attempting to copy '$s3ObjectKey' from bucket '$bucketName' to '$localDestination'..."

try {
    # The AWS cmdlets will automatically pick up the credentials set by Set-AWSCredential
    # This on copies just one object
    ##Copy-S3Object -BucketName $bucketName -Key $s3ObjectKey -LocalFile $localDestination -Force

    # To copy an entire folder from S3, you can do this:
    Read-S3Object -BucketName $bucketName -KeyPrefix $s3KeyPrefix -Folder $localDestination
    
    Write-Host "File copied successfully!" -ForegroundColor Green
}
catch {
    Write-Host "An error occurred during the S3 copy operation:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host "Please check your credentials, bucket name, file path, and IAM permissions."
}


# Restoring all backups from a set of backups
# Before running this you might need to clean/exclude the system databases
# since they wont be restorable because they are coming from old version of SQL Server
# using the -ReuseSourceFolderStructure switch to recreate the original folder structure
# If a Db already exists you can use -WithReplace to overwrite it
# If you want to leave the databases in restoring mode use -NoRecovery
Restore-DbaDatabase -SqlInstance $SqlInstance -Path $localDestination -ReuseSourceFolderStructure
#Check the databases' status
Get-DbaDatabase -SqlInstance $SqlInstance | Format-Table

# This is basically how I migrate SQL Server instances ...take full backups of the source instance...
##$databases = @('DBAdmin','DatabaseToRestore', 'OtherDatabase')
##$FullBackups = Backup-DbaDatabase -SqlInstance $SqlInstance -Database $databases -Type Full -CompressBackup -Path '/backups/sqlbackups/migrate/' 
##$FullBackups
##$FullBackups | Select-Object *

# Restore them the target instance...leave the databases in recovery 
##$FullBackups | Restore-DbaDatabase -SqlInstance 'localhost,1434' -SqlCredential $SqlCredential -NoRecovery -WithReplace

# Check the databases' status
##Get-DbaDatabase -SqlInstance 'localhost,1434' -SqlCredential $SqlCredential  | Format-Table

# Now at cutover time...stop the applications and take a differential backup on the source instance
##$DiffBackups = Backup-DbaDatabase -SqlInstance $SqlInstance -Database $databases -Type Differential -CompressBackup -Path '/backups/sqlbackups/migrate/'
##$DiffBackups
##$DiffBackups | Select-Object * 

# Set the source databases offline on the source system
##Set-DbaDbState -SqlInstance $SqlInstance -Database $databases -Online -Confirm:$false | Format-Table

# Restore it on the target instance and bring the databases online
##$DiffBackups | Restore-DbaDatabase -SqlInstance 'localhost,1434' -SqlCredential $SqlCredential -Continue -NoRecovery

# Check the databases' status
##Get-DbaDatabase -SqlInstance 'localhost,1434' -SqlCredential $SqlCredential  | Format-Table


#######################################################################################################################################
# EXTRA - Bringing balance to the force with - Invoke-DbaBalanceDataFiles
#    - Its common have all the database objects in one data file in the primary file group.
#    - Breaking databases into multiple files enables advanced data management techniques 
#    - Specifically, this can help with IO and backup/restore performance.
#######################################################################################################################################


# Let's check out the database file layout...to get parallelism we need to get lots of database files
Get-DbaDbFile -SqlInstance $SqlInstance -Database DBName | 
    Select-Object Database,FileGroupName,TypeDescription,LogicalName,PhysicalName,Size,UsedSpace | Format-Table


# Add one file per volume in the new file group...we'll need to set the permissions on the directories so the mssql user can create files
Invoke-DbaQuery -SqlInstance $SqlInstance -Database DBName -Query "ALTER DATABASE DBName ADD FILE (NAME = file_1, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL\DATA\DBName_file1.ndf', SIZE = 1024MB) TO FILEGROUP [PRIMARY];"
Invoke-DbaQuery -SqlInstance $SqlInstance -Database DBName -Query "ALTER DATABASE DBName ADD FILE (NAME = file_2, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL\DATA\DBName_file2.ndf', SIZE = 1024MB) TO FILEGROUP [PRIMARY];"
Invoke-DbaQuery -SqlInstance $SqlInstance -Database DBName -Query "ALTER DATABASE DBName ADD FILE (NAME = file_3, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL\DATA\DBName_file3.ndf', SIZE = 1024MB) TO FILEGROUP [PRIMARY];"
Invoke-DbaQuery -SqlInstance $SqlInstance -Database DBName -Query "ALTER DATABASE DBName ADD FILE (NAME = file_4, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL\DATA\DBName_file4.ndf', SIZE = 1024MB) TO FILEGROUP [PRIMARY];"


# Let's check out the database file layout...to get parallelism we need to get lots of database files...but the four new files are emtpy.
Get-DbaDbFile -SqlInstance $SqlInstance -Database DBName | 
    Select-Object Database,FileGroupName,TypeDescription,LogicalName,PhysicalName,Size,UsedSpace | Format-Table


# Balance the data into the new files. -Force is needed to override a space check that is Windows specific. 
# Takes about a minute. Currently this only supports rebuilding into the same file group. 
Invoke-DbaBalanceDataFiles -SqlInstance $SqlInstance -Database DBName -Verbose -Force


# Are the files balanced? Close enough, some objects such as heaps are ignored. 
Get-DbaDbFile -SqlInstance $SqlInstance -Database DBName | 
    Select-Object Database,FileGroupName,TypeDescription,LogicalName,PhysicalName,Size,UsedSpace | Format-Table



#######################################################################################################################################
# Just the two of us - The Copy-* cmdlets
# Even though dbatools has a fantastic migration cmdlet... 
#  - I often select the exact objects I want to migrate and migrate just those
#  - Also often used to keep objects in sync for Availability Groups
#  - There's also Sync-DbaAvailabilityGroup
#######################################################################################################################################


Get-Command -Verb Copy -Module dbatools | more


# Copy-DbaUser/Login
New-DbaLogin -SqlInstance $SqlInstance1 -Login login1 -SecurePassword $sqlpasswd
New-DbaLogin -SqlInstance $SqlInstance1 -Login login2 -SecurePassword $sqlpasswd
New-DbaLogin -SqlInstance $SqlInstance1 -Login login3 -SecurePassword $sqlpasswd
New-DbaLogin -SqlInstance $SqlInstance1 -Login login4 -SecurePassword $sqlpasswd


New-DbaDbUser -SqlInstance $SqlInstance1 -Database DBName -Login login1
New-DbaDbUser -SqlInstance $SqlInstance1 -Database DBName -Login login2
New-DbaDbUser -SqlInstance $SqlInstance1 -Database DBName -Login login3
New-DbaDbUser -SqlInstance $SqlInstance1 -Database DBName -Login login4


# Even though it's in an AG, its on you to copy instance objects like logins, linked servers, jobs and more.
Get-DbaLogin -SqlInstance 'localhost,1433' -SqlCredential $SqlCredential | Format-Table
Get-DbaLogin -SqlInstance 'localhost,1434' -SqlCredential $SqlCredential | Format-Table

# MISSING LOGINS ON SECONDARY REPLICAS HAS CAUSED SO MANY OUTAGES!!!!!!!!!

# This will also copy the password and permissions.
Copy-DbaLogin -Source $SqlInstance1 -Destination $SqlInstance2 

Get-DbaLogin -SqlInstance 'localhost,1433' -SqlCredential $SqlCredential | Format-Table
Get-DbaLogin -SqlInstance 'localhost,1434' -SqlCredential $SqlCredential | Format-Table


#######################################################################################################################################
# What's the scenario? - Configuration cmdlets
#   - The only way to keep things sane is to deploy in code...
#   - so I always use dbatools to test/set/get any of the core sql instance configuration settings.
#   - Further, I wrap them in Pester to ensure the settings are set and then I can come back later and re-test for compliance.
#######################################################################################################################################


# Let's Configure an¸Instance(s)
$SqlInstances = @($SqlInstance1, $SqlInstance2) # <----- I'm doing something super interesting right here...what is it????
Set-DbaMaxMemory -SqlInstance $SqlInstances #This throws a warning since it's trying to find multiple instances but cannot on SQL Server on Linux
Install-DbaWhoIsActive -SqlInstance $SqlInstances -SqlCredential $SqlCredential -Database master


# Run a pester test
$container = New-PesterContainer -Path './scripts/powershell/postinstallationchecks.tests.ps1' -Data @{ SqlInstance = $SqlInstances; SqlCredential = $SqlCredential; }
Invoke-Pester -Container $container -Output Detailed


# dbatools to get the cost threshold for parallelism
Get-DbaSpConfigure -SqlInstance $SqlInstance1 -SqlCredential $SqlCredential | Where-Object { $_.displayname -eq 'cost threshold for parallelism' } | Format-Table
