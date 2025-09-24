import sys
import os

import json
import boto3
import time

def lambda_handler(event, context):
    forecast = boto3.client('forecast')
    
    predictorARN = event['PredictorARN']
    forecast_name = event['forecast_name']
    datasetgroupARN = event['datasetgroupARN']
    forecartARN = event['ForecastARN']
    
    print('Checking Forecast Status: ')
    
    response_forecast_status = forecast.describe_forecast(
        ForecastArn = forecartARN
        )
        
    print('Forecast Status: ' + response_forecast_status['Status'])
    
    return {
        'PredictorARN': predictorARN,
        'forecast_name': forecast_name,
        'datasetgroupARN' : datasetgroupARN,
        'ForecastARN': forecartARN,
        'Status': response_forecast_status['Status']
    }

