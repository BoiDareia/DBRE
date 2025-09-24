# Octopus Deploy: Data Deployment and Release Orchestration Script

## 1. Overview

This PowerShell script is a sophisticated orchestration engine for executing database data changes within an Octopus Deploy pipeline. It is designed to run after the main schema deployment/validation steps and handles the entire lifecycle of a data deployment, from validation and execution to integration with Jira and Slack for release tracking and notifications.

The script reads a `manifest.txt` file from a version-controlled directory to determine which SQL scripts to run, in what order, providing a robust and auditable process for data modifications.

## 2. Features

* **Configuration-Driven**: Utilizes an XML configuration file to map databases to their respective Git repositories and directory structures.
* **Change Validation**: Performs a `git diff` to ensure that there are new data changes and a `manifest.txt` file present before proceeding, preventing unnecessary runs.
* **Manifest-Based Execution**: Reads a list of `.sql` files from a `manifest.txt` file and executes them sequentially. This ensures an explicit and version-controlled order of execution.
* **Jira Integration**:
    * Automatically finds or creates Jira tickets based on filenames.
    * Comments on tickets with the execution logs.
    * Transitions tickets to the appropriate status (e.g., "Deployed to Staging") upon successful completion.
* **Slack Notifications**:
    * Sends detailed success or failure notifications to designated Slack channels.
    * Supports threaded messages to keep deployment notifications organized.
    * Includes links to all relevant Jira tickets.
* **Flyway Integration**: Can create a "dummy" Flyway migration script for data-only deployments. This ensures that the data change is recorded in the `flyway_schema_history` table, keeping the database version history consistent.
* **Robust Error Handling**: A comprehensive `try/catch/finally` block ensures that failures are caught, logged, and reported to Jira and Slack, and the script exits with a non-zero exit code to fail the Octopus step.

## 3. Setup in Octopus Deploy

This script should be configured as a "Run a Script" step in your deployment process, typically running after schema migration and variable validation steps.

* **Step Name**: A descriptive name like `Deploy Data Changes`.
* **Script Source**: Copy and paste the PowerShell code into the script editor.
* **Execution Location**: This script must run on an Octopus Worker with the following prerequisites:
    * **Git** installed and available in the system's PATH.
    * **AWS CLI** installed and available in the system's PATH.
    * Any required PowerShell modules for Jira integration.
    * The necessary helper function libraries (`ReleaseChangeFunctionsOctopus.ps1`, `gitFunctionsOctopus.ps1`) must be present in the script's working directory.

### 3.1. Required Octopus Variables

This script relies heavily on variables, many of which are expected to be output variables from previous steps.

| **Variable Name** | **Description** | **Example Value** |
| :---------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------- | :-------------------------------------- |
| `REGION`                                                          | The target AWS region.                                                                                       | `us-east-1`                             |
| `SELECT_ENVIRONMENT`                                              | The target deployment environment.                                                                           | `STG`                                   |
| `DATABASE`                                                        | The name of the database being deployed.                                                                     | `ProductCatalog`                        |
| `RELEASE`                                                         | **Required.** The Git branch, tag, or commit hash to be deployed.                                            | `v2.5.1`                                |
| `BUILD_VERSION`                                                   | The unique build version or full commit hash, used for trunk-based deploys.                                  | `b1234`                                 |
| `DEPLOYMENT_TIME`                                                 | The phase of the deployment, used to find the correct data script folder.                                    | `BeforeDeploy` or `AfterDeploy`         |
| `STATUS`                                                          | The status of the deployment, used to find the correct data script folder.                                   | `Rollout` or `Rollback`                 |
| `Octopus.Action[RDS SQL Variables Check].Output.DEPLOY_TYPE`      | The deployment strategy (e.g., "trunkBase") from a previous step.                                            | `trunkBase`                             |
| `Octopus.Action[RDS SQL Variables Check].Output.LastDeployed`     | The Git reference of the last successful deployment from a previous step.                                    | `v2.5.0`                                |
| `Octopus.Action[RDS SQL Variables Check].Output.DATAPATH`         | The specific path within the repo where data changes are located, from a previous step.                      | `.../Data/BeforeDeploy/Rollout`         |
| `Octopus.Action[RDS SQL Variables Check].Output.DeploymentNoSchema` | A flag from a previous step indicating if a dummy Flyway migration is needed.                                | `Will NOT do Schema Deployment!`        |
| `threadIds`                                                       | A comma-separated list of Slack message timestamps for threaded replies.                                     | `1661432400.123456,...`                 |
| `channels`                                                        | A comma-separated list of Slack channel IDs corresponding to the `threadIds`.                                | `C0123ABC,C4567DEF`                     |

## 4. How It Works

1.  **Initialization**: The script loads all required parameters from Octopus and sets up the logging environment.
2.  **Parameter Validation**: It standardizes environment and database names and determines the precise release version to be deployed.
3.  **Change Detection**: It navigates to the local Git repository, and performs a `git diff` between the last deployed version and the target version, looking specifically for a `manifest.txt` file in the correct data path. If no manifest is found, it exits successfully, as there is nothing to do.
4.  **Execution Loop**:
    * It reads the list of `.sql` filenames from the `manifest.txt`.
    * It iterates through each file in the list.
    * For each file, it optionally interacts with **Jira** to create or find a ticket.
    * It executes the SQL script against the target database.
    * It captures the output and comments on the corresponding Jira ticket.
5.  **Error Handling**: If any script execution fails, the `catch` block is triggered. It logs the error, comments on the Jira ticket with the failure details, and prepares to exit with a failure code.
6.  **Finalization**: The `finally` block runs regardless of the outcome.
    * It transitions all processed **Jira tickets** to their final state.
    * It constructs a detailed **Slack message** summarizing the deployment (success or failure), including the number of scripts applied and links to all Jira tickets.
    * It sends the notification to the appropriate Slack channels, using the `threadIds` to reply to an existing conversation if available.
    * It exits with code `0` for success or `1` for failure, signaling the outcome to Octopus Deploy.