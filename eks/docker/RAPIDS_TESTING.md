# RAPIDS Testing Guide for EMR on EKS

This guide explains how to test RAPIDS GPU acceleration on EMR on EKS for fraud detection workloads.

## Overview

RAPIDS is a suite of open-source software libraries that accelerates data science and analytics pipelines on GPUs. This testing framework validates RAPIDS functionality on EMR on EKS.

## Prerequisites

### Infrastructure Requirements
- EKS cluster with GPU nodes (p3, p4, g4, or g5 instances)
- EMR on EKS virtual cluster configured
- S3 bucket for data storage
- Proper IAM roles and permissions

### Software Requirements
- AWS CLI configured
- Docker (for building custom images)
- Python 3.7+ with boto3
- kubectl access to EKS cluster

## Quick Start

### 1. Set Environment Variables

```bash
export VIRTUAL_CLUSTER_ID="your-emr-virtual-cluster-id"
export EMR_EXECUTION_ROLE_ARN="arn:aws:iam::account:role/EMRContainers-JobExecutionRole"
export AWS_DEFAULT_REGION="us-west-2"
export S3_BUCKET="your-fraud-detection-bucket"
```

### 2. Run Basic Tests

```bash
# Test without custom RAPIDS image (will likely fail but validates setup)
python3 test_rapids.py --skip-basic

# Build RAPIDS image and test
python3 test_rapids.py --build-image

# Test with existing RAPIDS image
python3 test_rapids.py --custom-image your-account.dkr.ecr.region.amazonaws.com/fraud-detection/emr-rapids:latest
```

## Test Components

### 1. RAPIDS Docker Image

**File:** `Dockerfile.rapids`

Creates a custom EMR image with:
- RAPIDS libraries (cuDF, cuML, cuGraph)
- RAPIDS Spark plugin
- GPU-optimized configurations
- Fraud detection dependencies

**Build Command:**
```bash
./build-rapids-image.sh
```

### 2. RAPIDS Test Job

**File:** `src/rapids_test_job.py`

Comprehensive test that validates:
- RAPIDS plugin availability
- GPU DataFrame operations
- Fraud detection simulation
- S3 integration
- Performance benchmarks

### 3. Test Framework

**File:** `test_rapids.py`

Automated test framework that:
- Checks prerequisites
- Builds Docker images
- Submits test jobs
- Monitors execution
- Reports results

## Test Scenarios

### Scenario 1: Basic Setup Validation

Tests EMR on EKS setup without RAPIDS:

```bash
python3 test_rapids.py --skip-basic
```

**Expected Result:** Job submission works, but RAPIDS functionality fails

### Scenario 2: RAPIDS Image Build and Test

Builds custom RAPIDS image and tests:

```bash
python3 test_rapids.py --build-image
```

**Expected Result:** Image builds successfully, RAPIDS tests pass

### Scenario 3: Production Image Test

Tests with pre-built RAPIDS image:

```bash
python3 test_rapids.py --custom-image $ECR_URI
```

**Expected Result:** All RAPIDS functionality works correctly

## Understanding Test Results

### ✅ Success Indicators

- **RAPIDS Availability:** Plugin loads correctly
- **GPU Operations:** DataFrame operations use GPU
- **Performance:** Significant speedup vs CPU
- **S3 Integration:** Read/write operations work
- **Fraud Simulation:** Complex analytics complete

### ❌ Common Failures

1. **Plugin Not Found**
   - Error: `java.lang.ClassNotFoundException: com.nvidia.spark.SQLPlugin`
   - Solution: Use RAPIDS-enabled Docker image

2. **No GPU Resources**
   - Error: GPU resources not available
   - Solution: Ensure EKS cluster has GPU nodes

3. **Memory Issues**
   - Error: Out of GPU memory
   - Solution: Adjust GPU memory settings

4. **Permission Errors**
   - Error: Access denied
   - Solution: Check IAM role trust policy

## Performance Benchmarks

### Expected Improvements with RAPIDS

| Operation | CPU Time | GPU Time | Speedup |
|-----------|----------|----------|---------|
| DataFrame Aggregations | 30s | 5s | 6x |
| Complex Joins | 45s | 8s | 5.6x |
| Window Functions | 60s | 12s | 5x |
| Feature Engineering | 120s | 25s | 4.8x |

### Fraud Detection Specific

| Workload | Dataset Size | CPU Time | GPU Time | Speedup |
|----------|--------------|----------|----------|---------|
| Feature Engineering | 10M transactions | 15 min | 3 min | 5x |
| Anomaly Detection | 5M transactions | 8 min | 90s | 5.3x |
| Risk Scoring | 1M customers | 5 min | 60s | 5x |

## Troubleshooting

### GPU Node Issues

```bash
# Check GPU nodes
kubectl get nodes -l node.kubernetes.io/instance-type=g4dn.xlarge

# Check GPU resources
kubectl describe node <gpu-node-name>
```

### EMR Job Issues

```bash
# Check job status
aws emr-containers describe-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID --id $JOB_ID

# Check pod logs
kubectl logs -n emr-fraud-detection <pod-name>

# Check service accounts
kubectl get serviceaccounts -n emr-fraud-detection
```

### RAPIDS Issues

```bash
# Test RAPIDS in container
docker run --gpus all -it your-rapids-image python3 -c "import cudf; print('RAPIDS working')"

# Check GPU availability
nvidia-smi
```

## Production Deployment

### 1. Update Terraform Configuration

The updated `emr.tf` includes:
- Fixed IAM trust policy for Web Identity
- Multiple service accounts for driver/executor
- Proper RBAC permissions

### 2. Deploy Infrastructure

```bash
cd eks/terraform
terraform plan
terraform apply
```

### 3. Build and Deploy RAPIDS Image

```bash
cd eks/docker
./build-rapids-image.sh
```

### 4. Update Job Templates

```python
# Use RAPIDS-enabled image in job submissions
job_manager.submit_feature_engineering_job(
    custom_configs={
        'spark.kubernetes.container.image': 'your-account.dkr.ecr.region.amazonaws.com/fraud-detection/emr-rapids:latest'
    }
)
```

## Cost Optimization

### GPU Instance Selection

| Instance Type | vCPUs | GPU Memory | Cost/Hour | Best For |
|---------------|-------|------------|-----------|----------|
| g4dn.xlarge | 4 | 16GB | $0.526 | Development |
| g4dn.2xlarge | 8 | 16GB | $0.752 | Small workloads |
| g4dn.4xlarge | 16 | 16GB | $1.204 | Medium workloads |
| p3.2xlarge | 8 | 16GB | $3.06 | High performance |

### Optimization Tips

1. **Use Spot Instances:** 60-70% cost savings
2. **Right-size GPU Memory:** Match workload requirements
3. **Optimize Partitioning:** Reduce data shuffle
4. **Cache Frequently Used Data:** Reduce I/O overhead
5. **Monitor GPU Utilization:** Ensure efficient usage

## Next Steps

1. **Validate Setup:** Run basic tests to ensure infrastructure works
2. **Build RAPIDS Image:** Create custom image with fraud detection libraries
3. **Performance Testing:** Benchmark against CPU-only workloads
4. **Production Deployment:** Update job templates to use RAPIDS
5. **Monitoring:** Set up GPU utilization monitoring
6. **Cost Analysis:** Compare costs vs performance benefits

## Support Resources

- [RAPIDS Documentation](https://docs.rapids.ai/)
- [EMR on EKS Guide](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/)
- [Spark RAPIDS Plugin](https://nvidia.github.io/spark-rapids/)
- [AWS GPU Instances](https://aws.amazon.com/ec2/instance-types/p3/)

## Troubleshooting Checklist

- [ ] EKS cluster has GPU nodes
- [ ] EMR virtual cluster is running
- [ ] IAM roles have correct permissions
- [ ] Service accounts are properly configured
- [ ] RAPIDS Docker image is built and pushed
- [ ] Environment variables are set
- [ ] S3 bucket is accessible
- [ ] GPU drivers are installed on nodes