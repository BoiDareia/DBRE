Database Operations & Automation
================================

This repository hosts a suite of GitHub Actions workflows designed to streamline database operations. It automates SQL code quality checks (linting), Jira ticket creation for database changes, and "ChatOps" based DBA review requests.

📂 Workflow Overview
--------------------

The repository utilizes a mix of caller and reusable workflows to handle distinct database lifecycle events.

| **Workflow / Feature** | **Files** | **Description** |
| --- | --- | --- |
| **SQL Ticket Automation** |

`create-db-ticket.yml`

`create_db_ticket_general.yml`

 | Detects SQL file changes in PRs and creates Jira tickets/Slack notifications. |
| **SQL Linting** | `linting.yml` (implied) | Lints modified SQL files using `sqlfluff` and annotates the Pull Request. |
| **DBA Review ChatOps** |

`dba_review_request.yml`

`dba_review_request_general.yml`

 | Triggers alerts to DBAs when a user requests a review via comment. |

* * * * *

1\. SQL File Detection & Ticket Automation
------------------------------------------

This modular workflow ensures tickets are created only when relevant database files are modified.

### Process Flow

1.  **Detection:** The `sql-file-check` job uses `git diff` (comparing `HEAD` vs `HEAD^1`) to identify if any `.sql` files were changed.

2.  **Logic:** If `sql-files-altered > 0`, the reusable workflow is triggered.

3.  **Action:**

    -   **Jira:** Creates or updates a ticket using `DBRE/.github/actions/Jira/db-ticket-create`.

    -   **Slack:** Sends a notification to the DBA channel only if a new ticket was successfully created.

* * * * *

2\. SQL Code Linting
--------------------

This workflow focuses on code quality by automating style checks and providing immediate feedback in the Pull Request.

### Workflow Details

-   **Linting Logic:**

    -   It identifies modified `.sql` files using `tj-actions/changed-files`.

    -   It installs `sqlfluff` and runs it against the files using the configuration found in `Core/DB.SDK/config.sqlfluff`.

    -   **Annotation:** Results are posted as annotations directly on the code in the PR's "Files changed" tab.

-   **Ticket Integration:**

    -   Executes a Python script (`.github/actions/create_db_ticket.py`) to handle ticket creation.

    -   If a ticket is created (`jira_action == 'created'`), a comment is posted on the PR with the ticket link.

* * * * *

3\. DBA Review Request (ChatOps)
--------------------------------

This workflow enables developers to request DBA reviews directly from a Pull Request comment.

### Usage

To trigger the request, a user must post a comment on the PR containing the following phrase:

> `@Company/dba review requested`

### Execution Logic

1.  **Validation:** The workflow verifies the event is a PR and the comment contains the specific "magic phrase".

2.  **Lookup:** It attempts to retrieve an existing DB Ticket URL using `DBRE/.github/actions/Jira/retrieve-db-ticket`.

3.  **Notification:** If a valid ticket link is found, a Slack notification is sent to the DBA channel using the `review_requested` message format.

* * * * *

🛠 Configuration & Secrets
--------------------------

### Required Secrets

To function correctly, the following secrets must be configured in the repository settings:

| **Secret Name** | **Required By** | **Description** |
| --- | --- | --- |
| `GITHUB_TOKEN` | All Workflows | Standard GitHub token for PR metadata and CLI access. |
| `JIRA_TOKEN_DB` | All Workflows | Token for authenticating with the Jira API to create/search tickets. |
| `SLACK_BOT_TOKEN` | Notifications | Token for the Slack Bot to send alerts to the DBA channel. |

### Enabling Triggers

By default, the workflows are often set to `workflow_dispatch` (manual). To enable automatic execution:

-   **For Ticket & Linting Workflows:** Uncomment the `pull_request` triggers in the YAML files.

-   **For Review Requests:** Uncomment the `issue_comment` trigger in `dba_review_request.yml`.

### Dependencies

These workflows rely on custom actions from the `DBRE` organization, including:

-   `DBRE/.github/actions/Jira/retrieve-db-ticket@main`

-   `DBRE/.github/actions/Slack/dba-slack-notification@main`

-   `DBRE/.github/actions/Jira/db-ticket-create@main`