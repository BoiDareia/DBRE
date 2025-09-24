# Documentation: `linting.yml` Workflow

## 📜 Overview

This GitHub Actions workflow is designed to automate two key processes related to database changes in a pull request (PR):

1.  **SQL Linting**: It automatically checks any modified `.sql` files for style and quality issues using the `sqlfluff` linter. The results are displayed directly in the PR as annotations.
2.  **Jira Ticket Creation**: If SQL files have been changed, it runs a script to automatically create a database-related ticket in Jira.
3.  **PR Notification**: If a Jira ticket is successfully created, it posts a comment on the PR with a direct link to the ticket, ensuring visibility for the development team.

This automation helps maintain SQL code quality and streamlines the process of tracking database changes.


---

## 🚀 Triggers

The workflow is currently configured to run under the following condition:

* **Manual Trigger (`workflow_dispatch`)**: A user can manually trigger the workflow from the "Actions" tab of the GitHub repository.

The configuration also includes a commented-out trigger for `pull_request` events. If enabled, the workflow would run automatically whenever a PR is opened, updated, or synchronized.

---

## 🛠️ Jobs

The workflow consists of two sequential jobs: `lint-sql-files` and `pr-comment`.

### Job: `lint-sql-files`

This is the primary job that performs the main logic.

**Purpose**: To lint all changed SQL files in a PR and, if applicable, create a corresponding Jira ticket.

**Steps**:
1.  **Checkout Repo**: Checks out the branch associated with the pull request. It fetches the last two commits to enable file change detection.
2.  **Setup Python**: Prepares a Python 3.x environment.
3.  **Install sqlfluff**: Installs the `sqlfluff` SQL linter via pip.
4.  **Get Changed SQL Files**: Uses the `tj-actions/changed-files` action to identify and list only the `.sql` files that were modified in the PR.
5.  **Lint SQL Files**:
    * This step only runs if the previous step found changes to SQL files.
    * It executes `sqlfluff lint` on the modified files using a predefined configuration (`Core/DB.SDK/config.sqlfluff`).
    * The output is formatted as JSON, compatible with GitHub annotations, and saved to a file named `annotations.json`.
6.  **Annotate**: Reads the `annotations.json` file and posts the linting warnings or errors as annotations directly on the relevant lines of code in the PR's "Files changed" tab.
7.  **Ticket Creation**:
    * Executes a Python script (`.github/actions/create_db_ticket.py`).
    * It passes necessary context to the script via environment variables, including repository info, PR details, and secrets.

**Outputs**: This job produces two outputs used by the next job:
* `jira_action`: The status of the ticket creation (e.g., `"created"`).
* `jira_ticket_link`: The URL of the newly created Jira ticket.

### Job: `pr-comment`

This job is dependent on the successful completion of the `lint-sql-files` job.

**Purpose**: To notify developers on the PR that a database ticket has been created.

**Condition**: This job has a strict `if` condition and **will only run if** the `jira_action` output from the previous job is equal to `"created"`.

**Steps**:
1.  **Checkout Repo**: Checks out the code.
2.  **Comment PR**:
    * Uses the official GitHub CLI (`gh`) to post a comment.
    * The comment content is a predefined message that includes the Jira ticket link, which it receives from the output of the `lint-sql-files` job.

---

## 🔐 Secrets

This workflow requires the following secrets to be configured in the repository's settings (`Settings > Secrets and variables > Actions`):

* `GITHUB_TOKEN`: This is automatically provided by GitHub Actions and is used by the CLI and other actions to interact with the repository.
* `JIRA_TOKEN_DB`: A personal access token or API key for Jira with permissions to create tickets in the designated database project. This is passed securely to the `create_db_ticket.py` script.