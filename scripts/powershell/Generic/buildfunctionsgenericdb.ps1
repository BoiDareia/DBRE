<#
.SYNOPSIS
A collection of helper functions designed for a generic database build and deployment process.
This script provides functions to create a database connection string and to execute a Python script
that generates deployment artifacts.
#>

# Sets the default error handling behavior for the script.
# 'Stop' ensures that any terminating error will halt execution and can be caught by a try/catch block.
$ErrorActionPreference = 'Stop'

Function GetConnectionString {
<#
.SYNOPSIS
    Constructs a formatted database connection string.
.PARAMETER dataSource
    The server name or IP address of the database server.
.PARAMETER credentials
    A PSCredential object containing the username and password for the database connection.
.PARAMETER database
    The name of the database to connect to.
.OUTPUTS
    System.String. A fully formatted connection string for a database connection (e.g., PostgreSQL, Redshift).
#>
    Param(
		[Parameter(Mandatory=$True)]
           [string]$dataSource,
        [Parameter(Mandatory=$True)]
           [System.Management.Automation.PSCredential]$credentials,
        [Parameter(Mandatory=$True)]
           [string]$database
    )
    try {
        # Display a status message to the console.
        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        Write-Host "Building Connection String" -ForegroundColor Cyan
        Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan  

        # Validate that the PSCredential object is not empty.
        if($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "Credentials are empty"
        }
        else{
            # Securely extract the plaintext password from the PSCredential object.
            $PlainPassword = $credentials.GetNetworkCredential().Password 
            # Extract the username from the PSCredential object.
            $userName = $credentials.UserName 
        }
    
        # Assemble and return the final connection string. Note the hardcoded port 5439.
        return "User=$userName;Password=$PlainPassword;Database=$database;Server=$dataSource;Port=5439;"
    }
    catch {
        # If an error occurs, prepare a custom error message to be thrown later.
        $toThrow = ('Failed to construct connection string: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally {
        # The 'finally' block always runs, regardless of whether an error occurred.
        # If the $toThrow variable was set in the 'catch' block, this throws the custom error, stopping the script.
        if ($toThrow) {
            Throw $toThrow
        }
    }
}

Function GenerateDeployScript {
<#
.SYNOPSIS
    Executes a Python build script to generate a deployment script or artifact.
.DESCRIPTION
    This function validates the Python environment, checks for the existence of the build script,
    temporarily adds Python to the PATH if needed, and then runs the specified Python script.
    It checks the exit code of the Python script to determine success or failure.
.PARAMETER pythonPath
    The file path to the Python installation directory.
.PARAMETER buildFile
    The name of the Python script to be executed (e.g., 'build.py').
.PARAMETER deployPath
    The path to the file or directory that the Python script is expected to create. This is used to verify success.
.PARAMETER filepath
    The base directory where the '_build' subfolder containing the Python script is located.
#>
    [CmdletBinding()]
    Param(
		[Parameter(Mandatory=$True)]
           [string]$pythonPath,
        [Parameter(Mandatory=$True)]
           [string]$buildFile,
        [Parameter(Mandatory=$True)]
           [string]$deployPath,
        [Parameter(Mandatory=$True)]
            [string]$filepath
    )

    # Check if a path to Python was provided.
    Write-Host 'Testing if Python was installed...' -ForegroundColor White
    Write-Host $pythonPath -ForegroundColor Cyan
    if (!$pythonPath) {
        throw 'No usable version of Python found.'
    }
    else {
        # This try/catch block is simple; its main purpose is to conform to the overall script structure.
        try {
            Write-Host 'Python found...' -ForegroundColor White
        }
        catch [System.Management.Automation.RuntimeException] {
            throw "Exception caught: " + $_.Exception.GetType().FullName
        }
    }
	
	# Construct the full path to the Python build script.
	$FullPath = $filepath + "_build\"+ $buildFile
	
    # Verify that the Python build script actually exists at the constructed path.
    if (Test-Path ($FullPath)) {
        Write-Host ('Loaded file ''{0}''.' -f ($FullPath)) -ForegroundColor White 
    }
    else {
        # If the file doesn't exist, throw an error.
        throw "$buildFile not found in $FullPath!" 
    }
    
    try {
        # Display a status message to the console.
        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        Write-Host "Generating Deploy Script ..." -ForegroundColor Cyan
        Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
		
		# Change the current working directory to the '_build' folder.
        # This is important so the Python script can use relative paths if needed.
		Set-Location "$($filepath)_build\"
		
		## Check if the Python directory is already in the system's PATH environment variable for this session.
        [string] $envVar = $env:PATH

        if  ($envVar -match [regex]::Escape($pythonPath)){
            Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Green
            Write-Host "Python is already in env:PATH!" -ForegroundColor Green
            Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Green
        }
        else {
            # If not, temporarily add it to the PATH for the current PowerShell session.
            # This allows calling 'py' or 'python' directly without specifying the full path.
            $env:PATH += "$pythonPath;"
        }
		
        ## Execute the Python script using the 'py' launcher and capture any standard output.
        $outputBox = py $FullPath

        # Check the exit code of the last command that was run.
        # An exit code of 0 universally means success. Any other number indicates an error.
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Python Deployed Successfully: $outputBox" -ForegroundColor Green
		
            # As a final verification, check if the expected deployment artifact was created.
            if (Test-Path $deployPath) {
                Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
                Write-Host "Generate DeployScript successful!" -ForegroundColor Green
                Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
            }
            else {
                # If the output file is missing, prepare a custom error message.
                $toThrow = ('Generate DeployScript failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
            }
        }
        else {
            # If the Python script returned a non-zero exit code, it failed.
            Write-Host "Python Error Manifest: $outputBox" -ForegroundColor Red
            $toThrow = ('Generate DeployScript failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
        }
    }  
    catch {
        # If any PowerShell error occurred during the 'try' block, prepare a custom error message.
        $toThrow = ('Generate DeployScript failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally {
        # The 'finally' block always runs. If any error was caught, throw it now to stop the script.
        if ($toThrow) {
            Throw $toThrow
        }
    }
}