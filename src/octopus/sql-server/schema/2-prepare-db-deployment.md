# Octopus Deploy: Database Build and Deploy Script

## 1. Overview

This PowerShell script is a comprehensive orchestration engine for building and deploying database changes within an Octopus Deploy process. It is designed to be executed by a build agent (such as a Jenkins slave or an Octopus Worker) and acts as the central point for a database CI/CD pipeline.

The script does not contain the deployment logic itself, but rather sources a set of modular PowerShell libraries (`.ps1` files) and calls a master function (`DeployDatabaseVersion`) to execute the full workflow. This includes fetching source code from Git, retrieving credentials, and running the database migration tools.

---

## 2. Features

* **Modular Design**: Separates configuration and orchestration from the core deployment logic, which is expected to be in dependent function files (`GitFunctionsOctopus.ps1`, `DacPacFunctionsOctopus.ps1`, etc.).
* **Secure Credential Handling**: Retrieves database and Git credentials from Octopus variables at deploy-time, with database passwords being fetched securely from AWS Secrets Manager.
* **Dynamic Git Checkout**: Intelligently determines whether the provided Git reference is a tag, branch, or commit hash to perform the correct checkout operation.
* **Environment-Specific Workspaces**: Remaps the source code checkout path to an environment-specific directory to prevent conflicts between concurrent deployments.
* **Robust Error Handling**: Uses a `try/catch/finally` block to ensure that the deployment status is always captured and reported back to Octopus Deploy, even if a step fails.
* **Centralized Logging**: Creates a detailed, timestamped log file for each deployment, capturing all output and errors for easy troubleshooting.

---

## 3. Setup in Octopus Deploy

This script should be configured as a "Run a Script" step in your Octopus Deploy project, typically after an "Assume Role" step if you are using temporary AWS credentials.

* **Step Name**: A descriptive name like `Build and Deploy Database`.
* **Script Source**: Copy and paste the PowerShell code into the script editor.
* **Execution Location**: This script must run on an Octopus Worker that has the following prerequisites:
    * **Git** installed and available in the system's PATH.
    * **AWS CLI** installed and available in the system's PATH.
    * Any required database build tools (e.g., **MSBuild** for DACPACs) and migration tools (e.g., **Flyway CLI**).
    * The necessary PowerShell function libraries (`GitFunctionsOctopus.ps1`, `DacPacFunctionsOctopus.ps1`, etc.) must be present in the script's working directory.

### 3.1. Required Octopus Variables

This script relies on variables passed from Octopus Deploy. Many of these will likely be output variables from a previous step (like the validation script or an AWS assume role step).

| **Variable Name** | **Description** | **Example Value** |
| :--- | :--- | :--- |
| `Step.SECRET_ID` | The ID of the secret in AWS Secrets Manager containing the database password. | `prod/mydatabase/credentials` |
| `Step.REGION` | The AWS region where the secret is stored. | `us-east-1` |
| `Step.GIT_USERNAME` | The username for authenticating with your Git repository. | `octopus-ci` |
| `Step.GIT_PASSWORD`| **(Sensitive)** The personal access token or password for the Git user. | `gittoken_...` |
| `Step.CONFIG_FILE`| The path to the environment-specific XML configuration file for the database. | `C:\path\to\config.xml` |
| `Step.ENV` | The target deployment environment (e.g., dev, test, prod). | `prod` |
| `Step.DATABASE` | The name of the database schema being deployed. | `CustomerDB` |
| `Step.PATH` | The root path for checking out the source code. | `C:\src` |
| `Step.DEPLOY_TYPE`| The deployment strategy, e.g., "trunkBase" or "tagBased". | `trunkBase` |
| `RELEASE` | **Required.** The Git branch, tag, or commit hash to be deployed. | `v1.2.4` |
| `BUILD_VERSION` | The unique build version or full commit hash, used for trunk-based deploys. | `2023.4.1.5678` |

---

## 4. How It Works

1.  **Initialization**: The script sets its working directory and loads all the necessary helper function libraries.
2.  **Load Variables**: It retrieves all required parameters—credentials, paths, and deployment targets—from Octopus variables.
3.  **Fetch Credentials**: It uses the AWS CLI to connect to AWS Secrets Manager and securely fetches the database username and password.
4.  **Execute Deployment**: The script enters a `try` block to safely execute the main deployment logic.
    * It determines if the Git reference (`RELEASE` variable) is a tag or a branch/commit.
    * It prepares a unique log file for the operation.
    * It calls the `DeployDatabaseVersion` function, passing all the prepared parameters. This external function is expected to handle the `git checkout`, database build, and migration execution.
5.  **Capture Status**:
    * If the `DeployDatabaseVersion` function completes without throwing an error, the `try` block finishes, and the script sets the final status to "SUCCEEDED".
    * If any command within the `try` block fails, the `catch` block is triggered. It captures the error message and sets the final status to "FAILED".
6.  **Finalize**: The `finally` block runs regardless of success or failure. It writes the final status message to the console, appends it to the log file, and sets the `COMPLETED` output variable in Octopus Deploy for downstream steps or notifications.