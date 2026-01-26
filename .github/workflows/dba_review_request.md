DBA Review Request Automation
=============================

This repository contains the GitHub Actions workflows designed to enable "ChatOps" for Database Administration. It allows developers to request a DBA review directly from a Pull Request comment, which then validates existing Jira tickets and notifies the DBA team via Slack.

📂 Workflow Files
-----------------

| **File** | **Type** | **Description** |
| --- | --- | --- |
| `dba_review_request.yml` | **Trigger Workflow** | Monitors PR comments for a specific "magic phrase" and extracts the necessary user and PR metadata. |
| `dba_review_request_general.yml` | **Reusable Workflow** | The logic handler. It looks up the associated Jira ticket and sends a Slack notification to the DBA channel. |

🚀 Usage & Trigger
------------------

This automation is designed to be triggered by an **Issue Comment** (Pull Request comment).

### 1\. The Trigger Phrase

The workflow listens specifically for comments on Pull Requests that contain the following mention:

> `@Company/dba review requested`

### 2\. Execution Logic

1.  **Validation:** The `variable-set` job ensures the event is a Pull Request and the comment body contains the required phrase.

2.  **Data Extraction:** The workflow captures the repository name, the PR URL, and the username of the person requesting the review.

3.  **Ticket Lookup:** The reusable workflow attempts to retrieve an existing DB Ticket URL using the `DBRE/.github/actions/Jira/retrieve-db-ticket` action.

4.  **Notification:**

    -   **Condition:** A Slack notification is sent **only if** a valid Jira ticket link is found (`outputs.jira_ticket_link != ''`).

    -   **Destination:** The notification is sent to the configured DBA Slack channel using the `review_requested` message format.

🛠 Setup & Configuration
------------------------

### Enabling the Trigger

By default, the `issue_comment` trigger is commented out in `dba_review_request.yml`. To enable the ChatOps functionality, you must uncomment the following lines:

YAML

```
on:
  # workflow_dispatch # Optional: keep for testing
  issue_comment:      # Uncomment this to enable comment monitoring

```

### Inputs

The reusable workflow requires the following inputs, which are passed automatically by the trigger workflow:

-   `github-repository`: The full name of the repository.

-   `pr-url`: The HTML URL of the Pull Request.

-   `user`: The login ID of the user triggering the request.

### Secrets

The following secrets must be inherited or present in the repository settings for the external actions to function:

| **Secret** | **Description** |
| --- | --- |
| `JIRA_TOKEN_DB` | Required to search Jira for the existing database ticket. |
| `SLACK_BOT_TOKEN` | Required to authenticate with the Slack API to send the notification. |

📦 Dependencies
---------------

This automation relies on the following custom actions from the `DBRE` organization:

1.  `DBRE/.github/actions/Jira/retrieve-db-ticket@main`

2.  `DBRE/.github/actions/Slack/dba-slack-notification@main`