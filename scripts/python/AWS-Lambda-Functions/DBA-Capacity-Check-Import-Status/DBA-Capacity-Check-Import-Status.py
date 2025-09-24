import sys
import os

import json
import boto3
import time


def lambda_handler(event, context):
    
    forecast = boto3.client('forecast')
    
    datasetARN = event['DataSetARN']
    datasetGroupARN = event['DatasetGroupArn']
    baseNamingConvention = event['BaseNamingConvention']
    importFilename = event['ImportFile']
    importARN = event['ImportARN']
    
    print('Getting Status Of Import')
    
    response_import = forecast.describe_dataset_import_job(
        DatasetImportJobArn= importARN
        )
    
    print('Import Status: '+response_import['Status'])
    return {
        'DataSetARN': datasetARN,
        'DatasetGroupArn':datasetGroupARN,
        'BaseNamingConvention': baseNamingConvention,
        'ImportFile': importFilename,
        'ImportARN':importARN,
        'Status':response_import['Status']
    }