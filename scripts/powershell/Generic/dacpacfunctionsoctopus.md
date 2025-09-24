# Octopus Deploy: DACPAC Deployment Functions Script

## 1. Overview

This PowerShell script provides a set of reusable functions for automating SQL Server database deployments using Data-Tier Application Packages (DACPACs). It is intended to be included as a library in an Octopus Deploy process, offering robust and standardized methods for generating deployment scripts and publishing changes directly.

The script includes functions for both modern (`sqlpackage.exe`) and legacy (`DACFx .NET library`) deployment methods.

## 2. Features

* **Connection String Builder**: Includes a helper function (`GetConnectionString`) to reliably construct SQL Server connection strings from standard parameters.
* **Script Generation**: The `GenerateDeployScript` function uses the industry-standard `sqlpackage.exe` tool to compare a DACPAC with a target database and generate a precise, differential SQL deployment script.
* **Flyway Compatibility**: After generating a script, it automatically removes or comments out SQLCMD-specific syntax, making the output script compatible with migration tools like Flyway.
* **Direct Publishing**: The `Publish-DatabaseDeployment` function provides a method to deploy a DACPAC directly to a database using the underlying .NET DAC Framework (DACFx) libraries.
* **Robust Error Handling**: Each function is wrapped in a `try/catch` block to provide clear error messages and ensure that failures are properly reported, causing the Octopus step to fail.
* **Detailed Logging**: Functions support writing detailed logs to a specified log file for easy troubleshooting.

## 3. Setup in Octopus Deploy

This script is not a standalone step but a library of functions. To use it, you should "dot-source" it at the beginning of your main deployment script.

**Example Main Script:**
```powershell
# Source the function library
. C:\path\to\this\script.ps1

# --- Now you can call the functions ---

# 1. Build the connection string
$creds = New-Object System.Management.Automation.PSCredential($username, $securePassword)
$connString = GetConnectionString -dataSource "my-server.database.windows.net" -credentials $creds -database "MyDatabase"

# 2. Generate the deployment script
GenerateDeployScript -dacpac "C:\path\to\MyDb.dacpac" `
                     -publishXml "C:\path\to\MyDb.publish.xml" `
                     -targetConnectionString $connString `
                     -filepath "C:\temp\deploy.sql" `
                     -database "MyDatabase" `
                     -logfile "C:\temp\deploy.log"

### Prerequisites
For **GenerateDeployScript**: The Octopus Worker must have SQL Server Data Tools (SSDT) installed, which includes `sqlpackage.exe`. The directory containing `sqlpackage.exe` should be in the system's PATH environment variable.

For **Publish-DatabaseDeployment**: The Octopus Worker must have the DAC Framework installed. You will need to provide the path to the `Microsoft.SqlServer.Dac.dll` assembly.

---
### Functions Explained

#### GetConnectionString
A utility function that takes a server name, a `PSCredential` object, and a database name, and returns a fully formatted JDBC-style connection string.

#### GenerateDeployScript
This is the recommended function for modern deployment workflows.
* It takes paths to a `.dacpac` file, a `.publish.xml` profile, a target connection string, and an output file path.
* It invokes `sqlpackage.exe` with the `/Action:Script` parameter. `sqlpackage.exe` connects to the target database to determine the exact changes needed to align its schema with the schema defined in the DACPAC.
* It saves the resulting SQL script to the specified output path.
* It then reads the generated script and performs several string replacements to make it compatible with tools that don't understand SQLCMD syntax (like Flyway).

#### Publish-DatabaseDeployment
This function is useful for scenarios where you want to deploy changes directly without generating an intermediate script.
* It dynamically loads the `Microsoft.SqlServer.Dac.dll` .NET assembly.
* It uses the `DacServices` class to connect to the target database and deploy the DACPAC, applying the settings from the `.publish.xml` profile.
* It registers an event handler to stream progress messages from the DACFx engine directly to the Octopus log.

---
### Prerequisites
The Octopus Worker executing these functions must have the following tools installed and available in the systems PATH:

* **Git CLI**
* **MSBuild** (typically available with Visual Studio or .NET SDK)
* **Flyway CLI**
* **Octo CLI** (for packaging and pushing artifacts)

---
### 4. Core Functions Explained

#### Deploy-DatabaseVersion
This is the primary orchestrator. It takes numerous parameters (config file, environment, credentials, branch name, etc.) and executes the deployment workflow in the correct order:

* Loads all necessary configuration from an XML file.
* Checks if the target version has already been deployed to avoid errors.
* Handles cleanup of files from any previous failed deployments.
* Calls `Build-DatabaseProject` to compile the DACPAC.
* Calls `GenerateDeployScript` (from the `DacPacFunctionsOctopus.ps1` library) to create the differential SQL script.
* Calls `ExecuteFlywayCreate` (from the `FlywayFunctionsOctopus.ps1` library) to prepare the final Flyway migration file.
* Uses the `octo` CLI to package the SQL script into a versioned `.zip` file and push it to the Octopus built-in feed.
* Sets Octopus output variables for use in the next step (e.g., the actual `Flyway migrate` step).

#### Publish-ImportantSchemaChanges
A powerful notification utility. After a script is generated, this function can be called to:

* Read the content of the `.sql` file.
* Use string matching to find all `CREATE TABLE`, `ALTER TABLE ADD`, `ALTER TABLE DROP`, etc., statements.
* Format these findings into a human-readable summary.
* Post the summary to a hardcoded Slack channel webhook, alerting teams to potentially impactful schema changes.

#### Refresh-CDC
A specialized utility function that executes a predefined SQL script (`Refresh_CDC_for_new_and_modified_tables.sql`) against the target database. This is used to ensure Change Data Capture is correctly configured after a deployment.