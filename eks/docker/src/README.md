# EMR on EKS Job Submission Utilities

This directory contains utilities and scripts for submitting and managing fraud detection jobs on EMR on EKS.

## Files Overview

### Utilities
- `emr_eks_utils.py` - Main utility module for EMR on EKS job management
- `ray_utils.py` - Ray cluster utilities (existing)

### Job Scripts
- `feature_engineering.py` - Standalone feature engineering script for EMR on EKS
- `xgboost_training.py` - XGBoost training script using Spark MLlib
- `batch_inference.py` - Batch inference script for fraud prediction

### Notebooks
- `../notebooks/emr_job_submission_demo.ipynb` - Demo notebook showing how to use the utilities
- `../notebooks/01_fraud_detection_feature_engineering_emr_eks.ipynb` - Updated feature engineering notebook

## Quick Start

### 1. Environment Setup

Ensure these environment variables are set in your JupyterHub environment:

```bash
export VIRTUAL_CLUSTER_ID="your-emr-virtual-cluster-id"
export EMR_EXECUTION_ROLE_ARN="arn:aws:iam::account:role/EMRContainers-JobExecutionRole"
export AWS_DEFAULT_REGION="us-west-2"
export S3_BUCKET="your-s3-bucket"
```

### 2. Basic Usage

```python
from emr_eks_utils import create_job_manager, quick_submit_feature_engineering

# Create job manager
job_manager = create_job_manager()

# Submit feature engineering job
job_id = quick_submit_feature_engineering()
print(f"Job submitted: {job_id}")

# Monitor job
from emr_eks_utils import print_job_status
print_job_status(job_id)
```

### 3. Advanced Usage

```python
# Submit job with custom configuration
custom_configs = {
    'spark.executor.instances': '8',
    'spark.sql.shuffle.partitions': '15000'
}

job_id = job_manager.submit_feature_engineering_job(
    output_path="s3://my-bucket/custom-output/",
    custom_configs=custom_configs
)

# Wait for completion
final_status = job_manager.wait_for_job_completion(job_id)
```

## Job Templates

The utility provides three pre-configured job templates:

### Feature Engineering
- **Purpose**: Process raw fraud detection data and create features
- **Resources**: 12 executors, 30G memory each, 1 GPU per executor
- **RAPIDS**: Enabled for GPU acceleration
- **Script**: `feature_engineering.py`

### Training
- **Purpose**: Train XGBoost model on processed features
- **Resources**: 8 executors, 30G memory each, 1 GPU per executor
- **RAPIDS**: Enabled for GPU acceleration
- **Script**: `xgboost_training.py`

### Inference
- **Purpose**: Batch inference on new transaction data
- **Resources**: 4 executors, 20G memory each, 1 GPU per executor
- **RAPIDS**: Enabled for GPU acceleration
- **Script**: `batch_inference.py`

## EMR on EKS Job Scripts

### feature_engineering.py

Performs the same feature engineering as the original notebook but as a standalone EMR job.

**Usage:**
```bash
spark-submit \
  --conf spark.rapids.sql.enabled=true \
  --conf spark.plugins=com.nvidia.spark.SQLPlugin \
  feature_engineering.py \
  --output-path s3://bucket/processed-features/
```

**Key Features:**
- Kubernetes-aware Spark configuration
- RAPIDS GPU acceleration
- Same business logic as original notebook
- Optimized for EMR on EKS environment

### xgboost_training.py

Trains XGBoost model using Spark MLlib with GPU acceleration.

**Usage:**
```bash
spark-submit \
  --conf spark.rapids.sql.enabled=true \
  xgboost_training.py \
  --features-path s3://bucket/processed-features/ \
  --model-output-path s3://bucket/models/xgboost/
```

**Key Features:**
- Spark MLlib GBT Classifier (XGBoost equivalent)
- GPU acceleration via RAPIDS
- Model evaluation and metrics
- S3 model storage

### batch_inference.py

Performs batch inference using trained models.

**Usage:**
```bash
spark-submit \
  --conf spark.rapids.sql.enabled=true \
  batch_inference.py \
  --model-path s3://bucket/models/xgboost/ \
  --input-data-path s3://bucket/new-transactions/ \
  --predictions-output-path s3://bucket/predictions/
```

**Key Features:**
- Load trained models from S3
- Batch prediction on new data
- Risk level classification
- Prediction statistics and summaries

## EMROnEKSJobManager Class

The main utility class provides comprehensive job management capabilities:

### Core Methods

```python
# Job submission
job_id = job_manager.submit_job(job_type, entry_point, **kwargs)

# Job monitoring
status = job_manager.get_job_status(job_id)
final_status = job_manager.wait_for_job_completion(job_id)

# Job management
jobs = job_manager.list_jobs(states=['RUNNING'])
success = job_manager.cancel_job(job_id)
```

### Convenience Methods

```python
# Quick job submission
fe_job_id = job_manager.submit_feature_engineering_job()
train_job_id = job_manager.submit_training_job()
infer_job_id = job_manager.submit_inference_job()
```

### Configuration

Jobs can be customized with:
- Custom Spark configurations
- Resource allocation (memory, CPU, GPU)
- Input/output paths
- Job tags for tracking

## Monitoring and Troubleshooting

### Job Status Monitoring

```python
# Get current status
status = job_manager.get_job_status(job_id)
print(f"Job state: {status['state']}")

# Get logs information
logs = job_manager.get_job_logs(job_id)
print(f"CloudWatch logs: {logs['console_url']}")
```

### Common Job States

- `PENDING` - Job is queued
- `RUNNING` - Job is executing
- `COMPLETED` - Job finished successfully
- `FAILED` - Job failed (check logs)
- `CANCELLED` - Job was cancelled

### Troubleshooting

1. **Job fails to start**: Check EMR execution role permissions
2. **Out of resources**: Adjust executor count or memory settings
3. **Data access issues**: Verify S3 bucket permissions
4. **GPU issues**: Check node availability and GPU configurations

### Useful Commands

```bash
# List EMR jobs
aws emr-containers list-job-runs --virtual-cluster-id $VIRTUAL_CLUSTER_ID

# Describe specific job
aws emr-containers describe-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID --id $JOB_ID

# Check Kubernetes pods
kubectl get pods -n emr-fraud-detection

# View pod logs
kubectl logs -n emr-fraud-detection <pod-name>
```

## Integration with Notebooks

The utilities are designed to work seamlessly with JupyterHub notebooks:

1. **Development**: Use notebooks for interactive development and testing
2. **Production**: Submit jobs via utilities for production workloads
3. **Monitoring**: Use notebook cells to monitor job progress
4. **Results**: Load job results back into notebooks for analysis

## Best Practices

1. **Resource Management**: Start with smaller resource allocations and scale up as needed
2. **Data Partitioning**: Ensure input data is properly partitioned for optimal performance
3. **Error Handling**: Always check job status and handle failures gracefully
4. **Cost Optimization**: Use spot instances and appropriate instance types
5. **Monitoring**: Set up CloudWatch alarms for job failures
6. **Testing**: Test jobs with small datasets before running on full data

## Requirements Addressed

This implementation addresses the following requirements from the specification:

- **2.1**: EMR on EKS job submission with RAPIDS acceleration
- **2.2**: Same S3 data sources and processing logic as original notebooks
- **Job Templates**: Different types of EMR jobs (feature engineering, training, inference)
- **Monitoring**: Job status checking and progress monitoring capabilities
- **Integration**: Helper functions for use from JupyterHub notebooks

## Next Steps

1. Test the utilities with your EMR on EKS cluster
2. Customize job templates for your specific requirements
3. Integrate with your CI/CD pipeline for automated job submission
4. Set up monitoring and alerting for production workloads
5. Extend with additional job types as needed