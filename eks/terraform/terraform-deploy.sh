#!/bin/bash

# Terraform-Only Deployment Script for EMR to EKS Migration
# This script replaces all bash deployment scripts with pure Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"emr-spark-rapids"}
AWS_REGION=${AWS_REGION:-"us-west-2"}

echo -e "${GREEN}🚀 Starting Terraform-Only Deployment for EMR to EKS Migration${NC}"
echo -e "${BLUE}Cluster: ${CLUSTER_NAME}, Region: ${AWS_REGION}${NC}"

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

# Initialize Terraform
echo -e "${YELLOW}🏗️ Initializing Terraform...${NC}"
terraform init

# Validate Terraform configuration
echo -e "${YELLOW}✅ Validating Terraform configuration...${NC}"
terraform validate

# Plan deployment
echo -e "${YELLOW}📋 Planning Terraform deployment...${NC}"
terraform plan -out=tfplan

# Apply deployment
echo -e "${YELLOW}🚀 Applying Terraform deployment...${NC}"
terraform apply tfplan

# Wait for EKS cluster to be ready
echo -e "${YELLOW}⏳ Waiting for EKS cluster to be ready...${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION --no-paginate

# Update kubeconfig
echo -e "${YELLOW}🔧 Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME --no-paginate

# Wait for nodes to be ready
echo -e "${YELLOW}⏳ Waiting for nodes to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# Verify deployment
echo -e "${YELLOW}🔍 Verifying deployment...${NC}"

# Check core components
echo -e "${BLUE}Checking core components...${NC}"
kubectl get nodes
kubectl get pods -n kube-system
kubectl get pods -n karpenter

# Check EKS Blueprint addons
echo -e "${BLUE}Checking EKS Blueprint addons...${NC}"
kubectl get deployment aws-load-balancer-controller -n kube-system || echo "AWS Load Balancer Controller not found"
kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system || echo "NVIDIA Device Plugin not found"
kubectl get deployment metrics-server -n kube-system || echo "Metrics Server not found"

# Check monitoring stack
echo -e "${BLUE}Checking monitoring stack...${NC}"
kubectl get pods -n kube-prometheus-stack || echo "Prometheus stack not found"
kubectl get pods -n kubecost || echo "Kubecost not found"

# Check JupyterHub
echo -e "${BLUE}Checking JupyterHub...${NC}"
kubectl get pods -n jupyterhub || echo "JupyterHub not found"

# Check Ray cluster
echo -e "${BLUE}Checking Ray cluster...${NC}"
kubectl get pods -n ray-system || echo "Ray system not found"
kubectl get raycluster -n ml-team-a || echo "Ray cluster not found"

# Check inference service
echo -e "${BLUE}Checking inference service...${NC}"
kubectl get deployment fraud-inference -n ml-team-a || echo "Inference service not found"

# Get access information
echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "${YELLOW}📊 Access Information:${NC}"

# JupyterHub URL
JUPYTERHUB_LB=$(kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
if [ "$JUPYTERHUB_LB" != "Not available" ]; then
    echo -e "${BLUE}🔗 JupyterHub: http://$JUPYTERHUB_LB${NC}"
    echo -e "${BLUE}👤 Login: any username, password: fraud-detection-demo${NC}"
else
    echo -e "${BLUE}🔗 JupyterHub: kubectl port-forward svc/proxy-public 8888:80 -n jupyterhub${NC}"
fi

# Inference service URL
INFERENCE_LB=$(kubectl get svc fraud-inference -n ml-team-a -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
if [ "$INFERENCE_LB" != "Not available" ]; then
    echo -e "${BLUE}🔗 Inference API: http://$INFERENCE_LB:8000${NC}"
else
    echo -e "${BLUE}🔗 Inference API: kubectl port-forward svc/fraud-inference 8080:8000 -n ml-team-a${NC}"
fi

# Monitoring dashboards
echo -e "${BLUE}📊 Monitoring:${NC}"
echo -e "${BLUE}  - Grafana: kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n kube-prometheus-stack${NC}"
echo -e "${BLUE}  - Prometheus: kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n kube-prometheus-stack${NC}"
echo -e "${BLUE}  - Kubecost: kubectl port-forward svc/kubecost-cost-analyzer 9090:9090 -n kubecost${NC}"

# Ray dashboard
echo -e "${BLUE}🔗 Ray Dashboard: kubectl port-forward svc/fraud-detection-cluster-head-svc 8265:8265 -n ml-team-a${NC}"

# S3 bucket
S3_BUCKET=$(terraform output -raw s3_bucket_id 2>/dev/null || echo "Not available")
echo -e "${BLUE}🗄️ S3 Bucket: $S3_BUCKET${NC}"

# Quick start commands
echo -e "${YELLOW}🚀 Quick Start Commands:${NC}"
echo -e "${BLUE}# Test inference API${NC}"
echo -e "curl -X POST http://localhost:8080/predict -H 'Content-Type: application/json' -d '{\"avg_amount\": 150.0, \"std_amount\": 75.0, \"tx_count\": 25}'"
echo ""
echo -e "${BLUE}# Access Grafana (admin/admin)${NC}"
echo -e "kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n kube-prometheus-stack"
echo ""
echo -e "${BLUE}# View cluster resources${NC}"
echo -e "kubectl get nodes,pods --all-namespaces"
echo ""
echo -e "${BLUE}# Check GPU nodes${NC}"
echo -e "kubectl get nodes -l accelerator=nvidia"

echo -e "${GREEN}🎉 EMR to EKS migration platform is ready!${NC}"
echo -e "${YELLOW}📖 Next steps:${NC}"
echo -e "${BLUE}1. Access JupyterHub to start developing ML workflows${NC}"
echo -e "${BLUE}2. Use Ray cluster for distributed training${NC}"
echo -e "${BLUE}3. Monitor costs and performance with Grafana dashboards${NC}"
echo -e "${BLUE}4. Deploy your fraud detection models to the inference service${NC}"