GitHub Action: Automated Jira Ticket Creation for Database Changes
==================================================================

📝 Summary
----------

This GitHub Action automates the process of creating a Jira ticket for database-related changes. It triggers on a pull request, checks if the DBA team has been requested for a review, and if any `.sql` files have been modified. If these conditions are met, it creates a Jira ticket and posts a link to it as a comment on the pull request.

* * * * *

⚙️ How It Works
---------------

The workflow is divided into two main jobs that run in sequence: `create-db-ticket` and `pr-comment`.

### 1\. Trigger Conditions

The action starts automatically when any of the following events occur on a pull request:

-   It's **opened** or **reopened**.

-   It's **edited** (e.g., the title is changed).

-   A **review is requested** from a team or user.

-   New commits are pushed to the branch (**synchronize**).

### 2\. Job: `create-db-ticket`

This is the core job that decides whether to create a ticket.

-   **DBA Review Check**: The job will **only run** if a team with the slug `dba` is added as a reviewer on the pull request.

-   **File Detection**: It then checks the pull request's commits to see if any files with a `.sql` extension have been changed.

-   **Ticket Creation**:

    -   If `.sql` files were changed, it runs a Python script (`.github/actions/create_db_ticket.py`).

    -   This script uses a Jira API token (stored as a secret) to create a new ticket in the database project.

    -   The script then outputs whether a ticket was created and the URL of the new ticket.

YAML

```
# This condition ensures the job only runs when the 'dba' team is a reviewer
if: ${{contains(github.event.pull_request.requested_teams.*.slug,'dba')}}

```

### 3\. Job: `pr-comment`

This job is responsible for notifying the team about the new ticket.

-   **Conditional Run**: It **only runs if** the `create-db-ticket` job successfully created a Jira ticket.

-   **Post Comment**: It uses the GitHub CLI (`gh`) to post a comment directly on the pull request, which includes a direct link to the Jira ticket.

Bash

```
# Example of the comment posted by the action
"A database ticket has been created for this PR. Ticket Link - $DB_TICKET_LINK"

```

* * * * *

🗺️ Workflow Diagram
--------------------

Code snippet

```
graph TD
    A[Pull Request Event] --> B{DBA Team Review Requested?};
    B -->|Yes| C{SQL Files Changed?};
    B -->|No| E[Workflow Ends];
    C -->|Yes| D[Run Python Script to Create Jira Ticket];
    C -->|No| E;
    D --> F{Ticket Created Successfully?};
    F -->|Yes| G[Post Jira Ticket Link as PR Comment];
    F -->|No| E;
    G --> E;

```

* * * * *

🔑 Required Secrets
-------------------

For this action to function, the following secret must be configured in the repository's settings (`Settings > Secrets and variables > Actions`):

-   **`JIRA_TOKEN_DB`**: An API token with permissions to create tickets in the relevant Jira project.