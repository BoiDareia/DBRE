####################################################################################################################################
# Validate variables that will be used in the deployment script
####################################################################################################################################

# Set the script's execution location to the source code directory.
Set-Location "C:\src\Database-deployment\GenericDB"

## Construct the path to the environment configuration file based on the database name.
# The '$DATABASE' variable is expected to be provided by the deployment tool (e.g., Octopus Deploy).
$configFile = 'C:\src\Database-deployment\GenericDB\config\{0}.xml' -f $DATABASE;

# Source (import) other PowerShell scripts, making their functions available in this script.
# These likely contain functions for deployment, Flyway operations, and Git interactions.
. .\DeployDatabaseVersionsGenericDBOctopus.ps1
. .\FlywayFunctionsGenericDBOctopus.ps1
. .\GitFunctionsGenericDBOctopus.ps1

## Get temporary AWS session variables from a previous Octopus Deploy step named "AWS Assume Role".
# This is a secure way to grant this script permissions to access AWS resources.
$env:AWS_ACCESS_KEY_ID = $OctopusParameters['Octopus.Action[AWS Assume Role].Output.AWS_ACCESS_KEY_ID']
$env:AWS_SECRET_ACCESS_KEY = $OctopusParameters['Octopus.Action[AWS Assume Role].Output.AWS_SECRET_ACCESS_KEY']
$env:AWS_SESSION_TOKEN = $OctopusParameters['Octopus.Action[AWS Assume Role].Output.AWS_SESSION_TOKEN']


## Load the configuration settings from the specified XML file.
# The 'LoadEnvironmentDetails' function is likely defined in one of the sourced scripts.
$config = LoadEnvironmentDetails $configFile

# Initialize variables for searching for the correct environment configuration.
$result = $false
$index = 0
$environments = $config.app.environments.environment
# Loop through the environments defined in the config file.
foreach($environment in $environments){
	# Check if the environment name matches the one selected for deployment ('$SELECT_ENVIRONMENT').
	If($environment.name -match $SELECT_ENVIRONMENT){
		$result = $true
		break # Exit the loop once the correct environment is found.
	}
    
	$index+=1 # Increment the index to track the position of the correct environment.
}

# Get the specific environment configuration block using the found index.
$appEnv = @($config.app.environments.environment)[$index]

# Extract global and environment-specific settings from the loaded config object.
[string] $CompanyGitURL = $config.app.global.CompanyGitURL
[string] $Engine = $config.app.global.engine
[string] $DeployType = $config.app.global.DeployType
## Gets the AWS Secret ID from the config file for the target environment.
[string] $secretid = $appEnv.connection.AWSSecretId
## Gets the AWS Region from the config file.
[string] $region = $config.app.global.AWSRegion

## Use the AWS CLI to retrieve the database credentials from AWS Secrets Manager.
# The secret value is a JSON string, which is then converted to a PowerShell object.
$secretvalue = (aws secretsmanager get-secret-value --secret-id $secretid --region $region --query SecretString --output text) | ConvertFrom-Json 
[string] $username = $secretvalue.username
# Convert the plain text password to a SecureString for better security.
[securestring] $securePassword = ConvertTo-SecureString $secretvalue.password -AsPlainText -Force
# Create a PSCredential object, which is a standard way to handle credentials in PowerShell.
$credentials = New-Object System.Management.Automation.PSCredential ($username, $SecurePassword) 

# Get data source details from the config file for Aurora DBs.
$Driver = $appEnv.connection.odbc
$MyServer = $appEnv.connection.url
$MyPort = $appEnv.connection.port
$MyDB = $appEnv.connection.database
$MyUid = $credentials.UserName
$MyPass = $credentials.GetNetworkCredential().Password # Extract the plain text password from the credential object.
# Build the ODBC connection string.
[string] $datasource = "$Driver;Server=$MyServer;Port=$MyPort;Database=$MyDB;Uid=$MyUid;Pwd=$MyPass;"


## Normalize the incoming release variable '$RELEASE' into '$BRANCH_TAG' for consistent use.
$BRANCH_TAG = $RELEASE

## Gets the local path for the Git repository checkout from the config file.
[string] $CheckoutPath = $config.app.global.filePath

## Validate if '$BRANCH_TAG' is a standard tag (e.g., v1.2.3) or a branch name that contains a tag.
# This block of code parses different formats to extract a clean release version string.
if ($BRANCH_TAG -notmatch '^v\d+\.\d+\.\d+$' -and $BRANCH_TAG -notmatch '^v\d+\.\d+$'){
	# Handles formats like 'feature/v1.2.3'
	if ($BRANCH_TAG -match '^[A-Za-z0-9]+/v\d+\.\d+\.\d+'){
		$BRANCH_TAG -match 'v\d+\.\d+\.\d+'
		$release = $Matches[0]
	}else{
        # Handles formats like 'feature/v1.2'
        if ($BRANCH_TAG -match '^[A-Za-z0-9]+/v\d+\.\d+'){
		$BRANCH_TAG -match 'v\d+\.\d+'
		$release = $Matches[0]
	    }else{
            # Handles pre-release formats like 'v1.2.3-alpha'
            if ($BRANCH_TAG -match '^v\d+\.\d+\.\d+\-[A-Za-z0-9]'){
		        $BRANCH_TAG -match 'v\d+\.\d+\.\d+'
		        $release = $Matches[0]
	        }else{
                # Handles pre-release formats like 'v1.2-beta'
                if ($BRANCH_TAG -match '^v\d+\.\d+\-[A-Za-z0-9]'){
		            $BRANCH_TAG -match 'v\d+\.\d+'
		            $release = $Matches[0]
	            }else{
		            ## If no version format matches, assume it's a commit hash or a non-standard branch name.
		            $release = $BRANCH_TAG
                    Write-Host "Release Hash? $release"
                 }
            }
        }
	}
}else{
	# If it's already a standard tag format, use it directly.
	$release = $BRANCH_TAG
}

Write-Host "Release? $release"
Write-Host "Branch/Tag? $BRANCH_TAG"

## Determine if the deployment is from a branch ('main') or a tag.
if ($BRANCH_TAG -eq 'main'){
    	[bool]$IsTag = $false
}else{
	## Check if the branch/tag name matches a version pattern or if the deployment type is 'trunkBase'.
	if ($BRANCH_TAG -match '^\w\d+.\d+.\d+$' -or $BRANCH_TAG -match '^\w\d+\.\d+$' -or $DeployType -eq 'trunkBase'){
		[bool]$IsTag = $true
	}else{
		[bool]$IsTag = $false
    }
}

## Checkout the specified branch or tag from the Git repository.
# The 'GitCheckoutBranch' function is defined in one of the sourced scripts.
GitCheckoutBranch $CheckoutPath $CompanyGitURL $BRANCH_TAG $IsTag $False

## --- Validation to see if there are database changes to deploy --- ##
[String] $Totag = $BRANCH_TAG

# Get the latest version number that was successfully deployed to the target database.
# This is done by querying the Flyway schema history table.
[string] $flywayHistoryTable = $config.app.global.schemaHistoryTable
$LatestDeployed = LatestVersionDeployed $BRANCH_TAG $datasource $flywayHistoryTable $Engine

Write-Host "Lastest Deploy on DB: $LatestDeployed"

## Parse the version returned from the database to ensure it's in a clean 'x.y.z' or 'x.y' format.
if ($LatestDeployed -match '\d+\.\d+\.\d+'){
    $version = $Matches[0]
}else{
     if ($LatestDeployed -match '\d+\.\d+'){
            $version = $Matches[0]
     }else{
            $version = $LatestDeployed
     }    
}

Write-Host "Matched Version? $version"

## Determine the "from" reference for the git diff command. This is the starting point for comparison.
## If the database has never been deployed to (version 0.0.0), start the comparison from the v0.0.0 tag.
if ($version -eq '0.0.0'){
    # This assumes a 'v0.0.0' tag exists for all new databases to serve as a baseline.
    $Fromtag = "v$version"
}else{
	# For 'releaseBranch' deployments to non-PROD environments, compare against the corresponding release branch (e.g., release/v1.2.3).
    if ($DeployType -eq 'releaseBranch' -and $SELECT_ENVIRONMENT -ne 'PROD'){
        $Fromtag = "release/v$version"
    }else{
		# For all other cases (PROD deployments, trunk-based), compare against the corresponding tag (e.g., v1.2.3).
        $Fromtag = "v$version"
    }
}

Write-Host "Deployed in $SELECT_ENVIRONMENT : $Fromtag"

# Convert the incoming '$REDEPLOY' string variable to a boolean.
[string] $strIsRedeploy = $REDEPLOY
[bool] $IsRedeploy = ($strisRedeploy -eq 'True')

Write-Host "Checking if it is REDEPLOY: $IsRedeploy"


## Use 'git diff' to check for any changes to .sql or manifest.txt files between the last deployed version and the current version.
$dif = git diff "$Fromtag..$ToTag" $CheckoutPath | Out-String -Stream | Select-String -Pattern ".sql", "manifest.txt"

# Analyze the diff output to decide if a deployment is needed.
if ($dif -like "*+++*"){ # '+++' in a git diff indicates new files or additions.
	# Check if a manifest file was changed and if the deployment type is trunk-based.
	if ($dif -like "*+++*manifest*.**" -and $DeployType -eq 'trunkBase'){
		Write-Host "Has Manifest File and It's Trunk base Deployment"
		$Deployment = "Will do TBD Deploment!"
	}else{
		# For all other cases with changes (with/without manifest in releaseBranch), proceed with a release branch deployment.
    	if ($dif -like "*+++*manifest*.**" -and $DeployType -eq 'releaseBranch'){
			Write-Host "Has Manifest File and It's release branch Deployment"
        	$Deployment = "Will do Release Branch Deploment!"
		}else{
        	Write-Host "No Manifest File so It's release branch Deployment"
        	$Deployment = "Will do Release Branch Deploment!"
        }
	}
}else{
	# If no changes are found in the git diff...
	if ($IsRedeploy -eq $true){
		# ...but it's a manual redeploy, allow it to proceed.
		Write-Host "It's a redeploy so It's Trunk base Deployment"
		$Deployment = "Will do Release Branch Deploment!"
	}else{
		# ...and it's not a redeploy, cancel the deployment.
		Write-Host "Nothing to Deploy, no DB changes found between [ $Fromtag ] and [ $ToTag ]"
      	$Deployment = ""
      	$DeploymentCancelled = "There are no DB changes to be made at all!"
    }
}

## --- PROD Safety Check --- ##
# If the target is PROD and the deployment source is not a tag, block the deployment and throw an error.
if ($IsTag -eq $false -and $SELECT_ENVIRONMENT -eq 'PROD'){
        $Deployment = ""
      	$DeploymentCancelled = "You can't deploy a release branch into PROD, please check if a TAG is created and SET on the DB ticket (Label) and reach out to the DBAs!"
        throw "You can't deploy a release branch into PROD, please check if a TAG is created and SET on the DB ticket (Label)!!"
}


## Set Octopus variables that can be used by subsequent steps in the deployment process.
Set-OctopusVariable -name "Deployment" -value $Deployment
Set-OctopusVariable -name "DeploymentCancelled" -value $DeploymentCancelled
Set-OctopusVariable -name "LastDeployed" -value $Fromtag
Set-OctopusVariable -name "IsTag" -value $IsTag
Set-OctopusVariable -name "Engine" -value $Engine