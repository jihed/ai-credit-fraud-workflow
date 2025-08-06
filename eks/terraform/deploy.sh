#!/bin/bash

# Fraud Detection EMR on EKS Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform >= 1.3.2"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    terraform init
    
    if [ $? -eq 0 ]; then
        print_status "Terraform initialized successfully!"
    else
        print_error "Terraform initialization failed!"
        exit 1
    fi
}

# Plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    if [ $? -eq 0 ]; then
        print_status "Terraform plan completed successfully!"
        print_warning "Please review the plan above before proceeding."
        read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled by user."
            exit 0
        fi
    else
        print_error "Terraform plan failed!"
        exit 1
    fi
}

# Apply Terraform deployment
apply_terraform() {
    print_status "Applying Terraform deployment..."
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        print_status "Terraform deployment completed successfully!"
    else
        print_error "Terraform deployment failed!"
        exit 1
    fi
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw region)
    
    aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME
    
    if [ $? -eq 0 ]; then
        print_status "kubectl configured successfully!"
        print_status "Testing cluster connection..."
        kubectl get nodes
    else
        print_error "kubectl configuration failed!"
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Check if nodes are ready
    print_status "Checking node status..."
    kubectl get nodes
    
    # Check if Karpenter is running
    print_status "Checking Karpenter status..."
    kubectl get pods -n karpenter
    
    # Check if NVIDIA GPU Operator is running (if enabled)
    if kubectl get namespace gpu-operator &> /dev/null; then
        print_status "Checking NVIDIA GPU Operator status..."
        kubectl get pods -n gpu-operator
    fi
    
    # Check EMR namespace
    print_status "Checking EMR namespace..."
    kubectl get namespace emr-fraud-detection
    kubectl get serviceaccount -n emr-fraud-detection
    
    print_status "Deployment verification completed!"
}

# Get service URLs
get_service_urls() {
    print_status "Getting service URLs (this may take a few minutes for LoadBalancers to be ready)..."
    
    # Wait for services to be ready
    sleep 30
    
    # Get JupyterHub URL
    JUPYTERHUB_URL=""
    if kubectl get svc -n jupyterhub proxy-public &> /dev/null; then
        JUPYTERHUB_URL=$(kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
    fi
    
    # Get Ray Dashboard URL
    RAY_DASHBOARD_URL=""
    if kubectl get svc -n ray-clusters ray-dashboard-service &> /dev/null; then
        RAY_DASHBOARD_URL=$(kubectl get svc -n ray-clusters ray-dashboard-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
    fi
    
    # Get Argo Workflows URL
    ARGO_URL=""
    if kubectl get svc -n argo-workflows argo-server &> /dev/null; then
        ARGO_URL=$(kubectl get svc -n argo-workflows argo-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
    fi
    
    # Get Grafana URL
    GRAFANA_URL=""
    if kubectl get svc -n kube-prometheus-stack kube-prometheus-stack-grafana &> /dev/null; then
        GRAFANA_URL=$(kubectl get svc -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
    fi
}

# Display outputs
display_outputs() {
    print_status "Deployment completed successfully!"
    echo
    echo "=== Cluster Information ==="
    echo "Cluster Name: $(terraform output -raw cluster_name)"
    echo "Cluster Endpoint: $(terraform output -raw cluster_endpoint)"
    echo "Region: $(terraform output -raw region)"
    echo "EMR Virtual Cluster ID: $(terraform output -raw emr_virtual_cluster_id)"
    echo "S3 Bucket: $(terraform output -raw s3_bucket_name)"
    echo
    
    # Get service URLs
    get_service_urls
    
    echo "=== JARK Stack Services ==="
    if [ ! -z "$JUPYTERHUB_URL" ] && [ "$JUPYTERHUB_URL" != "Pending..." ]; then
        echo "JupyterHub: http://$JUPYTERHUB_URL"
        echo "  - Username: any"
        echo "  - Password: fraud-detection-demo"
    else
        echo "JupyterHub: $(terraform output -raw get_jupyterhub_url)"
    fi
    
    if [ ! -z "$RAY_DASHBOARD_URL" ] && [ "$RAY_DASHBOARD_URL" != "Pending..." ]; then
        echo "Ray Dashboard: http://$RAY_DASHBOARD_URL:8265"
    else
        echo "Ray Dashboard: $(terraform output -raw get_ray_dashboard_url)"
    fi
    
    if [ ! -z "$ARGO_URL" ] && [ "$ARGO_URL" != "Pending..." ]; then
        echo "Argo Workflows: http://$ARGO_URL:2746"
    else
        echo "Argo Workflows: $(terraform output -raw get_argo_workflows_url)"
    fi
    
    if [ ! -z "$GRAFANA_URL" ] && [ "$GRAFANA_URL" != "Pending..." ]; then
        echo "Grafana: http://$GRAFANA_URL"
        echo "  - Username: admin"
        echo "  - Password: fraud-detection-grafana"
    else
        echo "Grafana: $(terraform output -raw get_grafana_url)"
    fi
    
    echo
    echo "=== Next Steps ==="
    echo "1. Configure kubectl: $(terraform output -raw configure_kubectl)"
    echo "2. Build and push notebook images: cd ../docker && ./build-images.sh"
    echo "3. Access JupyterHub to start developing fraud detection notebooks"
    echo "4. Use Ray for distributed ML training and serving"
    echo "5. Create Argo Workflows for ML pipeline orchestration"
    echo "6. Monitor everything with Grafana dashboards"
    echo
    echo "=== Quick Commands ==="
    echo "# Get all service URLs:"
    echo "kubectl get svc --all-namespaces -o wide | grep LoadBalancer"
    echo
    echo "# Check Ray cluster status:"
    echo "kubectl get rayclusters -n ray-clusters"
    echo
    echo "# Submit Argo workflow:"
    echo "$(terraform output -raw argo_workflow_submission_example)"
    echo
    print_status "🎉 Happy fraud detecting with the JARK stack on EKS!"
}

# Main execution
main() {
    print_status "Starting Fraud Detection EMR on EKS deployment..."
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found. Please copy terraform.tfvars.example to terraform.tfvars and customize it."
        exit 1
    fi
    
    check_prerequisites
    init_terraform
    plan_terraform
    apply_terraform
    configure_kubectl
    verify_deployment
    display_outputs
}

# Run main function
main "$@"