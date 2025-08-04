#!/bin/bash

# Deploy JupyterHub on EKS with RAPIDS support
set -e

echo "🚀 Deploying JupyterHub for Fraud Detection on EKS..."

# Configuration
CLUSTER_NAME=${1:-data-on-eks}
AWS_REGION=${AWS_DEFAULT_REGION:-us-west-2}
NAMESPACE="jupyterhub"

echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Namespace: $NAMESPACE"

# Update kubeconfig
echo "📋 Updating kubeconfig..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Check if cluster is accessible
echo "🔍 Checking cluster connectivity..."
kubectl cluster-info

# Build and push JupyterHub RAPIDS image
echo "🐳 Building JupyterHub RAPIDS image..."
./build-jupyterhub-image.sh

# Apply Terraform configuration for JupyterHub
echo "🏗️ Applying Terraform configuration..."
terraform plan -target=module.jupyterhub_irsa -target=aws_efs_file_system.jupyterhub_shared -target=helm_release.jupyterhub
terraform apply -target=module.jupyterhub_irsa -target=aws_efs_file_system.jupyterhub_shared -target=helm_release.jupyterhub -auto-approve

# Wait for JupyterHub to be ready
echo "⏳ Waiting for JupyterHub to be ready..."
kubectl wait --for=condition=ready pod -l app=jupyterhub,component=hub -n $NAMESPACE --timeout=300s

# Get JupyterHub service information
echo "📊 JupyterHub deployment status:"
kubectl get pods,svc,pvc -n $NAMESPACE

# Get load balancer URL
LB_HOSTNAME=$(kubectl get svc proxy-public -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -n "$LB_HOSTNAME" ]; then
    echo "🌐 JupyterHub URL: http://$LB_HOSTNAME"
    echo "👤 Login credentials:"
    echo "   Username: admin (or data-scientist, ml-engineer)"
    echo "   Password: fraud-detection-demo"
else
    echo "⚠️ Load balancer not ready yet. Check again in a few minutes:"
    echo "kubectl get svc proxy-public -n $NAMESPACE"
fi

# Show notebook templates
echo "📚 Available notebook templates:"
kubectl get configmap notebook-templates -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]'

echo "✅ JupyterHub deployment complete!"
echo ""
echo "🔗 Next steps:"
echo "1. Access JupyterHub at the URL above"
echo "2. Start a new notebook server (GPU-enabled)"
echo "3. Open one of the template notebooks:"
echo "   - templates/emr-spark-rapids-example.ipynb"
echo "   - templates/ray-xgboost-training.ipynb"
echo "   - templates/fraud-detection-pipeline.ipynb"
echo ""
echo "📖 Documentation:"
echo "- EMR on EKS: https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/"
echo "- Ray on Kubernetes: https://docs.ray.io/en/latest/cluster/kubernetes/index.html"
echo "- RAPIDS: https://rapids.ai/"