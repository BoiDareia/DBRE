SQL Server TempDB Configuration Script
======================================

This script automates the process of configuring the `tempdb` database by moving its files to a dedicated drive and setting a standardized size and file count. It's designed to align with SQL Server best practices, which often recommend isolating `tempdb` to improve performance.

This script is based on and adapted from the original work by **Michael Petri**, available on [GitHub Gist](https://gist.github.com/FlogDonkey/3b9851f1c13b94f3f2d26b4ab5b49de0).

📜 Script Overview
------------------

The primary goal of this script is to modify the existing `tempdb` data and log files and, if necessary, add new data files to reach a specified count. It calculates the appropriate size for each file based on the total drive size and a configurable buffer. It can also create the destination directory if it doesn't already exist.

**Key operations:**

1.  **Validates** the destination path.

2.  **Creates** the destination directory if it's missing.

3.  **Calculates** the size for each `tempdb` file.

4.  **Generates** `ALTER DATABASE` commands to move and resize existing files.

5.  **Generates** `ALTER DATABASE` commands to add new data files if needed.

6.  **Executes** the generated commands (unless in debug mode).

> ⚠️ **Important:** A restart of the SQL Server service is **required** for the changes to take effect after the script is successfully executed.

* * * * *

🛠️ Configuration Variables
---------------------------

Before running the script, you must configure the variables in the `DECLARE` block at the top.

SQL

```
DECLARE @DriveSizeGB				 INT		   = 75 /* Set to size of drive in GB */
		,@FileCount					 INT		   = 9  /* Set to desired number of data files + 1 log file */
		,@InstanceCount				 TINYINT	   = 1
		,@VolumeBuffer				 DECIMAL(8, 2) = .8 /* Set to amount of volume TempDB can fill. */
		,@CreateDirectoryIfNotExists BIT		   = 1	/* Flag to have SQL create the directories if they don't exist */
		,@DrivePath					 VARCHAR(100)  = 'T:\' + @@SERVICENAME + '\' /* Base path for tempdb files */
		,@Debug						 BIT		   = 1; /* Set to 0 to execute, 1 for a dry run */

```

-   `@DriveSizeGB`: The total size in gigabytes of the dedicated drive for `tempdb`.

-   `@FileCount`: The **total number of files** you want for `tempdb`. This count includes the single log file. For example, a value of `9` results in 8 data files and 1 log file.

-   `@InstanceCount`: The number of SQL instances sharing the drive. This is typically `1`.

-   `@VolumeBuffer`: A safety buffer. A value of `.8` means `tempdb` will be configured to use 80% of the allocated drive space, leaving 20% free.

-   `@CreateDirectoryIfNotExists`: If set to `1`, the script will attempt to create the destination folder using `xp_cmdshell`. If `0`, the script will fail if the folder doesn't exist.

-   `@DrivePath`: The full path to the folder where the `tempdb` files should be located. The script dynamically appends the SQL Server service name (e.g., `MSSQLSERVER`) to the path.

-   `@Debug`: A critical safety switch.

    -   **`1` (Default):** "Dry Run" mode. The script will `PRINT` the `ALTER DATABASE` commands it would run but **will not execute them**.

    -   **`0`:** "Execute" mode. The script will run the generated commands.

* * * * *

⚙️ How It Works
---------------

1.  **`xp_cmdshell` Handling**: The script checks if the `xp_cmdshell` system procedure is enabled, as it's needed to create the directory (`mkdir`). If disabled, the script temporarily enables it and ensures it is disabled again upon completion.

2.  **Path Validation**: It uses the undocumented `master..xp_fileexist` procedure to check if the `@DrivePath` exists and is a directory. If the path does not exist and `@CreateDirectoryIfNotExists` is enabled, it proceeds to create it.

3.  **File Size Calculation**: The script calculates the size for each individual file in megabytes. It takes the `@DriveSizeGB`, applies the `@VolumeBuffer`, and divides the result by the `@FileCount`.

4.  **Command Generation**:

    -   It queries `sys.master_files` to find the current `tempdb` files.

    -   For each existing file, it builds an `ALTER DATABASE tempdb MODIFY FILE` command to change its physical path (`FILENAME`) and `SIZE`.

    -   If the current number of files is less than `@FileCount`, it generates the necessary `ALTER DATABASE tempdb ADD FILE` commands to create the additional data files.

5.  **Execution**: The script loops through the generated commands. If `@Debug` is `0`, it executes each one. If `@Debug` is `1`, it simply prints them to the messages tab for review.

* * * * *

🚀 How to Use
-------------

1.  **Configure Variables**: Carefully edit the variables at the top of the script to match your server's environment. Pay close attention to `@DriveSizeGB`, `@FileCount`, and `@DrivePath`.

2.  **Run in Debug Mode**: Execute the script with `@Debug = 1`. This is the default and safest option.

3.  **Review the Output**: Check the "Messages" tab in SQL Server Management Studio (SSMS). You will see the `ALTER DATABASE` commands that the script generated. Verify that the paths, file names, and sizes are all correct.

4.  **Execute the Script**: Once you are confident the commands are correct, change the variable to `@Debug = 0` and execute the script again.

5.  **Restart SQL Server**: After the script finishes successfully, **you must restart the SQL Server service**. The file move and resize operations will only take effect after a restart. You can do this via SQL Server Configuration Manager or `services.msc`.