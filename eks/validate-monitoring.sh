#!/bin/bash

# Validate Enhanced Monitoring and Observability Implementation
# This script validates the monitoring setup for EMR to EKS migration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Enhanced Monitoring Validation ===${NC}"

# Function to check if resource exists
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if kubectl get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $resource_type/$resource_name exists in namespace $namespace"
        return 0
    else
        echo -e "${RED}✗${NC} $resource_type/$resource_name not found in namespace $namespace"
        return 1
    fi
}

# Function to check pod status
check_pod_status() {
    local label_selector=$1
    local namespace=$2
    local description=$3
    
    local pods=$(kubectl get pods -n $namespace -l "$label_selector" --no-headers 2>/dev/null | wc -l)
    local ready_pods=$(kubectl get pods -n $namespace -l "$label_selector" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$pods" -gt 0 ] && [ "$ready_pods" -eq "$pods" ]; then
        echo -e "${GREEN}✓${NC} $description: $ready_pods/$pods pods running"
        return 0
    else
        echo -e "${RED}✗${NC} $description: $ready_pods/$pods pods running"
        return 1
    fi
}

# Check namespaces
echo -e "${YELLOW}Checking namespaces...${NC}"
if kubectl get namespace kube-prometheus-stack >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} namespace/kube-prometheus-stack exists"
else
    echo -e "${RED}✗${NC} namespace/kube-prometheus-stack not found"
fi

if kubectl get namespace amazon-cloudwatch >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} namespace/amazon-cloudwatch exists"
else
    echo -e "${RED}✗${NC} namespace/amazon-cloudwatch not found"
fi

if kubectl get namespace fraud-detection >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} namespace/fraud-detection exists"
else
    echo -e "${RED}✗${NC} namespace/fraud-detection not found"
fi

# Check Prometheus stack components
echo -e "${YELLOW}Checking Prometheus stack components...${NC}"
check_pod_status "app.kubernetes.io/name=prometheus" "kube-prometheus-stack" "Prometheus"
check_pod_status "app.kubernetes.io/name=grafana" "kube-prometheus-stack" "Grafana"
check_pod_status "app.kubernetes.io/name=alertmanager" "kube-prometheus-stack" "Alertmanager"

# Check custom PrometheusRules
echo -e "${YELLOW}Checking custom PrometheusRules...${NC}"
check_resource prometheusrule fraud-detection-recording-rules kube-prometheus-stack
check_resource prometheusrule fraud-detection-alerting-rules kube-prometheus-stack

# Check custom metrics exporters
echo -e "${YELLOW}Checking custom metrics exporters...${NC}"
check_pod_status "app=emr-metrics-exporter" "kube-prometheus-stack" "EMR Metrics Exporter"
check_pod_status "app=ray-metrics-exporter" "kube-prometheus-stack" "Ray Metrics Exporter"

# Check NVIDIA DCGM Exporter
echo -e "${YELLOW}Checking NVIDIA DCGM Exporter...${NC}"
check_pod_status "app=nvidia-dcgm-exporter" "kube-system" "NVIDIA DCGM Exporter"

# Check Kubecost
echo -e "${YELLOW}Checking Kubecost...${NC}"
check_pod_status "app.kubernetes.io/name=kubecost" "kubecost" "Kubecost"

# Check ServiceMonitors
echo -e "${YELLOW}Checking ServiceMonitors...${NC}"
check_resource servicemonitor nvidia-dcgm-exporter kube-system
check_resource servicemonitor kubecost kubecost
check_resource servicemonitor emr-metrics-exporter kube-prometheus-stack
check_resource servicemonitor ray-metrics-exporter kube-prometheus-stack

# Check CloudWatch integration
echo -e "${YELLOW}Checking CloudWatch integration...${NC}"
check_resource configmap cloudwatch-config amazon-cloudwatch
check_pod_status "name=cloudwatch-agent" "amazon-cloudwatch" "CloudWatch Agent"

# Check Grafana dashboard ConfigMap
echo -e "${YELLOW}Checking Grafana dashboards...${NC}"
check_resource configmap fraud-detection-dashboard kube-prometheus-stack

# Validate Prometheus configuration
echo -e "${YELLOW}Validating Prometheus configuration...${NC}"
PROMETHEUS_POD=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROMETHEUS_POD" ]; then
    echo -e "${GREEN}✓${NC} Prometheus pod found: $PROMETHEUS_POD"
    
    # Check if Prometheus is ready
    if kubectl wait --for=condition=ready pod/$PROMETHEUS_POD -n kube-prometheus-stack --timeout=30s >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Prometheus pod is ready"
        
        # Port forward to check configuration (run in background)
        kubectl port-forward -n kube-prometheus-stack pod/$PROMETHEUS_POD 9090:9090 >/dev/null 2>&1 &
        PF_PID=$!
        
        sleep 5
        
        # Check if Prometheus API is accessible
        if curl -s http://localhost:9090/api/v1/status/config >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Prometheus API is accessible"
            
            # Check custom recording rules
            RULES_COUNT=$(curl -s http://localhost:9090/api/v1/rules | jq '.data.groups | length' 2>/dev/null || echo "0")
            if [ "$RULES_COUNT" -gt 0 ]; then
                echo -e "${GREEN}✓${NC} Custom recording rules loaded: $RULES_COUNT rule groups"
            else
                echo -e "${RED}✗${NC} No custom recording rules found"
            fi
            
            # Check targets
            UP_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | map(select(.health == "up")) | length' 2>/dev/null || echo "0")
            TOTAL_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length' 2>/dev/null || echo "0")
            
            if [ "$UP_TARGETS" -gt 0 ]; then
                echo -e "${GREEN}✓${NC} Prometheus targets: $UP_TARGETS/$TOTAL_TARGETS up"
            else
                echo -e "${RED}✗${NC} No Prometheus targets are up"
            fi
        else
            echo -e "${RED}✗${NC} Prometheus API is not accessible"
        fi
        
        # Kill port forward
        kill $PF_PID 2>/dev/null || true
    else
        echo -e "${RED}✗${NC} Prometheus pod is not ready"
    fi
else
    echo -e "${RED}✗${NC} Prometheus pod not found"
fi

# Check Grafana accessibility
echo -e "${YELLOW}Validating Grafana configuration...${NC}"
GRAFANA_POD=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$GRAFANA_POD" ]; then
    echo -e "${GREEN}✓${NC} Grafana pod found: $GRAFANA_POD"
    
    if kubectl wait --for=condition=ready pod/$GRAFANA_POD -n kube-prometheus-stack --timeout=30s >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Grafana pod is ready"
        
        # Check if custom dashboard ConfigMap is labeled correctly
        DASHBOARD_LABEL=$(kubectl get configmap fraud-detection-dashboard -n kube-prometheus-stack -o jsonpath='{.metadata.labels.grafana_dashboard}' 2>/dev/null || echo "")
        if [ "$DASHBOARD_LABEL" = "1" ]; then
            echo -e "${GREEN}✓${NC} Custom dashboard ConfigMap is properly labeled"
        else
            echo -e "${RED}✗${NC} Custom dashboard ConfigMap is not properly labeled"
        fi
    else
        echo -e "${RED}✗${NC} Grafana pod is not ready"
    fi
else
    echo -e "${RED}✗${NC} Grafana pod not found"
fi

# Check GPU monitoring capability
echo -e "${YELLOW}Checking GPU monitoring capability...${NC}"
GPU_NODES=$(kubectl get nodes -l accelerator=nvidia --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$GPU_NODES" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} GPU nodes found: $GPU_NODES"
    
    # Check if DCGM exporter is running on GPU nodes
    DCGM_PODS=$(kubectl get pods -n kube-system -l app=nvidia-dcgm-exporter --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$DCGM_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} NVIDIA DCGM Exporter pods: $DCGM_PODS"
    else
        echo -e "${YELLOW}⚠${NC} No NVIDIA DCGM Exporter pods found (normal if no GPU workloads are running)"
    fi
else
    echo -e "${YELLOW}⚠${NC} No GPU nodes found (normal for CPU-only clusters)"
fi

# Summary
echo -e "${BLUE}=== Monitoring Validation Summary ===${NC}"

# Count successful checks
TOTAL_CHECKS=19
PASSED_CHECKS=0

# Re-run critical checks for summary
kubectl get namespace kube-prometheus-stack >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q "Running" && ((PASSED_CHECKS++))
kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q "Running" && ((PASSED_CHECKS++))
kubectl get prometheusrule fraud-detection-recording-rules -n kube-prometheus-stack >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get prometheusrule fraud-detection-alerting-rules -n kube-prometheus-stack >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get configmap fraud-detection-dashboard -n kube-prometheus-stack >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get servicemonitor nvidia-dcgm-exporter -n kube-system >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get servicemonitor kubecost -n kubecost >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get servicemonitor emr-metrics-exporter -n kube-prometheus-stack >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get servicemonitor ray-metrics-exporter -n kube-prometheus-stack >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get configmap cloudwatch-config -n amazon-cloudwatch >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get namespace fraud-detection >/dev/null 2>&1 && ((PASSED_CHECKS++))
kubectl get pods -n kube-prometheus-stack -l app=emr-metrics-exporter --no-headers 2>/dev/null | grep -q "Running" && ((PASSED_CHECKS++))
kubectl get pods -n kube-prometheus-stack -l app=ray-metrics-exporter --no-headers 2>/dev/null | grep -q "Running" && ((PASSED_CHECKS++))
kubectl get pods -n kubecost -l app.kubernetes.io/name=kubecost --no-headers 2>/dev/null | grep -q "Running" && ((PASSED_CHECKS++))

echo -e "Validation Results: ${GREEN}$PASSED_CHECKS${NC}/$TOTAL_CHECKS checks passed"

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}✓ All monitoring components are properly deployed and configured${NC}"
elif [ $PASSED_CHECKS -gt $((TOTAL_CHECKS * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠ Most monitoring components are working, some issues detected${NC}"
else
    echo -e "${RED}✗ Significant issues detected with monitoring deployment${NC}"
fi

echo -e "${BLUE}=== Access Information ===${NC}"
echo -e "Grafana Dashboard: ${YELLOW}kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80${NC}"
echo -e "Prometheus UI: ${YELLOW}kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090${NC}"
echo -e "Kubecost UI: ${YELLOW}kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090${NC}"

echo -e "${BLUE}=== Grafana Admin Credentials ===${NC}"
echo -e "Username: ${YELLOW}admin${NC}"
echo -e "Password: ${YELLOW}$(kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo 'Unable to retrieve password')${NC}"

echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Access Grafana and verify the Fraud Detection Overview dashboard"
echo -e "2. Check Prometheus targets and ensure all expected services are being scraped"
echo -e "3. Verify alerting rules are loaded and configured correctly"
echo -e "4. Test GPU metrics collection by running a GPU workload"
echo -e "5. Validate CloudWatch log aggregation for EMR, Ray, and inference services"