import os
import sys

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError


def upload_file_to_slack(token, channel_id, file_path, title):
    client = WebClient(token=token)

    try:
        response = client.files_upload_v2(channel=channel_id, file=file_path, title=title)
        print(f"File uploaded successfully: {response['file']['id']}")
    except SlackApiError as e:
        print(f"Error uploading file: {e.response['error']}")
        raise e


if __name__ == "__main__":
    if "SLACK_BOT_TOKEN" not in os.environ:
        raise ValueError("SLACK_BOT_TOKEN is not set.")
    if "SLACK_CHANNEL_ID" not in os.environ:
        raise ValueError("SLACK_CHANNEL_ID is not set.")
    if len(sys.argv) < 2:
        raise ValueError("File path must be provided as the first argument.")

    SLACK_BOT_TOKEN = os.environ["SLACK_BOT_TOKEN"]
    CHANNEL_ID = os.environ["SLACK_CHANNEL_ID"]
    FILE_PATH = sys.argv[1]
    TITLE = sys.argv[2] if len(sys.argv) > 2 else None

    upload_file_to_slack(SLACK_BOT_TOKEN, CHANNEL_ID, FILE_PATH, TITLE)
