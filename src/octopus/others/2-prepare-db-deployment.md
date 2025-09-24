# Octopus Deploy: Database Build and Deploy Script

## 📜 Overview

This PowerShell script serves as the central execution engine for a database deployment process within Octopus Deploy. Its primary responsibility is to gather all necessary configurations, credentials, and parameters, and then invoke a core function (`DoDatabaseContinuousDeployment`) to perform the actual database migration.

The script is designed to be robust, using a `try/catch/finally` block to ensure that the deployment status is always reported back to Octopus Deploy, whether it succeeds or fails.


---

## ⚙️ Prerequisites

To run this script successfully, the following components must be configured:

* **Octopus Deploy**: The script is designed to be executed as a step in an Octopus Deploy project.
* **AWS Credentials**: A preceding step must provide temporary AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`).
* **Dependent Scripts**: The script relies on functions from several other PowerShell files that must be in the same directory:
    * `DeployDatabaseVersionsGenericDBOctopus.ps1`
    * `GitFunctionsGenericDBOctopus.ps1`
    * `BuildFunctionsGenericDB.ps1`
    * `FlywayFunctionsGenericDBOctopus.ps1`
* **XML Configuration**: A database-specific configuration file (e.g., `MyDatabase.xml`) must exist in the `config` sub-directory.

---

## 📥 Input Variables

This script consumes several variables provided by the Octopus Deploy step context.

| Variable Name                  | Type    | Description                                                                                             | Example                               |
| ------------------------------ | ------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `Step.ENV`                     | String  | The short name of the target environment (e.g., prod, dev, stg).                                        | `stg`                                 |
| `Step.DATABASE`                | String  | The name of the database, used to find the corresponding XML config file.                               | `AuthenticationDB`                    |
| `Step.ROLE_ARN`                | String  | The AWS Account ID used to construct the full IAM Role ARN for assuming permissions.                      | `123456789012`                        |
| `Step.AWS_ACCESS_KEY_ID`       | String  | The temporary AWS access key from an assume role step.                                                  | (sensitive value)                     |
| `Step.AWS_SECRET_ACCESS_KEY`   | String  | The temporary AWS secret key from an assume role step.                                                  | (sensitive value)                     |
| `Step.AWS_SESSION_TOKEN`       | String  | The temporary AWS session token from an assume role step.                                               | (sensitive value)                     |
| `Step.OCTOPUS_URL`             | String  | The URL of the Octopus Deploy server instance.                                                          | `https://octopus.mycompany.com`       |
| `Step.OCTOPUS_API_KEY`         | String  | An API key for authenticating with the Octopus server.                                                  | (sensitive value)                     |
| `RELEASE`                      | String  | The Git branch or tag to be deployed.                                                                   | `v2.15.0`                             |
| `REDEPLOY`                     | String  | A flag (`'True'` or `'False'`) indicating if this is a manual redeployment.                             | `False`                               |
| `Step.IsTag`                   | String  | A flag (`'True'` or `'False'`) from a previous step indicating if `$RELEASE` is a tag.                  | `True`                                |

---

## 🧠 Core Logic & Workflow

1.  **Initialization**: The script begins by reading key parameters from Octopus Deploy, such as the environment, database name, and AWS role. It constructs the full AWS Role ARN.
2.  **Environment Normalization**: A `switch` statement converts the short environment name (`prod`, `dev`) into a full name (`production`, `dev`) and saves it as an output variable for other steps.
3.  **Credential & Config Loading**:
    * It sets AWS and Octopus credentials as local environment variables.
    * It sources all necessary helper scripts.
    * It loads the database-specific `.xml` config file.
4.  **Parameter Extraction**: Key deployment parameters are read from the loaded XML config, including:
    * `OutOfOrder`: Whether to allow Flyway to run migrations out of sequence.
    * `AWSRegion`: The AWS region where resources are located.
    * `transaction`: Whether Flyway should wrap migrations in a transaction.
5.  **Database Credential Fetching**: The script retrieves the database credentials securely from AWS Secrets Manager using the Secret ID found in the config file. It also includes special character handling for passwords to prevent issues with command-line tools.
6.  **Execution**: The script calls the `DoDatabaseContinuousDeployment` function, passing all the collected parameters to it. This function (defined in one of the sourced scripts) contains the core logic for running the database migration.
7.  **Status Reporting**:
    * The entire execution is wrapped in a `try/catch/finally` block.
    * **On Success**: The `finally` block sets an Octopus output variable `COMPLETED` to `"SUCCEEDED!!"`.
    * **On Failure**: The `catch` block captures the exception, and the `finally` block sets `COMPLETED` to `"FAILED!!"` along with the error message. The script then exits with a non-zero code to signal failure to Octopus.

---

## 📤 Output Variables

The script produces the following output variables for use in subsequent Octopus Deploy steps.

| Variable Name     | Description                                                                                                       | Example Value                     |
| ----------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `ROLE_ARN`        | The full ARN of the IAM role to be used.                                                                          | `arn:aws:iam::...:role/...`       |
| `ENVIRONMENT`     | The normalized, full name of the environment.                                                                     | `staging`                         |
| `OUTOFORDER`      | Flag for Flyway's `outOfOrder` setting.                                                                           | `true`                            |
| `AWS_REGION`      | The AWS region for the deployment.                                                                                | `eu-west-1`                       |
| `FW_TRAN`         | Flag for Flyway's transaction setting.                                                                            | `true`                            |
| `SECRETMANAGERID` | The ID of the secret in AWS Secrets Manager.                                                                      | `db/creds/my-app`                 |
| `User`            | The database username.                                                                                            | `my_db_user`                      |
| `Password`        | The database password (plain text).                                                                               | (sensitive value)                 |
| `COMPLETED`       | A final status message indicating the outcome of the script.                                                      | `SUCCEEDED!!` or `FAILED!! With...` |