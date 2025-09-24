import json
import time
import boto3

cw_client = boto3.client('cloudwatch')

def lambda_handler(event, context):
    send_cloudwatch_data(event)
	
    return {
        'statusCode': 200,
        'body': 'ok'
    }

def send_cloudwatch_data(response):
    metric_data = []
    db_identifier = response['Identifier']
    name_space = response['NameSpace']
    data_point = response['MetricValue']
    for metric_response in response['MetricList']:
        cur_key = metric_response['Key']['Metric']

        for datapoint in metric_response['DataPoints']:
            metric_data.append({
				'MetricName': cur_key,
				'Dimensions': [
					{
						'Name':'DatabaseInstance',    
						'Value':db_identifier
					} 
				],
                'Timestamp': datapoint['PollDate'],
				'Value': datapoint[data_point]

			})

    if metric_data:
        cw_client.put_metric_data(
            Namespace= name_space, 
            MetricData= metric_data
        )