# Octopus Deploy AWS Assume Role Script

## 1. Overview

This PowerShell script is designed for use in an Octopus Deploy process to securely assume an AWS IAM Role. It retrieves temporary, short-lived credentials from the AWS Security Token Service (STS) and makes them available for subsequent steps in the deployment.

This is a best practice for providing AWS access to your deployments, as it avoids the need for long-lived IAM user credentials on your build servers or in your Octopus variables.

---

## 2. Features

* **Secure Authentication**: Uses AWS STS `assume-role` to get temporary credentials, enhancing security.
* **Session-Based**: Credentials are valid only for a specified duration (up to 12 hours).
* **Seamless Integration**: Automatically sets Octopus output variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) so subsequent steps can easily authenticate.
* **Environment Ready**: Also exports credentials as environment variables for use within the same script step.
* **Error Handling**: Includes checks to ensure the `assume-role` command succeeds and provides clear error messages if it fails.
* **Validation**: Automatically runs `aws sts get-caller-identity` to confirm the role was assumed successfully.

---

## 3. Setup in Octopus Deploy

To use this script, add a "Run a Script" step to your deployment process and configure the following.

* **Step Name**: A descriptive name like `Assume AWS Deploy Role`.
* **Script Source**: Copy and paste the PowerShell code into the script editor.
* **Execution Location**: This script must run on an Octopus Worker that has the **AWS CLI installed** and is configured with initial credentials that have permission to call `sts:AssumeRole` on the target role.

### 3.1. Required Octopus Variables

You need to define the following project variables for the script to use:

| **Variable Name** | **Description** | **Example Value** | **Sensitive** |
| :---------------- | :---------------------------------------------------------------------------------------------------------------- | :---------------------------------------------- | :------------ |
| `TMP_ROLE_ARN`    | **Required.** The Amazon Resource Name (ARN) of the IAM Role that you want the deployment to assume.                | `arn:aws:iam::123456789012:role/MyDeployRole`    | No            |
| `TMP_SESSION`     | **Required.** A unique name for the session. It's good practice to use Octopus variables to make this dynamic and traceable. | `Octopus-Deploy-#{Octopus.Release.Number}`       | No            |
| `TMP_AWS_REGION`  | The AWS region where your resources are located. This will be set as the `AWS_REGION` environment variable.         | `us-east-1`                                     | No            |

---

## 4. How It Works

1.  **Assume Role Command**: The script calls `aws sts assume-role` using the `TMP_ROLE_ARN` and `TMP_SESSION` variables provided by Octopus.
2.  **Capture Credentials**: The JSON output from the AWS CLI, which contains the temporary `AccessKeyId`, `SecretAccessKey`, and `SessionToken`, is saved to a temporary file.
3.  **Parse and Export**: The script reads the JSON file, extracts the credential values, and performs two actions:
    * It uses `Set-OctopusVariable` to create output variables. This makes the credentials available to **subsequent steps** in the same deployment. For example, a later step can use these by enabling the "AWS Account" feature in Octopus and selecting "AWS credentials from variables".
    * It sets local environment variables (`$env:AWS_...`). This makes the credentials immediately available to any AWS CLI commands that run **within the same script step**, right after the export.
4.  **Validation & Cleanup**: The script validates the new credentials with `get-caller-identity` and then deletes the temporary JSON file, ensuring no sensitive information is left on the worker's disk.