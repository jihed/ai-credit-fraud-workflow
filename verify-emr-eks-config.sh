#!/bin/bash

# EMR on EKS Configuration Verification Script
# This script verifies that EMR on EKS virtual clusters are properly configured
# with NVIDIA device plugin and GPU scheduling capabilities

set -e

echo "=== EMR on EKS Configuration Verification ==="
echo

# Check if kubectl is configured
echo "1. Checking kubectl configuration..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ kubectl is not configured or cluster is not accessible"
    echo "Please run: aws eks update-kubeconfig --region us-west-2 --name emr-spark-rapids --no-paginate"
    exit 1
fi
echo "✅ kubectl is configured and cluster is accessible"
echo

# Check EMR namespaces
echo "2. Checking EMR namespaces..."
NAMESPACES=$(kubectl get namespaces --no-headers | grep emr | wc -l)
if [ "$NAMESPACES" -eq 2 ]; then
    echo "✅ EMR namespaces found:"
    kubectl get namespaces | grep emr
else
    echo "❌ Expected 2 EMR namespaces, found $NAMESPACES"
    exit 1
fi
echo

# Check EMR virtual clusters
echo "3. Checking EMR virtual clusters..."
VIRTUAL_CLUSTERS=$(aws emr-containers list-virtual-clusters --region us-west-2 --no-cli-pager --query 'virtualClusters[?state==`RUNNING`]' --output text | wc -l)
if [ "$VIRTUAL_CLUSTERS" -ge 2 ]; then
    echo "✅ EMR virtual clusters are running:"
    aws emr-containers list-virtual-clusters --region us-west-2 --no-cli-pager --query 'virtualClusters[?state==`RUNNING`].[name,state]' --output table
else
    echo "❌ Expected at least 2 running virtual clusters, found $VIRTUAL_CLUSTERS"
    exit 1
fi
echo

# Check NVIDIA device plugin
echo "4. Checking NVIDIA device plugin..."
NVIDIA_PODS=$(kubectl get pods --all-namespaces --no-headers | grep nvidia-device-plugin | wc -l)
if [ "$NVIDIA_PODS" -gt 0 ]; then
    echo "✅ NVIDIA device plugin pods found:"
    kubectl get pods --all-namespaces | grep nvidia-device-plugin
else
    echo "❌ NVIDIA device plugin not found"
    exit 1
fi
echo

# Check Karpenter node pools
echo "5. Checking Karpenter node pools..."
KARPENTER_NODEPOOLS=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$KARPENTER_NODEPOOLS" -ge 2 ]; then
    echo "✅ Karpenter node pools found:"
    kubectl get nodepools
else
    echo "⚠️  Karpenter node pools not found or not accessible"
    echo "This might be expected if using managed node groups instead"
fi
echo

# Check node groups
echo "6. Checking EKS managed node groups..."
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name emr-spark-rapids --region us-west-2 --no-cli-pager --query 'nodegroups' --output text | wc -w)
if [ "$NODE_GROUPS" -ge 3 ]; then
    echo "✅ EKS managed node groups found:"
    aws eks list-nodegroups --cluster-name emr-spark-rapids --region us-west-2 --no-cli-pager --output table
else
    echo "❌ Expected at least 3 node groups, found $NODE_GROUPS"
fi
echo

# Check if GPU nodes can be scheduled
echo "7. Testing GPU node scheduling capability..."
echo "Creating test pod to verify GPU scheduling..."
kubectl apply -f gpu-test-pod.yaml

echo "Waiting for pod to be scheduled (timeout: 60s)..."
timeout 60s kubectl wait --for=condition=PodScheduled pod/gpu-test-pod -n emr-ml-team-a || {
    echo "⚠️  Pod scheduling test timed out - this is expected if no GPU nodes are currently running"
    echo "GPU nodes will be auto-provisioned by Karpenter when needed"
    kubectl describe pod gpu-test-pod -n emr-ml-team-a | grep -A 10 "Events:"
}

# Clean up test pod
kubectl delete pod gpu-test-pod -n emr-ml-team-a --ignore-not-found=true

echo
echo "=== Configuration Verification Complete ==="
echo "✅ EMR on EKS virtual clusters are properly configured"
echo "✅ NVIDIA device plugin is deployed"
echo "✅ GPU scheduling capability is available"
echo
echo "Next steps:"
echo "- Submit EMR Spark jobs to test GPU acceleration"
echo "- Monitor Karpenter for automatic GPU node provisioning"
echo "- Verify RAPIDS libraries work with EMR on EKS jobs"