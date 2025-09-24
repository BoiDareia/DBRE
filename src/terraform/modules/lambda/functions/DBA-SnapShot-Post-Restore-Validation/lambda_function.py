import json
import os
import boto3
import pymssql
import io
import pymysql
import psycopg
from datetime import datetime,timezone
from dateutil.relativedelta import relativedelta

os.environ["PGCLIENTENCODING"] = "utf-8" # to support connection to Redshift

rds_client = boto3.client('rds') # Needed to get the RDS list
redshift_client = boto3.client('redshift') #Needed to get the Redshift list
sm = boto3.client('secretsmanager') #Needed to work with the secret
s3 = boto3.client('s3') #Needed to create the source files


def lambda_handler(event, context):
    
    region = os.environ['AWS_SOURCE_REGION']
    aws_bucket = os.environ['AWS_BUCKET']
    directory = 'SnapshotRestoreTesting'
    
    #The event needs to supply the instance identifier, the hostname and the secret name
    identifier = event['Identifier']
    host = event['hostname']
    secret = event['secret']
    query = 'SELECT 1'
    healthStatus = 5 # default is 5 - this reflects if this is an unsupported check for the engine type
    db_infra_type = 'instance'

    #STEP 1 - Describe the instance and confirm status is available
    try:
        pi_instances = rds_client.describe_db_instances(DBInstanceIdentifier=identifier)
        dbs = pi_instances['DBInstances']
    except:
        try:
            print(f'{identifier} is a Redshift cluster!')
            pi_clusters = redshift_client.describe_clusters(ClusterIdentifier=identifier)
            dbs = pi_clusters['Clusters']
            db_infra_type = 'redshift_cluster'
        except:
            print(f'{identifier} is a cluster!')
            pi_clusters = rds_client.describe_db_clusters(DBClusterIdentifier=identifier)
            dbs = pi_clusters['DBClusters']
            db_infra_type = 'cluster'
            
            
    generateReport(identifier,db_infra_type,secret,host,dbs,query,aws_bucket,directory,'')
    
    return {
        'statusCode': 200,
        'Instance': identifier,
        'Bucket':aws_bucket
    }
    
def createSQLServerConnectionString(secret,host):
    
    # Calling SecretsManager
    get_secret_value_response = sm.get_secret_value(
        SecretId=secret
    )
    
    secret = get_secret_value_response['SecretString']
    j = json.loads(secret)
    username = j['username']
    password = j['password']
    
    connectionString = f'host={host},user={username},password={password},database=companyMonitor,port=1433'
    return connectionString

def createPostgresConnectionString(secret,host):
    
    # Calling SecretsManager
    get_secret_value_response = sm.get_secret_value(
        SecretId=secret
    )
    
    secret = get_secret_value_response['SecretString']
    j = json.loads(secret)
    username = j['username']
    password = j['password']
    
    connectionString = f'host={host} user={username} password={password} dbname=postgres port=5432'
    return connectionString

def createRedshiftConnectionString(secret,host):
    
    # Calling SecretsManager
    get_secret_value_response = sm.get_secret_value(
        SecretId=secret
    )
    
    secret = get_secret_value_response['SecretString']
    j = json.loads(secret)
    username = j['username']
    password = j['password']
    
    connectionString = f'host={host} user={username} password={password} port=5439'
    return connectionString
    
def createMySQLConnectionString(secret,host):
    
    # Calling SecretsManager
    get_secret_value_response = sm.get_secret_value(
        SecretId=secret
    )
    
    secret = get_secret_value_response['SecretString']
    j = json.loads(secret)
    username = j['username']
    password = j['password']
    
    connectionString = f'host={host},user={username},passwd={password},db=postgres,port=5432'
    return connectionString
    
def generateReport(identifier,db_infra_type,secret,host,dbs,query,aws_bucket,directory,cluster_name):

    #Get Date
    now = datetime.now()
    start = now.replace(minute=0,second=0,microsecond=0)

    if db_infra_type != 'cluster':

        if db_infra_type == 'instance':
            for instance in dbs:
                engine = instance['Engine']
                InstanceStatus = instance['DBInstanceStatus']
                PerfEnabled = instance['PerformanceInsightsEnabled']
                
                for paramG in instance['DBParameterGroups']:
                    paramStatus = paramG['ParameterApplyStatus']
                
                for optG in instance['OptionGroupMemberships']:
                    optGStatus = optG['Status']

        else:
            for cluster in dbs:
                engine='redshift'
                ClusterStatus = cluster['ClusterStatus']
                PerfEnabled = 'N/A'
                optGStatus = 'N/A'

                for paramG in cluster['ClusterParameterGroups']:
                    paramStatus = paramG['ParameterApplyStatus']
        
        try:
            if 'sqlserver' in engine:
                print('Creating Connection string for SQL Server')
                targetConnection = createSQLServerConnectionString(secret,host)

                # Parse the connection string into a dictionary
                conn_params = {k: v for k, v in (item.split('=', 1) for item in targetConnection.split(','))}

                print(f'Connecting To Instance: {host}')
                connection = pymssql.connect(host=conn_params['host'],user=conn_params['user'],password=conn_params['password'],database=conn_params['database'],port=conn_params['port'])
                
                cursor = connection.cursor()
                cursor.execute(query)
                for row in cursor.fetchall():
                    healthStatus = row[0]
                connection.close()
                print(healthStatus)
            #Step 2.2 - else if it's postgres connect and check
            elif 'postgres' in engine:
                print('Creating Connection string for Postgres')
                targetConnection = createPostgresConnectionString(secret,host)
                print(f'Connecting To Instance: {host}')
                connection = psycopg.connect(targetConnection)
                cursor = connection.cursor()
                cursor.execute(query)
                for row in cursor.fetchall():
                    healthStatus = row[0]
                connection.close()
                print(healthStatus)
            
            elif 'redshift' in engine:
                print('Creating Connection string for Redshift')
                targetConnection = createRedshiftConnectionString(secret,host)
                print(f'Connecting To Instance: {host}')
                connection = psycopg.connect(targetConnection)
                cursor = connection.cursor()
                cursor.execute(query)
                for row in cursor.fetchall():
                    healthStatus = row[0]
                connection.close()
                print(healthStatus)
                
            #Step 2.3 - else if it's MySQL connect and check
            elif 'mysql' in engine:
                print('Creating Connection string for MySQL')
                targetConnection = createMySQLConnectionString(secret,host)
                print(f'Connecting To Instance: {host}')
                connection = pymysql.connect(targetConnection)
                cursor = connection.cursor()
                cursor.execute(query)
                for row in cursor.fetchall():
                    healthStatus = row[0]
                connection.close()
                print(healthStatus)
            else:
                print('Unknown Engine Type.')
          
        #Now that we have some basic validations done we can create a report file confirming when we did this
        
            if healthStatus == 5:
                healthMessage = 'Check Not Supported Currently'
            elif healthStatus == 1:
                healthMessage = 'HEALTHY'
            else:
                healthMessage = 'UNHEALTHY'
        
        except:
            print('Failed to connect, health check N/A')
            healthMessage = 'N/A'

        output = io.StringIO()
        #Creating File HEADER
        line = "Server,Type,Parent_Cluster,Restore_Status,Parameter_Group_Status,Option_Group_Status,PerformanceInsightsEnabled,HealthCheck_Status,Date\n"
        output.write(line)

        if len(cluster_name) == 0:
            cluster_name = 'N/A'

        if db_infra_type == 'instance':
            line = identifier+","+db_infra_type+","+cluster_name+","+InstanceStatus+","+paramStatus+","+optGStatus+","+str(PerfEnabled)+","+healthMessage+","+start.strftime("%Y-%m-%d-%H-%M-%s")+"\n"
        else:
            line = identifier+","+db_infra_type+","+cluster_name+","+ClusterStatus+","+paramStatus+","+optGStatus+","+str(PerfEnabled)+","+healthMessage+","+start.strftime("%Y-%m-%d-%H-%M-%s")+"\n"
        
        output.write(line)
        
        contents = output.getvalue()
        output.close()
        
        filename = identifier+"_RestoreTest_"+start.strftime("%Y-%m-%d-%H-%M-%s")+".csv"
        filepath = directory+"/"+filename
        
        response = s3.put_object(Body=contents, Bucket=aws_bucket, Key=filepath)
    
    else:
        
        for cluster in dbs:
            for nodes in cluster['DBClusterMembers']:
                node = nodes['DBInstanceIdentifier']
                node_instances = rds_client.describe_db_instances(DBInstanceIdentifier=node)
                dbs = node_instances['DBInstances']
                generateReport(node,'instance',secret,host,dbs,query,aws_bucket,directory,identifier)