# Stop script execution on any error
$ErrorActionPreference = 'Stop'

# Function to build a SQL Server connection string
Function GetConnectionString {
    Param(
        # The name or IP address of the SQL server
        [Parameter(Mandatory=$True)]
        [string]$dataSource,
        # PowerShell credential object for authentication
        [Parameter(Mandatory=$True)]
        [System.Management.Automation.PSCredential]$credentials,
        # The name of the database to connect to
        [Parameter(Mandatory=$True)]
        [string]$database
    )
    try{
        # Display a message indicating the start of connection string creation
        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        Write-Host "Building Connection String" -ForegroundColor Cyan
        Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan  

        # Check if the credentials object is empty
        if($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "Credentials are empty"
        }
        else{
            # Extract plain text password and username from the credential object
            $PlainPassword = $credentials.GetNetworkCredential().Password 
            $userName = $credentials.UserName 
        }
    
        # Construct and return the connection string
        return "server=$dataSource;Initial Catalog=$database;Persist Security Info=True;user id=$userName;password=$PlainPassword;Pooling=False;MultipleActiveResultSets=False;Connect Timeout=60;Encrypt=False;TrustServerCertificate=True"
    }
    catch {
        # Catch any errors and create a custom error message
        $toThrow = ("Failed to construct connection string: ''{0}'' Reason: ''{1}''" -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally {
        # If a custom error message was created, throw it
        if ($toThrow) {
            Throw $toThrow
        }
    }
}

# Main function to decide which report to generate and export
Function ExportToFile {
    param
    (
        # The file path for the index report
        [string]$indexFilename,
        # The file path for the user report
        [string]$userFilename,
        # The name of the worksheet in the Excel file
        [string]$sheetName,
        # The name or IP address of the SQL server
        [string]$dataSource,
        # PowerShell credential object for authentication
        [System.Management.Automation.PSCredential]$credentials
    )

    # Check if a user report filename was provided and call the corresponding function
    if($userFilename) {
            ExportToFileUsers $userFilename $sheetName $dataSource $credentials
        }

    # Check if an index report filename was provided and call the corresponding function
    if($indexFilename) {
            ExportToFileIndex $indexFilename $sheetName $dataSource $credentials
        }

}

# Function to generate and export the user security report
Function ExportToFileUsers {
    param
    (
        # The file path for the user report
        [string]$userFilename,
        # The name of the worksheet in the Excel file
        [string]$sheetName,
        # The name or IP address of the SQL server
        [string]$dataSource,
        # PowerShell credential object for authentication
        [System.Management.Automation.PSCredential]$credentials
    )

    # SQL query to get user information from 'core' and 'frontend' databases
    [string] $queryUsers = "USE core;
                            
                            SELECT	'CORE' AS [Location],
                                    [role],
                                    [first_name],
                                    [last_name],
                                    [email],
                                    [activated],
                                    [activated_date],
                                    [locked_out],
                                    [last_login_date],
                                    [dtc000] AS [Soft_delete_date]
                            FROM dbo.[user] WITH(NOLOCK);

                            USE frontend;

                            SELECT 'FRONTEND' AS [Location],
                                    [role],
                                    [first_name],
                                    [last_name],
                                    [email],
                                    [activated],
                                    [activated_date],
                                    [locked_out],
                                    [last_login_date],
                                    [dtc000] AS [Soft_delete_date] 
                            FROM dbo.[user] WITH(NOLOCK);
                        "

    # Check if the credentials object is empty
    if($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "Credentials are empty"
        }

    # Get the connection string for the 'master' database
    [string] $targetConnectionString = GetConnectionString $dataSource $credentials 'master'

    # Create a new SQL connection object
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $targetConnectionString
    
    # Create a new SQL command object
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand

    # Set the query for the SQL command
    $SqlCmd.CommandText = $queryUsers

    # Assign the connection to the command
    $SqlCmd.Connection = $SqlConnection
    
    # Create a SQL data adapter to execute the command and fill a dataset
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCmd

    # Create a new dataset to hold the query results
    $DataSet = New-Object System.Data.DataSet
    # Fill the dataset with the data from the query
    $SqlAdapter.Fill($DataSet)

    # Display the output filename and sheet name for debugging purposes
    Write-Host "`nUser File Name is:" $userFilename.ToString() -ForegroundColor DarkYellow
    Write-Host "`nSheet Name is:" $sheetName.ToString() -ForegroundColor DarkYellow

    # Export the data from the dataset to an Excel file
    # It uses the ImportExcel module's Export-Excel cmdlet
    $DataSet.Tables | Export-Excel -Path $userFilename -WorksheetName $sheetName -ClearSheet -AutoFilter -BoldTopRow -FreezeTopRow

    # Close the SQL connection
    $SqlConnection.Close()
 
}

# Function to generate and export the database index report
Function ExportToFileIndex {
    param
    (
        # The file path for the index report
        [string]$indexFilename,
        # The name of the worksheet in the Excel file
        [string]$sheetName,
        # The name or IP address of the SQL server
        [string]$dataSource,
        # PowerShell credential object for authentication
        [System.Management.Automation.PSCredential]$credentials
    )

    # SQL query to execute the sp_blitzIndex stored procedure on all databases except CompanyMonitor and master
    [string] $queryIndex = "EXEC sp_blitzIndex @GetAllDatabases=1,@IgnoreDatabases='CompanyMonitor,master'"

    # Check if the credentials object is empty
    if($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "Credentials are empty"
        }

    # Get the connection string for the 'CompanyMonitor' database
    [string] $targetConnectionString = GetConnectionString $dataSource $credentials 'CompanyMonitor'

    # Create a new SQL connection object
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $targetConnectionString
    
    # Create a new SQL command object
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand

    # Set the query for the SQL command
    $SqlCmd.CommandText = $queryIndex

    # Assign the connection to the command
    $SqlCmd.Connection = $SqlConnection
	# Set the command timeout to 300 seconds (5 minutes)
	$SqlCmd.CommandTimeout = 300;
    
    # Create a SQL data adapter to execute the command and fill a dataset
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCmd

    # Create a new dataset to hold the query results
    $DataSet = New-Object System.Data.DataSet
    # Fill the dataset with the data from the query
    $SqlAdapter.Fill($DataSet)

    # Display the output filename and sheet name for debugging purposes
    Write-Host "`nIndex File Name is:" $indexFilename.ToString() -ForegroundColor DarkYellow
    Write-Host "`nSheet Name is:" $sheetName.ToString() -ForegroundColor DarkYellow

    # Export the data from the dataset to an Excel file, excluding some properties
    # It uses the ImportExcel module's Export-Excel cmdlet
    $DataSet.Tables | Export-Excel -Path $indexFilename -WorksheetName $sheetName -ClearSheet -AutoFilter -BoldTopRow -FreezeTopRow -ExcludeProperty ItemArray, RowError, RowState, Table, HasErrors,'Sample Query Plan'

    # Close the SQL connection
    $SqlConnection.Close()
 
}
