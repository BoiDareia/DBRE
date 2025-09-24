import requests
import os

# It's recommended to handle the Slack API token securely.
# Here, we're getting it from an environment variable for better security.
# In Octopus Deploy, you can set this as a sensitive variable.
SLACK_API_TOKEN = os.environ.get("SLACK_API_TOKEN")

def post_message_to_slack(text, channel, thread_ts=None):
    """
    Posts a message to a specified Slack channel. Can post as a new message
    or as a reply in a thread.

    Args:
        text (str): The message content to post.
        channel (str): The ID of the Slack channel to post to.
        thread_ts (str, optional): The timestamp of the parent message to reply to.
                                   If None, a new message is posted. Defaults to None.

    Returns:
        dict: The JSON response from the Slack API.
    """
    payload = {
        'token': SLACK_API_TOKEN,
        'channel': channel,
        'text': text
    }
    if thread_ts:
        payload['thread_ts'] = thread_ts

    return requests.post('https://slack.com/api/chat.postMessage', data=payload).json()

def add_reaction_to_message(emoji_name, channel, timestamp):
    """
    Adds a reaction (emoji) to a specific message in a Slack channel.

    Args:
        emoji_name (str): The name of the emoji to add (e.g., 'thumbsup').
        channel (str): The ID of the channel where the message is.
        timestamp (str): The timestamp of the message to react to.

    Returns:
        dict: The JSON response from the Slack API.
    """
    return requests.post('https://slack.com/api/reactions.add', data={
        'token': SLACK_API_TOKEN,
        'channel': channel,
        'name': emoji_name,
        'timestamp': timestamp
    }).json()

def get_octopus_variable(variable_name):
    """
    A mock function to represent getting a variable from Octopus Deploy.
    In a real Octopus script, you would use the provided mechanisms.
    Replace this with your actual `get_octopusvariable` function.
    """
    # This is a placeholder. In Octopus, this function would be provided.
    # For local testing, you can simulate it like this:
    mock_variables = {
        "message": "Deployment in progress...",
        "channels": "C12345678,C87654321",
        "inThreadIds": "",
        "Octopus.Action[Slack Threaded Notification - Initial].Output.threadIds": "",
        "Octopus.Action.StepName": "Slack Threaded Notification - In Progress"
    }
    return mock_variables.get(variable_name, "")

def set_octopus_variable(variable_name, value):
    """
    A mock function to represent setting an output variable in Octopus Deploy.
    Replace this with your actual `set_octopusvariable` function.
    """
    # This is a placeholder.
    print(f"Setting Octopus variable: '{variable_name}' = '{value}'")


def main():
    """
    Main function to orchestrate sending Slack notifications based on Octopus Deploy variables.
    """
    # --- Configuration ---
    # Emojis to use for success and failure notifications.
    SUCCESS_EMOJI = "large_green_circle"
    FAILED_EMOJI = "red_circle"

    # --- Get Octopus Variables ---
    # The main message content to be sent to Slack.
    message_text = get_octopus_variable("message")
    # A comma-separated string of Slack channel IDs.
    target_channels = get_octopus_variable("channels")
    # Thread IDs from a previous run of this script (if any).
    in_thread_ids = get_octopus_variable("inThreadIds")
    # Thread IDs from the initial notification step in the Octopus process.
    initial_thread_ids = get_octopus_variable("Octopus.Action[Slack Threaded Notification - Initial].Output.threadIds")
    # The name of the current step in the Octopus deployment process.
    current_step_name = get_octopus_variable("Octopus.Action.StepName")

    # --- Determine if Replying to a Thread ---
    # Decide which set of thread IDs to use, prioritizing `inThreadIds`.
    thread_ids_str = in_thread_ids or initial_thread_ids or ""
    if thread_ids_str:
        print("Previous message found. Replying to thread(s).")
    else:
        print("No previous message found. Creating new message(s).")

    # --- Process Each Channel ---
    channel_list = [channel.strip() for channel in target_channels.split(',') if channel.strip()]
    thread_id_list = [tid.strip() for tid in thread_ids_str.split(',') if tid.strip()]
    new_thread_ids = []

    for i, channel_id in enumerate(channel_list):
        thread_ts = thread_id_list[i] if i < len(thread_id_list) else None

        print(f"Processing channel: {channel_id}" + (f" | Replying to thread: {thread_ts}" if thread_ts else ""))

        # Post the message to the channel or thread.
        response = post_message_to_slack(message_text, channel_id, thread_ts)

        # Basic error handling for the Slack API response.
        if not response.get('ok'):
            error_message = response.get('error', 'Unknown error')
            if error_message == 'not_in_channel':
                raise Exception(f"The notification app is not in the channel '{channel_id}'. Please invite it.")
            else:
                raise Exception(f"Slack API error for channel '{channel_id}': {error_message}")

        # Store the timestamp of the new or initial message.
        if thread_ts:
            # If we replied, the original thread_ts is what we need to save for the next step.
            new_thread_ids.append(thread_ts)
        else:
            # If it was a new message, save its timestamp.
            new_thread_ids.append(response.get('ts', ''))


        # --- Add Reactions for Completed or Failed Steps ---
        if thread_ts: # Only add reactions to the parent message of a thread.
            if current_step_name == "Slack Threaded Notification - Completed":
                add_reaction_to_message(SUCCESS_EMOJI, channel_id, thread_ts)
                print(f"Added success emoji to message in channel {channel_id}")
            elif current_step_name == "Slack Threaded Notification - Failed":
                add_reaction_to_message(FAILED_EMOJI, channel_id, thread_ts)
                print(f"Added failure emoji to message in channel {channel_id}")

    # --- Set Octopus Output Variables ---
    # Save the thread IDs for subsequent steps in the deployment process.
    set_octopus_variable("threadIds", ",".join(new_thread_ids))
    # Pass the channels along as well, just in case.
    set_octopus_variable("channels", target_channels)

if __name__ == "__main__":
    # This block allows the script to be run directly for testing purposes.
    # You would need to set the SLACK_API_TOKEN environment variable.
    if not SLACK_API_TOKEN:
        print("Error: SLACK_API_TOKEN environment variable not set.")
    else:
        main()
