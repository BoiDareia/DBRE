#<#
#.SYNOPSIS
#  A PowerShell script with functions to prepare and execute Flyway database migrations.
#
#.DESCRIPTION
#  This script provides functions to:
#  1. Load environment and database connection details from a configuration file (JSON or XML).
#  2. Prepare the necessary arguments and command strings for executing a Flyway migration.
#     It intelligently parses version numbers from different formats (like git tags or branches)
#     and includes robust error handling.
#>

# Sets the default error handling behavior for the script. 
# 'Stop' will terminate the script immediately if a terminating error occurs.
# This line is commented out, so the script will use PowerShell's default ('Continue').
#$ErrorActionPreference = 'Stop'

#---------------------------------------------------------------------------------------------

<#
.SYNOPSIS
  Loads environment configuration from a specified JSON or XML file.

.PARAMETER configFile
  [string] The mandatory file path for the configuration file.

.OUTPUTS
  An object (either [xml] or [pscustomobject]) containing the configuration data.

.NOTES
  The function validates that the file path is provided and that the file exists before attempting to read it.
#>
function LoadEnvironmentDetails() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string]$configFile
    )
    
    # The .{} script block groups the commands. The output of these commands (like Write-Host)
    # is piped to Out-Null to prevent it from being returned by the function. Only the $config object is returned.
    .{
        Write-host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        Write-host "Loading Environment Details from configuration file: $configFile"
        Write-host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

        # Check if the configFile parameter is empty or null.
        if ([string]::IsNullOrEmpty($configFile)) {
            Write-host "No configuration file specified."
            throw "No configuration file specified."
            exit # Note: 'throw' will stop the script, so 'exit' is redundant here.
        }
        # Check if the file specified in $configFile does not exist.
        elseif (-NOT (Test-Path $configFile)) {
            Write-host "Unable to load configuration ($configFile) as file does not exist. Supported formats are JSON or XML."
            throw "Unable to load configuration ($configFile) as file does not exist. Supported formats are JSON or XML."
            exit
        }
        # If the file ends with .xml, parse it as XML.
        elseif ($configFile.EndsWith("xml")) {
            [xml]$config = Get-Content $configFile
        }
        # If the file ends with .json, parse it as a JSON object.
        elseif ($configFile.EndsWith("json")) {
            # -Raw ensures the entire file content is read as a single string.
            $config = Get-Content -Raw -Path $configFile | ConvertFrom-Json
        }
    } | Out-Null

    # Return the loaded configuration object.
    return $config
}

#---------------------------------------------------------------------------------------------

<#
.SYNOPSIS
  Prepares all the necessary parameters and variables to execute a Flyway migration command.

.DESCRIPTION
  This function takes various inputs like credentials, target version, and environment settings.
  It parses the target version from different string formats (e.g., git tags, branches),
  handles credentials securely, and constructs the arguments for the Flyway command line.

.PARAMETER credentials
  [PSCredential] A PSCredential object containing the username and password for the database.

.PARAMETER target
  [string] The target migration version. This can be a simple version (e.g., 'v1.2.3'), a git tag, a branch name, or a commit hash.

.PARAMETER baselineversion
  [string] The version to apply as the baseline for an existing database.

.PARAMETER appEnv
  [object] The application environment configuration object loaded by LoadEnvironmentDetails.

.PARAMETER flywayPath
  [string] The file path to the Flyway CLI directory.

.PARAMETER flywayHistoryTable
  [string] The name of the table Flyway uses to track migration history.

.PARAMETER HasBeenDeployed
  [bool] A flag indicating if this is a re-deployment of an existing version.

.PARAMETER appregion
  [string] The application region (e.g., 'EU', 'US'). Note: This parameter is not used in the current function body.

.PARAMETER logfile
  [string] The file path for logging output.

.OUTPUTS
  An array of strings containing the processed values needed to run the final Flyway command:
  - url, location, target, baselineversion, user, PlainPassword, generated_file
#>
function ExecuteFlywayCreate() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [System.Management.Automation.PSCredential]$credentials,
        [Parameter(Mandatory = $True)]
        [string]$target,
        [Parameter(Mandatory = $True)]
        [string] $baselineversion,
        [Parameter(Mandatory = $True)]
        $appEnv,
        [Parameter(Mandatory = $True)]
        [string] $flywayPath,
        [Parameter(Mandatory = $True)]
        [string] $flywayHistoryTable,
        [Parameter(Mandatory = $True)]
        [string] $HasBeenDeployed,
        [Parameter(Mandatory = $True)]
        $appregion,
        [Parameter(Mandatory = $True)]
        [string] $logfile
    )

    # A try/catch/finally block for robust error handling.
    try {
        # Again, using .{} and Out-Null to suppress intermediate output from this block.
        .{
            # Set error action to 'Continue' so the catch block can handle file renaming if an error occurs inside this block.
            $ErrorActionPreference = 'Continue'

            # Extract the path to the SQL migration scripts from the environment config.
            $locations = ([string]$appEnv.locations.location)

            # This complex block of code parses the version number from the $target string.
            # It uses regular expressions (-match) to handle various formats like 'v1.2.3', 'feature/v1.2.3', 'v1.2.3-beta', etc.
            if ($target -notmatch '^v\d+\.\d+\.\d+$' -and $target -notmatch '^v\d+\.\d+$') {
                # If the target is not a simple version string, try to extract one.
                if ($target -match '^[A-Za-z0-9]+/v\d+\.\d+\.\d+') { # e.g., 'feature/v1.2.3'
                    $target -match 'v\d+\.\d+\.\d+'
                    $version = $Matches[0] # $Matches is an automatic variable populated by the -match operator.
                }
                else {
                    if ($target -match '^[A-Za-z0-9]+/v\d+\.\d+') { # e.g., 'feature/v1.2'
                        $target -match 'v\d+\.\d+'
                        $version = $Matches[0]
                    }
                    else {
                        if ($target -match '^v\d+\.\d+\.\d+\-[A-Za-z0-9]') { # e.g., 'v1.2.3-beta'
                            $target -match 'v\d+\.\d+\.\d+'
                            $version = $Matches[0]
                        }
                        else {
                            if ($target -match '^v\d+\.\d+\-[A-Za-z0-9]') { # e.g., 'v1.2-beta'
                                $target -match 'v\d+\.\d+'
                                $version = $Matches[0]
                            }
                            else {
                                # If no standard version format is found, assume it's a commit hash or other identifier.
                                $version = $target
                                Write-Host "Input does not look like a standard version. Using raw target: $target"
                            }
                        }
                    }
                }
            }
            else {
                # If the target is already a simple version string, use it directly.
                $version = $target
            }

            # Standardize the version strings by removing the leading 'v' or 'V' if present.
            if ($version.StartsWith("v") -or $version.StartsWith("V")) {
                $version = $version.Substring(1)
            }
            if ($baselineversion.StartsWith("v") -or $baselineversion.StartsWith("V")) {
                $baselineversion = $baselineversion.Substring(1)
            }

            Write-Host "Version: $version"

            # Prepare path and filter variables for finding SQL script files.
            $location = $locations.ToString().Replace('filesystem:', '') + "\*"
            $filter = "V" + $version + "*.sql" # e.g., 'V1.2.3__description.sql'

            # If this is a re-deployment, we need to find the exact file that was previously run.
            # Flyway migration files often include a timestamp, so we find the most recent one for this version.
            if ($HasBeenDeployed) {
                # Find the most recently modified SQL file that matches the version filter.
                $generated_file = Get-ChildItem -path $location -Include $filter | Sort-Object -Descending LastWriteTime | Select-Object name -First 1 -ExpandProperty Name
                # Extract the precise version number from the filename.
                $target = $generated_file.substring(1, $generated_file.indexof('__') - 1)
                $filter = "V" + $version + "*.sql"
            }

            # Validate credentials and extract the plain-text password for the command line.
            if ($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
                "Credentials are empty" | ForEach-Object { write-host $_; out-file -filepath $logfile -inputobject $_ -append }
                throw "Credentials are empty"
            }
            else {
                # Get the password as a plain string.
                $PlainPassword = $credentials.GetNetworkCredential().Password
                # Escape the ampersand character '&' as it has a special meaning in command shells.
                if ($PlainPassword.Contains("&")) {
                    $PlainPassword = $PlainPassword.Replace("&", """&""")
                }
                $user = $credentials.UserName
            }

            # Assemble the arguments for the Flyway command.
            $url = $appEnv.connection.url
            $url += ";trustServerCertificate=true" # Append setting to trust the server's SSL certificate.
            $target = "`"$version`"" # Enclose version in quotes for the command line.
            $baselineversion = "`"$baselineversion`""

            # Create a masked version of the connection details for safe logging (hiding credentials).
            $flyEnvDetailsMasked = "-url=" + $url + " -user=**** -password=******** -table=" + $flywayHistoryTable + " -locations=" + $locations + " -target=" + $target
            # Define the static Flyway command arguments.
            $command = " -repeatableSqlMigrationPrefix=`"R`" -skipDefaultCallbacks=`"false`" -outOfOrder=`"false`" -validateOnMigrate=`"true`" -ignoreMigrationPatterns=`"*:missing`" -cleanDisabled=`"true`" -baselineOnMigrate=`"true`" -baselineVersion=$baselineversion -executeInTransaction=`"false`" migrate"
            
            # Log the full command (with masked credentials) to the console and the log file.
            # The `| ForEach-Object { ... }` (aliased as `%`) is used to pipe the string to two commands.
            "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" | % { write-host $_; out-file -filepath $logfile -inputobject $_ -append }
            "Command to Execute: flyway $flyEnvDetailsMasked $command" | % { write-host $_; out-file -filepath $logfile -inputobject $_ -append }
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" | % { write-host $_; out-file -filepath $logfile -inputobject $_ -append }

            # These lines are examples of how the final command could be constructed and executed. They are currently commented out.
            #[string] $command2 = "cd ""$flywayPath""; ./flyway -url=""$url"" -user=""$user"" -password='$PlainPassword' -table=""$flywayHistoryTable"" -locations=""$locations"" -target=""$target"" -baselineVersion=""$baselineversion"" -repeatableSqlMigrationPrefix=""R"" -skipDefaultCallbacks=""false"" -outOfOrder=""false"" -validateOnMigrate=""true"" -ignoreMigrationPatterns=""*:missing"" -cleanDisabled=""true"" -baselineOnMigrate=""true"" -executeInTransaction=""false"" migrate 2>&1"
            #[string] $command_repair = "cd ""$flywayPath""; ./flyway -url=""$url"" -user=""$user"" -password='$PlainPassword' -table=""$flywayHistoryTable"" -locations=""$locations"" repair 2>&1"

        } | Out-Null

        # Return the processed variables so they can be used by another function to execute the command.
        return $url, $location, $target, $baselineversion, $user, $PlainPassword, $generated_file
    }
    catch {
        # This block executes if any command in the 'try' block throws a terminating error.
        Write-Host "An error occurred during Flyway preparation. Renaming the failed SQL script."
        
        # To prevent a failed script from running again, rename it by adding a timestamp and a '_failed_' prefix.
        $failuredate = Get-Date -Format "yyyyMMdd_HHmmss"
        $failurereplace = $failuredate + "_failed_V"
        Get-ChildItem -path $location -Include $filter | Rename-Item -NewName { $_.Name -replace 'V', $failurereplace }

        # Prepare a custom error message to be thrown by the 'finally' block.
        $toThrow = ('Issue with Flyway Deploy preparation!')
    }
    finally {
        # This block ALWAYS runs, whether the 'try' block succeeded or failed.
        if ($toThrow) {
            # If an error was caught, log the custom message and re-throw it to halt the script.
            $toThrow | % { write-host $_; out-file -filepath $logfile -inputobject $_ -append }
            Throw $toThrow
        }
    }
}