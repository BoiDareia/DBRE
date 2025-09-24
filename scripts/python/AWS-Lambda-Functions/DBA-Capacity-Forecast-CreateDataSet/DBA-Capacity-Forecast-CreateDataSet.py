import sys
import os

import json
import boto3
import time


def lambda_handler(event, context):
    # TODO implement
    forecast = boto3.client('forecast') #For working with forcast service
    s3 = boto3.client('s3') #Forgetting the name of the file for import into the dataset
    
    timestr = time.strftime("%Y%m%d_%H%M%S") #needed for project names etc
    print(timestr);
    datagroup_name = os.environ['FORECAST_DATA_GROUP_NAME']+timestr   
    dataset_name = datagroup_name + '_dataset'  #dataset name
    dataset_import_name = dataset_name + '_import' #import name
    bucket_location = os.environ['FORECAST_SOURCE_BUCKET']  #top level location of the file
    
    print('Creating DataSet');
    response_dataset = forecast.create_dataset(
             Domain=os.environ['FORECAST_DOMAIN'],
             DatasetType=os.environ['FORECAST_TYPE'],
             DatasetName= dataset_name,
             DataFrequency=os.environ['FORECAST_FREQUENCY'], 
             Schema={
               'Attributes': [
                  {
                    'AttributeName': 'timestamp',
                    'AttributeType': 'timestamp'
                  },
                  {
                    'AttributeName': 'item_id',
                    'AttributeType': 'string'
                  },
                  {
                    'AttributeName': 'target_value',
                    'AttributeType': 'float'
                  }
               ]
             }
           )
    
    print('DataSet Created: '+dataset_name);
    print('DataSet ARN: ' + response_dataset['DatasetArn']);
    
    file_name = bucket_location + event['filename']
    
    print('Importing Data To DataSet');
    response_import = forecast.create_dataset_import_job(
    DatasetImportJobName=dataset_import_name,
    DatasetArn=response_dataset['DatasetArn'],
    DataSource={
        'S3Config': {
            'Path': file_name,
            'RoleArn': os.environ['FORECAST_ROLE']
        }
    },
    TimestampFormat='yyyy-MM-dd HH:mm:ss',
    TimeZone='Europe/Dublin',
    UseGeolocationForTimeZone=False
    )
    
    print('Importing Dataset: ' + dataset_import_name);
    print('Import ARN: '+ response_import['DatasetImportJobArn']);
    
    print('Creating DataSet Group');
    
    response_datasetgroup = forecast.create_dataset_group(
        DatasetGroupName=datagroup_name,
        Domain = 'CUSTOM',
        DatasetArns=[
        response_dataset['DatasetArn'],
    ]
    )
    
    print('DataGroup Created: '+datagroup_name);
    
    return {
        'DataSetARN': response_dataset['DatasetArn'],
        'DatasetGroupArn':response_datasetgroup['DatasetGroupArn'],
        'BaseNamingConvention': datagroup_name,
        'ImportFile': file_name,
        'ImportARN':response_import['DatasetImportJobArn']
    }