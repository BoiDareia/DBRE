import sys
import os

import json
import boto3
import time

def lambda_handler(event, context):
    forecast = boto3.client('forecast')
    
    forecastARN = event['ForecastARN']
    forecastExport = event['forecast_name'] + '_export'
    export_path = os.environ['FORECAST_EXPORT_BUCKET'] + forecastExport + '/'
    
    print('Creating export for forecast: ' + event['forecast_name'])
    
    response_export = forecast.create_forecast_export_job(
        ForecastExportJobName=forecastExport,
        ForecastArn=forecastARN,
        Destination={
            'S3Config': {
            'Path': export_path,
            'RoleArn': os.environ['FORECAST_ROLE']
            }
        }
        )
        
    print('Export ARN:' + response_export['ForecastExportJobArn']);
    
    return {
        'ForecastExportJobArn': response_export['ForecastExportJobArn'],
        'exportPath': export_path,
        'forecastARN': forecastARN
    }
