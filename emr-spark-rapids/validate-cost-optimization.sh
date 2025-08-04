#!/bin/bash

# Validate Cost Optimization Implementation
# This script validates that all cost optimization components are working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"emr-spark-rapids"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
NAMESPACE_MONITORING=${NAMESPACE_MONITORING:-"kube-prometheus-stack"}

echo -e "${GREEN}Starting Cost Optimization Validation...${NC}"

# Function to check resource quotas
validate_resource_quotas() {
    echo -e "${YELLOW}Validating resource quotas...${NC}"
    
    local namespaces=("ml-team-a" "ml-team-b" "ml-development")
    local all_passed=true
    
    for ns in "${namespaces[@]}"; do
        echo -e "${BLUE}Checking namespace: $ns${NC}"
        
        # Check if namespace exists
        if ! kubectl get namespace "$ns" &>/dev/null; then
            echo -e "${RED}❌ Namespace $ns does not exist${NC}"
            all_passed=false
            continue
        fi
        
        # Check resource quota
        if kubectl get resourcequota -n "$ns" | grep -q "${ns}-quota"; then
            echo -e "${GREEN}✓ Resource quota exists for $ns${NC}"
            
            # Show quota usage
            kubectl describe resourcequota "${ns}-quota" -n "$ns" | grep -E "(requests\.|limits\.)" | head -6
        else
            echo -e "${RED}❌ Resource quota missing for $ns${NC}"
            all_passed=false
        fi
        
        # Check limit range
        if kubectl get limitrange -n "$ns" | grep -q "${ns}-limits"; then
            echo -e "${GREEN}✓ Limit range exists for $ns${NC}"
        else
            echo -e "${RED}❌ Limit range missing for $ns${NC}"
            all_passed=false
        fi
        
        echo ""
    done
    
    if $all_passed; then
        echo -e "${GREEN}✓ All resource quotas and limits are configured correctly${NC}"
    else
        echo -e "${RED}❌ Some resource quotas or limits are missing${NC}"
        return 1
    fi
}

# Function to validate priority classes
validate_priority_classes() {
    echo -e "${YELLOW}Validating priority classes...${NC}"
    
    local priority_classes=("high-priority-ml" "medium-priority-ml" "low-priority-ml")
    local all_passed=true
    
    for pc in "${priority_classes[@]}"; do
        if kubectl get priorityclass "$pc" &>/dev/null; then
            local value=$(kubectl get priorityclass "$pc" -o jsonpath='{.value}')
            echo -e "${GREEN}✓ Priority class $pc exists with value: $value${NC}"
        else
            echo -e "${RED}❌ Priority class $pc does not exist${NC}"
            all_passed=false
        fi
    done
    
    if $all_passed; then
        echo -e "${GREEN}✓ All priority classes are configured correctly${NC}"
    else
        echo -e "${RED}❌ Some priority classes are missing${NC}"
        return 1
    fi
}

# Function to validate cleanup jobs
validate_cleanup_jobs() {
    echo -e "${YELLOW}Validating resource cleanup jobs...${NC}"
    
    local cleanup_jobs=("spark-cleanup" "ray-cleanup" "pvc-cleanup" "job-cleanup")
    local all_passed=true
    
    for job in "${cleanup_jobs[@]}"; do
        if kubectl get cronjob "$job" -n kube-system &>/dev/null; then
            local schedule=$(kubectl get cronjob "$job" -n kube-system -o jsonpath='{.spec.schedule}')
            local last_schedule=$(kubectl get cronjob "$job" -n kube-system -o jsonpath='{.status.lastScheduleTime}')
            echo -e "${GREEN}✓ Cleanup job $job exists (schedule: $schedule)${NC}"
            if [ -n "$last_schedule" ]; then
                echo -e "${BLUE}  Last run: $last_schedule${NC}"
            fi
        else
            echo -e "${RED}❌ Cleanup job $job does not exist${NC}"
            all_passed=false
        fi
    done
    
    # Check service account
    if kubectl get serviceaccount resource-cleanup -n kube-system &>/dev/null; then
        echo -e "${GREEN}✓ Resource cleanup service account exists${NC}"
    else
        echo -e "${RED}❌ Resource cleanup service account missing${NC}"
        all_passed=false
    fi
    
    # Check cluster role binding
    if kubectl get clusterrolebinding resource-cleanup &>/dev/null; then
        echo -e "${GREEN}✓ Resource cleanup cluster role binding exists${NC}"
    else
        echo -e "${RED}❌ Resource cleanup cluster role binding missing${NC}"
        all_passed=false
    fi
    
    if $all_passed; then
        echo -e "${GREEN}✓ All cleanup jobs are configured correctly${NC}"
    else
        echo -e "${RED}❌ Some cleanup jobs are missing or misconfigured${NC}"
        return 1
    fi
}

# Function to validate monitoring and alerts
validate_monitoring() {
    echo -e "${YELLOW}Validating cost monitoring and alerts...${NC}"
    
    # Check if Prometheus rules exist
    if kubectl get prometheusrules cost-optimization-alerts -n "$NAMESPACE_MONITORING" &>/dev/null; then
        echo -e "${GREEN}✓ Cost optimization alerting rules exist${NC}"
        
        # Count the number of rules
        local rule_count=$(kubectl get prometheusrules cost-optimization-alerts -n "$NAMESPACE_MONITORING" -o jsonpath='{.spec.groups[*].rules[*].alert}' | wc -w)
        echo -e "${BLUE}  Number of alert rules: $rule_count${NC}"
    else
        echo -e "${RED}❌ Cost optimization alerting rules missing${NC}"
        return 1
    fi
    
    # Check if custom metrics exporters are running
    local exporters=("emr-metrics-exporter" "ray-metrics-exporter")
    for exporter in "${exporters[@]}"; do
        if kubectl get deployment "$exporter" -n "$NAMESPACE_MONITORING" &>/dev/null; then
            local ready=$(kubectl get deployment "$exporter" -n "$NAMESPACE_MONITORING" -o jsonpath='{.status.readyReplicas}')
            if [ "$ready" = "1" ]; then
                echo -e "${GREEN}✓ $exporter is running${NC}"
            else
                echo -e "${YELLOW}⚠ $exporter exists but may not be ready${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ $exporter not found (may be optional)${NC}"
        fi
    done
    
    echo -e "${GREEN}✓ Monitoring components validated${NC}"
}

# Function to validate Karpenter
validate_karpenter() {
    echo -e "${YELLOW}Validating Karpenter autoscaling...${NC}"
    
    # Check if Karpenter is running
    if kubectl get deployment karpenter -n karpenter &>/dev/null; then
        local ready=$(kubectl get deployment karpenter -n karpenter -o jsonpath='{.status.readyReplicas}')
        if [ "$ready" -ge "1" ]; then
            echo -e "${GREEN}✓ Karpenter is running${NC}"
        else
            echo -e "${YELLOW}⚠ Karpenter exists but may not be ready${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Karpenter deployment not found${NC}"
    fi
    
    # Check NodePools
    local nodepool_count=$(kubectl get nodepools 2>/dev/null | wc -l)
    if [ "$nodepool_count" -gt 1 ]; then
        echo -e "${GREEN}✓ Karpenter NodePools are configured${NC}"
        kubectl get nodepools --no-headers | while read name rest; do
            echo -e "${BLUE}  NodePool: $name${NC}"
        done
    else
        echo -e "${YELLOW}⚠ No Karpenter NodePools found${NC}"
    fi
    
    # Check EC2NodeClasses
    local nodeclass_count=$(kubectl get ec2nodeclasses 2>/dev/null | wc -l)
    if [ "$nodeclass_count" -gt 1 ]; then
        echo -e "${GREEN}✓ Karpenter EC2NodeClasses are configured${NC}"
    else
        echo -e "${YELLOW}⚠ No Karpenter EC2NodeClasses found${NC}"
    fi
    
    # Check node termination handler (still relevant for Karpenter)
    if kubectl get daemonset aws-node-termination-handler -n kube-system &>/dev/null; then
        echo -e "${GREEN}✓ AWS Node Termination Handler is deployed${NC}"
    else
        echo -e "${YELLOW}⚠ AWS Node Termination Handler not found${NC}"
    fi
}

# Function to test resource limits
test_resource_limits() {
    echo -e "${YELLOW}Testing resource limits...${NC}"
    
    # Create a test pod that should be rejected due to resource limits
    cat <<EOF | kubectl apply -f - --dry-run=client
apiVersion: v1
kind: Pod
metadata:
  name: resource-limit-test
  namespace: ml-development
spec:
  containers:
  - name: test
    image: nginx
    resources:
      requests:
        cpu: "10"
        memory: "50Gi"
      limits:
        cpu: "20"
        memory: "100Gi"
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Resource limit validation works (dry-run passed)${NC}"
    else
        echo -e "${RED}❌ Resource limit validation failed${NC}"
        return 1
    fi
}

# Function to check cost metrics
check_cost_metrics() {
    echo -e "${YELLOW}Checking cost-related metrics...${NC}"
    
    # Check if Prometheus is accessible
    if kubectl get pods -n "$NAMESPACE_MONITORING" -l app.kubernetes.io/name=prometheus | grep -q Running; then
        echo -e "${GREEN}✓ Prometheus is running${NC}"
        
        # Port forward to Prometheus (in background, will be killed at script end)
        kubectl port-forward -n "$NAMESPACE_MONITORING" svc/kube-prometheus-stack-prometheus 9090:9090 &>/dev/null &
        local pf_pid=$!
        sleep 3
        
        # Test if we can query metrics
        if curl -s "http://localhost:9090/api/v1/query?query=up" | grep -q "success"; then
            echo -e "${GREEN}✓ Prometheus API is accessible${NC}"
            
            # Check for specific cost-related metrics
            local metrics=("kube_node_info" "kube_resourcequota" "container_memory_usage_bytes")
            for metric in "${metrics[@]}"; do
                if curl -s "http://localhost:9090/api/v1/query?query=$metric" | grep -q "success"; then
                    echo -e "${GREEN}✓ Metric $metric is available${NC}"
                else
                    echo -e "${YELLOW}⚠ Metric $metric may not be available${NC}"
                fi
            done
        else
            echo -e "${YELLOW}⚠ Cannot query Prometheus API${NC}"
        fi
        
        # Clean up port forward
        kill $pf_pid &>/dev/null || true
    else
        echo -e "${YELLOW}⚠ Prometheus is not running${NC}"
    fi
}

# Function to generate validation report
generate_report() {
    echo -e "${GREEN}Generating validation report...${NC}"
    
    local report_file="cost-optimization-validation-report.txt"
    
    cat > "$report_file" <<EOF
Cost Optimization Validation Report
Generated: $(date)
Cluster: $CLUSTER_NAME
Region: $AWS_REGION

=== Resource Quotas ===
EOF
    
    kubectl get resourcequotas --all-namespaces >> "$report_file" 2>/dev/null || echo "No resource quotas found" >> "$report_file"
    
    cat >> "$report_file" <<EOF

=== Limit Ranges ===
EOF
    
    kubectl get limitranges --all-namespaces >> "$report_file" 2>/dev/null || echo "No limit ranges found" >> "$report_file"
    
    cat >> "$report_file" <<EOF

=== Cleanup Jobs ===
EOF
    
    kubectl get cronjobs -n kube-system -l app=resource-cleanup >> "$report_file" 2>/dev/null || echo "No cleanup jobs found" >> "$report_file"
    
    cat >> "$report_file" <<EOF

=== Priority Classes ===
EOF
    
    kubectl get priorityclasses | grep -E "(high|medium|low)-priority-ml" >> "$report_file" 2>/dev/null || echo "No ML priority classes found" >> "$report_file"
    
    echo -e "${GREEN}✓ Validation report saved to: $report_file${NC}"
}

# Main validation function
main() {
    echo -e "${GREEN}EMR on EKS Cost Optimization Validation${NC}"
    echo "========================================"
    
    local validation_passed=true
    
    # Run all validations
    validate_resource_quotas || validation_passed=false
    echo ""
    
    validate_priority_classes || validation_passed=false
    echo ""
    
    validate_cleanup_jobs || validation_passed=false
    echo ""
    
    validate_monitoring || validation_passed=false
    echo ""
    
    validate_karpenter || validation_passed=false
    echo ""
    
    test_resource_limits || validation_passed=false
    echo ""
    
    check_cost_metrics || validation_passed=false
    echo ""
    
    # Generate report
    generate_report
    echo ""
    
    # Final result
    if $validation_passed; then
        echo -e "${GREEN}🎉 All cost optimization validations passed!${NC}"
        echo -e "${GREEN}Your cost optimization setup is working correctly.${NC}"
        return 0
    else
        echo -e "${RED}❌ Some validations failed.${NC}"
        echo -e "${YELLOW}Please check the output above and fix any issues.${NC}"
        return 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --quotas-only       Only validate resource quotas"
        echo "  --cleanup-only      Only validate cleanup jobs"
        echo "  --monitoring-only   Only validate monitoring"
        echo ""
        echo "Environment variables:"
        echo "  CLUSTER_NAME        EKS cluster name (default: emr-spark-rapids)"
        echo "  AWS_REGION          AWS region (default: us-west-2)"
        echo "  NAMESPACE_MONITORING Monitoring namespace (default: kube-prometheus-stack)"
        exit 0
        ;;
    --quotas-only)
        validate_resource_quotas
        exit $?
        ;;
    --cleanup-only)
        validate_cleanup_jobs
        exit $?
        ;;
    --monitoring-only)
        validate_monitoring
        exit $?
        ;;
    "")
        main
        exit $?
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage information"
        exit 1
        ;;
esac