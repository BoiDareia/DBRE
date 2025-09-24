# Git and Database Automation Script

This PowerShell script is a toolkit designed for use in automated deployment pipelines (like CI/CD). It provides functions to manage **Git repositories** and to **query a database** to check deployment history. 🤖

The script's main purpose is to automate the process of fetching the correct version of source code and understanding the current state of a database.

---

## Core Functions

The script can be broken down into a few key areas:

### 1. Git Workflow Management (`GitCheckoutBranch`)

This is the main, high-level function for handling source code. It automates the entire process of getting a specific branch or tag from a Git repository.

-   If the code doesn't exist locally, it will **clone** the repository.
-   If the code already exists, it will perform a **clean-up** (resetting any local changes and removing untracked files) and then **fetch** and **pull** the latest updates.
-   It handles authentication by embedding the username and password directly into the Git URL.

### 2. Git Command Helpers (`Invoke-Git`, `Execute-Command`)

These are lower-level functions that `GitCheckoutBranch` uses to run Git commands.

-   `Invoke-Git` is a simple wrapper for executing basic Git commands.
-   `Execute-Command` is a more robust function for running any external program, capturing all of its output (both standard and error streams) and its exit code for detailed error handling.

### 3. Database Version Check (`LatestVersionDeployed`)

This function connects to a SQL Server database to check the **Flyway schema history table**.

-   Its primary goal is to find out which version of the database schema (or data) was last deployed successfully.
-   This information is critical for automated processes to decide what the next migration should be or to determine the correct version for a rollback.

### 4. Utility Functions (`Test-LastExit`)

This is a small helper function that checks if the last command executed was successful. If not, it stops the script to prevent further issues in the deployment pipeline.