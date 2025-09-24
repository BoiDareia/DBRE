import json
import os
# A New Layer was created that enables these modules on to Python in Lambda
import requests
import boto3
from datetime import datetime
# importing function to Notify Slack Channel
from resources import get_cortex_tag


class BearerAuth(requests.auth.AuthBase):
    def __init__(self, token):
        self.token = token

    def __call__(self, r):
        r.headers["authorization"] = "Bearer " + self.token
        return r


secret_name = "set-secret"
region = os.environ['AWS_REGION']

print("Region: ", region)

# Set up Session and Client
session = boto3.session.Session()
client = session.client(
    service_name='secretsmanager',
    region_name=region
)

# Calling SecretsManager
get_secret_value_response = client.get_secret_value(
    SecretId=secret_name
)

secret_token = get_secret_value_response['SecretString']


def lambda_handler(event, context):
    source_rds = boto3.client('rds', region_name=region)
    source_redsh = boto3.client('redshift', region_name=region)
    
    try:
        instances = source_rds.describe_db_instances()
        
        
        ### To uncomment when Cortex.io makes Redshioft Clusters available has resources ###
        
        clusters = source_redsh.describe_clusters()
        
        for cluster in clusters['Clusters']:
            
            cluster_name = cluster['ClusterIdentifier']
            
            print("ClusterIdentifier: ", cluster_name)
            
            cortex_tag = get_cortex_tag(cluster_name)
            
            print("Cortex Tag: ", cortex_tag)
            
            red_public = cluster['PubliclyAccessible']
        
            myjson3 = {
                'description': "Publicly Accessible",
                'key': "public-access",
                'value': red_public
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')
        
            red_storage_encrypt = cluster['Encrypted']
        
            myjson3 = {
                'description': "Encrypted",
                'key': "disk-encrypt",
                'value': red_storage_encrypt
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')
            
            red_pending_values = cluster['PendingModifiedValues']
            
            myjson3 = {
                'description': "Pending Modified Values",
                'key': "pending-modified-values",
                'value': red_pending_values
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

        for db_instance in instances['DBInstances']:

            db_instance_name = db_instance['DBInstanceIdentifier']

            print("DBInstanceIdentifier: ", db_instance_name)
            
            #snapshots = source.describe_db_snapshots(DBInstanceIdentifier=db_instance_name)
        
            #reservations = source.describe_reserved_db_instances(db_instance_name)

            cortex_tag = get_cortex_tag(db_instance_name)
            
            #myjson3 = {
            #    'description': "DB Snapshots",
            #    'key': "snapshots",
            #    'value': snapshots
            #}
            
            #print("DB Snapshots: ", snapshots)

            #post_to_api_cortex(cortex_tag, myjson3, secret_token, '')
            

            db_param_group_sync = db_instance['DBParameterGroups'][0]['ParameterApplyStatus']

            myjson3 = {
                'description': "Parameter Group",
                'key': "param-group-sync",
                'value': db_param_group_sync
            }

            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

            db_opt_group_sync = db_instance['OptionGroupMemberships'][0]['Status']

            myjson3 = {
                'description': "Option Group",
                'key': "opt-group-sync",
                'value': db_opt_group_sync
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

            db_pending_values = db_instance['PendingModifiedValues']

            db_multi_az = db_instance['MultiAZ']

            myjson3 = {
                'description': "MultiAZ",
                'key': "multi-az",
                'value': db_multi_az
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

            db_perf_ins = db_instance['PerformanceInsightsEnabled']
            
            myjson3 = {
                        "description": "Performance Insights",
                        "key": "perf-insights",
                        "value": db_perf_ins
                    }
              
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')
            
            if db_perf_ins:
                db_perf_ins_retention = db_instance['PerformanceInsightsRetentionPeriod']
            else:
                db_perf_ins_retention = 0
            
            myjson3 = {
                        "description": "Performance Insights Retention",
                        "key": "perf-insights-days",
                        "value": db_perf_ins_retention
                    }    
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

            db_public = db_instance['PubliclyAccessible']

            myjson3 = {
                'description': "Publicly Accessible",
                'key': "public-access",
                'value': db_public
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

            db_storage_encrypt = db_instance['StorageEncrypted']

            myjson3 = {
                'description': "Storage Encrypted",
                'key': "disk-encrypt",
                'value': db_storage_encrypt
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')
            
            db_cert_identifier = db_instance['CACertificateIdentifier']

            myjson3 = {
                'description': "RDS Certificate Identifier",
                'key': "cert-info",
                'value': db_cert_identifier
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')
            
            db_cert_details = db_instance['CertificateDetails']['ValidTill']
            
            db_cert_info = json.dumps(db_cert_details, indent=4, sort_keys=True, default=str)
            
            db_cert_valid = db_cert_details.strftime('%d/%m/%Y')

            myjson3 = {
                'description': "RDS Certificate Valid Until",
                'key': "cert-valid-until",
                'value': db_cert_valid
            }
            
            post_to_api_cortex(cortex_tag, myjson3, secret_token, '')

            #print ("TEST: ",db_perf_ins)

            result = ("Instance Identifier: ", db_instance_name, "Cortex Tag: ", cortex_tag, ",Parameter Group Sync: ", db_param_group_sync, ",Option Group Sync: ", db_opt_group_sync, ",Pending Modified Values: ",
                      db_pending_values, ",Performance Insights Enabled: ", db_perf_ins, ",Perf Insights Retention: ", db_perf_ins_retention, ",Instance Publicly Accessible: ", db_public, ",Storage Encrypted: ", db_storage_encrypt)

            #line_items.append(myjson3)

            #print(json.dumps(line_items))

            #end_game = json.dumps(line_items)
            
            print (json.dumps(db_cert_details, indent=4, sort_keys=True, default=str))
            print (db_cert_valid)
            
            print (result)

        return

    except Exception as e:
        raise e


def post_to_api_cortex(cortex_tag, myjson3, secret_token, blocks=None):
    api_call = 'https://api.getcortexapp.com/api/v1/catalog/' + \
        cortex_tag + '/custom-data'
    print("Final url is :", api_call)

    print("Cortex Tag is :", cortex_tag)
    if cortex_tag == "No Cortex Tag Found":
        response = 'NO TAG'
        return response
        
    header = {"Content-type": "application/json"}

    try:
        response = requests.post(api_call, data=json.dumps(myjson3), headers=header, auth=BearerAuth(secret_token))
    except Exception as err:
        print(err)
        response = 'error'
    return response


