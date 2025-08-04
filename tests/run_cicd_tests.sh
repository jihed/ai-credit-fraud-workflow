#!/bin/bash

# CI/CD pipeline tests runner
# Tests deployment automation, validation, and rollback mechanisms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports/ci-cd"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$REPORTS_DIR"

echo -e "${BLUE}Running CI/CD Pipeline Tests...${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Reports: $REPORTS_DIR"
echo ""

# Set environment variables
export PYTHONPATH="$SCRIPT_DIR/..:$PYTHONPATH"
export TEST_REPORTS_DIR="$REPORTS_DIR"

# Configuration
CLUSTER_NAME=${EKS_CLUSTER_NAME:-"data-on-eks-cluster"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
NAMESPACE=${KUBERNETES_NAMESPACE:-"ml-team-a"}
REGISTRY_URL=${ECR_REGISTRY_URL:-"123456789012.dkr.ecr.us-west-2.amazonaws.com"}

echo -e "${YELLOW}Configuration:${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Namespace: $NAMESPACE"
echo "Registry: $REGISTRY_URL"
echo ""

# Check prerequisites
echo "Checking CI/CD prerequisites..."

# Check kubectl
if command -v kubectl &> /dev/null; then
    echo "✓ kubectl found"
    # Try to get cluster info (will fail gracefully if not connected)
    if kubectl cluster-info &> /dev/null; then
        echo "✓ kubectl connected to cluster"
    else
        echo "⚠ kubectl not connected - tests will use mocked responses"
    fi
else
    echo "⚠ kubectl not found - tests will use mocked responses"
fi

# Check terraform
if command -v terraform &> /dev/null; then
    echo "✓ terraform found"
else
    echo "⚠ terraform not found - tests will use mocked responses"
fi

# Check docker
if command -v docker &> /dev/null; then
    echo "✓ docker found"
else
    echo "⚠ docker not found - tests will use mocked responses"
fi

echo ""

# Export configuration for the test script
export EKS_CLUSTER_NAME="$CLUSTER_NAME"
export AWS_REGION
export KUBERNETES_NAMESPACE="$NAMESPACE"
export ECR_REGISTRY_URL="$REGISTRY_URL"

# Run CI/CD tests
cd "$SCRIPT_DIR"
python3 ci-cd/test_pipeline.py

echo -e "${GREEN}✓ CI/CD pipeline tests completed${NC}"
echo "Reports saved to: $REPORTS_DIR"
echo ""
echo "Generated files:"
ls -la "$REPORTS_DIR"