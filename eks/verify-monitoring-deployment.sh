#!/bin/bash

# Verify Monitoring Deployment for EMR to EKS Migration
# This script verifies that all monitoring components are deployed and working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Verifying Monitoring Deployment ===${NC}"

# Check Prometheus stack components
echo -e "${YELLOW}Checking Prometheus stack components...${NC}"
PROMETHEUS_PODS=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=prometheus --no-headers | grep -c "Running" || echo "0")
GRAFANA_PODS=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=grafana --no-headers | grep -c "Running" || echo "0")
ALERTMANAGER_PODS=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=alertmanager --no-headers | grep -c "Running" || echo "0")

echo -e "${GREEN}✓${NC} Prometheus pods running: $PROMETHEUS_PODS"
echo -e "${GREEN}✓${NC} Grafana pods running: $GRAFANA_PODS"
echo -e "${GREEN}✓${NC} Alertmanager pods running: $ALERTMANAGER_PODS"

# Check custom metrics exporters
echo -e "${YELLOW}Checking custom metrics exporters...${NC}"
EMR_EXPORTER_PODS=$(kubectl get pods -n kube-prometheus-stack -l app=emr-metrics-exporter --no-headers | grep -c "Running" || echo "0")
RAY_EXPORTER_PODS=$(kubectl get pods -n kube-prometheus-stack -l app=ray-metrics-exporter --no-headers | grep -c "Running" || echo "0")

echo -e "${GREEN}✓${NC} EMR metrics exporter pods running: $EMR_EXPORTER_PODS"
echo -e "${GREEN}✓${NC} Ray metrics exporter pods running: $RAY_EXPORTER_PODS"

# Check Kubecost
echo -e "${YELLOW}Checking Kubecost...${NC}"
KUBECOST_PODS=$(kubectl get pods -n kubecost -l app.kubernetes.io/name=cost-analyzer --no-headers | grep -c "Running" || echo "0")
echo -e "${GREEN}✓${NC} Kubecost pods running: $KUBECOST_PODS"

# Check PrometheusRules
echo -e "${YELLOW}Checking PrometheusRules...${NC}"
RECORDING_RULES=$(kubectl get prometheusrule fraud-detection-recording-rules -n kube-prometheus-stack >/dev/null 2>&1 && echo "1" || echo "0")
ALERTING_RULES=$(kubectl get prometheusrule fraud-detection-alerting-rules -n kube-prometheus-stack >/dev/null 2>&1 && echo "1" || echo "0")

echo -e "${GREEN}✓${NC} Custom recording rules deployed: $RECORDING_RULES"
echo -e "${GREEN}✓${NC} Custom alerting rules deployed: $ALERTING_RULES"

# Check ServiceMonitors
echo -e "${YELLOW}Checking ServiceMonitors...${NC}"
EMR_SM=$(kubectl get servicemonitor emr-metrics-exporter -n kube-prometheus-stack >/dev/null 2>&1 && echo "1" || echo "0")
RAY_SM=$(kubectl get servicemonitor ray-metrics-exporter -n kube-prometheus-stack >/dev/null 2>&1 && echo "1" || echo "0")
KUBECOST_SM=$(kubectl get servicemonitor kubecost -n kubecost >/dev/null 2>&1 && echo "1" || echo "0")

echo -e "${GREEN}✓${NC} EMR metrics ServiceMonitor deployed: $EMR_SM"
echo -e "${GREEN}✓${NC} Ray metrics ServiceMonitor deployed: $RAY_SM"
echo -e "${GREEN}✓${NC} Kubecost ServiceMonitor deployed: $KUBECOST_SM"

# Check Grafana dashboard
echo -e "${YELLOW}Checking Grafana dashboard...${NC}"
DASHBOARD_CM=$(kubectl get configmap fraud-detection-dashboard -n kube-prometheus-stack >/dev/null 2>&1 && echo "1" || echo "0")
DASHBOARD_LABEL=$(kubectl get configmap fraud-detection-dashboard -n kube-prometheus-stack -o jsonpath='{.metadata.labels.grafana_dashboard}' 2>/dev/null || echo "0")

echo -e "${GREEN}✓${NC} Dashboard ConfigMap deployed: $DASHBOARD_CM"
echo -e "${GREEN}✓${NC} Dashboard properly labeled: $DASHBOARD_LABEL"

# Test Prometheus API
echo -e "${YELLOW}Testing Prometheus API...${NC}"
PROMETHEUS_POD=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROMETHEUS_POD" ]; then
    # Port forward to Prometheus
    kubectl port-forward -n kube-prometheus-stack pod/$PROMETHEUS_POD 9090:9090 >/dev/null 2>&1 &
    PF_PID=$!
    
    sleep 5
    
    # Test API connectivity
    if curl -s http://localhost:9090/api/v1/status/config >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Prometheus API is accessible"
        
        # Check targets
        UP_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets | map(select(.health == "up")) | length' 2>/dev/null || echo "0")
        TOTAL_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets | length' 2>/dev/null || echo "0")
        
        echo -e "${GREEN}✓${NC} Prometheus targets: $UP_TARGETS/$TOTAL_TARGETS up"
        
        # Check rules
        RULE_GROUPS=$(curl -s http://localhost:9090/api/v1/rules | jq -r '.data.groups | length' 2>/dev/null || echo "0")
        echo -e "${GREEN}✓${NC} Prometheus rule groups loaded: $RULE_GROUPS"
        
    else
        echo -e "${RED}✗${NC} Prometheus API is not accessible"
    fi
    
    # Kill port forward
    kill $PF_PID 2>/dev/null || true
else
    echo -e "${RED}✗${NC} Prometheus pod not found"
fi

# Summary
echo -e "${BLUE}=== Monitoring Deployment Summary ===${NC}"

TOTAL_COMPONENTS=10
WORKING_COMPONENTS=0

# Count working components
[ "$PROMETHEUS_PODS" -gt 0 ] && ((WORKING_COMPONENTS++))
[ "$GRAFANA_PODS" -gt 0 ] && ((WORKING_COMPONENTS++))
[ "$ALERTMANAGER_PODS" -gt 0 ] && ((WORKING_COMPONENTS++))
[ "$EMR_EXPORTER_PODS" -gt 0 ] && ((WORKING_COMPONENTS++))
[ "$RAY_EXPORTER_PODS" -gt 0 ] && ((WORKING_COMPONENTS++))
[ "$KUBECOST_PODS" -gt 0 ] && ((WORKING_COMPONENTS++))
[ "$RECORDING_RULES" -eq 1 ] && ((WORKING_COMPONENTS++))
[ "$ALERTING_RULES" -eq 1 ] && ((WORKING_COMPONENTS++))
[ "$DASHBOARD_CM" -eq 1 ] && ((WORKING_COMPONENTS++))
[ "$DASHBOARD_LABEL" -eq 1 ] && ((WORKING_COMPONENTS++))

echo -e "Working components: ${GREEN}$WORKING_COMPONENTS${NC}/$TOTAL_COMPONENTS"

if [ $WORKING_COMPONENTS -eq $TOTAL_COMPONENTS ]; then
    echo -e "${GREEN}✓ All monitoring components are working properly${NC}"
elif [ $WORKING_COMPONENTS -gt $((TOTAL_COMPONENTS * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠ Most monitoring components are working${NC}"
else
    echo -e "${RED}✗ Several monitoring components have issues${NC}"
fi

echo -e "${BLUE}=== Access Information ===${NC}"
echo -e "Grafana: ${YELLOW}kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80${NC}"
echo -e "Prometheus: ${YELLOW}kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090${NC}"
echo -e "Kubecost: ${YELLOW}kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090${NC}"

echo -e "${BLUE}=== Grafana Admin Credentials ===${NC}"
echo -e "Username: ${YELLOW}admin${NC}"
GRAFANA_PASSWORD=$(kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo 'Unable to retrieve password')
echo -e "Password: ${YELLOW}$GRAFANA_PASSWORD${NC}"

echo -e "${GREEN}Monitoring deployment verification completed!${NC}"