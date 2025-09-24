import os

import json
import boto3
import time
from datetime import timezone
import datetime as dt
from dateutil.relativedelta import relativedelta
import io

def lambda_handler(event, context):
    redshift_status = boto3.client('redshift')
    
    #GET cluster identifier from the input event
    cluster_identifier = event['cluster_identifier']
    
    cluster_status_response = redshift_status.describe_clusters(
        ClusterIdentifier=cluster_identifier
    )
    
    for item in cluster_status_response['Clusters']:
       status = item['ClusterStatus']
       
       
    print('Status: ' + status)
    
    return {
        'cluster_identifier': cluster_identifier,
        'status': status
    }