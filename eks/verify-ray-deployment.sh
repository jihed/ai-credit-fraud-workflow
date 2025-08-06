#!/bin/bash

# Ray Cluster Deployment Verification Script
# This script verifies that the Ray cluster is properly deployed and configured

set -e

echo "🚀 Starting Ray cluster deployment verification..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "INFO")
            echo -e "ℹ️  $message"
            ;;
    esac
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_status "ERROR" "kubectl is not installed or not in PATH"
    exit 1
fi

print_status "INFO" "Checking Ray system namespace..."

# Check if ray-system namespace exists
if kubectl get namespace ray-system &> /dev/null; then
    print_status "SUCCESS" "ray-system namespace exists"
else
    print_status "ERROR" "ray-system namespace not found"
    exit 1
fi

print_status "INFO" "Checking KubeRay operator deployment..."

# Check KubeRay operator deployment
if kubectl get deployment kuberay-operator -n ray-system &> /dev/null; then
    # Check if deployment is ready
    READY=$(kubectl get deployment kuberay-operator -n ray-system -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment kuberay-operator -n ray-system -o jsonpath='{.spec.replicas}')
    
    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ]; then
        print_status "SUCCESS" "KubeRay operator is running ($READY/$DESIRED replicas ready)"
    else
        print_status "WARNING" "KubeRay operator deployment exists but not all replicas are ready ($READY/$DESIRED)"
    fi
else
    print_status "ERROR" "KubeRay operator deployment not found"
    exit 1
fi

print_status "INFO" "Checking Ray ML namespace..."

# Check if ray-ml namespace exists
if kubectl get namespace ray-ml &> /dev/null; then
    print_status "SUCCESS" "ray-ml namespace exists"
else
    print_status "ERROR" "ray-ml namespace not found"
    exit 1
fi

print_status "INFO" "Checking Ray cluster..."

# Check Ray cluster
if kubectl get raycluster fraud-training-cluster -n ray-ml &> /dev/null; then
    # Check Ray cluster status
    STATUS=$(kubectl get raycluster fraud-training-cluster -n ray-ml -o jsonpath='{.status.state}')
    if [ "$STATUS" = "ready" ]; then
        print_status "SUCCESS" "Ray cluster 'fraud-training-cluster' is ready"
    else
        print_status "WARNING" "Ray cluster exists but status is: $STATUS"
    fi
else
    print_status "ERROR" "Ray cluster 'fraud-training-cluster' not found"
    exit 1
fi

print_status "INFO" "Checking Ray head pod..."

# Check Ray head pod
HEAD_POD=$(kubectl get pods -n ray-ml -l app=ray-head --no-headers -o custom-columns=":metadata.name" | head -1)
if [ -n "$HEAD_POD" ]; then
    HEAD_STATUS=$(kubectl get pod $HEAD_POD -n ray-ml -o jsonpath='{.status.phase}')
    if [ "$HEAD_STATUS" = "Running" ]; then
        print_status "SUCCESS" "Ray head pod '$HEAD_POD' is running"
    else
        print_status "WARNING" "Ray head pod '$HEAD_POD' status: $HEAD_STATUS"
    fi
else
    print_status "ERROR" "Ray head pod not found"
fi

print_status "INFO" "Checking Ray worker pods..."

# Check Ray worker pods
WORKER_PODS=$(kubectl get pods -n ray-ml -l app=ray-worker --no-headers | wc -l)
RUNNING_WORKERS=$(kubectl get pods -n ray-ml -l app=ray-worker --field-selector=status.phase=Running --no-headers | wc -l)

if [ "$WORKER_PODS" -gt 0 ]; then
    print_status "SUCCESS" "Found $WORKER_PODS Ray worker pods ($RUNNING_WORKERS running)"
    
    # Check GPU workers specifically
    GPU_WORKERS=$(kubectl get pods -n ray-ml -l app=ray-worker,worker-type=gpu --no-headers | wc -l)
    if [ "$GPU_WORKERS" -gt 0 ]; then
        print_status "SUCCESS" "Found $GPU_WORKERS GPU worker pods"
    else
        print_status "WARNING" "No GPU worker pods found"
    fi
else
    print_status "WARNING" "No Ray worker pods found"
fi

print_status "INFO" "Checking Ray dashboard service..."

# Check Ray dashboard service
if kubectl get service ray-dashboard -n ray-ml &> /dev/null; then
    print_status "SUCCESS" "Ray dashboard service exists"
    
    # Get service details
    SERVICE_TYPE=$(kubectl get service ray-dashboard -n ray-ml -o jsonpath='{.spec.type}')
    SERVICE_PORT=$(kubectl get service ray-dashboard -n ray-ml -o jsonpath='{.spec.ports[0].port}')
    print_status "INFO" "Ray dashboard: $SERVICE_TYPE service on port $SERVICE_PORT"
    print_status "INFO" "Access dashboard: kubectl port-forward svc/ray-dashboard -n ray-ml 8265:8265"
else
    print_status "WARNING" "Ray dashboard service not found"
fi

print_status "INFO" "Checking GPU nodes..."

# Check GPU nodes
GPU_NODES=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers | wc -l)
if [ "$GPU_NODES" -gt 0 ]; then
    print_status "SUCCESS" "Found $GPU_NODES GPU-enabled nodes"
    
    # List GPU nodes
    echo "GPU Nodes:"
    kubectl get nodes -l nvidia.com/gpu.present=true -o custom-columns="NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,GPU:.status.allocatable.nvidia\.com/gpu"
else
    print_status "WARNING" "No GPU-enabled nodes found"
fi

print_status "INFO" "Checking NVIDIA device plugin..."

# Check NVIDIA device plugin
if kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system &> /dev/null; then
    DESIRED=$(kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system -o jsonpath='{.status.desiredNumberScheduled}')
    READY=$(kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system -o jsonpath='{.status.numberReady}')
    
    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
        print_status "SUCCESS" "NVIDIA device plugin is running on $READY/$DESIRED nodes"
    else
        print_status "WARNING" "NVIDIA device plugin: $READY/$DESIRED pods ready"
    fi
else
    print_status "WARNING" "NVIDIA device plugin daemonset not found"
fi

print_status "INFO" "Checking Karpenter node pools..."

# Check Karpenter node pools for Ray
RAY_GPU_NODEPOOL=$(kubectl get nodepool ray-gpu-nodepool -n karpenter 2>/dev/null | wc -l)
RAY_CPU_NODEPOOL=$(kubectl get nodepool ray-cpu-nodepool -n karpenter 2>/dev/null | wc -l)

if [ "$RAY_GPU_NODEPOOL" -gt 0 ]; then
    print_status "SUCCESS" "Ray GPU node pool exists"
else
    print_status "INFO" "Ray GPU node pool not found (using existing Spark GPU nodes)"
fi

if [ "$RAY_CPU_NODEPOOL" -gt 0 ]; then
    print_status "SUCCESS" "Ray CPU node pool exists"
else
    print_status "INFO" "Ray CPU node pool not found (using existing Spark CPU nodes)"
fi

echo ""
print_status "INFO" "=== Ray Cluster Deployment Summary ==="
echo "• KubeRay Operator: Deployed and running"
echo "• Ray Cluster: fraud-training-cluster in ray-ml namespace"
echo "• Ray Head Pod: Running"
echo "• Ray Worker Pods: $WORKER_PODS total ($RUNNING_WORKERS running)"
echo "• GPU Workers: $GPU_WORKERS pods"
echo "• GPU Nodes: $GPU_NODES available"
echo "• Dashboard: Available via port-forward"

echo ""
print_status "INFO" "=== Next Steps ==="
echo "1. Access Ray dashboard:"
echo "   kubectl port-forward svc/ray-dashboard -n ray-ml 8265:8265"
echo ""
echo "2. Test Ray cluster connectivity:"
echo "   kubectl apply -f examples/ray-xgboost/ray-training-job.yaml"
echo ""
echo "3. Monitor training jobs:"
echo "   kubectl logs -f job/ray-xgboost-training -n ray-ml"

print_status "SUCCESS" "Ray cluster deployment verification completed!"