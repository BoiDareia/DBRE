This script is a comprehensive orchestration engine for automating database migrations. It's designed to run within a CI/CD pipeline, specifically **Octopus Deploy**, and uses **Flyway** conventions for versioning. The script manages the entire process from fetching code to preparing deployment packages. 📦

* * * * *

Core Functions
--------------

The script's logic is divided into helper functions and two main orchestration functions.

#### Helper Functions

-   `GetFilename`: Takes a raw Git branch name (e.g., `release/V1.2.3`) and cleans it into a standardized, Flyway-compliant filename (e.g., `V1.2.3__DatabaseChanges.sql`).

-   `VersionHasBeenDeployed`: Connects to the target database and queries the Flyway schema history table. This is a crucial **idempotency** check to prevent re-deploying a version that has already succeeded. 🛡️

-   `AdjustFlywayIfFail`: A safety function. If a deployment fails, it connects to the database and deletes the "failed" entry from the Flyway history table, allowing a clean retry of the deployment.

-   `BuildProject`: A utility function to compile a .NET solution/project using the Visual Studio command-line tools (`devenv.com`).

#### Main Orchestration Functions

-   **`DeployDatabaseVersion`**: This is the heart of the script. It performs the end-to-end deployment workflow:

    1.  **Load Config**: Reads a detailed XML configuration file for environment-specific settings (database URLs, paths, engine type, etc.).

    2.  **Check History**: Calls `VersionHasBeenDeployed` to see if it should proceed.

    3.  **Get Code**: Checks out the specified branch/tag from Git.

    4.  **Prepare SQL**: Handles logic based on the database engine (`Redshift`, `Aurora`, `PostgreSQL`, etc.). It either generates SQL scripts using a Python tool or concatenates existing SQL files listed in a manifest.

    5.  **Package for Octopus**: This is the final step. It uses the `octo` command-line tool to:

        -   Create Octopus **artifacts** so the SQL scripts are visible in the deployment logs.

        -   Package the SQL scripts into a versioned `.zip` file.

        -   Push the package to the Octopus Deploy built-in repository.

-   **`DoDatabaseContinuousDeployment`**: A simple wrapper around `DeployDatabaseVersion`. It enables a "Continuous Delivery" flag and, most importantly, wraps the entire execution in a **PowerShell transcript**, which logs all console output to a file for auditing and debugging. 📝