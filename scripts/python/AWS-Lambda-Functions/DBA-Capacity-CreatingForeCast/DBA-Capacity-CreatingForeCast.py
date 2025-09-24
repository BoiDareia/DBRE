import sys
import os

import json
import boto3
import time

def lambda_handler(event, context):
    # TODO implement
    forecast = boto3.client('forecast')
    
    PredictorArn = event['PredictorArn']
    forecast_name = event['BaseNamingConvention'] + '_forecast'
    datasetgroupARN = event['datasetgroupARN']
    
    print('Creating Forecast: ' + forecast_name);
    
    response_forecast = forecast.create_forecast(
    ForecastName=forecast_name,
    PredictorArn=PredictorArn,
    ForecastTypes=[
        os.environ['FORECAST_TYPES_1'], os.environ['FORECAST_TYPES_2'], os.environ['FORECAST_TYPES_3'],
    ]
    )

    print('Started Forecast: ' + forecast_name);
    print('ForecastARN: ' + response_forecast['ForecastArn']);

    return {
        'PredictorARN': PredictorArn,
        'forecast_name': forecast_name,
        'datasetgroupARN' : datasetgroupARN,
        'ForecastARN': response_forecast['ForecastArn']
    }