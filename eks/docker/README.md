# Fraud Detection Docker Images

This directory contains Docker configurations for building fraud detection notebook and job execution environments.

## Images

### 1. Unified Notebook (`Dockerfile.unified`)
- **Purpose**: Complete development environment for JupyterHub
- **Base**: Ray 2.8.0 with Python 3.10
- **Includes**: Spark, Ray, ML libraries, JupyterLab
- **Use case**: Interactive development and experimentation
- **ECR Repository**: `fraud-detection/unified-notebook`

### 2. EMR Spark (`Dockerfile.emr`)
- **Purpose**: Minimal Spark job execution environment
- **Base**: EMR 6.15.0 Spark image
- **Includes**: Essential ML packages (scikit-learn, XGBoost)
- **Use case**: EMR on EKS batch jobs
- **ECR Repository**: `fraud-detection/emr-spark`

### 3. EMR RAPIDS (`Dockerfile.rapids`)
- **Purpose**: GPU-accelerated ML environment
- **Base**: EMR 7.3.0 notebook with RAPIDS
- **Includes**: RAPIDS (cuDF, cuML, cuGraph), additional ML packages
- **Use case**: GPU-accelerated fraud detection workloads
- **ECR Repository**: `fraud-detection/emr-rapids`

## Building Images

### Build All Images
```bash
./build-all.sh
```

### Build Specific Image
```bash
./build-all.sh build unified    # Build unified notebook
./build-all.sh build emr        # Build EMR Spark image
./build-all.sh build rapids     # Build EMR RAPIDS image
```

### Clean Up Local Images
```bash
./build-all.sh clean
```

## Prerequisites

1. **Docker**: Ensure Docker is installed and running
2. **AWS CLI**: Configure with appropriate permissions
3. **ECR Access**: Permissions to create repositories and push images

## Directory Structure

```
eks/docker/
├── Dockerfile.unified      # Unified notebook environment
├── Dockerfile.emr          # EMR Spark job environment  
├── Dockerfile.rapids       # EMR RAPIDS GPU environment
├── build-all.sh           # Consolidated build script
├── notebooks/             # Fraud detection notebooks
├── src/                   # Utility libraries
└── README.md              # This file
```

## Environment Variables

The build script uses these environment variables:
- `AWS_REGION`: AWS region for ECR (default: us-west-2)
- `AWS_ACCOUNT_ID`: Automatically detected from AWS CLI

## Image URIs

After building, images are available at:
- `{account}.dkr.ecr.{region}.amazonaws.com/fraud-detection/unified-notebook:latest`
- `{account}.dkr.ecr.{region}.amazonaws.com/fraud-detection/emr-spark:latest`
- `{account}.dkr.ecr.{region}.amazonaws.com/fraud-detection/emr-rapids:latest`

## JupyterHub Integration

Use the unified notebook image URI in your JupyterHub configuration:

```yaml
singleuser:
  image:
    name: "{account}.dkr.ecr.{region}.amazonaws.com/fraud-detection/unified-notebook"
    tag: "latest"
```

## Troubleshooting

### Platform Issues
All Dockerfiles include `--platform=linux/amd64` to ensure x86_64 compatibility when building on Apple Silicon.

### Permission Issues
The build script handles ECR login and repository creation automatically.

### Build Failures
Check the build logs for specific errors. Common issues:
- AWS credentials not configured
- Docker daemon not running
- Network connectivity to base image registries