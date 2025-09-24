<#
.SYNOPSIS
This script provides a collection of helper functions for a database deployment pipeline.
It includes functions for managing Git repositories (cloning, checking out branches),
handling file system operations (checking paths, reading manifest files), and directly
interacting with a Flyway schema history table in a database.
#>

<#
    # This block is a commented-out example for local testing and debugging.
    [string] $DeployLocation = "C:\src\Company\Deploy"
    [string] $RollbackLocation = "C:\src\Company\Rollback"
    [string] $DeployVersion = "V59.0"
    [string] $RollbackVersion = "V58.0"
    [string] $CompanyGitURL = "git@bitbucket.org:Company/de-redshift.git"
    [bool] $IsTag = $True

    GitCheckoutBranch $DeployLocation $CompanyGitURL $DeployVersion $IsTag
#>

# Sets the script's error handling to stop on any terminating error.
$ErrorActionPreference = 'Stop'

function GitCloneRemoteRepo(){
<#
.SYNOPSIS
    Clones a remote Git repository to a specified local directory.
#>
    [CmdletBinding()]
    Param(
		[Parameter(Mandatory=$True)]
           [string]$DeployLocation,
        [Parameter(Mandatory=$True)]
		   [string]$RemoteRepository
    )
    try{
        Set-Location $DeployLocation
        $myerrorstream = ""
        Write-Host "`nExecuting ""git clone" $RemoteRepository.ToString() "--quiet""" -ForegroundColor DarkYellow
        # Execute git clone and redirect the error stream (2) to the success stream (1) to capture it.
        $myerrorstream = & git clone --quiet $RemoteRepository.ToString() 2>&1

        # Check for non-terminating errors that git might produce.
        if(-not ([string]::IsNullOrEmpty($myerrorstream))) {					
            if($LASTEXITCODE -ne 0)	{ # An exit code other than 0 indicates an error.
                throw $myerrorstream
            }
            else {
                $myerrorstream # Write non-fatal warnings to the host.
            }
        }
    }
    catch{ throw }
}

function GitCheckoutBranch_TODELETE(){
<#
.SYNOPSIS
    DEPRECATED. This function is legacy and should not be used.
    Use the new `GitCheckoutBranch` function instead.
.DESCRIPTION
    This older version uses `Start-Job` to run git commands, which is more complex
    and has been replaced by more direct and efficient calls.
#>
    [CmdletBinding()]
    Param(
		[Parameter(Mandatory=$True)]
           [string]$CheckoutPath,
        [Parameter(Mandatory=$True)]
		   [string]$RemoteRepository,
        [Parameter(Mandatory=$True)]
           [string]$BranchName,
        [Parameter(Mandatory=$False)]
           [bool]$IsTag = $True,
           [Parameter(Mandatory=$False)]
              [string]$DeployType,
        [Parameter(Mandatory=$false)]
           [bool] $isContinuousDelivery = $False  
    )
    # ... Deprecated logic ...
}

function GitCheckoutBranch() {
<#
.SYNOPSIS
    Ensures a clean Git repository exists at a given path and checks out a specific branch or tag.
.DESCRIPTION
    This is the primary function for managing the source code. It will clone the repository if it
    doesn't exist locally. If it does exist, it will perform a hard reset to ensure the working
    directory is clean before checking out the desired branch or tag.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string]$CheckoutPath,
        [Parameter(Mandatory = $True)]
        [string]$RemoteRepository,
        [Parameter(Mandatory = $True)]
        [string]$BranchName,
        [Parameter(Mandatory = $False)]
        [bool]$IsTag = $True,
        [Parameter(Mandatory = $False)]
        [string]$DeployType,
        [Parameter(Mandatory = $False)]
        [bool]$isContinuousDelivery = $False
    )
    try {
        # Proactively create C:\tmp, as the version of bash included with Git for Windows
        # can sometimes produce warnings if this directory is missing.
        $tmpPath = "C:\tmp"
        if (-not (Test-Path -Path $tmpPath)) {
            Write-Host "Creating directory at $tmpPath for Git compatibility." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $tmpPath | Out-Null
        }

        [string]$CheckoutPathFull = $CheckoutPath
        if (-Not $CheckoutPathFull.EndsWith("\")) {
            $CheckoutPathFull += "\"
        }

        Write-Host "`nCheckout Path is:" $CheckoutPathFull.ToString() -ForegroundColor DarkYellow
        Write-Host "Remote Repository is:" $RemoteRepository.ToString() -ForegroundColor DarkYellow
        Write-Host "Branch to Checkout is:" $BranchName.ToString() -ForegroundColor DarkYellow

        Set-Location $CheckoutPathFull

        # Check if the current directory is a git repository.
        # `git rev-parse` returns 0 if it is, non-zero otherwise. Redirect error stream to null.
        git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            # If not a repo, clone it.
            Write-Host "`nCheckout location is not a GIT repository. Cloning" $RemoteRepository.ToString() "remote repo." -ForegroundColor Yellow
            GitCloneRemoteRepo $CheckoutPath $RemoteRepository
            Write-Host "`nSuccessfully cloned git repository" -ForegroundColor Green
        }
        else {
            # If it is a repo, clean the working directory to ensure a pristine state.
            Write-Host "`nCleaning existing repository..." -ForegroundColor Yellow
            git reset --hard HEAD       # Discard any local changes.
            git clean -f                # Delete any untracked files.
            git fetch origin --quiet    # Fetch the latest branches from the remote.
            git fetch --tags --force --quiet # Force an update to local tags.
        }

        # Sanitize the branch name by removing brackets and adding prefixes if needed.
        if ($BranchName.ToString() -match "\[") {
            $BranchName = $BranchName.ToString().Replace('[', '').Replace(']', '')
        }
        if ($BranchName.ToString().StartsWith("release/") -ne $true -and $DeployType -eq "releaseBranch") {
            $BranchName = "release/" + $BranchName.ToString()
        }

        # It's good practice to checkout and pull the main branch first to keep it up-to-date.
        Write-Host "`nChecking out and updating 'main' branch..." -ForegroundColor Cyan
        git checkout main --quiet
        git pull --quiet
        if ($LASTEXITCODE -ne 0) { throw "Failed to checkout or pull the 'main' branch." }
        Write-Host "`nSuccessfully checked out Main branch from Git" -ForegroundColor Green

        # Finally, checkout the target branch or tag for the deployment.
        Write-Host "`nChecking out target branch/tag '$BranchName'..." -ForegroundColor Cyan
        git checkout $BranchName --quiet
        if ($LASTEXITCODE -ne 0) { throw "Failed to checkout branch/tag '$BranchName'." }

        # If it is a branch (not a tag), pull the latest changes to ensure we have the newest code.
        if (-not $IsTag) {
            Write-Host "Pulling latest changes for branch '$BranchName'..." -ForegroundColor Cyan
            git pull --quiet
            if ($LASTEXITCODE -ne 0) { throw "Failed to pull changes for branch '$BranchName'." }
        }

        Write-Host "`nSuccessfully checked out branch/tag '$BranchName' from Git" -ForegroundColor Green
    }
    catch {
        # Re-throw the original exception to fail the script.
        throw $_.Exception
    }
}

Function ConfirmLocationExists {
<#
.SYNOPSIS
    A simple wrapper function to check if a file or directory path exists.
#>
    Param(
        [Parameter(Mandatory = $True)]
        [string] $path
    )
    try {
        return (Test-Path -Path $path)
    }
    catch {
        $toThrow = ('Failed to verify location: ''{0} {1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally {
        if ($toThrow) { Throw $toThrow }
    }
}

Function GetManifestList {
<#
.SYNOPSIS
    Finds the most recently modified manifest file in a directory and returns its contents.
.DESCRIPTION
    This supports a deployment model where a text file (`*manifest*.txt`) explicitly lists
    the SQL scripts that should be included in a migration.
#>
    Param(
        [Parameter(Mandatory = $True)]
        [string] $path
    )
    try {
        # Find the newest file matching the pattern '*manifest*.txt' in the specified path.
        $manifestFile = Get-ChildItem $path -Recurse -File -Filter '*manifest*.txt' | Sort-Object -Descending -Property LastWriteTime | Select -First 1
        
        if (-not $manifestFile) {
            Write-Host "No manifest files found in: $path" -ForegroundColor Yellow
            return "EMPTY" # Return a specific string to indicate no manifest was found.
        }
        else {
            Write-Host "Using Manifest File: $($manifestFile.FullName)" 
            # Read the content of the manifest file, which is a list of script filenames.
            $listOfFiles = Get-Content -Path $manifestFile.FullName
            foreach ($file in $listOfFiles) {
                Write-Host "File from manifest: $file"
            }
            return $listOfFiles
        }
    }
    catch {
        $toThrow = ('Issue With Manifest File: ''{0} {1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally {
        if ($toThrow) { Throw $toThrow }
    }
}

function LatestVersionDeployed{
<#
.SYNOPSIS
    Queries the Flyway schema history table to find the latest version that was deployed.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $BranchName,
        [Parameter(Mandatory=$True)]
            [string] $targetConnectionString,
        [Parameter(Mandatory=$True)]
            [string] $flywayHistoryTable,
        [Parameter(Mandatory=$False)]
            [string] $Engine 
    )
    try{
        # This block contains complex regex to parse a standard version string (e.g., v59.0)
        # from various possible Git branch or tag name formats.
        if ($BranchName -notmatch '^v\d+\.\d+\.\d+$' -and $BranchName -notmatch '^v\d+\.\d+$'){
            # ... regex logic ...
        }else{
            $version = $BranchName
        }

        # Construct a SQL query to get the latest version number from the history table.
        # The query is slightly different depending on the database engine.
        if ($Engine -eq "redshift" -or $Engine -eq "auroraPostgres" -or $Engine -eq "postgres" ) {
            [string] $CommandText = 'select version from public.' + $flywayHistoryTable.ToString() + ' WHERE type in (''SQL'',''BASELINE'') and version is NOT NULL ORDER BY installed_rank DESC LIMIT 1' 
        }
        # ... other engine types ...
        
        # Connect to the database via ODBC.
        $Connection = New-Object Data.Odbc.OdbcConnection
        $Connection.ConnectionString = "$targetConnectionString"
        $Connection.open()
        $ODBCCommand = New-Object Data.Odbc.OdbcCommand($CommandText, $Connection)
        
        # Execute the query and extract the version from the result set.
        $DataSet = New-Object system.Data.DataSet
        (New-Object system.Data.odbc.odbcDataAdapter($ODBCCommand)).fill($DataSet) | out-null
        $LatestDeployed = $DataSet.Tables[0].Rows[0]["version"]

        return $LatestDeployed 
    }
    catch{throw}
    finally{$Connection.Close()} # Ensure the connection is always closed.
}

function CleanDatabase{
<#
.SYNOPSIS
    Deletes entries for a specific version from the Flyway schema history table.
.DESCRIPTION
    This is a utility function used to clean up after a failed deployment or to
    prepare the database for a forced redeployment of an existing version.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $BranchName,
        [Parameter(Mandatory=$True)]
            [string] $targetConnectionString ,
        [Parameter(Mandatory=$True)]
            [string] $flywayHistoryTable,
        [Parameter(Mandatory=$False)]
            [string] $Engine,
        [Parameter(Mandatory=$False)]
            [string] $Redeploy = $False 
    )
    try{
        # ... (Identical regex block as LatestVersionDeployed to parse the version) ...

        # For redeploys, the check might be against the description column instead of the version.
        if ($Redeploy -eq $True){ $CheckColumn = 'description' }
        else { $CheckColumn = 'version' }

        # Construct the SQL DELETE command based on the engine type.
        if ($Engine -eq "redshift" -or $Engine -eq "auroraPostgres" -or $Engine -eq "postgres" ) {
            [string] $CommandText = 'delete from public.' + $flywayHistoryTable.ToString() + ' WHERE type in (''SQL'',''BASELINE'') and ' + $CheckColumn.ToString() + ' LIKE ''' + $version.ToString() + '%'' ' 
        }
        # ... other engine types ...
        
        # Connect to the database and execute the delete command.
        $Connection = New-Object Data.Odbc.OdbcConnection
        $Connection.ConnectionString = "$targetConnectionString"
        $Connection.open()
        $ODBCCommand = New-Object Data.Odbc.OdbcCommand($CommandText, $Connection)
        $rowsAffected = $ODBCCommand.ExecuteNonQuery()
        Write-Host "$rowsAffected rows deleted from $flywayHistoryTable."
    }
    catch{ throw }
    finally{ $Connection.Close() }
}

function CleanFiles($version, $ScriptsPath, $current) {
<#
.SYNOPSIS
    Deletes local SQL migration files from the filesystem that match a specific version.
.DESCRIPTION
    A cleanup utility to remove generated script files, often used after a failed deployment.
#>
    # Find all files in the path that contain the version string.
    $filesToDelete = Get-ChildItem -Path $ScriptsPath -File | Where-Object { $_.Name -like "*$version*" -and $_.Name -like "$current*" }
  
    if ($filesToDelete) {
      Write-Host "Deleting files:"
      foreach ($file in $filesToDelete) {
        Write-Host " - $($file.FullName)"
        Remove-Item -Path $file.FullName -Force
      }
    } else {
      Write-Host "No matching files to delete."
    }
}