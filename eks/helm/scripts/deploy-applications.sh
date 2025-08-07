#!/bin/bash

# Deploy fraud detection applications using Helm
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured or cluster is not accessible"
        print_error "Please run: aws eks --region <region> update-kubeconfig --name <cluster-name>"
        exit 1
    fi
    print_status "kubectl is configured and cluster is accessible"
}

# Add Helm repositories
add_helm_repos() {
    print_status "Adding Helm repositories..."
    ./scripts/add-helm-repos.sh
}

# Get Terraform outputs for configuration
get_terraform_outputs() {
    print_status "Getting Terraform outputs for configuration..."
    
    if [ ! -f "../terraform/terraform.tfstate" ]; then
        print_error "Terraform state not found. Please deploy infrastructure first."
        exit 1
    fi
    
    cd ../terraform
    
    export CLUSTER_NAME=$(terraform output -raw cluster_name)
    export EMR_VIRTUAL_CLUSTER_ID=$(terraform output -raw emr_virtual_cluster_id)
    export EMR_EXECUTION_ROLE_ARN=$(terraform output -raw emr_execution_role_arn)
    export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
    export REGION=$(terraform output -raw region)
    
    cd ../helm
    
    print_status "Configuration retrieved:"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  EMR Virtual Cluster: $EMR_VIRTUAL_CLUSTER_ID"
    echo "  S3 Bucket: $S3_BUCKET_NAME"
    echo "  Region: $REGION"
}

# Create service accounts with IRSA
create_service_accounts() {
    print_status "Creating service accounts with IRSA..."
    
    # JupyterHub service account
    kubectl create namespace jupyterhub --dry-run=client -o yaml | kubectl apply -f -
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jupyterhub-user-sa
  namespace: jupyterhub
  annotations:
    eks.amazonaws.com/role-arn: $EMR_EXECUTION_ROLE_ARN
EOF

    # Ray service account
    kubectl create namespace ray-system --dry-run=client -o yaml | kubectl apply -f -
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ray-cluster-sa
  namespace: ray-system
  annotations:
    eks.amazonaws.com/role-arn: $EMR_EXECUTION_ROLE_ARN
EOF

    print_status "Service accounts created successfully"
}

# Deploy JupyterHub
deploy_jupyterhub() {
    print_status "Deploying JupyterHub..."
    
    # Update values with Terraform outputs
    sed -i.bak "s|VIRTUAL_CLUSTER_ID: ''|VIRTUAL_CLUSTER_ID: '$EMR_VIRTUAL_CLUSTER_ID'|g" values/jupyterhub-values.yaml
    sed -i.bak "s|EMR_EXECUTION_ROLE_ARN: ''|EMR_EXECUTION_ROLE_ARN: '$EMR_EXECUTION_ROLE_ARN'|g" values/jupyterhub-values.yaml
    sed -i.bak "s|S3_BUCKET_NAME: ''|S3_BUCKET_NAME: '$S3_BUCKET_NAME'|g" values/jupyterhub-values.yaml
    
    helm install jupyterhub jupyterhub/jupyterhub \
        --namespace jupyterhub \
        --create-namespace \
        --values values/jupyterhub-values.yaml \
        --version 3.2.1 \
        --wait \
        --timeout 10m
    
    if [ $? -eq 0 ]; then
        print_status "JupyterHub deployed successfully!"
    else
        print_error "JupyterHub deployment failed!"
        exit 1
    fi
}

# Deploy KubeRay operator
deploy_kuberay_operator() {
    print_status "Deploying KubeRay operator..."
    
    helm install kuberay-operator kuberay/kuberay-operator \
        --namespace kuberay-operator \
        --create-namespace \
        --version 1.2.2 \
        --wait \
        --timeout 5m
    
    if [ $? -eq 0 ]; then
        print_status "KubeRay operator deployed successfully!"
    else
        print_error "KubeRay operator deployment failed!"
        exit 1
    fi
}

# Deploy Ray cluster
deploy_ray() {
    print_status "Deploying Ray cluster..."
    
    helm install ray-cluster kuberay/ray-cluster \
        --namespace ray-system \
        --create-namespace \
        --values values/ray-values.yaml \
        --version 1.2.2 \
        --wait \
        --timeout 10m
    
    if [ $? -eq 0 ]; then
        print_status "Ray cluster deployed successfully!"
    else
        print_error "Ray cluster deployment failed!"
        exit 1
    fi
}

# Verify deployments
verify_deployments() {
    print_status "Verifying deployments..."
    
    # Check JupyterHub
    print_status "Checking JupyterHub pods..."
    kubectl get pods -n jupyterhub
    
    # Check Ray cluster
    print_status "Checking Ray cluster pods..."
    kubectl get pods -n ray-system
    
    # Get service URLs
    print_status "Getting service URLs..."
    echo ""
    echo "=== Access Information ==="
    
    # JupyterHub URL
    JUPYTERHUB_URL=$(kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ ! -z "$JUPYTERHUB_URL" ]; then
        echo "JupyterHub: http://$JUPYTERHUB_URL"
        echo "  Username: any username"
        echo "  Password: fraud-detection-demo"
    else
        echo "JupyterHub: LoadBalancer URL not ready yet, check with: kubectl get svc -n jupyterhub"
    fi
    
    # Ray Dashboard
    echo "Ray Dashboard: kubectl port-forward -n ray-system svc/ray-cluster-head-svc 8265:8265"
    echo "  Then access: http://localhost:8265"
    
    echo ""
    print_status "All applications deployed successfully!"
}

# Cleanup function
cleanup() {
    print_warning "Cleaning up on error..."
    # Restore original values files
    if [ -f "values/jupyterhub-values.yaml.bak" ]; then
        mv values/jupyterhub-values.yaml.bak values/jupyterhub-values.yaml
    fi
}

# Set trap for cleanup on error
trap cleanup ERR

# Main execution
main() {
    print_status "Starting fraud detection application deployment..."
    
    check_kubectl
    add_helm_repos
    get_terraform_outputs
    create_service_accounts
    deploy_jupyterhub
    deploy_kuberay_operator
    deploy_ray
    verify_deployments
    
    # Cleanup backup files
    rm -f values/*.yaml.bak
    
    print_status "Deployment completed successfully!"
}

# Run main function
main "$@"