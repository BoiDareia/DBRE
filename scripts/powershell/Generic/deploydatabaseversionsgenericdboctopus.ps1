<#
.SYNOPSIS
This script is the main orchestrator for a database deployment process integrated with Octopus Deploy.
It sources helper functions, reads a configuration file, checks out a specific code branch/tag,
prepares SQL migration scripts, and packages them for a Flyway step in an Octopus deployment project.
#>

# Dot-source the required function libraries. This loads their functions into the current session.
. .\GitFunctionsGenericDBOctopus.ps1
. .\BuildFunctionsGenericDB.ps1
. .\FlywayFunctionsGenericDBOctopus.ps1

# Ensure the script stops on any terminating error, allowing try/catch blocks to function correctly.
$ErrorActionPreference = 'Stop'

<#
    # This block is a commented-out example for local testing and debugging.
    # It demonstrates how to call the main function with all required parameters.
    [string] $configFile = "C:\src\Company\Database-deployment\config\Orinoco.xml"
    [string] $env = "train"
    [securestring] $securePassword = ConvertTo-SecureString “pbd1tHRUcaumPTN76uYh” -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential ("user1", $SecurePassword)
    [string] $BranchName = "release\V58.0.0"
    [string] $CheckoutPath = "C:\src\Company\Deploy"
    [bool] $IsTag = $False
    [bool] $DbChangesScriptExist = $False 
    [bool] $isContinuousDelivery = $False

    DeployDatabaseVersion $configFile $env $credentials $BranchName $CheckoutPath $IsTag $DbChangesScriptExist $isContinuousDelivery
#>

function GetFilename{
<#
.SYNOPSIS
    Normalizes a branch name into a standard, Flyway-compliant version filename.
.DESCRIPTION
    Flyway requires a specific naming convention (e.g., V1_2_3__Description.sql). This function
    takes a raw branch name and cleans it by removing prefixes, special characters, and enforcing
    the leading 'V' character.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $BranchName,
        [Parameter(Mandatory=$True)]
            [string] $database,
        [Parameter(Mandatory=$false)] #Not used. Kept for backward compatibility.
            [bool] $isContinuousDelivery = $False    
    )

    # Combine branch and database name to form the base filename.
    [string] $scriptFilename = $BranchName + "__" + $database + "_DatabaseChanges.sql"

    # Clean up the filename through a series of string replacements.
    # Remove brackets that might be added by automated systems.
    if ($scriptFilename.ToString() -match "\[") {
        $scriptFilename = $scriptFilename.ToString().Replace('[', '')
        $scriptFilename = $scriptFilename.ToString().Replace(']', '')
    }
    # Remove 'release/' prefix.
    if ($scriptFilename.ToString().StartsWith("release/") -eq $true){
        $scriptFilename = $scriptFilename.ToString().Replace('release/','')
    }
    # Remove any prefix before an underscore (e.g., 'feature_V1.2.3' becomes 'V1.2.3').
    if ($scriptFilename -match "_") {
        $start = $scriptFilename.IndexOf('_')
        $start = $start + 1
        $len = $scriptFilename.Length
        $len -= $start
        $scriptFilename = $scriptFilename.Substring($start, $len)
    }
    # Standardize release candidate naming.
    if  ($scriptFilename -match "-rc"){
        $scriptFilename = $scriptFilename.ToString().Replace('-rc','.')
    }
    # Ensure the filename starts with a capital 'V' as required by Flyway.
    if ($scriptFilename.StartsWith("v") -ne $True) {
        $scriptFilename = "V"+$scriptFilename
    }
    else{
        $scriptFilename = $scriptFilename.ToString().Replace('v','V') 
    }

    return $scriptFilename
}

function VersionHasBeenDeployed{
<#
.SYNOPSIS
    Checks the Flyway schema history table to see if a version has already been deployed.
.DESCRIPTION
    Connects to the target database using ODBC and queries the history table to prevent
    re-deploying a version that has already been successfully applied.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $BranchName,
        [Parameter(Mandatory=$True)]
            [string] $database,
        [Parameter(Mandatory=$True)]
            [string] $datasource, # ODBC connection string
        [Parameter(Mandatory=$True)]
            [string] $flywayHistoryTable  
    )

    [bool] $result = $false
    try{
        # Normalize the branch name to match the version format stored in the database.
        # This logic mirrors the normalization in GetFilename.
        if ($BranchName.ToString() -match "\[") {
            $BranchName = $BranchName.ToString().Replace('[', '')
            $BranchName = $BranchName.ToString().Replace(']', '')
        }
        if ($BranchName.ToString().StartsWith("release/") -eq $true) {
            $BranchName = $BranchName.ToString().Replace('release/','')
        }
        if  ($BranchName -match "-rc"){
            $BranchName = $BranchName.ToString().Replace('-rc','.')
        }
        if ($BranchName -match "_") {
            $start = $BranchName.IndexOf('_')
            $start = $start + 1
            $len = $BranchName.Length
            $len -= $start
            $BranchName = $BranchName.Substring($start, $len)
        }
        if ($BranchName.ToString().StartsWith("V") -eq $true) {
            $BranchName = $BranchName.ToString().Replace('v', '')
            $BranchName = $BranchName.ToString().Replace('V', '')
        }

        # Add a wildcard to match all scripts associated with this version (e.g., V1.2.3.1, V1.2.3.2).
        $BranchName += "%"

        # Construct the SQL query to check for the version in the history table.
        [string] $CommandText = 'select version, description from ' + $database.ToString() + '.public.' + $flywayHistoryTable.ToString() + ' where version like ''' + $BranchName.ToString() + ''''
        
        # Create and open an ODBC connection to the database.
        $Connection = [System.Data.Odbc.OdbcConnection]::new($datasource)
        $Connection.open()
        $ODBCCommand = New-Object Data.Odbc.OdbcCommand($CommandText,$Connection)
        
        # Execute the query and load the results into a DataTable.
        $Reader = $ODBCCommand.ExecuteReader()
		$Datatable = New-Object System.Data.DataTable
        $Datatable.Load($Reader)

        # If one or more rows are returned, the version has been deployed.
        if($Datatable.Rows.Count -ge 1) {$result = $True}

        $Reader.Close()
		 
        return $result 
    }
    catch{throw} # Re-throw any exceptions.
    finally{$Connection.Close()} # Ensure the database connection is always closed.
}

function AdjustFlywayIfFail {
<#
.SYNOPSIS
    Deletes entries from the Flyway schema history table after a failed deployment.
.DESCRIPTION
    If a deployment fails, Flyway might leave a "failed" entry in its history table,
    preventing future attempts. This function connects to the database and removes
    all entries for a given version to allow a clean retry.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string] $BranchName,
        [Parameter(Mandatory = $True)]
        [string] $datasource,
        [Parameter(Mandatory = $True)]
        [string] $flywayHistoryTable  
    )

    [bool] $result = $false
    try {
        # Normalize the branch name to match the version format.
        if ($BranchName.ToString() -match "\[") {
            $BranchName = $BranchName.ToString().Replace('[', '')
            $BranchName = $BranchName.ToString().Replace(']', '')
        }
		
        if ($BranchName.ToString().StartsWith("release/") -eq $true) {
            $BranchName = $BranchName.ToString().Replace('release/', '')
        }
        if ($BranchName -match "-rc") {
            $BranchName = $BranchName.ToString().Replace('-rc', '.')
        }
        if ($BranchName -match "_") {
            $start = $BranchName.IndexOf('_')
            $start = $start + 1
            $len = $BranchName.Length
            $len -= $start
            $BranchName = $BranchName.Substring($start, $len)
        }
        if ($BranchName.ToString().StartsWith("V") -eq $true) {
            $BranchName = $BranchName.ToString().Replace('v', '')
            $BranchName = $BranchName.ToString().Replace('V', '')
        }

        # Add wildcard to delete all scripts for this version.
        $BranchName += "%"

        # Construct the DELETE command.
        [string] $CommandText = 'delete from public.[' + $flywayHistoryTable.ToString() + '] where [version] like ''' + $BranchName.ToString() + ''''
        
        # Establish ODBC connection.
        $Connection = New-Object Data.Odbc.OdbcConnection
        $Connection.ConnectionString = "$datasource"
        $Connection.open()
        $ODBCCommand = New-Object Data.Odbc.OdbcCommand($CommandText, $Connection)
        
        # Execute the delete command and get the number of rows affected.
        $rowsDeleted = $ODBCCommand.ExecuteNonQuery()
        Write-Host "$rowsDeleted rows deleted from schema history table.";

        $Connection.Close()
		 
        return $result 
    }
    catch { throw }
    finally { $Connection.Close() } # Always close the connection.
}

function BuildProject{
<#
.SYNOPSIS
    Builds a Visual Studio .NET project or solution using devenv.com.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $Solution, # Path to the .sln file
        [Parameter(Mandatory=$True)]
            [string] $Project   # Name of the .csproj file
    )

    try{
        # Path to the Visual Studio command-line executable.
        [string] $devEnvPath = 'devenv.com'
        # Command-line arguments to rebuild the specified project in Debug configuration.
        [string] $parameters = "/Rebuild Debug ""$Solution"" /Project ""$Project"""

        $command = $devEnvPath+' '+$parameters
        $scriptBlock = [Scriptblock]::Create($command)

        # Start the build as a background job to avoid blocking the console.
        Write-Host "Build job to start [$devEnvPath $parameters]`n" -ForegroundColor Cyan
        $j = Start-Job -ScriptBlock $scriptblock

        # Wait for the job to complete and receive its output.
        $j | Wait-Job
        $joboutput= Receive-job $j |ft -autosize|out-string
        Write-Host $joboutput

        # Check the final state of the job to determine success or failure.
        if ($j.State -eq 'Completed') {Write-host "Build job finished`n" -ForegroundColor Green}
        else {Throw "Build job exited with the following error: $stderr"}
    }
    catch{throw}
}

function DeployDatabaseVersion{
<#
.SYNOPSIS
    The main orchestration function for deploying a database version.
.DESCRIPTION
    This function reads deployment configuration, checks out code from Git, prepares SQL scripts
    based on the database engine and deployment type, and finally packages the scripts and
    pushes them to Octopus Deploy.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $configFile,        
        [Parameter(Mandatory=$True)]
            [string] $env,
        [Parameter(Mandatory=$True)]
            [System.Management.Automation.PSCredential] $credentials,
        [Parameter(Mandatory=$True)]
            [string] $BranchName,
        [Parameter(Mandatory=$True)]
            [string] $CheckoutPath,
        [Parameter(Mandatory=$False)]
            [bool] $IsTag = $False, 
        [Parameter(Mandatory=$false)]
            [bool] $isContinuousDelivery = $False,
        [Parameter(Mandatory=$False)]
            [bool] $IsRedeploy = $False            
    )
    try{
        # Initialize a variable to hold any error messages.
        [string] $toThrow = [string]::Empty
        
        # Log the start of the deployment.
        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        if ($isContinuousDelivery){
            Write-Host "Starting database Continuous Deployment" -ForegroundColor Yellow
        }
        else {
            [string] $branch_or_tag = "branch"
            if ($IsTag -eq $True) {$branch_or_tag = "tag"}
            Write-Host "Starting database version deployment for $branch_or_tag $BranchName" -ForegroundColor Yellow
        }
        Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        
        # Load environment details from the specified XML configuration file.
        $config = LoadEnvironmentDetails($configFile)
            
        # Find the correct environment configuration within the loaded XML.
        $result = $false
        $index = 0
        $environments = $config.app.environments.environment
        foreach($environment in $environments){
            If($environment.name -match $env){
                $result = $true
                break
            }
            $index+=1
        }
        if ($result -eq $false){throw "No configuration found for environment named $env"}
		
        # Get the specific environment object.
        $appEnv = @($config.app.environments.environment)[$index]
		
        if($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "Credentials are empty"
        }

        # Extract global configuration settings from the config file.
        [string] $buildFile = $config.app.global.buildFile
        [string] $scriptPath = $config.app.global.RootScriptsPath
        [string] $CompanyGitURL = $config.app.global.CompanyGitURL
        [string] $flywayPath = $config.app.global.flywayCmdPath
        [string] $baselineversion = $config.app.global.baseline
        [string] $flywayHistoryTable = $config.app.global.schemaHistoryTable
        [string] $pythonPath = $config.app.global.pythonPath
        [string] $filePath = $config.app.global.filePath
        [string] $deployPath = $filepath + $config.app.global.deployPath
        [string] $databaseName = $config.app.name
        [string] $engineName = $config.app.global.engine
        [string] $DeployType = $config.app.global.DeployType
        [string] $dbType = $config.app.global.DbType
		
        # Validate that essential configuration values are not empty.
        if($buildFile -eq '' -Or [string]::IsNullOrEmpty($buildFile)) {throw "build file location is empty"}
        if($scriptPath -eq '' -Or [string]::IsNullOrEmpty($scriptPath)) {throw "Path to store database changes scipt is empty"}
        if($CompanyGitURL -eq '' -Or [string]::IsNullOrEmpty($CompanyGitURL)) {throw "The url for Company Git is empty"}
        if($baselineversion -eq '' -Or [string]::IsNullOrEmpty($baselineversion)) {throw "The value for baseline version is empty"}

        # Validate and construct the path for storing SQL scripts.
        if (Test-Path $scriptPath) {
            if(-Not $scriptPath.EndsWith("\")) {$scriptPath+="\"}
            $scriptPath+=$env
            $scriptPath+="\"
        }
        else {
            throw "$scriptPath is not a valid path" 
        }

        # Extract environment-specific settings.
        [string] $url = $appEnv.connection.url
        if($url -eq '' -Or [string]::IsNullOrEmpty($url)) {throw "flyway url is empty"}
      
        # Construct the full ODBC data source connection string.
        $Driver = $appEnv.connection.odbc
        $MyServer = $appEnv.connection.url
        $MyPort = $appEnv.connection.port
        $MyDB = $appEnv.connection.database
        $MyUid = $credentials.GetNetworkCredential().UserName
        $MyPass = $credentials.GetNetworkCredential().Password
        [string] $datasource = "$Driver;Server=$MyServer;Port=$MyPort;Database=$MyDB;Uid=$MyUid;Pwd=$MyPass;"

        # Check if this version has already been deployed to prevent duplicate runs.
        [bool]$HasBeenDeployed = VersionHasBeenDeployed $BranchName $databaseName $datasource $flywayHistoryTable

        # Proceed only if the version is new or if it's a forced redeployment.
        if (-Not $HasBeenDeployed -or $isRedeploy -eq $true) {
		
            # Step 1: Check out the specified branch or tag from Git.
            GitCheckoutBranch $CheckoutPath $CompanyGitURL $BranchName $IsTag $DeployType $isContinuousDelivery

            # Step 2: Normalize the branch name into a clean version string.
            if ($BranchName.ToString() -match "\[") {
                $BranchName = $BranchName.ToString().Replace('[', '')
                $BranchName = $BranchName.ToString().Replace(']', '')
            }
            if ($BranchName.ToString().StartsWith("release/") -eq $true) {
                $BranchName = $BranchName.ToString().Replace('release/', '')
            }
            if ($BranchName -match "_") {
                $start = $BranchName.IndexOf('_')
                $start = $start + 1
                $len = $BranchName.Length
                $len -= $start
                $BranchName = $BranchName.Substring($start, $len)
            }
            if ($BranchName.StartsWith("v")) {
                $BranchName = $BranchName.ToString().Replace('v', 'V') # Ensure leading 'V' for Flyway
            }
            
            # Create a special redeploy version name if needed.
            if ($isRedeploy -eq $true -and $BranchName.StartsWith("v")) {
                $redeployBranchName = $BranchName.ToString().Replace('v', 'R__')
            }
            if ($isRedeploy -eq $true -and $BranchName.StartsWith("V")) {
                $redeployBranchName = $BranchName.ToString().Replace('V', 'R__')
            }

            # Step 3: Handle database-engine specific logic for generating or finding SQL scripts.
            if ($engineName -match "aurora" -or $engineName -eq "postgresql" -or $engineName -eq "mysql" -or $databaseName -eq "dev") {
                # For these engines, we expect a manifest file listing the SQL scripts to deploy.
                if (Test-Path $filepath) {
                    Write-Host "`nCheck $engineName DeployScript successful!" -ForegroundColor Green
                }
                else {
                    $toThrow = ('Check DeployScript failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
                }
            }
            elseif ($engineName -eq "redshift" -and $DeployType -eq "releaseBranch") {
                # For Redshift release branches, we generate the scripts using a Python tool.
                GenerateDeployScript $pythonPath $buildFile $deployPath $filepath
            }
		
			# Get the location where Flyway expects to find the SQL scripts.
			$locations = ([string]$appEnv.locations.location).ToString().Replace('/','\').Replace('filesystem:','')		
            			
            # Step 4: Copy or combine the SQL scripts into the Flyway location with the correct filename.
            if ($engineName -match "aurora" -or $engineName -eq "postgresql" -or $engineName -eq "mysql" -or $databaseName -eq "dev" -or $DeployType -eq "trunkBase") {
                # This logic reads a manifest file and concatenates all listed SQL files into one large migration script.
                $proceed = ConfirmLocationExists $filepath 
                if ($proceed -eq $True) {
                    $manifestList = @(GetManifestList $filepath)
                    if ($manifestList -eq "EMPTY") {throw "Manifest List to Deploy is $manifestList !!"}

                    # Loop through each file in the manifest.
                    foreach ($currentItemName in $manifestList) {
                        if ($null -ne $currentItemName) {
                            # Handle files in subdirectories.
                            if ($currentItemName.Contains("\")) {
                                $parts = $currentItemName.Split([char[]]"\", [System.StringSplitOptions]::None)
                                $path = $parts[0..($parts.Count - 2)] -join "\"
                                $filename = $parts[$parts.Count - 1]
                            }else {
                                $filename = $currentItemName
                                $path =  ''
                            }
                            
                            # Append the content of the current SQL file to the final migration script.
                            if ($isRedeploy -eq $true) {
                                # Use the redeploy naming convention.
                                if (-Not (Test-Path -Path "$locations\$($redeployBranchName)_DatabaseChanges.sql")) {
                                    Get-Content "$filepath\$path\$filename" | Set-Content "$locations\$($redeployBranchName)_DatabaseChanges.sql" -encoding UTF8
                                }else {
                                    Get-Content "$filepath\$path\$filename" | Add-Content "$locations\$($redeployBranchName)_DatabaseChanges.sql" -encoding UTF8
                                }
                            }
                            else {
                                # Use the standard version naming convention.
                                if (-Not (Test-Path -Path "$locations\$($BranchName)__DatabaseChanges.sql")) {
                                    Get-Content "$filepath\$path\$filename" | Set-Content "$locations\$($BranchName)__DatabaseChanges.sql" -encoding UTF8
                                }else {
                                    Get-Content "$filepath\$path\$filename" | Add-Content "$locations\$($BranchName)__DatabaseChanges.sql" -encoding UTF8
                                }
                            }
                        }
                    }
                }
            }
            elseif ($engineName -eq "redshift" -and $DeployType -eq "releaseBranch") {
                # For Redshift, copy each generated script individually, giving it a sequence number.
                $listFiles = @(Get-ChildItem $deployPath)
                $fileNumber = 1
                foreach ($currentItemName in $listFiles) {
                    if ($null -ne $currentItemName) {
                        if ($isRedeploy -eq $true) {
                            Get-Content "$($deployPath)\$currentItemName" | Set-Content "$locations\$($redeployBranchName).$($fileNumber)_$currentItemName" -encoding UTF8
                        }
                        else {
                            Get-Content "$($deployPath)\$currentItemName" | Set-Content "$locations\$($BranchName).$($fileNumber)__$currentItemName" -encoding UTF8
                        }
                        $fileNumber++
                    }
                }
            }

            $version = $BranchName.ToString().Replace('V','') 

            # Step 5: Integrate with Octopus Deploy.
            
            # Construct the JDBC URL that Flyway will use.
            $flywayUrl = "jdbc:$($dbType)://$($url):$($MyPort)/$($MyDB)"
            
            # Set Octopus variables that will be consumed by a later Flyway step in the deployment process.
            Set-OctopusVariable -name "URL" -value $flywayUrl
            Set-OctopusVariable -name "Baseline" -value $baselineversion
            Set-OctopusVariable -name "Locations" -value $locations

            # Create an Octopus artifact from the generated SQL file(s) so they are visible in the UI.
            Write-Host "Build artifacts to Octopus"
            $location = $locations + "\"
            if  ($isRedeploy -eq $true){
                $filter = "R*" + $version + "*.sql"
            }
            else {
                $filter = "V*" + $version + "*.sql"
            }
            $generated_file = Get-ChildItem -Path $location -Include $filter | Select-Object -ExpandProperty Name
            $generated_file | ForEach-Object { New-OctopusArtifact -path $location$_ -name $_ }

            # Use the 'octo' CLI to package the SQL script(s) into a versioned zip file.
            $OctoPackageId = $databaseName # Package ID will be the database name
            Write-Host "Using Octo Pack to zip sql file for $databaseName db, version $version."
            octo pack --id=$OctoPackageId --format="zip" --version="$version" --basePath="$location" --include="$filter" --overwrite 

            # Push the created package to the Octopus Deploy built-in package repository.
            $packagePath = $location + $OctoPackageId + "." + $version + ".zip"
            Write-Host "Using Octo Push to push package to Octopus: $packagePath"
            octo push --package="$packagePath" --server="$env:OCTOPUS_URL" --apiKey="$env:OCTOPUS_API_KEY" --replace-existing
        }
        else{
            Write-Host "'$BranchName' version has already been deployed." -ForegroundColor Green
        }

        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
    }
    catch{
        # This block executes if any part of the 'try' block fails.
        $toThrow = ("Database changesdeployment failed: ''{0}'' Reason: ''{1}''" -f $_.Exception.Message, $_.Exception.InnerException.Message)
		
        # CRITICAL: Clean up failed deployment artifacts to ensure a clean state for a retry.
        Write-Host "Deployment failed. Cleaning up generated files and database history entries." -ForegroundColor Red
        
        # Remove the generated SQL files from the Flyway location.
        if ($isRedeploy -eq $true) {
            # Cleanup for redeploy attempts
            if  (Test-Path "$locations\$($redeployBranchName)*.sql"){
                Remove-Item "$locations\$($redeployBranchName)*.sql" -Recurse
            }
        } else {
            # Cleanup for standard attempts
            if (Test-Path "$locations\$($BranchName)*.sql") {
                Remove-Item "$locations\$($BranchName)*.sql" -Recurse
            }
            # Also remove the failed entry from the Flyway history table.
            AdjustFlywayIfFail $BranchName $datasource $flywayHistoryTable
        }
    }
    finally{
        # The 'finally' block always runs. If an error was caught, throw it to fail the Octopus step.
        if ($toThrow) {
            Throw $toThrow
        }
    }
}

function DoDatabaseContinuousDeployment{
<#
.SYNOPSIS
    A wrapper function to execute the main deployment logic in a continuous deployment (CD) context.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
            [string] $configFile,         
        [Parameter(Mandatory=$True)]
            [string] $env,
        [Parameter(Mandatory=$True)]
            [System.Management.Automation.PSCredential] $credentials,
		[Parameter(Mandatory=$True)]
            [string] $BranchName,
        [Parameter(Mandatory=$True)]
            [string] $CheckoutPath,
        [Parameter(Mandatory=$False)]
            [bool] $IsTag = $False,
        [Parameter(Mandatory=$False)]
            [bool] $IsRedeploy = $False   
    )
    
    try{
        # Set the flag indicating a CD run.
        [bool] $isContinuousDelivery = $True
    
        # Start a transcript to log all console output to a file for auditing.
        [string] $transcript = $PWD
        [string] $currentdatetime = Get-Date -Format "yyyy.MM.dd.HH.mm"
        $Env:transcript = $transcript + "\Transcripts\DatabaseChangesDeploymentTranscript_" + $currentdatetime.ToString() + ".txt"
        Start-Transcript -Path $Env:transcript
    
        # Call the main deployment function.
        DeployDatabaseVersion $configFile $env $credentials $BranchName $CheckoutPath $IsTag $isContinuousDelivery $IsRedeploy
    }
    catch{
        # Catch any errors and format a specific message for CD failures.
        $toThrow = ("Database Continuous Deployment failed: ''{0}'' Reason: ''{1}''" -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally{
        # Always stop the transcript, ensuring the log file is closed correctly.
        Stop-transcript

        # If an error was caught, throw it to fail the pipeline.
        if ($toThrow) {
            Throw $toThrow
        }
    }
}