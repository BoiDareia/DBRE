import urllib3
import json
http = urllib3.PoolManager()


def notify_slack(event, context):
    url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
    jobName = event['function_name']
    input = event['info']
    slack_icon_url = 'https://dba-lambda.s3.amazonaws.com/Redshift_Icon.png'
	
    print(input)
    msg = {
        "channel":"#dba-aws-events",
        "username": jobName,
        "text":input,
        "icon_url": slack_icon_url
    }

	
    encoded_msg = json.dumps(msg).encode('utf-8')
    resp = http.request('POST',url, body=encoded_msg)
    print({
        "status_code":resp.status,
        "response":resp.data
    })

    return {
        'statusCode': 200,
        'body': 'Function was successful'
    }