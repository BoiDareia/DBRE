# Octopus Deploy: Database Deployment Validation Script

## 1. Overview

This PowerShell script serves as a critical pre-deployment validation step for database changes within an Octopus Deploy process. Its primary purpose is to intelligently determine if a database deployment (schema and/or data) is actually necessary.

It does this by comparing the Git version (tag or commit hash) you intend to deploy with the last version successfully deployed to the target database. It inspects the Git history between these two points for any relevant `.sql` file changes. If no changes are found, it sets an Octopus variable to gracefully skip the subsequent, potentially long-running, deployment steps like `Flyway migrate`.

---

## 2. Features

* **Configuration-Driven**: All environment-specific settings (database URLs, AWS Secret IDs, etc.) are loaded from a central XML configuration file.
* **Git-Aware**: Checks out the specified version of the database code from Git.
* **Secure Credential Management**: Fetches database credentials at deploy-time from AWS Secrets Manager.
* **Change Detection**: Performs a `git diff` to see if any `.sql` files have actually changed between the last deployed version and the target version.
* **Schema & Data Separation**: Can distinguish between schema-only, data-only, or combined deployments. For data deployments, it specifically looks for a `manifest.txt` file to ensure intentional changes.
* **Dynamic Control Flow**: Sets Octopus output variables (`DeploymentSchema`, `DeploymentData`, `DeploymentCancelled`) that can be used in the run conditions of subsequent steps to control the deployment workflow.
* **Idempotent & Safe**: Prevents re-deploying the same version and avoids unnecessary deployments when no code has changed.

---

## 3. Setup in Octopus Deploy

This script should be the **first step** in your database deployment process, running before any actual database migration steps (e.g., Flyway).

* **Step Name**: A descriptive name like `Validate Database Changes`.
* **Script Source**: Copy and paste the PowerShell code into the script editor.
* **Execution Location**: This script must run on an Octopus Worker with the following prerequisites:
    * **Git** installed and available in the system's PATH.
    * **AWS CLI** installed and available in the system's PATH.
    * An AWS IAM identity (via instance profile or configured credentials) with permissions for `secretsmanager:GetSecretValue`.
    * Access to the required PowerShell modules (`GitFunctionsOctopus.ps1`, etc.).

### 3.1. Required Octopus Variables

The script relies on several variables being available in your Octopus project.

| **Variable Name** | **Description** | **Example Value** |
| :--- | :--- | :--- |
| `DATABASE` | The name of the database being deployed. Used to locate the config file. | `CustomerDB` |
| `REGION` | The geographical or logical region. Used to locate the config file. | `EU` |
| `SELECT_ENVIRONMENT` | The target deployment environment (e.g., dev, test, prod). | `dev` |
| `BRANCH_TAG` | **Required.** The Git branch, tag, or commit hash to be deployed. | `v1.2.3` or `main` |
| `STEP_BUILD_VERSION` | The build version or commit hash, typically used for trunk-based prod deploys. | `a1b2c3d4` |
| `REDEPLOY` | A boolean flag (`True`/`False`) to force a re-deployment check against an older version. | `False` |
| `DEPLOYMENT_TIME` | The phase of the deployment, used to find data scripts. | `BeforeDeploy` |
| `STATUS` | The status of the deployment, used to find data scripts. | `Rollout` |
| `SCHEMA` | An input flag, usually from a previous step, indicating if schema has been handled. | `0` |
| `GIT_USER` | The username for authenticating with your Git repository. | `octopus-ci` |
| `GIT_TOKEN` | **(Sensitive)** The personal access token or password for the Git user. | `gittoken_...` |

---

## 4. How It Works

1.  **Load Config**: The script starts by constructing the path to a region-specific XML config file (e.g., `CustomerDB_EU_Release.xml`) and loads all settings. If the file doesn't exist, it assumes the database isn't applicable to this region and cancels the deployment.
2.  **Determine Version**: It parses the `$BRANCH_TAG` variable to extract a clean release tag or commit hash that will be checked out from Git.
3.  **Checkout Code**: It checks out the specified version of the database code into a local directory.
4.  **Fetch Credentials**: It connects to AWS Secrets Manager to retrieve the username and password for the target database.
5.  **Get Last Deployed Version**: The script connects to the target database and queries the Flyway schema history table (e.g., `flyway_schema_history`) to find the version tag/description of the most recent successful deployment.
6.  **Compare Versions**: It performs a `git diff` between the last deployed version (`FromTag`) and the version being deployed (`ToTag`).
    * For **schema changes**, it looks for any `.sql` file modifications outside of the designated data folder.
    * For **data changes**, it looks for `.sql` file modifications *and* the presence of a `manifest.txt` file within a specific folder structure (`/Data/{DeploymentTime}/{Status}`).
7.  **Set Output Variables**: Based on the results of the `git diff`, it sets the following boolean-style output variables:
    * `DeploymentSchema = "1"`: If schema changes were found.
    * `DeploymentData = "1"`: If valid data changes were found.
    * `DeploymentCancelled = "Reason..."`: If no changes were found or if the versions are the same.
8.  **Control Subsequent Steps**: Your next steps in Octopus (e.g., "Flyway Migrate - Schema", "Flyway Migrate - Data") should have their **Run Condition** set to "Variable", checking if the corresponding output variable (e.g., `#{Octopus.Action[Validate Database Changes].Output.DeploymentSchema}`) has a value of `1`.