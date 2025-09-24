<#
.SYNOPSIS
This script provides foundational helper functions for a Flyway-based database deployment process.
It includes functions to load environment configurations from files and to prepare the necessary
parameters and commands for executing a Flyway migration.
#>

# The script-level ErrorActionPreference is commented out, meaning it will use the shell's default.
# Individual functions may override this setting.
#$ErrorActionPreference = 'Stop'

function LoadEnvironmentDetails() {
<#
.SYNOPSIS
    Loads deployment configuration details from a specified XML or JSON file.
.PARAMETER configFile
    The full path to the configuration file. Must be a .xml or .json file.
.OUTPUTS
    An object (XML or PSCustomObject) containing the configuration data.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string]$configFile
    )
    Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
    Write-Host "Loading Environment Details from configuration file  $configFile" -ForegroundColor Cyan
    Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
    
    # Validate the configFile parameter.
    if ( [string]::IsNullOrEmpty($configFile)) {
        throw "No configuration file specified."
    }
    elseif (-NOT(Test-Path $configFile)) {
        throw "Unable to load configuration ($configFile) as file does not exist. Supported formats are JSON or XML."
    }
    # Load the file based on its extension.
    elseif ($configFile.EndsWith("xml")) {
        [xml]$config = Get-Content $configFile
    }
    elseif ( $configFile.EndsWith("json")) {
        $config = Get-Content -Raw -Path $configFile | ConvertFrom-Json
    }
    
    return $config
}

function ExecuteFlywayMigrate {
<#
.SYNOPSIS
    Prepares all necessary parameters and constructs the command-line arguments for a 'flyway migrate' execution.
.DESCRIPTION
    This function takes raw deployment inputs, normalizes the version strings to be Flyway-compliant,
    handles credentials securely, and builds the complete set of arguments needed to run Flyway.
    NOTE: The actual execution logic in this function is commented out. Its primary purpose in its
    current state is to return the prepared parameters to the calling script.
.OUTPUTS
    An array of prepared values: $url, $location, $target, $baselineversion, $user, $PlainPassword, $generated_file.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [System.Management.Automation.PSCredential]$credentials,
        [Parameter(Mandatory = $True)]
        [string]$target, # The target version for the migration
        [Parameter(Mandatory = $True)]
        [string] $baselineversion, # The baseline version for Flyway
        [Parameter(Mandatory = $True)]
        $appEnv, # The configuration object for the current environment
        [Parameter(Mandatory = $True)]
        [string] $flywayPath, # Path to the Flyway executable
        [Parameter(Mandatory = $True)]
        [string] $flywayHistoryTable # Name of the Flyway schema history table
    )
    try {
        # This script block ensures that any errors inside are non-terminating,
        # which is relevant for the commented-out Invoke-Expression logic.
        .{
            $ErrorActionPreference = 'Continue'

            # Normalize the target version string by removing common prefixes and suffixes.
            # This ensures consistency between branch names and Flyway version numbers.
            if ($target.ToString() -match "\[") {
                $target = $target.ToString().Replace('[', '')
                $target = $target.ToString().Replace(']', '')
            }
            if ($target.ToString().StartsWith("release/") -eq $true) {
                $target = $target.ToString().Replace('release/', '')
            }
            if ($target -match "-rc") {
                $target = $target.ToString().Replace('-rc', '.')
            }
            if ($baselineversion -match "-rc") {
                $baselineversion = $baselineversion.ToString().Replace('-rc', '.')
            }
            if ($target -match "_") {
                $start = $target.IndexOf('_')
                $start = $start + 1
                $len = $target.Length
                $len -= $start
                $target = $target.Substring($start, $len)
            }
            # Flyway's 'target' parameter should not include the leading 'V'.
            if ($target.StartsWith("V")) {
                $target = $target.ToString().Replace('V', '')
            }
            if ($baselineversion.StartsWith("V")) {
                $baselineversion = $baselineversion.ToString().Replace('v', '')
                $baselineversion = $baselineversion.ToString().Replace('V', '')
            }

            # Securely extract credentials from the PSCredential object.
            if ($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
                throw "Credentials are empty"
            }
            else {
                $PlainPassword = $credentials.GetNetworkCredential().Password 
                $user = $credentials.UserName 
            }
            
            # Prepare variables from the environment configuration for the Flyway command.
            $url = $appEnv.connection.url
            $target = "`"$target`"" # Enclose in quotes for the command line
            $baselineversion = "`"$baselineversion`"" # Enclose in quotes
            $OFS = ',' # Set Output Field Separator for array to string conversion
            $locations = ([string]$appEnv.locations.location) 
            $OFS = $nul # Reset Output Field Separator
            $location = $locations.ToString().Replace('filesystem:','')+"/"
            
            # Construct the full Flyway command arguments.
            # This first version is for logging purposes, with secrets masked.
            $flyEnvDetailsMasked = " -url=" + $url + "  -user=**** -password=******** -table=" + $flywayHistoryTable + " -locations=" + $locations + " -target=" + $target
            # These are the specific Flyway flags being used.
            $command = " -repeatableSqlMigrationPrefix=`"R`"  -skipDefaultCallbacks=`"false`"  -outOfOrder=`"true`"  -validateOnMigrate=`"false`" -cleanDisabled=`"true`" -baselineOnMigrate=`"true`" -baselineVersion=$baselineversion migrate "
                
            # Log the masked command that will be executed.
            Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
            Write-Host "Command to Execute: flyway $flyEnvDetailsMasked $command" -ForegroundColor Cyan
            Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
                
            #----------------------------------------------------------------------------------#
            # NOTE: The following blocks contain commented-out logic for executing Flyway.
            # This function, in its current state, prepares and returns the parameters
            # but does not run the command itself.
            #----------------------------------------------------------------------------------#
            
            ## Example of a full command string for a dry run (validate).
            #[string] $command2 = "cd ""$flywayPath""; ./flyway -url=""$url"" -user=""$user"" -password=""$PlainPassword"" -table=""$flywayHistoryTable"" -locations=""$locations"" -target=""$target"" -baselineVersion=""$baselineversion"" ... validate"

            ## Example of a full command string for a migration.
            #[string] $command2 = "cd ""$flywayPath""; ./flyway ... migrate 2>&1"
                
            ## Old logic using Start-Job to run the command asynchronously.
            #$scriptBlock = [Scriptblock]::Create($command2)
            #$j = Start-Job -ScriptBlock $scriptblock
            #$j | Wait-Job
            
            ## New logic using Invoke-Expression to run the command and capture output/errors.
            #$flywayOutput = (Invoke-Expression -Command $command2 -ErrorAction Continue)
            #if ($flywayOutput -like "*ERROR:*") {
            #    Throw $flywayOutput
            #}

        } | Out-Null

        # Return all the prepared parameters for the calling script to use.
        return $url, $location, $target, $baselineversion, $user, $PlainPassword, $generated_file
    
    }
    catch {
        # This block would catch errors from the execution, but since it's commented out,
        # it will primarily catch errors from the parameter preparation logic.
        Write-Host ($flywayOutput | Out-String) # Note: $flywayOutput may be null here.
        $toThrow = ('Issue with Flyway Deploy!')
    }
    finally {
        # If an error was caught, throw it to fail the script.
        if ($toThrow) {
            Throw $toThrow
        }
    }
}