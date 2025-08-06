#!/bin/bash

# Install ArgoCD for GitOps deployment
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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured or cluster is not accessible"
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Install ArgoCD
install_argocd() {
    print_status "Installing ArgoCD..."
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    print_status "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
    
    print_status "ArgoCD installed successfully!"
}

# Configure ArgoCD
configure_argocd() {
    print_status "Configuring ArgoCD..."
    
    # Patch ArgoCD server to use LoadBalancer (optional)
    read -p "Do you want to expose ArgoCD via LoadBalancer? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
        print_status "ArgoCD server exposed via LoadBalancer"
    else
        print_status "ArgoCD server will be accessible via port-forward only"
    fi
    
    # Configure ArgoCD to work with private repositories (if needed)
    print_status "ArgoCD configuration completed"
}

# Install ArgoCD CLI
install_argocd_cli() {
    print_status "Installing ArgoCD CLI..."
    
    # Check if argocd CLI is already installed
    if command -v argocd &> /dev/null; then
        print_status "ArgoCD CLI is already installed"
        return
    fi
    
    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) print_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    # Download and install ArgoCD CLI
    ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-$OS-$ARCH
    chmod +x argocd
    sudo mv argocd /usr/local/bin/
    
    print_status "ArgoCD CLI installed successfully!"
}

# Get access information
get_access_info() {
    print_status "Getting ArgoCD access information..."
    
    # Get admin password
    ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    # Check if LoadBalancer is configured
    LB_HOSTNAME=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    echo ""
    echo "=== ArgoCD Access Information ==="
    echo "Username: admin"
    echo "Password: $ADMIN_PASSWORD"
    echo ""
    
    if [ ! -z "$LB_HOSTNAME" ]; then
        echo "ArgoCD UI: https://$LB_HOSTNAME"
        echo "Note: It may take a few minutes for the LoadBalancer to be ready"
    else
        echo "ArgoCD UI: Use port-forward to access"
        echo "Command: kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo "URL: https://localhost:8080"
    fi
    
    echo ""
    echo "=== ArgoCD CLI Login ==="
    if [ ! -z "$LB_HOSTNAME" ]; then
        echo "argocd login $LB_HOSTNAME --username admin --password '$ADMIN_PASSWORD' --insecure"
    else
        echo "# In another terminal, run port-forward:"
        echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo ""
        echo "# Then login:"
        echo "argocd login localhost:8080 --username admin --password '$ADMIN_PASSWORD' --insecure"
    fi
    
    echo ""
    print_status "ArgoCD is ready for use!"
}

# Main execution
main() {
    print_status "Starting ArgoCD installation..."
    
    check_prerequisites
    install_argocd
    configure_argocd
    install_argocd_cli
    get_access_info
    
    print_status "ArgoCD installation completed successfully!"
    print_warning "Save the admin password in a secure location!"
}

# Run main function
main "$@"