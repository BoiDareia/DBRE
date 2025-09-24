# Octopus Deploy: DACPAC and Flyway Orchestration Library

## 1. Overview

This PowerShell script is a comprehensive library of functions designed to orchestrate a sophisticated database deployment workflow within Octopus Deploy. It manages the entire lifecycle of a schema deployment, from building the database project and generating a migration script, to packaging it for Flyway and notifying stakeholders of the changes.

It is intended to be "dot-sourced" (included) by other Octopus execution scripts, providing a centralized and reusable set of capabilities for database CI/CD.

## 2. Features

* **End-to-End Orchestration**: The `Deploy-DatabaseVersion` function acts as the main entry point, controlling the entire process from source code to a packaged Flyway migration.
* **Flyway Naming Convention**: The `Get-Filename` function automatically generates Flyway-compliant filenames, correctly distinguishing between versioned (`V__`) and repeatable (`R__`) migrations based on whether the version has been deployed before.
* **Idempotency Checks**: The `Test-VersionHasBeenDeployed` function queries the database's Flyway history table to prevent re-running already applied versions.
* **Automated Build**: The `Build-DatabaseProject` function uses MSBuild to compile the `.sqlproj` file, ensuring the DACPAC is always up-to-date.
* **Change Notification**: The `Publish-ImportantSchemaChanges` function parses the generated SQL script for critical DDL statements (like `CREATE TABLE`, `ALTER TABLE`) and sends a formatted summary to a Slack channel, providing visibility to data teams.
* **Utility Functions**: Includes helper functions for common tasks like refreshing Change Data Capture (`Refresh-CDC`).
* **Octopus Integration**: The script is designed to create and push packages (`.zip` files containing the SQL migration) directly to the Octopus built-in feed, making them available for subsequent Flyway steps.

## 3. Setup in Octopus Deploy

This script is a library and not a standalone execution step. It should be placed in a central location accessible by your Octopus Workers (e.g., in a version-controlled script repository).

Your main Octopus deployment scripts should then "dot-source" this file at the beginning to make its functions available.

**Example Main Execution Script:**

```powershell
# 1. Source the library
. C:\path\to\this\script.ps1
. .\GitFunctionsOctopus.ps1
. .\DacPacFunctionsOctopus.ps1

# 2. Set up parameters from Octopus variables
$configFile = $OctopusParameters["ConfigFile"]
$env = $OctopusParameters["Environment"]
# ... (and so on for all required parameters)

# 3. Call the main orchestration function
Deploy-DatabaseVersion -configFile $configFile -env $env -credentials $creds -BranchName $branch -releaseVersion $release -...

### Prerequisites
The Octopus Worker executing these functions must have the following tools installed and available in the systems PATH:

* **Git CLI**
* **MSBuild** (typically available with Visual Studio or .NET SDK)
* **Flyway CLI**
* **Octo CLI** (for packaging and pushing artifacts)

---
## 4. Core Functions Explained

### Deploy-DatabaseVersion
This is the primary orchestrator. It takes numerous parameters (config file, environment, credentials, branch name, etc.) and executes the deployment workflow in the correct order:

* Loads all necessary configuration from an XML file.
* Checks if the target version has already been deployed to avoid errors.
* Handles cleanup of files from any previous failed deployments.
* Calls `Build-DatabaseProject` to compile the DACPAC.
* Calls `GenerateDeployScript` (from the `DacPacFunctionsOctopus.ps1` library) to create the differential SQL script.
* Calls `ExecuteFlywayCreate` (from the `FlywayFunctionsOctopus.ps1` library) to prepare the final Flyway migration file.
* Uses the `octo` CLI to package the SQL script into a versioned `.zip` file and push it to the Octopus built-in feed.
* Sets Octopus output variables for use in the next step (e.g., the actual `Flyway migrate` step).

### Publish-ImportantSchemaChanges
A powerful notification utility. After a script is generated, this function can be called to:

* Read the content of the `.sql` file.
* Use string matching to find all `CREATE TABLE`, `ALTER TABLE ADD`, `ALTER TABLE DROP`, etc., statements.
* Format these findings into a human-readable summary.
* Post the summary to a hardcoded Slack channel webhook, alerting teams to potentially impactful schema changes.

### Refresh-CDC
A specialized utility function that executes a predefined SQL script (`Refresh_CDC_for_new_and_modified_tables.sql`) against the target database. This is used to ensure Change Data Capture is correctly configured after a deployment.