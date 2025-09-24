---

## Redshift Maintenance Automation Script 📜

### Overview

This Python script automates routine maintenance tasks on an Amazon Redshift data warehouse. Its primary purpose is to execute **`VACUUM`** and **`ANALYZE`** commands on tables to reclaim disk space, maintain sort order, and update statistics, which are all crucial for optimal query performance.

The script connects to AWS using the `boto3` library and interacts with the Redshift cluster via the **Redshift Data API**. This allows it to run SQL commands without a direct database connection.

***

### Key Features ✨

* **Smart Task Selection**: The script intelligently identifies which tables need maintenance.
    * **For `VACUUM`**: It queries system views (`svv_table_info`) to find tables with a significant number of deleted or unsorted rows.
    * **For `ANALYZE`**: It finds tables with stale statistics (where more than 10% of rows have changed since the last analysis).
* **Flexible Operation Modes**: The script can be run in different scopes:
    1.  **Full Mode**: Operates on all user databases in the cluster.
    2.  **Database Mode**: Targets all relevant tables within a single, specified database.
    3.  **Table Mode**: Targets one specific table in a specific database.
* **Automated `VACUUM` Logic**: The type of `VACUUM` performed is determined automatically:
    * **`VACUUM SORT ONLY`**: The default operation for most days.
    * **`VACUUM FULL`**: A more intensive operation performed automatically on **Saturdays**.
    * This logic can be overridden with a specific argument.
* **Timeout & Cancellation**: Long-running `ANALYZE` commands have a built-in timeout (5 minutes) to prevent them from getting stuck. If a command exceeds the timeout, the script attempts to cancel it and moves on.
* **Slack Reporting**: After completing its tasks, the script sends a summary report to a specified Slack channel. The message is posted as a reply within a pre-existing thread, keeping notifications organized.

***

### Configuration & Execution ⚙️

* **Configuration**: All necessary settings (AWS credentials, cluster details, Slack tokens, etc.) are expected to be provided by an **Octopus Deploy** server.
* **Execution**: The script is controlled by pipeline arguments, such as `DATABASE`, `TABLE`, `VACUUM`, and `ANALYZE`, which define the scope and the operations to be performed.