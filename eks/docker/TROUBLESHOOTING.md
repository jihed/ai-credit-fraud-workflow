# Docker Build Troubleshooting Guide

This guide helps resolve common issues when building custom JupyterHub images for the fraud detection demo.

## Quick Fix Commands

If you're experiencing build issues, try these commands in order:

```bash
# 1. Use the fixed build script
cd eks/docker
bash build-images-fixed.sh

# 2. If that fails, try the comprehensive setup script
bash setup-and-build.sh

# 3. For debugging, build one image at a time
bash build-images-fixed.sh single unified-dev
```

## Common Issues and Solutions

### 1. Shell Compatibility Issues

**Error**: `declare: -A: invalid option`

**Cause**: Script is running with sh instead of bash

**Solution**:
```bash
# Always use bash explicitly
bash build-images-fixed.sh

# Or make sure the script is executable and has proper shebang
chmod +x build-images-fixed.sh
./build-images-fixed.sh
```

### 2. AWS Authentication Issues

**Error**: `Failed to get AWS account ID`

**Cause**: AWS CLI not configured or credentials expired

**Solution**:
```bash
# Check AWS configuration
aws configure list
aws sts get-caller-identity

# If not configured, run:
aws configure

# If using SSO or temporary credentials, refresh:
aws sso login  # for SSO
# or
aws sts get-session-token  # for MFA
```

### 3. Docker Daemon Issues

**Error**: `Docker daemon is not running`

**Cause**: Docker service is not started

**Solution**:
```bash
# On macOS
open -a Docker

# On Linux
sudo systemctl start docker
sudo systemctl enable docker

# Verify Docker is running
docker info
```

### 4. ECR Permission Issues

**Error**: `Failed to login to ECR` or `no basic auth credentials`

**Cause**: Insufficient permissions or ECR login expired

**Solution**:
```bash
# Check ECR permissions
aws ecr describe-repositories --region us-west-2

# Re-login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com

# If using different region, update accordingly
export AWS_REGION=your-region
```

### 5. Missing Files or Directories

**Error**: `Directory not found` or `Dockerfile not found`

**Cause**: Missing required files from the repository

**Solution**:
```bash
# Check current directory structure
ls -la eks/docker/

# Required directories should include:
# - emr-spark-rapids/
# - ray-ml/
# - spark-notebook/
# - ray-notebook/
# - unified-dev/
# - notebooks/
# - src/

# If missing, ensure you have the complete repository
git status
git pull origin main
```

### 6. Docker Build Context Issues

**Error**: `COPY failed` or `no such file or directory`

**Cause**: Files not properly copied to build context

**Solution**:
```bash
# The fixed script handles this automatically, but you can manually check:
ls -la eks/docker/unified-dev/notebooks/
ls -la eks/docker/unified-dev/src/

# If empty, the script should copy them during build
```

### 7. Network/Download Issues

**Error**: `Failed to download` or timeout errors during build

**Cause**: Network connectivity or package repository issues

**Solution**:
```bash
# Retry the build (sometimes transient network issues)
bash build-images-fixed.sh

# Build one image at a time to isolate issues
bash build-images-fixed.sh single unified-dev

# Check Docker network settings
docker network ls
```

### 8. Disk Space Issues

**Error**: `no space left on device`

**Cause**: Insufficient disk space for Docker builds

**Solution**:
```bash
# Check disk space
df -h

# Clean up Docker
docker system prune -a
docker volume prune

# Remove unused images
docker image prune -a
```

### 9. Memory Issues During Build

**Error**: Build process killed or out of memory errors

**Cause**: Insufficient memory allocated to Docker

**Solution**:
```bash
# Increase Docker memory limit (Docker Desktop)
# Go to Docker Desktop -> Settings -> Resources -> Memory

# Or build images one at a time
bash build-images-fixed.sh single spark-notebook
bash build-images-fixed.sh single ray-notebook
bash build-images-fixed.sh single unified-dev
```

### 10. Base Image Pull Issues

**Error**: `pull access denied` or `manifest unknown`

**Cause**: Base images not accessible or incorrect image names

**Solution**:
```bash
# Test pulling base images manually
docker pull rayproject/ray:2.8.0-py310
docker pull jupyter/pyspark-notebook:spark-3.5.2
docker pull public.ecr.aws/emr-on-eks/spark/emr-7.2.0:latest

# If EMR image fails, check if you have access to public ECR
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
```

## Debugging Steps

### Step 1: Validate Environment

```bash
# Run the setup script to check everything
bash setup-and-build.sh

# This will validate:
# - Docker installation and daemon
# - AWS CLI configuration
# - kubectl access
# - Required files and directories
```

### Step 2: Test Individual Components

```bash
# Test AWS access
aws sts get-caller-identity
aws ecr describe-repositories --region us-west-2

# Test Docker
docker info
docker run hello-world

# Test base image access
docker pull rayproject/ray:2.8.0-py310
docker pull public.ecr.aws/emr-on-eks/spark/emr-7.2.0:latest
```

### Step 3: Build Images Individually

```bash
# Build one image at a time to isolate issues
bash build-images-fixed.sh single spark-notebook

# Check the logs for specific errors
# Common issues will be in the pip install or COPY commands
```

### Step 4: Inspect Build Context

```bash
# Check what files are being copied
ls -la eks/docker/notebooks/
ls -la eks/docker/src/

# Verify Dockerfile syntax
docker build --no-cache -t test-image eks/docker/unified-dev/
```

## Manual Build Process

If the automated scripts fail, you can build manually:

```bash
cd eks/docker

# Login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-west-2.amazonaws.com

# Create ECR repositories
aws ecr create-repository --repository-name fraud-detection/unified-notebook --region us-west-2

# Copy files to build context
cp -r notebooks unified-dev/
cp -r src unified-dev/

# Build image
docker build -t fraud-detection/unified-notebook:latest unified-dev/

# Tag for ECR
docker tag fraud-detection/unified-notebook:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-west-2.amazonaws.com/fraud-detection/unified-notebook:latest

# Push to ECR
docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-west-2.amazonaws.com/fraud-detection/unified-notebook:latest

# Clean up
rm -rf unified-dev/notebooks unified-dev/src
```

## Getting Help

If you continue to experience issues:

1. **Check the logs**: Look for specific error messages in the build output
2. **Verify prerequisites**: Ensure Docker, AWS CLI, and kubectl are properly configured
3. **Test components individually**: Build one image at a time
4. **Check AWS permissions**: Ensure your AWS user/role has ECR permissions
5. **Review Docker resources**: Ensure sufficient memory and disk space

## Success Indicators

You'll know the build is successful when you see:

```
✅ Successfully built fraud-detection/unified-notebook:latest
✅ Successfully pushed <account>.dkr.ecr.us-west-2.amazonaws.com/fraud-detection/unified-notebook:latest
🎉 All images built and pushed successfully!
```

And you can verify with:

```bash
# List images in ECR
aws ecr list-images --repository-name fraud-detection/unified-notebook --region us-west-2

# Test image locally
docker run --rm fraud-detection/unified-notebook:latest python -c "import ray, pyspark; print('Success!')"
```