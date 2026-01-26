DB Project Ticket Automation
============================

This repository contains a modular GitHub Actions workflow designed to automate the creation of Jira tickets and Slack notifications whenever SQL files are modified in a Pull Request.

📂 Workflow Files
-----------------

| **File** | **Type** | **Description** |
| --- | --- | --- |
| `create-db-ticket.yml` | **Caller Workflow** | The entry point. It checks out the code, identifies modified `.sql` files, and triggers the reusable workflow if changes are detected. |
| `create_db_ticket_general.yml` | **Reusable Workflow** | The logic handler. It receives data from the caller and executes the Jira ticket creation and Slack notification steps. |

🚀 Process Flow
---------------

The automation follows a two-stage process to ensure tickets are only created when relevant database files are altered.

Code snippet

```
graph TD
    A[Trigger: Manual or Pull Request] --> B(Job: sql-file-check)
    B --> C{Are .sql files changed?}
    C -- No --> D[End Workflow]
    C -- Yes --> E(Call Reusable Workflow)
    E --> F[Create/Update Jira Ticket]
    F --> G{Ticket Created?}
    G -- Yes --> H[Send Slack Notification]
    G -- No --> I[Skip Notification]

```

⚙️ Workflow Details
-------------------

### 1\. SQL File Detection (`sql-file-check`)

Located in `create-db-ticket.yml`, this job identifies changes using `git diff`:

-   It fetches the repository with a depth of 2 to compare the current commit against the previous one.

-   It runs a shell script to list files ending in `*.sql` modified between `HEAD` and `HEAD^1`.

-   **Outputs:**

    -   `DIFFS`: Returns `1` if SQL files are found, `0` if not.

    -   `SQL_FILES`: A space-separated string of the modified filenames.

### 2\. Ticket & Notification Logic (`create-db-ticket`)

Located in `create_db_ticket_general.yml`, this job executes the business logic:

-   **Condition:** It only runs if the input `sql-files-altered` is greater than `0`.

-   **Jira Integration:** Uses the custom action `DBRE/.github/actions/Jira/db-ticket-create` to create or update a ticket based on the PR details.

-   **Slack Integration:** Uses `DBRE/.github/actions/Slack/dba-slack-notification` to alert the DBA channel, but **only** if the Jira action reports that a new ticket was `'created'`.

🛠 Configuration & Secrets
--------------------------

To function correctly, the following secrets must be available in the repository or organization settings:

| **Secret Name** | **Required By** | **Description** |
| --- | --- | --- |
| `GITHUB_TOKEN` | Jira Action | Standard GitHub token for PR metadata access. |
| `JIRA_TOKEN_DB` | Jira Action | Authentication token for the Jira API. |
| `SLACK_BOT_TOKEN` | Slack Action | Authentication token for the Slack Bot. |

📖 Usage
--------

### Enabling Automatic Triggers

By default, the provided `create-db-ticket.yml` is configured for `workflow_dispatch` (manual trigger). To enable it for Pull Requests, uncomment the `pull_request` section in the YAML file:

YAML

```
on:
  workflow_dispatch
  pull_request:         # Uncomment
    types: [opened, synchronize] # Uncomment

```

### Inputs Reference

The reusable workflow (`create_db_ticket_general.yml`) accepts the following inputs passed from the caller:

-   `github-repository`: The full repository name (e.g., `owner/repo`).

-   `head-ref`: The source branch name.

-   `pr-url`: The URL of the Pull Request.

-   `repo-name`: The name of the repository.

-   `sql-files-altered`: Boolean/Integer flag indicating if SQL files changed.

-   `sql-files-list`: The list of specific SQL files modified.