#!/bin/bash

# Quick script to check what infrastructure already exists
# This helps you understand what you have before running terraform-import.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Checking Existing AWS Infrastructure${NC}"

# Get AWS region
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
AWS_REGION=${AWS_REGION:-us-west-2}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${BLUE}Account: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${BLUE}Region: ${AWS_REGION}${NC}"
echo ""

# Check EKS clusters
echo -e "${YELLOW}📊 EKS Clusters:${NC}"
CLUSTERS=$(aws eks list-clusters --region $AWS_REGION --query 'clusters[]' --output text)
if [ -n "$CLUSTERS" ]; then
    for cluster in $CLUSTERS; do
        STATUS=$(aws eks describe-cluster --name $cluster --region $AWS_REGION --query 'cluster.status' --output text)
        VERSION=$(aws eks describe-cluster --name $cluster --region $AWS_REGION --query 'cluster.version' --output text)
        echo -e "${GREEN}  ✅ $cluster (v$VERSION, $STATUS)${NC}"
    done
else
    echo -e "${YELLOW}  ⚠️ No EKS clusters found${NC}"
fi
echo ""

# Check if kubectl is configured
echo -e "${YELLOW}🔧 Kubectl Configuration:${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    CURRENT_CONTEXT=$(kubectl config current-context)
    echo -e "${GREEN}  ✅ Connected to: $CURRENT_CONTEXT${NC}"
    
    # Check nodes
    echo -e "${YELLOW}📦 Cluster Nodes:${NC}"
    kubectl get nodes --no-headers 2>/dev/null | while read line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_TYPE=$(kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}' 2>/dev/null || echo "unknown")
        echo -e "${GREEN}    ✅ $NODE_NAME ($NODE_TYPE, $NODE_STATUS)${NC}"
    done
    
    # Check existing namespaces
    echo -e "${YELLOW}📁 Relevant Namespaces:${NC}"
    for ns in jupyterhub ray-system ml-team-a kube-prometheus-stack prometheus kubecost; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            echo -e "${GREEN}    ✅ $ns${NC}"
        else
            echo -e "${YELLOW}    ⚠️ $ns (not found)${NC}"
        fi
    done
    
else
    echo -e "${YELLOW}  ⚠️ kubectl not configured or no cluster access${NC}"
fi
echo ""

# Check S3 buckets (look for spark/ml related buckets)
echo -e "${YELLOW}🗄️ S3 Buckets (spark/ml related):${NC}"
BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `spark`) || contains(Name, `ml`) || contains(Name, `emr`)].Name' --output text)
if [ -n "$BUCKETS" ]; then
    for bucket in $BUCKETS; do
        echo -e "${GREEN}  ✅ $bucket${NC}"
    done
else
    echo -e "${YELLOW}  ⚠️ No relevant S3 buckets found${NC}"
fi
echo ""

# Check VPCs
echo -e "${YELLOW}🌐 VPCs:${NC}"
aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[?!IsDefault].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output text | while read vpc_id vpc_name; do
    if [ "$vpc_name" = "None" ] || [ -z "$vpc_name" ]; then
        vpc_name="(unnamed)"
    fi
    echo -e "${GREEN}  ✅ $vpc_id $vpc_name${NC}"
done
echo ""

# Summary and recommendations
echo -e "${BLUE}📋 Summary:${NC}"
if [ -n "$CLUSTERS" ]; then
    echo -e "${GREEN}✅ You have existing EKS infrastructure${NC}"
    echo -e "${BLUE}💡 Recommended next steps:${NC}"
    echo -e "${BLUE}   1. Run './terraform-import.sh' to import existing resources${NC}"
    echo -e "${BLUE}   2. Run 'terraform plan' to see what will be added${NC}"
    echo -e "${BLUE}   3. Run 'terraform apply' to add missing components${NC}"
else
    echo -e "${YELLOW}⚠️ No EKS clusters found${NC}"
    echo -e "${BLUE}💡 Recommended next steps:${NC}"
    echo -e "${BLUE}   1. Run './terraform-deploy.sh' to create new infrastructure${NC}"
fi
echo ""

echo -e "${GREEN}🎯 For detailed guidance, see EXISTING_INFRASTRUCTURE.md${NC}"