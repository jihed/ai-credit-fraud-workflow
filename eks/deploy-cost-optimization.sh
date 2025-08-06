#!/bin/bash

# Deploy Cost Optimization and Resource Management
# This script deploys all cost optimization components for the EMR on EKS cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"emr-spark-rapids"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
NAMESPACE_MONITORING=${NAMESPACE_MONITORING:-"kube-prometheus-stack"}

echo -e "${GREEN}Starting Cost Optimization Deployment...${NC}"

# Function to check if kubectl is available and cluster is accessible
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}helm is not installed or not in PATH${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Prerequisites check passed${NC}"
}

# Function to apply Terraform configurations
apply_terraform_configs() {
    echo -e "${YELLOW}Applying Terraform configurations for Karpenter cost optimization...${NC}"
    
    if [ -f "cost-optimization/karpenter-cost-optimization.tf" ]; then
        echo "Terraform configuration found. Please run 'terraform plan' and 'terraform apply' manually."
        echo "The Karpenter cost optimization configuration is in: cost-optimization/karpenter-cost-optimization.tf"
        echo "Note: Karpenter is already enabled in the cluster, this adds cost-optimized NodePools."
    else
        echo -e "${RED}Terraform configuration not found${NC}"
        exit 1
    fi
}

# Function to create namespaces and apply resource quotas
apply_resource_quotas() {
    echo -e "${YELLOW}Applying resource quotas and limits...${NC}"
    
    if [ -f "cost-optimization/resource-quotas.yaml" ]; then
        kubectl apply -f cost-optimization/resource-quotas.yaml
        echo -e "${GREEN}Resource quotas applied successfully${NC}"
    else
        echo -e "${RED}Resource quotas file not found${NC}"
        exit 1
    fi
    
    # Verify namespaces were created
    echo "Verifying namespaces..."
    kubectl get namespaces ml-team-a ml-team-b ml-development
}

# Function to apply cost monitoring alerts
apply_cost_alerts() {
    echo -e "${YELLOW}Applying cost monitoring alerts...${NC}"
    
    # Ensure monitoring namespace exists
    kubectl create namespace ${NAMESPACE_MONITORING} --dry-run=client -o yaml | kubectl apply -f -
    
    if [ -f "cost-optimization/cost-alerting-rules.yaml" ]; then
        kubectl apply -f cost-optimization/cost-alerting-rules.yaml
        echo -e "${GREEN}Cost alerting rules applied successfully${NC}"
    else
        echo -e "${RED}Cost alerting rules file not found${NC}"
        exit 1
    fi
}

# Function to apply resource cleanup jobs
apply_resource_cleanup() {
    echo -e "${YELLOW}Applying resource cleanup configurations...${NC}"
    
    if [ -f "cost-optimization/resource-cleanup.yaml" ]; then
        # Replace placeholder with actual account ID
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" cost-optimization/resource-cleanup.yaml | kubectl apply -f -
        echo -e "${GREEN}Resource cleanup configurations applied successfully${NC}"
    else
        echo -e "${RED}Resource cleanup file not found${NC}"
        exit 1
    fi
}

# Function to import Grafana dashboard
import_grafana_dashboard() {
    echo -e "${YELLOW}Importing cost monitoring dashboard...${NC}"
    
    if [ -f "cost-optimization/cost-monitoring-dashboard.json" ]; then
        # Check if Grafana is running
        if kubectl get pods -n ${NAMESPACE_MONITORING} -l app.kubernetes.io/name=grafana | grep -q Running; then
            echo "Grafana dashboard JSON is available at: cost-optimization/cost-monitoring-dashboard.json"
            echo "Please import this dashboard manually through the Grafana UI"
            echo "Dashboard ID: Cost Optimization Dashboard"
        else
            echo -e "${YELLOW}Grafana is not running. Dashboard will be available for manual import.${NC}"
        fi
    else
        echo -e "${RED}Dashboard file not found${NC}"
        exit 1
    fi
}

# Function to verify deployment
verify_deployment() {
    echo -e "${YELLOW}Verifying cost optimization deployment...${NC}"
    
    # Check resource quotas
    echo "Checking resource quotas..."
    kubectl get resourcequotas --all-namespaces
    
    # Check limit ranges
    echo "Checking limit ranges..."
    kubectl get limitranges --all-namespaces
    
    # Check cleanup jobs
    echo "Checking cleanup cron jobs..."
    kubectl get cronjobs -n kube-system -l app=resource-cleanup
    
    # Check alerting rules
    echo "Checking Prometheus rules..."
    kubectl get prometheusrules -n ${NAMESPACE_MONITORING} cost-optimization-alerts
    
    # Check priority classes
    echo "Checking priority classes..."
    kubectl get priorityclasses | grep -E "(high|medium|low)-priority-ml"
    
    echo -e "${GREEN}Verification completed${NC}"
}

# Function to display cost optimization information
display_info() {
    echo -e "${GREEN}Cost Optimization Deployment Complete!${NC}"
    echo ""
    echo "Components deployed:"
    echo "✓ Resource quotas and limits for ml-team-a, ml-team-b, and ml-development namespaces"
    echo "✓ Priority classes for workload prioritization"
    echo "✓ Cost monitoring alerts and recording rules"
    echo "✓ Automatic resource cleanup jobs"
    echo "✓ Network policies for traffic optimization"
    echo ""
    echo "Next steps:"
    echo "1. Apply Terraform configuration for Karpenter cost optimization:"
    echo "   cd cost-optimization && terraform plan && terraform apply"
    echo "   (Note: This adds cost-optimized NodePools to existing Karpenter setup)"
    echo ""
    echo "2. Import Grafana dashboard:"
    echo "   - Access Grafana UI"
    echo "   - Import dashboard from cost-optimization/cost-monitoring-dashboard.json"
    echo ""
    echo "3. Configure IAM roles for resource cleanup (replace ACCOUNT_ID in YAML files)"
    echo ""
    echo "4. Monitor cost metrics and alerts in Prometheus/Grafana"
    echo ""
    echo "Useful commands:"
    echo "- Check resource quotas: kubectl get resourcequotas --all-namespaces"
    echo "- Check cleanup jobs: kubectl get cronjobs -n kube-system -l app=resource-cleanup"
    echo "- View cost alerts: kubectl get prometheusrules -n ${NAMESPACE_MONITORING}"
    echo "- Monitor cleanup logs: kubectl logs -n kube-system -l app=resource-cleanup"
}

# Main execution
main() {
    echo -e "${GREEN}EMR on EKS Cost Optimization Deployment${NC}"
    echo "========================================"
    
    check_prerequisites
    
    # Apply configurations
    apply_resource_quotas
    apply_cost_alerts
    apply_resource_cleanup
    import_grafana_dashboard
    
    # Verify deployment
    verify_deployment
    
    # Display information
    display_info
    
    echo -e "${GREEN}Cost optimization deployment completed successfully!${NC}"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --verify-only       Only run verification checks"
        echo "  --cleanup-only      Only apply cleanup configurations"
        echo ""
        echo "Environment variables:"
        echo "  CLUSTER_NAME        EKS cluster name (default: emr-spark-rapids)"
        echo "  AWS_REGION          AWS region (default: us-west-2)"
        echo "  NAMESPACE_MONITORING Monitoring namespace (default: kube-prometheus-stack)"
        exit 0
        ;;
    --verify-only)
        check_prerequisites
        verify_deployment
        exit 0
        ;;
    --cleanup-only)
        check_prerequisites
        apply_resource_cleanup
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage information"
        exit 1
        ;;
esac