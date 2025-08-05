#!/bin/bash

# Terraform-Only Cleanup Script for EMR to EKS Migration
# This script cleanly destroys all resources using Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧹 Starting Terraform-Only Cleanup for EMR to EKS Migration${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
if ! command_exists terraform; then
    echo -e "${RED}❌ Terraform is required but not installed${NC}"
    exit 1
fi

# Confirm destruction
echo -e "${RED}⚠️  WARNING: This will destroy ALL resources created by Terraform!${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo -e "${BLUE}- EKS Cluster and all workloads${NC}"
echo -e "${BLUE}- VPC and networking resources${NC}"
echo -e "${BLUE}- S3 buckets and data${NC}"
echo -e "${BLUE}- IAM roles and policies${NC}"
echo -e "${BLUE}- All monitoring and logging resources${NC}"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${GREEN}✅ Cleanup cancelled${NC}"
    exit 0
fi

# Plan destruction
echo -e "${YELLOW}📋 Planning Terraform destruction...${NC}"
terraform plan -destroy -out=destroy.tfplan

# Apply destruction
echo -e "${YELLOW}🗑️ Applying Terraform destruction...${NC}"
terraform apply destroy.tfplan

# Clean up Terraform state and files
echo -e "${YELLOW}🧹 Cleaning up Terraform files...${NC}"
rm -f destroy.tfplan
rm -f tfplan
rm -f terraform.tfstate.backup

echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
echo -e "${YELLOW}📝 Note: Some resources may take a few minutes to fully terminate${NC}"