import boto3
import logging
from datetime import datetime, timedelta, timezone
import json
import urllib3
import os
http = urllib3.PoolManager()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def send_slack_message(message):
    url = os.environ['env_slack_url']
	
    msg = {
        "channel": os.environ['env_alert_channel'],
        "username": os.environ['env_alert_username'],
        "text":message,
        "icon_emoji": ":no_entry:"
    }

	
    encoded_msg = json.dumps(msg).encode('utf-8')
    resp = http.request('POST',url, body=encoded_msg)
    print({
        "status_code":resp.status,
        "response":resp.data
    })
    #raise ValueError('An Error Notifciation Was Sent To Slack')
    return {
        'statusCode': 200,
        'body': 'Function was successful'
    }

def lambda_handler(event, context):
    
    rds_client = boto3.client('rds')
    
    sts_client = boto3.client('sts')
    
    account_id = sts_client.get_caller_identity()['Account']
    
    now = datetime.utcnow()
    
    #Threshold for warning
    threshold = timedelta(days=3*30)
    
    def check_certificate_expiration(resource, resource_type):
        cert_details = resource.get('CertificateDetails')
        if cert_details:
            cert_expiry_date = cert_details.get('ValidTill')
            days_to_expire = (cert_expiry_date - datetime.utcnow().replace(tzinfo=timezone.utc)).days
            if cert_expiry_date and (cert_expiry_date - datetime.utcnow().replace(tzinfo=timezone.utc)) < threshold:
                identifier = resource.get('DBInstanceIdentifier', resource.get('DBClusterIdentifier'))
                logging.info(f"Certificate for {resource_type} {identifier} is expiring on {cert_expiry_date.strftime('%d/%m/%Y %H:%M:%S')}, thats {days_to_expire} days before expiring, for Account {account_id}")                
                send_slack_message(f"Certificate for {resource_type} {identifier} is expiring on {cert_expiry_date.strftime('%d/%m/%Y %H:%M:%S')}, thats {days_to_expire} days before expiring, for Account {account_id}")                

    try:
        paginator = rds_client.get_paginator('describe_db_instances')
        for page in paginator.paginate():
            for db_instance in page.get('DBInstances',[]):
                check_certificate_expiration(db_instance, 'DBInstance')
    except Exception as e:
        logging.info(f"Error describind DB Instances: {e}")
        
    try:
        paginator = rds_client.get_paginator('describe_db_clusters')
        for page in paginator.paginate():
            for db_cluster in page.get('DBClusters',[]):
                check_certificate_expiration(db_cluster, 'DBCluster')
    except Exception as e:
        logging.info(f"Error describind DB clusters: {e}")        