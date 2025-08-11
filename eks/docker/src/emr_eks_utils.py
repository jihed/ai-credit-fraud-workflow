"""
EMR on EKS Job Submission and Management Utilities

This module provides helper functions to submit, monitor, and manage EMR on EKS jobs
from JupyterHub notebooks. It includes templates for different types of fraud detection
workloads: feature engineering, training, and inference.

Requirements addressed: 2.1, 2.2
"""

import boto3
import json
import time
import os
from typing import Dict, List, Optional, Any
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EMRJobSubmissionError(Exception):
    """Custom exception for EMR job submission errors"""
    pass


class EMRJobMonitoringError(Exception):
    """Custom exception for EMR job monitoring errors"""
    pass


class EMROnEKSJobManager:
    """
    Manages EMR on EKS job submission, monitoring, and templates for fraud detection workloads.
    """
    
    def __init__(self, 
                 virtual_cluster_id: str,
                 execution_role_arn: str,
                 region: str = 'us-west-2',
                 s3_bucket: str = None):
        """
        Initialize EMR on EKS Job Manager
        
        Args:
            virtual_cluster_id: EMR virtual cluster ID
            execution_role_arn: IAM role ARN for job execution
            region: AWS region
            s3_bucket: S3 bucket for storing job artifacts
        """
        self.virtual_cluster_id = virtual_cluster_id
        self.execution_role_arn = execution_role_arn
        self.region = region
        self.s3_bucket = s3_bucket or os.environ.get('S3_BUCKET')
        
        # Initialize AWS clients
        self.emr_client = boto3.client('emr-containers', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        
        # Job templates
        self.job_templates = self._initialize_job_templates()
        
        logger.info(f"EMR on EKS Job Manager initialized")
        logger.info(f"Virtual Cluster ID: {virtual_cluster_id}")
        logger.info(f"Region: {region}")
        logger.info(f"S3 Bucket: {self.s3_bucket}")
    
    def _initialize_job_templates(self) -> Dict[str, Dict]:
        """Initialize job templates for different fraud detection workloads"""
        return {
            'rapids_test': {
                'name_prefix': 'rapids-test',
                'release_label': 'emr-6.9.0-spark-rapids-latest',  # Use official RAPIDS image
                'executor_instances': '2',
                'executor_memory': '8G',
                'executor_cores': '2',
                'driver_cores': '2',
                'driver_memory': '4G',
                'container_image': 'public.ecr.aws/emr-on-eks/spark-rapids:emr-6.9.0-spark-rapids-latest',
                'spark_configs': {
                    # Core RAPIDS configuration - optimized for official image
                    'spark.plugins': 'com.nvidia.spark.SQLPlugin',
                    'spark.rapids.sql.enabled': 'true',
                    'spark.rapids.sql.python.gpu.enabled': 'true',
                    'spark.rapids.sql.concurrentGpuTasks': '2',
                    'spark.rapids.memory.pinnedPool.size': '2G',
                    'spark.rapids.memory.gpu.pool': 'ASYNC',
                    'spark.rapids.memory.gpu.allocFraction': '0.6',
                    'spark.rapids.shuffle.mode': 'MULTITHREADED',
                    
                    # GPU resource allocation - both driver and executors get GPU
                    'spark.executor.resource.gpu.vendor': 'nvidia.com',
                    'spark.executor.resource.gpu.amount': '1',
                    'spark.task.resource.gpu.amount': '1',
                    'spark.driver.resource.gpu.amount': '1',
                    
                    # Performance tuning for RAPIDS
                    'spark.sql.adaptive.enabled': 'true',
                    'spark.sql.adaptive.coalescePartitions.enabled': 'true',
                    'spark.sql.files.maxPartitionBytes': '512MB',
                    'spark.sql.shuffle.partitions': '200',
                    'spark.locality.wait': '0s',
                    'spark.dynamicAllocation.enabled': 'false',
                    
                    # Use official RAPIDS image
                    'spark.kubernetes.container.image': 'public.ecr.aws/emr-on-eks/spark-rapids:emr-6.9.0-spark-rapids-latest'
                }
            }
        }
    
    def submit_job(self, 
                   job_type: str,
                   entry_point: str,
                   job_name: Optional[str] = None,
                   spark_submit_parameters: Optional[str] = None,
                   custom_configs: Optional[Dict] = None,
                   tags: Optional[Dict] = None) -> str:
        """
        Submit an EMR on EKS job
        
        Args:
            job_type: Type of job ('feature_engineering', 'training', 'inference')
            entry_point: S3 path to the main Python script
            job_name: Custom job name (optional)
            spark_submit_parameters: Additional Spark submit parameters
            custom_configs: Custom Spark configurations to override defaults
            tags: Job tags for tracking
            
        Returns:
            Job run ID
            
        Raises:
            EMRJobSubmissionError: If job submission fails
        """
        try:
            if job_type not in self.job_templates:
                raise EMRJobSubmissionError(f"Unknown job type: {job_type}")
            
            template = self.job_templates[job_type]
            
            # Generate job name
            if not job_name:
                timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
                job_name = f"{template['name_prefix']}-{timestamp}"
            
            # Build Spark configurations
            spark_configs = template['spark_configs'].copy()
            if custom_configs:
                spark_configs.update(custom_configs)
            
            # For GPU jobs, upload pod templates and configure properly
            gpu_job_types = ['rapids_test']
            if job_type in gpu_job_types:
                # Upload pod templates to S3
                driver_pod_template_path = self._ensure_pod_template_uploaded('driver-pod-template.yaml')
                executor_pod_template_path = self._ensure_pod_template_uploaded('executor-pod-template.yaml')
                
                # Configure pod templates and naming - this is critical for GPU scheduling
                spark_configs.update({
                    'spark.kubernetes.driver.podTemplateFile': driver_pod_template_path,
                    'spark.kubernetes.executor.podTemplateFile': executor_pod_template_path,
                    'spark.kubernetes.executor.podNamePrefix': job_name.lower(),
                    'spark.kubernetes.file.upload.path': f's3://{self.s3_bucket}/fraud-detection-scripts/path/',
                    
                    # Increase timeouts for GPU node provisioning
                    'spark.kubernetes.allocation.batch.size': '1',
                    'spark.kubernetes.allocation.batch.delay': '5s',
                    'spark.kubernetes.executor.deleteOnTermination': 'false',
                    'spark.sql.adaptive.localShuffleReader.enabled': 'false'
                })
            
            # Build Spark submit parameters
            if job_type in gpu_job_types:
                base_params = f"--conf spark.rapids.sql.enabled=true --conf spark.plugins=com.nvidia.spark.SQLPlugin"
            else:
                # For non-GPU jobs, use minimal configuration
                base_params = "--conf spark.sql.adaptive.enabled=true"
            
            if spark_submit_parameters:
                base_params += f" {spark_submit_parameters}"
            
            # Prepare job configuration
            job_config = {
                'name': job_name,
                'virtualClusterId': self.virtual_cluster_id,
                'executionRoleArn': self.execution_role_arn,
                'releaseLabel': template['release_label'],
                'jobDriver': {
                    'sparkSubmitJobDriver': {
                        'entryPoint': entry_point,
                        'sparkSubmitParameters': base_params
                    }
                },
                'configurationOverrides': {
                    'applicationConfiguration': [
                        {
                            'classification': 'spark-defaults',
                            'properties': {
                                # Basic Spark configuration
                                'spark.driver.cores': template.get('driver_cores', '1'),
                                'spark.driver.memory': template.get('driver_memory', '2G'),
                                'spark.executor.instances': template['executor_instances'],
                                'spark.executor.memory': template['executor_memory'],
                                'spark.executor.cores': template['executor_cores'],
                                
                                # Service accounts
                                'spark.kubernetes.driver.serviceAccount': 'emr-containers-sa-spark-driver',
                                'spark.kubernetes.executor.serviceAccount': 'emr-containers-sa-spark-executor',
                                
                                # Merge template-specific configurations
                                **spark_configs
                            }
                        }
                    ],
                    'monitoringConfiguration': {
                        'cloudWatchMonitoringConfiguration': {
                            'logGroupName': f'/aws/emr-containers/{self.virtual_cluster_id}',
                            'logStreamNamePrefix': job_name
                        }
                    }
                }
            }
            
            # Add tags if provided
            if tags:
                job_config['tags'] = tags
            
            logger.info(f"Submitting EMR job: {job_name}")
            logger.info(f"Job type: {job_type}")
            logger.info(f"Entry point: {entry_point}")
            
            # Submit the job
            response = self.emr_client.start_job_run(**job_config)
            job_run_id = response['id']
            
            logger.info(f"✅ Job submitted successfully: {job_run_id}")
            logger.info(f"Monitor with: aws emr-containers describe-job-run --virtual-cluster-id {self.virtual_cluster_id} --id {job_run_id}")
            
            return job_run_id
            
        except Exception as e:
            logger.error(f"Failed to submit EMR job: {str(e)}")
            raise EMRJobSubmissionError(f"Job submission failed: {str(e)}")
    
    def get_job_status(self, job_run_id: str) -> Dict[str, Any]:
        """
        Get the status of an EMR on EKS job
        
        Args:
            job_run_id: Job run ID
            
        Returns:
            Job status information
        """
        try:
            response = self.emr_client.describe_job_run(
                virtualClusterId=self.virtual_cluster_id,
                id=job_run_id
            )
            
            job_run = response['jobRun']
            
            return {
                'id': job_run['id'],
                'name': job_run['name'],
                'state': job_run['state'],
                'created_at': job_run['createdAt'],
                'finished_at': job_run.get('finishedAt'),
                'state_details': job_run.get('stateDetails', ''),
                'failure_reason': job_run.get('failureReason', ''),
                'spark_ui': job_run.get('sparkUI', {})
            }
            
        except Exception as e:
            logger.error(f"Failed to get job status: {str(e)}")
            raise EMRJobMonitoringError(f"Failed to get job status: {str(e)}")
    
    def wait_for_job_completion(self, 
                               job_run_id: str, 
                               max_wait_time: int = 3600,
                               check_interval: int = 30) -> Dict[str, Any]:
        """
        Wait for job completion with periodic status checks
        
        Args:
            job_run_id: Job run ID
            max_wait_time: Maximum wait time in seconds (default: 1 hour)
            check_interval: Status check interval in seconds (default: 30 seconds)
            
        Returns:
            Final job status
        """
        start_time = time.time()
        
        logger.info(f"Waiting for job completion: {job_run_id}")
        logger.info(f"Max wait time: {max_wait_time} seconds")
        
        while time.time() - start_time < max_wait_time:
            status = self.get_job_status(job_run_id)
            state = status['state']
            
            logger.info(f"Job {job_run_id} status: {state}")
            
            if state in ['COMPLETED', 'FAILED', 'CANCELLED']:
                if state == 'COMPLETED':
                    logger.info(f"✅ Job completed successfully: {job_run_id}")
                else:
                    logger.error(f"❌ Job failed with state: {state}")
                    logger.error(f"Failure reason: {status.get('failure_reason', 'Unknown')}")
                
                return status
            
            time.sleep(check_interval)
        
        # Timeout reached
        logger.warning(f"⚠️ Job monitoring timeout reached for: {job_run_id}")
        return self.get_job_status(job_run_id)
    
    def list_jobs(self, 
                  max_results: int = 20,
                  states: Optional[List[str]] = None) -> List[Dict[str, Any]]:
        """
        List EMR on EKS jobs
        
        Args:
            max_results: Maximum number of results to return
            states: Filter by job states (e.g., ['RUNNING', 'COMPLETED'])
            
        Returns:
            List of job information
        """
        try:
            params = {
                'virtualClusterId': self.virtual_cluster_id,
                'maxResults': max_results
            }
            
            if states:
                params['states'] = states
            
            response = self.emr_client.list_job_runs(**params)
            
            jobs = []
            for job_run in response['jobRuns']:
                jobs.append({
                    'id': job_run['id'],
                    'name': job_run['name'],
                    'state': job_run['state'],
                    'created_at': job_run['createdAt'],
                    'finished_at': job_run.get('finishedAt')
                })
            
            return jobs
            
        except Exception as e:
            logger.error(f"Failed to list jobs: {str(e)}")
            raise EMRJobMonitoringError(f"Failed to list jobs: {str(e)}")
    
    def cancel_job(self, job_run_id: str) -> bool:
        """
        Cancel a running EMR on EKS job
        
        Args:
            job_run_id: Job run ID to cancel
            
        Returns:
            True if cancellation was successful
        """
        try:
            self.emr_client.cancel_job_run(
                virtualClusterId=self.virtual_cluster_id,
                id=job_run_id
            )
            
            logger.info(f"✅ Job cancellation requested: {job_run_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to cancel job: {str(e)}")
            return False
    
    def submit_feature_engineering_job(self, 
                                      input_data_path: str = None,
                                      output_path: str = None,
                                      custom_configs: Optional[Dict] = None) -> str:
        """
        Submit a feature engineering job with fraud detection specific configurations
        
        Args:
            input_data_path: S3 path to input data (optional, uses default)
            output_path: S3 path for output (optional, uses default)
            custom_configs: Custom Spark configurations
            
        Returns:
            Job run ID
        """
        # Default paths for fraud detection data
        if not input_data_path:
            input_data_path = "s3://nvidia-aws-fraud-detection-demo-training-data/"
        
        if not output_path:
            output_path = f"s3://{self.s3_bucket}/fraud-data/processed-features/"
        
        # Upload feature engineering script if needed
        script_path = self._ensure_script_uploaded('feature_engineering.py')
        
        # Add job-specific parameters
        spark_params = f"--py-files {script_path} --conf spark.sql.shuffle.partitions=20000"
        
        tags = {
            'JobType': 'FeatureEngineering',
            'Project': 'FraudDetection',
            'DataSource': input_data_path,
            'OutputPath': output_path
        }
        
        return self.submit_job(
            job_type='feature_engineering',
            entry_point=script_path,
            spark_submit_parameters=spark_params,
            custom_configs=custom_configs,
            tags=tags
        )
    
    def submit_training_job(self, 
                           features_path: str = None,
                           model_output_path: str = None,
                           custom_configs: Optional[Dict] = None) -> str:
        """
        Submit an XGBoost training job
        
        Args:
            features_path: S3 path to processed features
            model_output_path: S3 path for trained model
            custom_configs: Custom Spark configurations
            
        Returns:
            Job run ID
        """
        if not features_path:
            features_path = f"s3://{self.s3_bucket}/fraud-data/processed-features/"
        
        if not model_output_path:
            model_output_path = f"s3://{self.s3_bucket}/fraud-models/xgboost/"
        
        script_path = self._ensure_script_uploaded('xgboost_training.py')
        
        spark_params = f"--py-files {script_path}"
        
        tags = {
            'JobType': 'Training',
            'Project': 'FraudDetection',
            'Algorithm': 'XGBoost',
            'FeaturesPath': features_path,
            'ModelOutputPath': model_output_path
        }
        
        return self.submit_job(
            job_type='training',
            entry_point=script_path,
            spark_submit_parameters=spark_params,
            custom_configs=custom_configs,
            tags=tags
        )
    
    def submit_inference_job(self, 
                            model_path: str = None,
                            input_data_path: str = None,
                            predictions_output_path: str = None,
                            custom_configs: Optional[Dict] = None) -> str:
        """
        Submit a batch inference job
        
        Args:
            model_path: S3 path to trained model
            input_data_path: S3 path to data for inference
            predictions_output_path: S3 path for predictions output
            custom_configs: Custom Spark configurations
            
        Returns:
            Job run ID
        """
        if not model_path:
            model_path = f"s3://{self.s3_bucket}/fraud-models/xgboost/"
        
        if not input_data_path:
            input_data_path = f"s3://{self.s3_bucket}/fraud-data/new-transactions/"
        
        if not predictions_output_path:
            predictions_output_path = f"s3://{self.s3_bucket}/fraud-predictions/batch-results/"
        
        script_path = self._ensure_script_uploaded('batch_inference.py')
        
        spark_params = f"--py-files {script_path}"
        
        tags = {
            'JobType': 'Inference',
            'Project': 'FraudDetection',
            'ModelPath': model_path,
            'InputDataPath': input_data_path,
            'PredictionsPath': predictions_output_path
        }
        
        return self.submit_job(
            job_type='inference',
            entry_point=script_path,
            spark_submit_parameters=spark_params,
            custom_configs=custom_configs,
            tags=tags
        )
    
    def _ensure_script_uploaded(self, script_name: str) -> str:
        """
        Ensure the script is uploaded to S3 and return the S3 path
        
        Args:
            script_name: Name of the script file
            
        Returns:
            S3 path to the script
        """
        s3_key = f"fraud-detection-scripts/{script_name}"
        s3_path = f"s3://{self.s3_bucket}/{s3_key}"
        
        # Check if script exists locally and upload if needed
        local_script_path = f"/home/jovyan/src/{script_name}"
        
        if os.path.exists(local_script_path):
            try:
                self.s3_client.upload_file(local_script_path, self.s3_bucket, s3_key)
                logger.info(f"Uploaded script to: {s3_path}")
            except Exception as e:
                logger.warning(f"Failed to upload script: {str(e)}")
        
        return s3_path
    
    def _ensure_pod_template_uploaded(self, template_name: str) -> str:
        """
        Ensure the pod template is uploaded to S3 and return the S3 path
        
        Args:
            template_name: Name of the pod template file
            
        Returns:
            S3 path to the pod template
        """
        s3_key = f"fraud-detection-pod-templates/{template_name}"
        s3_path = f"s3://{self.s3_bucket}/{s3_key}"
        
        # Check if template exists locally and upload if needed
        local_template_path = os.path.join(os.path.dirname(__file__), '..', template_name)
        
        if os.path.exists(local_template_path):
            try:
                self.s3_client.upload_file(local_template_path, self.s3_bucket, s3_key)
                logger.info(f"Uploaded pod template to: {s3_path}")
            except Exception as e:
                logger.warning(f"Failed to upload pod template: {str(e)}")
        
        return s3_path
    
    def submit_rapids_test_job(self, 
                              custom_configs: Optional[Dict] = None,
                              container_image: Optional[str] = None) -> str:
        """
        Submit a RAPIDS test job using official EMR RAPIDS image
        
        Args:
            custom_configs: Custom Spark configurations
            container_image: Custom container image (defaults to official EMR RAPIDS image)
            
        Returns:
            Job run ID
        """
        # Upload RAPIDS test script if needed
        script_path = self._ensure_script_uploaded('rapids_test_job.py')
        
        # Add job-specific parameters
        spark_params = f"--py-files {script_path}"
        
        # Use official EMR RAPIDS image by default, or custom if provided
        if not custom_configs:
            custom_configs = {}
            
        if container_image:
            custom_configs['spark.kubernetes.container.image'] = container_image
        else:
            # Use official EMR RAPIDS image by default
            custom_configs['spark.kubernetes.container.image'] = 'public.ecr.aws/emr-on-eks/spark-rapids:emr-6.9.0-spark-rapids-latest'
        
        tags = {
            'JobType': 'RapidsTest',
            'Project': 'FraudDetection',
            'TestType': 'GPUAcceleration'
        }
        
        return self.submit_job(
            job_type='rapids_test',
            entry_point=script_path,
            spark_submit_parameters=spark_params,
            custom_configs=custom_configs,
            tags=tags
        )
    
    def get_job_logs(self, job_run_id: str) -> Dict[str, str]:
        """
        Get CloudWatch logs for a job (placeholder for log retrieval)
        
        Args:
            job_run_id: Job run ID
            
        Returns:
            Dictionary with log information
        """
        # This would integrate with CloudWatch Logs API
        # For now, return log group information
        return {
            'log_group': f'/aws/emr-containers/{self.virtual_cluster_id}',
            'log_stream_prefix': job_run_id,
            'console_url': f'https://console.aws.amazon.com/cloudwatch/home?region={self.region}#logsV2:log-groups/log-group/%2Faws%2Femr-containers%2F{self.virtual_cluster_id}'
        }


# Convenience functions for notebook usage
def create_job_manager(virtual_cluster_id: str = None,
                      execution_role_arn: str = None,
                      region: str = None,
                      s3_bucket: str = None) -> EMROnEKSJobManager:
    """
    Create an EMR on EKS Job Manager with environment variable defaults
    
    Args:
        virtual_cluster_id: EMR virtual cluster ID (defaults to env var)
        execution_role_arn: IAM role ARN (defaults to env var)
        region: AWS region (defaults to env var)
        s3_bucket: S3 bucket (defaults to env var)
        
    Returns:
        EMROnEKSJobManager instance
    """
    return EMROnEKSJobManager(
        virtual_cluster_id=virtual_cluster_id or os.environ.get('VIRTUAL_CLUSTER_ID'),
        execution_role_arn=execution_role_arn or os.environ.get('EMR_EXECUTION_ROLE_ARN'),
        region=region or os.environ.get('AWS_DEFAULT_REGION', 'us-west-2'),
        s3_bucket=s3_bucket or os.environ.get('S3_BUCKET')
    )


# Removed unused convenience functions - keeping only essential RAPIDS functionality


def monitor_job(job_run_id: str, wait_for_completion: bool = False) -> Dict[str, Any]:
    """
    Monitor a job and optionally wait for completion
    
    Args:
        job_run_id: Job run ID to monitor
        wait_for_completion: Whether to wait for job completion
        
    Returns:
        Job status information
    """
    job_manager = create_job_manager()
    
    if wait_for_completion:
        return job_manager.wait_for_job_completion(job_run_id)
    else:
        return job_manager.get_job_status(job_run_id)


# Example usage functions for notebooks
def print_job_status(job_run_id: str):
    """
    Print formatted job status information
    
    Args:
        job_run_id: Job run ID
    """
    try:
        status = monitor_job(job_run_id)
        
        print(f"\n=== Job Status: {job_run_id} ===")
        print(f"Name: {status['name']}")
        print(f"State: {status['state']}")
        print(f"Created: {status['created_at']}")
        if status['finished_at']:
            print(f"Finished: {status['finished_at']}")
        if status['state_details']:
            print(f"Details: {status['state_details']}")
        if status['failure_reason']:
            print(f"Failure Reason: {status['failure_reason']}")
        
        # Spark UI link if available
        spark_ui = status.get('spark_ui', {})
        if spark_ui.get('sparkUIUrl'):
            print(f"Spark UI: {spark_ui['sparkUIUrl']}")
            
    except Exception as e:
        print(f"Error getting job status: {str(e)}")


def submit_rapids_test(container_image: str = None) -> str:
    """
    Submit RAPIDS test job using official EMR RAPIDS image
    
    Args:
        container_image: Custom RAPIDS-enabled container image 
                        (defaults to official EMR RAPIDS image)
        
    Returns:
        Job run ID
    """
    job_manager = create_job_manager()
    return job_manager.submit_rapids_test_job(container_image=container_image)


# Essential functions for RAPIDS testing and monitoring