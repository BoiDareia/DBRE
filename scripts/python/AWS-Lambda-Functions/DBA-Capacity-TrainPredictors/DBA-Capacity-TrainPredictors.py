import sys
import os

import json
import boto3
import time

def lambda_handler(event, context):
    
    forecast = boto3.client('forecast')
    
    predictor_name = event['BaseNamingConvention'] + '_predictor'
    datasetARN = event['DataSetARN']
    datasetgroupARN = event['DatasetGroupArn']

    
    print('Creating Predictor: ' +predictor_name);
    
    response_predictor = forecast.create_predictor(
        PredictorName=predictor_name,
        ForecastHorizon=int(os.environ['FORECAST_HORIZON']),
        ForecastTypes=[os.environ['FORECAST_TYPES_1'], os.environ['FORECAST_TYPES_2'], os.environ['FORECAST_TYPES_3']],
        PerformAutoML=True,
        InputDataConfig={
            'DatasetGroupArn': datasetgroupARN
        },
        FeaturizationConfig={
        'ForecastFrequency': os.environ['FORECAST_FREQUENCY']
        },
        OptimizationMetric=os.environ['FORECAST_OPTIMIZATION_METRIC']
        )
    
    print('Predictor Started: ' +predictor_name);
    print('PredictorARN:' + response_predictor['PredictorArn']);
    
    return {
        'PredictorArn': response_predictor['PredictorArn'],
        'BaseNamingConvention': event['BaseNamingConvention'],
        'datasetgroupARN': event['DatasetGroupArn']
    }