<#
.SYNOPSIS
    A comprehensive script for Octopus Deploy to manage and validate database schema and data deployments.

.DESCRIPTION
    This script is the core logic for a database deployment step in Octopus Deploy. It performs the following key actions:
    1.  Loads deployment configuration from a region-specific XML file.
    2.  Determines the release version or commit hash from the branch/tag variable.
    3.  Checks out the correct version of the database code from a Git repository.
    4.  Retrieves database credentials securely from AWS Secrets Manager.
    5.  Compares the target Git version against the last deployed version in the database (read from the Flyway history table).
    6.  Detects if there are any actual schema or data changes (.sql files) between the two versions.
    7.  Sets Octopus output variables to control subsequent deployment steps (e.g., Flyway migrate). If no changes are detected, it sets a flag to cancel the deployment.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - AWS CLI installed on the Octopus worker.
                 - Git installed on the Octopus worker.
                 - Assumes dependent PowerShell function scripts (`GitFunctionsOctopus.ps1`, `DeployDatabaseVersionsOctopus.ps1`, `FlywayFunctionsOctopus.ps1`) are present.
#>

#================================================================================
# 1. INITIALIZATION & SCRIPT DEPENDENCIES
#================================================================================
Write-Host "--- Initializing Database Deployment Script ---"

# Set the working directory for the script execution.
Set-Location "C:\src\Database-deployment\SQLSchema"

# Source dependent function libraries.
. .\GitFunctionsOctopus.ps1
. .\DeployDatabaseVersionsOctopus.ps1
. .\FlywayFunctionsOctopus.ps1

#================================================================================
# 2. LOAD OCTOPUS & ENVIRONMENT VARIABLES
#================================================================================
Write-Host "--- Loading Octopus & Environment Variables ---"

# --- Input Variables from Octopus ---
$DatabaseName = $OctopusParameters["DATABASE"]
$Region = $OctopusParameters["REGION"]
$EnvironmentName = $OctopusParameters["SELECT_ENVIRONMENT"]
$BranchOrTag = $OctopusParameters["BRANCH_TAG"]
$BuildVersion = $OctopusParameters["STEP_BUILD_VERSION"] # Used for commit-based deploys
$IsRedeploy = [bool]$OctopusParameters["REDEPLOY"]
$DeploymentTime = $OctopusParameters["DEPLOYMENT_TIME"] # e.g., "BeforeDeploy", "AfterDeploy"
$DeploymentStatus = $OctopusParameters["STATUS"] # e.g., "Rollout", "Rollback"
$SchemaDeployedInPreviousStep = $OctopusParameters["SCHEMA"] # Flag to check if schema was already done

# --- AWS Credentials (from a previous Assume Role step) ---
$env:AWS_ACCESS_KEY_ID = $OctopusParameters['Step.AWS_ACCESS_KEY_ID']
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters['Step.AWS_SECRET_ACCESS_KEY']
$env:AWS_SESSION_TOKEN = $OctopusParameters['Step.AWS_SESSION_TOKEN']

# --- Static Configuration ---
$RootCheckoutPath = "C:\src"
$ConfigFileTemplate = 'C:\src\Database-deployment\SQLSchema\config\{0}_{1}_Release.xml' -f $DatabaseName, $Region

#================================================================================
# 3. CONFIGURATION FILE VALIDATION
#================================================================================
Write-Host "--- Validating Configuration File ---"
Write-Host "Looking for config file: $ConfigFileTemplate"

if (-not (Test-Path -Path $ConfigFileTemplate)) {
    Write-Host "Configuration file not found. This database does not exist for the '$Region' region." -ForegroundColor Red
    Set-OctopusVariable -name "DeploymentCancelled" -value "Configuration file not found for database '$DatabaseName' in region '$Region'."
    exit 0 # Exit gracefully so Octopus can proceed based on the variable.
}

Write-Host "Configuration file exists. Proceeding with deployment validation."
Set-OctopusVariable -name "Deployment" -value "Will deploy $DatabaseName in $Region on $EnvironmentName"

#================================================================================
# 4. LOAD DEPLOYMENT SETTINGS FROM CONFIG
#================================================================================
Write-Host "--- Loading Deployment Settings from Config ---"
$config = LoadEnvironmentDetails $ConfigFileTemplate

# Find the correct environment settings within the XML config.
$environmentConfig = $config.app.environments.environment | Where-Object { $_.name -match $EnvironmentName } | Select-Object -First 1

if (-not $environmentConfig) {
    Write-Error "Could not find environment details for '$EnvironmentName' in the configuration file."
    exit 1
}

# --- Extract Global and Environment-Specific Settings ---
$GitRepoUrl = $config.app.global.CompanyGitURL
$DbSchemaPath = $config.app.global.DBPath
$DbDataPath = $config.app.global.DataPath
$DeployType = $config.app.global.DeployType # e.g., "tagBased", "trunkBase"
$RootScriptsPath = $config.app.global.RootScriptsPath
$UseTransactions = $config.app.global.transaction
$FlywayHistoryTable = $config.app.global.schemaHistoryTable

$AwsSecretId = $environmentConfig.connection.AWSSecretId
$AwsRegion = $config.app.global.AWSRegion
$DatabaseUrl = $environmentConfig.connection.url

# Set Octopus variables for subsequent steps (e.g., Flyway)
Set-OctopusVariable -name "DEPLOY_TYPE" -value $DeployType
Set-OctopusVariable -name "SECRET_ID" -value $AwsSecretId
Set-OctopusVariable -name "AWSREGION" -value $AwsRegion

#================================================================================
# 5. DETERMINE RELEASE VERSION & CHECKOUT CODE
#================================================================================
Write-Host "--- Determining Release Version & Checking Out Code ---"

# Complex logic to parse a clean version/tag/hash from the input branch variable.
# This handles formats like 'v1.2.3', 'feature/v1.2.3', 'v1.2.3-rc1', or a commit hash.
function Get-ReleaseIdentifier($branch, $buildVersion, $environment) {
    if ($branch -match '^v\d+\.\d+(\.\d+)?(-\w+)?$') { return $branch } # Clean tag
    if ($branch -match '(v\d+\.\d+(\.\d+)?)') { return $Matches[0] } # Tag inside a branch name
    # For trunk-based, non-prod uses the branch name (commit hash), prod uses the build version.
    if ($environment -eq "prod") { return $buildVersion }
    return $branch
}

$releaseIdentifier = Get-ReleaseIdentifier -branch $BranchOrTag -buildVersion $BuildVersion -environment $EnvironmentName
$commitHash = if ($DeployType -eq "trunkBase") { $releaseIdentifier } else { $releaseIdentifier }

Write-Host "Deploying from Git reference: $releaseIdentifier"

# --- Git Checkout ---
$gitCheckoutPath = Join-Path -Path "C:\src\Release_repos\$($EnvironmentName.ToUpper())" -ChildPath "YourRepoName" # Adjust repo name
$gitUsername = $OctopusParameters['GIT_USER']
$gitPassword = $OctopusParameters['GIT_TOKEN']
$isTag = ($releaseIdentifier -match '^v\d+\.\d+')

# Create a log file for Git operations
$logDir = "$PWD\Transcripts"
New-Item -ItemType Directory -Path $logDir -Force
$logFile = Join-Path -Path $logDir -ChildPath "$($DatabaseName)_$($EnvironmentName)_GitLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-Host "Checking out code to: $gitCheckoutPath"
GitCheckoutBranch $gitCheckoutPath $GitRepoUrl $commitHash $isTag $False $logFile $gitUsername $gitPassword

#================================================================================
# 6. FETCH DATABASE CREDENTIALS & CONNECTION INFO
#================================================================================
Write-Host "--- Fetching Database Credentials ---"

$secretJson = aws secretsmanager get-secret-value --secret-id $AwsSecretId --region $AwsRegion --query SecretString --output text | ConvertFrom-Json
$dbUsername = $secretJson.username
$dbPassword = $secretJson.password
$securePassword = ConvertTo-SecureString $dbPassword -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($dbUsername, $securePassword)

# --- Prepare Flyway Connection Details ---
# Handle special characters in password for Flyway CLI
$flywayPassword = if ($dbPassword.Contains("&")) { $dbPassword.Replace("&", """&""") } else { $dbPassword }
$flywayUrl = "$($DatabaseUrl);trustServerCertificate=true"
Set-OctopusVariable -name "URL" -value $flywayUrl
Set-OctopusVariable -name "User" -value $dbUsername
Set-OctopusVariable -name "Pass" -value $flywayPassword

# --- Build DACPAC Connection String ---
$dataSource = ($DatabaseUrl -split '//' | Select-Object -Last 1) -split ':' | Select-Object -First 1
$dbNameFromUrl = ($DatabaseUrl -split 'databaseName=' | Select-Object -Last 1)
$targetConnectionString = GetConnectionString $dataSource $credentials $dbNameFromUrl

#================================================================================
# 7. DETERMINE LAST DEPLOYED VERSION
#================================================================================
Write-Host "--- Determining Last Deployed Version from Database ---"
$projectName = $OctopusParameters['Octopus.Project.Name']

# If it's a data-only deploy or a redeploy, get the second-to-last version. Otherwise, get the latest.
$historyIndex = if (($projectName -like "*Data*") -or $IsRedeploy) { 2 } else { 1 }
$lastDeployedVersion = LatestVersionDeployed $BranchOrTag $targetConnectionString $FlywayHistoryTable $commitHash $historyIndex
Write-Host "Last deployed version found in database: $lastDeployedVersion"

# Parse a clean version number from the history string
$fromTag = if ($lastDeployedVersion -match '(\d+\.\d+(\.\d+)?)') { "v$($Matches[0])" } else { $lastDeployedVersion }
Write-Host "Using '$fromTag' as the base for comparison."

#================================================================================
# 8. CHECK FOR DATABASE CHANGES
#================================================================================
Write-Host "--- Checking for Changes Between '$fromTag' and '$releaseIdentifier' ---"
$toTag = $releaseIdentifier

if ($toTag -like "*$fromTag*") {
    Write-Host "Target version '$toTag' seems to contain or be the same as the last deployed version '$fromTag'. No deployment needed." -ForegroundColor Yellow
    Set-OctopusVariable -name "DeploymentCancelled" -value "The target version has already been deployed."
} else {
    # Define paths for git diff
    $fullSchemaPath = Join-Path -Path $gitCheckoutPath -ChildPath $DbSchemaPath
    $fullDataPath = Join-Path -Path $gitCheckoutPath -ChildPath (Join-Path -Path $DbDataPath -ChildPath (Join-Path -Path $DeploymentTime -ChildPath $DeploymentStatus))
    $genericDataPath = Join-Path -Path $gitCheckoutPath -ChildPath $DbDataPath

    Write-Host "Schema Path: $fullSchemaPath"
    Write-Host "Data Path: $fullDataPath"

    # Check for schema changes (excluding data folder and project files)
    $schemaChanges = git diff "$fromTag..$toTag" -- $fullSchemaPath ":(exclude)$genericDataPath" ":(exclude)*.sqlproj" | Out-String
    $hasSchemaChanges = $schemaChanges -like "*+++*"

    # Check for data changes (looking for .sql files and manifest.txt)
    $dataChanges = git diff "$fromTag..$toTag" -- $fullDataPath | Out-String
    $hasDataChanges = ($dataChanges -like "*+++*") -and ($dataChanges -like "*manifest.txt*")

    # --- Deployment Decision Logic ---
    $willDeploySchema = $false
    $willDeployData = $false

    if ($projectName -like "*Data*") {
        # Data-only project
        if ($hasDataChanges) {
            $willDeployData = $true
            # If schema wasn't deployed in a prior step, we might need a placeholder schema version
            if ($SchemaDeployedInPreviousStep -eq '0') {
                Set-OctopusVariable -name "DeploymentNoSchema" -value "1"
            }
        }
    } else {
        # Combined schema/data project
        if ($hasSchemaChanges) { $willDeploySchema = $true }
        if ($hasDataChanges) { $willDeployData = $true }
    }

    # --- Set Final Octopus Variables ---
    if ($willDeploySchema) {
        Write-Host "Schema changes detected. Enabling schema deployment." -ForegroundColor Green
        Set-OctopusVariable -name "DeploymentSchema" -value "1"
    }
    if ($willDeployData) {
        Write-Host "Data changes with manifest detected. Enabling data deployment." -ForegroundColor Green
        Set-OctopusVariable -name "DeploymentData" -value "1"
    }

    if (-not $willDeploySchema -and -not $willDeployData) {
        Write-Host "No detectable schema or data changes found between the versions." -ForegroundColor Yellow
        Set-OctopusVariable -name "DeploymentCancelled" -value "No database changes detected between versions '$fromTag' and '$toTag'."
    }
}

#================================================================================
# 9. SET FINAL OUTPUT VARIABLES
#================================================================================
Write-Host "--- Setting Final Output Variables ---"
Set-OctopusVariable -name "DATAPATH" -value $fullDataPath
Set-OctopusVariable -name "LastDeployed" -value $fromTag
Set-OctopusVariable -name "ReleaseHash" -value $commitHash
Set-OctopusVariable -name "FW_TRAN" -value $UseTransactions
Set-OctopusVariable -name "ScriptsPath" -value $RootScriptsPath

Write-Host "Script completed."
