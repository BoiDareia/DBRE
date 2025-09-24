# Octopus Deploy: Generic Flyway Command Runner

## 1. Overview

This PowerShell script provides a powerful and flexible wrapper for executing the Flyway command-line tool within an Octopus Deploy process. It is designed as a single, reusable step that can run any Flyway command (`migrate`, `info`, `validate`, `baseline`, `check`, etc.) by dynamically building the command-line arguments from Octopus variables.

This approach allows you to standardize your Flyway operations and manage all configuration directly within Octopus Deploy, without needing to modify the script for different commands or environments.

---

## 2. Features

* **Universal Command Support**: Can execute any Flyway command by changing a single Octopus variable.
* **Multi-OS Compatibility**: Automatically detects and uses the correct executable for Windows and Linux workers.
* **Advanced Authentication**: Natively supports multiple authentication methods:
    * Username and Password
    * AWS IAM (generates a temporary token for RDS)
    * Azure Managed Identity
    * GCP Service Account
* **Dynamic Argument Building**: Intelligently adds command-line parameters only when a corresponding Octopus variable has a value, keeping the execution clean.
* **Artifact Creation**: Automatically captures and uploads important Flyway outputs, such as `migrate dry run` SQL scripts and HTML reports, as Octopus artifacts.
* **Placeholder Support**: Easily pass key-value placeholders to your migration scripts.

---

## 3. Setup in Octopus Deploy

This script is intended to be used as a "Run a Script" step in your deployment process.

* **Step Name**: A descriptive name, e.g., `Flyway Migrate`, `Flyway Info`, `Flyway Check Drift`.
* **Script Source**: Copy and paste the PowerShell code into the script editor.
* **Execution Location**: The script should run on an Octopus Worker where the **Flyway CLI** is available. This can be achieved by:
    1.  Including the Flyway CLI files within your deployment package.
    2.  Installing the Flyway CLI on the worker and adding it to the system's PATH.
    3.  Specifying an absolute path to the executable using the `Flyway.Executable.Path` variable.

### 3.1. Required Octopus Variables

The script is controlled entirely by Octopus variables. The variable names are designed to match the Flyway command-line parameters.

| **Variable Name** | **Description** | **Example Value** |
| :--- | :--- | :--- |
| `Flyway.Command.Value` | **Required.** The Flyway command to execute. | `migrate`, `info`, `validate`, `check drift` |
| `Flyway.Target.Url` | **Required.** The JDBC database connection URL. | `jdbc:sqlserver://host:1433;databaseName=MyDb` |
| `Flyway.Command.Locations` | **Required.** The path to your SQL migration files within the package. | `db/migrations` |
| `Flyway.Database.User` | The database username. | `myuser` |
| `Flyway.Database.User.Password` | **(Sensitive)** The database password. | (your password) |
| `Flyway.Authentication.Method` | The authentication method to use. | `usernamepassword`, `awsiam`, `azuremanagedidentity` |
| `Flyway.License.Key` | **(Sensitive)** Your Flyway license key for Teams/Enterprise features. | `FL01...` |
| `Flyway.Command.Schemas`| A comma-separated list of schemas to manage. | `dbo,sales,support` |
| `Flyway.Command.Target` | The version to migrate to (or `latest`). | `2.1.5` |
| `Flyway.Command.OutOfOrder` | (`True`/`False`) Allows migrations to be run out of order. | `True` |
| `Flyway.Command.PlaceHolders` | A multi-line key-value pair for placeholders. | `myApiUrl::https://api.prod.com` |
| `Flyway.Additional.Arguments` | Any other command-line arguments to pass directly to Flyway. | `-connectRetries=10` |

*(Note: This is a partial list. The script supports most standard Flyway parameters by following the `Flyway.Category.Parameter` naming convention.)*

---

## 4. How It Works

1.  **Initialization**: The script determines the operating system and loads all the `Flyway.*` variables from Octopus.
2.  **Locate Executable**: The `Get-FlywayExecutablePath` function searches for the Flyway CLI, prioritizing a user-provided path, then the package directory, and finally the system PATH.
3.  **Build Arguments**: The script starts with the core command (e.g., `migrate`) and then iterates through the Octopus variables.
    * Using the `Test-AddParameterToCommandline` helper function, it checks if each variable has a value and if it's applicable to the current command.
    * If the checks pass, it formats and adds the corresponding parameter (e.g., `-target="1.2.3"`) to an array of arguments.
4.  **Handle Authentication**: A `switch` block handles the selected authentication method. For cloud-based auth (like AWS IAM), it runs the necessary CLI commands to generate a temporary token and uses it as the password.
5.  **Execute Command**: The script constructs the final command, masks any passwords for logging purposes, and then executes the Flyway CLI with the built arguments. If Flyway returns a non-zero exit code, the script throws an error, failing the Octopus step.
6.  **Process Artifacts**: After a successful run, it checks for known output files (like `dryRunOutput.sql` or `report.html`). If found, it uses `New-OctopusArtifact` to upload them to the Octopus server, making them available in the deployment summary.