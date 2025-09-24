# -*- coding: utf-8 -*-
"""
This script performs maintenance tasks (VACUUM and ANALYZE) on an Amazon Redshift cluster.

It uses the AWS Boto3 library and the Redshift Data API to execute SQL commands.
The script can operate in several modes:
1.  On all tables in all user-defined databases.
2.  On all relevant tables within a specific database.
3.  On a single, specific table within a specific database.

The type of VACUUM operation (e.g., FULL, SORT ONLY) is determined by the day of the week
(FULL on Saturdays, SORT ONLY on other days) or can be specified via an argument.
The script identifies tables needing maintenance by querying Redshift's system views.

Results of the operations are logged to a file and reported to a specified Slack channel
as a threaded reply to an initial message.

Configuration, such as AWS credentials, cluster details, and Slack tokens, is expected
to be provided by an Octopus Deploy server via the `get_octopusvariable` function.
"""

# --- IMPORTS ---
import boto3
import os
import time
from slack_sdk import WebClient
import datetime
import pytz  # For timezone awareness
import logging
import botocore.session as bc # Used for creating boto3 session with specific credentials

# --- LOGGING CONFIGURATION ---
# Sets up logging to write informational messages and errors to 'myapp.log'.
# The file is overwritten on each run ('w' mode).
logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(name)-12s %(levelname)-8s %(message)s',
        datefmt='%m-%d %H:%M',
        filename='myapp.log',
        filemode='w'
)

# --- CONFIGURATION FROM OCTOPUS DEPLOY ---
# These variables are populated by an external system (Octopus Deploy).

# AWS settings
AWS_REGION = get_octopusvariable("AWS_REGION")
REDSHIFT_CLUSTER_IDENTIFIER = get_octopusvariable("REDSHIFT_CLUSTER_IDENTIFIER")
REDSHIFT_DB_USER = get_octopusvariable("REDSHIFT_USER") # Should be the ARN of the Redshift secret in Secrets Manager

# Slack integration settings
SLACK_BOT_TOKEN = get_octopusvariable("api.token")
SLACK_CHANNEL = get_octopusvariable("Octopus.Action[Slack Threaded Notification - Initial].Output.channels")
THREADID = get_octopusvariable("Octopus.Action[Slack Threaded Notification - Initial].Output.threadIds") # ID of the parent Slack message for threading replies

# Timezone for date-dependent logic (e.g., deciding to run VACUUM FULL on Saturday)
REDSHIFT_TIMEZONE = os.environ.get("REDSHIFT_TIMEZONE", "Etc/UTC")  # Default to UTC if not set

# Temporary AWS credentials for an assumed role
ACCESS_KEY_ID = get_octopusvariable("Octopus.Action[AWS Assume Role].Output.AWS_ACCESS_KEY_ID")
SECRET_ACCESS_KEY = get_octopusvariable("Octopus.Action[AWS Assume Role].Output.AWS_SECRET_ACCESS_KEY")
SESSION_TOKEN = get_octopusvariable("Octopus.Action[AWS Assume Role].Output.AWS_SESSION_TOKEN")

# Timeout for individual SQL commands to prevent long-running queries from blocking the script
COMMAND_TIMEOUT_SECONDS = 10 * 30  # 300 seconds (5 minutes)

# Pipeline arguments to control the script's behavior
ANALYZE_ARG = get_octopusvariable("ANALYZE")       # If 'YES', run ANALYZE operations
DATABASE_ARG = get_octopusvariable("DATABASE")    # Specific database to target
TABLE_ARG = get_octopusvariable("TABLE")          # Specific table to target (requires DATABASE_ARG)
VACUUM_ARG = get_octopusvariable("VACUUM")        # Specific VACUUM type (e.g., "FULL", "SORT ONLY")

# --- BOTO3 CLIENT INITIALIZATION ---

def get_client(service, endpoint=None, region=AWS_REGION):
    """
    Creates and returns a Boto3 client using the temporary assumed-role credentials.

    Args:
        service (str): The name of the AWS service (e.g., 'redshift-data').
        endpoint (str, optional): A specific endpoint URL. Defaults to None.
        region (str, optional): The AWS region. Defaults to the global AWS_REGION.

    Returns:
        boto3.Client: An initialized Boto3 client.
    """
    session = bc.get_session()
    s = boto3.Session(
        botocore_session=session,
        aws_access_key_id=ACCESS_KEY_ID,
        aws_secret_access_key=SECRET_ACCESS_KEY,
        aws_session_token=SESSION_TOKEN,
        region_name=region
    )
    if endpoint:
        return s.client(service, endpoint_url=endpoint)
    return s.client(service)

# Initialize the Redshift Data API client that will be used for all database operations
redshift_data = get_client('redshift-data')

# --- DATABASE METADATA FUNCTIONS ---

def get_all_databases_boto3():
    """
    Retrieves a list of all user-created database names in the Redshift cluster.

    It connects to the default 'dev' database to query the `pg_database` catalog,
    filtering out system and template databases.

    Returns:
        list: A list of database names (strings). Returns an empty list on error.
    """
    databases = []
    try:
        # Execute a SQL query to list databases
        response = redshift_data.execute_statement(
            ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
            Database="dev",  # Connect to a default database to list others
            SecretArn=REDSHIFT_DB_USER,
            Sql="SELECT datname FROM pg_database WHERE datistemplate = false and datname not like 'sys%' and datname not like 'dev%' and datname not like 'stg%' and datdba not like '1';"
        )
        query_id = response["Id"]

        # Poll the Redshift Data API until the query is finished
        while True:
            status_desc = redshift_data.describe_statement(Id=query_id)
            status = status_desc["Status"]
            if status in ("FINISHED", "FAILED", "ABORTED"):
                break
            time.sleep(1) # Wait 1 second between checks

        # If the query succeeded, retrieve and parse the results
        if status == "FINISHED":
            results = redshift_data.get_statement_result(Id=query_id)["Records"]
            for row in results:
                databases.append(row[0]["stringValue"])

    except Exception as e:
        print(f"Error retrieving database list: {e}")
        logging.error(f"Error retrieving database list: {e}")
    return databases

def get_all_tables_in_database_boto3(database_name):
    """
    Retrieves a list of tables in a specific database that are candidates for VACUUM.

    A table is considered a candidate if it has a significant number of deleted or unsorted rows.
    This helps to avoid vacuuming tables that don't need it.

    Args:
        database_name (str): The name of the database to query.

    Returns:
        list: A list of fully qualified table names ('schema.table'). Returns an empty list on error.
    """
    tables = []
    try:
        # This SQL query identifies tables that would benefit from a VACUUM.
        # It checks for:
        # - More than 1000 deleted rows.
        # - More than 10% of rows are deleted.
        # - More than 10% of the table is unsorted.
        # It excludes temporary tables and system schemas.
        sql_query = """
            SELECT schema, "table"
            FROM svv_table_info
            WHERE (tbl_rows - estimated_visible_rows > 1000
               OR (tbl_rows > 0 AND (tbl_rows - estimated_visible_rows) * 100.0 / tbl_rows > 10.0)
               OR unsorted > 10.0)
              AND "table" NOT LIKE 'tmp_%'
              -- AND "table" NOT LIKE 'stg_%' -- Exclude stg tables that are constantly rebuild
              AND schema NOT IN ('pg_catalog', 'information_schema', 'pg_automv','pg_internal','looker_scratch','looker_scratch_external');
        """
        response = redshift_data.execute_statement(
            ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
            Database=database_name,
            SecretArn=REDSHIFT_DB_USER,
            Sql=sql_query
        )
        query_id = response["Id"]

        # Poll for completion
        while True:
            status = redshift_data.describe_statement(Id=query_id)["Status"]
            if status in ("FINISHED", "FAILED", "ABORTED"):
                break
            time.sleep(1)

        # Retrieve and parse results
        if status == "FINISHED":
            results = redshift_data.get_statement_result(Id=query_id)["Records"]
            for row in results:
                tables.append(f"{row[0]['stringValue']}.{row[1]['stringValue']}")

    except Exception as e:
        print(f"Error retrieving table list for {database_name}: {e}")
        logging.error(f"Error retrieving table list for {database_name}: {e}")
    return tables

def get_analyze_commands_for_database_boto3(database_name):
    """
    Generates 'ANALYZE' commands for tables in a database with stale statistics.

    Stale statistics can lead to poor query performance. A table's statistics are
    considered stale if the 'stats_off' metric from `svv_table_info` is greater than 10%.

    Args:
        database_name (str): The name of the database to query.

    Returns:
        list: A list of SQL 'ANALYZE' command strings. Returns an empty list on error.
    """
    commands = []
    try:
        # `stats_off` indicates the percentage of table rows that have changed since the last ANALYZE.
        sql_query = """
            SELECT 'ANALYZE ' || "schema" || '.' || "table" || ';'
            FROM svv_table_info
            WHERE stats_off > 10
              AND "table" NOT LIKE 'tmp_%'
              -- AND "table" NOT LIKE 'stg_%' -- Exclude stg tables that are constantly rebuild
              AND schema NOT IN ('pg_catalog', 'information_schema', 'pg_automv','pg_internal','looker_scratch','looker_scratch_external');
        """
        response = redshift_data.execute_statement(
            ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
            Database=database_name,
            SecretArn=REDSHIFT_DB_USER,
            Sql=sql_query
        )
        query_id = response["Id"]

        # Poll for completion
        while True:
            status = redshift_data.describe_statement(Id=query_id)["Status"]
            if status in ("FINISHED", "FAILED", "ABORTED"):
                break
            time.sleep(1)

        # Retrieve and parse results
        if status == "FINISHED":
            results = redshift_data.get_statement_result(Id=query_id)["Records"]
            for row in results:
                commands.append(row[0]["stringValue"])

    except Exception as e:
        print(f"Error retrieving analyze commands for {database_name}: {e}")
        logging.error(f"Error retrieving analyze commands for {database_name}: {e}")
    return commands

def get_analyze_commands_for_table_boto3(database_name, table_name):
    """
    Generates an 'ANALYZE' command for a single, specific table.

    Args:
        database_name (str): The database containing the table.
        table_name (str): The fully qualified name of the table (e.g., 'schema.tablename').

    Returns:
        list: A list containing a single 'ANALYZE' command string.
    """
    # This function is simpler as it doesn't need to query system tables.
    # It directly constructs the command.
    return [f"ANALYZE {table_name};"]

# --- COMMAND EXECUTION FUNCTIONS ---

def run_analyze_commands_for_database_boto3(database_name, commands, analyzed_tables):
    """
    Executes a list of ANALYZE commands in a given database.

    It includes a timeout mechanism. If a command runs for too long, it is cancelled.
    Successfully analyzed tables are added to the `analyzed_tables` list for reporting.

    Args:
        database_name (str): The database to run commands against.
        commands (list): A list of SQL ANALYZE command strings.
        analyzed_tables (list): A list to which successfully analyzed table names will be appended.
    """
    try:
        # Set a session-level configuration to prevent ANALYZE from running on tables
        # with very few changes. Here it's set to 20%.
        set_threshold_sql = "SET analyze_threshold_percent TO 20;"
        response = redshift_data.execute_statement(
            ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
            Database=database_name, SecretArn=REDSHIFT_DB_USER, Sql=set_threshold_sql
        )
        # Wait for this quick command to finish before proceeding
        while True:
            status = redshift_data.describe_statement(Id=response["Id"])["Status"]
            if status in ("FINISHED", "FAILED", "ABORTED"):
                break
            time.sleep(1)
        print(f"Set analyze_threshold_percent to 20 in database '{database_name}'.")

        # Execute each provided ANALYZE command
        for command in commands:
            print(f"Running in database '{database_name}': {command}")
            try:
                response = redshift_data.execute_statement(
                    ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
                    Database=database_name, SecretArn=REDSHIFT_DB_USER, Sql=command
                )
                query_id = response["Id"]
                start_time = time.time()
                timed_out = False

                # --- Polling loop with timeout ---
                while True:
                    # 1. Check for timeout
                    elapsed_time = time.time() - start_time
                    if elapsed_time > COMMAND_TIMEOUT_SECONDS:
                        print(f"Timeout: Command '{command}' exceeded {COMMAND_TIMEOUT_SECONDS} seconds.")
                        logging.warning(f"Timeout: Command '{command}' exceeded {COMMAND_TIMEOUT_SECONDS} seconds.")
                        timed_out = True
                        # Attempt to cancel the long-running statement
                        try:
                            print(f"Attempting to cancel statement ID: {query_id}")
                            redshift_data.cancel_statement(Id=query_id)
                        except Exception as cancel_err:
                            print(f"Warning: Could not cancel statement {query_id}: {cancel_err}")
                        break  # Exit the waiting loop

                    # 2. Check statement status
                    status_desc = redshift_data.describe_statement(Id=query_id)
                    status = status_desc["Status"]
                    if status in ("FINISHED", "FAILED", "ABORTED"):
                        break # Exit loop on terminal status

                    # 3. Wait before checking again
                    time.sleep(15) # Check status every 15 seconds

                # --- Process result after the loop exits ---
                if timed_out:
                    continue # Move to the next command

                # Check the final status of the command
                statement_info = redshift_data.describe_statement(Id=query_id)
                if statement_info["Status"] == "FINISHED":
                    print(f"Command '{command}' executed successfully.")
                    # Extract table name from command (e.g., 'ANALYZE schema.table;') -> 'schema.table'
                    table_identifier = command.split()[1].rstrip(';')
                    analyzed_tables.append(f"{database_name}.{table_identifier}")
                else: # FAILED or ABORTED
                    error_msg = statement_info.get('Error', 'Unknown error')
                    print(f"Command '{command}' ended with status {statement_info['Status']}: {error_msg}")
                    logging.error(f"Command '{command}' ended with status {statement_info['Status']}: {error_msg}")

            except Exception as exec_err:
                print(f"Error submitting/monitoring command '{command}': {exec_err}")
                logging.error(f"Error submitting/monitoring command '{command}': {exec_err}")

    except Exception as e:
        print(f"An outer error occurred while running analyze commands for {database_name}: {e}")
        logging.error(f"An outer error occurred while running analyze commands for {database_name}: {e}")

def run_vacuum_all_databases_boto3(vacuum=None):
    """
    Runs VACUUM on all relevant tables across all user databases.

    It determines the vacuum type based on the day or the provided argument.
    It then finds tables needing a vacuum in each database and executes the command.

    Args:
        vacuum (str, optional): The specific VACUUM type to run (e.g., "FULL").
                                If None, it defaults based on the day.
    """
    all_databases = get_all_databases_boto3()
    vacuumed_tables = []

    # Determine the vacuum type: use the argument if provided, otherwise default.
    # Default: FULL on Saturday, SORT ONLY on other days.
    vacuum_type = vacuum
    if not vacuum_type:
        timezone = pytz.timezone(REDSHIFT_TIMEZONE)
        now = datetime.datetime.now(timezone)
        if now.weekday() == 5:  # Saturday is 5 in Python's datetime library
            vacuum_type = "FULL"
        else:
            vacuum_type = "SORT ONLY"
    print(f"\n--- Determined VACUUM type: {vacuum_type} ---")

    if not all_databases:
        print("Could not retrieve the list of databases for VACUUM.")
        return

    # Iterate through each database and its tables
    for database in all_databases:
        print(f"\n--- Processing database for VACUUM: {database} ---")
        tables_to_vacuum = get_all_tables_in_database_boto3(database)
        for table in tables_to_vacuum:
            vacuum_command = f"VACUUM {vacuum_type} {table};"
            print(f"Running: {vacuum_command}")
            try:
                response = redshift_data.execute_statement(
                    ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
                    Database=database, SecretArn=REDSHIFT_DB_USER, Sql=vacuum_command
                )
                query_id = response["Id"]

                # Poll for completion. VACUUM FULL can be slow, so polling interval is longer.
                sleep_duration = 30 if vacuum_type == 'FULL' else 10
                while True:
                    status = redshift_data.describe_statement(Id=query_id)["Status"]
                    if status in ("FINISHED", "FAILED", "ABORTED"):
                        break
                    time.sleep(sleep_duration)

                # Process final status
                statement_info = redshift_data.describe_statement(Id=query_id)
                if statement_info["Status"] == "FINISHED":
                    print(f"Successfully vacuumed {table} in {database}.")
                    vacuumed_tables.append(f"{database}.{table}")
                else:
                    error_msg = statement_info.get('Error', 'Unknown error')
                    print(f"Error running '{vacuum_command}': {error_msg}")
                    logging.error(f"Error running '{vacuum_command}': {error_msg}")

            except Exception as e:
                print(f"Error processing VACUUM for {table} in {database}: {e}")
                logging.error(f"Error processing VACUUM for {table} in {database}: {e}")

    # Send a summary report to Slack
    if vacuumed_tables:
        print(f"\n--- Summary of VACUUM ({vacuum_type})ed Tables ---")
        for table in vacuumed_tables:
            print(f"- {table}")
        send_slack_report_vacuum(vacuumed_tables, vacuum_type)
    else:
        print("\nNo tables required vacuuming.")

def run_vacuum_specific_boto3(database, vacuum=None, table=None):
    """
    Runs VACUUM on a specific database, and optionally on a specific table.

    Args:
        database (str): The name of the database to operate on.
        vacuum (str, optional): The VACUUM type. Defaults based on the day if None.
        table (str, optional): The specific table to vacuum. If None, all relevant tables in the database are processed.
    """
    if not database:
        print("ERROR: A database name is required for this function.")
        return

    vacuumed_tables = []
    # 1. Determine vacuum type (same logic as the 'all databases' function)
    vacuum_type = vacuum
    if not vacuum_type:
        timezone = pytz.timezone(REDSHIFT_TIMEZONE)
        now = datetime.datetime.now(timezone)
        vacuum_type = "FULL" if now.weekday() == 5 else "SORT ONLY"
    print(f"\n--- Determined VACUUM type: {vacuum_type} ---")

    # 2. Identify target tables
    tables_to_process = []
    if table: # If a specific table is provided
        tables_to_process = [table]
        print(f"Targeting specific table: '{table}' in database '{database}'")
    else: # Otherwise, find all tables in the database needing a vacuum
        print(f"Targeting all relevant tables in database '{database}'.")
        tables_to_process = get_all_tables_in_database_boto3(database)
        if not tables_to_process:
            print(f"No tables found in '{database}' that require vacuuming.")
            return

    # 3. Execute VACUUM for each target table
    for tbl in tables_to_process:
        vacuum_command = f"VACUUM {vacuum_type} {tbl};"
        print(f"Running: {vacuum_command}")
        try:
            response = redshift_data.execute_statement(
                ClusterIdentifier=REDSHIFT_CLUSTER_IDENTIFIER,
                Database=database, SecretArn=REDSHIFT_DB_USER, Sql=vacuum_command
            )
            query_id = response["Id"]

            # Poll for completion
            while True:
                status_desc = redshift_data.describe_statement(Id=query_id)
                status = status_desc["Status"]
                if status in ("FINISHED", "FAILED", "ABORTED"):
                    break
                time.sleep(15) # Poll every 15 seconds

            # Process final status
            if status == "FINISHED":
                print(f"Successfully vacuumed {tbl} in {database}.")
                vacuumed_tables.append(f"{database}.{tbl}")
            else:
                error_msg = status_desc.get('Error', 'Unknown error')
                print(f"VACUUM on {tbl} ended with status {status}: {error_msg}")
                logging.error(f"VACUUM on {tbl} ended with status {status}: {error_msg}")

        except Exception as e:
            print(f"Exception during VACUUM process for '{tbl}': {e}")
            logging.error(f"Exception during VACUUM process for '{tbl}': {e}")

    # 4. Send Slack report
    if vacuumed_tables:
        send_slack_report_vacuum(vacuumed_tables, vacuum_type)
    else:
        print("\nNo tables were successfully vacuumed in this run.")

# --- SLACK REPORTING FUNCTIONS ---

def send_slack_report(analyzed_tables):
    """
    Sends a summary report of ANALYZE operations to a Slack thread.
    """
    if not all([SLACK_BOT_TOKEN, SLACK_CHANNEL, THREADID]):
        print("Slack configuration is missing. Skipping Analyze report.")
        return

    slack_client = WebClient(token=SLACK_BOT_TOKEN)
    if analyzed_tables:
        report_message = "*Redshift Analyze Report:*\nSuccessfully analyzed the following tables:\n" + "\n".join(f"- `{table}`" for table in analyzed_tables)
    else:
        report_message = "*Redshift Analyze Report:*\nNo tables required analysis or no analysis was performed."

    try:
        slack_client.chat_postMessage(
            channel=SLACK_CHANNEL, text=report_message, thread_ts=THREADID
        )
        print("Analyze Slack report sent successfully.")
    except Exception as e:
        print(f"Error sending Analyze Slack report: {e}")

def send_slack_report_vacuum(vacuumed_tables, vacuum_type):
    """
    Sends a summary report of VACUUM operations to a Slack thread.
    """
    if not all([SLACK_BOT_TOKEN, SLACK_CHANNEL, THREADID]):
        print("Slack configuration is missing. Skipping VACUUM report.")
        return

    slack_client = WebClient(token=SLACK_BOT_TOKEN)
    if vacuumed_tables:
        report_message = f"*Redshift VACUUM ({vacuum_type}) Report:*\nSuccessfully vacuumed the following tables:\n" + "\n".join(f"- `{table}`" for table in vacuumed_tables)
    else:
        report_message = f"*Redshift VACUUM ({vacuum_type}) Report:*\nNo tables were vacuumed in this run."

    try:
        slack_client.chat_postMessage(
            channel=SLACK_CHANNEL, text=report_message, thread_ts=THREADID
        )
        print(f"VACUUM ({vacuum_type}) Slack report sent successfully.")
    except Exception as e:
        print(f"Error sending VACUUM ({vacuum_type}) Slack report: {e}")

# --- MAIN EXECUTION LOGIC ---

def main():
    """
    Main function to orchestrate the maintenance operations based on pipeline arguments.
    """
    all_analyzed_tables = [] # Collects all analyzed tables for a final summary report

    # --- Execution Path 1: Specific table in a specific database ---
    if DATABASE_ARG and TABLE_ARG:
        print(f"--- Running in scoped mode: Database '{DATABASE_ARG}', Table '{TABLE_ARG}' ---")
        if VACUUM_ARG:
            run_vacuum_specific_boto3(DATABASE_ARG, VACUUM_ARG, TABLE_ARG)
        if ANALYZE_ARG == 'YES':
            commands = get_analyze_commands_for_table_boto3(DATABASE_ARG, TABLE_ARG)
            run_analyze_commands_for_database_boto3(DATABASE_ARG, commands, all_analyzed_tables)

    # --- Execution Path 2: All tables in a specific database ---
    elif DATABASE_ARG:
        print(f"--- Running in database mode: Database '{DATABASE_ARG}' ---")
        if VACUUM_ARG:
            run_vacuum_specific_boto3(DATABASE_ARG, VACUUM_ARG)
        if ANALYZE_ARG == 'YES':
            print(f"\n--- Checking for tables to ANALYZE in DB {DATABASE_ARG} ---")
            commands = get_analyze_commands_for_database_boto3(DATABASE_ARG)
            if commands:
                print("Found tables needing ANALYZE:")
                for cmd in commands: print(f"- {cmd}")
                run_analyze_commands_for_database_boto3(DATABASE_ARG, commands, all_analyzed_tables)
            else:
                print("No tables in this database require ANALYZE.")

    # --- Execution Path 3: Default, all databases ---
    else:
        print("--- Running in full mode: All databases ---")
        all_databases = get_all_databases_boto3()
        if not all_databases:
            print("Could not retrieve database list. Exiting.")
            return

        print("Found the following databases:")
        for db in all_databases: print(f"- {db}")

        # Run VACUUM on all databases first
        run_vacuum_all_databases_boto3(VACUUM_ARG)

        # Then run ANALYZE on all databases
        if ANALYZE_ARG == 'YES':
            for database in all_databases:
                print(f"\n--- Processing database for ANALYZE: {database} ---")
                commands = get_analyze_commands_for_database_boto3(database)
                if commands:
                    print("Found tables needing ANALYZE:")
                    for cmd in commands: print(f"- {cmd}")
                    run_analyze_commands_for_database_boto3(database, commands, all_analyzed_tables)
                else:
                    print("No tables in this database require ANALYZE.")

    # --- Final Summary Report for ANALYZE ---
    # A single summary is sent at the end, regardless of execution path.
    if ANALYZE_ARG == 'YES':
        if all_analyzed_tables:
            print("\n--- Summary of All Analyzed Tables ---")
            for table in all_analyzed_tables:
                print(f"- {table}")
            send_slack_report(all_analyzed_tables)
        else:
            print("\nNo tables were analyzed across all specified scopes.")
            send_slack_report([]) # Send an empty report


# --- SCRIPT ENTRY POINT ---
if __name__ == "__main__":
    main()