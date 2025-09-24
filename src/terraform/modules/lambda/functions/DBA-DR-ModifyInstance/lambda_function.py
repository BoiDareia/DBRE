import os

import json
import boto3
import time
from datetime import timezone
import datetime as dt
from dateutil.relativedelta import relativedelta
import io

def lambda_handler(event, context):
    modify_instance = boto3.client('rds')
    
    instance_id = event['instance_identifier'] # value passed from previous step
    
    #Basic information to enable performance insights 
    response_modify_instance = modify_instance.modify_db_instance(
       DBInstanceIdentifier=instance_id,
       ApplyImmediately=True,
       BackupRetentionPeriod= 7,
       PreferredMaintenanceWindow=os.environ['AWS_PREF_MAINTENANCE_WINDOW'], # Configured in UTC time not local

       EnablePerformanceInsights=True,
       PerformanceInsightsRetentionPeriod=465
    )
    print('Enabling Monitoring For Instance:' + instance_id)
    return {
        'instance_identifier': instance_id
    }
