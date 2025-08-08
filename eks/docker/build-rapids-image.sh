#!/bin/bash

# Build and Push RAPIDS-enabled EMR Docker Image
# This script builds a custom EMR image with RAPIDS support and pushes it to ECR

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="fraud-detection/emr-rapids"
IMAGE_TAG=${IMAGE_TAG:-latest}
DOCKERFILE="Dockerfile.rapids"

echo "🚀 Building RAPIDS-enabled EMR Docker Image"
echo "============================================"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
echo "ECR Repository: $ECR_REPOSITORY"
echo "Image Tag: $IMAGE_TAG"
echo "Dockerfile: $DOCKERFILE"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "❌ AWS CLI is not configured. Please configure AWS credentials."
    exit 1
fi

# Create ECR repository if it doesn't exist
echo "📦 Creating ECR repository if it doesn't exist..."
aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION > /dev/null 2>&1 || \
aws ecr create-repository \
    --repository-name $ECR_REPOSITORY \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true

# Get ECR login token
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the Docker image
echo "🔨 Building Docker image..."
docker build -f $DOCKERFILE -t $ECR_REPOSITORY:$IMAGE_TAG .

# Tag the image for ECR
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG"
docker tag $ECR_REPOSITORY:$IMAGE_TAG $ECR_URI

echo "📤 Pushing image to ECR..."
docker push $ECR_URI

echo "✅ RAPIDS Docker image built and pushed successfully!"
echo "📋 Image Details:"
echo "   ECR URI: $ECR_URI"
echo "   Repository: $ECR_REPOSITORY"
echo "   Tag: $IMAGE_TAG"

echo ""
echo "🔧 To use this image in EMR on EKS jobs, update your job configuration:"
echo "   spark.kubernetes.container.image: $ECR_URI"

echo ""
echo "📝 Next steps:"
echo "1. Update your EMR job templates to use this image"
echo "2. Test RAPIDS functionality with the rapids_test_job.py script"
echo "3. Update Terraform configuration if needed"