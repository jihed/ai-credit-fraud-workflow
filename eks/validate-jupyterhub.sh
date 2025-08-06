#!/bin/bash

# Validate JupyterHub deployment and functionality
set -e

echo "🔍 Validating JupyterHub deployment..."

NAMESPACE="jupyterhub"
CLUSTER_NAME=${1:-data-on-eks}
AWS_REGION=${AWS_DEFAULT_REGION:-us-west-2}

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

echo "📋 Checking JupyterHub components..."

# Check namespace
if kubectl get namespace $NAMESPACE &>/dev/null; then
    echo "✅ Namespace '$NAMESPACE' exists"
else
    echo "❌ Namespace '$NAMESPACE' not found"
    exit 1
fi

# Check pods
echo "🔍 Checking pod status..."
kubectl get pods -n $NAMESPACE

# Check if hub is running
HUB_POD=$(kubectl get pods -n $NAMESPACE -l app=jupyterhub,component=hub -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HUB_POD" ]; then
    HUB_STATUS=$(kubectl get pod $HUB_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$HUB_STATUS" = "Running" ]; then
        echo "✅ JupyterHub hub is running"
    else
        echo "❌ JupyterHub hub status: $HUB_STATUS"
        kubectl describe pod $HUB_POD -n $NAMESPACE
    fi
else
    echo "❌ JupyterHub hub pod not found"
fi

# Check proxy
PROXY_POD=$(kubectl get pods -n $NAMESPACE -l app=jupyterhub,component=proxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PROXY_POD" ]; then
    PROXY_STATUS=$(kubectl get pod $PROXY_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$PROXY_STATUS" = "Running" ]; then
        echo "✅ JupyterHub proxy is running"
    else
        echo "❌ JupyterHub proxy status: $PROXY_STATUS"
    fi
else
    echo "❌ JupyterHub proxy pod not found"
fi

# Check services
echo "🔍 Checking services..."
kubectl get svc -n $NAMESPACE

# Check load balancer
LB_HOSTNAME=$(kubectl get svc proxy-public -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$LB_HOSTNAME" ]; then
    echo "✅ Load balancer hostname: $LB_HOSTNAME"
    
    # Test connectivity
    echo "🌐 Testing JupyterHub connectivity..."
    if curl -s --connect-timeout 10 "http://$LB_HOSTNAME" > /dev/null; then
        echo "✅ JupyterHub is accessible"
    else
        echo "⚠️ JupyterHub may not be fully ready yet"
    fi
else
    echo "⚠️ Load balancer not ready yet"
fi

# Check persistent volumes
echo "🔍 Checking storage..."
kubectl get pvc -n $NAMESPACE

# Check shared data PVC
SHARED_PVC=$(kubectl get pvc jupyterhub-shared-data -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$SHARED_PVC" = "Bound" ]; then
    echo "✅ Shared data PVC is bound"
else
    echo "❌ Shared data PVC status: $SHARED_PVC"
fi

# Check ConfigMap with templates
echo "🔍 Checking notebook templates..."
if kubectl get configmap notebook-templates -n $NAMESPACE &>/dev/null; then
    echo "✅ Notebook templates ConfigMap exists"
    TEMPLATE_COUNT=$(kubectl get configmap notebook-templates -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys | length')
    echo "📚 Number of templates: $TEMPLATE_COUNT"
else
    echo "❌ Notebook templates ConfigMap not found"
fi

# Check RBAC
echo "🔍 Checking RBAC..."
if kubectl get serviceaccount jupyterhub-notebook-sa -n $NAMESPACE &>/dev/null; then
    echo "✅ JupyterHub notebook service account exists"
    
    # Check IRSA annotation
    IRSA_ROLE=$(kubectl get serviceaccount jupyterhub-notebook-sa -n $NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    if [ -n "$IRSA_ROLE" ]; then
        echo "✅ IRSA role configured: $IRSA_ROLE"
    else
        echo "⚠️ IRSA role not configured"
    fi
else
    echo "❌ JupyterHub notebook service account not found"
fi

# Check ECR repository
echo "🔍 Checking ECR repository..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/jupyterhub-rapids"

if aws ecr describe-repositories --repository-names jupyterhub-rapids --region $AWS_REGION &>/dev/null; then
    echo "✅ ECR repository exists: $ECR_REPO"
    
    # Check if image exists
    if aws ecr describe-images --repository-name jupyterhub-rapids --region $AWS_REGION --image-ids imageTag=latest &>/dev/null; then
        echo "✅ JupyterHub RAPIDS image exists"
    else
        echo "⚠️ JupyterHub RAPIDS image not found - run ./build-jupyterhub-image.sh"
    fi
else
    echo "❌ ECR repository not found"
fi

# Check GPU nodes
echo "🔍 Checking GPU nodes..."
GPU_NODES=$(kubectl get nodes -l nvidia.com/gpu=true --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -gt 0 ]; then
    echo "✅ GPU nodes available: $GPU_NODES"
else
    echo "⚠️ No GPU nodes found - notebooks may not have GPU access"
fi

# Summary
echo ""
echo "📊 Validation Summary:"
echo "====================="

if [ -n "$HUB_POD" ] && [ "$HUB_STATUS" = "Running" ] && [ -n "$PROXY_POD" ] && [ "$PROXY_STATUS" = "Running" ]; then
    echo "✅ JupyterHub is running successfully"
    
    if [ -n "$LB_HOSTNAME" ]; then
        echo "🌐 Access URL: http://$LB_HOSTNAME"
        echo "👤 Login: admin / fraud-detection-demo"
    fi
    
    echo ""
    echo "🚀 Ready to use! Try these notebooks:"
    echo "- templates/emr-spark-rapids-example.ipynb"
    echo "- templates/ray-xgboost-training.ipynb"
    echo "- templates/fraud-detection-pipeline.ipynb"
else
    echo "❌ JupyterHub is not fully ready"
    echo "Check the pod logs for more details:"
    echo "kubectl logs -n $NAMESPACE -l app=jupyterhub,component=hub"
fi