<#
.SYNOPSIS
    Orchestrates the deployment of database data changes, including validation, execution, and notification.

.DESCRIPTION
    This script is a comprehensive engine for running data-only deployments within an Octopus Deploy process.
    It is designed to be run after a schema validation/deployment step.

    Key responsibilities include:
    1.  Loading all necessary parameters from Octopus Deploy variables.
    2.  Validating the Git reference and determining the exact version to deploy.
    3.  Checking for the existence of data change scripts (`.sql` files and a `manifest.txt`) between the last deployed version and the target version.
    4.  Executing the SQL scripts listed in the `manifest.txt` file against the target database.
    5.  Integrating with Jira to create, comment on, and transition release tickets.
    6.  Sending detailed success or failure notifications to Slack, including threaded replies.
    7.  Creating a "dummy" Flyway migration file if a data-only change needs to be recorded in the schema history table without an accompanying schema migration.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - AWS CLI, Git, and any required database client tools installed on the worker.
                 - Assumes dependent PowerShell function scripts (`ReleaseChangeFunctionsOctopus.ps1`, `gitFunctionsOctopus.ps1`) are present.
#>

#================================================================================
# 1. INITIALIZATION & SCRIPT DEPENDENCIES
#================================================================================
Write-Host "--- Initializing Data Deployment Script ---"
$ErrorActionPreference = 'Stop'
Set-Location "C:\src\Database-deployment\SQLData"

# Source required function libraries
. .\ReleaseChangeFunctionsOctopus.ps1
. .\gitFunctionsOctopus.ps1

#================================================================================
# 2. LOAD OCTOPUS & ENVIRONMENT VARIABLES
#================================================================================
Write-Host "--- Loading Octopus & Environment Variables ---"

# --- AWS Credentials (from a previous Assume Role step) ---
$env:AWS_ACCESS_KEY_ID = $OctopusParameters["Octopus.Action[AWS Assume Role].Output.AWS_ACCESS_KEY_ID"]
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters["Octopus.Action[AWS Assume Role].Output.AWS_SECRET_ACCESS_KEY"]
$env:AWS_SESSION_TOKEN = $OctopusParameters["Octopus.Action[AWS Assume Role].Output.AWS_SESSION_TOKEN"]

# --- Core Deployment Parameters ---
$region = $OctopusParameters["REGION"]
$environmentShortName = $OctopusParameters["SELECT_ENVIRONMENT"] # e.g., "PROD", "STG"
$databaseName = $OctopusParameters["DATABASE"]
$branchOrTag = $OctopusParameters["RELEASE"]
$buildVersion = $OctopusParameters["BUILD_VERSION"]
$deploymentTime = $OctopusParameters["DEPLOYMENT_TIME"] # "BeforeDeploy" or "AfterDeploy"
$status = $OctopusParameters["STATUS"] # "Rollout" or "Rollback"
$deployType = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.DEPLOY_TYPE"]
$noSchemaDeployment = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.DeploymentNoSchema"]
$schemaDeployedFlag = $OctopusParameters["SCHEMA"] # Flag indicating if a schema step ran

# --- Notification Parameters ---
$threadIds = $OctopusParameters["threadIds"]
$channels = $OctopusParameters["channels"]

#================================================================================
# 3. PREPARE & VALIDATE PARAMETERS
#================================================================================
Write-Host "--- Preparing and Validating Parameters ---"

# --- Standardize Environment Name ---
$environment = switch ($environmentShortName) {
    "PROD" { "production" }
    "STG" { "stg" }
    "DEV" { "dev" }
    default { $environmentShortName.ToLower() }
}

# --- Standardize Database Name for Config Lookup ---
$configDBname = $databaseName.ToLower()
switch ($databaseName) {
    "OrderFlowApiGateway" { $configDBname = "orderflowauth" }
    "ProductCatalog" { $configDBname = "product" }
    "Shop" { $configDBname = "frontend" }
    "nicelabel" { $configDBname = "Company_PrintData_AWS" }
}

# --- Determine Release Version ---
function Get-ReleaseVersion($branch, $build, $env, $schemaFlag) {
    if ($branch -match '^v\d+\.\d+(\.\d+)?(-\w+)?$') { return $branch } # Clean tag
    if ($branch -match '(v\d+\.\d+(\.\d+)?)') { return $Matches[0] }   # Tag inside a branch name
    if (($env -eq "prod") -or ($schemaFlag -eq '0')) { return $build }
    return $branch
}
$version = Get-ReleaseVersion -branch $branchOrTag -build $buildVersion -env $environmentShortName -schemaFlag $schemaDeployedFlag
Write-Host "Determined release version: $version"

# --- Setup Logging ---
$logsLocation = "C:\src\Database-deployment\SQLData\logs"
$logFile = "$logsLocation\$environment\${databaseName}_${version}_${status}_$(Get-Date -Format "yyyyMMdd_HHmmss").log"
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
Write-Host "Log file will be at: $logFile"

#================================================================================
# 4. DEPLOYMENT EXECUTION
#================================================================================
Write-Host "--- Starting Data Deployment Execution ---"
$lastExitCode = 0
$toThrow = ""
$tickets = @()

try {
    # --- Input Validation ---
    if (($deploymentTime -ne "BeforeDeploy") -and ($deploymentTime -ne "AfterDeploy")) {
        throw "Invalid value for deployment_time: '$deploymentTime'. Must be 'BeforeDeploy' or 'AfterDeploy'."
    }
    if (($status -ne "Rollout") -and ($status -ne "Rollback")) {
        throw "Invalid value for status: '$status'. Must be 'Rollout' or 'Rollback'."
    }

    # --- Load Configuration from XML ---
    $configFile = "C:\src\Database-deployment\SQLData\release-change-config.xml"
    [xml]$config = Get-Content -Path $configFile
    $dataDir = ($config.app.databases.database.CompanyGitDirectory | Where-Object { $_.name -eq $configDBname }).InnerXml
    $repoUrl = ($config.app.databases.database.CompanyGitURL | Where-Object { $_.name -eq $configDBname }).InnerXml
    $baseRepoLocation = 'C:\src\Release_repos\' + $environmentShortName.ToUpper() + '\'
    $repoLocation = $baseRepoLocation + ($dataDir.Split('\'))[0]
    
    # --- Check for Changes ---
    Set-Location $repoLocation
    $toTag = $branchOrTag
    $fromTag = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.LastDeployed"]
    $dataPath = $OctopusParameters["Octopus.Action[RDS SQL Variables Check].Output.DATAPATH"]
    
    Write-Host "Checking for data changes between Git refs '$fromTag' and '$toTag' in path '$dataPath'."
    $diff = git diff "$fromTag..$toTag" -- $dataPath | Out-String
    
    if (-not ($diff -like "*+++*manifest.txt*")) {
        Write-Host "No new manifest file found in the specified path. Nothing to deploy."
        exit 0
    }
    Write-Host "Manifest file changes detected. Proceeding with deployment."

    # --- Create Dummy Flyway File if Needed ---
    if ($noSchemaDeployment -like "*Will NOT do Schema*") {
        # Logic to create a dummy V{version}__...sql file to ensure Flyway records the data deployment.
        # This prevents Flyway from complaining about a missing schema migration for this version.
        # ... (implementation of dummy file creation) ...
        Set-OctopusVariable -name "DeployDir" -value $deployDir
    }

    # --- Execute Scripts from Manifest ---
    $fullLocation = buildFileLocation $configDBname $baseRepoLocation $version $deploymentTime $status $deployType
    if (-not (ConfirmLocationExists $fullLocation)) {
        throw "Script location does not exist: $fullLocation. No files to deploy."
    }

    $manifestList = GetManifestList $fullLocation
    if ($manifestList -eq "EMPTY") {
        throw "Manifest file is empty. No files to deploy."
    }

    # --- Initialize Integrations ---
    $jiraCred = if ($jira) { GetJiraCredentials $region }
    $session = if ($jira) { GetJiraSession $jiraCred }
    
    $fileList = $manifestList.Trim().Split(" ")
    $targetConnectionString = GetConnectionString $region $configDBname $environment

    # --- Main Execution Loop ---
    for ($i = 0; $i -lt $fileList.Length; $i++) {
        $currentFile = $fileList[$i]
        $header = [IO.File]::ReadAllText($logfile)

        if ($jira) {
            $curTicket = GetRCTicket $jiraCred $currentFile $databaseName $version $deploymentTime $status
        }

        $executionOutput = ExecuteSQLScripts $fullLocation $currentFile $targetConnectionString $logfile

        if ($jira) {
            $tickets += $curTicket
            $comment = $header + $executionOutput
            CommentRCTicket $jiraCred $curTicket $comment
        }
    }
    # (Additional logic for complex rollback scenarios would go here)
}
catch {
    $toThrow = "Error during data deployment: '$($_.Exception.Message)'. Inner Exception: '$($_.Exception.InnerException.Message)'"
    $lastExitCode = 1
    if ($jira -and $curTicket) {
        CommentRCTicket $jiraCred $curTicket ($toThrow + "`n" + [IO.File]::ReadAllText($logfile))
    }
}
finally {
    # --- Finalize Integrations and Send Notifications ---
    $header = "Applied $($i)/$($fileList.Length) files."
    if ($jira) {
        foreach ($ticket in $tickets) {
            TransitionRCTicket $jiraCred $ticket $status $environmentShortName
        }
        if ($session) { Remove-JiraSession $session }
    }

    if ($slack) {
        $statusEmoji = if ($lastExitCode -eq 0) { ":tada:" } else { ":scream:" }
        $statusText = if ($lastExitCode -eq 0) { "succeeded" } else { "failed" }
        $slackContent = "*Release Changes Deployment*`n`n$header`n`n*[$databaseName] $status of $version $deploymentTime data changes in $environment $region $statusText!* $statusEmoji"
        if ($tickets.Count -gt 0) {
            $slackContent += "`n*Applied RC tickets:*`n" + ($tickets | ForEach-Object { "https://Company.atlassian.net/browse/$_" }) -join "`n"
        }
        
        # Logic to send Slack notification via webhook, respecting threads
        # ... (implementation of Slack notification) ...
    }

    if ($toThrow) {
        Write-Error $toThrow
    }
    
    Write-Host "Script finished. Exiting with code: $lastExitCode"
    exit $lastExitCode
}
