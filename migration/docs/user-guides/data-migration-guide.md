# Data Migration Guide: EMR to EMR on EKS

## Overview

This guide provides detailed instructions for migrating data processing workloads from traditional Amazon EMR to EMR on EKS using the existing EMR Spark RAPIDS infrastructure.

## Migration Strategy

The data migration follows a phased approach:

1. **Assessment**: Analyze existing EMR workloads and dependencies
2. **Preparation**: Set up EMR on EKS infrastructure and validate compatibility
3. **Migration**: Convert and migrate data processing jobs
4. **Validation**: Verify data consistency and performance
5. **Cutover**: Switch production workloads to EMR on EKS

## Prerequisites

### Infrastructure Requirements
- EKS cluster with EMR Spark RAPIDS configuration deployed
- EMR on EKS virtual clusters configured
- S3 buckets accessible from both EMR and EMR on EKS
- Appropriate IAM roles and permissions

### Tools Required
- AWS CLI v2.x
- kubectl configured for EKS cluster
- Python 3.8+ with boto3
- Access to source EMR cluster configurations

## Phase 1: Assessment and Planning

### 1.1 Inventory Existing EMR Workloads

```bash
# List all EMR clusters
aws emr list-clusters --active

# Get detailed information for each cluster
aws emr describe-cluster --cluster-id j-1234567890abcdef0

# List running and completed jobs
aws emr list-steps --cluster-id j-1234567890abcdef0
```

Create an inventory spreadsheet with:
- Cluster configurations (instance types, applications, versions)
- Job schedules and dependencies
- Data sources and destinations
- Performance requirements
- Business criticality

### 1.2 Analyze Data Dependencies

```python
# Script to analyze S3 data dependencies
import boto3
import pandas as pd
from collections import defaultdict

def analyze_data_dependencies(bucket_name, prefix=""):
    """Analyze S3 data structure and access patterns"""
    
    s3_client = boto3.client('s3')
    
    # List all objects
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=bucket_name, Prefix=prefix)
    
    objects = []
    for page in pages:
        if 'Contents' in page:
            objects.extend(page['Contents'])
    
    # Analyze by file type and size
    analysis = defaultdict(lambda: {'count': 0, 'total_size': 0})
    
    for obj in objects:
        key = obj['Key']
        size = obj['Size']
        
        # Determine file type
        if key.endswith('.parquet'):
            file_type = 'parquet'
        elif key.endswith('.csv'):
            file_type = 'csv'
        elif key.endswith('.json'):
            file_type = 'json'
        else:
            file_type = 'other'
        
        analysis[file_type]['count'] += 1
        analysis[file_type]['total_size'] += size
    
    # Create summary report
    summary = []
    for file_type, stats in analysis.items():
        summary.append({
            'file_type': file_type,
            'count': stats['count'],
            'total_size_gb': stats['total_size'] / (1024**3),
            'avg_size_mb': (stats['total_size'] / stats['count']) / (1024**2) if stats['count'] > 0 else 0
        })
    
    return pd.DataFrame(summary)

# Run analysis
bucket_name = "your-data-bucket"
data_analysis = analyze_data_dependencies(bucket_name, "fraud-data/")
print(data_analysis)
```

### 1.3 Performance Baseline

Document current performance metrics:
- Job execution times
- Resource utilization
- Cost per job
- Data processing throughput

```bash
# Extract performance metrics from CloudWatch
aws logs filter-log-events \
    --log-group-name /aws/emr/j-1234567890abcdef0 \
    --start-time 1640995200000 \
    --end-time 1641081600000 \
    --filter-pattern "Job completed"
```

## Phase 2: Infrastructure Preparation

### 2.1 Verify EMR on EKS Setup

```bash
# Check EKS cluster status
kubectl get nodes
kubectl get namespaces

# Verify EMR virtual clusters
aws emr-containers list-virtual-clusters

# Check RAPIDS components
kubectl get pods -n kube-system | grep nvidia
kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system
```

### 2.2 Test Basic EMR on EKS Functionality

Create a simple test job to verify the setup:

```python
# test_emr_eks_basic.py
from pyspark.sql import SparkSession

# Initialize Spark with RAPIDS
spark = SparkSession.builder \
    .appName("EMR-EKS-Test") \
    .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
    .config("spark.rapids.sql.enabled", "true") \
    .getOrCreate()

# Create test data
data = [(1, "test1", 100.0), (2, "test2", 200.0), (3, "test3", 300.0)]
columns = ["id", "name", "amount"]

df = spark.createDataFrame(data, columns)
df.show()

# Test basic operations
result = df.groupBy().sum("amount").collect()
print(f"Total amount: {result[0][0]}")

spark.stop()
print("EMR on EKS test completed successfully!")
```

Submit the test job:

```bash
# Submit test job
aws emr-containers start-job-run \
    --virtual-cluster-id your-virtual-cluster-id \
    --name "emr-eks-test-$(date +%s)" \
    --execution-role-arn arn:aws:iam::your-account:role/EMRContainers-JobExecutionRole \
    --release-label emr-6.15.0-latest \
    --job-driver '{
        "sparkSubmitJobDriver": {
            "entryPoint": "s3://your-bucket/scripts/test_emr_eks_basic.py",
            "sparkSubmitParameters": "--conf spark.executor.instances=2 --conf spark.executor.memory=4G --conf spark.driver.memory=2G"
        }
    }' \
    --configuration-overrides '{
        "monitoringConfiguration": {
            "persistentAppUI": "ENABLED",
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "/aws/emr-containers/test"
            }
        }
    }'
```

## Phase 3: Job Migration

### 3.1 Convert EMR Jobs to EMR on EKS

Use the migration script to convert existing jobs:

```bash
# Run the EMR to EMR on EKS migration script
python migration/scripts/data-migration/emr-to-emr-on-eks.py \
    --emr-cluster-id j-1234567890abcdef0 \
    --virtual-cluster-id your-virtual-cluster-id \
    --cluster-name data-on-eks-cluster \
    --source-scripts-s3 s3://your-bucket/emr-scripts/ \
    --target-scripts-s3 s3://your-bucket/emr-eks-scripts/ \
    --output-manifest migration-manifest.json
```

### 3.2 Manual Job Conversion

For complex jobs that require manual conversion:

#### Original EMR Job Configuration
```json
{
    "Name": "fraud-detection-feature-engineering",
    "ActionOnFailure": "TERMINATE_CLUSTER",
    "HadoopJarStep": {
        "Jar": "command-runner.jar",
        "Args": [
            "spark-submit",
            "--deploy-mode", "cluster",
            "--executor-memory", "28G",
            "--executor-cores", "4",
            "--num-executors", "12",
            "--driver-memory", "8G",
            "--conf", "spark.sql.adaptive.enabled=true",
            "s3://your-bucket/scripts/fraud_detection_feature_engineering.py"
        ]
    }
}
```

#### Converted EMR on EKS Job Configuration
```json
{
    "name": "fraud-detection-feature-engineering-eks",
    "virtualClusterId": "your-virtual-cluster-id",
    "executionRoleArn": "arn:aws:iam::your-account:role/EMRContainers-JobExecutionRole",
    "releaseLabel": "emr-6.15.0-latest",
    "jobDriver": {
        "sparkSubmitJobDriver": {
            "entryPoint": "s3://your-bucket/emr-eks-scripts/fraud_detection_feature_engineering.py",
            "sparkSubmitParameters": "--conf spark.plugins=com.nvidia.spark.SQLPlugin --conf spark.rapids.sql.enabled=true --conf spark.executor.resource.gpu.amount=1 --conf spark.executor.instances=12 --conf spark.executor.memory=30G --conf spark.executor.cores=4 --conf spark.driver.memory=8G --conf spark.sql.adaptive.enabled=true --conf spark.kubernetes.container.image=your-account.dkr.ecr.us-west-2.amazonaws.com/spark-rapids:latest"
        }
    },
    "configurationOverrides": {
        "applicationConfiguration": [
            {
                "classification": "spark-defaults",
                "properties": {
                    "spark.plugins": "com.nvidia.spark.SQLPlugin",
                    "spark.rapids.sql.enabled": "true",
                    "spark.executor.resource.gpu.amount": "1",
                    "spark.task.resource.gpu.amount": "0.25"
                }
            }
        ],
        "monitoringConfiguration": {
            "persistentAppUI": "ENABLED",
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "/aws/emr-containers/fraud-detection",
                "logStreamNamePrefix": "feature-engineering"
            },
            "s3MonitoringConfiguration": {
                "logUri": "s3://your-bucket/logs/emr-containers/"
            }
        }
    }
}
```

### 3.3 Script Modifications for RAPIDS

Update Python scripts to leverage RAPIDS:

#### Original Script (CPU-based)
```python
# Original fraud_detection_feature_engineering.py
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.window import Window

spark = SparkSession.builder.appName("FraudDetection").getOrCreate()

# Read data
transactions_df = spark.read.parquet("s3://bucket/transactions/")

# Create time-based features using window functions
window_spec = Window.partitionBy("CUSTOMER_ID").orderBy("TX_DATETIME").rangeBetween(-86400, 0)

features_df = transactions_df.withColumn(
    "customer_nb_txns_1d",
    count("*").over(window_spec)
).withColumn(
    "customer_avg_amt_1d", 
    avg("TX_AMOUNT").over(window_spec)
)

# Write results
features_df.write.mode("overwrite").parquet("s3://bucket/features/")
```

#### Updated Script (RAPIDS-enabled)
```python
# Updated fraud_detection_feature_engineering.py
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.window import Window

# Initialize Spark with RAPIDS
spark = SparkSession.builder \
    .appName("FraudDetectionRAPIDS") \
    .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
    .config("spark.rapids.sql.enabled", "true") \
    .config("spark.executor.resource.gpu.amount", "1") \
    .config("spark.task.resource.gpu.amount", "0.25") \
    .config("spark.rapids.memory.pinnedPool.size", "2G") \
    .getOrCreate()

# Read data (RAPIDS will automatically accelerate parquet reading)
transactions_df = spark.read.parquet("s3://bucket/transactions/")

# Create time-based features (RAPIDS will accelerate window operations)
window_spec = Window.partitionBy("CUSTOMER_ID").orderBy("TX_DATETIME").rangeBetween(-86400, 0)

features_df = transactions_df.withColumn(
    "customer_nb_txns_1d",
    count("*").over(window_spec)
).withColumn(
    "customer_avg_amt_1d", 
    avg("TX_AMOUNT").over(window_spec)
)

# Additional RAPIDS-optimized operations
features_df = features_df.withColumn(
    "amount_zscore",
    (col("TX_AMOUNT") - avg("TX_AMOUNT").over(window_spec)) / 
    stddev("TX_AMOUNT").over(window_spec)
)

# Write results (RAPIDS will accelerate parquet writing)
features_df.write.mode("overwrite").parquet("s3://bucket/features/")

spark.stop()
```

### 3.4 Batch Migration Script

For migrating multiple jobs:

```python
# batch_migration.py
import json
import boto3
import time
from datetime import datetime

def migrate_jobs_batch(job_configs, virtual_cluster_id, execution_role_arn):
    """Migrate multiple jobs in batch"""
    
    emr_containers = boto3.client('emr-containers')
    migration_results = []
    
    for job_config in job_configs:
        try:
            # Submit migrated job
            response = emr_containers.start_job_run(
                virtualClusterId=virtual_cluster_id,
                name=f"{job_config['name']}-migration-{int(time.time())}",
                executionRoleArn=execution_role_arn,
                releaseLabel=job_config['releaseLabel'],
                jobDriver=job_config['jobDriver'],
                configurationOverrides=job_config.get('configurationOverrides', {})
            )
            
            job_run_id = response['id']
            
            migration_results.append({
                'job_name': job_config['name'],
                'job_run_id': job_run_id,
                'status': 'submitted',
                'timestamp': datetime.now().isoformat()
            })
            
            print(f"Migrated job: {job_config['name']} -> {job_run_id}")
            
        except Exception as e:
            migration_results.append({
                'job_name': job_config['name'],
                'status': 'failed',
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
            
            print(f"Failed to migrate job: {job_config['name']} - {e}")
    
    return migration_results

# Load job configurations from migration manifest
with open('migration-manifest.json', 'r') as f:
    manifest = json.load(f)

# Extract job configurations
job_configs = [manifest['target_eks_config']]  # Add more jobs as needed

# Run batch migration
results = migrate_jobs_batch(
    job_configs=job_configs,
    virtual_cluster_id="your-virtual-cluster-id",
    execution_role_arn="arn:aws:iam::your-account:role/EMRContainers-JobExecutionRole"
)

# Save results
with open('migration-results.json', 'w') as f:
    json.dump(results, f, indent=2)

print(f"Batch migration completed. Results saved to migration-results.json")
```

## Phase 4: Data Validation

### 4.1 Data Consistency Validation

```python
# data_consistency_validator.py
import pandas as pd
import numpy as np
import boto3
import s3fs
from datetime import datetime

class DataConsistencyValidator:
    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket
        self.s3_fs = s3fs.S3FileSystem()
        self.s3_client = boto3.client('s3')
    
    def compare_datasets(self, source_path, target_path, sample_size=10000):
        """Compare source and target datasets for consistency"""
        
        print(f"Comparing datasets:")
        print(f"Source: {source_path}")
        print(f"Target: {target_path}")
        
        # Load datasets
        source_df = pd.read_parquet(source_path, filesystem=self.s3_fs)
        target_df = pd.read_parquet(target_path, filesystem=self.s3_fs)
        
        # Sample for comparison if datasets are large
        if len(source_df) > sample_size:
            source_sample = source_df.sample(n=sample_size, random_state=42)
            target_sample = target_df.sample(n=sample_size, random_state=42)
        else:
            source_sample = source_df
            target_sample = target_df
        
        comparison_results = {
            'timestamp': datetime.now().isoformat(),
            'source_path': source_path,
            'target_path': target_path,
            'source_rows': len(source_df),
            'target_rows': len(target_df),
            'source_columns': list(source_df.columns),
            'target_columns': list(target_df.columns),
            'schema_match': list(source_df.columns) == list(target_df.columns),
            'row_count_match': len(source_df) == len(target_df)
        }
        
        # Compare schemas
        if not comparison_results['schema_match']:
            missing_in_target = set(source_df.columns) - set(target_df.columns)
            extra_in_target = set(target_df.columns) - set(source_df.columns)
            
            comparison_results['missing_columns'] = list(missing_in_target)
            comparison_results['extra_columns'] = list(extra_in_target)
        
        # Compare data types
        common_columns = set(source_df.columns) & set(target_df.columns)
        dtype_mismatches = []
        
        for col in common_columns:
            if source_df[col].dtype != target_df[col].dtype:
                dtype_mismatches.append({
                    'column': col,
                    'source_dtype': str(source_df[col].dtype),
                    'target_dtype': str(target_df[col].dtype)
                })
        
        comparison_results['dtype_mismatches'] = dtype_mismatches
        
        # Statistical comparison for numerical columns
        numerical_comparisons = {}
        for col in common_columns:
            if pd.api.types.is_numeric_dtype(source_df[col]) and pd.api.types.is_numeric_dtype(target_df[col]):
                source_stats = source_sample[col].describe()
                target_stats = target_sample[col].describe()
                
                numerical_comparisons[col] = {
                    'source_mean': source_stats['mean'],
                    'target_mean': target_stats['mean'],
                    'mean_diff_pct': abs(source_stats['mean'] - target_stats['mean']) / source_stats['mean'] * 100 if source_stats['mean'] != 0 else 0,
                    'source_std': source_stats['std'],
                    'target_std': target_stats['std'],
                    'std_diff_pct': abs(source_stats['std'] - target_stats['std']) / source_stats['std'] * 100 if source_stats['std'] != 0 else 0
                }
        
        comparison_results['numerical_comparisons'] = numerical_comparisons
        
        # Overall assessment
        issues = []
        if not comparison_results['schema_match']:
            issues.append("Schema mismatch")
        if not comparison_results['row_count_match']:
            issues.append("Row count mismatch")
        if dtype_mismatches:
            issues.append("Data type mismatches")
        
        # Check for significant statistical differences
        for col, stats in numerical_comparisons.items():
            if stats['mean_diff_pct'] > 1.0:  # More than 1% difference
                issues.append(f"Significant mean difference in {col}: {stats['mean_diff_pct']:.2f}%")
        
        comparison_results['issues'] = issues
        comparison_results['validation_passed'] = len(issues) == 0
        
        return comparison_results
    
    def validate_feature_engineering(self, input_path, output_path):
        """Validate feature engineering results"""
        
        input_df = pd.read_parquet(input_path, filesystem=self.s3_fs)
        output_df = pd.read_parquet(output_path, filesystem=self.s3_fs)
        
        validation_results = {
            'timestamp': datetime.now().isoformat(),
            'input_rows': len(input_df),
            'output_rows': len(output_df),
            'feature_count': len(output_df.columns) - len(input_df.columns),
            'new_features': list(set(output_df.columns) - set(input_df.columns))
        }
        
        # Validate feature ranges and distributions
        feature_validations = {}
        for feature in validation_results['new_features']:
            if pd.api.types.is_numeric_dtype(output_df[feature]):
                feature_stats = output_df[feature].describe()
                feature_validations[feature] = {
                    'min': feature_stats['min'],
                    'max': feature_stats['max'],
                    'mean': feature_stats['mean'],
                    'null_count': output_df[feature].isnull().sum(),
                    'null_percentage': output_df[feature].isnull().sum() / len(output_df) * 100
                }
        
        validation_results['feature_validations'] = feature_validations
        
        return validation_results

# Run validation
validator = DataConsistencyValidator("your-data-bucket")

# Compare EMR vs EMR on EKS outputs
comparison_result = validator.compare_datasets(
    source_path="s3://your-bucket/emr-output/features/",
    target_path="s3://your-bucket/emr-eks-output/features/"
)

print(f"Validation passed: {comparison_result['validation_passed']}")
if comparison_result['issues']:
    print("Issues found:")
    for issue in comparison_result['issues']:
        print(f"  - {issue}")

# Save validation results
with open('validation-results.json', 'w') as f:
    json.dump(comparison_result, f, indent=2, default=str)
```

### 4.2 Performance Comparison

```python
# performance_comparison.py
import boto3
import json
from datetime import datetime, timedelta

def compare_job_performance(emr_job_id, emr_eks_job_run_id, virtual_cluster_id):
    """Compare performance between EMR and EMR on EKS jobs"""
    
    emr_client = boto3.client('emr')
    emr_containers_client = boto3.client('emr-containers')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get EMR job details
    emr_steps = emr_client.list_steps(ClusterId=emr_job_id)
    emr_step = emr_steps['Steps'][0]  # Assuming first step
    
    emr_start_time = emr_step['Status']['Timeline']['StartDateTime']
    emr_end_time = emr_step['Status']['Timeline']['EndDateTime']
    emr_duration = (emr_end_time - emr_start_time).total_seconds()
    
    # Get EMR on EKS job details
    eks_job = emr_containers_client.describe_job_run(
        virtualClusterId=virtual_cluster_id,
        id=emr_eks_job_run_id
    )
    
    eks_start_time = eks_job['jobRun']['createdAt']
    eks_end_time = eks_job['jobRun']['finishedAt']
    eks_duration = (eks_end_time - eks_start_time).total_seconds()
    
    # Get resource utilization metrics from CloudWatch
    def get_cloudwatch_metrics(namespace, metric_name, dimensions, start_time, end_time):
        response = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5 minutes
            Statistics=['Average', 'Maximum']
        )
        return response['Datapoints']
    
    performance_comparison = {
        'timestamp': datetime.now().isoformat(),
        'emr_job_id': emr_job_id,
        'emr_eks_job_run_id': emr_eks_job_run_id,
        'emr_duration_seconds': emr_duration,
        'emr_eks_duration_seconds': eks_duration,
        'performance_improvement_pct': (emr_duration - eks_duration) / emr_duration * 100,
        'emr_start_time': emr_start_time.isoformat(),
        'emr_end_time': emr_end_time.isoformat(),
        'emr_eks_start_time': eks_start_time.isoformat(),
        'emr_eks_end_time': eks_end_time.isoformat()
    }
    
    return performance_comparison

# Example usage
performance_result = compare_job_performance(
    emr_job_id="j-1234567890abcdef0",
    emr_eks_job_run_id="your-job-run-id",
    virtual_cluster_id="your-virtual-cluster-id"
)

print(f"Performance improvement: {performance_result['performance_improvement_pct']:.2f}%")
```

## Phase 5: Production Cutover

### 5.1 Gradual Migration Strategy

Implement a gradual cutover approach:

1. **Parallel Running**: Run both EMR and EMR on EKS jobs in parallel
2. **Traffic Splitting**: Gradually shift workloads to EMR on EKS
3. **Monitoring**: Continuously monitor performance and data quality
4. **Rollback Plan**: Maintain ability to quickly rollback if issues arise

```python
# gradual_cutover.py
import boto3
import json
import random
from datetime import datetime

class GradualCutoverManager:
    def __init__(self, emr_cluster_id, virtual_cluster_id, execution_role_arn):
        self.emr_cluster_id = emr_cluster_id
        self.virtual_cluster_id = virtual_cluster_id
        self.execution_role_arn = execution_role_arn
        self.emr_client = boto3.client('emr')
        self.emr_containers_client = boto3.client('emr-containers')
    
    def route_job(self, job_config, cutover_percentage=0):
        """Route job to EMR or EMR on EKS based on cutover percentage"""
        
        # Determine routing based on percentage
        use_eks = random.randint(1, 100) <= cutover_percentage
        
        if use_eks:
            return self.submit_emr_eks_job(job_config)
        else:
            return self.submit_emr_job(job_config)
    
    def submit_emr_job(self, job_config):
        """Submit job to traditional EMR"""
        
        response = self.emr_client.add_job_flow_steps(
            JobFlowId=self.emr_cluster_id,
            Steps=[job_config['emr_step']]
        )
        
        return {
            'platform': 'emr',
            'job_id': response['StepIds'][0],
            'cluster_id': self.emr_cluster_id
        }
    
    def submit_emr_eks_job(self, job_config):
        """Submit job to EMR on EKS"""
        
        response = self.emr_containers_client.start_job_run(
            virtualClusterId=self.virtual_cluster_id,
            name=job_config['name'],
            executionRoleArn=self.execution_role_arn,
            releaseLabel=job_config['releaseLabel'],
            jobDriver=job_config['jobDriver'],
            configurationOverrides=job_config.get('configurationOverrides', {})
        )
        
        return {
            'platform': 'emr-eks',
            'job_run_id': response['id'],
            'virtual_cluster_id': self.virtual_cluster_id
        }

# Cutover schedule
cutover_schedule = [
    {'week': 1, 'percentage': 10},   # 10% to EMR on EKS
    {'week': 2, 'percentage': 25},   # 25% to EMR on EKS
    {'week': 3, 'percentage': 50},   # 50% to EMR on EKS
    {'week': 4, 'percentage': 75},   # 75% to EMR on EKS
    {'week': 5, 'percentage': 100}   # 100% to EMR on EKS
]

# Initialize cutover manager
cutover_manager = GradualCutoverManager(
    emr_cluster_id="j-1234567890abcdef0",
    virtual_cluster_id="your-virtual-cluster-id",
    execution_role_arn="arn:aws:iam::your-account:role/EMRContainers-JobExecutionRole"
)

# Example job routing
job_config = {
    'name': 'fraud-detection-feature-engineering',
    'releaseLabel': 'emr-6.15.0-latest',
    'jobDriver': {
        'sparkSubmitJobDriver': {
            'entryPoint': 's3://your-bucket/scripts/fraud_detection_feature_engineering.py'
        }
    }
}

# Route job based on current cutover percentage
current_week = 2  # Example: week 2 of cutover
cutover_percentage = cutover_schedule[current_week - 1]['percentage']

job_result = cutover_manager.route_job(job_config, cutover_percentage)
print(f"Job routed to: {job_result['platform']}")
```

### 5.2 Monitoring During Cutover

```python
# cutover_monitoring.py
import boto3
import json
import time
from datetime import datetime, timedelta

class CutoverMonitor:
    def __init__(self):
        self.cloudwatch = boto3.client('cloudwatch')
        self.emr_client = boto3.client('emr')
        self.emr_containers_client = boto3.client('emr-containers')
    
    def monitor_job_success_rates(self, time_window_hours=24):
        """Monitor job success rates for both platforms"""
        
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=time_window_hours)
        
        # Get EMR job success rate
        emr_success_rate = self.get_emr_success_rate(start_time, end_time)
        
        # Get EMR on EKS job success rate
        eks_success_rate = self.get_emr_eks_success_rate(start_time, end_time)
        
        monitoring_report = {
            'timestamp': datetime.now().isoformat(),
            'time_window_hours': time_window_hours,
            'emr_success_rate': emr_success_rate,
            'emr_eks_success_rate': eks_success_rate,
            'success_rate_difference': eks_success_rate - emr_success_rate
        }
        
        # Alert if success rate drops significantly
        if eks_success_rate < emr_success_rate - 5:  # 5% threshold
            monitoring_report['alert'] = f"EMR on EKS success rate ({eks_success_rate:.1f}%) is significantly lower than EMR ({emr_success_rate:.1f}%)"
        
        return monitoring_report
    
    def get_emr_success_rate(self, start_time, end_time):
        """Calculate EMR job success rate"""
        # Implementation to calculate EMR success rate
        # This would query CloudWatch metrics or EMR API
        return 95.0  # Placeholder
    
    def get_emr_eks_success_rate(self, start_time, end_time):
        """Calculate EMR on EKS job success rate"""
        # Implementation to calculate EMR on EKS success rate
        # This would query CloudWatch metrics or EMR Containers API
        return 97.0  # Placeholder
    
    def check_data_quality_metrics(self):
        """Check data quality metrics during cutover"""
        
        # Compare data quality metrics between platforms
        quality_metrics = {
            'timestamp': datetime.now().isoformat(),
            'emr_data_quality_score': 98.5,
            'emr_eks_data_quality_score': 98.7,
            'quality_improvement': 0.2
        }
        
        return quality_metrics

# Run monitoring
monitor = CutoverMonitor()
success_rate_report = monitor.monitor_job_success_rates()
quality_report = monitor.check_data_quality_metrics()

print(f"Success rate monitoring: {success_rate_report}")
print(f"Data quality monitoring: {quality_report}")
```

## Phase 6: Post-Migration Optimization

### 6.1 Performance Tuning

After successful migration, optimize performance:

```python
# performance_tuning.py
import boto3
import json

def optimize_spark_configuration(job_config, optimization_profile="gpu_optimized"):
    """Optimize Spark configuration for EMR on EKS"""
    
    optimization_profiles = {
        "gpu_optimized": {
            "spark.plugins": "com.nvidia.spark.SQLPlugin",
            "spark.rapids.sql.enabled": "true",
            "spark.executor.resource.gpu.amount": "1",
            "spark.task.resource.gpu.amount": "0.25",
            "spark.rapids.memory.pinnedPool.size": "2G",
            "spark.executor.memory": "30G",
            "spark.executor.cores": "4",
            "spark.sql.adaptive.enabled": "true",
            "spark.sql.adaptive.coalescePartitions.enabled": "true",
            "spark.sql.adaptive.skewJoin.enabled": "true",
            "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
        },
        "memory_optimized": {
            "spark.executor.memory": "50G",
            "spark.executor.cores": "8",
            "spark.executor.memoryFraction": "0.8",
            "spark.sql.shuffle.partitions": "800",
            "spark.sql.adaptive.enabled": "true",
            "spark.sql.adaptive.coalescePartitions.enabled": "true"
        },
        "compute_optimized": {
            "spark.executor.cores": "16",
            "spark.executor.memory": "20G",
            "spark.sql.shuffle.partitions": "1600",
            "spark.sql.adaptive.enabled": "true",
            "spark.dynamicAllocation.enabled": "true",
            "spark.dynamicAllocation.minExecutors": "2",
            "spark.dynamicAllocation.maxExecutors": "20"
        }
    }
    
    # Apply optimization profile
    optimized_config = job_config.copy()
    
    if 'configurationOverrides' not in optimized_config:
        optimized_config['configurationOverrides'] = {}
    
    if 'applicationConfiguration' not in optimized_config['configurationOverrides']:
        optimized_config['configurationOverrides']['applicationConfiguration'] = []
    
    # Add optimized Spark configuration
    spark_config = {
        'classification': 'spark-defaults',
        'properties': optimization_profiles[optimization_profile]
    }
    
    optimized_config['configurationOverrides']['applicationConfiguration'].append(spark_config)
    
    return optimized_config

# Example usage
base_job_config = {
    'name': 'fraud-detection-optimized',
    'releaseLabel': 'emr-6.15.0-latest',
    'jobDriver': {
        'sparkSubmitJobDriver': {
            'entryPoint': 's3://your-bucket/scripts/fraud_detection_feature_engineering.py'
        }
    }
}

optimized_config = optimize_spark_configuration(base_job_config, "gpu_optimized")
print(json.dumps(optimized_config, indent=2))
```

### 6.2 Cost Optimization

```python
# cost_optimization.py
import boto3
from datetime import datetime, timedelta

def analyze_cost_savings(emr_cluster_id, virtual_cluster_id, days=30):
    """Analyze cost savings from EMR to EMR on EKS migration"""
    
    ce_client = boto3.client('ce')
    
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=days)
    
    # Get EMR costs
    emr_cost_response = ce_client.get_cost_and_usage(
        TimePeriod={
            'Start': start_date.strftime('%Y-%m-%d'),
            'End': end_date.strftime('%Y-%m-%d')
        },
        Granularity='DAILY',
        Metrics=['BlendedCost'],
        GroupBy=[
            {
                'Type': 'DIMENSION',
                'Key': 'SERVICE'
            }
        ],
        Filter={
            'Dimensions': {
                'Key': 'SERVICE',
                'Values': ['Amazon Elastic MapReduce']
            }
        }
    )
    
    # Get EKS costs
    eks_cost_response = ce_client.get_cost_and_usage(
        TimePeriod={
            'Start': start_date.strftime('%Y-%m-%d'),
            'End': end_date.strftime('%Y-%m-%d')
        },
        Granularity='DAILY',
        Metrics=['BlendedCost'],
        GroupBy=[
            {
                'Type': 'DIMENSION',
                'Key': 'SERVICE'
            }
        ],
        Filter={
            'Dimensions': {
                'Key': 'SERVICE',
                'Values': ['Amazon Elastic Kubernetes Service']
            }
        }
    )
    
    # Calculate total costs
    emr_total_cost = sum(
        float(day['Total']['BlendedCost']['Amount'])
        for result in emr_cost_response['ResultsByTime']
        for day in result['Groups']
    )
    
    eks_total_cost = sum(
        float(day['Total']['BlendedCost']['Amount'])
        for result in eks_cost_response['ResultsByTime']
        for day in result['Groups']
    )
    
    cost_analysis = {
        'analysis_period_days': days,
        'emr_total_cost': emr_total_cost,
        'eks_total_cost': eks_total_cost,
        'cost_savings': emr_total_cost - eks_total_cost,
        'cost_savings_percentage': (emr_total_cost - eks_total_cost) / emr_total_cost * 100 if emr_total_cost > 0 else 0,
        'monthly_projected_savings': (emr_total_cost - eks_total_cost) * (30 / days)
    }
    
    return cost_analysis

# Analyze cost savings
cost_analysis = analyze_cost_savings(
    emr_cluster_id="j-1234567890abcdef0",
    virtual_cluster_id="your-virtual-cluster-id",
    days=30
)

print(f"Cost Analysis Results:")
print(f"EMR Cost (30 days): ${cost_analysis['emr_total_cost']:.2f}")
print(f"EKS Cost (30 days): ${cost_analysis['eks_total_cost']:.2f}")
print(f"Cost Savings: ${cost_analysis['cost_savings']:.2f} ({cost_analysis['cost_savings_percentage']:.1f}%)")
print(f"Projected Monthly Savings: ${cost_analysis['monthly_projected_savings']:.2f}")
```

## Troubleshooting Common Issues

### Issue 1: Job Failures Due to Resource Constraints

**Symptoms**: Jobs fail with out-of-memory errors or resource allocation failures

**Solution**:
```bash
# Check node capacity
kubectl describe nodes

# Check resource requests vs limits
kubectl get pods -n ml-team-a -o yaml | grep -A 5 resources

# Adjust Karpenter provisioner
kubectl patch provisioner default --type='merge' -p='{"spec":{"requirements":[{"key":"node.kubernetes.io/instance-type","operator":"In","values":["m5.2xlarge","m5.4xlarge","g5.2xlarge","g5.4xlarge"]}]}}'
```

### Issue 2: RAPIDS Not Working

**Symptoms**: Jobs run but don't show GPU acceleration

**Solution**:
```bash
# Check GPU availability
kubectl get nodes -l node.kubernetes.io/instance-type=g5.2xlarge
kubectl describe node <gpu-node> | grep nvidia.com/gpu

# Verify NVIDIA device plugin
kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system

# Check Spark configuration
kubectl logs <spark-driver-pod> -n ml-team-a | grep -i rapids
```

### Issue 3: Data Inconsistency

**Symptoms**: Output data differs between EMR and EMR on EKS

**Solution**:
```python
# Run detailed data validation
python migration/scripts/validation/validate-migration.py \
    --config validation-config.json \
    --output detailed-validation-report.json

# Check for floating-point precision differences
# Review datetime handling and timezone settings
# Verify sort order consistency
```

## Best Practices

1. **Incremental Migration**: Migrate jobs incrementally, starting with non-critical workloads
2. **Parallel Validation**: Run both platforms in parallel during transition period
3. **Comprehensive Testing**: Test with production-like data volumes and patterns
4. **Performance Monitoring**: Continuously monitor performance metrics during and after migration
5. **Rollback Planning**: Maintain ability to quickly rollback to EMR if issues arise
6. **Documentation**: Keep detailed documentation of all changes and configurations
7. **Team Training**: Ensure team is trained on new EKS-based workflows

## Support and Resources

- **AWS Documentation**: [EMR on EKS User Guide](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/)
- **RAPIDS Documentation**: [RAPIDS on Spark](https://rapids.ai/spark.html)
- **Internal Support**: See [Troubleshooting Runbook](../runbooks/troubleshooting-runbook.md)
- **Migration Scripts**: Available in `migration/scripts/` directory