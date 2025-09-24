import os

import json
import boto3
import time
from datetime import timezone
import datetime as dt
from dateutil.relativedelta import relativedelta
import io

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    bucket = os.environ['FORECAST_SOURCE_BUCKET']
    #EU FILES HAVE TO BE MOVED To US BUCKET - SO SPECTRUM CAN READ THEM
    destination_bucket = os.environ['FORECAST_BUCKET'] 
    key_original_data_source =os.environ['FORECAST_SOURCE_FILE_PATH']
    
    
    
    #Needed for getting the latest file in the surce directory
    current_date = dt.datetime(1970, 1, 1)
    # Subtract 12 years from current date
    n = 12
    createdDate = current_date - relativedelta(years=n)
    createdDate = createdDate.replace(tzinfo=timezone.utc)
    
    #Getting the Source File
    response = s3.list_objects(
        Bucket=bucket,
        Prefix=key_original_data_source
        )
    
    for content in response['Contents']:
        if content['LastModified'] > createdDate:
            filename = content['Key']
            createdDate = content['LastModified']
            
    #reset created date so it can be used again
    createdDate = current_date - relativedelta(years=n)
    createdDate = createdDate.replace(tzinfo=timezone.utc)
            
    print('Capacity File To Be Copied:',filename)
    #FOLDER FOR EU DATA IN THE US BUCKET
    key_destination = os.environ['FORECAST_DEST_FILE_PATH_REPORT'] + filename[6:]
    
    print('Moving File to:',key_destination)
    
    response_copy = s3.copy_object(
        Bucket=destination_bucket,
        CopySource= bucket+'/' + filename,
        Key=key_destination
        )
    
    print('File copied on: ', response_copy['CopyObjectResult']['LastModified'])
    
    print('Getting Prediction File Details:', event['exportPath'])
    
    export_prefix = event['exportPath']
    export_prefix = export_prefix[30:]
    
    print('Export Prefix:',export_prefix)
    
    #Getting the Source File
    response_export_file = s3.list_objects(
        Bucket=bucket,
        Prefix=export_prefix
        )
        
    prediction_filename = 'placeholder'
    
    for content in response_export_file['Contents']:
        if ((content['LastModified'] > createdDate) and ('_SUCCESS' not in content['Key'])):
            print(content['Key'])
            prediction_filename = content['Key']
            createdDate = content['LastModified'] 
            
            
    print('Prediction File To Be Copied:',prediction_filename)
    #FOLDER FOR EU DATA IN THE US BUCKET
    key_destination = os.environ['FORECAST_DEST_FILE_PATH_PRED'] + prediction_filename[68:]
    
    print('Location To Copy File:',key_destination)
    
    response_copy_predition = s3.copy_object(
        Bucket=destination_bucket,
        CopySource= bucket+'/' + prediction_filename,
        Key=key_destination
        )
    print('File copied on: ', response_copy_predition['CopyObjectResult']['LastModified'])
    
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }
