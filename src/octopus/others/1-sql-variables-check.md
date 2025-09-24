# Octopus Deploy: Database Deployment Validation Script

## 📜 Overview

This PowerShell script is a crucial pre-deployment step designed to run within an Octopus Deploy process. Its primary purpose is to **validate** and **prepare** variables for a database deployment.

The script automates the decision-making process by:
1.  Loading environment-specific configurations.
2.  Securely fetching database credentials from AWS Secrets Manager.
3.  Determining the last successfully deployed version by querying the database's schema history table.
4.  Performing a `git diff` to see if there are any actual database changes (`.sql` files) between the last version and the current release.
5.  Setting output variables to either **proceed with** or **cancel** the deployment based on the findings.

This prevents unnecessary deployments when no database changes have been made.


---

## ⚙️ Prerequisites

For this script to function correctly, the following must be in place:

* **Octopus Deploy Environment**: The script is intended to be run as a step in an Octopus Deploy project.
* **AWS Assume Role Step**: A preceding step named `AWS Assume Role` must run successfully to provide temporary AWS credentials.
* **Dependent Scripts**: The following PowerShell scripts must be present in the same execution directory:
    * `DeployDatabaseVersionsGenericDBOctopus.ps1`
    * `FlywayFunctionsGenericDBOctopus.ps1`
    * `GitFunctionsGenericDBOctopus.ps1`
* **Configuration File**: An XML configuration file must exist for the database being deployed (e.g., `C:\src\Database-deployment\GenericDB\config\MyDatabase.xml`).

---

## 📥 Input Variables

The script relies on the following variables being provided by Octopus Deploy:

| Variable Name           | Type    | Description                                                                                             | Example         |
| ----------------------- | ------- | ------------------------------------------------------------------------------------------------------- | --------------- |
| `$DATABASE`             | String  | The name of the database, used to locate its `.xml` config file.                                        | `CustomerDB`    |
| `$SELECT_ENVIRONMENT`   | String  | The target deployment environment (e.g., DEV, UAT, PROD).                                               | `PROD`          |
| `$RELEASE`              | String  | The Git branch, tag, or commit hash being deployed.                                                     | `v1.23.4`       |
| `$REDEPLOY`             | String  | A flag to force the deployment check even if no file changes are detected. Should be `'True'` or `'False'`. | `False`         |

---

## 🧠 Core Logic & Workflow

The script follows a logical sequence to determine if a deployment is necessary.

1.  **Initialization**: It sources helper functions and sets up temporary AWS credentials from the previous Octopus step.
2.  **Configuration Loading**: It loads the correct XML configuration file based on the `$DATABASE` and `$SELECT_ENVIRONMENT` variables.
3.  **Credential Fetching**: It uses the AWS CLI to retrieve the database username and password from AWS Secrets Manager and constructs a standard `PSCredential` object and a connection string.
4.  **Version Parsing**: The incoming `$RELEASE` variable is parsed and normalized to handle various formats like `v1.2.3`, `feature/v1.2.3`, and `v1.2.3-alpha`. This ensures a clean version string is used for comparisons.
5.  **Git Checkout**: The specified Git branch or tag is checked out to a local path.
6.  **Change Detection**:
    * It connects to the target database and queries the Flyway schema history table (e.g., `flyway_schema_history`) to find the most recent version tag deployed.
    * It then constructs and executes a `git diff` command to compare the codebase of the *last deployed tag* against the *current release tag*.
    * The diff specifically looks for changes in files ending in `.sql` or named `manifest.txt`.
7.  **Deployment Decision**:
    * **If changes are found**: The `$Deployment` variable is set to a value that signals subsequent steps to proceed.
    * **If NO changes are found**: The deployment is cancelled unless the `$REDEPLOY` flag is set to `True`.
8.  **PROD Safety Check**: As a final guardrail, the script checks if a deployment to the `PROD` environment is being attempted from a branch instead of a tag. If so, it throws an error and halts the process to prevent accidental deployments. 🚨

---

## 📤 Output Variables

After its analysis, the script sets the following Octopus Deploy output variables, which control the flow of the rest of the deployment pipeline:

| Variable Name           | Description                                                                                                                              | Example Value                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| `Deployment`            | A string that tells the next step what to do. If empty, the deployment is skipped.                                                       | `Will do Release Branch Deploment!` |
| `DeploymentCancelled`   | A human-readable message explaining why the deployment was cancelled.                                                                    | `There are no DB changes to be made at all!` |
| `LastDeployed`          | The "from" tag or branch that was used as the baseline for the `git diff` comparison.                                                      | `v1.23.3`                           |
| `IsTag`                 | A boolean (`$true`/`$false`) indicating whether the source of the deployment (`$RELEASE`) was a Git tag.                                   | `$true`                             |
| `Engine`                | The type of database engine (e.g., MySQL, PostgreSQL) as defined in the config file.                                                      | `aurora-mysql`                      |