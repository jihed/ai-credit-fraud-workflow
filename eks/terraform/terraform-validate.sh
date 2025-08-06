#!/bin/bash

# Terraform-Only Validation Script for EMR to EKS Migration
# This script validates all components deployed via Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Starting Terraform Deployment Validation${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check resource status
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-"default"}
    
    if kubectl get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $resource_type/$resource_name found in namespace $namespace${NC}"
        return 0
    else
        echo -e "${RED}❌ $resource_type/$resource_name not found in namespace $namespace${NC}"
        return 1
    fi
}

# Function to check pod readiness
check_pod_readiness() {
    local label_selector=$1
    local namespace=$2
    local timeout=${3:-300}
    
    echo -e "${YELLOW}⏳ Waiting for pods with selector '$label_selector' in namespace '$namespace'...${NC}"
    if kubectl wait --for=condition=ready pod -l "$label_selector" -n "$namespace" --timeout="${timeout}s" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Pods with selector '$label_selector' are ready in namespace '$namespace'${NC}"
        return 0
    else
        echo -e "${RED}❌ Pods with selector '$label_selector' are not ready in namespace '$namespace'${NC}"
        return 1
    fi
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
if ! command_exists kubectl; then
    echo -e "${RED}❌ kubectl is required but not installed${NC}"
    exit 1
fi

# Verify cluster connection
echo -e "${YELLOW}🔐 Verifying cluster connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    echo -e "${YELLOW}💡 Make sure to run: aws eks update-kubeconfig --region <region> --name <cluster-name> --no-paginate${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"

# Initialize counters
total_checks=0
passed_checks=0

# Function to run check and update counters
run_check() {
    total_checks=$((total_checks + 1))
    if "$@"; then
        passed_checks=$((passed_checks + 1))
    fi
}

echo -e "${BLUE}🏗️ Validating Core Infrastructure${NC}"

# Check nodes
echo -e "${YELLOW}Checking cluster nodes...${NC}"
kubectl get nodes
run_check kubectl get nodes --no-headers | grep -q Ready

# Check core namespaces
echo -e "${YELLOW}Checking core namespaces...${NC}"
run_check check_resource namespace kube-system
run_check check_resource namespace karpenter

echo -e "${BLUE}🔧 Validating EKS Blueprint Addons${NC}"

# Check AWS Load Balancer Controller
run_check check_resource deployment aws-load-balancer-controller kube-system

# Check Metrics Server
run_check check_resource deployment metrics-server kube-system

# Check Karpenter
run_check check_resource deployment karpenter karpenter

# Check EBS CSI Driver
run_check check_resource daemonset ebs-csi-node kube-system

# Check EFS CSI Driver
run_check check_resource daemonset efs-csi-node kube-system

echo -e "${BLUE}📊 Validating Monitoring Stack${NC}"

# Check Prometheus and Grafana
if kubectl get namespace kube-prometheus-stack >/dev/null 2>&1; then
    run_check check_resource deployment kube-prometheus-stack-grafana kube-prometheus-stack
    run_check check_resource statefulset prometheus-kube-prometheus-stack-prometheus kube-prometheus-stack
    run_check check_pod_readiness "app.kubernetes.io/name=grafana" kube-prometheus-stack
else
    echo -e "${YELLOW}⚠️ Prometheus stack namespace not found - monitoring may be disabled${NC}"
fi

# Check Kubecost
if kubectl get namespace kubecost >/dev/null 2>&1; then
    run_check check_resource deployment kubecost-cost-analyzer kubecost
    run_check check_pod_readiness "app.kubernetes.io/name=kubecost" kubecost
else
    echo -e "${YELLOW}⚠️ Kubecost namespace not found - cost monitoring may be disabled${NC}"
fi

# Check NVIDIA GPU monitoring
if kubectl get daemonset nvidia-dcgm-exporter -n kube-system >/dev/null 2>&1; then
    run_check check_resource daemonset nvidia-dcgm-exporter kube-system
    echo -e "${GREEN}✅ NVIDIA GPU monitoring is enabled${NC}"
else
    echo -e "${YELLOW}⚠️ NVIDIA GPU monitoring not found - may be disabled${NC}"
fi

echo -e "${BLUE}🤖 Validating ML Platform Components${NC}"

# Check JupyterHub
if kubectl get namespace jupyterhub >/dev/null 2>&1; then
    run_check check_resource deployment jupyterhub-hub jupyterhub
    run_check check_pod_readiness "app=jupyterhub,component=hub" jupyterhub
    
    # Check JupyterHub service
    JUPYTERHUB_LB=$(kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$JUPYTERHUB_LB" ]; then
        echo -e "${GREEN}✅ JupyterHub LoadBalancer: http://$JUPYTERHUB_LB${NC}"
    else
        echo -e "${YELLOW}⚠️ JupyterHub LoadBalancer not ready yet${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ JupyterHub namespace not found - may be disabled${NC}"
fi

# Check Ray system
if kubectl get namespace ray-system >/dev/null 2>&1; then
    run_check check_resource deployment kuberay-operator ray-system
    run_check check_pod_readiness "app.kubernetes.io/name=kuberay-operator" ray-system
else
    echo -e "${YELLOW}⚠️ Ray system namespace not found - may be disabled${NC}"
fi

# Check Ray cluster
if kubectl get namespace ml-team-a >/dev/null 2>&1; then
    if kubectl get raycluster fraud-detection-cluster -n ml-team-a >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Ray cluster 'fraud-detection-cluster' found${NC}"
        run_check check_pod_readiness "ray.io/cluster=fraud-detection-cluster" ml-team-a
    else
        echo -e "${YELLOW}⚠️ Ray cluster not found - may be disabled${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ ML team namespace not found - Ray cluster may be disabled${NC}"
fi

# Check inference service
if kubectl get namespace ml-team-a >/dev/null 2>&1; then
    if kubectl get deployment fraud-inference -n ml-team-a >/dev/null 2>&1; then
        run_check check_resource deployment fraud-inference ml-team-a
        run_check check_pod_readiness "app=fraud-inference" ml-team-a
        
        # Check inference service
        INFERENCE_LB=$(kubectl get svc fraud-inference -n ml-team-a -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$INFERENCE_LB" ]; then
            echo -e "${GREEN}✅ Inference API LoadBalancer: http://$INFERENCE_LB:8000${NC}"
        else
            echo -e "${YELLOW}⚠️ Inference API LoadBalancer not ready yet${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ Inference service not found - may be disabled${NC}"
    fi
fi

echo -e "${BLUE}🔍 Validating GPU Support${NC}"

# Check GPU nodes
GPU_NODES=$(kubectl get nodes -l accelerator=nvidia --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$GPU_NODES" -gt 0 ]; then
    echo -e "${GREEN}✅ Found $GPU_NODES GPU nodes${NC}"
    kubectl get nodes -l accelerator=nvidia
else
    echo -e "${YELLOW}⚠️ No GPU nodes found - GPU workloads may not be available${NC}"
fi

# Check NVIDIA device plugin
if kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system >/dev/null 2>&1; then
    echo -e "${GREEN}✅ NVIDIA device plugin found${NC}"
else
    echo -e "${YELLOW}⚠️ NVIDIA device plugin not found${NC}"
fi

echo -e "${BLUE}💾 Validating Storage${NC}"

# Check S3 bucket
if command_exists terraform; then
    S3_BUCKET=$(terraform output -raw s3_bucket_id 2>/dev/null || echo "")
    if [ -n "$S3_BUCKET" ]; then
        echo -e "${GREEN}✅ S3 bucket: $S3_BUCKET${NC}"
        if command_exists aws; then
            aws s3 ls "s3://$S3_BUCKET" --no-paginate >/dev/null 2>&1 && echo -e "${GREEN}✅ S3 bucket is accessible${NC}" || echo -e "${YELLOW}⚠️ S3 bucket access check failed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ S3 bucket information not available${NC}"
    fi
fi

# Check EFS storage
if kubectl get storageclass efs-sc >/dev/null 2>&1; then
    echo -e "${GREEN}✅ EFS storage class found${NC}"
else
    echo -e "${YELLOW}⚠️ EFS storage class not found${NC}"
fi

echo -e "${BLUE}🌐 Validating Network Connectivity${NC}"

# Check DNS resolution
if kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default >/dev/null 2>&1; then
    echo -e "${GREEN}✅ DNS resolution working${NC}"
else
    echo -e "${YELLOW}⚠️ DNS resolution test failed${NC}"
fi

# Summary
echo -e "${BLUE}📊 Validation Summary${NC}"
echo -e "${YELLOW}Total checks: $total_checks${NC}"
echo -e "${GREEN}Passed checks: $passed_checks${NC}"
echo -e "${RED}Failed checks: $((total_checks - passed_checks))${NC}"

if [ $passed_checks -eq $total_checks ]; then
    echo -e "${GREEN}🎉 All validation checks passed!${NC}"
    echo -e "${BLUE}Your EMR to EKS migration platform is fully operational.${NC}"
    exit 0
elif [ $passed_checks -gt $((total_checks * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠️ Most validation checks passed, but some components may need attention.${NC}"
    exit 0
else
    echo -e "${RED}❌ Multiple validation checks failed. Please review the deployment.${NC}"
    exit 1
fi