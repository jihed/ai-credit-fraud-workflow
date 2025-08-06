#!/bin/bash

# Terraform Import Script for Existing Infrastructure
# This script helps you import existing AWS resources into Terraform state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔄 Terraform Import for Existing Infrastructure${NC}"
echo -e "${BLUE}This script will help you import existing AWS resources into Terraform state${NC}"

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

if ! command_exists aws; then
    echo -e "${RED}❌ AWS CLI is required but not installed${NC}"
    exit 1
fi

if ! command_exists kubectl; then
    echo -e "${RED}❌ kubectl is required but not installed${NC}"
    exit 1
fi

# Verify AWS credentials
echo -e "${YELLOW}🔐 Verifying AWS credentials...${NC}"
if ! aws sts get-caller-identity --no-paginate >/dev/null 2>&1; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    exit 1
fi

# Get current AWS account and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-paginate)
AWS_REGION=${AWS_REGION:-$(aws configure get region --no-paginate)}
AWS_REGION=${AWS_REGION:-us-west-2}

echo -e "${BLUE}Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${BLUE}Region: ${AWS_REGION}${NC}"

# Initialize Terraform if not already done
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}🏗️ Initializing Terraform...${NC}"
    terraform init
fi

# Function to import resource if it exists
import_if_exists() {
    local resource_type=$1
    local resource_name=$2
    local aws_resource_id=$3
    
    echo -e "${YELLOW}🔍 Checking if $resource_type.$resource_name exists...${NC}"
    
    # Check if resource already exists in state
    if terraform state show "$resource_type.$resource_name" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $resource_type.$resource_name already in state${NC}"
        return 0
    fi
    
    # Try to import the resource
    if terraform import "$resource_type.$resource_name" "$aws_resource_id" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Successfully imported $resource_type.$resource_name${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️ Could not import $resource_type.$resource_name (resource may not exist)${NC}"
        return 1
    fi
}

# Function to find existing EKS cluster
find_eks_cluster() {
    echo -e "${YELLOW}🔍 Looking for existing EKS clusters...${NC}"
    
    # List all EKS clusters
    CLUSTERS=$(aws eks list-clusters --region $AWS_REGION --query 'clusters[]' --output text --no-paginate)
    
    if [ -z "$CLUSTERS" ]; then
        echo -e "${YELLOW}⚠️ No EKS clusters found in region $AWS_REGION${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Found EKS clusters:${NC}"
    for cluster in $CLUSTERS; do
        echo -e "${BLUE}  - $cluster${NC}"
    done
    
    # If there's only one cluster, use it
    if [ $(echo "$CLUSTERS" | wc -w) -eq 1 ]; then
        CLUSTER_NAME=$CLUSTERS
        echo -e "${GREEN}✅ Using cluster: $CLUSTER_NAME${NC}"
        return 0
    fi
    
    # Ask user to choose
    echo -e "${YELLOW}Multiple clusters found. Please choose one:${NC}"
    select cluster in $CLUSTERS; do
        if [ -n "$cluster" ]; then
            CLUSTER_NAME=$cluster
            echo -e "${GREEN}✅ Selected cluster: $CLUSTER_NAME${NC}"
            break
        fi
    done
}

# Function to update terraform.tfvars with existing cluster name
update_tfvars() {
    local cluster_name=$1
    
    echo -e "${YELLOW}📝 Updating terraform.tfvars...${NC}"
    
    # Create or update terraform.tfvars
    cat > terraform.tfvars << EOF
# Configuration for existing infrastructure
name = "$cluster_name"
region = "$AWS_REGION"

# Platform Components (adjust as needed)
enable_jupyterhub = true
enable_ray_cluster = true
enable_inference_service = true
enable_sample_data = true
enable_monitoring_dashboards = true

# Enhanced monitoring
enable_nvidia_gpu_monitoring = true
enable_cost_monitoring = true
enable_enhanced_logging = true

# Karpenter configuration
enable_karpenter_gpu_nodes = true
enable_karpenter_cpu_nodes = true

# Application settings
fraud_detection_model_version = "v1.0.0"
inference_service_replicas = 3
ray_cluster_workers = 2

tags = {
  Environment = "production"
  Project     = "fraud-detection"
  ManagedBy   = "terraform"
}
EOF
    
    echo -e "${GREEN}✅ Updated terraform.tfvars with cluster name: $cluster_name${NC}"
}

# Main import process
main() {
    echo -e "${YELLOW}🚀 Starting import process...${NC}"
    
    # Find existing EKS cluster
    if find_eks_cluster; then
        # Update terraform.tfvars
        update_tfvars "$CLUSTER_NAME"
        
        # Configure kubectl
        echo -e "${YELLOW}🔧 Configuring kubectl...${NC}"
        aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME --no-paginate
        
        # Validate cluster access
        if kubectl cluster-info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Successfully connected to cluster${NC}"
        else
            echo -e "${RED}❌ Could not connect to cluster${NC}"
            exit 1
        fi
        
        # Try to import key resources
        echo -e "${YELLOW}📦 Attempting to import existing resources...${NC}"
        
        # Import VPC (try to find it)
        VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text --no-paginate)
        if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
            import_if_exists "module.vpc.aws_vpc" "this[0]" "$VPC_ID"
        fi
        
        # Import EKS cluster
        import_if_exists "module.eks.aws_eks_cluster" "this[0]" "$CLUSTER_NAME"
        
        # Run terraform plan to see what needs to be created
        echo -e "${YELLOW}📋 Running terraform plan to see what needs to be created...${NC}"
        terraform plan
        
        echo -e "${GREEN}🎉 Import process completed!${NC}"
        echo -e "${BLUE}Next steps:${NC}"
        echo -e "${BLUE}1. Review the terraform plan output above${NC}"
        echo -e "${BLUE}2. Run 'terraform apply' to create missing resources${NC}"
        echo -e "${BLUE}3. Run './terraform-validate.sh' to check everything${NC}"
        
    else
        echo -e "${YELLOW}⚠️ No suitable EKS cluster found${NC}"
        echo -e "${BLUE}You can either:${NC}"
        echo -e "${BLUE}1. Create a new cluster with './terraform-deploy.sh'${NC}"
        echo -e "${BLUE}2. Specify an existing cluster name manually${NC}"
        
        read -p "Enter existing cluster name (or press Enter to create new): " MANUAL_CLUSTER_NAME
        
        if [ -n "$MANUAL_CLUSTER_NAME" ]; then
            CLUSTER_NAME=$MANUAL_CLUSTER_NAME
            update_tfvars "$CLUSTER_NAME"
            echo -e "${GREEN}✅ Configuration updated for cluster: $CLUSTER_NAME${NC}"
            echo -e "${BLUE}Run 'terraform plan' to see what will be created${NC}"
        else
            echo -e "${BLUE}Run './terraform-deploy.sh' to create a new cluster${NC}"
        fi
    fi
}

# Run main function
main

echo -e "${GREEN}✅ Script completed!${NC}"