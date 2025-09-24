####################################################################################################################################
# SCRIPT: cleanup_on_flyway_error.ps1
# PURPOSE: This script is designed to run after a failed Flyway database deployment. It cleans up both the database
#          by removing the failed migration entry from the Flyway history table and the local filesystem by deleting
#          the script files associated with the failed version.
# CONTEXT: Intended to be executed as part of an automated CI/CD pipeline (e.g., Octopus Deploy) on a deployment failure.
####################################################################################################################################


####################################################################################################################################
# 1. INITIALIZATION AND ENVIRONMENT SETUP
####################################################################################################################################

# Set the script's execution location to the root of the database deployment project.
Set-Location "C:\src\Database-deployment\GenericDB"

# Dynamically construct the path to the environment-specific configuration file.
# The '$DATABASE' variable is expected to be provided by the deployment tool (Octopus Deploy).
$configFile = 'C:\src\Database-deployment\GenericDB\config\{0}.xml' -f $DATABASE;

# Source (import) helper PowerShell scripts containing required functions.
# These modules likely contain functions for deploying, managing Flyway, and interacting with Git.
. .\DeployDatabaseVersionsGenericDBOctopus.ps1
. .\FlywayFunctionsGenericDBOctopus.ps1
. .\GitFunctionsGenericDBOctopus.ps1

####################################################################################################################################
# 2. AWS AUTHENTICATION
####################################################################################################################################

# Retrieve temporary AWS credentials from a preceding "AWS Assume Role" step in Octopus Deploy.
# This is a secure way to grant the script permissions without storing long-lived credentials.
$env:AWS_ACCESS_KEY_ID = $OctopusParameters['Octopus.Action[AWS Assume Role].Output.AWS_ACCESS_KEY_ID']
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters['Octopus.Action[AWS Assume Role].Output.AWS_SECRET_ACCESS_KEY']
$env:AWS_SESSION_TOKEN = $OctopusParameters['Octopus.Action[AWS Assume Role].Output.AWS_SESSION_TOKEN']


####################################################################################################################################
# 3. CONFIGURATION LOADING
####################################################################################################################################

# Load all environment configurations from the specified XML file using a custom function.
$config = LoadEnvironmentDetails $configFile

# Find the specific configuration block for the environment being deployed to (e.g., 'dev', 'staging', 'prod').
# The '$SELECT_ENVIRONMENT' variable is provided by the deployment tool.
$result = $false
$index = 0
$environments = $config.app.environments.environment
foreach($environment in $environments){
	If($environment.name -match $SELECT_ENVIRONMENT){
		$result = $true
		break
	}
    
	$index+=1
}

# Store the configuration for the target environment in its own variable.
$appEnv = @($config.app.environments.environment)[$index]

# Extract global and environment-specific settings from the loaded config object.
[string] $CompanyGitURL = $config.app.global.CompanyGitURL
[string] $Engine = $config.app.global.engine # E.g., 'mysql', 'postgresql'
[string] $DEPLOY_TYPE = $config.app.global.DeployType
[string] $secretid = $appEnv.connection.AWSSecretId # AWS Secrets Manager Secret ID
[string] $region = $config.app.global.AWSRegion # AWS Region
[string] $RootScriptsPath = $config.app.global.RootScriptsPath # Base path for SQL scripts
[string] $CheckoutPath = $config.app.global.filePath # Path for Git checkout

####################################################################################################################################
# 4. DATABASE CREDENTIALS AND CONNECTION
####################################################################################################################################

# Retrieve the database credentials securely from AWS Secrets Manager using the AWS CLI.
# The secret is expected to be a JSON string with 'username' and 'password' keys.
$secretvalue = (aws secretsmanager get-secret-value --secret-id $secretid --region $region --query SecretString --output text)   | ConvertFrom-Json 

# Create a PowerShell credential object for secure handling of the password.
[string] $username = $secretvalue.username
[securestring] $securePassword = ConvertTo-SecureString $secretvalue.password -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential ($username, $SecurePassword) 

# Construct the full path where SQL scripts for the current environment are stored.
[string] $ScriptsPath = $RootScriptsPath + $SELECT_ENVIRONMENT + '\'

# Build the ODBC database connection string using the details from the config and the retrieved credentials.
$Driver = $appEnv.connection.odbc
$MyServer = $appEnv.connection.url
$MyPort = $appEnv.connection.port
$MyDB = $appEnv.connection.database
$MyUid = $credentials.UserName
$MyPass = $credentials.GetNetworkCredential().Password
[string] $datasource = "$Driver;Server=$MyServer;Port=$MyPort;Database=$MyDB;Uid=$MyUid;Pwd=$MyPass;"


####################################################################################################################################
# 5. DETERMINE LATEST DEPLOYED VERSION
####################################################################################################################################

# Alias the Octopus release variable '$RELEASE' to '$BRANCH_TAG' for clarity in the script's context.
$BRANCH_TAG = $RELEASE

# Get the name of the Flyway schema history table from the config.
[string] $flywayHistoryTable = $config.app.global.schemaHistoryTable

# Call a custom function to query the database and get the latest version number recorded in the Flyway history table.
$LatestDeployed = LatestVersionDeployed $BRANCH_TAG $datasource $flywayHistoryTable $Engine

Write-Host "Lastest Deploy on DB: $LatestDeployed"

# Parse the version string returned from the database to extract a clean version number (e.g., "1.2.3").
# This handles different formats that might be stored (e.g., "V1.2.3", "R1.2", etc.).
if ($LatestDeployed -match '\d+\.\d+\.\d+'){
    $version = $Matches[0]
}else{
     if ($LatestDeployed -match '\d+\.\d+'){
            $version = $Matches[0]
     }else{
            $version = $LatestDeployed
     }    
}

####################################################################################################################################
# 6. CONDITIONAL CLEANUP LOGIC
####################################################################################################################################

try {
    # The core logic: check if the version that was supposed to be deployed ($BRANCH_TAG) matches the last
    # version recorded in the database ($version). If they match, it means the failed deployment *did* start
    # and made an entry in the history table, so a cleanup is required.
    if ($BRANCH_TAG.Contains($version)){
    
        Write-Host "Matched Version? $version"
        Write-Host "Matched Branch/Tag? $BRANCH_TAG"

        # Determine if this was a standard versioned migration ('V') or a repeatable migration ('R').
        # The '$REDEPLOY' variable is provided by the deployment tool.
        if ($REDEPLOY -eq 'True'){
            $current = "R" # Repeatable
        }else {
            $current = "V" # Versioned
        }

        Write-Host "Redeploy? $current"

        # Call the function to clean the database. This likely runs a DELETE command on the Flyway history table
        # for the specified version to allow the migration to be attempted again.
        CleanDatabase $version $datasource $flywayHistoryTable $Engine $REDEPLOY
    
        # Call the function to clean the local filesystem. This deletes the SQL script files that were
        # checked out or created for this specific version.
        CleanFiles $version $ScriptsPath $current 
    
    }else {
        # If the versions do not match, it implies the deployment failed before Flyway could even start
        # or record an entry in its history table. Therefore, no database cleanup is necessary.
        Write-Host "NOT Matched Version? $version"
        Write-Host "NOT Matched Branch/Tag? $BRANCH_TAG"
    
        Write-Host "No clean up needed because no deploy was actually made!"
    }

} catch {
    # Standard error handling block to catch any exceptions during the cleanup process.
    Write-Host "An error occurred while deleting data:"
    Write-Host $_.Exception.Message
    throw # Re-throw the exception to ensure the deployment tool registers the step as failed.
    exit 1
} finally {
    # This block will always execute, confirming the completion of the cleanup attempt.
    Write-Host "The delete operation is complete."
}