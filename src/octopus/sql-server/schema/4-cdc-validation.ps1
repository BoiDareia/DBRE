<#
.SYNOPSIS
    Refreshes Change Data Capture (CDC) for modified tables in a database.

.DESCRIPTION
    This script is designed to be run as a step in an Octopus Deploy process. Its primary function is to call a
    helper function, `RefreshCDC`, which contains the logic to identify and force a CDC refresh on database tables
    that may have missed the standard CDC process.

    It securely retrieves the necessary database credentials from AWS Secrets Manager using credentials
    passed from a previous "AWS Assume Role" step.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - AWS CLI to be installed on the Octopus worker.
                 - The `DeployDatabaseVersionsOctopus.ps1` script, containing the `RefreshCDC` function, must be
                   available in the working directory.
#>

#================================================================================
# 1. INITIALIZATION & SCRIPT DEPENDENCIES
#================================================================================
Write-Host "--- Initializing CDC Refresh Script ---"
$ErrorActionPreference = 'Stop'

# Set the working directory where the script and its dependencies are located.
Set-Location "C:\src\Database-deployment\SQLSchema"

# Source the required PowerShell module/function library.
. .\DeployDatabaseVersionsOctopus.ps1

#================================================================================
# 2. LOAD OCTOPUS & ENVIRONMENT VARIABLES
#================================================================================
Write-Host "--- Loading Octopus & Environment Variables ---"

# --- AWS Credentials (from a previous Assume Role step) ---
$env:AWS_ACCESS_KEY_ID = $OctopusParameters["Octopus.Action[AWS Assume Role].Output.AWS_ACCESS_KEY_ID"]
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters["Octopus.Action[AWS Assume Role].Output.AWS_SECRET_ACCESS_KEY"]
$env:AWS_SESSION_TOKEN = $OctopusParameters["Octopus.Action[AWS Assume Role].Output.AWS_SESSION_TOKEN"]

# --- Deployment Parameters (from a previous validation step) ---
$awsSecretId = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.SECRET_ID"]
$awsRegion = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.AWSREGION"]
$configFile = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.CONFIGFILE"]
$environmentName = $OctopusParameters["SELECT_ENVIRONMENT"] # Assuming this is a project-level variable

#================================================================================
# 3. FETCH DATABASE CREDENTIALS
#================================================================================
Write-Host "--- Fetching Database Credentials from AWS Secrets Manager ---"

try {
    $secretValueJson = (aws secretsmanager get-secret-value --secret-id $awsSecretId --region $awsRegion --query SecretString --output text) | ConvertFrom-Json
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
# 4. EXECUTE CDC REFRESH
#================================================================================
Write-Host "--- Executing CDC Refresh Logic ---"
$exitCode = 0

try {
    # Call the main function from the sourced script, passing the required parameters.
    # This function is expected to contain the core logic for checking and refreshing CDC.
    RefreshCDC -configFile $configFile -env $environmentName -credentials $credentials
    
    Write-Host "CDC Refresh process completed successfully."
}
catch {
    # Catch any terminating errors from the RefreshCDC function.
    $errorMessage = "Refresh CDC step failed: '$($_.Exception.Message)'"
    if ($_.Exception.InnerException) {
        $errorMessage += " | Inner Exception: '$($_.Exception.InnerException.Message)'"
    }
    
    Write-Error $errorMessage
    $exitCode = 1
}
finally {
    # The finally block ensures the script exits with the correct code.
    Write-Host "Script finished. Exiting with code: $exitCode"
    exit $exitCode
}
