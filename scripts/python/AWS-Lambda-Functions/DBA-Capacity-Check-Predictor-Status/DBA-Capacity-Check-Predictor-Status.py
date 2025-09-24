import sys
import os

import json
import boto3
import time

def lambda_handler(event, context):
    forecast = boto3.client('forecast')
    
    predictorARN = event['PredictorArn']
    baseNamingConvention = event['BaseNamingConvention']
    datasetGroupARN = event['datasetgroupARN']
    
    print('Checking Predictor Status');
    
    response_predictor_status = forecast.describe_predictor(
        PredictorArn = predictorARN
        )
    
    print('Predictor Status: ' + response_predictor_status['Status'])
    return {
        'PredictorArn': predictorARN,
        'BaseNamingConvention': baseNamingConvention,
        'datasetgroupARN': datasetGroupARN,
        'predictorStatus': response_predictor_status['Status']
    }