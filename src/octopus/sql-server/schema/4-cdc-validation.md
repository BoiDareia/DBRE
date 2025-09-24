# Octopus Deploy: CDC Refresh Script

## 1. Overview

This PowerShell script is a utility step designed to be used within an Octopus Deploy process to manage Change Data Capture (CDC) in a database. Its specific purpose is to invoke a custom function, `RefreshCDC`, which is responsible for identifying and manually refreshing CDC on any tables that might have been missed by automated processes.

The script securely handles database credentials by retrieving them at deploy-time from AWS Secrets Manager, using temporary AWS credentials provided by a preceding "Assume Role" step in the deployment process.

## 2. Features

* **Secure Credential Management**: Fetches database credentials on-the-fly from AWS Secrets Manager, avoiding the need to store sensitive information directly in Octopus variables.
* **Modular Functionality**: The core logic is encapsulated in an external function (`RefreshCDC`), making the script a clean and reusable orchestrator.
* **Robust Error Handling**: Utilizes a `try/catch/finally` block to ensure that any failures in the CDC refresh process are caught, logged clearly, and cause the Octopus step to fail correctly.
* **Seamless Integration**: Designed to work with output variables from previous Octopus steps, such as an "AWS Assume Role" step and a "Variable Check" step.

## 3. Setup in Octopus Deploy

This script should be configured as a "Run a Script" step in your deployment process. It should be placed **after** the steps that provide its input variables.

* **Step Name**: A descriptive name like `Refresh Change Data Capture`.
* **Script Source**: Copy and paste the PowerShell code into the script editor.
* **Execution Location**: This script must run on an Octopus Worker that has:
    * **AWS CLI** installed and available in the system's PATH.
    * The `DeployDatabaseVersionsOctopus.ps1` script (containing the `RefreshCDC` function) located in the specified working directory (`C:\src\Database-deployment\SQLSchema`).

### 3.1. Required Input Variables (from Previous Steps)

This script does not use its own unique project variables. Instead, it relies entirely on the **output variables** from preceding steps in the Octopus process.

| **Variable Name** | **Description** | **Example Source Step** |
| :--- | :--- | :--- |
| `Octopus.Action[AWS Assume Role].Output.AWS_ACCESS_KEY_ID` | The temporary AWS Access Key. | `AWS Assume Role` |
| `Octopus.Action[AWS Assume Role].Output.AWS_SECRET_ACCESS_KEY` | The temporary AWS Secret Key. | `AWS Assume Role` |
| `Octopus.Action[AWS Assume Role].Output.AWS_SESSION_TOKEN` | The temporary AWS Session Token. | `AWS Assume Role` |
| `Octopus.Action[RDS SQL Variables Check].Output.SECRET_ID` | The ID of the secret in AWS Secrets Manager. | `RDS SQL Variables Check` |
| `Octopus.Action[RDS SQL Variables Check].Output.AWSREGION` | The AWS region where the secret is stored. | `RDS SQL Variables Check` |
| `Octopus.Action[RDS SQL Variables Check].Output.CONFIGFILE` | The path to the database configuration file. | `RDS SQL Variables Check` |
| `SELECT_ENVIRONMENT` | The target deployment environment (e.g., dev, prod). | (Project Variable) |

## 4. How It Works

1.  **Initialization**: The script sets its working directory and "dot-sources" the `DeployDatabaseVersionsOctopus.ps1` file, which makes the `RefreshCDC` function available to it.
2.  **Load Variables**: It reads the output variables from the specified previous steps (`AWS Assume Role`, `RDS SQL Variables Check`) to get the necessary credentials and configuration details.
3.  **Fetch Credentials**: Using the temporary AWS credentials, it calls the AWS CLI to retrieve the database connection secret from AWS Secrets Manager. It then securely converts the password into a `PSCredential` object.
4.  **Execute Logic**: The script enters a `try` block and calls the `RefreshCDC` function, passing the configuration file path, environment name, and the secure credential object as parameters.
5.  **Handle Outcome**:
    * If `RefreshCDC` completes successfully, the script logs a success message and exits with a code of `0`.
    * If `RefreshCDC` throws an error, the `catch` block is triggered. It captures the exception details, writes a formatted error message to the log, and sets the exit code to `1`, which fails the Octopus deployment step.
    * The `finally` block ensures the script always exits with the correct code.