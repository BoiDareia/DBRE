import os

import json
import boto3
import time
from datetime import timezone
import datetime as dt
from dateutil.relativedelta import relativedelta
import io

def lambda_handler(event, context):
    snapshot = boto3.client('rds')
    
    #getting db-instance-id from environment variable
    instance_id = os.environ['AWS_INSTANCE_IDENTIFIER']
    
    #Getting list of available Snapshots for defined db-instance-id
    snapshot_list_response = snapshot.describe_db_snapshots(
       SnapshotType='manual',
       Filters=[
          {
             'Name':'db-instance-id',
             'Values':[instance_id]
          
          }
       ]
    )
    #Declaring this in the event no SnapShot is found
    current_instance_identifier = None
    current_snapshot_identifier = None
    
    #Needed for getting the most current snapshot -- Need to have date in correct format to do a comparision i.e. with timezone included
    current_date = dt.datetime(1970, 1, 1)
    createdDate = current_date.replace(tzinfo=timezone.utc)
    print('Finding the latest SnapShot')
    #Using loop to cycle through the list of available snapshots. Only At end of the loop the latest Snapshot name & identifier should be in the variables
    for item in snapshot_list_response['DBSnapshots']:
        if item['SnapshotCreateTime'] > createdDate:
           current_snapshot_identifier = item['DBSnapshotIdentifier']
           current_instance_identifier = item['DBInstanceIdentifier']
           current_storage_type = item['StorageType']
           current_iops = item['Iops']
           
    #SOME NPUT PARAMs NEED TO BE CONVERTED TO A DIFFERENT DATA TYPE - default is string which is not appropriate for all inputs
    converted_param_storage_throughput = int(os.environ['AWS_STORAGE_THROUGHPUT'])

    
    #If no Snapshot is found then current_snapshot_identifier will have no data in it
    #If variable contains no data we don't want a restore to be attempted    
    if current_snapshot_identifier:
         print('SnapShot Found: ' + current_snapshot_identifier);
         print('Instance Identifier: ' + current_instance_identifier);
         
         #Now that we have the snapshot we want to restore we need to attempt to restore it
         #Certain parameters don't need to be supplied to this. The config from original will be used.
         #For example: DBInstanceClass, Port, Engine etc
         
         response_restore_attempt = snapshot.restore_db_instance_from_db_snapshot(
         DBInstanceIdentifier=  current_instance_identifier,
         DBSnapshotIdentifier= current_snapshot_identifier,
         AvailabilityZone=os.environ['AWS_PREFERRED_ZONE'],
         DBSubnetGroupName=os.environ['AWS_SUBNET_GROUP'],#I think this needs to be the VPC name ...?
         MultiAZ= False, #For DR instance we don't want to create a multi az by default - can be added later
         PubliclyAccessible=False, # THIS SHOULD NEVER BE TRUE
         AutoMinorVersionUpgrade=False,
         Iops=current_iops, #MUST BE SPECIFIED BECAUSE WE ARE USING GP3 STORAGE
         OptionGroupName= os.environ['AWS_OPTION_GROUP'], #Use parameter so not hardcoded
         StorageType= current_storage_type,
         VpcSecurityGroupIds=[os.environ['AWS_SECURITY_GROUP']], #Use parameter so not hardcoded
         DBParameterGroupName=os.environ['AWS_PARAM_GROUP'], #Use parameter so not hardcoded
         StorageThroughput=converted_param_storage_throughput#, #Use parameter so not hardcoded

         )
         
         
         
    else:
        #No Snapshot found - want to ensure that this information gets returned in the output
        print('No Snapshot found. Stopping process');
        current_snapshot_identifier = 'Not Snapshot Found'
        current_instance_identifier = 'Not Snapshot Found'
     
    return {
        'snapshot_identifier': current_snapshot_identifier,
        'instance_identifier': current_instance_identifier
    }
