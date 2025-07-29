#!/bin/bash

# Example environment configuration for fraud detection EMR on EKS jobs
# Copy this file to env.sh and customize for your environment

#--------------------------------------------
# EMR on EKS Configuration
#--------------------------------------------
export EMR_VIRTUAL_CLUSTER_ID="your-emr-virtual-cluster-id"
export EMR_EXECUTION_ROLE_ARN="arn:aws:iam::123456789012:role/EMRContainers-JobExecutionRole"
export CLOUDWATCH_LOG_GROUP="/emr-on-eks-logs/your-cluster/emr-ml-team-a/"

#--------------------------------------------
# AWS Configuration
#--------------------------------------------
export AWS_REGION="us-west-2"
export S3_BUCKET="your-fraud-detection-bucket"

#--------------------------------------------
# Data Paths
#--------------------------------------------
export CUSTOMERS_S3_PATH="s3://${S3_BUCKET}/data/customers/"
export TERMINALS_S3_PATH="s3://${S3_BUCKET}/data/terminals/"
export TRANSACTIONS_S3_PATH="s3://${S3_BUCKET}/data/transactions/"
export OUTPUT_S3_PATH="s3://${S3_BUCKET}/output/fraud-detection/"

#--------------------------------------------
# Job Configuration
#--------------------------------------------
export NUM_EXECUTORS="12"
export ENVIRONMENT="dev"

#--------------------------------------------
# Docker Image Configuration
#--------------------------------------------
export ECR_REGISTRY="123456789012.dkr.ecr.us-west-2.amazonaws.com"
export ECR_REPOSITORY="data-on-eks/fraud-detection-rapids"
export IMAGE_TAG="latest"
export FRAUD_DETECTION_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

#--------------------------------------------
# Optional: Override default settings
#--------------------------------------------
# export PLATFORM="linux/amd64"
# export USE_KARPENTER="true"

# Load this configuration with:
# source config/env.sh