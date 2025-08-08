#!/bin/bash

# Configure JupyterHub values from Terraform outputs
# This script populates the JupyterHub values template with actual infrastructure values

set -e

# Configuration
TEMPLATE_FILE="$(dirname "$0")/../values/jupyterhub-values.yaml.template"
VALUES_FILE="$(dirname "$0")/../values/jupyterhub-values.yaml"
TERRAFORM_DIR="$(dirname "$0")/../../terraform"

echo "🔧 Configuring JupyterHub values from Terraform outputs..."

# Check if template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "❌ Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Check if Terraform directory exists
if [[ ! -d "$TERRAFORM_DIR" ]]; then
    echo "❌ Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

# Change to Terraform directory
cd "$TERRAFORM_DIR"

# Check if Terraform state exists
if [[ ! -f "terraform.tfstate" ]]; then
    echo "❌ Terraform state not found. Please run 'terraform apply' first."
    exit 1
fi

echo "📋 Extracting Terraform outputs..."

# Extract Terraform outputs
EMR_VIRTUAL_CLUSTER_ID=$(terraform output -raw emr_virtual_cluster_id 2>/dev/null || echo "")
EMR_EXECUTION_ROLE_ARN=$(terraform output -raw emr_execution_role_arn 2>/dev/null || echo "")
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
JUPYTERHUB_ROLE_ARN=$(terraform output -raw jupyterhub_role_arn 2>/dev/null || echo "")
ECR_REGISTRY=$(terraform output -raw ecr_registry 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "us-west-2")

# Set default values for missing outputs
RAY_CLUSTER_ADDRESS="ray://ray-cluster-head-svc.ray-system.svc.cluster.local:10001"

# Validate required outputs
if [[ -z "$EMR_VIRTUAL_CLUSTER_ID" ]]; then
    echo "⚠️  Warning: EMR virtual cluster ID not found in Terraform outputs"
    EMR_VIRTUAL_CLUSTER_ID="REPLACE_WITH_VIRTUAL_CLUSTER_ID"
fi

if [[ -z "$EMR_EXECUTION_ROLE_ARN" ]]; then
    echo "⚠️  Warning: EMR execution role ARN not found in Terraform outputs"
    EMR_EXECUTION_ROLE_ARN="REPLACE_WITH_EMR_EXECUTION_ROLE_ARN"
fi

if [[ -z "$S3_BUCKET_NAME" ]]; then
    echo "⚠️  Warning: S3 bucket name not found in Terraform outputs"
    S3_BUCKET_NAME="REPLACE_WITH_S3_BUCKET_NAME"
fi

if [[ -z "$JUPYTERHUB_ROLE_ARN" ]]; then
    echo "⚠️  Warning: JupyterHub role ARN not found in Terraform outputs"
    JUPYTERHUB_ROLE_ARN="REPLACE_WITH_JUPYTERHUB_ROLE_ARN"
fi

if [[ -z "$ECR_REGISTRY" ]]; then
    echo "⚠️  Warning: ECR registry not found in Terraform outputs"
    # Try to get from AWS CLI
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "ACCOUNT_ID")
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi

echo "📝 Configuration values:"
echo "   EMR Virtual Cluster ID: $EMR_VIRTUAL_CLUSTER_ID"
echo "   EMR Execution Role ARN: $EMR_EXECUTION_ROLE_ARN"
echo "   S3 Bucket Name: $S3_BUCKET_NAME"
echo "   JupyterHub Role ARN: $JUPYTERHUB_ROLE_ARN"
echo "   ECR Registry: $ECR_REGISTRY"
echo "   AWS Region: $AWS_REGION"
echo "   Ray Cluster Address: $RAY_CLUSTER_ADDRESS"

# Go back to original directory
cd - > /dev/null

# Create values file from template
echo "🔄 Generating JupyterHub values file..."
sed -e "s|\${VIRTUAL_CLUSTER_ID}|$EMR_VIRTUAL_CLUSTER_ID|g" \
    -e "s|\${EMR_EXECUTION_ROLE_ARN}|$EMR_EXECUTION_ROLE_ARN|g" \
    -e "s|\${S3_BUCKET_NAME}|$S3_BUCKET_NAME|g" \
    -e "s|\${ECR_REGISTRY}|$ECR_REGISTRY|g" \
    -e "s|\${AWS_REGION}|$AWS_REGION|g" \
    -e "s|\${RAY_CLUSTER_ADDRESS}|$RAY_CLUSTER_ADDRESS|g" \
    "$TEMPLATE_FILE" > "$VALUES_FILE"

# Update service account manifest with actual role ARN
MANIFEST_FILE="$(dirname "$0")/../manifests/jupyterhub-service-account.yaml"
if [[ -f "$MANIFEST_FILE" ]]; then
    echo "🔄 Updating service account manifest..."
    sed -i.bak "s|arn:aws:iam::ACCOUNT_ID:role/JupyterHub-S3-Access-Role|$JUPYTERHUB_ROLE_ARN|g" "$MANIFEST_FILE"
    rm "$MANIFEST_FILE.bak" 2>/dev/null || true
fi

echo "✅ JupyterHub configuration completed!"
echo ""
echo "📁 Generated files:"
echo "   Values file: $VALUES_FILE"
echo "   Service account: $MANIFEST_FILE"
echo ""
echo "🚀 Next steps:"
echo "   1. Review the generated values file"
echo "   2. Run: ./eks/helm/scripts/deploy-jupyterhub.sh"
echo ""