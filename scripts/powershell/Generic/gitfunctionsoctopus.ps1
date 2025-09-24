#<#
# .SYNOPSIS
#  A collection of PowerShell functions for automating Git operations and querying
#  database deployment history.

# .DESCRIPTION
#  This script provides functions to clone, check out, and manage Git repositories,
#  as well as a function to query a Flyway history table to find the latest
#  deployed version. It is designed for use in automated deployment pipelines.

# .NOTES
#  This script assumes that Git is installed and accessible in the system's PATH.
#  It also requires appropriate permissions to access the specified file paths
#  and remote repositories.
#>

#---------------------------------------------------------------------------------------------
# Test Usage Block
#
# This section provides an example of how the GitCheckoutBranch function can be
# called. It is commented out and serves as documentation for developers.
#---------------------------------------------------------------------------------------------
<#
    #TEST USAGE
    [string] $DeployLocation = "C:\src\Company\Deploy"
    [string] $RollbackLocation = "C:\src\Company\Rollback"
    [string] $DeployVersion = "v75.0"
    [string] $RollbackVersion = "v74.0"
    [string] $CompanyGitURL = ".git"
    [bool] $IsTag = $True

    GitCheckoutBranch $DeployLocation $CompanyGitURL $DeployVersion $IsTag
#>

# Set the error action preference to 'Stop'.
# This means the script will terminate immediately if any command encounters a terminating error.
$ErrorActionPreference = 'Stop'

#---------------------------------------------------------------------------------------------
# GitCloneRemoteRepo Function
#
# Clones a remote Git repository into a specified local directory.
#---------------------------------------------------------------------------------------------
function GitCloneRemoteRepo() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [string]$DeployLocation,       # The local directory to clone the repository into.
        [Parameter(Mandatory=$True)]
        [string]$RemoteRepository,     # The URL of the remote Git repository.
        [Parameter(Mandatory=$True)]
        [string]$logfile,              # Path to the log file for recording output.
        [Parameter(Mandatory=$True)]
        [string]$gitArguments          # Any additional arguments for the 'git clone' command.
    )

    try {
        # Change the current directory to the deploy location.
        Set-Location $DeployLocation
        Write-Output "`nExecuting ""git clone $RemoteRepository $gitArguments"""
        
        # Execute the git clone command and redirect the error stream (stderr) to a variable.
        # '2>&1' merges stderr (2) into the success output stream (1).
        $myerrorstream = & git clone $RemoteRepository $gitArguments 2>&1

        # Check the result of the command.
        # $LASTEXITCODE contains the exit code of the last native command executed.
        if (-not ([string]::IsNullOrEmpty($myerrorstream)) -and $LASTEXITCODE -eq 1) {
            # If there's an error message and the exit code is 1 (failure), throw an exception.
            throw $myerrorstream
        }
        elseif (-not ([string]::IsNullOrEmpty($myerrorstream))) {
            # If there's output but no error code, it's likely a warning; just display it.
            Write-Output $myerrorstream
        }
    }
    catch {
        # Re-throw any caught exceptions to be handled by the calling script.
        throw
    }
}

#---------------------------------------------------------------------------------------------
# Invoke-Git Function
#
# A generic wrapper function to execute any Git command.
#---------------------------------------------------------------------------------------------
Function Invoke-Git {
    param (
        $GitRepositoryUrl,             # URL of the Git repository (not used in current implementation).
        $GitFolder,                    # Local folder of the repository (not used in current implementation).
        $GitUsername,                  # Username for authentication (not used in current implementation).
        $GitPassword,                  # Password for authentication (not used in current implementation).
        $Path,                         # The working directory for the command.
        $GitCommand,                   # The Git command to execute (e.g., "clone", "pull").
        $AdditionalArguments,          # An array of additional arguments for the command.
        $SupressOutput = $false        # A boolean to control whether to display command output.
    )
    
    # Initialize an array to hold the command and its arguments.
    $gitArguments = @($GitCommand)
    
    # Add any extra arguments to the array.
    if ($null -ne $AdditionalArguments) {
        $gitArguments += $AdditionalArguments
    }

    # Add the --quiet flag if output suppression is requested.
    if ($SupressOutput -eq $true) {
        $gitArguments += "--quiet"
    }

    # Log the command being executed.
    "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    "Executing ""git $gitArguments"""
    "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    # Execute the Git command.
    $results = git $gitArguments
    
    # Display the results unless suppressed.
    if ($SupressOutput -ne $true) {
        Write-Host $results
    }
    
    # Save the results to a text file named after the command.
    $path = "$PWD\$($GitCommand).txt"
    Add-Content -Path $path -Value $results
}

#---------------------------------------------------------------------------------------------
# Execute-Command Function
#
# A robust function to execute any external command and capture its output streams
# (stdout, stderr) and exit code.
#---------------------------------------------------------------------------------------------
Function Execute-Command {
    param (
        $commandPath,                  # The path to the executable.
        $commandArguments,             # The arguments to pass to the executable.
        $workingDir                    # The directory where the command should be run.
    )

    Try {
        # Create a ProcessStartInfo object to configure the process.
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.WorkingDirectory = $workingDir
        $pinfo.RedirectStandardError = $true   # Capture the error stream.
        $pinfo.RedirectStandardOutput = $true  # Capture the output stream.
        $pinfo.UseShellExecute = $false        # Required for stream redirection.
        $pinfo.Arguments = $commandArguments
        
        # Create and start the process.
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        
        # Create a custom object to store the results.
        $executionResults = [pscustomobject]@{
            stdout = $p.StandardOutput.ReadToEnd() # Read the entire output stream.
            stderr = $p.StandardError.ReadToEnd()  # Read the entire error stream.
            ExitCode = $null
        }
        
        # Wait for the process to finish.
        $p.WaitForExit()
        $gitExitCode = [int]$p.ExitCode
        $executionResults.ExitCode = $gitExitCode
        
        # Check for a failed exit code (2 or greater is considered a severe error).
        if ($gitExitCode -ge 2) {
            throw "Command execution failed with exit code: $gitExitCode"
        }
        
        # Return the results object.
        return $executionResults
    }
    Catch {
        # Handle exceptions during the execution.
        if ($executionResults) {
            # If results were partially captured, write the stderr to the error stream.
            Write-Error -Message "$($executionResults.stderr)" -ErrorId $gitExitCode
        }
        else {
            # Otherwise, write the general exception message.
            Write-Error -Message $_.Exception.Message
        }
        # Exit the script with the command's exit code.
        exit $gitExitCode
    }
}

#---------------------------------------------------------------------------------------------
# Test-LastExit Function
#
# Checks the $LastExitCode of the previously run native command and throws an
# error if it's not zero (success).
#---------------------------------------------------------------------------------------------
function Test-LastExit($cmd) {
    if ($LastExitCode -ne 0) {
        # This line is specific to Octopus Deploy for formatting error messages.
        Write-Host "##octopus[stderr-error]"
        Write-Error "$cmd failed with exit code: $LastExitCode"
    }
}

#---------------------------------------------------------------------------------------------
# GitCheckoutBranch Function
#
# Manages the full lifecycle of getting code from a Git repository. It can clone
# a new repository or clean and update an existing one before checking out a
# specific branch or tag.
#---------------------------------------------------------------------------------------------
function GitCheckoutBranch() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [string]$CheckoutPath,         # The local directory for the code.
        [Parameter(Mandatory=$True)]
        [string]$RemoteRepository,     # The URL of the remote Git repository.
        [Parameter(Mandatory=$True)]
        [string]$BranchName,           # The name of the branch or tag to check out.
        [Parameter(Mandatory=$False)]
        [bool]$IsTag = $False,         # Specifies if $BranchName is a tag.
        [Parameter(Mandatory=$false)]
        [bool]$isContinuousDelivery = $False, # If true, forces checkout of the 'develop' branch.
        [Parameter(Mandatory=$True)]
        [string]$logfile,              # Path to the log file.
        [Parameter(Mandatory=$True)]
        [string]$GitUsername,          # Username for Git authentication.
        [Parameter(Mandatory=$True)]
        [string]$GitPassword           # Password for Git authentication.
    )
    try {
        # Proactively create C:\tmp to prevent "could not find /tmp" warnings from Git's underlying tools.
        $tmpPath = "C:\tmp"
        if (-not (Test-Path -Path $tmpPath)) {
            Write-Host "Creating directory at $tmpPath for Git compatibility." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $tmpPath | Out-Null
        }
        
        # If this is a continuous delivery build, override the branch name to 'develop'.
        if ($isContinuousDelivery) { $BranchName = "develop" }

        # Ensure the checkout path has a trailing backslash for consistency.
        $CheckoutPathFull = $CheckoutPath.TrimEnd('\') + "\"

        # Log the key operation details to the console and the log file.
        @(
            "`nCheckout Path is: $CheckoutPathFull",
            "`nRemote Repository is: $RemoteRepository",
            "`nBranch to Checkout is: $BranchName"
        ) | ForEach-Object { Write-Host $_; Out-File -FilePath $logfile -InputObject $_ -Append }

        # Set the current location to the checkout path.
        Set-Location $CheckoutPathFull

        # Construct the repository URL with embedded credentials for authentication.
        $gitArguments = @()
        if (![string]::IsNullOrWhitespace($RemoteRepository)) {
            $gitUri = [System.Uri]$RemoteRepository
            $gitUrl = "{0}://{1}:{2}@{3}:{4}{5}" -f $gitUri.Scheme, $GitUsername, $GitPassword, $gitUri.Host, $gitUri.Port, $gitUri.PathAndQuery
            $gitArguments += $gitUrl
        }

        # Check if the current directory is already a Git repository.
        # '2>$null' suppresses error messages if the command fails (i.e., not a repo).
        $IsGitRepository = git rev-parse --is-inside-work-tree 2>$null

        if ($IsGitRepository -ne $True) {
            # If it's not a Git repository, clone it.
            "`nCheckout location is not a GIT repository. Cloning $RemoteRepository remote repo." | 
                ForEach-Object { Write-Host $_; Out-File -FilePath $logfile -InputObject $_ -Append }
            
            Invoke-Git -GitCommand "clone" -AdditionalArguments @($RemoteRepository, $gitArguments) -Path $CheckoutPath -SupressOutput $true
            "`nSuccessfully cloned git repository" | ForEach-Object { Write-Host $_; Out-File -FilePath $logfile -InputObject $_ -Append }
        } else {
            # If it is a Git repository, clean it to ensure a fresh state.
            git reset --hard HEAD --quiet # Discard all local changes.
            Test-LastExit "git reset --hard HEAD --quiet"
            
            git clean -f --quiet # Remove all untracked files.
            Test-LastExit "git clean -f --quiet"
            
            git fetch origin --quiet # Fetch the latest changes from the remote.
            Test-LastExit "git fetch origin --quiet"
            
            git fetch --tags --force --quiet # Force-fetch all tags.
            Test-LastExit "git fetch --tags --force --quiet"
        }

        Write-Host "Going to checkout branch $BranchName"

        # Check out the specified branch or tag.
        Invoke-Git -GitCommand "checkout" -AdditionalArguments @($BranchName) -Path $CheckoutPath -SupressOutput $true
        
        # If checking out a branch (not a tag), pull the latest changes.
        if (-not $IsTag) {
            Invoke-Git -GitCommand "pull" -Path $CheckoutPath -SupressOutput $true
        }

        Write-Host "`nSuccessfully checked out branch $BranchName from Git"
    }
    catch {
        # Log any exceptions that occur during the process.
        $_.Exception | ForEach-Object { Write-Host $_; Out-File -FilePath $logfile -InputObject $_ -Append }
        throw $_.Exception
    }
}

#---------------------------------------------------------------------------------------------
# LatestVersionDeployed Function
#
# Connects to a target database and queries the Flyway schema history table to
# determine the version of the last successful deployment.
#---------------------------------------------------------------------------------------------
function LatestVersionDeployed {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BranchName,           # The name of the branch being deployed (used for context).
        [Parameter(Mandatory=$True)]
        [string]$targetConnectionString, # The connection string for the target database.
        [Parameter(Mandatory=$True)]
        [string]$flywayHistoryTable,   # The name of the Flyway schema history table.
        [Parameter(Mandatory=$False)]
        [string]$releaseHash,          # A hash or identifier for the release.
        [Parameter(Mandatory=$False)]
        $dataOrSchemaDeploy            # An integer (1 or 2) to distinguish between schema and data deploys.
    )

    $Connection = $null # Initialize the connection variable.
    try {
        # Determine the type of deployment for logging purposes.
        $deployType = if ($dataOrSchemaDeploy -eq 2) { "data deploy or redeploy" } else { "schema deploy" }
        Write-Host "It's a $deployType, getting the ${deployType}-specific version"
        
        # Construct the SQL query to find the Nth latest version from the history table.
        # This uses ROW_NUMBER() to rank deployments by their installed_rank.
        # $dataOrSchemaDeploy determines which rank to select (1 for latest schema, 2 for latest data).
        $CommandText = @"
        IF (OBJECT_ID('[dbo].[$flywayHistoryTable]') IS NOT NULL) 
        BEGIN 
            WITH OrderedDeploys AS (
                SELECT [version], [installed_by], 
                       ROW_NUMBER() OVER(ORDER BY installed_rank DESC) AS 'RowNum' 
                FROM [dbo].[$flywayHistoryTable] 
                WHERE [version] IS NOT NULL
            )
            SELECT [version], [installed_by] 
            FROM OrderedDeploys 
            WHERE RowNum = $dataOrSchemaDeploy
        END
"@

        # Establish a connection to the SQL database.
        $Connection = New-Object System.Data.SQLClient.SQLConnection
        $Connection.ConnectionString = $targetConnectionString
        $Connection.Open()
        
        # Create and configure the SQL command object.
        $Command = New-Object System.Data.SQLClient.SQLCommand
        $Command.Connection = $Connection
        $Command.CommandText = $CommandText
        
        # Use a SqlDataAdapter to execute the command and fill a DataSet.
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $SqlAdapter.SelectCommand = $Command
        $DataSet = New-Object System.Data.DataSet
        $SqlAdapter.Fill($DataSet) | Out-Null

        # Logic to determine which column represents the version.
        # 'dbroot' indicates a baseline migration, so the 'version' column is used.
        # Otherwise, the 'installed_by' column (often used for release identifiers) is used.
        $LastVersion = if ($releaseHash -eq 'dbroot' -or $DataSet.Tables[0].Rows[0]["installed_by"] -eq 'dbroot') {
            $DataSet.Tables[0].Rows[0]["version"]
        } else {
            $DataSet.Tables[0].Rows[0]["installed_by"]
        }

        # Return the found version.
        return $LastVersion
    }
    catch {
        # Re-throw any exceptions.
        throw
    }
    finally {
        # Ensure the database connection is always closed, even if errors occur.
        if ($Connection) { $Connection.Close() }
    }
}