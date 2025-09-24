Monthly Reports PowerShell Script
=================================

Overview
--------

This PowerShell script is designed to connect to a SQL Server instance, execute specific queries to generate monthly reports, and export the results into an Excel file. It can generate two types of reports: a User Security Report and a Database Index Report.

Prerequisites
-------------

-   **PowerShell 5.1 or later.**

-   **ImportExcel Module:** The script uses the `Export-Excel` cmdlet, which is part of the `ImportExcel` module. If you don't have it installed, you can install it by running the following command in PowerShell:

    ```
    Install-Module -Name ImportExcel -Scope CurrentUser

    ```

-   **SQL Server:** Access to a SQL Server instance with the necessary permissions to execute the queries. The script uses the `sp_blitzIndex` stored procedure, which is part of the [First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit "null") by Brent Ozar. This stored procedure must be installed on the target SQL Server.

Functions
---------

The script is composed of several functions:

### `GetConnectionString`

This function builds and returns a SQL Server connection string.

**Parameters:**

-   `$dataSource` (string, mandatory): The name or IP address of the SQL Server instance.

-   `$credentials` (PSCredential, mandatory): A PowerShell credential object containing the username and password for SQL Server authentication.

-   `$database` (string, mandatory): The name of the database to connect to.

**Returns:**

-   A formatted SQL Server connection string.

### `ExportToFile`

This is the main function that orchestrates the report generation. It determines which report to create based on the provided filenames.

**Parameters:**

-   `$indexFilename` (string): The full path where the Database Index Report Excel file should be saved.

-   `$userFilename` (string): The full path where the User Security Report Excel file should be saved.

-   `$sheetName` (string): The name of the worksheet to create in the Excel file.

-   `$dataSource` (string): The name or IP address of the SQL Server instance.

-   `$credentials` (PSCredential): A PowerShell credential object for authentication.

### `ExportToFileUsers`

This function generates the User Security Report. It queries the `core` and `frontend` databases to retrieve user information and exports it to an Excel file.

**Parameters:**

-   `$userFilename` (string): The full path for the output Excel file.

-   `$sheetName` (string): The name for the Excel worksheet.

-   `$dataSource` (string): The SQL Server instance name.

-   `$credentials` (PSCredential): The credentials for database access.

**SQL Query:**

The function executes a `UNION ALL` query to get user data from `dbo.[user]` tables in both the `core` and `frontend` databases. The fields retrieved include role, name, email, activation status, and login dates.

### `ExportToFileIndex`

This function generates the Database Index Report. It executes the `sp_blitzIndex` stored procedure to get a detailed analysis of database indexes and exports the results to an Excel file.

**Parameters:**

-   `$indexFilename` (string): The full path for the output Excel file.

-   `$sheetName` (string): The name for the Excel worksheet.

-   `$dataSource` (string): The SQL Server instance name.

-   `$credentials` (PSCredential): The credentials for database access.

**SQL Query:**

The function executes `sp_blitzIndex` with `@GetAllDatabases=1`, which runs it against all databases on the server, excluding `CompanyMonitor` and `master` as specified by `@IgnoreDatabases`.

How to Use
----------

1.  **Save the script:** Save the code as a `.ps1` file (e.g., `MonthlyReports.ps1`).

2.  **Open PowerShell:** Navigate to the directory where you saved the script.

3.  **Run the script:** You will need to call the `ExportToFile` function with the required parameters.

**Example:**

```
# Create a credential object
$creds = Get-Credential

# Define parameters for the user report
$userReportParams = @{
    userFilename = "C:\Reports\UserSecurityReport.xlsx"
    sheetName    = "User_Data"
    dataSource   = "YourSQLServerName"
    credentials  = $creds
}

# Generate the user report
ExportToFile @userReportParams

# Define parameters for the index report
$indexReportParams = @{
    indexFilename = "C:\Reports\DatabaseIndexReport.xlsx"
    sheetName     = "Index_Analysis"
    dataSource    = "YourSQLServerName"
    credentials   = $creds
}

# Generate the index report
ExportToFile @indexReportParams

```

This will prompt you for a username and password, create the credential object, and then generate the specified reports in the `C:\Reports\` directory.