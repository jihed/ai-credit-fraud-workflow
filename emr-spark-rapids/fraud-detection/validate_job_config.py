#!/usr/bin/env python3
"""
Validation script for fraud detection EMR on EKS job configuration
Tests job template, validates parameters, and checks dependencies
"""

import json
import sys
import os
from typing import Dict, List, Optional
import logging

# Optional imports for full validation
try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False

try:
    import boto3
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class JobConfigValidator:
    """
    Validates EMR on EKS job configuration for fraud detection
    """
    
    def __init__(self):
        self.errors = []
        self.warnings = []
        
    def validate_job_template(self, template_path: str) -> bool:
        """
        Validate the EMR on EKS job template JSON
        """
        logger.info(f"Validating job template: {template_path}")
        
        try:
            with open(template_path, 'r') as f:
                template = json.load(f)
            
            # Check required fields
            required_fields = [
                'name', 'virtualClusterId', 'executionRoleArn', 
                'releaseLabel', 'jobDriver', 'configurationOverrides'
            ]
            
            for field in required_fields:
                if field not in template:
                    self.errors.append(f"Missing required field in job template: {field}")
            
            # Validate job driver
            if 'jobDriver' in template:
                job_driver = template['jobDriver']
                if 'sparkSubmitJobDriver' not in job_driver:
                    self.errors.append("Missing sparkSubmitJobDriver in jobDriver")
                else:
                    spark_driver = job_driver['sparkSubmitJobDriver']
                    if 'entryPoint' not in spark_driver:
                        self.errors.append("Missing entryPoint in sparkSubmitJobDriver")
                    if 'entryPointArguments' not in spark_driver:
                        self.warnings.append("No entryPointArguments specified")
            
            # Validate configuration overrides
            if 'configurationOverrides' in template:
                config = template['configurationOverrides']
                if 'applicationConfiguration' not in config:
                    self.warnings.append("No applicationConfiguration specified")
                
                # Check for RAPIDS configuration
                if 'applicationConfiguration' in config:
                    app_configs = config['applicationConfiguration']
                    spark_defaults = None
                    
                    for app_config in app_configs:
                        if app_config.get('classification') == 'spark-defaults':
                            spark_defaults = app_config.get('properties', {})
                            break
                    
                    if spark_defaults:
                        # Check for essential RAPIDS settings
                        rapids_settings = [
                            'spark.plugins',
                            'spark.rapids.sql.enabled',
                            'spark.executor.resource.gpu.amount'
                        ]
                        
                        for setting in rapids_settings:
                            if setting not in spark_defaults:
                                self.warnings.append(f"Missing RAPIDS setting: {setting}")
                    else:
                        self.warnings.append("No spark-defaults configuration found")
            
            logger.info("Job template validation completed")
            return len(self.errors) == 0
            
        except json.JSONDecodeError as e:
            self.errors.append(f"Invalid JSON in job template: {str(e)}")
            return False
        except FileNotFoundError:
            self.errors.append(f"Job template file not found: {template_path}")
            return False
        except Exception as e:
            self.errors.append(f"Error validating job template: {str(e)}")
            return False
    
    def validate_pod_templates(self, driver_template: str, executor_template: str) -> bool:
        """
        Validate Kubernetes pod templates
        """
        logger.info("Validating pod templates")
        
        if not YAML_AVAILABLE:
            self.warnings.append("PyYAML not available, skipping pod template validation")
            return True
        
        templates = [
            ('driver', driver_template),
            ('executor', executor_template)
        ]
        
        for template_type, template_path in templates:
            try:
                with open(template_path, 'r') as f:
                    template = yaml.safe_load(f)
                
                # Check required fields
                if 'apiVersion' not in template:
                    self.errors.append(f"Missing apiVersion in {template_type} template")
                
                if 'kind' not in template or template['kind'] != 'Pod':
                    self.errors.append(f"Invalid or missing kind in {template_type} template")
                
                if 'spec' not in template:
                    self.errors.append(f"Missing spec in {template_type} template")
                    continue
                
                spec = template['spec']
                
                # Check node selector
                if 'nodeSelector' not in spec:
                    self.warnings.append(f"No nodeSelector in {template_type} template")
                
                # Check containers
                if 'containers' not in spec:
                    self.errors.append(f"Missing containers in {template_type} template")
                    continue
                
                containers = spec['containers']
                if not containers:
                    self.errors.append(f"No containers defined in {template_type} template")
                    continue
                
                # For executor template, check GPU resources
                if template_type == 'executor':
                    gpu_found = False
                    for container in containers:
                        resources = container.get('resources', {})
                        requests = resources.get('requests', {})
                        if 'nvidia.com/gpu' in requests:
                            gpu_found = True
                            break
                    
                    if not gpu_found:
                        self.warnings.append("No GPU resources requested in executor template")
                    
                    # Check tolerations for GPU
                    tolerations = spec.get('tolerations', [])
                    gpu_toleration = False
                    for toleration in tolerations:
                        if toleration.get('key') == 'nvidia.com/gpu':
                            gpu_toleration = True
                            break
                    
                    if not gpu_toleration:
                        self.warnings.append("No GPU toleration in executor template")
                
            except yaml.YAMLError as e:
                self.errors.append(f"Invalid YAML in {template_type} template: {str(e)}")
            except FileNotFoundError:
                self.errors.append(f"{template_type.title()} template file not found: {template_path}")
            except Exception as e:
                self.errors.append(f"Error validating {template_type} template: {str(e)}")
        
        logger.info("Pod template validation completed")
        return len(self.errors) == 0
    
    def validate_python_script(self, script_path: str) -> bool:
        """
        Validate the Python feature engineering script
        """
        logger.info(f"Validating Python script: {script_path}")
        
        try:
            with open(script_path, 'r') as f:
                script_content = f.read()
            
            # Check for required imports
            required_imports = [
                'from pyspark.sql import SparkSession',
                'from pyspark.sql import functions as F',
                'from pyspark.sql.window import Window'
            ]
            
            for import_stmt in required_imports:
                if import_stmt not in script_content:
                    self.warnings.append(f"Missing import: {import_stmt}")
            
            # Check for main function
            if 'def main():' not in script_content:
                self.errors.append("No main() function found in script")
            
            # Check for RAPIDS configuration
            if 'spark.rapids.sql.enabled' not in script_content:
                self.warnings.append("No RAPIDS SQL configuration found in script")
            
            # Check for command line argument handling
            if 'sys.argv' not in script_content:
                self.warnings.append("No command line argument handling found")
            
            logger.info("Python script validation completed")
            return len(self.errors) == 0
            
        except FileNotFoundError:
            self.errors.append(f"Python script file not found: {script_path}")
            return False
        except Exception as e:
            self.errors.append(f"Error validating Python script: {str(e)}")
            return False
    
    def validate_aws_resources(self, cluster_id: str, role_arn: str, 
                             s3_bucket: str, region: str = 'us-west-2') -> bool:
        """
        Validate AWS resources exist and are accessible
        """
        logger.info("Validating AWS resources")
        
        if not BOTO3_AVAILABLE:
            self.warnings.append("boto3 not available, skipping AWS resource validation")
            return True
        
        try:
            # Initialize AWS clients
            emr_client = boto3.client('emr-containers', region_name=region)
            iam_client = boto3.client('iam', region_name=region)
            s3_client = boto3.client('s3', region_name=region)
            
            # Check EMR virtual cluster
            try:
                response = emr_client.describe_virtual_cluster(id=cluster_id)
                cluster_state = response['virtualCluster']['state']
                if cluster_state != 'RUNNING':
                    self.warnings.append(f"EMR virtual cluster is not in RUNNING state: {cluster_state}")
            except emr_client.exceptions.ResourceNotFoundException:
                self.errors.append(f"EMR virtual cluster not found: {cluster_id}")
            except Exception as e:
                self.errors.append(f"Error checking EMR virtual cluster: {str(e)}")
            
            # Check IAM role
            try:
                role_name = role_arn.split('/')[-1]
                iam_client.get_role(RoleName=role_name)
            except iam_client.exceptions.NoSuchEntityException:
                self.errors.append(f"IAM role not found: {role_arn}")
            except Exception as e:
                self.errors.append(f"Error checking IAM role: {str(e)}")
            
            # Check S3 bucket
            try:
                s3_client.head_bucket(Bucket=s3_bucket)
            except s3_client.exceptions.NoSuchBucket:
                self.errors.append(f"S3 bucket not found: {s3_bucket}")
            except Exception as e:
                self.errors.append(f"Error checking S3 bucket: {str(e)}")
            
            logger.info("AWS resource validation completed")
            return len(self.errors) == 0
            
        except Exception as e:
            self.errors.append(f"Error validating AWS resources: {str(e)}")
            return False
    
    def print_results(self):
        """
        Print validation results
        """
        print("\n" + "="*60)
        print("VALIDATION RESULTS")
        print("="*60)
        
        if self.errors:
            print(f"\n❌ ERRORS ({len(self.errors)}):")
            for i, error in enumerate(self.errors, 1):
                print(f"  {i}. {error}")
        
        if self.warnings:
            print(f"\n⚠️  WARNINGS ({len(self.warnings)}):")
            for i, warning in enumerate(self.warnings, 1):
                print(f"  {i}. {warning}")
        
        if not self.errors and not self.warnings:
            print("\n✅ All validations passed!")
        elif not self.errors:
            print(f"\n✅ Validation passed with {len(self.warnings)} warnings")
        else:
            print(f"\n❌ Validation failed with {len(self.errors)} errors and {len(self.warnings)} warnings")
        
        print("="*60)
        
        return len(self.errors) == 0


def main():
    """
    Main validation function
    """
    if len(sys.argv) < 2:
        print("Usage: python validate_job_config.py [--full] [cluster_id] [role_arn] [s3_bucket] [region]")
        print("       python validate_job_config.py --templates-only")
        sys.exit(1)
    
    validator = JobConfigValidator()
    
    # Validate local files
    template_validation = validator.validate_job_template('fraud-detection-job-template.json')
    pod_validation = validator.validate_pod_templates(
        'driver-pod-template.yaml', 
        'executor-pod-template.yaml'
    )
    script_validation = validator.validate_python_script('fraud_detection_feature_engineering.py')
    
    # AWS resource validation (optional)
    aws_validation = True
    if len(sys.argv) > 2 and sys.argv[1] != '--templates-only':
        if len(sys.argv) >= 5:
            cluster_id = sys.argv[1] if sys.argv[1] != '--full' else sys.argv[2]
            role_arn = sys.argv[2] if sys.argv[1] != '--full' else sys.argv[3]
            s3_bucket = sys.argv[3] if sys.argv[1] != '--full' else sys.argv[4]
            region = sys.argv[4] if len(sys.argv) > 4 and sys.argv[1] != '--full' else sys.argv[5] if len(sys.argv) > 5 else 'us-west-2'
            
            aws_validation = validator.validate_aws_resources(cluster_id, role_arn, s3_bucket, region)
    
    # Print results
    success = validator.print_results()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()