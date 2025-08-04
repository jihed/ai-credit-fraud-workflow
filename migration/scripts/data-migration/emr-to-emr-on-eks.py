#!/usr/bin/env python3
"""
EMR to EMR on EKS Data Migration Script

This script migrates data processing jobs from traditional EMR to EMR on EKS
using the existing RAPIDS configuration and patterns.
"""

import json
import boto3
import yaml
import argparse
import logging
from datetime import datetime
from typing import Dict, List, Optional
import subprocess
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class EMRToEKSMigrator:
    """Handles migration from EMR to EMR on EKS"""
    
    def __init__(self, cluster_name: str, virtual_cluster_id: str, region: str = 'us-west-2'):
        self.cluster_name = cluster_name
        self.virtual_cluster_id = virtual_cluster_id
        self.region = region
        self.emr_client = boto3.client('emr', region_name=region)
        self.emr_containers_client = boto3.client('emr-containers', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        
    def get_emr_cluster_config(self, cluster_id: str) -> Dict:
        """Extract configuration from existing EMR cluster"""
        try:
            response = self.emr_client.describe_cluster(ClusterId=cluster_id)
            cluster = response['Cluster']
            
            config = {
                'name': cluster['Name'],
                'release_label': cluster['ReleaseLabel'],
                'applications': [app['Name'] for app in cluster['Applications']],
                'instance_groups': [],
                'configurations': cluster.get('Configurations', []),
                'bootstrap_actions': cluster.get('BootstrapActions', []),
                'tags': cluster.get('Tags', [])
            }
            
            # Extract instance group configurations
            instance_groups = self.emr_client.list_instance_groups(ClusterId=cluster_id)
            for ig in instance_groups['InstanceGroups']:
                config['instance_groups'].append({
                    'name': ig['Name'],
                    'instance_role': ig['InstanceGroupType'],
                    'instance_type': ig['InstanceType'],
                    'instance_count': ig['RequestedInstanceCount'],
                    'market': ig['Market'],
                    'configurations': ig.get('Configurations', [])
                })
            
            return config
            
        except Exception as e:
            logger.error(f"Failed to get EMR cluster config: {e}")
            raise
    
    def convert_to_emr_on_eks_config(self, emr_config: Dict) -> Dict:
        """Convert EMR configuration to EMR on EKS job configuration"""
        
        # Map EMR instance types to EKS node selectors
        instance_type_mapping = {
            'm5.xlarge': 'cpu-nodes',
            'm5.2xlarge': 'cpu-nodes', 
            'g4dn.xlarge': 'gpu-nodes',
            'g4dn.2xlarge': 'gpu-nodes',
            'g5.xlarge': 'gpu-nodes',
            'g5.2xlarge': 'gpu-nodes'
        }
        
        # Extract executor configuration from instance groups
        executor_config = {}
        for ig in emr_config['instance_groups']:
            if ig['instance_role'] == 'CORE':
                executor_config = {
                    'instance_type': ig['instance_type'],
                    'instance_count': ig['instance_count'],
                    'node_selector': instance_type_mapping.get(ig['instance_type'], 'cpu-nodes')
                }
                break
        
        # Build EMR on EKS job configuration
        eks_config = {
            'name': f"{emr_config['name']}-eks-migration",
            'virtualClusterId': self.virtual_cluster_id,
            'executionRoleArn': f"arn:aws:iam::{boto3.client('sts').get_caller_identity()['Account']}:role/EMRContainers-JobExecutionRole",
            'releaseLabel': emr_config['release_label'],
            'jobDriver': {
                'sparkSubmitJobDriver': {
                    'entryPoint': 's3://your-bucket/scripts/fraud-detection-feature-engineering.py',
                    'sparkSubmitParameters': self._build_spark_parameters(emr_config, executor_config)
                }
            },
            'configurationOverrides': {
                'applicationConfiguration': self._convert_configurations(emr_config['configurations']),
                'monitoringConfiguration': {
                    'persistentAppUI': 'ENABLED',
                    'cloudWatchMonitoringConfiguration': {
                        'logGroupName': f'/aws/emr-containers/{self.cluster_name}',
                        'logStreamNamePrefix': 'fraud-detection'
                    },
                    's3MonitoringConfiguration': {
                        'logUri': f's3://your-bucket/logs/emr-containers/{self.cluster_name}/'
                    }
                }
            }
        }
        
        return eks_config
    
    def _build_spark_parameters(self, emr_config: Dict, executor_config: Dict) -> str:
        """Build Spark submit parameters for EMR on EKS"""
        
        # Base RAPIDS configuration
        params = [
            '--conf spark.plugins=com.nvidia.spark.SQLPlugin',
            '--conf spark.rapids.sql.enabled=true',
            '--conf spark.executor.resource.gpu.amount=1',
            '--conf spark.task.resource.gpu.amount=0.25',
            '--conf spark.rapids.memory.pinnedPool.size=2G',
            '--conf spark.sql.adaptive.enabled=true',
            '--conf spark.sql.adaptive.coalescePartitions.enabled=true'
        ]
        
        # Executor configuration based on instance type
        if 'g5' in executor_config.get('instance_type', ''):
            params.extend([
                f'--conf spark.executor.instances={executor_config["instance_count"]}',
                '--conf spark.executor.memory=30G',
                '--conf spark.executor.cores=4',
                '--conf spark.executor.memoryFraction=0.8',
                '--conf spark.sql.shuffle.partitions=400'
            ])
        else:
            params.extend([
                f'--conf spark.executor.instances={executor_config["instance_count"]}',
                '--conf spark.executor.memory=14G', 
                '--conf spark.executor.cores=4',
                '--conf spark.sql.shuffle.partitions=200'
            ])
        
        # Driver configuration
        params.extend([
            '--conf spark.driver.memory=8G',
            '--conf spark.driver.cores=2',
            '--conf spark.kubernetes.container.image=your-account.dkr.ecr.us-west-2.amazonaws.com/spark-rapids:latest'
        ])
        
        return ' '.join(params)
    
    def _convert_configurations(self, emr_configurations: List[Dict]) -> List[Dict]:
        """Convert EMR configurations to EMR on EKS format"""
        
        eks_configurations = []
        
        for config in emr_configurations:
            if config['Classification'] == 'spark-defaults':
                # Convert spark-defaults to EMR on EKS format
                spark_config = {
                    'classification': 'spark-defaults',
                    'properties': config.get('Properties', {})
                }
                
                # Add RAPIDS-specific configurations
                spark_config['properties'].update({
                    'spark.plugins': 'com.nvidia.spark.SQLPlugin',
                    'spark.rapids.sql.enabled': 'true',
                    'spark.executor.resource.gpu.amount': '1',
                    'spark.task.resource.gpu.amount': '0.25'
                })
                
                eks_configurations.append(spark_config)
            
            elif config['Classification'] == 'spark':
                # Convert general spark configuration
                eks_configurations.append({
                    'classification': 'spark-defaults',
                    'properties': config.get('Properties', {})
                })
        
        return eks_configurations
    
    def migrate_job_scripts(self, source_s3_path: str, target_s3_path: str) -> bool:
        """Migrate job scripts from EMR to EMR on EKS compatible format"""
        
        try:
            # List all Python scripts in source path
            bucket, prefix = source_s3_path.replace('s3://', '').split('/', 1)
            
            response = self.s3_client.list_objects_v2(
                Bucket=bucket,
                Prefix=prefix
            )
            
            for obj in response.get('Contents', []):
                if obj['Key'].endswith('.py'):
                    # Download script
                    local_file = f"/tmp/{os.path.basename(obj['Key'])}"
                    self.s3_client.download_file(bucket, obj['Key'], local_file)
                    
                    # Modify script for EMR on EKS compatibility
                    self._modify_script_for_eks(local_file)
                    
                    # Upload modified script
                    target_bucket, target_prefix = target_s3_path.replace('s3://', '').split('/', 1)
                    target_key = f"{target_prefix}/{os.path.basename(obj['Key'])}"
                    
                    self.s3_client.upload_file(local_file, target_bucket, target_key)
                    logger.info(f"Migrated script: {obj['Key']} -> {target_key}")
                    
                    # Clean up
                    os.remove(local_file)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to migrate job scripts: {e}")
            return False
    
    def _modify_script_for_eks(self, script_path: str):
        """Modify Python script for EMR on EKS compatibility"""
        
        with open(script_path, 'r') as f:
            content = f.read()
        
        # Add EMR on EKS specific imports and configurations
        modifications = [
            "# EMR on EKS compatibility modifications",
            "import os",
            "from pyspark.sql import SparkSession",
            "",
            "# Initialize Spark session with RAPIDS configuration",
            "spark = SparkSession.builder \\",
            "    .appName('FraudDetectionEKS') \\",
            "    .config('spark.plugins', 'com.nvidia.spark.SQLPlugin') \\",
            "    .config('spark.rapids.sql.enabled', 'true') \\",
            "    .getOrCreate()",
            ""
        ]
        
        # Insert modifications at the beginning
        modified_content = '\n'.join(modifications) + '\n' + content
        
        with open(script_path, 'w') as f:
            f.write(modified_content)
    
    def create_migration_manifest(self, emr_cluster_id: str, output_file: str):
        """Create migration manifest with all configurations"""
        
        try:
            emr_config = self.get_emr_cluster_config(emr_cluster_id)
            eks_config = self.convert_to_emr_on_eks_config(emr_config)
            
            manifest = {
                'migration_info': {
                    'timestamp': datetime.now().isoformat(),
                    'source_cluster_id': emr_cluster_id,
                    'target_virtual_cluster_id': self.virtual_cluster_id,
                    'migrated_by': os.getenv('USER', 'unknown')
                },
                'source_emr_config': emr_config,
                'target_eks_config': eks_config,
                'migration_steps': [
                    'Extract EMR cluster configuration',
                    'Convert to EMR on EKS job configuration', 
                    'Migrate job scripts to S3',
                    'Create EMR on EKS job templates',
                    'Validate migration'
                ]
            }
            
            with open(output_file, 'w') as f:
                json.dump(manifest, f, indent=2, default=str)
            
            logger.info(f"Migration manifest created: {output_file}")
            
        except Exception as e:
            logger.error(f"Failed to create migration manifest: {e}")
            raise
    
    def validate_migration(self, manifest_file: str) -> bool:
        """Validate the migration configuration"""
        
        try:
            with open(manifest_file, 'r') as f:
                manifest = json.load(f)
            
            # Validate virtual cluster exists
            response = self.emr_containers_client.describe_virtual_cluster(
                id=self.virtual_cluster_id
            )
            
            if response['virtualCluster']['state'] != 'RUNNING':
                logger.error(f"Virtual cluster {self.virtual_cluster_id} is not running")
                return False
            
            # Validate job configuration
            eks_config = manifest['target_eks_config']
            
            # Check required fields
            required_fields = ['name', 'virtualClusterId', 'executionRoleArn', 'jobDriver']
            for field in required_fields:
                if field not in eks_config:
                    logger.error(f"Missing required field in EKS config: {field}")
                    return False
            
            logger.info("Migration validation passed")
            return True
            
        except Exception as e:
            logger.error(f"Migration validation failed: {e}")
            return False

def main():
    parser = argparse.ArgumentParser(description='Migrate EMR cluster to EMR on EKS')
    parser.add_argument('--emr-cluster-id', required=True, help='Source EMR cluster ID')
    parser.add_argument('--virtual-cluster-id', required=True, help='Target EMR on EKS virtual cluster ID')
    parser.add_argument('--cluster-name', required=True, help='EKS cluster name')
    parser.add_argument('--source-scripts-s3', help='Source S3 path for job scripts')
    parser.add_argument('--target-scripts-s3', help='Target S3 path for migrated scripts')
    parser.add_argument('--output-manifest', default='migration-manifest.json', help='Output manifest file')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    parser.add_argument('--validate-only', action='store_true', help='Only validate existing migration')
    
    args = parser.parse_args()
    
    migrator = EMRToEKSMigrator(
        cluster_name=args.cluster_name,
        virtual_cluster_id=args.virtual_cluster_id,
        region=args.region
    )
    
    try:
        if args.validate_only:
            if migrator.validate_migration(args.output_manifest):
                logger.info("Migration validation successful")
            else:
                logger.error("Migration validation failed")
                exit(1)
        else:
            # Create migration manifest
            migrator.create_migration_manifest(args.emr_cluster_id, args.output_manifest)
            
            # Migrate job scripts if paths provided
            if args.source_scripts_s3 and args.target_scripts_s3:
                if migrator.migrate_job_scripts(args.source_scripts_s3, args.target_scripts_s3):
                    logger.info("Job scripts migration completed")
                else:
                    logger.error("Job scripts migration failed")
                    exit(1)
            
            # Validate migration
            if migrator.validate_migration(args.output_manifest):
                logger.info("Migration completed successfully")
            else:
                logger.error("Migration validation failed")
                exit(1)
                
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        exit(1)

if __name__ == '__main__':
    main()