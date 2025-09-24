GitHub Action: Send DBA Review Request
======================================

This GitHub Actions workflow automates the process of notifying the Database Administration (DBA) team on Slack when a review is requested on a pull request. It's triggered by a specific comment, fetches a related Jira ticket, and then constructs a rich, interactive notification in a designated Slack channel.

workflow Overview
-----------------

The workflow is named `Send DBA Review Request` and is designed to streamline communication between developers and the DBA team.

-   **Trigger**: The workflow runs whenever a **comment is made on an issue** (which includes pull requests) within the repository.

-   **Condition**: It only proceeds if the comment is on a pull request and contains the specific trigger phrase: `@company/dba review requested`.

-   **Action**: It finds the associated Jira ticket for the PR and sends a notification to a Slack channel, tagging the DBA user group and providing a direct button to the ticket.

* * * * *

⚙️ Jobs
-------

The workflow consists of two sequential jobs: `get_ticket_info` and `slack-notification-send`.

### 1\. Job: `get_ticket_info`

This job is responsible for retrieving the URL of the Jira ticket associated with the pull request.

-   **Condition**: Runs only if the trigger comment is on a PR and contains `@company/dba review requested`.

-   **Runner**: Executes on an `ubuntu-latest` virtual machine.

-   **Output**: Produces an output named `jira_ticket_url`, which contains the link to the Jira ticket. This output is then used by the next job.

#### Steps:

1.  **Checkout Code**:

    YAML

    ```
    - id: repoCheckout
      uses: actions/checkout@v4

    ```

    Checks out the repository's code so that the workflow can access local files, such as the Python script.

2.  **Setup Python**:

    YAML

    ```
    - id: setup_python
      uses: actions/setup-python@v5

    ```

    Initializes a Python 3.x environment for the script to run in.

3.  **Get Ticket URL**:

    YAML

    ```
    - id: get_ticket_url
      run: |
        pip install requests
        python .github/actions/get_ticket_url.py

    ```

    This is the core step. It first installs the `requests` library and then executes the Python script located at `.github/actions/get_ticket_url.py`. This script contains the logic to interact with the GitHub and Jira APIs to find the correct ticket URL. It uses several secrets and context variables:

    -   `GITHUB_TOKEN`: An automatically generated token to authenticate with the GitHub API.

    -   `JIRA_TOKEN_DB`: A secret token for authenticating with the Jira API.

    -   `REPO_NAME`: The name of the current repository.

    -   `PR_URL`: The URL of the pull request that triggered the workflow.

* * * * *

### 2\. Job: `slack-notification-send`

This job takes the Jira ticket URL from the previous job and sends the notification to Slack.

-   **Dependency**: It `needs` the `get_ticket_info` job to complete successfully before it can run.

-   **Condition**: It only runs if the `jira_ticket_url` output from the previous job is not empty, ensuring a notification is only sent if a ticket was found.

-   **Runner**: Executes on an `ubuntu-latest` virtual machine.

#### Steps:

1.  **Send Slack Message**:

    YAML

    ```
    - id: dba_review_request
      uses: slackapi/slack-github-action@v2.0.0

    ```

    This step uses the official `slack-github-action` to send a message. The `with` block configures the message content and appearance using Slack's Block Kit API.

    **Payload Details**:

    -   `channel`: The message is sent to a specific channel ID (`G01CA414DPH`).

    -   `text`: A fallback text message for notifications that can't render blocks.

    -   `blocks`: A JSON structure that defines a rich, interactive message.

        -   **Header**: Displays who requested the review (e.g., `PR review requested by octocat`).

        -   **Divider**: A visual separator.

        -   **Section**: The main body of the message, which mentions the DBA subteam (`<!subteam^SOMETHING>`) to trigger a notification for that group.

        -   **Actions**: Contains interactive elements. In this case, it's a **button** labeled "DB Ticket" that links directly to the Jira ticket URL retrieved by the first job.

* * * * *

🔑 Required Secrets
-------------------

To function correctly, this workflow requires the following secrets to be configured in the repository's settings (`Settings > Secrets and variables > Actions`):

-   `JIRA_TOKEN_DB`: An API token with permissions to read from your Jira project.

-   `SLACK_BOT_TOKEN`: A Slack Bot token with `chat:write` permissions for the specified channel.