import os

import json
import boto3
import time
from datetime import timezone
import datetime as dt
from dateutil.relativedelta import relativedelta
import io

def lambda_handler(event, context):
    instance_status = boto3.client('rds')
    
    #Get instance idntifier from the input event
    instance_identifier = event['instance_identifier']
    
    instance_status_response = instance_status.describe_db_instances(
        DBInstanceIdentifier = instance_identifier
        )
        
    status_list = instance_status_response['DBInstances']
    
    for item in status_list:
       status = item['DBInstanceStatus']
    
    print('Status: ' + status)
    
    return {
        'instance_identifier': instance_identifier,
        'status': status
    }
