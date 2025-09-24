<#
.SYNOPSIS
    A PowerShell script to automatically stage, commit, and push changes in a Git repository.

.DESCRIPTION
    This script automates the process of committing and pushing changes to a Git repository.
    It first navigates to the specified repository path, fetches and merges the latest changes from the
    remote 'master' branch to ensure the local workspace is up-to-date. It then checks for any
    uncommitted local changes. If changes are found, it stages all of them, commits with a
    predefined message, and pushes them to the remote repository. If no changes are detected,
    the script exits gracefully.

.NOTES
    Author:      Your Name
    Date:        25/08/2025
    Requires:    - Git CLI to be installed and available in the system's PATH.
                 - The machine running the script must have appropriate permissions to push to the remote repository.
#>

#================================================================================
# 1. CONFIGURATION
#================================================================================
# The absolute path to the local Git repository.
[string]$repoPath = "C:\src\Database-deployment"
# The commit message to use for the new commit.
[string]$commitMessage = "Add new SQL release files"
# The name of the branch to sync with and push to.
[string]$branchName = "master"

#================================================================================
# 2. SCRIPT EXECUTION
#================================================================================

# --- Navigate to Repository ---
try {
    Set-Location -Path $repoPath
    Write-Host "Successfully navigated to the repository at '$repoPath'."
}
catch {
    Write-Error "Error: The repository path '$repoPath' was not found or is inaccessible."
    exit 1
}

# --- Sync with Remote Repository ---
Write-Host "Syncing local workspace with remote branch '$branchName'..."
git fetch origin $branchName --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Error "FAILED: Could not fetch from origin. Check your connection and repository URL."
    exit 1
}

git merge "origin/$branchName" --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Error "FAILED: Could not merge from 'origin/$branchName'. You may have local conflicts that require manual resolution."
    exit 1
}
Write-Host "Local branch is now in sync with the remote."

# --- Check for Changes ---
Write-Host "Checking for local changes to commit..."
$gitStatus = git status --porcelain

if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "No new changes detected. Nothing to commit. Script finished successfully."
    exit 0 # Exit with a success code as no action was needed.
}

# --- Stage, Commit, and Push Changes ---
Write-Host "Changes detected. Staging, committing, and pushing..."

git add -A
if ($LASTEXITCODE -ne 0) {
    Write-Error "FAILED: Could not stage changes using 'git add -A'."
    exit 1
}
Write-Host "Successfully staged all changes."

git commit -m "$commitMessage"
if ($LASTEXITCODE -ne 0) {
    Write-Error "FAILED: Could not commit changes. There might be pre-commit hooks failing or other Git issues."
    exit 1
}
Write-Host "Committed changes with message: `"$commitMessage`"."

git push --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Error "FAILED: Could not push changes to the remote repository. Check your permissions and ensure the local branch is not behind the remote."
    exit 1
}
Write-Host "Successfully pushed changes to the remote repository."
