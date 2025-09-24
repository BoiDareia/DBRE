import sys
import os

import json
import boto3
import time


def lambda_handler(event, context):
    forecast = boto3.client('forecast')
    
    ForecastExportJobArn = event['ForecastExportJobArn']
    exportPath = event['exportPath']
    forecastARN = event['forecastARN']
    
    print('Checking Export Progress For: ' + ForecastExportJobArn)
    
    response_export_check = forecast.describe_forecast_export_job(
        ForecastExportJobArn=ForecastExportJobArn
        )
    
    print('Export Status: ' + response_export_check['Status']);
    
    return {
        'ForecastExportJobArn': ForecastExportJobArn,
        'exportPath': exportPath,
        'forecastARN': forecastARN,
        'Status': response_export_check['Status']
    }
