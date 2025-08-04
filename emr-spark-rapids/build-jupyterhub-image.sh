#!/bin/bash

# Build and push JupyterHub RAPIDS image to ECR
set -e

# Configuration
AWS_REGION=${AWS_DEFAULT_REGION:-us-west-2}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="jupyterhub-rapids"
IMAGE_TAG=${1:-latest}

echo "🐳 Building JupyterHub RAPIDS Docker image..."
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
echo "ECR Repository: $ECR_REPOSITORY"
echo "Image Tag: $IMAGE_TAG"

# Get ECR login token
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the image
echo "🔨 Building Docker image..."
docker build -t $ECR_REPOSITORY:$IMAGE_TAG -f docker/jupyterhub-rapids/Dockerfile .

# Tag for ECR
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG"
docker tag $ECR_REPOSITORY:$IMAGE_TAG $ECR_URI

# Push to ECR
echo "📤 Pushing image to ECR..."
docker push $ECR_URI

echo "✅ Image successfully built and pushed!"
echo "Image URI: $ECR_URI"

# Also tag as latest if not already
if [ "$IMAGE_TAG" != "latest" ]; then
    echo "🏷️ Tagging as latest..."
    LATEST_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest"
    docker tag $ECR_REPOSITORY:$IMAGE_TAG $LATEST_URI
    docker push $LATEST_URI
    echo "Latest URI: $LATEST_URI"
fi

echo "🎉 JupyterHub RAPIDS image build complete!"