####################################################################################################################################
# Validate variables that will be used in the deployment script
####################################################################################################################################

# Retrieve initial parameters from the Octopus Deploy step variables.
[string] $env = $OctopusParameters['Step.ENV']
[string] $DATABASE = $OctopusParameters['Step.DATABASE']
[string] $ROLE_ARN = $OctopusParameters['Step.ROLE_ARN']
# Construct the full AWS IAM Role ARN using the account ID provided in the ROLE_ARN variable.
$ROLE_ARN='arn:aws:iam::{0}:role/dba-team-role'  -f $ROLE_ARN;

# Set the fully constructed ROLE_ARN as an Octopus output variable for use in subsequent steps.
Set-OctopusVariable -name "ROLE_ARN" -value $ROLE_ARN

# Normalize the environment name for consistency in other tools (e.g., S3 bucket naming).
switch($env) {
	"prod"{
    	## Adding environment variable to be used on the S3 Step
    	Set-OctopusVariable -name "ENVIRONMENT" -value 'production'
        break
	}
	"dev"{
    	## Adding environment variable to be used on the S3 Step
        Set-OctopusVariable -name "ENVIRONMENT" -value 'dev'
        break
        }
	"stg"{
    	## Adding environment variable to be used on the S3 Step
    	Set-OctopusVariable -name "ENVIRONMENT" -value 'staging' 
        break
    }
}


####################################################################################################################################
# Build, and deploy database changes for a version run on Windows-Octopus-slave
####################################################################################################################################
                    
# Set the error action preference to 'Stop' so the script will exit immediately if an error occurs.
$ErrorActionPreference = 'Stop'                
# Set the script's execution location to the source code directory.
Set-Location "C:\src\Database-deployment\GenericDB"

# Set temporary AWS credentials as environment variables from the Octopus Deploy step.
# These are likely from a preceding "AWS Assume Role" step.
$env:AWS_ACCESS_KEY_ID = $OctopusParameters['Step.AWS_ACCESS_KEY_ID']
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters['Step.AWS_SECRET_ACCESS_KEY']
$env:AWS_SESSION_TOKEN = $OctopusParameters['Step.AWS_SESSION_TOKEN']

## For testing purposes (currently commented out).
#Write-Host "Access Key: $env:AWS_ACCESS_KEY_ID"
#Write-Host "Secret Key: $env:AWS_SECRET_ACCESS_KEY"
#Write-Host "Secret Token: $env:AWS_SESSION_TOKEN"

# Set Octopus URL and API Key as environment variables for tools that might need to interact with the Octopus API.
$env:OCTOPUS_URL = $OctopusParameters['Step.OCTOPUS_URL']
$env:OCTOPUS_API_KEY = $OctopusParameters['Step.OCTOPUS_API_KEY']

# Source (import) other PowerShell scripts, making their functions available.
. .\DeployDatabaseVersionsGenericDBOctopus.ps1

## Construct the path to the configuration file based on the database name.
$configFile = 'C:\src\Database-deployment\GenericDB\config\{0}.xml' -f $DATABASE;

# Source additional required function scripts.
. .\\GitFunctionsGenericDBOctopus.ps1
. .\\BuildFunctionsGenericDB.ps1
. .\\FlywayFunctionsGenericDBOctopus.ps1
. .\\DeployDatabaseVersionsGenericDBOctopus.ps1

## Load the environment-specific configuration details from the XML file.
$config = LoadEnvironmentDetails $configFile

## Check the config to see if Flyway migrations can be run "out of order".
$outoforder = $config.app.global.OutOfOrder

## Gets the local Git repository checkout path from the config file.
[string] $CheckoutPath = $config.app.global.filePath

## Gets the AWS Region from the config file.
[string] $region = $config.app.global.AWSRegion

## Gets a flag from the config to determine if Flyway should use transactions.
[string] $transaction = $config.app.global.transaction

## Find the correct configuration block for the target environment inside the XML file.
$result = $false
$index = 0
$environments = $config.app.environments.environment
foreach($environment in $environments){
	If($environment.name -match $SELECT_ENVIRONMENT){
		$result = $true
		break # Exit the loop once the matching environment is found.
	}
    
	$index+=1
}

# Extract the specific environment configuration object.
$appEnv = @($config.app.environments.environment)[$index]

## Gets the AWS Secret ID for the database credentials from the config file.
[string] $secretid = $appEnv.connection.AWSSecretId


## Set deployment parameters based on user input or previous steps.
[string] $BranchName = $RELEASE # Can be a branch name or a Git tag.
# Determine if the deployment is from a tag based on a variable from a previous step.
if ($OctopusParameters['Step.IsTag'] -eq 'True'){
	[string] $strIsTag = $true
}else{
	[string] $strIsTag = $false
}
[string] $strIsRedeploy = $REDEPLOY

# Convert the string flags to boolean types for easier use in functions.
[bool] $IsTag = ($strIsTag -eq 'True')
[bool] $IsRedeploy = ($strisRedeploy -eq 'True')

# Retrieve the secret value (JSON string) from AWS Secrets Manager and convert it to a PowerShell object.
$secretvalue = (aws secretsmanager get-secret-value --secret-id $secretid --region $region --query SecretString --output text) | ConvertFrom-Json 
[string] $username = $secretvalue.username
# Convert the plain text password to a SecureString for creating a PSCredential object.
[securestring] $securePassword = ConvertTo-SecureString $secretvalue.password -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential ($username, $SecurePassword) 

## Setup credentials for Flyway.
# Get the password back in plain text from the credential object.
$PlainPassword = $credentials.GetNetworkCredential().Password 
# Special handling for passwords containing an ampersand (&), which can cause issues in command-line tools.
if($PlainPassword.Contains("&")){
	$PlainPassword=$PlainPassword.Replace("&","""&""")
}

$user = $credentials.UserName 

# Initialize variables for error handling.
[string] $toThrow = [string]::Empty 
$LastExitCode = 0 


## Set variables that will be used by subsequent steps in the Octopus Deploy process.
Set-OctopusVariable -name "OUTOFORDER" -value $outoforder
Set-OctopusVariable -name "AWS_REGION" -value $region
Set-OctopusVariable -name "FW_TRAN" -value $transaction
Set-OctopusVariable -name "SECRETMANAGERID" -value $secretid
Set-OctopusVariable -name "User" -value $user
Set-OctopusVariable -name "Password" -value $PlainPassword

try{
    # This block contains the main execution logic.
	.{
		## For testing purposes (currently commented out).
        #Write-Host "Variables that will be used. Secret: $secretid, Region: $region, Config File: $configFile, Environment: $env, Checkout Path: $CheckoutPath, Branch: $BranchName, Tag: $IsTag, RedeploY: $IsRedeploy, User: $username, Password: $securePassword "

        ## Call the main function to build and deploy the database changes.
        [string] $Output = DoDatabaseContinuousDeployment $configFile $env $credentials $BranchName $CheckoutPath $IsTag $IsRedeploy
      
	} | Out-Null # Suppress the direct output of the function call.
   
	return $Output

}
catch{
  # If an error occurs in the 'try' block, this 'catch' block will execute.
  $toThrow = ("Deployment failed: ''{0}'' Reason: ''{1}''" -f $_.Exception.Message, $_.Exception.PSMessageDetails)
  $LastExitCode = 1 # Set a non-zero exit code to indicate failure.
  
}
finally{
  # The 'finally' block will always execute, regardless of whether an error occurred.
  .{
    if ($toThrow){
        # If an error was caught, write it to the error stream and set the completion status to FAILED.
    	Write-Error $toThrow
    	Set-OctopusVariable -name "COMPLETED" -value "FAILED!! With: $toThrow"
        Write-Host #{COMPLETED}               
    }else{
        # If no error occurred, set the completion status to SUCCEEDED.
    	Set-OctopusVariable -name "COMPLETED" -value "SUCCEEDED!!"
        Write-Host #{COMPLETED} 
    }
    
   } | Out-Null

  # Exit the script with the final exit code (0 for success, 1 for failure).
  exit $LastExitCode
}
####################################################################################################################################