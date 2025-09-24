import os
import time
import traceback
import boto3
import logging
import random
from collections import OrderedDict
from datetime import date
from datetime import timedelta
from datetime import datetime

cloudwatch = boto3. client('cloudwatch')

metric_data = []

logger = logging.getLogger()
logger.setLevel(logging.INFO)

Metric_Namespace = os.environ['Metric_Value']

def lambda_handler(event, contect):
    # input parameters passed from the caller event
    # cluster identifier for the Amazon Redshift cluster
    redshift_cluster_id = event['redshift_cluster_id']
    # database name for the Amazon Redshift cluster
    redshift_database_name = event['redshift_database']
    # database user in the Amazon Redshift cluster with access to execute relevant SQL queries
    redshift_user = event['redshift_user']
    # IAM Role of Amazon Redshift cluster
    #redshift_iam_role = event['redshift_iam_role']
    # run_type can be either asynchronous or synchronous;
    run_type = event['run_type']
    
    sql_statements = OrderedDict()
    sql_names = OrderedDict()
    res = OrderedDict()

    if run_type != "synchronous" and run_type != "asynchronous":
        raise Exception(
            "Invalid Event run_type. \n run_type has to be synchronous or asynchronous.")

    isSynchronous = True if run_type == "synchronous" else False
    
    endingTime = datetime.today() 
    startingTime = endingTime - timedelta(hours = 1)
    
    print('Starting Time');
    print(startingTime);
    print('Ending Time');
    print(endingTime);

    
    # initiate redshift-data redshift_data_api_client in boto3
    redshift_data_api_client = boto3.client('redshift-data')

    sql_statements['SPILL_EVICTED'] = "SELECT COUNT(sqs.query) FROM svl_query_summary  sqs join pg_catalog.stl_wlm_query swq on sqs.query = swq.query where is_diskbased = 't' and swq.final_state = 'Evicted' and swq.exec_start_time >= DATEADD(hour,-1,sysdate) and swq.exec_start_time <= sysdate;"
    
    logger.info("Running sql queries in {} mode!\n".format(run_type))
    
    try:
        for command, query in sql_statements.items():
            print(command);
            logging.info("Example of {} command :".format(command))
            res[command + " STATUS: "] = execute_sql_data_api(redshift_data_api_client, redshift_database_name, command, query,
                                                              redshift_user, redshift_cluster_id, isSynchronous)

    except Exception as e:
        raise Exception(str(e) + "\n" + traceback.format_exc())

    responsex = cloudwatch.put_metric_data(
    Namespace = Metric_Namespace,
    MetricData = metric_data    
    )

    return res

def execute_sql_data_api(redshift_data_api_client, redshift_database_name, command, query, redshift_user, redshift_cluster_id, isSynchronous):

    MAX_WAIT_CYCLES = 100
    attempts = 0
    # Calling Redshift Data API with executeStatement()
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, DbUser=redshift_user, Sql=query, ClusterIdentifier=redshift_cluster_id)
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info(
        "Query status: {} .... for query-->{}".format(query_status, query))
    done = False

    # Wait until query is finished or max cycles limit has been reached.
    while not done and isSynchronous and attempts < MAX_WAIT_CYCLES:
        attempts += 1
        time.sleep(1)
        desc = redshift_data_api_client.describe_statement(Id=query_id)
        query_status = desc["Status"]

        if query_status == "FAILED":
            raise Exception('SQL query failed:' +
                            query_id + ": " + desc["Error"])

        elif query_status == "FINISHED":
            
            logger.info("query status is: {} for query id: {} and command: {}".format(
                query_status, query_id, command))
            done = True
            # print result if there is a result 
            if desc['HasResultSet']:
                response = redshift_data_api_client.get_statement_result(Id=query_id)
                logger.info("Printing response of {} query --> {}".format(command, response['Records'][0][0]['longValue']))
                logger.info("Printing column type of {} query --> {}".format(command, response['ColumnMetadata'][0]['typeName']))
                timestamp = datetime.today() - timedelta(minutes = 5)

                metric_data.append({
                    'MetricName': format(command),
                    'Dimensions': [
                        {
                            'Name':'DatabaseInstance',    
                            'Value':redshift_cluster_id
                        } 
                    ],
                   
                    'Value': response['Records'][0][0]['longValue'],
                    'Timestamp': timestamp
                })
        else:
            logger.info(
                "Current working... query status is: {} ".format(query_status))

    # Timeout Precaution
    if done == False and attempts >= MAX_WAIT_CYCLES and isSynchronous:
        logger.info("Limit for MAX_WAIT_CYCLES has been reached before the query was able to finish. We have exited out of the while-loop. You may increase the limit accordingly. \n")
        raise Exception("query status is: {} for query id: {} and command: {}".format(
            query_status, query_id, command))
    
    return query_status        