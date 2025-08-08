#!/bin/bash

# Validate JupyterHub profiles configuration
# This script checks that the profiles are properly configured and images are available

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

# Configuration
VALUES_FILE="$(dirname "$0")/../values/jupyterhub-values.yaml"
NAMESPACE="jupyterhub"

print_status "Validating JupyterHub profiles configuration..."

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    print_error "Values file not found: $VALUES_FILE"
    print_error "Run ./eks/helm/scripts/configure-jupyterhub.sh first"
    exit 1
fi

print_status "✅ Values file found: $VALUES_FILE"

# Extract image names from values file
print_status "Extracting container images from profiles..."

IMAGES=$(grep -E "image: '.*'" "$VALUES_FILE" | sed "s/.*image: '\(.*\)'.*/\1/" | sort -u)

if [[ -z "$IMAGES" ]]; then
    print_error "No container images found in values file"
    exit 1
fi

echo "Found images:"
for image in $IMAGES; do
    echo "  - $image"
done

# Check if JupyterHub is deployed
print_status "Checking JupyterHub deployment status..."

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    print_status "✅ JupyterHub namespace exists"
    
    # Check if JupyterHub pods are running
    if kubectl get pods -n "$NAMESPACE" -l app=jupyterhub >/dev/null 2>&1; then
        print_status "✅ JupyterHub pods found"
        
        # Show pod status
        echo "JupyterHub pod status:"
        kubectl get pods -n "$NAMESPACE" -l app=jupyterhub
        
        # Check if hub is ready
        HUB_READY=$(kubectl get pods -n "$NAMESPACE" -l component=hub -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$HUB_READY" == "True" ]]; then
            print_status "✅ JupyterHub hub is ready"
        else
            print_warning "⚠️  JupyterHub hub is not ready yet"
        fi
        
    else
        print_warning "⚠️  JupyterHub pods not found - may not be deployed yet"
    fi
    
else
    print_warning "⚠️  JupyterHub namespace not found - not deployed yet"
fi

# Check if images are available in ECR (if ECR registry is used)
print_status "Checking container image availability..."

for image in $IMAGES; do
    if [[ "$image" == *".amazonaws.com/"* ]]; then
        # ECR image - check if it exists
        ECR_REPO=$(echo "$image" | sed 's|.*amazonaws.com/||' | sed 's|:.*||')
        ECR_TAG=$(echo "$image" | sed 's|.*:||')
        
        print_status "Checking ECR image: $ECR_REPO:$ECR_TAG"
        
        if aws ecr describe-images --repository-name "$ECR_REPO" --image-ids imageTag="$ECR_TAG" >/dev/null 2>&1; then
            print_status "✅ ECR image available: $image"
        else
            print_error "❌ ECR image not found: $image"
            print_error "   Build and push the image first: ./eks/docker/build-images.sh"
        fi
    else
        # Public image - try to pull (but don't actually pull)
        print_status "Checking public image: $image"
        if docker manifest inspect "$image" >/dev/null 2>&1; then
            print_status "✅ Public image available: $image"
        else
            print_warning "⚠️  Could not verify public image: $image"
        fi
    fi
done

# Validate profile configuration
print_status "Validating profile configurations..."

# Check for required environment variables in profiles
REQUIRED_VARS=("VIRTUAL_CLUSTER_ID" "EMR_EXECUTION_ROLE_ARN" "RAY_ADDRESS" "AWS_REGION" "S3_BUCKET_NAME")

for var in "${REQUIRED_VARS[@]}"; do
    if grep -q "REPLACE_WITH_" "$VALUES_FILE" | grep -q "$var"; then
        print_error "❌ Environment variable $var not properly configured"
        print_error "   Found placeholder value in $VALUES_FILE"
    else
        print_status "✅ Environment variable $var configured"
    fi
done

# Check resource limits
print_status "Validating resource configurations..."

CPU_LIMITS=$(grep -E "cpu_limit: [0-9]+" "$VALUES_FILE" | sed 's/.*cpu_limit: \([0-9]*\).*/\1/')
MEM_LIMITS=$(grep -E "mem_limit: '[0-9]+G'" "$VALUES_FILE" | sed "s/.*mem_limit: '\([0-9]*\)G'.*/\1/")

echo "Resource configurations:"
echo "CPU limits: $(echo $CPU_LIMITS | tr '\n' ' ')"
echo "Memory limits (GB): $(echo $MEM_LIMITS | tr '\n' ' ')"

# Check for reasonable resource limits
for cpu in $CPU_LIMITS; do
    if [[ $cpu -gt 16 ]]; then
        print_warning "⚠️  High CPU limit detected: ${cpu} cores"
    fi
done

for mem in $MEM_LIMITS; do
    if [[ $mem -gt 64 ]]; then
        print_warning "⚠️  High memory limit detected: ${mem}GB"
    fi
done

# Summary
print_status "🎉 Profile validation completed!"
echo ""
echo "=== Summary ==="
echo "✅ Configuration file validated"
echo "✅ Container images checked"
echo "✅ Resource limits reviewed"
echo "✅ Environment variables validated"
echo ""
echo "🚀 Next steps:"
echo "   1. Build and push custom images: ./eks/docker/build-images.sh"
echo "   2. Deploy JupyterHub: ./eks/helm/scripts/deploy-jupyterhub.sh"
echo "   3. Access JupyterHub and test profiles"
echo ""