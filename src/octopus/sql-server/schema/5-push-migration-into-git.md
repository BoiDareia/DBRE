# Git Auto-Commit and Push Script

## 1. Overview

This PowerShell script automates the common workflow of synchronizing a local Git repository with its remote, and then committing and pushing any local changes. It is designed to be run in an automated environment, such as a CI/CD pipeline or a scheduled task, where new files (e.g., build artifacts, SQL release files) are generated and need to be version-controlled.

## 2. Features

* **Repository Synchronization**: Before checking for changes, the script safely fetches and merges the latest updates from the specified remote branch to prevent push conflicts.
* **Change Detection**: It uses `git status --porcelain` to reliably detect if there are any staged or unstaged changes in the workspace.
* **Automated Commit**: If changes are found, it stages all of them (`git add -A`), commits them with a configurable message, and pushes to the remote.
* **Graceful Exit**: If no changes are detected, the script logs a success message and exits cleanly, which is ideal for CI/CD environments where "no change" is a successful outcome.
* **Robust Error Handling**: The script checks the exit code of each Git command and will fail the step with a clear error message if any command fails, preventing silent errors.

## 3. Setup and Usage

### Prerequisites

* **Git CLI**: The machine executing the script must have the Git command-line interface installed and accessible via the system's PATH.
* **Permissions**: The execution context (e.g., the build agent user) must have the necessary permissions to `push` to the remote repository. This usually involves pre-configured SSH keys or a credential manager.

### Configuration

Before running the script, you need to configure the variables at the top of the file:

```powershell
# The absolute path to the local Git repository.
[string]$repoPath = "C:\src\Database-deployment"

# The commit message to use for the new commit.
[string]$commitMessage = "Add new SQL release files"

# The name of the branch to sync with and push to.
[string]$branchName = "master"