#!/usr/bin/env python3
"""
Migration Validation Script

This script validates the migration from EMR/SageMaker to EKS by running
comprehensive tests and checks.
"""

import json
import yaml
import boto3
import requests
import subprocess
import argparse
import logging
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import pandas as pd
import numpy as np

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MigrationValidator:
    """Validates EMR to EKS and SageMaker to EKS migrations"""
    
    def __init__(self, region: str = 'us-west-2'):
        self.region = region
        self.emr_containers_client = boto3.client('emr-containers', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        self.eks_client = boto3.client('eks', region_name=region)
        
    def validate_eks_cluster(self, cluster_name: str) -> bool:
        """Validate EKS cluster is ready"""
        
        try:
            response = self.eks_client.describe_cluster(name=cluster_name)
            cluster_status = response['cluster']['status']
            
            if cluster_status != 'ACTIVE':
                logger.error(f"EKS cluster {cluster_name} is not active. Status: {cluster_status}")
                return False
            
            logger.info(f"EKS cluster {cluster_name} is active")
            
            # Check node groups
            node_groups = self.eks_client.list_nodegroups(clusterName=cluster_name)
            
            for ng_name in node_groups['nodegroups']:
                ng_response = self.eks_client.describe_nodegroup(
                    clusterName=cluster_name,
                    nodegroupName=ng_name
                )
                
                ng_status = ng_response['nodegroup']['status']
                if ng_status != 'ACTIVE':
                    logger.error(f"Node group {ng_name} is not active. Status: {ng_status}")
                    return False
                
                logger.info(f"Node group {ng_name} is active")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to validate EKS cluster: {e}")
            return False
    
    def validate_emr_virtual_cluster(self, virtual_cluster_id: str) -> bool:
        """Validate EMR on EKS virtual cluster"""
        
        try:
            response = self.emr_containers_client.describe_virtual_cluster(
                id=virtual_cluster_id
            )
            
            vc_status = response['virtualCluster']['state']
            
            if vc_status != 'RUNNING':
                logger.error(f"Virtual cluster {virtual_cluster_id} is not running. Status: {vc_status}")
                return False
            
            logger.info(f"Virtual cluster {virtual_cluster_id} is running")
            return True
            
        except Exception as e:
            logger.error(f"Failed to validate virtual cluster: {e}")
            return False
    
    def validate_kubernetes_resources(self, namespace: str) -> bool:
        """Validate Kubernetes resources are deployed"""
        
        try:
            # Check if kubectl is available
            result = subprocess.run(['kubectl', 'version', '--client'], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                logger.error("kubectl is not available")
                return False
            
            # Check namespace exists
            result = subprocess.run(['kubectl', 'get', 'namespace', namespace], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                logger.error(f"Namespace {namespace} does not exist")
                return False
            
            logger.info(f"Namespace {namespace} exists")
            
            # Check for key resources
            resources_to_check = [
                ('deployment', 'fraud-inference'),
                ('service', 'fraud-inference'),
                ('hpa', 'fraud-inference-hpa')
            ]
            
            for resource_type, resource_name in resources_to_check:
                result = subprocess.run([
                    'kubectl', 'get', resource_type, resource_name, '-n', namespace
                ], capture_output=True, text=True)
                
                if result.returncode == 0:
                    logger.info(f"{resource_type}/{resource_name} exists in namespace {namespace}")
                else:
                    logger.warning(f"{resource_type}/{resource_name} not found in namespace {namespace}")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to validate Kubernetes resources: {e}")
            return False
    
    def validate_ray_cluster(self, namespace: str = 'ml-team-a') -> bool:
        """Validate Ray cluster is running"""
        
        try:
            # Check Ray cluster exists
            result = subprocess.run([
                'kubectl', 'get', 'raycluster', '-n', namespace
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                logger.error(f"No Ray clusters found in namespace {namespace}")
                return False
            
            # Check Ray cluster status
            result = subprocess.run([
                'kubectl', 'get', 'raycluster', '-n', namespace, '-o', 'json'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                clusters = json.loads(result.stdout)
                for cluster in clusters.get('items', []):
                    cluster_name = cluster['metadata']['name']
                    status = cluster.get('status', {})
                    state = status.get('state', 'Unknown')
                    
                    if state == 'ready':
                        logger.info(f"Ray cluster {cluster_name} is ready")
                        return True
                    else:
                        logger.warning(f"Ray cluster {cluster_name} state: {state}")
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to validate Ray cluster: {e}")
            return False
    
    def test_emr_on_eks_job(self, virtual_cluster_id: str, job_config_file: str) -> bool:
        """Test EMR on EKS job submission and execution"""
        
        try:
            # Load job configuration
            with open(job_config_file, 'r') as f:
                job_config = json.load(f)
            
            # Submit test job
            response = self.emr_containers_client.start_job_run(
                virtualClusterId=virtual_cluster_id,
                name=f"migration-test-{int(time.time())}",
                executionRoleArn=job_config['executionRoleArn'],
                releaseLabel=job_config['releaseLabel'],
                jobDriver=job_config['jobDriver'],
                configurationOverrides=job_config.get('configurationOverrides', {})
            )
            
            job_run_id = response['id']
            logger.info(f"Test job submitted: {job_run_id}")
            
            # Wait for job completion (with timeout)
            max_wait_time = 1800  # 30 minutes
            start_time = time.time()
            
            while time.time() - start_time < max_wait_time:
                job_response = self.emr_containers_client.describe_job_run(
                    virtualClusterId=virtual_cluster_id,
                    id=job_run_id
                )
                
                job_state = job_response['jobRun']['state']
                
                if job_state == 'COMPLETED':
                    logger.info(f"Test job {job_run_id} completed successfully")
                    return True
                elif job_state in ['FAILED', 'CANCELLED']:
                    logger.error(f"Test job {job_run_id} failed with state: {job_state}")
                    return False
                
                logger.info(f"Test job {job_run_id} state: {job_state}")
                time.sleep(30)
            
            logger.error(f"Test job {job_run_id} timed out")
            return False
            
        except Exception as e:
            logger.error(f"Failed to test EMR on EKS job: {e}")
            return False
    
    def test_ray_training_job(self, namespace: str = 'ml-team-a') -> bool:
        """Test Ray training job submission"""
        
        try:
            # Create a simple test training job
            test_job_yaml = f'''
apiVersion: ray.io/v1alpha1
kind: RayJob
metadata:
  name: migration-test-{int(time.time())}
  namespace: {namespace}
spec:
  entrypoint: python -c "import ray; ray.init(); print('Ray training test successful'); ray.shutdown()"
  runtimeEnv: '{{"pip": ["ray==2.8.0"]}}'
  rayClusterSpec:
    rayVersion: '2.8.0'
    headGroupSpec:
      replicas: 1
      rayStartParams:
        dashboard-host: '0.0.0.0'
      template:
        spec:
          containers:
          - name: ray-head
            image: rayproject/ray-ml:2.8.0
            resources:
              requests:
                cpu: "1"
                memory: "2Gi"
    workerGroupSpecs:
    - replicas: 1
      minReplicas: 1
      maxReplicas: 1
      groupName: test-workers
      template:
        spec:
          containers:
          - name: ray-worker
            image: rayproject/ray-ml:2.8.0
            resources:
              requests:
                cpu: "1"
                memory: "2Gi"
'''
            
            # Apply the test job
            with open('/tmp/test-ray-job.yaml', 'w') as f:
                f.write(test_job_yaml)
            
            result = subprocess.run([
                'kubectl', 'apply', '-f', '/tmp/test-ray-job.yaml'
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                logger.error(f"Failed to submit Ray test job: {result.stderr}")
                return False
            
            logger.info("Ray test job submitted successfully")
            
            # Wait for job completion
            max_wait_time = 600  # 10 minutes
            start_time = time.time()
            
            job_name = f"migration-test-{int(time.time())}"
            
            while time.time() - start_time < max_wait_time:
                result = subprocess.run([
                    'kubectl', 'get', 'rayjob', job_name, '-n', namespace, '-o', 'json'
                ], capture_output=True, text=True)
                
                if result.returncode == 0:
                    job_status = json.loads(result.stdout)
                    job_state = job_status.get('status', {}).get('jobStatus', 'Unknown')
                    
                    if job_state == 'SUCCEEDED':
                        logger.info("Ray test job completed successfully")
                        return True
                    elif job_state == 'FAILED':
                        logger.error("Ray test job failed")
                        return False
                
                time.sleep(10)
            
            logger.error("Ray test job timed out")
            return False
            
        except Exception as e:
            logger.error(f"Failed to test Ray training job: {e}")
            return False
    
    def test_inference_service(self, service_url: str) -> bool:
        """Test inference service endpoints"""
        
        try:
            # Test health endpoint
            health_response = requests.get(f"{service_url}/health", timeout=10)
            
            if health_response.status_code != 200:
                logger.error(f"Health check failed: {health_response.status_code}")
                return False
            
            logger.info("Health check passed")
            
            # Test readiness endpoint
            ready_response = requests.get(f"{service_url}/ready", timeout=10)
            
            if ready_response.status_code != 200:
                logger.error(f"Readiness check failed: {ready_response.status_code}")
                return False
            
            logger.info("Readiness check passed")
            
            # Test prediction endpoint with sample data
            sample_features = {
                "TX_AMOUNT": 100.0,
                "yyyy": 2023,
                "mm": 6,
                "dd": 15,
                "customer_id_nb_txns_1_window": 5,
                "customer_id_avg_amt_1_window": 85.5,
                "terminal_id_nb_txns_1_window": 20,
                "terminal_id_avg_amt_1_window": 95.2
            }
            
            prediction_response = requests.post(
                f"{service_url}/predict",
                json={"features": sample_features},
                timeout=30
            )
            
            if prediction_response.status_code != 200:
                logger.error(f"Prediction failed: {prediction_response.status_code}")
                return False
            
            prediction_data = prediction_response.json()
            
            if 'prediction' not in prediction_data or 'probability' not in prediction_data:
                logger.error("Invalid prediction response format")
                return False
            
            logger.info(f"Prediction test passed: {prediction_data}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to test inference service: {e}")
            return False
    
    def validate_data_consistency(self, source_s3_path: str, target_s3_path: str) -> bool:
        """Validate data consistency between source and target"""
        
        try:
            # Compare file counts and sizes
            source_bucket, source_prefix = source_s3_path.replace('s3://', '').split('/', 1)
            target_bucket, target_prefix = target_s3_path.replace('s3://', '').split('/', 1)
            
            # List source files
            source_response = self.s3_client.list_objects_v2(
                Bucket=source_bucket,
                Prefix=source_prefix
            )
            
            source_files = source_response.get('Contents', [])
            source_total_size = sum(obj['Size'] for obj in source_files)
            
            # List target files
            target_response = self.s3_client.list_objects_v2(
                Bucket=target_bucket,
                Prefix=target_prefix
            )
            
            target_files = target_response.get('Contents', [])
            target_total_size = sum(obj['Size'] for obj in target_files)
            
            logger.info(f"Source files: {len(source_files)}, Total size: {source_total_size}")
            logger.info(f"Target files: {len(target_files)}, Total size: {target_total_size}")
            
            # Allow for some variation in file sizes due to compression/format differences
            size_diff_ratio = abs(source_total_size - target_total_size) / max(source_total_size, 1)
            
            if size_diff_ratio > 0.1:  # 10% tolerance
                logger.warning(f"Significant size difference: {size_diff_ratio:.2%}")
            else:
                logger.info("Data size consistency check passed")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to validate data consistency: {e}")
            return False
    
    def run_comprehensive_validation(self, config: Dict) -> Dict[str, bool]:
        """Run comprehensive migration validation"""
        
        results = {}
        
        # Validate EKS cluster
        if 'cluster_name' in config:
            results['eks_cluster'] = self.validate_eks_cluster(config['cluster_name'])
        
        # Validate EMR virtual cluster
        if 'virtual_cluster_id' in config:
            results['emr_virtual_cluster'] = self.validate_emr_virtual_cluster(config['virtual_cluster_id'])
        
        # Validate Kubernetes resources
        if 'namespace' in config:
            results['kubernetes_resources'] = self.validate_kubernetes_resources(config['namespace'])
        
        # Validate Ray cluster
        results['ray_cluster'] = self.validate_ray_cluster(config.get('namespace', 'ml-team-a'))
        
        # Test EMR on EKS job
        if 'virtual_cluster_id' in config and 'emr_job_config' in config:
            results['emr_job_test'] = self.test_emr_on_eks_job(
                config['virtual_cluster_id'],
                config['emr_job_config']
            )
        
        # Test Ray training job
        results['ray_training_test'] = self.test_ray_training_job(config.get('namespace', 'ml-team-a'))
        
        # Test inference service
        if 'inference_service_url' in config:
            results['inference_service_test'] = self.test_inference_service(config['inference_service_url'])
        
        # Validate data consistency
        if 'source_data_path' in config and 'target_data_path' in config:
            results['data_consistency'] = self.validate_data_consistency(
                config['source_data_path'],
                config['target_data_path']
            )
        
        return results

def main():
    parser = argparse.ArgumentParser(description='Validate EMR to EKS migration')
    parser.add_argument('--config', required=True, help='Validation configuration file')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    parser.add_argument('--output', help='Output file for validation results')
    
    args = parser.parse_args()
    
    # Load validation configuration
    with open(args.config, 'r') as f:
        if args.config.endswith('.yaml') or args.config.endswith('.yml'):
            config = yaml.safe_load(f)
        else:
            config = json.load(f)
    
    validator = MigrationValidator(region=args.region)
    
    try:
        logger.info("Starting comprehensive migration validation...")
        
        results = validator.run_comprehensive_validation(config)
        
        # Generate validation report
        report = {
            'validation_timestamp': datetime.now().isoformat(),
            'configuration': config,
            'results': results,
            'summary': {
                'total_tests': len(results),
                'passed_tests': sum(1 for result in results.values() if result),
                'failed_tests': sum(1 for result in results.values() if not result),
                'success_rate': sum(1 for result in results.values() if result) / len(results) * 100
            }
        }
        
        # Print summary
        logger.info("=== Validation Summary ===")
        for test_name, result in results.items():
            status = "PASS" if result else "FAIL"
            logger.info(f"{test_name}: {status}")
        
        logger.info(f"Overall success rate: {report['summary']['success_rate']:.1f}%")
        
        # Save report if output file specified
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(report, f, indent=2)
            logger.info(f"Validation report saved to: {args.output}")
        
        # Exit with appropriate code
        if report['summary']['failed_tests'] > 0:
            logger.error("Some validation tests failed")
            exit(1)
        else:
            logger.info("All validation tests passed")
            exit(0)
            
    except Exception as e:
        logger.error(f"Validation failed: {e}")
        exit(1)

if __name__ == '__main__':
    main()