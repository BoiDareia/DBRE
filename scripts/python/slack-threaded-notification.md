# Octopus Deploy Slack Notification Script

## 1. Overview

This Python script is designed to be used as a step in an Octopus Deploy process to send notifications to Slack. It supports sending initial messages to one or more channels and then replying to those messages in a thread for subsequent updates (e.g., success or failure notifications).

The script is designed to be reusable across different steps of a deployment process to provide a continuous, threaded log of the deployment's progress directly in Slack.

---

## 2. Features

* **Multi-Channel Support**: Send notifications to a comma-separated list of Slack channels.
* **Threaded Conversations**: Automatically detects if an initial message was sent and replies in a thread for all subsequent messages.
* **Status Reactions**: Adds a success (✅) or failure (❌) emoji reaction to the initial message when a deployment process completes or fails.
* **Error Handling**: Provides clear error messages if the Slack API returns an error, such as the app not being in a channel.
* **Secure**: Designed to use a securely stored Slack API token (e.g., as a sensitive variable in Octopus Deploy).

---

## 3. Setup in Octopus Deploy

To use this script, you will need to configure it as one or more "Run a Script" steps in your Octopus Deploy project.

### 3.1. Initial Notification Step

This is the first step that sends a message. It creates the initial Slack messages that subsequent steps will reply to.

* **Step Name**: `Slack Threaded Notification - Initial` (The name is important as it's used to reference output variables).
* **Script Source**: Copy and paste the Python code into the script editor.
* **Variables**:
    * `message`: The initial message to send (e.g., "🚀 Deployment of version `#{Octopus.Release.Number}` to `#{Octopus.Environment.Name}` has started.").
    * `channels`: A comma-separated list of Slack channel IDs (e.g., `C0123ABC,C4567DEF`).

### 3.2. Subsequent Notification Steps (e.g., In Progress, Completed, Failed)

These steps will reply to the initial message.

* **Step Name**:
    * `Slack Threaded Notification - In Progress`
    * `Slack Threaded Notification - Completed`
    * `Slack Threaded Notification - Failed`
* **Script Source**: Use the same Python script.
* **Variables**:
    * `message`: The update message (e.g., "✅ Deployment completed successfully.").
    * `channels`: `#{Octopus.Action[Slack Threaded Notification - Initial].Output.channels}`
    * `inThreadIds`: `#{Octopus.Action[Previous Slack Step Name].Output.threadIds}`
        * For the second step, this would be `#{Octopus.Action[Slack Threaded Notification - Initial].Output.threadIds}`.
        * For the third step, it would be `#{Octopus.Action[Slack Threaded Notification - In Progress].Output.threadIds}`.

### 3.3. Required Octopus Variables

You need to define the following project variables:

| **Variable Name** | **Description** | **Example Value** | **Sensitive** |
| :---------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------- | :------------ |
| `SLACK_API_TOKEN` | **Required.** Your Slack Bot User OAuth Token. This allows the script to authenticate with the Slack API. You get this when you create a Slack App.                        | `xoxb-1234567890-abcdefghijklmnop`   | **Yes** |
| `channels`        | A comma-separated list of public Slack channel IDs where notifications will be sent.                                                                                     | `C0123ABC,C4567DEF`                  | No            |
| `message`         | The text of the message to be sent. You can use Octopus system variables here.                                                                                           | `Deploying release #{Octopus.Release.Number}` | No            |
| `inThreadIds`     | Used by the script to pass thread timestamps between steps. You typically won't set this manually, but rather by binding it to the output of a previous step.              | (output variable)                    | No            |

---

## 4. How It Works

1.  **Initial Message**: The first time the script runs in a deployment, the `threadIds` variable is empty. The script posts a new message to each channel specified in the `channels` variable. It then saves the timestamps (`ts`) of each of these new messages into an output variable called `threadIds`.
2.  **Threaded Replies**: In subsequent steps, the script receives the `threadIds` from the previous step. It splits these IDs and sends a reply to the corresponding message in each channel, creating a clean, threaded conversation.
3.  **Final Status**: For steps named `... - Completed` or `... - Failed`, the script will add a success or failure emoji to the *original* message in the thread, providing a clear visual indicator of the final deployment status.