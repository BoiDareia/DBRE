<#
.SYNOPSIS
    Builds and deploys database changes as part of a CI/CD process, orchestrated by Octopus Deploy.

.DESCRIPTION
    This script is designed to run on a build agent (like a Jenkins slave) as a step in an Octopus Deploy process.
    It orchestrates the entire database deployment workflow by calling a series of helper functions. Its main responsibilities include:
    1.  Initializing the environment and sourcing required function libraries.
    2.  Retrieving necessary credentials (AWS for secrets, Git for source code) from Octopus variables.
    3.  Determining the correct Git branch, tag, or commit hash to deploy.
    4.  Fetching the database connection password securely from AWS Secrets Manager.
    5.  Calling a master function (`DeployDatabaseVersion`) which encapsulates the core logic of checking out code, building the database project (e.g., DACPAC), and running migrations (e.g., Flyway).
    6.  Capturing the final status (success or failure) and setting an Octopus output variable.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - AWS CLI, Git, and any database build tools (e.g., MSBuild) installed on the worker.
                 - Assumes dependent PowerShell function scripts (`GitFunctionsOctopus.ps1`, `DacPacFunctionsOctopus.ps1`, etc.) are present in the working directory.
#>

#================================================================================
# 1. INITIALIZATION & SCRIPT DEPENDENCIES
#================================================================================
Write-Host "--- Initializing Database Build and Deploy Script ---"
$ErrorActionPreference = 'Stop'

# Set the working directory where the script and its dependencies are located.
Set-Location "C:\src\Database-deployment\SQLSchema"

# Source the required PowerShell modules/function libraries.
. .\GitFunctionsOctopus.ps1
. .\DacPacFunctionsOctopus.ps1
. .\FlywayFunctionsOctopus.ps1
. .\DeployDatabaseVersionsOctopus.ps1

#================================================================================
# 2. LOAD OCTOPUS & ENVIRONMENT VARIABLES
#================================================================================
Write-Host "--- Loading Octopus & Environment Variables ---"

# --- AWS Credentials (from a previous Assume Role step) ---
$env:AWS_ACCESS_KEY_ID = $OctopusParameters['Step.AWS_ACCESS_KEY_ID']
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters['Step.AWS_SECRET_ACCESS_KEY']
$env:AWS_SESSION_TOKEN = $OctopusParameters['Step.AWS_SESSION_TOKEN']

# --- Octopus Credentials (for interacting with the Octopus API if needed) ---
$env:OCTOPUS_URL = $OctopusParameters['Step.OCTOPUS_URL']
$env:OCTOPUS_API_KEY = $OctopusParameters['Step.OCTOPUS_API_KEY']

# --- Core Deployment Parameters from Octopus ---
$awsSecretId = $OctopusParameters['Step.SECRET_ID']
$awsRegion = $OctopusParameters['Step.REGION']
$gitUsername = $OctopusParameters['Step.GIT_USERNAME']
$gitPassword = $OctopusParameters['Step.GIT_PASSWORD']
$configFile = $OctopusParameters['Step.CONFIG_FILE']
$environmentName = $OctopusParameters['Step.ENV']
$databaseSchemaName = $OctopusParameters['Step.DATABASE']
$rootCheckoutPath = $OctopusParameters['Step.PATH']
$deployType = $OctopusParameters['Step.DEPLOY_TYPE'] # Assumed to be 'trunkBase' or 'tagBased'
$branchOrTag = $OctopusParameters['RELEASE']
$buildVersion = $OctopusParameters['BUILD_VERSION']

# Remap the checkout path to an environment-specific folder to avoid collisions.
$checkoutPath = $rootCheckoutPath.Replace('C:\src\', "C:\src\Release_repos\$($environmentName.ToUpper())\")

#================================================================================
# 3. FETCH DATABASE CREDENTIALS
#================================================================================
Write-Host "--- Fetching Database Credentials from AWS Secrets Manager ---"

try {
    $secretValueJson = aws secretsmanager get-secret-value --secret-id $awsSecretId --region $awsRegion --query SecretString --output text | ConvertFrom-Json
    $dbUsername = $secretValueJson.username
    $dbSecurePassword = ConvertTo-SecureString $secretValueJson.password -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential($dbUsername, $dbSecurePassword)
    Write-Host "Successfully retrieved credentials for user '$dbUsername'."
}
catch {
    Write-Error "Failed to retrieve credentials from AWS Secrets Manager. Secret ID: '$awsSecretId'. Region: '$awsRegion'."
    Write-Error $_.Exception.Message
    exit 1
}

#================================================================================
# 4. DEPLOYMENT EXECUTION
#================================================================================
Write-Host "--- Starting Database Deployment Process ---"
$finalStatusMessage = ""
$exitCode = 0

try {
    # --- Determine Git Reference Type (Tag vs. Branch/Commit) ---
    # This logic determines if a `git checkout` should treat the reference as a tag.
    $isTag = $false
    if ($branchOrTag -match '^v\d+\.\d+' -or $deployType -eq 'trunkBase') {
        $isTag = $true
    }
    Write-Host "Deploying from Git reference: '$branchOrTag'. Is Tag: $isTag."

    # --- Determine Release Identifier ---
    # This logic extracts a clean version number for logging and naming purposes.
    $releaseIdentifier = $branchOrTag
    if ($branchOrTag -notmatch '^v\d+\.\d+') {
        if ($branchOrTag -match '(v\d+\.\d+(\.\d+)?)') {
            $releaseIdentifier = $Matches[0]
        } elseif ($deployType -eq 'trunkBase') {
            $releaseIdentifier = $buildVersion # For trunk-based, the build number is the unique identifier
        }
    }
    Write-Host "Using release identifier: '$releaseIdentifier'."

    # --- Prepare Log File ---
    $logDir = "$PWD\Transcripts"
    New-Item -ItemType Directory -Path $logDir -Force
    $logFileName = "{0}_{1}_{2}_{3}_DBDeploy_{4}.log" -f $databaseSchemaName, $environmentName, $awsRegion, $releaseIdentifier, (Get-Date -Format "yyyyMMdd_HHmmss")
    $logFile = Join-Path -Path $logDir -ChildPath $logFileName
    Write-Host "Deployment log will be saved to: $logFile"

    # --- Call the Main Deployment Function ---
    # This function is expected to be in one of the sourced .ps1 files and should contain
    # the logic for git checkout, dacpac build, flyway migrate, etc.
    $isContinuousDelivery = $false # This seems to be a static flag in the original script.
    
    Write-Host "Invoking DeployDatabaseVersion function..."
    $deploymentOutput = DeployDatabaseVersion -configFile $configFile -env $environmentName -credentials $credentials -BranchName $branchOrTag -release $releaseIdentifier -CheckoutPath $checkoutPath -IsTag $isTag -isContinuousDelivery $isContinuousDelivery -logfile $logFile -GitUsername $gitUsername -GitPassword $gitPassword
    
    # Assuming the function returns a success message or throws an error.
    $finalStatusMessage = "SUCCEEDED!! Output: $deploymentOutput"
    $exitCode = 0
}
catch {
    # Catch any terminating errors from the try block.
    $errorMessage = "FAILED!! Reason: '$($_.Exception.Message)'"
    $finalStatusMessage = $errorMessage
    $exitCode = 1
}
finally {
    # This block will always run, ensuring the final status is logged and set in Octopus.
    Write-Host "--- Finalizing Deployment Step ---"
    
    if ($finalStatusMessage) {
        Write-Host $finalStatusMessage
        # Append the final status to the log file.
        if ($logFile -and (Test-Path $logFile)) {
            $finalStatusMessage | Out-File -FilePath $logFile -Append
        }
        # Set an Octopus output variable with the final status.
        Set-OctopusVariable -name "COMPLETED" -value $finalStatusMessage
    }
    
    Write-Host "Exiting with code: $exitCode"
    exit $exitCode
}
