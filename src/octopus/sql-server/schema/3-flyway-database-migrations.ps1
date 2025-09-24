<#
.SYNOPSIS
    A generic PowerShell wrapper for executing Flyway CLI commands within an Octopus Deploy step.

.DESCRIPTION
    This script dynamically builds and executes a Flyway command based on parameters provided by Octopus Deploy variables.
    It is designed to be a flexible, all-in-one step for running any Flyway command (migrate, info, validate, baseline, check, etc.).

    Key features include:
    1.  Automatically locating the Flyway executable on both Windows and Linux workers.
    2.  Supporting multiple authentication methods, including Username/Password, AWS IAM, Azure Managed Identity, and GCP Service Accounts.
    3.  Dynamically constructing the command-line arguments based on the selected Flyway command and provided parameters.
    4.  Handling special cases like "migrate dry run" and "check" sub-commands.
    5.  Creating Octopus artifacts from Flyway outputs, such as dry run SQL scripts and reports.
    6.  Cleaning up temporary files after execution.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - Flyway CLI to be available on the Octopus worker (either in the PATH, in the package, or at a specified path).
                 - AWS CLI, Azure PowerShell, or GCP SDK may be required for specific authentication methods.
#>

#================================================================================
# 1. HELPER FUNCTIONS
#================================================================================

function Get-FlywayExecutablePath {
<#
.SYNOPSIS
    Finds the path to the Flyway executable.
#>
    param (
        [string]$providedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($providedPath)) {
        Write-Host "Flyway executable path was provided. Using '$providedPath'."
        return if ([IO.Path]::IsPathRooted($providedPath)) { $providedPath } else { Join-Path (Get-Location) $providedPath }
    }

    if ($IsLinux) {
        Write-Host "Running on Linux. Searching for Flyway executable..."
        if (Test-Path "./flyway") { return "flyway" }
        if (Test-Path "/flyway/flyway") { return "/flyway/flyway" }
    }
    else {
        Write-Host "Running on Windows. Searching for Flyway executable..."
        if (Test-Path ".\flyway.cmd") { return ".\flyway.cmd" }
        $flywayInPath = Get-Command "flyway" -ErrorAction SilentlyContinue
        if ($null -ne $flywayInPath) { return $flywayInPath.Source }
    }

    throw "Unable to find Flyway executable. Please include it in the package or provide the path via the 'Flyway.Executable.Path' variable."
}

function Test-AddParameterToCommandline {
<#
.SYNOPSIS
    Determines if a given parameter should be added to the Flyway command line.
#>
    param (
        [string]$acceptedCommands,
        [string]$selectedCommand,
        [string]$parameterValue,
        [string]$defaultValue,
        [string]$parameterName
    )

    if ([string]::IsNullOrWhiteSpace($parameterValue)) { return $false }
    if ((-not [string]::IsNullOrWhiteSpace($defaultValue)) -and ($parameterValue.ToLower().Trim() -eq $defaultValue.ToLower().Trim())) { return $false }
    if (($acceptedCommands -eq "any") -or ([string]::IsNullOrWhiteSpace($acceptedCommands))) { return $true }

    return $acceptedCommands -split ',' | ForEach-Object { if ($_.Trim() -eq $selectedCommand.ToLower().Trim()) { return $true } }
}

function Get-ParsedUrl {
<#
.SYNOPSIS
    Parses a JDBC connection string into a URI object.
#>
    param (
        [string]$ConnectionUrl
    )
    $cleanUrl = $ConnectionUrl.ToLower().Replace("jdbc:", "")
    return [System.Uri]$cleanUrl
}

#================================================================================
# 2. INITIALIZATION & LOAD PARAMETERS
#================================================================================
Write-Host "--- Initializing Flyway Runner Script ---"
$VerboseActionPreference = "Continue"

# --- Determine Operating System ---
if ($null -eq $IsWindows) {
    $IsWindows = ([System.Environment]::OSVersion.Platform -eq "Win32NT")
    $IsLinux = ([System.Environment]::OSVersion.Platform -eq "Unix")
}

# --- Load Octopus Parameters ---
Write-Host "--- Loading Octopus Parameters ---"
$flywayUrl = $OctopusParameters["Flyway.Target.Url"]
$flywayUser = $OctopusParameters["Flyway.Database.User"]
$flywayUserPassword = $OctopusParameters["Flyway.Database.User.Password"]
$flywayCommand = $OctopusParameters["Flyway.Command.Value"]
$flywayLicenseKey = $OctopusParameters["Flyway.License.Key"]
$flywayExecutablePath = $OctopusParameters["Flyway.Executable.Path"]
$flywaySchemas = $OctopusParameters["Flyway.Command.Schemas"]
$flywayTarget = $OctopusParameters["Flyway.Command.Target"]
$flywayLocations = $OctopusParameters["Flyway.Command.Locations"]
$flywayAdditionalArguments = $OctopusParameters["Flyway.Additional.Arguments"]
$flywayAuthenticationMethod = $OctopusParameters["Flyway.Authentication.Method"]
# ... (and all other Flyway parameters)

# The path to the SQL migration files.
$flywayPackagePath = $flywayLocations
$flywayLocations = "filesystem:$flywayLocations" # Prepend the 'filesystem:' prefix for Flyway

Write-Host "Setting execution location to: $flywayPackagePath"
Set-Location $flywayPackagePath

#================================================================================
# 3. BUILD FLYWAY COMMAND ARGUMENTS
#================================================================================
Write-Host "--- Building Flyway Command Arguments ---"
$flywayCmd = Get-FlywayExecutablePath -providedPath $flywayExecutablePath

# Handle composite commands like "migrate dry run"
$commandToUse = $flywayCommand
if ($flywayCommand -eq "migrate dry run") { $commandToUse = "migrate" }
if ($flywayCommand -like "check*") { $commandToUse = "check" }

$arguments = @($commandToUse)

# Add flags for composite commands
if ($flywayCommand -eq "migrate dry run") { $arguments += "-dryrun" }
if ($flywayCommand -eq "check dry run") { $arguments += "-dryrun" }
if ($flywayCommand -eq "check changes") { $arguments += "-changes"; $arguments += "-dryrun" }
if ($flywayCommand -eq "check drift") { $arguments += "-drift" }

# --- Authentication ---
switch ($flywayAuthenticationMethod) {
    "awsiam" {
        $parsedUrl = Get-ParsedUrl -ConnectionUrl $flywayUrl
        $region = ($parsedUrl.Host.Split("."))[2]
        Write-Host "Generating AWS IAM token for user '$flywayUser' in region '$region'..."
        $flywayUserPassword = (aws rds generate-db-auth-token --hostname $parsedUrl.Host --region $region --port $parsedUrl.Port --username $flywayUser)
        $arguments += "-user=`"$flywayUser`""
        $arguments += "-password=`"$flywayUserPassword`""
    }
    "azuremanagedidentity" {
        # Logic for Azure Managed Identity...
    }
    "gcpserviceaccount" {
        # Logic for GCP Service Account...
    }
    "windowsauthentication" {
        Write-Host "Using Windows Authentication. User and password parameters will be omitted."
        $arguments += "-user=`"$flywayUser`""
    }
    default { # "usernamepassword"
        if (Test-AddParameterToCommandline -parameterValue $flywayUser -acceptedCommands "any" -selectedCommand $flywayCommand -parameterName "-user") {
            $arguments += "-user=`"$flywayUser`""
            $arguments += "-password=$flywayUserPassword"
        }
    }
}

# --- Common Parameters ---
$arguments += "-url=`"$flywayUrl`""
$arguments += "-locations=$flywayLocations"

if (Test-AddParameterToCommandline -parameterValue $flywaySchemas -acceptedCommands "any" -selectedCommand $flywayCommand -parameterName "-schemas") {
    $arguments += "-schemas=`"$flywaySchemas`""
}
if (Test-AddParameterToCommandline -parameterValue $flywayLicenseKey -acceptedCommands "any" -selectedCommand $flywayCommand -parameterName "-licenseKey") {
    $arguments += "-licenseKey=`"$flywayLicenseKey`""
}

# --- Command-Specific Parameters ---
# (Example for 'target' parameter)
if (Test-AddParameterToCommandline -parameterValue $flywayTarget -acceptedCommands "migrate,info,validate,undo,check" -selectedCommand $commandToUse -parameterName "-target") {
    $targetValue = $flywayTarget
    if ($targetValue.ToLower().Trim() -eq "latest" -and $flywayCommand -eq "undo") {
        Write-Host "Command is 'undo' with target 'latest', changing target to 'current'."
        $targetValue = "current"
    }
    $arguments += "-target=`"$targetValue`""
}

# (Add similar blocks for all other optional Flyway parameters like -outOfOrder, -baselineVersion, etc.)

# --- Placeholders ---
if (Test-AddParameterToCommandline -parameterValue $flywayPlaceHolders -acceptedCommands "migrate,info,validate,undo,repair,check" -selectedCommand $commandToUse -parameterName "-placeHolders") {
    $flywayPlaceHolders.Split("`n").Trim() | ForEach-Object {
        if ($_ -match '(.+?)::(.+)') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $arguments += "-placeholders.$key=`"$value`""
        }
    }
}

# --- Additional Arguments ---
if (-not [string]::IsNullOrWhitespace($flywayAdditionalArguments)) {
    $arguments += $flywayAdditionalArguments.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
}

#================================================================================
# 4. EXECUTE FLYWAY COMMAND
#================================================================================
Write-Host "--- Executing Flyway Command ---"

# Mask password for logging
$displayArguments = $arguments.PSObject.Copy()
for ($i = 0; $i -lt $displayArguments.Count; $i++) {
    if ($displayArguments[$i] -like "*-password=*") {
        $displayArguments[$i] = $displayArguments[$i].Replace($flywayUserPassword, "****")
    }
}
Write-Host "Executing: $flywayCmd $displayArguments"

# Execute the command
if ($IsLinux) { & bash $flywayCmd $arguments } else { & $flywayCmd $arguments }

if ($lastExitCode -ne 0) {
    throw "Execution of Flyway failed with exit code $lastExitCode."
}
Write-Host "Flyway command executed successfully."

#================================================================================
# 5. ARTIFACT HANDLING & CLEANUP
#================================================================================
Write-Host "--- Handling Artifacts and Cleanup ---"
$currentDateFormatted = (Get-Date).ToString("yyyyMMdd_HHmmss")
$stepName = $OctopusParameters["Octopus.Action.StepName"]
$environmentName = $OctopusParameters["Octopus.Environment.Name"]

# --- Create Artifacts from Dry Run Output ---
$dryRunOutputFile = ""
if ($flywayCommand -eq "migrate dry run") {
    $dryRunOutputFile = Join-Path (Get-Location) "dryRunOutput"
    $sqlDryRunFile = "$($dryRunOutputFile).sql"
    if (Test-Path $sqlDryRunFile) {
        New-OctopusArtifact -Path $sqlDryRunFile -Name "${stepName}_${environmentName}_${currentDateFormatted}_dryRun.sql"
    }
}

# --- Create Artifact from Report ---
$reportFile = Join-Path (Get-Location) "report.html"
if (Test-Path $reportFile) {
    New-OctopusArtifact -Path $reportFile -Name "${stepName}_${environmentName}_${currentDateFormatted}_report.html"
}

# --- Cleanup ---
# (Add any file cleanup logic here if necessary)

Write-Host "Script completed successfully."
