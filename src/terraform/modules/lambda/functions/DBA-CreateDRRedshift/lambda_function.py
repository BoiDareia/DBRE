import os

import json
import boto3
import time
from datetime import timezone,datetime, timezone,date
import datetime as dt
from dateutil.relativedelta import relativedelta
import io

def lambda_handler(event, context):
    snapshot = boto3.client('redshift')
    
    #getting db-instance-id from environment variable
    instance_id = os.environ['AWS_CLUSTER_IDENTIFIER']
    parameter_group = os.environ['REDSHIFT_PARAMETER_GROUP']
    security_group_id = os.environ['REDSHIFT_SECURITY_GROUP']
    redshift_kms = os.environ['REDSHIFT_KMS_KEY']
    
    #from the event input. default to 'automated' if not provided
    snapshot_type = event.get('input', 'automated')
    
    #Creating Date Range For List Of Snapshots To Return - Last 2 Days
    now = datetime.now()
    earlier = now - relativedelta(days=2)
    start = earlier.replace(minute=0,second=0,microsecond=0)
    
    snapshot_list_response = snapshot.describe_cluster_snapshots(
        ClusterIdentifier=instance_id,
        SnapshotType=snapshot_type,
        StartTime=start  
    )
    
    #Needed for getting the most current snapshot -- Need to have date in correct format to do a comparision i.e. with timezone included
    current_date = dt.datetime(1970, 1, 1)
    createdDate = current_date.replace(tzinfo=timezone.utc)
    print('Finding the latest SnapShot')
    
    #Declaring this in the event no SnapShot is found
    current_cluster_identifier = None
    current_snapshot_identifier = None
    
    #Using loop to cycle through the list of available snapshots. Only At end of the loop the latest Snapshot name & identifier should be in the variables
    for item in snapshot_list_response['Snapshots']:
        if item['SnapshotCreateTime'] > createdDate:
            #Updating the created date so at the end of the loop we have the details of the most recent Snapshot
            createdDate = item['SnapshotCreateTime']
            current_cluster_identifier = item['ClusterIdentifier']
            current_snapshot_identifier = item['SnapshotIdentifier']
            current_snapshot_created = item['SnapshotCreateTime']
            current_node_type = item['NodeType']
            current_node_number = int(item['NumberOfNodes'])  #Needs to be provided as an int later in the script
            
            print(f'Found Snapshot: {current_snapshot_identifier} for {current_cluster_identifier} created on {current_snapshot_created}') 
            
            
    if current_snapshot_identifier:
        #We have found a Snapshot - Now we need to restore it.
        #Step 1 - Create a New Name For The ClusterIdentifier
        new_cluster_identifier = 'DR-OR-VALIDATION-TESTING-' + current_cluster_identifier

        restore_response = snapshot.restore_from_cluster_snapshot(
            ClusterIdentifier= new_cluster_identifier,
            SnapshotIdentifier= current_snapshot_identifier,
            ClusterSubnetGroupName= 'cluster-subnet-group-1',  #This is what is currently in the Primary region in STG
            PubliclyAccessible= False,
            ClusterParameterGroupName= 'instance-name',
            VpcSecurityGroupIds=['sg-03150cxxxxx'], #This is what is currently in the Primary region in STG
            AutomatedSnapshotRetentionPeriod=7,
            KmsKeyId= '7160xxxe-75e3-41xx-96af-5ae15xxxxxxx', #This is what is currently in the Primary region in STG
            NodeType=current_node_type,
            NumberOfNodes=current_node_number
        )
        
    else:
        #No Snapshot Found 
        print('No Snapshot found. Stopping process');
        current_snapshot_identifier = 'Not Snapshot Found'
        current_cluster_identifier = 'Not Snapshot Found'
        new_cluster_identifier = 'Not Snapshot Found'
    
    return{
        'snapshot_identifier':current_snapshot_identifier,
        'cluster_identifier': new_cluster_identifier
    
    }