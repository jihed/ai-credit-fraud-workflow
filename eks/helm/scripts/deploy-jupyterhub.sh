#!/bin/bash

# Deploy JupyterHub on EKS for fraud detection demo
# This script installs JupyterHub with custom configuration for EMR on EKS and Ray integration

set -e

# Configuration
NAMESPACE="jupyterhub"
RELEASE_NAME="jupyterhub"
CHART_VERSION="3.2.1"
VALUES_FILE="$(dirname "$0")/../values/jupyterhub-values.yaml"
MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo "🚀 Deploying JupyterHub for fraud detection demo..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ helm is not installed or not in PATH"
    exit 1
fi

# Check if we're connected to the right cluster
echo "📋 Current Kubernetes context:"
kubectl config current-context

read -p "Is this the correct EKS cluster for fraud detection? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please switch to the correct Kubernetes context and try again"
    exit 1
fi

# Add JupyterHub Helm repository
echo "📦 Adding JupyterHub Helm repository..."
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update

# Apply Kubernetes manifests first
echo "🔧 Applying Kubernetes manifests..."
kubectl apply -f "$MANIFESTS_DIR/jupyterhub-namespace.yaml"
kubectl apply -f "$MANIFESTS_DIR/jupyterhub-service-account.yaml"

# Wait for namespace to be ready
echo "⏳ Waiting for namespace to be ready..."
kubectl wait --for=condition=Active namespace/$NAMESPACE --timeout=60s

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    echo "❌ Values file not found: $VALUES_FILE"
    exit 1
fi

# Install or upgrade JupyterHub
echo "🎯 Installing JupyterHub..."
helm upgrade --install $RELEASE_NAME jupyterhub/jupyterhub \
    --namespace $NAMESPACE \
    --values "$VALUES_FILE" \
    --version $CHART_VERSION \
    --timeout 10m \
    --wait

# Check deployment status
echo "✅ Checking JupyterHub deployment status..."
kubectl get pods -n $NAMESPACE
kubectl get services -n $NAMESPACE

# Get the LoadBalancer URL
echo "🌐 Getting JupyterHub access URL..."
EXTERNAL_IP=""
while [ -z $EXTERNAL_IP ]; do
    echo "⏳ Waiting for external IP..."
    EXTERNAL_IP=$(kubectl get svc proxy-public -n $NAMESPACE --template="{{range .status.loadBalancer.ingress}}{{.hostname}}{{.ip}}{{end}}")
    [ -z "$EXTERNAL_IP" ] && sleep 10
done

echo ""
echo "🎉 JupyterHub deployment completed successfully!"
echo ""
echo "📋 Access Information:"
echo "   URL: http://$EXTERNAL_IP"
echo "   Username: Any username (demo mode)"
echo "   Password: fraud-detection-demo"
echo ""
echo "📊 Available Notebook Profiles:"
echo "   1. Fraud Detection - Data Processing (EMR Spark + RAPIDS)"
echo "   2. Fraud Detection - ML Training (Ray + XGBoost)"
echo "   3. Fraud Detection - GPU Accelerated (RAPIDS + GPU)"
echo "   4. Fraud Detection - Unified (Spark + Ray)"
echo ""
echo "🔧 Next Steps:"
echo "   1. Access JupyterHub using the URL above"
echo "   2. Select appropriate notebook profile for your workload"
echo "   3. Upload or create notebooks for fraud detection"
echo "   4. Configure EMR virtual cluster ID and Ray cluster address if needed"
echo ""
echo "📝 Configuration Files:"
echo "   - Values: $VALUES_FILE"
echo "   - Manifests: $MANIFESTS_DIR/"
echo ""

# Show resource usage
echo "📊 Resource Usage:"
kubectl top nodes 2>/dev/null || echo "   (Metrics server not available)"
kubectl get resourcequota -n $NAMESPACE

echo "✨ JupyterHub is ready for fraud detection workloads!"