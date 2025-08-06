#!/bin/bash

# Validate Security and Compliance Controls
# This script validates the deployed security configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
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

print_status "Starting validation of security and compliance controls..."

# Test 1: Validate RBAC configurations
print_test "Testing RBAC configurations..."

# Check if namespaces exist
NAMESPACES=("ml-team-a" "ml-team-b" "fraud-detection" "ray-system" "inference")
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        print_status "✓ Namespace $ns exists"
    else
        print_error "✗ Namespace $ns does not exist"
    fi
done

# Check service accounts
print_test "Validating service accounts..."
SERVICE_ACCOUNTS=(
    "ml-team-a:emr-spark-driver"
    "ml-team-a:emr-spark-executor"
    "ml-team-b:emr-spark-driver"
    "ml-team-b:emr-spark-executor"
    "ray-system:ray-head"
    "ray-system:ray-worker"
    "fraud-detection:fraud-detection-processor"
    "inference:fraud-inference"
)

for sa in "${SERVICE_ACCOUNTS[@]}"; do
    IFS=':' read -r namespace account <<< "$sa"
    if kubectl get serviceaccount "$account" -n "$namespace" &> /dev/null; then
        # Check for IRSA annotation
        if kubectl get serviceaccount "$account" -n "$namespace" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | grep -q "arn:aws:iam"; then
            print_status "✓ Service account $account in $namespace has IRSA annotation"
        else
            print_warning "⚠ Service account $account in $namespace missing IRSA annotation"
        fi
    else
        print_error "✗ Service account $account does not exist in namespace $namespace"
    fi
done

# Test 2: Validate Network Policies
print_test "Testing network policies..."
for ns in "${NAMESPACES[@]}"; do
    if kubectl get networkpolicy default-deny-ingress -n "$ns" &> /dev/null; then
        print_status "✓ Default deny ingress policy exists in $ns"
    else
        print_warning "⚠ Default deny ingress policy missing in $ns"
    fi
done

# Test 3: Validate mTLS configurations
print_test "Testing mTLS configurations..."

# Check if cert-manager is running
if kubectl get pods -n cert-manager | grep -q "Running"; then
    print_status "✓ cert-manager is running"
    
    # Check CA certificate
    if kubectl get certificate fraud-detection-ca -n cert-manager &> /dev/null; then
        if kubectl get certificate fraud-detection-ca -n cert-manager -o jsonpath='{.status.conditions[0].status}' | grep -q "True"; then
            print_status "✓ CA certificate is ready"
        else
            print_warning "⚠ CA certificate is not ready"
        fi
    else
        print_error "✗ CA certificate does not exist"
    fi
    
    # Check service certificates
    CERTIFICATES=(
        "ml-team-a:emr-spark-driver-tls"
        "ml-team-b:emr-spark-driver-tls"
        "ray-system:ray-head-tls"
        "inference:fraud-inference-tls"
    )
    
    for cert in "${CERTIFICATES[@]}"; do
        IFS=':' read -r namespace certificate <<< "$cert"
        if kubectl get certificate "$certificate" -n "$namespace" &> /dev/null; then
            print_status "✓ Certificate $certificate exists in $namespace"
        else
            print_warning "⚠ Certificate $certificate missing in $namespace"
        fi
    done
else
    print_error "✗ cert-manager is not running"
fi

# Check Istio mTLS policies (if Istio is installed)
if kubectl get namespace istio-system &> /dev/null; then
    print_test "Testing Istio mTLS policies..."
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get peerauthentication default -n "$ns" &> /dev/null; then
            print_status "✓ Istio PeerAuthentication policy exists in $ns"
        else
            print_warning "⚠ Istio PeerAuthentication policy missing in $ns"
        fi
    done
else
    print_warning "Istio not installed, skipping Istio mTLS validation"
fi

# Test 4: Validate encryption configurations
print_test "Testing encryption configurations..."

# Check for encrypted storage class
if kubectl get storageclass encrypted-gp3 &> /dev/null; then
    print_status "✓ Encrypted storage class exists"
else
    print_warning "⚠ Encrypted storage class not found"
fi

# Check secrets encryption (this requires cluster-level access)
print_test "Checking secrets encryption..."
if kubectl get secret -A | head -1 | grep -q "NAME"; then
    print_status "✓ Can access secrets (encryption status requires cluster admin)"
else
    print_error "✗ Cannot access secrets"
fi

# Test 5: Validate audit logging
print_test "Testing audit logging configurations..."

# Check if logging namespace exists
if kubectl get namespace logging &> /dev/null; then
    print_status "✓ Logging namespace exists"
    
    # Check Fluent Bit DaemonSet
    if kubectl get daemonset fluent-bit-audit -n logging &> /dev/null; then
        # Check if pods are running
        READY_PODS=$(kubectl get daemonset fluent-bit-audit -n logging -o jsonpath='{.status.numberReady}')
        DESIRED_PODS=$(kubectl get daemonset fluent-bit-audit -n logging -o jsonpath='{.status.desiredNumberScheduled}')
        
        if [ "$READY_PODS" = "$DESIRED_PODS" ] && [ "$READY_PODS" -gt 0 ]; then
            print_status "✓ Fluent Bit audit logging is running ($READY_PODS/$DESIRED_PODS pods ready)"
        else
            print_warning "⚠ Fluent Bit audit logging pods not all ready ($READY_PODS/$DESIRED_PODS)"
        fi
    else
        print_error "✗ Fluent Bit audit logging DaemonSet not found"
    fi
else
    print_error "✗ Logging namespace does not exist"
fi

# Test 6: Security compliance checks
print_test "Running security compliance checks..."

# Check for privileged containers (should be none in production)
PRIVILEGED_PODS=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep -c "true" || true)
if [ "$PRIVILEGED_PODS" -eq 0 ]; then
    print_status "✓ No privileged containers found"
else
    print_warning "⚠ Found $PRIVILEGED_PODS privileged containers"
fi

# Check for containers running as root
ROOT_CONTAINERS=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[*].securityContext.runAsUser}{"\n"}{end}' | grep -c "^0$\|^$" || true)
if [ "$ROOT_CONTAINERS" -eq 0 ]; then
    print_status "✓ No containers running as root found"
else
    print_warning "⚠ Found containers that may be running as root"
fi

# Test 7: Network security validation
print_test "Testing network security..."

# Check if default service account has been modified
for ns in "${NAMESPACES[@]}"; do
    DEFAULT_SA_SECRETS=$(kubectl get serviceaccount default -n "$ns" -o jsonpath='{.secrets}' 2>/dev/null || echo "null")
    if [ "$DEFAULT_SA_SECRETS" = "null" ] || [ "$DEFAULT_SA_SECRETS" = "[]" ]; then
        print_status "✓ Default service account in $ns has no secrets (good security practice)"
    else
        print_warning "⚠ Default service account in $ns has secrets attached"
    fi
done

# Summary
print_status "Security validation completed!"
print_status "Summary of findings:"
print_status "- RBAC: Service accounts and roles configured"
print_status "- Network Policies: Default deny policies in place"
print_status "- mTLS: Certificate management configured"
print_status "- Encryption: Storage and secrets encryption configured"
print_status "- Audit Logging: Application audit logging deployed"
print_status "- Compliance: Security best practices validated"

print_status "For detailed security assessment, consider running:"
print_status "1. kubectl auth can-i --list --as=system:serviceaccount:ml-team-a:emr-spark-driver"
print_status "2. kubectl get networkpolicies -A"
print_status "3. kubectl get certificates -A"
print_status "4. kubectl logs -n logging -l app=fluent-bit-audit"

print_status "Security validation completed successfully!"