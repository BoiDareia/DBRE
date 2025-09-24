This script contains two helper functions designed to automate a database build and deployment process. It focuses on setting up a database connection and executing a Python-based deployment script.

* * * * *

### Functions

#### 1\. `GetConnectionString`

This function builds a formatted database connection string.

-   **Purpose**: To securely assemble the credentials and server information needed to connect to a database.

-   **Parameters**:

    -   `$dataSource`: The database server address.

    -   `$credentials`: A secure **PSCredential** object containing the username and password.

    -   `$database`: The name of the database.

-   **Process**: It securely extracts the username and plaintext password from the `PSCredential` object and combines them with the other parameters into a single connection string, hardcoded for port `5439`.

#### 2\. `GenerateDeployScript`

This function orchestrates the execution of a Python script that handles the main deployment logic.

-   **Purpose**: To validate the environment and run a Python build script, checking for success or failure.

-   **Parameters**:

    -   `$pythonPath`: The location of the Python installation.

    -   `$buildFile`: The name of the Python script to run (e.g., `build.py`).

    -   `$deployPath`: The location of the expected output file, used to confirm success.

    -   `$filepath`: The root directory containing the `_build` folder where the script is located.

-   **Process**:

    1.  It first checks if Python and the specified build file exist.

    2.  It temporarily adds the Python directory to the system's `PATH` if it's not already there.

    3.  It executes the Python script.

    4.  It checks the **`$LASTEXITCODE`** of the script. An exit code of **`0`** signifies success, while any other value indicates an error.

    5.  Finally, it verifies that the deployment artifact was created at the `$deployPath`.

* * * * *

### Key Features

-   **Robust Error Handling**: The script uses `$ErrorActionPreference = 'Stop'` and `try...catch...finally` blocks to ensure that any errors halt execution and are reported clearly.

-   **Clear Logging**: It uses `Write-Host` with different colors (Cyan for information, Green for success, Red for errors) to provide easy-to-read feedback to the user.

-   **Secure Credential Management**: It uses the standard `PSCredential` object to handle passwords securely, avoiding plaintext passwords directly in the script or logs.