<#
.SYNOPSIS
    A comprehensive PowerShell script with functions to manage a DACPAC-based database deployment workflow,
    including building, generating scripts, deploying with Flyway, and notifying stakeholders.

.DESCRIPTION
    This script is a library of functions designed to be sourced by an Octopus Deploy process. It orchestrates a
    complex database deployment that involves checking out code, building a database project, generating a
    differential script from a DACPAC, and using Flyway to apply the changes.

    Key Functions:
    - GetFilename: Creates a Flyway-compliant SQL script filename (e.g., V1.2.3__... or R__1.2.3...) based on the release version.
    - VersionHasBeenDeployed: Checks the Flyway history table in the target database to see if a specific version has already been deployed.
    - BuildProject: Compiles a SQL Server Database Project (.sqlproj) using MSBuild.
    - DeployDatabaseChanges: A high-level function that uses the generated script to run `flyway migrate`.
    - DeployDatabaseVersion: The main orchestrator function that ties everything together. It calls other functions to check out code, build the project, generate the script, and prepare for the Flyway migration.
    - PublishImportantSchemaChanges: Parses a generated SQL script to extract key schema changes (new tables, columns, etc.) and sends a summary notification to a Slack channel.
    - RefreshCDC: Executes a SQL script to refresh Change Data Capture on necessary tables.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - Git, MSBuild, and Flyway CLI installed on the Octopus Worker.
                 - Dependent function scripts (`GitFunctionsOctopus.ps1`, `DacPacFunctionsOctopus.ps1`, etc.) must be available.
#>

#================================================================================
# 1. SCRIPT DEPENDENCIES & INITIAL SETUP
#================================================================================
# These would be sourced at the beginning of the main execution script.
# . .\GitFunctionsOctopus.ps1
# . .\DacPacFunctionsOctopus.ps1
# . .\FlywayFunctionsOctopus.ps1

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'

#================================================================================
# 2. HELPER & ORCHESTRATION FUNCTIONS
#================================================================================

function Get-Filename {
<#
.SYNOPSIS
    Generates a Flyway-compliant migration script filename.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)] [string]$BranchName,
        [Parameter(Mandatory=$True)] [string]$database,
        [Parameter(Mandatory=$True)] [bool]$HasBeenDeployed
    )

    # Logic to parse a clean version number from various branch/tag formats
    $version = $BranchName
    if ($BranchName -match '(v\d+\.\d+(\.\d+)?)') {
        $version = $Matches[0]
    }
    $version = $version.Replace('v', '').Replace('V', '')

    # Create a repeatable migration (R__) if the version has been deployed before, otherwise a versioned migration (V__)
    if ($HasBeenDeployed) {
        $redeployDate = Get-Date -Format "HHmmss"
        return "R__$($version).$($redeployDate)__${database}_DatabaseChanges.sql"
    }
    else {
        return "V${version}__${database}_DatabaseChanges.sql"
    }
}

function Test-VersionHasBeenDeployed {
<#
.SYNOPSIS
    Checks the Flyway history table to see if a version has been deployed.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)] [string]$BranchName,
        [Parameter(Mandatory=$True)] [string]$targetConnectionString,
        [Parameter(Mandatory=$True)] [string]$flywayHistoryTable
    )

    $connection = $null
    try {
        # Logic to parse a clean version number from the branch name
        $version = $BranchName
        if ($BranchName -match '(v\d+\.\d+(\.\d+)?)') {
            $version = $Matches[0]
        }
        $version = $version.Replace('v', '')

        # Query the Flyway history table
        $query = 'IF (OBJECT_ID(''[dbo].[' + $flywayHistoryTable.ToString() + ']'') IS NOT NULL) BEGIN ;WITH OrderedDeploys AS (SELECT [version], [installed_by], ROW_NUMBER() OVER(ORDER BY installed_rank DESC) AS ''RowNum'' FROM [dbo].[' + $flywayHistoryTable.ToString() + '] where [version] like ''' + $version.ToString() + '%' + ''')SELECT [version] FROM OrderedDeploys WHERE RowNum = 1 END'

        Write-Host "Command to execute to check if it has been deployed: $query"
        
        $connection = New-Object System.Data.SQLClient.SQLConnection($targetConnectionString)
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        $reader = $command.ExecuteReader()
        $dataTable = New-Object System.Data.DataTable
        $dataTable.Load($reader)

        return $dataTable.Rows.Count -ge 1
    }
    catch {
        Write-Error "Failed to check Flyway history table. Reason: $($_.Exception.Message)"
        throw
    }
    finally {
        if ($connection) { $connection.Close() }
    }
}

function Build-DatabaseProject {
<#
.SYNOPSIS
    Builds a SQL Server Database Project (.sqlproj) using MSBuild.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)] [string]$Project,
        [Parameter(Mandatory=$True)] [string]$logfile
    )

    try {
        Write-Host "--- Building database project: $Project ---" | Tee-Object -FilePath $logfile -Append
        $msBuildArgs = @(
            "`"$Project`"",
            "/t:Rebuild",
            "/p:Configuration=Debug"
        )
        & MSBuild $msBuildArgs | Tee-Object -FilePath $logfile -Append

        if ($LASTEXITCODE -ne 0) {
            throw "MSBuild failed with exit code $LASTEXITCODE."
        }
        Write-Host "Project build successful." | Tee-Object -FilePath $logfile -Append
    }
    catch {
        $errorMessage = "Build project failed. Reason: '$($_.Exception.Message)'"
        $errorMessage | Tee-Object -FilePath $logfile -Append
        throw $errorMessage
    }
}

function Deploy-DatabaseVersion {
<#
.SYNOPSIS
    The main orchestrator function for a database version deployment.
#>
    [CmdletBinding()]
    Param(
        # ... (All parameters from original script) ...
    )

    try {
        # --- 1. Load Configuration ---
        $config = LoadEnvironmentDetails $configFile
        # ... (Logic to find the correct environment config) ...
        
        # --- 2. Get Global & Environment Settings ---
        # ... (Logic to extract paths, URLs, etc., from the config XML) ...

        # --- 3. Check if Version is Already Deployed ---
        $hasBeenDeployed = Test-VersionHasBeenDeployed $releaseVersion $targetConnectionString $flywayHistoryTable
        Write-Host "Version '$releaseVersion' has already been deployed: $hasBeenDeployed"

        # --- 4. Handle Previously Failed Deployments ---
        if ($hasBeenDeployed -and -not $isRedeploy) {
            # Logic to find and rename old SQL files from a previously failed run to prevent re-execution.
        }

        # --- 5. Determine Script Filename ---
        $scriptFilename = Get-Filename $releaseVersion $database $hasBeenDeployed
        $filepath = Join-Path $scriptPath $scriptFilename

        # --- 6. Build the Database Project ---
        Build-DatabaseProject $solution $project $logfile

        # --- 7. Generate the Deployment Script ---
        GenerateDeployScript -dacfxPath $dacfxPath -dacpac $dacpac -publishXml $publishXml -targetConnectionString $targetConnectionString -filepath $filepath -database $database -logfile $logfile

        # --- 8. Prepare for Flyway ---
        # Calls a function to create the final migration file and sets Octopus variables for the Flyway step.
        $flywayParams = ExecuteFlywayCreate $credentials $releaseVersion $baselineversion $appEnv $flywayPath $flywayHistoryTable $hasBeenDeployed $config.app.name $logfile
        Set-OctopusVariable -name "URL" -value $flywayParams.url
        # ... (Set other Flyway variables) ...

        # --- 9. Package and Push Artifacts to Octopus ---
        $packageId = "$database.$($flywayParams.target).zip"
        $packagePath = Join-Path $flywayParams.locations $packageId
        Write-Host "Packing and pushing Flyway package: $packageId"
        & octo pack --id=$database --format="zip" --version="$($flywayParams.target)" --basePath="$($flywayParams.locations)" --outFolder="$($flywayParams.locations)" --include="$($flywayParams.generated_file)" --overwrite
        & octo push --package="$packagePath" --server="$env:OCTOPUS_URL" --apiKey="$env:OCTOPUS_API_KEY" --overwrite-mode=OverwriteExisting
    }
    catch {
        # ... (Error handling) ...
    }
}

function Publish-ImportantSchemaChanges {
<#
.SYNOPSIS
    Parses a generated SQL script and sends a summary of important changes to Slack.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)] [string]$target,
        [Parameter(Mandatory=$True)] $config
    )
    
    try {
        # ... (Logic to find the generated SQL file) ...
        $scriptContent = Get-Content -Path $deployfile -Raw

        # --- Parse for Different Change Types ---
        $createTableCommands = ($scriptContent | Select-String -Pattern 'CREATE TABLE' -AllMatches).Matches.Value
        $addColumnCommands = ($scriptContent | Select-String -Pattern 'ALTER TABLE .* ADD ' -AllMatches).Matches.Value
        # ... (Add more patterns for DROP, ALTER, REBUILD etc.) ...

        # --- Build Slack Message ---
        $output = "*$($config.app.name) V$version Deployed to STG!* <!here>`n"
        $output += "Below are the key schema changes for the upcoming PROD deployment:`n`n"
        if ($createTableCommands) { $output += "*NEW TABLES*`n$($createTableCommands -join "`n")`n`n" }
        if ($addColumnCommands) { $output += "*NEW COLUMNS*`n$($addColumnCommands -join "`n")`n`n" }
        # ... (Add other sections) ...

        # --- Send Slack Notification ---
        $payload = @{
            channel = "#datawizards"
            text = $output
        } | ConvertTo-Json
        Invoke-WebRequest -Uri "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX" -Method Post -Body $payload -ContentType "application/json"
    }
    catch {
        # ... (Error handling) ...
    }
}

function Refresh-CDC {
<#
.SYNOPSIS
    Executes a predefined SQL script to refresh Change Data Capture on tables.
#>
    [CmdletBinding()]
    Param(
        # ... (Parameters for config, env, credentials) ...
    )
    $connection = $null
    try {
        # ... (Logic to load config and build connection string) ...
        
        $scriptContent = Get-Content -Path '.\Refresh_CDC_for_new_and_modified_tables.sql' -Raw -Replace 'GO', ''
        
        $connection = New-Object System.Data.SQLClient.SQLConnection($targetConnectionString)
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 0 # No timeout
        $command.CommandText = $scriptContent
        $cdcOutput = $command.ExecuteScalar()

        if ($cdcOutput) {
            Write-Host "--- CDC VALIDATION OUTPUT ---"
            Write-Host $cdcOutput
        }
    }
    catch {
        # ... (Error handling) ...
    }
    finally {
        if ($connection) { $connection.Close() }
    }
}
