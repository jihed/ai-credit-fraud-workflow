#!/bin/bash

# Deploy Security and Compliance Controls for EMR to EKS Migration
# This script deploys RBAC, mTLS, encryption, and audit logging configurations

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

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_status "Starting deployment of security and compliance controls..."

# Create namespaces first
print_status "Creating namespaces..."
kubectl apply -f rbac/namespaces.yaml

# Wait for namespaces to be ready
print_status "Waiting for namespaces to be ready..."
kubectl wait --for=condition=Active namespace/ml-team-a --timeout=60s
kubectl wait --for=condition=Active namespace/ml-team-b --timeout=60s
kubectl wait --for=condition=Active namespace/fraud-detection --timeout=60s
kubectl wait --for=condition=Active namespace/ray-system --timeout=60s
kubectl wait --for=condition=Active namespace/inference --timeout=60s

# Deploy RBAC configurations
print_status "Deploying RBAC configurations..."
kubectl apply -f rbac/service-accounts.yaml
kubectl apply -f rbac/cluster-roles.yaml
kubectl apply -f rbac/role-bindings.yaml

# Deploy network policies
print_status "Deploying network policies..."
kubectl apply -f rbac/network-policies.yaml

# Check if cert-manager is installed
if ! kubectl get namespace cert-manager &> /dev/null; then
    print_warning "cert-manager namespace not found. Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    # Wait for cert-manager to be ready
    print_status "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
    kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=300s
    kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=300s
fi

# Deploy mTLS configurations
print_status "Deploying mTLS configurations..."
kubectl apply -f mtls/cert-manager.yaml

# Wait for CA certificate to be ready
print_status "Waiting for CA certificate to be ready..."
kubectl wait --for=condition=Ready certificate/fraud-detection-ca -n cert-manager --timeout=120s

# Deploy Istio mTLS policies (if Istio is installed)
if kubectl get namespace istio-system &> /dev/null; then
    print_status "Deploying Istio mTLS policies..."
    kubectl apply -f mtls/istio-mtls-policy.yaml
else
    print_warning "Istio not found. Skipping Istio mTLS policies."
fi

# Create logging namespace if it doesn't exist
if ! kubectl get namespace logging &> /dev/null; then
    print_status "Creating logging namespace..."
    kubectl create namespace logging
fi

# Deploy audit logging configurations
print_status "Deploying audit logging configurations..."
kubectl apply -f audit/application-audit-logging.yaml

# Verify deployments
print_status "Verifying security control deployments..."

# Check service accounts
print_status "Checking service accounts..."
for namespace in ml-team-a ml-team-b ray-system fraud-detection inference; do
    if kubectl get serviceaccounts -n $namespace | grep -q "emr-spark\|ray\|fraud"; then
        print_status "✓ Service accounts created in namespace: $namespace"
    else
        print_warning "⚠ Some service accounts may be missing in namespace: $namespace"
    fi
done

# Check network policies
print_status "Checking network policies..."
for namespace in ml-team-a ml-team-b ray-system fraud-detection inference; do
    if kubectl get networkpolicies -n $namespace | grep -q "default-deny-ingress"; then
        print_status "✓ Network policies applied in namespace: $namespace"
    else
        print_warning "⚠ Network policies may be missing in namespace: $namespace"
    fi
done

# Check certificates
print_status "Checking certificates..."
if kubectl get certificates -A | grep -q "fraud-detection-ca"; then
    print_status "✓ CA certificate created"
else
    print_warning "⚠ CA certificate may not be ready"
fi

# Check audit logging
print_status "Checking audit logging..."
if kubectl get daemonset fluent-bit-audit -n logging &> /dev/null; then
    print_status "✓ Audit logging DaemonSet deployed"
else
    print_warning "⚠ Audit logging DaemonSet may not be ready"
fi

print_status "Security and compliance controls deployment completed!"
print_status "Please review the following:"
print_status "1. Verify all service accounts have proper IRSA role annotations"
print_status "2. Ensure KMS keys are created in Terraform for encryption"
print_status "3. Configure EKS cluster audit logging in Terraform"
print_status "4. Review network policies for your specific requirements"
print_status "5. Test mTLS communication between services"

print_status "For validation, run: ./validate-security-controls.sh"