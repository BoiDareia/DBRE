from http import client
import time
import traceback
from urllib import response
import boto3
import logging
import random
from collections import OrderedDict
import urllib3
import json
# importing function to Notify Slack Channel
from slack import notify_slack as notify

http = urllib3.PoolManager()

metric_data = []

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def redshift_ownership(event, context):
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
    # check if it's being ran from any kind of automatic event trigger like EventBridge, p.e.. It can be either MANUAL or AUTO;
    trigger = event['trigger']
    cw_dimensions = event['dimensions']
    cw_namespace = event['namespace']

    sqlFile = open('file.sql', 'r')
    queries = sqlFile.readlines()

    sql_statements = OrderedDict()
    sql_names = OrderedDict()
    res = OrderedDict()
    

    if run_type != "synchronous" and run_type != "asynchronous":
        raise Exception(
            "Invalid Event run_type. \n run_type has to be synchronous or asynchronous.")

    isSynchronous = True if run_type == "synchronous" else False

    # initiate redshift-data redshift_data_api_client in boto3
    redshift_data_api_client = boto3.client('redshift-data')
    

    i = 0
    while i < len(queries):

        query_string  = queries[i]

        query_name = query_string.split(' ')[0].upper()
                
        sql_statements[query_name] = query_string


        logger.info("Running sql queries in {} mode!\n".format(run_type))

        try:
            for command, query in sql_statements.items():
                
                logging.info("Example of {} command :".format(command))

                res[command + " STATUS: "] = execute_sql_data_api(redshift_data_api_client, redshift_database_name, command, query,
                                                                redshift_user, redshift_cluster_id, isSynchronous, cw_dimensions)
                

        except Exception as e:
            raise Exception(str(e) + "\n" + traceback.format_exc())

        i += 1
        

    inputParams = {
        "function_name" : redshift_ownership.__name__.upper(),
        "info" : json.dumps(res, indent=4)
    }

    if trigger == "MANUAL":
        notify(inputParams,'')
    else:
        logger.info("Successufully terminated and automatic run of the Lambda without sending slack notifications. \n")

    
    return res


def execute_sql_data_api(redshift_data_api_client, redshift_database_name, command, query, redshift_user, redshift_cluster_id, isSynchronous, cw_dimensions):

    MAX_WAIT_CYCLES = 300
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
                response = redshift_data_api_client.get_statement_result(
                    Id=query_id)
                logger.info(
                    "Printing response of {} query --> {}".format(command, response['Records']))
                
        else:
            logger.info(
                "Current working... query status is: {} ".format(query_status))
                

    # Timeout Precaution
    if done == False and attempts >= MAX_WAIT_CYCLES and isSynchronous:
        logger.info("Limit for MAX_WAIT_CYCLES has been reached before the query was able to finish. We have exited out of the while-loop. You may increase the limit accordingly. \n")
        raise Exception("query status is: {} for query id: {} and command: {}".format(
            query_status, query_id, command))
    
    return query_status
    