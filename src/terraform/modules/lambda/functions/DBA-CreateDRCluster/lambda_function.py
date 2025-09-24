import os
import json
import boto3
import time
import logging
from datetime import timezone
import datetime as dt

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_original_cluster_config(cluster_id, source_region):
    """
    Retrieve the configuration of the original cluster from the source region.
    """
    try:
        source_rds = boto3.client('rds', region_name=source_region)
        cluster_response = source_rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        
        if not cluster_response['DBClusters']:
            logger.warning(f"Cluster {cluster_id} not found in region {source_region}")
            return None
            
        cluster_info = cluster_response['DBClusters'][0]
        instance_ids = [member['DBInstanceIdentifier'] for member in cluster_info.get('DBClusterMembers', [])]
        
        if not instance_ids:
            logger.info("No instances found in the original cluster.")
            return {'cluster': cluster_info, 'instances': []}
        
        instances_response = source_rds.describe_db_instances(
            Filters=[{'Name': 'db-instance-id', 'Values': instance_ids}]
        )
        
        instance_map = {inst['DBInstanceIdentifier']: inst for inst in instances_response['DBInstances']}
        
        instances_info = []
        for member in cluster_info.get('DBClusterMembers', []):
            instance = instance_map.get(member['DBInstanceIdentifier'])
            if instance:
                db_parameter_group_name = None
                if instance.get('DBParameterGroups'):
                    db_parameter_group_name = instance['DBParameterGroups'][0].get('DBParameterGroupName')
                
                instances_info.append({
                    'DBInstanceClass': instance['DBInstanceClass'],
                    'Engine': instance['Engine'],
                    'IsClusterWriter': member['IsClusterWriter'],
                    'PromotionTier': member.get('PromotionTier', 1),
                    'DBParameterGroupName': db_parameter_group_name,
                    'PubliclyAccessible': instance.get('PubliclyAccessible', False)
                })
        
        return {
            'cluster': cluster_info,
            'instances': instances_info
        }
        
    except Exception as e:
        logger.error(f"Error retrieving original cluster config: {str(e)}")
        return None

def lambda_handler(event, context):
    rds_client = boto3.client('rds')
    
    #Get Configuration from Environment Variables 
    cluster_id = os.environ['AWS_CLUSTER_IDENTIFIER']
    source_region = os.environ.get('SOURCE_REGION')
    engine_mode = os.environ.get('AWS_ENGINE_MODE', 'provisioned')
    cluster_prefix = os.environ.get('AWS_CLUSTER_PREFIX', 'dr-or-validation-testing')

    #Find the Latest Snapshot 
    logger.info(f"Starting restore for cluster '{cluster_id}' in '{engine_mode}' mode.")
    try:
        snapshot_list_response = rds_client.describe_db_cluster_snapshots(Filters=[{'Name': 'db-cluster-id', 'Values': [cluster_id]}])
    except Exception as e:
        logger.error(f"Failed to list snapshots: {str(e)}")
        return {'status': 'FAILED', 'error': f'Failed to list snapshots: {str(e)}'}
    
    latest_snapshot = None
    latest_snapshot_time = dt.datetime(1970, 1, 1, tzinfo=timezone.utc)
    for item in snapshot_list_response['DBClusterSnapshots']:
        if item['SnapshotCreateTime'] > latest_snapshot_time:
            latest_snapshot_time = item['SnapshotCreateTime']
            latest_snapshot = item

    if not latest_snapshot:
        logger.error('FATAL: No snapshot found for the specified cluster identifier.')
        return {'status': 'FAILED', 'error': 'No snapshot found', 'cluster_identifier': cluster_id}

    current_snapshot_identifier = latest_snapshot['DBClusterSnapshotIdentifier']
    original_cluster_identifier = latest_snapshot['DBClusterIdentifier']
    engine = latest_snapshot['Engine']
    new_cluster_identifier = f"{cluster_prefix}-{original_cluster_identifier}"
    
    logger.info(f'Latest SnapShot Found: {current_snapshot_identifier}')
    
    #Discover Original Cluster Configuration
    original_config = None
    if source_region:
        logger.info(f'Attempting to discover original config from region: {source_region}')
        original_config = get_original_cluster_config(original_cluster_identifier, source_region)
        if original_config:
            logger.info(f"Successfully discovered original cluster configuration.")

    #Step 1: Restore the DB Cluster
    try:
        logger.info(f'Initiating restore for new cluster: {new_cluster_identifier}')
        
        restore_params = {
            'DBClusterIdentifier': new_cluster_identifier,
            'SnapshotIdentifier': current_snapshot_identifier,
            'Engine': engine,
            'DBSubnetGroupName': os.environ['AWS_SUBNET_GROUP'],
            'VpcSecurityGroupIds': [os.environ['AWS_SECURITY_GROUP']],
            'DBClusterParameterGroupName': os.environ['AWS_PARAM_GROUP'],
            'PubliclyAccessible': False
        }

        if engine_mode == 'serverless':
            scaling_config = original_config.get('cluster', {}).get('ServerlessV2ScalingConfiguration') if original_config else None
            if scaling_config:
                logger.info(f"Discovered Serverless V2 ACU settings: Min={scaling_config['MinCapacity']}, Max={scaling_config['MaxCapacity']}")
                restore_params['ServerlessV2ScalingConfiguration'] = {
                    'MinCapacity': scaling_config['MinCapacity'],
                    'MaxCapacity': scaling_config['MaxCapacity']
                }
            else:
                min_acu = float(os.environ['AWS_SERVERLESS_MIN_ACU'])
                max_acu = float(os.environ['AWS_SERVERLESS_MAX_ACU'])
                logger.warning(f"Could not discover ACU settings. Using fallback: Min={min_acu}, Max={max_acu}")
                restore_params['ServerlessV2ScalingConfiguration'] = {'MinCapacity': min_acu, 'MaxCapacity': max_acu}
        
        rds_client.restore_db_cluster_from_snapshot(**restore_params)
        logger.info(f'Cluster restore initiated successfully.')
    
    except Exception as e:
        logger.error(f'FATAL: Failed to initiate cluster restore: {str(e)}')
        return {'status': 'FAILED', 'error': str(e), 'snapshot_identifier': current_snapshot_identifier}

    #Step 2: Wait for the Cluster to Become Available
    try:
        logger.info(f'Waiting for cluster "{new_cluster_identifier}" to become available...')
        waiter = rds_client.get_waiter('db_cluster_available')
        max_attempts = int(os.environ.get('AWS_WAITER_MAX_ATTEMPTS', '30'))
        delay = int(os.environ.get('AWS_WAITER_DELAY', '30'))
        waiter.wait(DBClusterIdentifier=new_cluster_identifier, WaiterConfig={'Delay': delay, 'MaxAttempts': max_attempts})
        logger.info(f'SUCCESS: Cluster "{new_cluster_identifier}" is available.')
    except Exception as e:
        logger.error(f"FATAL: Error waiting for cluster to become available: {str(e)}")
        return {'status': 'FAILED', 'error': f'Cluster creation timeout or failure: {str(e)}'}

    #Step 2.5: Modify Cluster Attributes
    try:
        modify_params = {'DBClusterIdentifier': new_cluster_identifier}
        if os.environ.get('AWS_BACKUP_RETENTION_PERIOD'):
            modify_params['BackupRetentionPeriod'] = int(os.environ['AWS_BACKUP_RETENTION_PERIOD'])
        if os.environ.get('AWS_PREFERRED_BACKUP_WINDOW'):
            modify_params['PreferredBackupWindow'] = os.environ['AWS_PREFERRED_BACKUP_WINDOW']
        if os.environ.get('AWS_PREFERRED_MAINTENANCE_WINDOW'):
            modify_params['PreferredMaintenanceWindow'] = os.environ['AWS_PREFERRED_MAINTENANCE_WINDOW']
        
        #Only call modify if there are parameters to change
        if len(modify_params) > 1:
            logger.info(f"Applying lifecycle modifications to cluster: {modify_params.keys()}")
            rds_client.modify_db_cluster(**modify_params)
            logger.info("Lifecycle modifications applied successfully.")

    except Exception as e:
        logger.warning(f"Could not apply lifecycle modifications to cluster: {str(e)}")

    #Step 3: Create DB Instances in the New Cluster
    created_instances = []
    failed_instances = []
    
    if original_config and 'instances' in original_config:
        instance_count = len(original_config['instances'])
        logger.info(f"Discovered instance count from original cluster: {instance_count}")
    else:
        instance_count = int(os.environ.get('AWS_INSTANCE_COUNT', '1'))
        logger.info(f"Using instance count from environment variable: {instance_count}")

    if instance_count > 0:
        for i in range(instance_count):
            instance_id = f"{new_cluster_identifier}-instance-{i+1}"
            
            if engine_mode == 'serverless':
                final_instance_class = 'db.serverless'
                promotion_tier = 0 if i == 0 else i
            elif original_config and i < len(original_config['instances']):
                instance_details = original_config['instances'][i]
                final_instance_class = instance_details['DBInstanceClass']
                promotion_tier = instance_details['PromotionTier']
            else:
                final_instance_class = os.environ.get('AWS_INSTANCE_CLASS', 'db.r5.large')
                promotion_tier = 0 if i == 0 else i
            
            try:
                logger.info(f"Creating instance {i+1}/{instance_count}: {instance_id}")
                create_params = {
                    'DBInstanceIdentifier': instance_id,
                    'DBInstanceClass': final_instance_class,
                    'Engine': engine,
                    'DBClusterIdentifier': new_cluster_identifier,
                    'PromotionTier': promotion_tier
                }
                rds_client.create_db_instance(**create_params)
                created_instances.append(instance_id)
                logger.info(f'✅ Instance {instance_id} creation initiated successfully')
            except Exception as e:
                logger.error(f'❌ Error creating instance {instance_id}: {str(e)}')
                failed_instances.append({'instance': instance_id, 'error': str(e)})

    #Final Summary
    logger.info(f'🎯 Process complete.')
    return {
        'status': 'SUCCESS' if not failed_instances else 'PARTIAL_SUCCESS',
        'new_cluster_identifier': new_cluster_identifier,
        'instances_created': created_instances,
        'instances_failed': failed_instances
    }