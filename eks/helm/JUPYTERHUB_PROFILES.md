# JupyterHub Profiles for Fraud Detection

This document describes the different JupyterHub profiles available for the fraud detection demo on EKS.

## Overview

The JupyterHub deployment provides three specialized profiles, each optimized for different phases of the fraud detection pipeline:

1. **Data Processing** - EMR on EKS with Spark RAPIDS
2. **ML Training** - Ray cluster for distributed training  
3. **Unified** - Both Spark and Ray capabilities

## Profile Details

### 1. Data Processing Profile

**Purpose**: Feature engineering and data processing using EMR on EKS with Spark RAPIDS

**Container Image**: `fraud-detection/spark-notebook:latest`

**Resources**:
- CPU: 4 cores (2 guaranteed)
- Memory: 8GB (4GB guaranteed)
- Storage: Ephemeral (for demo)

**Environment Variables**:
- `VIRTUAL_CLUSTER_ID`: EMR on EKS virtual cluster ID
- `EMR_EXECUTION_ROLE_ARN`: IAM role for EMR job execution
- `AWS_REGION`: AWS region
- `S3_BUCKET_NAME`: S3 bucket for data storage
- `SPARK_DRIVER_MEMORY`: 4g
- `SPARK_EXECUTOR_MEMORY`: 4g

**Use Cases**:
- Running the fraud detection feature engineering notebook
- Submitting EMR on EKS Spark jobs with RAPIDS acceleration
- Interactive data exploration with GPU acceleration
- Processing large datasets from S3

**Sample Code**:
```python
# Connect to EMR on EKS
from emr_eks_utils import EMROnEKSClient, create_spark_session_for_emr_eks

# Option 1: Submit EMR job
emr_client = EMROnEKSClient()
job_id = emr_client.submit_spark_job(
    job_name="fraud-feature-engineering",
    entry_point="s3://fraud-detection-code/feature_engineering.py"
)

# Option 2: Interactive Spark session
spark = create_spark_session_for_emr_eks()
df = spark.read.parquet("s3://fraud-data/transactions/")
```

### 2. ML Training Profile

**Purpose**: Distributed machine learning training using Ray on EKS

**Container Image**: `fraud-detection/ray-notebook:latest`

**Resources**:
- CPU: 8 cores (4 guaranteed)
- Memory: 16GB (8GB guaranteed)
- Storage: Ephemeral (for demo)

**Environment Variables**:
- `RAY_ADDRESS`: Ray cluster head service address
- `AWS_REGION`: AWS region
- `S3_BUCKET_NAME`: S3 bucket for data and model storage

**Use Cases**:
- Distributed XGBoost training with Ray Train
- Hyperparameter tuning with Ray Tune
- Model evaluation and validation
- Connecting to Ray cluster for distributed computing

**Sample Code**:
```python
# Connect to Ray cluster
from ray_utils import RayClusterClient, FraudDetectionTrainer

ray_client = RayClusterClient()
ray_client.connect()

# Distributed training
trainer = FraudDetectionTrainer(ray_client)
train_dataset, val_dataset = trainer.prepare_data("s3://fraud-data/processed/")
result = trainer.train_model(train_dataset, val_dataset, num_workers=4, use_gpu=True)
```

### 3. Unified Profile

**Purpose**: Complete fraud detection pipeline with both Spark and Ray capabilities

**Container Image**: `fraud-detection/unified-notebook:latest`

**Resources**:
- CPU: 8 cores (4 guaranteed)
- Memory: 32GB (16GB guaranteed)
- Storage: Ephemeral (for demo)

**Environment Variables**:
- `VIRTUAL_CLUSTER_ID`: EMR on EKS virtual cluster ID
- `EMR_EXECUTION_ROLE_ARN`: IAM role for EMR job execution
- `RAY_ADDRESS`: Ray cluster head service address
- `AWS_REGION`: AWS region
- `S3_BUCKET_NAME`: S3 bucket for data storage

**Use Cases**:
- End-to-end fraud detection pipeline
- Switching between Spark and Ray in the same notebook
- Demonstrating unified data science workflow
- Development and prototyping

**Sample Code**:
```python
# Unified workflow example
from emr_eks_utils import EMROnEKSClient
from ray_utils import FraudDetectionTrainer

# Step 1: Feature engineering with Spark
emr_client = EMROnEKSClient()
feature_job = emr_client.submit_spark_job(
    job_name="fraud-features",
    entry_point="s3://fraud-code/feature_engineering.py"
)
emr_client.wait_for_job_completion(feature_job)

# Step 2: Training with Ray
trainer = FraudDetectionTrainer()
train_data, val_data = trainer.prepare_data("s3://fraud-data/processed/")
model_result = trainer.train_model(train_data, val_data)

# Step 3: Save model for inference
model_path = trainer.save_model("s3://fraud-models/latest/")
```

## Profile Selection Guide

| Use Case | Recommended Profile | Reason |
|----------|-------------------|---------|
| Feature Engineering | Data Processing | Optimized for Spark RAPIDS, EMR on EKS integration |
| Model Training | ML Training | Ray cluster connectivity, distributed training |
| Hyperparameter Tuning | ML Training | Ray Tune integration, scalable compute |
| End-to-End Pipeline | Unified | Both Spark and Ray, complete workflow |
| Development/Testing | Unified | Flexibility to use either framework |
| Production Jobs | Data Processing | Dedicated EMR on EKS for production workloads |

## Resource Management

### CPU and Memory Allocation

Each profile has different resource allocations based on typical workload requirements:

- **Data Processing**: Moderate resources for Spark driver, executors run on EMR
- **ML Training**: Higher resources for distributed training coordination
- **Unified**: Highest resources to support both frameworks

### Storage Considerations

- **Ephemeral Storage**: Used for demo to avoid persistent volume complexity
- **S3 Integration**: All profiles have S3 access via IRSA
- **Shared Storage**: Consider adding shared PVC for production use

### Network Policies

All profiles include network policies that:
- Allow ingress from JupyterHub namespace
- Allow egress to all destinations (S3, EMR, Ray)
- Can be restricted further for production security

## Environment Configuration

### Required Terraform Outputs

The profiles require these Terraform outputs to be properly configured:

```bash
# Extract from Terraform
VIRTUAL_CLUSTER_ID=$(terraform output -raw emr_virtual_cluster_id)
EMR_EXECUTION_ROLE_ARN=$(terraform output -raw emr_execution_role_arn)
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
ECR_REGISTRY=$(terraform output -raw ecr_registry)
```

### Service Account Configuration

All profiles use the `jupyterhub-user-sa` service account with IRSA annotations:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jupyterhub-user-sa
  namespace: jupyterhub
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/JupyterHub-S3-Access-Role
```

## Troubleshooting

### Common Issues

1. **Image Pull Errors**
   - Ensure custom images are built and pushed to ECR
   - Check ECR repository permissions
   - Verify image tags in values file

2. **Environment Variable Issues**
   - Run `configure-jupyterhub.sh` to populate values from Terraform
   - Check for placeholder values in `jupyterhub-values.yaml`
   - Verify Terraform outputs are available

3. **Resource Constraints**
   - Check node capacity and resource requests
   - Adjust resource limits if needed
   - Monitor cluster autoscaling

4. **Network Connectivity**
   - Verify EMR on EKS virtual cluster is accessible
   - Check Ray cluster service endpoints
   - Validate S3 bucket permissions

### Validation Commands

```bash
# Validate profile configuration
./eks/helm/scripts/validate-jupyterhub-profiles.sh

# Check JupyterHub status
kubectl get pods -n jupyterhub

# Test image availability
docker manifest inspect fraud-detection/unified-notebook:latest

# Verify service account
kubectl describe sa jupyterhub-user-sa -n jupyterhub
```

## Next Steps

1. **Build Images**: Run `./eks/docker/build-images.sh` to build custom images
2. **Configure Values**: Run `./eks/helm/scripts/configure-jupyterhub.sh` to populate configuration
3. **Deploy JupyterHub**: Run `./eks/helm/scripts/deploy-jupyterhub.sh` to deploy
4. **Test Profiles**: Access JupyterHub and test each profile with sample notebooks
5. **Monitor Usage**: Set up monitoring for resource usage and performance