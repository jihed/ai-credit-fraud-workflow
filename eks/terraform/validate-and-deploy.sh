#!/bin/bash

# EKS Infrastructure Validation and Deployment Script
set -e

echo "🔍 Validating Terraform configuration..."

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan the deployment
echo "📋 Creating deployment plan..."
terraform plan -out=tfplan

echo "✅ Validation complete. Key changes made:"
echo "1. EKS control plane and nodes use private subnets (10.1.x.x)"
echo "2. Secondary CIDR subnets (100.64.x.x) available for future pod networking"
echo "3. VPC CNI configured with prefix delegation for efficient IP usage"
echo "4. Karpenter NodePools target private subnets for node placement"

echo ""
echo "🚀 To apply these changes, run:"
echo "terraform apply tfplan"

echo ""
echo "📊 After deployment, verify with:"
echo "kubectl get nodes"
echo "kubectl get pods -A"