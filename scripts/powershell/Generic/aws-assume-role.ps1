<#
.SYNOPSIS
    Assumes an AWS IAM Role using the AWS CLI and exports the temporary security credentials
    for use in subsequent Octopus Deploy steps.

.DESCRIPTION
    This script calls the `aws sts assume-role` command with a given Role ARN and session name.
    It parses the temporary credentials (Access Key, Secret Key, Session Token) from the JSON
    response and sets them as both Octopus output variables and environment variables for the
    current PowerShell session. This allows subsequent steps in the deployment to authenticate
    with AWS using the permissions of the assumed role.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    AWS CLI to be installed and configured on the Octopus worker.
                 Initial AWS credentials must be available for the script to be able to
                 run the `assume-role` command.
#>

#================================================================================
# 1. CONFIGURATION & INPUT VARIABLES
#================================================================================
# These variables should be configured in your Octopus Deploy project.

# The Amazon Resource Name (ARN) of the role to assume.
$RoleArn = $OctopusParameters["TMP_ROLE_ARN"]
# A unique identifier for the assumed role session.
$SessionName = $OctopusParameters["TMP_SESSION"]
# The AWS region to be used for AWS CLI commands.
$AwsRegion = $OctopusParameters["TMP_AWS_REGION"]
# The duration, in seconds, of the role session. Default is 1 hour (3600), max is 12 hours (43200).
$DurationSeconds = 43200
# The temporary file to store credentials from the AWS CLI command.
$CredFile = "awsCreds.json"

# --- Pre-flight Checks ---
if (-not $RoleArn) {
    Write-Error "Required Octopus variable 'TMP_ROLE_ARN' is missing. Please define it in your project."
    exit 1
}
if (-not $SessionName) {
    Write-Error "Required Octopus variable 'TMP_SESSION' is missing. Please define it in your project."
    exit 1
}

#================================================================================
# 2. EXECUTE AWS ASSUME ROLE COMMAND
#================================================================================
Write-Host "Attempting to assume role: $RoleArn"
Write-Host "Using session name: $SessionName"

try {
    # Execute the AWS CLI command to assume the role.
    # The output is redirected to a JSON file. Using -ErrorAction Stop to catch errors.
    & aws sts assume-role --role-arn $RoleArn --role-session-name $SessionName --duration-seconds $DurationSeconds --region $AwsRegion --output json > $CredFile
    Write-Host "Successfully received temporary credentials from AWS."
}
catch {
    Write-Error "Failed to assume AWS role. Please check the AWS CLI output and IAM permissions."
    # Output the error details from the AWS CLI if available.
    Write-Error $_.Exception.Message
    exit 1
}

#================================================================================
# 3. PARSE AND EXPORT CREDENTIALS
#================================================================================
Write-Host "Parsing credentials from '$CredFile'..."

# Read the JSON file and convert it into a PowerShell object.
$awsCredentials = Get-Content $CredFile -Raw | ConvertFrom-Json

# Extract the specific credential components.
$accessKey = $awsCredentials.Credentials.AccessKeyId
$secretKey = $awsCredentials.Credentials.SecretAccessKey
$sessionToken = $awsCredentials.Credentials.SessionToken

# --- Set Octopus Output Variables ---
# These variables will be available to subsequent steps in the deployment process.
Write-Host "Setting Octopus output variables for subsequent steps..."
Set-OctopusVariable -name "AWS_ACCESS_KEY_ID" -value $accessKey
Set-OctopusVariable -name "AWS_SECRET_ACCESS_KEY" -value $secretKey
Set-OctopusVariable -name "AWS_SESSION_TOKEN" -value $sessionToken

# --- Set Environment Variables for the Current Session ---
# These allow subsequent commands within THIS script step to use the new credentials.
Write-Host "Exporting credentials as environment variables for the current session..."
$env:AWS_ACCESS_KEY_ID = $accessKey
$env:AWS_SECRET_ACCESS_KEY = $secretKey
$env:AWS_SESSION_TOKEN = $sessionToken
$env:AWS_REGION = $AwsRegion

#================================================================================
# 4. VALIDATION
#================================================================================
Write-Host "Validation: Checking the new identity..."

try {
    # Use the new credentials to verify the identity.
    $identity = & aws sts get-caller-identity --output text --query "Arn"
    Write-Host "Successfully assumed role. Current identity is: $identity"
}
catch {
    Write-Warning "Could not validate the new AWS identity using 'get-caller-identity'."
}
finally {
    # Clean up the temporary credentials file.
    if (Test-Path $CredFile) {
        Remove-Item $CredFile
        Write-Host "Cleaned up temporary credential file."
    }
}

Write-Host "Script completed successfully."
