# A New Layer was created that enables requests module on to Python in Lambda
# How To:
# Create Python Virtual Environment
# $ python -m venv requests_venv
###
# Activate Virtual Environment
# $ source activate
###
# Check Python Version
# $ python --version
###
# Create directory with name python
# $ mkdir python
###
# Install requests package in python directory
# $ pip install requests -t python
###
# Zip python directory and Create a new lambda layer to use in your function
###
# Permissions needed for Role DBA-PerformanceInsightsCounterMetricsRole
##
# {
# "Version": "2012-10-17",
# "Statement": [
# {
# "Sid": "VisualEditor0",
# "Effect": "Allow",
# "Action": "secretsmanager:GetSecretValue",
# "Resource": "arn:aws:secretsmanager:us-east-1:set-account:secret:slack-token"
# }
# ]
# }
##
from __future__ import print_function
import json
import logging
import urllib3
# A New Layer was created that enables this module on to Python in Lambda
import requests
# Importing secret manager modules
import boto3
import base64
import os

# Secret's name and region
secret_name = "slack-token"
region_name = os.environ['AWS_REGION']

# Set up Session and Client
session = boto3.session.Session()
client = session.client(
    service_name='secretsmanager',
    region_name=region_name
)

# Calling SecretsManager
get_secret_value_response = client.get_secret_value(
    SecretId=secret_name
)
secret_token = json.loads(get_secret_value_response['SecretString'])

http = urllib3.PoolManager()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

slack_channel = '#dba-aws-events'
slack_token = secret_token['token']


print('Loading function')


def lambda_handler(event, context):
    #print("Received event: " + json.dumps(event, indent=2))
    message = json.loads(event['Records'][0]['Sns']['Message'])
    #print("From SNS: " + message)

    aws_account_id = context.invoked_function_arn.split(":")[4]
    aws_account_name = account_name(aws_account_id)

    slack_user_name = 'AWS Notification From ' + \
        aws_account_name + ' ' + region_name

    logger.info(
        "Printing message: {}".format(message))

    severity = "good"

    dangerMessages = [
        "The DB instance has failed due to an incompatible configuration or an underlying storage issue. Begin a point-in-time-restore for the DB instance.",
        "The DB instance is in an incompatible network. Some of the specified subnet IDs are invalid or do not exist.",
        "The DB instance has invalid parameters. For example, if the DB instance could not start because a memory-related parameter is set too high for this instance class, the customer action would be to modify the memory parameter and reboot the DB instance.",
        "Error while creating Statspack user account PERFSTAT. Please drop the account before adding the Statspack option.",
        "A Multi-AZ failover that resulted in the promotion of a standby instance has started.",
        "The allocated storage for the DB instance has been consumed. To resolve this issue, allocate additional storage for the DB instance.",
        "A Multi-AZ failover that resulted in the promotion of a standby instance is complete. It may take several minutes for the DNS to transfer to the new primary DB instance.",
        "The DB instance restarted.",
        "The DB instance has been deleted.",
        "DB instance shutdown.",
        "The DB instance has been stopped.",
        "RDS can't modify the DB instance class because the target instance class can't support the number of databases that exist on the source DB instance.",
        "DB instance is in a state that can't be upgraded.",
        "An error has occurred in the read replication process.",
        "Replication on the read replica was terminated.",
        "Replication on the read replica was manually stopped.",
        "Test message: Is RED"
    ]

    warningMessages = [
        "The DB instance has consumed more than 90% of its allocated storage. You can monitor the storage space for a DB instance using the Free Storage Space metric.",
        "The IAM role that you use to access your Amazon S3 bucket for SQL Server native backup and restore is configured incorrectly.",
        "Enhanced Monitoring was disabled due to an error making the configuration change.",
        "Enhanced Monitoring cannot be enabled without the enhanced monitoring IAM role.",
        "The instance has recovered from a partial failover.",
        "A Multi-AZ failover has completed.",
        "The DB instance has a DB engine minor version upgrade available.",
        "The number of tables you have for your DB instance exceeds the recommended best practices for Amazon RDS. Please reduce the number of tables on your DB instance.",
        "The number of databases you have for your DB instance exceeds the recommended best practices for Amazon RDS. Please reduce the number of databases on your DB instance.",
        "You attempted to convert a DB instance to Multi-AZ, but it contains in-memory file groups that are not supported for Multi-AZ.",
        "The read replica has resumed replication.",
        "Replication on the read replica was reset.",
        "Recovery of the DB instance has started. Recovery time will vary with the amount of data to be recovered.",
        "Recovery of the Multi-AZ instance has started.",
        "The SQL Server DB instance is re-establishing its mirror. Performance will be degraded until the mirror is reestablished.",
        "Emergent Snapshot Request: Databases found to still be awaiting snapshot.",
        "You may want to increase the provisioned storage to address this issue.",
        "The gp2 burst balance credits for the RDS database instance are low. To resolve this issue, reduce IOPS usage or modify your storage settings to enable higher performance.",
        "Reset master credentials",
        "Test message: Is YELLOW"
    ]

    ignoredMessages = [
        "Emergent Snapshot Request: Databases found to still be awaiting snapshot.",
        "Emergent Snapshot Request: Success",
        "Backing up DB instance",
        "Finished DB Instance backup",
        "Test message: ignored"
    ]

    eventSubject = event['Records'][0]['Sns']['Subject']
    eventMessage = message['Event Message']
    eventTime = message['Event Time']
    identifierLink = message['Identifier Link']
    sourceID = message['Source ID']

    if eventMessage in dangerMessages:
        severity = "danger"

    if severity == "good":
        if eventMessage in warningMessages:
            severity = "warning"
        elif eventMessage in ignoredMessages:
            severity = "ignored"

    icon = slack_icon(severity)

    if severity != "ignored":
        if severity == "danger":
            eventSubject += "   <!subteam^S0237SK1E67>"

        finalMessage = ("- Subject: " + eventSubject + "\n- "
                        "Event Time: " + eventTime + "\n- "
                        "Identifier Link: " + identifierLink + "\n- "
                        "Source ID: `" + sourceID + "`\n- "
                        "Event Message: *" + eventMessage + "*")

        post_message_to_slack(finalMessage, icon, slack_user_name, '')

        #print("From SNS after treatment: " + finalMessage)

        return finalMessage


def post_message_to_slack(text, emoji, user,  blocks=None):
    return requests.post('https://slack.com/api/chat.postMessage', {
        'token': slack_token,
        'channel': slack_channel,
        'text': text,
        'icon_emoji': emoji,
        'username': user,
        'blocks': json.dumps(blocks) if blocks else None
    }).json()


def slack_icon(severity):
    if severity == "danger":
        slack_icon = ":red_circle:"
    elif severity == "warning":
        slack_icon = ":large_yellow_circle:"
    elif severity == "ignored":
        slack_icon = ":information_desk_person:"
    else:
        slack_icon = ":large_green_circle:"

    return slack_icon


def account_name(i):
    switcher = {
        '690171673945': 'Company-analytics-prod',
        '660365688072': 'Company-analytics-stg',
        '983256399917': 'Company-apps-dev',
        '386629955161': 'Company-apps-prod',
        '854192745208': 'Company-apps-qa',
        '055566514766': 'Company-apps-stg',
        '605577347017': 'Company-business-systems',
        '112019969075': 'Company-sandbox',
        '548537837502': 'company-gen-apps-prod',
        '838441653878': 'company-gen-apps-stg'
    }
    return switcher.get(i, 'No Account Found')
