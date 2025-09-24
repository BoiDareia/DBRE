import os
import json
import time
import boto3

pi_client = boto3.client('pi')
rds_client = boto3.client('rds')
cw_client = boto3.client('cloudwatch')

DB_Instance = os.environ['Instance_Value']

def lambda_handler(event, context):
    # TODO implement -- NEED TO CHANGE DB INSTANCE NAME BETWEEN EU AND US
    response = rds_client.describe_db_instances(DBInstanceIdentifier=DB_Instance)["DBInstances"]

    print(response)
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }